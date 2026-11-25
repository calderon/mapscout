-- MapScout: texts in English (the base: every key is defined here).
-- Other locales only override what they translate; a key missing everywhere
-- shows the key itself, so a forgotten text is visible, never an error.
-- To add a language: copy Locales/esES.lua, change the GetLocale() check,
-- translate, and add the file to MapScout.toc after this one.

local _, ns = ...

local EN = {
	-- Slash commands
	HELP_TITLE = "commands (/mapscout or /ms):",
	HELP_HELP = "this list",
	HELP_VERSION = "show the version",
	HELP_DEBUG = "developer checks (/ms debug for the list)",
	HELP_DIAG = "show the game version and what this client can do",
	VERSION = "version %s",
	DEBUG_TITLE = "debug topics:",

	-- /ms diag
	DIAG_HEADER = "version %s · WoW %s · %s · %s",
	YES = "yes",
	NO = "no",

	-- Saved data
	DB_ACCOUNT = "account",
	DB_CHARACTER = "character",
	DB_NEWER = "your saved %s data comes from a newer MapScout. It is left untouched, and changes made now won't be saved.",
	DB_FAILED = "your saved %s data could not be updated (%s). It is left untouched, and changes made now won't be saved.",
	DB_NOT_LOADED = "saved data not loaded yet",
	DB_STATE_new = "new",
	DB_STATE_current = "current",
	DB_STATE_upgraded = "upgraded",
	DB_STATE_newer = "newer",
	DB_STATE_failed = "failed",
	DB_REPORT = "saved data: schema %d (current %d), account %s, character %s",
	DB_REPORT_ACCOUNT = "  account: %d aliases, %d hidden, %d favorites, %d in frequency, max results %d",
	DB_REPORT_CHARACTER = "  character: %d recent searches, %d known flight paths",
	DEBUG_DB = "saved data: schema, state and sizes",
	DEBUG_API = "public API: version, state and functions",
	DEBUG_API_RESULT = "MapScoutAPI version %d, ready: %s, %d calls waiting, functions: %s",
	DEBUG_PROVIDERS = "search providers: state, entries and errors",
	DEBUG_PROVIDERS_NONE = "no search providers registered",
	DEBUG_PROVIDERS_TITLE = "%d search providers:",
	DEBUG_PROVIDERS_LINE = "  %s (%s): %s, %d entries, %d errors, filters %s",

	-- Search providers
	PROVIDER_FAILED = "the search source \"%s\" failed %d times and is turned off until you reload the interface.",
	PROVIDER_STATE_ON = "on",
	PROVIDER_STATE_OFF = "off",
	PROVIDER_STATE_FAILED = "turned off after errors",
	DEBUG_QUERY = "how a search is read: /ms debug query <text>",
	DEBUG_QUERY_RESULT = "filters: %s · coordinates: %s · zone: %s · text: \"%s\"",
	DEBUG_NORMALIZE = "how a text is searched: /ms debug normalize <text>",
	DEBUG_NORMALIZE_RESULT = "\"%s\" is searched as \"%s\"",

	-- Key names (ns.KeyName)
	KEY_ALT = "Alt",
	KEY_ALT_MAC = "Option",
	KEY_CTRL = "Ctrl",
	KEY_CTRL_MAC = "Cmd",
}

-- Search words (ns.Words): English lists, always searchable in every language.
-- Providers add theirs here (e.g. FILTER_FLIGHTS = { "flights", "flight" }).
local WORDS = {}

ns.L_EN = EN
ns.W_EN = WORDS
ns.L = setmetatable({}, {
	__index = function(_, key)
		local text = EN[key]
		return text == nil and key or text
	end,
})
ns.W = {} -- localized search words, filled by the player's locale file

-- Name of a modifier key as the player sees it ("ALT" -> "Alt", or "Option" on Mac)
function ns.KeyName(key)
	local L = ns.L
	if IsMacClient() then
		return L["KEY_" .. key .. "_MAC"]
	end
	return L["KEY_" .. key]
end

-- Search words for a key: the English ones plus the player's language,
-- lowercase and without repeats.
function ns.Words(key)
	local result, seen = {}, {}
	for _, list in ipairs({ WORDS[key], ns.W[key] }) do
		for _, word in ipairs(list) do
			word = word:lower()
			if not seen[word] then
				seen[word] = true
				result[#result + 1] = word
			end
		end
	end
	return result
end
