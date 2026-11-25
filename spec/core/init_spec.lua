-- Core/Init.lua: event dispatcher and slash commands
describe("Core/Init.lua", function()
	local ns, frame

	before_each(function()
		ResetWoW()
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[1]
	end)

	describe("event dispatcher", function()
		it("calls the handler with the event and its arguments", function()
			local got
			ns.RegisterEvent("PLAYER_LOGIN", "test", function(...)
				got = { ... }
			end)
			assert.is_true(frame.events.PLAYER_LOGIN)
			frame:Fire("PLAYER_LOGIN", 1, "two")
			assert.are.same({ "PLAYER_LOGIN", 1, "two" }, got)
		end)

		it("calls every owner, and registering again replaces the owner's function", function()
			local calls = {}
			ns.RegisterEvent("E", "a", function() calls[#calls + 1] = "a1" end)
			ns.RegisterEvent("E", "b", function() calls[#calls + 1] = "b" end)
			ns.RegisterEvent("E", "a", function() calls[#calls + 1] = "a2" end)
			frame:Fire("E")
			assert.are.same({ "b", "a2" }, calls)
		end)

		it("stops listening to the game event when the last owner leaves", function()
			ns.RegisterEvent("E", "a", function() end)
			ns.RegisterEvent("E", "b", function() end)
			ns.UnregisterEvent("E", "a")
			assert.is_true(frame.events.E)
			ns.UnregisterEvent("E", "b")
			assert.is_nil(frame.events.E)
			ns.UnregisterEvent("E", "b") -- nothing to do, no error
		end)

		it("lets a handler unregister itself and others during the event", function()
			local calls = {}
			ns.RegisterEvent("E", "a", function()
				calls[#calls + 1] = "a"
				ns.UnregisterEvent("E", "a")
				ns.RegisterEvent("E", "c", function() calls[#calls + 1] = "c" end)
			end)
			ns.RegisterEvent("E", "b", function() calls[#calls + 1] = "b" end)
			frame:Fire("E")
			assert.are.same({ "a", "b" }, calls) -- c is new: next time
			frame:Fire("E")
			assert.are.same({ "a", "b", "b", "c" }, calls)
		end)

		it("reports an error in one handler and still runs the others", function()
			local ran = false
			ns.RegisterEvent("E", "bad", function() error("boom") end)
			ns.RegisterEvent("E", "good", function() ran = true end)
			frame:Fire("E")
			assert.is_true(ran)
			assert.are.equal(1, #ReportedErrors)
			assert.matches("boom", ReportedErrors[1])
		end)

		it("rejects bad arguments", function()
			assert.has_error(function() ns.RegisterEvent(nil, "a", function() end) end)
			assert.has_error(function() ns.RegisterEvent("E", nil, function() end) end)
			assert.has_error(function() ns.RegisterEvent("E", "a", "not a function") end)
		end)
	end)

	describe("slash commands", function()
		it("registers /mapscout and /ms", function()
			assert.are.equal("/mapscout", SLASH_MAPSCOUT1)
			assert.are.equal("/ms", SLASH_MAPSCOUT2)
			assert.are.equal(ns.HandleSlash, SlashCmdList.MAPSCOUT)
		end)

		it("splits the subcommand from the rest, ignoring case and spaces", function()
			assert.are.same({ "version", "" }, { ns.ParseCommand("  VERSION ") })
			assert.are.same({ "debug", "bench mail box" }, { ns.ParseCommand("debug bench mail box") })
			assert.are.same({ "", "" }, { ns.ParseCommand("") })
			assert.are.same({ "", "" }, { ns.ParseCommand(nil) })
		end)

		it("prints the version", function()
			SlashCmdList.MAPSCOUT("version")
			assert.matches("version " .. ns.VERSION, ChatLog[#ChatLog], 1, true)
		end)

		it("runs commands added by modules, with the rest of the text", function()
			local got
			ns.RegisterCommand("Echo", function(rest) got = rest end, "repeat text")
			SlashCmdList.MAPSCOUT("echo Hello There")
			assert.are.equal("Hello There", got)
		end)

		it("shows the help for an empty or unknown command", function()
			SlashCmdList.MAPSCOUT("")
			local help = table.concat(ChatLog, "\n")
			assert.matches("/ms version", help, 1, true)
			local before = #ChatLog
			SlashCmdList.MAPSCOUT("nonsense")
			assert.is_true(#ChatLog > before)
			assert.matches("/ms help", ChatLog[#ChatLog - 1] .. ChatLog[#ChatLog], 1, true)
		end)
	end)
end)
