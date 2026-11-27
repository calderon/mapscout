-- MapScout: previewing a place on the map (hovering a result).
-- A pulsing marker on the point, if it falls inside the open map (also from a
-- sub-map: a Forjaz mailbox shows on the Eastern Kingdoms map), and nothing
-- else: the map never changes on hover, only on click.
-- An NPC who walks a route has no exact point: its route is drawn instead
-- (the part on the open map), or, when the route isn't known, a big soft
-- circle without the pin.
-- The marker is MapScout's own frame hung on the map's canvas (as Bridge's
-- pins), so it follows zoom and panning, and keeps its size on screen.
-- ns.Preview.Show(place) / ns.Preview.Hide() are the only way in: the results
-- list uses them, and so will the API that lets other addons highlight places.

local _, ns = ...
local L = ns.L

local Preview = {}
ns.Preview = Preview

Preview.SIZE = 24 -- marker size on screen
Preview.GLOW_SIZE = 64
Preview.PIN_ATLAS = "Waypoint-MapPin-Untracked"
Preview.PIN_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"
Preview.GLOW_TEXTURE = "Interface\\Cooldown\\ping4"
Preview.ROAM_SIZE = 140 -- the soft circle of an NPC that roams with no known route
Preview.ROUTE_THICKNESS = 3 -- route lines, on screen

local marker, routeFrame

-- Where a point of some map is on the open map (kept here for existing callers)
Preview.PositionOnMap = function(...)
	return ns.PositionOnMap(...)
end

local function canvas()
	return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
end

local function createMarker(parent)
	local frame = CreateFrame("Frame", "MapScoutPreviewMarker", parent)
	frame:SetSize(Preview.SIZE, Preview.SIZE)
	frame:EnableMouse(false) -- the map under it keeps working

	local glow = frame:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(Preview.GLOW_TEXTURE)
	glow:SetBlendMode("ADD")
	glow:SetSize(Preview.GLOW_SIZE, Preview.GLOW_SIZE)
	glow:SetPoint("CENTER")
	glow:SetVertexColor(1, 0.82, 0)

	-- The game's waypoint diamond, centred on the point like the halo
	local pin = frame:CreateTexture(nil, "ARTWORK")
	pin:SetSize(Preview.SIZE, Preview.SIZE)
	pin:SetPoint("CENTER")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(Preview.PIN_ATLAS) then
		pin:SetAtlas(Preview.PIN_ATLAS)
	else
		pin:SetTexture(Preview.PIN_TEXTURE)
	end

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.25)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.6)
	local scale = pulse:CreateAnimation("Scale")
	scale:SetScaleFrom(0.7, 0.7)
	scale:SetScaleTo(1.1, 1.1)
	scale:SetDuration(0.6)

	frame.Glow, frame.Pin, frame.Pulse = glow, pin, pulse
	frame:Hide()
	return frame
end

-- Lines of a route on the open map: { x1, y1, x2, y2 } per segment whose two
-- ends are on it (0-1 of the open map). A path that leaves the map is cut.
function Preview.RouteSegments(route, openMapID)
	local segments = {}
	for _, path in ipairs(route or {}) do
		local points = path.points or {}
		local lastX, lastY
		for i = 1, #points - 1, 2 do
			local x, y = ns.PositionOnMap(path.mapID, points[i], points[i + 1], openMapID)
			if x and lastX then
				segments[#segments + 1] = { lastX, lastY, x, y }
			end
			lastX, lastY = x, y
		end
	end
	return segments
end

-- The route's own frame on the canvas: its lines are drawn in a frame scaled
-- like the marker, so they keep their thickness on screen
local function createRouteFrame(parent)
	local frame = CreateFrame("Frame", "MapScoutPreviewRoute", parent)
	frame:EnableMouse(false)
	frame.lines = {}
	local pulse = frame:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.55)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.8)
	frame.Pulse = pulse
	frame:Hide()
	return frame
end

-- Line i of the route frame (a dark border under a golden line), made once
local function routeLine(i)
	local line = routeFrame.lines[i]
	if not line then
		local border = routeFrame:CreateLine(nil, "BORDER")
		border:SetColorTexture(0, 0, 0, 0.6)
		border:SetThickness(Preview.ROUTE_THICKNESS + 2)
		local gold = routeFrame:CreateLine(nil, "ARTWORK")
		gold:SetColorTexture(1, 0.82, 0, 1)
		gold:SetThickness(Preview.ROUTE_THICKNESS)
		line = { border, gold }
		routeFrame.lines[i] = line
	end
	return line
end

local function canvasScaleOf()
	local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	return scale
end

-- Draws a route on the canvas. Returns true if some of it is on the open map.
local function showRoute(target, route, openMapID)
	local segments = Preview.RouteSegments(route, openMapID)
	if #segments == 0 then
		return false
	end
	if not routeFrame then
		routeFrame = createRouteFrame(target)
	end
	routeFrame:SetParent(target)
	local scale = canvasScaleOf()
	local width, height = target:GetWidth() * scale, target:GetHeight() * scale
	routeFrame:SetScale(1 / scale) -- same thickness on screen at any zoom
	routeFrame:ClearAllPoints()
	routeFrame:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
	routeFrame:SetSize(width, height)
	routeFrame:SetFrameLevel(math.min(math.max(target:GetFrameLevel() + 1500, 9000), 9990))
	for i, segment in ipairs(segments) do
		for _, line in ipairs(routeLine(i)) do
			line:SetStartPoint("TOPLEFT", routeFrame, segment[1] * width, -segment[2] * height)
			line:SetEndPoint("TOPLEFT", routeFrame, segment[3] * width, -segment[4] * height)
			line:Show()
		end
	end
	for i = #segments + 1, #routeFrame.lines do
		for _, line in ipairs(routeFrame.lines[i]) do
			line:Hide()
		end
	end
	routeFrame:Show()
	routeFrame.Pulse:Play()
	return true
end

-- Shows a place { mapID, x, y } if it is on the open map: its route when it
-- has one, a big soft circle when it roams with no known route, else the
-- marker on the point. Returns true when something is shown.
function Preview.Show(place)
	Preview.Hide()
	local target = canvas()
	local openMapID = ns.Map.GetMapID()
	if target and place.route and showRoute(target, place.route, openMapID) then
		Preview.shown = { mapID = place.mapID, x = place.x, y = place.y, route = true }
		return true
	end
	local x, y = Preview.PositionOnMap(place.mapID, place.x, place.y, openMapID)
	if not (target and x) then
		return false
	end
	if not marker then
		marker = createMarker(target)
	end
	marker:SetParent(target)
	local canvasScale = canvasScaleOf()
	marker:SetScale(1 / canvasScale) -- same size on screen at any zoom
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", target, "TOPLEFT", x * target:GetWidth() * canvasScale,
		-y * target:GetHeight() * canvasScale)
	marker:SetFrameLevel(math.min(math.max(target:GetFrameLevel() + 1500, 9000), 9990)) -- over the map's pins
	-- Roaming with no known route: somewhere around here, not on this spot
	local roams = (place.roams or place.route) and true or false
	local glowSize = roams and Preview.ROAM_SIZE or Preview.GLOW_SIZE
	marker.Glow:SetSize(glowSize, glowSize)
	marker.Pin:SetShown(not roams)
	marker:Show()
	marker.Pulse:Play()
	Preview.shown = { mapID = place.mapID, x = place.x, y = place.y, onMap = { x, y }, roams = roams or nil }
	return true
end

function Preview.Hide()
	if marker then
		marker.Pulse:Stop()
		marker:Hide()
	end
	if routeFrame then
		routeFrame.Pulse:Stop()
		routeFrame:Hide()
	end
	Preview.shown = nil
end

-- The tooltip of a result: name, subtitle, place and coordinates, distance.
function Preview.FillTooltip(tooltip, result, subtitle, distance)
	local entry = result.item.entry
	tooltip:SetText(entry.name, 1, 1, 1)
	if subtitle and subtitle ~= "" then
		tooltip:AddLine(subtitle, 0.8, 0.8, 0.8)
	end
	local place = ns.MapPlace(entry.mapID)
	if place then
		local where = place.continentName and (place.zoneName .. " › " .. place.continentName) or place.zoneName
		if place.name ~= place.zoneName then
			where = place.name .. ", " .. where
		end
		tooltip:AddLine(where, 1, 0.82, 0)
	end
	if entry.x and entry.y then
		tooltip:AddLine(L.PREVIEW_COORDS:format(entry.x * 100, entry.y * 100), 0.7, 0.7, 0.7)
	end
	if distance then
		tooltip:AddLine(L.PREVIEW_DISTANCE:format(distance), 0.7, 0.7, 0.7)
	end
	-- Extra lines from the provider (#137 adds more sources)
	for _, line in ipairs(type(entry.details) == "table" and entry.details or {}) do
		tooltip:AddLine(line, 0.6, 0.8, 1, true)
	end
end

ns.Map.Listen(function(what)
	if what == "hidden" or what == "mapChanged" then
		Preview.Hide()
	end
end)
