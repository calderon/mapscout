"""City services: banks, auction houses, inns, mailboxes, stable masters,
repair vendors, barbers, transmogrifiers, guild masters, battlemasters, anvils
and forges.

The client data has none of them (the NPCs and mailboxes are the server's), so
they come from our harvest mode (Debug/Harvest.lua), measured in the game:

- directions.csv: what a city guard marks on the map when asked ("The bank"),
  with the guard's words for it. The guard's answer is the place (the bank's
  building), named as the game names it, in the language of the client that
  asked.
- npcs.csv: the NPCs a player talked to, with the services they offered.
- objects.csv: the mailboxes a player opened, and the anvils and forges noted
  with /ms harvest here.

Services not harvested yet on a map may come from manual/services.csv: single
facts from public sources, at least two that agree.

For one service on one map, the guard's places win: when a guard gave them,
the NPCs of that service on that map are left out (the bankers stand in the
bank the guard points to). Mailboxes add up: every one opened is a mailbox,
and the guard's one is too. Points of one service closer than SAME_PLACE are
one. A guard answer whose words are not known is reported, so a new language
or a new city's words are not missed.

Battlemasters also say which battleground they send to ("Battlemaster >
Alterac Valley" -> "alterac"): each battleground is its own point.
"""

import csv
import os
import unicodedata

import lua
from geo import to_int

KINDS = ("bank", "auction", "inn", "mailbox", "stable", "repair", "barber", "transmog", "guild", "battle", "anvil",
         "forge")

# The guard's words for each service (the start of the option, lowercase,
# without accents), per language. Options for later categories are known and
# left out without a report.
GUARD_WORDS = {
    "bank": ("banco", "bank", "the bank"),
    "auction": ("casa de subastas", "auction house", "the auction house"),
    "inn": ("la posada", "posada", "the inn", "inn"),
    "mailbox": ("buzon", "mailbox", "the mailbox"),
    "stable": ("maestro de establos", "stable master", "the stable master"),
    "barber": ("peluqueria", "barberia", "barber", "the barber", "barbershop", "barber shop"),
    "transmog": ("transfigurador", "transfiguradora", "transfiguracion", "transmogrifier", "the transmogrifier",
                 "transmogrification"),
    "guild": ("maestro de la hermandad", "guild master", "the guild master"),
    "battle": ("maestro de batalla", "maestros de batalla", "battlemaster", "battlemasters", "battle master"),
}
# The battlegrounds a battlemaster sends to (the guard's submenu, plain)
BATTLEGROUNDS = {
    "alterac": ("valle de alterac", "alterac valley"),
    "arathi": ("cuenca de arathi", "arathi basin"),
    "warsong": ("garganta grito de guerra", "warsong gulch"),
}
GUARD_LATER = (
    "instructor", "maestro de grifos", "tren subterraneo", "trainer", "gryphon master", "wind rider master",
    "flight master", "deeprun tram", "zeppelin master", "bat handler", "hippogryph master",
)
NPC_SERVICES = {"bank": "bank", "auction": "auction", "innkeeper": "inn", "stable": "stable", "repair": "repair",
                "guild": "guild", "battlemaster": "battle", "transmog": "transmog"}
OBJECTS = ("mailbox", "anvil", "forge")
FACTIONS = ("Alliance", "Horde")
ANYONE = ("mailbox", "anvil", "forge")  # any player can use them, whatever the guard's faction
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


def battleground(asked):
    """The battleground of a battlemaster answer ("Maestro de batalla > Valle de
    Alterac" -> "alterac"), "" when it names none, None if its words are not
    known."""
    parts = asked.split(">")
    if len(parts) < 2:
        return ""
    rest = plain(parts[1])
    for key, words in BATTLEGROUNDS.items():
        if rest in words:
            return key
    return None


def _read(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as source:
        return list(csv.DictReader(source))


def _faction(value):
    return value if value in FACTIONS else ""


def points(folder, roaming=frozenset()):
    """[(uiMap, kind, x, y, faction, locale, name, what[, True])] from the
    harvest CSV files (what: the battleground of a battlemaster, else ""; a
    ninth True: an NPC who walks a route, its ID in roaming), and the guard
    answers whose words are not known."""
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
            what = battleground(asked) if kind == "battle" else ""
            if kind is None or what is None:
                unknown.append(asked)
            elif kind:
                kinds.add((kind, what))
        for kind, what in sorted(kinds):
            ui_map = int(row["uiMap"])
            from_guards.add((ui_map, kind))
            faction = "" if kind in ANYONE else faction_of.get(row["guard"], "")
            found.append((ui_map, kind, float(row["x"]), float(row["y"]), faction,
                          row.get("locale") or DEFAULT_LOCALE, row["name"], what))
    for row in npcs:
        ui_map = int(row["uiMap"])
        for service in row["services"].split():
            kind = NPC_SERVICES.get(service)
            if kind and (ui_map, kind) not in from_guards:
                point = (ui_map, kind, float(row["x"]), float(row["y"]), _faction(row["faction"]),
                         row.get("locale") or DEFAULT_LOCALE, row["name"], "")
                found.append(point + (True,) if int(row["npc"]) in roaming else point)
    for row in _read(folder, "objects"):
        if row["service"] in OBJECTS:
            found.append((int(row["uiMap"]), row["service"], float(row["x"]), float(row["y"]), "", "", "", ""))
    return found, sorted(set(unknown))


def manual(path):
    """Points of the hand-written file, as points() gives them (no name)."""
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as source:
        lines = [line for line in source if line.strip() and not line.lstrip().startswith("#")]
    out = []
    for row in csv.DictReader(lines):
        kind, ui_map = row["service"], int(row["uiMap"])
        x, y = float(row["x"]), float(row["y"])
        if kind not in KINDS:
            raise ValueError("%s: unknown service %r" % (path, kind))
        if not (0 <= x <= 100 and 0 <= y <= 100):
            raise ValueError("%s: %s on %d is off the map (%s, %s)" % (path, kind, ui_map, x, y))
        if len([s for s in row["sources"].split(";") if s.strip()]) < 2:
            raise ValueError("%s: %s on %d needs two sources" % (path, kind, ui_map))
        out.append((ui_map, kind, x / 100, y / 100, _faction(row["faction"]), "", "", ""))
    return out


def with_manual(found, hand):
    """The harvested points plus the hand-written ones of services not
    harvested on their map."""
    harvested = {(p[0], p[1]) for p in found}
    return found + [p for p in hand if (p[0], p[1]) not in harvested]


def merge(found):
    """One point per place: points of one service (and battleground) on one map
    closer than SAME_PLACE are one (the first with a name keeps it). Sorted."""
    out = []
    for point in sorted(found, key=lambda p: (p[0], p[1], p[7], p[6] == "", p[2], p[3])):
        ui_map, kind, x, y = point[:4]
        if any(o[0] == ui_map and o[1] == kind and o[7] == point[7] and abs(o[2] - x) < SAME_PLACE
               and abs(o[3] - y) < SAME_PLACE for o in out):
            continue
        out.append(point)
    return sorted(out, key=lambda p: (p[0], KINDS.index(p[1]), p[7], p[2], p[3]))


def write(path, version, date, found):
    """Writes Services.lua; names are numbered in their order of appearance."""
    names, index = {}, {}
    rows = {}
    for point in found:
        ui_map, kind, x, y, faction, locale, name, what = point[:8]
        number = 0
        if name:
            key = (locale, name)
            if key not in index:
                names.setdefault(locale, []).append(name)
                index[key] = len(names[locale])
            number = index[key]
        row = [kind, to_int(x), to_int(y), faction, locale if number else "", number]
        if what or point[8:9] == (True,):
            row.append(what)
        if point[8:9] == (True,):
            row.append(True)  # walks a route: the point is one spot of it
        rows.setdefault(ui_map, []).append(row)
    lines_out = [lua.header("city services", version, date, [
        "harvest/directions.csv (the places city guards mark on the map), harvest/npcs.csv (service NPCs talked "
        "to) and harvest/objects.csv (mailboxes opened, anvils and forges noted): recorded in the game with the "
        "harvest mode",
        "manual/services.csv: services not harvested yet, from at least two public sources that agree (cited there)",
    ])]
    lines_out.append("local _, pack = ...\n")
    lines_out.append("-- Built only when MapScout asks for it (see Pack.lua)")
    lines_out.append("pack.categories.services = function()")
    lines_out.append("\treturn {")
    lines_out.append("\t\tbuild = %s," % lua.string(version))
    lines_out.append("\t\t-- [uiMapID] = { { service, x, y, faction, locale, name[, battleground[, roams]] }, ... }:")
    lines_out.append("\t\t-- service")
    lines_out.append("\t\t-- \"bank\", \"auction\", \"inn\", \"mailbox\", \"stable\", \"repair\", \"barber\", \"transmog\",")
    lines_out.append("\t\t-- \"guild\", \"battle\", \"anvil\" or \"forge\"; x, y 0-10000 on the map; faction")
    lines_out.append("\t\t-- \"Alliance\", \"Horde\" or \"\" (anyone); name = index in names[locale] of the place's")
    lines_out.append("\t\t-- name as the game wrote it in that language (0: none); battleground (battlemasters only)")
    lines_out.append("\t\t-- \"alterac\", \"arathi\" or \"warsong\" (\"\" for the others); roams: true when the NPC")
    lines_out.append("\t\t-- walks a route (the point is one spot of it)")
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
