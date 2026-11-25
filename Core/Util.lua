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

ns.RegisterDebug("normalize", function(text)
	ns.Print(L.DEBUG_NORMALIZE_RESULT:format(text, ns.Normalize(text)))
end, L.DEBUG_NORMALIZE)
