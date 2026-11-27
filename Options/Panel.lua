-- MapScout: its page in the game's options (Options > AddOns > MapScout).
-- Opened with /ms (or /mapscout) alone and with the gear of the search bar.
-- The page is registered at login but filled the first time it is shown.
-- In combat the game may block opening the options: then it opens as soon
-- as combat ends, with a note in chat.
-- Its sections (search categories, aliases, hidden results...) come with
-- their own issues and add themselves with ns.Options.AddSection.

local ADDON_NAME, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local frame, category
local sections = {} -- fn(parent, previousAnchor) -> lastAnchor, in order
local built = false
local pendingOpen = false

-- Modules add a block of the page: build(parent, anchor) returns the region
-- the next block goes under. Called only when the page is first shown.
function Options.AddSection(build)
	sections[#sections + 1] = build
end

local function build()
	built = true
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ADDON_NAME)
	Options.title = title -- sections may line up with it
	local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, 0)
	version:SetText(L.VERSION:format(ns.VERSION))
	local about = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	about:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	about:SetJustifyH("LEFT")
	about:SetText(L.OPTIONS_ABOUT)
	local anchor = about
	for _, section in ipairs(sections) do
		local ok, nextAnchor = ns.API.SafeCall(section, frame, anchor)
		if ok and nextAnchor then
			anchor = nextAnchor -- the next section goes under this one
		end
	end
end

function Options.Create()
	if frame or not ns.Caps.settings then
		return
	end
	frame = CreateFrame("Frame", "MapScoutOptions")
	frame:Hide()
	frame:SetScript("OnShow", function()
		if not built then
			build()
		end
	end)
	category = Settings.RegisterCanvasLayoutCategory(frame, ADDON_NAME)
	Settings.RegisterAddOnCategory(category)
	Options.frame, Options.category = frame, category
end

local function categoryID()
	return category.GetID and category:GetID() or category.ID
end

-- Opens MapScout's page, or after combat if the game is in combat lockdown.
function Options.Open()
	if not category then
		ns.HandleSlash("help")
		return false
	end
	if InCombatLockdown() then
		if not pendingOpen then
			pendingOpen = true
			ns.Print(L.OPTIONS_AFTER_COMBAT)
			ns.RegisterEvent("PLAYER_REGEN_ENABLED", "Options", function()
				ns.UnregisterEvent("PLAYER_REGEN_ENABLED", "Options")
				pendingOpen = false
				Options.Open()
			end)
		end
		return false
	end
	Settings.OpenToCategory(categoryID())
	return true
end

ns.OpenOptions = Options.Open

ns.RegisterEvent("PLAYER_LOGIN", "Options", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "Options")
	Options.Create()
end)
