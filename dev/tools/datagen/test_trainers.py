"""Tests for the trainers generator (no game, no network)."""

import csv
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import trainers  # noqa: E402

NPCS = [
    {"npc": "5595", "name": "Guardia de Forjaz", "faction": "Alliance", "services": "", "skill": "",
     "uiMap": "1455", "x": "0.33", "y": "0.63"},
    {"npc": "4772", "name": "Ultham Hierrocuerno", "faction": "Alliance", "services": "trainer",
     "skill": "Equitación", "uiMap": "1426", "x": "0.6382", "y": "0.5011"},
    {"npc": "5164", "name": "Grumnus Aceroforma", "faction": "Alliance", "services": "trainer vendor",
     "skill": "Herrería", "uiMap": "1455", "x": "0.5", "y": "0.42"},  # the guard's one: left out
    {"npc": "5146", "name": "Nittlebur", "faction": "Alliance", "services": "trainer", "skill": "Fuego",
     "uiMap": "1455", "x": "0.27", "y": "0.11"},  # a class trainer: not told apart
]
DIRECTIONS = [
    {"locale": "esES", "asked": "Instructor de clases > Mago | Instructor de clases > Paladín",
     "name": "Sala de los Misterios", "guard": "5595", "uiMap": "1455", "x": "0.2692", "y": "0.1095"},
    {"locale": "esES", "asked": "Instructor de profesiones > Herrería", "name": "La Gran Fundición",
     "guard": "5595", "uiMap": "1455", "x": "0.5016", "y": "0.4316"},
    {"locale": "esES", "asked": "Instructor de armas", "name": "Bixi y Buliwyf", "guard": "5595",
     "uiMap": "1455", "x": "0.6176", "y": "0.8923"},
    {"locale": "esES", "asked": "Banco de Forjaz", "name": "Las Arcas", "guard": "5595",
     "uiMap": "1455", "x": "0.3515", "y": "0.6116"},
    {"locale": "esES", "asked": "Instructor de clases > Monje", "name": "?", "guard": "5595",
     "uiMap": "1455", "x": "0.1", "y": "0.1"},
]


def write_csv(folder, name, rows):
    with open(os.path.join(folder, name + ".csv"), "w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class TrainersTest(unittest.TestCase):
    def test_guard_words(self):
        self.assertEqual(trainers.guard_trainer("Instructor de clases > Pícaro"), ("class", "ROGUE"))
        self.assertEqual(trainers.guard_trainer("Class Trainer > Mage"), ("class", "MAGE"))
        self.assertEqual(trainers.guard_trainer("Instructor de profesiones > Primeros auxilios"),
                         ("profession", "firstaid"))
        self.assertEqual(trainers.guard_trainer("Profession Trainer > Herbalism"), ("profession", "herbalism"))
        self.assertEqual(trainers.guard_trainer("Instructor de profesiones > Equitación"), ("riding", ""))
        self.assertEqual(trainers.guard_trainer("Instructor de armas"), ("weapon", ""))
        self.assertEqual(trainers.guard_trainer("Weapon Master"), ("weapon", ""))
        self.assertIsNone(trainers.guard_trainer("Banco de Forjaz"))
        self.assertIs(trainers.guard_trainer("Instructor de clases > Monje"), False)

    def test_npc_skill(self):
        self.assertEqual(trainers.npc_trainer("Equitación"), ("riding", ""))
        self.assertEqual(trainers.npc_trainer("Mining"), ("profession", "mining"))
        self.assertIsNone(trainers.npc_trainer("Fuego"))
        self.assertIsNone(trainers.npc_trainer(""))

    def test_points(self):
        with tempfile.TemporaryDirectory() as folder:
            write_csv(folder, "npcs", NPCS)
            write_csv(folder, "directions", DIRECTIONS)
            found, unknown = trainers.points(folder)
        self.assertEqual(unknown, ["Instructor de clases > Monje"])
        merged = trainers.merge(found)
        self.assertEqual([(p[0], p[1], p[2], p[7]) for p in merged], [
            (1426, "riding", "", "Ultham Hierrocuerno"),
            (1455, "class", "MAGE", "Sala de los Misterios"),
            (1455, "class", "PALADIN", "Sala de los Misterios"),
            (1455, "profession", "blacksmithing", "La Gran Fundición"),
            (1455, "weapon", "", "Bixi y Buliwyf"),
        ])
        self.assertEqual(merged[1][5:7], ("Alliance", "esES"))  # the guard's faction

    def test_write(self):
        found = [(1455, "class", "MAGE", 0.2692, 0.1095, "Alliance", "esES", "Sala de los Misterios"),
                 (1455, "class", "PALADIN", 0.2692, 0.1095, "Alliance", "esES", "Sala de los Misterios"),
                 (1455, "weapon", "", 0.6176, 0.8923, "Alliance", "", "")]
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Trainers.lua")
            self.assertEqual(trainers.write(path, "1.2.3.4", "2026-01-01", found), 3)
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("pack.categories.trainers = function()", text)
        self.assertIn('{ "class", "MAGE", 2692, 1095, "Alliance", "esES", 1 },', text)
        self.assertIn('{ "class", "PALADIN", 2692, 1095, "Alliance", "esES", 1 },', text)
        self.assertIn('{ "weapon", "", 6176, 8923, "Alliance", "", 0 },', text)
        self.assertEqual(text.count('"Sala de los Misterios"'), 1)


if __name__ == "__main__":
    unittest.main()
