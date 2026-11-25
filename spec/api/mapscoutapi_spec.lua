-- API/MapScoutAPI.lua: the public global, read-only, versioned, with a queue before login
describe("API/MapScoutAPI.lua", function()
	local ns, frame

	local function load()
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		LoadAddonFile("Core/Util.lua", ns)
		LoadAddonFile("API/MapScoutAPI.lua", ns)
		return ns.API
	end

	local function login()
		frame:Fire("PLAYER_LOGIN")
	end

	before_each(function()
		ResetWoW()
	end)

	it("creates the global with its version", function()
		load()
		assert.is_table(MapScoutAPI)
		assert.are.equal(1, MapScoutAPI.version)
		assert.is_false(MapScoutAPI:IsReady())
		login()
		assert.is_true(MapScoutAPI:IsReady())
		assert.is_true(MapScoutAPI.IsReady()) -- with "." as well
	end)

	it("is read-only: writing fails and changes nothing", function()
		load()
		assert.has_error(function() MapScoutAPI.version = 2 end)
		assert.has_error(function() MapScoutAPI.IsReady = function() return "hacked" end end)
		assert.has_error(function() MapScoutAPI.NewField = 1 end)
		assert.are.equal(1, MapScoutAPI.version)
		assert.is_false(MapScoutAPI:IsReady())
		assert.is_nil(rawget(MapScoutAPI, "NewField"))
		assert.is_false(getmetatable(MapScoutAPI))
	end)

	it("doesn't replace another MapScoutAPI already there", function()
		local other = {}
		_G.MapScoutAPI = other
		load()
		assert.are.equal(other, MapScoutAPI)
	end)

	describe("queue before PLAYER_LOGIN", function()
		it("stores queued calls and runs them in order at login, with all their arguments", function()
			local API = load()
			local calls = {}
			API.Define("Register", function(...)
				calls[#calls + 1] = { select("#", ...), ... }
			end, { queue = true })
			MapScoutAPI:Register("a", nil, 3)
			MapScoutAPI.Register("b")
			assert.are.same({}, calls)
			login()
			assert.are.same({ { 3, "a", nil, 3 }, { 1, "b" } }, calls)
		end)

		it("gives the caller the early result while waiting", function()
			local API = load()
			API.Define("Make", function() end, {
				queue = true,
				early = function(name) return { handle = name } end,
			})
			assert.are.same({ handle = "x" }, MapScoutAPI:Make("x"))
		end)

		it("runs calls at once after login, and functions without queue always", function()
			local API = load()
			local ran = {}
			API.Define("Queued", function(v) ran[#ran + 1] = v; return "done" end, { queue = true })
			API.Define("Direct", function(v) return v * 2 end)
			assert.are.equal(4, MapScoutAPI:Direct(2))
			login()
			assert.are.equal("done", MapScoutAPI:Queued("now"))
			assert.are.same({ "now" }, ran)
		end)

		it("reports an error in a queued call and still runs the next ones", function()
			local API = load()
			local ran = false
			API.Define("Bad", function() error("third-party bug") end, { queue = true })
			API.Define("Good", function() ran = true end, { queue = true })
			MapScoutAPI:Bad()
			MapScoutAPI:Good()
			login()
			assert.is_true(ran)
			assert.are.equal(1, #ReportedErrors)
			assert.matches("third-party bug", ReportedErrors[1], 1, true)
		end)
	end)

	it("SafeCall reports errors and returns false, or true and the results", function()
		local API = load()
		assert.are.same({ true, 1, 2 }, { API.SafeCall(function(a) return a, 2 end, 1) })
		assert.is_false((API.SafeCall(function() error("x") end)))
		assert.are.equal(1, #ReportedErrors)
	end)

	it("rejects repeated or bad function names", function()
		local API = load()
		assert.has_error(function() API.Define("IsReady", function() end) end)
		assert.has_error(function() API.Define(nil, function() end) end)
	end)

	it("/ms debug api shows version, state and functions", function()
		load()
		SlashCmdList.MAPSCOUT("debug api")
		assert.matches("MapScoutAPI version 1, ready: no, 0 calls waiting, functions: IsReady", ChatLog[#ChatLog], 1, true)
	end)

	it("CopyTable copies at any depth", function()
		load()
		local original = { a = { b = { 1 } } }
		local copy = ns.CopyTable(original)
		copy.a.b[1] = 2
		assert.are.equal(1, original.a.b[1])
		assert.are.equal("text", ns.CopyTable("text"))
	end)
end)
