# 09 - Scenario, modding, random maps

## Goal

Game must be modular enough to add:

- generated v0 sandbox maps;
- campaign scenarios;
- alternate-history scenarios;
- custom maps;
- random maps;
- new factions;
- new unit/equipment/resource tables;
- balance mods.

## Content philosophy

Code implements systems. Data defines scenario content.

No scenario-specific logic in core code unless absolutely necessary. Use triggers/objectives/events.

Asset, formula, balance and global gameplay settings are centralized. Scenario packs may override data through declared manifests, but must not require hard-coded asset paths, special-case formulas or scenario-specific engine branches.

## Content pack structure

```text
content/
├── common/
│   ├── assets/
│   │   ├── asset_catalog.json
│   │   ├── visual_style.json
│   │   └── import_profiles.json
│   ├── balance/
│   │   ├── resources.json
│   │   ├── supplies.json
│   │   ├── units.json
│   │   ├── equipment.json
│   │   └── buildings.json
│   ├── formulas/
│   │   ├── movement.json
│   │   ├── economy.json
│   │   ├── logistics.json
│   │   └── combat.json
│   └── globals/
│       ├── simulation.json
│       ├── renderer.json
│       └── ui.json
├── maps/
│   ├── generated/
│   │   └── river_delta_001/
│   │       ├── map.json
│   │       ├── generator_config.json
│   │       ├── layers/
│   │       ├── graphs/
│   │       └── features/
│   └── historical/
│       └── regional_adapter/
│           └── README.md
│           # future adapter output, not v0
├── map_presets/
│   └── generator_presets.json
├── factions/
│   ├── faction_a.json
│   └── faction_b.json
└── scenarios/
    ├── generated_sandbox/
    │   ├── scenario_01.json
    │   ├── initial_state.json
    │   └── objectives.json
    └── campaign_pack/
        └── README.md
        # future strict historical content
```

Content validation must reject:

- gameplay definitions that reference unknown asset IDs;
- direct Godot resource paths in scenario/unit/faction gameplay data;
- formula overrides without schema version;
- asset metadata without source marketplace, pack/vendor, license note and import profile.

## Scenario manifest

Example:

```json
{
  "id": "generated_logistics_sandbox",
  "title": "Generated Logistics Sandbox",
  "period": {
    "start_date": "0001-01-01",
    "end_date": "0001-12-31"
  },
  "map_id": "generated_river_delta_001",
  "factions": ["faction_a", "faction_b"],
  "player_faction": "faction_a",
  "historical_accuracy": "fictional_generated",
  "source_ids": [],
  "initial_state": "initial_state.json",
  "objectives": "objectives.json",
  "events": "events.json",
  "allowed_optional_units": {
    "firearm_infantry": false,
    "naval_cannon": false
  }
}
```

If strict historical campaign does not verify firearms/cannon for a scenario, disable them there. Random map can enable them.

Strict historical campaign manifests should be added after the regional adapter/content phase. V0 scenarios should use generated maps and should not claim historical accuracy.

## Faction definition

```json
{
  "id": "faction_a",
  "display_name": "Faction A",
  "heat_sensitivity": 0.35,
  "base_legitimacy": 0.65,
  "starting_relations": {
    "faction_b": -1.0
  },
  "unit_access": {
    "spearmen": true,
    "swordsmen": true,
    "archers": true,
    "cavalry": true,
    "engineers": true,
    "firearm_infantry": "scenario_controlled"
  },
  "ai_profile": "resistance_logistics"
}
```

## Unit table

```json
{
  "id": "spearmen",
  "base_power": 1.10,
  "base_speed_km_day": 18,
  "supply": {
    "rice_kg_day": 0.75,
    "water_l_day": 3.0
  },
  "equipment_required": ["spear"],
  "modifiers": {
    "vs_cavalry_formation_locked": 1.55,
    "forest_movement": 0.80
  }
}
```

## Building/structure table

```json
{
  "id": "raised_granary",
  "kind": "depot",
  "cost": {
    "wood": 60,
    "iron": 0,
    "gold": 0
  },
  "capacity": 4000,
  "preservation_multiplier": 0.70,
  "base_structural_risk_per_day": 0.006,
  "base_resupply_radius_m": 3000,
  "required_work_points": 500
}
```

## Event system

Events should be data-driven:

```json
{
  "id": "enemy_reinforcement_warning",
  "trigger": {
    "type": "date_reached",
    "date": "0001-06-01"
  },
  "conditions": [
    { "type": "faction_alive", "faction": "faction_b" }
  ],
  "effects": [
    {
      "type": "spawn_army",
      "faction": "faction_b",
      "spawn_marker": "north_road_entry",
      "army_template": "faction_b_column_small"
    }
  ],
  "source_ids": []
}
```

Historical events need sources. Fictional gameplay events can set:

```json
"historical": false
```

## Objective system

Objective types:

- hold region;
- survive until date;
- cut supply route;
- build depot;
- preserve support above threshold;
- capture/encircle stronghold;
- escort convoy;
- maintain army supply days;
- avoid civilian collapse.

Example:

```json
{
  "id": "maintain_local_support",
  "type": "metric_threshold",
  "metric": "region.local_support",
  "region": "faction_a_core",
  "operator": ">=",
  "value": 0.55,
  "duration_days": 30,
  "failure_if_below": 0.30
}
```

## V0 map generator

Inputs:

```json
{
  "seed": 12345,
  "map_size_km": [64, 48],
  "faction_count": 4,
  "terrain_style": "coastal_delta_highland_mix",
  "sea_edge": "east",
  "field_density": "normal",
  "forest_density": "normal",
  "resource_density": "normal",
  "river_density": "high",
  "road_density": "low",
  "storm_frequency": "normal",
  "starting_conditions": "asymmetric"
}
```

Generation steps:

1. generate elevation;
2. derive slope;
3. apply optional sea/coastline mask;
4. carve river network downhill;
5. mark floodplains/rice potential and dry fields;
6. place forests by elevation/slope/wetness;
7. place iron/salt/wood/water access;
8. create settlements and roads;
9. pick spawn regions;
10. assign faction start resources;
11. save map pack;
12. validate fairness and connectivity.

Generator output must use the neutral map pack format from [03 - Map generator, map pack format, geography adapter](03-map-geography-data-pipeline.md). Future Vietnam adapters must output the same format.

## Spawn placement

Candidate spawn score:

```text
spawn_score =
    0.25 * food_access
  + 0.20 * water_access
  + 0.15 * wood_access
  + 0.15 * defensive_terrain
  + 0.15 * road_or_river_access
  + 0.10 * expansion_space
```

Fairness:

```text
max(spawn_score) - min(spawn_score) <= 0.15
```

Distance:

```text
distance_between_spawns >= min(map_width, map_height) * 0.20
```

## Modding validation

Validator must check:

- all IDs unique;
- all referenced unit/equipment/building exists;
- recipes use known resources;
- scenario dates valid;
- historical content has source if `requires_source`;
- no route starts outside map;
- no initial army lacks water access or starting ration unless intentional;
- generated map pack has valid `source.kind = "generated"`;
- random map preset has feasible spawn constraints.

## Versioning

Content has semantic version:

```json
{
  "content_version": "0.1.0",
  "game_schema_version": "0.1.0"
}
```

Save compatibility:

- patch version: load directly;
- minor version: migration required;
- major version: may be incompatible.

## Acceptance criteria

- Add a new scenario without changing core code.
- Validate a scenario and get clear errors.
- Disable firearms in strict historical scenario by data.
- Generate a map from seed, save it as a map pack, reload it, and replay the same map.
- Add a new unit type from data and see it in simulation tests.
