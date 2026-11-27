"""Which subzone each piece of ground belongs to, from the client's map files.

Many subzones have no label in the client data (AreaPOI): their name is part
of the map's art (Saldean's Farm, Jangolode Mine). Their place comes from the
terrain. Each continent is a grid of tiles (WDT file, chunk MAID: the root ADT
file of each tile), and each tile is 16 x 16 chunks of about 33 yards (MCNK),
each one with the AreaTable ID of the subzone it belongs to and its world
position.

The tiles come from wago.tools one by one, slowly (wago.Files). Only what is
needed is kept in the cache: per tile, the area of each chunk and its centre.
"""

import json
import math
import os
import struct
from collections import deque

CHUNK = 100 / 3  # yards: a tile is 533.33 yards, 16 chunks
MCNK_AREA, MCNK_POSITION = 52, 104  # offsets in the MCNK header


def _chunks(data):
    """(tag, offset of its data, size) of each chunk of a client file."""
    at = 0
    while at + 8 <= len(data):
        tag = data[at:at + 4][::-1].decode("ascii", "replace")
        size = struct.unpack_from("<I", data, at + 4)[0]
        yield tag, at + 8, size
        at += 8 + size


def tile_files(wdt):
    """FileDataIDs of the root ADT of every tile the continent has (WDT MAID)."""
    for tag, at, size in _chunks(wdt):
        if tag == "MAID":
            # 4096 entries of 8 IDs (root, obj0, obj1, tex0, lod, map texture...)
            return sorted({struct.unpack_from("<I", wdt, at + i * 32)[0] for i in range(size // 32)} - {0})
    return []


def tile_areas(adt):
    """[[areaID, world x, world y]] for each chunk of a root ADT: the centre of
    the chunk (its position is its corner with the highest x and y)."""
    out = []
    for tag, at, _ in _chunks(adt):
        if tag == "MCNK":
            area = struct.unpack_from("<I", adt, at + MCNK_AREA)[0]
            x, y = struct.unpack_from("<2f", adt, at + MCNK_POSITION)
            out.append([area, round(x - CHUNK / 2, 1), round(y - CHUNK / 2, 1)])
    return out


def continent(files, wdt_id, cache_path, log=print):
    """[[areaID, x, y]] of every chunk of a continent. Downloads the tiles not
    in the cache yet, saving it every few tiles (a stopped run goes on later)."""
    cached = {}
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as source:
            cached = json.load(source)
    tiles = cached.get("tiles", {})
    if "files" not in cached:
        cached["files"] = tile_files(files.get(wdt_id))
    missing = [f for f in cached["files"] if str(f) not in tiles]
    if missing:
        log("terrain: %d of %d tiles of WDT %d to download (about %d min)" % (
            len(missing), len(cached["files"]), wdt_id, len(missing) * files.DELAY // 60 + 1))
    for count, file_id in enumerate(missing, 1):
        tiles[str(file_id)] = tile_areas(files.get(file_id))
        if count % 25 == 0 or count == len(missing):
            cached["tiles"] = tiles
            _save(cache_path, cached)
            log("terrain: %d/%d" % (count, len(missing)))
    return [chunk for f in cached["files"] for chunk in tiles[str(f)]]


def _save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as out:
        json.dump(data, out, separators=(",", ":"))
    os.replace(path + ".tmp", path)


def middles(chunks, wanted):
    """{areaID: (x, y, size)}: for each wanted area, a point inside it near its
    middle. Its biggest connected piece of ground (size: its chunks), and there
    the chunk farthest from any other area (then the closest to its centre)."""
    cells = {}
    for area, x, y in chunks:
        if area in wanted:
            # a chunk's centre is half a chunk from the grid lines: (cell + 0.5) * CHUNK
            cells[(math.floor(x / CHUNK), math.floor(y / CHUNK))] = area
    by_area = {}
    for cell, area in cells.items():
        by_area.setdefault(area, set()).add(cell)
    out = {}
    for area, own in by_area.items():
        piece = max(_pieces(own), key=lambda p: (len(p), min(p)))
        depth = _depth(piece)
        cx = sum(c[0] for c in piece) / len(piece)
        cy = sum(c[1] for c in piece) / len(piece)
        best = min(piece, key=lambda c: (-depth[c], (c[0] - cx) ** 2 + (c[1] - cy) ** 2, c))
        out[area] = ((best[0] + 0.5) * CHUNK, (best[1] + 0.5) * CHUNK, len(piece))
    return out


def _neighbours(cell):
    x, y = cell
    return ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))


def _pieces(cells):
    left, out = set(cells), []
    while left:
        start = left.pop()
        piece, queue = {start}, deque([start])
        while queue:
            for n in _neighbours(queue.popleft()):
                if n in left:
                    left.remove(n)
                    piece.add(n)
                    queue.append(n)
        out.append(piece)
    return out


def _depth(piece):
    """Steps from each cell to the nearest cell outside the piece."""
    depth = {c: 1 for c in piece if any(n not in piece for n in _neighbours(c))}
    queue = deque(depth)
    while queue:
        cell = queue.popleft()
        for n in _neighbours(cell):
            if n in piece and n not in depth:
                depth[n] = depth[cell] + 1
                queue.append(n)
    return depth
