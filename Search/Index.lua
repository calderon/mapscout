-- MapScout: the search index.
-- Keeps, for each enabled provider, its pushed entries with their texts already
-- normalized, so that searching never normalizes an entry again.
-- A provider's part (bucket) is built the first time a search needs it and
-- thrown away when its entries change, when it is turned off or removed.

local _, ns = ...

local Index = {}
ns.Index = Index

local buckets = {} -- providerID -> list of items (nil: not built yet)
Index.version = 0 -- goes up on every change: cached searches compare it

-- An indexed entry. The entry itself is the provider's copy kept by the
-- registry; MapScout never changes it.
local function makeItem(providerID, entry)
	local name = ns.Normalize(entry.name)
	local item = {
		key = providerID .. ":" .. tostring(entry.id),
		provider = providerID,
		category = entry.category,
		entry = entry,
		name = name,
		nameWords = ns.SplitWords(name),
		keywords = {}, -- normalized keywords
		keywordWords = {},
		weight = type(entry.weight) == "number" and entry.weight or 0.5,
	}
	if type(entry.keywords) == "table" then
		for _, keyword in ipairs(entry.keywords) do
			local normalized = ns.Normalize(keyword)
			if normalized ~= "" then
				item.keywords[#item.keywords + 1] = normalized
				for _, word in ipairs(ns.SplitWords(normalized)) do
					item.keywordWords[#item.keywordWords + 1] = word
				end
			end
		end
	end
	return item
end

local function build(record)
	local items = {}
	for _, entry in ipairs(record.entries) do
		items[#items + 1] = makeItem(record.id, entry)
	end
	buckets[record.id] = items
	return items
end

-- The items of a provider (built now if needed), or an empty list if it is off.
function Index.Items(providerID)
	local record = ns.Registry.Get(providerID)
	if not (record and record.enabled) then
		return {}
	end
	return buckets[providerID] or build(record)
end

-- Number of providers whose part is built, and of items in them
function Index.Stats()
	local built, items = 0, 0
	for _, list in pairs(buckets) do
		built = built + 1
		items = items + #list
	end
	return built, items
end

ns.Registry.Listen(function(what, providerID)
	if what == "entries" or what == "toggled" or what == "removed" then
		buckets[providerID] = nil -- rebuilt on the next search (or gone if off)
		Index.version = Index.version + 1
	elseif what == "categories" then
		Index.version = Index.version + 1 -- same entries, but searches must not reuse earlier matches
	end
end)
