"""Boats, zeppelins, skyships and trams: their docks and where they go.

The client knows the route of each boat and zeppelin: TaxiPath holds one path
per line and TaxiPathNode its points in the world, in order; the points where
it waits (Flags bit 2, with a Delay) are its stops, the docks. The client does
not say which kind of transport runs on a path (that is the server's), nor
which paths players really ride, so manual/transport.csv lists the lines, one
row each, with its kind ("none": a path left out on purpose). A path with stops that is not in that file is
reported, so a new build's new lines are not missed.

The Deeprun Tram is an instance of its own: its two entrances are the area
triggers that send players into it (AreaTrigger), also listed in that file.

Each stop is named after the town or capital next to it (AreaPOI, the names
the world map writes, in every language); a stop with none is named in the
game after its map. Stops of the same kind at the same place (two lines from
one pier) become one dock with every destination.
"""

import csv
import math

import lua
from geo import to_int

KINDS = ("boat", "zeppelin", "skyship", "tram")
STOP = 2  # TaxiPathNode.Flags: the transport waits here
SAME_DOCK = 30  # yards: closer stops of one kind are the same dock
NEAR_TOWN = 600  # yards: farther, a stop is not named after a town
TOWN, CAPITAL = 5, 29  # AreaPOI.Flags (see places.py)
FLYING = ("zeppelin", "skyship")
HIGH = 40  # yards over the sea: a flying route's middle is higher


def lines(path):
    """[{line, kind, path, triggers}] from manual/transport.csv."""
    out = []
    with open(path, newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            kind = row["kind"].strip()
            if kind not in KINDS + ("none",):
                raise ValueError("%s: line %s: unknown kind %r" % (path, row["line"], kind))
            out.append({
                "line": int(row["line"]),
                "kind": kind,
                "path": int(row["path"] or 0),
                "triggers": [int(t) for t in row["triggers"].split()],
            })
    return out


def path_stops(path_nodes):
    """{pathID: [(continent, x, y, z)]} of the stops of every path, in order,
    and {pathID: median height of the whole path}."""
    by_path = {}
    for row in path_nodes:
        by_path.setdefault(int(row["PathID"]), []).append(row)
    stops, heights = {}, {}
    for path, rows in by_path.items():
        rows.sort(key=lambda r: int(r["NodeIndex"]))
        found = [(int(r["ContinentID"]), float(r["Loc_0"]), float(r["Loc_1"]), float(r["Loc_2"]))
                 for r in rows if int(r["Flags"]) & STOP]
        if found:
            stops[path] = found
            z = sorted(float(r["Loc_2"]) for r in rows)
            heights[path] = z[len(z) // 2]
    return stops, heights


def check(listed, stops, heights):
    """Problems with the list: missing paths, kinds that do not fit the height,
    and paths with stops the list does not have."""
    problems = []
    used = set()
    for entry in listed:
        if entry["path"]:
            used.add(entry["path"])
            if entry["path"] not in stops:
                problems.append("line %d: path %d has no stops" % (entry["line"], entry["path"]))
                continue
            if entry["kind"] == "none":
                continue
            flying = heights[entry["path"]] > HIGH
            if flying != (entry["kind"] in FLYING):
                problems.append("line %d: a %s, but its path is %s" % (
                    entry["line"], entry["kind"], "high in the air" if flying else "at sea level"))
    for path in sorted(set(stops) - used):
        problems.append("path %d has stops and is not in manual/transport.csv (a new line? or add it as 'none')" % path)
    return problems


def town(pois, continent, x, y):
    """AreaPOI ID of the capital near the point, else of the nearest town; 0."""
    best = {}
    for row in pois:
        flags = int(row["Flags"])
        if int(row["ContinentID"]) != continent or flags not in (TOWN, CAPITAL):
            continue
        if int(row["PlayerConditionID"] or 0) or int(row["WorldStateID"] or 0):
            continue
        distance = math.hypot(float(row["Pos_0"]) - x, float(row["Pos_1"]) - y)
        if distance <= NEAR_TOWN and (flags not in best or distance < best[flags][0]):
            best[flags] = (distance, int(row["ID"]))
    for flags in (CAPITAL, TOWN):
        if flags in best:
            return best[flags][1]
    return 0


def docks(maps, listed, stops, triggers, pois):
    """[(dockID, kind, uiMapID, x, y, townPOI, [destination dockIDs])] sorted.

    A dock's ID is its first line's ID * 10 + the stop's number on it (1, 2...),
    so it stays the same while that line does."""
    trigger_at = {int(r["ID"]): (int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"])) for r in triggers}
    found = []  # {id, kind, continent, x, y, lines: set}
    for entry in sorted(listed, key=lambda e: e["line"]):
        if entry["kind"] not in KINDS:
            continue
        if entry["path"]:
            points = [(c, x, y) for c, x, y, _ in stops.get(entry["path"], [])]
        else:
            points = [trigger_at[t] for t in entry["triggers"]]
        for number, (continent, x, y) in enumerate(points, 1):
            dock = next((d for d in found if d["kind"] == entry["kind"] and d["continent"] == continent
                         and math.hypot(d["x"] - x, d["y"] - y) <= SAME_DOCK), None)
            if not dock:
                dock = {"id": entry["line"] * 10 + number, "kind": entry["kind"],
                        "continent": continent, "x": x, "y": y, "lines": []}
                found.append(dock)
            if entry["line"] not in dock["lines"]:
                dock["lines"].append(entry["line"])
    out = []
    for dock in found:
        place = maps.place(dock["continent"], dock["x"], dock["y"])
        if not place:
            raise ValueError("dock %d: no map holds it" % dock["id"])
        to = sorted({d["id"] for d in found if d is not dock and set(d["lines"]) & set(dock["lines"])})
        ui_map, x, y = place
        out.append((dock["id"], dock["kind"], ui_map, to_int(x), to_int(y),
                    town(pois, dock["continent"], dock["x"], dock["y"]), to))
    out.sort()
    return out


def names(rows_by_locale, ids):
    wanted = set(i for i in ids if i)
    return {locale: {int(r["ID"]): r["Name_lang"] for r in rows if int(r["ID"]) in wanted and r["Name_lang"]}
            for locale, rows in rows_by_locale.items()}


def write(path, version, date, found, names_by_locale):
    lines_out = [lua.header("boats, zeppelins, skyships and trams", version, date, [
        "the client's TaxiPath and TaxiPathNode (the stops of each route), AreaTrigger (the tram's entrances), "
        "AreaPOI (town names), UiMapAssignment and UiMap tables, through wago.tools",
        "manual/transport.csv (which routes players ride, and their kind)",
    ])]
    lines_out.append("local _, pack = ...\n")
    lines_out.append("-- Built only when MapScout asks for it (see Pack.lua)")
    lines_out.append("pack.categories.transport = function()")
    lines_out.append("\treturn {")
    lines_out.append("\t\tbuild = %s," % lua.string(version))
    lines_out.append("\t\t-- [dock] = { kind, uiMapID, x, y, town, destination docks... }: kind \"boat\", \"zeppelin\",")
    lines_out.append("\t\t-- \"skyship\" or \"tram\"; x, y 0-10000 on the map; town = AreaPOI ID of the town it is named")
    lines_out.append("\t\t-- after, 0 if none (the game names it after its map)")
    lines_out.append("\t\tdocks = {")
    for dock, kind, ui_map, x, y, town_id, to in found:
        lines_out.append("\t\t\t[%d] = %s," % (dock, lua.row([kind, ui_map, x, y, town_id] + to)))
    lines_out.append("\t\t},")
    lines_out.append("\t\t-- Town names in MapScout's languages; any other uses enUS")
    lines_out.append("\t\tnames = {")
    for locale in sorted(names_by_locale):
        lines_out.append("\t\t\t%s = {" % locale)
        for poi in sorted(names_by_locale[locale]):
            lines_out.append("\t\t\t\t[%d] = %s," % (poi, lua.string(names_by_locale[locale][poi])))
        lines_out.append("\t\t\t},")
    lines_out.append("\t\t},")
    lines_out.append("\t}")
    lines_out.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines_out) + "\n")
