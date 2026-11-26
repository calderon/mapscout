-- UI/Results.lua: the list of results under the bar
describe("UI/Results.lua", function()
	local ns, frame, map
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		StubGlobals({
			C_Map = { GetMapInfo = function(id) return MAPS[id] end },
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
		})
		map = CreateFrame("Frame", "WorldMapFrame")
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
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Results.lua" }) do
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
