-- MapScout: what this game client can do.
-- ns.Caps holds one boolean per capability, found by checking that the game
-- functions exist (feature detection), never by comparing version numbers.
-- Providers and options read it to hide what the client cannot do.
-- Some functions exist but return nothing in a given client (see the Forever
-- table in ARCHITECTURE.md): that is the providers' business, not this file's.

local _, ns = ...
local L = ns.L

-- Each capability and the game functions it needs (all of them must exist).
local CHECKS = {
	{ "settings", { "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory", "Settings.OpenToCategory" } },
	{ "menuUtil", { "MenuUtil.CreateContextMenu" } },
	{ "userWaypoint", { "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap", "UiMapPoint.CreateFromCoordinates" } },
	{ "superTrack", { "C_SuperTrack.SetSuperTrackedUserWaypoint" } },
	{ "taxi", { "C_TaxiMap.GetTaxiNodesForMap" } },
	{ "dungeonEntrances", { "C_EncounterJournal.GetDungeonEntrancesForMap" } },
	{ "areaPOI", { "C_AreaPoiInfo.GetAreaPOIForMap", "C_AreaPoiInfo.GetAreaPOIInfo" } },
	{ "areaPOIEvents", { "C_AreaPoiInfo.GetEventsForMap" } },
	{ "vignettes", { "C_VignetteInfo.GetVignettes", "C_VignetteInfo.GetVignetteInfo", "C_VignetteInfo.GetVignettePosition" } },
	{ "questLog", { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestsOnMap" } },
	{ "taskQuest", { "C_TaskQuest.GetQuestsOnMap" } },
	{ "mapLinks", { "C_Map.GetMapLinksForMap" } },
	{ "loadOnDemand", { "C_AddOns.LoadAddOn", "C_AddOns.IsAddOnLoadOnDemand", "C_AddOns.GetAddOnMetadata" } },
}
ns.CAPS_CHECKS = CHECKS

-- Game flavor from WOW_PROJECT_ID (only used to pick data packs, never for features)
local FLAVORS = {
	[1] = "retail",
	[2] = "classic",
	[18] = "forever",
}

-- Finds a value by its dotted path in the global table ("C_Map.SetUserWaypoint").
local function resolve(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end
	return value
end

local function hasTemplate(name)
	local getInfo = resolve("C_XMLUtil.GetTemplateInfo")
	if type(getInfo) ~= "function" then
		return false
	end
	local ok, info = pcall(getInfo, name)
	return ok and info ~= nil
end

function ns.DetectCaps()
	local caps = {}
	for _, check in ipairs(CHECKS) do
		local ok = true
		for _, path in ipairs(check[2]) do
			if type(resolve(path)) ~= "function" then
				ok = false
				break
			end
		end
		caps[check[1]] = ok
	end
	caps.searchBox = hasTemplate("SearchBoxTemplate")

	local projectID = rawget(_G, "WOW_PROJECT_ID")
	caps.flavor = FLAVORS[projectID] or ("unknown:" .. tostring(projectID))
	local version, build = GetBuildInfo()
	caps.build = tostring(version) .. " (" .. tostring(build) .. ")"
	return caps
end

ns.Caps = ns.DetectCaps()

-- /ms diag ----------------------------------------------------------------

local function yesNo(value)
	return value and ("|cff00ff00" .. L.YES .. "|r") or ("|cffff4040" .. L.NO .. "|r")
end

function ns.CapsReport(caps)
	local lines = {
		L.DIAG_HEADER:format(ns.VERSION, caps.build, caps.flavor, GetLocale()),
	}
	local names = { "searchBox" }
	for _, check in ipairs(CHECKS) do
		names[#names + 1] = check[1]
	end
	local parts = {}
	for _, name in ipairs(names) do
		parts[#parts + 1] = name .. " " .. yesNo(caps[name])
		if #parts == 4 then
			lines[#lines + 1] = "  " .. table.concat(parts, ", ")
			parts = {}
		end
	end
	if #parts > 0 then
		lines[#lines + 1] = "  " .. table.concat(parts, ", ")
	end
	return lines
end

ns.RegisterCommand("diag", function()
	local lines = ns.CapsReport(ns.Caps)
	ns.Print(lines[1])
	for i = 2, #lines do
		DEFAULT_CHAT_FRAME:AddMessage(lines[i])
	end
end, L.HELP_DIAG)
