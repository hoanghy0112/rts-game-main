# Abstract Field Architecture

`AbstractField.gd` is an abstract GDScript contract, not a scene script to attach directly to a node. Godot 4.6 prevents instantiating scripts marked with `@abstract`, so every real field scene must attach a concrete script such as `RiceField.gd extends AbstractField`.

## Required Methods

Concrete field scripts implement:

- `configure_field(plot_data, crop_type, season_weather)`: receive the generated `FieldPlotData`, the selected `CropTypeData`, and the map-level `SeasonWeatherSystem`.
- `apply_environment(snapshot)`: apply a season/weather snapshot to runtime field state and visuals.
- `rebuild_visuals()`: rebuild mesh scale, materials, crops, water, or other scene-only presentation.
- `get_ground_state_id(snapshot)`: resolve the crop-specific ground state for a snapshot, such as `dry`, `wet`, `muddy`, or `flooded`.

## Responsibilities

Field scenes are presentation and local interaction nodes. They can own meshes, materials, collision hints, selection markers, crop props, and water visuals.

Gameplay state belongs in `FieldPlotData` and registries. Plot id, footprint, bounding dimensions, crop stage, flood level, mud level, labor, irrigation, and safety values should be stored in data objects so simulation systems can query them without walking visual scene nodes.

Generated footprints may be concave orthogonal polygons rather than rectangles. Concrete field scenes should treat the polygon as authoritative and expect right-angle jogs along both row-aligned and lateral-aligned edges.

## Concrete Fields

`RiceField.tscn` attaches `RiceField.gd`, which implements the abstract methods and reacts to `SeasonWeatherSystem.environment_changed`. Future `CornField.tscn` or `VegetableField.tscn` scenes should follow the same pattern:

1. Attach a concrete script extending `AbstractField`.
2. Use `plot_data.footprint` for visual meshes, crop scattering, collision hints, and point checks. Use `plot_data.length` and `plot_data.width` only as bounding extents or compatibility dimensions.
3. Use `crop_type.get_ground_state_id(snapshot)` and `crop_type.get_ground_state_data(id)` for ground material and movement metadata.
4. Update `plot_data.ground_state_id` and `plot_data.ground_state_data` when environment changes.

## Season And Weather

Maps contain one `SeasonWeatherSystem.tscn`. `VillageRegion` resolves it through `season_weather_path` and passes it into each generated field. The field connects to `environment_changed(snapshot)` and also applies `get_snapshot_at(global_position)` during configuration.

`SeasonWeatherSystem` currently returns one global snapshot, but `get_snapshot_at(world_position)` keeps the API ready for weather cells or localized flooding later.

## Registry Rule

Units should query `FieldTerrainRegistry`, not field scene nodes. The registry stores plot data and field transforms, answers polygon point-in-field checks, and returns ground state or speed multiplier values. This keeps movement code independent from crop-specific scene hierarchies.
