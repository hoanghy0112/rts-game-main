# 02 - Kiến trúc game

## Nguyên tắc

1. Gameplay core tách khỏi rendering.
2. Mọi hệ thống có công thức và tham số rõ ràng.
3. Scenario/map/faction/unit phải data-driven.
4. Bản đồ là một thế giới liên tục, nhưng runtime load theo chunk.
5. Simulation tick cố định, render frame độc lập.
6. Không dùng scene node làm nguồn sự thật cho unit/logistics/economy.
7. Dữ liệu lịch sử có source và độ tin cậy.
8. Không hard-code asset path, magic number, tham số balance hoặc global gameplay setting trong core code.
9. Asset, công thức, bảng balance và global config phải đi qua registry/schema tập trung.
10. Logic có nhiều state, source hoặc formula variant phải dùng pattern rõ ràng như State, Strategy, Adapter hoặc Command thay vì nhánh điều kiện lan rộng. Chi tiết ở [13 - Clean code và design patterns](13-clean-code-design-patterns.md).

## Module runtime

```text
GameRoot
├── AppState
├── SimulationHost
│   ├── TimeSystem
│   ├── WeatherSystem
│   ├── TerrainSystem
│   ├── EconomySystem
│   ├── LogisticsSystem
│   ├── HomefrontSystem
│   ├── MilitarySystem
│   ├── CombatSystem
│   ├── SiegeSystem
│   ├── DiplomacySystem
│   ├── IntelligenceSystem
│   └── AiDirector
├── MapRenderer
│   ├── ChunkStreamer
│   ├── TerrainMeshLayer
│   ├── RoadRiverLayer
│   ├── ResourceOverlayLayer
│   ├── DamageOverlayLayer
│   └── FlagMarkerLayer
├── UiShell
│   ├── TopStatusBar
│   ├── RegionInspector
│   ├── GeneralReportPanel
│   ├── LogisticsPanel
│   ├── ConstructionPanel
│   └── DiplomacyPanel
└── ToolingDebug
    ├── FormulaInspector
    ├── PathDebugOverlay
    ├── WeatherDebugOverlay
    └── PerfCounters
```

## Đề xuất cấu trúc thư mục

```text
project/
├── game/
│   ├── project.godot
│   ├── scenes/
│   ├── scripts/
│   │   ├── sim/
│   │   ├── runtime/
│   │   ├── render/
│   │   ├── ui/
│   │   └── tests/
│   ├── assets/
│   └── addons/
├── content/
│   ├── common/
│   │   ├── assets/
│   │   ├── formulas/
│   │   ├── balance/
│   │   └── globals/
│   ├── maps/
│   ├── scenarios/
│   ├── factions/
│   ├── units/
│   ├── equipment/
│   └── sources/
├── docs/
└── tools/
    ├── map_generator/
    ├── map_compiler/
    ├── map_adapters/
    ├── scenario_validator/
    └── balance_runner/
```

Trong repo hiện tại mới có docs. Cấu trúc trên là target sau phase 1.

## Registry và cấu hình tập trung

Gameplay core chỉ nhận dữ liệu đã validate từ content/config registry. Code không tự tra trực tiếp `res://...`, không tự nhúng số tuning và không tự tạo default gameplay tùy tiện.

Registry tối thiểu:

```text
content/common/
├── assets/
│   ├── asset_catalog.json
│   ├── visual_style.json
│   └── import_profiles.json
├── formulas/
│   ├── movement.json
│   ├── weather.json
│   ├── economy.json
│   ├── logistics.json
│   └── combat.json
├── balance/
│   ├── units.json
│   ├── buildings.json
│   ├── resources.json
│   └── terrain.json
└── globals/
    ├── simulation.json
    ├── renderer.json
    ├── camera.json
    └── ui.json
```

Quy tắc:

- gameplay systems dùng semantic IDs như `unit.infantry_column`, `asset.army.flag.faction_a`, `formula.movement.base_speed`, không dùng path/string rải rác;
- renderer là lớp duy nhất resolve asset ID sang Godot resource path;
- formula code nhận named parameters từ registry và phải fail fast nếu thiếu key bắt buộc;
- mọi config có schema, default, min/max và version;
- scenario/mod chỉ override data qua manifest, không sửa logic core;
- hằng số toán học hoặc unit conversion có thể nằm trong code, nhưng mọi giá trị gameplay/balance phải nằm trong config.

## Tick và vòng đời frame

Simulation chạy fixed tick, render chạy theo frame.

Default:

- render: uncapped hoặc 60 FPS target;
- simulation: 10 ticks/second ở chiến lược;
- tactical local steering: 20 ticks/second khi có combat gần camera;
- economy/weather: update theo giờ/ngày in-game, nhưng được chia nhỏ vào tick.

Pseudo-loop:

```text
while accumulator >= sim_dt:
    read_queued_player_orders()
    simulation_tick(sim_dt)
    produce_render_snapshot()
    accumulator -= sim_dt

render(interpolate(previous_snapshot, current_snapshot, alpha))
```

`sim_dt = 0.1 seconds real-time` ở 1x.

## Tọa độ thế giới

Simulation dùng tọa độ mét trong hệ quy chiếu cục bộ của map.

```text
WorldPos {
    double x_m;
    double y_m;
    double elevation_m;
}
```

Render dùng chunk-relative float:

```text
RenderPos = WorldPos - CameraFloatingOrigin
```

Lý do:

- map generated v0 nhỏ, nhưng format phải scale được lên map lớn sau này;
- adapter khu vực sau v0 có thể tạo map dài hàng triệu mét;
- float 32-bit có thể gây jitter khi camera zoom sâu;
- simulation cần khoảng cách/độ dốc/route cost ổn định.

## Entity model

Gameplay entity không phải Godot node.

Entity chính:

- `Faction`
- `Region`
- `Settlement`
- `ResourceSite`
- `RoadSegment`
- `RiverSegment`
- `Depot`
- `Camp`
- `Army`
- `Formation`
- `UnitIndividual`
- `General`
- `ConstructionProject`
- `SupplyRoute`
- `RefugeeGroup`
- `DiplomaticAgreement`
- `WeatherCell`
- `MapChunk`

Mỗi entity có:

```text
EntityId id;
EntityType type;
Version version;
```

## Tầng mô phỏng unit

Không render từng cá nhân ở mọi zoom. Dùng 3 tầng:

1. **Individual record**
   - courage, loyalty, intelligence, strength, health;
   - equipment assignment;
   - squad membership;
   - training history.

2. **Formation aggregate**
   - count;
   - average stats;
   - stat variance;
   - equipment mix;
   - current order;
   - supply state.

3. **Visual proxy**
   - flag;
   - marching column;
   - camp icon;
   - low-count unit silhouettes only near camera.

Khi unit chuyển squad, individual stat đi theo record, không bị reset.

## Map chunking

Mỗi map được chia:

- chunk cấp macro: 64 km x 64 km;
- chunk cấp operational: 8 km x 8 km;
- chunk cấp tactical: 1 km x 1 km hoặc nhỏ hơn ở vùng quan trọng.

Default target:

| LOD | Kích thước | Nội dung |
|---|---:|---|
| LOD0 | 64 km | terrain color, rivers major, region borders |
| LOD1 | 8 km | roads, forests, rice paddies, depots, camps |
| LOD2 | 1 km | local slope, bridge, trench, fort footprint |
| LOD3 | 250 m | chỉ quanh camera/combat |

## Snapshot render

Simulation không gửi object sống sang renderer. Nó gửi snapshot:

```text
RenderSnapshot {
    tick_id;
    visible_chunks;
    army_markers;
    camp_markers;
    depot_markers;
    road_conditions;
    weather_overlays;
    terrain_damage_overlays;
    reports;
}
```

Renderer dùng snapshot để vẽ flags, roads, burned areas, scorched forest, destroyed bridges.

## Save/load

Save chia làm 3 phần:

1. Static content references:
   - map id;
   - scenario id;
   - content version.

2. Mutable simulation state:
   - entities;
   - resources;
   - weather state;
   - route assignments;
   - current orders.

3. Replay metadata:
   - RNG seed;
   - command log hash;
   - game speed settings.

## Determinism

Mục tiêu v1: deterministic enough for replay/debug, chưa cần multiplayer.

Quy tắc:

- mọi random dùng seeded RNG;
- không dùng `DateTime.Now` trong simulation;
- không dùng frame delta trực tiếp;
- không phụ thuộc thứ tự dictionary không ổn định cho combat result;
- floating point cho rendering; simulation quan trọng có thể dùng fixed decimal hoặc double nhất quán.

## Testing strategy

Clean-code checklist cho phase đầu nằm ở [13 - Clean code và design patterns](13-clean-code-design-patterns.md). Dependency injection là mặc định cho simulation systems; State Pattern dùng cho lifecycle phức tạp như app state, army order, construction và weather cell; Adapter Pattern dùng cho map source, asset/resource lookup, save migration và external data trước khi dữ liệu đi vào core.

### Unit tests

- morale formula;
- spoilage formula;
- tax/happiness formula;
- route cost;
- encirclement score;
- report accuracy.

### Golden tests

- cùng seed + cùng command log phải ra cùng snapshot hash;
- map generator/compiler tạo cùng chunk metadata;
- scenario validator phát hiện missing source/history references.

### Simulation benchmarks

- 1.000, 5.000, 10.000 formations;
- 100, 1.000, 10.000 supply routes;
- 1, 10, 100 simultaneous sieges;
- whole-day weather update.

### Playtest metrics

- thời gian người chơi hiểu tình trạng logistics;
- số click để tạo route kho -> camp;
- số lần báo cáo tướng sai/đúng theo intelligence;
- FPS khi zoom macro và zoom camp.
