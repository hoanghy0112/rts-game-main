@tool
extends Resource
class_name FieldPlotData

@export var id: StringName = &""
@export var center: Vector3 = Vector3.ZERO
@export var row_direction: Vector3 = Vector3.RIGHT
@export var lateral_direction: Vector3 = Vector3.FORWARD
@export var length: float = 1.0
@export var width: float = 1.0
@export var area: float = 1.0
@export var footprint: PackedVector2Array = PackedVector2Array()
@export var stage: StringName = &"empty"

@export_range(0.0, 1.0, 0.01) var water_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var flood_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var irrigation_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var labor_level: float = 0.0
@export_range(0.0, 1.0, 0.01) var safety_level: float = 1.0
@export_range(0.0, 1.0, 0.01) var mud_level: float = 0.0

var ground_state_id: StringName = &"dry"
var ground_state_data: FieldGroundStateData


func configure(
	new_id: StringName,
	new_center: Vector3,
	new_row_direction: Vector3,
	new_lateral_direction: Vector3,
	new_length: float,
	new_width: float,
	new_footprint: PackedVector2Array = PackedVector2Array()
) -> void:
	id = new_id
	center = new_center
	row_direction = new_row_direction.normalized()
	lateral_direction = new_lateral_direction.normalized()
	length = maxf(new_length, 0.0)
	width = maxf(new_width, 0.0)
	footprint = new_footprint.duplicate()
	if footprint.size() < 3:
		footprint = _make_rectangle_footprint(length, width)
	_update_bounds_from_footprint()


func get_local_outline_2d() -> PackedVector2Array:
	return footprint.duplicate()


func get_region_outline_2d() -> PackedVector2Array:
	var outline := PackedVector2Array()
	var row_2d := _row_direction_2d()
	var lateral_2d := _lateral_direction_2d()
	if row_2d.length_squared() <= 0.0001 or lateral_2d.length_squared() <= 0.0001:
		return outline

	var center_2d := Vector2(center.x, center.z)
	for local_point: Vector2 in footprint:
		outline.append(center_2d + row_2d * local_point.x + lateral_2d * local_point.y)
	return outline


func get_world_outline() -> PackedVector3Array:
	var outline := PackedVector3Array()
	for point: Vector2 in get_region_outline_2d():
		outline.append(Vector3(point.x, center.y, point.y))
	return outline


func get_footprint_cache_key() -> String:
	var mixed := int(2166136261)
	for point: Vector2 in footprint:
		mixed = int((mixed ^ roundi(point.x * 1000.0)) * 16777619)
		mixed = int((mixed ^ roundi(point.y * 1000.0)) * 16777619)
	return "%d:%d" % [footprint.size(), mixed]


func to_plot_local_2d(region_point: Vector2) -> Vector2:
	var row_2d := _row_direction_2d()
	var lateral_2d := _lateral_direction_2d()
	if row_2d.length_squared() <= 0.0001 or lateral_2d.length_squared() <= 0.0001:
		return Vector2(INF, INF)

	var relative := region_point - Vector2(center.x, center.z)
	return Vector2(relative.dot(row_2d), relative.dot(lateral_2d))


func contains_region_point(region_point: Vector2, inset: float = 0.0) -> bool:
	return contains_local_point(to_plot_local_2d(region_point), inset)


func contains_local_point(local_point: Vector2, inset: float = 0.0) -> bool:
	if footprint.size() < 3:
		return false
	if not _is_point_in_polygon(local_point, footprint):
		return false
	var safe_inset := maxf(inset, 0.0)
	if safe_inset <= 0.0:
		return true
	return get_local_edge_distance(local_point) >= safe_inset


func get_region_edge_distance(region_point: Vector2) -> float:
	return get_local_edge_distance(to_plot_local_2d(region_point))


func get_local_edge_distance(local_point: Vector2) -> float:
	if footprint.size() < 3:
		return -INF

	var min_distance := INF
	for index: int in range(footprint.size()):
		var from_point := footprint[index]
		var to_point := footprint[(index + 1) % footprint.size()]
		min_distance = minf(min_distance, _distance_to_segment(local_point, from_point, to_point))

	if _is_point_in_polygon(local_point, footprint):
		return min_distance
	return -min_distance


func _update_bounds_from_footprint() -> void:
	if footprint.size() < 3:
		length = 0.0
		width = 0.0
		area = 0.0
		return

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in footprint:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	length = maxf(max_point.x - min_point.x, 0.0)
	width = maxf(max_point.y - min_point.y, 0.0)
	area = absf(_get_polygon_signed_area(footprint))


func _row_direction_2d() -> Vector2:
	return Vector2(row_direction.x, row_direction.z).normalized()


func _lateral_direction_2d() -> Vector2:
	return Vector2(lateral_direction.x, lateral_direction.z).normalized()


func _make_rectangle_footprint(rect_length: float, rect_width: float) -> PackedVector2Array:
	var half_length := maxf(rect_length, 0.0) * 0.5
	var half_width := maxf(rect_width, 0.0) * 0.5
	return PackedVector2Array([
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
	])


func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous_index := polygon.size() - 1
	for current_index: int in range(polygon.size()):
		var current := polygon[current_index]
		var previous := polygon[previous_index]
		if _is_point_on_segment(point, previous, current):
			return true
		if (current.y > point.y) != (previous.y > point.y):
			var denominator := previous.y - current.y
			if absf(denominator) > 0.000001:
				var crossing_x := (previous.x - current.x) * (point.y - current.y) / denominator + current.x
				if point.x <= crossing_x:
					inside = not inside
		previous_index = current_index
	return inside


func _is_point_on_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> bool:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_squared_to(from_point) <= 0.000001

	var weight := (point - from_point).dot(segment) / length_squared
	if weight < -0.0001 or weight > 1.0001:
		return false
	var closest := from_point + segment * clampf(weight, 0.0, 1.0)
	return point.distance_squared_to(closest) <= 0.000001


func _distance_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from_point)

	var weight := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from_point + segment * weight)


func _get_polygon_signed_area(polygon: PackedVector2Array) -> float:
	var polygon_area := 0.0
	for index: int in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		polygon_area += current.x * next.y - next.x * current.y
	return polygon_area * 0.5
