"""Tests for the NPCs who walk a route (no game, no network)."""

import csv
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harvest  # noqa: E402
import roams  # noqa: E402
from geo import Maps  # noqa: E402

# Ironforge-like map: 1000 x 800 yards
UI_MAPS = [{"ID": "1455", "Type": "3", "System": "0", "Name_lang": "Forjaz"}]
ASSIGNMENTS = [{"UiMapID": "1455", "MapID": "0", "Region_0": "0", "Region_1": "0", "Region_2": "0",
                "Region_3": "800", "Region_4": "1000", "Region_5": "100",
                "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1", "AreaID": "1537"}]


def npcs_csv(folder, rows):
    with open(os.path.join(folder, "npcs.csv"), "w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, fieldnames=harvest.FILES["npcs"])
        writer.writeheader()
        writer.writerows(rows)


class RoamsTest(unittest.TestCase):
    def setUp(self):
        self.maps = Maps(UI_MAPS, ASSIGNMENTS)

    def test_yards_on_a_map(self):
        self.assertAlmostEqual(self.maps.yards(1455, 0, 0, 0.1, 0), 100)
        self.assertAlmostEqual(self.maps.yards(1455, 0, 0, 0, 0.1), 80)
        self.assertIsNone(self.maps.yards(9999, 0, 0, 1, 1))

    def test_far_apart(self):
        near = [(1455, 0.50, 0.50), (1455, 0.51, 0.51)]  # about 13 yards: talked to from two sides
        self.assertFalse(roams.far_apart(near, self.maps))
        self.assertTrue(roams.far_apart(near + [(1455, 0.60, 0.50)], self.maps))  # 100 yards
        self.assertFalse(roams.far_apart([(1455, 0.5, 0.5), (1453, 0.9, 0.9)], self.maps))  # other map
        self.assertFalse(roams.far_apart([(9999, 0.1, 0.1), (9999, 0.9, 0.9)], self.maps))  # size unknown

    def test_npcs_from_the_harvest_and_by_hand(self):
        with tempfile.TemporaryDirectory() as folder:
            npcs_csv(folder, [
                {"npc": "5109", "uiMap": "1455", "x": "0.4", "y": "0.7", "seen": "1455:0.2756:0.7192"},
                {"npc": "2460", "uiMap": "1455", "x": "0.3452", "y": "0.5893", "seen": "1455:0.345:0.589"},
                {"npc": "8720", "uiMap": "1455", "x": "0.2444", "y": "0.7443", "seen": ""},
            ])
            path = os.path.join(folder, "roams.csv")
            with open(path, "w", encoding="utf-8") as out:
                out.write("# by hand\nnpc,name,sources\n8720,Subastador Redmuse,Daniel in game 2026-11-28\n")
            self.assertEqual(roams.npcs(folder, self.maps, path), {5109, 8720})
            self.assertEqual(roams.npcs(folder, self.maps), {5109})
            with open(path, "w", encoding="utf-8") as out:
                out.write("npc,name,sources\n8720,Subastador Redmuse,\n")
            with self.assertRaises(ValueError):
                roams.manual(path)  # a flag needs its sources


if __name__ == "__main__":
    unittest.main()
