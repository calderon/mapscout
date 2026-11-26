-- MapScout: the search bar in the world map.
-- A search box with the game's own look (SearchBoxTemplate: magnifier,
-- placeholder, clear button) and a gear button, in the map's title strip:
-- right after the zone path (breadcrumbs), just left of the map's ▲ button,
-- where Blizzard puts its own quest log search box. Nothing of the map covers
-- it there (the zone label Blizzard shows on hover is at the top of the map).
-- The box takes the room left by the zone path, which changes with the map
-- (longer names, more steps); with too little room it goes inside the map,
-- top left, next to Blizzard's round buttons.
-- Typing searches after a short pause (debounce), so fast typing runs one
-- search, not one per letter. Esc clears the text, then leaves the box: it
-- never closes the map by accident (the box has the keyboard while focused).
-- Other modules (the results list) hear every search with ns.SearchBar.Listen.

local _, ns = ...
local L = ns.L

local SearchBar = {}
ns.SearchBar = SearchBar

SearchBar.DEBOUNCE = 0.15 -- seconds of pause before searching
SearchBar.WIDTH = 260 -- widest box
SearchBar.MIN_WIDTH = 140 -- narrower than this, the bar goes inside the map
SearchBar.TITLE_X, SearchBar.TITLE_Y = -30, 11 -- gear: left of the ▲ button, above the map's top edge
SearchBar.INSIDE_X, SearchBar.INSIDE_Y = 42, -8 -- inside the map, after Blizzard's round buttons
SearchBar.CRUMB_GAP = 12 -- space kept after the last step of the zone path

local listeners = {} -- fn(results, query, stats)
local timer
local live = false -- /ms debug bar live: print every search

function SearchBar.Listen(fn)
	listeners[#listeners + 1] = fn
end

-- Runs the search for the bar's current text now and tells the listeners.
function SearchBar.Search()
	if timer then
		timer:Cancel()
		timer = nil
	end
	local box = SearchBar.box
	local text = box and box:GetText() or ""
	local query = ns.Query.Parse(text)
	local start = debugprofilestop()
	local results, stats = ns.Engine.Search(query, { zoneMapID = ns.Map.GetMapID() })
	stats.ms = debugprofilestop() - start
	SearchBar.last = { text = text, query = query, results = results, stats = stats }
	for _, fn in ipairs(listeners) do
		ns.API.SafeCall(fn, results, query, stats)
	end
	if live then
		ns.Print(L.DEBUG_BAR_LIVE:format(text, #results, stats.ms))
	end
end

local function schedule()
	if timer then
		timer:Cancel()
	end
	timer = C_Timer.NewTimer(SearchBar.DEBOUNCE, SearchBar.Search)
end

-- The gear: the options panel once it exists (#49); for now, the help.
local function openOptions()
	if ns.OpenOptions then
		ns.OpenOptions()
	else
		ns.HandleSlash("help")
	end
end

-- Right edge of the last visible step of the map's zone path, or nil
local function lastCrumbRight()
	local nav = WorldMapFrame and WorldMapFrame.NavBar
	local list = type(nav) == "table" and nav.navList
	if type(list) ~= "table" then
		return nil
	end
	local right
	for _, button in ipairs(list) do
		if type(button) == "table" and button:IsShown() then
			local r = button:GetRight()
			if r and (not right or r > right) then
				right = r
			end
		end
	end
	return right
end

-- Places the bar: in the title strip when the zone path leaves room for it,
-- otherwise inside the map. Only MapScout's frames move.
local function layout()
	local box, gear, layer = SearchBar.box, SearchBar.gear, ns.Map.layer
	gear:ClearAllPoints()
	gear:SetPoint("RIGHT", layer, "TOPRIGHT", SearchBar.TITLE_X, SearchBar.TITLE_Y)
	local width = SearchBar.WIDTH
	local gearLeft, crumbRight = gear:GetLeft(), lastCrumbRight()
	if gearLeft and crumbRight then
		width = math.min(width, gearLeft - 4 - crumbRight - SearchBar.CRUMB_GAP)
	end
	box:ClearAllPoints()
	if width >= SearchBar.MIN_WIDTH then
		SearchBar.placement = "title"
		box:SetPoint("RIGHT", gear, "LEFT", -4, 0)
		box:SetWidth(width)
	else
		SearchBar.placement = "inside"
		box:SetPoint("TOPLEFT", layer, "TOPLEFT", SearchBar.INSIDE_X, SearchBar.INSIDE_Y)
		box:SetWidth(SearchBar.WIDTH)
		gear:ClearAllPoints()
		gear:SetPoint("LEFT", box, "RIGHT", 4, 0)
	end
end
SearchBar.Layout = layout

-- The map's border (with its title strip) is drawn in a higher layer (strata)
-- than the map itself, and its parts (title background, buttons) sit at high
-- levels in it: the bar goes in the same strata, above the highest of them,
-- or the title strip hides it. Only MapScout's frames change.
SearchBar.LEVEL_ABOVE_BORDER = 10

local function highestLevel(frame)
	local highest = frame:GetFrameLevel() or 0
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			if type(child) == "table" and child.GetFrameLevel then
				highest = math.max(highest, highestLevel(child))
			end
		end
	end
	return highest
end

function SearchBar.Raise(frame, extra)
	local border = WorldMapFrame and WorldMapFrame.BorderFrame
	if type(border) == "table" and border.GetFrameStrata then
		frame:SetFrameStrata(border:GetFrameStrata())
		frame:SetFrameLevel(highestLevel(border) + SearchBar.LEVEL_ABOVE_BORDER + (extra or 0))
	else
		frame:SetFrameLevel(ns.Map.layer:GetFrameLevel() + 10 + (extra or 0))
	end
end

-- Builds the bar on MapScout's map layer.
function SearchBar.Create()
	if SearchBar.box then
		return
	end
	local layer = ns.Map.layer
	local box = CreateFrame("EditBox", "MapScoutSearchBox", layer, ns.Caps.searchBox and "SearchBoxTemplate" or "InputBoxTemplate")
	box:SetSize(SearchBar.WIDTH, 20)
	SearchBar.Raise(box)
	box:SetAutoFocus(false)
	box:SetMaxLetters(80)
	-- Parts of the template (not in InputBoxTemplate, or in some clients)
	if type(box.Instructions) == "table" then
		box.Instructions:SetText(L.SEARCH_PLACEHOLDER)
	end

	-- MapScout's own box: the template's OnTextChanged (clear button, placeholder)
	-- is kept with HookScript; OnEscapePressed is ours.
	box:HookScript("OnTextChanged", function(_, userInput)
		if userInput then
			schedule()
		end
	end)
	-- Back to a box that still has text: show its results again
	box:HookScript("OnEditFocusGained", function(self)
		if self:GetText() ~= "" then
			SearchBar.Search()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then
			self:SetText("")
			SearchBar.Search()
		else
			self:ClearFocus()
		end
	end)
	box:SetScript("OnEnterPressed", function(self)
		SearchBar.Search()
		local first = ns.Results and ns.Results.FirstResult()
		if first then
			ns.Waypoint.Go(first, self:GetText()) -- Enter: the first result
		end
	end)
	if type(box.clearButton) == "table" then
		box.clearButton:HookScript("OnClick", function()
			SearchBar.Search()
		end)
	end

	local gear = CreateFrame("Button", "MapScoutSettingsButton", layer)
	gear:SetSize(20, 20)
	SearchBar.Raise(gear)
	local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("questlog-icon-setting")
	if atlas then
		gear:SetNormalAtlas("questlog-icon-setting")
		gear:SetHighlightAtlas("questlog-icon-setting", "ADD")
	else
		gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	end
	gear:SetScript("OnClick", openOptions)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L.SETTINGS)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	SearchBar.box, SearchBar.gear = box, gear
	layout()
end

-- Builds the providers' part of the index while the map opens, so the
-- first letter typed doesn't pay for it.
local function warmIndex()
	for _, record in ipairs(ns.Registry.List()) do
		if record.enabled then
			ns.Index.Items(record.id)
		end
	end
end

-- Something changed in what can be found (a provider turned on or off, new
-- entries, also when a provider finishes building, a category turned on or
-- off): the search typed in the bar runs again, after the same short pause.
ns.Registry.Listen(function(what)
	if what == "toggled" or what == "entries" or what == "categories" or what == "removed" then
		if SearchBar.box and SearchBar.box:GetText() ~= "" then
			schedule()
		end
	end
end)

ns.Map.Listen(function(what)
	if what == "attached" then
		SearchBar.Create()
	elseif what == "shown" then
		C_Timer.After(0, warmIndex)
		C_Timer.After(0, layout) -- after the map has placed its zone path
	elseif what == "mapChanged" then
		if SearchBar.box then
			C_Timer.After(0, layout) -- the zone path changes with the map
		end
		-- another zone: search again so "In this zone" follows the map
		if SearchBar.box and SearchBar.box:GetText() ~= "" then
			SearchBar.Search()
		end
	elseif what == "hidden" then
		if SearchBar.box then
			SearchBar.box:ClearFocus()
		end
	elseif what == "resized" and SearchBar.box then
		layout()
	end
end)

-- /ms debug bar [live] ------------------------------------------------------------

local function describe(frame)
	if not frame then
		return "-"
	end
	local left, top = frame:GetLeft(), frame:GetTop()
	return ("%s %s at %s,%s size %sx%s %s/%s"):format(frame:IsShown() and "shown" or "hidden",
		frame:IsVisible() and "visible" or "not visible", tostring(left and math.floor(left)),
		tostring(top and math.floor(top)), tostring(math.floor(frame:GetWidth() or 0)),
		tostring(math.floor(frame:GetHeight() or 0)), tostring(frame:GetFrameStrata()), tostring(frame:GetFrameLevel()))
end

ns.RegisterDebug("bar", function(args)
	if args == "where" then
		ns.Print(("placement %s · box: %s · gear: %s"):format(tostring(SearchBar.placement), describe(SearchBar.box),
			describe(SearchBar.gear)))
		return
	end
	if args == "live" then
		live = not live
		ns.Print(live and L.DEBUG_BAR_LIVE_ON or L.DEBUG_BAR_LIVE_OFF)
		return
	end
	local last = SearchBar.last
	if not last then
		ns.Print(L.DEBUG_BAR_NOTHING)
		return
	end
	ns.Print(L.DEBUG_BAR_LIVE:format(last.text, #last.results, last.stats.ms))
end, L.DEBUG_BAR)
