-- Providers/Geography.lua: continents, zones and areas from the game's map tree
describe("Providers/Geography.lua", function()
	local ns, map, frame
	local MAPS = dofile("spec/fixtures/maps.lua")

	local function children()
		local list = {}
		for _, info in pairs(MAPS) do
			if info.mapID ~= 947 then
				list[#list + 1] = info
			end
		end
		table.sort(list, function(a, b) return a.mapID < b.mapID end)
		list[#list + 1] = MAPS[1455] -- the tree can repeat a map
		list[#list + 1] = { mapID = 7000, name = "Las Minas de la Muerte", mapType = 4, parentMapID = 1436 } -- dungeon
		return list
	end

	before_each(function()
		ResetWoW()
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function(root) return root == 947 and children() or {} end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			GetLocale = function() return "esES" end,
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		map.mapID = 1453
		function map:GetMapID() return self.mapID end
		function map:SetMapID(id) self.mapID = id end
		function map:GetCanvas() return CreateFrame("Frame") end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "Core/Packs.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Geography.lua", "UI/Map.lua",
			"UI/SearchBar.lua", "UI/Preview.lua", "UI/Results.lua", "UI/Waypoint.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	local function search(text)
		local names = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			names[i] = r.item.entry.name
		end
		return names
	end

	it("registers through the API like any other provider", function()
		local record = ns.Registry.Get("geography")
		assert.is_true(record.enabled)
		assert.are.equal("Lugares", record.spec.name)
	end)

	it("has every continent, zone and area once, and no dungeon interiors", function()
		local byID = {}
		for _, entry in ipairs(ns.Registry.Get("geography").entries) do
			assert.is_nil(byID[entry.id], "repeated " .. entry.id)
			byID[entry.id] = entry
			assert.is_true(entry.isMap)
		end
		assert.are.equal("continents", byID[1415].category)
		assert.are.equal("cities", byID[1455].category) -- a capital
		assert.are.equal("zones", byID[1426].category)
		assert.are.equal("others", byID[9001].category)
		assert.is_nil(byID[7000]) -- a dungeon interior
		assert.is_nil(byID[947]) -- the world itself
	end)

	it("finds places by name, in the player's language", function()
		assert.are.same({ "Forjaz" }, search("forjaz"))
		assert.are.same({ "Ciudad de Ventormenta" }, search("ventormenta"))
		assert.are.same({ "Reinos del Este" }, search("reinos"))
	end)

	it("filters by kind with @ words in Spanish and English", function()
		assert.are.same({ "Kalimdor", "Reinos del Este" }, search("@continentes"))
		assert.are.same({ "Kalimdor", "Reinos del Este" }, search("@continents"))
		assert.are.same({ "Forjaz", "Orgrimmar", "Ciudad de Ventormenta" }, search("@ciudades"))
		assert.are.same({ "Forjaz", "Orgrimmar", "Ciudad de Ventormenta" }, search("@capital"))
		assert.are.same({ "Dun Morogh" }, search("@zonas")) -- capitals aren't zones here
		assert.are.same({ "Sala de los Expedicionarios" }, search("@campos"))
		assert.are.same({ "Sala de los Expedicionarios" }, search("@bg"))
		assert.are.equal(7, #search("@lugares"))
		assert.are.equal(7, #search("@regiones"))
		assert.are.equal(7, #search("@region"))
		assert.are.equal(7, #search("@región")) -- with the accent too
	end)

	it("selects places while the @ word is still being typed", function()
		assert.are.same({ "Kalimdor", "Reinos del Este" }, search("@cont"))
		assert.are.same({ "Dun Morogh" }, search("@zon"))
		assert.are.equal(3, #search("@ciu"))
	end)

	local function groupsOf(text)
		ns.SearchBar.box:SetText(text)
		ns.SearchBar.Search()
		local groups = {}
		for _, line in ipairs(ns.Results.lines) do
			if line.kind == "group" then
				groups[#groups + 1] = line.text
			end
		end
		return groups
	end

	it("groups whole maps under the map above them", function()
		-- cities under their continent, one group each, not one per city
		assert.are.same({ "Reinos del Este", "Kalimdor" }, groupsOf("@ciudades"))
		-- continents under the world
		assert.are.same({ "Azeroth" }, groupsOf("@continentes"))
	end)

	it("searches all places when the chosen kind finds nothing, and says so", function()
		local results, stats = ns.Engine.Search(ns.Query.Parse("@zona reinos del este"))
		assert.are.equal("Reinos del Este", results[1].item.entry.name)
		assert.are.same({ { provider = "geography", category = "zones" } }, stats.widened)
		ns.SearchBar.box:SetText("@zona reinos del este")
		ns.SearchBar.Search()
		assert.are.same({ kind = "hint", text = "Nada en Zonas; resultados en todo Lugares" }, ns.Results.lines[1])
		-- a whole provider, or a kind that finds something, isn't widened
		local _, plain = ns.Engine.Search(ns.Query.Parse("@zona dun"))
		assert.is_nil(plain.widened)
		local _, none = ns.Engine.Search(ns.Query.Parse("@lugares zzzz"))
		assert.is_nil(none.widened)
	end)

	it("opens the map without halo nor pin, and shows no distance", function()
		ns.SearchBar.box:SetText("forjaz")
		ns.SearchBar.Search()
		local line = ns.Results.lines[#ns.Results.lines]
		assert.is_nil(line.distance)
		ns.Waypoint.Go(ns.Results.FirstResult(), "forjaz")
		assert.are.equal(1455, map.mapID)
		assert.is_nil(ns.Preview.shown)
	end)
end)
