-- luacheck settings (all warnings are checked: see scripts/check-lua.sh)
-- Add here every WoW API global the addon uses. A name missing from both lists
-- makes the check fail: either it is a typo, or it has to be added here.
std = "lua51"
max_line_length = false
exclude_files = { "node_modules/", ".release/", "dev/" }

ignore = {
	"212/self",  -- unused self in methods (common in WoW frame handlers)
	"212/event", -- unused event argument of event handlers
	"211/_.*",   -- unused variables named _ or _something (on purpose)
	"212/_.*",   -- unused arguments named _ or _something (on purpose)
	"212/%.%.%.", -- unused vararg (the addon name and namespace in every file)
}

-- Unit tests (busted): its globals, and the helpers defined in spec/helpers/wow.lua
local testHelpers = { "LoadAddonFile", "NewNamespace", "ResetWoW", "StubGlobals", "RunTimers", "PendingTimers", "FakeFrames", "ChatLog", "ReportedErrors" }
files["spec/"] = {
	std = "+busted",
	read_globals = testHelpers,
}
files["spec/helpers/"] = {
	globals = {
		"LoadAddonFile", "NewNamespace", "ResetWoW", "StubGlobals", "RunTimers", "PendingTimers", "FakeFrames", "ChatLog", "ReportedErrors", "GameTooltip",
		-- WoW API stubs
		"GetLocale", "GetBuildInfo", "IsMacClient", "debugprofilestop", "bit", "time", "hooksecurefunc", "InCombatLockdown", "C_Timer", "CreateFrame", "DEFAULT_CHAT_FRAME", "geterrorhandler", "strtrim",
		"xpcall", "jit", "unpack",
	},
}

-- Globals MapScout defines
globals = {
	"MapScoutAPI",
	"MapScoutDB",
	"MapScoutCharDB",
	"MapScoutDataForever", -- set by the data pack (MapScout_Data_Forever/Pack.lua)
	"SLASH_MAPSCOUT1",
	"SLASH_MAPSCOUT2",
	"SlashCmdList",
}

-- WoW API and Blizzard UI globals MapScout reads
read_globals = {
	-- Lua extensions of the game
	"strsplit", "strjoin", "strtrim", "strlower", "strupper", "strsub", "strfind", "strmatch",
	"format", "tinsert", "tremove", "wipe", "max", "min", "floor", "ceil", "abs",
	"date", "time", "debugprofilestop", "GetBuildInfo", "geterrorhandler", "hooksecurefunc", "securecallfunction",
	-- Namespaces
	"C_AddOns", "C_AreaPoiInfo", "C_Calendar", "C_DateAndTime", "C_EventUtils", "C_XMLUtil", "C_Texture", "C_EncounterJournal", "C_Map", "C_QuestLog", "C_SuperTrack",
	"C_TaskQuest", "C_TaxiMap", "C_Timer", "C_TooltipInfo", "C_VignetteInfo", "Enum",
	-- Functions
	"CreateFrame", "CreateFramePool", "GetTaxiMapID", "bit", "UnitLevel", "UnitRace", "UnitClass", "GetNumTrainerServices", "GetTrainerServiceSkillLine", "UnitQuestTrivialLevelRange", "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "CreateVector2D", "UnitPosition", "GetLocale", "GetTime", "InCombatLockdown", "IsMacClient",
	"IsInInstance", "GetInstanceInfo", "C_GossipInfo", "CanMerchantRepair",
	"IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "PlaySound", "UnitFactionGroup",
	"UnitGUID", "UnitName", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "UnitIsGhost", "C_DeathInfo",
	-- Frames and UI
	"UIParent", "WorldFrame", "WorldMapFrame", "GameTooltip", "MenuUtil", "Settings", "UiMapPoint",
	"ChatFrame_OpenChat", "DEFAULT_CHAT_FRAME", "EventRegistry", "TomTom",
}
