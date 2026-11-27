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
--        keeps them, one record per place, without the time it was seen
-- No player data: no names, realm, guild, GUIDs nor times.

local _, ns = ...
local L = ns.L

local Recorder = ns.Recorder

local Contribute = {}
ns.Contribute = Contribute

Contribute.KINDS = { "npcs", "objects", "entrances", "directions", "graveyards" }

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

local keep = {}

function keep.npc(npc)
	local entry = Recorder.AddNPC(store().npcs, timeless(npc))
	entry.at = nil
end

function keep.object(object)
	store().objects[Recorder.PlaceKey(object.service, object.map, object.x, object.y)] = {
		service = object.service, objectID = object.id, map = object.map, x = object.x, y = object.y,
	}
end

function keep.entrance(record)
	if record then
		local key = Recorder.PlaceKey(tostring(record.instance), record.map, record.x, record.y)
		store().entrances[key] = timeless(record)
	end
end

function keep.death(record)
	if record then
		local entry = timeless(record)
		entry.how = "death"
		store().graveyards[Recorder.PlaceKey("death", record.map, record.x, record.y)] = entry
	end
end

function keep.healer(record)
	local entry = timeless(record)
	entry.how = "healer"
	store().graveyards[Recorder.PlaceKey("healer", record.map, record.x, record.y)] = entry
end

function keep.direction(direction)
	Recorder.AddDirection(store().directions, timeless(direction))
end

function Contribute.Keep(kind, record, why)
	if keep[kind] then
		keep[kind](record, why)
	end
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

-- "one place is saved", "3 places are saved"...
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
	end
end)
