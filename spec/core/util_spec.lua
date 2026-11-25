-- Core/Util.lua: text normalization for searching
describe("Core/Util.lua", function()
	local ns, normalize

	before_each(function()
		ResetWoW()
		ns = LoadAddonFile("Core/Init.lua")
		LoadAddonFile("Core/Util.lua", ns)
		normalize = ns.Normalize
	end)

	-- What the search does with these forms: prefix of the entry
	local function startsWith(entry, query)
		local e, q = normalize(entry), normalize(query)
		return e:sub(1, #q) == q
	end

	describe("Normalize", function()
		it("matches the examples of the issue", function()
			assert.are.equal(normalize("forjaz"), normalize("Forjaz"))
			assert.is_true(startsWith("Ventormenta", "ventor"))
			assert.are.equal("gromgol", normalize("Grom'gol"))
		end)

		it("lowercases and removes accents in Spanish texts", function()
			assert.are.equal("canon de los ancestros", normalize("Cañón de los Ancestros"))
			assert.are.equal("arbol de ceniza", normalize("ÁRBOL DE CENIZA"))
			assert.are.equal("pinguino", normalize("Pingüino"))
			assert.are.equal("instructor de herreria", normalize("Instructor de herrería"))
			assert.are.equal("buzon", normalize("buzón"))
		end)

		it("covers other Latin letters", function()
			assert.are.equal("strasse", normalize("Straße"))
			assert.are.equal("francais", normalize("Français"))
			assert.are.equal("aeoe", normalize("Æœ"))
			assert.are.equal("oyo", normalize("ØÝö"))
		end)

		it("joins words split by any apostrophe", function()
			assert.are.equal("gromgol", normalize("Grom’gol"))
			assert.are.equal("kaelthas", normalize("Kael‘thas"))
			assert.are.equal("zulfarrak", normalize("Zul`Farrak"))
			assert.are.equal("uldaman", normalize("Uld´aman"))
		end)

		it("turns other signs into single spaces", function()
			assert.are.equal("cima del trueno", normalize("Cima-del  Trueno!"))
			assert.are.equal("puerto de menethil los humedales", normalize("Puerto de Menethil, Los Humedales"))
			assert.are.equal("la ruta de las tres", normalize("«La ruta» de las… tres"))
			assert.are.equal("hola que tal", normalize("¡Hola! ¿Qué tal?"))
			assert.are.equal("a b", normalize("a · b"))
			assert.are.equal("2 3", normalize("2 × 3")) -- × is a sign, not a letter
		end)

		it("removes the game's colour, texture, atlas and link codes", function()
			assert.are.equal("banco", normalize("|cffffd100Banco|r"))
			assert.are.equal("buzon", normalize("|TInterface\\Icons\\mail:14|t Buzón"))
			assert.are.equal("ubicacion en el mapa", normalize("|Hworldmap:1455:5000:5000|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Ubicación en el mapa]|h"))
		end)

		it("keeps numbers and trims spaces", function()
			assert.are.equal("zona 51", normalize("  Zona   51  "))
			assert.are.equal("45 2 67 8", normalize("45.2, 67.8"))
		end)

		it("returns an empty text for nothing", function()
			assert.are.equal("", normalize(nil))
			assert.are.equal("", normalize(""))
			assert.are.equal("", normalize("  ¡!  "))
		end)

		it("gives the same result when normalizing twice", function()
			for _, text in ipairs({ "Cañón", "Grom'gol", "|cff00ff00Ventormenta|r", "Straße 12" }) do
				local once = normalize(text)
				assert.are.equal(once, normalize(once))
			end
		end)
	end)

	it("splits a normalized text into words", function()
		assert.are.same({ "instructor", "de", "herreria" }, ns.SplitWords(normalize("Instructor de herrería")))
		assert.are.same({}, ns.SplitWords(""))
	end)

	it("/ms debug normalize shows how a text is searched", function()
		SlashCmdList.MAPSCOUT("debug normalize Grom'gol, Tierras Inhóspitas")
		assert.matches('"Grom\'gol, Tierras Inhóspitas" is searched as "gromgol tierras inhospitas"', ChatLog[#ChatLog], 1, true)
	end)
end)
