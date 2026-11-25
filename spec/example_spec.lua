-- Example test: shows how to load an addon file and test its functions.
-- Real tests come with each search core issue (normalization, queries,
-- matching and scoring, SavedVariables migrations).
describe("test setup", function()
	it("loads an addon file with its namespace", function()
		local ns = LoadAddonFile("spec/fixtures/module.lua")
		assert.is_function(ns.Greeting)
		assert.are.equal("Hello from enUS", ns.Greeting())
	end)

	it("gives each test a fresh namespace", function()
		local a = LoadAddonFile("spec/fixtures/module.lua")
		local b = LoadAddonFile("spec/fixtures/module.lua")
		assert.are_not.equal(a, b)
	end)
end)
