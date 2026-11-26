-- Core/Util.lua: where maps are, and distances
describe("Map places and distances", function()
	local ns
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		StubGlobals({ C_Map = { GetMapInfo = function(id) return MAPS[id] end } })
		ns = LoadAddonFile("Core/Init.lua")
		LoadAddonFile("Core/Util.lua", ns)
	end)

	it("knows a map's zone and continent", function()
		local place = ns.MapPlace(9001)
		assert.are.equal("Sala de los Expedicionarios", place.name)
		assert.are.same({ 1455, "Forjaz" }, { place.zoneID, place.zoneName })
		assert.are.same({ 1415, "Reinos del Este" }, { place.continentID, place.continentName })
		assert.are.equal(1455, ns.MapPlace(1455).zoneID)
		assert.is_nil(ns.MapPlace(123456))
		assert.is_nil(ns.MapPlace(nil))
	end)

	it("knows if a map is inside another", function()
		assert.is_true(ns.IsMapInside(1455, 1455))
		assert.is_true(ns.IsMapInside(9001, 1455))
		assert.is_true(ns.IsMapInside(1455, 1415))
		assert.is_false(ns.IsMapInside(1453, 1455))
		assert.is_false(ns.IsMapInside(1454, 1415))
		assert.is_false(ns.IsMapInside(nil, 1455))
	end)

	it("measures the distance from the player on the same continent only", function()
		StubGlobals({
			UnitPosition = function() return 100, 200, 0, 0 end, -- world x, y, z, continent 0
			CreateVector2D = function(x, y) return { x = x, y = y } end,
		})
		_G.C_Map.GetWorldPosFromMapPos = function(mapID, pos)
			local world = { GetXY = function() return pos.x * 1000, pos.y * 1000 end }
			return mapID == 1454 and 1 or 0, world
		end
		-- the point is at world (400, 500), the player at (100, 200): 300 and 300 apart
		assert.are.equal(424, math.floor(ns.DistanceToPlayer(1455, 0.4, 0.5) + 0.5))
		assert.is_nil(ns.DistanceToPlayer(1454, 0.4, 0.5)) -- another continent
		assert.is_nil(ns.DistanceToPlayer(1455, nil, 0.5))
	end)

	it("formats distances in meters, or yards for enUS", function()
		assert.are.equal("5 yd", ns.FormatDistance(5))
		assert.are.equal("1.5k yd", ns.FormatDistance(1500))
		StubGlobals({ GetLocale = function() return "esES" end })
		assert.are.equal("91 m", ns.FormatDistance(100))
		assert.are.equal("1.4 km", ns.FormatDistance(1500))
	end)
end)
