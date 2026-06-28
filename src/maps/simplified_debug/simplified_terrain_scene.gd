extends Node3D
class_name SimplifiedTerrainScene

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")

const TERRAIN_VISUALS_NODE_NAME := "SimplifiedTerrainTiles"
const GROUND_BODY_NODE_NAME := "SimplifiedGroundBody"
const GRID_LINES_NODE_NAME := "SimplifiedTileGrid"
const DEBUG_GROUP := &"simplified_terrain_debug"

@export_range(8, 256, 1, "or_greater") var width_cells: int = 48
@export_range(8, 256, 1, "or_greater") var height_cells: int = 32
@export_range(0.5, 64.0, 0.5, "or_greater") var cell_size_meters: float = 4.0
@export var map_center: Vector2 = Vector2.ZERO
@export var terrain_y: float = 0.0
@export var walkable_tile_color: Color = Color(0.24, 0.39, 0.27, 1.0)
@export var non_walkable_tile_color: Color = Color(0.32, 0.11, 0.09, 1.0)
@export var grid_line_color: Color = Color(0.70, 0.86, 0.88, 0.28)
@export var terrain_visible := true:
	set(value):
		terrain_visible = value
		_update_debug_visibility()
@export var show_tile_grid := true:
	set(value):
		show_tile_grid = value
		_update_debug_visibility()

var _movement_map: MovementMapData
var _terrain_visuals: Node3D
var _grid_lines: MeshInstance3D
var _ground_body: StaticBody3D


func _enter_tree() -> void:
	add_to_group(DEBUG_GROUP)
	_movement_map = _build_movement_map()
	_assign_movement_map_to_runtime_nodes()


func _ready() -> void:
	_assign_movement_map_to_runtime_nodes()
	_rebuild_flat_terrain()
	_center_camera()
	_update_debug_visibility()


func _exit_tree() -> void:
	remove_from_group(DEBUG_GROUP)


func get_movement_map() -> MovementMapData:
	return _movement_map


func set_terrain_visible(enabled: bool) -> void:
	terrain_visible = enabled


func is_terrain_visible() -> bool:
	return terrain_visible


func get_debug_summary() -> Dictionary:
	if not _movement_map:
		return {}
	var blocked := 0
	for speed: float in _movement_map.speed_multipliers:
		if speed <= 0.0:
			blocked += 1
	var total := _movement_map.width * _movement_map.height
	return {
		"width": _movement_map.width,
		"height": _movement_map.height,
		"cell_size_meters": _movement_map.cell_size_meters,
		"walkable_cells": total - blocked,
		"non_walkable_cells": blocked,
	}


func _build_movement_map() -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	var safe_width := maxi(width_cells, 1)
	var safe_height := maxi(height_cells, 1)
	var safe_cell_size := maxf(cell_size_meters, 0.001)
	data.origin = _get_map_origin(safe_width, safe_height, safe_cell_size)
	data.cell_size_meters = safe_cell_size
	data.resize_map(safe_width, safe_height, 1.0, 0)

	for y: int in range(safe_height):
		for x: int in range(safe_width):
			var cell := Vector2i(x, y)
			if _is_non_walkable_cell(cell, safe_width, safe_height):
				var index := data.get_cell_index(cell)
				data.speed_multipliers[index] = 0.0
				data.flags[index] = MovementMapDataScript.FLAG_STEEP_SLOPE
	return data


func _is_non_walkable_cell(cell: Vector2i, map_width: int, map_height: int) -> bool:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= map_width - 1 or cell.y >= map_height - 1:
		return true

	var center_x := int(map_width / 2)
	var vertical_bar := absi(cell.x - center_x) <= 1
	var north_gap := cell.y >= 6 and cell.y <= 10
	var south_gap := cell.y >= map_height - 11 and cell.y <= map_height - 7
	if vertical_bar and not north_gap and not south_gap:
		return true

	var horizontal_bar := cell.y >= int(map_height * 0.52) and cell.y <= int(map_height * 0.52) + 1
	var horizontal_span := cell.x >= 7 and cell.x <= int(map_width * 0.44)
	var gate := cell.x >= 12 and cell.x <= 14
	if horizontal_bar and horizontal_span and not gate:
		return true

	var pond_center := Vector2(float(map_width - 12), 9.5)
	var pond_delta := Vector2(float(cell.x), float(cell.y)) - pond_center
	if (pond_delta.x * pond_delta.x) / 18.0 + (pond_delta.y * pond_delta.y) / 30.0 <= 1.0:
		return true

	var ridge_start := Vector2i(9, map_height - 10)
	var ridge_end := Vector2i(18, map_height - 4)
	if cell.x >= ridge_start.x and cell.x <= ridge_end.x and cell.y >= ridge_start.y and cell.y <= ridge_end.y:
		return absi((cell.y - ridge_start.y) - int((cell.x - ridge_start.x) * 0.7)) <= 1

	return false


func _rebuild_flat_terrain() -> void:
	_clear_generated_node(TERRAIN_VISUALS_NODE_NAME)
	_clear_generated_node(GROUND_BODY_NODE_NAME)
	_terrain_visuals = Node3D.new()
	_terrain_visuals.name = TERRAIN_VISUALS_NODE_NAME
	add_child(_terrain_visuals)
	_terrain_visuals.owner = null

	var walkable_transforms: Array[Transform3D] = []
	var blocked_transforms: Array[Transform3D] = []
	var data := _movement_map
	if not data:
		return

	for y: int in range(data.height):
		for x: int in range(data.width):
			var cell := Vector2i(x, y)
			var center := data.cell_to_world_center(cell)
			var transform := Transform3D(Basis(), Vector3(center.x, terrain_y, center.y))
			if data.is_walkable_cell(cell):
				walkable_transforms.append(transform)
			else:
				blocked_transforms.append(transform)

	_terrain_visuals.add_child(_make_tile_multimesh("WalkableTiles", walkable_transforms, walkable_tile_color))
	_terrain_visuals.add_child(_make_tile_multimesh("NonWalkableTiles", blocked_transforms, non_walkable_tile_color))
	_grid_lines = _make_grid_lines()
	_terrain_visuals.add_child(_grid_lines)
	_create_ground_collision()
	_update_debug_visibility()


func _make_tile_multimesh(name: String, transforms: Array[Transform3D], color: Color) -> MultiMeshInstance3D:
	var tile_mesh := PlaneMesh.new()
	var tile_gap := minf(maxf(cell_size_meters * 0.025, 0.02), 0.12)
	var tile_size := maxf(cell_size_meters - tile_gap, 0.05)
	tile_mesh.size = Vector2(tile_size, tile_size)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tile_mesh
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = multimesh
	instance.material_override = _make_tile_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance


func _make_grid_lines() -> MeshInstance3D:
	var data := _movement_map
	var instance := MeshInstance3D.new()
	instance.name = GRID_LINES_NODE_NAME
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if not data:
		return instance

	var mesh := ImmediateMesh.new()
	var material := _make_grid_material()
	var origin := data.origin
	var size := Vector2(float(data.width), float(data.height)) * data.cell_size_meters
	var y := terrain_y + 0.035
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for x: int in range(data.width + 1):
		var world_x := origin.x + float(x) * data.cell_size_meters
		mesh.surface_add_vertex(Vector3(world_x, y, origin.y))
		mesh.surface_add_vertex(Vector3(world_x, y, origin.y + size.y))
	for z: int in range(data.height + 1):
		var world_z := origin.y + float(z) * data.cell_size_meters
		mesh.surface_add_vertex(Vector3(origin.x, y, world_z))
		mesh.surface_add_vertex(Vector3(origin.x + size.x, y, world_z))
	mesh.surface_end()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _create_ground_collision() -> void:
	var data := _movement_map
	if not data:
		return
	_ground_body = StaticBody3D.new()
	_ground_body.name = GROUND_BODY_NODE_NAME
	_ground_body.collision_layer = 1
	_ground_body.collision_mask = 0
	var shape := BoxShape3D.new()
	var size := Vector2(float(data.width), float(data.height)) * data.cell_size_meters
	shape.size = Vector3(size.x, 0.12, size.y)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	_ground_body.add_child(collision)
	_ground_body.position = Vector3(data.origin.x + size.x * 0.5, terrain_y - 0.06, data.origin.y + size.y * 0.5)
	add_child(_ground_body)
	_ground_body.owner = null


func _make_tile_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _make_grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = grid_line_color
	material.no_depth_test = true
	return material


func _assign_movement_map_to_runtime_nodes() -> void:
	if not _movement_map:
		return
	_assign_movement_map_recursive(self)


func _assign_movement_map_recursive(node: Node) -> void:
	if node != self:
		if _object_has_property(node, &"movement_map"):
			node.set("movement_map", _movement_map)
		if _object_has_property(node, &"movement_map_path"):
			node.set("movement_map_path", "")
	for child: Node in node.get_children():
		_assign_movement_map_recursive(child)


func _center_camera() -> void:
	var camera_rig := get_node_or_null("RTSCameraRig")
	if camera_rig and camera_rig.has_method("set_target_world_position"):
		camera_rig.call("set_target_world_position", Vector3(map_center.x, terrain_y, map_center.y), true)


func _update_debug_visibility() -> void:
	if is_instance_valid(_terrain_visuals):
		_terrain_visuals.visible = true
		for child: Node in _terrain_visuals.get_children():
			if child == _grid_lines:
				continue
			if child is Node3D:
				(child as Node3D).visible = terrain_visible
	if is_instance_valid(_grid_lines):
		_grid_lines.visible = show_tile_grid


func _clear_generated_node(node_name: String) -> void:
	var existing := get_node_or_null(node_name)
	if not existing:
		return
	remove_child(existing)
	existing.free()


func _get_map_origin(map_width: int, map_height: int, safe_cell_size: float) -> Vector2:
	return map_center - Vector2(float(map_width), float(map_height)) * safe_cell_size * 0.5


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(String(property.get("name", ""))) == property_name:
			return true
	return false
