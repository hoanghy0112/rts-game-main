# 12 - Chuẩn asset và cấu hình tập trung

## Mục tiêu

Tài liệu này chốt hai nguyên tắc vận hành:

- art direction dùng phong cách thống nhất với model 3D/2.5D từ các marketplace asset lớn, không dùng hand-drawn art làm hướng chính;
- asset, công thức, tham số balance và global config phải được tập trung trong registry/schema để dễ chỉnh, test và mod.

## Art direction

Visual target là 3D/2.5D strategy map: terrain và công trình có chiều sâu, unit hiển thị bằng formation proxy, flag, impostor hoặc marker có cùng ngôn ngữ hình ảnh.

Quy tắc chọn asset:

- chọn pack/model từ marketplace lớn sau khi kiểm tra license, provenance, engine compatibility và format import;
- ưu tiên cùng vendor, cùng series hoặc cùng style guide hơn là gom asset rời;
- asset phải khớp scale, pivot, texel density, PBR/material workflow, palette và mức stylization;
- asset phải có hoặc hỗ trợ tạo LOD/impostor cho zoom xa;
- pack phải cho phép chỉnh sửa/import vào Godot theo license đã kiểm tra;
- không trộn hand-drawn unit/building art với model 3D/2.5D làm gameplay asset chính.

Nguồn marketplace cụ thể sẽ được chọn trong phase 0 sau khi kiểm tra license hiện hành, khả năng mua/tải và format kỹ thuật. Không hard-code phụ thuộc vào một marketplace trong code.

## Asset catalog

Gameplay code không tham chiếu trực tiếp file path. Mọi asset đi qua semantic ID.

Example:

```json
{
  "id": "asset.building.depot.tier_1",
  "type": "building_model",
  "source": {
    "marketplace": "approved_marketplace",
    "vendor": "vendor_or_creator",
    "pack": "pack_name",
    "license_note": "commercial_use_checked",
    "source_version": "2026-06-07"
  },
  "style_profile": "rts_grounded_3d_v0",
  "import_profile": "godot_glb_pbr_v0",
  "resources": {
    "godot_scene": "res://assets/marketplace/approved_pack/depot_tier_1.tscn",
    "preview_icon": "res://assets/generated_icons/depot_tier_1.png"
  },
  "scale_meters": {
    "x": 12,
    "y": 8,
    "z": 5
  },
  "lod": {
    "near": "asset.building.depot.tier_1.lod0",
    "medium": "asset.building.depot.tier_1.lod1",
    "far": "asset.building.depot.tier_1.impostor"
  }
}
```

Renderer resolves `asset.*` IDs to Godot resources. Simulation stores only gameplay state and semantic IDs.

## Central config layout

Target layout:

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

Every file must have:

- schema version;
- stable IDs;
- default values;
- min/max or allowed enum values where relevant;
- source/provenance note for historical or purchased content;
- validation tests.

## Formula rules

Formula code implements reusable functions. Formula config supplies values.

Allowed in code:

- mathematical constants;
- unit conversion constants;
- data structure defaults that are not gameplay tuning.

Not allowed in code:

- combat coefficients;
- movement speeds;
- spoilage rates;
- terrain multipliers;
- weather thresholds;
- camera zoom thresholds;
- UI warning thresholds;
- direct asset paths;
- faction/unit/building IDs embedded in branching logic.

If a system needs a new number, add it to the correct config file, schema, fixture and formula inspector.

## Validation

Content validation should fail builds/tests when:

- a referenced semantic ID is missing;
- a gameplay file contains a direct Godot resource path;
- formula config is missing required keys;
- an override targets an unknown version;
- asset metadata lacks marketplace/vendor/license/import profile;
- two assets in the same visual profile violate scale or import rules;
- generated maps or scenarios depend on code branches not declared in data.

## Implementation rule

Prefer small reusable loaders and registries:

- `AssetCatalog` for semantic asset lookup;
- `FormulaRegistry` for named formula parameters;
- `BalanceCatalog` for unit/resource/building/terrain definitions;
- `GlobalConfig` for tick, renderer, camera, UI and debug settings;
- schema validators in tools/tests before runtime load.

Runtime systems should receive typed config objects through constructors or system context. Avoid static global reads inside formulas so tests can pass controlled fixtures.
