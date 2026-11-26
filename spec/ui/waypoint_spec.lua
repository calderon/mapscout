-- UI/Waypoint.lua: going to a result
describe("UI/Waypoint.lua", function()
	local ns, frame, map, calls
	local MAPS = dofile("spec/fixtures/maps.lua")

	before_each(function()
		ResetWoW()
		calls = {}
		local function record(name)
			return function(...) table.insert(calls, { name, ... }) end
		end
		StubGlobals({
			C_Map = {
				GetMapInfo = function(id) return MAPS[id] end,
				-- the museum (9001) doesn't allow pins; its zone (Forjaz) does
				CanSetUserWaypointOnMap = function(id) return id ~= 9001 end,
				SetUserWaypoint = record("SetUserWaypoint"),
				GetWorldPosFromMapPos = function(_, pos) return 0, { GetXY = function() return pos.x / 2, pos.y / 2 end } end,
				GetMapPosFromWorldPos = function(_, world) local x, y = world:GetXY(); return 0, { GetXY = function() return x, y end } end,
			},
			C_SuperTrack = { SetSuperTrackedUserWaypoint = record("SuperTrack") },
			UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { mapID = id, x = x, y = y } end },
			CreateVector2D = function(x, y) return { x = x, y = y } end,
			C_XMLUtil = { GetTemplateInfo = function() return {} end },
		})
		map = CreateFrame("Frame", "WorldMapFrame")
		map.ScrollContainer = CreateFrame("Frame", nil, map)
		local canvas = CreateFrame("Frame", nil, map.ScrollContainer)
		map.mapID = 1453
		function map:GetMapID() return self.mapID end
		function map:SetMapID(id) self.mapID = id; table.insert(calls, { "SetMapID", id }) end
		function map:GetCanvas() return canvas end
		function map:OnMapChanged() end
		StubGlobals({ WorldMapFrame = map })
		local before = #FakeFrames
		ns = LoadAddonFile("Core/Init.lua")
		frame = FakeFrames[before + 1]
		for _, file in ipairs({ "Core/Caps.lua", "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "UI/Map.lua", "UI/SearchBar.lua", "UI/Preview.lua",
			"UI/Results.lua", "UI/Waypoint.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
		MapScoutAPI:RegisterProvider("p", { name = "P" }):SetEntries({
			{ id = 1, name = "Buzón de Forjaz", mapID = 1455, x = 0.3, y = 0.6 },
			{ id = 2, name = "Buzón del museo", mapID = 9001, x = 0.5, y = 0.5 },
			{ id = 3, name = "Sin sitio" },
		})
	end)

	local function result(text)
		local results = ns.Engine.Search(ns.Query.Parse(text))
		return results[1]
	end

	local function find(name)
		for _, call in ipairs(calls) do
			if call[1] == name then
				return call
			end
		end
	end

	local function pinsOn()
		MapScoutDB.options.waypoint.native = true
		MapScoutDB.options.waypoint.superTrack = true
	end

	it("by default opens the place's map and shows the halo, without the game's pin", function()
		assert.is_true(ns.Waypoint.Go(result("buzon de forjaz"), "buzon de forjaz"))
		assert.are.same({ "SetMapID", 1455 }, find("SetMapID"))
		assert.is_nil(find("SetUserWaypoint"))
		assert.is_nil(find("SuperTrack"))
		assert.is_table(ns.Preview.shown)
		assert.are.equal(0, #ChatLog) -- no "can't set a pin" message: none was wanted
	end)

	it("sets and tracks the game's pin when the player turns them on", function()
		pinsOn()
		assert.is_true(ns.Waypoint.Go(result("buzon de forjaz"), "buzon de forjaz"))
		assert.are.same({ "SetMapID", 1455 }, find("SetMapID"))
		assert.are.same({ "SetUserWaypoint", { mapID = 1455, x = 0.3, y = 0.6 } }, find("SetUserWaypoint"))
		assert.are.same({ "SuperTrack", true }, find("SuperTrack"))
	end)

	it("puts the pin on the zone when the place's own map doesn't allow it", function()
		pinsOn()
		ns.Waypoint.Go(result("museo"))
		assert.are.same({ "SetUserWaypoint", { mapID = 1455, x = 0.25, y = 0.25 } }, find("SetUserWaypoint"))
	end)

	it("doesn't change the map when it is already open", function()
		map.mapID = 1455
		ns.Waypoint.Go(result("buzon de forjaz"))
		assert.is_nil(find("SetMapID"))
	end)

	it("adds a TomTom waypoint only when the player turned it on", function()
		local tomtom = { AddWaypoint = function(_, ...) table.insert(calls, { "TomTom", ... }) end }
		StubGlobals({ TomTom = tomtom })
		ns.Waypoint.Go(result("buzon de forjaz"))
		assert.is_nil(find("TomTom"))
		MapScoutDB.options.waypoint.tomtom = true
		ns.Waypoint.Go(result("buzon de forjaz"))
		local call = find("TomTom")
		assert.are.same({ 1455, 0.3, 0.6 }, { call[2], call[3], call[4] })
		assert.are.equal("Buzón de Forjaz", call[5].title)
	end)

	it("can set the game's pin without tracking it", function()
		pinsOn()
		MapScoutDB.options.waypoint.superTrack = false
		ns.Waypoint.Go(result("buzon de forjaz"))
		assert.is_nil(find("SuperTrack"))
		assert.is_table(find("SetUserWaypoint"))
	end)

	it("closes the list, leaves the box and keeps the halo until the map changes", function()
		ns.SearchBar.box:SetFocus()
		ns.SearchBar.box:SetText("buzon")
		ns.SearchBar.Search()
		assert.is_true(ns.Results.frame:IsShown())
		ns.Waypoint.Go(ns.Results.FirstResult(), "buzon")
		assert.is_false(ns.Results.frame:IsShown())
		assert.is_false(ns.SearchBar.box:HasFocus())
		assert.is_table(ns.Preview.shown)
		RunTimers()
		assert.is_table(ns.Preview.shown) -- no timer: it stays
		map:OnMapChanged()
		assert.is_nil(ns.Preview.shown)
	end)

	it("remembers how often and what was chosen, newest first, without repeats", function()
		ns.Waypoint.Go(result("buzon de forjaz"), "forjaz")
		ns.Waypoint.Go(result("museo"), "museo")
		ns.Waypoint.Go(result("buzon de forjaz"), "buzon")
		assert.are.equal(2, MapScoutDB.frequency["p:1"].count)
		assert.are.equal(1, MapScoutDB.frequency["p:2"].count)
		local history = MapScoutCharDB.history
		assert.are.same({ "p:1", "p:2" }, { history[1].key, history[2].key })
		assert.are.equal("buzon", history[1].text)
		for i = 1, 15 do
			ns.Waypoint.Remember({ item = { key = "k" .. i, entry = { name = "x" } } }, "x")
		end
		assert.are.equal(10, #MapScoutCharDB.history)
	end)

	it("does nothing for a result without a place", function()
		assert.is_false(ns.Waypoint.Go(result("sin sitio")))
		assert.is_nil(find("SetUserWaypoint"))
	end)

	it("says so when the player wants the pin and the game allows none there", function()
		pinsOn()
		_G.C_Map.CanSetUserWaypointOnMap = function() return false end
		ns.Waypoint.Go(result("buzon de forjaz"))
		assert.matches("doesn't allow a map pin for Buzón de Forjaz", ChatLog[#ChatLog], 1, true)
	end)

	it("goes on click, and Enter goes to the first result", function()
		ns.SearchBar.box:SetText("museo")
		ns.SearchBar.box:Run("OnEnterPressed")
		assert.are.equal(9001, map.mapID)
		calls = {}
		ns.SearchBar.box:SetText("buzon de forjaz")
		ns.SearchBar.Search()
		local clicked = false
		for _, f in ipairs(FakeFrames) do
			local line = rawget(f, "line")
			if not clicked and f.type == "Button" and line and line.kind == "result" then
				f:Run("OnClick", "LeftButton") -- the first result row (headers come before it)
				clicked = true
			end
		end
		assert.are.same({ "SetMapID", 1455 }, find("SetMapID"))
	end)
end)
