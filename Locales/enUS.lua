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

	-- Search bar
	SEARCH_PLACEHOLDER = "Search the map",
	SETTINGS = "MapScout settings",

	-- Results
	RESULTS_IN_ZONE = "In %s",
	RESULTS_ELSEWHERE = "Elsewhere",
	RESULTS_NO_PLACE = "Unknown place",
	RESULTS_NONE = "No results",
	RESULTS_HINT = "Try @ or coordinates (45 67)",
	RESULTS_WIDENED = "Nothing in %s; showing all of %s",

	-- Preview
	PREVIEW_COORDS = "%.1f, %.1f",
	PREVIEW_DISTANCE = "%s away",

	-- Going to a result
	WAYPOINT_NOT_POSSIBLE = "the game doesn't allow a map pin for %s here; the map shows where it is.",

	-- Places (geography provider)
	GEOGRAPHY_NAME = "Places",
	GEOGRAPHY_DESCRIPTION = "Continents, cities, zones and battlegrounds of the world map",
	GEOGRAPHY_CONTINENTS = "Continents",
	GEOGRAPHY_CITIES = "Cities",
	GEOGRAPHY_ZONES = "Zones",
	GEOGRAPHY_OTHERS = "Battlegrounds and others",

	-- Coordinates
	COORDS_GO = "Go to %s",
	COORDS_GO_IN = "Go to %s in %s",
	COORDS_SUBTITLE = "Coordinates",

	-- Flight masters
	FLIGHTS_NAME = "Flight masters",
	FLIGHTS_DESCRIPTION = "Flight masters of your faction and neutral ones",
	FLIGHTS_SUBTITLE = "Flight master",
	FLIGHTS_SUBTITLE_UNKNOWN = "Flight master · not known yet",
	FLIGHTS_HOW_TO_LEARN = "Open the flight map of any flight master once, so MapScout learns which ones this character knows.",
	DEBUG_FLIGHTS = "flight masters and the map each one is placed in",
	DEBUG_FLIGHTS_RESULT = "%d flight masters (%d known) for %s:",

	-- Quests
	QUESTS_NAME = "Quests",
	QUESTS_DESCRIPTION = "The quests in your log, where to do them or turn them in",
	QUESTS_READY = "Ready to turn in",
	QUESTS_ONGOING = "In progress",
	QUESTS_SUBTITLE = "Level %d · %s",
	QUESTS_NO_PLACE = "The game doesn't show where this quest is on the map.",

	-- Available quests (QuestieDB)
	AVAILABLE_NAME = "Available quests",
	AVAILABLE_DESCRIPTION = "Quests you can take now, from QuestieDB",
	AVAILABLE_SUBTITLE = "Available · Level %d · %s",
	AVAILABLE_GIVER = "Given by %s",
	DEBUG_QUESTIE = "available quests from QuestieDB",
	DEBUG_QUESTIE_RESULT = "QuestieDB contract %d: %d quests, %d available now (%d with no known place), built in %.0f ms",

	-- Services (QuestieDB)
	SERVICES_NAME = "Services",
	SERVICES_DESCRIPTION = "Banks, inns, trainers and other services, from QuestieDB",
	SERVICE_bank = "Bank",
	SERVICE_auction = "Auction house",
	SERVICE_inn = "Inn",
	SERVICE_stable = "Stable master",
	SERVICE_trainer = "Trainer",
	SERVICE_repair = "Repairs",
	SERVICE_battle = "Battlemaster",
	SERVICE_guild = "Guild",
	SERVICE_vendor = "Vendor",
	DEBUG_SERVICES = "services from QuestieDB",
	DEBUG_SERVICES_RESULT = "QuestieDB: %d NPCs, %d services, built in %.0f ms",

	-- Options page
	OPTIONS_ABOUT = "A search bar in the world map. Type a place, a service, a quest or coordinates; @ chooses what to search (@zona, @banco, @mision...).",
	OPTIONS_AFTER_COMBAT = "the options will open when combat ends.",

	-- Search providers
	PROVIDER_FAILED = "the search source \"%s\" failed %d times and is turned off until you reload the interface.",
	PROVIDER_STATE_ON = "on",
	PROVIDER_STATE_OFF = "off",
	PROVIDER_STATE_FAILED = "turned off after errors",
	DEBUG_QUERY = "how a search is read: /ms debug query <text>",
	DEBUG_QUERY_RESULT = "filters: %s · coordinates: %s · zone: %s · text: \"%s\"",
	DEBUG_SEARCH = "search without the map: /ms debug search <text>",
	DEBUG_SEARCH_TITLE = "\"%s\": %d results",
	DEBUG_SEARCH_LINE = "  %d. %s (%s) %.0f%s",
	DEBUG_BENCH = "time a search: /ms debug bench <text>",
	DEBUG_BENCH_RESULT = "\"%s\": %.2f ms, %d candidates, %d results, typos: %s · typed letter by letter (%d searches): %.2f ms, slowest %.2f ms · index: %d providers, %d entries, built in %.2f ms",
	DEBUG_MAP = "the world map layer: /ms debug map [outline]",
	DEBUG_MAP_NOT_READY = "the world map layer is not ready yet",
	DEBUG_MAP_RESULT = "map %s (%s), open: %s, layer %.0f x %.0f, in combat: %s",
	DEBUG_BAR = "the map search bar: /ms debug bar [live]",
	DEBUG_BAR_LIVE = "bar: \"%s\" -> %d results in %.2f ms",
	DEBUG_BAR_LIVE_ON = "every search of the bar will be shown in chat (/ms debug bar live to stop)",
	DEBUG_BAR_LIVE_OFF = "searches of the bar no longer shown in chat",
	DEBUG_BAR_NOTHING = "the bar hasn't searched anything yet",
	DEBUG_SAMPLE = "test places (development only): /ms debug sample [big]",
	DEBUG_SAMPLE_ON = "sample provider on: %d places (/ms debug sample again to turn it off, @sample to see them)",
	DEBUG_SAMPLE_OFF = "sample provider off",
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
local WORDS = {
	-- singular first (the one shown), plurals still work
	GEOGRAPHY = { "region", "map", "places", "regions", "maps" },
	CONTINENTS = { "continents" },
	CITIES = { "capital", "cities", "capitals" },
	ZONES = { "zones" },
	OTHERS = { "bg", "area", "battlegrounds", "areas" },
	FLIGHTS = { "fly", "taxi", "flights" },
	FLIGHT_MASTER = { "flight master" },
	QUESTS = { "quests", "mission", "missions" },
	QUEST = { "quest" },
	AVAILABLE = { "availables" },
	-- services: the first word is the main @ word (singular)
	SERVICES = { "services" },
	BANK = { "bank", "banks", "banker" },
	AUCTION = { "auction", "ah", "auctioneer", "auctions" },
	INN = { "inn", "innkeeper", "inns", "tavern" },
	STABLE = { "stable", "stablemaster", "stables" },
	TRAINER = { "trainer", "trainers" },
	REPAIR = { "repair", "repairs" },
	BATTLEMASTER = { "battlemaster", "battle" },
	GUILD = { "guild", "tabard" },
	VENDOR = { "vendor", "merchant", "shop", "vendors" },
}

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
