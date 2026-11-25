-- Test helper (loaded by busted before the tests, see .busted).
-- Loads addon files the way the game does, and defines the few WoW API
-- functions that pure logic touches. Add stubs here only when a tested
-- module needs them; anything visual is tested in the game, not here.

local ADDON_NAME = "MapScout"

-- A fresh addon namespace (the "ns" every addon file receives), with the
-- language files already loaded, as in the game (they come first in the .toc).
function NewNamespace()
	local ns = {}
	for _, path in ipairs({ "Locales/enUS.lua", "Locales/esES.lua" }) do
		assert(loadfile(path))(ADDON_NAME, ns)
	end
	return ns
end

-- Runs an addon file like the game does: with the addon name and the
-- shared namespace as its "..." arguments. Returns the namespace.
function LoadAddonFile(path, ns)
	ns = ns or NewNamespace()
	local chunk = assert(loadfile(path))
	chunk(ADDON_NAME, ns)
	return ns
end

-- Minimal WoW API stubs: GetLocale, GetBuildInfo and IsMacClient are set
-- again by ResetWoW, so a test can replace them with StubGlobals.
local function baseStubs()
	GetLocale = function()
		return "enUS"
	end
	GetBuildInfo = function()
		return "1.60.1", "71139", "Nov 24 2026", 16001
	end
	IsMacClient = function()
		return false
	end
	debugprofilestop = function()
		return os.clock() * 1000
	end
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

-- Fake frames: they remember registered events, scripts, hooks, points,
-- size and level. frame:Fire(event, ...) runs OnEvent like the game would;
-- frame:Run(script, ...) runs a script and its hooks (OnShow, OnHide...).
-- Any other method exists and does nothing, so UI code can run in tests.
local newFrame -- defined below
local Frame = {}

function Frame:RegisterEvent(event)
	self.events[event] = true
end
function Frame:UnregisterEvent(event)
	self.events[event] = nil
end
function Frame:SetScript(script, fn)
	self.scripts[script] = fn
	self.hooks[script] = nil -- like the game: SetScript drops the hooks
end
function Frame:GetScript(script)
	return self.scripts[script]
end
function Frame:HookScript(script, fn)
	self.hooks[script] = self.hooks[script] or {}
	table.insert(self.hooks[script], fn)
end
function Frame:Run(script, ...)
	if self.scripts[script] then
		self.scripts[script](self, ...)
	end
	for _, fn in ipairs(self.hooks[script] or {}) do
		fn(self, ...)
	end
end
function Frame:Fire(event, ...)
	self.scripts.OnEvent(self, event, ...)
end
function Frame:Show()
	self.shown = true
	self:Run("OnShow")
end
function Frame:Hide()
	self.shown = false
	self:Run("OnHide")
end
function Frame:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function Frame:IsShown()
	return self.shown
end
function Frame:GetFrameLevel()
	return self.level
end
function Frame:SetFrameLevel(level)
	self.level = level
end
function Frame:GetSize()
	return self.width, self.height
end
function Frame:SetSize(width, height)
	self.width, self.height = width, height
end
function Frame:SetAllPoints(target)
	self.points = { { "ALL", target or self.parent } }
end
function Frame:SetPoint(...)
	self.points = self.points or {}
	table.insert(self.points, { ... })
end
function Frame:ClearAllPoints()
	self.points = {}
end
function Frame:CreateTexture()
	return newFrame("Texture", nil, self)
end
function Frame:CreateFontString()
	return newFrame("FontString", nil, self)
end

local FrameMeta = {
	__index = function(_, key)
		return Frame[key] or function() end
	end,
}

newFrame = function(frameType, name, parent)
	local frame = setmetatable({
		type = frameType, name = name, parent = parent, events = {}, scripts = {}, hooks = {},
		shown = true, level = (parent and parent.level or 0) + 1, width = 0, height = 0,
	}, FrameMeta)
	FakeFrames[#FakeFrames + 1] = frame
	return frame
end

-- hooksecurefunc(table, "Method", fn): fn runs after the method, like the game
local function fakeHooksecurefunc(target, method, fn)
	local original = target[method]
	target[method] = function(...)
		local results = { original(...) }
		fn(...)
		return unpack(results)
	end
end

-- Globals set by StubGlobals, removed by the next ResetWoW
local stubbed = {}

-- Sets fake game globals for one test: StubGlobals({ C_Map = { ... } })
-- (writes the real global table: assignments inside a test file stay local to it)
function StubGlobals(values)
	for name, value in pairs(values) do
		stubbed[name] = true
		_G[name] = value
	end
end

function ResetWoW()
	for name in pairs(stubbed) do
		_G[name] = nil
	end
	stubbed = {}
	MapScoutAPI, MapScoutDB, MapScoutCharDB = nil, nil, nil
	baseStubs()
	FakeFrames, ChatLog, ReportedErrors = {}, {}, {}
	SlashCmdList = {}
	CreateFrame = newFrame
	hooksecurefunc = fakeHooksecurefunc
	InCombatLockdown = function()
		return false
	end
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
