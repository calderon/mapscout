-- MapScout: the public global MapScoutAPI.
-- Other addons (and MapScout's own providers) only talk to MapScout through it.
--   * Read-only: writing a field raises an error and never changes MapScout.
--   * Versioned: MapScoutAPI.version (an integer) goes up only with incompatible
--     changes; additions keep it.
--   * Calls that register things before PLAYER_LOGIN are queued and applied in
--     order once MapScout is ready (saved data and options loaded).
--   * Third-party functions MapScout calls back run through ns.API.SafeCall,
--     so an error in another addon is reported but never breaks MapScout.
--   * Tables handed to other addons are copies (ns.CopyTable).
-- Functions can be called with ":" or ".": MapScoutAPI:Foo(x) == MapScoutAPI.Foo(x).
-- Internal modules add functions with ns.API.Define (see API/Registry.lua).

local _, ns = ...
local L = ns.L

local API = {}
ns.API = API

API.VERSION = 1

local methods = {} -- name -> public function
local ready = false
local queue = {} -- { name, n, args } waiting for PLAYER_LOGIN

local proxy = setmetatable({}, {
	__index = function(_, key)
		if key == "version" then
			return API.VERSION
		end
		return methods[key]
	end,
	__newindex = function(_, key)
		error("MapScoutAPI is read-only (tried to set '" .. tostring(key) .. "')", 2)
	end,
	__metatable = false, -- getmetatable(MapScoutAPI) gives nothing to change
})

-- Calls fn(...) catching any error: the error goes to the game's error
-- handler (so the player sees which addon failed) and MapScout goes on.
-- Returns true and fn's results, or false.
function API.SafeCall(fn, ...)
	return xpcall(fn, geterrorhandler(), ...)
end

-- Adds a public function.
--   fn(...) does the work (without the self argument).
--   opts.queue: before PLAYER_LOGIN, the call is stored and run later, in
--     order; the caller then gets opts.early(...) (or nothing) right away.
function API.Define(name, fn, opts)
	assert(type(name) == "string" and methods[name] == nil, "bad or repeated API name: " .. tostring(name))
	assert(type(fn) == "function", "fn must be a function")
	opts = opts or {}
	methods[name] = function(...)
		local n = select("#", ...)
		local args = { ... }
		local first = 1
		if args[1] == proxy then -- called with ":"
			first = 2
		end
		if opts.queue and not ready then
			queue[#queue + 1] = { name = name, fn = fn, n = n, first = first, args = args }
			if opts.early then
				return opts.early(unpack(args, first, n))
			end
			return
		end
		return fn(unpack(args, first, n))
	end
end

function API.IsReady()
	return ready
end

-- Runs the queued calls in order. Called once, at PLAYER_LOGIN.
function API.Start()
	if ready then
		return
	end
	ready = true
	local pending = queue
	queue = {}
	for _, call in ipairs(pending) do
		API.SafeCall(call.fn, unpack(call.args, call.first, call.n))
	end
end

ns.RegisterEvent("PLAYER_LOGIN", "API", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "API")
	API.Start()
end)

API.Define("IsReady", API.IsReady)

-- Don't replace another copy of MapScout's API (e.g. a second MapScout folder)
if MapScoutAPI == nil then
	MapScoutAPI = proxy
end
API.proxy = proxy

-- /ms debug api ------------------------------------------------------------

ns.RegisterDebug("api", function()
	local names = {}
	for name in pairs(methods) do
		names[#names + 1] = name
	end
	table.sort(names)
	ns.Print(L.DEBUG_API_RESULT:format(API.VERSION, ready and L.YES or L.NO, #queue, table.concat(names, ", ")))
end, L.DEBUG_API)
