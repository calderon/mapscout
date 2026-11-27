-- Debug/Harvest.lua: the development-only harvest mode
describe("Debug/Harvest.lua", function()
	local ns, frame, npc, position, instance, now, death

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
		death = { ghost = false } -- release: where the game says the ghost will appear, on the continent
		StubGlobals({
			UnitIsGhost = function() return death.ghost end,
			C_DeathInfo = {
				GetDeathReleasePosition = function(mapID)
					local at = death.release
					return at and mapID == 1415 and { GetXY = function() return at.x, at.y end } or nil
				end,
			},
			GetTime = function() return now end,
			strsplit = strsplitStub,
			UnitGUID = function() return npc.guid end,
			UnitName = function() return npc.name end,
			UnitFactionGroup = function() return npc.faction end,
			CanMerchantRepair = function() return npc.repair end,
			C_Map = {
				GetBestMapForUnit = function() return position.map end,
				GetMapInfo = function(id)
					return ({ [1415] = { mapID = 1415, mapType = 2, parentMapID = 947 },
						[1455] = { mapID = 1455, mapType = 3, parentMapID = 1415 },
						[947] = { mapID = 947, mapType = 1, parentMapID = 0 } })[id]
				end,
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
		assert.are.same({ "Creature", 4092, "000" }, { ns.Harvest.ParseGUID("Creature-0-1-2-3-4092-000") })
		assert.are.same({ "GameObject", 32349, "000" }, { ns.Harvest.ParseGUID("GameObject-0-1-2-3-32349-000") })
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

	it("keeps every place an NPC was talked to, once each, telling apart NPCs that share an ID", function()
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("BANKFRAME_OPENED")
		frame:Fire("BANKFRAME_OPENED") -- the same spot again
		position.x, position.y = 0.40, 0.70
		frame:Fire("BANKFRAME_OPENED")
		npc.guid = "Creature-0-1-2-3-4092-001" -- another NPC with the same ID, at the same spot
		frame:Fire("BANKFRAME_OPENED")
		local record = ns.db.harvest.npcs[4092]
		assert.are.same({ { 1455, 0.3561, 0.6043, "000" }, { 1455, 0.4, 0.7, "000" }, { 1455, 0.4, 0.7, "001" } },
			record.seen)
		assert.are.same({ 0.4, 0.7 }, { record.x, record.y }) -- the last one
		for i = 1, 20 do
			ns.Harvest.AddSighting(record, 1455, i / 100, 0.1)
		end
		assert.are.equal(ns.Harvest.SIGHTINGS, #record.seen)
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

	it("records the skill a trainer teaches, from the first service that has one", function()
		SlashCmdList.MAPSCOUT("harvest on")
		local skills = { "", "Equitación", "Equitación" }
		StubGlobals({
			GetNumTrainerServices = function() return #skills end,
			GetTrainerServiceSkillLine = function(i) return skills[i] end,
		})
		frame:Fire("TRAINER_SHOW")
		local record = ns.db.harvest.npcs[4092]
		assert.are.same({ trainer = true }, record.services)
		assert.are.equal("Equitación", record.skill)
		skills = {} -- a window without services keeps what was learnt before
		frame:Fire("TRAINER_SHOW")
		assert.are.equal("Equitación", record.skill)
	end)

	it("records mailboxes as objects", function()
		SlashCmdList.MAPSCOUT("harvest on")
		npc.guid = nil
		frame:Fire("MAIL_SHOW")
		local _, object = next(ns.db.harvest.objects)
		assert.are.equal("mailbox", object.service)
		assert.are.equal(1455, object.map)
	end)

	-- the last entrance recorded for an instance (one record per entry)
	local function entrance(id)
		local found
		for _, record in pairs(ns.db.harvest.entrances) do
			if record.instance == id and (not found or record.at >= found.at) then
				found = record
			end
		end
		return found
	end

	it("pairs the last place outside with the instance entered next", function()
		SlashCmdList.MAPSCOUT("harvest on")
		position = { map = 1437, x = 0.4779, y = 0.5616 }
		frame:Fire("PLAYER_LEAVING_WORLD")
		instance = { inside = true, kind = "party", name = "Excavación: Los Humedales", id = 2998 }
		frame:Fire("PLAYER_ENTERING_WORLD")
		local record = entrance(2998)
		assert.are.same({ 1437, 0.4779, 0.5616, "party" }, { record.map, record.x, record.y, record.kind })
	end)

	it("keeps every entry of an instance, not only the last one", function()
		SlashCmdList.MAPSCOUT("harvest on")
		for i, x in ipairs({ 0.59, 0.62 }) do -- two doors of Dire Maul, a second apart
			StubGlobals({ time = function() return 1000 + i end })
			position = { map = 1444, x = x, y = 0.45 }
			frame:Fire("PLAYER_LEAVING_WORLD")
			instance = { inside = true, kind = "party", name = "La Masacre", id = 429 }
			frame:Fire("PLAYER_ENTERING_WORLD")
			instance = { inside = false }
			frame:Fire("PLAYER_ENTERING_WORLD")
		end
		local xs = {}
		for _, record in pairs(ns.db.harvest.entrances) do
			xs[#xs + 1] = record.x
		end
		table.sort(xs)
		assert.are.same({ 0.59, 0.62 }, xs)
	end)

	it("pairs too without a loading screen: the place noted every second, then a zone change", function()
		SlashCmdList.MAPSCOUT("harvest on")
		position = { map = 1455, x = 0.2763, y = 0.4783 }
		RunTimers()
		instance = { inside = true, kind = "party", name = "El Salón de los Feudales", id = 3065 }
		frame:Fire("ZONE_CHANGED_NEW_AREA")
		assert.are.equal(1455, entrance(3065).map)
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
		assert.are.equal(1455, entrance(3065).map)
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
	it("records the line under an NPC's name, to tell quartermasters apart", function()
		StubGlobals({
			C_TooltipInfo = {
				GetUnit = function() return { lines = { { leftText = "Tilda" }, { leftText = "Intendente" } } } end,
			},
		})
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("MERCHANT_SHOW")
		assert.are.equal("Intendente", ns.db.harvest.npcs[4092].title)
	end)

	it("records transmogrifiers and guild banks opened through the interaction manager", function()
		StubGlobals({ Enum = { PlayerInteractionType = { Merchant = 5, Transmogrifier = 3, GuildBanker = 10 } } })
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
		assert.are.same({ transmog = true }, ns.db.harvest.npcs[4092].services)
		npc.guid = "GameObject-0-1-2-3-187299-000"
		frame:Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
		local _, object = next(ns.db.harvest.objects)
		assert.are.equal("guildbank", object.service)
		assert.are.equal(187299, object.objectID)
		frame:Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5) -- has its own event: not twice
		assert.are.same({ transmog = true }, ns.db.harvest.npcs[4092].services)
	end)

	it("does not register events the client does not have", function()
		StubGlobals({ C_EventUtils = { IsEventValid = function(event) return event ~= "TRANSMOGRIFY_OPEN" end } })
		assert.is_false(ns.Harvest.HasEvent("TRANSMOGRIFY_OPEN"))
		assert.is_true(ns.Harvest.HasEvent("BANKFRAME_OPENED"))
		SlashCmdList.MAPSCOUT("harvest on")
		frame:Fire("TRANSMOGRIFY_OPEN")
		assert.is_nil(next(ns.db.harvest.npcs))
	end)

	it("notes anvils and forges where the player stands", function()
		SlashCmdList.MAPSCOUT("harvest here anvil")
		local key, object = next(ns.db.harvest.objects)
		assert.are.equal("anvil:1455:356:604", key)
		assert.are.same({ "anvil", 1455, 0.3561, 0.6043 }, { object.service, object.map, object.x, object.y })
		SlashCmdList.MAPSCOUT("harvest here chair")
		assert.matches("anvil|forge", ChatLog[#ChatLog], 1, true)
		assert.are.equal(1, #(function() local t = {} for k in pairs(ns.db.harvest.objects) do t[#t + 1] = k end return t end)())
	end)

	describe("graveyards", function()
		before_each(function()
			SlashCmdList.MAPSCOUT("harvest on")
			-- the continent's point, placed on its outdoor zone (Core/Util.lua does it in the game)
			ns.PlaceOutdoors = function(mapID, x, y)
				assert.are.equal(1415, mapID)
				return 1426, x + 0.06, y - 0.14
			end
		end)

		local function graveyards()
			local list = {}
			for key, record in pairs(ns.db.harvest.graveyards) do
				list[#list + 1] = { key = key, record = record }
			end
			return list
		end

		it("records on dying the graveyard the game names, asked on the continent", function()
			death.release = { x = 0.47939, y = 0.53830 }
			frame:Fire("PLAYER_DEAD")
			local list = graveyards()
			assert.are.equal(1, #list)
			assert.are.equal("death:" .. list[1].record.at, list[1].key)
			local r = list[1].record
			assert.are.same({ "death", 1426, 0.5394, 0.3983, 1415, 0.4794, 0.5383, 1455 },
				{ r.how, r.map, r.x, r.y, r.continent, r.cx, r.cy, r.died })
			assert.matches("cementerio guardado", ChatLog[#ChatLog], 1, true)
		end)

		it("says so when the game gives no point (inside an instance, or no answer)", function()
			death.release = nil
			frame:Fire("PLAYER_DEAD")
			assert.are.same({}, graveyards())
			assert.matches("NO guardado", ChatLog[#ChatLog], 1, true)
			death.release = { x = 0, y = 0 }
			frame:Fire("PLAYER_DEAD")
			assert.are.same({}, graveyards())
		end)

		it("records a spirit healer talked to as a ghost, not as a service NPC", function()
			death.ghost = true
			npc = { guid = "Creature-0-1-2-3-6491-000", name = "Ángel de la Resurrección" }
			position = { map = 1426, x = 0.5421, y = 0.3903 }
			frame:Fire("GOSSIP_SHOW")
			local list = graveyards()
			assert.are.equal(1, #list)
			local r = list[1].record
			assert.are.same({ "healer", 6491, 1426, 0.5421, 0.3903 }, { r.how, r.npc, r.map, r.x, r.y })
			assert.is_nil(next(ns.db.harvest.npcs))
			SlashCmdList.MAPSCOUT("harvest")
			assert.matches("1 cementerios", ChatLog[#ChatLog], 1, true)
		end)

		it("records nothing while off", function()
			SlashCmdList.MAPSCOUT("harvest off")
			death.release = { x = 0.47939, y = 0.53830 }
			frame:Fire("PLAYER_DEAD")
			death.ghost = true
			frame:Fire("GOSSIP_SHOW")
			assert.are.same({}, graveyards())
		end)
	end)
end)
