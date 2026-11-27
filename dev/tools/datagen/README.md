# Data generator (WoW Forever)

Writes the Lua files of `MapScout_Data_Forever/`, the static data pack: what the
game cannot tell the addon while playing. Development tool only: it is not part
of the addon zip (`dev/` is in `.pkgmeta` `ignore`).

```sh
python3 dev/tools/datagen/datagen.py harvest     # bring in what /ms harvest recorded
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
| Hand-written entrances (`manual/entrances.csv`) | Single facts from public sources, at least two that agree, cited per row. Never another addon's list | Entrances the client data does not have |
| Harvest data (`harvest/*.csv`) | Recorded in the game with `/ms harvest on` (Debug/Harvest.lua, development only), brought in with `datagen.py harvest` | Dungeon entrances (they count as checked); city services: the places city guards mark when asked for them (`directions.csv`), service NPCs talked to (`npcs.csv`, trainers with the skill they teach) and mailboxes opened (`objects.csv`) |
| wow-completionist-data (CC BY-SA 4.0) | Quest and NPC seed (#104) | Not yet |

Never data from other addons' databases, emulator databases or wiki scraping
(see ARCHITECTURE.md, "Data sources").

Tables per output:

- `Places.lua`: `AreaPOI` (enUS, esES, esMX), `UiMap`, `UiMapAssignment`.
- `Dungeons.lua`: `Map` (enUS, esES, esMX), `UiMap`, `UiMapAssignment`, `LFGDungeons`, `ContentTuning`, plus `manual/entrances.csv`.
- `Services.lua`: only the harvest (the client has no service NPCs nor mailboxes).
- `Trainers.lua`: only the harvest, like `Services.lua`.
- `Transport.lua`: `TaxiPathNode`, `AreaTrigger`, `AreaPOI` (enUS, esES, esMX), `UiMap`, `UiMapAssignment`, plus `manual/transport.csv`.

`manual/transport.csv` lists the transport lines players ride, one row each:
its kind (`boat`, `zeppelin`, `skyship`, `tram`, or `none` for a path left out
on purpose, like Naxxramas'), its `TaxiPath` ID, or for the tram the
`AreaTrigger` IDs of its entrances. The client knows each route and where it
stops, but not what runs on it nor whether players ride it. The generator
reports a path with stops that is not listed (a new build's new line), and a
kind that does not fit the route's height (zeppelins and skyships fly, boats
stay at sea level).

`manual/verified.csv` lists the entrances checked in the game. Only those get
a place on the map; every other dungeon or raid the group finder knows is still
written, with no place (uiMapID 0), and MapScout shows it as "entrance to be
confirmed". A point that is not where players walk in (the client's corpse
point is often the portal deep inside a cave) is worse than none.

`manual/*.pending.csv` (not committed) holds points waiting for their author's
permission. `--pending` adds them, for tests in the game only: never commit a
file generated with it.

## Harvesting city services

The quickest way to record a city: `/ms harvest on`, then ask a city guard for
each of its options, submenus too. The guard marks the place on the map, and
the harvest keeps it with the guard's words ("Banco de Forjaz") and the
client's language. Repair vendors are not among a guard's options: they are
recorded by opening their window. `services.py` knows the guards' words in
English and Spanish (`GUARD_WORDS`); the generator reports an answer it does
not know, so a new city or language is not missed.

Trainers come from the same guards ("Instructor de clases > Mago",
"Instructor de profesiones > Alquimia", "Instructor de armas"): `trainers.py`
knows those words and the names of the classes and professions. Riding
trainers are not among a guard's options: talking to one records the skill its
window teaches ("Equitación"), which tells riding and profession trainers
apart (a class trainer's window teaches its schools, not its class, so those
come only from guards).

## Outputs

Each file starts with "Generated … Do not edit", the build and its date, and
the sources. Same inputs, same text: rows are sorted and coordinates rounded the
same way, so a new build only changes the lines that really changed.

Positions are integers 0–10000 on a uiMapID. Zone maps are rectangles that
overlap their neighbours: a point is stored on its zone only when a single zone
map holds it, else on the continent map, and the addon finds its zone in the
game (`ns.PlaceOnMap`).

- `Places.lua`: towns and camps, and named places (the names the world map
  writes, where it writes them; a name is kept once per map). Not every subzone
  is there: some names are part of the map's art.
- `Dungeons.lua`: dungeon and raid entrances (where the corpse of a player who
  dies inside goes), their kind, recommended level and names. Instances without
  that point (Forever's new ones, Naxxramas, Caverns of Time) come from
  `manual/entrances.csv` when there are public sources for them, and later from
  the harvest mode (#40).
- `Transport.lua`: the docks of boats, zeppelins and skyships (the stops of
  their routes in the client) and the two entrances of the Deeprun Tram, each
  with the docks it goes to, named after the town or capital next to it (none:
  the addon names it after its map). Stops of one kind at the same pier are one
  dock with every destination.
- `Services.lua`: banks, auction houses, inns, mailboxes, stable masters and
  repair vendors, per map, with the faction that can use them (none for
  mailboxes) and the name of the place as the game wrote it, in the language
  it was harvested in. For one service on one map, the places a guard gave
  win over the NPCs talked to (they stand inside); every mailbox opened adds
  up.
- `Trainers.lua`: class, profession, riding and weapon trainers, per map, with
  what they teach (class token or profession), the faction and the place's
  name, as in `Services.lua`. The guard's place wins over the NPC talked to.
