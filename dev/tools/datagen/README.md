# Data generator (WoW Forever)

Writes the Lua files of `MapScout_Data_Forever/`, the static data pack: what the
game cannot tell the addon while playing. Development tool only: it is not part
of the addon zip (`dev/` is in `.pkgmeta` `ignore`).

```sh
python3 dev/tools/datagen/datagen.py             # the build in BUILD (datagen.py)
python3 dev/tools/datagen/datagen.py --refresh   # download the tables again
python3 -m unittest discover -s dev/tools/datagen
```

Python 3.9 or newer, standard library only. The generated files are committed;
run the generator again when Forever gets a new build (change `BUILD`) or when a
generator changes, and commit what changed.

## Inputs

| Input | Where it comes from | Used for |
|---|---|---|
| The Forever client's DB2 tables of one exact build (`BUILD`, now 1.60.1.71139) | CSV exports of [wago.tools](https://wago.tools) (`/db2/{table}/csv?version=…`), the build's own client data. Its `robots.txt` and `/llms.txt` allow these downloads. Kept in `.cache/<build>/` (not committed) | Instance entrances, map positions, names, levels |
| Harvest data (#40) | Recorded in the game | Not yet |
| wow-completionist-data (CC BY-SA 4.0) | Quest and NPC seed (#104) | Not yet |

Never data from other addons' databases, emulator databases or wiki scraping
(see ARCHITECTURE.md, "Data sources").

Tables per output:

- `Dungeons.lua`: `Map` (enUS, esES, esMX), `UiMap`, `UiMapAssignment`, `LFGDungeons`, `ContentTuning`.

## Outputs

Each file starts with "Generated … Do not edit", the build and its date, and
the sources. Same inputs, same text: rows are sorted and coordinates rounded the
same way, so a new build only changes the lines that really changed.

Positions are integers 0–10000 on a uiMapID. Zone maps are rectangles that
overlap their neighbours: a point is stored on its zone only when a single zone
map holds it, else on the continent map, and the addon finds its zone in the
game (`ns.PlaceOnMap`).

- `Dungeons.lua`: dungeon and raid entrances (where the corpse of a player who
  dies inside goes), their kind, recommended level and names. Instances without
  that point (Forever's new ones, Naxxramas, Caverns of Time) are not there yet:
  they will come from the harvest mode (#40).
