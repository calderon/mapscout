-- Core/Recorder.lua: the moments the game tells where something is
describe("Core/Recorder.lua", function()
	local ns, frame, Recorder, heard, npc, position, gossip

	local function strsplitStub(sep, text)
		local parts = {}
		for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
			parts[#parts + 1] = part
		end
		return unpack(parts)
	end

	local function listener(name)
		return function(kind, record, why)
			heard[#heard + 1] = { who = name, kind = kind, record = record, why = why }
		end
	end

	-- the events the game is asked for (the event frame of Core/Init.lua)
	local function events()
		local list = {}
		for event in pairs(frame.events) do
			list[#list + 1] = event
		end
		table.sort(list)
		return list
	end

	before_each(function()
		ResetWoW()
		heard = {}
		npc = { guid = "Creature-0-1-2-3-4092-000", name = "Banquero Tilda", faction = "Alliance" }
		position = { map = 1455, x = 0.35612, y = 0.60433 }
		gossip = { options = {}, poi = nil } -- poi: { map, x, y, name } the guard marked
		StubGlobals({
			strsplit = strsplitStub,
			GetTime = function() return 100 end,
			UnitIsGhost = function() return false end,
			UnitGUID = function() return npc.guid end,
			UnitName = function() return npc.name end,
			UnitFactionGroup = function() return npc.faction end,
			IsInInstance = function() return false end,
			C_Map = {
				GetBestMapForUnit = function() return position.map end,
				GetMapInfo = function(id)
					return ({ [1455] = { mapID = 1455, mapType = 3, parentMapID = 1415 },
						[1415] = { mapID = 1415, mapType = 2, parentMapID = 0 } })[id]
				end,
				GetPlayerMapPosition = function()
					return { GetXY = function() return position.x, position.y end }
				end,
			},
			C_GossipInfo = {
				GetOptions = function() return gossip.options end,
				SelectOption = function() gossip.options = {} end,
				GetPoiForUiMapID = function(mapID)
					return gossip.poi and gossip.poi.map == mapID and 0 or nil
				end,
				GetPoiInfo = function()
					local poi = gossip.poi
					return { name = poi.name, textureIndex = 7, position = { GetXY = function() return poi.x, poi.y end } }
				end,
			},
		})
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		LoadAddonFile("Core/Util.lua", ns)
		LoadAddonFile("Core/Recorder.lua", ns)
		Recorder = ns.Recorder
	end)

	it("listens to no event until someone starts it, and to none once the last one stops", function()
		assert.are.same({}, events())
		frame.scripts.OnEvent(frame, "BANKFRAME_OPENED") -- nobody is listening
		Recorder.Start("A", listener("A"))
		assert.is_true(Recorder.IsRunning())
		assert.is_true(frame.events.BANKFRAME_OPENED)
		assert.is_true(frame.events.PLAYER_DEAD)
		Recorder.Start("B", listener("B"))
		Recorder.Stop("A")
		assert.is_true(frame.events.BANKFRAME_OPENED) -- B still listens
		Recorder.Stop("B")
		assert.is_false(Recorder.IsRunning())
		assert.are.same({}, events())
		assert.are.equal(0, PendingTimers()) -- the place outside is no longer noted
	end)

	it("tells every listener, even when one of them fails", function()
		Recorder.Start("A", function() error("broken") end)
		Recorder.Start("B", listener("B"))
		frame:Fire("BANKFRAME_OPENED")
		assert.are.equal(1, #heard)
		assert.are.equal(1, #ReportedErrors)
	end)

	it("tells a service NPC with its place, and stores nothing", function()
		Recorder.Start("A", listener("A"))
		frame:Fire("BANKFRAME_OPENED")
		local r = heard[1].record
		assert.are.equal("npc", heard[1].kind)
		assert.are.same({ "bank", 4092, "000", "Banquero Tilda", "Alliance", 1455, 0.3561, 0.6043 },
			{ r.service, r.id, r.spawn, r.name, r.faction, r.map, r.x, r.y })
		assert.is_nil(ns.db)
	end)

	it("tells objects apart from NPCs", function()
		Recorder.Start("A", listener("A"))
		npc.guid = nil
		frame:Fire("MAIL_SHOW")
		assert.are.equal("object", heard[1].kind)
		assert.are.equal("mailbox", heard[1].record.service)
		npc.guid = "Player-1-2" -- neither a creature nor an object: nothing
		frame:Fire("BANKFRAME_OPENED")
		assert.are.equal(1, #heard)
	end)

	it("tells nothing when the game gives no position", function()
		Recorder.Start("A", listener("A"))
		position = { map = nil }
		frame:Fire("BANKFRAME_OPENED")
		assert.are.same({}, heard)
	end)

	it("tells why an entrance gave no place", function()
		Recorder.Start("A", listener("A"))
		StubGlobals({
			IsInInstance = function() return true, "pvp" end,
			GetInstanceInfo = function() return "Garganta Grito de Guerra", "pvp", 1, "", 5, 0, false, 489 end,
		})
		frame:Fire("PLAYER_ENTERING_WORLD")
		assert.are.equal("entrance", heard[1].kind)
		assert.is_nil(heard[1].record)
		assert.are.same({ "Garganta Grito de Guerra", "pvp", 489, true },
			{ heard[1].why.name, heard[1].why.kind, heard[1].why.instance, heard[1].why.place })
	end)

	it("tells the place a guard marks, only for the final answer", function()
		Recorder.Start("A", listener("A"))
		npc.guid = "Creature-0-1-2-3-5595-000"
		gossip.options = { { gossipOptionID = 11, name = "El banco" } }
		frame:Fire("GOSSIP_SHOW") -- the guard's options
		heard = {}
		gossip.poi = { map = 1455, x = 0.31, y = 0.61, name = "Banco de Forjaz" }
		C_GossipInfo.SelectOption(11)
		RunTimers()
		local directions = {}
		for _, h in ipairs(heard) do
			assert.are.equal("direction", h.kind)
			Recorder.AddDirection(directions, h.record)
		end
		assert.are.equal(2, #heard) -- looked for twice, the same answer
		local r = directions["1455:310:610"]
		assert.are.same({ "El banco", "Banco de Forjaz", 5595, 0.31 }, { r.asked, r.name, r.guard, r.x })
	end)

	it("tells no guard's answer while stopped, though its hook stays", function()
		Recorder.Start("A", listener("A"))
		Recorder.Stop("A")
		gossip.poi = { map = 1455, x = 0.31, y = 0.61, name = "Banco de Forjaz" }
		C_GossipInfo.SelectOption(11)
		RunTimers()
		assert.are.same({}, heard)
	end)

	describe("keeping", function()
		local function seen(x, y, spawn, service)
			return { service = service or "bank", id = 4092, spawn = spawn or "000", name = "Tilda", faction = "Alliance",
				locale = "esES", map = 1455, x = x, y = y, at = 1 }
		end

		it("reads the kind, ID and spawn of a GUID", function()
			assert.are.same({ "Creature", 4092, "000" }, { Recorder.ParseGUID("Creature-0-1-2-3-4092-000") })
			assert.is_nil(Recorder.ParseGUID(nil))
		end)

		it("keys a place on a map, with or without a prefix", function()
			assert.are.equal("mailbox:1455:356:604", Recorder.PlaceKey("mailbox", 1455, 0.3561, 0.6043))
			assert.are.equal("1455:356:604", Recorder.PlaceKey(nil, 1455, 0.3561, 0.6043))
		end)

		it("adds up an NPC's services and keeps every place, once per spawn", function()
			local npcs = {}
			Recorder.AddNPC(npcs, seen(0.35, 0.60))
			Recorder.AddNPC(npcs, seen(0.35, 0.60)) -- the same spot again
			local vendor = seen(0.40, 0.70, "000", "vendor")
			vendor.repair, vendor.title = true, "Intendente"
			Recorder.AddNPC(npcs, vendor)
			Recorder.AddNPC(npcs, seen(0.40, 0.70, "001")) -- another NPC with the same ID
			local entry = npcs[4092]
			assert.are.same({ bank = true, vendor = true, repair = true }, entry.services)
			assert.are.same({ { 1455, 0.35, 0.6, "000" }, { 1455, 0.4, 0.7, "000" }, { 1455, 0.4, 0.7, "001" } },
				entry.seen)
			assert.are.equal("Intendente", entry.title) -- kept when a later window does not say it
			for i = 1, 20 do
				Recorder.AddSighting(entry, 1455, i / 100, 0.1)
			end
			assert.are.equal(Recorder.SIGHTINGS, #entry.seen)
		end)

		it("keeps a trainer's skill and the gossip options", function()
			local npcs = {}
			local trainer = seen(0.35, 0.60, "000", "trainer")
			trainer.skill = "Equitación"
			Recorder.AddNPC(npcs, trainer)
			Recorder.AddNPC(npcs, seen(0.35, 0.60, "000", "trainer")) -- no skill this time
			local talk = seen(0.35, 0.60, "000", "gossip")
			talk.gossip = { "132052:Hazme tu hogar" }
			Recorder.AddNPC(npcs, talk)
			assert.are.same({ trainer = true }, npcs[4092].services)
			assert.are.equal("Equitación", npcs[4092].skill)
			assert.are.same({ "132052:Hazme tu hogar" }, npcs[4092].gossip)
		end)

		it("joins the questions that give one place, each once", function()
			local directions = {}
			local function ask(asked)
				return Recorder.AddDirection(directions, { map = 1455, x = 0.31, y = 0.61, asked = asked })
			end
			assert.is_truthy(ask("El banco"))
			assert.is_nil(ask("El banco"))
			assert.is_truthy(ask("Buzón"))
			assert.are.equal("Buzón | El banco", directions["1455:310:610"].asked)
		end)
	end)
end)
