# MapScout architecture

How MapScout is built and why. Every issue that adds code should fit this document; when a decision changes, this document changes in the same pull request.

MapScout is a light search bar built into the world map (`WorldMapFrame`) of World of Warcraft. It targets **WoW Forever** first (`## Interface: 16001`); Retail and Classic come later (milestone 4.0).

## Principles

- **Map-only, zero bloat.** MapScout only searches things that have a place in the world map. No general launcher features.
- **Core without data: everything is a provider.** MapScout itself is the search engine, the bar and the options. Every result comes from a provider: built-in ones (geography, travel, services, quests, coordinates…) and any other addon's. Built-in providers use **only the public `MapScoutAPI`**: if the public API is enough for our own data, it is enough for anyone.
- **Integrations are built by the integrating addon.** MapScout never ships code for a specific addon. An addon that wants to add results or actions (e.g. Bridge: its stops, "Add to route") registers itself. Optional adapters for popular addons that don't integrate themselves are separate modules (milestone 3.0).
- **Nothing disabled is loaded.** A disabled provider or category is never loaded, indexed, queried or listening to events, and its static data pack is never loaded.
- **Taint-free.** Only MapScout's own frames; `hooksecurefunc`/`HookScript` only on scripts the frame already handles; never write fields or methods on Blizzard frames, never add to Blizzard tables (`UISpecialFrames`, map data providers, `AcquirePin`).
- **Detect capabilities, not versions.** `ns.Caps` says which APIs exist in the running client; Retail and Classic support is new data and providers, not branches in the code.
- **Lua 5.1 limits.** Small files, one module each; at most 200 `local` variables in a file's main chunk (internal sections in `do … end` blocks).

## Folder structure

```
MapScout/
  MapScout.toc                 # Interface 16001 (Forever). Later: one .toc per flavor
  Locales/
    enUS.lua                   # L["KEY"] base; missing keys fall back to English
    esES.lua                   # Spanish, also used for esMX
  Core/
    Init.lua                   # namespace ns, event dispatcher, /mapscout and /ms
    Caps.lua                   # which C_* APIs and features exist in this client
    DB.lua                     # SavedVariables, defaults, schema version + migrations
    Util.lua                   # text normalization, coordinates, map helpers
  Search/
    Query.lua                  # splits the text into @filters, handler matches and free text
    Index.lua                  # static entries, normalized once, per-provider buckets
    Engine.lua                 # matching (exact/prefix/substring/fuzzy), scoring, result cap
    Merge.lua                  # one row for the same place coming from several providers
    Ranking.lua                # favorites, aliases, frequency, recency
    Cache.lua                  # live results per provider and uiMapID, event invalidation
  API/
    Registry.lua               # providers, categories, query handlers, actions, enabled state, cost
    MapScoutAPI.lua            # the public global MapScoutAPI (thin, versioned layer over Registry)
    Discovery.lua              # providers declared in other addons' .toc (## X-MapScout-Provider)
  Providers/                   # built-in providers, registered through MapScoutAPI only
    Coordinates.lua            # query handler: "45.2, 67.8", "45 67", "Elwynn 42 65"
    Geography.lua Instances.lua Taxi.lua Transport.lua Services.lua Trainers.lua SpiritHealers.lua Quests.lua
    AreaPOI.lua Vignettes.lua Portals.lua
  UI/
    Map.lua                    # MapScout's layer over the map area, map hooks, open/close/change events
    SearchBar.lua              # edit box + gear button anchored to WorldMapFrame
    Results.lua                # pooled rows, groups "In this zone" / "Elsewhere"
    Preview.lua                # hover marker on the map canvas (own frames)
    Menu.lua                   # right-click menu (MenuUtil) and row action buttons
    Waypoint.lua               # C_Map.SetUserWaypoint + super-track, optional TomTom
  Adapters/                    # other addons read at runtime (QuestieDB...), inert when absent
    QuestieDB.lua              # available quests
    QuestieDBServices.lua      # services and trainers, handed to Services and Trainers (stopgap)
    QuestieDBSpiritHealers.lua # spirit healers, handed to SpiritHealers (stopgap)
  Options/
    Panel.lua                  # Settings canvas category (fallback if missing)
MapScout_Data_Forever/         # LoadOnDemand static data packs (data-only providers), one file per category

dev/tools/                     # data generators (not packaged, not checked)
spec/                          # unit tests (busted), not packaged
```

**Load order** in the `.toc`: Locales → Core → Search → API → built-in providers → UI → Options. LoadOnDemand modules are loaded by MapScout when needed (see *Static data*).

## Providers

A provider is anything that adds results. All of them, ours and other addons', go through the same registry (`API/Registry.lua`) and get the same treatment: a toggle in the options (with sub-toggles per category), `@` filter words, ranking, merging, actions and cost measurement.

| Kind | How it gives results | Examples |
|---|---|---|
| **Pushed entries** | `provider:SetEntries(list)` whenever its data changes; MapScout indexes them lazily | Bridge's stops, static data packs |
| **Live** | `Collect(ctx, add)`, called only while enabled, with the map open and a search running; cached per uiMapID until `Invalidate` or an event | Quests, area POIs, vignettes, flight paths |
| **Query handler** | Recognises a format in the typed text and produces results or filters | Coordinates |
| **Data-only** | A declarative table, no code (`RegisterDataProvider`) | Community data addons |

- **Discovery.** Addons can declare `## X-MapScout-Provider: <id>` in their `.toc`. MapScout reads it with `C_AddOns.GetAddOnMetadata`, lists them in the options before they load and loads LoadOnDemand ones only when enabled.
- **Merging.** Results for the same place from several providers (same map, close position, same NPC/object or similar name) become one row with both sources and both providers' actions.
- **Cost.** Each provider's time per search and approximate memory are measured (`debugprofilestop`, `/ms diag`, options). A provider over its budget is skipped for that keystroke and retried after the debounce; one provider can never freeze the search.
- **On and off.** `OnEnable` runs when a provider is turned on, also at login: that is where pushed providers call `SetEntries` (entries set before login are applied first). A disabled provider keeps nothing: its entries are dropped and `SetEntries` is ignored until it is on again. Only choices that differ from `defaultEnabled` are saved.
- **Validation.** A bad spec (no name, bad id or field types) raises a clear error to the registering addon. Bad entries (no id or name, coordinates outside 0–1, unknown category) are skipped and reported once per provider through the game's error handler.
- **Errors.** Every call into a provider or action runs in `xpcall`; after 3 errors in a session the provider is disabled for the session (not saved) and reported once in chat.
- **Internal listeners.** The index, the cache and the options follow the registry with `ns.Registry.Listen` (`registered`, `toggled`, `entries`, `invalidate`, `removed`). `/ms debug providers` lists every provider with its state, entries, errors and `@` words.
- **Inside another provider.** A provider can declare `parent = "<provider id>"`: the options show it after that provider's categories, with its own categories under it, and the outer checkbox turns both on or off (as a group's does); that provider's `@` word selects it too. Each keeps its own toggle, data and loading. Trainers use it to be one more kind of service: inside Services, found with `@service`, while their pack still loads only when Trainers is on.
- **Settings.** A provider can have on/off settings that change what it gives (`Registry.AddSettings`, internal for now, not in the public API), shown in the options after its categories and greyed while it is off; only values that differ from the default are saved (`options.settings`), and the provider rebuilds when told (`setting`). The QuestieDB adapter uses them for which available quests to show: high-level (also the ones not takeable yet), gray, seasonal and repeatable, all off by default as in Questie. Seasonal quests show only while their holiday is on, read from the game's calendar (Forever's holiday IDs from its `Holidays` table mapped to QuestieDB's holiday sorts); quests of QuestieDB's generic "seasonal" sort never show. Book quests (started at an object and at an NPC who also finishes it, the rule that places them at the book) are the adapter's one category, "Books" (`@book`); the other available quests have no category, so they show whenever the provider is on.
- **Actions.** Any addon can add actions to **any** result (`RegisterResultAction`): menu entries, optional row buttons and submenus (e.g. Bridge: "Add to current route", "Add to a saved route").

The full public contract (functions, result fields, events, versioning) is in `API.md` (#70); the agreed design is in epics #95 and #7.

### Result fields (summary)

`id` and `name` are required; `mapID`, `x`, `y` (uiMapID and 0–1 coordinates) for anything that has a place. Optional: `category`, `subtitle`, `keywords`, `icon`, `weight`, `data` (opaque, for the provider's own actions). An NPC who walks a route sets `roams = true` (its point is one spot of the route: the row says the position is approximate) and, when known, `route`: a list of paths, each on a map, with its points as `x1, y1, x2, y2…` (`{ { mapID = 1455, points = { 0.2, 0.3, 0.25, 0.3 } } }`). The map draws the part of the route on the open map instead of the pin, or, with no route there, a big soft circle without the pin. MapScout adds `provider`, `zoneName`, `continentID` and a stable `key` used by favorites, aliases, blacklist and frequency. Results handed to other addons are copies.

## Search pipeline

```
OnTextChanged
  → debounce (~150 ms, restarted on each key)
  → Query: @filters, query handlers (coordinates…), free text tokens
  → enabled providers only
  → Index (pushed/static entries) + Cache[provider][uiMapID] (live entries)
  → Engine: score (exact > prefix > word prefix > substring > fuzzy)
  → Merge duplicates
  → Ranking: favorites > aliases > frequency/recency > text score
  → cap (default 50)
  → Results: "In this zone" first, then "Elsewhere" by continent → zone
```

- **Normalization once.** Each entry's text is normalized when indexed (lowercase, accents removed, punctuation and apostrophes ignored), never per keystroke.
- **Narrowing.** If the new query extends the previous one, only the previous candidates are filtered.
- **No `OnUpdate`.** Live providers are refreshed by events (throttled when bursty) and only while the map is open.
- **No new frames while typing.** Result rows come from a pool.

## Data sources

In this order of preference (research and links: #104):

1. **Live game APIs** — nothing stored. `C_Map` (map tree, subzone names), `C_EncounterJournal.GetDungeonEntrancesForMap`, `C_TaxiMap`, `C_QuestLog`, `C_AreaPoiInfo`, `C_VignetteInfo`, later `C_TaskQuest` (Retail). Every live provider checks `ns.Caps` first and is hidden from the options when its API is missing.
2. **The Forever client's own data files** — DB2 tables of one exact Forever build, downloaded as **wago.tools' CSV exports** (`/db2/{table}/csv?version=…`; its `robots.txt` and `/llms.txt` allow them, not the browsing pages) by the generator in `dev/tools/datagen` (#38). Maps, areas, flight nodes, instances. `QuestV2` only has quest IDs, no titles.
3. **Open data under CC BY-SA 4.0: [wow-completionist-data](https://github.com/danielalanbates/wow-completionist-data)** — quests (givers, enders, objectives, prerequisites) and NPC/object positions for Forever, built from Warcraft Wiki and client data, with no emulator nor addon databases. Seed for quests and NPCs (#38). Forever coverage when checked: 3,483 quests, start located 48 %, start and end 40 %, NPCs located 47 %, few high-confidence points (many come from Retail-era wiki pages). No services (vendors, trainers, innkeepers, bankers).
4. **Our in-game harvest mode** — NPCs and objects recorded when interacting with them (#40): services, Forever-only content, and corrections to the seed.
5. **Single facts from public sources, by hand** — a point the client lacks (e.g. the entrance of a Forever dungeon) written in `dev/tools/datagen/manual/`, only when at least two public sources agree, each row citing them. Never another addon's list: data from an addon needs its author's written permission, and is credited.
6. **Other addons, only read at runtime** — never copied. **QuestieDB** (by the Questie team, GPLv3, a separate addon, supports Forever) for available quests (#83); its NPCs' waypoints are the route of a quest giver or service NPC who walks one (#179).

Not used: **Warcraft Wiki directly** (its text is CC BY-SA 4.0, but wiki.gg's terms forbid crawling, scraping and automated access; we'd need their permission), **Wowhead** (no public API, scraping is against its terms), **emulator databases** (licences incompatible with ours, and no Forever-only content), **other addons' databases** (their own licences).

**Licences.** A data pack built from CC BY-SA 4.0 data is CC BY-SA 4.0 as a whole, including what our harvest adds to it. So the packs are a **separate module** (`MapScout_Data_Forever`) with their own LICENSE and attribution (Warcraft Wiki contributors, wow-completionist-data), credited in the README (#88). MapScout's code keeps its own licence.

### Static data packs

What the client cannot tell us at runtime (NPC services, mailboxes and other objects, transport docks and destinations, portals and destinations, world bosses, subzone centres) lives in `MapScout_Data_Forever`, a LoadOnDemand addon with one file per category. The packs are data-only providers.

- Loaded with `C_AddOns.LoadAddOn` only when the first enabled category needs it; disabled categories are never built (`Core/Packs.lua`: `Packs.Get(name)` loads and builds once, `Packs.Release(name)` forgets it when its provider is turned off).
- The pack sets one global, `MapScoutDataForever`, whose `categories` are functions that return each category's table: a loaded pack costs only those functions until a category is asked for. `/ms diag` shows the memory of MapScout and of the pack, and the categories built.
- Shipped in the same zip as its own addon folder (`.pkgmeta` `move-folders`); its version follows MapScout's (release-please).
- Compact format per uiMapID, coordinates as integers 0–10000: `[1453] = { "bank", 6270, 7310, npcID, … }`.
- A position is stored on its zone map only when a single zone map holds it (zone maps are overlapping rectangles); else on the continent map, and the provider finds the zone in the game with `ns.PlaceOnMap`.
- Generated by `dev/tools/datagen` (see its README: inputs, build, how to run it again). The generated files are committed.
- Names: types from `L`; NPC and area names from the client when possible, with the English name stored as fallback.
- Files start with a "Generated, do not edit" header with the source build.

**Towns and named places** (`Places.lua`) are the names the world map writes (the client's `AreaPOI`), where it writes them. Subzones whose name is part of the map's art (Saldean's Farm, Jangolode Mine) have no such label: they come from the terrain. Every chunk of ground (about 33 yards) in the client's map tiles (ADT files, listed by each continent's WDT) says which subzone it belongs to; the generator downloads the tiles from wago.tools slowly, caches only that, and places each subzone not found yet at the chunk of its biggest piece of ground farthest from any other area (`areas` in the pack, by AreaTable ID, with the subzone's names from `AreaTable`). They are shown as named places too.

**City services** (`Services.lua`) come only from our harvest mode: the client has neither the service NPCs nor the mailboxes. The quickest source is a city guard: asked for a service, it marks the place on the map (a gossip POI), and the harvest keeps it with the guard's words and the client's language. Repair vendors and mailboxes are recorded by opening them. Barbers, transmogrifiers, guild masters and battlemasters come from the same guards (#47); a battlemaster is one point per battleground, named after it. Anvils and forges have no window: the harvest notes them where the player stands (`/ms harvest here anvil|forge`). Services not harvested yet on a map may come from `manual/services.csv`, single facts from at least two public sources that agree (the Orgrimmar transmogrifier); a harvested one on that map replaces them. Place names are shown only to players of the language they were harvested in; everyone else sees the service and its city. Until our data covers the world, the QuestieDB services adapter fills the gaps. It is not a provider of its own (where a service comes from is MapScout's business, not the player's): it hands its entries to Services (`Services.SetExtra`) and its trainers to Trainers, so one Services option and its categories turn both sources on and off; the kinds only it gives (quartermaster, vendor) are added to Services' categories when QuestieDB is installed (`Registry.AddCategories`, internal). It is built while Services or Trainers is on, and leaves out a service on a map where our pack has that service, so each city harvested moves to our data by itself, and the adapter can be removed once it adds nothing.

**Trainers** (`Trainers.lua`) come the same way, and are shown inside Services in the options (`parent`); `@service` finds them too: guards mark class, profession and weapon trainers (the building, not the NPC); riding trainers are recorded by talking to them, with the skill their window teaches. Each result is named after what it teaches ("Mage trainer"), found by trainer, class and profession words in English and the player's language. The player's own class has its toggle and comes first (higher weight); other classes have a toggle of their own. Where our pack has any trainer on a map, the QuestieDB adapter leaves its trainers out there; elsewhere its trainers are in Trainers, in the category their title names ("Mage Trainer", "Instructora de herrería": class, other class, profession, riding, weapon), or in none when it doesn't say.

**Spirit healers** (`SpiritHealers.lua`, #208, #209) are a provider of their own, not a kind of service: a player who just died looks for the nearest graveyard, and `@service` should not list them all. Forever's client has no graveyard table (`WorldSafeLocs` is not in its DB2) and `C_DeathInfo.GetGraveyardsForMap` returns none, so they come from our harvest mode: on dying, `C_DeathInfo.GetDeathReleasePosition` names the graveyard the ghost will appear at (exactly; only while dead, and only asked on the continent's map, since a city's map leaves the graveyard outside it), and a spirit healer talked to as a ghost is noted where it stands. The generator joins the records of one graveyard into the `spirithealers` pack category. Until our data covers the world, the QuestieDB adapter (`Adapters/QuestieDBSpiritHealers.lua`) fills the gaps through `SpiritHealers.SetExtra`, as with services: its spirit healers (NPCs with the `SPIRIT_HEALER` flag, one result per spawn) are left out where our pack has a graveyard within `NEAR` on the same map, so each graveyard harvested moves to our data by itself. One result per graveyard, named "Spirit Healer" in the player's language, with its zone as subtitle and search word. Found with `@spirithealer`/`@graveyard` (`@angel`/`@cementerio`).

## Persistence

| SavedVariable | Scope | Contents |
|---|---|---|
| `MapScoutDB` | Account | `schema`, `options` (providers and categories, waypoint preferences, bar position and scale, result cap), `aliases`, `blacklist`, `favorites`, `frequency` |
| `MapScoutCharDB` | Character | `schema`, `history` (recent searches), per-character caches (e.g. known flight paths) |

`Core/DB.lua` merges defaults without overwriting user values and runs ordered migrations `migrations[n](db)` up to the current `SCHEMA` on `ADDON_LOADED`. Data from a newer, unknown schema is left untouched (read-only) with one warning.

## Integration with the world map

- MapScout's frames are parented to `WorldMapFrame` (or its border frame) and anchored; they adapt to the maximized and minimized map.
- Hooks: `OnShow`/`OnHide` of the map and `hooksecurefunc` on map changes. No `SetScript` on Blizzard frames (it would also wipe other addons' hooks).
- The hover marker and highlights are MapScout's own frames over the map canvas, not map pins. A route is MapScout's own frame of lines (`CreateLine`) on the canvas, scaled like the marker so the lines keep their thickness on screen.
- The search box never closes the map by accident (Esc clears, then loses focus) and keys typed in it never move the character.
- Destination: `C_Map.SetUserWaypoint` + `C_SuperTrack`, falling back to the parent zone when the map does not allow user waypoints; optional TomTom waypoint.
- Must work in combat and inside instances with no taint warnings (checked with `/console taintLog 1`).

## Localization

`Locales/enUS.lua` defines every text in `ns.L` (English base); `Locales/esES.lua` overrides what it translates for esES and esMX. A key missing everywhere shows the key itself. Both files load first in the `.toc`. Unit tests check that every `L.KEY` used in the code exists in English and that translations keep the same placeholders (`%s`, `%d`).

- `ns.KeyName("ALT")` / `("CTRL")`: modifier names as on the player's keyboard (Option and Cmd on Mac).
- `ns.Words(key)`: search words for a filter or category: the English list (`ns.W_EN`) plus the player's language (`ns.W`), lowercase, without repeats. English words always work in every language.
- Slash subcommands stay in English.

## Quality checks

- `npm run check:lua` — compiles every `.lua` with LuaJIT (syntax, 200-locals limit) and runs full luacheck (`.luacheckrc` lists the WoW globals in use).
- `npm test` — unit tests with busted (`spec/`). Every piece of pure logic (normalization, query parsing, matching and scoring, merging, migrations) has tests; `spec/helpers/wow.lua` loads addon files the way the game does and stubs the few WoW functions they need. What is visual is tested in the game.
- Both run in GitHub on every pull request; `main` requires them to pass.

## Forever client API

Audited in game (#20) on **WoW Forever 1.60.1 (build 71139)**, `toc=16001`, `WOW_PROJECT_ID=18`, esES client, from Ironforge, plus every zone of Kalimdor and the Eastern Kingdoms asked by mapID. The audit commands are kept in `dev/audit/` to repeat it on other clients (Retail, Classic: milestone 4.0).

**Summary:** the client is modern (Settings, MenuUtil, ScrollBox, user waypoints and super-track, `C_XMLUtil`, `C_AddOns`); only pre-Dragonflight globals are missing. But several live APIs exist and **return nothing** in Forever: dungeon entrances, area POI events, map links and world quests. That content needs static data.

`ns.Caps` (`Core/Caps.lua`) also has `flavor` (`forever`, `retail`, `classic`, from `WOW_PROJECT_ID`: only to pick data packs) and `build`; `/ms diag` prints them all.

| API / feature | Forever | `ns.Caps` flag | Notes |
|---|---|---|---|
| `Settings.RegisterCanvasLayoutCategory`, `RegisterAddOnCategory`, `OpenToCategory` | ✅ | `settings` | Options panel (#49). `InterfaceOptions_AddCategory` is **missing**: no fallback needed |
| `MenuUtil.CreateContextMenu` | ✅ | `menuUtil` | `EasyMenu` is **missing**; `UIDropDownMenu_Initialize` exists |
| Templates: `SearchBoxTemplate`, `InputBoxTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `SettingsCheckboxControlTemplate`, `WowScrollBoxList`, `MinimalScrollBar`, `BackdropTemplate`, `TooltipBackdropTemplate` | ✅ | `searchBox` (only `SearchBoxTemplate`) | Checked with `C_XMLUtil.GetTemplateInfo` |
| `CreateFramePool`, `CreateObjectPool`, `CreateScrollBoxListLinearView`, `EventRegistry` | ✅ | — | |
| `C_Map` (`GetMapInfo`, `GetMapChildrenInfo`, `GetAreaInfo`, `GetMapGroupMembersInfo`, `GetMapInfoAtPosition`, world/map position conversion) | ✅ | — | Map tree: Azeroth (947) → Kalimdor, Eastern Kingdoms, Zephras Isle. Includes Forever-only zones (Mount Hyjal 2482, Shen'dralas 2652, Riverglen 2548, Blackspear Islands 2524) |
| `C_Map.SetUserWaypoint`, `CanSetUserWaypointOnMap`, `GetUserWaypointHyperlink`, `C_SuperTrack.SetSuperTrackedUserWaypoint` | ✅ | `userWaypoint`, `superTrack` | Waypoints allowed on zone, continent and world maps; chat link `\|Hworldmap:1455:5000:5000\|h` works |
| `C_Navigation.GetDistance` | ✅ | — | |
| `C_TaxiMap.GetTaxiNodesForMap` | ⚠️ partial | `taxi` | Works outside the flight window, but returns **all nodes of the continent** for a zone map (Kalimdor 38, Eastern Kingdoms 36), with positions relative to the asked map, and `state = nil` (known/unknown not available). Nodes must be assigned to their zone by position (cities overlap their zone, so a bounds check is not enough). Known nodes: cache on `TAXIMAP_OPENED` (#43) |
| `C_TaxiMap.GetAllTaxiNodes` | ⚠️ | — | Returns 0 outside the flight window |
| `C_EncounterJournal.GetDungeonEntrancesForMap` | ❌ empty | `dungeonEntrances` | Exists but returns **0 entrances in all 53 zones**: dungeons and raids need static data (#42). `EJ_GetInstanceInfo` exists |
| `C_AreaPoiInfo.GetAreaPOIForMap` / `GetAreaPOIInfo` | ⚠️ almost empty | `areaPOI` | Only capital city labels on continent/world maps and 4 POIs in the Blackspear Islands (no atlas). Little value in Forever (#77) |
| `C_AreaPoiInfo.GetEventsForMap` | ❌ empty | `areaPOIEvents` | 0 events in every zone |
| `C_Map.GetMapLinksForMap` | ❌ empty | `mapLinks` | 0 links: portals need static data (#80) |
| `C_VignetteInfo` (`GetVignettes`, `GetVignetteInfo`, `GetVignettePosition`) | ✅ (untested in the field) | `vignettes` | 0 vignettes in Ironforge, as expected in a city; to check near rares/treasures (#78) |
| `C_QuestLog` (`GetNumQuestLogEntries`, `GetInfo`, `GetQuestsOnMap`, `GetNextWaypoint`, `GetQuestObjectives`, `GetTitleForQuestID`, `IsComplete`) | ✅ | `questLog` | `GetQuestsOnMap` returns quest IDs (1 in Ironforge, 12 on the Eastern Kingdoms map). Old `GetNumQuestLogEntries`/`GetQuestLogTitle` globals are **missing** |
| `C_TaskQuest.GetQuestsOnMap` | ❌ empty | `taskQuest` | Exists, returns 0 (no world quests in Forever). `GetQuestsForPlayerByMapID` is missing |
| `C_Calendar` (`OpenCalendar`, `GetMonthInfo`, `GetNumDayEvents`, `GetDayEvent`, `GetHolidayInfo`) | ✅ | — | Checked for #147 (27/11/2026): holidays come as `calendarType = "HOLIDAY"` with the `Holidays` table ID as `eventID` (Hallow's End 324, Darkmoon Faire 263/264, Call to Arms 1840–1842...). Loaded in the background after `OpenCalendar` (`CALENDAR_UPDATE_EVENT_LIST`); only the current and next month have events |
| `C_AddOns` (`LoadAddOn`, `GetAddOnMetadata`, `IsAddOnLoaded`, `IsAddOnLoadOnDemand`, `GetAddOnInfo`) | ✅ | `loadOnDemand` | LoadOnDemand data packs and `## X-MapScout-Provider` discovery are possible |
| `C_Timer.NewTimer`, `debugprofilestop`, `GetAddOnMemoryUsage`, `UpdateAddOnMemoryUsage` | ✅ | — | Debounce and cost measurement |
| `WorldMapFrame` (`ScrollContainer`, `BorderFrame`, `BorderFrame.MaximizeMinimizeFrame`, `SidePanelToggle`, `SetMapID`, `GetMapID`, `pinPools`) | ✅ | — | |
| `TomTom` | ⚠️ | — | Present as a table when **Bridge** is loaded: Bridge defines a fake `TomTom` (`TomTom.isBridge`) when the real one is missing. Treat both the same (its `AddWaypoint` turns into a Bridge stop) |

### Services in Forever

According to Daniel (from playing it; not yet checked against data), Forever has all the services in the plan (confirmed again by Daniel for #47), so the static data packs cover them all: banks, auction houses, mailboxes, innkeepers, repair vendors, stable masters, class/profession/riding/weapon trainers, **barbers**, **transmogrifiers**, **crafting stations** (anvils, forges and others), **faction/reputation quartermasters** and **guild banks**. Barbers, transmogrifiers (only three: Stormwind, Orgrimmar and Dalaran), guild masters, battlemasters, anvils and forges are in `Services.lua` (#47). Forever has **no training dummies** in its cities (they came with Wrath of the Lich King; none found in Ironforge or Stormwind, 27/11/2026), so they are not offered. Guild banks are recorded by the harvest mode when met, with no trips on purpose; quartermasters come from QuestieDB's NPC titles at runtime. Retail-only services (Catalyst, crafting orders) are still left to 4.0. Forever-only services, if any, are added when found (harvest mode, #40).
