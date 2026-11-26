-- Providers/Flights.lua: flight masters from the game, placed in their zone
describe("Providers/Flights.lua", function()
	local ns, frame
	local MAPS = dofile("spec/fixtures/maps.lua")

	-- Nodes as Forever gives them: all of a continent, positions on the continent
	local NODES = {
		[1415] = {
			{ nodeID = 6, name = "Forjaz, Dun Morogh", faction = 2, position = { x = 0.47, y = 0.60 } },
			{ nodeID = 2, name = "Ventormenta, Elwynn", faction = 2, position = { x = 0.42, y = 0.72 } },
			{ nodeID = 10, name = "Refugio de la Zaga, Arathi", faction = 0, position = { x = 0.50, y = 0.40 } },
			{ nodeID = 11, name = "Fuera del mapa", faction = 0, position = { x = 1.4, y = 0.4 } },
			{ nodeID = 6, name = "Forjaz, Dun Morogh", faction = 2, position = { x = 0.47, y = 0.60 } }, -- repeated
		},
		[1414] = {
			{ nodeID = 23, name = "Orgrimmar, Durotar", faction = 1, position = { x = 0.58, y = 0.43 } },
		},
	}

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
				-- Forjaz and Stormwind occupy those points of the Eastern Kingdoms
				GetMapInfoAtPosition = function(mapID, x)
					if mapID == 1415 and x > 0.46 and x < 0.48 then return MAPS[1455] end
					if mapID == 1415 and x > 0.41 and x < 0.43 then return MAPS[1453] end
					return MAPS[mapID]
				end,
				-- world coordinates = continent coordinates; a city map covers a tenth of it
				GetWorldPosFromMapPos = function(_, pos) return 0, { GetXY = function() return pos.x, pos.y end } end,
				GetMapPosFromWorldPos = function(_, world, mapID)
					local x, y = world:GetXY()
					if mapID == 1455 then x, y = (x - 0.42) * 10, (y - 0.55) * 10 end
					if mapID == 1453 then x, y = (x - 0.37) * 10, (y - 0.67) * 10 end
					return 0, { GetXY = function() return x, y end }
				end,
			},
			C_TaxiMap = {
				GetTaxiNodesForMap = function(mapID) return NODES[mapID] or {} end,
				GetAllTaxiNodes = function() return {
					{ nodeID = 6, state = 0 }, -- current
					{ nodeID = 2, state = 1 }, -- reachable
					{ nodeID = 10, state = 2 }, -- unreachable: not known
				} end,
			},
			CreateVector2D = function(x, y) return { x = x, y = y } end,
			UnitFactionGroup = function() return "Alliance" end,
			GetLocale = function() return "esES" end,
		})
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Flights.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	local function entries()
		local byID = {}
		for _, entry in ipairs(ns.Registry.Get("flights").entries) do
			byID[entry.id] = entry
		end
		return byID
	end

	local function search(text)
		local names = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			names[i] = r.item.entry.name
		end
		return names
	end

	it("places each node in the city or zone at its point, with that map's position", function()
		local forjaz = entries()[6]
		assert.are.equal(1455, forjaz.mapID)
		assert.is_true(math.abs(forjaz.x - 0.5) < 1e-9 and math.abs(forjaz.y - 0.5) < 1e-9)
		assert.are.equal(1453, entries()[2].mapID)
		assert.are.equal(1415, entries()[10].mapID) -- no more precise map there
	end)

	it("leaves out the other faction, repeated nodes and points off the map", function()
		local byID = entries()
		assert.is_nil(byID[23]) -- Horde, for an Alliance player
		assert.is_nil(byID[11])
		local count = 0
		for _ in pairs(byID) do
			count = count + 1
		end
		assert.are.equal(3, count)
	end)

	it("shows unknown nodes dimmed until the flight window says they are known", function()
		assert.is_true(entries()[6].dimmed)
		assert.are.equal("Maestro de vuelo · aún desconocido", entries()[6].subtitle)
		assert.matches("Abre una vez el mapa de vuelo", entries()[6].details[1], 1, true)
		frame:Fire("TAXIMAP_OPENED")
		assert.is_nil(entries()[10].details) -- learnt once: no more hint, even for unknown ones
		assert.is_falsy(entries()[6].dimmed)
		assert.is_falsy(entries()[2].dimmed)
		assert.is_true(entries()[10].dimmed) -- unreachable: still unknown
		assert.are.same({ [6] = true, [2] = true }, MapScoutCharDB.knownTaxi)
		assert.are.equal("Maestro de vuelo", entries()[6].subtitle)
	end)

	it("is found by name, by @vuelo and by 'maestro de vuelo'", function()
		assert.are.same({ "Forjaz, Dun Morogh" }, search("forjaz"))
		assert.are.equal(3, #search("@vuelo"))
		assert.are.equal(3, #search("@flight"))
		assert.are.equal(3, #search("maestro de vuelo"))
		assert.are.same({ "Refugio de la Zaga, Arathi" }, search("@vuelo arathi"))
	end)

	it("stops listening to the flight window when turned off", function()
		ns.Registry.SetEnabled("flights", false)
		assert.is_nil(frame.events.TAXIMAP_OPENED)
	end)

	it("/ms debug flights lists nodes and their maps", function()
		SlashCmdList.MAPSCOUT("debug flights")
		assert.matches("3 maestros de vuelo (0 conocidos) para Alliance", table.concat(ChatLog, "\n"), 1, true)
		assert.matches("Forjaz, Dun Morogh -> Forjaz (1455)", table.concat(ChatLog, "\n"), 1, true)
	end)
end)
