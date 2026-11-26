-- Core/Packs.lua: loading the static data pack on demand
describe("Core/Packs.lua", function()
	local loads

	-- The game loading the real pack (its files in .toc order)
	local function loadRealPack()
		local pack = {}
		for _, path in ipairs({ "MapScout_Data_Forever/Pack.lua", "MapScout_Data_Forever/Dungeons.lua" }) do
			assert(loadfile(path))("MapScout_Data_Forever", pack)
		end
	end

	local function setup(globals, loadAddOn)
		loads = {}
		StubGlobals(globals or {})
		StubGlobals({
			C_AddOns = {
				LoadAddOn = function(name)
					loads[#loads + 1] = name
					return (loadAddOn or function()
						loadRealPack()
						return true
					end)(name)
				end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function() end,
				GetAddOnMemoryUsage = function(name) return name == "MapScout" and 512 or 2048 end,
				UpdateAddOnMemoryUsage = function() end,
			},
		})
		local ns = LoadAddonFile("Core/Init.lua")
		LoadAddonFile("Core/Caps.lua", ns)
		LoadAddonFile("Core/Packs.lua", ns)
		return ns
	end

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	it("loads the pack only when a category is asked for, and once", function()
		local ns = setup({ WOW_PROJECT_ID = 18 })
		assert.are.same({}, loads)
		local dungeons = ns.Packs.Get("dungeons")
		assert.are.same({ "MapScout_Data_Forever" }, loads)
		assert.is_table(dungeons.entrances)
		assert.are.equal("Deadmines", dungeons.names.enUS[36])
		assert.are.same({ "dungeon", 1415, 4068, 7958, 16 }, dungeons.entrances[36])
		assert.are.equal(dungeons, ns.Packs.Get("dungeons")) -- built once
		assert.are.same({ "MapScout_Data_Forever" }, loads)
		assert.are.same({ "dungeons" }, ns.Packs.Built())
	end)

	it("forgets a released category and builds it again when asked", function()
		local ns = setup({ WOW_PROJECT_ID = 18 })
		local first = ns.Packs.Get("dungeons")
		ns.Packs.Release("dungeons")
		assert.are.same({}, ns.Packs.Built())
		local again = ns.Packs.Get("dungeons")
		assert.are_not.equal(first, again)
		assert.are.same({ "MapScout_Data_Forever" }, loads) -- the addon is not loaded twice
	end)

	it("says why when there is no pack, and does not try again", function()
		local ns = setup({ WOW_PROJECT_ID = 18 }, function() return false, "MISSING" end)
		assert.are.same({ nil, "MISSING" }, { ns.Packs.Get("dungeons") })
		assert.are.same({ nil, "MISSING" }, { ns.Packs.Get("dungeons") })
		assert.are.equal(1, #loads)
	end)

	it("has no pack for other games", function()
		local ns = setup({ WOW_PROJECT_ID = 1 })
		assert.are.same({ nil, "flavor" }, { ns.Packs.Get("dungeons") })
		assert.are.same({}, loads)
	end)

	it("reports an unknown category and a pack that did not register", function()
		local ns = setup({ WOW_PROJECT_ID = 18 })
		assert.are.same({ nil, "category" }, { ns.Packs.Get("nothing") })
		rawset(_G, "MapScoutDataForever", nil)
		ns = setup({ WOW_PROJECT_ID = 18 }, function() return true end)
		assert.are.same({ nil, "invalid" }, { ns.Packs.Get("dungeons") })
	end)

	it("reports memory and built categories in /ms diag", function()
		local ns = setup({ WOW_PROJECT_ID = 18 })
		local lines = ns.Packs.Report()
		assert.are.equal("memory of MapScout: 512 KB", lines[1])
		assert.are.equal("memory of MapScout_Data_Forever: not loaded (no category has needed it)", lines[2])
		ns.Packs.Get("dungeons")
		lines = ns.Packs.Report()
		assert.are.equal("memory of MapScout_Data_Forever: 2048 KB", lines[2])
		assert.are.equal("data built: dungeons", lines[3])
	end)
end)
