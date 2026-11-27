-- MapScout options: help improve MapScout's data. One checkbox that turns the
-- contribution mode (Core/Contribute.lua) on or off, with a line on what it
-- does, in a box of its own so it stands out. It follows /ms contribute on|off
-- too.

local _, ns = ...
local L = ns.L

local PADDING = 14
local SPACING = 3 -- between the lines of the explanation

local check

local function refresh()
	if check then
		check:SetChecked(ns.Contribute.IsOn())
	end
end

local function build(parent, anchor)
	local box = CreateFrame("Frame", "MapScoutOptionsContributeBox", parent)
	box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -PADDING, -16)
	box:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	local background = box:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 0.82, 0, 0.16) -- a faint gold, as the game's titles
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)
	edge:SetColorTexture(1, 0.82, 0, 0.8)

	check = CreateFrame("CheckButton", "MapScoutOptionsContribute", box, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", box, "TOPLEFT", PADDING - 2, -PADDING + 2)
	local label = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	label:SetText(L.OPTIONS_CONTRIBUTE)
	check:SetScript("OnClick", function(self)
		ns.Contribute.SetOn(self:GetChecked())
	end)

	local help = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 2, -4)
	-- its width from the page, which has a size from the start (the box gets its
	-- own only after the first layout, and the text was cut to one line)
	help:SetPoint("RIGHT", parent, "RIGHT", -16 - PADDING, 0)
	help:SetJustifyH("LEFT")
	help:SetWordWrap(true)
	help:SetSpacing(SPACING)
	help:SetText(L.OPTIONS_CONTRIBUTE_HELP)

	-- The box grows with the explanation (its lines depend on the page's width)
	local function fit()
		box:SetHeight(PADDING + 24 + 4 + help:GetStringHeight() + PADDING)
	end
	box:SetScript("OnSizeChanged", fit)
	box:SetScript("OnShow", fit)
	fit()
	C_Timer.After(0, fit) -- once the page is laid out, the text's real lines are known
	refresh()
	-- The next section lines up with the page's text, not with the box's edge
	local below = CreateFrame("Frame", nil, parent)
	below:SetSize(1, 1)
	below:SetPoint("TOPLEFT", box, "BOTTOMLEFT", PADDING, 0)
	return below
end

ns.Options.AddSection(build)
ns.Contribute.Listen(refresh)
