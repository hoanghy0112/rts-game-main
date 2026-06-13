# 03 - Map generator, map pack format, geography adapter

## V0 decision

V0 does **not** include a Vietnam map.

V0 builds:

1. a deterministic procedural map generator;
2. a neutral runtime map pack format;
3. a compiler/validator that can save, load and validate generated maps;
4. renderer/simulation queries over that map pack.

The future Vietnam map pipeline is an adapter. It will convert GIS/geography/historical data into the same map pack format and add sourced resource/historical overrides later. Runtime code should not care whether a map came from the generator, a hand-authored pack, or a Vietnam adapter.

## Map format principles

- Source-neutral: generated maps and real-world adapters output the same structure.
- Versioned: every map pack declares `map_schema_version`.
- Deterministic: same generator config + seed produces the same map pack.
- Inspectable: manifests, graphs and sparse features stay JSON.
- Efficient enough: dense tile/raster layers can be compact binary arrays after the prototype.
- Validated: invalid terrain, routes, resources or spawn positions fail before runtime.
- No false history: generated maps are marked fictional/procedural and carry no historical claims.

V1 implementation note: the in-repo validator currently checks required layers/features, duplicate IDs, feature bounds, flow-vector shape/strength, infrastructure shape, spawn scores and basic resource-vs-terrain compatibility. The stricter GIS-grade checks below remain the target for the future adapter/compiler phase.

## Runtime map pack

Target directory:

```text
content/maps/generated/river_delta_001/
├── map.json
├── generator_config.json
├── provenance.json
├── layers/
│   ├── elevation.f32
│   ├── moisture.u8
│   ├── terrain_class.u8
│   ├── fertility.u8
│   ├── forest_density.u8
│   ├── flood_risk.u8
│   └── resource_potential.u8
├── chunks/
│   ├── lod0/
│   ├── lod1/
│   ├── lod2/
│   └── lod3/
├── graphs/
│   ├── road_graph.json
│   ├── water_graph.json
│   └── strategic_graph.json
├── features/
│   ├── rivers.json
│   ├── roads.json
│   ├── settlements.json
│   ├── resource_sites.json
│   ├── spawn_regions.json
│   ├── named_markers.json
│   ├── flow_vectors.json
│   └── infrastructure.json
└── overlays/
    └── initial_mutable_state.json
```

Prototype rule: a small v0 prototype may store dense layers as JSON arrays first. The format should still be shaped like the final map pack so the binary array swap is mechanical.

## Manifest

`map.json`:

```json
{
  "map_schema_version": "0.1.0",
  "id": "generated_river_delta_001",
  "display_name": "River Delta 001",
  "source": {
    "kind": "generated",
    "seed": 12345,
    "generator_id": "v0_procedural_map_generator",
    "generator_version": "0.1.0"
  },
  "size_m": {
    "width": 64000,
    "height": 48000
  },
  "coordinate_system": {
    "kind": "local_meters",
    "origin": { "x_m": 0, "y_m": 0 },
    "projection_id": null
  },
  "tile": {
    "size_m": 64,
    "width": 1000,
    "height": 750
  },
  "chunking": {
    "lod0_size_m": 64000,
    "lod1_size_m": 8000,
    "lod2_size_m": 1000,
    "lod3_size_m": 250
  },
  "terrain_classes": [
    "sea",
    "coast",
    "plain",
    "hill",
    "mountain",
    "wetland",
    "paddy_field",
    "dry_field",
    "forest",
    "dense_forest",
    "river",
    "road",
    "settlement"
  ],
  "feature_files": {
    "rivers": "features/rivers.json",
    "roads": "features/roads.json",
    "resource_sites": "features/resource_sites.json",
    "spawn_regions": "features/spawn_regions.json",
    "settlements": "features/settlements.json",
    "flow_vectors": "features/flow_vectors.json",
    "infrastructure": "features/infrastructure.json"
  }
}
```

## Dense layers

Dense layers are tile-aligned arrays. They are used for terrain rendering, movement cost, placement preview and local simulation queries.

Required v0 layers:

| Layer | Type | Meaning |
|---|---|---|
| `elevation` | `float32` | meters above local sea level |
| `terrain_class` | `uint8 enum` | dominant terrain class |
| `moisture` | `uint8 0..255` | water availability/wetness |
| `fertility` | `uint8 0..255` | field/rice/food potential |
| `forest_density` | `uint8 0..255` | tree cover and wood potential |
| `flood_risk` | `uint8 0..255` | seasonal flood susceptibility |
| `resource_potential` | `uint8 0..255` | generic strategic resource score |

Optional later layers:

- soil class;
- climate normals;
- erosion/landslide risk;
- visibility/line-of-sight precompute;
- historical override masks.

Dense binary convention:

- row-major order, `y * width + x`;
- little-endian numeric values;
- no compression in v0 unless profiling shows file size is a problem;
- layer dimensions and type are declared in `map.json`, not inferred from file size.

## Sparse features

Sparse features are JSON because designers and adapters need to inspect and patch them.

River feature:

```json
{
  "id": "river_001",
  "kind": "river",
  "polyline_m": [
    { "x": 1200, "y": 400 },
    { "x": 2000, "y": 900 }
  ],
  "width_m": 35,
  "flow_direction": "downstream",
  "navigability": 0.55,
  "seasonal_depth": [0.3, 0.6, 0.9, 0.5]
}
```

Road feature:

```json
{
  "id": "road_001",
  "kind": "road",
  "polyline_m": [
    { "x": 300, "y": 800 },
    { "x": 1200, "y": 1100 }
  ],
  "surface": "earth",
  "width_class": 1,
  "condition": 0.8,
  "flood_risk": 0.35
}
```

Resource site:

```json
{
  "id": "wood_site_001",
  "resource": "wood",
  "position_m": { "x": 4200, "y": 1800 },
  "radius_m": 900,
  "yield_score": 0.7,
  "renewable": true,
  "source": "generated"
}
```

Flow vector feature, used by map editor and renderer to preserve authored water-flow direction:

```json
{
  "id": "main_flow_00",
  "position_m": { "x": 12800, "y": 7200 },
  "direction": { "x": 0.12, "y": 0.99 },
  "strength": 0.65,
  "source": "generated|editor"
}
```

Infrastructure feature, used for default village/campaign fixtures and editor-authored map setup:

```json
{
  "id": "village_river_01_granary",
  "kind": "granary|village_granary|road_marker|bridge_site|watch_post|depot_site",
  "position_m": { "x": 10400, "y": 5600 },
  "source": "generated|editor"
}
```

Spawn region:

```json
{
  "id": "spawn_west_001",
  "center_m": { "x": 6000, "y": 12000 },
  "radius_m": 2500,
  "score": {
    "food_access": 0.72,
    "water_access": 0.88,
    "wood_access": 0.66,
    "defense": 0.51,
    "route_access": 0.58
  }
}
```

## Generator input

`generator_config.json`:

```json
{
  "seed": 12345,
  "map_size_km": [64, 48],
  "tile_size_m": 64,
  "terrain_style": "coastal_delta_highland_mix",
  "sea": {
    "enabled": true,
    "edge": "east",
    "coast_roughness": 0.45
  },
  "elevation": {
    "mountain_ratio": 0.25,
    "hill_ratio": 0.35,
    "plain_ratio": 0.40
  },
  "rivers": {
    "density": "high",
    "major_river_count": 2,
    "allow_deltas": true
  },
  "land_cover": {
    "field_density": "normal",
    "forest_density": "normal",
    "wetland_density": "normal"
  },
  "resources": {
    "rice": "normal",
    "wood": "normal",
    "iron": "scarce",
    "salt": "coastal"
  },
  "roads": {
    "density": "low",
    "connect_settlements": true,
    "prefer_river_crossings": true
  },
  "spawns": {
    "faction_count": 4,
    "starting_conditions": "asymmetric_balanced",
    "min_distance_ratio": 0.20
  }
}
```

## Generation steps

1. Generate heightfield from seeded noise, ridges and basin masks.
2. Apply sea/coastline mask if enabled.
3. Derive slope, wetness and flood risk.
4. Carve river network downhill, then widen major rivers/deltas.
5. Mark terrain classes: sea, coast, wetland, paddy field, dry field, forest, hill, mountain, plain.
6. Place forests from elevation, slope and moisture.
7. Place fields from low slope, fertility, wetness and floodplain proximity.
8. Place resource sites: rice/food, wood, iron, salt, water access.
9. Create settlements and road graph between settlements, crossings and ports.
10. Build water graph for navigable rivers/coast.
11. Choose faction spawn regions using fairness constraints.
12. Compile chunks/LOD metadata.
13. Save map pack and validate.

## Terrain classification

```text
terrain_class =
    sea if sea_mask
    river if river_width_m covers tile
    coast if distance_to_sea_m < coast_threshold
    paddy_field if low_slope && high_moisture && high_fertility && near_floodplain
    dry_field if low_slope && medium_fertility
    dense_forest if forest_density >= 0.75
    forest if forest_density >= 0.35
    mountain if slope_deg >= 18 || elevation_m >= mountain_threshold
    hill if slope_deg >= 7
    wetland if high_moisture && low_elevation
    plain otherwise
```

## Placement suitability

Player can place camp/depot/road/trench with free-form placement. The system samples the map pack around the cursor.

Preview scores:

- construction cost modifier;
- defense score;
- logistics score;
- spoilage risk;
- flood risk;
- water access;
- wood/field access.

```text
logistics_score =
    0.30 * road_access
  + 0.20 * water_access
  + 0.20 * flat_land
  + 0.15 * local_food_potential
  + 0.10 * security
  + 0.05 * wood_access
```

```text
defense_score =
    0.35 * normalized_elevation_advantage
  + 0.25 * slope_cover
  + 0.20 * forest_cover
  + 0.10 * river_barrier
  + 0.10 * fortification_potential
```

## Spawn fairness

```text
spawn_score =
    0.25 * food_access
  + 0.20 * water_access
  + 0.15 * wood_access
  + 0.15 * defensive_terrain
  + 0.15 * road_or_river_access
  + 0.10 * expansion_space
```

Required:

```text
spawn_score >= 0.55
max(spawn_score) - min(spawn_score) <= configured_variance
distance_between_spawns >= min(map_width, map_height) * min_distance_ratio
reachable_food_sites >= 2
reachable_wood_sites >= 1
reachable_water_sources >= 1
```

## Validation checks

Map validator fails if:

- manifest schema/version is invalid;
- dense layer dimensions do not match `tile.width` and `tile.height`;
- terrain enum contains unknown values;
- river flows uphill for long segments without an explicit waterfall/rapid marker;
- road crosses river without bridge/ford/ferry/crossing marker;
- route graph is disconnected outside configured islands/blocked areas;
- resource site is on invalid terrain, such as iron in sea or paddy field on steep mountain;
- spawn has no reachable food, wood or water;
- spawn fairness exceeds configured threshold;
- feature position is outside map bounds;
- generated map claims historical source IDs.

Validator warns if:

- too much map area is impassable;
- no sea exists when config requested coastal resources;
- too few crossings exist for the faction count;
- field/forest/resource density deviates strongly from preset.

## Future Vietnam adapter

The Vietnam adapter is not v0. It should output the exact same map pack structure.

Adapter input candidates:

- DEM/elevation raster;
- hydrography;
- coastline;
- land-cover/forest proxy;
- roads/tracks proxy;
- soil/arable proxy;
- hand-authored historical overrides;
- sourced resource overrides.

Adapter steps:

1. Read source GIS layers.
2. Reproject to a local projected CRS.
3. Normalize to local meter coordinates.
4. Resample dense layers to map tile resolution.
5. Convert source categories into neutral terrain classes.
6. Build river, road and strategic graphs.
7. Attach provenance and source metadata.
8. Add historical/resource overrides only when sourced or explicitly marked fictional.
9. Save the same `map.json`, layers, graphs and feature files.
10. Run the same validator.

Adapter provenance example:

```json
{
  "source": {
    "kind": "adapter",
    "adapter_id": "regional_gis_adapter",
    "adapter_version": "0.1.0"
  },
  "input_sources": [
    {
      "source_id": "geo_dem_001",
      "kind": "DEM",
      "confidence": "medium",
      "notes": "Modern elevation proxy, not historical proof."
    }
  ]
}
```

Historical/resource override example:

```json
{
  "id": "hist_resource_area_001",
  "resource": "rice",
  "position_m": { "x": 1000, "y": 2000 },
  "radius_m": 5000,
  "yield_score": 0.65,
  "historical": true,
  "confidence": "medium",
  "source_ids": ["source_010"],
  "notes": "Only use in strict campaign if source supports this claim."
}
```

## Tooling cần xây

- `map_generator`: tạo map pack procedural từ seed/config.
- `map_compiler`: compile dense layers/chunks/LOD/runtime metadata.
- `map_validator`: kiểm schema, terrain, graph, resource và spawn.
- `map_viewer`: debug terrain, slope, river, road, resource, flood risk.
- `route_debugger`: hiển thị route cost theo mùa/thời tiết.
- `scenario_validator`: kiểm scenario/content references.
- `historical_source_registry`: quản lý source IDs, độ tin cậy sau v0.
- `map_adapters/regional`: chuyển GIS region data sang map pack sau v0.
