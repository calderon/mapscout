-- API/Registry.lua: search providers registered through MapScoutAPI
describe("API/Registry.lua", function()
	local ns, frame, Registry, events

	local function load(saved)
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua" }) do
			LoadAddonFile(file, ns)
		end
		Registry = ns.Registry
		events = {}
		Registry.Listen(function(what, id, ...)
			events[#events + 1] = table.concat({ what, id, tostring((...)) }, " ")
		end)
		_G.MapScoutDB = saved
		frame:Fire("ADDON_LOADED", "MapScout")
	end

	local function login()
		frame:Fire("PLAYER_LOGIN")
	end

	local function entry(id, extra)
		local e = { id = id, name = "Entry " .. id, mapID = 1453, x = 0.5, y = 0.5 }
		for k, v in pairs(extra or {}) do
			e[k] = v
		end
		return e
	end

	before_each(function()
		ResetWoW()
	end)

	describe("registering", function()
		it("waits for login, then enables and calls OnEnable", function()
			load()
			local enabled = 0
			local provider = MapScoutAPI:RegisterProvider("test", { name = "Test", OnEnable = function() enabled = enabled + 1 end })
			assert.is_false(provider:IsEnabled())
			assert.are.equal(0, enabled)
			login()
			assert.is_true(provider:IsEnabled())
			assert.are.equal(1, enabled)
		end)

		it("registers at once after login", function()
			load()
			login()
			local provider = MapScoutAPI:RegisterProvider("late", { name = "Late" })
			assert.is_true(provider:IsEnabled())
			assert.are.equal("Late", Registry.Get("late").spec.name)
		end)

		it("keeps entries set before login and applies them before OnEnable", function()
			load()
			local provider
			provider = MapScoutAPI:RegisterProvider("early", {
				name = "Early",
				OnEnable = function()
					assert.are.equal(1, #Registry.Get("early").entries) -- already there
				end,
			})
			provider:SetEntries({ entry(1) })
			login()
			assert.are.equal(1, #Registry.Get("early").entries)
		end)

		it("lists providers in order", function()
			load()
			login()
			MapScoutAPI:RegisterProvider("a", { name = "A" })
			MapScoutAPI:RegisterProvider("b", { name = "B" })
			assert.are.same({ "a", "b" }, { Registry.List()[1].id, Registry.List()[2].id })
		end)

		it("rejects a bad spec with a clear message", function()
			load()
			local function message(id, spec)
				local ok, err = pcall(MapScoutAPI.RegisterProvider, MapScoutAPI, id, spec)
				assert.is_false(ok)
				return err
			end
			assert.matches("name is required", message("x", {}), 1, true)
			assert.matches("must be a word", message("bad id", { name = "X" }), 1, true)
			assert.matches("Collect must be a function", message("x", { name = "X", Collect = 1 }), 1, true)
			assert.matches("categories[1] needs an id and a name", message("x", { name = "X", categories = { {} } }), 1, true)
			assert.matches("second argument must be a table", message("x", nil), 1, true)
			MapScoutAPI:RegisterProvider("dup", { name = "Dup" })
			assert.matches("already registered", message("dup", { name = "Dup" }), 1, true)
		end)
	end)

	describe("entries", function()
		it("stores copies of valid entries and tells the listeners", function()
			load()
			login()
			local provider = MapScoutAPI:RegisterProvider("p", { name = "P" })
			local list = { entry(1), entry(2) }
			provider:SetEntries(list)
			list[1].name = "changed later"
			local stored = Registry.Get("p").entries
			assert.are.equal(2, #stored)
			assert.are.equal("Entry 1", stored[1].name)
			assert.are.equal("entries p nil", events[#events])
		end)

		it("skips invalid entries and reports them once", function()
			load()
			login()
			local provider = MapScoutAPI:RegisterProvider("p", { name = "P", categories = { { id = "shops", name = "Shops" } } })
			provider:SetEntries({
				entry(1),
				{ id = 2 }, -- no name
				entry(3, { x = 1.5 }), -- bad coords
				entry(4, { mapID = "x" }),
				entry(5, { category = "nope" }),
				entry(6, { category = "shops" }),
				{ id = 7, name = "No position" }, -- fine: only actions
			})
			local stored = Registry.Get("p").entries
			assert.are.equal(3, #stored)
			assert.are.equal(4, Registry.Get("p").skipped)
			assert.are.equal(1, #ReportedErrors)
			assert.matches("4 entries skipped (first problem: name is required)", ReportedErrors[1], 1, true)
			provider:SetEntries({ { id = 8 } })
			assert.are.equal(1, #ReportedErrors) -- only once per provider
		end)

		it("checks the roams flag and the route of an entry", function()
			load()
			login()
			local provider = MapScoutAPI:RegisterProvider("p", { name = "P" })
			local route = { { mapID = 1455, points = { 0.1, 0.2, 0.3, 0.4 } } }
			provider:SetEntries({
				entry(1, { roams = true }),
				entry(2, { route = route }),
				entry(3, { roams = "yes" }),
				entry(4, { route = { { mapID = 1455, points = { 0.1, 0.2 } } } }), -- one point
				entry(5, { route = { { points = { 0.1, 0.2, 0.3, 0.4 } } } }), -- no map
				entry(6, { route = { { mapID = 1455, points = { 0.1, 0.2, 3, 0.4 } } } }), -- off the map
				entry(7, { route = { 5 } }),
			})
			local stored = Registry.Get("p").entries
			assert.are.equal(2, #stored)
			assert.are.same(route, stored[2].route)
			assert.are.equal(5, Registry.Get("p").skipped)
			assert.matches("first problem: roams must be true or false", ReportedErrors[1], 1, true)
			assert.is_nil(Registry.RouteProblem(route))
			assert.matches("route[1]: points must be numbers from 0 to 1", Registry.RouteProblem({ { mapID = 1, points = { 0, 0, 2, 0 } } }), 1, true)
		end)

		it("forwards Invalidate to the listeners", function()
			load()
			login()
			MapScoutAPI:RegisterProvider("p", { name = "P" }):Invalidate(1453)
			assert.are.equal("invalidate p 1453", events[#events])
		end)
	end)

	describe("turning on and off", function()
		it("drops the entries, calls OnDisable and saves the choice", function()
			load()
			login()
			local calls = {}
			local provider = MapScoutAPI:RegisterProvider("p", {
				name = "P",
				OnEnable = function() calls[#calls + 1] = "on" end,
				OnDisable = function() calls[#calls + 1] = "off" end,
			})
			provider:SetEntries({ entry(1) })
			Registry.SetEnabled("p", false)
			assert.is_false(provider:IsEnabled())
			assert.are.equal(0, #Registry.Get("p").entries)
			assert.is_false(MapScoutDB.options.providers.p)
			provider:SetEntries({ entry(2) }) -- ignored while off
			assert.are.equal(0, #Registry.Get("p").entries)
			Registry.SetEnabled("p", true)
			assert.is_nil(MapScoutDB.options.providers.p) -- back to the default: nothing saved
			assert.are.same({ "on", "off", "on" }, calls)
			assert.matches("toggled p false", table.concat(events, ","), 1, true)
		end)

		it("respects a saved choice and defaultEnabled", function()
			load({ schema = 1, options = { providers = { saved = false } } })
			MapScoutAPI:RegisterProvider("saved", { name = "Saved" })
			MapScoutAPI:RegisterProvider("optin", { name = "Opt-in", defaultEnabled = false })
			login()
			assert.is_false(Registry.Get("saved").enabled)
			assert.is_false(Registry.Get("optin").enabled)
			Registry.SetEnabled("optin", true)
			assert.is_true(MapScoutDB.options.providers.optin)
		end)

		it("knows which categories are turned off", function()
			load({ schema = 1, options = { categories = { ["p.rares"] = false } } })
			assert.is_false(Registry.IsCategoryEnabled("p", "rares"))
			assert.is_true(Registry.IsCategoryEnabled("p", "treasures"))
		end)

		it("unregisters a provider", function()
			load()
			login()
			local off = false
			MapScoutAPI:RegisterProvider("p", { name = "P", OnDisable = function() off = true end })
			MapScoutAPI:UnregisterProvider("p")
			assert.is_true(off)
			assert.is_nil(Registry.Get("p"))
			assert.are.equal(0, #Registry.List())
		end)
	end)

	describe("errors in provider code", function()
		it("turns a provider off for the session after 3 errors, with one message", function()
			load()
			login()
			MapScoutAPI:RegisterProvider("bad", { name = "Bad", Collect = function() error("boom") end })
			local record = Registry.Get("bad")
			for _ = 1, 4 do
				Registry.Call(record, "Collect", {}, function() end)
			end
			assert.is_true(record.failed)
			assert.is_false(record.enabled)
			assert.are.equal(3, record.errors) -- the 4th call doesn't run: it is off
			assert.are.equal(1, #ChatLog)
			assert.matches('"Bad" failed 3 times', ChatLog[1], 1, true)
			assert.is_nil(MapScoutDB.options.providers.bad) -- not saved: back after a reload
			Registry.SetEnabled("bad", true)
			assert.is_false(record.enabled) -- stays off this session
		end)

		it("survives an error in OnEnable", function()
			load()
			MapScoutAPI:RegisterProvider("x", { name = "X", OnEnable = function() error("oops") end })
			login()
			assert.are.equal(1, #ReportedErrors)
			assert.are.equal(1, Registry.Get("x").errors)
		end)
	end)

	it("turns filter words into @ filters", function()
		load()
		login()
		MapScoutAPI:RegisterProvider("bridge", { name = "Bridge", filter = "Bridge", filterAliases = { "rutas", "Route" } })
		MapScoutAPI:RegisterProvider("aliasonly", { name = "A", filterAliases = { "Rutas" } })
		assert.are.same({ "bridge", "rutas", "route" }, Registry.Get("bridge").filters)
		assert.are.same({ { provider = "bridge" }, { provider = "aliasonly" } }, Registry.FindByFilter("RUTAS"))
		assert.are.same({}, Registry.FindByFilter("nothing"))
	end)

	it("turns category filter words into @ filters for that category", function()
		load()
		login()
		MapScoutAPI:RegisterProvider("services", {
			name = "Services",
			filter = "services",
			categories = {
				{ id = "mail", name = "Mailboxes", filter = "mailbox", filterAliases = { "buzón" } },
				{ id = "bank", name = "Banks", filter = "bank" },
				{ id = "plain", name = "No words" },
			},
		})
		assert.are.same({ { provider = "services", category = "mail" } }, Registry.FindByFilter("Buzon"))
		assert.are.same({ { provider = "services" } }, Registry.FindByFilter("services"))
		local ok, err = pcall(MapScoutAPI.RegisterProvider, MapScoutAPI, "x",
			{ name = "X", categories = { { id = "a", name = "A", filter = 3 } } })
		assert.is_false(ok)
		assert.matches("filter must be a string", err, 1, true)
	end)

	it("finds the providers inside another one with its @ word", function()
		load()
		login()
		MapScoutAPI:RegisterProvider("services", { name = "Services", filter = "service",
			categories = { { id = "bank", name = "Banks", filter = "bank" } } })
		MapScoutAPI:RegisterProvider("trainers", { name = "Trainers", filter = "trainer", parent = "services" })
		assert.are.same({ { provider = "services" }, { provider = "trainers" } }, Registry.FindByFilter("service"))
		assert.are.same({ { provider = "services" }, { provider = "trainers" } }, Registry.FindByFilterPrefix("serv"))
		assert.are.same({ { provider = "trainers" } }, Registry.FindByFilter("trainer")) -- not the other way
		assert.are.same({ { provider = "services", category = "bank" } }, Registry.FindByFilter("bank"))
		assert.are.same({ "trainers" }, (function()
			local ids = {}
			for i, record in ipairs(Registry.Children("services")) do ids[i] = record.id end
			return ids
		end)())
		local ok, err = pcall(MapScoutAPI.RegisterProvider, MapScoutAPI, "x", { name = "X", parent = 3 })
		assert.is_false(ok)
		assert.matches("parent must be a string", err, 1, true)
	end)

	it("/ms debug providers lists them", function()
		load()
		SlashCmdList.MAPSCOUT("debug providers")
		assert.matches("no search providers", ChatLog[#ChatLog], 1, true)
		login()
		MapScoutAPI:RegisterProvider("p", { name = "P", filter = "pp" }):SetEntries({ entry(1) })
		SlashCmdList.MAPSCOUT("debug providers")
		assert.matches("p (P): on, 1 entries, 0 errors, filters @pp", ChatLog[#ChatLog], 1, true)
	end)
end)
