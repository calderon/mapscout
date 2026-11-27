"""World positions -> map positions, as the game's map does it.

UiMapAssignment says which part of the world each map (uiMapID) shows:
Region_0..2 are the lowest world x, y, z and Region_3..5 the highest, and
UiMin/UiMax the part of the map they fill (0..1). On the map, x grows when the
world y falls (west to east) and y grows when the world x falls (north to south).
"""

import math

# UiMap.Type: 2 = continent, 3 = zone (cities are zones too)
CONTINENT, ZONE = 2, 3


class Maps:
    def __init__(self, ui_maps, assignments):
        # System 0 = the world map (1 = the flight map, with its own copies)
        self.types = {int(row["ID"]): int(row["Type"]) for row in ui_maps if row["System"] == "0"}
        self.names = {int(row["ID"]): row["Name_lang"] for row in ui_maps}
        self.assignments = []
        for row in assignments:
            ui_map = int(row["UiMapID"])
            if self.types.get(ui_map) not in (CONTINENT, ZONE):
                continue
            region = [float(row["Region_%d" % i]) for i in range(6)]
            ui = [float(row[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")]
            area = (region[3] - region[0]) * (region[4] - region[1])
            if area <= 0:
                continue
            self.assignments.append({
                "uiMap": ui_map, "continent": int(row["MapID"]), "type": self.types[ui_map],
                "region": region, "ui": ui, "area": area, "areaID": int(row.get("AreaID") or 0),
            })

    def _holding(self, continent, world_x, world_y, kind):
        found = []
        for a in self.assignments:
            min_x, min_y, _, max_x, max_y, _ = a["region"]
            if a["continent"] == continent and a["type"] == kind \
                    and min_x <= world_x <= max_x and min_y <= world_y <= max_y:
                found.append(a)
        return found

    def place(self, continent, world_x, world_y):
        """(uiMapID, x, y) with x, y in 0..1, or None if no map holds the point.

        Zone maps are rectangles and neighbours overlap, while the game knows
        each zone's real outline. So: the zone map if it is the only one that
        holds the point; else the continent map, and the addon finds the zone
        in the game (ns.PlaceOnMap, as it does for flight masters)."""
        zones = self._holding(continent, world_x, world_y, ZONE)
        if len(zones) == 1:
            return self._convert(zones[0], world_x, world_y)
        continents = sorted(self._holding(continent, world_x, world_y, CONTINENT), key=lambda a: a["area"])
        if continents:
            return self._convert(continents[0], world_x, world_y)
        return None

    def place_in_zone(self, area_id, continent, world_x, world_y):
        """(uiMapID, x, y) on the zone map of an AreaTable zone (the parent of a
        subzone) when it holds the point, else as place() does. The point is
        known to be in that zone: no need for the game to guess at a border."""
        for a in self._holding(continent, world_x, world_y, ZONE):
            if a["areaID"] == area_id:
                return self._convert(a, world_x, world_y)
        return self.place(continent, world_x, world_y)

    @staticmethod
    def _convert(a, world_x, world_y):
        min_x, min_y, _, max_x, max_y, _ = a["region"]
        ui_min_x, ui_min_y, ui_max_x, ui_max_y = a["ui"]
        x = ui_min_x + (max_y - world_y) / (max_y - min_y) * (ui_max_x - ui_min_x)
        y = ui_min_y + (max_x - world_x) / (max_x - min_x) * (ui_max_y - ui_min_y)
        return a["uiMap"], x, y


def to_int(value):
    """A map coordinate 0..1 as the packs store it: an integer 0..10000
    (halves round up; Python's round() would send them to the even number)."""
    return max(0, min(10000, math.floor(value * 10000 + 0.5)))
