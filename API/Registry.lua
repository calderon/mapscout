-- MapScout: the registry of search providers.
-- Every source of results is a provider, MapScout's own and other addons'
-- alike, and all of them register through MapScoutAPI:RegisterProvider.
--
--   local provider = MapScoutAPI:RegisterProvider("myaddon", {
--       name = "My Addon",                 -- required, shown in the options
--       description = "...", icon = "Interface\\...",
--       filter = "myaddon",                -- "@myaddon" in the search
--       filterAliases = { "mine" },        -- more @ words
--       categories = { { id = "shops", name = "Shops", filter = "shops" } }, -- sub-toggles, own @ words
--       defaultEnabled = true,
--       OnEnable = function() provider:SetEntries(...) end, -- on, at login too
--       OnDisable = function() end,        -- off: stop events, drop data
--       Collect = function(ctx, add) end,  -- live results, asked per search
--   })
--   provider:SetEntries(list)  provider:Invalidate([mapID])  provider:IsEnabled()
--
-- A disabled provider keeps nothing: its entries are dropped and SetEntries
-- is ignored until it is enabled again (then OnEnable is called, and pushes
-- them again). A provider whose code fails 3 times is turned off for the
-- session. See ARCHITECTURE.md (Providers) for the whole contract.

local _, ns = ...
local L = ns.L
local API = ns.API

local Registry = {}
ns.Registry = Registry

local MAX_ERRORS = 3

local providers = {} -- id -> record
local order = {} -- ids in registration order
local listeners = {} -- fn(what, id, ...) called on "entries", "toggled", "invalidate", "removed"

-- Internal modules (index, cache, options) follow the registry with this.
function Registry.Listen(fn)
	listeners[#listeners + 1] = fn
end

local function notify(what, id, ...)
	for _, fn in ipairs(listeners) do
		API.SafeCall(fn, what, id, ...)
	end
end

-- Validation ----------------------------------------------------------------

local function fail(id, message)
	error(("MapScoutAPI:RegisterProvider(%q): %s"):format(tostring(id), message), 0)
end

local function optional(id, spec, field, kind)
	if spec[field] ~= nil and type(spec[field]) ~= kind then
		fail(id, field .. " must be a " .. kind)
	end
end

local function validateSpec(id, spec)
	if type(id) ~= "string" or not id:match("^[%w_%-]+$") then
		fail(id, "the id must be a word (letters, digits, _ or -)")
	end
	if type(spec) ~= "table" then
		fail(id, "the second argument must be a table")
	end
	if type(spec.name) ~= "string" or spec.name == "" then
		fail(id, "name is required")
	end
	optional(id, spec, "description", "string")
	optional(id, spec, "icon", "string")
	optional(id, spec, "filter", "string")
	optional(id, spec, "filterAliases", "table")
	optional(id, spec, "categories", "table")
	optional(id, spec, "defaultEnabled", "boolean")
	for _, field in ipairs({ "Collect", "OnEnable", "OnDisable" }) do
		optional(id, spec, field, "function")
	end
	for i, category in ipairs(spec.categories or {}) do
		if type(category) ~= "table" or type(category.id) ~= "string" or type(category.name) ~= "string" then
			fail(id, ("categories[%d] needs an id and a name"):format(i))
		end
		if (category.filter ~= nil and type(category.filter) ~= "string")
			or (category.filterAliases ~= nil and type(category.filterAliases) ~= "table") then
			fail(id, ("categories[%d]: filter must be a string and filterAliases a list"):format(i))
		end
	end
end

local function isCoord(value)
	return type(value) == "number" and value >= 0 and value <= 1
end

-- Returns nil if the entry is fine, or what is wrong with it.
local function entryProblem(record, entry)
	if type(entry) ~= "table" then
		return "not a table"
	end
	if type(entry.id) ~= "string" and type(entry.id) ~= "number" then
		return "id is required"
	end
	if type(entry.name) ~= "string" or entry.name == "" then
		return "name is required"
	end
	if entry.mapID ~= nil or entry.x ~= nil or entry.y ~= nil then
		if type(entry.mapID) ~= "number" then
			return "mapID must be a number"
		end
		if not (isCoord(entry.x) and isCoord(entry.y)) then
			return "x and y must be numbers from 0 to 1"
		end
	end
	if entry.category ~= nil and not record.categoryIDs[entry.category] then
		return "unknown category " .. tostring(entry.category)
	end
	return nil
end
Registry.EntryProblem = entryProblem

-- Saved state ---------------------------------------------------------------

local function savedOptions()
	return ns.db and ns.db.options
end

local function wantsEnabled(record)
	local options = savedOptions()
	local saved = options and options.providers[record.id]
	if saved ~= nil then
		return saved
	end
	return record.spec.defaultEnabled ~= false
end

-- Calling provider code -----------------------------------------------------

local disable -- defined below

-- Calls one of the provider's functions safely. After MAX_ERRORS failures the
-- provider is turned off for this session (not saved) with one chat message.
local function callProvider(record, field, ...)
	local fn = record.spec[field]
	if not fn then
		return true
	end
	if record.failed then
		return false -- turned off after errors: its code doesn't run again this session
	end
	local results = { API.SafeCall(fn, ...) }
	if not results[1] then
		record.errors = record.errors + 1
		if record.errors >= MAX_ERRORS and not record.failed then
			record.failed = true
			ns.Print(L.PROVIDER_FAILED:format(record.spec.name, record.errors))
			disable(record)
		end
	end
	return unpack(results)
end
Registry.Call = callProvider

local function enable(record)
	if record.enabled or record.failed then
		return
	end
	record.enabled = true
	notify("toggled", record.id, true)
	if record.pendingEntries then -- set before login: older than what OnEnable may push
		local list = record.pendingEntries
		record.pendingEntries = nil
		record.handle:SetEntries(list)
	end
	callProvider(record, "OnEnable")
end

function disable(record)
	if not record.enabled then
		return
	end
	record.enabled = false
	record.entries = {}
	record.pendingEntries = nil
	notify("toggled", record.id, false)
	if not record.failed then
		callProvider(record, "OnDisable")
	end
end

-- Provider handle (what RegisterProvider returns) ---------------------------

local Handle = {}
Handle.__index = Handle

function Handle:SetEntries(list)
	local record = self.record
	if type(list) ~= "table" then
		error("provider:SetEntries needs a list", 2)
	end
	if not record.active then
		record.pendingEntries = list -- applied when MapScout is ready
		return
	end
	if not record.enabled then
		return -- nothing is kept for a disabled provider
	end
	local entries, skipped, firstProblem = {}, 0, nil
	for _, entry in ipairs(list) do
		local problem = entryProblem(record, entry)
		if problem then
			skipped = skipped + 1
			firstProblem = firstProblem or problem
		else
			entries[#entries + 1] = ns.CopyTable(entry)
		end
	end
	record.entries = entries
	record.skipped = skipped
	if skipped > 0 and not record.warnedEntries then
		record.warnedEntries = true
		geterrorhandler()(("MapScout: provider %q: %d entries skipped (first problem: %s)"):format(record.id, skipped,
			firstProblem))
	end
	notify("entries", record.id)
end

function Handle:Invalidate(mapID)
	if self.record.active and self.record.enabled then
		notify("invalidate", self.record.id, mapID)
	end
end

function Handle:IsEnabled()
	return self.record.enabled == true
end

-- Registration --------------------------------------------------------------

-- The @ words of a provider or category (filter + filterAliases), normalized
local function filterWords(spec)
	local words, result = { spec.filter }, {}
	for _, alias in ipairs(spec.filterAliases or {}) do
		words[#words + 1] = alias
	end
	for _, word in pairs(words) do
		local normalized = ns.Normalize(word)
		if normalized ~= "" then
			result[#result + 1] = normalized
		end
	end
	return result
end

local function create(id, spec)
	validateSpec(id, spec)
	local existing = providers[id]
	if existing then
		if existing.spec == spec and not existing.active then
			return existing -- the same call, queued before login
		end
		fail(id, "a provider with this id is already registered")
	end
	local record = {
		id = id, spec = spec, enabled = false, errors = 0, entries = {},
		categoryIDs = {}, filters = {}, categoryFilters = {},
	}
	record.filters = filterWords(spec)
	for _, category in ipairs(spec.categories or {}) do
		record.categoryIDs[category.id] = true
		for _, word in ipairs(filterWords(category)) do
			record.categoryFilters[word] = record.categoryFilters[word] or {}
			table.insert(record.categoryFilters[word], category.id)
		end
	end
	record.handle = setmetatable({ record = record }, Handle)
	providers[id] = record
	order[#order + 1] = id
	return record
end

local function activate(id, spec)
	local record = create(id, spec)
	if not record.active then
		record.active = true
		notify("registered", id)
		if wantsEnabled(record) then
			enable(record)
		else
			record.pendingEntries = nil
		end
	end
	return record.handle
end

local function unregister(id)
	local record = providers[id]
	if not record then
		return
	end
	disable(record)
	providers[id] = nil
	for i, other in ipairs(order) do
		if other == id then
			table.remove(order, i)
			break
		end
	end
	notify("removed", id)
end

API.Define("RegisterProvider", activate, {
	queue = true,
	early = function(id, spec)
		return create(id, spec).handle
	end,
})
API.Define("UnregisterProvider", unregister, { queue = true })

-- For MapScout itself (search, options) ---------------------------------------

function Registry.Get(id)
	return providers[id]
end

-- Registered providers, in registration order
function Registry.List()
	local list = {}
	for _, id in ipairs(order) do
		list[#list + 1] = providers[id]
	end
	return list
end

-- Turns a provider on or off and saves the choice (the options panel uses it).
function Registry.SetEnabled(id, on)
	local record = providers[id]
	if not record then
		return
	end
	local options = savedOptions()
	if options then
		local default = record.spec.defaultEnabled ~= false
		if on == default then
			options.providers[id] = nil -- only choices that differ from the default are saved
		else
			options.providers[id] = on
		end
	end
	if on then
		enable(record)
	else
		disable(record)
	end
end

function Registry.IsCategoryEnabled(id, categoryID)
	local options = savedOptions()
	return not (options and options.categories[id .. "." .. categoryID] == false)
end

-- What an @ word selects: a list of { provider = id, category = id or nil }.
-- A provider's word selects the whole provider; a category's word, that category.
function Registry.FindByFilter(word)
	word = ns.Normalize(word)
	local found = {}
	for _, id in ipairs(order) do
		local record = providers[id]
		local whole = false
		for _, filter in ipairs(record.filters) do
			if filter == word then
				whole = true
				found[#found + 1] = { provider = id }
				break
			end
		end
		if not whole then
			for _, categoryID in ipairs(record.categoryFilters[word] or {}) do
				found[#found + 1] = { provider = id, category = categoryID }
			end
		end
	end
	return found
end

-- What an @ word being typed selects: the filters whose word starts with it
-- ("zon" -> zones, zonas). Same list form as FindByFilter.
function Registry.FindByFilterPrefix(start)
	start = ns.Normalize(start)
	local found, seen = {}, {}
	if start == "" then
		return found
	end
	local function add(id, category)
		local key = id .. "." .. tostring(category)
		if not seen[key] then
			seen[key] = true
			found[#found + 1] = { provider = id, category = category }
		end
	end
	for _, id in ipairs(order) do
		local record = providers[id]
		local whole = false
		for _, filter in ipairs(record.filters) do
			if filter:sub(1, #start) == start then
				whole = true
				add(id)
				break
			end
		end
		if not whole then
			for word, categories in pairs(record.categoryFilters) do
				if word:sub(1, #start) == start then
					for _, categoryID in ipairs(categories) do
						add(id, categoryID)
					end
				end
			end
		end
	end
	return found
end

-- /ms debug providers ------------------------------------------------------------

ns.RegisterDebug("providers", function()
	local list = Registry.List()
	if #list == 0 then
		ns.Print(L.DEBUG_PROVIDERS_NONE)
		return
	end
	ns.Print(L.DEBUG_PROVIDERS_TITLE:format(#list))
	for _, record in ipairs(list) do
		local state = record.failed and L.PROVIDER_STATE_FAILED or (record.enabled and L.PROVIDER_STATE_ON or L.PROVIDER_STATE_OFF)
		DEFAULT_CHAT_FRAME:AddMessage(L.DEBUG_PROVIDERS_LINE:format(record.id, record.spec.name, state, #record.entries,
			record.errors, #record.filters > 0 and ("@" .. table.concat(record.filters, " @")) or "-"))
	end
end, L.DEBUG_PROVIDERS)
