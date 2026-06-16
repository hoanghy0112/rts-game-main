@tool
extends Node3D
class_name ForestRegion

const DEFAULT_PALETTE: ForestPaletteData = preload("res://assets/models/forest/default_forest_palette.tres")
const ForestRegionData = preload("res://addons/forest_brush/forest_region_data.gd")
const RUNTIME_CONTAINER_NAME := "__ForestRuntimeInstances"
const MAX_PLACEMENTS_PER_CELL := 512
const LOD_TIER_COUNT := 4
const LOD_FADE_BEGIN_RATIO := 0.88
const DENSE_GRASS_LAYER_META := &"forest_dense_grass_layer"

signal cells_changed
signal resources_changed

enum PaintMode {
	PAINT,
	ERASE,
}

@export var palette: ForestPaletteData = DEFAULT_PALETTE:
	set(value):
		if palette == value:
			return
		palette = value
		_scene_part_cache.clear()
		resources_changed.emit()
		_notify_resource_rendering_changed()

@export_node_path("Node3D") var terrain_path: NodePath
@export_range(0.1, 256.0, 0.1, "or_greater") var cell_size: float = 4.0:
	set(value):
		var clamped_value := maxf(value, 0.1)
		if is_equal_approx(cell_size, clamped_value):
			return
		cell_size = clamped_value
		_notify_cells_changed([], true)

@export_range(0.0, 16.0, 0.01, "or_greater") var density_multiplier: float = 1.0:
	set(value):
		var clamped_value := maxf(value, 0.0)
		if is_equal_approx(density_multiplier, clamped_value):
			return
		density_multiplier = clamped_value
		_notify_cells_changed([], true)

@export var macro_overlay_enabled := true:
	set(value):
		if macro_overlay_enabled == value:
			return
		macro_overlay_enabled = value
		resources_changed.emit()

@export_group("Tree Placement")
@export_range(0.05, 8.0, 0.01, "or_greater") var tree_scale_multiplier: float = 1.0:
	set(value):
		var clamped_value := maxf(value, 0.05)
		if is_equal_approx(tree_scale_multiplier, clamped_value):
			return
		tree_scale_multiplier = clamped_value
		_notify_resource_rendering_changed()

@export_group("Tree LOD")
@export_range(1.0, 10000.0, 1.0, "or_greater") var tree_low_poly_distance: float = 450.0:
	set(value):
		var clamped_value := maxf(value, 1.0)
		if is_equal_approx(tree_low_poly_distance, clamped_value):
			return
		tree_low_poly_distance = clamped_value
		_notify_resource_rendering_changed()

@export_range(0.0, 512.0, 1.0, "or_greater") var tree_lod_fade_margin_meters: float = 48.0:
	set(value):
		var clamped_value := maxf(value, 0.0)
		if is_equal_approx(tree_lod_fade_margin_meters, clamped_value):
			return
		tree_lod_fade_margin_meters = clamped_value
		_notify_resource_rendering_changed()

@export_range(0.0, 2048.0, 1.0, "or_greater") var tree_billboard_fade_margin_meters: float = 240.0:
	set(value):
		var clamped_value := maxf(value, 0.0)
		if is_equal_approx(tree_billboard_fade_margin_meters, clamped_value):
			return
		tree_billboard_fade_margin_meters = clamped_value
		_notify_resource_rendering_changed()

@export_group("")
@export var origin: Vector3 = Vector3.ZERO:
	set(value):
		if origin == value:
			return
		origin = value
		_notify_cells_changed([], true)

@export var generation_seed: int = 20260614:
	set(value):
		if generation_seed == value:
			return
		generation_seed = value
		_notify_cells_changed([], true)

@export var async_runtime_preview_on_ready := true
@export_range(1, 32, 1, "or_greater") var runtime_chunk_build_batch_size: int = 2

var _chunk_size_cells := 8
@export_range(1, 128, 1, "or_greater") var chunk_size_cells: int = 8:
	get:
		return _chunk_size_cells
	set(value):
		var clamped_value := maxi(value, 1)
		if _chunk_size_cells == clamped_value:
			return
		_chunk_size_cells = clamped_value
		if _region_data:
			_region_data.encode_from_cells(_forest_cells_cache, _cell_plant_ids_cache, _chunk_size_cells)
			_sync_legacy_cache_from_region_data()
		_notify_cells_changed([], true)

var _region_data: ForestRegionData
@export var region_data: ForestRegionData:
	get:
		return _ensure_region_data()
	set(value):
		_region_data = value
		if not _region_data:
			_region_data = ForestRegionData.new()
			_region_data.chunk_size_cells = _chunk_size_cells
		else:
			_chunk_size_cells = maxi(_region_data.chunk_size_cells, 1)
		_sync_legacy_cache_from_region_data()
		_notify_cells_changed([], true)

var forest_cells: Array[Vector2i]:
	get:
		return copy_cells(_forest_cells_cache)
	set(value):
		_set_legacy_forest_cells(value)

var cell_plant_ids: Dictionary:
	get:
		return copy_cell_plant_ids(_cell_plant_ids_cache)
	set(value):
		_set_legacy_cell_plant_ids(value)

var _forest_cells_cache: Array[Vector2i] = []
var _cell_plant_ids_cache: Dictionary = {}
var _forest_cells_revision := 0
var _suspend_cell_notifications := false
var _editor_gizmo_update_pending := false
var _editor_runtime_preview_batch_depth := 0
var _runtime_container: Node3D
var _scene_part_cache: Dictionary = {}


static func normalize_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	return ForestRegionData.normalize_cells(value)


static func normalize_cell_plant_ids(value: Dictionary, valid_cells: Array[Vector2i] = []) -> Dictionary:
	return ForestRegionData.normalize_cell_plant_ids(value, valid_cells)


static func normalize_plant_ids(value: Variant) -> Array[StringName]:
	return ForestRegionData.normalize_plant_ids(value)


static func copy_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	return ForestRegionData.copy_cells(value)


static func copy_cell_plant_ids(value: Dictionary) -> Dictionary:
	return ForestRegionData.copy_cell_plant_ids(value)


static func cell_key(cell: Vector2i) -> String:
	return ForestRegionData.cell_key(cell)


static func cell_key_from_variant(value: Variant) -> String:
	return ForestRegionData.cell_key_from_variant(value)


static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	return ForestRegionData._compare_cells(a, b)


func _ready() -> void:
	_ensure_region_data()
	_sync_legacy_cache_from_region_data()
	if Engine.is_editor_hint():
		return
	if async_runtime_preview_on_ready:
		rebuild_runtime_preview_deferred.call_deferred()
	else:
		rebuild_runtime_preview()


func _exit_tree() -> void:
	_editor_gizmo_update_pending = false
	_editor_runtime_preview_batch_depth = 0
	clear_runtime_instances()


func set_forest_data(new_forest_cells: Array[Vector2i], new_cell_plant_ids: Dictionary) -> void:
	var normalized_cells := normalize_cells(new_forest_cells)
	var normalized_plant_map := normalize_cell_plant_ids(new_cell_plant_ids, normalized_cells)
	var dirty_chunks := _get_changed_chunks_between(
		_forest_cells_cache,
		_cell_plant_ids_cache,
		normalized_cells,
		normalized_plant_map
	)

	if normalized_cells == _forest_cells_cache and _cell_plant_maps_equal(normalized_plant_map, _cell_plant_ids_cache):
		return

	_set_compact_data_from_legacy(normalized_cells, normalized_plant_map)
	_notify_cells_changed(dirty_chunks)


func set_region_data_snapshot(snapshot: ForestRegionData) -> void:
	var next_data: ForestRegionData
	if snapshot:
		next_data = snapshot.duplicate_data() as ForestRegionData
	if not next_data:
		next_data = ForestRegionData.new()
		next_data.chunk_size_cells = _chunk_size_cells

	if _region_data_matches(next_data):
		return

	_region_data = next_data
	_chunk_size_cells = maxi(_region_data.chunk_size_cells, 1)
	_sync_legacy_cache_from_region_data()
	_notify_cells_changed([], true)


func paint_cells(cells: Array[Vector2i], plant_ids: Array[StringName], mode: int) -> bool:
	var normalized_cells := normalize_cells(cells)
	if normalized_cells.is_empty():
		return false

	var data := _ensure_region_data()
	var patch_result: Dictionary
	match mode:
		PaintMode.PAINT:
			var effective_plant_ids := _get_effective_plant_ids(plant_ids)
			if effective_plant_ids.is_empty():
				return false
			patch_result = data.paint_cells(normalized_cells, effective_plant_ids)
		PaintMode.ERASE:
			patch_result = data.erase_cells(normalized_cells)
		_:
			return false

	if not bool(patch_result.get("changed", false)):
		return false

	_sync_legacy_cache_from_region_data()
	_notify_cells_changed(_variant_to_chunk_array(patch_result.get("changed_chunks", [])))
	return true


func clear_forest_cells() -> void:
	set_forest_data([], {})


func get_editor_gizmo_cell_revision() -> int:
	return _forest_cells_revision


func world_to_cell(world_position: Vector3) -> Vector2i:
	var local_position := _world_to_region_local(world_position) - origin
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2i(
		floori(local_position.x / safe_cell_size),
		floori(local_position.z / safe_cell_size)
	)


func cell_to_local_center(cell: Vector2i) -> Vector3:
	var safe_cell_size := maxf(cell_size, 0.1)
	return origin + Vector3(
		(float(cell.x) + 0.5) * safe_cell_size,
		0.0,
		(float(cell.y) + 0.5) * safe_cell_size
	)


func get_cell_plant_ids(cell: Vector2i) -> Array[StringName]:
	var raw_ids: Array[StringName] = []
	if _ensure_region_data().has_cell(cell):
		raw_ids = _ensure_region_data().get_cell_plant_ids(cell)
	else:
		raw_ids = normalize_plant_ids(_cell_plant_ids_cache.get(cell_key(cell), []))

	if palette:
		raw_ids = palette.filter_plant_ids(raw_ids)
		if raw_ids.is_empty():
			raw_ids = palette.get_default_selected_plant_ids()
	return raw_ids


func to_runtime_data() -> Dictionary:
	return {
		"palette": palette,
		"terrain_path": terrain_path,
		"cell_size": cell_size,
		"density_multiplier": density_multiplier,
		"tree_scale_multiplier": tree_scale_multiplier,
		"tree_low_poly_distance": tree_low_poly_distance,
		"origin": origin,
		"generation_seed": generation_seed,
		"chunk_size_cells": chunk_size_cells,
		"region_data": _ensure_region_data().duplicate_data(),
		"forest_cells": copy_cells(_forest_cells_cache),
		"cell_plant_ids": copy_cell_plant_ids(_cell_plant_ids_cache),
		"global_transform": global_transform if is_inside_tree() else transform,
	}


func get_macro_detail_data() -> Dictionary:
	if not macro_overlay_enabled:
		return {}
	return to_runtime_data()


func should_trigger_macro_overlay() -> bool:
	return macro_overlay_enabled


func rebuild_runtime_preview() -> void:
	clear_runtime_instances()

	if _forest_cells_cache.is_empty() or not palette:
		return

	var terrain := _get_terrain_node()
	var groups := _build_instance_groups(terrain)
	var dense_layer_specs := _build_dense_grass_layer_specs(terrain)
	if groups.is_empty() and dense_layer_specs.is_empty():
		return

	_ensure_runtime_container()
	_create_multimesh_groups(groups)
	_create_dense_grass_layers(dense_layer_specs)


func rebuild_runtime_preview_deferred() -> void:
	if not is_inside_tree():
		return

	await get_tree().process_frame
	if not is_inside_tree():
		return

	await rebuild_runtime_preview_async()


func rebuild_runtime_preview_async() -> void:
	clear_runtime_instances()

	if _forest_cells_cache.is_empty() or not palette:
		_mark_startup_phase("forest_ready", {"cells": 0})
		return

	var terrain := _get_terrain_node()
	var chunks := _ensure_region_data().get_chunks()
	if chunks.is_empty():
		for cell: Vector2i in _forest_cells_cache:
			var chunk_coord := _get_chunk_coord(cell)
			if not chunks.has(chunk_coord):
				chunks.append(chunk_coord)
		chunks.sort_custom(ForestRegionData._compare_chunks)

	_ensure_runtime_container()
	_mark_startup_phase("forest_build_start", {
		"cells": _forest_cells_cache.size(),
		"chunks": chunks.size(),
	})

	var chunk_batch: Array[Vector2i] = []
	for chunk_coord: Vector2i in chunks:
		chunk_batch.append(chunk_coord)
		if chunk_batch.size() >= runtime_chunk_build_batch_size:
			await _create_runtime_chunk_batch_async(terrain, chunk_batch)
			chunk_batch.clear()
			if not is_inside_tree():
				return

	if not chunk_batch.is_empty():
		await _create_runtime_chunk_batch_async(terrain, chunk_batch)
		if not is_inside_tree():
			return

	_mark_startup_phase("forest_multimesh_ready", {"chunks": chunks.size()})
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var dense_layer_specs := _build_dense_grass_layer_specs(terrain)
	await _create_dense_grass_layers_async(dense_layer_specs)
	_mark_startup_phase("forest_ready", {
		"dense_layers": dense_layer_specs.size(),
		"chunks": chunks.size(),
	})


func rebuild_runtime_chunks(chunks: Array[Vector2i]) -> void:
	if chunks.is_empty():
		return

	if not is_instance_valid(_runtime_container):
		_runtime_container = get_node_or_null(RUNTIME_CONTAINER_NAME) as Node3D

	if not is_instance_valid(_runtime_container):
		rebuild_runtime_preview()
		return

	_remove_dense_grass_layers()

	if _forest_cells_cache.is_empty() or not palette:
		return

	var near_chunk_filter: Dictionary = {}
	for chunk_coord: Vector2i in chunks:
		near_chunk_filter[chunk_coord] = true
	var far_chunk_filter := _expand_chunks_for_lod_multipliers(chunks)
	_remove_runtime_chunks_for_rebuild(near_chunk_filter, far_chunk_filter)

	var terrain := _get_terrain_node()
	var near_groups := _build_instance_groups(terrain, near_chunk_filter, {0: true, 1: true})
	_create_multimesh_groups(near_groups)
	if far_chunk_filter != near_chunk_filter:
		var far_groups := _build_instance_groups(terrain, far_chunk_filter, {2: true, 3: true})
		_create_multimesh_groups(far_groups)
	_create_dense_grass_layers(_build_dense_grass_layer_specs(terrain))


func clear_runtime_instances() -> void:
	var container := _runtime_container
	if not is_instance_valid(container):
		container = get_node_or_null(RUNTIME_CONTAINER_NAME) as Node3D

	if is_instance_valid(container):
		var parent := container.get_parent()
		if parent:
			parent.remove_child(container)
		container.free()

	_runtime_container = null


func begin_editor_runtime_preview_batch() -> void:
	if not Engine.is_editor_hint():
		return

	_editor_runtime_preview_batch_depth += 1


func end_editor_runtime_preview_batch(_rebuild: bool) -> void:
	if not Engine.is_editor_hint():
		return

	if _editor_runtime_preview_batch_depth <= 0:
		_editor_runtime_preview_batch_depth = 0
		return

	_editor_runtime_preview_batch_depth -= 1


func request_editor_gizmo_update() -> void:
	if not Engine.is_editor_hint() or is_queued_for_deletion() or not is_inside_tree() or not _is_in_active_edited_scene():
		return
	if _editor_gizmo_update_pending:
		return

	_editor_gizmo_update_pending = true
	_flush_editor_gizmo_update.call_deferred()


func _flush_editor_gizmo_update() -> void:
	_editor_gizmo_update_pending = false
	if not Engine.is_editor_hint() or is_queued_for_deletion() or not is_inside_tree() or not _is_in_active_edited_scene():
		return

	update_gizmos()


func _notify_cells_changed(dirty_chunks: Array[Vector2i] = [], force_full_rebuild := false) -> void:
	if _suspend_cell_notifications:
		return

	_forest_cells_revision += 1
	cells_changed.emit()
	if Engine.is_editor_hint() and is_inside_tree():
		request_editor_gizmo_update()
	elif is_inside_tree():
		if force_full_rebuild or dirty_chunks.is_empty():
			rebuild_runtime_preview()
		else:
			rebuild_runtime_chunks(dirty_chunks)


func _notify_resource_rendering_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		request_editor_gizmo_update()
	elif is_inside_tree():
		rebuild_runtime_preview()


func _ensure_region_data() -> ForestRegionData:
	if not _region_data:
		_region_data = ForestRegionData.new()
		_region_data.chunk_size_cells = _chunk_size_cells
	return _region_data


func _sync_legacy_cache_from_region_data() -> void:
	var data := _ensure_region_data()
	_forest_cells_cache = data.to_cells()
	_cell_plant_ids_cache = data.to_cell_plant_ids()


func _set_legacy_forest_cells(value: Array[Vector2i]) -> void:
	var normalized_cells := normalize_cells(value)
	var normalized_plant_map := normalize_cell_plant_ids(_cell_plant_ids_cache, normalized_cells)
	var dirty_chunks := _get_changed_chunks_between(
		_forest_cells_cache,
		_cell_plant_ids_cache,
		normalized_cells,
		normalized_plant_map
	)
	if normalized_cells == _forest_cells_cache and _cell_plant_maps_equal(normalized_plant_map, _cell_plant_ids_cache):
		return

	_set_compact_data_from_legacy(normalized_cells, normalized_plant_map)
	_notify_cells_changed(dirty_chunks)


func _set_legacy_cell_plant_ids(value: Dictionary) -> void:
	var normalized_plant_map := normalize_cell_plant_ids(value, _forest_cells_cache)
	if _cell_plant_maps_equal(normalized_plant_map, _cell_plant_ids_cache):
		return

	if _forest_cells_cache.is_empty():
		_cell_plant_ids_cache = normalized_plant_map
		_notify_cells_changed([])
		return

	var dirty_chunks := _get_changed_chunks_between(
		_forest_cells_cache,
		_cell_plant_ids_cache,
		_forest_cells_cache,
		normalized_plant_map
	)
	_set_compact_data_from_legacy(_forest_cells_cache, normalized_plant_map)
	_notify_cells_changed(dirty_chunks)


func _set_compact_data_from_legacy(cells: Array[Vector2i], plant_map: Dictionary) -> void:
	_ensure_region_data().encode_from_cells(cells, plant_map, _chunk_size_cells)
	_sync_legacy_cache_from_region_data()


func _build_instance_groups(terrain: Node3D, chunk_filter: Dictionary = {}, lod_filter: Dictionary = {}) -> Dictionary:
	var plant_types_by_id := _get_palette_plant_types_by_id()
	var groups: Dictionary = {}
	var cells_to_build := _get_cells_for_runtime_build(chunk_filter)
	var lod_tiers_by_plant_id: Dictionary = {}

	for cell: Vector2i in cells_to_build:
		var plant_ids := get_cell_plant_ids(cell)
		for plant_id: StringName in plant_ids:
			var plant_type := plant_types_by_id.get(plant_id) as ForestPlantTypeData
			if not _is_chunked_multimesh_plant(plant_type):
				continue

			var lod_tiers: Array[int] = []
			if lod_tiers_by_plant_id.has(plant_id):
				lod_tiers = lod_tiers_by_plant_id[plant_id]
			else:
				lod_tiers = _get_lod_tiers_for_plant_type(plant_type)
				lod_tiers_by_plant_id[plant_id] = lod_tiers
			if lod_tiers.is_empty():
				continue

			var placements := _build_cell_placements(cell, plant_type, terrain)
			for placement: Dictionary in placements:
				for lod_tier: int in lod_tiers:
					if not lod_filter.is_empty() and not lod_filter.has(lod_tier):
						continue
					if not _placement_is_kept_for_lod(placement, plant_type, lod_tier):
						continue

					var parts := _get_scene_parts(plant_type, lod_tier)
					for part: Dictionary in parts:
						_add_placement_part_to_groups(groups, cell, plant_type, lod_tier, placement, part)

	return groups


func _get_cells_for_runtime_build(chunk_filter: Dictionary) -> Array[Vector2i]:
	if chunk_filter.is_empty():
		return copy_cells(_forest_cells_cache)

	var data := _ensure_region_data()
	var cells: Array[Vector2i] = []
	var chunks: Array[Vector2i] = []
	for key: Variant in chunk_filter.keys():
		chunks.append(key as Vector2i)
	chunks.sort_custom(ForestRegionData._compare_chunks)
	for chunk_coord: Vector2i in chunks:
		cells.append_array(data.get_cells_in_chunk(chunk_coord))
	return cells


func _build_cell_placements(cell: Vector2i, plant_type: ForestPlantTypeData, terrain: Node3D) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var density := maxf(plant_type.density_per_cell * density_multiplier, 0.0)
	if density <= 0.0:
		return placements

	var rng := _get_rng_for_cell_and_plant(cell, plant_type.id)
	var density_jitter := clampf(plant_type.density_jitter, 0.0, 1.0)
	var desired_count := density * rng.randf_range(1.0 - density_jitter, 1.0 + density_jitter)
	var count := floori(desired_count)
	if rng.randf() < desired_count - float(count):
		count += 1
	count = clampi(count, 0, MAX_PLACEMENTS_PER_CELL)
	if count <= 0:
		return placements

	var safe_cell_size := maxf(cell_size, 0.1)
	var grid_side := ceili(sqrt(float(count)))
	var edge_margin := clampf(plant_type.cell_edge_margin, 0.0, 0.45)
	var usable_size := safe_cell_size * (1.0 - edge_margin * 2.0)
	var cell_min := Vector2(
		origin.x + float(cell.x) * safe_cell_size + edge_margin * safe_cell_size,
		origin.z + float(cell.y) * safe_cell_size + edge_margin * safe_cell_size
	)

	for index: int in range(count):
		var grid_x := index % grid_side
		var grid_y := index / grid_side
		var local_point := Vector2(
			cell_min.x + (float(grid_x) + rng.randf()) / float(grid_side) * usable_size,
			cell_min.y + (float(grid_y) + rng.randf()) / float(grid_side) * usable_size
		)
		var yaw := rng.randf_range(0.0, TAU) if plant_type.random_yaw else 0.0
		var min_scale := minf(plant_type.min_scale, plant_type.max_scale)
		var max_scale := maxf(plant_type.min_scale, plant_type.max_scale)
		var scale := rng.randf_range(min_scale, max_scale) * _get_region_scale_multiplier_for_plant_type(plant_type)
		placements.append({
			"transform": _get_placement_transform(local_point, yaw, scale, plant_type, terrain),
			"lod_roll": rng.randf(),
		})

	return placements


func _get_placement_transform(
	local_point: Vector2,
	yaw: float,
	scale: float,
	plant_type: ForestPlantTypeData,
	terrain: Node3D
) -> Transform3D:
	var world_position := _get_surface_world_position_from_local_2d(local_point, terrain)
	world_position.y += plant_type.surface_offset
	var local_position := _world_to_region_local(world_position)

	var basis := Basis(Vector3.UP, yaw)
	basis = basis.scaled(Vector3(scale, scale, scale))
	return Transform3D(basis, local_position)


func _placement_is_kept_for_lod(placement: Dictionary, plant_type: ForestPlantTypeData, lod_tier: int) -> bool:
	var keep_ratio := plant_type.get_keep_ratio_for_lod(lod_tier)
	if keep_ratio <= 0.0:
		return false
	if keep_ratio >= 1.0:
		return true
	return float(placement.get("lod_roll", 1.0)) <= keep_ratio


func _add_placement_part_to_groups(
	groups: Dictionary,
	cell: Vector2i,
	plant_type: ForestPlantTypeData,
	lod_tier: int,
	placement: Dictionary,
	part: Dictionary
) -> void:
	var mesh := part.get("mesh") as Mesh
	if not mesh:
		return

	var material := part.get("material") as Material
	var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
	var placement_transform: Transform3D = placement.get("transform", Transform3D.IDENTITY)
	var lod_scale := plant_type.get_scale_multiplier_for_lod(lod_tier)
	if not is_equal_approx(lod_scale, 1.0):
		placement_transform.basis = placement_transform.basis.scaled(Vector3.ONE * lod_scale)

	var final_transform := placement_transform * part_transform
	var chunk_coord := _get_chunk_coord_for_lod(cell, lod_tier)
	var chunk_origin := _get_chunk_origin_for_lod(chunk_coord, lod_tier)
	var base_chunk_coord := _get_chunk_coord(cell)
	var base_chunk_key := _chunk_key(base_chunk_coord)
	var relative_transform := final_transform
	relative_transform.origin -= chunk_origin

	var group_key := "%s|%d|%d,%d|%d|%d" % [
		str(plant_type.id),
		lod_tier,
		chunk_coord.x,
		chunk_coord.y,
		mesh.get_instance_id(),
		material.get_instance_id() if material else 0,
	]

	var group: Dictionary = groups.get(group_key, {})
	if group.is_empty():
		group = {
			"name": "%s_L%d_%d_%d" % [str(plant_type.id), lod_tier, chunk_coord.x, chunk_coord.y],
			"plant_type": plant_type,
			"lod_tier": lod_tier,
			"mesh": mesh,
			"material": material,
			"chunk_coord": chunk_coord,
			"chunk_key": _chunk_key_for_lod(chunk_coord, lod_tier),
			"chunk_origin": chunk_origin,
			"base_chunk_keys": {},
			"shadow_casting": _get_shadow_casting_for_lod(plant_type, lod_tier, int(part.get("shadow_casting", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))),
			"transforms": [],
		}
		groups[group_key] = group

	var transforms: Array = group["transforms"]
	transforms.append(relative_transform)
	var base_chunk_keys := group.get("base_chunk_keys", {}) as Dictionary
	base_chunk_keys[base_chunk_key] = true
	group["base_chunk_keys"] = base_chunk_keys


func _create_multimesh_groups(groups: Dictionary) -> void:
	if groups.is_empty():
		return

	var group_keys: Array[String] = []
	for key: Variant in groups.keys():
		group_keys.append(str(key))
	group_keys.sort()
	for group_key: String in group_keys:
		_create_multimesh_group(groups[group_key])


func _build_dense_grass_layer_specs(terrain: Node3D) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []

	var plant_types_by_id := _get_palette_plant_types_by_id()
	var cells_by_plant_id: Dictionary = {}
	for cell: Vector2i in _forest_cells_cache:
		var plant_ids := get_cell_plant_ids(cell)
		for plant_id: StringName in plant_ids:
			var plant_type := plant_types_by_id.get(plant_id) as ForestPlantTypeData
			if not _is_dense_grass_particle_plant(plant_type):
				continue

			var cells: Array[Vector2i] = []
			if cells_by_plant_id.has(plant_id):
				cells = cells_by_plant_id[plant_id]
			if not cells.has(cell):
				cells.append(cell)
			cells_by_plant_id[plant_id] = cells

	var plant_ids: Array[StringName] = []
	for plant_id_variant: Variant in cells_by_plant_id.keys():
		plant_ids.append(plant_id_variant as StringName)
	plant_ids.sort()

	for plant_id: StringName in plant_ids:
		var plant_type := plant_types_by_id.get(plant_id) as ForestPlantTypeData
		var cells := cells_by_plant_id[plant_id] as Array[Vector2i]
		if not plant_type or cells.is_empty():
			continue
		cells.sort_custom(_compare_cells)
		specs.append({
			"plant_type": plant_type,
			"cells": cells,
			"terrain": terrain,
		})

	return specs


func _create_dense_grass_layers(specs: Array[Dictionary]) -> void:
	if specs.is_empty():
		return

	_ensure_runtime_container()
	for spec: Dictionary in specs:
		_create_dense_grass_layer(spec)


func _create_runtime_chunk_batch_async(terrain: Node3D, chunks: Array[Vector2i]) -> void:
	if chunks.is_empty():
		return

	var chunk_filter: Dictionary = {}
	for chunk_coord: Vector2i in chunks:
		chunk_filter[chunk_coord] = true

	var groups := _build_instance_groups(terrain, chunk_filter)
	_create_multimesh_groups(groups)
	await get_tree().process_frame


func _create_dense_grass_layers_async(specs: Array[Dictionary]) -> void:
	if specs.is_empty():
		return

	_ensure_runtime_container()
	for spec: Dictionary in specs:
		if not is_inside_tree():
			return
		_create_dense_grass_layer(spec)
		await get_tree().process_frame


func _create_dense_grass_layer(spec: Dictionary) -> void:
	var plant_type := spec.get("plant_type") as ForestPlantTypeData
	if not _is_dense_grass_particle_plant(plant_type):
		return

	var scene := plant_type.dense_particle_scene
	var layer := scene.instantiate() as Node3D
	if not layer:
		return

	layer.name = "%s_DenseGrass" % str(plant_type.id)
	layer.set_meta(DENSE_GRASS_LAYER_META, true)
	layer.set_meta(&"forest_plant_id", plant_type.id)

	_runtime_container.add_child(layer, false, INTERNAL_MODE_BACK)
	layer.owner = null

	var cells := spec.get("cells", []) as Array[Vector2i]
	var terrain := spec.get("terrain") as Node3D
	if layer.has_method("configure_from_region"):
		layer.call("configure_from_region", terrain, self, cells, plant_type.id, cell_size, origin)
	else:
		layer.set("terrain", terrain)


func _create_multimesh_group(group: Dictionary) -> void:
	var transforms: Array = group.get("transforms", [])
	if transforms.is_empty():
		return

	var mesh := group.get("mesh") as Mesh
	if not mesh:
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])

	var custom_aabb := _calculate_group_aabb(transforms, mesh)
	if custom_aabb.size.length_squared() > 0.0:
		custom_aabb = custom_aabb.grow(maxf(0.25, cell_size * 0.05))
		multimesh.custom_aabb = custom_aabb

	var instance := MultiMeshInstance3D.new()
	instance.name = str(group.get("name", "ForestInstances"))
	instance.multimesh = multimesh
	instance.position = group.get("chunk_origin", Vector3.ZERO)
	instance.cast_shadow = int(group.get("shadow_casting", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
	instance.set_meta("forest_chunk", group.get("chunk_coord", Vector2i.ZERO))
	instance.set_meta("forest_chunk_key", str(group.get("chunk_key", "")))
	instance.set_meta("forest_lod_tier", int(group.get("lod_tier", 0)))
	instance.set_meta("forest_base_chunk_keys", _packed_string_array_from_keys(group.get("base_chunk_keys", {})))
	if custom_aabb.size.length_squared() > 0.0:
		instance.custom_aabb = custom_aabb

	var material := group.get("material") as Material
	if material:
		instance.material_override = material

	var plant_type := group.get("plant_type") as ForestPlantTypeData
	if plant_type:
		var lod_tier := int(group.get("lod_tier", 0))
		_configure_visibility_range(instance, plant_type, lod_tier)

	_ensure_runtime_container()
	_runtime_container.add_child(instance, false, INTERNAL_MODE_BACK)
	instance.owner = null


func _configure_visibility_range(instance: GeometryInstance3D, plant_type: ForestPlantTypeData, lod_tier: int) -> void:
	var end_distance := _get_visible_distance_for_lod(plant_type, lod_tier)
	var begin_distance := 0.0
	if lod_tier > 0:
		begin_distance = maxf(0.0, _get_begin_distance_for_lod(plant_type, lod_tier))

	instance.visibility_range_begin = begin_distance
	instance.visibility_range_end = end_distance
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var fade_margin := _get_visibility_fade_margin_for_lod(lod_tier)
	instance.visibility_range_begin_margin = fade_margin if begin_distance > 0.0 else 0.0
	instance.visibility_range_end_margin = fade_margin


func _get_scene_parts(plant_type: ForestPlantTypeData, lod_tier: int) -> Array[Dictionary]:
	var scene := plant_type.get_scene_for_lod(lod_tier)
	if not scene:
		return []

	var cache_key := "%s|%d" % [_get_resource_cache_key(scene), lod_tier]
	var cached: Variant = _scene_part_cache.get(cache_key)
	if cached is Array:
		return cached as Array[Dictionary]

	var parts: Array[Dictionary] = []
	var instance := scene.instantiate()
	if not instance:
		return parts

	if instance.has_method("get_multimesh_parts"):
		parts = _normalize_scene_parts(instance.call("get_multimesh_parts"))
	else:
		_collect_mesh_parts(instance, Transform3D.IDENTITY, true, parts)

	instance.free()
	_scene_part_cache[cache_key] = parts
	return parts


func _normalize_scene_parts(raw_parts: Variant) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if not (raw_parts is Array):
		return parts

	for raw_part: Variant in raw_parts:
		if not (raw_part is Dictionary):
			continue
		var part := raw_part as Dictionary
		var mesh := part.get("mesh") as Mesh
		if not mesh:
			continue
		parts.append({
			"mesh": mesh,
			"transform": part.get("transform", Transform3D.IDENTITY),
			"material": part.get("material"),
			"shadow_casting": int(part.get("shadow_casting", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)),
		})
	return parts


func _collect_mesh_parts(node: Node, parent_transform: Transform3D, is_root: bool, parts: Array[Dictionary]) -> void:
	var current_transform := parent_transform
	if node is Node3D and not is_root:
		current_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			parts.append({
				"mesh": mesh_instance.mesh,
				"transform": current_transform,
				"material": mesh_instance.material_override,
				"shadow_casting": mesh_instance.cast_shadow,
			})

	for child: Node in node.get_children():
		_collect_mesh_parts(child, current_transform, false, parts)


func _get_palette_plant_types_by_id() -> Dictionary:
	var plant_types_by_id: Dictionary = {}
	if not palette:
		return plant_types_by_id
	for plant_type: ForestPlantTypeData in palette.plant_types:
		if plant_type and plant_type.id != &"":
			plant_types_by_id[plant_type.id] = plant_type
	return plant_types_by_id


func _get_effective_plant_ids(plant_ids: Array[StringName]) -> Array[StringName]:
	var normalized := _copy_plant_ids(plant_ids)
	if palette:
		normalized = palette.filter_plant_ids(normalized)
		if normalized.is_empty():
			normalized = palette.get_default_selected_plant_ids()
	return normalized


func _is_chunked_multimesh_plant(plant_type: ForestPlantTypeData) -> bool:
	return (
		plant_type
		and plant_type.scene
		and plant_type.render_strategy == ForestPlantTypeData.RenderStrategy.MULTIMESH
	)


func _is_dense_grass_particle_plant(plant_type: ForestPlantTypeData) -> bool:
	return (
		plant_type
		and plant_type.dense_particle_scene
		and plant_type.render_strategy == ForestPlantTypeData.RenderStrategy.DENSE_GRASS_PARTICLES
	)


func _get_lod_tiers_for_plant_type(plant_type: ForestPlantTypeData) -> Array[int]:
	var tiers: Array[int] = []
	if not plant_type:
		return tiers

	for lod_tier: int in range(LOD_TIER_COUNT):
		if plant_type.get_keep_ratio_for_lod(lod_tier) <= 0.0:
			continue
		if _get_visible_distance_for_lod(plant_type, lod_tier) <= 0.0:
			continue
		if not plant_type.get_scene_for_lod(lod_tier):
			continue
		tiers.append(lod_tier)
	return tiers


func _get_visible_distance_for_lod(plant_type: ForestPlantTypeData, lod_tier: int) -> float:
	if not _uses_region_tree_low_poly_distance(plant_type):
		return plant_type.get_visible_distance_for_lod(lod_tier)

	match lod_tier:
		1:
			return _get_low_poly_distance_for_plant_type(plant_type)
		2:
			return maxf(plant_type.far_visible_distance, _get_low_poly_distance_for_plant_type(plant_type))
		3:
			return maxf(plant_type.billboard_visible_distance, plant_type.far_visible_distance)
		_:
			return plant_type.get_visible_distance_for_lod(lod_tier)


func _get_begin_distance_for_lod(plant_type: ForestPlantTypeData, lod_tier: int) -> float:
	match lod_tier:
		1:
			return plant_type.near_visible_distance * LOD_FADE_BEGIN_RATIO
		2:
			return _get_low_poly_distance_for_plant_type(plant_type) * LOD_FADE_BEGIN_RATIO
		3:
			return plant_type.far_visible_distance * LOD_FADE_BEGIN_RATIO
		_:
			return 0.0


func _get_visibility_fade_margin_for_lod(lod_tier: int) -> float:
	if lod_tier >= 3:
		return tree_billboard_fade_margin_meters
	return tree_lod_fade_margin_meters


func _get_low_poly_distance_for_plant_type(plant_type: ForestPlantTypeData) -> float:
	if _uses_region_tree_low_poly_distance(plant_type):
		return maxf(tree_low_poly_distance, plant_type.near_visible_distance)
	return plant_type.mid_visible_distance


func _uses_region_tree_low_poly_distance(plant_type: ForestPlantTypeData) -> bool:
	return (
		plant_type
		and plant_type.category == ForestPlantTypeData.PlantCategory.TREE
		and plant_type.lod2_scene
	)


func _get_region_scale_multiplier_for_plant_type(plant_type: ForestPlantTypeData) -> float:
	if plant_type and plant_type.category == ForestPlantTypeData.PlantCategory.TREE:
		return maxf(tree_scale_multiplier, 0.05)
	return 1.0


func _get_rng_for_cell_and_plant(cell: Vector2i, plant_id: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_value := int(generation_seed)
	seed_value = _mix_hash(seed_value, cell.x)
	seed_value = _mix_hash(seed_value, cell.y)
	seed_value = _mix_hash(seed_value, _hash_string(str(plant_id)))
	rng.seed = absi(seed_value)
	return rng


func _mix_hash(current: int, value: int) -> int:
	return int((current ^ value) * 16777619)


func _hash_string(value: String) -> int:
	var mixed := int(2166136261)
	for index: int in range(value.length()):
		mixed = _mix_hash(mixed, value.unicode_at(index))
	return mixed


func _get_chunk_coord(cell: Vector2i) -> Vector2i:
	return ForestRegionData.get_chunk_coord_for_cell(cell, _chunk_size_cells)


func _get_chunk_origin(chunk_coord: Vector2i) -> Vector3:
	var safe_chunk_size := maxi(_chunk_size_cells, 1)
	var safe_cell_size := maxf(cell_size, 0.1)
	return origin + Vector3(
		float(chunk_coord.x * safe_chunk_size) * safe_cell_size,
		0.0,
		float(chunk_coord.y * safe_chunk_size) * safe_cell_size
	)


func _get_chunk_coord_for_lod(cell: Vector2i, lod_tier: int) -> Vector2i:
	return ForestRegionData.get_chunk_coord_for_cell(cell, _get_chunk_size_cells_for_lod(lod_tier))


func _get_chunk_origin_for_lod(chunk_coord: Vector2i, lod_tier: int) -> Vector3:
	var safe_chunk_size := _get_chunk_size_cells_for_lod(lod_tier)
	var safe_cell_size := maxf(cell_size, 0.1)
	return origin + Vector3(
		float(chunk_coord.x * safe_chunk_size) * safe_cell_size,
		0.0,
		float(chunk_coord.y * safe_chunk_size) * safe_cell_size
	)


func _get_chunk_size_cells_for_lod(lod_tier: int) -> int:
	var safe_chunk_size := maxi(_chunk_size_cells, 1)
	if lod_tier >= 3:
		return safe_chunk_size * 8
	if lod_tier == 2:
		return safe_chunk_size * 2
	return safe_chunk_size


func _chunk_key_for_lod(chunk_coord: Vector2i, lod_tier: int) -> String:
	if lod_tier <= 1:
		return _chunk_key(chunk_coord)
	return "lod%d:%s" % [lod_tier, _chunk_key(chunk_coord)]


func _expand_chunks_for_lod_multipliers(chunks: Array[Vector2i]) -> Dictionary:
	var expanded: Dictionary = {}
	for chunk_coord: Vector2i in chunks:
		expanded[chunk_coord] = true
		_add_base_chunks_for_multiplier(expanded, chunk_coord, 2)
		_add_base_chunks_for_multiplier(expanded, chunk_coord, 8)
	return expanded


func _add_base_chunks_for_multiplier(expanded: Dictionary, chunk_coord: Vector2i, multiplier: int) -> void:
	var safe_multiplier := maxi(multiplier, 1)
	var parent_chunk := Vector2i(
		_floor_div_int(chunk_coord.x, safe_multiplier),
		_floor_div_int(chunk_coord.y, safe_multiplier)
	)
	for x: int in range(parent_chunk.x * safe_multiplier, parent_chunk.x * safe_multiplier + safe_multiplier):
		for y: int in range(parent_chunk.y * safe_multiplier, parent_chunk.y * safe_multiplier + safe_multiplier):
			expanded[Vector2i(x, y)] = true


func _packed_string_array_from_keys(keys_variant: Variant) -> PackedStringArray:
	var packed := PackedStringArray()
	if not (keys_variant is Dictionary):
		return packed
	var keys := keys_variant as Dictionary
	var sorted_keys: Array[String] = []
	for key: Variant in keys.keys():
		sorted_keys.append(str(key))
	sorted_keys.sort()
	for key: String in sorted_keys:
		packed.append(key)
	return packed


func _chunk_coord_from_key(chunk_key: String) -> Vector2i:
	var normalized := chunk_key
	var prefix_index := normalized.find(":")
	if prefix_index >= 0:
		normalized = normalized.substr(prefix_index + 1)
	var parts := normalized.split(",", false, 1)
	if parts.size() != 2:
		return Vector2i(2147483647, 2147483647)
	return Vector2i(int(parts[0]), int(parts[1]))


func _floor_div_int(value: int, divisor: int) -> int:
	var safe_divisor := maxi(divisor, 1)
	if value >= 0:
		return value / safe_divisor
	return -int(ceili(float(-value) / float(safe_divisor)))


func _get_shadow_casting_for_lod(
	plant_type: ForestPlantTypeData,
	lod_tier: int,
	part_shadow_casting: int
) -> int:
	if not plant_type or plant_type.disable_shadows:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if plant_type.max_shadow_lod_tier < 0 or lod_tier > plant_type.max_shadow_lod_tier:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part_shadow_casting


func _get_surface_world_position_from_local_2d(local_point: Vector2, terrain: Node3D) -> Vector3:
	var world_position := _region_local_to_world(Vector3(local_point.x, 0.0, local_point.y))
	var terrain_height := _get_terrain_height(terrain, world_position)
	if terrain_height != null:
		world_position.y = terrain_height
	return world_position


func _get_terrain_height(terrain: Node3D, world_position: Vector3) -> Variant:
	if not _is_terrain_ready_for_height_queries(terrain):
		return null

	var terrain_data: Variant = terrain.get("data")
	if not (terrain_data is Object):
		return null

	var terrain_data_object := terrain_data as Object
	if not _is_terrain_data_ready_for_height_queries(terrain_data_object):
		return null

	var height: float = terrain_data_object.call("get_height", world_position)
	if is_nan(height) or absf(height) > 1.0e20:
		return null

	return height


func _is_terrain_ready_for_height_queries(terrain: Node3D) -> bool:
	if not is_instance_valid(terrain) or terrain.is_queued_for_deletion():
		return false
	if Engine.is_editor_hint() and not _is_node_in_active_edited_scene(terrain):
		return false
	return true


func _is_terrain_data_ready_for_height_queries(terrain_data_object: Object) -> bool:
	if not is_instance_valid(terrain_data_object) or terrain_data_object.is_queued_for_deletion():
		return false
	if not terrain_data_object.has_method("get_height"):
		return false
	if terrain_data_object.has_method("get_region_count"):
		var region_count := int(terrain_data_object.call("get_region_count"))
		if region_count <= 0:
			return false
	return true


func _get_terrain_node() -> Node3D:
	if terrain_path.is_empty():
		return null

	var terrain := get_node_or_null(terrain_path)
	if terrain is Node3D:
		return terrain
	return null


func _world_to_region_local(world_position: Vector3) -> Vector3:
	if is_inside_tree():
		return to_local(world_position)
	return transform.affine_inverse() * world_position


func _region_local_to_world(local_position: Vector3) -> Vector3:
	if is_inside_tree():
		return to_global(local_position)
	return transform * local_position


func _is_in_active_edited_scene() -> bool:
	return _is_node_in_active_edited_scene(self)


func _is_node_in_active_edited_scene(node: Node) -> bool:
	if not Engine.is_editor_hint():
		return true
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if not Engine.has_singleton(&"EditorInterface"):
		return true

	var editor_interface := Engine.get_singleton(&"EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_edited_scene_root"):
		return true

	var edited_root := editor_interface.call("get_edited_scene_root") as Node
	if not is_instance_valid(edited_root):
		return false

	return node == edited_root or edited_root.is_ancestor_of(node)


func _ensure_runtime_container() -> Node3D:
	if is_instance_valid(_runtime_container):
		return _runtime_container

	_runtime_container = get_node_or_null(RUNTIME_CONTAINER_NAME) as Node3D
	if is_instance_valid(_runtime_container):
		return _runtime_container

	_runtime_container = Node3D.new()
	_runtime_container.name = RUNTIME_CONTAINER_NAME
	add_child(_runtime_container, false, INTERNAL_MODE_BACK)
	_runtime_container.owner = null
	return _runtime_container


func _has_runtime_container() -> bool:
	if is_instance_valid(_runtime_container):
		return true
	_runtime_container = get_node_or_null(RUNTIME_CONTAINER_NAME) as Node3D
	return is_instance_valid(_runtime_container)


func _remove_runtime_chunk(chunk_coord: Vector2i) -> void:
	if not is_instance_valid(_runtime_container):
		return

	var chunk_key := _chunk_key(chunk_coord)
	var children_to_remove: Array[Node] = []
	for child: Node in _runtime_container.get_children(true):
		if str(child.get_meta("forest_chunk_key", "")) == chunk_key:
			children_to_remove.append(child)

	for child: Node in children_to_remove:
		_runtime_container.remove_child(child)
		child.free()


func _remove_runtime_chunks_for_rebuild(near_chunk_filter: Dictionary, far_chunk_filter: Dictionary) -> void:
	if not is_instance_valid(_runtime_container):
		return

	var children_to_remove: Array[Node] = []
	for child: Node in _runtime_container.get_children(true):
		if not (child is MultiMeshInstance3D):
			continue
		var lod_tier := int(child.get_meta("forest_lod_tier", 0))
		var filter := far_chunk_filter if lod_tier >= 2 else near_chunk_filter
		if _runtime_child_intersects_base_chunks(child, filter):
			children_to_remove.append(child)

	for child: Node in children_to_remove:
		_runtime_container.remove_child(child)
		child.free()


func _runtime_child_intersects_base_chunks(child: Node, chunk_filter: Dictionary) -> bool:
	if chunk_filter.is_empty():
		return false
	var packed_keys: Variant = child.get_meta("forest_base_chunk_keys", PackedStringArray())
	if packed_keys is PackedStringArray:
		for key: String in packed_keys:
			var chunk := _chunk_coord_from_key(key)
			if chunk_filter.has(chunk):
				return true
	var chunk_key := str(child.get_meta("forest_chunk_key", ""))
	if not chunk_key.is_empty():
		var chunk := _chunk_coord_from_key(chunk_key)
		return chunk_filter.has(chunk)
	return false


func _remove_dense_grass_layers() -> void:
	if not is_instance_valid(_runtime_container):
		return

	var children_to_remove: Array[Node] = []
	for child: Node in _runtime_container.get_children(true):
		if bool(child.get_meta(DENSE_GRASS_LAYER_META, false)):
			children_to_remove.append(child)

	for child: Node in children_to_remove:
		_runtime_container.remove_child(child)
		child.free()


func _calculate_group_aabb(transforms: Array, mesh: Mesh) -> AABB:
	var mesh_aabb := mesh.get_aabb()
	var bounds := AABB()
	var has_bounds := false
	for transform_variant: Variant in transforms:
		if not (transform_variant is Transform3D):
			continue
		var transformed_aabb := _transform_aabb(mesh_aabb, transform_variant as Transform3D)
		if not has_bounds:
			bounds = transformed_aabb
			has_bounds = true
		else:
			bounds = bounds.merge(transformed_aabb)
	return bounds if has_bounds else AABB()


func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var min_corner := aabb.position
	var max_corner := aabb.position + aabb.size
	var points: Array[Vector3] = [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z),
	]

	var first_point := transform * points[0]
	var result := AABB(first_point, Vector3.ZERO)
	for index: int in range(1, points.size()):
		result = result.expand(transform * points[index])
	return result


func _variant_to_chunk_array(value: Variant) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	if value is Array:
		for chunk_variant: Variant in value:
			if chunk_variant is Vector2i:
				chunks.append(chunk_variant as Vector2i)
	chunks.sort_custom(ForestRegionData._compare_chunks)
	return chunks


func _get_changed_chunks_between(
	before_cells: Array[Vector2i],
	before_cell_plant_ids: Dictionary,
	after_cells: Array[Vector2i],
	after_cell_plant_ids: Dictionary
) -> Array[Vector2i]:
	var chunk_lookup: Dictionary = {}
	var all_cell_lookup: Dictionary = {}
	for cell: Vector2i in before_cells:
		all_cell_lookup[cell] = true
	for cell: Vector2i in after_cells:
		all_cell_lookup[cell] = true

	for key: Variant in all_cell_lookup.keys():
		var cell := key as Vector2i
		var before_has := before_cells.has(cell)
		var after_has := after_cells.has(cell)
		var before_ids := normalize_plant_ids(before_cell_plant_ids.get(cell_key(cell), []))
		var after_ids := normalize_plant_ids(after_cell_plant_ids.get(cell_key(cell), []))
		if before_has != after_has or before_ids != after_ids:
			chunk_lookup[_get_chunk_coord(cell)] = true

	return _variant_to_chunk_array(chunk_lookup.keys())


func _chunk_key(chunk_coord: Vector2i) -> String:
	return "%d,%d" % [chunk_coord.x, chunk_coord.y]


func _mark_startup_phase(label: String, context: Dictionary = {}) -> void:
	if Engine.is_editor_hint():
		return

	var probe := get_node_or_null("/root/StartupPerformanceProbe") if is_inside_tree() else null
	if probe and probe.has_method("mark_phase"):
		probe.call("mark_phase", label, context)


func _cell_plant_maps_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a.keys():
		if not b.has(key):
			return false
		if normalize_plant_ids(a[key]) != normalize_plant_ids(b[key]):
			return false
	return true


func _region_data_matches(other_data: ForestRegionData) -> bool:
	if not other_data:
		return false

	var data := _ensure_region_data()
	if data.chunk_size_cells != other_data.chunk_size_cells:
		return false
	if data.row_runs != other_data.row_runs:
		return false
	if data.plant_sets.size() != other_data.plant_sets.size():
		return false

	for index: int in range(data.plant_sets.size()):
		if data.plant_sets[index] != other_data.plant_sets[index]:
			return false
	return true


func _copy_plant_ids(plant_ids: Array[StringName]) -> Array[StringName]:
	var copied: Array[StringName] = []
	for plant_id: StringName in plant_ids:
		if plant_id != &"" and not copied.has(plant_id):
			copied.append(plant_id)
	return copied


func _get_resource_cache_key(resource: Resource) -> String:
	if not resource:
		return ""
	if not resource.resource_path.is_empty():
		return resource.resource_path
	return str(resource.get_instance_id())
