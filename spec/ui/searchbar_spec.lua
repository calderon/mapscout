-- UI/SearchBar.lua: the search box in the world map
describe("UI/SearchBar.lua", function()
	local ns, frame, map, box, searches

	local function fakeWorldMap()
		local m = CreateFrame("Frame", "WorldMapFrame")
		m.shown = false
		m.ScrollContainer = CreateFrame("Frame", nil, m)
		m.ScrollContainer.level = 5
		function m:GetMapID()
			return 1455
		end
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

	it("is a search box with the game's look at the top centre of the map", function()
		assert.are.equal("MapScoutSearchBox", box.name)
		assert.are.equal("SearchBoxTemplate", box.template)
		assert.are.equal(ns.Map.layer, box.parent)
		assert.are.same({ "TOP", ns.Map.layer, "TOP", -12, -10 }, box.points[1])
		assert.is_true(box.level > ns.Map.layer.level)
		assert.are.equal("MapScoutSettingsButton", ns.SearchBar.gear.name)
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

	it("keeps the template's own text handling (hook, not replace)", function()
		assert.is_nil(box.scripts.OnTextChanged)
		assert.are.equal(1, #box.hooks.OnTextChanged)
	end)

	it("the gear shows the help until the options panel exists", function()
		ns.SearchBar.gear:Run("OnClick")
		assert.matches("/ms help", table.concat(ChatLog, "\n"), 1, true)
	end)

	it("gets narrower on a small map", function()
		ns.Map.layer:SetSize(500, 400)
		ns.Map.layer:Run("OnSizeChanged")
		assert.are.equal(200, box:GetWidth())
		ns.Map.layer:SetSize(1200, 800)
		ns.Map.layer:Run("OnSizeChanged")
		assert.are.equal(260, box:GetWidth())
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
