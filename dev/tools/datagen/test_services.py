"""Tests for the city services generator (no game, no network)."""

import csv
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import services  # noqa: E402

NPCS = [
    {"npc": "5595", "name": "Guardia de Forjaz", "faction": "Alliance", "services": "", "uiMap": "1455",
     "x": "0.33", "y": "0.63"},
    {"npc": "2460", "name": "Barnum", "faction": "Alliance", "services": "bank", "uiMap": "1455",
     "x": "0.3452", "y": "0.5893"},
    {"npc": "9", "name": "Herrero", "faction": "Alliance", "services": "vendor repair", "uiMap": "1455",
     "x": "0.5", "y": "0.5"},
    {"npc": "10", "name": "Banquera", "faction": "Horde", "services": "bank", "uiMap": "1454",
     "x": "0.4", "y": "0.4"},
]
DIRECTIONS = [
    {"key": "a", "locale": "esES", "asked": "Banco de Forjaz", "name": "Las Arcas", "guard": "5595",
     "uiMap": "1455", "x": "0.3515", "y": "0.6116"},
    {"key": "b", "locale": "esES", "asked": "Instructor de clases > Mago | Instructor de clases > Paladín",
     "name": "Sala de los Misterios", "guard": "5595", "uiMap": "1455", "x": "0.2692", "y": "0.1095"},
    {"key": "c", "locale": "", "asked": "Buzón", "name": "Buzón de Forjaz", "guard": "5595",
     "uiMap": "1455", "x": "0.2011", "y": "0.5331"},
    {"key": "d", "locale": "esES", "asked": "Algo nuevo", "name": "?", "guard": "5595",
     "uiMap": "1455", "x": "0.1", "y": "0.1"},
]
OBJECTS = [
    {"key": "m1", "service": "mailbox", "uiMap": "1455", "x": "0.3316", "y": "0.6521"},
    {"key": "m2", "service": "mailbox", "uiMap": "1455", "x": "0.2012", "y": "0.5332"},  # the guard's one
]


def write_csv(folder, name, rows):
    with open(os.path.join(folder, name + ".csv"), "w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class ServicesTest(unittest.TestCase):
    def test_guard_words(self):
        self.assertEqual(services.guard_service("Banco de Ventormenta"), "bank")
        self.assertEqual(services.guard_service("The Bank"), "bank")
        self.assertEqual(services.guard_service("Bank of Stormwind"), "bank")
        self.assertEqual(services.guard_service("BUZÓN"), "mailbox")
        self.assertEqual(services.guard_service("La posada"), "inn")
        self.assertEqual(services.guard_service("Instructor de clases > Mago"), "")
        self.assertEqual(services.guard_service("Bancal"), None)

    def test_points_guard_wins_mailboxes_add_up(self):
        with tempfile.TemporaryDirectory() as folder:
            write_csv(folder, "npcs", NPCS)
            write_csv(folder, "directions", DIRECTIONS)
            write_csv(folder, "objects", OBJECTS)
            found, unknown = services.points(folder)
        self.assertEqual(unknown, ["Algo nuevo"])
        merged = services.merge(found)
        kinds = [(p[0], p[1], p[6]) for p in merged]
        self.assertEqual(kinds, [
            (1454, "bank", "Banquera"),  # no guard there: the NPC
            (1455, "bank", "Las Arcas"),  # the guard's bank, not Barnum
            (1455, "mailbox", "Buzón de Forjaz"),  # the opened one at the same place is the same
            (1455, "mailbox", ""),
            (1455, "repair", "Herrero"),
        ])
        self.assertEqual(merged[0][4], "Horde")
        self.assertEqual(merged[1][4:6], ("Alliance", "esES"))
        self.assertEqual(merged[2][4:6], ("", "esES"))  # a mailbox is for anyone; harvested before records said their language
        self.assertEqual(merged[3][4:6], ("", ""))

    def test_write(self):
        found = [(1455, "bank", 0.3515, 0.6116, "Alliance", "esES", "Las Arcas"),
                 (1455, "mailbox", 0.3316, 0.6521, "", "", "")]
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Services.lua")
            self.assertEqual(services.write(path, "1.2.3.4", "2026-01-01", found), 2)
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("pack.categories.services = function()", text)
        self.assertIn('{ "bank", 3515, 6116, "Alliance", "esES", 1 },', text)
        self.assertIn('{ "mailbox", 3316, 6521, "", "", 0 },', text)
        self.assertIn('esES = {\n\t\t\t\t"Las Arcas",', text)


if __name__ == "__main__":
    unittest.main()
