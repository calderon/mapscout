-- Debug/Sample.lua: the development-only sample provider
describe("Debug/Sample.lua", function()
	local ns

	before_each(function()
		ResetWoW()
		ns = LoadAddonFile("Core/Init.lua")
		local frame = FakeFrames[1]
		for _, file in ipairs({ "Core/Util.lua", "Core/DB.lua", "API/MapScoutAPI.lua", "API/Registry.lua",
			"Search/Query.lua", "Search/Index.lua", "Search/Engine.lua", "Debug/Sample.lua" }) do
			LoadAddonFile(file, ns)
		end
		frame:Fire("ADDON_LOADED", "MapScout")
		frame:Fire("PLAYER_LOGIN")
	end)

	local function search(text)
		return (ns.Engine.Search(ns.Query.Parse(text)))
	end

	it("turns on and off with /ms debug sample, through the public API", function()
		SlashCmdList.MAPSCOUT("debug sample")
		local record = ns.Registry.Get("sample")
		assert.is_true(record.enabled)
		assert.are.equal(#ns.Sample.ENTRIES, #record.entries)
		assert.matches(#ns.Sample.ENTRIES .. " places", ChatLog[#ChatLog], 1, true)
		SlashCmdList.MAPSCOUT("debug sample")
		assert.is_nil(ns.Registry.Get("sample"))
		assert.matches("off", ChatLog[#ChatLog], 1, true)
	end)

	it("gives searchable places with icons, also by category @ words", function()
		ns.Sample.On()
		assert.is_true(#search("buzon") >= 3)
		local banks = search("@banco")
		assert.are.equal(3, #banks)
		for _, result in ipairs(banks) do
			assert.is_string(result.item.entry.icon)
		end
		assert.are.equal(#ns.Sample.ENTRIES, #search("@sample"))
	end)

	it("adds 5,000 more places with big", function()
		SlashCmdList.MAPSCOUT("debug sample big")
		assert.are.equal(#ns.Sample.ENTRIES + 5000, #ns.Registry.Get("sample").entries)
	end)

	it("has valid entries only (none skipped)", function()
		ns.Sample.On()
		assert.are.equal(0, ns.Registry.Get("sample").skipped)
		assert.are.equal(0, #ReportedErrors)
	end)
end)
