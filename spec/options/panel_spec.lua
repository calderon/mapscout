-- Options/Panel.lua: MapScout's page in the game's options
describe("Options/Panel.lua", function()
	local ns, frame, opened, registered

	before_each(function()
		ResetWoW()
		opened, registered = {}, {}
		StubGlobals({
			Settings = {
				RegisterCanvasLayoutCategory = function(panel, name)
					return { ID = 42, panel = panel, name = name, GetID = function(self) return self.ID end }
				end,
				RegisterAddOnCategory = function(category) registered[#registered + 1] = category end,
				OpenToCategory = function(id) opened[#opened + 1] = id end,
			},
		})
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "API/MapScoutAPI.lua", "Options/Panel.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("PLAYER_LOGIN")
	end)

	it("registers MapScout's page in the game's options at login", function()
		assert.are.equal(1, #registered)
		assert.are.equal("MapScout", registered[1].name)
		assert.are.equal(ns.Options.frame, registered[1].panel)
	end)

	it("fills the page only the first time it is shown, with its sections in order", function()
		local calls = {}
		ns.Options.AddSection(function(_, anchor) calls[#calls + 1] = anchor; return "first" end)
		ns.Options.AddSection(function(_, anchor) calls[#calls + 1] = anchor end)
		assert.are.same({}, calls)
		ns.Options.frame:Show()
		assert.are.equal(2, #calls)
		assert.are.equal("first", calls[2]) -- the second goes under the first
		ns.Options.frame:Hide()
		ns.Options.frame:Show()
		assert.are.equal(2, #calls) -- not built again
	end)

	it("opens with /ms alone, and /ms help still lists the commands", function()
		SlashCmdList.MAPSCOUT("")
		assert.are.same({ 42 }, opened)
		SlashCmdList.MAPSCOUT("help")
		assert.matches("/ms version", table.concat(ChatLog, "\n"), 1, true)
		assert.are.same({ 42 }, opened)
	end)

	it("in combat, opens when combat ends, saying so once", function()
		StubGlobals({ InCombatLockdown = function() return true end })
		SlashCmdList.MAPSCOUT("")
		SlashCmdList.MAPSCOUT("")
		assert.are.same({}, opened)
		assert.are.equal(1, #ChatLog)
		assert.matches("when combat ends", ChatLog[1], 1, true)
		_G.InCombatLockdown = function() return false end
		frame:Fire("PLAYER_REGEN_ENABLED")
		assert.are.same({ 42 }, opened)
		assert.is_nil(frame.events.PLAYER_REGEN_ENABLED)
	end)

	it("falls back to the help without the game's Settings", function()
		ResetWoW()
		local plain = LoadAddonFile("Core/Init.lua")
		local f = FakeFrames[1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "API/MapScoutAPI.lua", "Options/Panel.lua" }) do
			LoadAddonFile(file, plain)
		end
		f:Fire("PLAYER_LOGIN")
		SlashCmdList.MAPSCOUT("")
		assert.matches("/ms version", table.concat(ChatLog, "\n"), 1, true)
	end)
end)
