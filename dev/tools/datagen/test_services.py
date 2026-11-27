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
    {"key": "e", "locale": "esES", "asked": "Maestro de batalla > Valle de Alterac", "name": "Glordrum",
     "guard": "5595", "uiMap": "1455", "x": "0.6959", "y": "0.9072"},
    {"key": "f", "locale": "esES", "asked": "Maestro de batalla > Cuenca de Arathi", "name": "Donal",
     "guard": "5595", "uiMap": "1455", "x": "0.6960", "y": "0.9073"},  # next to the other: not the same
    {"key": "g", "locale": "esES", "asked": "Maestro de batalla > Ojo de la Tormenta", "name": "?",
     "guard": "5595", "uiMap": "1455", "x": "0.2", "y": "0.2"},
    {"key": "h", "locale": "esES", "asked": "Peluquería", "name": "Peluquería de Forjaz", "guard": "5595",
     "uiMap": "1455", "x": "0.267", "y": "0.5028"},
]
OBJECTS = [
    {"key": "m1", "service": "mailbox", "uiMap": "1455", "x": "0.3316", "y": "0.6521"},
    {"key": "m2", "service": "mailbox", "uiMap": "1455", "x": "0.2012", "y": "0.5332"},  # the guard's one
    {"key": "a1", "service": "anvil", "uiMap": "1455", "x": "0.5126", "y": "0.4236"},
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
        self.assertEqual(services.guard_service("Peluquería"), "barber")
        self.assertEqual(services.guard_service("Maestro de la hermandad"), "guild")
        self.assertEqual(services.guard_service("Maestro de batalla > Valle de Alterac"), "battle")
        self.assertEqual(services.guard_service("Maestro de grifos"), "")
        self.assertEqual(services.guard_service("Transfigurador"), "transmog")

    def test_battlegrounds(self):
        self.assertEqual(services.battleground("Maestro de batalla > Garganta Grito de Guerra"), "warsong")
        self.assertEqual(services.battleground("Battlemaster > Arathi Basin"), "arathi")
        self.assertEqual(services.battleground("Maestro de batalla"), "")
        self.assertEqual(services.battleground("Maestro de batalla > Ojo de la Tormenta"), None)

    def test_points_guard_wins_mailboxes_add_up(self):
        with tempfile.TemporaryDirectory() as folder:
            write_csv(folder, "npcs", NPCS)
            write_csv(folder, "directions", DIRECTIONS)
            write_csv(folder, "objects", OBJECTS)
            found, unknown = services.points(folder)
        self.assertEqual(unknown, ["Algo nuevo", "Maestro de batalla > Ojo de la Tormenta"])
        merged = services.merge(found)
        kinds = [(p[0], p[1], p[6], p[7]) for p in merged]
        self.assertEqual(kinds, [
            (1454, "bank", "Banquera", ""),  # no guard there: the NPC
            (1455, "bank", "Las Arcas", ""),  # the guard's bank, not Barnum
            (1455, "mailbox", "Buzón de Forjaz", ""),  # the opened one at the same place is the same
            (1455, "mailbox", "", ""),
            (1455, "repair", "Herrero", ""),
            (1455, "barber", "Peluquería de Forjaz", ""),
            (1455, "battle", "Glordrum", "alterac"),  # one point per battleground
            (1455, "battle", "Donal", "arathi"),
            (1455, "anvil", "", ""),
        ])
        self.assertEqual(merged[0][4], "Horde")
        self.assertEqual(merged[1][4:6], ("Alliance", "esES"))
        self.assertEqual(merged[2][4:6], ("", "esES"))  # a mailbox is for anyone; harvested before records said their language
        self.assertEqual(merged[3][4:6], ("", ""))

    def test_manual_only_where_not_harvested(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "services.csv")
            with open(path, "w", encoding="utf-8") as out:
                out.write("# a comment\nservice,uiMap,x,y,faction,sources\n"
                          "transmog,1454,46.2,53.4,Horde,https://a ; https://b\n"
                          "transmog,1453,48,84.5,Alliance,https://a ; https://b\n")
            hand = services.manual(path)
            self.assertEqual(hand[0], (1454, "transmog", 0.462, 0.534, "Horde", "", "", ""))
            harvested = [(1453, "transmog", 0.4821, 0.8471, "Alliance", "esES", "Transfigurador", "")]
            found = services.with_manual(harvested, hand)
            self.assertEqual([(p[0], p[6]) for p in found], [(1453, "Transfigurador"), (1454, "")])
            with open(path, "w", encoding="utf-8") as out:
                out.write("service,uiMap,x,y,faction,sources\ntransmog,1454,46.2,53.4,Horde,https://a\n")
            with self.assertRaises(ValueError):
                services.manual(path)  # one source is not enough

    def test_write(self):
        found = [(1455, "bank", 0.3515, 0.6116, "Alliance", "esES", "Las Arcas", ""),
                 (1455, "mailbox", 0.3316, 0.6521, "", "", "", ""),
                 (1455, "battle", 0.6959, 0.9072, "Alliance", "esES", "Glordrum", "alterac")]
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Services.lua")
            self.assertEqual(services.write(path, "1.2.3.4", "2026-01-01", found), 3)
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("pack.categories.services = function()", text)
        self.assertIn('{ "bank", 3515, 6116, "Alliance", "esES", 1 },', text)
        self.assertIn('{ "mailbox", 3316, 6521, "", "", 0 },', text)
        self.assertIn('{ "battle", 6959, 9072, "Alliance", "esES", 2, "alterac" },', text)
        self.assertIn('esES = {\n\t\t\t\t"Las Arcas",', text)


if __name__ == "__main__":
    unittest.main()
