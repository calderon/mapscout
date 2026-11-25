-- Example addon file used by spec/example_spec.lua (not part of the addon)
local _, ns = ...

function ns.Greeting()
	return "Hello from " .. GetLocale()
end
