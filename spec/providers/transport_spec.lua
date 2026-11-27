-- Providers/Transport.lua: boats, zeppelins and trams from the static data pack
describe("Providers/Transport.lua", function()
	local ns, frame, loads, faction
	local MAPS = dofile("spec/fixtures/maps.lua")
	local STRANGLETHORN = { mapID = 1434, name = "Vega de Tuercespina", mapType = 3, parentMapID = 1415 }
	local ZEPHRAS = { mapID = 2521, name = "Isla de Zephras", mapType = 2, parentMapID = 947 }

	local function loadRealPack()
		local pack = {}
		for _, path in ipairs({ "MapScout_Data_Forever/Pack.lua", "MapScout_Data_Forever/Transport.lua" }) do
			assert(loadfile(path))("MapScout_Data_Forever", pack)
		end
	end

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		loads = 0
		faction = nil -- no faction yet (as in the first moments of a login): everything
		StubGlobals({
			WOW_PROJECT_ID = 18,
			UnitFactionGroup = function() return faction end,
			GetLocale = function() return "esES" end,
			C_Map = {
				GetMapInfo = function(id)
					return MAPS[id] or (id == 1434 and STRANGLETHORN) or (id == 2521 and ZEPHRAS)
						or { mapID = id, name = "Zona " .. id, mapType = 3, parentMapID = 1415 } -- any other zone
				end,
				GetMapChildrenInfo = function() return {} end,
				-- a point of the Eastern Kingdoms map (the tram) is in Stormwind
				GetMapInfoAtPosition = function(mapID) return mapID == 1415 and MAPS[1453] or nil end,
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
			"API/Registry.lua", "Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Transport.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	local function entry(id)
		for _, e in ipairs(ns.Registry.Get("transport").entries) do
			if e.id == id then
				return e
			end
		end
	end

	local function search(text)
		local found = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			found[i] = r.item.entry
		end
		return found
	end

	local function has(list, id)
		for _, e in ipairs(list) do
			if e.id == id then
				return true
			end
		end
		return false
	end

	it("names each dock after its town, with where it goes in the subtitle", function()
		assert.are.equal(1, loads)
		local bootyBay = entry(2412)
		assert.are.equal("Bahía del Botín", bootyBay.name)
		assert.are.equal("Barco a Trinquete", bootyBay.subtitle)
		assert.are.equal("boats", bootyBay.category)
		assert.are.equal(1434, bootyBay.mapID)
		assert.are.equal(0.2567, bootyBay.x)
		local ratchet = entry(2411)
		assert.are.equal("Trinquete", ratchet.name)
		assert.are.equal("Barco a Bahía del Botín", ratchet.subtitle)
	end)

	it("lists both ends of every line, and every destination of a shared pier", function()
		local entries = ns.Registry.Get("transport").entries
		assert.are.equal(27, #entries)
		assert.are.equal("Zepelín a Orgrimmar", entry(2851).subtitle)
		assert.are.equal("Zepelín a Campamento Grom'Gol", entry(2852).subtitle)
		local menethil = entry(2951)
		assert.are.equal("Puerto de Menethil", menethil.name)
		assert.is_truthy(menethil.subtitle:find("Auberdine", 1, true))
		assert.is_truthy(menethil.subtitle:find("Costasur", 1, true))
	end)

	it("names a dock with no town after its map, and covers skyships and the tram", function()
		local zephras = entry(113982)
		assert.are.equal("Isla de Zephras", zephras.name)
		assert.are.equal("zeppelins", zephras.category)
		assert.is_truthy(zephras.subtitle:find("^Aeronave a "))
		local stormwind = entry(3691) -- on the Eastern Kingdoms map: placed in Stormwind by the game
		assert.are.equal("Ciudad de Ventormenta", stormwind.name)
		assert.are.equal(1453, stormwind.mapID)
		assert.are.equal("Tranvía a Forjaz", stormwind.subtitle)
		assert.are.equal("trams", stormwind.category)
		assert.are.equal("Zona 1438", entry(2931).name) -- Rut'theran: no town in the data
	end)

	it("finds a dock by where it is and by where it goes, in both languages", function()
		local bootyBay = search("bahia del botin")
		assert.is_true(has(bootyBay, 2412))
		assert.is_true(has(bootyBay, 2411)) -- the Ratchet dock goes there
		assert.is_true(has(search("booty bay"), 2412))
		assert.is_true(has(search("ratchet"), 2412))
		assert.is_true(has(search("tranvia"), 3691))
		assert.is_true(has(search("deeprun"), 3692))
	end)

	it("filters by kind with @ words", function()
		local boats = search("@barco")
		assert.is_true(#boats > 5)
		for _, e in ipairs(boats) do
			assert.are.equal("boats", e.category)
		end
		local zeppelins = search("@zeppelin")
		assert.is_true(has(zeppelins, 2851))
		assert.is_true(has(zeppelins, 114571)) -- skyships too
		assert.are.equal(2, #search("@tranvia"))
		assert.are.equal(27, #search("@transporte"))
	end)

	local function asFaction(side)
		faction = side
		ns.Registry.SetEnabled("transport", false)
		ns.Registry.SetEnabled("transport", true)
	end

	it("leaves out the docks of the other faction, also as destinations", function()
		asFaction("Alliance")
		assert.is_nil(entry(2851)) -- Grom'gol zeppelin
		assert.is_nil(entry(3021)) -- Orgrimmar - Undercity
		assert.is_truthy(entry(3691)) -- Deeprun Tram
		assert.is_truthy(entry(2921)) -- Menethil - Theramore
		assert.is_truthy(entry(2412)) -- Booty Bay: anyone
		assert.is_truthy(entry(114571)) -- a pending line: anyone until checked
		assert.is_false(has(search("orgrimmar"), 2852))
		asFaction("Horde")
		assert.is_truthy(entry(2851))
		assert.is_nil(entry(3691))
		assert.is_nil(entry(2921))
		assert.is_truthy(entry(2412))
		assert.is_truthy(entry(114571))
		assert.are.equal(0, #search("@tranvia"))
		for _, e in ipairs(ns.Registry.Get("transport").entries) do
			assert.is_nil(e.subtitle:find("Forjaz", 1, true)) -- no destination of the other faction
		end
	end)

	it("lets the data go when turned off, and loads it again when turned on", function()
		assert.are.same({ "transport" }, ns.Packs.Built())
		ns.Registry.SetEnabled("transport", false)
		assert.are.same({}, ns.Packs.Built())
		ns.Registry.SetEnabled("transport", true)
		assert.are.same({ "transport" }, ns.Packs.Built())
		assert.are.equal("Bahía del Botín", entry(2412).name)
	end)
end)
