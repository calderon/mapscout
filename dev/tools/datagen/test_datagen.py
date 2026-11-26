"""Unit tests for the data generator (no network): python3 -m unittest discover dev/tools/datagen"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dungeons  # noqa: E402
import lua  # noqa: E402
from geo import Maps, to_int  # noqa: E402


def ui_map(id_, type_, system="0", name="Map"):
    return {"ID": str(id_), "Type": str(type_), "System": system, "Name_lang": name}


def assignment(ui, continent, min_x, min_y, max_x, max_y):
    row = {"UiMapID": str(ui), "MapID": str(continent), "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1"}
    for i, v in enumerate((min_x, min_y, -1e6, max_x, max_y, 1e6)):
        row["Region_%d" % i] = str(v)
    return row


# A continent 0..1000 x 0..1000, a zone in its north-west corner, and two
# zones whose rectangles overlap in the south
MAPS = Maps(
    [ui_map(10, 2), ui_map(11, 3), ui_map(12, 3), ui_map(13, 3), ui_map(99, 2, system="1")],
    [
        assignment(10, 0, 0, 0, 1000, 1000),
        assignment(99, 0, 100, 100, 900, 900),  # the flight map: never used
        assignment(11, 0, 500, 500, 1000, 1000),
        assignment(12, 0, 0, 0, 300, 600),
        assignment(13, 0, 0, 400, 300, 1000),
    ],
)


class GeoTest(unittest.TestCase):
    def test_world_to_map_axes(self):
        # map x grows when world y falls; map y grows when world x falls
        ui, x, y = MAPS.place(0, 1000, 1000)
        self.assertEqual((ui, x, y), (11, 0, 0))
        ui, x, y = MAPS.place(0, 500, 500)
        self.assertEqual((ui, x, y), (11, 1, 1))
        ui, x, y = MAPS.place(0, 750, 600)
        self.assertEqual(ui, 11)
        self.assertAlmostEqual(x, 0.8)
        self.assertAlmostEqual(y, 0.5)

    def test_overlapping_zones_fall_back_to_the_continent(self):
        ui, x, y = MAPS.place(0, 100, 500)  # inside both 12 and 13
        self.assertEqual(ui, 10)
        self.assertAlmostEqual(x, 0.5)
        self.assertAlmostEqual(y, 0.9)

    def test_outside_every_zone_uses_the_continent(self):
        self.assertEqual(MAPS.place(0, 400, 200)[0], 10)

    def test_other_continent_or_outside(self):
        self.assertIsNone(MAPS.place(1, 100, 100))
        self.assertIsNone(MAPS.place(0, 2000, 100))

    def test_to_int(self):
        self.assertEqual(to_int(0.12345), 1235)  # 1234.5 rounds up
        self.assertEqual(to_int(0.5), 5000)
        self.assertEqual(to_int(-0.1), 0)
        self.assertEqual(to_int(1.2), 10000)


def instance(id_, name, kind, continent, x, y):
    return {"ID": str(id_), "MapName_lang": name, "InstanceType": str(kind), "CorpseMapID": str(continent),
            "Corpse_0": str(x), "Corpse_1": str(y)}


class DungeonsTest(unittest.TestCase):
    def test_levels_by_name(self):
        found = dungeons.levels(
            [{"Name_lang": "Deadmines", "ContentTuningID": "1"}, {"Name_lang": "Elwynn", "ContentTuningID": "2"}],
            [{"ID": "1", "MinLevelSquish": "16"}, {"ID": "2", "MinLevelSquish": "0"}],
        )
        self.assertEqual(found, {"Deadmines": 16})

    def test_entrances(self):
        rows = [
            instance(36, "Deadmines", 1, 0, 750, 600),
            instance(249, "Onyxia's Lair", 2, 0, 100, 500),
            instance(30, "Alterac Valley", 3, 0, 750, 600),  # battleground
            instance(35, "<unused>Prison", 1, 0, 750, 600),
            instance(533, "Naxxramas", 2, 0, 0, 0),  # no corpse point
            instance(13, "Test Dungeon", 1, -1, 750, 600),
        ]
        found = dungeons.entrances(MAPS, rows, {"Deadmines": 16, "Onyxia": 60})
        self.assertEqual(found, [(36, "dungeon", 11, 8000, 5000, 16), (249, "raid", 10, 5000, 9000, 60)])

    def test_names_only_for_kept_instances(self):
        names = dungeons.names({"esES": [{"ID": "36", "MapName_lang": "Minas de la Muerte"},
                                         {"ID": "30", "MapName_lang": "Valle de Alterac"}]}, [36])
        self.assertEqual(names, {"esES": {36: "Minas de la Muerte"}})

    def test_write_is_stable_lua(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Dungeons.lua")
            dungeons.write(path, "1.60.1.1", "2026-01-02", [(36, "dungeon", 11, 8000, 5000, 16)],
                           {"enUS": {36: 'Dead "mines"'}})
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("build 1.60.1.1 (2026-01-02). Do not edit.", text)
        self.assertIn("pack.categories.dungeons = function()", text)
        self.assertIn('[36] = { "dungeon", 11, 8000, 5000, 16 },', text)
        self.assertIn('[36] = "Dead \\"mines\\"",', text)


class ManualTest(unittest.TestCase):
    def manual_file(self, folder, name, body):
        path = os.path.join(folder, name)
        with open(path, "w", encoding="utf-8") as out:
            out.write("# comment\ninstance,uiMap,x,y,sources\n" + body)
        return path

    def test_manual_rows_and_later_file_wins(self):
        with tempfile.TemporaryDirectory() as folder:
            a = self.manual_file(folder, "a.csv", "2970,1434,21.4,27.9,guide one ; guide two\n")
            b = self.manual_file(folder, "b.csv", "2970,1434,22,28,other\n")
            (row,) = dungeons.manual([a])
            self.assertEqual((row[0], row[1], row[4]), (2970, 1434, "guide one ; guide two"))
            self.assertAlmostEqual(row[2], 0.214)
            self.assertAlmostEqual(row[3], 0.279)
            (row,) = dungeons.manual([a, b])
            self.assertEqual((row[1], row[4]), (1434, "other"))
            self.assertAlmostEqual(row[2], 0.22)

    def test_manual_rows_need_sources_and_a_place_on_the_map(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                dungeons.manual([self.manual_file(folder, "a.csv", "1,1434,21,27, \n")])
            with self.assertRaises(ValueError):
                dungeons.manual([self.manual_file(folder, "b.csv", "1,1434,121,27,x\n")])

    def test_merge_adds_and_overrides(self):
        rows = [instance(36, "Deadmines", 1, 0, 750, 600), instance(2970, "The Drowned City", 1, -1, 0, 0)]
        found = dungeons.entrances(MAPS, rows, {})
        merged = dungeons.merge(found, rows, {"The Drowned City": 35},
                                [(2970, 1434, 0.214, 0.279, "s"), (36, 11, 0.5, 0.5, "s")])
        self.assertEqual(merged, [(36, "dungeon", 11, 5000, 5000, 0), (2970, "dungeon", 1434, 2140, 2790, 35)])
        with self.assertRaises(ValueError):
            dungeons.merge(found, rows, {}, [(30, 1, 0.5, 0.5, "s")])  # not an instance


def poi(id_, name, flags, continent=0, x=750, y=600, condition=0):
    return {"ID": str(id_), "Name_lang": name, "Flags": str(flags), "ContinentID": str(continent), "Pos_0": str(x),
            "Pos_1": str(y), "PlayerConditionID": str(condition), "WorldStateID": "0"}


class PlacesTest(unittest.TestCase):
    def test_towns_and_places_only_once_per_map(self):
        import places
        rows = [
            poi(1, "Goldshire", 5),
            poi(2, "Stormwind", 29),  # a capital: a map of its own
            poi(3, "Tower", 135),  # PvP objective
            poi(4, "Whelgar's Excavation Site", 4),
            poi(5, "Goldshire", 4, x=760),  # the same name on the same map
            poi(6, "Hidden camp", 5, condition=77),  # only for some players
            poi(7, "Elsewhere", 4, continent=30),  # a battleground
        ]
        found = places.places(MAPS, rows)
        self.assertEqual([(p[0], p[1]) for p in found], [(1, "town"), (4, "place")])


class LuaTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(lua.row([1, "a\\b", True]), '{ 1, "a\\\\b", true }')
        with self.assertRaises(TypeError):
            lua.value(1.5)


if __name__ == "__main__":
    unittest.main()
