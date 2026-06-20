extends Node3D
class_name Troop

signal selected_changed(selected: bool)
signal state_changed(state: StringName)
signal destination_changed(summary: Dictionary)

const DEFAULT_SOLDIER_SCENE: PackedScene = preload("res://modules/units/human/human.tscn")
const TroopRouteVisualScript = preload("res://modules/troops/troop_route_visual.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")

const STATE_IDLE := &"idle"
const STATE_MOVING := &"moving"
const STATE_BLOCKED := &"blocked"

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"

const SOLDIER_CONTAINER_NAME := "Soldiers"
const RING_NODE_NAME := "TroopRing"
const SELECTION_PROXY_NAME := "TroopClickProxy"
const ROUTE_VISUAL_NAME := "TroopRouteVisual"

@export_group("Identity")
@export var troop_id: StringName = &"troop_01"
@export var display_name := "Troop"

@export_group("Formation")
@export_range(2, 256, 1, "or_greater") var soldier_count: int = 12:
	set(value):
		soldier_count = maxi(value, 2)
		if is_inside_tree():
			rebuild_formation()
@export var soldier_scene: PackedScene = DEFAULT_SOLDIER_SCENE:
	set(value):
		soldier_scene = value
		if is_inside_tree():
			rebuild_formation()
@export_range(1, 32, 1, "or_greater") var formation_columns: int = 4:
	set(value):
		formation_columns = maxi(value, 1)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.2, 16.0, 0.05, "or_greater") var formation_spacing: float = 1.45:
	set(value):
		formation_spacing = maxf(value, 0.2)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.1, 8.0, 0.05, "or_greater") var soldier_scale: float = 1.0:
	set(value):
		soldier_scale = maxf(value, 0.1)
		if is_inside_tree():
			rebuild_formation()

@export_group("Flags")
@export var team_flag_color: Color = Color(0.1, 0.28, 0.82, 1.0):
	set(value):
		team_flag_color = value
		if is_inside_tree():
			rebuild_formation()
@export var troop_flag_color: Color = Color(0.78, 0.1, 0.08, 1.0):
	set(value):
		troop_flag_color = value
		if is_inside_tree():
			rebuild_formation()
@export var carried_flag_mount_offset: Vector3 = Vector3(0.18, 0.22, 0.0):
	set(value):
		carried_flag_mount_offset = value
		if is_inside_tree():
			rebuild_formation()
@export_range(0.5, 8.0, 0.05, "or_greater") var carried_flag_pole_height: float = 2.45:
	set(value):
		carried_flag_pole_height = maxf(value, 0.5)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.01, 0.5, 0.005, "or_greater") var carried_flag_pole_radius: float = 0.04:
	set(value):
		carried_flag_pole_radius = maxf(value, 0.01)
		if is_inside_tree():
			rebuild_formation()
@export var carried_flag_banner_size: Vector2 = Vector2(1.12, 0.66):
	set(value):
		carried_flag_banner_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		if is_inside_tree():
			rebuild_formation()
@export_range(-45.0, 45.0, 0.5) var carried_flag_roll_degrees: float = -8.0:
	set(value):
		carried_flag_roll_degrees = value
		if is_inside_tree():
			rebuild_formation()

@export_group("Visibility")
@export_range(0.0, 128.0, 0.1, "or_greater") var ring_radius: float = 0.0:
	set(value):
		ring_radius = maxf(value, 0.0)
		if is_inside_tree():
			_rebuild_ring()
			_rebuild_selection_proxy()
@export_range(0.01, 16.0, 0.01, "or_greater") var ring_width: float = 0.16:
	set(value):
		ring_width = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_ring()
@export_range(1.0, 12.0, 0.1, "or_greater") var ring_screen_width_px: float = 2.25:
	set(value):
		ring_screen_width_px = maxf(value, 1.0)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.01, 2.0, 0.01, "or_greater") var ring_min_world_width: float = 0.04:
	set(value):
		ring_min_world_width = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.05, 12.0, 0.05, "or_greater") var ring_max_world_width: float = 4.0:
	set(value):
		ring_max_world_width = maxf(value, 0.05)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.0, 8.0, 0.01, "or_greater") var ring_surface_offset: float = 0.42
@export var ring_color: Color = Color(0.18, 0.82, 0.95, 0.58):
	set(value):
		ring_color = value
		if is_inside_tree():
			_update_ring_material()
@export var selected_ring_color: Color = Color(1.0, 0.82, 0.28, 0.78):
	set(value):
		selected_ring_color = value
		if is_inside_tree():
			_update_ring_material()

@export_group("Selection")
@export_flags_3d_physics var selection_collision_layer: int = 1 << 5:
	set(value):
		selection_collision_layer = value
		if is_inside_tree():
			_rebuild_selection_proxy()

@export_group("Movement")
@export var movement_map: Resource
@export_file("*.res", "*.tres") var movement_map_path := ""
@export_node_path("Node3D") var terrain_path: NodePath
@export_range(0.1, 40.0, 0.1, "or_greater") var movement_speed_mps: float = 4.5
@export_range(0.1, 32.0, 0.1, "or_greater") var arrival_radius: float = 1.25
@export_range(0, 64, 1, "or_greater") var nearest_walkable_search_radius_cells: int = 12
@export_range(0.05, 2.0, 0.05, "or_greater") var route_refresh_interval: float = 0.25

@export_group("Route Visual")
@export_range(0.01, 8.0, 0.01, "or_greater") var route_line_width: float = 0.16:
	set(value):
		route_line_width = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(1.0, 12.0, 0.1, "or_greater") var route_line_screen_width_px: float = 2.0:
	set(value):
		route_line_screen_width_px = maxf(value, 1.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 2.0, 0.01, "or_greater") var route_line_min_world_width: float = 0.04:
	set(value):
		route_line_min_world_width = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.05, 12.0, 0.05, "or_greater") var route_line_max_world_width: float = 4.0:
	set(value):
		route_line_max_world_width = maxf(value, 0.05)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 2.0, 0.01, "or_greater") var route_line_height: float = 0.035:
	set(value):
		route_line_height = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.25, 32.0, 0.25, "or_greater") var route_dash_length: float = 5.0:
	set(value):
		route_dash_length = maxf(value, 0.25)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.0, 32.0, 0.25, "or_greater") var route_dash_gap: float = 3.0:
	set(value):
		route_dash_gap = maxf(value, 0.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.0, 8.0, 0.01, "or_greater") var route_surface_offset: float = 0.35:
	set(value):
		route_surface_offset = maxf(value, 0.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(1.0, 12.0, 0.05, "or_greater") var destination_flag_pole_height: float = 4.2:
	set(value):
		destination_flag_pole_height = maxf(value, 1.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 0.5, 0.005, "or_greater") var destination_flag_pole_radius: float = 0.08:
	set(value):
		destination_flag_pole_radius = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export var destination_flag_banner_size: Vector2 = Vector2(1.65, 0.94):
	set(value):
		destination_flag_banner_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()

var _soldier_container: Node3D
var _ring_instance: MeshInstance3D
var _selection_proxy: StaticBody3D
var _route_visual: Node
var _terrain: Node3D
var _movement_map: Resource
var _selected := false
var _state: StringName = STATE_IDLE
var _path_points: Array[Vector3] = []
var _current_path_index := 0
var _has_destination := false
var _destination := Vector3.ZERO
var _last_path_result: Dictionary = {}
var _route_refresh_remaining := 0.0
var _last_ring_world_width := -1.0


func _ready() -> void:
	add_to_group(&"troops")
	_resolve_dependencies()
	_ensure_scene_nodes()
	_load_movement_map()
	rebuild_formation()
	_rebuild_ring()
	_rebuild_selection_proxy()
	_update_ring_material()
	_snap_to_surface()
	_emit_destination_changed()


func _physics_process(delta: float) -> void:
	if _state != STATE_MOVING:
		return

	_follow_path(delta)
	_route_refresh_remaining -= delta
	if _route_refresh_remaining <= 0.0:
		_route_refresh_remaining = maxf(route_refresh_interval, 0.05)
		_update_route_visual()


func _process(_delta: float) -> void:
	_update_screen_constant_ring_width()


func rebuild_formation() -> void:
	_ensure_scene_nodes()
	_clear_children(_soldier_container)

	var scene := soldier_scene if soldier_scene else DEFAULT_SOLDIER_SCENE
	var columns := mini(maxi(formation_columns, 1), soldier_count)
	var rows := ceili(float(soldier_count) / float(columns))
	for index: int in range(soldier_count):
		var soldier := scene.instantiate()
		if not (soldier is Node3D):
			soldier.free()
			continue

		var spatial := soldier as Node3D
		spatial.name = "Soldier_%03d" % index
		_configure_visual_soldier(spatial)
		_soldier_container.add_child(spatial)
		spatial.owner = null
		spatial.position = _get_formation_position(index, columns, rows)
		spatial.rotation.y = 0.0
		spatial.scale = Vector3.ONE * soldier_scale

		if index == 0:
			_attach_flag_to_soldier(spatial, "TeamFlag", team_flag_color, troop_flag_color)
		elif index == 1:
			_attach_flag_to_soldier(spatial, "TroopFlag", troop_flag_color, team_flag_color)

	_rebuild_ring()
	_rebuild_selection_proxy()
	_emit_destination_changed()


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_update_ring_material()
	selected_changed.emit(_selected)


func is_selected() -> bool:
	return _selected


func set_move_destination(world_position: Vector3) -> bool:
	_load_movement_map()
	if not _movement_map:
		_last_path_result = MovementMapPathfinderScript.find_path(null, global_position, world_position)
		_set_state(STATE_BLOCKED)
		_emit_destination_changed()
		return false

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		_movement_map,
		global_position,
		world_position,
		maxf(movement_speed_mps, 0.1),
		nearest_walkable_search_radius_cells
	)
	_last_path_result = result
	if not bool(result.get("reachable", false)):
		_path_points.clear()
		_current_path_index = 0
		_has_destination = false
		_clear_route_visual()
		_set_state(STATE_BLOCKED)
		_emit_destination_changed()
		return false

	_path_points = _snap_path_points(result.get("points", []) as Array)
	_current_path_index = 1 if _path_points.size() > 1 else 0
	_destination = _snap_world_point(result.get("resolved_destination", world_position) as Vector3)
	_has_destination = true
	_route_refresh_remaining = 0.0
	_update_route_visual()
	_set_state(STATE_MOVING)
	_emit_destination_changed()
	return true


func stop_movement() -> void:
	_path_points.clear()
	_current_path_index = 0
	_has_destination = false
	_last_path_result.clear()
	_clear_route_visual()
	_set_state(STATE_IDLE)
	_emit_destination_changed()


func clear_destination() -> void:
	stop_movement()


func has_destination() -> bool:
	return _has_destination


func get_destination() -> Vector3:
	return _destination


func get_troop_summary() -> Dictionary:
	return {
		"troop_id": troop_id,
		"display_name": display_name,
		"soldier_count": get_soldier_count(),
		"state": _state,
		"selected": _selected,
		"has_destination": _has_destination,
		"destination": _destination,
		"path_distance_m": float(_last_path_result.get("distance_m", 0.0)),
		"estimated_seconds": float(_last_path_result.get("estimated_seconds", 0.0)),
		"failure_reason": StringName(_last_path_result.get("failure_reason", &"")),
	}


func get_soldier_count() -> int:
	if not _soldier_container:
		return 0
	return _soldier_container.get_child_count()


func get_flag_holder_count() -> int:
	if not _soldier_container:
		return 0
	var count := 0
	for soldier: Node in _soldier_container.get_children():
		if soldier.find_child("TeamFlag", true, false) or soldier.find_child("TroopFlag", true, false):
			count += 1
	return count


func get_selection_proxy() -> StaticBody3D:
	return _selection_proxy


func get_route_dash_count() -> int:
	return int(_route_visual.call("get_dash_count")) if _route_visual and _route_visual.has_method("get_dash_count") else 0


func has_destination_marker() -> bool:
	return bool(_route_visual.call("has_destination_flag")) if _route_visual and _route_visual.has_method("has_destination_flag") else false


func _ensure_scene_nodes() -> void:
	_soldier_container = get_node_or_null(SOLDIER_CONTAINER_NAME) as Node3D
	if not _soldier_container:
		_soldier_container = Node3D.new()
		_soldier_container.name = SOLDIER_CONTAINER_NAME
		add_child(_soldier_container)
		_soldier_container.owner = null

	_route_visual = get_node_or_null(ROUTE_VISUAL_NAME)
	if not _route_visual:
		_route_visual = TroopRouteVisualScript.new()
		_route_visual.name = ROUTE_VISUAL_NAME
		add_child(_route_visual)
		_route_visual.owner = null
	if _route_visual.has_method("configure_terrain"):
		_route_visual.call("configure_terrain", _terrain)
	_apply_route_visual_settings()


func _resolve_dependencies() -> void:
	_terrain = get_node_or_null(terrain_path) as Node3D if not terrain_path.is_empty() else null


func _load_movement_map() -> void:
	_movement_map = movement_map
	if _movement_map or movement_map_path.is_empty() or not ResourceLoader.exists(movement_map_path):
		return
	_movement_map = ResourceLoader.load(movement_map_path, "", ResourceLoader.CACHE_MODE_REUSE)


func _configure_visual_soldier(spatial: Node3D) -> void:
	spatial.process_mode = Node.PROCESS_MODE_DISABLED
	if spatial.has_method("clear_move_target"):
		spatial.call("clear_move_target")
	if _object_has_property(spatial, &"use_terrain_height"):
		spatial.set("use_terrain_height", false)
	if spatial is CollisionObject3D:
		var collision := spatial as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false


func _get_formation_position(index: int, columns: int, rows: int) -> Vector3:
	var column := index % columns
	var row := int(index / columns)
	var width := float(columns - 1) * formation_spacing
	var depth := float(rows - 1) * formation_spacing
	return Vector3(
		float(column) * formation_spacing - width * 0.5,
		0.0,
		float(row) * formation_spacing - depth * 0.5
	)


func _attach_flag_to_soldier(
	soldier: Node3D,
	flag_name: String,
	banner_color: Color,
	accent_color: Color
) -> void:
	var parent := soldier
	if soldier.has_method("get_right_hand_socket"):
		var socket: Variant = soldier.call("get_right_hand_socket")
		if socket is Node3D:
			parent = socket as Node3D

	var flag := _create_flag(flag_name, banner_color, accent_color)
	parent.add_child(flag)
	flag.owner = null
	flag.position = carried_flag_mount_offset
	flag.rotation = Vector3(0.0, 0.0, deg_to_rad(carried_flag_roll_degrees))


func _create_flag(flag_name: String, banner_color: Color, accent_color: Color) -> Node3D:
	var flag := Node3D.new()
	flag.name = flag_name

	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = carried_flag_pole_radius
	pole_mesh.bottom_radius = carried_flag_pole_radius
	pole_mesh.height = carried_flag_pole_height
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, carried_flag_pole_height * 0.5, 0.0)
	pole.material_override = _make_material(Color(0.42, 0.28, 0.12, 1.0))
	flag.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(carried_flag_banner_size.x, carried_flag_banner_size.y, 0.035)
	banner.mesh = banner_mesh
	banner.position = Vector3(carried_flag_banner_size.x * 0.5, carried_flag_pole_height * 0.82, 0.0)
	banner.material_override = _make_material(banner_color)
	flag.add_child(banner)

	var stripe := MeshInstance3D.new()
	stripe.name = "AccentStripe"
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(carried_flag_banner_size.x * 1.03, carried_flag_banner_size.y * 0.22, 0.04)
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(
		carried_flag_banner_size.x * 0.5,
		banner.position.y - carried_flag_banner_size.y * 0.32,
		0.024
	)
	stripe.material_override = _make_material(accent_color)
	flag.add_child(stripe)
	return flag


func _rebuild_ring() -> void:
	if _ring_instance and is_instance_valid(_ring_instance):
		remove_child(_ring_instance)
		_ring_instance.free()

	_ring_instance = MeshInstance3D.new()
	_ring_instance.name = RING_NODE_NAME
	_ring_instance.mesh = _build_ring_mesh(_get_effective_ring_radius())
	_last_ring_world_width = _get_current_ring_world_width()
	_ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ring_instance.position.y = ring_surface_offset
	add_child(_ring_instance)
	_ring_instance.owner = null
	_update_ring_material()


func _build_ring_mesh(radius: float) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.1)
	var half_width := maxf(_get_current_ring_world_width(), 0.01) * 0.5
	var inner_radius := maxf(safe_radius - half_width, 0.05)
	var outer_radius := safe_radius + half_width
	var segments := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * outer_radius)
		vertices.append(direction * inner_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		colors.append(Color.WHITE)
		colors.append(Color.WHITE)

	for index: int in range(segments):
		var next_index := (index + 1) % segments
		var outer_a := index * 2
		var inner_a := outer_a + 1
		var outer_b := next_index * 2
		var inner_b := outer_b + 1
		indices.append(outer_a)
		indices.append(inner_a)
		indices.append(outer_b)
		indices.append(outer_b)
		indices.append(inner_a)
		indices.append(inner_b)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _rebuild_selection_proxy() -> void:
	if _selection_proxy and is_instance_valid(_selection_proxy):
		remove_child(_selection_proxy)
		_selection_proxy.free()

	_selection_proxy = StaticBody3D.new()
	_selection_proxy.name = SELECTION_PROXY_NAME
	_selection_proxy.collision_layer = selection_collision_layer
	_selection_proxy.collision_mask = 0
	_selection_proxy.input_ray_pickable = true
	_selection_proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_TROOP_TYPE)
	_selection_proxy.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _get_effective_ring_radius() + maxf(formation_spacing * 0.75, ring_width)
	cylinder.height = 5.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.0, 0.0)
	_selection_proxy.add_child(shape)
	add_child(_selection_proxy)
	_selection_proxy.owner = null


func _update_ring_material() -> void:
	if not _ring_instance:
		return

	var color := selected_ring_color if _selected else ring_color
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 22
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.25 if _selected else 0.12
	_ring_instance.material_override = material


func _get_effective_ring_radius() -> float:
	if ring_radius > 0.0:
		return ring_radius
	var columns := mini(maxi(formation_columns, 1), soldier_count)
	var rows := ceili(float(soldier_count) / float(columns))
	var width := maxf(float(columns - 1) * formation_spacing, formation_spacing)
	var depth := maxf(float(rows - 1) * formation_spacing, formation_spacing)
	return Vector2(width, depth).length() * 0.5 + formation_spacing * 1.35


func _update_screen_constant_ring_width() -> void:
	if not _ring_instance or not is_instance_valid(_ring_instance):
		return
	var width := _get_current_ring_world_width()
	var change_threshold := maxf(_last_ring_world_width * 0.08, 0.015)
	if _last_ring_world_width < 0.0 or absf(width - _last_ring_world_width) > change_threshold:
		_rebuild_ring()


func _get_current_ring_world_width() -> float:
	return _world_units_for_screen_pixels(
		global_position,
		ring_screen_width_px,
		ring_width,
		ring_min_world_width,
		ring_max_world_width
	)


func _world_units_for_screen_pixels(
	world_position: Vector3,
	pixel_width: float,
	fallback_world_width: float,
	min_world_width: float,
	max_world_width: float
) -> float:
	var viewport := get_viewport()
	if not viewport:
		return fallback_world_width
	var viewport_height := viewport.get_visible_rect().size.y
	if viewport_height <= 0.0:
		return fallback_world_width

	var camera := viewport.get_camera_3d()
	if not camera:
		return fallback_world_width

	var units_per_pixel := 0.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		units_per_pixel = camera.size / viewport_height
	else:
		var forward := -camera.global_transform.basis.z.normalized()
		var depth := (world_position - camera.global_position).dot(forward)
		if depth <= camera.near:
			return fallback_world_width
		units_per_pixel = 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height

	var lower_limit := minf(min_world_width, max_world_width)
	var upper_limit := maxf(min_world_width, max_world_width)
	return clampf(maxf(pixel_width, 1.0) * units_per_pixel, lower_limit, upper_limit)


func _follow_path(delta: float) -> void:
	if _current_path_index >= _path_points.size():
		_finish_movement()
		return

	var target := _path_points[_current_path_index]
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= arrival_radius:
		_current_path_index += 1
		if _current_path_index >= _path_points.size():
			_finish_movement()
		return

	var direction := to_target / distance
	global_position += direction * minf(movement_speed_mps * delta, distance)
	_face_direction(direction, delta)
	_snap_to_surface()


func _finish_movement() -> void:
	if _has_destination:
		global_position.x = _destination.x
		global_position.z = _destination.z
		_snap_to_surface()
	_path_points.clear()
	_current_path_index = 0
	_has_destination = false
	_clear_route_visual()
	_set_state(STATE_IDLE)
	_emit_destination_changed()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0))


func _snap_path_points(raw_points: Array) -> Array[Vector3]:
	var snapped: Array[Vector3] = []
	for point_variant: Variant in raw_points:
		if point_variant is Vector3:
			snapped.append(_snap_world_point(point_variant as Vector3))
	return snapped


func _snap_world_point(point: Vector3) -> Vector3:
	var result := point
	var height: Variant = _get_surface_height(point)
	if height != null:
		result.y = float(height)
	return result


func _snap_to_surface() -> void:
	var height: Variant = _get_surface_height(global_position)
	if height == null:
		return
	var snapped := global_position
	snapped.y = float(height)
	global_position = snapped


func _get_surface_height(world_position: Vector3) -> Variant:
	if not is_instance_valid(_terrain):
		return null
	if _terrain.has_method("get_height"):
		var height: Variant = _terrain.call("get_height", world_position)
		if height is float or height is int:
			return float(height)

	var data: Variant = _terrain.get("data")
	if data and data is Object and (data as Object).has_method("get_height"):
		var data_height: Variant = (data as Object).call("get_height", world_position)
		if data_height is float or data_height is int:
			return float(data_height)
	return null


func _update_route_visual() -> void:
	if not _route_visual or not _has_destination:
		return
	_apply_route_visual_settings()
	var points := _get_remaining_route_points()
	if _route_visual.has_method("set_route"):
		_route_visual.call("set_route", points, _destination, troop_flag_color, team_flag_color)


func _clear_route_visual() -> void:
	if _route_visual and _route_visual.has_method("clear_route"):
		_route_visual.call("clear_route")


func _apply_route_visual_settings() -> void:
	if not _route_visual:
		return
	_set_route_visual_property(&"route_width", route_line_width)
	_set_route_visual_property(&"route_screen_width_px", route_line_screen_width_px)
	_set_route_visual_property(&"route_min_world_width", route_line_min_world_width)
	_set_route_visual_property(&"route_max_world_width", route_line_max_world_width)
	_set_route_visual_property(&"route_height", route_line_height)
	_set_route_visual_property(&"dash_length", route_dash_length)
	_set_route_visual_property(&"dash_gap", route_dash_gap)
	_set_route_visual_property(&"surface_offset", route_surface_offset)
	_set_route_visual_property(&"destination_flag_pole_height", destination_flag_pole_height)
	_set_route_visual_property(&"destination_flag_pole_radius", destination_flag_pole_radius)
	_set_route_visual_property(&"destination_flag_banner_size", destination_flag_banner_size)


func _set_route_visual_property(property_name: StringName, value: Variant) -> void:
	if _route_visual and _object_has_property(_route_visual, property_name):
		_route_visual.set(String(property_name), value)


func _get_remaining_route_points() -> Array[Vector3]:
	var points: Array[Vector3] = [global_position]
	for index: int in range(_current_path_index, _path_points.size()):
		points.append(_path_points[index])
	if points.back().distance_squared_to(_destination) > 0.01:
		points.append(_destination)
	return points


func _set_state(next_state: StringName) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)


func _emit_destination_changed() -> void:
	destination_changed.emit(get_troop_summary())


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _clear_children(node: Node) -> void:
	if not node:
		return
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false
