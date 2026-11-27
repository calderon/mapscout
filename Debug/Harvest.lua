-- MapScout harvest mode, for development only: records in the game what the
-- client data does not have, for the data generator (dev/tools/datagen).
-- Not in the released zip (its .toc line is inside #@do-not-package@) and not
-- documented for players. The moments come from the recorder
-- (Core/Recorder.lua, see there what each one gives); this file keeps them
-- and says so in the chat.
--   /ms harvest          what has been recorded
--   /ms harvest on|off   start or stop recording (it remembers it)
--   /ms harvest clear    forget everything recorded
--   /ms harvest here anvil|forge   note one where the player stands
--                        (anvils and forges have no window to notice them by)
-- What it keeps, in MapScoutDB.harvest (account SavedVariables):
--   * entrances: every entry is kept ("instance:time"): the point depends on
--     where the player walked in, so the generator averages them, and an
--     instance with several doors (Dire Maul's wings) has several
--   * npcs: service NPCs by ID, their services added up, every place they
--     were talked to (seen)
--   * objects: mailboxes and guild banks opened, and what "here" notes
--   * directions: the places city guards mark, one record per place
--   * graveyards: on dying ("death:time") and spirit healers talked to as a
--     ghost ("healer:time"); the generator joins those of one graveyard

local _, ns = ...

local Recorder = ns.Recorder
local round = Recorder.Round

local Harvest = {}
ns.Harvest = Harvest

-- What "/ms harvest here" can note
Harvest.HERE = { anvil = true, forge = true }

local function store()
	local db = ns.db
	db.harvest = db.harvest or {}
	local data = db.harvest
	data.entrances = data.entrances or {}
	data.npcs = data.npcs or {}
	data.objects = data.objects or {}
	data.graveyards = data.graveyards or {}
	return data
end

local function point(map, x, y)
	return ("%d, %.1f, %.1f"):format(map, x * 100, y * 100)
end

local keep = {}

function keep.npc(npc)
	Recorder.AddNPC(store().npcs, npc)
end

function keep.object(object)
	store().objects[Recorder.PlaceKey(object.service, object.map, object.x, object.y)] = {
		service = object.service, objectID = object.id, map = object.map, x = object.x, y = object.y, at = object.at,
	}
end

function keep.entrance(record, why)
	if not record then
		local from = why.place and "sí" or (why.age and ("de hace %.0f s"):format(why.age))
			or (why.noPosition and "el juego no da posición") or "ninguna"
		ns.Print(("harvest: entrada NO guardada (%s, tipo %s, id %s, posición de fuera: %s)"):format(
			tostring(why.name), tostring(why.kind), tostring(why.instance), from))
		return
	end
	store().entrances[("%d:%d"):format(record.instance, record.at)] = record
	ns.Print(("harvest: entrada de %s guardada (%s)"):format(tostring(record.name), point(record.map, record.x, record.y)))
end

function keep.death(record, why)
	if not record then
		ns.Print(("harvest: cementerio NO guardado (mapa %s, continente %s, el juego no da el punto)"):format(
			tostring(why.map), tostring(why.continent)))
		return
	end
	store().graveyards["death:" .. record.at] = {
		how = "death", map = record.map, x = record.x, y = record.y, continent = record.continent,
		cx = record.cx, cy = record.cy, died = record.died, at = record.at,
	}
	ns.Print(("harvest: cementerio guardado (%s)"):format(point(record.map, record.x, record.y)))
end

function keep.healer(record)
	store().graveyards["healer:" .. record.at] = {
		how = "healer", npc = record.npc, map = record.map, x = record.x, y = record.y, at = record.at,
	}
	ns.Print(("harvest: ángel guardado (%s)"):format(point(record.map, record.x, record.y)))
end

function keep.direction(direction)
	local data = store()
	data.directions = data.directions or {}
	if Recorder.AddDirection(data.directions, direction) then
		ns.Print(("harvest: dirección «%s» guardada (%s, %s)"):format(direction.asked, tostring(direction.name),
			point(direction.map, direction.x, direction.y)))
	end
end

function Harvest.Keep(kind, record, why)
	if keep[kind] then
		keep[kind](record, why)
	end
end

-- "/ms harvest here anvil": an object noted where the player stands
function Harvest.NoteHere(what)
	local mapID, x, y = Recorder.Where()
	if not (Harvest.HERE[what] and mapID) then
		return nil
	end
	local data = store()
	x, y = round(x), round(y)
	local key = Recorder.PlaceKey(what, mapID, x, y)
	data.objects[key] = { service = what, map = mapID, x = x, y = y, at = time() }
	ns.Print(("harvest: %s guardado aquí (%s)"):format(what, point(mapID, x, y)))
	return data.objects[key]
end

local warned
function Harvest.SetOn(on)
	store().on = on and true or nil
	if on then
		if not (warned or Recorder.CanAskGuards()) then
			warned = true
			ns.Print("harvest: este cliente no tiene C_GossipInfo.GetPoiForUiMapID: no se pueden guardar direcciones")
		end
		Recorder.Start("Harvest", Harvest.Keep)
	else
		Recorder.Stop("Harvest")
	end
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

ns.RegisterCommand("harvest", function(args)
	args = (args or ""):lower()
	local here = args:match("^here%s*(%a*)$")
	if here then
		if not Harvest.NoteHere(here) then
			ns.Print("harvest: usa /ms harvest here anvil|forge (y que el juego dé tu posición)")
		end
		return
	end
	if args == "on" or args == "off" then
		Harvest.SetOn(args == "on")
	elseif args == "clear" then
		local on = store().on
		ns.db.harvest = nil
		store().on = on
	end
	local data = store()
	ns.Print(("harvest %s: %d entradas, %d PNJ, %d objetos, %d direcciones, %d cementerios"):format(
		data.on and "|cff00ff00ON|r" or "OFF", count(data.entrances), count(data.npcs), count(data.objects),
		count(data.directions or {}), count(data.graveyards)))
end)

ns.RegisterEvent("PLAYER_LOGIN", "Harvest", function()
	if ns.db and ns.db.harvest and ns.db.harvest.on then
		Harvest.SetOn(true)
	end
end)
