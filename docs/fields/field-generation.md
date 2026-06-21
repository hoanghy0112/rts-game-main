# Field Generation

Painted `field_cells` are the source mask for generated rice paddies. `VillageRegion` asks `FieldPlotGenerator` for plot footprints plus generated bund polylines, then renders the paddy block with one shared `RicePaddyRenderer` instead of instancing a full field scene for every plot.

## Algorithm

Generation runs per connected component of painted cells:

1. Normalize and sort `field_cells`, then split them into 4-neighbor connected components.
2. Trace the component boundary from exposed cell edges and convert the dominant loop into a polygon in region-local XZ space.
3. Pick the nearest road tangent as the frontage direction. If no road is available, use a deterministic fallback direction from `generation_seed` and the component identity.
4. Build local layout axes where `u` follows the road frontage and `v` is perpendicular to the road. Longitudinal division lines are constant-`u` lines running across field depth, so they are perpendicular to the adjacent road.
5. Estimate component frontage and depth in meters, then generate randomized `u` intervals from the target plot area settings. The defaults target `300m2` to `600m2`, with `450m2` preferred.
6. Add transverse constant-`v` cuts at randomized depth intervals. Interval sizes are derived from the current frontage width and clamped to the target area range when possible.
7. Clip the component boundary polygon by each oriented interval using half-plane clipping. This keeps plots inside the painted field even when the component outline or division lines are irregular.
8. Reject tiny, sliver, self-intersecting, or road-overlapping polygons. Oversized polygons are split recursively along their longest local axis until they are near the target area.
9. Store each accepted polygon as a `FieldPlotData` footprint in plot-local coordinates. `length` and `width` remain bounding extents for compatibility, while `area` comes from the actual polygon.
10. Emit each plot perimeter as generated bund polylines. The same lines are also mirrored into generated field-road debug polylines for older tooling.

The result is usually rectangular because the layout is road-aligned, but clipping and non-parallel boundary conditions can produce trapezoids, triangles, and other valid irregular shapes. The generator is deterministic for identical input masks, road data, seed, and export settings.

## Runtime Flow

At runtime:

1. `VillageRegion` builds authored road polylines and configures `FieldPlotGenerator`.
2. The generator returns `Array[FieldPlotData]`, generated field-road polylines, generated paddy bund polylines, and the field cells used for terrain masks.
3. `VillageRegion` copies runtime Terrain3D regions, lowers polygon plot floors, paints authored roads, and paints the field road/bund mask.
4. `VillageRegion` instantiates `RicePaddyRenderer` once for the generated block.
5. `RicePaddyRenderer` builds elevated soil bund meshes from generated bund polylines, shallow flooded water meshes from plot footprints, and a mask texture for dense rice plant particles.
6. `FieldTerrainRegistry.register_field(plot_data, field_node)` records each plot against the shared renderer for movement and terrain queries.

Navigation rebaking is intentionally out of scope for this system. Movement penalties begin through `FieldTerrainRegistry.get_speed_multiplier_at(world_pos, unit_type)`, which checks the polygon footprint rather than a bounding rectangle.

## Visual Model

The paddy renderer is fully procedural:

- Bunds are low trapezoidal soil embankments sampled against terrain height and shaded with a muddy-earth/grass blend.
- Water is rendered as shallow translucent plot surfaces slightly above the lowered field floor.
- Rice plants use `RiceDensePlantsParticles` with generated upright, curved blade strips for the near view. A lightweight macro overlay is preserved as a far-distance LOD only, so close fields read as dense plants instead of flat painted surfaces.

This keeps the runtime draw-call count low compared with one scene per plot while still preserving individual plot footprints for gameplay and movement queries.
