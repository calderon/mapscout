-- Core/DB.lua: SavedVariables with a versioned schema
describe("Core/DB.lua", function()
	local ns, frame

	local function load()
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		LoadAddonFile("Core/Util.lua", ns)
		LoadAddonFile("Core/DB.lua", ns)
		return ns.DB
	end

	-- What the game does when it loads the addon's saved data
	local function addonLoaded(name)
		frame:Fire("ADDON_LOADED", name or "MapScout")
	end

	before_each(function()
		ResetWoW()
	end)

	describe("Attach and Prune", function()
		it("reads the defaults through, without copying them into the data", function()
			local DB = load()
			local defaults = { a = 2, b = 3, nested = { keep = "default", add = true } }
			local data = DB.Attach({ a = 1, nested = { keep = "mine" } }, defaults)
			assert.are.equal(1, data.a)
			assert.are.equal(3, data.b)
			assert.are.equal("mine", data.nested.keep)
			assert.is_true(data.nested.add)
			assert.is_nil(rawget(data, "b")) -- read through, not stored
			assert.is_nil(rawget(data.nested, "add"))
		end)

		it("creates the structure tables, so writing never touches the defaults", function()
			local DB = load()
			local defaults = { options = { waypoint = { native = false } } }
			local data = DB.Attach({}, defaults)
			data.options.waypoint.native = true
			assert.is_true(rawget(data.options.waypoint, "native"))
			assert.is_false(defaults.options.waypoint.native)
		end)

		it("keeps a player's value of another type than its default", function()
			local DB = load()
			local data = DB.Attach({ list = "not a table", flag = false }, { list = { 1 }, flag = true })
			assert.are.equal("not a table", data.list)
			assert.is_false(data.flag)
		end)

		it("removes saved values equal to their default, at any depth", function()
			local DB = load()
			local defaults = { a = 1, b = 2, nested = { x = false, y = 5 } }
			local data = DB.Prune({ a = 1, b = 9, nested = { x = false, y = 6 }, extra = "kept" }, defaults)
			assert.are.same({ b = 9, nested = { y = 6 }, extra = "kept" }, data)
		end)
	end)

	describe("Prepare", function()
		it("creates new data with the current schema", function()
			local DB = load()
			local data, state = DB.Prepare(nil, { x = {}, y = 1 }, {}, 3)
			assert.are.equal("new", state)
			assert.are.equal(3, data.schema)
			assert.are.equal(1, data.y)
			assert.is_nil(rawget(data, "y")) -- a default: not stored
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
			_G.MapScoutDB = { schema = 2, aliases = { ah = "key" }, options = { maxResults = 20, waypoint = { tomtom = true } } }
			addonLoaded()
			assert.are.equal("key", MapScoutDB.aliases.ah)
			assert.are.equal(20, MapScoutDB.options.maxResults)
			assert.is_true(MapScoutDB.options.waypoint.tomtom) -- kept
			assert.is_false(MapScoutDB.options.waypoint.native) -- completed from the defaults
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
		assert.are.equal(2, MapScoutDB.schema)
		assert.are.equal("upgraded", ns.DB.state.account)
	end)

	it("turns the game's map pin and its tracking off when upgrading to schema 2", function()
		load()
		_G.MapScoutDB = { schema = 1, options = { waypoint = { native = true, superTrack = true, tomtom = true } } }
		addonLoaded()
		assert.are.same({ native = false, superTrack = false, tomtom = true }, MapScoutDB.options.waypoint)
		assert.are.equal(2, MapScoutDB.schema)
	end)

	it("saves only what the player changed, also after an older version saved all", function()
		load()
		_G.MapScoutDB = { schema = 2, options = { maxResults = 50, waypoint = { native = false, tomtom = true } } }
		addonLoaded()
		assert.is_nil(rawget(MapScoutDB.options, "maxResults")) -- equal to the default: removed on load
		assert.is_true(rawget(MapScoutDB.options.waypoint, "tomtom")) -- changed: kept
		assert.are.equal(50, MapScoutDB.options.maxResults) -- still read through
		MapScoutDB.options.maxResults = 20
		MapScoutDB.options.waypoint.tomtom = false -- back to the default
		frame:Fire("PLAYER_LOGOUT")
		assert.are.equal(20, rawget(MapScoutDB.options, "maxResults"))
		assert.is_nil(rawget(MapScoutDB.options.waypoint, "tomtom"))
	end)

	it("/ms debug db shows the state and sizes", function()
		load()
		_G.MapScoutCharDB = { schema = 2, history = { "bank", "mail" } }
		addonLoaded()
		SlashCmdList.MAPSCOUT("debug db")
		local out = table.concat(ChatLog, "\n")
		assert.matches("schema 2 (current 2), account new, character current", out, 1, true)
		assert.matches("2 recent searches", out, 1, true)
	end)

	it("/ms debug lists the topics", function()
		load()
		SlashCmdList.MAPSCOUT("debug")
		assert.matches("/ms debug db", table.concat(ChatLog, "\n"), 1, true)
	end)
end)
