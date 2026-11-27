-- MapScout contribution mode: what is sent, as text. The format is fixed from
-- the first release (the generator of 2.0 reads it): a later change is a new
-- FORMAT number, and the generator keeps reading the old ones.
--
-- Format 1: one line per row, fields separated by a tab. A text field has its
-- tabs and line breaks turned into spaces; a missing value is empty; numbers
-- as written (positions 0-1, 4 decimals). The first line says what it is:
--   contribution  format  id  locale  pack  build
--     format 1; id the anonymous ID; locale the client's language ("esES");
--     pack the data pack's version ("" without one); build the client's
--     ("1.60.1.71139")
-- Then one line per record not sent yet, by kind in this order, sorted:
--   npc        npc  locale  name  faction  title  services  skill  uiMap  x  y  seen
--     services space-separated ("bank repair vendor"); seen the places it was
--     talked to, space-separated, each "uiMap:x:y:spawn" (spawn: the last
--     part of its GUID, tells apart NPCs that share an ID)
--   object     service  object  uiMap  x  y
--   entrance   instance  name  kind  uiMap  x  y
--   direction  locale  asked  name  poi  texture  guard  uiMap  x  y
--   graveyard  how  npc  uiMap  x  y  continent  cx  cy  died
-- The marks around it and its compression belong to the export window.

local _, ns = ...

local Contribute = ns.Contribute

local Export = {}
Contribute.Export = Export

Export.FORMAT = 1

local function field(value)
	if value == nil then
		return ""
	end
	return (tostring(value):gsub("[\t\r\n]", " "))
end

local function line(fields, n)
	local out = {}
	for i = 1, n do
		out[i] = field(fields[i])
	end
	return table.concat(out, "\t")
end

local function sortedKeys(set)
	local list = {}
	for key, on in pairs(set or {}) do
		if on then
			list[#list + 1] = tostring(key)
		end
	end
	table.sort(list)
	return list
end

local function seenText(seen)
	local spots = {}
	for i, spot in ipairs(seen or {}) do
		spots[i] = ("%s:%s:%s:%s"):format(field(spot[1]), field(spot[2]), field(spot[3]), field(spot[4]))
	end
	return table.concat(spots, " ")
end

-- kind -> { tag, row(entry) }
local ROWS = {
	{ "npcs", "npc", function(e)
		return { e.id, e.locale, e.name, e.faction, e.title, table.concat(sortedKeys(e.services), " "), e.skill,
			e.map, e.x, e.y, seenText(e.seen) }, 11
	end },
	{ "objects", "object", function(e)
		return { e.service, e.objectID, e.map, e.x, e.y }, 5
	end },
	{ "entrances", "entrance", function(e)
		return { e.instance, e.name, e.kind, e.map, e.x, e.y }, 6
	end },
	{ "directions", "direction", function(e)
		return { e.locale, e.asked, e.name, e.poi, e.texture, e.guard, e.map, e.x, e.y }, 9
	end },
	{ "graveyards", "graveyard", function(e)
		return { e.how, e.npc, e.map, e.x, e.y, e.continent, e.cx, e.cy, e.died }, 9
	end },
}

function Export.Header(id)
	local version, build = GetBuildInfo()
	return line({ "contribution", Export.FORMAT, id, GetLocale(), ns.Packs.Version() or "",
		build and (version .. "." .. build) or version }, 6)
end

-- The text of what has not been sent yet, and how many records it has
-- (0 and nil when there is nothing to send)
function Export.Text()
	local data = ns.db and ns.db.contribution
	if not (data and data.id) then
		return nil, 0
	end
	local lines, n = { Export.Header(data.id) }, 0
	for _, spec in ipairs(ROWS) do
		local kind, tag, row = spec[1], spec[2], spec[3]
		local rows = {}
		for _, entry in pairs(data[kind] or {}) do
			if not entry.sent then
				local fields, count = row(entry)
				rows[#rows + 1] = tag .. "\t" .. line(fields, count)
			end
		end
		table.sort(rows)
		for _, text in ipairs(rows) do
			lines[#lines + 1] = text
		end
		n = n + #rows
	end
	if n == 0 then
		return nil, 0
	end
	return table.concat(lines, "\n"), n
end
