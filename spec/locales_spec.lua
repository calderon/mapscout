-- Locales: English base, Spanish overrides, key names and search words
describe("Locales", function()
	before_each(function()
		ResetWoW()
	end)

	local function namespaceFor(locale)
		StubGlobals({ GetLocale = function() return locale end })
		return NewNamespace()
	end

	it("uses English by default and shows the key for a missing text", function()
		local L = namespaceFor("enUS").L
		assert.are.equal("version %s", L.VERSION)
		assert.are.equal("NOT_A_KEY", L.NOT_A_KEY)
	end)

	it("uses Spanish for esES and esMX, English for other languages", function()
		assert.are.equal("versión %s", namespaceFor("esES").L.VERSION)
		assert.are.equal("versión %s", namespaceFor("esMX").L.VERSION)
		assert.are.equal("version %s", namespaceFor("deDE").L.VERSION)
	end)

	it("falls back to English for a text not translated to Spanish", function()
		local L = namespaceFor("esES").L
		assert.are.equal("Alt", L.KEY_ALT)
	end)

	it("only translates keys that exist in English, with the same placeholders", function()
		local ns = namespaceFor("esES")
		local function placeholders(text)
			local list = {}
			for p in text:gmatch("%%[%a]") do
				list[#list + 1] = p
			end
			return table.concat(list)
		end
		for key, text in pairs(ns.L) do -- only the Spanish overrides are stored in L
			assert.is_not_nil(ns.L_EN[key], "unknown key in esES: " .. key)
			assert.are.equal(placeholders(ns.L_EN[key]), placeholders(text), "placeholders of " .. key)
		end
	end)

	it("defines in English every text the addon code uses", function()
		local en = NewNamespace().L_EN
		local files = io.popen("ls Core/*.lua Search/*.lua API/*.lua Providers/*.lua UI/*.lua Options/*.lua Debug/*.lua 2>/dev/null")
		for path in files:lines() do
			local source = io.open(path):read("*a")
			for key in source:gmatch("%f[%w_]L%.([%w_]+)") do
				assert.is_not_nil(en[key], path .. " uses missing text L." .. key)
			end
			for key in source:gmatch('%f[%w_]L%["([%w_]+)"%]') do
				assert.is_not_nil(en[key], path .. ' uses missing text L["' .. key .. '"]')
			end
		end
		files:close()
	end)

	it("names modifier keys as on the player's keyboard", function()
		assert.are.equal("Alt", namespaceFor("enUS").KeyName("ALT"))
		StubGlobals({ IsMacClient = function() return true end })
		assert.are.equal("Option", namespaceFor("enUS").KeyName("ALT"))
		assert.are.equal("Opción", namespaceFor("esES").KeyName("ALT"))
		assert.are.equal("Cmd", namespaceFor("esES").KeyName("CTRL"))
	end)

	it("joins English and localized search words, lowercase and without repeats", function()
		local ns = namespaceFor("esES")
		ns.W_EN.TEST = { "Flights", "flight" }
		ns.W.TEST = { "vuelos", "FLIGHT" }
		assert.are.same({ "flights", "flight", "vuelos" }, ns.Words("TEST"))
		assert.are.same({}, ns.Words("NOTHING"))
	end)
end)
