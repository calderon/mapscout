"""NPCs who walk a route (#179).

The harvest keeps every place an NPC was talked to (the "seen" column of
harvest/npcs.csv, the player's position each time, with the spawn: NPCs that
share an ID, like every Ironforge mountaineer, are told apart by it). One NPC
(same ID and spawn) seen on one map in two places farther apart than FAR_YARDS
walks a route: the point we have is only
one spot on it, and MapScout shows it as approximate. Talking to an NPC who
stands still from either side leaves the places a few yards apart, well under
FAR_YARDS.

manual/roams.csv flags NPCs by hand (one seen walking, before the harvest has
two far places): npc, name, sources (who saw it and when, or public sources).
"""

import csv
import itertools
import os

import harvest

FAR_YARDS = 25


def far_apart(places, maps):
    """True when two places of one spawn on one map are farther apart than
    FAR_YARDS (places without a spawn can't be told apart: not compared)."""
    for a, b in itertools.combinations(places, 2):
        if a[0] != b[0] or not a[3] or a[3] != b[3]:
            continue
        yards = maps.yards(a[0], a[1], a[2], b[1], b[2])
        if yards is not None and yards > FAR_YARDS:
            return True
    return False


def manual(path):
    """NPC IDs of the hand-written file; each row needs its sources."""
    if not os.path.exists(path):
        return set()
    with open(path, newline="", encoding="utf-8") as source:
        lines = [line for line in source if line.strip() and not line.lstrip().startswith("#")]
    found = set()
    for row in csv.DictReader(lines):
        if not (row.get("sources") or "").strip():
            raise ValueError("%s: NPC %s needs its sources" % (path, row["npc"]))
        found.add(int(row["npc"]))
    return found


def npcs(folder, maps, manual_path=None):
    """NPC IDs that walk a route: harvested far apart, or flagged by hand."""
    found = set(manual(manual_path)) if manual_path else set()
    for row in harvest.read(folder, "npcs").values():
        if far_apart(harvest.spots(row.get("seen")), maps):
            found.add(int(row["npc"]))
    return found
