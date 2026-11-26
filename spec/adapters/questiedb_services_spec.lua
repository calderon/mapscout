-- Adapters/QuestieDBServices.lua: services from QuestieDB's NPC flags
describe("Adapters/QuestieDBServices.lua", function()
	local ns
	local MAPS = dofile("spec/fixtures/maps.lua")
	local FLAGS = { VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, BANKER = 256, PETITIONER = 512,
		TABARD_DESIGNER = 1024, BATTLEMASTER = 2048, AUCTIONEER = 4096, STABLEMASTER = 8192, REPAIR = 16384 }
	local HERE = { [1537] = { { 30, 60 } } }
	local NPCS = {
		[1] = { name = "Olthran", flags = 256, friendly = "AH", spawns = HERE, sub = "Banquero" },
		[2] = { name = "Tabernero Brebefuego", flags = 128 + 4, friendly = "AH", spawns = HERE },
		[3] = { name = "Herrero Rudo", flags = 16384 + 4, friendly = "AH", spawns = HERE },
		[4] = { name = "Banquero de la Horda", flags = 256, friendly = "H", spawns = HERE },
		[5] = { name = "Grifero", flags = 8, friendly = "AH", spawns = HERE },
		[6] = { name = "Sin sitio", flags = 256, friendly = "AH" },
		[7] = { name = "Bixi", flags = 16, friendly = "AH", spawns = HERE, sub = "Instructora de herrería" },
		[8] = { name = "Vendedora", flags = 4, friendly = "AH", spawns = HERE },
		[9] = { name = "Nadie", flags = 0, friendly = "AH", spawns = HERE },
	}

	local function load(withDB)
		ResetWoW()
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
				subName = function(id) return NPCS[id].sub end,
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
				GetAreaInfo = function(areaID) return areaID == 1537 and "Forjaz" or nil end,
			},
			C_QuestLog = { GetNumQuestLogEntries = function() return 0 end },
			UnitLevel = function() return 10 end,
			UnitRace = function() return "Enano", "Dwarf", 3 end,
			UnitClass = function() return "Guerrero", "WARRIOR", 1 end,
			UnitFactionGroup = function() return "Alliance" end,
			GetLocale = function() return "esES" end,
			LibQuestieDB = db,
		})
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua", "Search/Query.lua",
			"Search/Index.lua", "Search/Engine.lua", "Adapters/QuestieDB.lua", "Adapters/QuestieDBServices.lua", "UI/Map.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		for _ = 1, 20 do
			if PendingTimers() == 0 then break end
			RunTimers()
		end
	end

	local function byName()
		local list = {}
		for _, entry in ipairs(ns.Registry.Get("questiedb-services").entries) do
			list[entry.name] = entry
		end
		return list
	end

	local function search(text)
		local names = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			names[i] = r.item.entry.name
		end
		table.sort(names)
		return names
	end

	it("does nothing without QuestieDB", function()
		load(false)
		assert.is_nil(ns.Registry.Get("questiedb-services"))
	end)

	it("lists friendly NPCs with a service, placed where they stand", function()
		load(true)
		local list = byName()
		assert.are.same({ "Bixi", "Herrero Rudo", "Olthran", "Tabernero Brebefuego", "Vendedora" },
			(function() local n = {} for k in pairs(list) do n[#n + 1] = k end table.sort(n) return n end)())
		assert.are.same({ 1455, 0.3, 0.6 }, { list.Olthran.mapID, list.Olthran.x, list.Olthran.y })
		assert.are.equal(5, ns.QuestieServices.stats.services)
	end)

	it("puts each NPC in its first service, named by its subname or the service", function()
		load(true)
		local list = byName()
		assert.are.equal("bank", list.Olthran.category)
		assert.are.equal("Banquero", list.Olthran.subtitle)
		assert.are.equal("inn", list["Tabernero Brebefuego"].category) -- also a vendor
		assert.are.equal("Posada", list["Tabernero Brebefuego"].subtitle)
		assert.are.equal("repair", list["Herrero Rudo"].category)
		assert.are.equal("Instructora de herrería", list.Bixi.subtitle)
	end)

	it("is found with the service @ words, and by typing any of its services", function()
		load(true)
		assert.are.same({ "Olthran" }, search("@banco"))
		assert.are.same({ "Olthran" }, search("@bank"))
		assert.are.same({ "Tabernero Brebefuego" }, search("@posada"))
		assert.are.same({ "Vendedora" }, search("@vendedor")) -- category: the vendor-only NPC
		assert.are.same({ "Herrero Rudo", "Tabernero Brebefuego", "Vendedora" }, search("vendedor")) -- typed: all that sell
		-- by subname (first; "Herrero" follows as a near match: few results allow typos)
		assert.are.equal("Bixi", (ns.Engine.Search(ns.Query.Parse("herreria")))[1].item.entry.name)
		assert.are.equal(5, #search("@servicio"))
	end)
end)
