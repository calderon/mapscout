"""City services: banks, auction houses, inns, mailboxes, stable masters and
repair vendors.

The client data has none of them (the NPCs and mailboxes are the server's), so
they come from our harvest mode (Debug/Harvest.lua), measured in the game:

- directions.csv: what a city guard marks on the map when asked ("The bank"),
  with the guard's words for it. The guard's answer is the place (the bank's
  building), named as the game names it, in the language of the client that
  asked.
- npcs.csv: the NPCs a player talked to, with the services they offered.
- objects.csv: the mailboxes a player opened.

For one service on one map, the guard's places win: when a guard gave them,
the NPCs of that service on that map are left out (the bankers stand in the
bank the guard points to). Mailboxes add up: every one opened is a mailbox,
and the guard's one is too. Points of one service closer than SAME_PLACE are
one. A guard answer whose words are not known is reported, so a new language
or a new city's words are not missed.
"""

import csv
import os
import unicodedata

import lua
from geo import to_int

KINDS = ("bank", "auction", "inn", "mailbox", "stable", "repair")

# The guard's words for each service (the start of the option, lowercase,
# without accents), per language. Options for later categories are known and
# left out without a report.
GUARD_WORDS = {
    "bank": ("banco", "bank", "the bank"),
    "auction": ("casa de subastas", "auction house", "the auction house"),
    "inn": ("la posada", "posada", "the inn", "inn"),
    "mailbox": ("buzon", "mailbox", "the mailbox"),
    "stable": ("maestro de establos", "stable master", "the stable master"),
}
GUARD_LATER = (
    "instructor", "maestro de batalla", "maestro de grifos", "maestro de la hermandad", "tren subterraneo",
    "peluqueria", "trainer", "battlemaster", "gryphon master", "wind rider master", "flight master",
    "guild master", "deeprun tram", "barber", "zeppelin master", "bat handler", "hippogryph master",
)
NPC_SERVICES = {"bank": "bank", "auction": "auction", "innkeeper": "inn", "stable": "stable", "repair": "repair"}
FACTIONS = ("Alliance", "Horde")
ANYONE = ("mailbox",)  # any player can use them, whatever the guard's faction
SAME_PLACE = 0.003  # map units (0-1): closer points of one service are the same place
DEFAULT_LOCALE = "esES"  # the language of what was harvested before records said it


def plain(text):
    """Lowercase, without accents, single spaces."""
    text = unicodedata.normalize("NFD", text or "").encode("ascii", "ignore").decode()
    return " ".join(text.lower().split())


def guard_service(asked):
    """The service a guard answer is about ("Banco de Forjaz" -> "bank"), "" for
    an option of a later category, None if its words are not known."""
    first = plain(asked.split(">")[0])
    for kind, words in GUARD_WORDS.items():
        for word in words:
            if first == word or first.startswith(word + " "):
                return kind
    if any(first == w or first.startswith(w + " ") for w in GUARD_LATER):
        return ""
    return None


def _read(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as source:
        return list(csv.DictReader(source))


def _faction(value):
    return value if value in FACTIONS else ""


def points(folder):
    """[(uiMap, kind, x, y, faction, locale, name)] from the harvest CSV files,
    and the guard answers whose words are not known."""
    npcs = _read(folder, "npcs")
    faction_of = {row["npc"]: _faction(row["faction"]) for row in npcs}
    unknown = []
    from_guards, found = set(), []
    for row in _read(folder, "directions"):
        kinds = set()
        for asked in row["asked"].split("|"):
            asked = asked.strip()
            if not asked:
                continue
            kind = guard_service(asked)
            if kind is None:
                unknown.append(asked)
            elif kind:
                kinds.add(kind)
        for kind in sorted(kinds):
            ui_map = int(row["uiMap"])
            from_guards.add((ui_map, kind))
            faction = "" if kind in ANYONE else faction_of.get(row["guard"], "")
            found.append((ui_map, kind, float(row["x"]), float(row["y"]), faction,
                          row.get("locale") or DEFAULT_LOCALE, row["name"]))
    for row in npcs:
        ui_map = int(row["uiMap"])
        for service in row["services"].split():
            kind = NPC_SERVICES.get(service)
            if kind and (ui_map, kind) not in from_guards:
                found.append((ui_map, kind, float(row["x"]), float(row["y"]), _faction(row["faction"]),
                              row.get("locale") or DEFAULT_LOCALE, row["name"]))
    for row in _read(folder, "objects"):
        if row["service"] == "mailbox":
            found.append((int(row["uiMap"]), "mailbox", float(row["x"]), float(row["y"]), "", "", ""))
    return found, sorted(set(unknown))


def merge(found):
    """One point per place: points of one service on one map closer than
    SAME_PLACE are one (the first with a name keeps it). Sorted."""
    out = []
    for point in sorted(found, key=lambda p: (p[0], p[1], p[6] == "", p[2], p[3])):
        ui_map, kind, x, y = point[:4]
        if any(o[0] == ui_map and o[1] == kind and abs(o[2] - x) < SAME_PLACE and abs(o[3] - y) < SAME_PLACE
               for o in out):
            continue
        out.append(point)
    return sorted(out, key=lambda p: (p[0], KINDS.index(p[1]), p[2], p[3]))


def write(path, version, date, found):
    """Writes Services.lua; names are numbered in their order of appearance."""
    names, index = {}, {}
    rows = {}
    for ui_map, kind, x, y, faction, locale, name in found:
        number = 0
        if name:
            key = (locale, name)
            if key not in index:
                names.setdefault(locale, []).append(name)
                index[key] = len(names[locale])
            number = index[key]
        rows.setdefault(ui_map, []).append([kind, to_int(x), to_int(y), faction, locale if number else "", number])
    lines_out = [lua.header("city services", version, date, [
        "harvest/directions.csv (the places city guards mark on the map), harvest/npcs.csv (service NPCs talked "
        "to) and harvest/objects.csv (mailboxes opened): recorded in the game with the harvest mode",
    ])]
    lines_out.append("local _, pack = ...\n")
    lines_out.append("-- Built only when MapScout asks for it (see Pack.lua)")
    lines_out.append("pack.categories.services = function()")
    lines_out.append("\treturn {")
    lines_out.append("\t\tbuild = %s," % lua.string(version))
    lines_out.append("\t\t-- [uiMapID] = { { service, x, y, faction, locale, name }, ... }: service \"bank\", \"auction\",")
    lines_out.append("\t\t-- \"inn\", \"mailbox\", \"stable\" or \"repair\"; x, y 0-10000 on the map; faction \"Alliance\",")
    lines_out.append("\t\t-- \"Horde\" or \"\" (anyone); name = index in names[locale] of the place's name as the game")
    lines_out.append("\t\t-- wrote it in that language (0: none)")
    lines_out.append("\t\tmaps = {")
    for ui_map in sorted(rows):
        lines_out.append("\t\t\t[%d] = {" % ui_map)
        for row in rows[ui_map]:
            lines_out.append("\t\t\t\t%s," % lua.row(row))
        lines_out.append("\t\t\t},")
    lines_out.append("\t\t},")
    lines_out.append("\t\tnames = {")
    for locale in sorted(names):
        lines_out.append("\t\t\t%s = {" % locale)
        for name in names[locale]:
            lines_out.append("\t\t\t\t%s," % lua.string(name))
        lines_out.append("\t\t\t},")
    lines_out.append("\t\t},")
    lines_out.append("\t}")
    lines_out.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines_out) + "\n")
    return sum(len(r) for r in rows.values())
