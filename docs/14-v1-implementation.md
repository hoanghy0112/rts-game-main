# 14 - V1 implementation notes

## Scope delivered

V1 in this repository is a playable generated-map sandbox, not a historical Vietnam campaign.

Implemented:

- Godot 4.6.3 local binary under `tools/godot/`;
- fixed-tick `SimulationHost` separated from scene rendering;
- central JSON content/config registry under `src/content/`;
- deterministic generated map pack path with save/load validation, including bounds/resource checks plus editor-authored flow vectors and infrastructure;
- Vietnamese playable UI with main menu, map setup screen, in-game status bar, accordion command panel, report accordions, bottom unit-card strip, minimap and forecast;
- map editor screen reachable from setup, with brushes for terrain, resources, river-flow direction and default infrastructure plus climate/wind controls;
- setup screen can load a previously saved `user://saved_maps/<folder>` map into gameplay or back into the editor;
- `AppStateMachine` for boot/menu/setup/loading/in-game/paused/error flow;
- `PlayerCommandFacade` with injected action classes for player commands instead of UI mutating simulation directly;
- typed domain object classes for people, livestock, supplies, boats, depots, camps, armies, routes and strongholds, with adapters from the v1 DTO state;
- `RenderSnapshotBuilder` creates read-only render/UI DTOs from simulation state;
- pan/zoom continuous 3D strategy map with terrain, rivers, roads, resources, depots, camps, armies, routes and siege ring;
- desktop starts fullscreen and uses the Forward+ renderer, with responsive HUD layout over the world view;
- camera uses a lower perspective battlefield angle closer to Total War-style tactical framing while preserving map pan/zoom and editor picking;
- natural generated terrain defaults to a 32x24 km mountain-valley-delta map with ridges, hills, valleys, main river, tributaries, villages and rice belts around water instead of square resource blocks;
- terrain is rendered as an elevation mesh, with contour lines for macro/topographic reading and raised 3D terrain at close zoom;
- close zoom shows procedural low-poly 3D models for trees, paddy fields, river reeds, boulders, village houses, civilians, livestock, river boats with boatmen, camps, depots, animated flags, strongholds and siege camps;
- armies render as small low-poly 3D formation groups with soldiers, spears/shields, cavalry riders, banners and morale bars instead of single map pins;
- rivers use curved Catmull-Rom meshes with variable width, shoreline banks, foam strips and animated water shaders; editor-authored flow vectors drive extra water streaks, and weather/props continue animating independently of the fixed simulation tick;
- climate/wind saved in the map manifest seeds runtime weather and drives rain direction in the renderer;
- editor-authored infrastructure is rendered as 3D bridge/watch-post/road/depot/granary markers at close zoom;
- map modes include terrain/3D, topographic, resources, population and military, with HUD legends for resource and terrain colors;
- weather visualization includes animated rain streaks and wet/flood tint while weather still affects gameplay formulas;
- logistics: depot construction, manual routes, throughput, ETA, route risk, guard effect, camp rice/water consumption, spoilage, gunpowder wetness/misfire risk and bandit loss;
- economy/home front: tax, happiness/support, recruit quality, report accuracy, refugees from combat pressure;
- weather: rain, mud, flood, storm halt, heat stress by faction sensitivity and 1-3 day forecast;
- warfare: terrain combat, coherent spearmen vs cavalry, cavalry penalties in paddy/forest/mud, rout/desertion pressure, report uncertainty;
- siege: free placement of siege camps, encirclement score, blockade, defender supply/morale attrition and surrender chance;
- construction: depot and bridge/road repair work points;
- data-driven scenario objectives and optional firearm disable flag;
- clean render layer boundaries: terrain mesh, contour, features, environment props, entity markers, weather and camera rig;
- `.gitignore`, run/test/build helper scripts and README instructions.

## Runtime controls

- Mouse wheel zooms.
- Middle mouse drags camera.
- Arrow keys pan.
- `Space` pauses.
- `1..4` set simulation speed.
- `L`, `M`, `R`, `I` toggle route, weather, road and debug grid overlays.
- HUD map-mode buttons switch terrain/3D, topographic, resources, population and military views.
- `D` creates a forward depot.
- `S` places the next siege camp.
- `C` resolves the sample combat.

The left UI panel exposes the same key sandbox commands.

## Test coverage

The Godot headless runner covers:

- content/schema validation;
- generated map determinism and map pack save/load/reload;
- validator rejection for malformed/out-of-bounds map features;
- generated-map realism smoke coverage for strategic size, flow vectors, scattered villages and rice belts;
- map editor brush coverage for terrain/resource/flow/infrastructure/climate;
- editor-saved map pack reload validation;
- loading saved map packs into runtime by folder name;
- fixed tick time advance and pause;
- same seed plus same command log state hash;
- route risk, guard reduction, weather throughput and road damage/repair;
- camp rice/water shortage morale and health loss;
- depot spoilage and gunpowder misfire risk;
- livestock slaughter and meat gain;
- tax income, happiness/support, recruit quality and report accuracy;
- heat penalty differences between climate-sensitive formations;
- storm halt movement factor;
- spearmen/cavalry and terrain combat formulas;
- siege encirclement, blockade attrition and objective completion.
- domain object factory coverage for livestock/person objects;
- injected action facade smoke coverage;
- render snapshot and 3D renderer smoke coverage, including map-mode switching;
- `GameRoot` start/pause flow smoke coverage.

Current local run:

```text
Headless tests complete: 87 checks, 0 failures
```

Run with:

```bash
./scripts/test.sh
```

## Known boundaries

- Visual assets are repo-owned procedural low-poly 3D models using Godot primitive meshes. Marketplace 3D/2.5D art remains a future asset-sourcing phase and should be resolved through semantic asset IDs/catalog metadata.
- The current renderer is a polished procedural 2.5D vertical slice, not licensed Total War-quality marketplace art. The code is structured so future marketplace models can replace procedural meshes through the render/model factory and asset catalog path.
- V1 does not include the Vietnam GIS adapter or strict historical campaign content.
- Full executable export requires Godot export templates. The included build script validates project packaging by exporting a `.pck`.
