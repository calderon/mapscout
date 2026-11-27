"""Brings what the harvest mode recorded in the game (Debug/Harvest.lua, saved
in MapScout's SavedVariables) into the repository, as CSV files in harvest/:
our own data, measured in the game. Run it after playing with /ms harvest on:

    python3 dev/tools/datagen/datagen.py harvest [path/to/SavedVariables/MapScout.lua]

New records are added to what is already there; a newer record of the same
NPC, object or entrance replaces the old one. Then run the generator again.
"""

import csv
import glob
import os

import savedvars

FOREVER_SAVED = "/Applications/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/MapScout.lua"

FILES = {
    "entrances": ["instance", "name", "kind", "uiMap", "x", "y", "at"],
    "npcs": ["npc", "locale", "name", "faction", "title", "services", "skill", "uiMap", "x", "y", "gossip", "at"],
    "objects": ["key", "service", "object", "uiMap", "x", "y", "at"],
    "directions": ["key", "locale", "asked", "name", "poi", "texture", "guard", "uiMap", "x", "y", "at"],
}


def find_saved():
    found = sorted(glob.glob(FOREVER_SAVED))
    return found[0] if len(found) == 1 else None


def rows_from_saved(text):
    """{file: {key: row}} from the SavedVariables text."""
    data = (savedvars.load(text).get("MapScoutDB") or {}).get("harvest") or {}
    out = {name: {} for name in FILES}
    for instance, e in (data.get("entrances") or {}).items():
        out["entrances"][str(instance)] = {
            "instance": instance, "name": e.get("name", ""), "kind": e.get("kind", ""),
            "uiMap": e["map"], "x": e["x"], "y": e["y"], "at": e.get("at", 0)}
    for npc, n in (data.get("npcs") or {}).items():
        services = sorted(k for k, v in (n.get("services") or {}).items() if v)
        gossip = n.get("gossip") or []
        if isinstance(gossip, dict):
            gossip = [gossip[k] for k in sorted(gossip)]
        out["npcs"][str(npc)] = {
            "npc": npc, "locale": n.get("locale") or "esES", "name": n.get("name", ""), "faction": n.get("faction", ""),
            "title": n.get("title", ""), "services": " ".join(services), "skill": n.get("skill", ""), "uiMap": n["map"], "x": n["x"], "y": n["y"],
            "gossip": " | ".join(gossip), "at": n.get("at", 0)}
    for key, o in (data.get("objects") or {}).items():
        out["objects"][key] = {
            "key": key, "service": o.get("service", ""), "object": o.get("objectID") or "",
            "uiMap": o["map"], "x": o["x"], "y": o["y"], "at": o.get("at", 0)}
    for key, d in (data.get("directions") or {}).items():
        out["directions"][key] = {
            "key": key, "locale": d.get("locale") or "esES", "asked": d.get("asked", ""), "name": d.get("name", ""), "poi": d.get("poi") or "", "texture": d.get("texture", ""),
            "guard": d.get("guard") or "", "uiMap": d["map"], "x": d["x"], "y": d["y"], "at": d.get("at", 0)}
    return out


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
            if old is None:
                added += 1
            elif int(float(old.get("at") or 0)) > int(row["at"] or 0):
                continue  # what is there is newer
            else:
                updated += 1
            rows[key] = row
        with open(os.path.join(folder, name + ".csv"), "w", newline="", encoding="utf-8") as out:
            writer = csv.DictWriter(out, fieldnames=columns, lineterminator="\n")
            writer.writeheader()
            for key in sorted(rows, key=lambda k: (len(str(k)), str(k))):
                writer.writerow({c: rows[key].get(c, "") for c in columns})
        counts[name] = (added, updated)
    return counts


def entrances(folder):
    """Harvested entrances as manual rows: [(instance, uiMap, x, y, source, wing)]."""
    out = []
    for row in read(folder, "entrances").values():
        out.append((int(row["instance"]), int(row["uiMap"]), float(row["x"]), float(row["y"]), "harvest (in game)",
                    (row.get("wing") or "").strip()))
    return sorted(out)
