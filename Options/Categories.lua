-- MapScout options: what to search. A checkbox per provider (Places, Flight
-- masters...), with its categories under it (Bank, Inn...). Providers of one
-- group (spec.group: "Quests" = in your log + available) hang from one more
-- checkbox that turns them all on or off.
--   * A provider turned off is really off: not loaded, indexed nor listening
--     to events (the registry drops it). Its categories show greyed.
--   * A category turned off is left out of the results.
--   * A provider with some categories off shows its check dimmed (partial);
--     clicking it turned off turns it on with all its categories.
--   * "Restore defaults" forgets every choice.
-- Changes apply at once (the search bar runs its search again by itself,
-- when the registry tells it). Only choices that differ
-- from the defaults are saved. Providers registered later appear by themselves.

local _, ns = ...
local L = ns.L

local Categories = {}
ns.OptionsCategories = Categories

Categories.ROW_HEIGHT = 24
Categories.INDENT = 24

local list, content, rows = nil, nil, {}

-- The state of a provider's checkbox: checked, and whether it is partial
local function providerState(record)
	if not record.enabled then
		return false, false
	end
	for _, category in ipairs(record.spec.categories or {}) do
		if not ns.Registry.IsCategoryEnabled(record.id, category.id) then
			return true, true
		end
	end
	return true, false
end

local function newRow(index)
	local row = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	row:SetSize(Categories.ROW_HEIGHT, Categories.ROW_HEIGHT)
	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Label:SetPoint("LEFT", row, "RIGHT", 4, 0)
	row.index = index
	row:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.Label:GetText(), 1, 1, 1)
			GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		Categories.Toggle(self.line)
	end)
	return row
end

-- The state of a group's checkbox: checked if any provider is on, partial
-- if some provider is off or partial
local function groupState(records)
	local anyOn, allFull = false, true
	for _, record in ipairs(records) do
		local on, partial = providerState(record)
		anyOn = anyOn or on
		if not on or partial then
			allFull = false
		end
	end
	return anyOn, anyOn and not allFull
end

-- What the list shows, in order:
-- { kind = "group"|"provider"|"category", level = 0..2, record, category, records }
function Categories.Lines()
	local lines, groups = {}, {}
	local function addProvider(record, level)
		lines[#lines + 1] = { kind = "provider", record = record, level = level }
		for _, category in ipairs(record.spec.categories or {}) do
			lines[#lines + 1] = { kind = "category", record = record, category = category, level = level + 1 }
		end
	end
	for _, record in ipairs(ns.Registry.List()) do
		local group = record.spec.group
		if group then
			if not groups[group] then
				groups[group] = { kind = "group", group = group, name = record.spec.groupName or group, level = 0, records = {} }
				lines[#lines + 1] = groups[group]
				lines[#lines + 1] = { kind = "groupEnd", group = group } -- where its providers go
			end
			table.insert(groups[group].records, record)
		else
			addProvider(record, 0)
		end
	end
	-- put each group's providers right after the group line
	local ordered = {}
	for _, line in ipairs(lines) do
		if line.kind == "groupEnd" then
			for _, record in ipairs(groups[line.group].records) do
				ordered[#ordered + 1] = { kind = "provider", record = record, level = 1 }
				for _, category in ipairs(record.spec.categories or {}) do
					ordered[#ordered + 1] = { kind = "category", record = record, category = category, level = 2 }
				end
			end
		else
			ordered[#ordered + 1] = line
		end
	end
	return ordered
end

local function turnOn(record)
	for _, category in ipairs(record.spec.categories or {}) do
		ns.Registry.SetCategoryEnabled(record.id, category.id, true)
	end
	ns.Registry.SetEnabled(record.id, true)
end

function Categories.Toggle(line)
	local record = line.record
	if line.kind == "group" then
		local anyOn = groupState(line.records)
		for _, member in ipairs(line.records) do
			if anyOn then
				ns.Registry.SetEnabled(member.id, false)
			else
				turnOn(member) -- with all its categories
			end
		end
	elseif line.kind == "provider" then
		if record.enabled then
			ns.Registry.SetEnabled(record.id, false)
		else
			turnOn(record) -- turned on again: with all its categories
		end
	else
		local on = ns.Registry.IsCategoryEnabled(record.id, line.category.id)
		ns.Registry.SetCategoryEnabled(record.id, line.category.id, not on)
	end
	Categories.Refresh()
end

-- Draws the list again from the registry
function Categories.Refresh()
	if not content then
		return
	end
	local lines = Categories.Lines()
	for i, line in ipairs(lines) do
		local row = rows[i] or newRow(i)
		rows[i] = row
		row.line = line
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", (line.level or 0) * Categories.INDENT, -(i - 1) * Categories.ROW_HEIGHT)
		local record = line.record
		local checked, label -- set by every kind below
		local partial, enabled, tooltip, font = false, true, nil, "GameFontHighlight"
		if line.kind == "group" then
			checked, partial = groupState(line.records)
			label, font = line.name, "GameFontNormal"
		elseif line.kind == "provider" then
			checked, partial = providerState(record)
			label, tooltip = record.spec.name, record.spec.description
			font = (line.level or 0) == 0 and "GameFontNormal" or "GameFontHighlight"
			if record.failed then
				label = label .. " (" .. L.PROVIDER_STATE_FAILED .. ")"
				enabled = false
			end
		else
			checked = ns.Registry.IsCategoryEnabled(record.id, line.category.id)
			label = line.category.name
			enabled = record.enabled -- greyed while its provider is off
		end
		row:SetChecked(checked)
		local texture = row:GetCheckedTexture()
		if texture then
			texture:SetDesaturated(partial)
			texture:SetAlpha(partial and 0.5 or 1)
		end
		row.Label:SetFontObject(font)
		row.Label:SetText(label)
		row.tooltip = tooltip
		if enabled then
			row:Enable()
		else
			row:Disable()
		end
		row:Show()
	end
	for i = #lines + 1, #rows do
		rows[i]:Hide()
		rows[i].line = nil
	end
	content:SetHeight(#lines * Categories.ROW_HEIGHT)
end

function Categories.Reset()
	ns.Registry.ResetChoices()
	Categories.Refresh()
end

-- The section of the options page (built when the page is first shown)
local function build(parent, anchor)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
	title:SetText(L.OPTIONS_CATEGORIES_TITLE)
	local help = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	help:SetJustifyH("LEFT")
	help:SetText(L.OPTIONS_CATEGORIES_HELP)

	local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	reset:SetSize(160, 22)
	reset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -16)
	reset:SetText(L.OPTIONS_RESET)
	reset:SetScript("OnClick", Categories.Reset)

	list = CreateFrame("ScrollFrame", "MapScoutOptionsCategories", parent, "UIPanelScrollFrameTemplate")
	list:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
	list:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -32, 16)
	content = CreateFrame("Frame", nil, list)
	content:SetSize(400, 1)
	list:SetScrollChild(content)
	Categories.list, Categories.content = list, content
	Categories.Refresh()
	return list
end

ns.Options.AddSection(build)

-- Providers registered, removed or turned on/off elsewhere: draw again
ns.Registry.Listen(function(what)
	if what == "registered" or what == "removed" or what == "toggled" then
		Categories.Refresh()
	end
end)
