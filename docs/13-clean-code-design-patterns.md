# 13 - Clean code và design patterns

## Mục tiêu

Tài liệu này chốt chuẩn code để logic, công thức và tham số gameplay có thể thay đổi trong tương lai mà không phải sửa lan rộng trong core.

Nguyên tắc chính:

- code mô phỏng giữ thuật toán và lifecycle;
- content/config giữ số balance, ngưỡng, modifier, ID và rule variant;
- runtime nhận dependency đã validate, không tự đọc singleton/global tùy tiện;
- renderer, Godot scene, map source, save file và external tool đi qua adapter;
- khi logic có nhiều trạng thái hoặc biến thể công thức, ưu tiên pattern rõ ràng thay cho chuỗi `if/elif` dài.

## Ranh giới kiến trúc

Target dependency direction:

```text
Godot scenes/UI/renderer
        ↓
Runtime orchestration
        ↓
Simulation systems
        ↓
Domain models + formula interfaces
        ↑
Validated content/config registries
```

Quy tắc:

- simulation core không phụ thuộc trực tiếp vào scene tree, node path, resource path hoặc UI;
- systems không tự load file trong `tick`; dữ liệu phải đi qua loader/registry trước runtime;
- công thức chỉ nhận input object và parameter object đã typed/validated;
- mọi logic scenario, map source và asset path phải được chuyển thành semantic ID hoặc DTO trung lập trước khi vào core;
- tests có thể chạy headless với fixture data nhỏ, không cần mở scene.

## Dependency Injection

Dependency Injection là mặc định cho runtime systems.

Mỗi system nhận dependency qua constructor, `setup(context)` hoặc factory ở composition root:

```text
SimulationHost
├── creates ContentRegistry
├── creates FormulaRegistry
├── creates EntityFactory
├── creates systems with typed dependencies
└── owns tick order
```

Ví dụ dependency hợp lệ:

- `TimeSystem` nhận `SimulationClockConfig`;
- `MovementSystem` nhận `TerrainQuery`, `RoadGraph`, `FormulaRegistry`, `MovementBalance`;
- `CombatSystem` nhận `CombatFormula`, `EquipmentCatalog`, `RngStream`;
- `AiDecisionSystem` nhận `TacticalSituationBuilder`, `AiActionGenerator`, `AiScoringStrategy`, `AiMistakeBiasStrategy`, `AiProfileRegistry`, `CommandBus`, `RngStream`;
- `MoraleCohesionSystem` nhận `MoraleFormula`, `DesertionFormula`, `DisciplinePolicy`, `RngStream`;
- `CivilianMigrationSystem` nhận `RegionSafetyQuery`, `RouteSafetyQuery`, `DisplacementFormula`, `DestinationScoringStrategy`, `RngStream`;
- `MapRenderer` nhận `AssetCatalog` và render snapshot;
- `ScenarioLoader` nhận `ContentRegistry` và `MapPackAdapter`.

Không làm:

- system gọi trực tiếp `ProjectSettings`, autoload singleton hoặc file path để lấy số balance;
- formula tự mở JSON;
- class gameplay tự tạo RNG mới;
- UI gọi thẳng method mutate state của entity.

Autoload/singleton trong Godot chỉ nên là composition root hoặc service biên như logging/dev console. Không dùng singleton làm kho dữ liệu gameplay sống.

## State Pattern

Dùng State Pattern khi entity hoặc module có lifecycle phức tạp, nhiều transition và hành vi thay đổi theo trạng thái.

Áp dụng sớm cho:

- `AppState`: boot, main menu, loading, in game, paused, saving, error;
- `ArmyOrderState`: idle, marching, foraging, camping, fighting, retreating, routing;
- `FormationAiState`: idle, marching, deploying, skirmishing, fighting, withdrawing, routing, deserting;
- `ConstructionProjectState`: planned, gathering materials, building, blocked, completed, abandoned;
- `RefugeeGroupState`: preparing, moving, blocked, sheltering, settling, returning;
- `DiplomacyAgreementState`: proposed, active, violated, expired;
- `WeatherCellState`: clear, rain, storm, flood recovery;
- `AiDirectorState`: observe, plan, execute, recover.

Interface target:

```text
State
├── enter(entity, context)
├── tick(entity, dt, context)
├── handle_order(entity, order, context)
└── exit(entity, context)
```

Transition phải có lý do rõ ràng:

```text
current_state.tick(...)
if transition_requested:
    current_state.exit(...)
    current_state = state_factory.create(next_state_id)
    current_state.enter(...)
```

Quy tắc:

- state object chứa behavior, entity giữ state ID và data;
- transition guard đọc rule từ config khi đó là balance/tuning;
- state không được gọi renderer/UI trực tiếp;
- state phải phát domain event nếu UI/render cần biết;
- không dùng State Pattern cho boolean đơn giản hoặc enum không có behavior riêng.

Nếu một file có nhiều nhánh kiểu `if army.order == ...` và mỗi nhánh có logic dài, chuyển sang State Pattern.

## Strategy Pattern cho công thức

Formula phải được đóng gói như Strategy để thay công thức hoặc mode balance mà không sửa system.

Ví dụ:

```text
MovementSystem
└── MovementFormulaStrategy
    ├── DefaultMovementFormula
    ├── NavalMovementFormula
    └── DebugFastMovementFormula
```

System chỉ gọi:

```text
distance = movement_formula.calculate(input, params)
```

Trong đó:

- `input` là dữ liệu runtime đã chuẩn hóa;
- `params` đến từ `content/common/formulas/*.json`;
- strategy được chọn từ config, scenario manifest hoặc debug profile đã validate.

Quy tắc:

- không hard-code hệ số combat, speed, spoilage, terrain multiplier trong strategy;
- không để strategy mutate world state;
- không trộn lookup asset/UI trong formula;
- mỗi formula có fixture test với input/output kỳ vọng;
- Formula Inspector phải đọc được formula ID, parameter set và intermediate values.

Dùng Strategy Pattern cho movement, logistics throughput, spoilage, morale, desertion, combat resolution, disease risk, recruitment quality, tax output, civilian displacement, refugee destination scoring, AI scoring và AI mistake bias.

## AI architecture rules

AI là simulation client, không phải ngoại lệ của architecture.

Quy tắc:

- AI chỉ gửi `Command` qua command queue giống player/replay, không mutate entity trực tiếp;
- tactical AI đọc `TacticalSituation` snapshot, không đọc renderer/UI hoặc node tree;
- scoring, mistake bias, morale/desertion và civilian displacement đều là strategy/config;
- random decision dùng injected `RngStream`, seed ổn định theo tick/entity để replay deterministic;
- debug event phải giải thích candidate actions, score, probability và reason chọn action;
- không hard-code "tướng ngu thì luôn thua"; intelligence chỉ thay đổi phân phối xác suất chọn action.

AI composition target:

```text
AiDecisionSystem
├── TacticalSituationBuilder
├── AiActionGenerator
├── AiScoringStrategy
├── AiMistakeBiasStrategy
├── AiProfileRegistry
├── CommandValidator
└── RngStream
```

Civilian movement target:

```text
CivilianMigrationSystem
├── RegionSafetyQuery
├── RouteSafetyQuery
├── DisplacementFormula
├── DestinationScoringStrategy
├── RefugeeGroupFactory
└── RngStream
```

## Adapter Pattern

Adapter chuyển dữ liệu hoặc API bên ngoài thành format trung lập mà core hiểu.

Adapter bắt buộc cho:

- map generator output sang map pack runtime;
- future GIS region geography data sang cùng map pack;
- hand-authored map pack sang runtime DTO;
- Godot resource path sang `asset.*` semantic ID lookup;
- savegame version cũ sang state version hiện tại;
- external historical/source data sang source registry;
- platform/file IO nếu cần test headless.

Runtime không được phân nhánh kiểu:

```text
if map_source == "generated":
    ...
elif map_source == "regional_gis":
    ...
```

Thay vào đó:

```text
MapPackAdapter
├── GeneratedMapAdapter
├── HistoricalGisMapAdapter
└── HandAuthoredMapAdapter
```

Tất cả adapter output cùng DTO:

```text
RuntimeMapPack
├── manifest
├── dense_layers
├── feature_index
├── road_graph
├── water_graph
└── provenance
```

Adapter test phải kiểm tra:

- schema version;
- required fields;
- deterministic output nếu có seed;
- source/provenance;
- unknown ID rejection;
- không rò Godot resource path vào gameplay data.

## Command Pattern

Player order, AI order và replay input nên đi qua Command Pattern.

Command là data bất biến:

```text
MoveArmyCommand {
    command_id;
    actor_faction_id;
    army_id;
    target_position_m;
    issued_tick;
}
```

Simulation tick chỉ xử lý command queue đã validate. Lợi ích:

- dễ replay/debug;
- dễ test determinism;
- dễ thêm AI hoặc multiplayer sau này;
- UI không mutate core trực tiếp.

Mọi command phải có validator riêng. Command sai quyền, sai state, sai target hoặc thiếu resource phải fail trước khi mutate world.

## Observer/Event Bus

Simulation phát domain event, UI/render/audio/debug đọc event hoặc snapshot.

Ví dụ event:

- `ArmyStateChanged`;
- `SupplyRouteFailed`;
- `DepotSpoilageOccurred`;
- `WeatherStormStarted`;
- `ConstructionBlocked`;
- `CombatResolved`.
- `AiDecisionMade`;
- `CommandDisobeyed`;
- `FormationRouted`;
- `UnitDeserted`;
- `CivilianDisplacementStarted`;
- `RefugeesArrived`;
- `RefugeesSettled`.

Quy tắc:

- event là record bất biến, có tick và entity ID;
- event không chứa reference tới node hoặc object mutable;
- event không được dùng để điều khiển logic chính phụ thuộc thứ tự listener;
- core system không biết listener cụ thể là UI, renderer hay telemetry.

Dùng event cho notification và visualization. Dùng system call rõ ràng cho mutation gameplay quan trọng.

## Factory, Registry và Builder

Dùng Factory khi tạo entity cần validate nhiều catalog:

- `EntityFactory.create_army(template_id, faction_id, spawn_context)`;
- `EntityFactory.create_depot(building_id, position, owner)`;
- `ScenarioFactory.create_initial_state(manifest)`.

Dùng Registry để lookup dữ liệu ổn định:

- `ContentRegistry`;
- `FormulaRegistry`;
- `BalanceCatalog`;
- `AssetCatalog`;
- `SourceRegistry`.

Dùng Builder cho object cấu hình phức tạp trong tools/tests, ví dụ map fixture, scenario fixture hoặc combat test case.

Không để gameplay code tự ghép string ID hoặc tự tạo default nếu registry thiếu key. Dev/test phải fail fast.

## Facade và subsystem boundary

Facade hợp lệ khi cần một API nhỏ cho module lớn:

- `SimulationHost` là facade của tick order, command queue và snapshot;
- `MapQueryFacade` gom terrain/road/water query cho movement/logistics;
- `RendererFacade` nhận snapshot và asset IDs;
- `ContentValidationFacade` chạy schema/content checks trong tools/tests.

Facade không được trở thành god object. Nếu facade bắt đầu chứa công thức gameplay, tách về system hoặc strategy.

## Specification/Policy Pattern

Dùng Specification hoặc Policy cho rule kiểm tra có thể thay đổi bằng data:

- có được đặt depot ở vị trí này không;
- army có được nhận lệnh hành quân không;
- route có đủ throughput không;
- faction có được recruit unit này không;
- scenario có cho phép firearms/cannon không.

Ví dụ:

```text
PlacementPolicy.can_place_depot(position, map_query, params) -> PlacementResult
```

Kết quả nên giải thích được:

```text
PlacementResult {
    allowed;
    score;
    failed_rules;
    warnings;
}
```

UI dùng `failed_rules` để hiển thị lý do, không tự tính lại rule.

## Khi nào chưa cần pattern

Không thêm abstraction chỉ để có pattern.

Chưa cần pattern nếu:

- logic có một nhánh ngắn, không có biến thể tương lai rõ ràng;
- dữ liệu chỉ dùng trong một tool prototype;
- pattern làm test khó hơn hoặc che giấu flow;
- state không có behavior riêng;
- công thức chưa có tham số hoặc chưa cần đổi theo scenario/mod.

Ngưỡng refactor:

- hơn 3 state có behavior khác nhau;
- hơn 2 formula variant;
- một system đọc hơn 2 catalog trực tiếp;
- một file có nhiều nhánh theo `source`, `state`, `mode` hoặc `scenario`;
- test fixture phải mock quá nhiều Godot node để test logic.

## Checklist khi thêm logic mới

Trước khi commit logic gameplay mới:

- công thức và số balance nằm trong `content/common/formulas` hoặc `content/common/balance`;
- system nhận dependency qua constructor/context;
- không có direct Godot resource path trong core;
- không có scenario-specific branch trong core;
- state phức tạp đã tách thành state class;
- formula có strategy hoặc function object riêng;
- data source mới đi qua adapter;
- command từ UI/AI được validate trước mutation;
- domain event/snapshot đủ cho UI/debug;
- có unit test hoặc fixture validation cho rule chính;
- debug inspector có thể giải thích output của công thức quan trọng.

## Anti-patterns cần tránh

- `GameManager` chứa mọi thứ.
- Autoload singleton làm nguồn sự thật gameplay.
- Entity Godot node chứa state mô phỏng chính.
- Magic number trong system hoặc state.
- Branch theo string map/scenario/faction trong core.
- Formula mutate world state.
- UI tính lại rule gameplay riêng.
- Adapter trả object khác nhau cho từng source.
- Event listener thay đổi kết quả mô phỏng phụ thuộc thứ tự đăng ký.
- Save/load bỏ qua schema version.

## Thứ tự áp dụng trong phase đầu

Phase 0-1:

- tạo `SimulationHost` làm composition root;
- tạo `ContentRegistry`, `FormulaRegistry`, `BalanceCatalog`, `AssetCatalog`;
- inject registry/config vào systems;
- tách `AppState` và `ArmyOrderState` sớm;
- command queue cho player order cơ bản;
- map loader đi qua `MapPackAdapter`;
- unit tests cho formula và deterministic tick.

Phase 2-4:

- adapter rõ ràng cho generator/compiler output;
- Strategy Pattern cho movement, route throughput, spoilage và economy output;
- Policy cho placement, construction và recruitment;
- event bus/snapshot cho UI overlays;
- validation tool fail build khi data sai schema.

Phase 5+:

- thêm strategy cho weather, combat, morale, desertion, disease, civilian displacement, refugee destination scoring, AI scoring và AI mistake bias;
- thêm savegame migration adapter;
- mở rộng Formula Inspector để compare parameter set;
- thêm replay test từ command log.
