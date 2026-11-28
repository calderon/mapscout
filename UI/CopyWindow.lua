-- MapScout copy window: a text to copy and the address of a page where to
-- paste it (addons can't reach the internet, nor open a web page). Generic:
-- the contributions export (UI/ContributeWindow.lua) and the problem report
-- use it.
--   ns.CopyWindow.Open({
--     title = "...",        the window's title
--     intro = "...",        what it is and what to do (may have line breaks)
--     text = "...",         the text to copy
--     addressLabel = "...", what the address is
--     address = "https://...",
--     confirm = { label = "...", onClick = fn }, optional: a button that
--                           closes the window after fn (closing does not call it)
--   })
-- Both the text and the address are selected when clicked, ready for Ctrl+C
-- (Cmd+C on Mac); typing in them does not change them. Escape closes it.

local _, ns = ...
local L = ns.L

local CopyWindow = {}
ns.CopyWindow = CopyWindow

local WIDTH, HEIGHT = 560, 480
local PADDING = 16

local frame, current

-- An edit box that can't be changed, and selects everything when clicked
local function readOnly(box, getText)
	box:SetAutoFocus(false)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(getText())
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnMouseUp", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		frame:Hide()
	end)
end

local function build()
	frame = CreateFrame("Frame", "MapScoutCopyWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "MapScoutCopyWindow") -- Escape closes it

	local title = frame.TitleText
	if not title then
		title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
	end
	frame.Title = title

	local intro = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", PADDING, -34)
	intro:SetPoint("RIGHT", -PADDING, 0)
	intro:SetJustifyH("LEFT")
	intro:SetWordWrap(true)
	intro:SetSpacing(3)
	frame.Intro = intro

	-- Bottom up: the buttons, the address, and the text fills what is left
	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(120, 24)
	close:SetPoint("BOTTOMRIGHT", -PADDING, PADDING - 4)
	close:SetText(L.COPY_CLOSE)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local confirm = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	confirm:SetSize(180, 24)
	confirm:SetPoint("RIGHT", close, "LEFT", -8, 0)
	confirm:SetScript("OnClick", function()
		local spec = current
		frame:Hide()
		if spec and spec.confirm and spec.confirm.onClick then
			spec.confirm.onClick()
		end
	end)
	frame.Confirm = confirm

	local address = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	address:SetHeight(22)
	address:SetPoint("BOTTOMLEFT", PADDING + 6, PADDING + 30)
	address:SetPoint("RIGHT", -PADDING, 0)
	address:SetFontObject("ChatFontNormal")
	readOnly(address, function()
		return current and current.address or ""
	end)
	frame.Address = address

	local addressLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	addressLabel:SetPoint("BOTTOMLEFT", address, "TOPLEFT", -6, 4)
	addressLabel:SetPoint("RIGHT", -PADDING, 0)
	addressLabel:SetJustifyH("LEFT")
	frame.AddressLabel = addressLabel

	local back = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	back:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -10)
	back:SetPoint("BOTTOMRIGHT", addressLabel, "TOPRIGHT", 4, 12)
	back:SetColorTexture(0, 0, 0, 0.5)

	local scroll = CreateFrame("ScrollFrame", "MapScoutCopyWindowScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", back, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -26, 6)

	local text = CreateFrame("EditBox", nil, scroll)
	text:SetMultiLine(true)
	text:SetMaxLetters(0)
	text:SetFontObject("ChatFontNormal")
	text:SetWidth(WIDTH - 2 * PADDING - 40)
	readOnly(text, function()
		return current and current.text or ""
	end)
	scroll:SetScrollChild(text)
	-- a click anywhere on the dark area selects the text
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseUp", function()
		text:SetFocus()
		text:HighlightText()
	end)
	frame.Text = text
	frame.Scroll = scroll

	frame:SetScript("OnHide", function()
		text:ClearFocus()
		address:ClearFocus()
		current = nil
	end)
end

function CopyWindow.Open(spec)
	if not frame then
		build()
	end
	current = spec
	frame.Title:SetText(spec.title or "MapScout")
	frame.Intro:SetText(spec.intro or "")
	frame.AddressLabel:SetText(spec.addressLabel or "")
	frame.Address:SetText(spec.address or "")
	frame.Address:SetCursorPosition(0)
	frame.Text:SetText(spec.text or "")
	frame.Text:SetCursorPosition(0)
	frame.Scroll:SetVerticalScroll(0)
	if spec.confirm then
		frame.Confirm:SetText(spec.confirm.label)
		frame.Confirm:Show()
	else
		frame.Confirm:Hide()
	end
	frame:Show()
	frame:Raise()
	frame.Text:SetFocus()
	frame.Text:HighlightText()
end

function CopyWindow.Close()
	if frame then
		frame:Hide()
	end
end

function CopyWindow.IsShown()
	return frame and frame:IsShown() or false
end
