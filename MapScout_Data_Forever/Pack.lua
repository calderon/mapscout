-- MapScout_Data_Forever: MapScout's static data for WoW Forever, what the game
-- cannot tell the addon while playing. A LoadOnDemand addon: MapScout loads it
-- (Core/Packs.lua) when the first enabled category needs it.
-- Every other file is generated (dev/tools/datagen) and adds one category:
--   pack.categories.<name> = function() return { ... } end
-- a function, so its table is only built when MapScout asks for that category.

local _, pack = ...

pack.categories = {}

-- How MapScout finds the pack once loaded
MapScoutDataForever = pack
