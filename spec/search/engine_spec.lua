-- Search/Index.lua and Search/Engine.lua: indexing and scoring
describe("Search engine", function()
	local ns, Registry, Engine

	local function entry(id, name, extra)
		local e = { id = id, name = name, mapID = 1455, x = 0.5, y = 0.5 }
		for k, v in pairs(extra or {}) do
			e[k] = v
		end
		return e
	end

	local function load(saved)
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua" }) do
			LoadAddonFile(file, ns)
		end
		Registry, Engine = ns.Registry, ns.Engine
		_G.MapScoutDB = saved
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	local function provider(id, entries, spec)
		spec = spec or {}
		spec.name = spec.name or id
		local p = MapScoutAPI:RegisterProvider(id, spec)
		p:SetEntries(entries)
		return p
	end

	local function search(text, opts)
		local results, stats = Engine.Search(ns.Query.Parse(text), opts)
		local names = {}
		for i, r in ipairs(results) do
			names[i] = r.item.entry.name
		end
		return names, stats, results
	end

	before_each(function()
		ResetWoW()
		load()
	end)

	describe("scoring", function()
		it("ranks exact name > starts with > word > contains", function()
			provider("p", {
				entry(1, "Contrabanco"), entry(2, "Gran Banco"), entry(3, "Bancos del gremio"),
				entry(4, "Banco de Forjaz"), entry(5, "Banco"), entry(6, "Taberna"),
			})
			assert.are.same({ "Banco", "Banco de Forjaz", "Bancos del gremio", "Gran Banco", "Contrabanco" }, search("banco"))
		end)

		it("needs every typed word, in any order", function()
			provider("p", { entry(1, "Banco de Forjaz"), entry(2, "Banco de Ventormenta"), entry(3, "Forjaz") })
			assert.are.same({ "Banco de Forjaz" }, search("forjaz banco"))
			assert.are.same({ "Banco de Forjaz" }, search("ban forj"))
		end)

		it("ignores accents, case and apostrophes", function()
			provider("p", { entry(1, "Cañón de Grom'gol") })
			assert.are.same({ "Cañón de Grom'gol" }, search("CANON gromgol"))
		end)

		it("matches keywords, below a match in the name", function()
			provider("p", {
				entry(1, "Buzón", { keywords = { "mailbox", "correo" } }),
				entry(2, "Mailbox Street"),
			})
			assert.are.same({ "Mailbox Street", "Buzón" }, search("mailbox"))
			assert.are.same({ "Buzón" }, search("correo"))
		end)

		it("uses the entry's weight to break close scores", function()
			provider("p", { entry(1, "Posada A", { weight = 0 }), entry(2, "Posada B", { weight = 1 }) })
			assert.are.same({ "Posada B", "Posada A" }, search("posada"))
		end)

		it("keeps a stable order: shorter name, then alphabetical, then key", function()
			provider("p", { entry(3, "Inn B"), entry(1, "Inn Aa"), entry(2, "Inn A") })
			provider("q", { entry(1, "Inn A") })
			local _, _, results = search("inn")
			local keys = {}
			for i, r in ipairs(results) do
				keys[i] = r.item.key
			end
			assert.are.same({ "p:2", "q:1", "p:3", "p:1" }, keys)
		end)
	end)

	describe("typos", function()
		it("finds words with one wrong, missing, extra or swapped letter", function()
			provider("p", { entry(1, "Ventormenta"), entry(2, "Orgrimmar") })
			for _, typo in ipairs({ "ventormneta", "ventormenta", "vemtormenta", "ventrmenta", "orgrimar", "orgrimmmar" }) do
				local names, stats, results = search(typo)
				assert.are.equal(1, #names, typo)
				if typo ~= "ventormenta" then
					assert.is_true(stats.fuzzy and results[1].fuzzy == true, typo)
				end
			end
		end)

		it("accepts a typo while still typing a long word", function()
			provider("p", { entry(1, "Ventormenta") })
			assert.are.same({ "Ventormenta" }, search("vemtor"))
		end)

		it("doesn't guess with fewer than 4 letters", function()
			provider("p", { entry(1, "Ventormenta") })
			assert.are.same({}, search("vnt"))
		end)

		it("only looks for typos when the normal search finds few results", function()
			local list = {}
			for i = 1, 6 do
				list[i] = entry(i, "Posada " .. i)
			end
			list[7] = entry(7, "Posadas")
			list[8] = entry(8, "Pisada")
			provider("p", list)
			local names, stats = search("posada")
			assert.is_false(stats.fuzzy)
			assert.are.equal(7, #names) -- "Pisada" (one letter away) not added
		end)

		it("measures the distance between words", function()
			assert.are.equal(0, Engine.Distance("abc", "abc", 2))
			assert.are.equal(1, Engine.Distance("abcd", "abdc", 2)) -- swap
			assert.are.equal(1, Engine.Distance("abcd", "abd", 2))
			assert.are.equal(1, Engine.Distance("abcd", "abxd", 2))
			assert.are.equal(2, Engine.Distance("kitten", "sitting", 1)) -- over max: max + 1
		end)
	end)

	describe("limits and filters", function()
		it("caps results at the player's option, 50 by default, or opts.max", function()
			local list = {}
			for i = 1, 60 do
				list[i] = entry(i, "Buzón " .. i)
			end
			provider("p", list)
			assert.are.equal(50, #search("buzon"))
			MapScoutDB.options.maxResults = 10
			assert.are.equal(10, #search("buzon"))
			assert.are.equal(3, #search("buzon", { max = 3 }))
		end)

		it("searches only the providers and categories of the @ filters", function()
			provider("flights", { entry(1, "Forjaz (vuelos)") }, { filter = "flights" })
			provider("services", {
				entry(1, "Banco de Forjaz", { category = "bank" }),
				entry(2, "Buzón de Forjaz", { category = "mail" }),
				entry(3, "Forjaz sin categoría"),
			}, {
				filter = "services",
				categories = { { id = "bank", name = "Banks", filter = "bank" }, { id = "mail", name = "Mail", filter = "mailbox" } },
			})
			assert.are.equal(4, #search("forjaz"))
			assert.are.same({ "Forjaz (vuelos)" }, search("@flights forjaz"))
			assert.are.same({ "Buzón de Forjaz" }, search("@mailbox forjaz"))
			assert.are.equal(3, #search("@services forjaz"))
			assert.are.same({ "Banco de Forjaz", "Buzón de Forjaz" }, search("@bank @mailbox forjaz"))
		end)

		it("lists everything a filter selects when there is no text", function()
			provider("flights", { entry(1, "B"), entry(2, "A") }, { filter = "flights" })
			assert.are.same({ "A", "B" }, search("@flights"))
			assert.are.same({}, search(""))
		end)

		it("leaves out turned-off providers and categories", function()
			provider("p", { entry(1, "Buzón", { category = "mail" }), entry(2, "Buzón libre") },
				{ categories = { { id = "mail", name = "Mail" } } })
			provider("off", { entry(1, "Buzón apagado") })
			Registry.SetEnabled("off", false)
			MapScoutDB.options.categories["p.mail"] = false
			assert.are.same({ "Buzón libre" }, search("buzon"))
		end)
	end)

	describe("aliases", function()
		it("puts the alias' result first, even if its name doesn't match", function()
			provider("p", { entry(1, "Casa de subastas"), entry(2, "Ah'Kahet") })
			MapScoutDB.aliases.ah = "p:1"
			assert.are.same({ "Casa de subastas", "Ah'Kahet" }, search("ah"))
		end)
	end)

	describe("narrowing and the index", function()
		it("checks only the previous matches when the text grows", function()
			local list = {}
			for i = 1, 30 do
				list[i] = entry(i, (i % 2 == 0 and "Ventana " or "Puerta ") .. i)
			end
			provider("p", list)
			local _, first = search("ven")
			assert.is_false(first.narrowed)
			assert.are.equal(30, first.candidates)
			local names, second = search("venta")
			assert.is_true(second.narrowed)
			assert.are.equal(15, second.candidates)
			assert.are.equal(15, #names)
			local _, other = search("pue")
			assert.is_false(other.narrowed) -- not an extension
		end)

		it("doesn't narrow after the index changed", function()
			local p = provider("p", { entry(1, "Ventana") })
			search("ven")
			p:SetEntries({ entry(1, "Ventana"), entry(2, "Ventisca") })
			local names, stats = search("vent")
			assert.is_false(stats.narrowed)
			assert.are.equal(2, #names)
		end)

		it("normalizes each entry once, not on every search", function()
			provider("p", { entry(1, "Cañón"), entry(2, "Árbol") })
			search("can")
			local calls = 0
			local normalize = ns.Normalize
			ns.Normalize = function(...)
				calls = calls + 1
				return normalize(...)
			end
			Engine.Reset()
			search("arbol")
			search("arb")
			assert.are.equal(2, calls) -- only the two queries
		end)

		it("drops a provider's part of the index when it is turned off", function()
			provider("p", { entry(1, "Ventana") })
			search("ven")
			assert.are.same({ 1, 1 }, { ns.Index.Stats() })
			Registry.SetEnabled("p", false)
			assert.are.same({ 0, 0 }, { ns.Index.Stats() })
			assert.are.same({}, search("ventana"))
		end)
	end)

	it("/ms debug search and bench print results and times", function()
		provider("p", { entry(1, "Ventormenta"), entry(2, "Ventana") })
		SlashCmdList.MAPSCOUT("debug search vent")
		assert.matches('"vent": 2 results', ChatLog[#ChatLog - 2], 1, true)
		assert.matches("1. Ventana (p)", ChatLog[#ChatLog - 1], 1, true)
		SlashCmdList.MAPSCOUT("debug bench vent")
		assert.matches('"vent": [%d.]+ ms, 2 candidates, 2 results, typos: yes · typed letter by letter %(4 searches%): [%d.]+ ms, slowest [%d.]+ ms · index: 1 providers, 2 entries, built in',
			ChatLog[#ChatLog])
	end)
end)

describe("Search engine with the open map", function()
	local ns
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		StubGlobals({ C_Map = { GetMapInfo = function(id) return MAPS[id] end } })
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	it("always keeps the results of the open map, first, even past the limit", function()
		local list = {}
		for i = 1, 5 do -- better matches, elsewhere
			list[#list + 1] = { id = "far" .. i, name = "Buzón", mapID = 1453, x = 0.5, y = 0.5 }
		end
		list[#list + 1] = { id = "near", name = "Buzón de la plaza", mapID = 1455, x = 0.5, y = 0.5 }
		list[#list + 1] = { id = "inside", name = "Buzón del museo", mapID = 9001, x = 0.5, y = 0.5 }
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries(list)
		local results, stats = ns.Engine.Search(ns.Query.Parse("buzon"), { max = 3, zoneMapID = 1455 })
		assert.are.equal(3, #results)
		assert.are.equal(2, stats.inZone)
		assert.is_true(results[1].inZone and results[2].inZone)
		-- same score: the shorter name first
		assert.are.same({ "p:inside", "p:near" }, { results[1].item.key, results[2].item.key })
		assert.is_nil(results[3].inZone)
		-- without the open map, the better matches win
		local plain = ns.Engine.Search(ns.Query.Parse("buzon"), { max = 3 })
		assert.are.equal("Buzón", plain[1].item.entry.name)
		assert.are.equal(3, #plain)
	end)
end)
