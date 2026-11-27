-- MapScout: the static data packs (LoadOnDemand addons, one per game flavor).
-- Packs.Get("dungeons") loads the pack the first time a category needs it and
-- builds that category's table once; categories nobody asks for are never
-- built. Packs.Release(name) forgets a table (its provider was turned off), so
-- the memory goes back to the game.
-- A pack registers itself as a global table with .categories, each one a
-- function that returns its data (see MapScout_Data_Forever/Pack.lua).

local _, ns = ...
local L = ns.L

local Packs = {}
ns.Packs = Packs

-- flavor -> { addon folder, global the pack sets }
Packs.BY_FLAVOR = {
	forever = { addon = "MapScout_Data_Forever", global = "MapScoutDataForever" },
}

local built, order = {}, {}
local failure -- why the pack could not be loaded (it is not tried again)

function Packs.Info()
	return Packs.BY_FLAVOR[ns.Caps.flavor]
end

-- The loaded pack, or nil and why: "flavor" (no pack for this game), "api"
-- (the client cannot load addons on demand), or the game's reason
-- ("MISSING", "DISABLED"...), or "invalid" (it loaded but did not register)
function Packs.Load()
	local info = Packs.Info()
	if not info then
		return nil, "flavor"
	end
	local pack = rawget(_G, info.global)
	if type(pack) == "table" then
		return pack
	end
	if failure then
		return nil, failure
	end
	if not ns.Caps.loadOnDemand then
		failure = "api"
		return nil, failure
	end
	local ok, reason = C_AddOns.LoadAddOn(info.addon)
	pack = rawget(_G, info.global)
	if not ok or type(pack) ~= "table" or type(pack.categories) ~= "table" then
		failure = (not ok and tostring(reason or "?")) or "invalid"
		return nil, failure
	end
	return pack
end

-- A category's data (built once), or nil and why
function Packs.Get(name)
	if built[name] then
		return built[name]
	end
	local pack, reason = Packs.Load()
	if not pack then
		return nil, reason
	end
	local build = pack.categories[name]
	if type(build) ~= "function" then
		return nil, "category"
	end
	local ok, data = pcall(build)
	if not ok or type(data) ~= "table" then
		geterrorhandler()(("MapScout: data pack category %s: %s"):format(name, tostring(data)))
		return nil, "error"
	end
	built[name] = data
	order[#order + 1] = name
	return data
end

function Packs.Release(name)
	if not built[name] then
		return
	end
	built[name] = nil
	for i, other in ipairs(order) do
		if other == name then
			table.remove(order, i)
			break
		end
	end
end

-- Categories built right now, in the order they were built
function Packs.Built()
	local list = {}
	for i, name in ipairs(order) do
		list[i] = name
	end
	return list
end

function Packs.IsBuilt(name)
	return built[name] ~= nil
end

-- The pack's version (its .toc), read without loading it, or nil
function Packs.Version()
	local info = Packs.Info()
	local get = info and C_AddOns and C_AddOns.GetAddOnMetadata
	if not get then
		return nil
	end
	local ok, version = pcall(get, info.addon, "Version")
	return ok and type(version) == "string" and version ~= "" and version or nil
end

-- For the tests: back to "nothing loaded"
function Packs.Reset()
	built, order, failure = {}, {}, nil
end

-- /ms diag: memory of MapScout and its pack, and what the pack has built
local function memory(addon)
	local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
	local ok, kb = pcall(get, addon)
	return ok and type(kb) == "number" and kb or nil
end

function Packs.Report()
	local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
	if update then
		pcall(update)
	end
	local info = Packs.Info()
	local lines = {}
	local own = memory("MapScout")
	lines[#lines + 1] = L.DIAG_MEMORY:format("MapScout", own and ("%.0f KB"):format(own) or "?")
	if not info then
		lines[#lines + 1] = L.DIAG_PACK_NONE
		return lines
	end
	local loaded = type(rawget(_G, info.global)) == "table"
	local kb = loaded and memory(info.addon)
	lines[#lines + 1] = L.DIAG_MEMORY:format(info.addon, loaded and (kb and ("%.0f KB"):format(kb) or "?")
		or (failure and L.DIAG_PACK_FAILED:format(failure) or L.DIAG_PACK_NOT_LOADED))
	local names = Packs.Built()
	lines[#lines + 1] = L.DIAG_PACK_BUILT:format(#names > 0 and table.concat(names, ", ") or "-")
	return lines
end

ns.AddDiagSection(Packs.Report)
