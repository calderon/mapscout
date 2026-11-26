"""Towns and named places of the world map (subzones without a map of their own).

AreaPOI holds the names the world map writes on itself, with their world
position: towns and camps (Flags bit 1, e.g. Goldshire, Brill, Crossroads) and
named places (Flags 4: Whelgar's Excavation Site, Drywhisker Gorge...). The
position is where the game writes the name, so it is the game's own.
Left out: capitals (Flags 29: they are maps of their own), PvP objectives
(Flags bit 128), event notices and labels of other kinds.
"""

import lua
from geo import to_int

TOWN, LANDMARK = 5, 4  # Flags values kept
OUTDOOR = (0, 1)  # Eastern Kingdoms, Kalimdor


def places(maps, rows):
    """[(poiID, kind, uiMapID, x, y)] sorted by ID. A name repeated on the same
    map is kept once (a town before a place, then the lowest ID)."""
    out, seen = [], set()
    rows = sorted(rows, key=lambda r: (int(r["Flags"]) & 1 == 0, int(r["ID"])))
    for row in rows:
        flags, continent = int(row["Flags"]), int(row["ContinentID"])
        if continent not in OUTDOOR or flags not in (TOWN, LANDMARK, 1):
            continue
        if int(row["PlayerConditionID"] or 0) or int(row["WorldStateID"] or 0):
            continue  # shown only to some players or at some times
        place = maps.place(continent, float(row["Pos_0"]), float(row["Pos_1"]))
        if not place:
            continue
        ui_map, x, y = place
        key = (row["Name_lang"], ui_map)
        if key in seen:
            continue
        seen.add(key)
        kind = "town" if flags & 1 else "place"
        out.append((int(row["ID"]), kind, ui_map, to_int(x), to_int(y)))
    out.sort()
    return out


def names(rows_by_locale, ids):
    wanted = set(ids)
    return {locale: {int(r["ID"]): r["Name_lang"] for r in rows if int(r["ID"]) in wanted and r["Name_lang"]}
            for locale, rows in rows_by_locale.items()}


def write(path, version, date, found, names_by_locale):
    lines = [lua.header("towns and named places", version, date, [
        "the client's AreaPOI (the names the world map writes), UiMapAssignment and UiMap tables, through wago.tools",
    ])]
    lines.append("local _, pack = ...\n")
    lines.append("-- Built only when MapScout asks for it (see Pack.lua)")
    lines.append("pack.categories.places = function()")
    lines.append("\treturn {")
    lines.append("\t\tbuild = %s," % lua.string(version))
    lines.append("\t\t-- [AreaPOI ID] = { kind, uiMapID, x, y }: kind \"town\" or \"place\"; x, y 0-10000 on the map")
    lines.append("\t\tplaces = {")
    for poi, kind, ui_map, x, y in found:
        lines.append("\t\t\t[%d] = %s," % (poi, lua.row([kind, ui_map, x, y])))
    lines.append("\t\t},")
    lines.append("\t\t-- Names in MapScout's languages; any other uses enUS")
    lines.append("\t\tnames = {")
    for locale in sorted(names_by_locale):
        lines.append("\t\t\t%s = {" % locale)
        for poi in sorted(names_by_locale[locale]):
            lines.append("\t\t\t\t[%d] = %s," % (poi, lua.string(names_by_locale[locale][poi])))
        lines.append("\t\t\t},")
    lines.append("\t\t},")
    lines.append("\t}")
    lines.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines) + "\n")
