-- Providers/Services.lua: city services from the static data pack
describe("Providers/Services.lua", function()
	local ns, frame, loads, locale, faction
	local MAPS = dofile("spec/fixtures/maps.lua")

	local PACK = {
		maps = {
			[1455] = {
				{ "bank", 3515, 6116, "Alliance", "esES", 1 },
				{ "mailbox", 3316, 6521, "", "", 0 },
				{ "stable", 6937, 8358, "Alliance", "esES", 2 },
				{ "barber", 2670, 5028, "Alliance", "esES", 4 },
				{ "battle", 6959, 9072, "Alliance", "esES", 5, "alterac" },
				{ "battle", 7099, 8870, "Alliance", "esES", 6, "warsong" },
			},
			[1454] = {
				{ "bank", 4000, 4000, "Horde", "esES", 3 },
			},
		},
		names = { esES = { "Las Arcas", "Ulbrek Manofuego", "Banco de Orgrimmar", "Peluquería de Forjaz",
			"Glordrum Barbacerada", "Lylandris" } },
	}

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		loads, locale, faction = 0, "esES", "Alliance"
		StubGlobals({
			WOW_PROJECT_ID = 18,
			GetLocale = function() return locale end,
			UnitFactionGroup = function() return faction end,
			C_Map = {
				GetMapInfo = function(id)
					return MAPS[id] or { mapID = id, name = "Orgrimmar", mapType = 3, parentMapID = 1414 }
				end,
				GetMapChildrenInfo = function() return {} end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			C_AddOns = {
				LoadAddOn = function()
					loads = loads + 1
					rawset(_G, "MapScoutDataForever", { categories = { services = function() return PACK end } })
					return true
				end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function() end,
			},
		})
	end)

	local function start()
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Locales/enUS.lua", "Locales/esES.lua", "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua",
			"Core/Packs.lua", "API/MapScoutAPI.lua", "API/Registry.lua", "Search/Query.lua", "Search/Index.lua",
			"Search/Engine.lua", "Providers/Services.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	local function entries()
		return ns.Registry.Get("services").entries
	end

	local function entry(id)
		for _, e in ipairs(entries()) do
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

	it("names each result after its service, with the place the game gave it", function()
		start()
		assert.are.equal(1, loads)
		local bank = entry("bank:1455:1")
		assert.are.equal("Banco", bank.name)
		assert.are.equal("Las Arcas", bank.subtitle)
		assert.are.equal("bank", bank.category)
		assert.are.equal(1455, bank.mapID)
		assert.are.equal(0.3515, bank.x)
		assert.are.equal("Forjaz", entry("mailbox:1455:2").subtitle) -- no place name: its city
	end)

	it("leaves out what only the other faction can use, but not mailboxes", function()
		start()
		assert.are.equal(6, #entries())
		assert.is_nil(entry("bank:1454:1"))
	end)

	it("does the same the other way round for a Horde player", function()
		faction = "Horde"
		start()
		assert.is_truthy(entry("bank:1454:1"))
		assert.is_truthy(entry("mailbox:1455:2"))
		assert.is_nil(entry("bank:1455:1"))
	end)

	it("shows place names only in the language they were harvested in", function()
		locale = "enUS"
		start()
		local bank = entry("bank:1455:1")
		assert.are.equal("Bank", bank.name)
		assert.are.equal("Forjaz", bank.subtitle)
		locale = "esMX"
		ns.Registry.SetEnabled("services", false)
		ns.Registry.SetEnabled("services", true)
		assert.are.equal("Las Arcas", entry("bank:1455:1").subtitle)
	end)

	it("is found by service words in English and Spanish, and by @ words", function()
		start()
		for _, text in ipairs({ "banco", "bank", "banquero", "las arcas" }) do
			local found = search(text)
			assert.are.equal("bank:1455:1", found[1] and found[1].id, text)
		end
		assert.are.equal("mailbox:1455:2", search("buzon")[1].id)
		assert.are.equal("mailbox:1455:2", search("mailbox")[1].id)
		local all = search("@servicio")
		assert.are.equal(6, #all)
		local mail = search("@buzon")
		assert.are.equal(1, #mail)
		assert.are.equal("mailbox", mail[1].category)
	end)

	it("names battlemasters after their battleground, and finds them by it", function()
		start()
		local alterac = entry("battle:1455:5")
		assert.are.equal("Maestro de batalla del Valle de Alterac", alterac.name)
		assert.are.equal("Glordrum Barbacerada", alterac.subtitle)
		assert.are.equal("battle", alterac.category)
		assert.are.equal("battle:1455:5", search("alterac")[1].id)
		assert.are.equal("battle:1455:6", search("garganta grito de guerra")[1].id)
		assert.are.equal("battle:1455:6", search("wsg")[1].id)
		assert.are.equal(2, #search("@battlemaster"))
		assert.are.equal(2, #search("@batalla"))
	end)

	it("finds barbers", function()
		start()
		local barber = entry("barber:1455:4")
		assert.are.equal("Peluquería", barber.name)
		assert.are.equal("Peluquería de Forjaz", barber.subtitle)
		for _, text in ipairs({ "peluqueria", "barber", "barbero", "@peluqueria" }) do
			local found = search(text)
			assert.are.equal("barber:1455:4", found[1] and found[1].id, text)
		end
	end)

	it("knows which services the pack has on each map", function()
		start()
		local Services = ns.Services
		assert.is_true(Services.Covers(PACK, 1455, "bank"))
		assert.is_true(Services.Covers(PACK, 1454, "bank")) -- either faction
		assert.is_false(Services.Covers(PACK, 1455, "inn"))
		assert.is_false(Services.Covers(PACK, 1, "bank"))
		assert.is_false(Services.Covers(nil, 1455, "bank"))
	end)

	it("lets the pack go when turned off", function()
		start()
		ns.Registry.SetEnabled("services", false)
		assert.are.same({}, ns.Packs.Built())
		assert.are.equal(0, #entries())
	end)
end)
