# Field Generation

Painted `field_cells` are the source mask for generated plots. `VillageRegion` does not place field meshes directly; it asks `FieldPlotGenerator` for `FieldPlotData` and then instantiates `default_crop_type.field_scene` once per valid plot.

## Algorithm

Generation runs per connected component of painted cells:

1. Normalize and sort `field_cells`, then split them into 4-neighbor connected components.
2. Pick a straight row direction from the nearest road tangent. If no road tangent is available, use a deterministic fallback direction from `generation_seed` and the component identity.
3. Bias the row direction toward the region's local X axis by `field_horizontal_split_bias`. The default `1.0` forces horizontal east-west/local-X rows so vertical field roads are north-south/local-Z corridors.
4. Project every cell corner into local `(u, v)` space, where `u` is row direction and `v` is lateral direction.
5. Walk across `v` using seeded high-variance widths between `field_min_plot_width` and `field_max_plot_width`, separated by `field_bund_gap`. The default width range is `4.8m` to `11.2m`.
6. For each row band, scan along `u` in `field_sample_step` increments.
7. Keep continuous valid intervals whose samples are inside `field_cells` and outside road clearance.
8. Discard intervals shorter than `field_min_plot_length`; the default length range is `8.0m` to `24.0m`.
9. Split intervals longer than `field_max_plot_length` into shorter high-variance horizontal segments, leaving `field_bund_gap` as vertical north-south/local-Z corridors between neighboring left/right plots.
10. Build a plot-local polygon footprint for each valid segment. Eligible plots receive deterministic orthogonal stepped variants with varied horizontal and vertical edge jogs; small plots fall back to a rectangle.
11. Emit one `FieldPlotData` per valid segment.

Each plot stores stable id, local center, row direction, lateral direction, polygon footprint, length, width, area, crop stage, and mutable terrain state fields. The footprint is stored in plot-local 2D space: X follows `row_direction`, Y follows `lateral_direction`, and `(0, 0)` is the plot center. `length` and `width` are bounding extents kept for compatibility; `area` comes from the footprint polygon.

The same `field_bund_gap` is used for horizontal gaps between row bands and vertical gaps between horizontally split segments. `VillageRegion` treats every non-plot sample inside the painted field component, plus a `field_region_road_margin` perimeter, as continuous road/bund terrain. Generated gap polylines remain useful debugging data, but the runtime terrain pass fills the whole surface mask instead of only spraying thin centerlines. Irregular footprints only cut border-scale pieces out of the assigned plot envelope, so they do not introduce new wide blank spacing between plots.

Footprint variation is intentionally right-angled. The generator varies the apparent horizontal and vertical field lines with small inward rectangular jogs that stay parallel to the plot's row and lateral axes. This keeps field corners at 90 degrees or very close to it after world rotation while avoiding repeated equal rectangles.

Field plots are visually and physically lower than the road/bund surface. `field_floor_drop` defaults to `0.5m`; `field_edge_slope_width` defines the steep ramp from raised terrain down into the polygon field floor. On Terrain3D maps, runtime region copies are sculpted and restored on cleanup. On non-Terrain3D maps, field scenes fall back to a visual downward offset so generation remains usable.

## Determinism

Generation uses `RandomNumberGenerator.seed` derived from `generation_seed`; it never calls `randomize()`. The same seed, cell mask, road data, and generation settings produce the same plot count, ids, positions, widths, lengths, and footprints.

Plot ids use component, row, interval, segment, and plot indexes. They are stable for identical input data. Editing the painted mask, road layout, or length splitting settings can intentionally change ids because the logical plot layout changed.

## Road Clearance

A plot sample is valid only when it falls inside the painted field mask and is farther than `road_width * 0.5 + field_road_clearance` from road polylines. This keeps generated plot envelopes from overlapping roads while preserving painted fields as the authoritative authoring mask. Footprint variants stay inside the accepted envelope.

## Runtime Flow

At runtime:

1. `VillageRegion` builds road polylines and configures `FieldPlotGenerator`.
2. The generator returns `Array[FieldPlotData]`, generated field-road polylines, and the field cells used for the road mask.
3. `VillageRegion` copies runtime Terrain3D regions, lowers polygon plot floors, paints authored roads, and paints the continuous field road/bund mask.
4. `VillageRegion` instantiates `default_crop_type.field_scene` for each plot at the lowered floor height.
5. The concrete field receives `configure_field(plot_data, crop_type)`.
6. `FieldTerrainRegistry.register_field(plot_data, field_node)` records the plot for later movement queries.

Navigation rebaking is intentionally out of scope for this refactor. Movement penalties begin through `FieldTerrainRegistry.get_speed_multiplier_at(world_pos, unit_type)`, which checks the polygon footprint rather than the bounding rectangle.
