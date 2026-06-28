extends Node3D
class_name TroopRouteVisual

const DESTINATION_FLAG_META := &"troop_destination_flag"
const DEFAULT_ROUTE_RECORD_ID := &"troop"
const DASH_RECORD_ID_META := &"troop_route_record_id"
const DASH_PROGRESS_END_META := &"troop_route_progress_end"
const ROUTE_TRIM_MARGIN_M := 0.12

@export_group("Route")
@export_range(0.01, 8.0, 0.01, "or_greater") var route_width: float = 0.16
@export_range(1.0, 12.0, 0.1, "or_greater") var route_screen_width_px: float = 2.0
@export_range(0.01, 2.0, 0.01, "or_greater") var route_min_world_width: float = 0.04
@export_range(0.05, 12.0, 0.05, "or_greater") var route_max_world_width: float = 4.0
@export_range(0.01, 2.0, 0.01, "or_greater") var route_height: float = 0.035
@export_range(0.25, 32.0, 0.25, "or_greater") var dash_length: float = 1.25
@export_range(0.0, 32.0, 0.25, "or_greater") var dash_gap: float = 0.5
@export_range(0.0, 8.0, 0.01, "or_greater") var surface_offset: float = 0.35
@export var route_color: Color = Color(0.12, 0.42, 1.0, 0.88)

@export_group("Destination Flag")
@export_range(1.0, 12.0, 0.05, "or_greater") var destination_flag_pole_height: float = 4.2
@export_range(0.01, 0.5, 0.005, "or_greater") var destination_flag_pole_radius: float = 0.08
@export var destination_flag_banner_size: Vector2 = Vector2(1.65, 0.94)

var _terrain: Node3D
var _route_material: StandardMaterial3D
var _flag_pole_material: StandardMaterial3D
var _dash_nodes: Array[MeshInstance3D] = []
var _destination_flag: Node3D
var _route_key: StringName = &""
var _route_records: Dictionary = {}


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
	team_color: Color,
	line_color: Color = Color(0.12, 0.42, 1.0, 0.88),
	route_key: StringName = &""
) -> void:
	if points.size() < 2:
		clear_route()
		return

	var route_record := {
		"id": DEFAULT_ROUTE_RECORD_ID,
		"points": points,
		"current_position": points[0],
	}
	var rebuilt := _set_route_records([route_record], line_color, route_key)
	if rebuilt:
		_destination_flag = _create_destination_flag(destination, troop_color, team_color)
		add_child(_destination_flag)
	elif is_instance_valid(_destination_flag):
		_destination_flag.position = _with_surface_height(Vector3(destination.x, 0.0, destination.z))


func set_routes(
	route_records: Array[Dictionary],
	_troop_color: Color,
	_team_color: Color,
	line_color: Color = Color(0.12, 0.42, 1.0, 0.88),
	route_key: StringName = &""
) -> void:
	_set_route_records(route_records, line_color, route_key)


func clear_route() -> void:
	for dash: MeshInstance3D in _dash_nodes:
		if is_instance_valid(dash):
			dash.queue_free()
	_dash_nodes.clear()

	if is_instance_valid(_destination_flag):
		_destination_flag.queue_free()
	_destination_flag = null
	_route_key = &""
	_route_records.clear()


func get_dash_count() -> int:
	var count := 0
	for dash: MeshInstance3D in _dash_nodes:
		if is_instance_valid(dash) and not dash.is_queued_for_deletion():
			count += 1
	return count


func has_destination_flag() -> bool:
	return is_instance_valid(_destination_flag)


func _set_route_records(route_records: Array, line_color: Color, route_key: StringName) -> bool:
	_ensure_materials()
	_set_route_color(line_color)
	var next_key := route_key
	if next_key == &"":
		next_key = _make_route_key(route_records)
	var rebuilt := next_key != _route_key
	if rebuilt:
		clear_route()
		_route_key = next_key

	var seen_records := {}
	for record_variant: Variant in route_records:
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		var record_id: Variant = record.get("id", DEFAULT_ROUTE_RECORD_ID)
		var points := _extract_route_points(record.get("points", []))
		if points.size() < 2:
			continue
		seen_records[record_id] = true
		if not _route_records.has(record_id):
			_build_route_record(record_id, points)
		_trim_route_record(record_id, record.get("current_position", points[0]))

	for existing_id: Variant in _route_records.keys():
		if not seen_records.has(existing_id):
			_trim_record_dashes(existing_id, INF)
			_route_records.erase(existing_id)
	_compact_dash_nodes()
	_update_dash_screen_widths(true)
	return rebuilt


func _build_route_record(record_id: Variant, points: Array[Vector3]) -> void:
	var distances: Array[float] = [0.0]
	var total_distance := 0.0
	for index: int in range(1, points.size()):
		var segment_length := _add_dashed_segment(points[index - 1], points[index], record_id, total_distance)
		total_distance += segment_length
		distances.append(total_distance)
	_route_records[record_id] = {
		"points": points,
		"distances": distances,
		"progress": 0.0,
	}


func _add_dashed_segment(start: Vector3, end: Vector3, record_id: Variant, progress_offset: float) -> float:
	var horizontal_start := Vector3(start.x, 0.0, start.z)
	var horizontal_end := Vector3(end.x, 0.0, end.z)
	var segment := horizontal_end - horizontal_start
	var segment_length := segment.length()
	if segment_length <= 0.01:
		return 0.0

	var direction := segment / segment_length
	var cursor := 0.0
	var safe_dash_length := maxf(dash_length, 0.05)
	var step := safe_dash_length + maxf(dash_gap, 0.0)
	while cursor < segment_length:
		var current_dash_length := minf(safe_dash_length, segment_length - cursor)
		var center := horizontal_start + direction * (cursor + current_dash_length * 0.5)
		center = _with_surface_height(center)
		_add_dash(center, direction, current_dash_length, record_id, progress_offset + cursor + current_dash_length)
		cursor += step
	return segment_length


func _add_dash(
	center: Vector3,
	direction: Vector3,
	current_dash_length: float,
	record_id: Variant,
	progress_end: float
) -> void:
	var dash := MeshInstance3D.new()
	dash.name = "RouteDash_%03d" % _dash_nodes.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_get_route_world_width(center), route_height, maxf(current_dash_length, 0.05))
	dash.mesh = mesh
	dash.material_override = _route_material
	dash.set_meta(DASH_RECORD_ID_META, record_id)
	dash.set_meta(DASH_PROGRESS_END_META, progress_end)
	dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dash.position = center
	dash.rotation.y = atan2(direction.x, direction.z)
	add_child(dash)
	_dash_nodes.append(dash)


func _trim_route_record(record_id: Variant, current_position_variant: Variant) -> void:
	if not _route_records.has(record_id):
		return
	if not (current_position_variant is Vector3):
		return
	var record: Dictionary = _route_records[record_id] as Dictionary
	var current_progress := _get_progress_for_position(record, current_position_variant as Vector3)
	var next_progress := maxf(float(record.get("progress", 0.0)), current_progress)
	record["progress"] = next_progress
	_route_records[record_id] = record
	_trim_record_dashes(record_id, next_progress)


func _trim_record_dashes(record_id: Variant, progress: float) -> void:
	var remove_before := progress - ROUTE_TRIM_MARGIN_M
	for dash: MeshInstance3D in _dash_nodes:
		if not is_instance_valid(dash):
			continue
		if dash.get_meta(DASH_RECORD_ID_META, null) != record_id:
			continue
		var dash_progress := float(dash.get_meta(DASH_PROGRESS_END_META, INF))
		if dash_progress <= remove_before:
			dash.queue_free()


func _compact_dash_nodes() -> void:
	var active: Array[MeshInstance3D] = []
	for dash: MeshInstance3D in _dash_nodes:
		if is_instance_valid(dash) and not dash.is_queued_for_deletion():
			active.append(dash)
	_dash_nodes = active


func _get_progress_for_position(record: Dictionary, world_position: Vector3) -> float:
	var points: Array = record.get("points", [])
	var distances: Array = record.get("distances", [])
	if points.size() < 2 or distances.size() < points.size():
		return float(record.get("progress", 0.0))
	var horizontal_position := Vector3(world_position.x, 0.0, world_position.z)
	var best_distance_squared := INF
	var best_progress := float(record.get("progress", 0.0))
	for index: int in range(1, points.size()):
		if not (points[index - 1] is Vector3 and points[index] is Vector3):
			continue
		var start := points[index - 1] as Vector3
		var end := points[index] as Vector3
		var horizontal_start := Vector3(start.x, 0.0, start.z)
		var horizontal_end := Vector3(end.x, 0.0, end.z)
		var segment := horizontal_end - horizontal_start
		var segment_length_squared := segment.length_squared()
		if segment_length_squared <= 0.0001:
			continue
		var progress_ratio := clampf((horizontal_position - horizontal_start).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest := horizontal_start + segment * progress_ratio
		var distance_squared := closest.distance_squared_to(horizontal_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_progress = float(distances[index - 1]) + sqrt(segment_length_squared) * progress_ratio
	return best_progress


func _extract_route_points(points_variant: Variant) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not (points_variant is Array):
		return points
	for point_variant: Variant in points_variant:
		if point_variant is Vector3:
			points.append(point_variant as Vector3)
	return points


func _make_route_key(route_records: Array) -> StringName:
	var parts: Array[String] = []
	for record_variant: Variant in route_records:
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		var points := _extract_route_points(record.get("points", []))
		if points.size() < 2:
			continue
		parts.append("%s:%d:%s" % [
			str(record.get("id", DEFAULT_ROUTE_RECORD_ID)),
			points.size(),
			_point_signature(points.back()),
		])
	if parts.is_empty():
		return &"empty"
	return StringName("|".join(parts))


func _point_signature(point: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [point.x, point.y, point.z]


func _set_route_color(color: Color) -> void:
	route_color = color
	_apply_route_material_color()


func _apply_route_material_color() -> void:
	if not _route_material:
		return
	_route_material.albedo_color = route_color
	_route_material.emission = Color(route_color.r, route_color.g, route_color.b, 1.0)


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
		_route_material.emission_enabled = true
		_route_material.emission_energy_multiplier = 0.2
	_apply_route_material_color()

	if not _flag_pole_material:
		_flag_pole_material = _make_flag_material(Color(0.45, 0.31, 0.16, 1.0))


func _make_flag_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
