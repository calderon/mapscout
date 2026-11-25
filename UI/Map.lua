-- MapScout: the layer where everything MapScout shows in the world map lives.
-- Rules (no taint, see ARCHITECTURE.md "Integration with the world map"):
--   * Only MapScout's own frames, children of WorldMapFrame and anchored to it;
--     never added to Blizzard tables (UISpecialFrames, data providers, pins).
--   * Blizzard frames are only followed with HookScript on scripts they already
--     have (OnShow, OnHide) and hooksecurefunc on their methods (OnMapChanged);
--     never SetScript, never a field written on them.
--   * Nothing protected is called, so it works the same in combat.
-- Other modules (search bar, results, preview) put their frames in
-- ns.Map.layer and follow the map with ns.Map.Listen.

local _, ns = ...
local L = ns.L

local Map = {}
ns.Map = Map

-- fn(what, ...): "attached" (the layer exists), "shown", "hidden",
-- "mapChanged" (mapID), "resized"
local listeners = {}

-- Modules follow the map with this (register at load time: "attached" comes
-- at login, followed by "shown" if the map is already open).
function Map.Listen(fn)
	listeners[#listeners + 1] = fn
end

local function notify(what, ...)
	for _, fn in ipairs(listeners) do
		ns.API.SafeCall(fn, what, ...)
	end
end

function Map.IsShown()
	return WorldMapFrame ~= nil and WorldMapFrame:IsShown() == true
end

function Map.GetMapID()
	return WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
end

-- Builds the layer once the world map exists. Returns true if it is ready.
function Map.Attach()
	if Map.layer then
		return true
	end
	if not WorldMapFrame then
		return false
	end
	local canvas = WorldMapFrame.ScrollContainer or WorldMapFrame

	-- Covers the map area, above the map and its pins, under the map's own
	-- buttons. It doesn't take the mouse: only its children (the bar) do.
	local layer = CreateFrame("Frame", "MapScoutMapLayer", WorldMapFrame)
	layer:SetAllPoints(canvas)
	layer:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	layer:SetFrameLevel(canvas:GetFrameLevel() + 100)
	layer:EnableMouse(false)
	layer:SetScript("OnSizeChanged", function() -- MapScout's own frame
		notify("resized")
	end)
	Map.layer = layer

	WorldMapFrame:HookScript("OnShow", function()
		notify("shown")
		notify("mapChanged", Map.GetMapID())
	end)
	WorldMapFrame:HookScript("OnHide", function()
		notify("hidden")
	end)
	if type(WorldMapFrame.OnMapChanged) == "function" then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			notify("mapChanged", Map.GetMapID())
		end)
	end

	notify("attached")
	if Map.IsShown() then
		notify("shown")
		notify("mapChanged", Map.GetMapID())
	end
	return true
end

-- The world map is part of the game's interface at login; if a client loads
-- it later, attach when its addon loads.
ns.RegisterEvent("PLAYER_LOGIN", "Map", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "Map")
	if not Map.Attach() then
		ns.RegisterEvent("ADDON_LOADED", "Map", function(_, name)
			if name == "Blizzard_WorldMap" and Map.Attach() then
				ns.UnregisterEvent("ADDON_LOADED", "Map")
			end
		end)
	end
end)

-- /ms debug map [outline] ---------------------------------------------------------

local outline

ns.RegisterDebug("map", function(args)
	if not Map.layer then
		ns.Print(L.DEBUG_MAP_NOT_READY)
		return
	end
	if args == "outline" then
		if not outline then
			outline = Map.layer:CreateTexture(nil, "BACKGROUND")
			outline:SetAllPoints()
			outline:SetColorTexture(0.2, 0.6, 1, 0.15)
		else
			outline:SetShown(not outline:IsShown())
		end
	end
	local mapID = Map.GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	local width, height = Map.layer:GetSize()
	ns.Print(L.DEBUG_MAP_RESULT:format(tostring(mapID), info and info.name or "?", Map.IsShown() and L.YES or L.NO,
		width or 0, height or 0, InCombatLockdown() and L.YES or L.NO))
end, L.DEBUG_MAP)
