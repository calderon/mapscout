"""Dungeon and raid entrances.

Map (the instances) keeps, for each dungeon and raid, where a dead player's
corpse is moved to: the outside entrance (Corpse_0/1 on the CorpseMapID
continent). The recommended level comes from LFGDungeons -> ContentTuning
(MinLevelSquish); LFGDungeons.MapID is empty in this client, so its rows are
matched by name (NAMES lists the names that differ).

Instances without a corpse point (Forever's own ones, and a few like
Naxxramas) are left out: their entrances will come from the harvest mode (#40).
"""

import lua
from geo import to_int

# Map.InstanceType
DUNGEON, RAID = 1, 2
KINDS = {DUNGEON: "dungeon", RAID: "raid"}

# Map name -> LFGDungeons name, where they differ (wings share the level)
NAMES = {
    "Stormwind Stockade": "Stormwind Stockades",
    "Zul'Farrak": "Zul'Farak",
    "Onyxia's Lair": "Onyxia",
    "Blackrock Spire": "Lower Blackrock Spire",
    "Dire Maul": "Dire Maul - East",
}


def levels(lfg_dungeons, content_tuning):
    tuning = {row["ID"]: row for row in content_tuning}
    found = {}
    for row in lfg_dungeons:
        level = int(tuning.get(row["ContentTuningID"], {}).get("MinLevelSquish") or 0)
        if level > 0:
            found[row["Name_lang"]] = level
    return found


def entrances(maps, instance_rows, level_by_name):
    """[(instanceMapID, kind, uiMapID, x, y, level)] sorted by instance."""
    out = []
    for row in instance_rows:
        kind = KINDS.get(int(row["InstanceType"]))
        name = row["MapName_lang"]
        continent = int(row["CorpseMapID"])
        world_x, world_y = float(row["Corpse_0"]), float(row["Corpse_1"])
        if not kind or name.startswith("<") or continent < 0 or (world_x == 0 and world_y == 0):
            continue
        place = maps.place(continent, world_x, world_y)
        if not place:
            continue
        ui_map, x, y = place
        level = level_by_name.get(NAMES.get(name, name), 0)
        out.append((int(row["ID"]), kind, ui_map, to_int(x), to_int(y), level))
    out.sort()
    return out


def names(rows_by_locale, ids):
    """{locale: {instanceMapID: name}} for the instances kept."""
    wanted = set(ids)
    out = {}
    for locale, rows in rows_by_locale.items():
        out[locale] = {int(r["ID"]): r["MapName_lang"] for r in rows if int(r["ID"]) in wanted and r["MapName_lang"]}
    return out


def write(path, version, date, found, names_by_locale):
    lines = [lua.header("dungeon and raid entrances", version, date, [
        "the client's Map (Corpse_0/1, CorpseMapID), UiMapAssignment, UiMap, LFGDungeons and ContentTuning tables, through wago.tools",
    ])]
    lines.append("local _, pack = ...\n")
    lines.append("pack.dungeons = {")
    lines.append('\tbuild = %s,' % lua.string(version))
    lines.append("\t-- [instance mapID] = { kind, uiMapID, x, y, level }: x, y 0-10000 on the map; level 0 = unknown")
    lines.append("\tentrances = {")
    for instance, kind, ui_map, x, y, level in found:
        lines.append("\t\t[%d] = %s," % (instance, lua.row([kind, ui_map, x, y, level])))
    lines.append("\t},")
    lines.append("\t-- Names in MapScout's languages; any other uses enUS")
    lines.append("\tnames = {")
    for locale in sorted(names_by_locale):
        lines.append("\t\t%s = {" % locale)
        for instance in sorted(names_by_locale[locale]):
            lines.append("\t\t\t[%d] = %s," % (instance, lua.string(names_by_locale[locale][instance])))
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines) + "\n")
