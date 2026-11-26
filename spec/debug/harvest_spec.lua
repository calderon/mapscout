-- Debug/Harvest.lua: the development-only harvest mode
describe("Debug/Harvest.lua", function()
	local ns, frame, npc, position, instance, now

	local function strsplitStub(sep, text)
		local parts = {}
		for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
			parts[#parts + 1] = part
		end
		return unpack(parts)
	end

	before_each(function()
		ResetWoW()
		npc = { guid = "Creature-0-1-2-3-4092-000", name = "Banquero Tilda", faction = "Alliance" }
		position = { map = 1455, x = 0.35612, y = 0.60433 }
		instance = { inside = false }
		now = 100
		StubGlobals({
			GetTime = function() return now end,
			strsplit = strsplitStub,
			UnitGUID = function() return npc.guid end,
			UnitName = function() return npc.name end,
			UnitFactionGroup = function() return npc.faction end,
			CanMerchantRepair = function() return npc.repair end,
			C_Map = {
				GetBestMapForUnit = function() return position.map end,
				GetPlayerMapPosition = function()
					return { GetXY = function() return position.x, position.y end }
				end,
			},
			C_GossipInfo = { GetOptions = function() return { { icon = 132052, name = "Hazme tu hogar" } } end },
			IsInInstance = function() return instance.inside, instance.kind end,
			GetInstanceInfo = function() return instance.name, "party", 1, "", 5, 0, false, instance.id end,
		})
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "Debug/Harvest.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	it("reads the kind and ID of a GUID", function()
		assert.are.same({ "Creature", 4092 }, { ns.Harvest.ParseGUID("Creature-0-1-2-3-4092-000") })
		assert.are.same({ "GameObject", 32349 }, { ns.Harvest.ParseGUID("GameObject-0-1-2-3-32349-000") })
		assert.is_nil(ns.Harvest.ParseGUID(nil))
	end)

	it("records nothing while off, and service NPCs once on", function()
		frame:Fire("BANKFRAME_OPENED")
		assert.is_nil(ns.db.harvest)
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("BANKFRAME_OPENED")
		local record = ns.db.harvest.npcs[4092]
		assert.are.equal("Banquero Tilda", record.name)
		assert.are.equal("Alliance", record.faction)
		assert.are.same({ bank = true }, record.services)
		assert.are.same({ 1455, 0.3561, 0.6043 }, { record.map, record.x, record.y })
		SlashCmdList.MAPSCOUT("harvest")
		assert.matches("1 PNJ", ChatLog[#ChatLog], 1, true)
	end)

	it("adds services to the same NPC, repair included, and keeps its gossip options", function()
		SlashCmdList.MAPSCOUT("harvest on")
		npc.repair = true
		frame:Fire("MERCHANT_SHOW")
		frame:Fire("GOSSIP_SHOW")
		local record = ns.db.harvest.npcs[4092]
		assert.are.same({ vendor = true, repair = true }, record.services)
		assert.are.same({ "132052:Hazme tu hogar" }, record.gossip)
	end)

	it("records mailboxes as objects", function()
		SlashCmdList.MAPSCOUT("harvest on")
		npc.guid = nil
		frame:Fire("MAIL_SHOW")
		local _, object = next(ns.db.harvest.objects)
		assert.are.equal("mailbox", object.service)
		assert.are.equal(1455, object.map)
	end)

	it("pairs the last place outside with the instance entered next", function()
		SlashCmdList.MAPSCOUT("harvest on")
		position = { map = 1437, x = 0.4779, y = 0.5616 }
		frame:Fire("PLAYER_LEAVING_WORLD")
		instance = { inside = true, kind = "party", name = "Excavación: Los Humedales", id = 2998 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		local record = ns.db.harvest.entrances[2998]
		assert.are.same({ 1437, 0.4779, 0.5616, "party" }, { record.map, record.x, record.y, record.kind })
	end)

	it("pairs too without a loading screen: the place noted every second, then a zone change", function()
		SlashCmdList.MAPSCOUT("harvest on")
		position = { map = 1455, x = 0.2763, y = 0.4783 }
		RunTimers()
		instance = { inside = true, kind = "party", name = "El Salón de los Feudales", id = 3065 }
		frame:Fire("ZONE_CHANGED_NEW_AREA")
		assert.are.equal(1455, ns.db.harvest.entrances[3065].map)
		local messages = #ChatLog
		frame:Fire("PLAYER_ENTERING_WORLD") -- the same instance: nothing changes, no message
		assert.are.equal(messages, #ChatLog)
	end)

	it("says why when it cannot pair", function()
		SlashCmdList.MAPSCOUT("harvest on")
		instance = { inside = true, kind = "pvp", name = "Garganta Grito de Guerra", id = 489 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		assert.matches("NO guardada", ChatLog[#ChatLog], 1, true)
		assert.is_nil(next(ns.db.harvest.entrances))
	end)

	it("counts the age until leaving the world, not until the loading screen ends", function()
		SlashCmdList.MAPSCOUT("harvest on")
		position = { map = 1455, x = 0.2763, y = 0.4783 }
		now = now + 0.5
		frame:Fire("PLAYER_LEAVING_WORLD")
		now = now + 12 -- a long loading screen
		instance = { inside = true, kind = "party", name = "El Salón de los Feudales", id = 3065 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		assert.are.equal(1455, ns.db.harvest.entrances[3065].map)
	end)

	it("says when the game gives no position outside", function()
		position = { map = nil }
		SlashCmdList.MAPSCOUT("harvest on")
		instance = { inside = true, kind = "party", name = "El Salón de los Feudales", id = 3065 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		assert.matches("el juego no da posición", ChatLog[#ChatLog], 1, true)
	end)

	it("does not pair an old place outside", function()
		SlashCmdList.MAPSCOUT("harvest on")
		now = now + 10 -- ten seconds later (teleported, summoned...)
		instance = { inside = true, kind = "party", name = "Minas", id = 36 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		assert.is_nil(next(ns.db.harvest.entrances))
	end)

	it("does not pair when leaving from inside or entering the open world", function()
		instance = { inside = true, kind = "party", id = 36 }
		SlashCmdList.MAPSCOUT("harvest on") -- turned on inside an instance
		frame:Fire("PLAYER_LEAVING_WORLD") -- leaving an instance
		frame:Fire("PLAYER_ENTERING_WORLD")
		instance = { inside = false }
		frame:Fire("PLAYER_LEAVING_WORLD")
		frame:Fire("PLAYER_ENTERING_WORLD") -- a loading screen to the open world
		assert.is_nil(next(ns.db.harvest.entrances))
	end)

	it("stays on after a reload, and forgets everything on clear", function()
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("BANKFRAME_OPENED")
		frame:Fire("PLAYER_LOGIN") -- as after /reload
		SlashCmdList.MAPSCOUT("harvest clear")
		assert.is_true(ns.db.harvest.on)
		assert.is_nil(next(ns.db.harvest.npcs))
	end)
end)
