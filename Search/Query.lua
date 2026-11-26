-- MapScout: what the player typed, split into its parts.
--   Query.Parse("@services bank")      -> filters { services }, text "bank"
--   Query.Parse("45.2, 67.8")          -> coords { x = .452, y = .678 } (open map)
--   Query.Parse("Elwynn 42 65")        -> coords + mapID of Elwynn Forest
--   Query.Parse("@zon")                -> an @ word being typed: zones (it starts "zones")
--   Query.Parse("@nonsense mail")      -> unknown @ word: text "nonsense mail"
-- Result: { raw, filters = { { provider, category }, ... }, coords = { x, y } or nil,
--   zoneText, mapID (when a zone was named with the coordinates), text, words }.
-- text and words are normalized (ns.Normalize): ready to compare with the index.

local _, ns = ...
local L = ns.L

local Query = {}
ns.Query = Query

-- A number like 45, 45.2 or 45,2 (Spanish decimal comma)
local NUMBER = "%d+[%.,]?%d*"
-- Two numbers separated by spaces, a comma or a semicolon, not inside a longer number
local COORDS = "%f[%d](" .. NUMBER .. ")[%s,;]+(" .. NUMBER .. ")%f[^%d]"

local function toNumber(text)
	return tonumber((text:gsub(",", "."):gsub("%.$", "")))
end

-- Finds coordinates (0-100 each) in a text.
-- Returns x, y as 0-1 and the text without them; or nil, nil and the text.
-- With two decimals separated by a comma ("45,2 67,8" or "45.2,67.8") the
-- decimal form is tried first, so "45,2 67,8" is 45.2 / 67.8, not 45 / 2.
function Query.ParseCoordinates(text)
	local patterns = {
		"%f[%d](%d+[%.,]%d+)[%s,;]+(%d+[%.,]%d+)%f[^%d]", -- two decimals
		COORDS,
	}
	for _, pattern in ipairs(patterns) do
		local first, last, a, b = text:find(pattern)
		if first then
			local x, y = toNumber(a), toNumber(b)
			if x and y and x <= 100 and y <= 100 then
				return x / 100, y / 100, text:sub(1, first - 1) .. " " .. text:sub(last + 1)
			end
			return nil, nil, text
		end
	end
	return nil, nil, text
end

-- opts.findZone(text) -> mapID: how a zone name is resolved (default ns.FindMapByName)
function Query.Parse(raw, opts)
	opts = opts or {}
	raw = raw or ""
	local result = { raw = raw, filters = {} }

	-- @ words: known ones select providers or categories; a word being typed
	-- selects the filters it starts ("@zon" -> zones); others stay as text
	local seen = {}
	local rest = raw:gsub("@([^%s@]+)", function(word)
		local matches = ns.Registry.FindByFilter(word)
		if #matches == 0 then
			matches = ns.Registry.FindByFilterPrefix(word)
		end
		if #matches == 0 then
			return word
		end
		for _, match in ipairs(matches) do
			local key = match.provider .. "." .. tostring(match.category)
			if not seen[key] then
				seen[key] = true
				result.filters[#result.filters + 1] = match
			end
		end
		return " "
	end)

	-- Coordinates, and what is left next to them may be a zone name
	local x, y
	x, y, rest = Query.ParseCoordinates(rest)
	if x then
		result.coords = { x = x, y = y }
		local zoneText = ns.Normalize(rest)
		if zoneText ~= "" then
			result.zoneText = zoneText
			result.mapID = (opts.findZone or ns.FindMapByName)(zoneText)
			if result.mapID then
				rest = "" -- the words were the zone, not something to search
			end
		end
	end

	result.text = ns.Normalize(rest)
	result.words = ns.SplitWords(result.text)
	return result
end

-- /ms debug query <text> --------------------------------------------------------

ns.RegisterDebug("query", function(text)
	local q = Query.Parse(text)
	local filters = {}
	for _, f in ipairs(q.filters) do
		filters[#filters + 1] = f.category and (f.provider .. "/" .. f.category) or f.provider
	end
	local coords = q.coords and ("%.1f, %.1f"):format(q.coords.x * 100, q.coords.y * 100) or "-"
	local zone = q.zoneText and (q.zoneText .. " = " .. tostring(q.mapID)) or "-"
	ns.Print(L.DEBUG_QUERY_RESULT:format(#filters > 0 and table.concat(filters, ", ") or "-", coords, zone, q.text))
end, L.DEBUG_QUERY)
