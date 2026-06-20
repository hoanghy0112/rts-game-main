@tool
extends Node3D
class_name VillageRegion

const DEFAULT_HOUSE_SCENE: PackedScene = preload("res://addons/village_brush/defaults/default_house.tscn")
const DEFAULT_PEASANT_SCENE: PackedScene = preload("res://modules/units/peasant/peasant.tscn")
const DEFAULT_CROP_TYPE: CropTypeData = preload("res://modules/village/fields/crops/rice_crop.tres")
const DEFAULT_BALANCE_CONFIG: Resource = preload("res://modules/village/default_village_balance.tres")
const VILLAGE_STORAGE_SCENE: PackedScene = preload("res://modules/village/house/thatched_hut_on_stilts.tscn")
const FieldPlotGeneratorScript = preload("res://modules/village/fields/field_plot_generator.gd")
const VillageCellData = preload("res://addons/village_brush/village_cell_data.gd")
const RUNTIME_CONTAINER_NAME := "__VillageRuntimeInstances"
const VILLAGE_STORAGE_NODE_NAME := "VillageStorage"
const PRESERVE_VISIBILITY_RANGE_META := &"village_preserve_visibility_range"
const SELECTABLE_TYPE_META := &"village_selectable_type"
const SELECTABLE_REGION_PATH_META := &"village_region_path"
const SELECTABLE_FLAG_TYPE := &"flag"
const SELECTABLE_VILLAGE_TYPE := &"village"
const ROAD_NEIGHBOR_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]
const HOUSE_ATTEMPT_MULTIPLIER := 80
const MIN_TERRAIN_PAINT_STEP := 0.25
const TERRAIN_PAINT_RECORD_STEP := 0.25
const PAINT_PRIORITY_FIELD := 10
const PAINT_PRIORITY_HOUSE := 20
const PAINT_PRIORITY_FIELD_ROAD := 30
const PAINT_PRIORITY_ROAD := 40
const DEFAULT_PEASANT_TARGET_COUNT := 8
const DEFAULT_PEASANT_SPAWN_RATE_PER_MINUTE := 12.0
const DEFAULT_PEASANT_DEATH_RATE_PER_MINUTE := 0.0

signal cells_changed
signal resources_changed
signal food_state_changed(summary: Dictionary)

enum PaintMode {
	HOUSE,
	FIELD,
	ROAD,
	ERASE,
}

@export var village_type: VillageTypeData:
	set(value):
		village_type = value
		resources_changed.emit()

@export var wall_type: WallTypeData:
	set(value):
		wall_type = value
		resources_changed.emit()

@export var house_scene: PackedScene:
	set(value):
		house_scene = value
		resources_changed.emit()

@export var house_scenes: Array[PackedScene] = []:
	set(value):
		house_scenes = value
		resources_changed.emit()

@export var peasant_scene: PackedScene:
	set(value):
		peasant_scene = value
		resources_changed.emit()

@export var default_crop_type: CropTypeData:
	set(value):
		default_crop_type = value
		resources_changed.emit()

@export var balance_config: Resource = DEFAULT_BALANCE_CONFIG:
	set(value):
		balance_config = value
		resources_changed.emit()
		_refresh_food_summary(true)

@export_node_path("Node3D") var terrain_path: NodePath
@export var field_terrain_registry_path: NodePath
@export var time_system_path: NodePath
@export var apply_runtime_terrain_edits := false
@export var auto_apply_terrain_textures := true
@export var auto_apply_field_road_textures := false
@export var async_runtime_preview_on_ready := true
@export_range(1, 64, 1, "or_greater") var runtime_house_batch_size: int = 6
@export_range(1, 64, 1, "or_greater") var runtime_peasant_batch_size: int = 4
@export_range(0.0, 10000.0, 1.0, "or_greater") var village_visible_distance_meters: float = 800.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var village_visibility_fade_margin_meters: float = 80.0

@export var road_texture_id: int = 2
@export_range(0.1, 64.0, 0.1, "or_greater") var road_width: float = 3.2
@export_range(0.1, 16.0, 0.1, "or_greater") var road_sample_spacing: float = 0.35
@export_range(0, 6, 1) var road_curve_iterations: int = 2
@export_range(0.0, 0.49, 0.01) var road_curve_amount: float = 0.35
@export_range(0.0, 1.0, 0.01) var road_texture_strength: float = 0.9
@export_range(0.0, 1.0, 0.01) var road_edge_feather: float = 0.72
@export var field_road_texture_id: int = -1
@export var house_sand_texture_id: int = 2
@export_range(0.0, 1.0, 0.01) var house_texture_strength: float = 0.68
@export_range(0.0, 1.0, 0.01) var house_edge_feather: float = 0.58
@export var field_mud_texture_id: int = 4
@export_range(0.0, 1.0, 0.01) var field_texture_strength: float = 0.88
@export_range(0.0, 1.0, 0.01) var field_edge_feather: float = 0.22

@export_range(0.0, 64.0, 0.1, "or_greater") var house_min_spacing: float = 3.0
@export_range(1.0, 4.0, 0.05, "or_greater") var house_size_spacing_multiplier: float = 1.05
@export_range(0.0, 32.0, 0.1, "or_greater") var house_footprint_padding: float = 0.2
@export_range(0.0, 32.0, 0.1, "or_greater") var house_region_margin: float = 0.75
@export_range(0.0, 32.0, 0.1, "or_greater") var house_road_clearance: float = 2.0
@export_range(0, 512, 1, "or_greater") var house_max_count: int = 32
@export_range(0.25, 4.0, 0.05, "or_greater") var house_density: float = 2.0
@export_range(0.0, 128.0, 0.1, "or_greater") var village_house_ring_margin: float = 6.0
@export_range(0.0, 8.0, 0.05, "or_greater") var village_ring_surface_offset: float = 0.65
@export_range(0.0, 64.0, 0.1, "or_greater") var village_ground_highlight_width: float = 12.0
@export_range(0.1, 8.0, 0.05, "or_greater") var village_storage_model_scale: float = 1.35
@export_range(0.0, 128.0, 0.1, "or_greater") var village_storage_clearance_radius: float = 0.0

@export_range(0, 512, 1, "or_greater") var peasant_target_count: int = DEFAULT_PEASANT_TARGET_COUNT
@export_range(0.0, 512.0, 0.1, "or_greater") var peasant_spawn_rate_per_minute: float = DEFAULT_PEASANT_SPAWN_RATE_PER_MINUTE
@export_range(0.0, 512.0, 0.01, "or_greater") var peasant_death_rate_per_minute: float = DEFAULT_PEASANT_DEATH_RATE_PER_MINUTE
@export_range(0.0, 64.0, 0.1, "or_greater") var peasant_house_spawn_radius: float = 4.5
@export_range(0.0, 256.0, 0.1, "or_greater") var peasant_roam_radius: float = 72.0
@export_range(0.0, 30.0, 0.1, "or_greater") var peasant_death_cleanup_seconds: float = 3.0

@export_range(0.1, 64.0, 0.1, "or_greater") var field_min_plot_width: float = 19.2
@export_range(0.1, 64.0, 0.1, "or_greater") var field_max_plot_width: float = 44.8
@export_range(0.0, 16.0, 0.1, "or_greater") var field_bund_gap: float = 0.35
@export_range(0.0, 16.0, 0.1, "or_greater") var field_road_gap_width: float = 1.2
@export_range(0.1, 64.0, 0.1, "or_greater") var field_min_plot_length: float = 32.0
@export_range(0.1, 128.0, 0.1, "or_greater") var field_max_plot_length: float = 96.0
@export_range(0.1, 16.0, 0.1, "or_greater") var field_sample_step: float = 1.0
@export_range(0.0, 32.0, 0.1, "or_greater") var field_road_clearance: float = 1.0
@export_range(0.0, 1.0, 0.01) var field_horizontal_split_bias: float = 1.0
@export_range(0.0, 1.0, 0.01) var field_shape_variation: float = 0.65
@export_range(0.0, 16.0, 0.1, "or_greater") var field_region_road_margin: float = 0.6
@export_range(0.0, 4.0, 0.01, "or_greater") var field_floor_drop: float = 0.5
@export_range(0.0, 1.0, 0.01, "or_greater") var field_visual_surface_offset: float = 0.06
@export_range(0.01, 8.0, 0.01, "or_greater") var field_edge_slope_width: float = 0.12

@export_range(0.1, 256.0, 0.1, "or_greater") var cell_size: float = 4.0:
	set(value):
		cell_size = maxf(value, 0.1)
		_notify_cells_changed()

@export var origin: Vector3 = Vector3.ZERO:
	set(value):
		origin = value
		_notify_cells_changed()

var _cell_data: VillageCellData
@export var cell_data: VillageCellData:
	get:
		return _cell_data
	set(value):
		_set_cell_data(value)

@export var house_cells: Array[Vector2i] = []:
	set(value):
		if _cell_data:
			var empty_cells: Array[Vector2i] = []
			house_cells = empty_cells
		else:
			house_cells = normalize_cells(value)
		_notify_cells_changed()

@export var field_cells: Array[Vector2i] = []:
	set(value):
		if _cell_data:
			var empty_cells: Array[Vector2i] = []
			field_cells = empty_cells
		else:
			field_cells = normalize_cells(value)
		_notify_cells_changed()

@export var road_cells: Array[Vector2i] = []:
	set(value):
		if _cell_data:
			var empty_cells: Array[Vector2i] = []
			road_cells = empty_cells
		else:
			road_cells = normalize_cells(value)
		_notify_cells_changed()

@export var generation_seed: int = 0

var _suspend_cell_notifications := false
var _runtime_container: Node3D
var _runtime_road_terrain: Node3D
var _runtime_road_control_records: Array[Dictionary] = []
var _runtime_road_original_regions: Array = []
var _runtime_road_copied_regions: Array = []
var _runtime_road_using_region_copies := false
var _runtime_field_terrain_shape_applied := false
var _village_ring_node: Node3D
var _village_ring_material: StandardMaterial3D
var _village_ground_highlight_material: StandardMaterial3D
var _runtime_peasants: Array[Node3D] = []
var _house_food_records: Array[Dictionary] = []
var _house_food_record_lookup: Dictionary = {}
var _village_food_summary: Dictionary = {}
var _village_storage_food_kg := 0.0
var _village_storage_node: Node3D
var _food_total_field_area_m2 := 0.0
var _food_last_shortage_kg := 0.0
var _food_cumulative_shortage_kg := 0.0
var _food_days_elapsed := 0
var _food_last_farmer_count := -1
var _time_system_node: Node
var _last_time_snapshot: Dictionary = {}
var _peasant_runtime_terrain: Node3D
var _peasant_anchors: Dictionary = {}
var _peasant_population_rng := RandomNumberGenerator.new()
var _peasant_spawn_budget := 0.0
var _peasant_death_budget := 0.0
var _peasant_spawn_serial := 0
var _editor_gizmo_update_pending := false
var _house_footprint_cache: Dictionary = {}
var _cached_road_polylines_key := ""
var _cached_road_polylines: Array = []
var _cached_field_generation_key := ""
var _cached_field_generation: Dictionary = {}


static func normalize_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var unique_cells: Dictionary = {}
	for cell: Vector2i in value:
		unique_cells[cell] = true

	var normalized: Array[Vector2i] = []
	for key: Variant in unique_cells.keys():
		var cell: Vector2i = key
		normalized.append(cell)
	normalized.sort_custom(_compare_cells)
	return normalized


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_bind_time_system_day_signal()
	if async_runtime_preview_on_ready:
		rebuild_runtime_preview_deferred.call_deferred()
	else:
		rebuild_runtime_preview()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_update_runtime_peasant_population(delta)


func _exit_tree() -> void:
	_editor_gizmo_update_pending = false
	if Engine.is_editor_hint():
		return

	_unbind_time_system_day_signal()
	_restore_runtime_road_texture()


static func copy_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var copied: Array[Vector2i] = []
	for cell: Vector2i in value:
		copied.append(cell)
	return copied


func get_house_cells() -> Array[Vector2i]:
	if _cell_data:
		return _cell_data.to_house_cells()
	return copy_cells(house_cells)


func get_field_cells() -> Array[Vector2i]:
	if _cell_data:
		return _cell_data.to_field_cells()
	return copy_cells(field_cells)


func get_road_cells() -> Array[Vector2i]:
	if _cell_data:
		return _cell_data.to_road_cells()
	return copy_cells(road_cells)


func has_cell_data() -> bool:
	return _cell_data != null


func _set_cell_data(value: VillageCellData) -> void:
	if _cell_data == value:
		return

	var legacy_house_cells := copy_cells(house_cells)
	var legacy_field_cells := copy_cells(field_cells)
	var legacy_road_cells := copy_cells(road_cells)
	_cell_data = value

	if _cell_data:
		if (
			_cell_data.is_empty()
			and (
				not legacy_house_cells.is_empty()
				or not legacy_field_cells.is_empty()
				or not legacy_road_cells.is_empty()
			)
		):
			_cell_data.encode_from_cells(legacy_house_cells, legacy_field_cells, legacy_road_cells)
			if _save_cell_data_resource_if_external():
				_clear_inline_cell_arrays()
		else:
			_clear_inline_cell_arrays()

	_notify_cells_changed()


func _clear_inline_cell_arrays() -> void:
	_suspend_cell_notifications = true
	house_cells = []
	field_cells = []
	road_cells = []
	_suspend_cell_notifications = false


func _save_cell_data_resource_if_external() -> bool:
	if not Engine.is_editor_hint() or not _cell_data:
		return false

	# Property setters can run while Godot is still loading scenes and refreshing script classes.
	# Saving then can recursively trigger the editor filesystem scanner.
	if not is_inside_tree():
		return false

	var resource_path := _cell_data.resource_path
	if resource_path.is_empty() or not resource_path.begins_with("res://"):
		return false

	var error := ResourceSaver.save(_cell_data, resource_path)
	if error != OK:
		push_warning("VillageRegion could not save cell_data resource %s: %d" % [resource_path, error])
		return false
	return true


static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


func set_cell_arrays(
	new_house_cells: Array[Vector2i],
	new_field_cells: Array[Vector2i],
	new_road_cells: Array[Vector2i] = []
) -> void:
	var normalized_house_cells := normalize_cells(new_house_cells)
	var normalized_field_cells := normalize_cells(new_field_cells)
	var normalized_road_cells := normalize_cells(new_road_cells)

	if _cell_data:
		_suspend_cell_notifications = true
		_cell_data.encode_from_cells(normalized_house_cells, normalized_field_cells, normalized_road_cells)
		house_cells = []
		field_cells = []
		road_cells = []
		_suspend_cell_notifications = false
		_save_cell_data_resource_if_external()
		_notify_cells_changed()
		return

	_suspend_cell_notifications = true
	house_cells = normalized_house_cells
	field_cells = normalized_field_cells
	road_cells = normalized_road_cells
	_suspend_cell_notifications = false
	_notify_cells_changed()


func paint_cells(cells: Array[Vector2i], mode: int) -> bool:
	var active_house_cells := get_house_cells()
	var active_field_cells := get_field_cells()
	var active_road_cells := get_road_cells()
	var house_lookup := _to_cell_lookup(active_house_cells)
	var field_lookup := _to_cell_lookup(active_field_cells)
	var road_lookup := _to_cell_lookup(active_road_cells)

	for cell: Vector2i in cells:
		match mode:
			PaintMode.HOUSE:
				house_lookup[cell] = true
				field_lookup.erase(cell)
			PaintMode.FIELD:
				field_lookup[cell] = true
				house_lookup.erase(cell)
			PaintMode.ROAD:
				road_lookup[cell] = true
			PaintMode.ERASE:
				house_lookup.erase(cell)
				field_lookup.erase(cell)
				road_lookup.erase(cell)

	var new_house_cells := _lookup_to_cells(house_lookup)
	var new_field_cells := _lookup_to_cells(field_lookup)
	var new_road_cells := _lookup_to_cells(road_lookup)
	if (
		new_house_cells == active_house_cells
		and new_field_cells == active_field_cells
		and new_road_cells == active_road_cells
	):
		return false

	set_cell_arrays(new_house_cells, new_field_cells, new_road_cells)
	return true


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


func to_runtime_data() -> Dictionary:
	var active_house_cells := get_house_cells()
	var active_field_cells := get_field_cells()
	var active_road_cells := get_road_cells()
	return {
		"village_type": village_type,
		"wall_type": wall_type,
		"house_scene": _get_house_scene(),
		"house_scenes": _get_house_scenes(),
		"peasant_scene": _get_peasant_scene(),
		"default_crop_type": _get_default_crop_type(),
		"balance_config": _get_balance_config(),
		"terrain_path": terrain_path,
		"field_terrain_registry_path": field_terrain_registry_path,
		"time_system_path": time_system_path,
		"apply_runtime_terrain_edits": apply_runtime_terrain_edits,
		"auto_apply_terrain_textures": auto_apply_terrain_textures,
		"auto_apply_field_road_textures": auto_apply_field_road_textures,
		"runtime_peasant_batch_size": runtime_peasant_batch_size,
		"village_visible_distance_meters": village_visible_distance_meters,
		"village_visibility_fade_margin_meters": village_visibility_fade_margin_meters,
		"road_texture_id": road_texture_id,
		"road_width": road_width,
		"road_sample_spacing": road_sample_spacing,
		"road_curve_iterations": road_curve_iterations,
		"road_curve_amount": road_curve_amount,
		"road_texture_strength": road_texture_strength,
		"road_edge_feather": road_edge_feather,
		"field_road_texture_id": field_road_texture_id,
		"house_sand_texture_id": house_sand_texture_id,
		"house_texture_strength": house_texture_strength,
		"house_edge_feather": house_edge_feather,
		"field_mud_texture_id": field_mud_texture_id,
		"field_texture_strength": field_texture_strength,
		"field_edge_feather": field_edge_feather,
		"house_min_spacing": house_min_spacing,
		"house_size_spacing_multiplier": house_size_spacing_multiplier,
		"house_footprint_padding": house_footprint_padding,
		"house_region_margin": house_region_margin,
		"house_road_clearance": house_road_clearance,
		"house_max_count": house_max_count,
		"house_density": house_density,
		"village_house_ring_margin": village_house_ring_margin,
		"village_ring_surface_offset": village_ring_surface_offset,
		"village_ground_highlight_width": village_ground_highlight_width,
		"peasant_target_count": _get_effective_peasant_target_count(),
		"peasant_spawn_rate_per_minute": _get_effective_peasant_spawn_rate_per_minute(),
		"peasant_death_rate_per_minute": _get_effective_peasant_death_rate_per_minute(),
		"peasant_house_spawn_radius": peasant_house_spawn_radius,
		"peasant_roam_radius": peasant_roam_radius,
		"peasant_death_cleanup_seconds": peasant_death_cleanup_seconds,
		"field_min_plot_width": field_min_plot_width,
		"field_max_plot_width": field_max_plot_width,
		"field_bund_gap": field_bund_gap,
		"field_road_gap_width": field_road_gap_width,
		"field_min_plot_length": field_min_plot_length,
		"field_max_plot_length": field_max_plot_length,
		"field_sample_step": field_sample_step,
		"field_road_clearance": field_road_clearance,
		"field_horizontal_split_bias": field_horizontal_split_bias,
		"field_shape_variation": field_shape_variation,
		"field_region_road_margin": field_region_road_margin,
		"field_floor_drop": field_floor_drop,
		"field_visual_surface_offset": field_visual_surface_offset,
		"field_edge_slope_width": field_edge_slope_width,
		"cell_size": cell_size,
		"origin": origin,
		"house_cells": active_house_cells,
		"field_cells": active_field_cells,
		"road_cells": active_road_cells,
		"generation_seed": generation_seed,
		"global_transform": global_transform if is_inside_tree() else transform,
	}


func get_macro_detail_data() -> Dictionary:
	var data := to_runtime_data()
	var road_polylines := _build_road_polylines()
	var field_generation := _build_field_generation(road_polylines)
	data["road_polylines"] = _duplicate_polylines(road_polylines)
	data["field_generation"] = _duplicate_field_generation(field_generation)
	return data


func get_house_food_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record: Dictionary in _house_food_records:
		records.append(record.duplicate(true))
	return records


func get_house_food_record(id: Variant) -> Dictionary:
	var house_id := StringName(str(id))
	if not _house_food_record_lookup.has(house_id):
		return {}
	return (_house_food_record_lookup[house_id] as Dictionary).duplicate(true)


func get_village_food_summary() -> Dictionary:
	if _village_food_summary.is_empty():
		_refresh_food_summary(false)
	return _village_food_summary.duplicate(true)


func get_village_storage_summary() -> Dictionary:
	if _village_food_summary.is_empty():
		_refresh_food_summary(false)
	return {
		"storage_food_kg": _village_storage_food_kg,
		"storage_world_position": get_village_storage_world_position(),
		"summary": _village_food_summary.duplicate(true),
	}


func get_village_storage_world_position() -> Vector3:
	if is_instance_valid(_village_storage_node):
		return _village_storage_node.global_position

	var center := _get_village_storage_center_local_2d()
	var terrain := _get_terrain_node()
	return _get_surface_world_position_from_local_2d(center, terrain)


func withdraw_food_kg(amount_kg: float) -> float:
	var requested := maxf(amount_kg, 0.0)
	if requested <= 0.0:
		return 0.0

	var withdrawn := minf(_village_storage_food_kg, requested)
	if withdrawn <= 0.0:
		return 0.0

	_village_storage_food_kg = maxf(_village_storage_food_kg - withdrawn, 0.0)
	_refresh_food_summary(true)
	return withdrawn


func deposit_food_kg(amount_kg: float) -> float:
	var deposited := maxf(amount_kg, 0.0)
	if deposited <= 0.0:
		return 0.0

	_village_storage_food_kg += deposited
	_refresh_food_summary(true)
	return deposited


func advance_food_days(days: int) -> void:
	var day_count := maxi(days, 0)
	if day_count <= 0:
		return

	var daily_production := _get_daily_rice_production_kg()
	var daily_consumption := _get_daily_rice_consumption_kg()
	var shortage_total := 0.0
	for _day: int in range(day_count):
		_village_storage_food_kg += daily_production
		var consumed := minf(_village_storage_food_kg, daily_consumption)
		_village_storage_food_kg = maxf(_village_storage_food_kg - consumed, 0.0)
		shortage_total += maxf(daily_consumption - consumed, 0.0)

	_food_last_shortage_kg = shortage_total
	_food_cumulative_shortage_kg += shortage_total
	_food_days_elapsed += day_count
	_refresh_food_summary(true)


func _bind_time_system_day_signal() -> void:
	_unbind_time_system_day_signal()
	_time_system_node = _get_time_system_node()
	if not _time_system_node:
		return

	var callable := Callable(self, "_on_time_day_changed")
	if _time_system_node.has_signal("day_changed") and not _time_system_node.is_connected("day_changed", callable):
		_time_system_node.connect("day_changed", callable)

	if _time_system_node.has_method("get_current_snapshot"):
		var snapshot: Variant = _time_system_node.call("get_current_snapshot")
		if snapshot is Dictionary:
			_last_time_snapshot = (snapshot as Dictionary).duplicate(true)


func _unbind_time_system_day_signal() -> void:
	if not _time_system_node:
		return

	var callable := Callable(self, "_on_time_day_changed")
	if _time_system_node.has_signal("day_changed") and _time_system_node.is_connected("day_changed", callable):
		_time_system_node.disconnect("day_changed", callable)
	_time_system_node = null


func _get_time_system_node() -> Node:
	if time_system_path.is_empty():
		return null
	return get_node_or_null(time_system_path)


func _on_time_day_changed(snapshot: Dictionary, days_elapsed: int = 1) -> void:
	_last_time_snapshot = snapshot.duplicate(true)
	var day_count := maxi(days_elapsed, 0)
	if day_count <= 0:
		return
	advance_food_days(day_count)


func rebuild_runtime_preview() -> void:
	if Engine.is_editor_hint():
		return

	clear_runtime_instances()

	var active_house_cells := get_house_cells()
	var active_field_cells := get_field_cells()
	var active_road_cells := get_road_cells()
	if active_house_cells.is_empty() and active_field_cells.is_empty() and active_road_cells.is_empty():
		return

	_runtime_container = Node3D.new()
	_runtime_container.name = RUNTIME_CONTAINER_NAME
	add_child(_runtime_container)
	_runtime_container.owner = null

	var terrain := _get_terrain_node()
	var road_polylines := _build_road_polylines()
	var field_generation := _build_field_generation(road_polylines)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(generation_seed)
	var house_placements := _build_house_placements(road_polylines, rng)
	_initialize_house_food_records(house_placements, field_generation)

	if apply_runtime_terrain_edits or auto_apply_terrain_textures:
		_apply_field_terrain_and_road_texture(
			terrain,
			road_polylines,
			field_generation,
			house_placements,
			apply_runtime_terrain_edits,
			apply_runtime_terrain_edits or auto_apply_field_road_textures
		)
	else:
		_runtime_field_terrain_shape_applied = false
	_generate_houses(terrain, house_placements)
	_generate_fields(terrain, field_generation)
	_generate_village_ring(terrain, house_placements)
	_generate_village_flag(terrain)
	_generate_village_storage(terrain, house_placements)
	_generate_peasants(terrain, house_placements, road_polylines, field_generation)
	_refresh_food_summary(true)


func rebuild_runtime_preview_deferred() -> void:
	if not is_inside_tree():
		return

	await get_tree().process_frame
	if not is_inside_tree():
		return

	await rebuild_runtime_preview_async()


func rebuild_runtime_preview_async() -> void:
	if Engine.is_editor_hint():
		return

	clear_runtime_instances()

	var active_house_cells := get_house_cells()
	var active_field_cells := get_field_cells()
	var active_road_cells := get_road_cells()
	if active_house_cells.is_empty() and active_field_cells.is_empty() and active_road_cells.is_empty():
		_mark_startup_phase("village_ready", {"cells": 0})
		return

	_runtime_container = Node3D.new()
	_runtime_container.name = RUNTIME_CONTAINER_NAME
	add_child(_runtime_container)
	_runtime_container.owner = null

	var terrain := _get_terrain_node()
	_mark_startup_phase("village_build_start", {
		"field_cells": active_field_cells.size(),
		"house_cells": active_house_cells.size(),
		"road_cells": active_road_cells.size(),
	})

	var road_polylines := _build_road_polylines()
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var field_generation := _build_field_generation(road_polylines)
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(generation_seed)
	var house_placements := _build_house_placements(road_polylines, rng)
	_initialize_house_food_records(house_placements, field_generation)
	_mark_startup_phase("village_layout_ready", {
		"houses": house_placements.size(),
		"plots": (field_generation.get("plots", []) as Array).size(),
	})

	if apply_runtime_terrain_edits or auto_apply_terrain_textures:
		_apply_field_terrain_and_road_texture(
			terrain,
			road_polylines,
			field_generation,
			house_placements,
			apply_runtime_terrain_edits,
			apply_runtime_terrain_edits or auto_apply_field_road_textures
		)
	else:
		_runtime_field_terrain_shape_applied = false
	await get_tree().process_frame
	if not is_inside_tree():
		return

	await _generate_houses_async(terrain, house_placements)
	if not is_inside_tree():
		return

	_generate_fields_async(terrain, field_generation)
	_generate_village_ring(terrain, house_placements)
	_generate_village_flag(terrain)
	_generate_village_storage(terrain, house_placements)
	await _generate_peasants_async(terrain, house_placements, road_polylines, field_generation)
	_refresh_food_summary(true)
	_mark_startup_phase("village_ready", {
		"houses": house_placements.size(),
		"peasants": _get_alive_peasant_count(),
		"plots": (field_generation.get("plots", []) as Array).size(),
	})


func clear_runtime_instances() -> void:
	_restore_runtime_road_texture()
	_runtime_field_terrain_shape_applied = false
	_runtime_peasants.clear()
	_village_ring_node = null
	_village_ring_material = null
	_village_ground_highlight_material = null
	_village_storage_node = null
	_house_food_records.clear()
	_house_food_record_lookup.clear()
	_village_storage_food_kg = 0.0
	_food_total_field_area_m2 = 0.0
	_food_last_shortage_kg = 0.0
	_food_cumulative_shortage_kg = 0.0
	_food_days_elapsed = 0
	_food_last_farmer_count = -1
	_peasant_runtime_terrain = null
	_peasant_anchors.clear()
	_peasant_spawn_budget = 0.0
	_peasant_death_budget = 0.0

	var container := _runtime_container
	if not is_instance_valid(container):
		container = get_node_or_null(RUNTIME_CONTAINER_NAME) as Node3D

	if is_instance_valid(container):
		var parent := container.get_parent()
		if parent:
			parent.remove_child(container)
		container.free()

	_runtime_container = null
	_refresh_food_summary(true)


func _to_cell_lookup(cells: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for cell: Vector2i in cells:
		lookup[cell] = true
	return lookup


func _lookup_to_cells(lookup: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for key: Variant in lookup.keys():
		var cell: Vector2i = key
		cells.append(cell)
	return normalize_cells(cells)


func _build_house_placements(road_polylines: Array, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var scenes := _get_house_scenes()
	var active_house_cells := get_house_cells()
	if scenes.is_empty() or active_house_cells.is_empty() or house_max_count <= 0:
		return placements

	var house_lookup := _to_cell_lookup(active_house_cells)
	var storage_center := _get_village_storage_center_local_2d()
	var storage_clearance_radius := _get_village_storage_reserved_radius()
	var target_house_count := _get_effective_house_max_count()
	var attempts := maxi(
		target_house_count * HOUSE_ATTEMPT_MULTIPLIER,
		ceili(float(active_house_cells.size()) * 12.0 * _get_safe_house_density())
	)

	for _attempt: int in range(attempts):
		if placements.size() >= target_house_count:
			break

		var cell := active_house_cells[rng.randi_range(0, active_house_cells.size() - 1)]
		var local_point := _get_random_point_in_cell(cell, rng)

		var scene := _get_house_scene_for_index(placements.size(), rng)
		if not scene:
			return placements

		var footprint_data := _get_house_footprint_data(scene)
		var footprint := float(footprint_data.get("footprint", cell_size))
		var footprint_radius := float(footprint_data.get("radius", footprint * 0.5))
		var placement_margin := house_region_margin + footprint_radius
		var road_clearance := maxf(0.0, road_width * 0.5 + house_road_clearance + footprint_radius)

		if not _is_point_in_shrunken_cells(local_point, house_lookup, placement_margin):
			continue
		if _is_point_near_roads(local_point, road_polylines, road_clearance):
			continue
		if not _has_house_spacing(local_point, footprint, placements):
			continue
		if _is_house_overlapping_storage(local_point, footprint_radius, storage_center, storage_clearance_radius):
			continue

		placements.append({
			"scene": scene,
			"position": local_point,
			"rotation_y": _get_house_yaw(local_point, road_polylines, rng),
			"footprint": footprint,
			"radius": footprint_radius,
		})

	return placements


func _generate_houses(terrain: Node3D, house_placements: Array[Dictionary]) -> void:
	for placement_index: int in range(house_placements.size()):
		var placement := house_placements[placement_index]
		var scene := placement.get("scene") as PackedScene
		if not scene:
			continue

		var spatial := _instantiate_runtime_scene(scene, "House", placement_index)
		if not spatial:
			return

		var local_point: Vector2 = placement.get("position", Vector2.ZERO)
		_set_runtime_node_position(spatial, local_point, terrain)
		spatial.rotation.y = float(placement.get("rotation_y", 0.0))
		_configure_runtime_visibility_recursive(
			spatial,
			village_visible_distance_meters,
			village_visibility_fade_margin_meters
		)


func _generate_houses_async(terrain: Node3D, house_placements: Array[Dictionary]) -> void:
	for placement_index: int in range(house_placements.size()):
		if not is_inside_tree():
			return

		var placement := house_placements[placement_index]
		var scene := placement.get("scene") as PackedScene
		if not scene:
			continue

		var spatial := _instantiate_runtime_scene(scene, "House", placement_index)
		if not spatial:
			return

		var local_point: Vector2 = placement.get("position", Vector2.ZERO)
		_set_runtime_node_position(spatial, local_point, terrain)
		spatial.rotation.y = float(placement.get("rotation_y", 0.0))
		_configure_runtime_visibility_recursive(
			spatial,
			village_visible_distance_meters,
			village_visibility_fade_margin_meters
		)

		if (placement_index + 1) % runtime_house_batch_size == 0:
			await get_tree().process_frame


func _generate_village_ring(terrain: Node3D, house_placements: Array[Dictionary]) -> void:
	if not _runtime_container or house_placements.is_empty():
		return

	var metrics := _get_house_ring_metrics(house_placements)
	var center: Vector2 = metrics.get("center", Vector2.ZERO)
	var radius := maxf(float(metrics.get("radius", 0.0)), cell_size)
	var center_world := _get_surface_world_position_from_local_2d(center, terrain)
	var ring := Node3D.new()
	ring.name = "VillageSelectionRing"
	ring.set_meta(SELECTABLE_TYPE_META, SELECTABLE_VILLAGE_TYPE)
	ring.set_meta(SELECTABLE_REGION_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	_runtime_container.add_child(ring)
	ring.owner = null
	ring.position = _world_to_region_local(center_world)

	_village_ring_material = _make_village_ring_material(false)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RingMesh"
	mesh_instance.mesh = _make_village_ring_mesh(terrain, center, center_world.y, radius)
	mesh_instance.material_override = _village_ring_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ring.add_child(mesh_instance)

	_village_ground_highlight_material = _make_village_ground_highlight_material(false)
	var ground_highlight := MeshInstance3D.new()
	ground_highlight.name = "GroundHighlightMesh"
	ground_highlight.mesh = _make_village_ground_highlight_mesh(terrain, center, center_world.y, radius)
	ground_highlight.material_override = _village_ground_highlight_material
	ground_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_highlight.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ring.add_child(ground_highlight)

	_add_village_ring_click_proxies(ring, radius)
	_village_ring_node = ring
	_configure_runtime_visibility_recursive(
		ring,
		village_visible_distance_meters,
		village_visibility_fade_margin_meters
	)


func set_village_hovered(hovered: bool) -> void:
	if not is_instance_valid(_village_ring_node) or not _village_ring_material:
		return

	if hovered:
		_village_ring_material.albedo_color = Color(1.0, 0.82, 0.34, 0.72)
		_village_ring_material.emission = Color(1.0, 0.58, 0.12, 1.0)
		_village_ring_material.emission_energy_multiplier = 0.55
		if _village_ground_highlight_material:
			_village_ground_highlight_material.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	else:
		_village_ring_material.albedo_color = Color(0.34, 0.86, 0.9, 0.48)
		_village_ring_material.emission = Color(0.12, 0.48, 0.54, 1.0)
		_village_ring_material.emission_energy_multiplier = 0.22
		if _village_ground_highlight_material:
			_village_ground_highlight_material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	_village_ring_node.scale = Vector3.ONE


func _get_house_ring_metrics(house_placements: Array[Dictionary]) -> Dictionary:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)

	for placement: Dictionary in house_placements:
		var point: Vector2 = placement.get("position", Vector2.ZERO)
		var radius := maxf(float(placement.get("radius", cell_size * 0.5)), cell_size * 0.5)
		min_point.x = minf(min_point.x, point.x - radius)
		min_point.y = minf(min_point.y, point.y - radius)
		max_point.x = maxf(max_point.x, point.x + radius)
		max_point.y = maxf(max_point.y, point.y + radius)

	if not is_finite(min_point.x) or not is_finite(max_point.x):
		return {"center": _get_village_center_local_2d(), "radius": cell_size}

	var center := (min_point + max_point) * 0.5
	var radius := 0.0
	for corner: Vector2 in [
		min_point,
		Vector2(min_point.x, max_point.y),
		max_point,
		Vector2(max_point.x, min_point.y),
	]:
		radius = maxf(radius, center.distance_to(corner))

	return {
		"center": center,
		"radius": radius + maxf(village_house_ring_margin, 0.0),
	}


func _make_village_ring_mesh(terrain: Node3D, center: Vector2, center_height: float, radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var segments := clampi(ceili(radius * TAU / 5.0), 32, 96)
	var band_width := clampf(radius * 0.035, 0.65, 2.4)
	var inner_radius := maxf(radius - band_width * 0.5, 0.1)
	var outer_radius := radius + band_width * 0.5

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(segments):
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var inner_a := _get_ring_vertex(terrain, center, center_height, inner_radius, angle_a)
		var outer_a := _get_ring_vertex(terrain, center, center_height, outer_radius, angle_a)
		var inner_b := _get_ring_vertex(terrain, center, center_height, inner_radius, angle_b)
		var outer_b := _get_ring_vertex(terrain, center, center_height, outer_radius, angle_b)

		mesh.surface_add_vertex(inner_a)
		mesh.surface_add_vertex(outer_a)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_add_vertex(inner_a)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_add_vertex(inner_b)
	mesh.surface_end()
	return mesh


func _make_village_ground_highlight_mesh(terrain: Node3D, center: Vector2, center_height: float, radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var segments := clampi(ceili(radius * TAU / 5.0), 32, 128)
	var ring_band_width := clampf(radius * 0.035, 0.65, 2.4)
	var inner_radius := radius + ring_band_width * 0.55
	var outer_radius := inner_radius + clampf(village_ground_highlight_width, 2.0, 64.0)
	var inner_color := Color(0.54, 0.92, 0.48, 0.24)
	var outer_color := Color(0.54, 0.92, 0.48, 0.0)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(segments):
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var inner_a := _get_ground_highlight_vertex(terrain, center, center_height, inner_radius, angle_a)
		var outer_a := _get_ground_highlight_vertex(terrain, center, center_height, outer_radius, angle_a)
		var inner_b := _get_ground_highlight_vertex(terrain, center, center_height, inner_radius, angle_b)
		var outer_b := _get_ground_highlight_vertex(terrain, center, center_height, outer_radius, angle_b)

		mesh.surface_set_color(inner_color)
		mesh.surface_add_vertex(inner_a)
		mesh.surface_set_color(outer_color)
		mesh.surface_add_vertex(outer_a)
		mesh.surface_set_color(outer_color)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_set_color(inner_color)
		mesh.surface_add_vertex(inner_a)
		mesh.surface_set_color(outer_color)
		mesh.surface_add_vertex(outer_b)
		mesh.surface_set_color(inner_color)
		mesh.surface_add_vertex(inner_b)
	mesh.surface_end()
	return mesh


func _get_ring_vertex(
	terrain: Node3D,
	center: Vector2,
	center_height: float,
	radius: float,
	angle: float
) -> Vector3:
	var local_point := center + Vector2(cos(angle), sin(angle)) * radius
	var world_position := _get_surface_world_position_from_local_2d(local_point, terrain)
	return Vector3(
		local_point.x - center.x,
		world_position.y - center_height + maxf(village_ring_surface_offset, 0.0),
		local_point.y - center.y
	)


func _get_ground_highlight_vertex(
	terrain: Node3D,
	center: Vector2,
	center_height: float,
	radius: float,
	angle: float
) -> Vector3:
	var local_point := center + Vector2(cos(angle), sin(angle)) * radius
	var world_position := _get_surface_world_position_from_local_2d(local_point, terrain)
	return Vector3(
		local_point.x - center.x,
		world_position.y - center_height + maxf(village_ring_surface_offset * 0.5, 0.25),
		local_point.y - center.y
	)


func _add_village_ring_click_proxies(ring: Node3D, radius: float) -> void:
	var segments := clampi(ceili(radius * TAU / maxf(cell_size * 1.5, 4.0)), 16, 48)
	var arc_length := radius * TAU / float(segments)
	var radial_width := clampf(radius * 0.08, 2.4, 7.5)

	_add_village_center_click_proxy(ring, radius)

	for index: int in range(segments):
		var angle := TAU * (float(index) + 0.5) / float(segments)
		var proxy := StaticBody3D.new()
		proxy.name = "VillageRingClickProxy_%02d" % index
		proxy.collision_layer = 1
		proxy.collision_mask = 0
		proxy.input_ray_pickable = true
		proxy.position = Vector3(cos(angle) * radius, maxf(village_ring_surface_offset, 0.0), sin(angle) * radius)
		proxy.rotation.y = PI * 0.5 - angle

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(arc_length * 0.92, 1.0), 2.2, radial_width)
		shape.shape = box
		shape.position = Vector3(0.0, 1.0, 0.0)
		proxy.add_child(shape)
		ring.add_child(proxy)


func _add_village_center_click_proxy(ring: Node3D, radius: float) -> void:
	var proxy := StaticBody3D.new()
	proxy.name = "VillageCenterClickProxy"
	proxy.collision_layer = 1
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	proxy.position = Vector3(0.0, maxf(village_ring_surface_offset, 0.0), 0.0)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(radius, 0.1)
	cylinder.height = 5.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.5, 0.0)
	proxy.add_child(shape)
	ring.add_child(proxy)


func _make_village_ring_material(hovered: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 20
	material.emission_enabled = true
	if hovered:
		material.albedo_color = Color(1.0, 0.82, 0.34, 0.72)
		material.emission = Color(1.0, 0.58, 0.12, 1.0)
		material.emission_energy_multiplier = 0.55
	else:
		material.albedo_color = Color(0.34, 0.86, 0.9, 0.48)
		material.emission = Color(0.12, 0.48, 0.54, 1.0)
		material.emission_energy_multiplier = 0.22
	return material


func _make_village_ground_highlight_material(hovered: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 18
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.95 if hovered else 0.55)
	return material


func _generate_village_flag(terrain: Node3D) -> void:
	if not _runtime_container:
		return

	var center := _get_village_center_local_2d()
	var flag := Node3D.new()
	flag.name = "VillageFlag"
	flag.set_meta(SELECTABLE_TYPE_META, SELECTABLE_FLAG_TYPE)
	flag.set_meta(SELECTABLE_REGION_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	_runtime_container.add_child(flag)
	flag.owner = null
	_set_runtime_node_position(flag, center, terrain)

	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 3.2
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 1.6, 0.0)
	pole.material_override = _make_flag_material(Color(0.52, 0.36, 0.16, 1.0))
	flag.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(1.2, 0.68, 0.045)
	banner.mesh = banner_mesh
	banner.position = Vector3(0.62, 2.55, 0.0)
	banner.material_override = _make_flag_material(Color(0.78, 0.12, 0.1, 1.0))
	flag.add_child(banner)

	var proxy := StaticBody3D.new()
	proxy.name = "VillageFlagClickProxy"
	proxy.collision_layer = 1
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_FLAG_TYPE)
	proxy.set_meta(SELECTABLE_REGION_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.8, 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.9, 0.0)
	proxy.add_child(shape)
	flag.add_child(proxy)
	_configure_runtime_visibility_recursive(
		flag,
		village_visible_distance_meters,
		village_visibility_fade_margin_meters
	)


func _generate_village_storage(terrain: Node3D, house_placements: Array[Dictionary]) -> void:
	if not _runtime_container:
		return

	var center := _get_village_storage_center_local_2d(house_placements)
	var storage := Node3D.new()
	storage.name = VILLAGE_STORAGE_NODE_NAME
	_runtime_container.add_child(storage)
	storage.owner = null
	_set_runtime_node_position(storage, center, terrain)
	_village_storage_node = storage

	var storage_model := VILLAGE_STORAGE_SCENE.instantiate()
	if storage_model is Node3D:
		var model_node := storage_model as Node3D
		model_node.name = "StorageHut"
		model_node.scale *= maxf(village_storage_model_scale, 0.1)
		storage.add_child(model_node)
		model_node.owner = null
	else:
		storage_model.free()

	var marker := Node3D.new()
	marker.name = "StorageMarker"
	var marker_offset := maxf(_get_village_storage_reserved_radius() * 0.42, 2.0)
	marker.position = Vector3(-marker_offset, 0.0, -marker_offset * 0.62)
	storage.add_child(marker)

	var pole := MeshInstance3D.new()
	pole.name = "MarkerPole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.1
	pole_mesh.bottom_radius = 0.1
	pole_mesh.height = 8.4
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 4.2, 0.0)
	pole.material_override = _make_flag_material(Color(0.34, 0.22, 0.11, 1.0))
	marker.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "FoodDepotBanner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(3.15, 1.72, 0.08)
	banner.mesh = banner_mesh
	banner.position = Vector3(1.58, 7.05, 0.0)
	banner.material_override = _make_flag_material(Color(0.92, 0.74, 0.24, 1.0))
	marker.add_child(banner)

	var grain := MeshInstance3D.new()
	grain.name = "GrainMark"
	var grain_mesh := CylinderMesh.new()
	grain_mesh.top_radius = 0.18
	grain_mesh.bottom_radius = 0.18
	grain_mesh.height = 0.065
	grain_mesh.radial_segments = 12
	grain.mesh = grain_mesh
	grain.rotation.x = PI * 0.5
	grain.position = Vector3(1.58, 7.05, 0.055)
	grain.material_override = _make_flag_material(Color(0.48, 0.32, 0.08, 1.0))
	marker.add_child(grain)

	_configure_runtime_visibility_recursive(
		storage,
		village_visible_distance_meters,
		village_visibility_fade_margin_meters
	)


func _make_flag_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _build_field_generation(road_polylines: Array) -> Dictionary:
	var crop_type := _get_default_crop_type()
	var cache_key := _get_field_generation_cache_key(crop_type, road_polylines)
	if _cached_field_generation_key == cache_key and not _cached_field_generation.is_empty():
		return _duplicate_field_generation(_cached_field_generation)

	var field_generation := _build_field_generation_uncached(crop_type, road_polylines)
	_cached_field_generation_key = cache_key
	_cached_field_generation = _duplicate_field_generation(field_generation)
	return field_generation


func _build_field_generation_uncached(crop_type: CropTypeData, road_polylines: Array) -> Dictionary:
	var active_field_cells := get_field_cells()
	if not crop_type or active_field_cells.is_empty():
		return {
			"crop_type": crop_type,
			"plots": [],
			"field_road_polylines": [],
			"field_cells": [],
		}

	var generator := FieldPlotGeneratorScript.new()
	generator.cell_size = cell_size
	generator.origin = origin
	generator.generation_seed = generation_seed
	generator.min_plot_width = field_min_plot_width
	generator.max_plot_width = field_max_plot_width
	generator.bund_gap = field_bund_gap
	generator.field_road_gap_width = field_road_gap_width
	generator.min_plot_length = field_min_plot_length
	generator.max_plot_length = field_max_plot_length
	generator.sample_step = field_sample_step
	generator.road_width = road_width
	generator.road_clearance = field_road_clearance
	generator.horizontal_split_bias = field_horizontal_split_bias
	generator.field_shape_variation = field_shape_variation

	var plots: Array[FieldPlotData] = generator.generate(active_field_cells, road_polylines)
	return {
		"crop_type": crop_type,
		"plots": plots,
		"field_road_polylines": generator.generated_road_polylines.duplicate(true),
		"field_cells": active_field_cells,
	}


func _generate_fields(_terrain: Node3D, _field_generation: Dictionary) -> void:
	_clear_runtime_field_registry()


func _generate_fields_async(_terrain: Node3D, _field_generation: Dictionary) -> void:
	_clear_runtime_field_registry()


func _generate_peasants(
	terrain: Node3D,
	house_placements: Array[Dictionary],
	road_polylines: Array,
	field_generation: Dictionary
) -> void:
	if not _prepare_peasant_population(terrain, house_placements, road_polylines, field_generation):
		return

	var target_count := _get_effective_peasant_target_count()
	for peasant_index: int in range(target_count):
		_spawn_peasant(peasant_index)


func _generate_peasants_async(
	terrain: Node3D,
	house_placements: Array[Dictionary],
	road_polylines: Array,
	field_generation: Dictionary
) -> void:
	if not _prepare_peasant_population(terrain, house_placements, road_polylines, field_generation):
		return

	var target_count := _get_effective_peasant_target_count()
	for peasant_index: int in range(target_count):
		if not is_inside_tree():
			return

		_spawn_peasant(peasant_index)
		if (peasant_index + 1) % runtime_peasant_batch_size == 0:
			await get_tree().process_frame


func _prepare_peasant_population(
	terrain: Node3D,
	house_placements: Array[Dictionary],
	road_polylines: Array,
	field_generation: Dictionary
) -> bool:
	_runtime_peasants.clear()
	_peasant_runtime_terrain = terrain
	_peasant_anchors = _build_peasant_anchors(terrain, house_placements, road_polylines, field_generation)
	_peasant_spawn_budget = 0.0
	_peasant_death_budget = 0.0
	_peasant_spawn_serial = 0
	_peasant_population_rng.seed = _get_peasant_population_seed()

	return (
		_get_effective_peasant_target_count() > 0
		and _get_peasant_scene() != null
		and not (_peasant_anchors.get("house_points", []) as Array).is_empty()
	)


func _spawn_peasant(peasant_index: int) -> Node3D:
	var scene := _get_peasant_scene()
	if not scene or not _runtime_container:
		return null
	if (_peasant_anchors.get("house_points", []) as Array).is_empty():
		return null

	var spatial := _instantiate_runtime_scene(scene, "Peasant", _peasant_spawn_serial)
	if not spatial:
		return null

	_peasant_spawn_serial += 1
	_runtime_peasants.append(spatial)

	var local_point := _get_peasant_spawn_local_point()
	_set_runtime_node_position(spatial, local_point, _peasant_runtime_terrain)
	spatial.rotation.y = _peasant_population_rng.randf_range(0.0, TAU)
	_configure_runtime_visibility_recursive(
		spatial,
		village_visible_distance_meters,
		village_visibility_fade_margin_meters
	)
	_configure_runtime_peasant(spatial, peasant_index)
	return spatial


func _configure_runtime_peasant(spatial: Node3D, peasant_index: int) -> void:
	var behavior_anchors := _peasant_anchors.duplicate(true)
	behavior_anchors["roam_radius"] = peasant_roam_radius
	if spatial.has_method("configure_village_context"):
		spatial.call(
			"configure_village_context",
			self,
			_peasant_runtime_terrain,
			behavior_anchors,
			_mix_peasant_seed(peasant_index, _peasant_population_rng.randi())
		)
	elif spatial.has_method("configure_surface_height_source"):
		spatial.call("configure_surface_height_source", _peasant_runtime_terrain)

	if spatial.has_signal("died"):
		var died_callable := Callable(self, "_on_runtime_peasant_died").bind(spatial)
		if not spatial.is_connected("died", died_callable):
			spatial.connect("died", died_callable)


func _build_peasant_anchors(
	terrain: Node3D,
	house_placements: Array[Dictionary],
	road_polylines: Array,
	field_generation: Dictionary
) -> Dictionary:
	var house_points: Array[Vector2] = []
	for placement: Dictionary in house_placements:
		var point_variant: Variant = placement.get("position", Vector2.ZERO)
		if point_variant is Vector2:
			house_points.append(point_variant as Vector2)

	var road_points := _collect_peasant_road_points(road_polylines)
	var field_points := _collect_peasant_field_points(field_generation)
	return {
		"house_points": house_points,
		"road_points": road_points,
		"field_points": field_points,
		"house_world_points": _local_2d_points_to_surface_world(house_points, terrain),
		"road_world_points": _local_2d_points_to_surface_world(road_points, terrain),
		"field_world_points": _local_2d_points_to_surface_world(field_points, terrain),
	}


func _collect_peasant_road_points(road_polylines: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var min_spacing_squared := maxf(road_width, cell_size) * maxf(road_width, cell_size)
	for polyline: PackedVector2Array in road_polylines:
		for point: Vector2 in polyline:
			if points.is_empty() or points[points.size() - 1].distance_squared_to(point) >= min_spacing_squared:
				points.append(point)
	return points


func _collect_peasant_field_points(field_generation: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var plots: Array = field_generation.get("plots", [])
	for plot_variant: Variant in plots:
		if not (plot_variant is FieldPlotData):
			continue
		var plot := plot_variant as FieldPlotData
		points.append(Vector2(plot.center.x, plot.center.z))
	return points


func _local_2d_points_to_surface_world(points: Array[Vector2], terrain: Node3D) -> Array[Vector3]:
	var world_points: Array[Vector3] = []
	for point: Vector2 in points:
		world_points.append(_get_surface_world_position_from_local_2d(point, terrain))
	return world_points


func _get_peasant_spawn_local_point() -> Vector2:
	var house_points: Array = _peasant_anchors.get("house_points", [])
	var anchor: Vector2 = house_points[_peasant_population_rng.randi_range(0, house_points.size() - 1)]
	var radius := maxf(peasant_house_spawn_radius, 0.0)
	if radius <= 0.0:
		return anchor

	var angle := _peasant_population_rng.randf_range(0.0, TAU)
	var distance := _peasant_population_rng.randf_range(0.0, radius)
	return anchor + Vector2(cos(angle), sin(angle)) * distance


func _update_runtime_peasant_population(delta: float) -> void:
	if not is_instance_valid(_runtime_container):
		return
	if _peasant_anchors.is_empty():
		return

	_prune_runtime_peasants()
	var target_count := _get_effective_peasant_target_count()
	var alive_count := _get_alive_peasant_count()
	if target_count <= 0:
		_despawn_surplus_peasants(alive_count)
		_refresh_food_summary_if_farmer_count_changed()
		return
	if alive_count > target_count:
		_despawn_surplus_peasants(alive_count - target_count)
		_refresh_food_summary_if_farmer_count_changed()
		return

	_update_peasant_ambient_deaths(delta)
	_prune_runtime_peasants()
	alive_count = _get_alive_peasant_count()

	var missing_count := target_count - alive_count
	if missing_count <= 0:
		_refresh_food_summary_if_farmer_count_changed()
		return

	var spawn_rate := _get_effective_peasant_spawn_rate_per_minute()
	if spawn_rate <= 0.0:
		_refresh_food_summary_if_farmer_count_changed()
		return

	_peasant_spawn_budget += spawn_rate * delta / 60.0
	while missing_count > 0 and _peasant_spawn_budget >= 1.0:
		var spawned := _spawn_peasant(_peasant_spawn_serial)
		if not spawned:
			_peasant_spawn_budget = 0.0
			return

		_peasant_spawn_budget -= 1.0
		missing_count -= 1
	_refresh_food_summary_if_farmer_count_changed()


func _update_peasant_ambient_deaths(delta: float) -> void:
	var death_rate := _get_effective_peasant_death_rate_per_minute()
	if death_rate <= 0.0:
		return

	_peasant_death_budget += death_rate * delta / 60.0
	while _peasant_death_budget >= 1.0 and _get_alive_peasant_count() > 0:
		if not _kill_random_runtime_peasant(&"village_death_rate"):
			_peasant_death_budget = 0.0
			return
		_peasant_death_budget -= 1.0


func _kill_random_runtime_peasant(reason: StringName) -> bool:
	var alive_peasants := _get_alive_peasants()
	if alive_peasants.is_empty():
		return false

	var peasant := alive_peasants[_peasant_population_rng.randi_range(0, alive_peasants.size() - 1)]
	if peasant.has_method("kill"):
		peasant.call("kill", reason)
	else:
		_runtime_peasants.erase(peasant)
		peasant.queue_free()
	return true


func _despawn_surplus_peasants(count: int) -> void:
	for _index: int in range(maxi(count, 0)):
		var alive_peasants := _get_alive_peasants()
		if alive_peasants.is_empty():
			return
		var peasant := alive_peasants[alive_peasants.size() - 1]
		_runtime_peasants.erase(peasant)
		peasant.queue_free()


func _get_alive_peasant_count() -> int:
	return _get_alive_peasants().size()


func _get_alive_peasants() -> Array[Node3D]:
	var alive_peasants: Array[Node3D] = []
	for peasant: Node3D in _runtime_peasants:
		if not is_instance_valid(peasant):
			continue
		if peasant.has_method("is_alive") and not bool(peasant.call("is_alive")):
			continue
		alive_peasants.append(peasant)
	return alive_peasants


func _prune_runtime_peasants() -> void:
	for index: int in range(_runtime_peasants.size() - 1, -1, -1):
		var peasant := _runtime_peasants[index]
		if not is_instance_valid(peasant):
			_runtime_peasants.remove_at(index)
			continue
		if peasant.has_method("is_alive") and not bool(peasant.call("is_alive")):
			_runtime_peasants.remove_at(index)


func _on_runtime_peasant_died(_reason: StringName, peasant: Node3D) -> void:
	_runtime_peasants.erase(peasant)
	_refresh_food_summary_if_farmer_count_changed()
	if not is_instance_valid(peasant):
		return

	var cleanup_delay := maxf(peasant_death_cleanup_seconds, 0.0)
	if cleanup_delay <= 0.0 or not is_inside_tree():
		peasant.queue_free()
		return

	await get_tree().create_timer(cleanup_delay).timeout
	if is_instance_valid(peasant):
		peasant.queue_free()


func _refresh_food_summary_if_farmer_count_changed() -> void:
	if _get_alive_peasant_count() != _food_last_farmer_count:
		_refresh_food_summary(true)


func _clear_runtime_field_registry() -> void:
	var terrain_registry := _get_field_terrain_registry_node()
	if terrain_registry and terrain_registry.has_method("clear"):
		terrain_registry.call("clear")
	if terrain_registry and terrain_registry.has_method("rebuild"):
		terrain_registry.call("rebuild")


func _instantiate_runtime_scene(scene: PackedScene, name_prefix: String, index: int) -> Node3D:
	if not scene:
		return null

	var instance := scene.instantiate()
	if not (instance is Node3D):
		push_warning("%s must instantiate a Node3D root." % scene.resource_path)
		instance.free()
		return null

	var spatial := instance as Node3D
	spatial.name = "%s_%03d" % [name_prefix, index]
	_runtime_container.add_child(spatial)
	spatial.owner = null
	return spatial


func _configure_runtime_visibility_recursive(root_node: Node, end_distance: float, fade_margin: float) -> void:
	if not root_node or end_distance <= 0.0:
		return

	var safe_fade_margin := clampf(fade_margin, 0.0, end_distance)
	if root_node is GeometryInstance3D and not bool(root_node.get_meta(PRESERVE_VISIBILITY_RANGE_META, false)):
		_configure_runtime_visibility_instance(root_node as GeometryInstance3D, end_distance, safe_fade_margin)

	for child: Node in root_node.get_children(true):
		_configure_runtime_visibility_recursive(child, end_distance, safe_fade_margin)


func _configure_runtime_visibility_instance(
	instance: GeometryInstance3D,
	end_distance: float,
	fade_margin: float
) -> void:
	instance.visibility_range_begin = 0.0
	instance.visibility_range_begin_margin = 0.0
	instance.visibility_range_end = end_distance
	instance.visibility_range_end_margin = fade_margin
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _set_runtime_node_position(spatial: Node3D, local_point: Vector2, terrain: Node3D) -> void:
	var world_position := _get_surface_world_position_from_local_2d(local_point, terrain)
	spatial.position = _world_to_region_local(world_position)


func _get_house_yaw(local_point: Vector2, road_polylines: Array, rng: RandomNumberGenerator) -> float:
	var nearest := _get_nearest_road(local_point, road_polylines)
	if nearest.is_empty():
		return rng.randf_range(0.0, TAU)

	var road_point: Vector2 = nearest["point"]
	var direction := road_point - local_point
	if direction.length_squared() <= 0.0001:
		return rng.randf_range(0.0, TAU)

	return _yaw_for_minus_z(direction.normalized())


func _face_nearest_road_or_random(spatial: Node3D, local_point: Vector2, road_polylines: Array, rng: RandomNumberGenerator) -> void:
	spatial.rotation.y = _get_house_yaw(local_point, road_polylines, rng)

func _get_cell_surface_world_position(cell: Vector2i, terrain: Node3D) -> Vector3:
	return _get_surface_world_position_from_local_2d(_cell_to_local_2d_center(cell), terrain)


func _get_surface_world_position_from_local_2d(local_point: Vector2, terrain: Node3D) -> Vector3:
	var world_position := _region_local_to_world(Vector3(local_point.x, 0.0, local_point.y))
	var terrain_height := _get_terrain_height(terrain, world_position)
	if terrain_height != null:
		world_position.y = terrain_height
	return world_position


func _build_road_polylines() -> Array:
	var cache_key := _get_road_polylines_cache_key()
	if _cached_road_polylines_key == cache_key:
		return _duplicate_polylines(_cached_road_polylines)

	var polylines := _build_road_polylines_uncached()
	_cached_road_polylines_key = cache_key
	_cached_road_polylines = _duplicate_polylines(polylines)
	return polylines


func _build_road_polylines_uncached() -> Array:
	var polylines: Array = []
	var active_road_cells := get_road_cells()
	if active_road_cells.is_empty():
		return polylines

	var road_lookup := _to_cell_lookup(active_road_cells)
	var visited_edges: Dictionary = {}

	for cell: Vector2i in active_road_cells:
		var neighbors := _get_road_neighbors(cell, road_lookup)
		if neighbors.is_empty():
			var point_polyline := PackedVector2Array()
			point_polyline.append(_cell_to_local_2d_center(cell))
			polylines.append(point_polyline)

	for cell: Vector2i in active_road_cells:
		var neighbors := _get_road_neighbors(cell, road_lookup)
		if neighbors.size() > 1:
			continue

		for neighbor: Vector2i in neighbors:
			if not visited_edges.has(_edge_key(cell, neighbor)):
				polylines.append(_trace_road_polyline(cell, neighbor, road_lookup, visited_edges))

	for cell: Vector2i in active_road_cells:
		for neighbor: Vector2i in _get_road_neighbors(cell, road_lookup):
			if not visited_edges.has(_edge_key(cell, neighbor)):
				polylines.append(_trace_road_polyline(cell, neighbor, road_lookup, visited_edges))

	return _smooth_road_polylines(polylines)


func _trace_road_polyline(start_cell: Vector2i, next_cell: Vector2i, road_lookup: Dictionary, visited_edges: Dictionary) -> PackedVector2Array:
	var polyline := PackedVector2Array()
	polyline.append(_cell_to_local_2d_center(start_cell))

	var previous := start_cell
	var current := next_cell
	var safety := road_lookup.size() + 1
	visited_edges[_edge_key(previous, current)] = true

	while safety > 0:
		polyline.append(_cell_to_local_2d_center(current))

		var current_degree := _get_road_neighbors(current, road_lookup).size()
		if current_degree != 2 and current != start_cell:
			break

		var next_options := _get_unvisited_road_neighbors(current, previous, road_lookup, visited_edges)
		if next_options.is_empty():
			break

		var next := next_options[0]
		visited_edges[_edge_key(current, next)] = true
		previous = current
		current = next
		safety -= 1

	return polyline


func _smooth_road_polylines(polylines: Array) -> Array:
	var smoothed_polylines: Array = []
	for polyline: PackedVector2Array in polylines:
		smoothed_polylines.append(_smooth_road_polyline(polyline))
	return smoothed_polylines


func _smooth_road_polyline(polyline: PackedVector2Array) -> PackedVector2Array:
	var iterations := clampi(road_curve_iterations, 0, 6)
	var amount := clampf(road_curve_amount, 0.0, 0.49)
	if polyline.size() < 3 or iterations <= 0 or amount <= 0.0:
		return polyline.duplicate()

	var current := polyline.duplicate()
	for _iteration: int in range(iterations):
		var next := PackedVector2Array()
		next.append(current[0])

		for index: int in range(current.size() - 1):
			var from_point := current[index]
			var to_point := current[index + 1]
			var first_cut := from_point.lerp(to_point, amount)
			var second_cut := from_point.lerp(to_point, 1.0 - amount)
			_append_road_curve_point(next, first_cut)
			_append_road_curve_point(next, second_cut)

		_append_road_curve_point(next, current[current.size() - 1])
		current = next

	return current


func _append_road_curve_point(polyline: PackedVector2Array, point: Vector2) -> void:
	if not polyline.is_empty() and polyline[polyline.size() - 1].distance_squared_to(point) <= 0.0001:
		return
	polyline.append(point)


func _get_road_polylines_cache_key() -> String:
	return "roads|%s|%.4f|%s|%d|%.4f" % [
		_get_cells_cache_key(get_road_cells()),
		cell_size,
		str(origin),
		road_curve_iterations,
		road_curve_amount,
	]


func _get_field_generation_cache_key(crop_type: CropTypeData, road_polylines: Array) -> String:
	return "fields|%s|%s|%.4f|%s|%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%s" % [
		_get_cells_cache_key(get_field_cells()),
		_get_resource_cache_key(crop_type),
		cell_size,
		str(origin),
		generation_seed,
		field_min_plot_width,
		field_max_plot_width,
		field_bund_gap,
		field_road_gap_width,
		field_min_plot_length,
		field_max_plot_length,
		field_sample_step,
		field_road_clearance,
		field_horizontal_split_bias,
		field_shape_variation,
		_get_polylines_cache_key(road_polylines),
	]


func _get_cells_cache_key(cells: Array[Vector2i]) -> String:
	var mixed := int(2166136261)
	for cell: Vector2i in cells:
		mixed = int((mixed ^ cell.x) * 16777619)
		mixed = int((mixed ^ cell.y) * 16777619)
	return "%d:%d" % [cells.size(), mixed]


func _get_polylines_cache_key(polylines: Array) -> String:
	var mixed := int(2166136261)
	var point_count := 0
	for polyline: PackedVector2Array in polylines:
		mixed = int((mixed ^ polyline.size()) * 16777619)
		point_count += polyline.size()
		for point: Vector2 in polyline:
			mixed = int((mixed ^ roundi(point.x * 1000.0)) * 16777619)
			mixed = int((mixed ^ roundi(point.y * 1000.0)) * 16777619)
	return "%d:%d:%d" % [polylines.size(), point_count, mixed]


func _get_resource_cache_key(resource: Resource) -> String:
	if not resource:
		return ""
	if not resource.resource_path.is_empty():
		return resource.resource_path
	return str(resource.get_instance_id())


func _duplicate_polylines(polylines: Array) -> Array:
	var duplicated: Array = []
	for polyline: PackedVector2Array in polylines:
		duplicated.append(polyline.duplicate())
	return duplicated


func _duplicate_field_generation(field_generation: Dictionary) -> Dictionary:
	var plots: Array = field_generation.get("plots", [])
	var duplicated_plots: Array[FieldPlotData] = []
	for plot_variant: Variant in plots:
		if plot_variant is FieldPlotData:
			duplicated_plots.append((plot_variant as FieldPlotData).duplicate() as FieldPlotData)

	return {
		"crop_type": field_generation.get("crop_type"),
		"plots": duplicated_plots,
		"field_road_polylines": _duplicate_polylines(field_generation.get("field_road_polylines", [])),
		"field_cells": _copy_cells_from_variant(field_generation.get("field_cells", [])),
	}


func _initialize_house_food_records(house_placements: Array[Dictionary], field_generation: Dictionary) -> void:
	_house_food_records.clear()
	_house_food_record_lookup.clear()
	_food_total_field_area_m2 = _get_total_field_area_m2(field_generation)
	_village_storage_food_kg = 0.0
	_food_last_shortage_kg = 0.0
	_food_cumulative_shortage_kg = 0.0
	_food_days_elapsed = 0
	_food_last_farmer_count = -1

	var default_reserve := maxf(_get_balance_float(&"default_food_reserve_kg_per_house", 30.0), 0.0)
	for index: int in range(house_placements.size()):
		var placement := house_placements[index]
		var house_id := _make_house_food_id(index)
		placement["id"] = house_id
		var local_point: Vector2 = placement.get("position", Vector2.ZERO)
		var record := {
			"id": house_id,
			"house_id": house_id,
			"display_name": "House %02d" % [index + 1],
			"resident_count": _get_deterministic_house_resident_count(index, placement),
			"food_reserve_kg": default_reserve,
			"initial_food_reserve_kg": default_reserve,
			"daily_production_share_kg": 0.0,
			"daily_consumption_share_kg": 0.0,
			"daily_net_kg": 0.0,
			"shortage_kg": 0.0,
			"food_days_remaining": 0.0,
			"position": local_point,
			"world_position": _region_local_to_world(Vector3(local_point.x, 0.0, local_point.y)),
		}
		_house_food_records.append(record)
		_house_food_record_lookup[house_id] = record

	_village_storage_food_kg = default_reserve * float(_house_food_records.size())
	_refresh_food_summary(false)


func _make_house_food_id(index: int) -> StringName:
	return StringName("house_%03d" % [index])


func _get_deterministic_house_resident_count(index: int, placement: Dictionary) -> int:
	var min_residents := maxi(_get_balance_int(&"house_min_villagers", 3), 0)
	var max_residents := maxi(_get_balance_int(&"house_max_villagers", 4), min_residents)
	var span := maxi(max_residents - min_residents + 1, 1)
	var point: Vector2 = placement.get("position", Vector2.ZERO)
	var mixed := int(generation_seed)
	mixed = int((mixed * 1103515245 + 12345 + index * 2654435761) & 0x7fffffff)
	mixed = int((mixed * 1103515245 + 12345 + roundi(point.x * 1000.0)) & 0x7fffffff)
	mixed = int((mixed * 1103515245 + 12345 + roundi(point.y * 1000.0)) & 0x7fffffff)
	return min_residents + (absi(mixed) % span)


func _get_total_field_area_m2(field_generation: Dictionary) -> float:
	var total_area := 0.0
	var plots: Array = field_generation.get("plots", [])
	for plot_variant: Variant in plots:
		if plot_variant is FieldPlotData:
			total_area += maxf((plot_variant as FieldPlotData).area, 0.0)
	return total_area


func _get_daily_rice_production_kg() -> float:
	var days_per_year := maxi(_get_balance_int(&"food_days_per_year", 360), 1)
	return _food_total_field_area_m2 * maxf(_get_balance_float(&"rice_kg_per_square_meter_per_year", 0.1), 0.0) / float(days_per_year)


func _get_daily_rice_consumption_kg() -> float:
	return float(_get_alive_peasant_count()) * maxf(_get_balance_float(&"daily_rice_kg_per_farmer", 1.0), 0.0)


func _get_total_food_reserve_kg() -> float:
	return maxf(_village_storage_food_kg, 0.0)


func _get_total_house_resident_count() -> int:
	var total := 0
	for record: Dictionary in _house_food_records:
		total += maxi(int(record.get("resident_count", 0)), 0)
	return total


func _refresh_food_summary(emit_signal: bool) -> void:
	_update_house_food_daily_shares()
	_village_food_summary = _make_village_food_summary()
	_food_last_farmer_count = int(_village_food_summary.get("farmer_count", 0))
	if emit_signal:
		food_state_changed.emit(_village_food_summary.duplicate(true))


func _update_house_food_daily_shares() -> void:
	var house_count := _house_food_records.size()
	if house_count <= 0:
		return

	var production_share := _get_daily_rice_production_kg() / float(house_count)
	var consumption_share := _get_daily_rice_consumption_kg() / float(house_count)
	var reserve_share := _get_total_food_reserve_kg() / float(house_count)
	for record: Dictionary in _house_food_records:
		var reserve := maxf(reserve_share, 0.0)
		var shortage_share := _food_last_shortage_kg / float(house_count)
		record["food_reserve_kg"] = reserve
		record["daily_production_share_kg"] = production_share
		record["daily_consumption_share_kg"] = consumption_share
		record["daily_net_kg"] = production_share - consumption_share
		record["shortage_kg"] = shortage_share
		record["food_days_remaining"] = reserve / consumption_share if consumption_share > 0.0 else 0.0


func _make_village_food_summary() -> Dictionary:
	var daily_production := _get_daily_rice_production_kg()
	var daily_consumption := _get_daily_rice_consumption_kg()
	var total_reserve := _get_total_food_reserve_kg()
	var days_remaining := total_reserve / daily_consumption if daily_consumption > 0.0 else 0.0
	var summary := {
		"house_count": _house_food_records.size(),
		"resident_count": _get_total_house_resident_count(),
		"farmer_count": _get_alive_peasant_count(),
		"total_reserve_kg": total_reserve,
		"daily_production_kg": daily_production,
		"daily_consumption_kg": daily_consumption,
		"daily_net_kg": daily_production - daily_consumption,
		"field_area_m2": _food_total_field_area_m2,
		"food_days_remaining": days_remaining,
		"storage_food_kg": total_reserve,
		"storage_world_position": get_village_storage_world_position(),
		"shortage_kg": _food_last_shortage_kg,
		"cumulative_shortage_kg": _food_cumulative_shortage_kg,
		"food_days_elapsed": _food_days_elapsed,
	}
	_append_time_summary(summary)
	return summary


func _append_time_summary(summary: Dictionary) -> void:
	if _last_time_snapshot.is_empty():
		return

	for key: String in [
		"year",
		"calendar_month",
		"month",
		"month_name",
		"day_of_month",
		"day_of_year",
		"absolute_day",
		"hour",
		"minute",
		"time_of_day_minutes",
		"date_label",
		"time_label",
		"date_time_label",
	]:
		if _last_time_snapshot.has(key):
			summary[key] = _last_time_snapshot[key]


func _get_balance_config() -> Resource:
	return balance_config if balance_config else DEFAULT_BALANCE_CONFIG


func _get_balance_float(property: StringName, fallback: float) -> float:
	var config := _get_balance_config()
	if not config:
		return fallback
	var value: Variant = config.get(property)
	return fallback if value == null else float(value)


func _get_balance_int(property: StringName, fallback: int) -> int:
	var config := _get_balance_config()
	if not config:
		return fallback
	var value: Variant = config.get(property)
	return fallback if value == null else int(value)


func _copy_cells_from_variant(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for cell_variant: Variant in value:
		if cell_variant is Vector2i:
			cells.append(cell_variant as Vector2i)
	return copy_cells(cells)


func _get_road_neighbors(cell: Vector2i, road_lookup: Dictionary) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset: Vector2i in ROAD_NEIGHBOR_OFFSETS:
		var neighbor := cell + offset
		if road_lookup.has(neighbor):
			neighbors.append(neighbor)
	neighbors.sort_custom(_compare_cells)
	return neighbors


func _get_unvisited_road_neighbors(
	cell: Vector2i,
	previous: Vector2i,
	road_lookup: Dictionary,
	visited_edges: Dictionary
) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for neighbor: Vector2i in _get_road_neighbors(cell, road_lookup):
		if neighbor == previous:
			continue
		if visited_edges.has(_edge_key(cell, neighbor)):
			continue
		neighbors.append(neighbor)
	return neighbors


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var first := a
	var second := b
	if _compare_cells(b, a):
		first = b
		second = a
	return "%d,%d:%d,%d" % [first.x, first.y, second.x, second.y]


func _apply_field_terrain_and_road_texture(
	terrain: Node3D,
	road_polylines: Array,
	field_generation: Dictionary,
	house_placements: Array[Dictionary] = [],
	shape_field_surface: bool = true,
	paint_field_roads: bool = true
) -> void:
	var plots: Array = field_generation.get("plots", [])
	var field_generation_cells: Array = field_generation.get("field_cells", [])
	var generated_field_road_polylines: Array = field_generation.get("field_road_polylines", [])
	var has_field_layout := not field_generation_cells.is_empty() and not plots.is_empty()
	var should_shape_field_surface := shape_field_surface and has_field_layout
	var should_paint_field_roads := paint_field_roads and has_field_layout
	var has_generated_field_roads := not generated_field_road_polylines.is_empty()
	var should_paint_generated_field_roads := paint_field_roads and has_generated_field_roads
	var has_house_surface := not house_placements.is_empty()
	if (
		road_polylines.is_empty()
		and not should_shape_field_surface
		and not should_paint_field_roads
		and not should_paint_generated_field_roads
		and not has_house_surface
	):
		return

	if not is_instance_valid(terrain):
		push_warning("VillageRegion terrain_path does not resolve to a Node3D; skipping runtime terrain texture edits.")
		return

	var terrain_data := _get_terrain_data(terrain)
	if not terrain_data:
		push_warning("VillageRegion terrain has no Terrain3D data; skipping runtime terrain texture edits.")
		return

	var terrain_assets_variant: Variant = terrain.get("assets")
	if not (terrain_assets_variant is Object):
		push_warning("VillageRegion terrain has no Terrain3D assets; skipping runtime terrain texture edits.")
		return

	var terrain_assets := terrain_assets_variant as Object
	if not terrain_assets.has_method("get_texture_count"):
		push_warning("VillageRegion terrain assets cannot report texture count; skipping runtime terrain texture edits.")
		return

	var texture_count := _get_terrain_texture_count(terrain_assets)
	var road_texture_valid := _is_terrain_texture_id_valid(road_texture_id, texture_count)
	var field_texture_id := _get_field_road_texture_id(texture_count)
	var field_texture_valid := _is_terrain_texture_id_valid(field_texture_id, texture_count)
	var field_mud_texture_valid := _is_terrain_texture_id_valid(field_mud_texture_id, texture_count)
	var house_sand_texture_valid := _is_terrain_texture_id_valid(house_sand_texture_id, texture_count)

	if not terrain_data.has_method("set_control_base_id"):
		push_warning("VillageRegion Terrain3D data cannot set control texture IDs; skipping runtime terrain texture edits.")
		road_texture_valid = false
		field_texture_valid = false
		field_mud_texture_valid = false
		house_sand_texture_valid = false
	if not terrain_data.has_method("get_control") or not terrain_data.has_method("set_control"):
		push_warning("VillageRegion Terrain3D data cannot restore control values; skipping runtime terrain texture edits.")
		road_texture_valid = false
		field_texture_valid = false
		field_mud_texture_valid = false
		house_sand_texture_valid = false

	var radius := maxf(road_width * 0.5, 0.05)
	var sample_spacing := maxf(road_sample_spacing, 0.1)
	var paint_step := maxf(MIN_TERRAIN_PAINT_STEP, minf(sample_spacing * 0.5, radius * 0.25))
	var painted_points: Dictionary = {}
	_runtime_road_terrain = terrain
	_runtime_road_control_records.clear()
	_runtime_field_terrain_shape_applied = false
	var touched_field_cells := field_generation_cells if should_shape_field_surface or should_paint_field_roads or should_paint_generated_field_roads else []
	var touched_regions := _collect_runtime_terrain_regions(terrain_data, touched_field_cells, house_placements)
	if not _use_runtime_terrain_region_copies(terrain_data, touched_regions):
		push_warning("VillageRegion could not create runtime Terrain3D region copies; skipping terrain texture edits to avoid modifying terrain files.")
		_runtime_road_terrain = null
		return

	if should_shape_field_surface:
		_runtime_field_terrain_shape_applied = _shape_field_terrain(terrain_data, terrain, plots)

	if should_shape_field_surface and field_mud_texture_valid:
		_paint_field_plot_surfaces(
			terrain_data,
			terrain,
			plots,
			texture_count,
			painted_points,
			field_mud_texture_id
		)
	elif should_shape_field_surface:
		push_warning(
			"VillageRegion field mud texture id %d is invalid for %d Terrain3D textures; skipping field mud texture."
			% [field_mud_texture_id, texture_count]
		)

	if has_house_surface and house_sand_texture_valid:
		_paint_house_clearings(
			terrain_data,
			terrain,
			house_placements,
			texture_count,
			painted_points,
			house_sand_texture_id
		)
	elif has_house_surface:
		push_warning(
			"VillageRegion house ground texture id %d is invalid for %d Terrain3D textures; skipping house clearing texture."
			% [house_sand_texture_id, texture_count]
		)

	if road_texture_valid:
		for polyline: PackedVector2Array in road_polylines:
			_paint_road_polyline(
				terrain_data,
				terrain,
				polyline,
				radius,
				sample_spacing,
				paint_step,
				texture_count,
				painted_points,
				road_texture_id,
				road_texture_strength,
				road_edge_feather,
				PAINT_PRIORITY_ROAD
			)
	elif not road_polylines.is_empty():
		push_warning(
			"VillageRegion road_texture_id %d is invalid for %d Terrain3D textures; skipping authored road texture."
			% [road_texture_id, texture_count]
		)

	if should_paint_field_roads and field_texture_valid:
		_paint_field_road_surface_mask(
			terrain_data,
			terrain,
			field_generation_cells,
			plots,
			generated_field_road_polylines,
			texture_count,
			painted_points,
			field_texture_id
		)
	elif should_paint_generated_field_roads and field_texture_valid:
		_apply_road_texture_to_generated_lines(
			terrain_data,
			terrain,
			generated_field_road_polylines,
			texture_count,
			painted_points,
			field_texture_id
		)
	elif should_paint_field_roads or should_paint_generated_field_roads:
		push_warning(
			"VillageRegion field road texture id %d is invalid for %d Terrain3D textures; skipping field road texture."
			% [field_texture_id, texture_count]
		)

	if not painted_points.is_empty() and terrain_data.has_method("update_maps"):
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_CONTROL, true, false)
	if _runtime_field_terrain_shape_applied and terrain_data.has_method("update_maps"):
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_HEIGHT, true, false)
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_MAX, true, false)


func _apply_road_texture(terrain: Node3D, road_polylines: Array, field_road_polylines: Array = []) -> void:
	_apply_field_terrain_and_road_texture(
		terrain,
		road_polylines,
		{
			"plots": [],
			"field_cells": [],
			"field_road_polylines": field_road_polylines,
		}
	)


func _collect_runtime_terrain_regions(
	terrain_data: Object,
	field_generation_cells: Array,
	house_placements: Array[Dictionary]
) -> Dictionary:
	var regions: Dictionary = {}
	if not terrain_data.has_method("get_regionp"):
		return regions

	var road_margin := maxf(road_width * 0.5 + road_sample_spacing + MIN_TERRAIN_PAINT_STEP, 0.0)
	_add_touched_terrain_regions_for_cells(regions, terrain_data, get_road_cells(), road_margin)

	var field_margin := maxf(
		maxf(field_region_road_margin, _get_field_road_width() * 0.5),
		field_edge_slope_width + MIN_TERRAIN_PAINT_STEP
	)
	_add_touched_terrain_regions_for_cells(regions, terrain_data, field_generation_cells, field_margin)
	_add_touched_terrain_regions_for_house_placements(regions, terrain_data, house_placements)
	return regions


func _add_touched_terrain_regions_for_cells(
	regions: Dictionary,
	terrain_data: Object,
	cells: Array,
	margin: float
) -> void:
	var safe_margin := maxf(margin, 0.0)
	for cell_variant: Variant in cells:
		if not (cell_variant is Vector2i):
			continue

		var cell := cell_variant as Vector2i
		for point: Vector2 in _get_expanded_cell_sample_points(cell, safe_margin):
			var world_position := _region_local_to_world(Vector3(point.x, 0.0, point.y))
			var region_variant: Variant = terrain_data.call("get_regionp", world_position)
			if region_variant is Object:
				regions[region_variant] = true


func _get_expanded_cell_sample_points(cell: Vector2i, margin: float) -> Array[Vector2]:
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	var min_point := cell_min - Vector2(margin, margin)
	var max_point := cell_min + Vector2(safe_cell_size, safe_cell_size) + Vector2(margin, margin)
	return [
		(min_point + max_point) * 0.5,
		min_point,
		Vector2(max_point.x, min_point.y),
		max_point,
		Vector2(min_point.x, max_point.y),
	]


func _add_touched_terrain_regions_for_house_placements(
	regions: Dictionary,
	terrain_data: Object,
	house_placements: Array[Dictionary]
) -> void:
	for placement: Dictionary in house_placements:
		var center: Vector2 = placement.get("position", Vector2.ZERO)
		var radius := _get_house_clearing_radius(placement)
		var points := [
			center,
			center + Vector2(radius, 0.0),
			center + Vector2(-radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(0.0, -radius),
			center + Vector2(radius, radius),
			center + Vector2(-radius, radius),
			center + Vector2(radius, -radius),
			center + Vector2(-radius, -radius),
		]

		for point: Vector2 in points:
			var world_position := _region_local_to_world(Vector3(point.x, 0.0, point.y))
			var region_variant: Variant = terrain_data.call("get_regionp", world_position)
			if region_variant is Object:
				regions[region_variant] = true


func _paint_field_plot_surfaces(
	terrain_data: Object,
	terrain: Node3D,
	plots: Array,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int
) -> void:
	var sample_spacing := maxf(MIN_TERRAIN_PAINT_STEP, minf(maxf(field_sample_step, MIN_TERRAIN_PAINT_STEP), 1.0))
	for plot_variant: Variant in plots:
		if not (plot_variant is FieldPlotData):
			continue

		var plot := plot_variant as FieldPlotData
		var bounds := _get_plot_bounds_2d(plot, sample_spacing)
		if bounds.is_empty():
			continue

		var min_point: Vector2 = bounds["min"]
		var max_point: Vector2 = bounds["max"]
		var x := min_point.x
		while x <= max_point.x + 0.001:
			var z := min_point.y
			while z <= max_point.y + 0.001:
				var local_point := Vector2(x, z)
				var strength := _get_plot_texture_strength(local_point, plot, field_texture_strength, field_edge_feather)
				if strength > 0.003:
					_paint_texture_point(
						terrain_data,
						terrain,
						local_point,
						texture_count,
						painted_points,
						target_texture_id,
						strength,
						PAINT_PRIORITY_FIELD
					)
				z += sample_spacing
			x += sample_spacing


func _paint_house_clearings(
	terrain_data: Object,
	terrain: Node3D,
	house_placements: Array[Dictionary],
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int
) -> void:
	for placement: Dictionary in house_placements:
		var radius := _get_house_clearing_radius(placement)
		var sample_step := maxf(MIN_TERRAIN_PAINT_STEP, minf(road_sample_spacing, radius * 0.35))
		_paint_radial_texture_sample(
			terrain_data,
			terrain,
			placement.get("position", Vector2.ZERO),
			radius,
			sample_step,
			texture_count,
			painted_points,
			target_texture_id,
			house_texture_strength,
			house_edge_feather,
			PAINT_PRIORITY_HOUSE
		)


func _get_house_clearing_radius(placement: Dictionary) -> float:
	var radius := float(placement.get("radius", cell_size * 0.5))
	return maxf(radius, cell_size * 0.45)


func _get_plot_texture_strength(local_point: Vector2, plot: FieldPlotData, texture_strength: float, edge_feather: float) -> float:
	var edge_distance := plot.get_region_edge_distance(local_point)
	if edge_distance < 0.0:
		return 0.0

	var strength := clampf(texture_strength, 0.0, 1.0)
	var feather := clampf(edge_feather, 0.0, 1.0)
	if feather <= 0.0:
		return strength

	var half_length := plot.length * 0.5
	var half_width := plot.width * 0.5
	var feather_width := maxf(minf(half_length, half_width) * feather, MIN_TERRAIN_PAINT_STEP)
	return strength * _smootherstep(edge_distance / feather_width)


func _paint_field_road_surface_mask(
	terrain_data: Object,
	terrain: Node3D,
	field_generation_cells: Array,
	plots: Array,
	field_road_polylines: Array,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int
) -> void:
	var field_lookup := _to_cell_lookup(field_generation_cells)
	var field_road_width := _get_field_road_width()
	var field_surface_margin := maxf(field_region_road_margin, field_road_width * 0.5)
	var bounds := _get_cell_bounds_2d(field_generation_cells, field_surface_margin)
	if bounds.is_empty():
		return

	var field_sample_spacing := maxf(0.1, minf(road_sample_spacing, field_road_width * 0.5))
	var field_radius := maxf(field_road_width * 0.5, field_sample_spacing * 0.65)
	var field_paint_step := maxf(0.05, minf(field_sample_spacing * 0.5, field_radius * 0.5))

	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var x := min_point.x
	while x <= max_point.x + 0.001:
		var z := min_point.y
		while z <= max_point.y + 0.001:
			var local_point := Vector2(x, z)
			if (
				_is_point_in_expanded_cells(local_point, field_lookup, field_surface_margin)
				and not _is_point_inside_any_plot(local_point, plots, 0.0)
			):
				_paint_road_sample(
					terrain_data,
					terrain,
					local_point,
					field_radius,
					field_paint_step,
					texture_count,
					painted_points,
					target_texture_id,
					road_texture_strength,
					road_edge_feather,
					PAINT_PRIORITY_FIELD_ROAD
				)
			z += field_sample_spacing
		x += field_sample_spacing

	for polyline: PackedVector2Array in field_road_polylines:
		_paint_road_polyline(
			terrain_data,
			terrain,
			polyline,
			field_radius,
			field_sample_spacing,
			field_paint_step,
			texture_count,
			painted_points,
			target_texture_id,
			road_texture_strength,
			road_edge_feather,
			PAINT_PRIORITY_FIELD_ROAD
		)

	var plot_perimeter_polylines: Array = []
	for plot: Variant in plots:
		if plot is FieldPlotData:
			_append_plot_perimeter_roads(plot_perimeter_polylines, plot as FieldPlotData)

	for polyline: PackedVector2Array in plot_perimeter_polylines:
		_paint_road_polyline(
			terrain_data,
			terrain,
			polyline,
			field_radius,
			field_sample_spacing,
			field_paint_step,
			texture_count,
			painted_points,
			target_texture_id,
			road_texture_strength,
			road_edge_feather,
			PAINT_PRIORITY_FIELD_ROAD
		)


func _append_plot_perimeter_roads(polylines: Array, plot: FieldPlotData) -> void:
	var outline := plot.get_region_outline_2d()
	if outline.size() < 2:
		return

	for index: int in range(outline.size()):
		var polyline := PackedVector2Array()
		polyline.append(outline[index])
		polyline.append(outline[(index + 1) % outline.size()])
		polylines.append(polyline)


func _get_field_road_texture_id(texture_count: int) -> int:
	if _is_terrain_texture_id_valid(field_road_texture_id, texture_count):
		return field_road_texture_id
	return road_texture_id


func _is_terrain_texture_id_valid(texture_id: int, texture_count: int) -> bool:
	return texture_id >= 0 and texture_id < texture_count


func _get_field_road_width() -> float:
	return maxf(maxf(field_road_gap_width, field_bund_gap), 0.05)


func _shape_field_terrain(terrain_data: Object, terrain: Node3D, plots: Array) -> bool:
	if field_floor_drop <= 0.0 or plots.is_empty():
		return false
	if not terrain.has_method("get_region_size") or not terrain.has_method("get_vertex_spacing"):
		return false
	if not terrain_data.has_method("get_regionp"):
		return false

	var vertex_spacing := maxf(float(terrain.call("get_vertex_spacing")), 0.01)
	var sample_step := maxf(0.1, minf(vertex_spacing, maxf(field_edge_slope_width, 0.1)))
	var modified_regions: Dictionary = {}
	var modified_pixels: Dictionary = {}
	var any_modified := false

	for plot_variant: Variant in plots:
		if not (plot_variant is FieldPlotData):
			continue

		var plot := plot_variant as FieldPlotData
		var bounds := _get_plot_bounds_2d(plot, field_edge_slope_width + sample_step)
		if bounds.is_empty():
			continue

		var min_point: Vector2 = bounds["min"]
		var max_point: Vector2 = bounds["max"]
		var x := min_point.x
		while x <= max_point.x + 0.001:
			var z := min_point.y
			while z <= max_point.y + 0.001:
				var local_point := Vector2(x, z)
				var lowering_weight := _get_plot_lowering_weight(local_point, plot)
				if lowering_weight > 0.001:
					any_modified = _set_terrain_height_delta(
						terrain_data,
						terrain,
						local_point,
						-field_floor_drop * lowering_weight,
						modified_regions,
						modified_pixels
					) or any_modified
				z += sample_step
			x += sample_step

	for region_variant: Variant in modified_regions.keys():
		var region := region_variant as Object
		var image := modified_regions[region_variant] as Image
		if region and image and region.has_method("set_height_map"):
			region.call("set_height_map", image)

	return any_modified


func _set_terrain_height_delta(
	terrain_data: Object,
	terrain: Node3D,
	local_point: Vector2,
	delta_height: float,
	modified_regions: Dictionary,
	modified_pixels: Dictionary
) -> bool:
	var world_position := _region_local_to_world(Vector3(local_point.x, 0.0, local_point.y))
	var region_variant: Variant = terrain_data.call("get_regionp", world_position)
	if not (region_variant is Object):
		return false

	var region := region_variant as Object
	if not region.has_method("get_height_map") or not region.has_method("set_height_map"):
		return false

	var height_map := modified_regions.get(region)
	if not (height_map is Image):
		var map_variant: Variant = region.call("get_height_map")
		if not (map_variant is Image):
			return false
		height_map = (map_variant as Image).duplicate()
		modified_regions[region] = height_map

	var pixel := _get_terrain_height_pixel(terrain_data, terrain, world_position, height_map as Image)
	if pixel.x < 0:
		return false

	var region_pixels: Dictionary = modified_pixels.get(region, {})
	if region_pixels.has(pixel):
		return false
	region_pixels[pixel] = true
	modified_pixels[region] = region_pixels

	var image := height_map as Image
	var current_color := image.get_pixel(pixel.x, pixel.y)
	current_color.r += delta_height
	image.set_pixel(pixel.x, pixel.y, current_color)
	return true


func _get_terrain_height_pixel(terrain_data: Object, terrain: Node3D, world_position: Vector3, height_map: Image) -> Vector2i:
	if not terrain_data.has_method("get_region_location"):
		return Vector2i(-1, -1)

	var region_location_variant: Variant = terrain_data.call("get_region_location", world_position)
	if not (region_location_variant is Vector2i):
		return Vector2i(-1, -1)

	var region_location := region_location_variant as Vector2i
	var region_size := int(terrain.call("get_region_size"))
	var vertex_spacing := maxf(float(terrain.call("get_vertex_spacing")), 0.01)
	var terrain_local := terrain.to_local(world_position)
	var map_x := floori((terrain_local.x / vertex_spacing) - float(region_location.x * region_size))
	var map_y := floori((terrain_local.z / vertex_spacing) - float(region_location.y * region_size))
	map_x = clampi(map_x, 0, height_map.get_width() - 1)
	map_y = clampi(map_y, 0, height_map.get_height() - 1)
	return Vector2i(map_x, map_y)


func _get_plot_lowering_weight(local_point: Vector2, plot: FieldPlotData) -> float:
	var edge_distance := plot.get_region_edge_distance(local_point)
	if edge_distance < 0.0:
		return 0.0

	var slope_width := maxf(field_edge_slope_width, 0.01)
	return clampf(edge_distance / slope_width, 0.0, 1.0)


func _get_plot_bounds_2d(plot: FieldPlotData, margin: float) -> Dictionary:
	var outline := plot.get_region_outline_2d()
	if outline.is_empty():
		return {}

	var points: Array[Vector2] = []
	for point: Vector2 in outline:
		points.append(point)
	return _get_point_bounds_2d(points, margin)


func _get_cell_bounds_2d(cells: Array, margin: float) -> Dictionary:
	if cells.is_empty():
		return {}

	var points: Array[Vector2] = []
	for cell: Vector2i in cells:
		points.append_array(_get_cell_corners(cell))
	return _get_point_bounds_2d(points, margin)


func _get_point_bounds_2d(points: Array, margin: float) -> Dictionary:
	if points.is_empty():
		return {}

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	var safe_margin := maxf(margin, 0.0)
	return {
		"min": min_point - Vector2(safe_margin, safe_margin),
		"max": max_point + Vector2(safe_margin, safe_margin),
	}


func _is_point_in_expanded_cells(point: Vector2, cell_lookup: Dictionary, margin: float) -> bool:
	if _is_point_in_cells(point, cell_lookup):
		return true

	var safe_margin := maxf(margin, 0.0)
	if safe_margin <= 0.0:
		return false

	var radius_cells := ceili(safe_margin / maxf(cell_size, 0.1)) + 1
	var center_cell := _local_2d_to_cell(point)
	for x_offset: int in range(-radius_cells, radius_cells + 1):
		for y_offset: int in range(-radius_cells, radius_cells + 1):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			if cell_lookup.has(cell) and _distance_to_cell_rect(point, cell) <= safe_margin:
				return true
	return false


func _distance_to_cell_rect(point: Vector2, cell: Vector2i) -> float:
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	var cell_max := cell_min + Vector2(safe_cell_size, safe_cell_size)
	var dx := maxf(maxf(cell_min.x - point.x, 0.0), point.x - cell_max.x)
	var dz := maxf(maxf(cell_min.y - point.y, 0.0), point.y - cell_max.y)
	return Vector2(dx, dz).length()


func _is_point_inside_any_plot(point: Vector2, plots: Array, inset: float) -> bool:
	for plot_variant: Variant in plots:
		if plot_variant is FieldPlotData and _is_point_inside_plot(point, plot_variant as FieldPlotData, inset):
			return true
	return false


func _is_point_inside_plot(point: Vector2, plot: FieldPlotData, inset: float) -> bool:
	return plot.contains_region_point(point, inset)


func _apply_road_texture_to_generated_lines(
	terrain_data: Object,
	terrain: Node3D,
	field_road_polylines: Array,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int
) -> void:
	if not field_road_polylines.is_empty():
		var field_road_width := _get_field_road_width()
		var field_radius := maxf(field_road_width * 0.5, 0.025)
		var field_sample_spacing := maxf(0.1, minf(road_sample_spacing, field_road_width * 0.5))
		var field_paint_step := maxf(0.05, minf(field_sample_spacing * 0.5, field_radius * 0.5))
		for polyline: PackedVector2Array in field_road_polylines:
			_paint_road_polyline(
				terrain_data,
				terrain,
				polyline,
				field_radius,
				field_sample_spacing,
				field_paint_step,
				texture_count,
				painted_points,
				target_texture_id,
				road_texture_strength,
				road_edge_feather,
				PAINT_PRIORITY_FIELD_ROAD
			)


func _restore_runtime_road_texture() -> void:
	if _runtime_road_using_region_copies:
		var terrain_data := _get_terrain_data(_runtime_road_terrain)
		if terrain_data:
			_restore_original_terrain_regions(terrain_data)
		_runtime_road_control_records.clear()
		_runtime_road_terrain = null
		return

	if _runtime_road_control_records.is_empty():
		_runtime_road_terrain = null
		return

	var terrain := _runtime_road_terrain
	var terrain_data := _get_terrain_data(terrain)
	if terrain_data and terrain_data.has_method("set_control"):
		for index: int in range(_runtime_road_control_records.size() - 1, -1, -1):
			var record := _runtime_road_control_records[index]
			terrain_data.call("set_control", record["position"], record["control"])

		if terrain_data.has_method("update_maps"):
			terrain_data.call("update_maps", Terrain3DRegion.TYPE_CONTROL, true, false)

	_runtime_road_control_records.clear()
	_runtime_road_terrain = null


func _use_runtime_terrain_region_copies(terrain_data: Object, touched_regions: Dictionary) -> bool:
	_runtime_road_original_regions.clear()
	_runtime_road_copied_regions.clear()
	_runtime_road_using_region_copies = false

	if not (
		terrain_data.has_method("get_regions_active")
		and terrain_data.has_method("remove_region")
		and terrain_data.has_method("add_region")
	):
		return false

	var original_regions: Array = terrain_data.call("get_regions_active", false, false)
	if original_regions.is_empty() or touched_regions.is_empty():
		return false

	var all_copied_regions: Array = terrain_data.call("get_regions_active", true, true)
	if all_copied_regions.size() != original_regions.size():
		return false

	var selected_original_regions: Array = []
	var copied_regions: Array = []
	for index: int in range(original_regions.size()):
		var region: Variant = original_regions[index]
		if not touched_regions.has(region):
			continue

		var copied_region: Variant = all_copied_regions[index]
		if not (copied_region is Resource):
			return false
		(copied_region as Resource).resource_path = ""
		selected_original_regions.append(region)
		copied_regions.append(copied_region)

	if selected_original_regions.is_empty():
		return false

	for region: Variant in selected_original_regions:
		terrain_data.call("remove_region", region, false)

	for region: Variant in copied_regions:
		var error := int(terrain_data.call("add_region", region, false))
		if error != OK:
			_restore_regions_after_copy_failure(terrain_data, copied_regions, selected_original_regions)
			return false

	_runtime_road_original_regions = selected_original_regions
	_runtime_road_copied_regions = copied_regions
	_runtime_road_using_region_copies = true
	if terrain_data.has_method("update_maps"):
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_MAX, true, false)

	return true


func _restore_regions_after_copy_failure(terrain_data: Object, copied_regions: Array, original_regions: Array) -> void:
	for region: Variant in copied_regions:
		terrain_data.call("remove_region", region, false)

	for region: Variant in original_regions:
		terrain_data.call("add_region", region, false)

	if terrain_data.has_method("update_maps"):
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_MAX, true, false)


func _restore_original_terrain_regions(terrain_data: Object) -> void:
	if _runtime_road_original_regions.is_empty():
		_runtime_road_copied_regions.clear()
		_runtime_road_using_region_copies = false
		return

	if terrain_data.has_method("get_regions_active") and terrain_data.has_method("remove_region") and terrain_data.has_method("add_region"):
		for region: Variant in _runtime_road_copied_regions:
			terrain_data.call("remove_region", region, false)

		for region: Variant in _runtime_road_original_regions:
			terrain_data.call("add_region", region, false)

		if terrain_data.has_method("update_maps"):
			terrain_data.call("update_maps", Terrain3DRegion.TYPE_MAX, true, false)

	_runtime_road_original_regions.clear()
	_runtime_road_copied_regions.clear()
	_runtime_road_using_region_copies = false


func _get_terrain_texture_count(terrain_assets: Object) -> int:
	var texture_count := _get_texture_count_from_assets(terrain_assets)
	if texture_count > 0:
		return texture_count

	var resource_path := str(terrain_assets.get("resource_path"))
	if not resource_path.begins_with("res://"):
		return texture_count

	var extension := resource_path.get_extension()
	if extension != "tres" and extension != "res":
		return texture_count

	var loaded_assets := load(resource_path)
	if loaded_assets is Object and loaded_assets != terrain_assets:
		texture_count = max(texture_count, _get_texture_count_from_assets(loaded_assets as Object))

	return texture_count


func _get_texture_count_from_assets(terrain_assets: Object) -> int:
	var texture_count := 0
	if terrain_assets.has_method("get_texture_count"):
		texture_count = int(terrain_assets.call("get_texture_count"))

	if terrain_assets.has_method("get_texture_list"):
		var texture_list_variant: Variant = terrain_assets.call("get_texture_list")
		if texture_list_variant is Array:
			texture_count = max(texture_count, (texture_list_variant as Array).size())

	return texture_count


func _paint_road_polyline(
	terrain_data: Object,
	terrain: Node3D,
	polyline: PackedVector2Array,
	radius: float,
	sample_spacing: float,
	paint_step: float,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int,
	texture_strength: float,
	edge_feather: float,
	priority: int
) -> void:
	if polyline.is_empty():
		return

	if polyline.size() == 1:
		_paint_road_sample(
			terrain_data,
			terrain,
			polyline[0],
			radius,
			paint_step,
			texture_count,
			painted_points,
			target_texture_id,
			texture_strength,
			edge_feather,
			priority
		)
		return

	for index: int in range(polyline.size() - 1):
		var from_point := polyline[index]
		var to_point := polyline[index + 1]
		var segment := to_point - from_point
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue

		var sample_count := maxi(1, ceili(segment_length / sample_spacing))
		for sample_index: int in range(sample_count + 1):
			var weight := float(sample_index) / float(sample_count)
			_paint_road_sample(
				terrain_data,
				terrain,
				from_point.lerp(to_point, weight),
				radius,
				paint_step,
				texture_count,
				painted_points,
				target_texture_id,
				texture_strength,
				edge_feather,
				priority
			)


func _paint_road_sample(
	terrain_data: Object,
	terrain: Node3D,
	local_center: Vector2,
	radius: float,
	paint_step: float,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int,
	texture_strength: float,
	edge_feather: float,
	priority: int
) -> void:
	_paint_radial_texture_sample(
		terrain_data,
		terrain,
		local_center,
		radius,
		paint_step,
		texture_count,
		painted_points,
		target_texture_id,
		texture_strength,
		edge_feather,
		priority
	)


func _paint_radial_texture_sample(
	terrain_data: Object,
	terrain: Node3D,
	local_center: Vector2,
	radius: float,
	paint_step: float,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int,
	texture_strength: float,
	edge_feather: float,
	priority: int
) -> void:
	var safe_radius := maxf(radius, 0.001)
	var safe_paint_step := maxf(paint_step, MIN_TERRAIN_PAINT_STEP)
	var x := -safe_radius
	while x <= safe_radius + 0.001:
		var z := -safe_radius
		while z <= safe_radius + 0.001:
			var offset := Vector2(x, z)
			if offset.length_squared() <= safe_radius * safe_radius:
				var strength := _get_radial_texture_strength(offset.length() / safe_radius, texture_strength, edge_feather)
				if strength > 0.003:
					_paint_texture_point(
						terrain_data,
						terrain,
						local_center + offset,
						texture_count,
						painted_points,
						target_texture_id,
						strength,
						priority
					)
			z += safe_paint_step
		x += safe_paint_step


func _paint_texture_point(
	terrain_data: Object,
	terrain: Node3D,
	local_point: Vector2,
	texture_count: int,
	painted_points: Dictionary,
	target_texture_id: int,
	strength: float,
	priority: int
) -> void:
	var paint_key := Vector2i(
		roundi(local_point.x / TERRAIN_PAINT_RECORD_STEP),
		roundi(local_point.y / TERRAIN_PAINT_RECORD_STEP)
	)
	var existing_point_data: Variant = painted_points.get(paint_key)
	if existing_point_data is Dictionary:
		var existing_data := existing_point_data as Dictionary
		var existing_priority := int(existing_data.get("priority", 0))
		var existing_strength := float(existing_data.get("strength", 0.0))
		if existing_priority > priority or (existing_priority == priority and existing_strength >= strength):
			return

		existing_data["strength"] = strength
		existing_data["priority"] = priority
		painted_points[paint_key] = existing_data
	else:
		var world_position := _get_surface_world_position_from_local_2d(local_point, terrain)
		var original_control := int(terrain_data.call("get_control", world_position))
		var base_texture_id := _get_overlay_base_texture_id(terrain_data, world_position, original_control, texture_count, target_texture_id)
		_runtime_road_control_records.append({
			"position": world_position,
			"control": original_control,
		})
		painted_points[paint_key] = {
			"position": world_position,
			"base_texture_id": base_texture_id,
			"strength": strength,
			"priority": priority,
		}

	var point_data := painted_points[paint_key] as Dictionary
	_set_terrain_overlay_control(
		terrain_data,
		point_data["position"],
		int(point_data["base_texture_id"]),
		strength,
		target_texture_id
	)


func _set_terrain_overlay_control(terrain_data: Object, world_position: Vector3, base_texture_id: int, strength: float, target_texture_id: int) -> void:
	terrain_data.call("set_control_base_id", world_position, base_texture_id)
	if terrain_data.has_method("set_control_overlay_id"):
		terrain_data.call("set_control_overlay_id", world_position, target_texture_id)
	if terrain_data.has_method("set_control_blend"):
		terrain_data.call("set_control_blend", world_position, clampf(strength, 0.0, 1.0))
	if terrain_data.has_method("set_control_auto"):
		terrain_data.call("set_control_auto", world_position, false)


func _get_radial_texture_strength(normalized_distance: float, texture_strength: float, edge_feather: float) -> float:
	var strength := clampf(texture_strength, 0.0, 1.0)
	var feather := clampf(edge_feather, 0.0, 1.0)
	if feather <= 0.0:
		return strength

	var inner := clampf(1.0 - feather, 0.0, 1.0)
	if normalized_distance <= inner:
		return strength

	var edge_weight := clampf((normalized_distance - inner) / maxf(feather, 0.001), 0.0, 1.0)
	return strength * (1.0 - _smootherstep(edge_weight))


func _smootherstep(weight: float) -> float:
	var value := clampf(weight, 0.0, 1.0)
	return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)


func _get_overlay_base_texture_id(terrain_data: Object, world_position: Vector3, original_control: int, texture_count: int, target_texture_id: int) -> int:
	var control_auto := (original_control & 0x1) != 0
	var control_base_id := (original_control >> 27) & 0x1f
	var control_overlay_id := (original_control >> 22) & 0x1f
	var control_blend := float((original_control >> 14) & 0xff) / 255.0

	if not control_auto:
		var visible_control_id := control_overlay_id if control_blend >= 0.5 else control_base_id
		if _is_valid_overlay_base_texture_id(visible_control_id, texture_count, target_texture_id):
			return visible_control_id
		if _is_valid_overlay_base_texture_id(control_base_id, texture_count, target_texture_id):
			return control_base_id
		if _is_valid_overlay_base_texture_id(control_overlay_id, texture_count, target_texture_id):
			return control_overlay_id

	if terrain_data.has_method("get_texture_id"):
		var texture_info: Variant = terrain_data.call("get_texture_id", world_position)
		if texture_info is Vector3:
			var texture_ids := texture_info as Vector3
			if not is_nan(texture_ids.z):
				if texture_ids.z >= 0.5 and not is_nan(texture_ids.y):
					var visible_overlay_id := int(texture_ids.y)
					if _is_valid_overlay_base_texture_id(visible_overlay_id, texture_count, target_texture_id):
						return visible_overlay_id
				elif texture_ids.z < 0.5 and not is_nan(texture_ids.x):
					var visible_base_id := int(texture_ids.x)
					if _is_valid_overlay_base_texture_id(visible_base_id, texture_count, target_texture_id):
						return visible_base_id
			if not is_nan(texture_ids.x) and _is_valid_overlay_base_texture_id(int(texture_ids.x), texture_count, target_texture_id):
				return int(texture_ids.x)
			if not is_nan(texture_ids.y) and _is_valid_overlay_base_texture_id(int(texture_ids.y), texture_count, target_texture_id):
				return int(texture_ids.y)

	return 0


func _is_valid_overlay_base_texture_id(texture_id: int, texture_count: int, target_texture_id: int) -> bool:
	return texture_id >= 0 and texture_id < texture_count and texture_id != target_texture_id


func _get_nearest_road(point: Vector2, road_polylines: Array) -> Dictionary:
	var nearest := {}
	var best_distance_squared := INF

	for polyline: PackedVector2Array in road_polylines:
		if polyline.is_empty():
			continue

		if polyline.size() == 1:
			var point_distance_squared := point.distance_squared_to(polyline[0])
			if point_distance_squared < best_distance_squared:
				best_distance_squared = point_distance_squared
				nearest = {
					"point": polyline[0],
					"tangent": Vector2.ZERO,
					"distance": sqrt(point_distance_squared),
				}
			continue

		for index: int in range(polyline.size() - 1):
			var from_point := polyline[index]
			var to_point := polyline[index + 1]
			var closest := _closest_point_on_segment(point, from_point, to_point)
			var distance_squared := point.distance_squared_to(closest)
			if distance_squared < best_distance_squared:
				var tangent := to_point - from_point
				best_distance_squared = distance_squared
				nearest = {
					"point": closest,
					"tangent": tangent.normalized() if tangent.length_squared() > 0.0001 else Vector2.ZERO,
					"distance": sqrt(distance_squared),
				}

	return nearest


func _closest_point_on_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> Vector2:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return from_point

	var weight := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return from_point + segment * weight


func _is_point_near_roads(point: Vector2, road_polylines: Array, clearance: float) -> bool:
	if clearance <= 0.0 or road_polylines.is_empty():
		return false

	var nearest := _get_nearest_road(point, road_polylines)
	if nearest.is_empty():
		return false

	return float(nearest.get("distance", INF)) <= clearance


func _is_point_in_shrunken_cells(point: Vector2, cell_lookup: Dictionary, margin: float) -> bool:
	if not _is_point_in_cells(point, cell_lookup):
		return false

	var safe_margin := maxf(margin, 0.0)
	if safe_margin <= 0.0:
		return true

	var cell := _local_2d_to_cell(point)
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	var cell_max := cell_min + Vector2(safe_cell_size, safe_cell_size)

	if point.x - cell_min.x < safe_margin and not cell_lookup.has(cell + Vector2i(-1, 0)):
		return false
	if cell_max.x - point.x < safe_margin and not cell_lookup.has(cell + Vector2i(1, 0)):
		return false
	if point.y - cell_min.y < safe_margin and not cell_lookup.has(cell + Vector2i(0, -1)):
		return false
	if cell_max.y - point.y < safe_margin and not cell_lookup.has(cell + Vector2i(0, 1)):
		return false

	return true


func _is_point_in_cells(point: Vector2, cell_lookup: Dictionary) -> bool:
	return cell_lookup.has(_local_2d_to_cell(point))


func _has_house_spacing(point: Vector2, footprint: float, placed_houses: Array[Dictionary]) -> bool:
	var safe_footprint := maxf(footprint, 0.1)
	var safe_multiplier := maxf(house_size_spacing_multiplier, 1.0)
	var density_spacing_scale := 1.0 / sqrt(_get_safe_house_density())
	for placed_house: Dictionary in placed_houses:
		var placed_position: Vector2 = placed_house.get("position", Vector2.ZERO)
		var placed_footprint := maxf(float(placed_house.get("footprint", safe_footprint)), 0.1)
		var required_spacing := maxf(house_min_spacing, safe_multiplier * maxf(safe_footprint, placed_footprint))
		required_spacing *= density_spacing_scale
		if point.distance_squared_to(placed_position) < required_spacing * required_spacing:
			return false
	return true


func _is_house_overlapping_storage(
	point: Vector2,
	footprint_radius: float,
	storage_center: Vector2,
	storage_clearance_radius: float
) -> bool:
	var required_spacing := maxf(footprint_radius, 0.0) + maxf(storage_clearance_radius, 0.0)
	if required_spacing <= 0.0:
		return false
	return point.distance_squared_to(storage_center) < required_spacing * required_spacing


func _get_village_storage_reserved_radius() -> float:
	if village_storage_clearance_radius > 0.0:
		return village_storage_clearance_radius

	var scene_radius := _get_scene_plan_radius(VILLAGE_STORAGE_SCENE, village_storage_model_scale)
	return maxf(scene_radius + maxf(house_min_spacing, house_footprint_padding), cell_size * 2.2)


func _get_scene_plan_radius(scene: PackedScene, scene_scale: float) -> float:
	if not scene:
		return 0.0

	var instance := scene.instantiate()
	if not (instance is Node3D):
		instance.free()
		return 0.0

	var spatial := instance as Node3D
	spatial.scale *= maxf(scene_scale, 0.1)
	var bounds := _get_node_local_aabb(spatial, Transform3D.IDENTITY)
	var radius := 0.0
	if bounds.size.length_squared() > 0.0001:
		radius = maxf(
			maxf(absf(bounds.position.x), absf(bounds.end.x)),
			maxf(absf(bounds.position.z), absf(bounds.end.z))
		)
	instance.free()
	return radius


func _get_effective_house_max_count() -> int:
	return maxi(ceili(float(house_max_count) * _get_safe_house_density()), 0)


func _get_safe_house_density() -> float:
	return maxf(house_density, 0.25)


func _get_house_footprint_data(scene: PackedScene) -> Dictionary:
	var cache_key := scene.resource_path if not scene.resource_path.is_empty() else str(scene.get_instance_id())
	if _house_footprint_cache.has(cache_key):
		return _get_padded_house_footprint_data(_house_footprint_cache[cache_key] as Dictionary)

	var footprint := cell_size
	var base_radius := cell_size * 0.5
	var instance := scene.instantiate()
	if instance is Node3D:
		var bounds := _get_node_local_aabb(instance as Node3D, Transform3D.IDENTITY)
		if bounds.size.length_squared() > 0.0001:
			footprint = maxf(maxf(bounds.size.x, bounds.size.z), 0.1)
			base_radius = maxf(
				maxf(absf(bounds.position.x), absf(bounds.end.x)),
				maxf(absf(bounds.position.z), absf(bounds.end.z))
			)

	instance.free()
	var cached_data := {
		"footprint": footprint,
		"base_radius": maxf(base_radius, footprint * 0.5),
	}
	_house_footprint_cache[cache_key] = cached_data
	return _get_padded_house_footprint_data(cached_data)


func _get_padded_house_footprint_data(cached_data: Dictionary) -> Dictionary:
	var footprint := maxf(float(cached_data.get("footprint", cell_size)), 0.1)
	var base_radius := maxf(float(cached_data.get("base_radius", footprint * 0.5)), footprint * 0.5)
	return {
		"footprint": footprint,
		"radius": base_radius + maxf(house_footprint_padding, 0.0),
	}


func _get_node_local_aabb(node: Node3D, parent_transform: Transform3D) -> AABB:
	var local_transform := parent_transform * node.transform
	var has_bounds := false
	var bounds := AABB()

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			bounds = _merge_optional_aabb(bounds, _transform_aabb(local_transform, mesh_instance.mesh.get_aabb()), has_bounds)
			has_bounds = true
	elif node is CollisionShape3D:
		var shape_bounds := _get_collision_shape_aabb((node as CollisionShape3D).shape)
		if shape_bounds.size.length_squared() > 0.0001:
			bounds = _merge_optional_aabb(bounds, _transform_aabb(local_transform, shape_bounds), has_bounds)
			has_bounds = true

	for child: Node in node.get_children():
		if not (child is Node3D):
			continue
		var child_bounds := _get_node_local_aabb(child as Node3D, local_transform)
		if child_bounds.size.length_squared() <= 0.0001:
			continue
		bounds = _merge_optional_aabb(bounds, child_bounds, has_bounds)
		has_bounds = true

	return bounds if has_bounds else AABB()


func _get_collision_shape_aabb(shape: Shape3D) -> AABB:
	if not shape:
		return AABB()

	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(size * -0.5, size)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		var size := Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
		return AABB(size * -0.5, size)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var size := Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
		return AABB(size * -0.5, size)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		return AABB(size * -0.5, size)

	return AABB()


func _transform_aabb(transform: Transform3D, aabb: AABB) -> AABB:
	var corners := [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.end,
	]

	var transformed := AABB(transform * corners[0], Vector3.ZERO)
	for index: int in range(1, corners.size()):
		transformed = transformed.expand(transform * corners[index])
	return transformed


func _merge_optional_aabb(current: AABB, added: AABB, has_current: bool) -> AABB:
	if not has_current:
		return added
	return current.merge(added)


func _get_random_point_in_cell(cell: Vector2i, rng: RandomNumberGenerator) -> Vector2:
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	return cell_min + Vector2(
		rng.randf_range(0.0, safe_cell_size),
		rng.randf_range(0.0, safe_cell_size)
	)


func _local_2d_to_cell(point: Vector2) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2i(
		floori((point.x - origin.x) / safe_cell_size),
		floori((point.y - origin.z) / safe_cell_size)
	)


func _cell_to_local_2d_center(cell: Vector2i) -> Vector2:
	var local_center := cell_to_local_center(cell)
	return Vector2(local_center.x, local_center.z)


func _cell_to_local_2d_min(cell: Vector2i) -> Vector2:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2(
		origin.x + float(cell.x) * safe_cell_size,
		origin.z + float(cell.y) * safe_cell_size
	)


func _get_village_center_local_2d() -> Vector2:
	var cells: Array[Vector2i] = []
	cells.append_array(get_house_cells())
	cells.append_array(get_field_cells())
	cells.append_array(get_road_cells())
	var bounds := _get_cell_bounds_2d(cells, 0.0)
	if not bounds.is_empty():
		var min_point: Vector2 = bounds.get("min", Vector2.ZERO)
		var max_point: Vector2 = bounds.get("max", Vector2.ZERO)
		return min_point.lerp(max_point, 0.5)

	if not _house_food_records.is_empty():
		var total := Vector2.ZERO
		for record: Dictionary in _house_food_records:
			var position: Vector2 = record.get("position", Vector2.ZERO)
			total += position
		return total / float(_house_food_records.size())

	return Vector2(origin.x, origin.z)


func _get_village_storage_center_local_2d(house_placements: Array[Dictionary] = []) -> Vector2:
	if not house_placements.is_empty():
		var placement_points: Array[Vector2] = []
		for placement: Dictionary in house_placements:
			placement_points.append(placement.get("position", Vector2.ZERO))
		var placement_bounds := _get_point_bounds_2d(placement_points, 0.0)
		if not placement_bounds.is_empty():
			var placement_min: Vector2 = placement_bounds.get("min", Vector2.ZERO)
			var placement_max: Vector2 = placement_bounds.get("max", Vector2.ZERO)
			return placement_min.lerp(placement_max, 0.5)

	if not _house_food_records.is_empty():
		var total := Vector2.ZERO
		for record: Dictionary in _house_food_records:
			total += record.get("position", Vector2.ZERO)
		return total / float(_house_food_records.size())

	var bounds := _get_cell_bounds_2d(get_house_cells(), 0.0)
	if not bounds.is_empty():
		var min_point: Vector2 = bounds.get("min", Vector2.ZERO)
		var max_point: Vector2 = bounds.get("max", Vector2.ZERO)
		return min_point.lerp(max_point, 0.5)
	return _get_village_center_local_2d()


func _get_cell_corners(cell: Vector2i) -> Array[Vector2]:
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	return [
		cell_min,
		cell_min + Vector2(safe_cell_size, 0.0),
		cell_min + Vector2(safe_cell_size, safe_cell_size),
		cell_min + Vector2(0.0, safe_cell_size),
	]


func _yaw_for_minus_z(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)


func _yaw_for_plus_x(direction: Vector2) -> float:
	return atan2(-direction.y, direction.x)


func _get_house_scene() -> PackedScene:
	if house_scene:
		return house_scene
	if village_type and village_type.house_scene:
		return village_type.house_scene
	return DEFAULT_HOUSE_SCENE


func _get_house_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for scene: PackedScene in house_scenes:
		if scene:
			scenes.append(scene)

	if scenes.is_empty() and village_type:
		for scene: PackedScene in village_type.house_scenes:
			if scene:
				scenes.append(scene)

	if scenes.is_empty():
		var fallback := _get_house_scene()
		if fallback:
			scenes.append(fallback)

	return scenes


func _get_house_scene_for_index(index: int, rng: RandomNumberGenerator) -> PackedScene:
	var scenes := _get_house_scenes()
	if scenes.is_empty():
		return null
	if scenes.size() == 1:
		return scenes[0]

	var mixed_index := absi(_mix_house_variant(index, rng.randi()))
	return scenes[mixed_index % scenes.size()]


func _mix_house_variant(index: int, random_value: int) -> int:
	var mixed := int(generation_seed)
	mixed = int((mixed * 1664525 + (index + 1) * 1013904223) & 0x7fffffff)
	mixed = int((mixed * 1664525 + random_value * 1013904223) & 0x7fffffff)
	return mixed


func _get_peasant_scene() -> PackedScene:
	if peasant_scene:
		return peasant_scene
	if village_type and village_type.peasant_scene:
		return village_type.peasant_scene
	return DEFAULT_PEASANT_SCENE


func _get_effective_peasant_target_count() -> int:
	if (
		village_type
		and peasant_target_count == DEFAULT_PEASANT_TARGET_COUNT
		and village_type.peasant_target_count != DEFAULT_PEASANT_TARGET_COUNT
	):
		return maxi(village_type.peasant_target_count, 0)
	return maxi(peasant_target_count, 0)


func _get_effective_peasant_spawn_rate_per_minute() -> float:
	if (
		village_type
		and is_equal_approx(peasant_spawn_rate_per_minute, DEFAULT_PEASANT_SPAWN_RATE_PER_MINUTE)
		and not is_equal_approx(village_type.peasant_spawn_rate_per_minute, DEFAULT_PEASANT_SPAWN_RATE_PER_MINUTE)
	):
		return maxf(village_type.peasant_spawn_rate_per_minute, 0.0)
	return maxf(peasant_spawn_rate_per_minute, 0.0)


func _get_effective_peasant_death_rate_per_minute() -> float:
	if (
		village_type
		and is_equal_approx(peasant_death_rate_per_minute, DEFAULT_PEASANT_DEATH_RATE_PER_MINUTE)
		and not is_equal_approx(village_type.peasant_death_rate_per_minute, DEFAULT_PEASANT_DEATH_RATE_PER_MINUTE)
	):
		return maxf(village_type.peasant_death_rate_per_minute, 0.0)
	return maxf(peasant_death_rate_per_minute, 0.0)


func _get_peasant_population_seed() -> int:
	return _mix_peasant_seed(0x5eed, generation_seed)


func _mix_peasant_seed(index: int, random_value: int) -> int:
	var mixed := int(generation_seed)
	mixed = int((mixed * 1103515245 + 12345 + index * 2654435761) & 0x7fffffff)
	mixed = int((mixed * 1103515245 + 12345 + random_value) & 0x7fffffff)
	return absi(mixed)


func _get_default_crop_type() -> CropTypeData:
	return default_crop_type if default_crop_type else DEFAULT_CROP_TYPE


func _get_terrain_node() -> Node3D:
	if terrain_path.is_empty():
		return null

	var terrain := get_node_or_null(terrain_path)
	if terrain is Node3D:
		return terrain
	return null


func _mark_startup_phase(label: String, context: Dictionary = {}) -> void:
	if Engine.is_editor_hint():
		return

	var probe := get_node_or_null("/root/StartupPerformanceProbe") if is_inside_tree() else null
	if probe and probe.has_method("mark_phase"):
		probe.call("mark_phase", label, context)


func _get_field_terrain_registry_node() -> FieldTerrainRegistry:
	if field_terrain_registry_path.is_empty():
		return null

	var node := get_node_or_null(field_terrain_registry_path)
	if node is FieldTerrainRegistry:
		return node
	return null


func _get_terrain_data(terrain: Node3D) -> Object:
	if not _is_terrain_ready_for_height_queries(terrain):
		return null

	var terrain_data: Variant = terrain.get("data")
	if not (terrain_data is Object):
		return null

	var terrain_data_object := terrain_data as Object
	if not is_instance_valid(terrain_data_object) or terrain_data_object.is_queued_for_deletion():
		return null

	return terrain_data_object


func _get_terrain_height(terrain: Node3D, world_position: Vector3) -> Variant:
	var terrain_data_object := _get_terrain_data(terrain)
	if not terrain_data_object:
		return null

	if not terrain_data_object.has_method("get_height"):
		return null
	if terrain_data_object.has_method("get_region_count"):
		var region_count := int(terrain_data_object.call("get_region_count"))
		if region_count <= 0:
			return null

	var height: float = terrain_data_object.call("get_height", world_position)
	if is_nan(height) or absf(height) > 1.0e20:
		return null

	return height


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


func _notify_cells_changed() -> void:
	if _suspend_cell_notifications:
		return
	cells_changed.emit()
	if Engine.is_editor_hint() and is_inside_tree():
		request_editor_gizmo_update()


func _region_local_to_world(local_position: Vector3) -> Vector3:
	if is_inside_tree():
		return global_transform * local_position
	return transform * local_position


func _world_to_region_local(world_position: Vector3) -> Vector3:
	if is_inside_tree():
		return to_local(world_position)
	return transform.affine_inverse() * world_position


func _is_terrain_ready_for_height_queries(terrain: Node3D) -> bool:
	if not is_instance_valid(terrain) or terrain.is_queued_for_deletion():
		return false
	if Engine.is_editor_hint() and not _is_node_in_active_edited_scene(terrain):
		return false
	return true


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
