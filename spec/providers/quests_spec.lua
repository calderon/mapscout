-- Providers/Quests.lua: the quests in the log, placed where the game shows them
describe("Providers/Quests.lua", function()
	local ns, frame, map, builds
	local MAPS = dofile("spec/fixtures/maps.lua")

	local LOG = {
		{ title = "Reinos del Este", isHeader = true },
		{ title = "Los muertos sin descanso", questID = 101, level = 15 },
		{ title = "Reliquias importantes", questID = 102, level = 15 },
		{ title = "Sin sitio", questID = 103, level = 10 },
		{ title = "Oculta", questID = 104, isHidden = true },
	}
	local OBJECTIVES = {
		[101] = { { text = "12/15 Aparición enfurecida", finished = false }, { text = "1/1 Llave", finished = true } },
		[102] = { { text = "Reliquia: 1/1", finished = true } },
		[103] = {},
	}

	before_each(function()
		ResetWoW()
		builds = 0
		local children = {}
		for _, info in pairs(MAPS) do
			children[#children + 1] = info
		end
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function(root) return root == 947 and children or {} end,
				GetMapInfoAtPosition = function(mapID, x)
					if mapID == 1415 and x > 0.46 and x < 0.48 then return MAPS[1455] end
					return MAPS[mapID]
				end,
				GetWorldPosFromMapPos = function(_, pos) return 0, { GetXY = function() return pos.x, pos.y end } end,
				GetMapPosFromWorldPos = function(_, world)
					local x, y = world:GetXY()
					return 0, { GetXY = function() return (x - 0.42) * 10, (y - 0.55) * 10 end }
				end,
			},
			C_QuestLog = {
				GetNumQuestLogEntries = function() builds = builds + 1; return #LOG end,
				GetInfo = function(i) return LOG[i] end,
				IsComplete = function(questID) return questID == 102 end,
				GetQuestObjectives = function(questID) return OBJECTIVES[questID] end,
				GetQuestsOnMap = function(mapID)
					if mapID ~= 1415 then return {} end
					return { { questID = 101, x = 0.47, y = 0.60 }, { questID = 102, x = 0.30, y = 0.30 } }
				end,
			},
			CreateVector2D = function(x, y) return { x = x, y = y } end,
			GetLocale = function() return "esES" end,
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		map.shown = false
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Quests.lua", "UI/Map.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	local function entries()
		local byID = {}
		for _, entry in ipairs(ns.Registry.Get("quests").entries) do
			byID[entry.id] = entry
		end
		return byID
	end

	it("lists the quests of the log, not headers nor hidden ones", function()
		local byID = entries()
		assert.is_table(byID[101])
		assert.is_table(byID[102])
		assert.is_table(byID[103])
		assert.is_nil(byID[104])
		local count = 0
		for _ in pairs(byID) do
			count = count + 1
		end
		assert.are.equal(3, count)
	end)

	it("says the level and the first objective to do, or that it is ready", function()
		assert.are.equal("Nivel 15 · 12/15 Aparición enfurecida", entries()[101].subtitle)
		assert.are.equal("Nivel 15 · Lista para entregar", entries()[102].subtitle)
		assert.are.equal("Nivel 10 · En curso", entries()[103].subtitle)
		assert.are.equal(ns.Quests.ICON_READY, entries()[102].icon)
	end)

	it("lists every objective in the tooltip, done ones in grey", function()
		assert.are.same({ "12/15 Aparición enfurecida", "|cff8080801/1 Llave|r" }, entries()[101].details)
	end)

	it("places each quest where the game shows it, in the most precise map", function()
		local quest = entries()[101]
		assert.are.equal(1455, quest.mapID) -- Forjaz, not the continent
		assert.is_true(math.abs(quest.x - 0.5) < 1e-9)
		assert.are.equal(1415, entries()[102].mapID)
		local nowhere = entries()[103]
		assert.is_nil(nowhere.mapID)
		assert.are.equal("El juego no indica en el mapa dónde está esta misión.", nowhere.details[#nowhere.details])
	end)

	it("is found by title and by @mision", function()
		local results = ns.Engine.Search(ns.Query.Parse("@mision"))
		assert.are.equal(3, #results)
		results = ns.Engine.Search(ns.Query.Parse("reliquias"))
		assert.are.equal("Reliquias importantes", results[1].item.entry.name)
	end)

	it("with the map closed, waits for it to open to rebuild", function()
		local before = builds
		frame:Fire("QUEST_LOG_UPDATE")
		frame:Fire("QUEST_ACCEPTED")
		assert.are.equal(before, builds)
		assert.are.equal(0, PendingTimers())
		map:Show()
		assert.are.equal(before + 1, builds)
	end)

	it("with the map open, rebuilds once after a burst of events", function()
		map:Show()
		local before = builds
		for _ = 1, 5 do
			frame:Fire("QUEST_LOG_UPDATE")
		end
		assert.are.equal(1, PendingTimers())
		RunTimers()
		assert.are.equal(before + 1, builds)
	end)

	it("listens to nothing while turned off", function()
		ns.Registry.SetEnabled("quests", false)
		assert.is_nil(frame.events.QUEST_LOG_UPDATE)
		assert.is_nil(frame.events.QUEST_TURNED_IN)
	end)
end)
