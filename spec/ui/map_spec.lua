-- UI/Map.lua: MapScout's layer in the world map, without taint
describe("UI/Map.lua", function()
	local ns, frame, events, blizzardOnShow

	-- A fake world map, with a script of its own (Blizzard's)
	local function fakeWorldMap(shown)
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.shown = shown or false
		map.mapID = 1455
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		map.ScrollContainer.level = 5
		function map:GetMapID()
			return self.mapID
		end
		function map:OnMapChanged() end
		blizzardOnShow = function() end
		map:SetScript("OnShow", blizzardOnShow)
		return map
	end

	local function load(map)
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1] -- MapScout's event frame (the fake map may come first)
		for _, file in ipairs({ "Core/Util.lua", "API/MapScoutAPI.lua", "UI/Map.lua" }) do
			LoadAddonFile(file, ns)
		end
		if map then
			StubGlobals({ WorldMapFrame = map })
		end
		events = {}
		ns.Map.Listen(function(what, arg)
			events[#events + 1] = arg and (what .. " " .. tostring(arg)) or what
		end)
	end

	local function login()
		frame:Fire("PLAYER_LOGIN")
	end

	before_each(function()
		ResetWoW()
		StubGlobals({ C_Map = { GetMapInfo = function(id) return { name = "Map " .. id } end } })
	end)

	it("puts its own layer over the map area, above the map, without taking the mouse", function()
		local map = fakeWorldMap()
		load(map)
		login()
		local layer = ns.Map.layer
		assert.are.equal(map, layer.parent)
		assert.are.same({ { "ALL", map.ScrollContainer } }, layer.points)
		assert.is_true(layer.level > map.ScrollContainer.level)
		assert.are.equal("MapScoutMapLayer", layer.name)
	end)

	it("only hooks Blizzard's scripts, never replaces them", function()
		local map = fakeWorldMap()
		load(map)
		login()
		assert.are.equal(blizzardOnShow, map.scripts.OnShow) -- untouched
		assert.is_nil(map.scripts.OnHide)
		assert.are.equal(1, #map.hooks.OnShow)
		assert.are.equal(1, #map.hooks.OnHide)
	end)

	it("tells the modules when the map opens, closes and changes", function()
		local map = fakeWorldMap()
		load(map)
		login()
		assert.are.same({ "attached" }, events)
		map:Show()
		map.mapID = 1453
		map:OnMapChanged()
		map:Hide()
		ns.Map.layer:Run("OnSizeChanged")
		assert.are.same({ "attached", "shown", "mapChanged 1455", "mapChanged 1453", "hidden", "resized" }, events)
	end)

	it("says the map is shown when it was already open at login", function()
		load(fakeWorldMap(true))
		login()
		assert.are.same({ "attached", "shown", "mapChanged 1455" }, events)
		assert.is_true(ns.Map.IsShown())
		assert.are.equal(1455, ns.Map.GetMapID())
	end)

	it("waits for the world map addon if the map doesn't exist at login", function()
		load()
		login()
		assert.is_nil(ns.Map.layer)
		StubGlobals({ WorldMapFrame = fakeWorldMap() })
		frame:Fire("ADDON_LOADED", "SomethingElse")
		assert.is_nil(ns.Map.layer)
		frame:Fire("ADDON_LOADED", "Blizzard_WorldMap")
		assert.is_table(ns.Map.layer)
		assert.is_nil(frame.events.ADDON_LOADED)
	end)

	it("keeps telling the other modules if one of them fails", function()
		local map = fakeWorldMap()
		load(map)
		ns.Map.Listen(function() error("module bug") end)
		local after = 0
		ns.Map.Listen(function() after = after + 1 end)
		login()
		map:Show()
		assert.are.equal(3, after) -- attached, shown, mapChanged
		assert.are.equal(3, #ReportedErrors)
	end)

	it("/ms debug map describes the layer", function()
		load(fakeWorldMap(true))
		SlashCmdList.MAPSCOUT("debug map")
		assert.matches("not ready", ChatLog[#ChatLog], 1, true)
		login()
		ns.Map.layer:SetSize(800, 600)
		SlashCmdList.MAPSCOUT("debug map outline")
		assert.matches("map 1455 (Map 1455), open: yes, layer 800 x 600, in combat: no", ChatLog[#ChatLog], 1, true)
	end)
end)
