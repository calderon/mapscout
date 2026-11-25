-- MapScout: the search bar in the world map.
-- A search box with the game's own look (SearchBoxTemplate: magnifier,
-- placeholder, clear button) and a gear button, at the top centre of the map,
-- where Blizzard's buttons (left) and Bridge's (right) are not.
-- Typing searches after a short pause (debounce), so fast typing runs one
-- search, not one per letter. Esc clears the text, then leaves the box: it
-- never closes the map by accident (the box has the keyboard while focused).
-- Other modules (the results list) hear every search with ns.SearchBar.Listen.

local _, ns = ...
local L = ns.L

local SearchBar = {}
ns.SearchBar = SearchBar

SearchBar.DEBOUNCE = 0.15 -- seconds of pause before searching
SearchBar.WIDTH = 260
SearchBar.NARROW_WIDTH = 200 -- when the map is small
SearchBar.NARROW_MAP = 600 -- map width under which the bar is narrower

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
	local results, stats = ns.Engine.Search(query)
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

local function layout()
	local box, layer = SearchBar.box, ns.Map.layer
	local width = layer:GetWidth() or 0
	box:SetWidth(width > 0 and width < SearchBar.NARROW_MAP and SearchBar.NARROW_WIDTH or SearchBar.WIDTH)
end

-- Builds the bar on MapScout's map layer.
function SearchBar.Create()
	if SearchBar.box then
		return
	end
	local layer = ns.Map.layer
	local box = CreateFrame("EditBox", "MapScoutSearchBox", layer, ns.Caps.searchBox and "SearchBoxTemplate" or "InputBoxTemplate")
	box:SetSize(SearchBar.WIDTH, 20)
	box:SetPoint("TOP", layer, "TOP", -12, -10)
	box:SetFrameLevel(layer:GetFrameLevel() + 10)
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
	box:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then
			self:SetText("")
			SearchBar.Search()
		else
			self:ClearFocus()
		end
	end)
	box:SetScript("OnEnterPressed", function()
		SearchBar.Search() -- choosing the first result comes with #37
	end)
	if type(box.clearButton) == "table" then
		box.clearButton:HookScript("OnClick", function()
			SearchBar.Search()
		end)
	end

	local gear = CreateFrame("Button", "MapScoutSettingsButton", layer)
	gear:SetSize(20, 20)
	gear:SetPoint("LEFT", box, "RIGHT", 4, 0)
	gear:SetFrameLevel(box:GetFrameLevel())
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

ns.Map.Listen(function(what)
	if what == "attached" then
		SearchBar.Create()
	elseif what == "shown" then
		C_Timer.After(0, warmIndex)
	elseif what == "hidden" then
		if SearchBar.box then
			SearchBar.box:ClearFocus()
		end
	elseif what == "resized" and SearchBar.box then
		layout()
	end
end)

-- /ms debug bar [live] ------------------------------------------------------------

ns.RegisterDebug("bar", function(args)
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
