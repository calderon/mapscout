"""Trainers: class, profession, riding and weapon trainers.

Like the city services (services.py), the client has none of them: they come
from our harvest mode (Debug/Harvest.lua), measured in the game:

- directions.csv: what a city guard marks on the map when asked for a trainer
  ("Class trainer > Mage", "Profession trainer > Alchemy", "Weapon master").
  The guard marks the trainer's building, named as the game names it.
- npcs.csv: the trainers a player talked to (service "trainer"), with the skill
  their window teaches ("Riding"). Only riding and professions are told apart
  this way: a class trainer teaches its class's schools ("Fire"), not its class.

For one trainer on one map, the guard's places win (the trainer stands in the
building the guard points to). Each trainer is a kind ("class", "profession",
"riding", "weapon") and what it teaches: the class token ("MAGE") or the
profession ("alchemy"); "" for riding and weapons. A guard answer or skill
whose words are not known is reported.
"""

import services
from geo import to_int
import lua

KINDS = ("class", "profession", "riding", "weapon")

CLASSES = {
    "WARRIOR": ("guerrero", "warrior"),
    "PALADIN": ("paladin",),
    "HUNTER": ("cazador", "hunter"),
    "ROGUE": ("picaro", "rogue"),
    "PRIEST": ("sacerdote", "priest"),
    "SHAMAN": ("chaman", "shaman"),
    "MAGE": ("mago", "mage"),
    "WARLOCK": ("brujo", "warlock"),
    "DRUID": ("druida", "druid"),
}
PROFESSIONS = {
    "alchemy": ("alquimia", "alchemy"),
    "blacksmithing": ("herreria", "blacksmithing"),
    "cooking": ("cocina", "cooking"),
    "enchanting": ("encantamiento", "enchanting"),
    "engineering": ("ingenieria", "engineering"),
    "fishing": ("pesca", "fishing"),
    "herbalism": ("botanica", "herboristeria", "herbalism"),
    "firstaid": ("primeros auxilios", "first aid"),
    "skinning": ("desuello", "skinning"),
    "leatherworking": ("peleteria", "leatherworking"),
    "tailoring": ("sastreria", "tailoring"),
    "mining": ("mineria", "mining"),
}
RIDING = ("equitacion", "riding")

# The guard's words for each kind of trainer (the first option, plain)
GUARD_CLASS = ("instructor de clases", "instructor de clase", "class trainer", "class trainers")
GUARD_PROFESSION = ("instructor de profesiones", "instructor de profesion", "profession trainer",
                    "profession trainers")
GUARD_WEAPON = ("instructor de armas", "maestro de armas", "weapon master", "weapons master", "weapon trainer",
                "weapons trainer")
GUARD_RIDING = ("instructor de equitacion", "riding trainer", "riding instructor")


def _find(table, word):
    for key, words in table.items():
        if word in words:
            return key
    return None


def guard_trainer(asked):
    """(kind, what) of a guard answer ("Instructor de clases > Mago" ->
    ("class", "MAGE")), None if it is not about trainers, or False if it is
    but its words are not known."""
    parts = [services.plain(p) for p in asked.split(">")]
    first, rest = parts[0], parts[1] if len(parts) > 1 else ""
    if first in GUARD_WEAPON:
        return ("weapon", "")
    if first in GUARD_RIDING:
        return ("riding", "")
    if first in GUARD_CLASS:
        token = _find(CLASSES, rest)
        return ("class", token) if token else False
    if first in GUARD_PROFESSION:
        if rest in RIDING:
            return ("riding", "")
        profession = _find(PROFESSIONS, rest)
        return ("profession", profession) if profession else False
    if first.startswith("instructor") or "trainer" in first:
        return False
    return None


def npc_trainer(skill):
    """(kind, what) of a trainer NPC from the skill its window teaches, or None
    (a class trainer, or not known)."""
    word = services.plain(skill)
    if word in RIDING:
        return ("riding", "")
    profession = _find(PROFESSIONS, word)
    return ("profession", profession) if profession else None


def points(folder):
    """[(uiMap, kind, what, x, y, faction, locale, name)] from the harvest CSV
    files, and the guard answers whose words are not known."""
    npcs = services._read(folder, "npcs")
    faction_of = {row["npc"]: services._faction(row["faction"]) for row in npcs}
    found, unknown, from_guards = [], [], set()
    for row in services._read(folder, "directions"):
        for asked in row["asked"].split("|"):
            asked = asked.strip()
            trainer = guard_trainer(asked) if asked else None
            if trainer is False:
                unknown.append(asked)
            elif trainer:
                ui_map = int(row["uiMap"])
                from_guards.add((ui_map,) + trainer)
                found.append((ui_map, trainer[0], trainer[1], float(row["x"]), float(row["y"]),
                              faction_of.get(row["guard"], ""), row.get("locale") or services.DEFAULT_LOCALE,
                              row["name"]))
    for row in npcs:
        if "trainer" not in row["services"].split():
            continue
        trainer = npc_trainer(row.get("skill", ""))
        ui_map = int(row["uiMap"])
        if trainer and (ui_map,) + trainer not in from_guards:
            found.append((ui_map, trainer[0], trainer[1], float(row["x"]), float(row["y"]),
                          services._faction(row["faction"]), row.get("locale") or services.DEFAULT_LOCALE,
                          row["name"]))
    return found, sorted(set(unknown))


def merge(found):
    """One point per trainer and place (closer than services.SAME_PLACE), sorted."""
    out = []
    for point in sorted(found, key=lambda p: (p[0], p[1], p[2], p[7] == "", p[3], p[4])):
        ui_map, kind, what, x, y = point[:5]
        if any(o[:3] == (ui_map, kind, what) and abs(o[3] - x) < services.SAME_PLACE
               and abs(o[4] - y) < services.SAME_PLACE for o in out):
            continue
        out.append(point)
    return sorted(out, key=lambda p: (p[0], KINDS.index(p[1]), p[2], p[3], p[4]))


def write(path, version, date, found):
    """Writes Trainers.lua; names are numbered in their order of appearance."""
    names, index, rows = {}, {}, {}
    for ui_map, kind, what, x, y, faction, locale, name in found:
        number = 0
        if name:
            key = (locale, name)
            if key not in index:
                names.setdefault(locale, []).append(name)
                index[key] = len(names[locale])
            number = index[key]
        rows.setdefault(ui_map, []).append(
            [kind, what, to_int(x), to_int(y), faction, locale if number else "", number])
    out = [lua.header("trainers", version, date, [
        "harvest/directions.csv (the places city guards mark on the map) and harvest/npcs.csv (trainers talked "
        "to): recorded in the game with the harvest mode",
    ])]
    out.append("local _, pack = ...\n")
    out.append("-- Built only when MapScout asks for it (see Pack.lua)")
    out.append("pack.categories.trainers = function()")
    out.append("\treturn {")
    out.append("\t\tbuild = %s," % lua.string(version))
    out.append("\t\t-- [uiMapID] = { { kind, what, x, y, faction, locale, name }, ... }: kind \"class\",")
    out.append("\t\t-- \"profession\", \"riding\" or \"weapon\"; what = class token (\"MAGE\") or profession")
    out.append("\t\t-- (\"alchemy\"), \"\" for the others; x, y 0-10000 on the map; faction \"Alliance\", \"Horde\"")
    out.append("\t\t-- or \"\" (anyone); name = index in names[locale] of the place's name as the game wrote it")
    out.append("\t\t-- in that language (0: none)")
    out.append("\t\tmaps = {")
    for ui_map in sorted(rows):
        out.append("\t\t\t[%d] = {" % ui_map)
        for row in rows[ui_map]:
            out.append("\t\t\t\t%s," % lua.row(row))
        out.append("\t\t\t},")
    out.append("\t\t},")
    out.append("\t\tnames = {")
    for locale in sorted(names):
        out.append("\t\t\t%s = {" % locale)
        for name in names[locale]:
            out.append("\t\t\t\t%s," % lua.string(name))
        out.append("\t\t\t},")
    out.append("\t\t},")
    out.append("\t}")
    out.append("end")
    with open(path, "w", encoding="utf-8", newline="\n") as target:
        target.write("\n".join(out) + "\n")
    return sum(len(r) for r in rows.values())
