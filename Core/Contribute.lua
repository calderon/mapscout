-- MapScout contribution mode: the player can help improve MapScout's data.
-- While it is on, what the recorder (Core/Recorder.lua) notices is kept on
-- this computer, to be sent by the player later.
-- Off by default. Once turned on, it starts by itself every session until it
-- is turned off; turned off, it stops listening at once (the recorder stops
-- when nobody else uses it).
--   /ms contribute          open the window to send what is new
--                           (UI/ContributeWindow.lua)
--   /ms contribute on|off   turn it on or off (account-wide)
--   /ms contribute status   whether it is on and how much is kept
--   /ms contribute clear    forget everything kept and the anonymous ID
--   /ms contribute messages on|off   whether the chat says when it saves
-- At login, one line says MapScout is loaded and, while contributing is on,
-- how many locations are new (not sent yet), with a chat link that opens the
-- window to send them, or thanks the player when none is; while it is off, it says how to turn it on. While it is on, the chat also says
-- each time a new location is saved (one kept already says nothing): those
-- can be silenced without turning it off (quiet = true); the login line can't.
-- What it keeps, in MapScoutDB.contribution (account SavedVariables):
--   on   true while it is on
--   id   a random anonymous ID for this installation, made the first time
--        something is kept (so the generator can count distinct contributors)
--   npcs, objects, entrances, directions, graveyards: as the harvest mode
--        keeps them, one record per place, without the time it was seen;
--        sent = true once the player has sent it (the export window)
--   pack the data pack's version the records were last checked against
--   quiet true when the chat should not say each location saved
-- Only what the data pack lacks is kept (Core/PackCheck.lua): a service, a
-- mailbox, an entrance or a graveyard the pack has near that place is not.
-- When the pack changes version, what it has gained is dropped, sent or not.
-- Each kind holds at most MAX records (vendors apart from the other NPCs,
-- MAX.vendors); when full, a sent one makes room.
-- No player data: no player names, realm, guild nor times; from an NPC's GUID
-- only its spawn number (it tells apart NPCs that share an ID).
-- Nothing is checked or kept in combat: it waits until the fight is over.

local _, ns = ...
local L = ns.L

local Recorder = ns.Recorder
local PackCheck = ns.PackCheck

local Contribute = {}
ns.Contribute = Contribute

Contribute.KINDS = { "npcs", "objects", "entrances", "directions", "graveyards" }
Contribute.MAX = { npcs = 150, vendors = 150, objects = 100, entrances = 50, directions = 150, graveyards = 50 }
Contribute.PRUNE_DELAY = 15 -- seconds after logging in: the pack is checked once it changed version
Contribute.WAITING = 30 -- most moments kept while in combat

local listeners = {} -- fn(on) when it is turned on or off

local function saved()
	local db = ns.db
	if not db then
		return nil
	end
	db.contribution = db.contribution or {}
	return db.contribution
end

-- A random ID ("3f9a0c1d7e2b4a65"), not tied to the player
function Contribute.NewID()
	local parts = {}
	for i = 1, 4 do
		parts[i] = ("%04x"):format(math.random(0, 0xffff))
	end
	return table.concat(parts)
end

local function store()
	local data = saved()
	data.id = data.id or Contribute.NewID()
	for _, kind in ipairs(Contribute.KINDS) do
		data[kind] = data[kind] or {}
	end
	return data
end

-- A copy of a record without the time it was seen
local function timeless(record)
	local copy = {}
	for field, value in pairs(record) do
		if field ~= "at" then
			copy[field] = value
		end
	end
	return copy
end

local function isVendor(entry)
	return entry.services and entry.services.vendor and true or false
end

-- Whether one more record of a kind fits (an NPC: as a vendor or not): when
-- it is full, a sent record makes room (the pack did not take it; what is not
-- sent yet stays)
local function fits(kind, vendor)
	local records, n, sent = store()[kind], 0, nil
	for key, entry in pairs(records) do
		if kind ~= "npcs" or isVendor(entry) == vendor then
			n = n + 1
			sent = sent or (entry.sent and key)
		end
	end
	if n < Contribute.MAX[vendor and "vendors" or kind] then
		return true
	end
	if sent then
		records[sent] = nil
		return true
	end
	return false
end

-- Keeps entry under key, if the pack lacks it and it fits. Returns true
-- when it was not kept yet.
local function put(kind, key, entry)
	if not PackCheck.Lacks(kind, entry) then
		return false
	end
	local records = store()[kind]
	local new = not records[key]
	if not new or fits(kind, false) then
		records[key] = entry
		return new
	end
	return false
end

-- What the chat calls each service
local SERVICE_TEXT = {
	bank = "SERVICE_bank", auction = "SERVICE_auction", vendor = "SERVICE_vendor", trainer = "SERVICE_trainer",
	stable = "SERVICE_stable", guild = "SERVICE_guild", tabard = "SERVICE_guild", battlemaster = "SERVICE_battle",
	innkeeper = "SERVICE_inn", transmog = "SERVICE_transmog", barber = "SERVICE_barber",
	guildbank = "CONTRIBUTE_GUILD_BANK", mailbox = "SERVICE_mailbox",
}

local function serviceText(service)
	local key = SERVICE_TEXT[service]
	return key and L[key] or nil
end

local function zoneName(mapID)
	local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return info and info.name or nil
end

-- Each keep.<kind> keeps what the recorder noticed; when it is a new
-- location, it returns how the chat names it and what it is (or nil)
local keep = {}

function keep.npc(npc)
	local services = { [npc.service] = true, repair = npc.repair }
	if not PackCheck.Lacks("npcs", { services = services, map = npc.map, x = npc.x, y = npc.y }) then
		return nil
	end
	local npcs = store().npcs
	local new = not npcs[npc.id]
	if not new or fits("npcs", npc.service == "vendor") then
		local entry = Recorder.AddNPC(npcs, timeless(npc))
		entry.at, entry.sent = nil, nil -- something new about it: not sent yet
		if new then
			return npc.name, serviceText(npc.service)
		end
	end
	return nil
end

function keep.object(object)
	if put("objects", Recorder.PlaceKey(object.service, object.map, object.x, object.y), {
		service = object.service, objectID = object.id, map = object.map, x = object.x, y = object.y,
	}) then
		return serviceText(object.service) or object.service, zoneName(object.map)
	end
	return nil
end

-- Entering a dungeon again by another spot keeps that spot too, but it is not
-- a new location
local function hasInstance(instance)
	for _, entry in pairs(store().entrances) do
		if entry.instance == instance then
			return true
		end
	end
	return false
end

function keep.entrance(record)
	if not record then
		return nil
	end
	local first = not hasInstance(record.instance)
	local key = Recorder.PlaceKey(tostring(record.instance), record.map, record.x, record.y)
	if put("entrances", key, timeless(record)) and first then
		return record.name, record.kind == "raid" and L.DUNGEONS_RAID or L.DUNGEONS_DUNGEON
	end
	return nil
end

local function graveyard(record, how)
	local entry = timeless(record)
	entry.how = how
	if put("graveyards", Recorder.PlaceKey(how, record.map, record.x, record.y), entry) then
		return L.CONTRIBUTE_GRAVEYARD, zoneName(record.map)
	end
	return nil
end

function keep.death(record)
	return record and graveyard(record, "death") or nil
end

function keep.healer(record)
	return graveyard(record, "healer")
end

function keep.direction(direction)
	local entry = timeless(direction)
	if not PackCheck.Lacks("directions", entry) then
		return nil
	end
	local directions = store().directions
	local new = not directions[Recorder.PlaceKey(nil, entry.map, entry.x, entry.y)]
	if not new or fits("directions", false) then
		Recorder.AddDirection(directions, entry)
		if new then
			return entry.name or L.CONTRIBUTE_PLACE, entry.asked ~= "" and entry.asked or zoneName(entry.map)
		end
	end
	return nil
end

-- In combat nothing is checked nor kept: the moments wait for the fight to end
local waiting = {}

local function afterCombat(fn)
	if not InCombatLockdown() then
		fn()
		return
	end
	if #waiting < Contribute.WAITING then
		waiting[#waiting + 1] = fn
	end
	ns.RegisterEvent("PLAYER_REGEN_ENABLED", "Contribute", function()
		ns.UnregisterEvent("PLAYER_REGEN_ENABLED", "Contribute")
		local list = waiting
		waiting = {}
		for _, wait in ipairs(list) do
			xpcall(wait, geterrorhandler())
		end
	end)
end

function Contribute.Keep(kind, record, why)
	if not keep[kind] then
		return
	end
	afterCombat(function()
		local name, what = keep[kind](record, why)
		PackCheck.Done()
		if name and Contribute.IsOn() and Contribute.Tells() then
			ns.Print(what and L.CONTRIBUTE_SAVED:format(name, what) or L.CONTRIBUTE_SAVED_PLAIN:format(name))
		end
	end)
end

-- Drops what the pack has now (sent or not) and notes the pack's version.
-- Returns how many records were dropped, or nil when the pack can't be read.
function Contribute.Prune()
	local data = saved()
	if not data then
		return nil
	end
	if Contribute.Count() == 0 then -- nothing to check: the pack is not loaded for nothing
		data.pack = ns.Packs.Version()
		return 0
	end
	if not PackCheck.HasPack() then
		return nil
	end
	local dropped = 0
	for _, kind in ipairs(Contribute.KINDS) do
		for key, entry in pairs(data[kind] or {}) do
			if not PackCheck.Lacks(kind, entry) then
				data[kind][key] = nil
				dropped = dropped + 1
			end
		end
	end
	PackCheck.Done()
	data.pack = ns.Packs.Version()
	return dropped
end

-- Once per pack version, a while after logging in and never in combat
local function pruneIfNewPack()
	local data = saved()
	local version = ns.Packs.Version()
	if not (data and version and data.pack ~= version) then
		return
	end
	C_Timer.After(Contribute.PRUNE_DELAY, function()
		afterCombat(Contribute.Prune)
	end)
end

function Contribute.IsOn()
	local data = saved()
	return data and data.on == true or false
end

function Contribute.SetOn(on)
	local data = saved()
	if not data then
		return
	end
	on = on and true or false
	data.on = on or nil
	if on then
		Recorder.Start("Contribute", Contribute.Keep)
	else
		Recorder.Stop("Contribute")
	end
	for _, fn in ipairs(listeners) do
		xpcall(fn, geterrorhandler(), on)
	end
end

-- Whether the chat says each new location saved
function Contribute.Tells()
	local data = saved()
	return not (data and data.quiet)
end

function Contribute.SetTells(on)
	local data = saved()
	if not data then
		return
	end
	data.quiet = not on or nil
	for _, fn in ipairs(listeners) do
		xpcall(fn, geterrorhandler(), Contribute.IsOn())
	end
end

-- fn(on) when contributing is turned on or off, or its messages (the options)
function Contribute.Listen(fn)
	listeners[#listeners + 1] = fn
end

-- Forgets everything kept and the anonymous ID; on or off stays as it was
function Contribute.Clear()
	local data = saved()
	if data then
		ns.db.contribution = { on = data.on, quiet = data.quiet }
	end
end

-- How many records are kept, in all
function Contribute.Count()
	local data, n = saved(), 0
	for _, kind in ipairs(Contribute.KINDS) do
		for _ in pairs(data and data[kind] or {}) do
			n = n + 1
		end
	end
	return n
end

-- How many records are new: not sent yet
function Contribute.CountNew()
	local data, n = saved(), 0
	for _, kind in ipairs(Contribute.KINDS) do
		for _, entry in pairs(data and data[kind] or {}) do
			if not entry.sent then
				n = n + 1
			end
		end
	end
	return n
end

-- "one location is saved", "3 locations are saved"...
function Contribute.PlacesText(n)
	if n == 0 then
		return L.CONTRIBUTE_PLACES_NONE
	elseif n == 1 then
		return L.CONTRIBUTE_PLACES_ONE
	end
	return L.CONTRIBUTE_PLACES:format(n)
end

-- "You have 2 new locations."; thanks when none is new
function Contribute.NewText(n)
	if n == 0 then
		return L.CONTRIBUTE_NEW_NONE
	elseif n == 1 then
		return L.CONTRIBUTE_NEW_ONE
	end
	return L.CONTRIBUTE_NEW:format(n)
end

local function status()
	local text = Contribute.IsOn() and L.CONTRIBUTE_STATUS_ON or L.CONTRIBUTE_STATUS_OFF
	ns.Print(text:format(Contribute.PlacesText(Contribute.Count())))
end

ns.RegisterCommand("contribute", function(args)
	args = strtrim(args or ""):lower()
	if args == "on" or args == "off" then
		Contribute.SetOn(args == "on")
		ns.Print(args == "on" and L.CONTRIBUTE_TURNED_ON or L.CONTRIBUTE_TURNED_OFF)
	elseif args == "clear" then
		Contribute.Clear()
		ns.Print(Contribute.IsOn() and L.CONTRIBUTE_CLEARED_ON or L.CONTRIBUTE_CLEARED_OFF)
	elseif args == "messages on" or args == "messages off" then
		Contribute.SetTells(args == "messages on")
		ns.Print(args == "messages on" and L.CONTRIBUTE_MESSAGES_ON or L.CONTRIBUTE_MESSAGES_OFF)
	elseif args == "" then
		Contribute.Share()
	elseif args == "status" then
		status()
	else
		ns.Print(L.CONTRIBUTE_USAGE)
	end
end, L.HELP_CONTRIBUTE)

ns.RegisterEvent("PLAYER_LOGIN", "Contribute", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "Contribute")
	if Contribute.IsOn() then
		Contribute.SetOn(true)
		local n = Contribute.CountNew()
		local text = Contribute.NewText(n)
		if n > 0 and Contribute.ShareLink then
			text = text .. " " .. Contribute.ShareLink(n)
		end
		ns.Print(L.CONTRIBUTE_LOGIN_ON:format(ns.VERSION, text))
		pruneIfNewPack()
	else
		ns.Print(L.CONTRIBUTE_LOGIN_OFF:format(ns.VERSION))
	end
end)
