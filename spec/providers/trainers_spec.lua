-- Providers/Trainers.lua: trainers from the static data pack
describe("Providers/Trainers.lua", function()
	local ns, frame, loads, locale, faction, class
	local MAPS = dofile("spec/fixtures/maps.lua")

	local PACK = {
		maps = {
			[1455] = {
				{ "class", "MAGE", 2692, 1095, "Alliance", "esES", 1 },
				{ "class", "WARRIOR", 6831, 8602, "Alliance", "esES", 2 },
				{ "profession", "blacksmithing", 5016, 4316, "Alliance", "esES", 3 },
				{ "weapon", "", 6176, 8923, "Alliance", "", 0 },
			},
			[1454] = {
				{ "class", "MAGE", 4000, 4000, "Horde", "esES", 4 },
				{ "riding", "", 5000, 5000, "Horde", "", 0 },
			},
		},
		names = { esES = { "Sala de los Misterios", "Sala de Armas", "La Gran Fundición", "Sala de los Magos" } },
	}

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		loads, locale, faction, class = 0, "esES", "Alliance", "MAGE"
		StubGlobals({
			WOW_PROJECT_ID = 18,
			GetLocale = function() return locale end,
			UnitFactionGroup = function() return faction end,
			UnitClass = function() return "Mago", class end,
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
					rawset(_G, "MapScoutDataForever", { categories = { trainers = function() return PACK end } })
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
			"Search/Engine.lua", "Providers/Trainers.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	local function entries()
		return ns.Registry.Get("trainers").entries
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

	it("names each result after what it teaches, with the place the game gave it", function()
		start()
		assert.are.equal(1, loads)
		local mage = entry("class:MAGE:1455:1")
		assert.are.equal("Instructor de magos", mage.name)
		assert.are.equal("Sala de los Misterios", mage.subtitle)
		assert.are.equal(1455, mage.mapID)
		assert.are.equal(0.2692, mage.x)
		assert.are.equal("Instructor de herrería", entry("profession:blacksmithing:1455:3").name)
		local weapon = entry("weapon::1455:4")
		assert.are.equal("Instructor de armas", weapon.name)
		assert.are.equal("Forjaz", weapon.subtitle) -- no place name: its city
	end)

	it("puts the player's class in its own toggle, and other classes in another", function()
		start()
		assert.are.equal("class", entry("class:MAGE:1455:1").category)
		assert.are.equal("otherclass", entry("class:WARRIOR:1455:2").category)
		local found = search("instructor")
		assert.are.equal("class:MAGE:1455:1", found[1].id) -- own class first
		ns.Registry.SetCategoryEnabled("trainers", "otherclass", false)
		for _, e in ipairs(search("instructor")) do
			assert.are_not.equal("otherclass", e.category)
		end
	end)

	it("leaves out what only the other faction can use", function()
		start()
		assert.are.equal(4, #entries())
		assert.is_nil(entry("class:MAGE:1454:1"))
		assert.is_nil(entry("riding::1454:2"))
	end)

	it("is found by trainer and class or profession words, in English and Spanish", function()
		start()
		for text, id in pairs({
			["instructor de magos"] = "class:MAGE:1455:1",
			["instructor mago"] = "class:MAGE:1455:1",
			["instructor maga"] = "class:MAGE:1455:1",
			["mage trainer"] = "class:MAGE:1455:1",
			["instructor de herreria"] = "profession:blacksmithing:1455:3",
			["blacksmithing trainer"] = "profession:blacksmithing:1455:3",
			["instructor de guerreros"] = "class:WARRIOR:1455:2",
			["la gran fundicion"] = "profession:blacksmithing:1455:3",
		}) do
			local found = search(text)
			assert.are.equal(id, found[1] and found[1].id, text)
		end
	end)

	it("is found in English by a player of another language, with English names", function()
		locale = "enUS"
		start()
		local mage = entry("class:MAGE:1455:1")
		assert.are.equal("Mage trainer", mage.name)
		assert.are.equal("Forjaz", mage.subtitle) -- the place was harvested in Spanish
		assert.are.equal("class:MAGE:1455:1", search("mage trainer")[1].id)
	end)

	it("has @ words for all trainers and for each toggle", function()
		start()
		assert.are.equal(4, #search("@instructor"))
		assert.are.equal(4, #search("@trainer"))
		local professions = search("@profesion")
		assert.are.equal(1, #professions)
		assert.are.equal("profession", professions[1].category)
		assert.are.equal(1, #search("@clase"))
		assert.are.equal(1, #search("@weapon"))
	end)

	it("knows on which maps the pack has trainers", function()
		start()
		local Trainers = ns.Trainers
		assert.is_true(Trainers.Covers(PACK, 1455))
		assert.is_true(Trainers.Covers(PACK, 1454)) -- either faction
		assert.is_false(Trainers.Covers(PACK, 1))
		assert.is_false(Trainers.Covers(nil, 1455))
	end)

	it("lets the pack go when turned off", function()
		start()
		ns.Registry.SetEnabled("trainers", false)
		assert.are.same({}, ns.Packs.Built())
		assert.are.equal(0, #entries())
	end)
end)
