-- MapScout: whether the data pack already has what the contribution mode
-- recorded, so only what it lacks is kept (and what it has since gained is
-- dropped). A record is lacking when it has something the generator turns
-- into pack data and the pack has nothing of that kind within YARDS of it.
-- Without the pack (another game, disabled, missing) everything is lacking.
-- The pack's categories are built only for the check: the ones nobody else
-- had built are released again with PackCheck.Done().
--   PackCheck.Lacks(kind, entry)   kind as Contribute.KINDS, entry as kept

local _, ns = ...

local PackCheck = {}
ns.PackCheck = PackCheck

-- Closer than this (yards) to a point of the pack of the same kind: the pack
-- has it. A player talks to an NPC within a few steps; an entrance's point is
-- where the player stood up to 3 s before the loading screen.
PackCheck.YARDS = { npcs = 10, objects = 10, directions = 10, entrances = 20, graveyards = 20 }

-- A service NPC's service as kept -> the pack's service kind. Vendors (with
-- their title, which tells quartermasters apart) are not in the pack yet: so
-- that one day its data needs no other addon, every one is lacking. The others
-- (flight masters, which the game gives while playing, tabard vendors,
-- gossip) are never kept.
PackCheck.NPC_KINDS = {
	bank = "bank", auction = "auction", innkeeper = "inn", stable = "stable", repair = "repair",
	guild = "guild", battlemaster = "battle", transmog = "transmog", barber = "barber", vendor = "vendor",
}
PackCheck.OBJECT_KINDS = { mailbox = "mailbox" }

local borrowed = {} -- categories built for a check, released by Done

local function category(name)
	if not ns.Packs.IsBuilt(name) then
		local data = ns.Packs.Get(name)
		if data then
			borrowed[name] = true
		end
		return data
	end
	return (ns.Packs.Get(name))
end

-- Releases the categories built only for the checks
function PackCheck.Done()
	for name in pairs(borrowed) do
		ns.Packs.Release(name)
	end
	borrowed = {}
end

-- Whether the pack can be read at all
function PackCheck.HasPack()
	return ns.Packs.Load() ~= nil
end

local function near(mapID, x, y, packMap, px, py, yards)
	local distance = ns.Yards(mapID, x, y, packMap, px / 10000, py / 10000)
	return distance ~= nil and distance <= yards
end

-- Whether a list of rows ({ kind, x, y, ... } on mapID) has one of kind near
local function rowNear(rows, kind, mapID, x, y, yards)
	for _, row in ipairs(rows or {}) do
		if (kind == nil or row[1] == kind) and near(mapID, x, y, mapID, row[2], row[3], yards) then
			return true
		end
	end
	return false
end

local function trainerNear(mapID, x, y, yards)
	local data = category("trainers")
	for _, row in ipairs(data and data.maps and data.maps[mapID] or {}) do
		if near(mapID, x, y, mapID, row[3], row[4], yards) then
			return true
		end
	end
	return false
end

local lacks = {}

-- Lacking when one of its services is not in the pack near it
function lacks.npcs(entry)
	local yards = PackCheck.YARDS.npcs
	local services = entry.services or {}
	local data
	for service in pairs(services) do
		local kind = PackCheck.NPC_KINDS[service]
		if service == "trainer" then
			if not trainerNear(entry.map, entry.x, entry.y, yards) then
				return true
			end
		elseif kind then
			data = data or category("services")
			local rows = data and data.maps and data.maps[entry.map]
			if not rowNear(rows, kind, entry.map, entry.x, entry.y, yards) then
				return true
			end
		end
	end
	return false
end

function lacks.objects(entry)
	local kind = PackCheck.OBJECT_KINDS[entry.service]
	if not kind then
		return false
	end
	local data = category("services")
	return not rowNear(data and data.maps and data.maps[entry.map], kind, entry.map, entry.x, entry.y,
		PackCheck.YARDS.objects)
end

-- A guard's answer: the pack has a service or trainer of that name near it
-- (names as the game wrote them, in the record's language)
local function namedNear(data, first, entry, yards)
	local names = data and data.names and data.names[entry.locale]
	for _, row in ipairs(data and data.maps and data.maps[entry.map] or {}) do
		local name = names and names[row[first + 5]]
		if name == entry.name and near(entry.map, entry.x, entry.y, entry.map, row[first + 1], row[first + 2], yards) then
			return true
		end
	end
	return false
end

function lacks.directions(entry)
	if not entry.name or entry.name == "" then
		return true
	end
	local yards = PackCheck.YARDS.directions
	return not (namedNear(category("services"), 1, entry, yards) or namedNear(category("trainers"), 2, entry, yards))
end

-- Its entrance (or one of its doors) near it; an entrance not confirmed yet
-- (uiMapID 0) is lacking
function lacks.entrances(entry)
	local data = category("dungeons")
	if not data then
		return true
	end
	local yards = PackCheck.YARDS.entrances
	local entrance = data.entrances and data.entrances[entry.instance]
	if entrance and entrance[2] ~= 0 and near(entry.map, entry.x, entry.y, entrance[2], entrance[3], entrance[4], yards) then
		return false
	end
	for _, door in ipairs(data.doors and data.doors[entry.instance] or {}) do
		if near(entry.map, entry.x, entry.y, door[2], door[3], door[4], yards) then
			return false
		end
	end
	return true
end

-- A spirit healer near it, on any map of the same continent
function lacks.graveyards(entry)
	local data = category("spirithealers")
	local yards = PackCheck.YARDS.graveyards
	for mapID, points in pairs(data and data.maps or {}) do
		for _, point in ipairs(points) do
			if near(entry.map, entry.x, entry.y, mapID, point[1], point[2], yards) then
				return false
			end
		end
	end
	return true
end

-- Whether an entry has something the pack lacks (kind: "npcs", "objects",
-- "entrances", "directions" or "graveyards")
function PackCheck.Lacks(kind, entry)
	local check = lacks[kind]
	if not (check and entry and entry.map and entry.x and entry.y) then
		return false
	end
	return check(entry)
end
