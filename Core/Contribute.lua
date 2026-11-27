-- MapScout contribution mode: the player can help improve MapScout's data.
-- While it is on, what the recorder (Core/Recorder.lua) notices is kept on
-- this computer, to be sent by the player later.
-- Off by default. Once turned on, it starts by itself every session until it
-- is turned off; turned off, it stops listening at once (the recorder stops
-- when nobody else uses it).
--   /ms contribute on|off   turn it on or off (account-wide)
--   /ms contribute status   whether it is on and how much is kept
--   /ms contribute clear    forget everything kept and the anonymous ID
-- What it keeps, in MapScoutDB.contribution (account SavedVariables):
--   on   true while it is on
--   id   a random anonymous ID for this installation, made the first time
--        something is kept (so the generator can count distinct contributors)
--   npcs, objects, entrances, directions, graveyards: as the harvest mode
--        keeps them, one record per place, without the time it was seen;
--        sent = true once the player has sent it (the export window)
--   pack the data pack's version the records were last checked against
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

-- Keeps entry under key, if the pack lacks it and it fits
local function put(kind, key, entry)
	if not PackCheck.Lacks(kind, entry) then
		return
	end
	local records = store()[kind]
	if records[key] or fits(kind, false) then
		records[key] = entry
	end
end

local keep = {}

function keep.npc(npc)
	local services = { [npc.service] = true, repair = npc.repair }
	if not PackCheck.Lacks("npcs", { services = services, map = npc.map, x = npc.x, y = npc.y }) then
		return
	end
	local npcs = store().npcs
	if npcs[npc.id] or fits("npcs", npc.service == "vendor") then
		local entry = Recorder.AddNPC(npcs, timeless(npc))
		entry.at, entry.sent = nil, nil -- something new about it: not sent yet
	end
end

function keep.object(object)
	put("objects", Recorder.PlaceKey(object.service, object.map, object.x, object.y), {
		service = object.service, objectID = object.id, map = object.map, x = object.x, y = object.y,
	})
end

function keep.entrance(record)
	if record then
		put("entrances", Recorder.PlaceKey(tostring(record.instance), record.map, record.x, record.y), timeless(record))
	end
end

function keep.death(record)
	if record then
		local entry = timeless(record)
		entry.how = "death"
		put("graveyards", Recorder.PlaceKey("death", record.map, record.x, record.y), entry)
	end
end

function keep.healer(record)
	local entry = timeless(record)
	entry.how = "healer"
	put("graveyards", Recorder.PlaceKey("healer", record.map, record.x, record.y), entry)
end

function keep.direction(direction)
	local entry = timeless(direction)
	if not PackCheck.Lacks("directions", entry) then
		return
	end
	local directions = store().directions
	if directions[Recorder.PlaceKey(nil, entry.map, entry.x, entry.y)] or fits("directions", false) then
		Recorder.AddDirection(directions, entry)
	end
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
		keep[kind](record, why)
		PackCheck.Done()
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

-- fn(on) when contributing is turned on or off (the options checkbox)
function Contribute.Listen(fn)
	listeners[#listeners + 1] = fn
end

-- Forgets everything kept and the anonymous ID; on or off stays as it was
function Contribute.Clear()
	local data = saved()
	if data then
		ns.db.contribution = { on = data.on }
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

-- "one location is saved", "3 locations are saved"...
function Contribute.PlacesText(n)
	if n == 0 then
		return L.CONTRIBUTE_PLACES_NONE
	elseif n == 1 then
		return L.CONTRIBUTE_PLACES_ONE
	end
	return L.CONTRIBUTE_PLACES:format(n)
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
	elseif args == "status" or args == "" then
		status()
	else
		ns.Print(L.CONTRIBUTE_USAGE)
	end
end, L.HELP_CONTRIBUTE)

ns.RegisterEvent("PLAYER_LOGIN", "Contribute", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "Contribute")
	if Contribute.IsOn() then
		Contribute.SetOn(true)
		pruneIfNewPack()
	end
end)
