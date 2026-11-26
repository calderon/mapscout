"""Tests for the SavedVariables reader and the harvest importer (no game, no network)."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harvest  # noqa: E402
import savedvars  # noqa: E402

SAVED = r'''
MapScoutDB = {
["harvest"] = {
["entrances"] = {
[3065] = {
["map"] = 1455,
["x"] = 0.2748,
["name"] = "El Salón de los Feudales",
["instance"] = 3065,
["kind"] = "party",
["at"] = 1795717954,
["y"] = 0.4789,
},
},
["objects"] = {
["mailbox:1455:330:668"] = {
["service"] = "mailbox",
["map"] = 1455,
["x"] = 0.3301,
["y"] = 0.6688,
["at"] = 5,
},
},
["directions"] = {
["1455:356:609"] = {
["map"] = 1455,
["x"] = 0.3561,
["y"] = 0.6093,
["name"] = "Banco de Forjaz",
["texture"] = 7,
["asked"] = "Banco de Forjaz",
["guard"] = 5595,
["at"] = 9,
},
},
["on"] = true,
["npcs"] = {
[5099] = {
["at"] = 1795717435,
["x"] = 0.3631,
["name"] = "Soleil \"la\" Mantopétreo",
["services"] = {
["bank"] = true,
},
["id"] = 5099,
["map"] = 1455,
["y"] = 0.6228,
["faction"] = "Alliance",
["gossip"] = {
"132053:Banco",
"132053:La posada", -- [2]
},
},
},
},
["schema"] = 2,
["empty"] = {
},
}
MapScoutCharDB = nil
'''


class SavedVarsTest(unittest.TestCase):
    def test_reads_tables_lists_strings_numbers(self):
        data = savedvars.load(SAVED)
        db = data["MapScoutDB"]
        self.assertEqual(db["schema"], 2)
        self.assertEqual(db["empty"], {})
        self.assertIsNone(data["MapScoutCharDB"])
        npc = db["harvest"]["npcs"][5099]
        self.assertEqual(npc["name"], 'Soleil "la" Mantopétreo')
        self.assertEqual(npc["gossip"], ["132053:Banco", "132053:La posada"])
        self.assertIs(npc["services"]["bank"], True)
        self.assertAlmostEqual(npc["x"], 0.3631)


class HarvestTest(unittest.TestCase):
    def test_import_and_merge(self):
        rows = harvest.rows_from_saved(SAVED)
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(harvest.merge(folder, rows)["npcs"], (1, 0))
            self.assertEqual(harvest.entrances(folder), [(3065, 1455, 0.2748, 0.4789, "harvest (in game)")])
            # the same again: nothing new; an older record does not replace a newer one
            older = harvest.rows_from_saved(SAVED.replace("1795717954", "100"))
            counts = harvest.merge(folder, older)
            self.assertEqual(counts["npcs"], (0, 1))
            self.assertEqual(counts["entrances"], (0, 0))
            npc = harvest.read(folder, "npcs")["5099"]
            self.assertEqual(npc["services"], "bank")
            self.assertEqual(npc["gossip"], "132053:Banco | 132053:La posada")
            self.assertEqual(harvest.read(folder, "objects")["mailbox:1455:330:668"]["service"], "mailbox")
            direction = harvest.read(folder, "directions")["1455:356:609"]
            self.assertEqual((direction["name"], direction["guard"], direction["uiMap"]), ("Banco de Forjaz", "5595", "1455"))


if __name__ == "__main__":
    unittest.main()
