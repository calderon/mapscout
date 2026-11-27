-- Adapters/QuestieDBSpiritHealers.lua: spirit healers from QuestieDB's NPC flags
describe("Adapters/QuestieDBSpiritHealers.lua", function()
	local ns
	local MAPS = dofile("spec/fixtures/maps.lua")
	local FLAGS = { VENDOR = 4, TRAINER = 16, SPIRIT_HEALER = 32, BANKER = 256 }
	local AREAS = { [1537] = "Forjaz", [1] = "Dun Morogh" }
	local NPCS = {
		-- one NPC at several graveyards; an area without a map and a spawn without a place are skipped
		[6491] = { name = "Spirit Healer", flags = 32, friendly = "AH",
			spawns = { [1] = { { 46, 52 }, { 30, 70 } }, [1537] = { { 60, 40 }, { -1, -1 } }, [999] = { { 10, 10 } } } },
		[2] = { name = "Banker", flags = 256, friendly = "AH", spawns = { [1537] = { { 30, 60 } } } },
		[3] = { name = "Horde healer", flags = 32, friendly = "H", spawns = { [1537] = { { 20, 20 } } } },
		[4] = { name = "Healer of all", flags = 32 + 4, spawns = { [1] = { { 10, 20 } } } },
		[5] = { name = "Nowhere", flags = 32, friendly = "AH" },
	}

	-- our pack: the graveyard outside Ironforge (QuestieDB's 46, 52 is the same one), and one QuestieDB lacks
	local OWN = { maps = { [1426] = { { 4650, 5230 }, { 8000, 8000 } } } }

	local function load(withDB, withOwn)
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		local db = withDB and {
			RequireContract = function(n) return n == 4 end,
			contractVersion = 4,
			Enum = { npcFlags = FLAGS, raceMaskById = {} },
			Quest = { GetAllIds = function() return {} end },
			Npc = {
				GetAllIds = function()
					local ids = {}
					for id in pairs(NPCS) do ids[#ids + 1] = id end
					table.sort(ids)
					return ids
				end,
				name = function(id) return NPCS[id].name end,
				npcFlags = function(id) return NPCS[id].flags end,
				friendlyToFaction = function(id) return NPCS[id].friendly end,
				spawns = function(id) return NPCS[id].spawns end,
				subName = function() return nil end,
			},
		} or nil
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
			C_QuestLog = { GetNumQuestLogEntries = function() return 0 end },
			UnitLevel = function() return 10 end,
			UnitRace = function() return "Enano", "Dwarf", 3 end,
			UnitClass = function() return "Guerrero", "WARRIOR", 1 end,
			UnitFactionGroup = function() return "Alliance" end,
			GetLocale = function() return "esES" end,
			LibQuestieDB = db,
			WOW_PROJECT_ID = 18,
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			C_AddOns = {
				LoadAddOn = function()
					rawset(_G, "MapScoutDataForever", { categories = {
						spirithealers = function() return withOwn and OWN or { maps = {} } end,
					} })
					return true
				end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function() end,
			},
		})
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "Core/Packs.lua", "API/MapScoutAPI.lua",
			"API/Registry.lua", "Search/Query.lua", "Search/Index.lua", "Search/Engine.lua",
			"Providers/SpiritHealers.lua", "Adapters/QuestieDB.lua", "Adapters/QuestieDBSpiritHealers.lua",
			"UI/Map.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		for _ = 1, 20 do
			if PendingTimers() == 0 then break end
			RunTimers()
		end
	end

	local function settle()
		for _ = 1, 20 do
			if PendingTimers() == 0 then break end
			RunTimers()
		end
	end

	local function entries()
		local record = ns.Registry.Get("spirithealers")
		return record and record.entries or {}
	end

	local function search(text)
		local list = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			local entry = r.item.entry
			list[i] = ("%s %d %.2f %.2f"):format(entry.subtitle, entry.mapID, entry.x, entry.y)
		end
		table.sort(list)
		return list
	end

	local ALL = {
		"Dun Morogh 1426 0.10 0.20", "Dun Morogh 1426 0.30 0.70", "Dun Morogh 1426 0.46 0.52", "Forjaz 1455 0.60 0.40",
	}

	it("does nothing without QuestieDB: the option is ours, with our data only", function()
		load(false, true)
		assert.is_nil(ns.QuestieSpiritHealers)
		assert.are.same({ "Dun Morogh 1426 0.47 0.52", "Dun Morogh 1426 0.80 0.80" }, search("cementerio"))
	end)

	it("has no option of its own: its spirit healers are in Spirit healers", function()
		load(true)
		local record = ns.Registry.Get("spirithealers")
		assert.is_truthy(record)
		assert.is_nil(record.spec.parent)
		assert.is_nil(ns.Registry.Get("services"))
	end)

	it("leaves out a spirit healer where our pack has that graveyard, and adds the others", function()
		load(true, true)
		assert.are.same({ "Dun Morogh 1426 0.10 0.20", "Dun Morogh 1426 0.30 0.70", "Dun Morogh 1426 0.47 0.52",
			"Dun Morogh 1426 0.80 0.80", "Forjaz 1455 0.60 0.40" }, search("cementerio"))
	end)

	it("gives one result per spawn of each spirit healer the player can use", function()
		load(true)
		assert.are.equal(4, #entries())
		for _, entry in ipairs(entries()) do
			assert.are.equal("Ángel de la resurrección", entry.name)
		end
	end)

	it("is found by its words and its @ words, in Spanish and English", function()
		load(true)
		for _, text in ipairs({ "ángel", "angel de la resurreccion", "cementerio", "spirit healer", "graveyard",
			"@angel", "@cementerio", "@spirithealer", "@graveyard" }) do
			assert.are.same(ALL, search(text), text)
		end
		assert.are.same({ "Forjaz 1455 0.60 0.40" }, search("@angel forjaz"))
	end)

	it("follows the Spirit healers toggle", function()
		load(true)
		ns.Registry.SetEnabled("spirithealers", false)
		settle()
		assert.are.same({}, search("cementerio"))
		assert.are.same({}, ns.Registry.Get("spirithealers").entries or {})
		ns.Registry.SetEnabled("spirithealers", true)
		settle()
		assert.are.same(ALL, search("cementerio"))
	end)
end)
