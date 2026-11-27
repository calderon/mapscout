"""Unit tests for the data generator (no network): python3 -m unittest discover dev/tools/datagen"""

import os
import sys
import tempfile
import unittest
from unittest import mock

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

    def test_a_subzone_on_its_own_zone_where_rectangles_overlap(self):
        zone12 = assignment(12, 0, 0, 0, 300, 600)
        zone12["AreaID"] = "40"
        maps = Maps([ui_map(10, 2), ui_map(12, 3), ui_map(13, 3)],
                    [assignment(10, 0, 0, 0, 1000, 1000), zone12, assignment(13, 0, 0, 400, 300, 1000)])
        self.assertEqual(maps.place_in_zone(40, 0, 100, 500)[0], 12)
        self.assertEqual(maps.place_in_zone(99, 0, 100, 500)[0], 10)  # another zone: the continent

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

    def test_other_names_from_the_area_when_they_differ(self):
        maps = {"enUS": [{"ID": "109", "MapName_lang": "Sunken Temple", "AreaTableID": "1477"},
                         {"ID": "70", "MapName_lang": "Uldaman", "AreaTableID": "1337"},
                         {"ID": "36", "MapName_lang": "Deadmines", "AreaTableID": "0"},
                         {"ID": "34", "MapName_lang": "Stormwind Stockade", "AreaTableID": "717"}],
                "esES": [{"ID": "109", "MapName_lang": "Templo Sumergido", "AreaTableID": "1477"}]}
        areas = {"enUS": [{"ID": "1477", "AreaName_lang": "The Temple of Atal'Hakkar"},
                          {"ID": "1337", "AreaName_lang": "uldaman"},
                          {"ID": "717", "AreaName_lang": "The Stockade"}],
                 "esES": [{"ID": "1477", "AreaName_lang": "El Templo de Atal'Hakkar"}]}
        found = dungeons.other_names(maps, areas, [109, 70, 36])
        self.assertEqual(found, {"enUS": {109: "The Temple of Atal'Hakkar"},
                                 "esES": {109: "El Templo de Atal'Hakkar"}})

    def test_write_is_stable_lua(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Dungeons.lua")
            dungeons.write(path, "1.60.1.1", "2026-01-02", [(36, "dungeon", 11, 8000, 5000, 16)],
                           {"enUS": {36: 'Dead "mines"'}}, other_names_by_locale={"enUS": {36: "The Mines"}})
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn('otherNames = {\n\t\t\tenUS = {\n\t\t\t\t[36] = "The Mines",', text)
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
            self.assertEqual((row[0], row[1], row[4], row[5]), (2970, 1434, "guide one ; guide two", ""))
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

    def test_manual_doors_need_a_known_wing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "a.csv")
            with open(path, "w", encoding="utf-8") as out:
                out.write("instance,uiMap,x,y,sources,wing\n189,1420,85.35,32.39,s,library\n189,1420,84.8,30.37,s,graveyard\n")
            rows = dungeons.manual([path])
            self.assertEqual([(r[0], r[5]) for r in rows], [(189, "graveyard"), (189, "library")])
            with open(path, "a", encoding="utf-8") as out:
                out.write("189,1420,1,1,s,kitchen\n")
            with self.assertRaises(ValueError):
                dungeons.manual([path])

    def test_merge_adds_and_overrides(self):
        rows = [instance(36, "Deadmines", 1, 0, 750, 600), instance(2970, "The Drowned City", 1, -1, 0, 0)]
        found = dungeons.entrances(MAPS, rows, {})
        merged = dungeons.merge(found, rows, {"The Drowned City": 35},
                                [(2970, 1434, 0.214, 0.279, "s", ""), (36, 11, 0.5, 0.5, "s", "")])
        self.assertEqual(merged, [(36, "dungeon", 11, 5000, 5000, 0), (2970, "dungeon", 1434, 2140, 2790, 35)])
        with self.assertRaises(ValueError):
            dungeons.merge(found, rows, {}, [(30, 1, 0.5, 0.5, "s", "")])  # not an instance

    def test_doors_replace_the_single_entrance(self):
        rows = [instance(189, "Scarlet Monastery", 1, 0, 750, 600)]
        found = dungeons.entrances(MAPS, rows, {})
        doors = [(189, 1420, 0.8535, 0.3239, "s", "library"), (189, 1420, 0.848, 0.3037, "s", "graveyard"),
                 (189, 1420, 0.826, 0.338, "s", "armory")]
        self.assertEqual(dungeons.merge(found, rows, {}, doors), [(189, "dungeon", 0, 0, 0, 0)])
        checked = {(189, "library"), (189, "graveyard")}  # the armory is not checked: no door
        self.assertEqual(dungeons.doors(doors, checked),
                         {189: [("library", 1420, 8535, 3239), ("graveyard", 1420, 8480, 3037)]})

    def test_via_only_between_kept_instances(self):
        found = [(229, "dungeon", 1427, 3480, 8400, 53), (230, "dungeon", 1427, 3480, 8400, 48),
                 (409, "raid", 0, 0, 0, 60)]
        self.assertEqual(dungeons.via(found), {409: (230, "")})

    def test_write_doors(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Dungeons.lua")
            dungeons.write(path, "1.60.1.1", "2026-01-02", [(329, "dungeon", 0, 0, 0, 55)], {"enUS": {329: "Stratholme"}},
                           [(329, 1423, 0.3, 0.15, "s", "main")], {329: [("main", 1423, 3000, 1500)]},
                           {409: (230, ""), 469: (229, "upper")})
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("-- Source: instance 329 (main): s", text)
        self.assertIn('\t\t\t[329] = {\n\t\t\t\t{ "main", 1423, 3000, 1500 },\n\t\t\t},', text)
        self.assertIn("[409] = { 230 },", text)
        self.assertIn('[469] = { 229, "upper" },', text)


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


def area_row(id_, name, parent=40, continent=0):
    return {"ID": str(id_), "AreaName_lang": name, "ParentAreaID": str(parent), "ContinentID": str(continent)}


class TerrainTest(unittest.TestCase):
    @staticmethod
    def chunk(tag, data):
        import struct
        return tag[::-1].encode() + struct.pack("<I", len(data)) + data

    def test_tile_files_from_the_wdt(self):
        import struct
        import terrain
        maid = bytearray(4096 * 32)
        struct.pack_into("<8I", maid, 5 * 32, 777, 1, 2, 3, 4, 5, 6, 7)
        struct.pack_into("<8I", maid, 9 * 32, 555, 0, 0, 0, 0, 0, 0, 0)
        wdt = self.chunk("MVER", b"\x12\0\0\0") + self.chunk("MAID", bytes(maid))
        self.assertEqual(terrain.tile_files(wdt), [555, 777])

    def test_tile_areas_from_the_adt(self):
        import struct
        import terrain
        header = bytearray(128 + 16)
        struct.pack_into("<I", header, terrain.MCNK_AREA, 107)
        struct.pack_into("<3f", header, terrain.MCNK_POSITION, 1000.0, 2000.0, 5.0)
        adt = self.chunk("MVER", b"\x12\0\0\0") + self.chunk("MCNK", bytes(header))
        self.assertEqual(terrain.tile_areas(adt), [[107, round(1000 - terrain.CHUNK / 2, 1),
                                                     round(2000 - terrain.CHUNK / 2, 1)]])

    def test_middles_deep_inside_the_biggest_piece(self):
        import terrain
        c = terrain.CHUNK
        # chunk centres, as the tiles give them: half a chunk from the grid lines
        chunks = [[1, (x + 0.5) * c, (y + 0.5) * c] for x in range(5) for y in range(5)]  # a 5 x 5 square
        chunks += [[1, 40.5 * c, 40.5 * c]]  # a loose chunk far away
        chunks += [[2, (x + 0.5) * c, 10.5 * c] for x in range(3)]  # a line, not wanted
        found = terrain.middles(chunks, {1})
        self.assertEqual(list(found), [1])
        self.assertAlmostEqual(found[1][0], 2.5 * c)
        self.assertAlmostEqual(found[1][1], 2.5 * c)
        self.assertEqual(found[1][2], 25)

    def test_middles_of_a_ring_stay_on_the_ground(self):
        import terrain
        c = terrain.CHUNK
        ring = [[1, (x + 0.5) * c, (y + 0.5) * c] for x in range(5) for y in range(5) if x in (0, 4) or y in (0, 4)]
        x, y, _ = terrain.middles(ring, {1})[1]
        self.assertTrue(any(abs(x - cx) < 0.01 and abs(y - cy) < 0.01 for _, cx, cy in ring))

    def test_middles_of_real_chunk_centres_make_one_piece(self):
        import terrain
        # centres from tile_areas: corner minus half a chunk, rounded to 0.1
        corner = 6400.0
        chunks = [[1, round(corner - i * terrain.CHUNK - terrain.CHUNK / 2, 1), -16.7] for i in range(9)]
        self.assertEqual(terrain.middles(chunks, {1})[1][2], 9)


class SubzonesTest(unittest.TestCase):
    def test_only_subzones_not_found_yet_on_outdoor_continents(self):
        import places
        import terrain
        c = terrain.CHUNK
        areas = [
            area_row(107, "Saldean's Farm"),
            area_row(87, "Goldshire"),  # already an AreaPOI place
            area_row(40, "Westfall", parent=0),  # a zone
            area_row(111, "Jangolode Mine"),  # no ground of its own
            area_row(900, "Battleground camp", continent=30),
            area_row(2364, "The Great Sea"),  # the sea next to the coast
            area_row(2518, "Lariss Pavilion"),  # the place is "Lariss Pavillion", same name in Spanish
            area_row(200, "Lordamere Lake"), area_row(201, "Lordamere Lake", parent=41),  # split by a border
        ]
        chunks = {0: [[107, 600 + c * i, 700] for i in range(3)] + [[87, 650, 650], [40, 900, 900], [2364, 700, 950]]
                      + [[200, 800, 800]] + [[201, 800 + c * i, 850] for i in range(2)]}
        chunks[0].append([2518, 610, 610])
        found = places.subzones(MAPS, areas, chunks, ["goldshire", "Westfall", "Pabellón de Lariss"],
                                {2518: ["Pabellón de Lariss"]})
        self.assertEqual([a[0] for a in found], [107, 201])
        self.assertEqual(found[0][1], 11)

    def test_write_areas_and_their_names(self):
        import places
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Places.lua")
            places.write(path, "1.0", "2026-01-01", [(1, "town", 10, 5, 6)], {"enUS": {1: "Goldshire"}},
                         [(107, 1436, 4500, 3000)], {"enUS": {107: "Saldean's Farm"}, "esES": {107: "Granja de Saldean"}})
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("[107] = { 1436, 4500, 3000 },", text)
        self.assertIn('[107] = "Granja de Saldean",', text)


def path_node(path, index, continent, x, y, z=0, flags=0):
    return {"PathID": str(path), "NodeIndex": str(index), "ContinentID": str(continent), "Loc_0": str(x),
            "Loc_1": str(y), "Loc_2": str(z), "Flags": str(flags)}


def line(id_, kind, path=0, triggers=(), faction=""):
    return {"line": id_, "kind": kind, "faction": faction, "path": path, "triggers": list(triggers)}


class TransportTest(unittest.TestCase):
    # path 1: a boat between a dock in zone 11 and one in zone 12; path 2: a
    # zeppelin up high, from the same pier as path 1's first stop and back
    NODES = [
        path_node(1, 0, 0, 750, 600, flags=2), path_node(1, 1, 0, 400, 300), path_node(1, 2, 0, 100, 100, flags=2),
        path_node(2, 0, 0, 755, 600, z=80, flags=2), path_node(2, 1, 0, 600, 900, z=90),
        path_node(2, 2, 0, 900, 900, z=80, flags=2),
        path_node(3, 0, 0, 100, 100), path_node(3, 1, 0, 200, 200),  # a flight path: no stops
    ]

    def stops(self):
        import transport
        return transport.path_stops(self.NODES)

    def test_stops_in_order_and_height(self):
        stops, heights = self.stops()
        self.assertEqual(sorted(stops), [1, 2])
        self.assertEqual([s[:3] for s in stops[1]], [(0, 750, 600), (0, 100, 100)])
        self.assertEqual(heights[1], 0)
        self.assertEqual(heights[2], 80)

    def test_check_kinds_and_unlisted_paths(self):
        import transport
        stops, heights = self.stops()
        self.assertEqual(transport.check([line(1, "boat", 1), line(2, "zeppelin", 2)], stops, heights), [])
        problems = transport.check([line(1, "zeppelin", 1), line(9, "boat", 9)], stops, heights)
        self.assertEqual(len(problems), 3)  # 1 is not up high, 9 has no stops, 2 is not listed
        self.assertEqual(transport.check([line(1, "boat", 1), line(2, "none", 2)], stops, heights), [])

    def test_docks_named_after_towns_with_their_destinations(self):
        import transport
        stops, _ = self.stops()
        pois = [poi(40, "Booty Bay", 5, x=760, y=610), poi(41, "Faraway", 5, x=100, y=900),
                poi(33, "Orgrimmar", 29, x=900, y=950), poi(42, "Hamlet", 5, x=890, y=900)]
        triggers = [{"ID": "7", "ContinentID": "0", "Pos_0": "800", "Pos_1": "800"},
                    {"ID": "8", "ContinentID": "0", "Pos_0": "200", "Pos_1": "100"}]
        with mock.patch.object(transport, "NEAR_TOWN", 100):  # the test world is only 1000 yards wide
            found = transport.docks(MAPS, [line(2, "zeppelin", 2), line(1, "boat", 1), line(5, "tram", 0, (7, 8)),
                                           line(4, "none", 2)], stops, triggers, pois)
        self.assertEqual(found, [
            (11, "boat", 11, 8000, 5000, 40, "", [12]),
            (12, "boat", 12, 8333, 6667, 0, "", [11]),  # no town near it
            (21, "zeppelin", 11, 8000, 4900, 40, "", [22]),  # same pier, another kind: a dock of its own
            (22, "zeppelin", 11, 2000, 2000, 33, "", [21]),  # the capital wins over the nearer town
            (51, "tram", 11, 4000, 4000, 0, "", [52]),  # the tram's entrances: area triggers
            (52, "tram", 12, 8333, 3333, 0, "", [51]),
        ])

    def test_lines_of_one_pier_share_a_dock(self):
        import transport
        nodes = self.NODES + [path_node(4, 0, 0, 760, 600, flags=2), path_node(4, 1, 0, 900, 900, flags=2)]
        stops, _ = transport.path_stops(nodes)
        found = transport.docks(MAPS, [line(1, "boat", 1), line(4, "boat", 4)], stops, [], [])
        self.assertEqual([(d[0], d[7]) for d in found], [(11, [12, 42]), (12, [11]), (42, [11])])

    def test_dock_faction_is_its_lines_faction(self):
        import transport
        nodes = self.NODES + [path_node(4, 0, 0, 760, 600, flags=2), path_node(4, 1, 0, 900, 900, flags=2),
                              path_node(5, 0, 0, 100, 900, flags=2), path_node(5, 1, 0, 900, 100, flags=2)]
        stops, _ = transport.path_stops(nodes)
        found = transport.docks(MAPS, [line(1, "boat", 1, faction="Alliance"), line(4, "boat", 4, faction="Horde"),
                                       line(5, "boat", 5, faction="pending")], stops, [], [])
        self.assertEqual({d[0]: d[6] for d in found}, {
            11: "",  # one pier of both factions: anyone
            12: "Alliance",
            42: "Horde",
            51: "", 52: "",  # pending: anyone until checked
        })
        self.assertEqual(transport.pending([line(5, "boat", 5, faction="pending"), line(6, "none", 6)]), [5])

    def test_lines_file(self):
        import transport
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "transport.csv")
            with open(path, "w", encoding="utf-8") as out:
                out.write("line,kind,faction,path,triggers,note\n241,boat,Anyone,241,,x\n"
                          "369,tram,Alliance,,2173 2175,y\n11391,boat,pending,11391,,z\n436,none,,436,,w\n")
            self.assertEqual(transport.lines(path), [
                line(241, "boat", 241), line(369, "tram", 0, (2173, 2175), "Alliance"),
                line(11391, "boat", 11391, faction="pending"), line(436, "none", 436)])
            for bad in ("1,rocket,Anyone,1,,x", "1,boat,,1,,x", "1,boat,horde,1,,x"):
                with open(path, "w", encoding="utf-8") as out:
                    out.write("line,kind,faction,path,triggers,note\n%s\n" % bad)
                with self.assertRaises(ValueError):
                    transport.lines(path)

    def test_write(self):
        import transport
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Transport.lua")
            transport.write(path, "1.60.1.1", "2026-01-02", [(11, "boat", 11, 8000, 5000, 40, "Horde", [12])],
                            {"enUS": {40: "Booty Bay"}})
            with open(path, encoding="utf-8") as source:
                text = source.read()
        self.assertIn("pack.categories.transport = function()", text)
        self.assertIn('[11] = { "boat", 11, 8000, 5000, 40, "Horde", 12 },', text)
        self.assertIn('[40] = "Booty Bay",', text)


class LuaTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(lua.row([1, "a\\b", True]), '{ 1, "a\\\\b", true }')
        with self.assertRaises(TypeError):
            lua.value(1.5)


if __name__ == "__main__":
    unittest.main()
