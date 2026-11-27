-- MapScout harvest mode, for development only: records in the game what the
-- client data does not have, for the data generator (dev/tools/datagen).
-- Not in the released zip (its .toc line is inside #@do-not-package@) and not
-- documented for players.
--   /ms harvest          what has been recorded
--   /ms harvest on|off   start or stop recording (it remembers it)
--   /ms harvest clear    forget everything recorded
--   /ms harvest here anvil|forge   note one where the player stands
--                        (anvils and forges have no window to notice them by)
-- What it records, in MapScoutDB.harvest (account SavedVariables):
--   * entrances: entering a dungeon or raid, where the player stood just
--     before the loading screen (the instance's map ID from GetInstanceInfo).
--     Every entry is kept ("instance:time"): the point depends on where the
--     player walked in, so the generator averages them, and an instance with
--     several doors (Dire Maul's wings) has several
--   * npcs: talking to a service NPC (bank, auction, vendor and repair,
--     trainer, stable, flight master, guild, battlemaster, innkeeper), with
--     the options of its gossip window, to tell its services apart later, the
--     line under its name ("Quartermaster"), and for a trainer the skill it
--     teaches; also transmogrifiers
--   * objects: opening a mailbox or a guild bank, and what "here" notes
--   * directions: the place a city guard marks on the map when asked for a
--     service (the guard's own answer, with the choices that led to it)
--   * graveyards: on dying, the graveyard the ghost will appear at (the game
--     says so at once, no need to release the spirit); and, as a ghost,
--     talking to a spirit healer, where it stands
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
	-- older events, only where the client still has them
	TRANSMOGRIFY_OPEN = "transmog",
	GUILDBANKFRAME_OPENED = "guildbank",
}

-- Windows opened through the interaction manager (Enum.PlayerInteractionType
-- name -> service), for services without an event of their own
Harvest.INTERACTIONS = { Transmogrifier = "transmog", GuildBanker = "guildbank", Barber = "barber" }

-- What "/ms harvest here" can note
Harvest.HERE = { anvil = true, forge = true }

-- Whether this client has an event (registering an unknown one is an error)
function Harvest.HasEvent(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event) and true or false
	end
	return true
end

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

-- The line under a unit's name in its tooltip ("Intendente de Forjaz",
-- or its level when it has no title), or nil
local scanner
function Harvest.UnitTitle(unit)
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		local info = C_TooltipInfo.GetUnit(unit)
		local line = info and info.lines and info.lines[2]
		return line and line.leftText or nil
	end
	if not CreateFrame then
		return nil
	end
	scanner = scanner or CreateFrame("GameTooltip", "MapScoutHarvestTooltip", nil, "GameTooltipTemplate")
	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanner:SetUnit(unit)
	local line = _G.MapScoutHarvestTooltipTextLeft2
	local text = line and line:GetText()
	scanner:Hide()
	return text
end

-- The skill a trainer's window teaches ("Riding", "Mining"), or nil: tells
-- riding and profession trainers apart (a class trainer teaches its schools)
function Harvest.TrainerSkill()
	if not (GetNumTrainerServices and GetTrainerServiceSkillLine) then
		return nil
	end
	for i = 1, GetNumTrainerServices() or 0 do
		local skill = GetTrainerServiceSkillLine(i)
		if skill and skill ~= "" then
			return skill
		end
	end
	return nil
end

function Harvest.RecordNPC(service, unit)
	unit = unit or "npc"
	local kind, id = Harvest.ParseGUID(UnitGUID(unit))
	local mapID, x, y = Harvest.Where()
	if not mapID then
		return nil
	end
	local data = store()
	if kind == "GameObject" or (not kind and (service == "mailbox" or service == "guildbank")) then
		local key = ("%s:%d:%d:%d"):format(service, mapID, math.floor(x * 1000), math.floor(y * 1000))
		data.objects[key] = { service = service, objectID = id, map = mapID, x = round(x), y = round(y), at = time() }
		return data.objects[key]
	end
	if kind ~= "Creature" or not id then
		return nil
	end
	local record = data.npcs[id] or { id = id, services = {} }
	data.npcs[id] = record
	record.name = UnitName(unit)
	record.faction = UnitFactionGroup(unit) or "Neutral"
	record.title = Harvest.UnitTitle(unit) or record.title
	record.locale = GetLocale()
	record.map, record.x, record.y, record.at = mapID, round(x), round(y), time()
	if service == "gossip" then
		record.gossip = gossipOptions()
	elseif service == "trainer" then
		record.services.trainer = true
		record.skill = Harvest.TrainerSkill() or record.skill
	else
		record.services[service] = true
		if service == "vendor" and CanMerchantRepair and CanMerchantRepair() then
			record.services.repair = true
		end
	end
	return record
end

-- A window opened through the interaction manager
function Harvest.OnInteraction(interaction)
	local names = Enum and Enum.PlayerInteractionType
	for name, value in pairs(names or {}) do
		if value == interaction and Harvest.INTERACTIONS[name] then
			return Harvest.RecordNPC(Harvest.INTERACTIONS[name])
		end
	end
	return nil
end

-- "/ms harvest here anvil": an object noted where the player stands
function Harvest.NoteHere(what)
	local mapID, x, y = Harvest.Where()
	if not (Harvest.HERE[what] and mapID) then
		return nil
	end
	local data = store()
	local key = ("%s:%d:%d:%d"):format(what, mapID, math.floor(x * 1000), math.floor(y * 1000))
	data.objects[key] = { service = what, map = mapID, x = round(x), y = round(y), at = time() }
	ns.Print(("harvest: %s guardado aquí (%d, %.1f, %.1f)"):format(what, mapID, x * 100, y * 100))
	return data.objects[key]
end

-- Graveyards. On dying, the game says where the ghost will appear
-- (C_DeathInfo.GetDeathReleasePosition), but only on the continent's map: on a
-- city's map the graveyard outside it is off the map. The point is then placed
-- on its outdoor zone. It answers nothing while alive. As a ghost, the only NPC
-- one can talk to is a spirit healer: its gossip window notes where it stands.
-- Every record is kept ("death:time", "healer:time"); the generator joins
-- those of the same graveyard.

-- The continent a map is in, or nil (an instance has none)
function Harvest.ContinentOf(mapID)
	local id, seen = mapID, 0
	while id and id ~= 0 and seen < 10 do
		local info = C_Map.GetMapInfo(id)
		if not info then
			return nil
		end
		if info.mapType == 2 then
			return id
		end
		id, seen = info.parentMapID, seen + 1
	end
	return nil
end

local function onMap(x, y)
	return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (x == 0 and y == 0)
end

function Harvest.RecordDeath()
	local death = C_DeathInfo
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local continent = mapID and Harvest.ContinentOf(mapID)
	local at = continent and death and death.GetDeathReleasePosition and death.GetDeathReleasePosition(continent)
	local cx, cy
	if at then
		cx, cy = at:GetXY()
	end
	if not onMap(cx, cy) then
		ns.Print(("harvest: cementerio NO guardado (mapa %s, continente %s, el juego no da el punto)"):format(
			tostring(mapID), tostring(continent)))
		return nil
	end
	local zone, x, y = ns.PlaceOutdoors(continent, cx, cy)
	local record = {
		how = "death", map = zone, x = round(x), y = round(y), continent = continent, cx = round(cx), cy = round(cy),
		died = mapID, at = time(),
	}
	store().graveyards["death:" .. record.at] = record
	ns.Print(("harvest: cementerio guardado (%d, %.1f, %.1f)"):format(zone, x * 100, y * 100))
	return record
end

function Harvest.RecordHealer()
	local mapID, x, y = Harvest.Where()
	if not mapID then
		return nil
	end
	local _, npcID = Harvest.ParseGUID(UnitGUID("npc"))
	local record = { how = "healer", npc = npcID, map = mapID, x = round(x), y = round(y), at = time() }
	store().graveyards["healer:" .. record.at] = record
	ns.Print(("harvest: ángel guardado (%d, %.1f, %.1f)"):format(mapID, x * 100, y * 100))
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
	store().entrances[("%d:%d"):format(instanceID, record.at)] = record
	ns.Print(("harvest: entrada de %s guardada (%d, %.1f, %.1f)"):format(tostring(name), from.map, from.x * 100, from.y * 100))
	return record
end

-- Directions: a city guard asked for a service ("The bank") marks it on the
-- map with a gossip POI. After each gossip choice, the POI is looked for on the
-- player's map and the maps above it, and kept with the choices that led to it
-- ("Profession trainer > Alchemy"). Several guards giving the same place are
-- one record (its key is the map and position).
Harvest.POI_DELAYS = { 0.3, 1 } -- seconds after a choice: the POI may come late
local listening = false
local choices = {} -- the options chosen with the current guard, in order
local warned

-- The options of the gossip window shown last, by option ID and by position:
-- read when the window opens, because after a choice it already shows the next
-- page's options
local shown = { byID = {}, byIndex = {} }

local function noteOptions()
	shown = { byID = {}, byIndex = {} }
	for i, option in ipairs(C_GossipInfo.GetOptions() or {}) do
		if option.gossipOptionID then
			shown.byID[option.gossipOptionID] = option.name
		end
		shown.byIndex[option.orderIndex or (i - 1)] = option.name
		shown.byIndex[i] = shown.byIndex[i] or option.name
	end
end

-- The gossip POI shown now: uiMapID, x, y, name, texture index, POI ID; or nil
function Harvest.FindPoi()
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	while mapID and mapID > 0 do
		local poiID = C_GossipInfo.GetPoiForUiMapID(mapID)
		local info = poiID and C_GossipInfo.GetPoiInfo(mapID, poiID)
		if info and info.position then
			local x, y = info.position:GetXY()
			return mapID, x, y, info.name, info.textureIndex, poiID
		end
		local map = C_Map.GetMapInfo(mapID)
		mapID = map and map.parentMapID
	end
	return nil
end

-- Only a final answer is kept: while the window still has options, the choice
-- opened a submenu (or the answer has not come yet) and the POI shown is still
-- the previous one's. Forever gives every POI the ID 0, so it cannot tell them
-- apart. Two answers at the same place are one record with both.
function Harvest.RecordPoi(asked)
	if #(C_GossipInfo.GetOptions() or {}) > 0 then
		return nil
	end
	local mapID, x, y, name, texture, poiID = Harvest.FindPoi()
	if not mapID then
		return nil
	end
	local key = ("%d:%d:%d"):format(mapID, math.floor(x * 1000), math.floor(y * 1000))
	asked = asked or ""
	local directions = store().directions or {}
	if directions[key] and directions[key].asked:find(asked, 1, true) and asked ~= "" then
		local parts = "|" .. directions[key].asked:gsub("%s*|%s*", "|") .. "|"
		if parts:find("|" .. asked .. "|", 1, true) then
			return nil -- already there (the second check after the same choice)
		end
	end
	store().directions = directions
	local old = directions[key]
	local list = {}
	for part in ((old and old.asked) or ""):gmatch("[^|]+") do
		part = strtrim(part)
		if part ~= "" and part ~= asked then
			list[#list + 1] = part
		end
	end
	list[#list + 1] = asked
	table.sort(list)
	local kind, guard = Harvest.ParseGUID(UnitGUID("npc"))
	local record = {
		map = mapID, x = round(x), y = round(y), name = name, texture = texture, poi = poiID, locale = GetLocale(),
		asked = table.concat(list, " | "), guard = kind == "Creature" and guard or nil, at = time(),
	}
	directions[key] = record
	ns.Print(("harvest: dirección «%s» guardada (%s, %d, %.1f, %.1f)"):format(asked, tostring(name), mapID,
		x * 100, y * 100))
	return record
end

local function onChoice(name)
	if not listening then
		return
	end
	choices[#choices + 1] = name
	local asked = table.concat(choices, " > ")
	for _, delay in ipairs(Harvest.POI_DELAYS) do
		C_Timer.After(delay, function()
			Harvest.RecordPoi(asked)
		end)
	end
end

local hooked
local function hookGossip()
	if hooked then
		return
	end
	if not (C_GossipInfo and C_GossipInfo.GetPoiForUiMapID and C_GossipInfo.GetPoiInfo) then
		if not warned then
			warned = true
			ns.Print("harvest: este cliente no tiene C_GossipInfo.GetPoiForUiMapID: no se pueden guardar direcciones")
		end
		return
	end
	hooked = true
	if C_GossipInfo.SelectOption then
		hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
			onChoice(shown.byID[optionID] or ("id " .. tostring(optionID)))
		end)
	end
	if C_GossipInfo.SelectOptionByIndex then
		hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(index)
			onChoice(shown.byIndex[index] or ("index " .. tostring(index)))
		end)
	end
end

local function onGossipClosed()
	choices = {}
end

local function onService(event)
	if event == "GOSSIP_SHOW" and hooked then
		noteOptions()
	end
	if event == "GOSSIP_SHOW" and UnitIsGhost("player") then
		Harvest.RecordHealer() -- a ghost only talks to spirit healers: not a service
		return
	end
	local service = Harvest.SERVICES[event]
	if service then
		Harvest.RecordNPC(service)
	end
end

function Harvest.SetOn(on)
	store().on = on and true or nil
	if on == listening then
		return
	end
	listening = on
	for event in pairs(Harvest.SERVICES) do
		if on and Harvest.HasEvent(event) then
			ns.RegisterEvent(event, "Harvest", onService)
		else
			ns.UnregisterEvent(event, "Harvest")
		end
	end
	local others = {
		MAIL_SHOW = function() Harvest.RecordNPC("mailbox") end,
		PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(_, interaction) Harvest.OnInteraction(interaction) end,
		PLAYER_LEAVING_WORLD = Harvest.LeavingWorld,
		PLAYER_ENTERING_WORLD = Harvest.EnteringWorld,
		ZONE_CHANGED_NEW_AREA = Harvest.EnteringWorld,
		PLAYER_DEAD = Harvest.RecordDeath,
	}
	for event, fn in pairs(others) do
		if on and Harvest.HasEvent(event) then
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
		ns.RegisterEvent("GOSSIP_CLOSED", "Harvest", onGossipClosed)
		hookGossip()
	else
		ns.UnregisterEvent("GOSSIP_CLOSED", "Harvest")
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

