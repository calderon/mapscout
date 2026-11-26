-- Search/Query.lua: @ filters, coordinates, zone names and free text
describe("Search/Query.lua", function()
	local ns, Query

	-- A small Forever-like map tree for ns.FindMapByName
	local MAPS = {
		{ mapID = 1415, name = "Reinos del Este", mapType = 2 },
		{ mapID = 1414, name = "Kalimdor", mapType = 2 },
		{ mapID = 1429, name = "Bosque de Elwynn", mapType = 3 },
		{ mapID = 1453, name = "Ciudad de Ventormenta", mapType = 3 },
		{ mapID = 1455, name = "Forjaz", mapType = 3 },
		{ mapID = 1426, name = "Dun Morogh", mapType = 3 },
		{ mapID = 1418, name = "Tierras Inhóspitas", mapType = 3 },
		{ mapID = 1419, name = "Las Tierras Devastadas", mapType = 3 },
		{ mapID = 1460, name = "Garganta Grito de Guerra", mapType = 6 }, -- battleground: not searched
	}

	before_each(function()
		ResetWoW()
		StubGlobals({
			C_Map = {
				GetMapChildrenInfo = function(root)
					return root == 947 and MAPS or {}
				end,
			},
		})
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua", "Search/Query.lua" }) do
			LoadAddonFile(file, ns)
		end
		Query = ns.Query
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("flights", { name = "Flights", filter = "flights", filterAliases = { "vuelos" } })
		MapScoutAPI:RegisterProvider("services", {
			name = "Services",
			filter = "services",
			filterAliases = { "servicios" },
			categories = {
				{ id = "mail", name = "Mailboxes", filter = "mailbox", filterAliases = { "buzón" } },
				{ id = "bank", name = "Banks", filter = "bank" },
			},
		})
	end)

	describe("coordinates", function()
		local cases = {
			{ "45.2, 67.8", 0.452, 0.678 },
			{ "45.2 67.8", 0.452, 0.678 },
			{ "45 67", 0.45, 0.67 },
			{ "45,2 67,8", 0.452, 0.678 },
			{ "45, 67", 0.45, 0.67 },
			{ "45,67", 0.45, 0.67 },
			{ "45.2,67.8", 0.452, 0.678 },
			{ "45;67", 0.45, 0.67 },
			{ "0 100", 0, 1 },
		}
		for _, case in ipairs(cases) do
			it("reads \"" .. case[1] .. "\"", function()
				local q = Query.Parse(case[1])
				assert.is_table(q.coords)
				assert.is_true(math.abs(q.coords.x - case[2]) < 1e-9, "x of " .. case[1])
				assert.is_true(math.abs(q.coords.y - case[3]) < 1e-9, "y of " .. case[1])
				assert.are.equal("", q.text)
			end)
		end

		it("ignores numbers out of range and single numbers", function()
			assert.is_nil(Query.Parse("145 67").coords)
			assert.is_nil(Query.Parse("Zona 51").coords)
			assert.are.equal("zona 51", Query.Parse("Zona 51").text)
		end)
	end)

	describe("zone names with coordinates", function()
		it("resolves a zone before or after the coordinates", function()
			for _, text in ipairs({ "Elwynn 42 65", "42 65 Elwynn", "42, 65 bosque de elwynn" }) do
				local q = Query.Parse(text)
				assert.are.equal(1429, q.mapID, text)
				assert.are.equal(0.42, q.coords.x, text)
				assert.are.equal("", q.text, text)
			end
		end)

		it("keeps the words as text when they are not a zone", function()
			local q = Query.Parse("hello 42 65")
			assert.is_nil(q.mapID)
			assert.are.equal("hello", q.zoneText)
			assert.are.equal("hello", q.text)
			assert.is_table(q.coords) -- still coordinates, in the open map
		end)

		it("uses a custom zone finder", function()
			local q = Query.Parse("anywhere 1 2", { findZone = function(name) return name == "anywhere" and 99 end })
			assert.are.equal(99, q.mapID)
		end)
	end)

	describe("@ filters", function()
		it("selects providers and categories, in English or the player's language", function()
			assert.are.same({ { provider = "flights" } }, Query.Parse("@flights").filters)
			assert.are.same({ { provider = "flights" } }, Query.Parse("@vuelos").filters)
			assert.are.same({ { provider = "services", category = "mail" } }, Query.Parse("@buzón forjaz").filters)
			assert.are.equal("forjaz", Query.Parse("@buzón forjaz").text)
		end)

		it("allows several, once each, anywhere in the text", function()
			local q = Query.Parse("bank @flights near @BANK @flights")
			assert.are.same({ { provider = "flights" }, { provider = "services", category = "bank" } }, q.filters)
			assert.are.equal("bank near", q.text)
			assert.are.same({ "bank", "near" }, q.words)
		end)

		it("takes an @ word being typed as the filters it starts", function()
			assert.are.same({ { provider = "services", category = "mail" } }, Query.Parse("@buz").filters)
			assert.are.same({ { provider = "flights" } }, Query.Parse("@vue forjaz").filters)
			assert.are.equal("forjaz", Query.Parse("@vue forjaz").text)
			local several = Query.Parse("@s").filters -- services (whole provider) and nothing else
			assert.are.same({ { provider = "services" } }, several)
		end)

		it("treats an unknown @ word as text", function()
			local q = Query.Parse("@nonsense mail")
			assert.are.same({}, q.filters)
			assert.are.equal("nonsense mail", q.text)
		end)

		it("works together with coordinates", function()
			local q = Query.Parse("@services Forjaz 30 60")
			assert.are.same({ { provider = "services" } }, q.filters)
			assert.are.equal(1455, q.mapID)
		end)
	end)

	it("parses an empty search", function()
		local q = Query.Parse(nil)
		assert.are.equal("", q.text)
		assert.are.same({}, q.words)
		assert.are.same({}, q.filters)
	end)

	describe("FindMapByName", function()
		it("prefers exact names, then names that start with it, then any word", function()
			assert.are.equal(1455, ns.FindMapByName("Forjaz"))
			assert.are.equal(1453, ns.FindMapByName("ciudad de vent"))
			assert.are.equal(1453, ns.FindMapByName("ventormenta"))
			assert.are.equal(1418, ns.FindMapByName("tierras")) -- shortest of the two
		end)

		it("prefers zones over continents and skips other map types", function()
			assert.are.equal(1414, ns.FindMapByName("kalimdor"))
			assert.is_nil(ns.FindMapByName("garganta"))
			assert.is_nil(ns.FindMapByName("nowhere"))
			assert.is_nil(ns.FindMapByName(""))
		end)
	end)

	it("/ms debug query shows how a search is read", function()
		SlashCmdList.MAPSCOUT("debug query @buzón Elwynn 42,5 65")
		assert.matches('filters: services/mail · coordinates: 42.5, 65.0 · zone: elwynn = 1429 · text: ""', ChatLog[#ChatLog], 1, true)
	end)
end)
