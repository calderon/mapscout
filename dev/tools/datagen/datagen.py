"""MapScout static data generator for WoW Forever.

Reads the client data tables (DB2) of one exact Forever build and writes the
Lua files of the MapScout_Data_Forever pack. See README.md.

Usage (from the repository root):
    python3 dev/tools/datagen/datagen.py                # the build in BUILD
    python3 dev/tools/datagen/datagen.py --build 1.60.1.71139 --refresh
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dungeons  # noqa: E402
from geo import Maps  # noqa: E402
from wago import Tables, build_date  # noqa: E402

PRODUCT = "wowf"  # WoW Forever on wago.tools
BUILD = "1.60.1.71139"  # the build the packs are made from (game version 1.60.1)
LOCALES = ["enUS", "esES", "esMX"]  # MapScout's languages (Locales/)
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "MapScout_Data_Forever")
CACHE = os.path.join(HERE, ".cache")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--build", default=BUILD, help="full Forever version, e.g. 1.60.1.71139")
    parser.add_argument("--refresh", action="store_true", help="download the tables again")
    args = parser.parse_args(argv)

    tables = Tables(args.build, CACHE, refresh=args.refresh)
    date = build_date(PRODUCT, args.build)
    if date is None:
        sys.exit("Build %s is not a %s build on wago.tools" % (args.build, PRODUCT))
    maps = Maps(tables.rows("UiMap"), tables.rows("UiMapAssignment"))
    os.makedirs(OUT, exist_ok=True)

    level_by_name = dungeons.levels(tables.rows("LFGDungeons"), tables.rows("ContentTuning"))
    found = dungeons.entrances(maps, tables.rows("Map"), level_by_name)
    names = dungeons.names({locale: tables.rows("Map", locale) for locale in LOCALES}, [e[0] for e in found])
    dungeons.write(os.path.join(OUT, "Dungeons.lua"), args.build, date, found, names)
    print("Dungeons.lua: %d entrances (build %s, %s)" % (len(found), args.build, date))


if __name__ == "__main__":
    main()
