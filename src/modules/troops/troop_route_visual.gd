extends Node3D
class_name TroopRouteVisual

const DESTINATION_FLAG_META := &"troop_destination_flag"

@export_group("Route")
@export_range(0.01, 8.0, 0.01, "or_greater") var route_width: float = 0.16
@export_range(1.0, 12.0, 0.1, "or_greater") var route_screen_width_px: float = 2.0
@export_range(0.01, 2.0, 0.01, "or_greater") var route_min_world_width: float = 0.04
@export_range(0.05, 12.0, 0.05, "or_greater") var route_max_world_width: float = 4.0
@export_range(0.01, 2.0, 0.01, "or_greater") var route_height: float = 0.035
@export_range(0.25, 32.0, 0.25, "or_greater") var dash_length: float = 5.0
@export_range(0.0, 32.0, 0.25, "or_greater") var dash_gap: float = 3.0
@export_range(0.0, 8.0, 0.01, "or_greater") var surface_offset: float = 0.35
@export var route_color: Color = Color(0.94, 0.86, 0.42, 0.82)

@export_group("Destination Flag")
@export_range(1.0, 12.0, 0.05, "or_greater") var destination_flag_pole_height: float = 4.2
@export_range(0.01, 0.5, 0.005, "or_greater") var destination_flag_pole_radius: float = 0.08
@export var destination_flag_banner_size: Vector2 = Vector2(1.65, 0.94)

var _terrain: Node3D
var _route_material: StandardMaterial3D
var _flag_pole_material: StandardMaterial3D
var _dash_nodes: Array[MeshInstance3D] = []
var _destination_flag: Node3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(_delta: float) -> void:
	_update_dash_screen_widths(false)


func configure_terrain(terrain: Node3D) -> void:
	_terrain = terrain


func set_route(
	points: Array[Vector3],
	destination: Vector3,
	troop_color: Color,
	team_color: Color
) -> void:
	clear_route()
	if points.size() < 2:
		return

	_ensure_materials()
	for index: int in range(1, points.size()):
		_add_dashed_segment(points[index - 1], points[index])
	_update_dash_screen_widths(true)
	_destination_flag = _create_destination_flag(destination, troop_color, team_color)
	add_child(_destination_flag)


func clear_route() -> void:
	for dash: MeshInstance3D in _dash_nodes:
		if is_instance_valid(dash):
			dash.queue_free()
	_dash_nodes.clear()

	if is_instance_valid(_destination_flag):
		_destination_flag.queue_free()
	_destination_flag = null


func get_dash_count() -> int:
	var count := 0
	for dash: MeshInstance3D in _dash_nodes:
		if is_instance_valid(dash):
			count += 1
	return count


func has_destination_flag() -> bool:
	return is_instance_valid(_destination_flag)


func _add_dashed_segment(start: Vector3, end: Vector3) -> void:
	var horizontal_start := Vector3(start.x, 0.0, start.z)
	var horizontal_end := Vector3(end.x, 0.0, end.z)
	var segment := horizontal_end - horizontal_start
	var segment_length := segment.length()
	if segment_length <= 0.01:
		return

	var direction := segment / segment_length
	var cursor := 0.0
	var safe_dash_length := maxf(dash_length, 0.05)
	var step := safe_dash_length + maxf(dash_gap, 0.0)
	while cursor < segment_length:
		var current_dash_length := minf(safe_dash_length, segment_length - cursor)
		var center := horizontal_start + direction * (cursor + current_dash_length * 0.5)
		center = _with_surface_height(center)
		_add_dash(center, direction, current_dash_length)
		cursor += step


func _add_dash(center: Vector3, direction: Vector3, current_dash_length: float) -> void:
	var dash := MeshInstance3D.new()
	dash.name = "RouteDash_%03d" % _dash_nodes.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_get_route_world_width(center), route_height, maxf(current_dash_length, 0.05))
	dash.mesh = mesh
	dash.material_override = _route_material
	dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dash.position = center
	dash.rotation.y = atan2(direction.x, direction.z)
	add_child(dash)
	_dash_nodes.append(dash)


func _create_destination_flag(destination: Vector3, troop_color: Color, team_color: Color) -> Node3D:
	var flag := Node3D.new()
	flag.name = "TroopDestinationFlag"
	flag.set_meta(DESTINATION_FLAG_META, true)
	flag.position = _with_surface_height(Vector3(destination.x, 0.0, destination.z))

	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = destination_flag_pole_radius
	pole_mesh.bottom_radius = destination_flag_pole_radius
	pole_mesh.height = destination_flag_pole_height
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, destination_flag_pole_height * 0.5, 0.0)
	pole.material_override = _flag_pole_material
	flag.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(destination_flag_banner_size.x, destination_flag_banner_size.y, 0.055)
	banner.mesh = banner_mesh
	banner.position = Vector3(destination_flag_banner_size.x * 0.5, destination_flag_pole_height * 0.82, 0.0)
	banner.material_override = _make_flag_material(troop_color)
	flag.add_child(banner)

	var stripe := MeshInstance3D.new()
	stripe.name = "TeamStripe"
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(destination_flag_banner_size.x * 1.03, destination_flag_banner_size.y * 0.24, 0.065)
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(
		destination_flag_banner_size.x * 0.5,
		banner.position.y - destination_flag_banner_size.y * 0.32,
		0.035
	)
	stripe.material_override = _make_flag_material(team_color)
	flag.add_child(stripe)
	return flag


func _update_dash_screen_widths(force: bool) -> void:
	for dash: MeshInstance3D in _dash_nodes:
		if not is_instance_valid(dash):
			continue
		var mesh := dash.mesh as BoxMesh
		if not mesh:
			continue
		var next_width := _get_route_world_width(dash.global_position)
		var change_threshold := maxf(mesh.size.x * 0.08, 0.015)
		if force or absf(mesh.size.x - next_width) > change_threshold:
			mesh.size = Vector3(next_width, route_height, mesh.size.z)


func _get_route_world_width(world_position: Vector3) -> float:
	return _world_units_for_screen_pixels(
		world_position,
		route_screen_width_px,
		route_width,
		route_min_world_width,
		route_max_world_width
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


func _with_surface_height(point: Vector3) -> Vector3:
	var result := point
	var height: Variant = _get_surface_height(point)
	if height != null:
		result.y = float(height)
	result.y += surface_offset
	return result


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


func _ensure_materials() -> void:
	if not _route_material:
		_route_material = StandardMaterial3D.new()
		_route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_route_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_route_material.no_depth_test = true
		_route_material.render_priority = 24
		_route_material.albedo_color = route_color
		_route_material.emission_enabled = true
		_route_material.emission = Color(route_color.r, route_color.g, route_color.b, 1.0)
		_route_material.emission_energy_multiplier = 0.2

	if not _flag_pole_material:
		_flag_pole_material = _make_flag_material(Color(0.45, 0.31, 0.16, 1.0))


func _make_flag_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
