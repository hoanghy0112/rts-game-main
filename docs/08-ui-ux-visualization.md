# 08 - UI/UX và hiển thị bản đồ

## Design principles

UI phải đơn giản, sạch, không dùng gradient trang trí, không "AI Slop".

Ưu tiên:

- dense but readable;
- military staff/map-room feel;
- thông tin trực tiếp trên bản đồ;
- panel ít chữ thừa;
- icon/flag/overlay rõ nghĩa;
- trạng thái có uncertainty;
- zoom mượt từ macro tới camp.

Không làm:

- hero/landing page;
- card lồng card;
- decorative blobs/orbs;
- gradient background;
- icon vô nghĩa;
- pop-up giải thích dài dòng;
- text che map hoặc overlap nhau.

## Visual asset direction

Art direction đã chốt theo hướng unified 3D/2.5D strategy, không dùng hand-drawn art làm pipeline chính.

Asset rules:

- dùng model/pack từ các marketplace asset lớn sau khi kiểm tra license, provenance và khả năng import vào Godot;
- ưu tiên cùng vendor/series/style pack để giữ thống nhất về scale, vật liệu, texel density, palette và mức stylization;
- terrain, công trình, trại, cầu, thuyền, xe kéo, vũ khí lớn và props dùng 3D model hoặc 2.5D billboard/render từ 3D;
- unit/army ở zoom xa dùng flag, marker, marching-column proxy hoặc impostor dựa trên asset catalog, không render từng lính bằng sprite hand-drawn;
- UI icon cho gameplay entity nên lấy từ render/icon atlas sinh từ model hoặc hệ icon UI nhất quán; không trộn nhiều style minh họa;
- mọi asset được gọi qua semantic asset ID trong `asset_catalog.json`, không tham chiếu path trực tiếp từ gameplay code.

## Main screen

Main screen hiển thị:

- bản đồ lớn;
- top status bar;
- left command panel;
- right report panel;
- bottom timeline/order queue;
- contextual inspector khi chọn entity.

V1 HUD implementation uses a battle-command layout:

- left command groups are accordion sections for time, orders, map/overlay and objectives;
- right intelligence groups are accordion sections for reports, forecast and legend;
- bottom strip contains commander badge, unit cards and command status;
- minimap is always visible in the lower-right corner;
- unit cards use compact morale bars and faction colors.

Top bar:

| Indicator | Display |
|---|---|
| date/season | compact text |
| speed | segmented control |
| rice | number + trend |
| water | warning only if constrained |
| gold | number |
| army supply days | worst/median |
| unstable regions | count |
| active battles | count |
| critical reports | count |

## Map overlays

Overlay toggles:

- terrain defense;
- logistics suitability;
- road condition;
- supply routes;
- weather/mud;
- region control;
- unrest/bandit risk;
- resource potential;
- burned/damaged land;
- intel confidence.

No overlay should hide core map completely. Use restrained colors, line styles, hatching, flags.

V1 map-mode buttons:

| Mode | Purpose |
|---|---|
| `terrain` / `3D` | default oblique 2.5D view with terrain mesh, scenery props, armies, camps, routes and weather |
| `topographic` | macro planning view with contour lines, restrained terrain tint, water/rice symbols and fewer close-zoom props |
| `resources` | resource-potential view with colored disks and labels for rice, wood, iron, salt and water |
| `population` | settlement/population view with village disks and population labels |
| `military` | army, stronghold, blockade and command-marker view |

HUD legend must change with the active mode so colors are readable without opening documentation.

## Map editor UI

V1 editor is opened from map setup and stays on the same 2.5D map renderer.

Editor controls:

- brush mode: terrain, resource, flow, infrastructure;
- terrain brush: paddy field, forest, dense forest, hill, mountain, wetland, river, plain, dry field;
- resource brush: rice, wood, iron, salt, water;
- flow brush: direction in degrees and strength saved as `flow_vectors`; water animation reads these vectors;
- infrastructure brush: village granary, road marker, bridge site, watch post, depot site; close zoom renders matching 3D markers;
- climate/wind setup: wind direction, rainfall and wind intensity saved into map manifest and used by runtime weather/rain visuals;
- save control: writes a neutral map pack to `user://saved_maps/<folder>`.
- load controls on setup screen can reopen saved maps for play or further editing.

Editor actions mutate the map pack through `MapEditorController`; UI does not edit dense layers or feature arrays directly.

## Flags and markers

Use flags as primary indicators:

- faction flag for armies;
- small pennants for patrols;
- depot banner with category stripe;
- warning pennant for threatened route;
- smoke/damage mark for burned area;
- broken bridge drawing on actual bridge;
- red/black crossed route line for blocked supply.

Marker state:

```text
Marker {
    icon;
    faction_color;
    confidence_style;
    status_style;
    stale_age;
}
```

Confidence styles:

- solid: high confidence;
- dashed outline: medium;
- faded/blurred area: low;
- timestamp marker: stale.

## General reports

Report statuses:

- Stable;
- Threatened;
- Critical;
- At War;
- Collapse Risk;
- Unknown/Stale.

Report card content:

- general portrait/name if known;
- assigned camp/army;
- status;
- confidence;
- last updated;
- top reason: "Water shortage", "Enemy near route", "Road cut", "Depot overloaded";
- action button: inspect, send supplies, reinforce, change order.

Accuracy depends on intelligence. UI must show confidence, not pretend all reports are exact.

Report accuracy display:

```text
confidence_percent = round(100 * intel_confidence)
```

If confidence low:

- avoid exact numbers;
- show ranges;
- mark enemy locations as approximate.

## Zoom levels

### Macro zoom

Shows:

- regions;
- major rivers;
- major roads;
- armies as flags;
- depots as warehouse markers;
- active fronts;
- weather cells.

### Operational zoom

Shows:

- camps;
- route segments;
- road condition;
- resource zones;
- patrol coverage;
- siege arcs;
- bridge/ford/dock.
- battlefield camera uses a lower perspective angle so hills, formations, flags and roads read more like a tactical field instead of a flat board.

### Tactical camp zoom

Shows:

- camp footprint;
- trenches/ramparts;
- storage buildings;
- local water source;
- formation positions;
- construction projects;
- burned fields/damaged roads.

No scene transition/loading. It is still the same map.

## Placement UI

For free-form placement:

1. player selects structure/order;
2. cursor previews footprint;
3. terrain score ring updates live;
4. route links preview if relevant;
5. resource/manpower cost shown compactly;
6. warnings shown as icons, not long text;
7. click confirms.

Placement preview metrics:

- defense;
- logistics;
- build difficulty;
- flood risk;
- concealment;
- water access;
- road access.

Metric style:

```text
0.00..0.33 = poor
0.34..0.66 = usable
0.67..1.00 = strong
```

## Route drawing UI

Player manually maps route:

- click source depot;
- draw path by waypoints or auto-snap to road/river;
- click target camp/depot;
- choose priority/resource;
- assign guards/transport.

Route preview:

- ETA;
- throughput/day;
- risk;
- weather vulnerability;
- guard coverage;
- expected loss/month.

Route line styles:

- solid: safe;
- dashed: low confidence or poor road;
- red segments: enemy/bandit risk;
- blue segments: water route;
- broken segment: destroyed bridge/road.

## Construction UI

Construction panel must show:

- required resources;
- manpower assignment;
- build time;
- combat readiness penalty if using soldiers;
- weather risk;
- expected maintenance.

Manpower assignment controls:

- civilians;
- engineers;
- regular army;
- pause/resume;
- priority.

## Combat and siege UI

Siege view overlays:

- stronghold supply entries;
- covered arcs by siege camps;
- route blockade strength;
- defender estimated supply days;
- assault score range;
- pursuit policy per camp.

Direct assault UI must show uncertainty:

```text
Assault estimate: Risky
Confidence: 62%
Reasons: wall intact, rain, defender morale unknown
```

It must not show fake precision if intel is low.

## Visualizing map damage

Damage is not just icons.

Examples:

- burned rice fields: darker/charred field texture on terrain;
- scorched forest: thinned tree overlay and dark ground;
- destroyed bridge: bridge mesh broken, road route interrupted;
- damaged road: rough/dark segment, lower road condition;
- collapsed depot: damaged footprint and scattered goods marker;
- flooded areas: water overlay along low terrain.

## Accessibility and readability

Minimum:

- all critical states have shape/icon, not color only;
- text never overlaps panels;
- UI scale options;
- pause speed available;
- keyboard shortcuts for common overlays;
- colorblind-safe palette for faction/route danger.

## Debug UI for development

Required debug overlays:

- selected formula breakdown;
- route cost components;
- morale components;
- depot spoilage components;
- report accuracy hidden truth vs reported value;
- chunk/LOD boundaries;
- simulation tick time.

## Acceptance criteria

- Player can understand why a camp is threatened in under 10 seconds.
- Player can draw a supply route and see risk/throughput immediately.
- Zooming changes detail level without loading screen.
- Burned roads/fields/bridges are visible on the map itself.
- Reports show uncertainty tied to intelligence.
- UI remains legible at 1366x768 and 1920x1080.
