-- Providers/Geography.lua: towns and named places from the static data pack
describe("Providers/Geography.lua: towns and places", function()
	local ns, frame, loads
	local MAPS = dofile("spec/fixtures/maps.lua")

	local function loadRealPack()
		local pack = {}
		for _, path in ipairs({ "MapScout_Data_Forever/Pack.lua", "MapScout_Data_Forever/Places.lua" }) do
			assert(loadfile(path))("MapScout_Data_Forever", pack)
		end
	end

	before_each(function()
		ResetWoW()
		rawset(_G, "MapScoutDataForever", nil)
		loads = 0
		StubGlobals({
			WOW_PROJECT_ID = 18,
			GetLocale = function() return "esES" end,
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				GetMapChildrenInfo = function() return {} end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
			C_AddOns = {
				LoadAddOn = function()
					loads = loads + 1
					loadRealPack()
					return true
				end,
				IsAddOnLoadOnDemand = function() return true end,
				GetAddOnMetadata = function() end,
			},
		})
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "Core/Packs.lua", "API/MapScoutAPI.lua",
			"API/Registry.lua", "Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Providers/Geography.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	after_each(function()
		rawset(_G, "MapScoutDataForever", nil)
	end)

	local function search(text)
		local found = {}
		for i, r in ipairs((ns.Engine.Search(ns.Query.Parse(text)))) do
			found[i] = r.item.entry
		end
		return found
	end

	it("finds towns by name in both languages, as points with their kind", function()
		local goldshire = search("villadorada")[1]
		assert.are.equal("Villadorada", goldshire.name)
		assert.are.equal("Pueblo", goldshire.subtitle)
		assert.are.equal("towns", goldshire.category)
		assert.is_nil(goldshire.isMap)
		assert.is_number(goldshire.x)
		assert.are.equal("Villadorada", search("goldshire")[1].name)
	end)

	it("filters towns and named places with @ words", function()
		local towns = search("@pueblo")
		assert.is_true(#towns > 40)
		for _, entry in ipairs(towns) do
			assert.are.equal("towns", entry.category)
		end
		local places = search("@subzona")
		assert.are.equal(50, #places) -- the result cap; there are more
		assert.are.equal("Lugar", places[1].subtitle)
		local count = 0
		for _, entry in ipairs(ns.Registry.Get("geography").entries) do
			count = count + (entry.category == "subzones" and 1 or 0)
		end
		assert.is_true(count > 100)
	end)

	it("keeps a name once per map", function()
		local seen = {}
		for _, entry in ipairs(ns.Registry.Get("geography").entries) do
			if entry.mapID then
				local key = entry.name .. "@" .. entry.mapID
				assert.is_nil(seen[key], "repeated " .. key)
				seen[key] = true
			end
		end
	end)

	it("loads the pack only while towns or places are on", function()
		assert.are.equal(1, loads)
		assert.are.same({ "places" }, ns.Packs.Built())
		ns.Registry.SetCategoryEnabled("geography", "towns", false)
		assert.are.same({ "places" }, ns.Packs.Built()) -- places still on
		ns.Registry.SetCategoryEnabled("geography", "subzones", false)
		assert.are.same({}, ns.Packs.Built())
		assert.are.equal(0, #search("villadorada"))
		ns.Registry.SetCategoryEnabled("geography", "towns", true)
		assert.are.same({ "places" }, ns.Packs.Built())
		assert.are.equal("Villadorada", search("villadorada")[1].name)
	end)
end)
