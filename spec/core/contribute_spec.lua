-- Core/Contribute.lua: the player turns contributing on or off
describe("Core/Contribute.lua", function()
	local ns, frame, npc

	local function strsplitStub(sep, text)
		local parts = {}
		for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
			parts[#parts + 1] = part
		end
		return unpack(parts)
	end

	-- A new session (after /reload or logging in), with what was saved
	local function session(saved)
		ResetWoW()
		_G.MapScoutDB = saved
		StubGlobals({
			strsplit = strsplitStub,
			GetTime = function() return 100 end,
			UnitIsGhost = function() return false end,
			UnitGUID = function() return npc.guid end,
			UnitName = function() return npc.name end,
			UnitFactionGroup = function() return "Alliance" end,
			IsInInstance = function() return false end,
			C_Map = {
				GetBestMapForUnit = function() return 1455 end,
				GetMapInfo = function() return nil end,
				GetPlayerMapPosition = function()
					return { GetXY = function() return 0.35612, 0.60433 end }
				end,
			},
		})
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "Core/Recorder.lua", "Core/Contribute.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	before_each(function()
		npc = { guid = "Creature-0-1-2-3-4092-000", name = "Banquero Tilda" }
		session(nil)
	end)

	it("is off by default, listening to nothing and keeping nothing", function()
		assert.is_false(ns.Contribute.IsOn())
		assert.is_false(ns.Recorder.IsRunning())
		frame:Fire("BANKFRAME_OPENED")
		assert.are.equal(0, ns.Contribute.Count())
		assert.is_nil(_G.MapScoutDB.contribution and _G.MapScoutDB.contribution.id)
	end)

	it("once on, keeps what the recorder notices, with an anonymous ID and no times", function()
		SlashCmdList.MAPSCOUT("contribute on")
		assert.is_true(ns.Recorder.IsRunning())
		frame:Fire("BANKFRAME_OPENED")
		local data = _G.MapScoutDB.contribution
		assert.matches("^%x+$", data.id)
		assert.are.equal(16, #data.id)
		assert.is_true(data.npcs[4092].services.bank)
		assert.is_nil(data.npcs[4092].at)
		assert.are.equal(1, ns.Contribute.Count())
	end)

	it("starts by itself every session until turned off", function()
		ns.Contribute.SetOn(true)
		session(_G.MapScoutDB)
		assert.is_true(ns.Recorder.IsRunning())
		SlashCmdList.MAPSCOUT("contribute off")
		session(_G.MapScoutDB)
		assert.is_false(ns.Recorder.IsRunning())
	end)

	it("stops listening at once when turned off, keeping what was saved", function()
		ns.Contribute.SetOn(true)
		frame:Fire("BANKFRAME_OPENED")
		SlashCmdList.MAPSCOUT("contribute off")
		assert.is_false(ns.Recorder.IsRunning())
		assert.is_nil(frame.events.BANKFRAME_OPENED)
		npc.guid = "Creature-0-1-2-3-5000-000"
		frame:Fire("BANKFRAME_OPENED")
		assert.are.equal(1, ns.Contribute.Count())
	end)

	it("clear forgets everything saved and the anonymous ID, and stays on", function()
		ns.Contribute.SetOn(true)
		frame:Fire("BANKFRAME_OPENED")
		local id = _G.MapScoutDB.contribution.id
		SlashCmdList.MAPSCOUT("contribute clear")
		assert.are.equal(0, ns.Contribute.Count())
		assert.is_nil(_G.MapScoutDB.contribution.id)
		assert.is_true(ns.Contribute.IsOn())
		assert.matches("We keep saving", ChatLog[#ChatLog], 1, true)
		frame:Fire("BANKFRAME_OPENED")
		assert.are_not.equal(id, _G.MapScoutDB.contribution.id) -- a new ID from then on
	end)

	it("status says whether it is on and how much is saved", function()
		SlashCmdList.MAPSCOUT("contribute status")
		assert.matches("no place is saved yet", ChatLog[#ChatLog], 1, true)
		ns.Contribute.SetOn(true)
		frame:Fire("BANKFRAME_OPENED")
		SlashCmdList.MAPSCOUT("contribute")
		assert.matches("thank you for helping improve MapScout. Right now one place is saved.", ChatLog[#ChatLog], 1, true)
		npc.guid = "Creature-0-1-2-3-5000-000"
		frame:Fire("BANKFRAME_OPENED")
		SlashCmdList.MAPSCOUT("contribute status")
		assert.matches("2 places are saved", ChatLog[#ChatLog], 1, true)
	end)

	it("tells whoever listens when it is turned on or off", function()
		local heard = {}
		ns.Contribute.Listen(function(on) heard[#heard + 1] = on end)
		ns.Contribute.SetOn(true)
		ns.Contribute.SetOn(false)
		assert.are.same({ true, false }, heard)
	end)

	it("is listed in /ms help", function()
		SlashCmdList.MAPSCOUT("help")
		assert.matches("/ms contribute", table.concat(ChatLog, "\n"), 1, true)
	end)
end)
