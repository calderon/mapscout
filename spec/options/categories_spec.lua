-- Options/Categories.lua: turning providers and categories on and off
describe("Options/Categories.lua", function()
	local ns, frame

	before_each(function()
		ResetWoW()
		StubGlobals({
			Settings = {
				RegisterCanvasLayoutCategory = function() return { ID = 1 } end,
				RegisterAddOnCategory = function() end,
				OpenToCategory = function() end,
			},
		})
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "Options/Panel.lua",
			"Options/Categories.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("services", {
			name = "Servicios",
			description = "Bancos y posadas",
			categories = { { id = "bank", name = "Banco" }, { id = "inn", name = "Posada" } },
		}):SetEntries({
			{ id = 1, name = "Banco de Forjaz", category = "bank", mapID = 1455, x = 0.5, y = 0.5 },
			{ id = 2, name = "Posada de Forjaz", category = "inn", mapID = 1455, x = 0.5, y = 0.5 },
		})
		MapScoutAPI:RegisterProvider("flights", { name = "Vuelos" })
		ns.Options.frame:Show() -- builds the page
	end)

	local function rowsShown()
		local list = {}
		for _, f in ipairs(FakeFrames) do
			local line = rawget(f, "line")
			if f.type == "CheckButton" and line then
				local name = line.category and line.category.name or line.setting and line.setting.name or line.record.spec.name
				list[#list + 1] = { name, f:GetChecked(), f:IsEnabled(), f }
			end
		end
		table.sort(list, function(a, b) return a[4].index < b[4].index end)
		return list
	end

	local function row(name)
		for _, r in ipairs(rowsShown()) do
			if r[1] == name then
				return r[4]
			end
		end
	end

	local function found(text)
		return #(ns.Engine.Search(ns.Query.Parse(text)))
	end

	it("lists each provider with its categories under it", function()
		local names = {}
		for i, r in ipairs(rowsShown()) do
			names[i] = r[1]
		end
		assert.are.same({ "Servicios", "Banco", "Posada", "Vuelos" }, names)
		assert.are.equal("Bancos y posadas", row("Servicios").tooltip)
	end)

	it("turns a category off: left out of the results, saved", function()
		assert.are.equal(2, found("forjaz"))
		row("Banco"):Run("OnClick")
		assert.is_false(row("Banco"):GetChecked())
		assert.are.equal(1, found("forjaz"))
		assert.is_false(MapScoutDB.options.categories["services.bank"])
		row("Banco"):Run("OnClick")
		assert.is_nil(rawget(MapScoutDB.options.categories, "services.bank")) -- back on: nothing saved
	end)

	it("shows a provider as partial when some of its categories are off", function()
		row("Posada"):Run("OnClick")
		assert.is_true(row("Servicios"):GetChecked()) -- still on...
		assert.are.same({ true, false }, { row("Banco"):GetChecked(), row("Posada"):GetChecked() })
		-- (the dimmed check is drawn with the game's texture, not checked here)
	end)

	it("turns a whole provider off for real, greying its categories", function()
		row("Servicios"):Run("OnClick")
		assert.is_false(ns.Registry.Get("services").enabled)
		assert.are.equal(0, #ns.Registry.Get("services").entries) -- nothing kept
		assert.is_false(row("Banco"):IsEnabled())
		assert.are.equal(0, found("forjaz"))
		assert.is_false(MapScoutDB.options.providers.services)
	end)

	it("turns a provider back on with all its categories", function()
		row("Posada"):Run("OnClick")
		row("Servicios"):Run("OnClick")
		row("Servicios"):Run("OnClick")
		assert.is_true(ns.Registry.Get("services").enabled)
		assert.is_true(row("Posada"):GetChecked())
		assert.is_true(ns.Registry.IsCategoryEnabled("services", "inn"))
	end)

	it("restores the defaults", function()
		row("Banco"):Run("OnClick")
		row("Vuelos"):Run("OnClick")
		ns.OptionsCategories.Reset()
		assert.is_true(ns.Registry.Get("flights").enabled)
		assert.is_true(ns.Registry.IsCategoryEnabled("services", "bank"))
		assert.is_true(row("Vuelos"):GetChecked())
	end)

	it("shows a provider's settings after its categories, off by default, saved only when changed", function()
		local changed = {}
		ns.Registry.Listen(function(what, id, settingID)
			if what == "setting" then changed[#changed + 1] = id .. "." .. tostring(settingID) end
		end)
		ns.Registry.AddSettings("flights", { { id = "far", name = "Lejanos", tooltip = "Los de lejos", default = false } })
		ns.OptionsCategories.Refresh()
		local names = {}
		for i, r in ipairs(rowsShown()) do
			names[i] = r[1]
		end
		assert.are.same({ "Servicios", "Banco", "Posada", "Vuelos", "Lejanos" }, names)
		assert.is_false(row("Lejanos"):GetChecked())
		assert.are.equal("Los de lejos", row("Lejanos").tooltip)
		row("Lejanos"):Run("OnClick")
		assert.is_true(ns.Registry.GetSetting("flights", "far"))
		assert.is_true(MapScoutDB.options.settings["flights.far"])
		assert.are.same({ "flights.far" }, changed)
		row("Vuelos"):Run("OnClick") -- provider off: its setting greyed
		assert.is_false(row("Lejanos"):IsEnabled())
		ns.OptionsCategories.Reset()
		assert.is_false(ns.Registry.GetSetting("flights", "far"))
		assert.is_nil(rawget(MapScoutDB.options.settings, "flights.far"))
		assert.are.equal("flights.nil", changed[2]) -- told on reset
	end)

	it("adds providers registered later by themselves", function()
		MapScoutAPI:RegisterProvider("late", { name = "Llega tarde" })
		assert.is_table(row("Llega tarde"))
	end)
end)

describe("Options/Categories.lua groups", function()
	local ns

	before_each(function()
		ResetWoW()
		StubGlobals({
			Settings = {
				RegisterCanvasLayoutCategory = function() return { ID = 1 } end,
				RegisterAddOnCategory = function() end,
				OpenToCategory = function() end,
			},
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
		})
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		function map:GetMapID() return 1455 end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Preview.lua",
			"UI/Results.lua", "Options/Panel.lua", "Options/Categories.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("log", { name = "En tu registro", group = "quests", groupName = "Misiones",
			filter = "quest", filterAliases = { "registro" } }):SetEntries({ { id = 1, name = "Reliquias", mapID = 1455, x = 0.5, y = 0.5 } })
		MapScoutAPI:RegisterProvider("places", { name = "Lugares" })
		MapScoutAPI:RegisterProvider("available", { name = "Disponibles", group = "quests", groupName = "Misiones",
			filter = "available", filterAliases = { "quest", "disponible" } }):SetEntries({ { id = 2, name = "Niebla", mapID = 1455, x = 0.5, y = 0.5 } })
		ns.Options.frame:Show()
	end)

	local function lines()
		local list = {}
		for i, line in ipairs(ns.OptionsCategories.Lines()) do
			list[i] = (line.level or 0) .. " " .. (line.name or (line.category and line.category.name) or line.record.spec.name)
		end
		return list
	end

	local function groupLine()
		return ns.OptionsCategories.Lines()[1]
	end

	local function count(text)
		return #(ns.Engine.Search(ns.Query.Parse(text)))
	end

	it("shows a group with its providers under it, where the first one was", function()
		assert.are.same({ "0 Misiones", "1 En tu registro", "1 Disponibles", "0 Lugares" }, lines())
	end)

	it("turns the whole group off and on", function()
		ns.OptionsCategories.Toggle(groupLine())
		assert.is_false(ns.Registry.Get("log").enabled)
		assert.is_false(ns.Registry.Get("available").enabled)
		assert.are.equal(0, count("@disponible"))
		ns.OptionsCategories.Toggle(groupLine())
		assert.is_true(ns.Registry.Get("log").enabled)
		assert.is_true(ns.Registry.Get("available").enabled)
	end)

	it("finds all quests with @mision, the log with @registro, the available ones with @disponible", function()
		assert.are.equal(2, count("@quest"))
		assert.are.equal(1, count("@registro"))
		assert.are.equal(1, count("@disponible"))
	end)

	it("treats typing exactly a turned-off kind as searching it", function()
		ns.Registry.SetEnabled("available", false)
		ns.Registry.SetEnabled("log", false)
		ns.SearchBar.box:SetText("quest")
		ns.SearchBar.Search()
		assert.are.same({ kind = "empty", text = "En tu registro, Disponibles: turned off in the options (/ms)" },
			ns.Results.lines[1])
		-- a long note wraps: its row (and the list) grows instead of cutting it
		for _, f in ipairs(FakeFrames) do
			local line = rawget(f, "line")
			if line and line.kind == "empty" then
				assert.is_true(f.height > ns.Results.HEADER_HEIGHT)
			end
		end
		-- something more precise is a normal search by name
		local results = ns.Engine.Search(ns.Query.Parse("questing beast"))
		assert.are.equal(0, #results) -- nothing named so, but no "turned off" note
	end)

	it("says when the @ words searched are turned off", function()
		ns.Registry.SetEnabled("available", false)
		ns.SearchBar.box:SetText("@disponible")
		ns.SearchBar.Search()
		assert.are.same({ kind = "empty", text = "Disponibles: turned off in the options (/ms)" }, ns.Results.lines[1])
	end)
end)
