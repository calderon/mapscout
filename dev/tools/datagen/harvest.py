"""Brings what the harvest mode recorded in the game (Debug/Harvest.lua, saved
in MapScout's SavedVariables) into the repository, as CSV files in harvest/:
our own data, measured in the game. Run it after playing with /ms harvest on:

    python3 dev/tools/datagen/datagen.py harvest [path/to/SavedVariables/MapScout.lua]

New records are added to what is already there; a newer record of the same
NPC or object replaces the old one. Every entry into a dungeon is a record of
its own (where the player walks into the portal changes the point a little):
the generator uses their average. For an instance with several doors (Dire
Maul's wings), write each record's wing by hand in harvest/entrances.csv
(WINGS in dungeons.py); importing again keeps it. Then run the generator again.
"""

import csv
import glob
import os
from collections import defaultdict

import savedvars

# Columns written by hand after importing: a new import keeps them
KEEP = {"entrances": ["wing"]}

FOREVER_SAVED = "/Applications/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/MapScout.lua"

FILES = {
    "entrances": ["key", "instance", "name", "kind", "uiMap", "x", "y", "at", "wing"],
    "npcs": ["npc", "locale", "name", "faction", "title", "services", "skill", "uiMap", "x", "y", "gossip", "at",
             "seen"],
    "objects": ["key", "service", "object", "uiMap", "x", "y", "at"],
    "directions": ["key", "locale", "asked", "name", "poi", "texture", "guard", "uiMap", "x", "y", "at"],
    "graveyards": ["key", "how", "npc", "uiMap", "x", "y", "continent", "cx", "cy", "died", "at"],
}


def find_saved():
    found = sorted(glob.glob(FOREVER_SAVED))
    return found[0] if len(found) == 1 else None


def rows_from_saved(text):
    """{file: {key: row}} from the SavedVariables text."""
    data = (savedvars.load(text).get("MapScoutDB") or {}).get("harvest") or {}
    out = {name: {} for name in FILES}
    for key, e in (data.get("entrances") or {}).items():  # "instance:time" (older ones: the instance)
        out["entrances"][str(key)] = {
            "key": str(key), "instance": e.get("instance") or key, "name": e.get("name", ""), "kind": e.get("kind", ""),
            "uiMap": e["map"], "x": e["x"], "y": e["y"], "at": e.get("at", 0), "wing": ""}
    for npc, n in (data.get("npcs") or {}).items():
        services = sorted(k for k, v in (n.get("services") or {}).items() if v)
        gossip = n.get("gossip") or []
        if isinstance(gossip, dict):
            gossip = [gossip[k] for k in sorted(gossip)]
        seen = n.get("seen") or []
        if isinstance(seen, dict):
            seen = [seen[k] for k in sorted(seen)]
        out["npcs"][str(npc)] = {
            "npc": npc, "locale": n.get("locale") or "esES", "name": n.get("name", ""), "faction": n.get("faction", ""),
            "title": n.get("title", ""), "services": " ".join(services), "skill": n.get("skill", ""), "uiMap": n["map"], "x": n["x"], "y": n["y"],
            "gossip": " | ".join(gossip), "at": n.get("at", 0),
            "seen": spots_text([_spot(s) for s in seen if _spot(s)])}
    for key, o in (data.get("objects") or {}).items():
        out["objects"][key] = {
            "key": key, "service": o.get("service", ""), "object": o.get("objectID") or "",
            "uiMap": o["map"], "x": o["x"], "y": o["y"], "at": o.get("at", 0)}
    for key, d in (data.get("directions") or {}).items():
        out["directions"][key] = {
            "key": key, "locale": d.get("locale") or "esES", "asked": d.get("asked", ""), "name": d.get("name", ""), "poi": d.get("poi") or "", "texture": d.get("texture", ""),
            "guard": d.get("guard") or "", "uiMap": d["map"], "x": d["x"], "y": d["y"], "at": d.get("at", 0)}
    for key, g in (data.get("graveyards") or {}).items():  # "death:time" or "healer:time"
        out["graveyards"][key] = {
            "key": key, "how": g.get("how", ""), "npc": g.get("npc") or "", "uiMap": g["map"], "x": g["x"], "y": g["y"],
            "continent": g.get("continent") or "", "cx": g.get("cx", ""), "cy": g.get("cy", ""),
            "died": g.get("died") or "", "at": g.get("at", 0)}
    return out


def _spot(value):
    """(uiMap, x, y) of a saved place ({ map, x, y }, read as a list or a dict)."""
    if isinstance(value, dict):
        value = [value[k] for k in sorted(value)]
    if not isinstance(value, (list, tuple)) or len(value) < 3:
        return None
    return int(value[0]), float(value[1]), float(value[2])


def spots(text):
    """[(uiMap, x, y)] of a "seen" cell ("1455:0.2756:0.7192 1455:0.3:0.6")."""
    out = []
    for part in (text or "").split():
        ui_map, x, y = part.split(":")
        out.append((int(ui_map), float(x), float(y)))
    return out


def spots_text(found):
    """A "seen" cell: each place once, in order."""
    out = []
    for spot in found:
        if spot not in out:
            out.append(spot)
    return " ".join("%d:%s:%s" % (m, _num(x), _num(y)) for m, x, y in out)


def _num(value):
    return ("%.4f" % value).rstrip("0").rstrip(".")


def _npc_seen(old, row):
    """Where an NPC was seen, from both imports: the old row's places and
    position, then the new one's (a position alone counts as a place)."""
    found = []
    for r in (old, row):
        if not r:
            continue
        found += spots(r.get("seen"))
        if r.get("uiMap") not in (None, "") and r.get("x") not in (None, ""):
            found.append((int(r["uiMap"]), float(r["x"]), float(r["y"])))
    return spots_text(found)


def read(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        return {}
    with open(path, newline="", encoding="utf-8") as source:
        return {row[FILES[name][0]]: row for row in csv.DictReader(source)}


def merge(folder, new):
    """Adds the new rows to the CSV files; returns {file: (added, updated)}."""
    os.makedirs(folder, exist_ok=True)
    counts = {}
    for name, columns in FILES.items():
        rows = read(folder, name)
        added = updated = 0
        for key, row in new[name].items():
            old = rows.get(key)
            if name == "npcs":
                seen = _npc_seen(old, row)
                if old is not None and int(float(old.get("at") or 0)) > int(row["at"] or 0):
                    old["seen"] = seen  # what is there is newer, but the places add up
                    continue
                row = dict(row, seen=seen)
            if old is None:
                added += 1
            elif int(float(old.get("at") or 0)) > int(row["at"] or 0):
                continue  # what is there is newer
            else:
                updated += 1
                row = dict(row)
                for column in KEEP.get(name, ()):
                    row[column] = row.get(column) or old.get(column, "")
            rows[key] = row
        with open(os.path.join(folder, name + ".csv"), "w", newline="", encoding="utf-8") as out:
            writer = csv.DictWriter(out, fieldnames=columns, lineterminator="\n")
            writer.writeheader()
            for key in sorted(rows, key=lambda k: (len(str(k)), str(k))):
                writer.writerow({c: rows[key].get(c, "") for c in columns})
        counts[name] = (added, updated)
    return counts


def entrances(folder):
    """Harvested entrances as manual rows: [(instance, uiMap, x, y, source, wing)],
    one per instance and wing: the average of its entries (on the map of the
    latest one)."""
    groups = defaultdict(list)
    for row in read(folder, "entrances").values():
        groups[(int(row["instance"]), (row.get("wing") or "").strip())].append(row)
    out = []
    for (instance, wing), rows in groups.items():
        latest = max(rows, key=lambda r: int(float(r.get("at") or 0)))
        same = [r for r in rows if r["uiMap"] == latest["uiMap"]]
        x = round(sum(float(r["x"]) for r in same) / len(same), 4)
        y = round(sum(float(r["y"]) for r in same) / len(same), 4)
        source = "harvest (in game)" if len(same) == 1 else "harvest (in game, average of %d entries)" % len(same)
        out.append((instance, int(latest["uiMap"]), x, y, source, wing))
    return sorted(out, key=lambda r: (r[0], r[5]))
