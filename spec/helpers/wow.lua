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
local newTimerAPI -- defined below

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
	time = os.time -- the game's time() is Lua's os.time()
	C_Timer = newTimerAPI()
end

-- Timers don't run by themselves: a test runs them with RunTimers(), the
-- way time passing would. PendingTimers() says how many are waiting.
local timers = {}

function RunTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do
		if not timer.cancelled then
			timer.callback()
			if timer.ticker and not timer.cancelled then
				table.insert(timers, timer) -- a ticker comes back
			end
		end
	end
end

function PendingTimers()
	local n = 0
	for _, timer in ipairs(timers) do
		if not timer.cancelled then
			n = n + 1
		end
	end
	return n
end

newTimerAPI = function()
	timers = {}
	return {
		After = function(seconds, callback)
			table.insert(timers, { seconds = seconds, callback = callback })
		end,
		NewTicker = function(seconds, callback)
			local timer = { seconds = seconds, callback = callback, ticker = true }
			function timer.Cancel(self)
				self.cancelled = true
			end
			table.insert(timers, timer)
			return timer
		end,
		NewTimer = function(seconds, callback)
			local timer = { seconds = seconds, callback = callback }
			function timer.Cancel(self)
				self.cancelled = true
			end
			table.insert(timers, timer)
			return timer
		end,
	}
end

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

-- The game's bit library (LuaJIT has it; plain Lua 5.1 in GitHub doesn't)
if not bit then
	bit = {
		band = function(a, b)
			local result, value = 0, 1
			while a > 0 and b > 0 do
				if a % 2 == 1 and b % 2 == 1 then
					result = result + value
				end
				a, b, value = math.floor(a / 2), math.floor(b / 2), value * 2
			end
			return result
		end,
	}
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
	table.insert(self.points, { ... })
end
function Frame:ClearAllPoints()
	self.points = {}
end
function Frame:GetWidth()
	return self.width
end
function Frame:SetWidth(width)
	self.width = width
end
function Frame:GetText()
	return rawget(self, "text") or "" -- rawget: unknown keys of fake frames are functions
end
function Frame:SetText(text)
	self.text = text
end
function Frame:SetFocus()
	self.focus = true
end
function Frame:ClearFocus()
	self.focus = false
end
function Frame:HasFocus()
	return self.focus == true
end
function Frame:SetChecked(checked)
	self.checked = checked and true or false
end
function Frame:GetChecked()
	return rawget(self, "checked") == true
end
function Frame:Enable()
	self.disabled = false
end
function Frame:Disable()
	self.disabled = true
end
function Frame:IsEnabled()
	return rawget(self, "disabled") ~= true
end
function Frame:GetStringHeight()
	-- about 14 per line of 40 characters of the text, for wrapping notes
	local text = rawget(self, "text") or ""
	return 14 * math.max(1, math.ceil(#text / 40))
end
function Frame:CreateAnimationGroup()
	return newFrame("AnimationGroup", nil, self)
end
function Frame:CreateAnimation()
	return newFrame("Animation", nil, self)
end
function Frame:SetParent(parent)
	self.parent = parent
end
function Frame:GetParent()
	return self.parent
end
function Frame:SetScale(scale)
	self.scale = scale
end
function Frame:GetHeight()
	return self.height
end
function Frame:SetHeight(height)
	self.height = height
end
function Frame:AddLine(text)
	local lines = rawget(self, "lines") or {}
	rawset(self, "lines", lines)
	table.insert(lines, text)
end
function Frame:CreateTexture()
	return newFrame("Texture", nil, self)
end
function Frame:CreateFontString()
	return newFrame("FontString", nil, self)
end
function Frame:CreateLine(_, layer)
	local line = newFrame("Line", nil, self)
	line.layer = layer
	return line
end
function Frame:SetStartPoint(...)
	self.startPoint = { ... }
end
function Frame:SetEndPoint(...)
	self.endPoint = { ... }
end

local FrameMeta = {
	__index = function(_, key)
		return Frame[key] or function() end
	end,
}

newFrame = function(frameType, name, parent, template)
	local frame = setmetatable({
		type = frameType, name = name, parent = parent, template = template, events = {}, scripts = {}, hooks = {},
		shown = true, level = (parent and parent.level or 0) + 1, width = 0, height = 0, points = {},
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
	GameTooltip = newFrame("GameTooltip", "GameTooltip")
	table.remove(FakeFrames) -- not one of the addon's frames
end
ResetWoW()
