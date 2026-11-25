-- Core/Caps.lua: client capabilities and /ms diag
describe("Core/Caps.lua", function()
	local fn = function() end

	-- A client like WoW Forever (see the audit table in ARCHITECTURE.md)
	local function foreverLike()
		StubGlobals({
			WOW_PROJECT_ID = 18,
			Settings = { RegisterCanvasLayoutCategory = fn, RegisterAddOnCategory = fn, OpenToCategory = fn },
			MenuUtil = { CreateContextMenu = fn },
			C_Map = { SetUserWaypoint = fn, CanSetUserWaypointOnMap = fn, GetMapLinksForMap = fn },
			UiMapPoint = { CreateFromCoordinates = fn },
			C_SuperTrack = { SetSuperTrackedUserWaypoint = fn },
			C_TaxiMap = { GetTaxiNodesForMap = fn },
			C_EncounterJournal = { GetDungeonEntrancesForMap = fn },
			C_AreaPoiInfo = { GetAreaPOIForMap = fn, GetAreaPOIInfo = fn, GetEventsForMap = fn },
			C_VignetteInfo = { GetVignettes = fn, GetVignetteInfo = fn, GetVignettePosition = fn },
			C_QuestLog = { GetNumQuestLogEntries = fn, GetInfo = fn, GetQuestsOnMap = fn },
			C_TaskQuest = { GetQuestsOnMap = fn },
			C_AddOns = { LoadAddOn = fn, IsAddOnLoadOnDemand = fn, GetAddOnMetadata = fn },
			C_XMLUtil = {
				GetTemplateInfo = function(name)
					if name == "SearchBoxTemplate" then
						return { type = "EditBox" }
					end
				end,
			},
		})
	end

	local function load()
		local ns = LoadAddonFile("Core/Init.lua")
		return LoadAddonFile("Core/Caps.lua", ns)
	end

	before_each(function()
		ResetWoW()
	end)

	it("finds every capability of a Forever-like client", function()
		foreverLike()
		local caps = load().Caps
		for _, check in ipairs(load().CAPS_CHECKS) do
			assert.is_true(caps[check[1]], check[1])
		end
		assert.is_true(caps.searchBox)
		assert.are.equal("forever", caps.flavor)
		assert.are.equal("1.60.1 (71139)", caps.build)
	end)

	it("says no when a function is missing, even if its namespace exists", function()
		foreverLike()
		_G.C_AreaPoiInfo.GetAreaPOIInfo = nil -- only GetAreaPOIForMap left
		_G.Settings = nil
		local caps = load().Caps
		assert.is_false(caps.areaPOI)
		assert.is_true(caps.areaPOIEvents)
		assert.is_false(caps.settings)
		assert.is_true(caps.menuUtil)
	end)

	it("says no to everything in a client without the APIs", function()
		local caps = load().Caps
		for _, check in ipairs(load().CAPS_CHECKS) do
			assert.is_false(caps[check[1]], check[1])
		end
		assert.is_false(caps.searchBox)
		assert.are.equal("unknown:nil", caps.flavor)
	end)

	it("doesn't break if the template lookup fails", function()
		StubGlobals({ C_XMLUtil = { GetTemplateInfo = function() error("no") end } })
		assert.is_false(load().Caps.searchBox)
	end)

	it("names the flavor from WOW_PROJECT_ID", function()
		StubGlobals({ WOW_PROJECT_ID = 1 })
		assert.are.equal("retail", load().Caps.flavor)
		StubGlobals({ WOW_PROJECT_ID = 2 })
		assert.are.equal("classic", load().Caps.flavor)
	end)

	it("prints the capabilities with /ms diag", function()
		foreverLike()
		load()
		SlashCmdList.MAPSCOUT("diag")
		local out = table.concat(ChatLog, "\n")
		assert.matches("version 0.0.0 · WoW 1.60.1 (71139) · forever · enUS", out, 1, true)
		assert.matches("dungeonEntrances |cff00ff00yes|r", out, 1, true)
		assert.matches("searchBox |cff00ff00yes|r", out, 1, true)
	end)
end)
