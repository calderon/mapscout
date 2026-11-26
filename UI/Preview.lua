-- MapScout: previewing a place on the map (hovering a result).
-- A pulsing marker on the point, if it falls inside the open map (also from a
-- sub-map: a Forjaz mailbox shows on the Eastern Kingdoms map), and nothing
-- else: the map never changes on hover, only on click.
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

local marker

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

-- Shows the marker on a place { mapID, x, y } if it is on the open map.
-- Returns true when it is shown.
function Preview.Show(place)
	Preview.Hide()
	local target = canvas()
	local openMapID = ns.Map.GetMapID()
	local x, y = Preview.PositionOnMap(place.mapID, place.x, place.y, openMapID)
	if not (target and x) then
		return false
	end
	if not marker then
		marker = createMarker(target)
	end
	marker:SetParent(target)
	local canvasScale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
	if not canvasScale or canvasScale <= 0 then
		canvasScale = 1
	end
	marker:SetScale(1 / canvasScale) -- same size on screen at any zoom
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", target, "TOPLEFT", x * target:GetWidth() * canvasScale,
		-y * target:GetHeight() * canvasScale)
	marker:SetFrameLevel(math.min(math.max(target:GetFrameLevel() + 1500, 9000), 9990)) -- over the map's pins
	marker:Show()
	marker.Pulse:Play()
	Preview.shown = { mapID = place.mapID, x = place.x, y = place.y, onMap = { x, y } }
	return true
end

function Preview.Hide()
	if marker then
		marker.Pulse:Stop()
		marker:Hide()
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
