-- MapScout: a sample search provider, for development only.
-- Not in the released zip: its .toc line is inside #@do-not-package@ and the
-- Debug folder is ignored in .pkgmeta.
--   /ms debug sample        some places in real Forever zones (on/off)
--   /ms debug sample big    5,000 entries more, to measure speed
-- It registers through MapScoutAPI like any other addon would.

local _, ns = ...
local L = ns.L

local Sample = {}
ns.Sample = Sample

local ICONS = {
	mail = "Interface\\Icons\\INV_Letter_15",
	bank = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
	inn = "Interface\\Icons\\INV_Drink_04",
	flight = "Interface\\Icons\\Ability_Mount_Gryphon_01",
}

-- Rough positions in real maps of Forever (not exact: only for testing)
Sample.ENTRIES = {
	{ id = "if-bank", name = "Banco de Forjaz", category = "bank", mapID = 1455, x = 0.356, y = 0.604 },
	{ id = "if-mail1", name = "Buzón de la Gran Fundición", category = "mail", mapID = 1455, x = 0.458, y = 0.524 },
	{ id = "if-mail2", name = "Buzón del Ágora", category = "mail", mapID = 1455, x = 0.330, y = 0.668 },
	{ id = "if-inn", name = "Posada de la Cerveza de Piedra", category = "inn", mapID = 1455, x = 0.188, y = 0.512 },
	{ id = "if-flight", name = "Maestro de vuelo de Forjaz", category = "flight", mapID = 1455, x = 0.554, y = 0.478 },
	{ id = "sw-bank", name = "Banco de Ventormenta", category = "bank", mapID = 1453, x = 0.627, y = 0.776 },
	{ id = "sw-mail", name = "Buzón de la plaza de la Catedral", category = "mail", mapID = 1453, x = 0.494, y = 0.604 },
	{ id = "sw-inn", name = "Posada del Cerdo Borracho", category = "inn", mapID = 1453, x = 0.605, y = 0.751 },
	{ id = "dm-inn", name = "Posada de Kharanos", category = "inn", mapID = 1426, x = 0.474, y = 0.524 },
	{ id = "dm-mail", name = "Buzón de Kharanos", category = "mail", mapID = 1426, x = 0.472, y = 0.538 },
	{ id = "ew-inn", name = "Posada del León Orgulloso", category = "inn", mapID = 1429, x = 0.437, y = 0.658 },
	{ id = "og-bank", name = "Banco de Orgrimmar", category = "bank", mapID = 1454, x = 0.492, y = 0.692 },
	{ id = "og-flight", name = "Maestro de vuelo de Orgrimmar", category = "flight", mapID = 1454, x = 0.452, y = 0.637 },
}

local SPEC = {
	name = "Sample (development)",
	description = "Test places for developing MapScout",
	filter = "sample",
	categories = {
		{ id = "mail", name = "Buzones", filter = "mailbox", filterAliases = { "buzón" } },
		{ id = "bank", name = "Bancos", filter = "bank", filterAliases = { "banco" } },
		{ id = "inn", name = "Posadas", filter = "inn", filterAliases = { "posada" } },
		{ id = "flight", name = "Vuelos", filter = "flights", filterAliases = { "vuelos" } },
	},
}

local provider

local function withIcons(list)
	for _, entry in ipairs(list) do
		entry.icon = entry.icon or ICONS[entry.category]
	end
	return list
end

function Sample.IsOn()
	return provider ~= nil
end

function Sample.On(big)
	if not provider then
		provider = MapScoutAPI:RegisterProvider("sample", SPEC)
	end
	local list = ns.CopyTable(Sample.ENTRIES)
	if big then
		for i = 1, 5000 do
			list[#list + 1] = { id = "big" .. i, name = "Posada " .. i, category = "inn", mapID = 1455, x = (i % 100) / 100,
				y = 0.5 }
		end
	end
	provider:SetEntries(withIcons(list))
	return #list
end

function Sample.Off()
	if provider then
		MapScoutAPI:UnregisterProvider("sample")
		provider = nil
	end
end

ns.RegisterDebug("sample", function(args)
	if args == "big" then
		ns.Print(L.DEBUG_SAMPLE_ON:format(Sample.On(true)))
	elseif Sample.IsOn() then
		Sample.Off()
		ns.Print(L.DEBUG_SAMPLE_OFF)
	else
		ns.Print(L.DEBUG_SAMPLE_ON:format(Sample.On(false)))
	end
end, L.DEBUG_SAMPLE)
