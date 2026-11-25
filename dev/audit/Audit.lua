-- Client API audit (#20). Not part of the addon: to repeat it on another client, add
-- "dev/audit/Audit.lua" at the end of MapScout.toc (do not commit that), restart the
-- game, run /ms audit and /ms audit2, /reload, and read MapScoutDB.audit and .audit2
-- in WTF/Account/<account>/SavedVariables/MapScout.lua.
-- /ms audit checks which game APIs exist
-- in this client and what they return here, and saves it in MapScoutDB.audit.
local _, ns = ...

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

local APIS = {
	"Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory", "Settings.OpenToCategory",
	"Settings.RegisterVerticalLayoutCategory", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
	"MenuUtil.CreateContextMenu", "MenuUtil.CreateButtonMenu", "EasyMenu", "UIDropDownMenu_Initialize",
	"CreateFramePool", "CreateObjectPool", "CreateScrollBoxListLinearView", "EventRegistry",
	"C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo", "C_Map.GetMapGroupMembersInfo",
	"C_Map.GetAreaInfo", "C_Map.GetPlayerMapPosition", "C_Map.SetUserWaypoint", "C_Map.ClearUserWaypoint",
	"C_Map.CanSetUserWaypointOnMap", "C_Map.GetUserWaypointHyperlink", "C_Map.GetMapPosFromWorldPos",
	"C_Map.GetWorldPosFromMapPos", "C_Map.GetMapInfoAtPosition", "C_Map.GetMapLinksForMap",
	"UiMapPoint.CreateFromCoordinates",
	"C_SuperTrack.SetSuperTrackedUserWaypoint", "C_SuperTrack.IsSuperTrackingUserWaypoint",
	"C_Navigation.GetDistance",
	"C_TaxiMap.GetTaxiNodesForMap", "C_TaxiMap.GetAllTaxiNodes",
	"C_EncounterJournal.GetDungeonEntrancesForMap", "EJ_GetInstanceInfo",
	"C_AreaPoiInfo.GetAreaPOIForMap", "C_AreaPoiInfo.GetAreaPOIInfo", "C_AreaPoiInfo.GetEventsForMap",
	"C_VignetteInfo.GetVignettes", "C_VignetteInfo.GetVignetteInfo", "C_VignetteInfo.GetVignettePosition",
	"C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestsOnMap",
	"C_QuestLog.GetNextWaypoint", "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetTitleForQuestID",
	"C_QuestLog.IsComplete", "GetNumQuestLogEntries", "GetQuestLogTitle",
	"C_TaskQuest.GetQuestsOnMap", "C_TaskQuest.GetQuestsForPlayerByMapID",
	"C_AddOns.LoadAddOn", "C_AddOns.GetAddOnMetadata", "C_AddOns.IsAddOnLoaded", "C_AddOns.GetNumAddOns",
	"C_AddOns.GetAddOnInfo", "C_AddOns.IsAddOnLoadOnDemand",
	"C_Timer.NewTimer", "C_Timer.After", "C_TooltipInfo.GetHyperlink", "C_ChatInfo.SendAddonMessage",
	"GetAddOnMemoryUsage", "UpdateAddOnMemoryUsage", "debugprofilestop", "IsMacClient", "GetBuildInfo",
	"UnitPosition", "C_Minimap.GetViewRadius", "C_Texture.GetAtlasInfo",
	"WorldMapFrame", "WorldMapFrame.ScrollContainer", "WorldMapFrame.BorderFrame", "WorldMapFrame.SetMapID",
	"WorldMapFrame.GetMapID", "WorldMapFrame.AddDataProvider", "WorldMapFrame.pinPools",
	"WorldMapFrame.BorderFrame.MaximizeMinimizeFrame", "WorldMapFrame.SidePanelToggle",
	"Enum.UIMapType", "TomTom",
}

local function count(t)
	return type(t) == "table" and #t or tostring(t)
end

local function sample(list, field, n)
	local out = {}
	if type(list) == "table" then
		for i = 1, math.min(n or 5, #list) do
			local v = list[i]
			out[#out + 1] = type(v) == "table" and tostring(v[field]) or tostring(v)
		end
	end
	return table.concat(out, " | ")
end

local function try(report, key, fn)
	local ok, result = pcall(fn)
	report[key] = ok and result or ("ERROR: " .. tostring(result))
end

local function audit()
	local report = { apis = {}, maps = {}, templates = {} }
	local build, buildNum, date, toc = GetBuildInfo()
	report.build = string.format("%s (%s) %s toc=%s project=%s locale=%s", tostring(build), tostring(buildNum),
		tostring(date), tostring(toc), tostring(WOW_PROJECT_ID), GetLocale())

	local missing = 0
	for _, path in ipairs(APIS) do
		local value = resolve(path)
		report.apis[path] = value == nil and "MISSING" or type(value)
		if value == nil then
			missing = missing + 1
		end
	end

	-- Templates: only asked about, never created (creating them with the wrong frame type shows Lua errors)
	for _, template in ipairs({ "SearchBoxTemplate", "InputBoxTemplate", "UIPanelButtonTemplate", "UIPanelCloseButton",
		"UICheckButtonTemplate", "ScrollFrameTemplate", "UIPanelScrollFrameTemplate", "WowScrollBoxList",
		"MinimalScrollBar", "SettingsCheckboxControlTemplate", "TooltipBackdropTemplate", "BackdropTemplate" }) do
		if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
			local ok, info = pcall(C_XMLUtil.GetTemplateInfo, template)
			report.templates[template] = (ok and info) and ("ok " .. tostring(info.type)) or "MISSING"
		else
			report.templates[template] = "C_XMLUtil missing"
		end
	end

	local zone = C_Map.GetBestMapForUnit("player")
	local maps = { zone }
	local info = zone and C_Map.GetMapInfo(zone)
	while info and info.parentMapID and info.parentMapID > 0 do
		maps[#maps + 1] = info.parentMapID
		info = C_Map.GetMapInfo(info.parentMapID)
	end

	for _, mapID in ipairs(maps) do
		local m = {}
		report.maps[#report.maps + 1] = m
		local mi = C_Map.GetMapInfo(mapID)
		m.map = string.format("%d %s type=%s parent=%s", mapID, mi and mi.name or "?", mi and tostring(mi.mapType) or "?",
			mi and tostring(mi.parentMapID) or "?")
		try(m, "children", function()
			local c = C_Map.GetMapChildrenInfo(mapID)
			return count(c) .. " : " .. sample(c, "name", 8)
		end)
		try(m, "canUserWaypoint", function() return tostring(C_Map.CanSetUserWaypointOnMap(mapID)) end)
		try(m, "taxiNodes", function()
			local t = C_TaxiMap.GetTaxiNodesForMap(mapID)
			local s = sample(t, "name", 5)
			if type(t) == "table" and t[1] then
				s = s .. " || state=" .. tostring(t[1].state) .. " pos=" .. tostring(t[1].position and t[1].position.x)
			end
			return count(t) .. " : " .. s
		end)
		try(m, "dungeonEntrances", function()
			local t = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
			return count(t) .. " : " .. sample(t, "name", 5)
		end)
		try(m, "areaPOIs", function()
			local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID)
			local names = {}
			if type(ids) == "table" then
				for i = 1, math.min(8, #ids) do
					local p = C_AreaPoiInfo.GetAreaPOIInfo(mapID, ids[i])
					names[#names + 1] = p and (tostring(p.name) .. "/" .. tostring(p.atlasName)) or "?"
				end
			end
			return count(ids) .. " : " .. table.concat(names, " | ")
		end)
		try(m, "questsOnMap", function()
			local q = C_QuestLog.GetQuestsOnMap(mapID)
			return count(q) .. " : " .. sample(q, "questID", 5)
		end)
		try(m, "taskQuests", function()
			return count(C_TaskQuest.GetQuestsOnMap(mapID))
		end)
	end

	try(report, "vignettes", function()
		local ids = C_VignetteInfo.GetVignettes()
		local names = {}
		if type(ids) == "table" then
			for i = 1, math.min(8, #ids) do
				local v = C_VignetteInfo.GetVignetteInfo(ids[i])
				names[#names + 1] = v and (tostring(v.name) .. "/" .. tostring(v.atlasName)) or "?"
			end
		end
		return count(ids) .. " : " .. table.concat(names, " | ")
	end)
	try(report, "questLog", function()
		return tostring(C_QuestLog.GetNumQuestLogEntries())
	end)
	try(report, "allTaxiNodes", function()
		return count(C_TaxiMap.GetAllTaxiNodes(maps[#maps]))
	end)
	try(report, "userWaypointHyperlink", function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zone, 0.5, 0.5))
		local link = C_Map.GetUserWaypointHyperlink()
		C_Map.ClearUserWaypoint()
		return tostring(link):gsub("|", "||")
	end)
	try(report, "loadOnDemandTest", function()
		return tostring(C_AddOns.GetAddOnMetadata("MapScout", "Title"))
	end)

	MapScoutDB = MapScoutDB or {}
	MapScoutDB.audit = report
	ns.Print(string.format("audit done: %d APIs missing. Now type /reload so it is saved.", missing))
end

ns.RegisterCommand("audit", audit, "TEMPORARY: check the game APIs (#20)")

-- Second pass: every zone of every continent, asked by mapID (no need to travel)
local function audit2()
	local zones, totals = {}, { zones = 0, entrances = 0, pois = 0, events = 0, links = 0 }
	local function inside(p)
		return p and p.x and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1
	end
	for _, continent in ipairs(C_Map.GetMapChildrenInfo(947) or {}) do
		for _, zone in ipairs(C_Map.GetMapChildrenInfo(continent.mapID, nil, true) or {}) do
			local z = { map = string.format("%d %s type=%s (%s)", zone.mapID, zone.name, tostring(zone.mapType), continent.name) }
			totals.zones = totals.zones + 1
			local ok, ents = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, zone.mapID)
			if ok and type(ents) == "table" and #ents > 0 then
				local names = {}
				for _, e in ipairs(ents) do
					names[#names + 1] = tostring(e.name) .. string.format("@%.2f,%.2f", e.position and e.position.x or -1,
						e.position and e.position.y or -1) .. "/" .. tostring(e.atlasName)
				end
				z.entrances = table.concat(names, " | ")
				totals.entrances = totals.entrances + #ents
			end
			local ok2, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, zone.mapID)
			if ok2 and type(ids) == "table" and #ids > 0 then
				local names = {}
				for _, id in ipairs(ids) do
					local p = C_AreaPoiInfo.GetAreaPOIInfo(zone.mapID, id)
					names[#names + 1] = p and (tostring(p.name) .. "/" .. tostring(p.atlasName)) or tostring(id)
				end
				z.pois = table.concat(names, " | ")
				totals.pois = totals.pois + #ids
			end
			local ok3, evs = pcall(C_AreaPoiInfo.GetEventsForMap, zone.mapID)
			if ok3 and type(evs) == "table" and #evs > 0 then
				z.events = #evs
				totals.events = totals.events + #evs
			end
			local ok4, links = pcall(C_Map.GetMapLinksForMap, zone.mapID)
			if ok4 and type(links) == "table" and #links > 0 then
				local names = {}
				for _, l in ipairs(links) do
					names[#names + 1] = tostring(l.name) .. "->" .. tostring(l.linkedUiMapID)
				end
				z.links = table.concat(names, " | ")
				totals.links = totals.links + #links
			end
			local ok5, taxi = pcall(C_TaxiMap.GetTaxiNodesForMap, zone.mapID)
			if ok5 and type(taxi) == "table" then
				local n = 0
				for _, t in ipairs(taxi) do
					if inside(t.position) then
						n = n + 1
					end
				end
				z.taxiInside = n .. "/" .. #taxi
			end
			zones[#zones + 1] = z
		end
	end
	MapScoutDB = MapScoutDB or {}
	MapScoutDB.audit2 = { zones = zones, totals = totals }
	ns.Print(string.format("audit2 done: %d maps, %d entrances, %d POIs, %d events, %d links. Now /reload.",
		totals.zones, totals.entrances, totals.pois, totals.events, totals.links))
end

ns.RegisterCommand("audit2", audit2, "TEMPORARY: check every zone (#20)")
