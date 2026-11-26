-- UI/Preview.lua: previewing a place on the map
describe("UI/Preview.lua", function()
	local ns, frame, map, canvas
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				-- the sub-map 9001 is the top-left quarter of Forjaz (1455)
				GetWorldPosFromMapPos = function(mapID, pos)
					local x, y = pos.x, pos.y
					if mapID == 9001 then
						x, y = x / 2, y / 2
					end
					return 0, { GetXY = function() return x, y end }
				end,
				GetMapPosFromWorldPos = function(_, world, mapID)
					local x, y = world:GetXY()
					if mapID ~= 1455 then
						return 0, { GetXY = function() return 5, 5 end } -- off that map
					end
					return 0, { GetXY = function() return x, y end }
				end,
			},
			CreateVector2D = function(x, y) return { x = x, y = y } end,
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		canvas = CreateFrame("Frame", nil, map.ScrollContainer)
		canvas:SetSize(1000, 600)
		map.mapID, map.canvasScale = 1455, 2
		function map:GetMapID() return self.mapID end
		function map:GetCanvas() return canvas end
		function map:GetCanvasScale() return self.canvasScale end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Util.lua", "API/MapScoutAPI.lua", "UI/Map.lua", "UI/Preview.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("PLAYER_LOGIN")
	end)

	local function marker()
		for _, f in ipairs(FakeFrames) do
			if f.name == "MapScoutPreviewMarker" then
				return f
			end
		end
	end

	it("finds where a point is on the open map, also from a sub-map", function()
		assert.are.same({ 0.3, 0.6 }, { ns.Preview.PositionOnMap(1455, 0.3, 0.6, 1455) })
		assert.are.same({ 0.25, 0.25 }, { ns.Preview.PositionOnMap(9001, 0.5, 0.5, 1455) })
		assert.is_nil(ns.Preview.PositionOnMap(9001, 0.5, 0.5, 1453)) -- not on that map
		assert.is_nil(ns.Preview.PositionOnMap(nil, 0.5, 0.5, 1455))
	end)

	it("shows a marker on the canvas, at the point, the same size at any zoom", function()
		assert.is_true(ns.Preview.Show({ mapID = 1455, x = 0.3, y = 0.6 }))
		local m = marker()
		assert.are.equal(canvas, m.parent)
		assert.is_true(m:IsShown())
		assert.are.equal(0.5, m.scale) -- canvas zoomed x2
		assert.are.same({ "CENTER", canvas, "TOPLEFT", 600, -720 }, m.points[1]) -- 0.3*1000*2, 0.6*600*2
		ns.Preview.Hide()
		assert.is_false(m:IsShown())
		assert.is_nil(ns.Preview.shown)
	end)

	it("shows nothing for a place that isn't on the open map", function()
		map.mapID = 1453
		assert.is_false(ns.Preview.Show({ mapID = 9001, x = 0.5, y = 0.5 }))
		assert.is_nil(marker())
	end)

	it("hides when the map changes or closes, never changing the map itself", function()
		ns.Preview.Show({ mapID = 1455, x = 0.3, y = 0.6 })
		assert.are.equal(1455, map.mapID)
		map:Hide()
		assert.is_false(marker():IsShown())
	end)

	it("fills the tooltip with name, subtitle, place, coordinates and distance", function()
		local tooltip = CreateFrame("GameTooltip")
		local result = { item = { entry = { name = "Buzón del museo", mapID = 9001, x = 0.452, y = 0.678 } } }
		ns.Preview.FillTooltip(tooltip, result, "Buzones", "120 m")
		assert.are.equal("Buzón del museo", tooltip:GetText())
		assert.are.same({ "Buzones", "Sala de los Expedicionarios, Forjaz › Reinos del Este", "45.2, 67.8",
			"120 m away" }, tooltip.lines)
	end)
end)
