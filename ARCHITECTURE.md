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
    Geography.lua Instances.lua Taxi.lua Transport.lua Services.lua Quests.lua
    AreaPOI.lua Vignettes.lua Portals.lua
  UI/
    SearchBar.lua              # edit box + gear button anchored to WorldMapFrame
    Results.lua                # pooled rows, groups "In this zone" / "Elsewhere"
    Preview.lua                # hover marker on the map canvas (own frames)
    Menu.lua                   # right-click menu (MenuUtil) and row action buttons
    Waypoint.lua               # C_Map.SetUserWaypoint + super-track, optional TomTom
  Options/
    Panel.lua                  # Settings canvas category (fallback if missing)
MapScout_Data_Forever/         # LoadOnDemand static data packs (data-only providers), one file per category
MapScout_<Addon>/              # LoadOnDemand adapters for addons that don't integrate themselves (3.0)
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
- **Errors.** Every call into a provider or action runs in `xpcall`; after 3 errors in a session the provider is disabled for the session and reported once in chat.
- **Actions.** Any addon can add actions to **any** result (`RegisterResultAction`): menu entries, optional row buttons and submenus (e.g. Bridge: "Add to current route", "Add to a saved route").

The full public contract (functions, result fields, events, versioning) is in `API.md` (#70); the agreed design is in epics #95 and #7.

### Result fields (summary)

`id` and `name` are required; `mapID`, `x`, `y` (uiMapID and 0–1 coordinates) for anything that has a place. Optional: `category`, `subtitle`, `keywords`, `icon`, `weight`, `data` (opaque, for the provider's own actions). MapScout adds `provider`, `zoneName`, `continentID` and a stable `key` used by favorites, aliases, blacklist and frequency. Results handed to other addons are copies.

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

In this order of preference:

1. **Live game APIs** — nothing stored. `C_Map` (map tree, subzone names), `C_EncounterJournal.GetDungeonEntrancesForMap`, `C_TaxiMap`, `C_QuestLog`, `C_AreaPoiInfo`, `C_VignetteInfo`, later `C_TaskQuest` (Retail). Every live provider checks `ns.Caps` first and is hidden from the options when its API is missing.
2. **The Forever client's own data files** — DB2 tables of the installed build (UiMap, UiMapAssignment, AreaTable, AreaPOI, TaxiNodes, JournalInstance…), converted by our generator in `dev/tools` (#38). Native and ours.
3. **Our in-game harvest mode** — positions of NPCs and objects recorded when interacting with them (#40). Ours.
4. **External sources with a public API** whose terms allow the use, each checked first (#104).
5. **Never** other addons' databases (Questie, HandyNotes, EasyFind…): they have their own licences. They can only be read at runtime by optional adapters, or better, register themselves as providers.

### Static data packs

What the client cannot tell us at runtime (NPC services, mailboxes and other objects, transport docks and destinations, portals and destinations, world bosses, subzone centres) lives in `MapScout_Data_Forever`, a LoadOnDemand addon with one file per category. The packs are data-only providers.

- Loaded with `C_AddOns.LoadAddOn` only when the first enabled category needs it; disabled categories are never built.
- Compact format per uiMapID, coordinates as integers 0–10000: `[1453] = { "bank", 6270, 7310, npcID, … }`.
- Names: types from `L`; NPC and area names from the client when possible, with the English name stored as fallback.
- Files start with a "Generated, do not edit" header with the source build.

## Persistence

| SavedVariable | Scope | Contents |
|---|---|---|
| `MapScoutDB` | Account | `schema`, `options` (providers and categories, waypoint preferences, bar position and scale, result cap), `aliases`, `blacklist`, `favorites`, `frequency` |
| `MapScoutCharDB` | Character | `schema`, `history` (recent searches), per-character caches (e.g. known flight paths) |

`Core/DB.lua` merges defaults without overwriting user values and runs ordered migrations `migrations[n](db)` up to the current `SCHEMA` on `ADDON_LOADED`. Data from a newer, unknown schema is left untouched (read-only) with one warning.

## Integration with the world map

- MapScout's frames are parented to `WorldMapFrame` (or its border frame) and anchored; they adapt to the maximized and minimized map.
- Hooks: `OnShow`/`OnHide` of the map and `hooksecurefunc` on map changes. No `SetScript` on Blizzard frames (it would also wipe other addons' hooks).
- The hover marker and highlights are MapScout's own frames over the map canvas, not map pins.
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
| `C_AddOns` (`LoadAddOn`, `GetAddOnMetadata`, `IsAddOnLoaded`, `IsAddOnLoadOnDemand`, `GetAddOnInfo`) | ✅ | `loadOnDemand` | LoadOnDemand data packs and `## X-MapScout-Provider` discovery are possible |
| `C_Timer.NewTimer`, `debugprofilestop`, `GetAddOnMemoryUsage`, `UpdateAddOnMemoryUsage` | ✅ | — | Debounce and cost measurement |
| `WorldMapFrame` (`ScrollContainer`, `BorderFrame`, `BorderFrame.MaximizeMinimizeFrame`, `SidePanelToggle`, `SetMapID`, `GetMapID`, `pinPools`) | ✅ | — | |
| `TomTom` | ⚠️ | — | Present as a table when **Bridge** is loaded: Bridge defines a fake `TomTom` (`TomTom.isBridge`) when the real one is missing. Treat both the same (its `AddWaypoint` turns into a Bridge stop) |

### Services in Forever

According to Daniel (from playing it; not yet checked against data), Forever has all the services in the plan, so the static data packs cover them all: banks, auction houses, mailboxes, innkeepers, repair vendors, stable masters, class/profession/riding/weapon trainers, **barbers**, **transmogrifiers**, **training dummies**, **crafting stations** (anvils, forges and others), **faction/reputation quartermasters** and **guild banks**. Retail-only services (Catalyst, crafting orders) are still left to 4.0. Forever-only services, if any, are added when found (harvest mode, #40).
