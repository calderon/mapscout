-- Test helper (loaded by busted before the tests, see .busted).
-- Loads addon files the way the game does, and defines the few WoW API
-- functions that pure logic touches. Add stubs here only when a tested
-- module needs them; anything visual is tested in the game, not here.

local ADDON_NAME = "MapScout"

-- A fresh, empty addon namespace (the "ns" every addon file receives).
function NewNamespace()
	return {}
end

-- Runs an addon file like the game does: with the addon name and the
-- shared namespace as its "..." arguments. Returns the namespace.
function LoadAddonFile(path, ns)
	ns = ns or NewNamespace()
	local chunk = assert(loadfile(path))
	chunk(ADDON_NAME, ns)
	return ns
end

-- Minimal WoW API stubs
function GetLocale()
	return "enUS"
end

C_Timer = {
	-- Runs at once: tests don't wait for real time
	After = function(_, callback)
		callback()
	end,
}

-- The game's (and LuaJIT's) xpcall passes extra arguments to the function;
-- plain Lua 5.1 (used by the tests in GitHub) doesn't. Same behaviour here.
if not jit then
	local plainXpcall = xpcall
	-- luacheck: push ignore 121
	xpcall = function(fn, handler, ...)
		local args, n = { ... }, select("#", ...)
		return plainXpcall(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
	-- luacheck: pop
end

function strtrim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Fake frames: they remember registered events and scripts.
-- frame:Fire(event, ...) runs its OnEvent script like the game would.
local function newFrame(frameType, name)
	local frame = { type = frameType, name = name, events = {}, scripts = {} }
	function frame:RegisterEvent(event)
		self.events[event] = true
	end
	function frame:UnregisterEvent(event)
		self.events[event] = nil
	end
	function frame:SetScript(script, fn)
		self.scripts[script] = fn
	end
	function frame:Fire(event, ...)
		self.scripts.OnEvent(self, event, ...)
	end
	FakeFrames[#FakeFrames + 1] = frame
	return frame
end

-- Fresh fake game state: call it in before_each.
-- FakeFrames: frames created; ChatLog: chat lines; ReportedErrors: errors sent
-- to the game's error handler.
function ResetWoW()
	FakeFrames, ChatLog, ReportedErrors = {}, {}, {}
	SlashCmdList = {}
	CreateFrame = newFrame
	DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, msg)
			ChatLog[#ChatLog + 1] = msg
		end,
	}
	geterrorhandler = function()
		return function(err)
			ReportedErrors[#ReportedErrors + 1] = err
		end
	end
end
ResetWoW()
