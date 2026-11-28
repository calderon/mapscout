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
-- What is copied (Export.Wrap) has marks around it, so a cut copy is noticed:
--   -----BEGIN MAPSCOUT 1 PLAIN-----     the text as it is, or
--   -----BEGIN MAPSCOUT 1 DEFLATE-----   compressed (Deflate) and in Base64,
--                                        in lines of 76 letters
--   ...
--   -----END MAPSCOUT-----
-- (1 is the version of the marks; the text inside says its own format). It
-- is compressed when the client can (C_EncodingUtil) and it is shorter.

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

-- What has not been sent yet: the text (nil when nothing is new), how many
-- records it has, how many of each kind ({ npcs = 3, ... }), the records
-- themselves (to mark them as sent: Export.MarkSent) and how many are left
-- for a later part. With a limit, the text holds the first records whose
-- copy (Export.Wrap) fits in that many letters (at least one): the form that
-- receives it takes a limited answer.
function Export.Collect(limit)
	local data = ns.db and ns.db.contribution
	local counts, picked = {}, {}
	if not (data and data.id) then
		return nil, 0, counts, picked, 0
	end
	local rows = {}
	for _, spec in ipairs(ROWS) do
		local kind, tag, row = spec[1], spec[2], spec[3]
		local list = {}
		for key, entry in pairs(data[kind] or {}) do
			if not entry.sent then
				local fields, count = row(entry)
				list[#list + 1] = { tag .. "\t" .. line(fields, count), kind, key, entry }
			end
		end
		table.sort(list, function(a, b)
			return a[1] < b[1]
		end)
		for _, item in ipairs(list) do
			rows[#rows + 1] = item
		end
	end
	if #rows == 0 then
		return nil, 0, counts, picked, 0
	end
	local header = Export.Header(data.id)
	local function textOf(n)
		local lines = { header }
		for i = 1, n do
			lines[i + 1] = rows[i][1]
		end
		return table.concat(lines, "\n")
	end
	local n = #rows
	if limit and #Export.Wrap(textOf(n)) > limit then
		-- the most records that fit: fits(low) and not fits(high)
		local low, high = 1, n
		while high - low > 1 do
			local mid = math.floor((low + high) / 2)
			if #Export.Wrap(textOf(mid)) <= limit then
				low = mid
			else
				high = mid
			end
		end
		n = low
	end
	for _, spec in ipairs(ROWS) do
		counts[spec[1]] = 0
	end
	for i = 1, n do
		local kind = rows[i][2]
		counts[kind] = counts[kind] + 1
		picked[i] = { kind, rows[i][3], rows[i][4] }
	end
	return textOf(n), n, counts, picked, #rows - n
end

-- The text of what has not been sent yet, and how many records it has
-- (nil and 0 when there is nothing to send)
function Export.Text()
	local text, n = Export.Collect()
	return text, n
end

-- Marks those records as sent (the ones still kept: clear may have forgotten
-- them while the window was open). Returns how many.
function Export.MarkSent(picked)
	local data = ns.db and ns.db.contribution
	local n = 0
	for _, record in ipairs(picked or {}) do
		local kind, key, entry = record[1], record[2], record[3]
		if data and data[kind] and data[kind][key] == entry then
			entry.sent = true
			n = n + 1
		end
	end
	return n
end

Export.MARKS = 1 -- version of the marks around the copied text
Export.LIMIT = 30000 -- most letters per copied text (the form takes about 32000)
Export.WIDTH = 76 -- letters per line of the compressed text

-- The text compressed and in Base64, or nil when the client can't
local function compress(text)
	local util = C_EncodingUtil
	if not (util and util.CompressString and util.EncodeBase64) then
		return nil
	end
	local deflate = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
	local ok, packed = pcall(util.CompressString, text, deflate)
	if not (ok and type(packed) == "string") then
		return nil
	end
	local encoded
	ok, encoded = pcall(util.EncodeBase64, packed)
	if not (ok and type(encoded) == "string" and encoded ~= "") then
		return nil
	end
	local lines = {}
	for i = 1, #encoded, Export.WIDTH do
		lines[#lines + 1] = encoded:sub(i, i + Export.WIDTH - 1)
	end
	return table.concat(lines, "\n")
end

-- What the player copies: the text between its marks, compressed when it can
-- be and it is shorter
function Export.Wrap(text)
	local how, body = "PLAIN", text
	local packed = compress(text)
	if packed and #packed < #text then
		how, body = "DEFLATE", packed
	end
	return ("-----BEGIN MAPSCOUT %d %s-----\n%s\n-----END MAPSCOUT-----"):format(Export.MARKS, how, body)
end
