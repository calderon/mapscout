-- MapScout: saved data (SavedVariables) with a versioned schema.
--   MapScoutDB      account: options, aliases, blacklist, favorites, frequency
--   MapScoutCharDB  character: history of searches, known flight paths
-- On ADDON_LOADED both are upgraded step by step with ns.DB.migrations and
-- completed with the defaults (never overwriting what the player has).
-- If the data comes from a newer MapScout (unknown schema) or a migration
-- fails, it is left untouched: this session works on a copy of the defaults
-- that is not saved, and the player is warned once.
-- Modules read ns.db and ns.charDB from PLAYER_LOGIN on (ADDON_LOADED comes first).

local ADDON_NAME, ns = ...
local L = ns.L

local DB = {}
ns.DB = DB

-- Raise SCHEMA and add DB.migrations.account[n] / .char[n] when the layout changes.
DB.SCHEMA = 1

DB.ACCOUNT_DEFAULTS = {
	options = {
		providers = {}, -- providerID -> false when the player turned it off
		categories = {}, -- "providerID.categoryID" -> false when turned off
		waypoint = { native = true, superTrack = true, tomtom = false },
		bar = { position = "TOPLEFT", x = 0, y = 0, scale = 1 },
		maxResults = 50,
	},
	aliases = {}, -- alias -> result key
	blacklist = {}, -- result key -> true
	favorites = {}, -- result key -> true
	frequency = {}, -- result key -> { count = n, last = time }
}

DB.CHAR_DEFAULTS = {
	history = {}, -- recent searches, newest first
	knownTaxi = {}, -- flight node ID -> true
}

-- migrations.account[n](db) upgrades account data from schema n - 1 to n
-- (same for .char). A missing step means nothing to change for that schema.
DB.migrations = { account = {}, char = {} }

-- 0 -> 1: before the schema existed, only the client API audit (#20,
-- dev/audit) saved data here; it is not needed any more.
DB.migrations.account[1] = function(db)
	db.audit, db.audit2 = nil, nil
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in pairs(value) do
		result[k] = copy(v)
	end
	return result
end
DB.Copy = copy

-- Adds the defaults the data lacks, at any depth, never replacing a value the
-- player has. Tables from the defaults are copied, never shared.
function DB.MergeDefaults(data, defaults)
	for key, value in pairs(defaults) do
		if data[key] == nil then
			data[key] = copy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			DB.MergeDefaults(data[key], value)
		end
	end
	return data
end

-- Brings one saved table up to date.
-- Returns the table to use and its state: "new", "current", "upgraded",
-- or "newer"/"failed" (then a session-only copy of the defaults is returned
-- and the saved table is not touched).
function DB.Prepare(saved, defaults, migrations, schema)
	if type(saved) ~= "table" or next(saved) == nil then
		local fresh = DB.MergeDefaults({}, defaults)
		fresh.schema = schema
		return fresh, "new"
	end

	local from = tonumber(saved.schema) or 0
	if from > schema then
		return DB.MergeDefaults({}, defaults), "newer"
	end

	local state = "current"
	for step = from + 1, schema do
		local migrate = migrations[step]
		if migrate then
			local ok, err = pcall(migrate, saved)
			if not ok then
				return DB.MergeDefaults({}, defaults), "failed", err
			end
		end
		saved.schema = step
		state = "upgraded"
	end
	return DB.MergeDefaults(saved, defaults), state
end

local WARNINGS = { newer = "DB_NEWER", failed = "DB_FAILED" }

function DB.Load()
	local account, accountState, accountErr = DB.Prepare(MapScoutDB, DB.ACCOUNT_DEFAULTS, DB.migrations.account, DB.SCHEMA)
	local char, charState, charErr = DB.Prepare(MapScoutCharDB, DB.CHAR_DEFAULTS, DB.migrations.char, DB.SCHEMA)

	-- Only data that is safe to change goes back to the SavedVariables
	if WARNINGS[accountState] then
		ns.Print(L[WARNINGS[accountState]]:format(L.DB_ACCOUNT, tostring(accountErr)))
	else
		MapScoutDB = account
	end
	if WARNINGS[charState] then
		ns.Print(L[WARNINGS[charState]]:format(L.DB_CHARACTER, tostring(charErr)))
	else
		MapScoutCharDB = char
	end

	ns.db, ns.charDB = account, char
	DB.state = { account = accountState, char = charState }
end

ns.RegisterEvent("ADDON_LOADED", "DB", function(_, name)
	if name == ADDON_NAME then
		ns.UnregisterEvent("ADDON_LOADED", "DB")
		DB.Load()
	end
end)

-- /ms debug db: a quick look at the saved data --------------------------------

local function size(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

function DB.Report()
	if not ns.db then
		return { L.DB_NOT_LOADED }
	end
	local db, char = ns.db, ns.charDB
	return {
		L.DB_REPORT:format(db.schema or 0, DB.SCHEMA, L["DB_STATE_" .. DB.state.account], L["DB_STATE_" .. DB.state.char]),
		L.DB_REPORT_ACCOUNT:format(size(db.aliases), size(db.blacklist), size(db.favorites), size(db.frequency),
			db.options.maxResults),
		L.DB_REPORT_CHARACTER:format(size(char.history), size(char.knownTaxi)),
	}
end

ns.RegisterDebug("db", function()
	for _, line in ipairs(DB.Report()) do
		ns.Print(line)
	end
end, L.DEBUG_DB)
