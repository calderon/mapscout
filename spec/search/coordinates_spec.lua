-- Search/Coordinates.lua: "45 67" or "Dun Morogh 30 40" gives a result to go there
describe("Search by coordinates", function()
	local ns, map
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		local children = {}
		for _, info in pairs(MAPS) do
			children[#children + 1] = info
		end
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function(root) return root == 947 and children or {} end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		map.mapID = 1455
		function map:GetMapID() return self.mapID end
		function map:SetMapID(id) self.mapID = id end
		function map:GetCanvas() return CreateFrame("Frame") end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Search/Coordinates.lua", "UI/Map.lua",
			"UI/SearchBar.lua", "UI/Preview.lua", "UI/Results.lua", "UI/Waypoint.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	local function first(text, zoneMapID)
		local results = ns.Engine.Search(ns.Query.Parse(text), { zoneMapID = zoneMapID })
		return results[1], results
	end

	it("goes to the point on the open map", function()
		local result = first("45 67", 1455)
		local entry = result.item.entry
		assert.are.equal("Go to 45.0, 67.0 in Forjaz", entry.name)
		assert.are.same({ 1455, 0.45, 0.67 }, { entry.mapID, entry.x, entry.y })
		assert.is_true(result.inZone)
	end)

	it("goes to the point on the zone named with it", function()
		local result = first("Dun Morogh 30 40", 1455)
		assert.are.equal("Go to 30.0, 40.0 in Dun Morogh", result.item.entry.name)
		assert.are.equal(1426, result.item.entry.mapID)
		assert.is_nil(result.inZone) -- not the open map
	end)

	it("reads dot and comma decimals", function()
		assert.are.equal("Go to 45.2, 67.8 in Forjaz", first("45.2, 67.8", 1455).item.entry.name)
		assert.are.equal("Go to 45.2, 67.8 in Forjaz", first("45,2 67,8", 1455).item.entry.name)
	end)

	it("gives nothing out of range or without a map", function()
		assert.is_nil(first("145 67", 1455))
		assert.is_nil(first("45 67", nil))
	end)

	it("comes first, before other results", function()
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries({
			{ id = 1, name = "Hello there", mapID = 1455, x = 0.5, y = 0.5 },
		})
		local result, all = first("hello 45 67", 1455)
		assert.are.equal("coordinates", result.item.provider)
		assert.are.equal("Hello there", all[2].item.entry.name)
	end)

	it("opens its map with the halo, and isn't remembered", function()
		map.mapID = 1453
		ns.Waypoint.Go((first("Dun Morogh 30 40", 1453)), "Dun Morogh 30 40")
		assert.are.equal(1426, map.mapID)
		assert.is_table(ns.Preview.shown)
		assert.are.same({}, MapScoutDB.frequency)
		assert.are.same({}, MapScoutCharDB.history)
	end)

	it("shows in the list with its subtitle and icon", function()
		ns.SearchBar.box:SetText("45 67")
		ns.SearchBar.Search()
		local line = ns.Results.lines[2] -- after "In Forjaz"
		assert.are.equal("Go to 45.0, 67.0 in Forjaz", line.text)
		assert.are.equal("Coordinates", line.subtitle)
	end)
end)
