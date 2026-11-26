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
        self.assertIn('[36] = { "dungeon", 11, 8000, 5000, 16 },', text)
        self.assertIn('[36] = "Dead \\"mines\\"",', text)


class LuaTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(lua.row([1, "a\\b", True]), '{ 1, "a\\\\b", true }')
        with self.assertRaises(TypeError):
            lua.value(1.5)


if __name__ == "__main__":
    unittest.main()
