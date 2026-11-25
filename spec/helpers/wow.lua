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
