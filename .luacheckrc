-- luacheck settings (only globals are checked: see scripts/check-lua.sh)
-- Add here every WoW API global the addon uses. A name missing from both lists
-- makes the check fail: either it is a typo, or it has to be added here.
std = "lua51"
max_line_length = false
exclude_files = { "node_modules/", ".release/", "dev/" }

-- Globals MapScout defines
globals = {
	"MapScoutAPI",
	"MapScoutDB",
	"MapScoutCharDB",
	"SLASH_MAPSCOUT1",
	"SLASH_MAPSCOUT2",
	"SlashCmdList",
}

-- WoW API and Blizzard UI globals MapScout reads
read_globals = {
	-- Lua extensions of the game
	"strsplit", "strjoin", "strtrim", "strlower", "strupper", "strsub", "strfind", "strmatch",
	"format", "tinsert", "tremove", "wipe", "max", "min", "floor", "ceil", "abs",
	"date", "time", "debugprofilestop", "geterrorhandler", "hooksecurefunc", "securecallfunction",
	-- Namespaces
	"C_AddOns", "C_AreaPoiInfo", "C_EncounterJournal", "C_Map", "C_QuestLog", "C_SuperTrack",
	"C_TaskQuest", "C_TaxiMap", "C_Timer", "C_VignetteInfo",
	-- Functions
	"CreateFrame", "CreateFramePool", "GetLocale", "GetTime", "InCombatLockdown", "IsMacClient",
	"IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "PlaySound", "UnitFactionGroup",
	"UnitGUID", "UnitName", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
	-- Frames and UI
	"UIParent", "WorldMapFrame", "GameTooltip", "MenuUtil", "Settings", "UiMapPoint",
	"ChatFrame_OpenChat", "DEFAULT_CHAT_FRAME", "EventRegistry", "TomTom",
}
