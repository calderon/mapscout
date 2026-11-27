"""Tests for the graveyards generator (no game, no network)."""

import csv
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import graveyards  # noqa: E402
import harvest  # noqa: E402

ROWS = [
    # Dun Morogh, outside Ironforge: two deaths, a spirit healer talked to
    {"key": "death:1", "how": "death", "uiMap": "1426", "x": "0.5435", "y": "0.3924", "at": "1"},
    {"key": "death:2", "how": "death", "uiMap": "1426", "x": "0.5437", "y": "0.3926", "at": "2"},
    {"key": "healer:3", "how": "healer", "npc": "6491", "uiMap": "1426", "x": "0.5421", "y": "0.3903", "at": "3"},
    # Another graveyard of the same zone (Kharanos), only talked to
    {"key": "healer:4", "how": "healer", "npc": "6491", "uiMap": "1426", "x": "0.47", "y": "0.55", "at": "4"},
    {"key": "healer:5", "how": "healer", "npc": "6491", "uiMap": "1426", "x": "0.472", "y": "0.552", "at": "5"},
    # Same numbers, another map: another graveyard
    {"key": "death:6", "how": "death", "uiMap": "1429", "x": "0.5435", "y": "0.3924", "at": "6"},
]


class GraveyardsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        columns = harvest.FILES["graveyards"]
        with open(os.path.join(self.dir.name, "graveyards.csv"), "w", newline="", encoding="utf-8") as out:
            writer = csv.DictWriter(out, fieldnames=columns)
            writer.writeheader()
            for row in ROWS:
                writer.writerow({c: row.get(c, "") for c in columns})

    def tearDown(self):
        self.dir.cleanup()

    def test_joins_the_records_of_one_graveyard(self):
        self.assertEqual(graveyards.points(self.dir.name), [
            (1426, 0.471, 0.551, 2),  # only talked to: their average
            (1426, 0.5436, 0.3925, 3),  # the deaths' average: exact, the healer's point is not used
            (1429, 0.5435, 0.3924, 1),
        ])

    def test_writes_the_pack(self):
        path = os.path.join(self.dir.name, "SpiritHealers.lua")
        count = graveyards.write(path, "1.60.1.71139", "2026-11-25", graveyards.points(self.dir.name))
        self.assertEqual(count, 3)
        with open(path, encoding="utf-8") as source:
            text = source.read()
        self.assertIn("pack.categories.spirithealers = function()", text)
        self.assertIn("[1426] = {\n\t\t\t\t{ 4710, 5510 },\n\t\t\t\t{ 5436, 3925 },\n\t\t\t},", text)

    def test_imports_them_from_the_saved_variables(self):
        text = """MapScoutDB = { ["harvest"] = { ["graveyards"] = {
            ["death:9"] = { ["how"] = "death", ["map"] = 1426, ["x"] = 0.5435, ["y"] = 0.3924, ["continent"] = 1415,
                ["cx"] = 0.4794, ["cy"] = 0.5383, ["died"] = 1455, ["at"] = 9 },
            ["healer:10"] = { ["how"] = "healer", ["npc"] = 6491, ["map"] = 1426, ["x"] = 0.5421, ["y"] = 0.3903,
                ["at"] = 10 },
        } } }"""
        rows = harvest.rows_from_saved(text)["graveyards"]
        self.assertEqual(rows["death:9"]["continent"], 1415)
        self.assertEqual(rows["death:9"]["died"], 1455)
        self.assertEqual(rows["healer:10"]["npc"], 6491)
        self.assertEqual(rows["healer:10"]["cx"], "")


if __name__ == "__main__":
    unittest.main()
