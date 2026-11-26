-- MapScout: the quests in the player's log (built-in provider, through MapScoutAPI).
-- Searchable by title (@quest, @mision), with their level and, as subtitle,
-- the first objective still to do, or "Ready to turn in".
-- Where: the game places each quest on the continent map (its objective area,
-- or its turn-in when it is complete); each one is then placed in the most
-- precise map there (a zone, a city). A quest without a place is still found,
-- but leads nowhere, and its tooltip says so.
-- The log changes a lot while playing: on its events the entries are rebuilt
-- after a short pause (throttle), and only while the map is open; with the map
-- closed they are marked out of date and rebuilt when it opens. A turned-off
-- provider listens to nothing.

local _, ns = ...
local L = ns.L

local Quests = {}
ns.Quests = Quests

Quests.THROTTLE = 0.5 -- seconds: quest log events come in bursts
Quests.ICON_ONGOING = "Interface\\GossipFrame\\IncompleteQuestIcon"
Quests.ICON_READY = "Interface\\GossipFrame\\ActiveQuestIcon"

local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }

-- Where the game places each quest: questID -> { mapID, x, y }
local function places()
	local found = {}
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
		return found
	end
	for _, continentID in ipairs(ns.Continents()) do
		for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(continentID) or {}) do
			local x, y = poi.x, poi.y
			if poi.questID and not found[poi.questID] and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				local mapID, px, py = ns.PlaceOnMap(continentID, x, y)
				found[poi.questID] = { mapID = mapID, x = px, y = py }
			end
		end
	end
	return found
end

local function isComplete(questID, info)
	if C_QuestLog.IsComplete then
		return C_QuestLog.IsComplete(questID) == true
	end
	return info.isComplete == true or info.isComplete == 1
end

-- Objectives as lines ("12/15 Aparición enfurecida"), and the first one to do
local function objectives(questID)
	local lines, pending = {}, nil
	for _, objective in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID) or {}) do
		if objective.text and objective.text ~= "" then
			lines[#lines + 1] = (objective.finished and "|cff808080" or "") .. objective.text
				.. (objective.finished and "|r" or "")
			if not objective.finished and not pending then
				pending = objective.text
			end
		end
	end
	return lines, pending
end

function Quests.Entries()
	local entries = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return entries
	end
	local where = places()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID and info.title then
			local questID = info.questID
			local ready = isComplete(questID, info)
			local lines, pending = objectives(questID)
			local place = where[questID]
			local status = ready and L.QUESTS_READY or pending or L.QUESTS_ONGOING
			local entry = {
				id = questID,
				name = info.title,
				subtitle = info.level and info.level > 0 and L.QUESTS_SUBTITLE:format(info.level, status) or status,
				keywords = ns.Words("QUEST"),
				details = lines,
				icon = ready and Quests.ICON_READY or Quests.ICON_ONGOING,
				weight = ready and 0.7 or 0.5,
				questID = questID,
			}
			if place then
				entry.mapID, entry.x, entry.y = place.mapID, place.x, place.y
			else
				table.insert(lines, L.QUESTS_NO_PLACE)
			end
			entries[#entries + 1] = entry
		end
	end
	return entries
end

local provider
local outOfDate = false
local timer

function Quests.Rebuild()
	if timer then
		timer:Cancel()
		timer = nil
	end
	outOfDate = false
	if provider and provider:IsEnabled() then
		provider:SetEntries(Quests.Entries())
	end
end

-- A quest log event: rebuild soon if the map is open, else when it opens
local function changed()
	if not ns.Map.IsShown() then
		outOfDate = true
		return
	end
	if not timer then
		timer = C_Timer.NewTimer(Quests.THROTTLE, Quests.Rebuild)
	end
end
Quests.Changed = changed

-- Rebuilds what went out of date while the map was closed. Hooked on the
-- first OnEnable: providers load before the map layer (UI/Map.lua).
local listening = false
local function followMap()
	if listening then
		return
	end
	listening = true
	ns.Map.Listen(function(what)
		if what == "shown" and outOfDate then
			Quests.Rebuild()
		end
	end)
end

provider = MapScoutAPI:RegisterProvider("quests", {
	name = L.QUESTS_NAME,
	description = L.QUESTS_DESCRIPTION,
	icon = Quests.ICON_ONGOING,
	group = "quests",
	groupName = L.GROUP_QUESTS,
	filter = "quest", -- @quest / @mision: all quests (with the available ones)
	filterAliases = (function()
		local words = ns.Words("QUESTS")
		for _, word in ipairs(ns.Words("QUEST_LOG")) do
			words[#words + 1] = word -- @registro / @log: only these
		end
		return words
	end)(),
	OnEnable = function()
		followMap()
		Quests.Rebuild()
		for _, event in ipairs(EVENTS) do
			ns.RegisterEvent(event, "Quests", changed)
		end
	end,
	OnDisable = function()
		for _, event in ipairs(EVENTS) do
			ns.UnregisterEvent(event, "Quests")
		end
		if timer then
			timer:Cancel()
			timer = nil
		end
		outOfDate = false
	end,
})

