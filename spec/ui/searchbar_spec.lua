-- UI/SearchBar.lua: the search box in the world map
describe("UI/SearchBar.lua", function()
	local ns, frame, map, box, searches

	local function fakeWorldMap()
		local m = CreateFrame("Frame", "WorldMapFrame")
		m.shown = false
		m.ScrollContainer = CreateFrame("Frame", nil, m)
		m.ScrollContainer.level = 5
		m.BorderFrame = CreateFrame("Frame", nil, m)
		m.BorderFrame.level = 2
		m.BorderFrame.GetFrameStrata = function() return "HIGH" end
		function m:GetMapID()
			return 1455
		end
		function m:OnMapChanged() end
		return m
	end

	before_each(function()
		ResetWoW()
		StubGlobals({ C_XMLUtil = { GetTemplateInfo = function() return { type = "EditBox" } end } })
		map = fakeWorldMap()
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries({
			{ id = 1, name = "Banco de Forjaz", mapID = 1455, x = 0.3, y = 0.6 },
			{ id = 2, name = "Buzón de Forjaz", mapID = 1455, x = 0.4, y = 0.6 },
		})
		box = ns.SearchBar.box
		searches = {}
		ns.SearchBar.Listen(function(results, query)
			searches[#searches + 1] = { text = query.raw, count = #results }
		end)
	end)

	local function type(text)
		box:SetText(text)
		box:Run("OnTextChanged", true) -- typed by the player
	end

	it("is a search box with the game's look in the map's title strip", function()
		assert.are.equal("MapScoutSearchBox", box.name)
		assert.are.equal("SearchBoxTemplate", box.template)
		assert.are.equal(ns.Map.layer, box.parent)
		local gear = ns.SearchBar.gear
		assert.are.equal("MapScoutSettingsButton", gear.name)
		assert.are.equal("title", ns.SearchBar.placement)
		assert.are.same({ "RIGHT", ns.Map.layer, "TOPRIGHT", -30, 11 }, gear.points[1])
		assert.are.same({ "RIGHT", gear, "LEFT", -4, 0 }, box.points[1])
	end)

	it("is drawn above the map's border, in its layer, so the title strip doesn't hide it", function()
		local strata = {}
		for _, f in ipairs({ box, ns.SearchBar.gear }) do
			f.SetFrameStrata = function(self, s) strata[self] = s end
		end
		ns.SearchBar.Raise(box)
		ns.SearchBar.Raise(ns.SearchBar.gear)
		assert.are.equal("HIGH", strata[box])
		assert.are.equal("HIGH", strata[ns.SearchBar.gear])
		assert.are.equal(12, box.level) -- border level 2 + 10 (its children are lower here)
		local high = CreateFrame("Button", nil, map.BorderFrame)
		high.level = 2008 -- like Blizzard's maximize button
		map.BorderFrame.GetChildren = function() return high end
		ns.SearchBar.Raise(box)
		assert.are.equal(2018, box.level)
	end)

	describe("room left by the zone path", function()
		local function withZonePath(crumbRight)
			ns.SearchBar.gear.GetLeft = function() return 900 end
			local crumb = CreateFrame("Button")
			crumb.GetRight = function() return crumbRight end
			local hidden = CreateFrame("Button")
			hidden.shown = false
			hidden.GetRight = function() return 2000 end
			map.NavBar = { navList = { crumb, hidden } }
			ns.SearchBar.Layout()
		end

		it("keeps the widest box when there is room", function()
			withZonePath(600) -- 900 - 4 - 600 - 12 = 284 of room
			assert.are.equal("title", ns.SearchBar.placement)
			assert.are.equal(260, box:GetWidth())
		end)

		it("gets narrower with a longer zone path", function()
			withZonePath(700) -- 184 of room
			assert.are.equal("title", ns.SearchBar.placement)
			assert.are.equal(184, box:GetWidth())
		end)

		it("goes inside the map when the zone path leaves too little room", function()
			withZonePath(800) -- 84 of room
			assert.are.equal("inside", ns.SearchBar.placement)
			assert.are.same({ "TOPLEFT", ns.Map.layer, "TOPLEFT", 42, -8 }, box.points[1])
			assert.are.same({ "LEFT", box, "RIGHT", 4, 0 }, ns.SearchBar.gear.points[1])
			assert.are.equal(260, box:GetWidth())
		end)

		it("is placed again when the map changes", function()
			withZonePath(600)
			map.NavBar.navList[1].GetRight = function() return 800 end
			map:OnMapChanged()
			RunTimers()
			assert.are.equal("inside", ns.SearchBar.placement)
		end)
	end)

	it("falls back to a plain input box without the search template", function()
		ResetWoW()
		local m = fakeWorldMap()
		StubGlobals({ WorldMapFrame = m })
		local before = #FakeFrames
		local other = LoadAddonFile("Core/Init.lua")
		local f = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua" }) do
			LoadAddonFile(file, other)
		end
		f:Fire("PLAYER_LOGIN")
		assert.are.equal("InputBoxTemplate", other.SearchBar.box.template)
	end)

	it("searches once after a pause, not on every letter", function()
		type("b")
		type("ba")
		type("ban")
		assert.are.same({}, searches)
		assert.are.equal(1, PendingTimers())
		RunTimers()
		assert.are.same({ { text = "ban", count = 1 } }, searches)
	end)

	it("searches again by itself when what can be found changes", function()
		type("ban")
		RunTimers()
		assert.are.equal(1, #searches)
		-- a provider finishing its build (new entries)
		MapScoutAPI:RegisterProvider("late", { name = "Late" }):SetEntries({
			{ id = 1, name = "Banco tardío", mapID = 1455, x = 0.5, y = 0.5 },
		})
		RunTimers()
		assert.are.same({ text = "ban", count = 2 }, searches[#searches])
		-- a provider turned off
		ns.Registry.SetEnabled("late", false)
		RunTimers()
		assert.are.same({ text = "ban", count = 1 }, searches[#searches])
		-- nothing typed: nothing to search again
		box:SetText("")
		local before = #searches
		ns.Registry.SetEnabled("late", true)
		RunTimers()
		assert.are.equal(before, #searches)
	end)

	it("doesn't search when the text is changed by code", function()
		box:SetText("ban")
		box:Run("OnTextChanged", false)
		assert.are.equal(0, PendingTimers())
	end)

	it("searches at once on Enter, without waiting", function()
		type("forjaz")
		box:Run("OnEnterPressed")
		assert.are.same({ { text = "forjaz", count = 2 } }, searches)
		assert.are.equal(0, PendingTimers()) -- the pending search was cancelled
	end)

	it("Esc clears the text first, then leaves the box", function()
		box:SetFocus()
		type("ban")
		box:Run("OnEscapePressed")
		assert.are.equal("", box:GetText())
		assert.is_true(box:HasFocus())
		assert.are.same({ text = "", count = 0 }, searches[#searches])
		box:Run("OnEscapePressed")
		assert.is_false(box:HasFocus())
	end)

	it("shows the results again when the box gets the focus back with text", function()
		box:SetText("ban")
		box:Run("OnEditFocusGained")
		assert.are.same({ text = "ban", count = 1 }, searches[#searches])
		local before = #searches
		box:SetText("")
		box:Run("OnEditFocusGained")
		assert.are.equal(before, #searches) -- an empty box doesn't search
	end)

	it("keeps the template's own text handling (hook, not replace)", function()
		assert.is_nil(box.scripts.OnTextChanged)
		assert.are.equal(1, #box.hooks.OnTextChanged)
	end)

	it("the gear shows the help until the options panel exists", function()
		ns.SearchBar.gear:Run("OnClick")
		assert.matches("/ms help", table.concat(ChatLog, "\n"), 1, true)
	end)

	it("builds the index when the map opens and leaves the box when it closes", function()
		assert.are.same({ 0, 0 }, { ns.Index.Stats() })
		map:Show()
		RunTimers()
		assert.are.same({ 1, 2 }, { ns.Index.Stats() })
		box:SetFocus()
		map:Hide()
		assert.is_false(box:HasFocus())
	end)

	it("/ms debug bar shows the last search, and live prints each one", function()
		SlashCmdList.MAPSCOUT("debug bar")
		assert.matches("hasn't searched", ChatLog[#ChatLog], 1, true)
		SlashCmdList.MAPSCOUT("debug bar live")
		type("buzon")
		RunTimers()
		assert.matches('bar: "buzon" -> 1 results in', ChatLog[#ChatLog], 1, true)
	end)
end)
