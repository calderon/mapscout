-- Providers/Dungeons.lua: dungeons and raids from the static data pack
describe("Providers/Dungeons.lua", function()
	local ns, frame, loads
	local MAPS = dofile("spec/fixtures/maps.lua")
	local WESTFALL = { mapID = 1436, name = "Páramos de Poniente", mapType = 3, parentMapID = 1415 }

	local function loadRealPack()
		local pack = {}
		for _, path in ipairs({ "MapScout_Data_Forever/Pack.lua", "MapScout_Data_Forever/Dungeons.lua" }) do
			assert(loadfile(path))("MapScout_Data_Forever", pack)
		end
	end

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		loads = 0
		StubGlobals({
			WOW_PROJECT_ID = 18,
			GetLocale = function() return "esES" end,
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function() return {} end,
				-- every point of the Eastern Kingdoms is in Westfall, here
				GetMapInfoAtPosition = function(mapID) return mapID == 1415 and WESTFALL or nil end,
				GetWorldPosFromMapPos = function(_, v) return 0, v end,
				GetMapPosFromWorldPos = function(_, v) return 0, { GetXY = function() return v.x / 2, v.y / 2 end } end,
			},
			CreateVector2D = function(x, y) return { x = x, y = y } end,
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			C_AddOns = {
				LoadAddOn = function()
					loads = loads + 1
					loadRealPack()
					return true
				end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function() end,
			},
		})
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "Core/Packs.lua", "API/MapScoutAPI.lua",
			"API/Registry.lua", "Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Dungeons.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	local function entry(id)
		for _, e in ipairs(ns.Registry.Get("dungeons").entries) do
			if e.id == id then
				return e
			end
		end
	end

	local function search(text)
		local names = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			names[i] = r.item.entry.name
		end
		return names
	end

	it("loads the pack once and lists dungeons and raids in the player's language", function()
		assert.are.equal(1, loads)
		local sfk = entry(33)
		assert.are.equal("Castillo de Colmillo Oscuro", sfk.name)
		assert.are.equal("Mazmorra · nivel 18", sfk.subtitle)
		assert.are.equal("dungeons", sfk.category)
		local onyxia = entry(249)
		assert.are.equal("Guarida de Onyxia", onyxia.name)
		assert.are.equal("Banda · nivel 60", onyxia.subtitle)
		assert.are.equal("raids", onyxia.category)
		assert.are.equal("Banda", entry(509).subtitle) -- no known level
	end)

	it("places a continent point in its zone, and keeps a zone point", function()
		local scholomance = entry(289) -- stored on the Eastern Kingdoms map
		assert.are.equal(1436, scholomance.mapID)
		assert.are.equal(0.5271 / 2, scholomance.x)
		local zg = entry(309) -- stored on Stranglethorn Vale
		assert.are.equal(1434, zg.mapID)
		assert.are.equal(0.5399, zg.x)
	end)

	it("finds an unconfirmed entrance by name, with no place and saying so", function()
		local naxx = ns.Dungeons.Entries({
			entrances = { [533] = { "raid", 0, 0, 0, 60 } },
			names = { enUS = { [533] = "Naxxramas" } },
		})[1] -- every entrance in the pack has a place now
		assert.are.equal("Naxxramas", naxx.name)
		assert.are.equal("Banda · nivel 60 · entrada por confirmar", naxx.subtitle)
		assert.is_nil(naxx.mapID)
		assert.are.same({ ns.L.DUNGEONS_NO_ENTRANCE }, naxx.details)
	end)

	it("places a raid with no door outside on the dungeon it is entered from, and says so", function()
		local core, depths = entry(409), entry(230)
		assert.are.equal("Banda · nivel 60", core.subtitle)
		assert.are.same({ depths.mapID, depths.x, depths.y }, { core.mapID, core.x, core.y })
		assert.are.same({ "Se entra desde Profundidades de Roca Negra." }, core.details)
		assert.are.same({ "Se entra desde Cumbre de Roca Negra (Superior)." }, entry(469).details)
	end)

	it("places Forever's new dungeons", function()
		local alcaz = entry(2994) -- from DungeonJournal, with its author's permission
		assert.are.equal("Mazmorra · nivel 48", alcaz.subtitle)
		assert.are.equal(1445, alcaz.mapID)
	end)

	it("never leaves an entrance on the map of a building or an instance", function()
		local inner = { mapID = 1585, name = "Montaña Roca Negra", mapType = 5, parentMapID = 1436 }
		local getInfo = C_Map.GetMapInfo
		StubGlobals({ C_Map = setmetatable({
			GetMapInfo = function(id) return id == 1585 and inner or id == 1436 and WESTFALL or getInfo(id) end,
			GetMapInfoAtPosition = function() return inner end,
		}, { __index = C_Map }) })
		local mapID, x, y = ns.Dungeons.Place(1415, 0.4, 0.6)
		assert.are.equal(1436, mapID) -- its zone, not Blackrock Mountain
		assert.are.equal(0.2, x)
		assert.are.equal(0.3, y)
	end)

	it("keeps a zone point on its zone, even where the game sees the zone next to it", function()
		local badlands = { mapID = 1418, name = "Tierras Inhóspitas", mapType = 3, parentMapID = 1415 }
		local getInfo = C_Map.GetMapInfo
		StubGlobals({ C_Map = setmetatable({
			GetMapInfo = function(id) return id == 1418 and badlands or getInfo(id) end,
			GetMapInfoAtPosition = function() return WESTFALL end,
		}, { __index = C_Map }) })
		local mapID, x, y = ns.Dungeons.Place(1418, 0.443, 0.12) -- Uldaman, at the north edge
		assert.are.equal(1418, mapID)
		assert.are.equal(0.443, x)
		assert.are.equal(0.12, y)
	end)

	it("shows every door of an instance with several, each one as \"Name (wing)\"", function()
		assert.is_nil(entry(189)) -- no single result for the Monastery
		local library = entry("189:library")
		assert.are.equal("Monasterio Escarlata (Biblioteca)", library.name)
		assert.are.equal("Mazmorra · nivel 30", library.subtitle)
		assert.are.equal(1420, library.mapID)
		assert.are.equal(0.8535, library.x)
		assert.are.equal("Stratholme (Puerta de servicio)", entry("329:service").name)
		local wings = search("monasterio escarlata")
		assert.are.equal(4, #wings)
		assert.are.same({ "Monasterio Escarlata (Armería)" }, search("scarlet monastery armory"))
		assert.are.equal(3, #search("la masacre"))
	end)

	it("lists the doors of one instance in their order", function()
		local entries = ns.Dungeons.Entries({
			entrances = { [189] = { "dungeon", 0, 0, 0, 30 }, [36] = { "dungeon", 1436, 4250, 7170, 16 } },
			doors = { [189] = { { "library", 1420, 8535, 3239 }, { "graveyard", 1420, 8480, 3037 } } },
			names = { enUS = { [189] = "Scarlet Monastery", [36] = "Deadmines" } },
		})
		local ids = {}
		for i, e in ipairs(entries) do
			ids[i] = e.id
		end
		assert.are.same({ 36, "189:library", "189:graveyard" }, ids)
	end)

	it("finds them by name in both languages and by @ words", function()
		assert.are.equal("Minas de la Muerte", search("minas de la muerte")[1])
		assert.are.equal("Minas de la Muerte", search("deadmines")[1])
		local raids = search("@banda")
		assert.is_true(#raids >= 5)
		for _, name in ipairs(raids) do
			assert.is_not_equal("Minas de la Muerte", name)
		end
		assert.is_true(#search("@mazmorra") > #raids)
	end)

	it("lets the data go when turned off, and loads it again when turned on", function()
		assert.are.same({ "dungeons" }, ns.Packs.Built())
		ns.Registry.SetEnabled("dungeons", false)
		assert.are.same({}, ns.Packs.Built())
		ns.Registry.SetEnabled("dungeons", true)
		assert.are.same({ "dungeons" }, ns.Packs.Built())
		assert.are.equal("Minas de la Muerte", entry(36).name)
	end)
end)
