-- MapScout: namespace, event dispatcher and slash commands.
-- First file loaded: every other module adds itself to the shared namespace ns
-- and listens to game events through ns.RegisterEvent (never its own frame).

local ADDON_NAME, ns = ...

-- Kept up to date by release-please (the game doesn't re-read the .toc on /reload)
ns.VERSION = "0.0.0" -- x-release-please-version
ns.NAME = ADDON_NAME

-- Chat output -------------------------------------------------------------

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MapScout|r: " .. tostring(msg))
end

-- Event dispatcher ---------------------------------------------------------
-- ns.RegisterEvent(event, owner, fn): fn(event, ...) is called for the event.
-- One function per owner and event: registering again replaces it.
-- Lists are copied on change, so handlers may register or unregister while
-- an event is being dispatched without breaking the loop.
-- An error in one handler is reported and the other handlers still run.

local eventFrame = CreateFrame("Frame")
local handlers = {} -- event -> { { owner = owner, fn = fn }, ... }

local function copyWithout(list, owner)
	local copy = {}
	if list then
		for _, h in ipairs(list) do
			if h.owner ~= owner then
				copy[#copy + 1] = h
			end
		end
	end
	return copy
end

function ns.RegisterEvent(event, owner, fn)
	assert(type(event) == "string", "event must be a string")
	assert(owner ~= nil, "owner is required")
	assert(type(fn) == "function", "fn must be a function")
	local list = copyWithout(handlers[event], owner)
	list[#list + 1] = { owner = owner, fn = fn }
	if not handlers[event] then
		eventFrame:RegisterEvent(event)
	end
	handlers[event] = list
end

function ns.UnregisterEvent(event, owner)
	local list = handlers[event]
	if not list then
		return
	end
	list = copyWithout(list, owner)
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	else
		handlers[event] = list
	end
end

local function dispatch(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		xpcall(list[i].fn, geterrorhandler(), event, ...)
	end
end
eventFrame:SetScript("OnEvent", dispatch)

-- Slash commands -----------------------------------------------------------
-- /mapscout and /ms. Modules add subcommands with ns.RegisterCommand.
-- Subcommands are in English only.

local commands = {} -- name -> { fn = fn, help = text }
local commandOrder = {}

function ns.RegisterCommand(name, fn, help)
	assert(type(name) == "string" and name ~= "", "name is required")
	assert(type(fn) == "function", "fn must be a function")
	name = name:lower()
	if not commands[name] then
		commandOrder[#commandOrder + 1] = name
	end
	commands[name] = { fn = fn, help = help }
end

local function printHelp()
	ns.Print("commands (/mapscout or /ms):")
	for _, name in ipairs(commandOrder) do
		local help = commands[name].help
		if help then
			DEFAULT_CHAT_FRAME:AddMessage("  /ms " .. name .. " - " .. help)
		end
	end
end

-- Returns the subcommand (lowercase) and the rest of the text.
function ns.ParseCommand(text)
	local name, rest = strtrim(text or ""):match("^(%S*)%s*(.-)$")
	return name:lower(), rest
end

function ns.HandleSlash(text)
	local name, rest = ns.ParseCommand(text)
	local command = commands[name]
	if command then
		command.fn(rest)
	else
		printHelp()
	end
end

ns.RegisterCommand("help", printHelp, "this list")
ns.RegisterCommand("version", function()
	ns.Print("version " .. ns.VERSION)
end, "show the version")

-- /ms debug <topic>: developer checks that modules add with ns.RegisterDebug.
local debugTopics = {} -- name -> { fn = fn, help = text }
local debugOrder = {}

function ns.RegisterDebug(name, fn, help)
	assert(type(name) == "string" and name ~= "", "name is required")
	assert(type(fn) == "function", "fn must be a function")
	name = name:lower()
	if not debugTopics[name] then
		debugOrder[#debugOrder + 1] = name
	end
	debugTopics[name] = { fn = fn, help = help }
end

ns.RegisterCommand("debug", function(rest)
	local name, args = ns.ParseCommand(rest)
	local topic = debugTopics[name]
	if topic then
		topic.fn(args)
		return
	end
	ns.Print("debug topics:")
	for _, topicName in ipairs(debugOrder) do
		DEFAULT_CHAT_FRAME:AddMessage("  /ms debug " .. topicName .. " - " .. (debugTopics[topicName].help or ""))
	end
end, "developer checks (/ms debug for the list)")

SLASH_MAPSCOUT1 = "/mapscout"
SLASH_MAPSCOUT2 = "/ms"
SlashCmdList.MAPSCOUT = ns.HandleSlash
