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


def entry(key, instance, x, y, at, wing="", ui_map=1444):
    return {"key": key, "instance": instance, "name": "", "kind": "party", "uiMap": ui_map, "x": x, "y": y,
            "at": at, "wing": wing}


class EntrancesTest(unittest.TestCase):
    def test_average_of_the_entries_of_each_door(self):
        with tempfile.TemporaryDirectory() as folder:
            empty = {name: {} for name in harvest.FILES}
            harvest.merge(folder, dict(empty, entrances={
                "429:1": entry("429:1", 429, 0.60, 0.30, 1, "west"),
                "429:2": entry("429:2", 429, 0.62, 0.32, 2, "west"),
                "429:3": entry("429:3", 429, 0.65, 0.48, 3, "east"),
                "34:4": entry("34:4", 34, 0.50, 0.66, 4, ui_map=1453),
            }))
            found = harvest.entrances(folder)
        self.assertEqual([(r[0], r[5]) for r in found], [(34, ""), (429, "east"), (429, "west")])
        west = found[2]
        self.assertEqual((west[1], west[2], west[3]), (1444, 0.61, 0.31))
        self.assertEqual(west[4], "harvest (in game, average of 2 entries)")
        self.assertEqual(found[0][4], "harvest (in game)")

    def test_a_new_import_keeps_the_wing_written_by_hand(self):
        with tempfile.TemporaryDirectory() as folder:
            empty = {name: {} for name in harvest.FILES}
            harvest.merge(folder, dict(empty, entrances={"429:1": entry("429:1", 429, 0.6, 0.3, 1, "west")}))
            harvest.merge(folder, dict(empty, entrances={"429:1": entry("429:1", 429, 0.6, 0.3, 1)}))
            self.assertEqual(harvest.read(folder, "entrances")["429:1"]["wing"], "west")


class HarvestTest(unittest.TestCase):
    def test_import_and_merge(self):
        rows = harvest.rows_from_saved(SAVED)
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(harvest.merge(folder, rows)["npcs"], (1, 0))
            self.assertEqual(harvest.entrances(folder), [(3065, 1455, 0.2748, 0.4789, "harvest (in game)", "")])
            # the same again: nothing new; an older record does not replace a newer one
            older = harvest.rows_from_saved(SAVED.replace("1795717954", "100"))
            counts = harvest.merge(folder, older)
            self.assertEqual(counts["npcs"], (0, 1))
            self.assertEqual(counts["entrances"], (0, 0))
            self.assertEqual(harvest.read(folder, "entrances")["3065"]["key"], "3065")
            npc = harvest.read(folder, "npcs")["5099"]
            self.assertEqual(npc["services"], "bank")
            self.assertEqual(npc["gossip"], "132053:Banco | 132053:La posada")
            self.assertEqual(harvest.read(folder, "objects")["mailbox:1455:330:668"]["service"], "mailbox")
            direction = harvest.read(folder, "directions")["1455:356:609"]
            self.assertEqual((direction["name"], direction["guard"], direction["uiMap"]), ("Banco de Forjaz", "5595", "1455"))

    def test_places_an_npc_was_seen_add_up_across_imports(self):
        def npc(x, at, seen):
            return {"npc": "5109", "name": "Myra", "uiMap": 1455, "x": x, "y": 0.7, "at": at,
                    "seen": harvest.spots_text(seen)}
        with tempfile.TemporaryDirectory() as folder:
            empty = {name: {} for name in harvest.FILES}
            harvest.merge(folder, dict(empty, npcs={"5109": npc(0.27, 1, [(1455, 0.27, 0.7, "A1")])}))
            self.assertEqual(harvest.read(folder, "npcs")["5109"]["seen"], "1455:0.27:0.7:A1")
            # a later import (the SavedVariables were cleared): its places are added
            harvest.merge(folder, dict(empty, npcs={"5109": npc(0.4, 2, [(1455, 0.4, 0.7, "A1")])}))
            self.assertEqual(harvest.read(folder, "npcs")["5109"]["seen"], "1455:0.27:0.7:A1 1455:0.4:0.7:A1")
            # an older one doesn't replace the row, but its places count
            harvest.merge(folder, dict(empty, npcs={"5109": npc(0.5, 0, [(1455, 0.5, 0.7, "")])}))
            row = harvest.read(folder, "npcs")["5109"]
            self.assertEqual(row["x"], "0.4")
            self.assertEqual(harvest.spots(row["seen"]),
                             [(1455, 0.27, 0.7, "A1"), (1455, 0.4, 0.7, "A1"), (1455, 0.5, 0.7, "")])

    def test_reads_the_places_from_the_saved_variables(self):
        text = SAVED.replace('["x"] = 0.3631,', '["x"] = 0.3631, ["seen"] = { { 1455, 0.3631, 0.6, "00A1" }, { 1455, 0.5, 0.6 } },')
        self.assertIn('["seen"]', text)
        npc = harvest.rows_from_saved(text)["npcs"]["5099"]
        self.assertEqual(npc["seen"], "1455:0.3631:0.6:00A1 1455:0.5:0.6")


if __name__ == "__main__":
    unittest.main()
