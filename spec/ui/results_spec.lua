-- UI/Results.lua: the list of results under the bar
describe("UI/Results.lua", function()
	local ns, frame, map
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		StubGlobals({
			C_Map = { GetMapInfo = function(id) return MAPS[id] end },
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			C_EventUtils = { IsEventValid = function(event) return event == "GLOBAL_MOUSE_DOWN" end },
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		function map:OnMapChanged() end
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		map.mapID = 1455
		function map:GetMapID()
			return self.mapID
		end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Preview.lua", "UI/Results.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("services", {
			name = "Services",
			categories = { { id = "mail", name = "Buzones" } },
		}):SetEntries({
			{ id = 1, name = "Buzón de la Gran Fundición", category = "mail", mapID = 1455, x = 0.5, y = 0.5 },
			{ id = 2, name = "Buzón del museo", category = "mail", mapID = 9001, x = 0.5, y = 0.5 },
			{ id = 3, name = "Buzón de Ventormenta", category = "mail", mapID = 1453, x = 0.5, y = 0.5 },
			{ id = 4, name = "Buzón de Kharanos", category = "mail", mapID = 1426, x = 0.5, y = 0.5 },
			{ id = 5, name = "Buzón de Orgrimmar", category = "mail", mapID = 1454, x = 0.5, y = 0.5 },
		})
	end)

	local function search(text)
		ns.SearchBar.box:SetText(text)
		ns.SearchBar.Search()
		local lines = {}
		for i, line in ipairs(ns.Results.lines) do
			lines[i] = line.kind .. ": " .. line.text .. (line.subtitle and (" | " .. line.subtitle) or "")
		end
		return lines
	end

	it("groups results: this map first, then the rest by continent and zone", function()
		-- same score for all: shorter names first, and groups in the order of their best result
		assert.are.same({
			"zone: In Forjaz",
			"result: Buzón del museo | Buzones · Sala de los Expedicionarios",
			"result: Buzón de la Gran Fundición | Buzones",
			"elsewhere: Elsewhere",
			"group: Reinos del Este › Dun Morogh",
			"result: Buzón de Kharanos | Buzones",
			"group: Kalimdor › Orgrimmar",
			"result: Buzón de Orgrimmar | Buzones",
			"group: Reinos del Este › Ciudad de Ventormenta",
			"result: Buzón de Ventormenta | Buzones",
		}, search("buzon"))
	end)

	it("follows the open map", function()
		map.mapID = 1453
		local lines = search("buzon")
		assert.are.equal("zone: In Ciudad de Ventormenta", lines[1])
		assert.are.equal("result: Buzón de Ventormenta | Buzones", lines[2])
	end)

	it("shows the distance in this zone when it is known", function()
		StubGlobals({
			UnitPosition = function() return 0, 0, 0, 0 end,
			CreateVector2D = function(x, y) return { x = x, y = y } end,
		})
		_G.C_Map.GetWorldPosFromMapPos = function(_, pos)
			return 0, { GetXY = function() return pos.x * 100, 0 end }
		end
		search("gran fundicion")
		assert.are.equal("50 yd", ns.Results.lines[2].distance)
	end)

	describe("a click outside", function()
		local box

		before_each(function()
			box = ns.SearchBar.box
			box:SetFocus()
			search("buzon")
			assert.is_true(ns.Results.frame:IsShown())
		end)

		it("closes the list and leaves the box, keeping the text", function()
			frame:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
			assert.is_false(ns.Results.frame:IsShown())
			assert.is_false(box:HasFocus())
			assert.are.equal("buzon", box:GetText())
			assert.is_nil(frame.events.GLOBAL_MOUSE_DOWN) -- not watched while closed
		end)

		it("does nothing on the list or on the box", function()
			ns.Results.frame.IsMouseOver = function() return true end
			frame:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
			assert.is_true(ns.Results.frame:IsShown())
			ns.Results.frame.IsMouseOver = function() return false end
			box.IsMouseOver = function() return true end
			frame:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
			assert.is_true(ns.Results.frame:IsShown())
		end)

		it("keeps it closed when the map changes, until the box is used again", function()
			frame:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
			map.mapID = 1453
			map:OnMapChanged() -- e.g. a pin of the map was clicked
			assert.is_false(ns.Results.frame:IsShown())
			box:Run("OnEditFocusGained")
			assert.is_true(ns.Results.frame:IsShown())
			assert.are.equal("zone: In Ciudad de Ventormenta", ns.Results.lines[1].kind .. ": " .. ns.Results.lines[1].text)
		end)

		it("searches again when the map changes with the list open", function()
			map.mapID = 1453
			map:OnMapChanged()
			assert.is_true(ns.Results.frame:IsShown())
			assert.are.equal("In Ciudad de Ventormenta", ns.Results.lines[1].text)
		end)
	end)

	it("shows a hint when nothing matches, and nothing for an empty search", function()
		assert.are.same({ "empty: No results", "hint: Try @ or coordinates (45 67)" },
			search("zzzz"))
		assert.are.same({}, search(""))
		assert.is_false(ns.Results.frame:IsShown())
	end)

	it("reuses its rows between searches", function()
		search("buzon")
		local created = ns.Results.RowCount()
		search("kharanos")
		search("buzon")
		assert.are.equal(created, ns.Results.RowCount())
		assert.is_true(ns.Results.frame:IsShown())
	end)

	it("shows the scroll bar only when the list doesn't fit", function()
		local bar = CreateFrame("Slider")
		ns.Results.scroll.ScrollBar = bar
		search("buzon") -- 10 lines: fits
		assert.is_false(ns.Results.overflows)
		assert.is_false(bar:IsShown())
		local many = {}
		for i = 1, 30 do
			many[i] = { id = i, name = "Posada " .. i, mapID = 1455, x = 0.5, y = 0.5 }
		end
		MapScoutAPI:RegisterProvider("inns", { name = "Inns" }):SetEntries(many)
		search("posada")
		assert.is_true(ns.Results.overflows)
		assert.is_true(bar:IsShown())
		ns.Results.scroll:Run("OnScrollRangeChanged") -- the template showing it again
		search("kharanos")
		ns.Results.scroll:Run("OnScrollRangeChanged")
		assert.is_false(bar:IsShown())
	end)

	it("hides with the map", function()
		search("buzon")
		map:Hide()
		assert.is_false(ns.Results.frame:IsShown())
	end)
end)

describe("UI/Results.lua hover", function()
	it("previews the place and shows a tooltip on result rows only", function()
		ResetWoW()
		local MAPS = dofile("spec/fixtures/maps.lua")
		StubGlobals({
			C_Map = { GetMapInfo = function(id) return MAPS[id] end },
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
		})
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		local ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Preview.lua",
			"UI/Results.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries({
			{ id = 1, name = "Buzón de Forjaz", mapID = 1455, x = 0.3, y = 0.6 },
		})
		local shown, hidden = {}, 0
		ns.Preview.Show = function(place) shown[#shown + 1] = place.name end
		ns.Preview.Hide = function() hidden = hidden + 1 end
		ns.SearchBar.box:SetText("buzon")
		ns.SearchBar.Search()
		-- the header row ("In Forjaz") is first, the result second
		local rows = {}
		for _, f in ipairs(FakeFrames) do
			if f.type == "Button" and f.index then
				rows[f.index] = f
			end
		end
		rows[1]:Run("OnEnter")
		assert.are.same({}, shown) -- a header: nothing
		rows[2]:Run("OnEnter")
		assert.are.same({ "Buzón de Forjaz" }, shown)
		assert.are.equal("Buzón de Forjaz", GameTooltip:GetText())
		rows[2]:Run("OnLeave")
		assert.is_true(hidden >= 1)
	end)
end)

describe("UI/Results.lua live distances", function()
	local ns, map, px

	before_each(function()
		ResetWoW()
		local MAPS = dofile("spec/fixtures/maps.lua")
		px = 0
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetWorldPosFromMapPos = function(_, pos) return 0, { GetXY = function() return pos.x * 100, 0 end } end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			UnitPosition = function() return px, 0, 0, 0 end,
			CreateVector2D = function(x, y) return { x = x, y = y } end,
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Preview.lua",
			"UI/Results.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries({
			{ id = 1, name = "Buzón de Forjaz", mapID = 1455, x = 0.5, y = 0.5 }, -- 50 yards east of x = 0
			{ id = 2, name = "Buzón lejano", mapID = 1453, x = 0.5, y = 0.5 },
		})
		ns.SearchBar.box:SetText("buzon")
		ns.SearchBar.Search()
	end)

	local function distance()
		return ns.Results.lines[2].distance -- the first result, after "In Forjaz"
	end

	it("follows the player while the list is open", function()
		assert.are.equal("50 yd", distance())
		assert.is_true(ns.Results.IsFollowingDistances())
		px = 20
		RunTimers()
		assert.are.equal("30 yd", distance())
	end)

	it("does nothing while the player stands still", function()
		assert.is_false(ns.Results.UpdateDistances())
		px = 0.5 -- less than a yard
		assert.is_false(ns.Results.UpdateDistances())
	end)

	it("stops when the list closes", function()
		ns.Results.Hide()
		assert.is_false(ns.Results.IsFollowingDistances())
		px = 20
		RunTimers()
		assert.are.equal("50 yd", distance()) -- not worked out again
	end)

	it("doesn't start without distances to follow", function()
		ns.SearchBar.box:SetText("lejano")
		ns.SearchBar.Search()
		assert.is_false(ns.Results.IsFollowingDistances())
	end)
end)
