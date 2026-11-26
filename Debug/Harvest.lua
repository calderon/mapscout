-- MapScout harvest mode, for development only: records in the game what the
-- client data does not have, for the data generator (dev/tools/datagen).
-- Not in the released zip (its .toc line is inside #@do-not-package@) and not
-- documented for players.
--   /ms harvest          what has been recorded
--   /ms harvest on|off   start or stop recording (it remembers it)
--   /ms harvest clear    forget everything recorded
-- What it records, in MapScoutDB.harvest (account SavedVariables):
--   * entrances: entering a dungeon or raid, where the player stood just
--     before the loading screen (the instance's map ID from GetInstanceInfo)
--   * npcs: talking to a service NPC (bank, auction, vendor and repair,
--     trainer, stable, flight master, guild, battlemaster, innkeeper), with
--     the options of its gossip window, to tell its services apart later
--   * objects: opening a mailbox
-- Positions are the player's, on the most precise map (an NPC is within a few
-- steps of whoever talks to it).

local _, ns = ...

local Harvest = {}
ns.Harvest = Harvest

-- event -> service
Harvest.SERVICES = {
	BANKFRAME_OPENED = "bank",
	AUCTION_HOUSE_SHOW = "auction",
	MERCHANT_SHOW = "vendor",
	TRAINER_SHOW = "trainer",
	PET_STABLE_SHOW = "stable",
	TAXIMAP_OPENED = "flight",
	GUILD_REGISTRAR_SHOW = "guild",
	OPEN_TABARD_FRAME = "tabard",
	BATTLEFIELDS_SHOW = "battlemaster",
	CONFIRM_BINDER = "innkeeper",
	GOSSIP_SHOW = "gossip",
}

local function store()
	local db = ns.db
	db.harvest = db.harvest or {}
	local data = db.harvest
	data.entrances = data.entrances or {}
	data.npcs = data.npcs or {}
	data.objects = data.objects or {}
	return data
end

-- The kind and ID in a GUID ("Creature-0-1-2-3-1234-0000" -> "Creature", 1234)
function Harvest.ParseGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

-- Where the player is: uiMapID, x, y (0..1), or nil
function Harvest.Where()
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not x or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

local function round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end

-- Gossip options (name and icon), to tell services apart later
local function gossipOptions()
	local list = {}
	if C_GossipInfo and C_GossipInfo.GetOptions then
		for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
			list[#list + 1] = tostring(option.icon) .. ":" .. tostring(option.name)
		end
	end
	return list
end

function Harvest.RecordNPC(service)
	local kind, id = Harvest.ParseGUID(UnitGUID("npc"))
	local mapID, x, y = Harvest.Where()
	if not mapID then
		return nil
	end
	local data = store()
	if kind == "GameObject" or (not kind and service == "mailbox") then
		local key = ("%s:%d:%d:%d"):format(service, mapID, math.floor(x * 1000), math.floor(y * 1000))
		data.objects[key] = { service = service, objectID = id, map = mapID, x = round(x), y = round(y), at = time() }
		return data.objects[key]
	end
	if kind ~= "Creature" or not id then
		return nil
	end
	local record = data.npcs[id] or { id = id, services = {} }
	data.npcs[id] = record
	record.name = UnitName("npc")
	record.faction = UnitFactionGroup("npc") or "Neutral"
	record.map, record.x, record.y, record.at = mapID, round(x), round(y), time()
	if service == "gossip" then
		record.gossip = gossipOptions()
	else
		record.services[service] = true
		if service == "vendor" and CanMerchantRepair and CanMerchantRepair() then
			record.services.repair = true
		end
	end
	return record
end

-- Entrances: the last place outside, paired with the instance entered next.
-- While outside, the place is noted every second (Forever may not show a real
-- loading screen); entering is noticed after a loading screen or a zone change.
Harvest.TRACK_EVERY = 1
Harvest.MAX_AGE = 3 -- seconds between the last place outside and leaving the world
local outside, ticker, lastInstance, noPosition

function Harvest.NoteOutside()
	if IsInInstance() then
		return
	end
	lastInstance = nil
	local mapID, x, y = Harvest.Where()
	noPosition = not mapID
	if mapID then
		outside = { map = mapID, x = round(x), y = round(y), at = GetTime() }
	end
end

-- Just before a loading screen: the age of the place outside counts until now
-- (a loading screen can take several seconds)
function Harvest.LeavingWorld()
	Harvest.NoteOutside()
	if outside and not outside.left then
		outside.left = GetTime()
	end
end

function Harvest.EnteringWorld()
	local inside, kind = IsInInstance()
	if not inside then
		Harvest.NoteOutside()
		return nil
	end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if lastInstance and lastInstance == instanceID then
		return nil -- still the same instance (a zone change inside it)
	end
	lastInstance = instanceID
	local from = outside
	outside = nil
	local age = from and ((from.left or GetTime()) - from.at)
	if age and age > Harvest.MAX_AGE then
		from = nil
	end
	if not (from and instanceID and (kind == "party" or kind == "raid" or kind == "scenario")) then
		local why = from and "sí" or (age and ("de hace %.0f s"):format(age)) or (noPosition and "el juego no da posición") or "ninguna"
		ns.Print(("harvest: entrada NO guardada (%s, tipo %s, id %s, posición de fuera: %s)"):format(tostring(name),
			tostring(kind), tostring(instanceID), why))
		return nil
	end
	local record = { instance = instanceID, name = name, kind = kind, map = from.map, x = from.x, y = from.y, at = time() }
	store().entrances[instanceID] = record
	ns.Print(("harvest: entrada de %s guardada (%d, %.1f, %.1f)"):format(tostring(name), from.map, from.x * 100, from.y * 100))
	return record
end

local function onService(event)
	local service = Harvest.SERVICES[event]
	if service then
		Harvest.RecordNPC(service)
	end
end

local listening = false
function Harvest.SetOn(on)
	store().on = on and true or nil
	if on == listening then
		return
	end
	listening = on
	for event in pairs(Harvest.SERVICES) do
		if on then
			ns.RegisterEvent(event, "Harvest", onService)
		else
			ns.UnregisterEvent(event, "Harvest")
		end
	end
	local others = {
		MAIL_SHOW = function() Harvest.RecordNPC("mailbox") end,
		PLAYER_LEAVING_WORLD = Harvest.LeavingWorld,
		PLAYER_ENTERING_WORLD = Harvest.EnteringWorld,
		ZONE_CHANGED_NEW_AREA = Harvest.EnteringWorld,
	}
	for event, fn in pairs(others) do
		if on then
			ns.RegisterEvent(event, "Harvest", fn)
		else
			ns.UnregisterEvent(event, "Harvest")
		end
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if on then
		Harvest.NoteOutside()
		ticker = C_Timer.NewTicker(Harvest.TRACK_EVERY, Harvest.NoteOutside)
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
	if args == "on" or args == "off" then
		Harvest.SetOn(args == "on")
	elseif args == "clear" then
		local on = store().on
		ns.db.harvest = nil
		store().on = on
	end
	local data = store()
	ns.Print(("harvest %s: %d entradas, %d PNJ, %d objetos"):format(data.on and "|cff00ff00ON|r" or "OFF",
		count(data.entrances), count(data.npcs), count(data.objects)))
end)

ns.RegisterEvent("PLAYER_LOGIN", "Harvest", function()
	if ns.db and ns.db.harvest and ns.db.harvest.on then
		Harvest.SetOn(true)
	end
end)
