"""Dungeon and raid entrances.

Map (the instances) keeps, for each dungeon and raid, where a dead player's
corpse is moved to: the outside entrance (Corpse_0/1 on the CorpseMapID
continent). The recommended level comes from LFGDungeons -> ContentTuning
(MinLevelSquish); LFGDungeons.MapID is empty in this client, so its rows are
matched by name (NAMES lists the names that differ).

Instances without a corpse point (Forever's own ones, and a few like
Naxxramas) come from manual/entrances.csv (written by hand, with the public
sources of each point), and from the harvest mode.

An instance with several doors (the wings of Scarlet Monastery, Stratholme's
two gates, Dire Maul's three wings: one instance map each in this client) has
one row per door in manual/entrances.csv, with its wing (WINGS). Those doors
replace the instance's single entrance: MapScout shows one result per door.
"""

import csv

import lua
from geo import to_int

# Map.InstanceType
DUNGEON, RAID = 1, 2
KINDS = {DUNGEON: "dungeon", RAID: "raid"}

# The wings or gates an instance's doors can have, in the order they are
# written; MapScout names each one (Locales: DUNGEONS_WING_<WING>)
WINGS = ("library", "armory", "cathedral", "graveyard", "main", "service", "east", "west", "north")

# Map name -> LFGDungeons name, where they differ (wings share the level)
NAMES = {
    "Stormwind Stockade": "Stormwind Stockades",
    "Zul'Farrak": "Zul'Farak",
    "Onyxia's Lair": "Onyxia",
    "Blackrock Spire": "Lower Blackrock Spire",
    "Dire Maul": "Dire Maul - East",
    "The Hall of Thanes": "Hall of Thanes",
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


def manual(paths):
    """Rows of the hand-written files: [(instance, uiMap, x, y, sources, wing)],
    x and y 0..1, wing "" for an instance's only entrance. A later file wins
    over an earlier one for the same instance and wing."""
    rows = {}
    for path in paths:
        with open(path, newline="", encoding="utf-8") as source:
            lines = [line for line in source if line.strip() and not line.lstrip().startswith("#")]
        for row in csv.DictReader(lines):
            instance = int(row["instance"])
            wing = (row.get("wing") or "").strip()
            x, y = float(row["x"]), float(row["y"])
            if not (0 <= x <= 100 and 0 <= y <= 100):
                raise ValueError("%s: instance %d is off the map (%s, %s)" % (path, instance, x, y))
            if not (row["sources"] or "").strip():
                raise ValueError("%s: instance %d has no sources" % (path, instance))
            if wing and wing not in WINGS:
                raise ValueError("%s: instance %d has an unknown wing %r (see WINGS)" % (path, instance, wing))
            rows[(instance, wing)] = (instance, int(row["uiMap"]), x / 100, y / 100, row["sources"].strip(), wing)
    return [rows[k] for k in sorted(rows)]


def merge(found, instance_rows, level_by_name, manual_rows):
    """The client entrances plus the manual ones (a manual row wins). An
    instance with doors keeps no single place: see doors()."""
    by_id = {e[0]: e for e in found}
    rows = {int(r["ID"]): r for r in instance_rows}
    with_doors = {m[0] for m in manual_rows if m[5]}
    for instance, ui_map, x, y, _, wing in manual_rows:
        row = rows.get(instance)
        kind = row and KINDS.get(int(row["InstanceType"]))
        if not kind:
            raise ValueError("manual entrance for %d: not a dungeon or raid in this build" % instance)
        name = row["MapName_lang"]
        level = level_by_name.get(NAMES.get(name, name), 0)
        if instance in with_doors:  # its doors replace the single entrance
            by_id[instance] = (instance, kind, 0, 0, 0, level)
        else:
            by_id[instance] = (instance, kind, ui_map, to_int(x), to_int(y), level)
    return [by_id[k] for k in sorted(by_id)]


def doors(manual_rows, checked):
    """{instance: [(wing, uiMap, x, y)]}: the checked doors of the instances
    with several, x and y 0-10000, in WINGS order."""
    out = {}
    for instance, ui_map, x, y, _, wing in manual_rows:
        if wing and (instance, wing) in checked:
            out.setdefault(instance, []).append((wing, ui_map, to_int(x), to_int(y)))
    for found in out.values():
        found.sort(key=lambda door: WINGS.index(door[0]))
    return out


def verified(path):
    """(instance, wing) of the entrances checked in the game (manual/verified.csv);
    wing "" for an instance's only entrance."""
    with open(path, newline="", encoding="utf-8") as source:
        lines = [line for line in source if line.strip() and not line.lstrip().startswith("#")]
    return {(int(row["instance"]), (row.get("wing") or "").strip()) for row in csv.DictReader(lines)}


def known(instance_rows, level_by_name):
    """The dungeons and raids players can run in this build: those the
    group finder lists (LFGDungeons, matched by name). {instance: (kind, level)}"""
    out = {}
    for row in instance_rows:
        kind = KINDS.get(int(row["InstanceType"]))
        name = row["MapName_lang"]
        level = level_by_name.get(NAMES.get(name, name))
        if kind and level:
            out[int(row["ID"])] = (kind, level)
    return out


def checked_only(found, instance_rows, level_by_name, checked):
    """Checked entrances keep their place; every other one (and every known
    instance without an entrance) stays, with no place: uiMapID 0."""
    out = {}
    for instance, kind, ui_map, x, y, level in found:
        out[instance] = (instance, kind, ui_map, x, y, level) if (instance, "") in checked else (instance, kind, 0, 0, 0, level)
    for instance, (kind, level) in known(instance_rows, level_by_name).items():
        out.setdefault(instance, (instance, kind, 0, 0, 0, level))
    return [out[k] for k in sorted(out)]


def names(rows_by_locale, ids):
    """{locale: {instanceMapID: name}} for the instances kept."""
    wanted = set(ids)
    out = {}
    for locale, rows in rows_by_locale.items():
        out[locale] = {int(r["ID"]): r["MapName_lang"] for r in rows if int(r["ID"]) in wanted and r["MapName_lang"]}
    return out


def write(path, version, date, found, names_by_locale, manual_rows=(), doors_by_instance=None):
    lines = [lua.header("dungeon and raid entrances", version, date, [
        "the client's Map (Corpse_0/1, CorpseMapID), UiMapAssignment, UiMap, LFGDungeons and ContentTuning tables, through wago.tools",
    ] + ["instance %d%s: %s" % (row[0], " (%s)" % row[5] if row[5] else "", row[4]) for row in manual_rows])]
    lines.append("local _, pack = ...\n")
    lines.append("-- Built only when MapScout asks for it (see Pack.lua)")
    lines.append("pack.categories.dungeons = function()")
    lines.append("\treturn {")
    lines.append('\t\tbuild = %s,' % lua.string(version))
    lines.append("\t\t-- [instance mapID] = { kind, uiMapID, x, y, level }: x, y 0-10000 on the map; level 0 = unknown;\n"
                 "\t\t-- uiMapID 0 = entrance not confirmed yet (found by name, with no place)")
    lines.append("\t\tentrances = {")
    for instance, kind, ui_map, x, y, level in found:
        lines.append("\t\t\t[%d] = %s," % (instance, lua.row([kind, ui_map, x, y, level])))
    lines.append("\t\t},")
    lines.append("\t\t-- Instances with several doors: [instance mapID] = { { wing, uiMapID, x, y }, ... },\n"
                 "\t\t-- one result each (they replace the entrance above)")
    lines.append("\t\tdoors = {")
    for instance in sorted(doors_by_instance or {}):
        lines.append("\t\t\t[%d] = {" % instance)
        for door in doors_by_instance[instance]:
            lines.append("\t\t\t\t%s," % lua.row(list(door)))
        lines.append("\t\t\t},")
    lines.append("\t\t},")
    lines.append("\t\t-- Names in MapScout's languages; any other uses enUS")
    lines.append("\t\tnames = {")
    for locale in sorted(names_by_locale):
        lines.append("\t\t\t%s = {" % locale)
        for instance in sorted(names_by_locale[locale]):
            lines.append("\t\t\t\t[%d] = %s," % (instance, lua.string(names_by_locale[locale][instance])))
        lines.append("\t\t\t},")
    lines.append("\t\t},")
    lines.append("\t}")
    lines.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines) + "\n")
