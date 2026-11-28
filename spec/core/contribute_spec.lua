-- Core/Contribute.lua: the player turns contributing on or off
describe("Core/Contribute.lua", function()
	local ns, frame, npc, pack, combat, here

	-- Every map is a rectangle of the world: 1455 (Ironforge) 1000 x 700 yards,
	-- 1426 (Dun Morogh) 5000 x 3500 yards around it, both on continent 0
	local WORLD = { [1455] = { 0, 2000, 1500, 1000, 700 }, [1426] = { 0, 0, 0, 5000, 3500 } }
	local function vector(x, y)
		return { x = x, y = y, GetXY = function() return x, y end }
	end
	local function worldPos(mapID, v)
		local map = WORLD[mapID]
		if not map then
			return nil
		end
		return map[1], vector(map[2] + v.x * map[4], map[3] + v.y * map[5])
	end

	-- A data pack with what each test puts in it
	local function fakePack(categories)
		local built = {}
		for name, data in pairs(categories) do
			built[name] = function() return data end
		end
		rawset(_G, "MapScoutDataForever", { categories = built })
	end

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
			InCombatLockdown = function() return combat end,
			WOW_PROJECT_ID = 18,
			CreateVector2D = vector,
			C_AddOns = {
				LoadAddOn = function() return pack ~= nil end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function(_, field) return field == "Version" and pack and pack.version or nil end,
			},
			C_Map = {
				GetBestMapForUnit = function() return 1455 end,
				GetMapInfo = function() return nil end,
				GetWorldPosFromMapPos = worldPos,
				GetPlayerMapPosition = function()
					return { GetXY = function() return here[1], here[2] end }
				end,
			},
		})
		rawset(_G, "MapScoutDataForever", nil)
		if pack then
			fakePack(pack.categories)
		end
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "Core/Packs.lua", "Core/Recorder.lua",
			"Core/PackCheck.lua", "Core/Contribute.lua", "Core/ContributeExport.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end

	before_each(function()
		npc = { guid = "Creature-0-1-2-3-4092-000", name = "Banquero Tilda" }
		pack, combat, here = nil, false, { 0.35612, 0.60433 }
		session(nil)
	end)

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
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
		assert.matches("no location is saved yet", ChatLog[#ChatLog], 1, true)
		ns.Contribute.SetOn(true)
		frame:Fire("BANKFRAME_OPENED")
		SlashCmdList.MAPSCOUT("contribute")
		assert.matches("thank you for helping improve MapScout. Right now one location is saved.", ChatLog[#ChatLog], 1, true)
		npc.guid = "Creature-0-1-2-3-5000-000"
		frame:Fire("BANKFRAME_OPENED")
		SlashCmdList.MAPSCOUT("contribute status")
		assert.matches("2 locations are saved", ChatLog[#ChatLog], 1, true)
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
	describe("tells the player in the chat", function()
		local function said(text)
			for _, line in ipairs(ChatLog) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end

		it("at login while on, with how many locations are new (not sent)", function()
			ns.Contribute.SetOn(true)
			frame:Fire("BANKFRAME_OPENED")
			npc.guid = "Creature-0-1-2-3-5000-000"
			frame:Fire("BANKFRAME_OPENED")
			_G.MapScoutDB.contribution.npcs[4092].sent = true
			session(_G.MapScoutDB)
			assert.are.same({ "|cff33ff99MapScout|r: v0.0.0 loaded. "
				.. "You have 1 new location ready to share with /ms contribute." }, ChatLog)
		end)

		it("at login says when nothing is new yet, and while off how to turn it on", function()
			ns.Contribute.SetOn(true)
			session(_G.MapScoutDB)
			assert.are.same({ "|cff33ff99MapScout|r: v0.0.0 loaded. Thank you for helping improve MapScout." }, ChatLog)
			ns.Contribute.SetOn(false)
			session(_G.MapScoutDB)
			assert.are.same({ "|cff33ff99MapScout|r: v0.0.0 loaded. Help us improve MapScout with /ms contribute on. "
				.. "For more help type /ms help" }, ChatLog)
		end)

		it("each new location once, with what it is", function()
			ns.Contribute.SetOn(true)
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal("|cff33ff99MapScout|r: location saved: Banquero Tilda (Bank).", ChatLog[#ChatLog])
			local lines = #ChatLog
			frame:Fire("BANKFRAME_OPENED") -- kept already
			frame:Fire("MERCHANT_SHOW") -- one more service of the same NPC
			assert.are.equal(lines, #ChatLog)
			npc.guid = nil
			frame:Fire("MAIL_SHOW")
			assert.matches("location saved: Mailbox.", ChatLog[#ChatLog], 1, true)
		end)

		it("a dungeon once, even entered again by another spot", function()
			ns.Contribute.SetOn(true)
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.3, y = 0.3 })
			assert.matches("location saved: Gnomeregan (Dungeon).", ChatLog[#ChatLog], 1, true)
			local lines = #ChatLog
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.4, y = 0.3 })
			assert.are.equal(lines, #ChatLog)
			assert.are.equal(2, ns.Contribute.Count())
		end)

		it("a guard's answer with the question asked, and a graveyard", function()
			ns.Contribute.SetOn(true)
			ns.Contribute.Keep("direction", { map = 1455, x = 0.2, y = 0.2, name = "Las Arcas", locale = "esES", asked = "Banco" })
			assert.matches("location saved: Las Arcas (Banco).", ChatLog[#ChatLog], 1, true)
			ns.Contribute.Keep("healer", { npc = 6491, map = 1426, x = 0.7, y = 0.7 })
			assert.matches("location saved: Graveyard.", ChatLog[#ChatLog], 1, true)
		end)

		it("each location can be silenced without turning contributing off, also after clear", function()
			ns.Contribute.SetOn(true)
			SlashCmdList.MAPSCOUT("contribute messages off")
			assert.matches("we keep saving them", ChatLog[#ChatLog], 1, true)
			SlashCmdList.MAPSCOUT("contribute clear")
			local lines = #ChatLog
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(lines, #ChatLog)
			assert.are.equal(1, ns.Contribute.Count())
			session(_G.MapScoutDB)
			assert.is_true(ns.Contribute.IsOn())
			assert.is_true(said("v0.0.0 loaded. You have 1 new location")) -- the login line always
			SlashCmdList.MAPSCOUT("contribute messages on")
			npc.guid = "Creature-0-1-2-3-5000-000"
			frame:Fire("BANKFRAME_OPENED")
			assert.matches("location saved:", ChatLog[#ChatLog], 1, true)
		end)

		it("says nothing while off", function()
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.3, y = 0.3 })
			assert.is_false(said("location saved"))
		end)
	end)

	describe("keeps only what the data pack lacks", function()
		local services, trainers, dungeons, healers

		-- Logs in with that pack and turns contributing on
		local function withPack(version)
			pack = { version = version or "0.2.0", categories = {
				services = services, trainers = trainers, dungeons = dungeons, spirithealers = healers,
			} }
			session(_G.MapScoutDB)
			ns.Contribute.SetOn(true)
		end

		local function kept(kind)
			local n = 0
			for _ in pairs(_G.MapScoutDB.contribution[kind] or {}) do
				n = n + 1
			end
			return n
		end

		before_each(function()
			services = {
				maps = { [1455] = { { "bank", 3561, 6043, "Alliance", "esES", 1 }, { "mailbox", 5000, 5000, "", "", 0 } } },
				names = { esES = { "Las Arcas" } },
			}
			trainers = { maps = { [1455] = { { "class", "MAGE", 2000, 2000, "Alliance", "esES", 1 } } },
				names = { esES = { "Sala de los Misterios" } } }
			dungeons = {
				entrances = { [90] = { "dungeon", 1426, 5000, 5000, 26 }, [91] = { "dungeon", 0, 0, 0, 0 } },
				doors = { [189] = { { "library", 1426, 1000, 1000 } } },
			}
			healers = { maps = { [1426] = { { 4000, 4286 } } } }
		end)

		it("not a service the pack has near that place, but one farther away", function()
			withPack()
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(0, ns.Contribute.Count())
			here = { 0.38612, 0.60433 } -- 30 yards away
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(1, ns.Contribute.Count())
			assert.are.same({}, ReportedErrors)
		end)

		it("everything useful when there is no pack", function()
			ns.Contribute.SetOn(true)
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(1, ns.Contribute.Count())
		end)

		it("not what the pack never needs: flight masters, gossip", function()
			ns.Contribute.SetOn(true)
			frame:Fire("TAXIMAP_OPENED")
			frame:Fire("GOSSIP_SHOW")
			assert.are.equal(0, ns.Contribute.Count())
		end)

		it("every vendor, with its title (quartermasters), even where the pack has repairs", function()
			services.maps[1455][1] = { "repair", 3561, 6043, "Alliance", "esES", 1 }
			withPack()
			StubGlobals({ C_TooltipInfo = { GetUnit = function()
				return { lines = { {}, { leftText = "Intendente de Forjaz" } } }
			end } })
			frame:Fire("MERCHANT_SHOW")
			local vendor = _G.MapScoutDB.contribution.npcs[4092]
			assert.is_true(vendor.services.vendor)
			assert.are.equal("Intendente de Forjaz", vendor.title)
		end)

		it("holds vendors apart from the other NPCs", function()
			ns.Contribute.SetOn(true)
			ns.Contribute.MAX.vendors = 1
			frame:Fire("MERCHANT_SHOW")
			npc.guid = "Creature-0-1-2-3-5000-000"
			frame:Fire("MERCHANT_SHOW") -- no room for another vendor
			frame:Fire("BANKFRAME_OPENED") -- but for a banker
			assert.are.equal(2, kept("npcs"))
			assert.is_nil(_G.MapScoutDB.contribution.npcs[5000].services.vendor)
			ns.Contribute.MAX.vendors = 150
		end)

		it("not a trainer or a mailbox the pack has there", function()
			withPack()
			here = { 0.2, 0.2 }
			frame:Fire("TRAINER_SHOW")
			npc.guid = nil
			here = { 0.5003, 0.5 }
			frame:Fire("MAIL_SHOW")
			assert.are.equal(0, ns.Contribute.Count())
			here = { 0.6, 0.5 }
			frame:Fire("MAIL_SHOW")
			assert.are.equal(1, kept("objects"))
		end)

		it("not a guard's answer the pack has, by its name in that language", function()
			withPack()
			local answer = { map = 1455, x = 0.3561, y = 0.6043, name = "Las Arcas", locale = "esES", asked = "Banco" }
			ns.Contribute.Keep("direction", answer)
			assert.are.equal(0, ns.Contribute.Count())
			answer.locale = "enUS" -- the pack has no English name for it yet
			ns.Contribute.Keep("direction", answer)
			assert.are.equal(1, kept("directions"))
			ns.Contribute.Keep("direction", { map = 1455, x = 0.2, y = 0.2, name = "Sala de los Misterios",
				locale = "esES", asked = "Instructor de clases > Mago" })
			assert.are.equal(1, kept("directions"))
		end)

		it("not an entrance or door the pack has, but one not confirmed yet", function()
			withPack()
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.501, y = 0.5 })
			ns.Contribute.Keep("entrance", { instance = 189, name = "Monasterio", kind = "party", map = 1426, x = 0.1, y = 0.1 })
			assert.are.equal(0, ns.Contribute.Count())
			ns.Contribute.Keep("entrance", { instance = 91, name = "Nueva", kind = "party", map = 1426, x = 0.3, y = 0.3 })
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.6, y = 0.5 })
			assert.are.equal(2, kept("entrances"))
		end)

		it("not a graveyard the pack has, measured on another map of the continent", function()
			withPack()
			-- (0.4, 0.4286) of Dun Morogh is (0, 0) of Ironforge's map: 2000, 1500 yards
			ns.Contribute.Keep("death", { map = 1455, x = 0, y = 0, continent = 1415 })
			assert.are.equal(0, ns.Contribute.Count())
			ns.Contribute.Keep("healer", { npc = 6491, map = 1426, x = 0.7, y = 0.7 })
			assert.are.equal(1, kept("graveyards"))
		end)

		it("builds the pack only for the check, and gives the memory back", function()
			withPack()
			frame:Fire("BANKFRAME_OPENED")
			assert.are.same({}, ns.Packs.Built())
			ns.Packs.Get("services") -- its provider is on: it stays
			frame:Fire("BANKFRAME_OPENED")
			assert.are.same({ "services" }, ns.Packs.Built())
		end)

		it("checks nothing in combat, and keeps it when the fight is over", function()
			ns.Contribute.SetOn(true)
			combat = true
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(0, ns.Contribute.Count())
			combat = false
			frame:Fire("PLAYER_REGEN_ENABLED")
			assert.are.equal(1, ns.Contribute.Count())
			assert.is_nil(frame.events.PLAYER_REGEN_ENABLED)
		end)

		it("holds at most MAX of each kind; a sent one makes room", function()
			ns.Contribute.SetOn(true)
			ns.Contribute.MAX.objects = 2
			npc.guid = nil
			for i = 1, 3 do
				here = { 0.1 * i, 0.5 }
				frame:Fire("MAIL_SHOW")
			end
			assert.are.equal(2, kept("objects"))
			local _, first = next(_G.MapScoutDB.contribution.objects)
			first.sent = true
			frame:Fire("MAIL_SHOW")
			assert.are.equal(2, kept("objects"))
			assert.is_nil(_G.MapScoutDB.contribution.objects[next(_G.MapScoutDB.contribution.objects)].sent)
			ns.Contribute.MAX.objects = 100
		end)

		it("drops what a new pack version has gained, sent or not, once per version", function()
			ns.Contribute.SetOn(true)
			frame:Fire("BANKFRAME_OPENED") -- no pack yet: kept
			_G.MapScoutDB.contribution.npcs[4092].sent = true
			npc.guid = "Creature-0-1-2-3-5000-000"
			here = { 0.9, 0.9 }
			frame:Fire("BANKFRAME_OPENED")
			assert.are.equal(2, ns.Contribute.Count())
			withPack("0.3.0")
			RunTimers()
			assert.are.equal(1, ns.Contribute.Count())
			assert.is_nil(_G.MapScoutDB.contribution.npcs[4092])
			assert.are.equal("0.3.0", _G.MapScoutDB.contribution.pack)
			assert.are.same({}, ns.Packs.Built())
			services.maps[1455][3] = { "bank", 9000, 9000, "Alliance", "esES", 1 }
			withPack("0.3.0") -- same version: not checked again
			RunTimers()
			assert.are.equal(1, ns.Contribute.Count())
		end)
	end)

	describe("export", function()
		it("has nothing to send before anything is kept", function()
			assert.are.same({ nil, 0 }, { ns.Contribute.Export.Text() })
		end)

		it("is a header and one line per record not sent, in a fixed format", function()
			pack = { version = "0.2.0", categories = {} }
			session(nil)
			ns.Contribute.SetOn(true)
			StubGlobals({ CanMerchantRepair = function() return true end })
			npc.name = "Banquero\tTilda"
			frame:Fire("BANKFRAME_OPENED")
			frame:Fire("MERCHANT_SHOW")
			ns.Contribute.Keep("entrance", { instance = 90, name = "Gnomeregan", kind = "party", map = 1426, x = 0.3, y = 0.3 })
			ns.Contribute.Keep("direction", { map = 1455, x = 0.2, y = 0.2, name = "Las Arcas", locale = "esES",
				asked = "Banco", poi = 0, texture = 7, guard = 5595 })
			ns.Contribute.Keep("death", { map = 1426, x = 0.4, y = 0.4, continent = 1415, cx = 0.5, cy = 0.6, died = 1455 })
			npc.guid = nil
			frame:Fire("MAIL_SHOW")
			local text, n = ns.Contribute.Export.Text()
			assert.are.equal(5, n)
			local id = _G.MapScoutDB.contribution.id
			assert.are.same({
				"contribution\t1\t" .. id .. "\tenUS\t0.2.0\t1.60.1.71139",
				"npc\t4092\tenUS\tBanquero Tilda\tAlliance\t\tbank repair vendor\t\t1455\t0.3561\t0.6043\t1455:0.3561:0.6043:000",
				"object\tmailbox\t\t1455\t0.3561\t0.6043",
				"entrance\t90\tGnomeregan\tparty\t1426\t0.3\t0.3",
				"direction\tesES\tBanco\tLas Arcas\t0\t7\t5595\t1455\t0.2\t0.2",
				"graveyard\tdeath\t\t1426\t0.4\t0.4\t1415\t0.5\t0.6\t1455",
			}, { strsplitStub("\n", text) })
			_G.MapScoutDB.contribution.npcs[4092].sent = true
			text, n = ns.Contribute.Export.Text()
			assert.are.equal(4, n)
			assert.is_nil(text:find("npc\t", 1, true))
		end)
	end)
end)
