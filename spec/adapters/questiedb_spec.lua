-- Adapters/QuestieDB.lua: available quests read from QuestieDB at runtime
describe("Adapters/QuestieDB.lua", function()
	local ns, frame, map
	local MAPS = dofile("spec/fixtures/maps.lua")
	local AREAS = { [1537] = "Forjaz", [1] = "Dun Morogh", [9999] = "Un sitio sin mapa" }

	-- A small QuestieDB: quests by id with their fields
	local QUESTS = {
		[1] = { name = "Lista", level = 5, req = 1, starter = { { 100 } }, text = { "Habla con Brann" } },
		[2] = { name = "Demasiado alta", level = 50, req = 45, starter = { { 100 } } },
		[3] = { name = "Otra clase", level = 5, req = 1, classes = 4, starter = { { 100 } } },
		[4] = { name = "Hecha", level = 5, req = 1, starter = { { 100 } } },
		[5] = { name = "En el registro", level = 5, req = 1, starter = { { 100 } } },
		[6] = { name = "Previa sin hacer", level = 5, req = 1, group = { 99 }, starter = { { 100 } } },
		[7] = { name = "Previa hecha", level = 5, req = 1, single = { 4, 98 }, starter = { { 100 } } },
		[8] = { name = "De la Horda", level = 5, req = 1, starter = { { 200 } } },
		[9] = { name = "Excluyente", level = 5, req = 1, exclusive = { 4 }, starter = { { 100 } } },
		[10] = { name = "De profesión", level = 5, req = 1, skill = { 164, 50 }, starter = { { 100 } } },
		[11] = { name = "De un objeto", level = 5, req = 1, starter = { nil, { 300 } } },
		[12] = { name = "Sin sitio", level = 5, req = 1, starter = { { 400 } } },
		[13] = { name = "De temporada", level = 10, req = 1, sort = -22, starter = { { 100 } } },
		[14] = { name = "Muy alta", level = 21, req = 1, starter = { { 100 } } },
		[15] = { name = "Gris", level = 1, req = 1, starter = { { 100 } } },
		[16] = { name = "Algo alta", level = 20, req = 1, starter = { { 100 } } },
		[17] = { name = "Sin nivel", level = 0, req = 0, starter = { { 100 } } },
		[18] = { name = "Repetible", level = 10, req = 1, special = 1, starter = { { 100 } } },
	}
	local NPCS = {
		[100] = { name = "Brann", friendly = "AH", spawns = { [1537] = { { 30, 60 } } } },
		[200] = { name = "Grunt", friendly = "H", spawns = { [1] = { { 50, 50 } } } },
		[400] = { name = "Perdido", friendly = "AH", spawns = { [9999] = { { 10, 10 } } } },
	}

	local function fakeDB(contract)
		local function field(name)
			return function(id) return QUESTS[id] and QUESTS[id][name] end
		end
		return {
			contractVersion = contract,
			RequireContract = function(n) return n == contract end,
			Enum = { raceMaskById = { [3] = 4 } }, -- dwarf
			Quest = {
				GetAllIds = function()
					local ids = {}
					for id in pairs(QUESTS) do ids[#ids + 1] = id end
					table.sort(ids)
					return ids
				end,
				name = field("name"), questLevel = field("level"), requiredLevel = field("req"),
				requiredMaxLevel = field("max"), requiredRaces = field("races"), requiredClasses = field("classes"),
				requiredSkill = field("skill"), preQuestGroup = field("group"), preQuestSingle = field("single"),
				exclusiveTo = field("exclusive"), startedBy = field("starter"), objectivesText = field("text"),
				zoneOrSort = field("sort"), specialFlags = field("special"),
			},
			Npc = {
				name = function(id) return NPCS[id].name end,
				friendlyToFaction = function(id) return NPCS[id].friendly end,
				spawns = function(id) return NPCS[id].spawns end,
			},
			Object = {
				name = function() return "Cartel de se busca" end,
				spawns = function() return { [1] = { { 40, 40 } } } end,
			},
		}
	end

	local function load(db)
		ResetWoW()
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function(root)
					if root ~= 947 then return {} end
					local list = {}
					for _, info in pairs(MAPS) do list[#list + 1] = info end
					return list
				end,
				GetAreaInfo = function(areaID) return AREAS[areaID] end,
			},
			C_QuestLog = {
				IsQuestFlaggedCompleted = function(id) return id == 4 end,
				GetNumQuestLogEntries = function() return 1 end,
				GetInfo = function() return { questID = 5, title = "En el registro" } end,
			},
			UnitLevel = function() return 10 end,
			UnitQuestTrivialLevelRange = function() return 6 end, -- gray: 7+ levels below
			UnitRace = function() return "Enano", "Dwarf", 3 end,
			UnitClass = function() return "Guerrero", "WARRIOR", 1 end,
			UnitFactionGroup = function() return "Alliance" end,
			GetLocale = function() return "esES" end,
			LibQuestieDB = db,
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
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Adapters/QuestieDB.lua", "UI/Map.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	local function build()
		for _ = 1, 20 do
			if PendingTimers() == 0 then
				break
			end
			RunTimers()
		end
	end

	local function names()
		local list = {}
		for _, entry in ipairs(ns.Registry.Get("questiedb").entries) do
			list[#list + 1] = entry.name
		end
		table.sort(list)
		return list
	end

	it("does nothing without QuestieDB or with a contract it can't read", function()
		load(nil)
		assert.is_nil(ns.Registry.Get("questiedb"))
		load(fakeDB(5))
		assert.is_nil(ns.Registry.Get("questiedb"))
	end)

	it("finds the quests the character can take now", function()
		load(fakeDB(4))
		build()
		-- not "De temporada" (seasonal), "Muy alta" (11 above) nor "Gris" (9 below);
		-- "Algo alta" (10 above) is still in
		assert.are.same({ "Algo alta", "De un objeto", "Lista", "Previa hecha" }, names())
		local stats = ns.QuestieAdapter.stats
		assert.are.equal(18, stats.quests) -- "Sin nivel" (level 0) and "Repetible" are left out too
		assert.are.equal(2, stats.unplaced) -- the Horde giver and the one with no known map
	end)

	it("places each quest where its giver is, on the matching zone", function()
		load(fakeDB(4))
		build()
		local entry = ns.Registry.Get("questiedb").entries[1]
		assert.are.equal("Lista", entry.name)
		assert.are.same({ 1455, 0.3, 0.6 }, { entry.mapID, entry.x, entry.y })
		assert.are.equal("Disponible · Nivel 5 · Brann", entry.subtitle)
		assert.are.same({ "Habla con Brann", "La da: Brann" }, entry.details)
	end)

	it("prefers the game's title in the player's language", function()
		load(fakeDB(4))
		_G.C_QuestLog.GetTitleForQuestID = function(id) return id == 1 and "Lista (del juego)" or nil end
		ns.QuestieAdapter.Build()
		build()
		assert.are.same({ "Algo alta", "De un objeto", "Lista (del juego)", "Previa hecha" }, names())
	end)

	it("builds in steps without freezing", function()
		load(fakeDB(4))
		ns.QuestieAdapter.STEP = 3
		ns.QuestieAdapter.Build() -- replaces the build started at login
		local steps = 0
		while PendingTimers() > 0 do
			RunTimers()
			steps = steps + 1
		end
		ns.QuestieAdapter.STEP = 200
		assert.is_true(steps >= 6) -- 18 quests, 3 per step
		assert.are.equal(4, #ns.Registry.Get("questiedb").entries)
	end)

	it("is found with @disponible and @mision", function()
		load(fakeDB(4))
		build()
		assert.are.equal(4, #(ns.Engine.Search(ns.Query.Parse("@disponible"))))
		assert.are.equal(4, #(ns.Engine.Search(ns.Query.Parse("@mision"))))
		assert.are.equal("Lista", (ns.Engine.Search(ns.Query.Parse("brann")))[1].item.entry.name)
	end)

	it("rebuilds when something changes, waiting for the map if it is closed", function()
		load(fakeDB(4))
		build()
		frame:Fire("QUEST_ACCEPTED")
		assert.are.equal(0, PendingTimers()) -- map closed: later
		map:Show()
		assert.is_true(PendingTimers() > 0) -- building again
		build()
		map:Show()
		frame:Fire("PLAYER_LEVEL_UP")
		assert.are.equal(1, PendingTimers()) -- the pause before rebuilding
	end)
end)
