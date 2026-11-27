"""Graveyards: the spirit healer of each graveyard.

The client has no graveyard table (WorldSafeLocs is not in Forever's DB2), and
the game's graveyard API answers nothing. They come from our harvest mode
(Debug/Harvest.lua), in harvest/graveyards.csv:

- how "death": on dying, the game says where the ghost will appear
  (C_DeathInfo.GetDeathReleasePosition): the graveyard itself, exactly.
- how "healer": a spirit healer talked to as a ghost, where the player stood
  (a few steps from it).

Records of one graveyard are joined: on the same map and within NEAR of each
other. A graveyard's point is the average of its "death" records (exact), or of
its "healer" ones when it has no other.
"""

import math

import harvest
import lua
from geo import to_int

NEAR = 0.02  # map units: records closer than this are one graveyard


def points(folder):
    """[(uiMap, x, y, records)], one per graveyard, sorted."""
    groups = []  # [(uiMap, [rows])]
    rows = sorted(harvest.read(folder, "graveyards").values(), key=lambda r: (r["how"] != "death", r["key"]))
    for row in rows:
        ui_map, x, y = int(row["uiMap"]), float(row["x"]), float(row["y"])
        for group_map, members in groups:
            if group_map == ui_map and any(math.hypot(x - float(m["x"]), y - float(m["y"])) < NEAR for m in members):
                members.append(row)
                break
        else:
            groups.append((ui_map, [row]))
    out = []
    for ui_map, members in groups:
        best = [m for m in members if m["how"] == "death"] or members
        x = round(sum(float(m["x"]) for m in best) / len(best), 4)
        y = round(sum(float(m["y"]) for m in best) / len(best), 4)
        out.append((ui_map, x, y, len(members)))
    return sorted(out)


def write(path, version, date, found):
    """Writes SpiritHealers.lua; returns how many graveyards."""
    rows = {}
    for ui_map, x, y, _ in found:
        rows.setdefault(ui_map, []).append([to_int(x), to_int(y)])
    out = [lua.header("spirit healers", version, date, [
        "harvest/graveyards.csv (where the game sends the ghost on dying, and spirit healers talked to): "
        "recorded in the game with the harvest mode",
    ])]
    out.append("local _, pack = ...\n")
    out.append("-- Built only when MapScout asks for it (see Pack.lua)")
    out.append("pack.categories.spirithealers = function()")
    out.append("\treturn {")
    out.append("\t\tbuild = %s," % lua.string(version))
    out.append("\t\t-- [uiMapID] = { { x, y }, ... }: one spirit healer per graveyard, x, y 0-10000 on the map")
    out.append("\t\tmaps = {")
    for ui_map in sorted(rows):
        out.append("\t\t\t[%d] = {" % ui_map)
        for row in sorted(rows[ui_map]):
            out.append("\t\t\t\t%s," % lua.row(row))
        out.append("\t\t\t},")
    out.append("\t\t},")
    out.append("\t}")
    out.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as target:
        target.write("\n".join(out) + "\n")
    return sum(len(r) for r in rows.values())
