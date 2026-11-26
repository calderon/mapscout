-- MapScout: small helpers shared by the whole addon.
-- ns.Normalize: the form every text takes before searching, so that
-- "Grom'gol", "GROMGOL" and "gromgol" are the same, and "Ventormenta"
-- starts with "ventor". The search index normalizes each entry once, when it
-- is indexed, and the query once per search: never per entry and keystroke.

local _, ns = ...
local L = ns.L

-- Latin letters with accents (UTF-8, two bytes) -> plain letters.
-- Covers English, Spanish and the other Latin-alphabet game languages.
local ACCENTS = {}
do
	local LATIN1 = { -- U+00C0 .. U+00FF in order, both cases
		"a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i", -- À..Ï
		"d", "n", "o", "o", "o", "o", "o", " ", "o", "u", "u", "u", "u", "y", "th", "ss", -- Ð..ß (× is a sign)
		"a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i", -- à..ï
		"d", "n", "o", "o", "o", "o", "o", " ", "o", "u", "u", "u", "u", "y", "th", "y", -- ð..ÿ (÷ is a sign)
	}
	for i, plain in ipairs(LATIN1) do
		ACCENTS["\195" .. string.char(127 + i)] = plain
	end
	ACCENTS["\197\146"] = "oe" -- Œ
	ACCENTS["\197\147"] = "oe" -- œ
end

-- Apostrophes join the word: ' ’ ‘ ´ `
local APOSTROPHES = { "'", "`", "\226\128\153", "\226\128\152", "\194\180" }

local function replaceAccent(char)
	return ACCENTS[char] or char
end

-- Returns the searchable form of a text: no game escape codes, no accents,
-- no apostrophes, lowercase, other signs turned into single spaces.
function ns.Normalize(text)
	if text == nil then
		return ""
	end
	text = tostring(text)
	-- Most texts are plain: skip the steps they don't need
	if text:find("|", 1, true) then
		text = text
			:gsub("|c%x%x%x%x%x%x%x%x", "") -- colours
			:gsub("|r", "")
			:gsub("|T.-|t", " ") -- textures
			:gsub("|A.-|a", " ") -- atlases
			:gsub("|H.-|h(.-)|h", "%1") -- links: keep their text
			:gsub("||", " ")
	end
	text = text:gsub("['`]", "")
	if text:find("[\128-\255]") then
		for i = 3, #APOSTROPHES do
			text = text:gsub(APOSTROPHES[i], "")
		end
		text = text
			:gsub("[\195\197][\128-\191]", replaceAccent)
			:gsub("\226\128[\128-\191]", " ") -- general punctuation: “ ” – — … etc.
			:gsub("\194[\128-\191]", " ") -- Latin-1 signs: « » · ¡ ¿ etc.
	end
	text = text
		:lower()
		:gsub("[%p%c]", " ") -- ASCII punctuation and control characters
		:gsub("%s+", " ")
	return (text:match("^ ?(.-) ?$"))
end

-- Deep copy of a table (other values are returned as they are). Used for the
-- defaults of the saved data and for every table handed to other addons.
function ns.CopyTable(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in pairs(value) do
		result[k] = ns.CopyTable(v)
	end
	return result
end

-- Splits a normalized text into its words.
function ns.SplitWords(normalized)
	local words = {}
	for word in normalized:gmatch("%S+") do
		words[#words + 1] = word
	end
	return words
end

-- Maps by name -------------------------------------------------------------------
-- Continents and zones of the world map tree, with their normalized names,
-- built the first time they are needed.

local MAP_ROOTS = { 946, 947 } -- Cosmic (Retail), Azeroth (Forever, Classic)
local MAP_TYPES = { [2] = true, [3] = true } -- continent, zone (cities are zones)
local mapNames -- list of { mapID, name, normalized, mapType }

local function buildMapNames()
	mapNames = {}
	if not (C_Map and C_Map.GetMapChildrenInfo) then
		return
	end
	local seen = {}
	for _, root in ipairs(MAP_ROOTS) do
		for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
			if MAP_TYPES[info.mapType] and not seen[info.mapID] then
				seen[info.mapID] = true
				mapNames[#mapNames + 1] = {
					mapID = info.mapID, name = info.name, normalized = ns.Normalize(info.name), mapType = info.mapType,
				}
			end
		end
	end
end

-- Finds a continent or zone by (part of) its name: the exact name first, then
-- a name that starts with it, then a name with a word that starts with it
-- ("elwynn" finds "Bosque de Elwynn"). Zones win over continents, then the
-- shortest name. Returns mapID and name, or nil.
function ns.FindMapByName(text)
	local wanted = ns.Normalize(text)
	if wanted == "" then
		return nil
	end
	if not mapNames then
		buildMapNames()
	end
	local best, bestRank
	for _, map in ipairs(mapNames) do
		local rank
		if map.normalized == wanted then
			rank = 1
		elseif map.normalized:sub(1, #wanted) == wanted then
			rank = 2
		elseif (" " .. map.normalized):find(" " .. wanted, 1, true) then
			rank = 3
		end
		if rank then
			rank = rank * 10 + (map.mapType == 3 and 0 or 1)
			if not best or rank < bestRank or (rank == bestRank and #map.normalized < #best.normalized) then
				best, bestRank = map, rank
			end
		end
	end
	if best then
		return best.mapID, best.name
	end
end

-- Where a map is -----------------------------------------------------------------
-- For a uiMapID: its name, its zone (the nearest map of type zone, itself
-- included) and its continent. Cached: map data doesn't change in a session.

local MAP_TYPE_CONTINENT, MAP_TYPE_ZONE = 2, 3
local places = {}

function ns.MapPlace(mapID)
	if not mapID then
		return nil
	end
	local place = places[mapID]
	if place ~= nil then
		return place or nil
	end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if not info then
		places[mapID] = false
		return nil
	end
	place = { mapID = mapID, name = info.name, mapType = info.mapType, parent = info.parentMapID, ancestors = {} }
	local current, guard = info, 0
	while current and guard < 20 do -- guard: never loop on a broken map tree
		guard = guard + 1
		local id = current.mapID or mapID
		place.ancestors[id] = true
		if not place.zoneID and current.mapType == MAP_TYPE_ZONE then
			place.zoneID, place.zoneName = id, current.name
		end
		if current.mapType == MAP_TYPE_CONTINENT then
			place.continentID, place.continentName = id, current.name
			break
		end
		if not current.parentMapID or current.parentMapID == 0 then
			break
		end
		current = C_Map.GetMapInfo(current.parentMapID)
	end
	place.zoneID = place.zoneID or mapID
	place.zoneName = place.zoneName or info.name
	places[mapID] = place
	return place
end

-- Is this map the other one, or inside it (a city in its zone, a zone in its continent)?
function ns.IsMapInside(mapID, outerID)
	if not (mapID and outerID) then
		return false
	end
	local place = ns.MapPlace(mapID)
	return place ~= nil and place.ancestors[outerID] == true
end

-- Distance --------------------------------------------------------------------

-- Yards from the player to a point of a map, or nil when it can't be known
-- (another continent, an instance, no position).
function ns.DistanceToPlayer(mapID, x, y)
	if not (mapID and x and y and UnitPosition and CreateVector2D and C_Map and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local px, py, _, instance = UnitPosition("player")
	if not px then
		return nil
	end
	local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not world or continent ~= instance then
		return nil
	end
	local wx, wy = world:GetXY()
	local dx, dy = px - wx, py - wy
	return math.sqrt(dx * dx + dy * dy)
end

-- The game measures in yards: meters for every client but enUS (as Bridge).
function ns.FormatDistance(yards)
	if GetLocale() == "enUS" then
		if yards >= 1000 then
			return ("%.1fk yd"):format(yards / 1000)
		end
		return ("%d yd"):format(math.floor(yards + 0.5))
	end
	local meters = yards * 0.9144
	if meters >= 1000 then
		return ("%.1f km"):format(meters / 1000)
	end
	return ("%d m"):format(math.floor(meters + 0.5))
end

ns.RegisterDebug("normalize", function(text)
	ns.Print(L.DEBUG_NORMALIZE_RESULT:format(text, ns.Normalize(text)))
end, L.DEBUG_NORMALIZE)
