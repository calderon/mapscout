-- MapScout: the list of results under the search bar.
--   In <open map>          results in the open map (or inside it), with distance
--   Elsewhere
--     Continent › Zone     the rest, grouped, groups in the order of their best result
-- Each row: icon, name, subtitle (category · place) and, in this zone, distance.
-- With text but no results, a short hint. The list has a limited height and
-- scrolls; rows are reused (#35 will only lay out the visible ones).
-- Hovering a row previews the place on the map (UI/Preview.lua); clicking
-- it goes there (UI/Waypoint.lua).

local _, ns = ...
local L = ns.L

local Results = {}
ns.Results = Results

Results.ROW_HEIGHT = 20
Results.HEADER_HEIGHT = 18
Results.MAX_VISIBLE_ROWS = 12
Results.WIDTH_EXTRA = 28 -- the gear and some air to the right of the box
Results.MIN_WIDTH = 300 -- never narrower, even when the box is
Results.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local rows = {} -- reused row frames
Results.lines = {} -- what is shown: { kind = "zone"|"elsewhere"|"group"|"result"|"empty"|"hint", ... }

-- Building the lines ------------------------------------------------------------

local function categoryName(item)
	local record = ns.Registry.Get(item.provider)
	if record and item.category then
		for _, category in ipairs(record.spec.categories or {}) do
			if category.id == item.category then
				return category.name
			end
		end
	end
	return record and record.spec.name
end

local function subtitle(result)
	local entry, parts = result.item.entry, {}
	parts[#parts + 1] = entry.subtitle or categoryName(result.item)
	local place = ns.MapPlace(entry.mapID)
	if place and result.inZone and place.mapID ~= ns.Map.GetMapID() then
		parts[#parts + 1] = place.name -- a city or place inside the open map
	end
	return table.concat(parts, " · ")
end

local function categoryLabel(providerID, categoryID)
	local record = ns.Registry.Get(providerID)
	if record then
		for _, category in ipairs(record.spec.categories or {}) do
			if category.id == categoryID then
				return category.name
			end
		end
		return record.spec.name
	end
	return categoryID
end

-- "Nothing in Zones; showing all of Places"
local function widenedNote(widened)
	local narrowed, wide, seen = {}, {}, {}
	for _, filter in ipairs(widened) do
		narrowed[#narrowed + 1] = categoryLabel(filter.provider, filter.category)
		if not seen[filter.provider] then
			seen[filter.provider] = true
			local record = ns.Registry.Get(filter.provider)
			wide[#wide + 1] = record and record.spec.name or filter.provider
		end
	end
	return L.RESULTS_WIDENED:format(table.concat(narrowed, ", "), table.concat(wide, ", "))
end

-- Turns the engine's results into the lines of the list.
function Results.Build(results, query, stats)
	local lines = {}
	if #results == 0 then
		if query and (query.text ~= "" or #query.filters > 0) then
			lines[1] = { kind = "empty", text = L.RESULTS_NONE }
			lines[2] = { kind = "hint", text = L.RESULTS_HINT }
		end
		return lines
	end

	if stats and stats.widened then
		lines[#lines + 1] = { kind = "hint", text = widenedNote(stats.widened) }
	end

	local openPlace = ns.MapPlace(ns.Map.GetMapID())
	local zone, groups, order = {}, {}, {}
	for _, result in ipairs(results) do
		if result.inZone then
			zone[#zone + 1] = result
		else
			local place = ns.MapPlace(result.item.entry.mapID)
			local key
			if not place then
				key = L.RESULTS_NO_PLACE
			elseif result.item.entry.isMap then
				-- a whole map: under the map above it (continents under the world)
				local parent = ns.MapPlace(place.parent)
				key = parent and parent.name or place.name
			else
				key = (place.continentName or "?") .. " › " .. place.zoneName
			end
			if not groups[key] then
				groups[key] = {}
				order[#order + 1] = key
			end
			table.insert(groups[key], result)
		end
	end

	local function addResult(result)
		local entry = result.item.entry
		local line = { kind = "result", result = result, text = entry.name, subtitle = subtitle(result) }
		if result.inZone and not entry.isMap then
			local yards = ns.DistanceToPlayer(entry.mapID, entry.x, entry.y)
			line.distance = yards and ns.FormatDistance(yards)
		end
		lines[#lines + 1] = line
	end

	if #zone > 0 then
		lines[#lines + 1] = { kind = "zone", text = L.RESULTS_IN_ZONE:format(openPlace and openPlace.name or "?") }
		for _, result in ipairs(zone) do
			addResult(result)
		end
	end
	if #order > 0 then
		lines[#lines + 1] = { kind = "elsewhere", text = L.RESULTS_ELSEWHERE }
		for _, key in ipairs(order) do
			lines[#lines + 1] = { kind = "group", text = key }
			for _, result in ipairs(groups[key]) do
				addResult(result)
			end
		end
	end
	return lines
end

-- Frames -----------------------------------------------------------------------

local HEADER_COLOR = { 1, 0.82, 0 } -- the game's gold
local GROUP_COLOR = { 0.6, 0.6, 0.6 }

local function iconOf(item)
	local record = ns.Registry.Get(item.provider)
	return item.entry.icon or (record and record.spec.icon) or Results.DEFAULT_ICON
end

local function setIcon(texture, icon)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon) then
		texture:SetAtlas(icon)
	else
		texture:SetTexture(icon)
	end
end

local function createRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(Results.ROW_HEIGHT)
	row.index = index
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 4, 0)
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Sub:SetPoint("LEFT", row.Name, "RIGHT", 6, 0)
	row.Sub:SetJustifyH("LEFT")
	row.Sub:SetWordWrap(false)
	row.Distance = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.Distance:SetPoint("RIGHT", -4, 0)
	row.Sub:SetPoint("RIGHT", row.Distance, "LEFT", -4, 0)
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetAllPoints()
	row.Highlight:SetColorTexture(1, 1, 1, 0.08)
	-- Hover: preview on the map and tooltip (MapScout's own rows)
	row:SetScript("OnEnter", function(self)
		local line = self.line
		if not (line and line.kind == "result") then
			return
		end
		ns.Preview.Show(line.result.item.entry)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.Preview.FillTooltip(GameTooltip, line.result, line.subtitle, line.distance)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		ns.Preview.Hide()
		GameTooltip:Hide()
	end)
	-- Click: go there (the right button is for the menu, #61)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self)
		local line = self.line
		if line and line.kind == "result" then
			ns.Waypoint.Go(line.result, ns.SearchBar.box:GetText())
		end
	end)
	return row
end

local function fillRow(row, line)
	row.line = line
	local isResult = line.kind == "result"
	row:SetHeight(isResult and Results.ROW_HEIGHT or Results.HEADER_HEIGHT)
	row:EnableMouse(isResult)
	row.Icon:SetShown(isResult)
	row.Sub:SetShown(isResult)
	row.Distance:SetShown(isResult and line.distance ~= nil)
	row.Name:ClearAllPoints()
	if isResult then
		setIcon(row.Icon, iconOf(line.result.item))
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
		if line.result.item.entry.dimmed then -- e.g. a flight master not known yet
			row.Name:SetTextColor(0.6, 0.6, 0.6)
		else
			row.Name:SetTextColor(1, 1, 1)
		end
		row.Sub:SetText(line.subtitle or "")
		row.Distance:SetText(line.distance or "")
	else
		row.Name:SetPoint("LEFT", line.kind == "group" and 12 or 4, 0)
		local color = line.kind == "group" and GROUP_COLOR or HEADER_COLOR
		row.Name:SetTextColor(color[1], color[2], color[3])
	end
	row.Name:SetText(line.text)
	row:Show()
end

function Results.Create()
	if Results.frame then
		return
	end
	local frame = CreateFrame("Frame", "MapScoutResults", ns.Map.layer, "BackdropTemplate")
	ns.SearchBar.Raise(frame, 5)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
		frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	end
	frame:EnableMouse(true) -- clicks on the list don't go through to the map
	frame:Hide()

	local scroll = CreateFrame("ScrollFrame", "MapScoutResultsScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	-- The template shows its scroll bar on its own when the range changes:
	-- put back what the list decided (shown only when it doesn't fit).
	scroll:HookScript("OnScrollRangeChanged", function()
		Results.UpdateScrollBar()
	end)

	Results.frame, Results.scroll, Results.content = frame, scroll, content
end

local SCROLL_BAR_SPACE = 22 -- room the scroll bar takes on the right

-- The template's scroll bar, if this client's template has one
local function scrollBar()
	local bar = Results.scroll and Results.scroll.ScrollBar
	return type(bar) == "table" and bar or nil
end

-- Shows the scroll bar only when the list doesn't fit, and gives its room
-- back to the rows when it is hidden.
function Results.UpdateScrollBar()
	local bar = scrollBar()
	if bar then
		bar:SetShown(Results.overflows == true)
	end
end

-- Shows these lines (or hides the list when there are none).
function Results.Show(lines)
	Results.lines = lines
	local frame = Results.frame
	if not frame then
		return
	end
	if #lines == 0 then
		frame:Hide()
		return
	end
	local box = ns.SearchBar.box
	local width = math.max(box:GetWidth() + Results.WIDTH_EXTRA, Results.MIN_WIDTH)
	-- In the title strip the bar is at the map's right edge: the list lines up
	-- with the right edge of the box and grows to the left, so it stays over
	-- the map. Inside, it hangs from the box.
	frame:ClearAllPoints()
	if ns.SearchBar.placement == "title" then
		frame:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
	else
		frame:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	end
	local height = 0
	for _, line in ipairs(lines) do
		height = height + (line.kind == "result" and Results.ROW_HEIGHT or Results.HEADER_HEIGHT)
	end
	local maxHeight = Results.MAX_VISIBLE_ROWS * Results.ROW_HEIGHT
	Results.overflows = height > maxHeight
	local inner = width - 8 - (Results.overflows and SCROLL_BAR_SPACE or 0)

	local scroll, content = Results.scroll, Results.content
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4 - (Results.overflows and SCROLL_BAR_SPACE or 0), 4)

	local y = 0
	for i, line in ipairs(lines) do
		local row = rows[i] or createRow(content, i)
		rows[i] = row
		fillRow(row, line)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetWidth(inner)
		y = y + (line.kind == "result" and Results.ROW_HEIGHT or Results.HEADER_HEIGHT)
	end
	for i = #lines + 1, #rows do
		rows[i]:Hide()
		rows[i].line = nil
	end
	content:SetSize(inner, y)
	frame:SetSize(width, math.min(y, maxHeight) + 8)
	scroll:SetVerticalScroll(0)
	Results.UpdateScrollBar()
	frame:Show()
end

function Results.Hide()
	if Results.frame then
		Results.frame:Hide()
	end
	ns.Preview.Hide()
end

-- The first result shown (what Enter goes to), or nil
function Results.FirstResult()
	for _, line in ipairs(Results.lines) do
		if line.kind == "result" then
			return line.result
		end
	end
end

-- Rows created so far (reused between searches)
function Results.RowCount()
	return #rows
end

-- Wiring ------------------------------------------------------------------------

ns.Map.Listen(function(what)
	if what == "attached" then
		Results.Create() -- the bar, registered first, already exists
	elseif what == "hidden" then
		Results.Hide()
	end
end)

ns.SearchBar.Listen(function(results, query, stats)
	Results.Show(Results.Build(results, query, stats))
end)
