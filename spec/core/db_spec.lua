-- Core/DB.lua: SavedVariables with a versioned schema
describe("Core/DB.lua", function()
	local ns, frame

	local function load()
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		LoadAddonFile("Core/DB.lua", ns)
		return ns.DB
	end

	-- What the game does when it loads the addon's saved data
	local function addonLoaded(name)
		frame:Fire("ADDON_LOADED", name or "MapScout")
	end

	before_each(function()
		ResetWoW()
		StubGlobals({ MapScoutDB = false, MapScoutCharDB = false }) -- so ResetWoW clears them
		_G.MapScoutDB, _G.MapScoutCharDB = nil, nil
	end)

	describe("MergeDefaults", function()
		it("adds what is missing at any depth and keeps the player's values", function()
			local DB = load()
			local data = { a = 1, nested = { keep = "mine" } }
			DB.MergeDefaults(data, { a = 2, b = 3, nested = { keep = "default", add = true } })
			assert.are.same({ a = 1, b = 3, nested = { keep = "mine", add = true } }, data)
		end)

		it("keeps a player's false and doesn't replace a value of another type", function()
			local DB = load()
			local data = { flag = false, list = "not a table" }
			DB.MergeDefaults(data, { flag = true, list = { 1 } })
			assert.is_false(data.flag)
			assert.are.equal("not a table", data.list)
		end)

		it("copies default tables instead of sharing them", function()
			local DB = load()
			local defaults = { list = { 1 } }
			local a = DB.MergeDefaults({}, defaults)
			a.list[2] = 2
			assert.are.same({ 1 }, defaults.list)
			assert.are.same({ 1 }, DB.MergeDefaults({}, defaults).list)
		end)
	end)

	describe("Prepare", function()
		it("creates new data with the current schema", function()
			local DB = load()
			local data, state = DB.Prepare(nil, { x = {} }, {}, 3)
			assert.are.equal("new", state)
			assert.are.same({ x = {}, schema = 3 }, data)
		end)

		it("runs the missing migrations in order and completes the defaults", function()
			local DB = load()
			local order = {}
			local migrations = {
				[2] = function(db) order[#order + 1] = 2; db.renamed = db.old; db.old = nil end,
				[3] = function() order[#order + 1] = 3 end,
			}
			local saved = { schema = 1, old = "value" }
			local data, state = DB.Prepare(saved, { extra = true }, migrations, 3)
			assert.are.equal("upgraded", state)
			assert.are.same({ 2, 3 }, order)
			assert.are.equal(saved, data) -- the same table: it is what gets saved
			assert.are.same({ schema = 3, renamed = "value", extra = true }, data)
		end)

		it("treats data without schema as schema 0", function()
			local DB = load()
			local ran = false
			local _, state = DB.Prepare({ something = 1 }, {}, { [1] = function() ran = true end }, 1)
			assert.are.equal("upgraded", state)
			assert.is_true(ran)
		end)

		it("leaves data from a newer MapScout untouched", function()
			local DB = load()
			local saved = { schema = 9, mine = true }
			local data, state = DB.Prepare(saved, { extra = true }, {}, 1)
			assert.are.equal("newer", state)
			assert.are_not.equal(saved, data)
			assert.are.same({ schema = 9, mine = true }, saved)
			assert.is_true(data.extra)
		end)

		it("leaves data untouched when a migration fails", function()
			local DB = load()
			local saved = { schema = 1, mine = true }
			local data, state, err = DB.Prepare(saved, {}, { [2] = function() error("broken") end }, 2)
			assert.are.equal("failed", state)
			assert.matches("broken", err)
			assert.are_not.equal(saved, data)
			assert.are.equal(1, saved.schema)
		end)
	end)

	describe("on ADDON_LOADED", function()
		it("creates both SavedVariables with the defaults", function()
			local DB = load()
			addonLoaded()
			assert.are.equal(ns.db, MapScoutDB)
			assert.are.equal(ns.charDB, MapScoutCharDB)
			assert.are.equal(DB.SCHEMA, MapScoutDB.schema)
			assert.is_table(MapScoutDB.options.waypoint)
			assert.is_table(MapScoutDB.aliases)
			assert.is_table(MapScoutDB.blacklist)
			assert.is_table(MapScoutDB.favorites)
			assert.is_table(MapScoutDB.frequency)
			assert.is_table(MapScoutCharDB.history)
			assert.is_table(MapScoutCharDB.knownTaxi)
		end)

		it("keeps the player's saved values", function()
			load()
			_G.MapScoutDB = { schema = 1, aliases = { ah = "key" }, options = { maxResults = 20 } }
			addonLoaded()
			assert.are.equal("key", MapScoutDB.aliases.ah)
			assert.are.equal(20, MapScoutDB.options.maxResults)
			assert.is_true(MapScoutDB.options.waypoint.native)
		end)

		it("ignores other addons and listens only once", function()
			load()
			addonLoaded("Bridge")
			assert.is_nil(ns.db)
			addonLoaded()
			assert.is_table(ns.db)
			assert.is_nil(frame.events.ADDON_LOADED)
		end)

		it("warns once and doesn't save over data from a newer MapScout", function()
			load()
			local newer = { schema = 99, future = true }
			_G.MapScoutDB = newer
			addonLoaded()
			assert.are.equal(newer, MapScoutDB)
			assert.are_not.equal(newer, ns.db)
			assert.are.equal(1, #ChatLog)
			assert.matches("newer MapScout", ChatLog[1], 1, true)
		end)
	end)

	it("drops the old client audit data when upgrading to schema 1", function()
		load()
		_G.MapScoutDB = { audit = { apis = {} }, audit2 = { zones = {} } }
		addonLoaded()
		assert.is_nil(MapScoutDB.audit)
		assert.is_nil(MapScoutDB.audit2)
		assert.are.equal(1, MapScoutDB.schema)
		assert.are.equal("upgraded", ns.DB.state.account)
	end)

	it("/ms debug db shows the state and sizes", function()
		load()
		_G.MapScoutCharDB = { schema = 1, history = { "bank", "mail" } }
		addonLoaded()
		SlashCmdList.MAPSCOUT("debug db")
		local out = table.concat(ChatLog, "\n")
		assert.matches("schema 1 (current 1), account new, character current", out, 1, true)
		assert.matches("2 recent searches", out, 1, true)
	end)

	it("/ms debug lists the topics", function()
		load()
		SlashCmdList.MAPSCOUT("debug")
		assert.matches("/ms debug db", table.concat(ChatLog, "\n"), 1, true)
	end)
end)
