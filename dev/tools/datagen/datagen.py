"""MapScout static data generator for WoW Forever.

Reads the client data tables (DB2) of one exact Forever build and writes the
Lua files of the MapScout_Data_Forever pack. See README.md.

Usage (from the repository root):
    python3 dev/tools/datagen/datagen.py                # the build in BUILD
    python3 dev/tools/datagen/datagen.py --build 1.60.1.71139 --refresh
    python3 dev/tools/datagen/datagen.py harvest [SavedVariables/MapScout.lua]
        brings in what /ms harvest recorded in the game (see harvest.py)
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dungeons  # noqa: E402
import harvest  # noqa: E402
import places  # noqa: E402
import services  # noqa: E402
import trainers  # noqa: E402
import transport  # noqa: E402
from geo import Maps  # noqa: E402
from wago import Tables, build_date  # noqa: E402

PRODUCT = "wowf"  # WoW Forever on wago.tools
BUILD = "1.60.1.71139"  # the build the packs are made from (game version 1.60.1)
LOCALES = ["enUS", "esES", "esMX"]  # MapScout's languages (Locales/)
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "MapScout_Data_Forever")
CACHE = os.path.join(HERE, ".cache")
MANUAL = os.path.join(HERE, "manual")
HARVEST = os.path.join(HERE, "harvest")


def import_harvest(path):
    path = path or harvest.find_saved()
    if not path or not os.path.exists(path):
        sys.exit("Where is MapScout.lua? Pass the path of SavedVariables/MapScout.lua")
    with open(path, encoding="utf-8") as source:
        counts = harvest.merge(HARVEST, harvest.rows_from_saved(source.read()))
    for name, (added, updated) in counts.items():
        print("harvest/%s.csv: %d new, %d updated" % (name, added, updated))
    print("Now run the generator again.")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["harvest"]:
        return import_harvest(argv[1] if len(argv) > 1 else None)
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--build", default=BUILD, help="full Forever version, e.g. 1.60.1.71139")
    parser.add_argument("--refresh", action="store_true", help="download the tables again")
    parser.add_argument("--pending", action="store_true",
                        help="also use manual/*.pending.csv (local tests only: never commit that output)")
    args = parser.parse_args(argv)

    tables = Tables(args.build, CACHE, refresh=args.refresh)
    date = build_date(PRODUCT, args.build)
    if date is None:
        sys.exit("Build %s is not a %s build on wago.tools" % (args.build, PRODUCT))
    maps = Maps(tables.rows("UiMap"), tables.rows("UiMapAssignment"))
    os.makedirs(OUT, exist_ok=True)

    level_by_name = dungeons.levels(tables.rows("LFGDungeons"), tables.rows("ContentTuning"))
    instances = tables.rows("Map")
    files = [os.path.join(MANUAL, "entrances.csv")]
    if args.pending:
        files.append(os.path.join(MANUAL, "entrances.pending.csv"))
    manual = dungeons.manual([f for f in files if os.path.exists(f)])
    harvested = harvest.entrances(HARVEST)  # measured in the game: they win, and count as checked
    manual = sorted({(row[0], row[5]): row for row in manual + harvested}.values())
    found = dungeons.merge(dungeons.entrances(maps, instances, level_by_name), instances, level_by_name, manual)
    checked = dungeons.verified(os.path.join(MANUAL, "verified.csv")) | {(row[0], row[5]) for row in harvested}
    if not args.pending:  # local tests with --pending keep every point
        found = dungeons.checked_only(found, instances, level_by_name, checked)
    doors = dungeons.doors(manual, checked if not args.pending else {(row[0], row[5]) for row in manual})
    names = dungeons.names({locale: tables.rows("Map", locale) for locale in LOCALES}, [e[0] for e in found])
    dungeons.write(os.path.join(OUT, "Dungeons.lua"), args.build, date, found, names, manual, doors)
    pois = tables.rows("AreaPOI")
    found_places = places.places(maps, pois)
    place_names = places.names({locale: tables.rows("AreaPOI", locale) for locale in LOCALES}, [p[0] for p in found_places])
    places.write(os.path.join(OUT, "Places.lua"), args.build, date, found_places, place_names)
    print("Places.lua: %d towns, %d named places" % (
        sum(1 for p in found_places if p[1] == "town"), sum(1 for p in found_places if p[1] == "place")))

    listed = transport.lines(os.path.join(MANUAL, "transport.csv"))
    stops, heights = transport.path_stops(tables.rows("TaxiPathNode"))
    for problem in transport.check(listed, stops, heights):
        print("transport: " + problem)
    found_docks = transport.docks(maps, listed, stops, tables.rows("AreaTrigger"), pois)
    dock_names = transport.names({locale: tables.rows("AreaPOI", locale) for locale in LOCALES},
                                 [d[5] for d in found_docks])
    transport.write(os.path.join(OUT, "Transport.lua"), args.build, date, found_docks, dock_names)
    print("Transport.lua: %d docks of %d lines" % (
        len(found_docks), sum(1 for e in listed if e["kind"] in transport.KINDS)))

    found_services, unknown = services.points(HARVEST)
    for asked in unknown:
        print("services: unknown guard answer %r (add its words to services.py)" % asked)
    found_services = services.with_manual(found_services, services.manual(os.path.join(MANUAL, "services.csv")))
    count = services.write(os.path.join(OUT, "Services.lua"), args.build, date, services.merge(found_services))
    print("Services.lua: %d places" % count)

    found_trainers, unknown = trainers.points(HARVEST)
    for asked in unknown:
        print("trainers: unknown guard answer %r (add its words to trainers.py)" % asked)
    count = trainers.write(os.path.join(OUT, "Trainers.lua"), args.build, date, trainers.merge(found_trainers))
    print("Trainers.lua: %d trainers" % count)

    placed = sum(1 for e in found if e[2])
    print("Dungeons.lua: %d instances, %d with a checked entrance, %d by hand (build %s, %s)%s" % (
        len(found), placed, len(manual), args.build, date, "  WITH PENDING ROWS: do not commit" if args.pending else ""))


if __name__ == "__main__":
    main()
