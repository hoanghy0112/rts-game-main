# Field Generation

Painted `field_cells` are the source mask for generated plots. `VillageRegion` does not place field meshes directly; it asks `FieldPlotGenerator` for `FieldPlotData` and then instantiates `default_crop_type.field_scene` once per valid plot.

## Algorithm

Generation runs per connected component of painted cells:

1. Normalize and sort `field_cells`, then split them into 4-neighbor connected components.
2. Pick a straight row direction from the nearest road tangent. If no road tangent is available, use a deterministic fallback direction from `generation_seed` and the component identity.
3. Bias the row direction toward the region's local X axis by `field_horizontal_split_bias`. The default `1.0` forces horizontal east-west/local-X rows so vertical field roads are north-south/local-Z corridors.
4. Project every cell corner into local `(u, v)` space, where `u` is row direction and `v` is lateral direction.
5. Walk across `v` using seeded uneven widths between `field_min_plot_width` and `field_max_plot_width`, separated by `field_bund_gap`.
6. For each row band, scan along `u` in `field_sample_step` increments.
7. Keep continuous valid intervals whose samples are inside `field_cells` and outside road clearance.
8. Discard intervals shorter than `field_min_plot_length`.
9. Split intervals longer than `field_max_plot_length` into shorter horizontal segments, leaving `field_bund_gap` as vertical north-south/local-Z corridors between neighboring left/right plots.
10. Emit one `FieldPlotData` per valid segment.

Each plot stores stable id, local center, row direction, lateral direction, length, width, area, crop stage, and mutable terrain state fields.

The same `field_bund_gap` is used for horizontal gaps between row bands and vertical gaps between horizontally split segments. `VillageRegion` now treats every non-plot sample inside the painted field component, plus a `field_region_road_margin` perimeter, as continuous road/bund terrain. Generated gap polylines remain useful debugging data, but the runtime terrain pass fills the whole surface mask instead of only spraying thin centerlines.

Field plots are visually and physically lower than the road/bund surface. `field_floor_drop` defaults to `0.5m`; `field_edge_slope_width` defines the steep ramp from raised terrain down into the field floor. On Terrain3D maps, runtime region copies are sculpted and restored on cleanup. On non-Terrain3D maps, field scenes fall back to a visual downward offset so generation remains usable.

## Determinism

Generation uses `RandomNumberGenerator.seed` derived from `generation_seed`; it never calls `randomize()`. The same seed, cell mask, road data, and generation settings produce the same plot count, ids, positions, widths, and lengths.

Plot ids use component, row, interval, segment, and plot indexes. They are stable for identical input data. Editing the painted mask, road layout, or length splitting settings can intentionally change ids because the logical plot layout changed.

## Road Clearance

A plot sample is valid only when it falls inside the painted field mask and is farther than `road_width * 0.5 + field_road_clearance` from road polylines. This keeps generated plots from overlapping roads while preserving painted fields as the authoritative authoring mask.

## Runtime Flow

At runtime:

1. `VillageRegion` builds road polylines and configures `FieldPlotGenerator`.
2. The generator returns `Array[FieldPlotData]`, generated field-road polylines, and the field cells used for the road mask.
3. `VillageRegion` copies runtime Terrain3D regions, lowers plot floors, paints authored roads, and paints the continuous field road/bund mask.
4. `VillageRegion` instantiates `default_crop_type.field_scene` for each plot at the lowered floor height.
5. The concrete field receives `configure_field(plot_data, crop_type, season_weather)`.
6. `FieldTerrainRegistry.register_field(plot_data, field_node)` records the plot for later movement queries.

Navigation rebaking is intentionally out of scope for this refactor. Movement penalties begin through `FieldTerrainRegistry.get_speed_multiplier_at(world_pos, unit_type)`.
