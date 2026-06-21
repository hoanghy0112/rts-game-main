extends RefCounted
class_name FieldPlotGenerator

const NEIGHBOR_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var cell_size: float = 4.0
var origin: Vector3 = Vector3.ZERO
var generation_seed: int = 0
var min_plot_width: float = 19.2
var max_plot_width: float = 44.8
var bund_gap: float = 0.35
var field_road_gap_width: float = 1.2
var min_plot_length: float = 32.0
var max_plot_length: float = 96.0
var sample_step: float = 1.0
var road_width: float = 3.2
var road_clearance: float = 1.0
var horizontal_split_bias: float = 1.0
var field_shape_variation: float = 0.65
var generated_road_polylines: Array = []
var generated_bund_polylines: Array = []
var target_plot_area_min_m2: float = 300.0
var target_plot_area_max_m2: float = 600.0
var preferred_plot_area_m2: float = 450.0
var _road_segments: Array[Dictionary] = []
var _road_segment_buckets: Dictionary = {}
var _road_bucket_size := 4.0


func generate(field_cells: Array[Vector2i], road_polylines: Array) -> Array[FieldPlotData]:
	var plots: Array[FieldPlotData] = []
	generated_road_polylines.clear()
	generated_bund_polylines.clear()
	_build_road_segment_buckets(road_polylines)
	if field_cells.is_empty():
		return plots

	var normalized_cells := _normalize_cells(field_cells)
	var field_lookup := _to_cell_lookup(normalized_cells)
	var components := _get_cell_components(normalized_cells, field_lookup)
	var plot_index := 0

	for component_index: int in range(components.size()):
		var component: Array = components[component_index]
		if component.is_empty():
			continue

		var rng := RandomNumberGenerator.new()
		rng.seed = _component_seed(component_index, component)
		var component_center := _get_component_center(component)
		var road_direction := _get_nearest_road_tangent(component_center, road_polylines)
		if road_direction.length_squared() <= 0.0001:
			road_direction = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		road_direction = _normalize_or_right(road_direction)
		road_direction = _canonical_axis_direction(road_direction)
		var depth_direction := Vector2(-road_direction.y, road_direction.x).normalized()

		var component_outline := _build_component_outline(component)
		if component_outline.size() < 3:
			component_outline = _build_component_bounds_outline(component, component_center, road_direction, depth_direction)
		if component_outline.size() < 3:
			continue

		var component_plots := _build_area_targeted_plots(
			component_index,
			component_outline,
			component_center,
			road_direction,
			depth_direction,
			field_lookup,
			road_polylines,
			rng,
			plot_index
		)

		for plot: FieldPlotData in component_plots:
			plots.append(plot)
			_append_plot_bund_polylines(plot)
			plot_index += 1

	return plots


func _build_area_targeted_plots(
	component_index: int,
	component_outline: PackedVector2Array,
	component_center: Vector2,
	road_direction: Vector2,
	depth_direction: Vector2,
	field_lookup: Dictionary,
	road_polylines: Array,
	rng: RandomNumberGenerator,
	plot_index_start: int
) -> Array[FieldPlotData]:
	var plots: Array[FieldPlotData] = []
	var bounds := _get_polygon_oriented_bounds(component_outline, component_center, road_direction, depth_direction)
	if bounds.is_empty():
		return plots

	var min_u := float(bounds.get("min_u", 0.0))
	var max_u := float(bounds.get("max_u", 0.0))
	var min_v := float(bounds.get("min_v", 0.0))
	var max_v := float(bounds.get("max_v", 0.0))
	if max_u - min_u <= 0.1 or max_v - min_v <= 0.1:
		return plots

	var safe_gap := maxf(bund_gap, 0.0)
	var safe_min_area := maxf(target_plot_area_min_m2, 25.0)
	var safe_max_area := maxf(target_plot_area_max_m2, safe_min_area)
	var safe_preferred_area := clampf(preferred_plot_area_m2, safe_min_area, safe_max_area)
	var min_frontage := clampf(sqrt(safe_min_area / 2.25), 8.0, 30.0)
	var max_frontage := clampf(sqrt(safe_max_area * 1.2), min_frontage, 36.0)
	var preferred_frontage := clampf(sqrt(safe_preferred_area / 1.5), min_frontage, max_frontage)
	var frontage_intervals := _build_random_intervals(min_u, max_u, min_frontage, max_frontage, preferred_frontage, safe_gap, rng)

	for frontage_index: int in range(frontage_intervals.size()):
		var frontage_interval: Vector2 = frontage_intervals[frontage_index]
		var frontage_width := maxf(frontage_interval.y - frontage_interval.x, 0.1)
		var min_depth := clampf(safe_min_area / frontage_width, 10.0, 72.0)
		var max_depth := clampf(safe_max_area / frontage_width, min_depth, 96.0)
		var preferred_depth := clampf(safe_preferred_area / frontage_width, min_depth, max_depth)
		var depth_intervals := _build_random_intervals(min_v, max_v, min_depth, max_depth, preferred_depth, safe_gap, rng)

		for depth_index: int in range(depth_intervals.size()):
			var depth_interval: Vector2 = depth_intervals[depth_index]
			var polygon := _clip_polygon_to_oriented_rect(
				component_outline,
				component_center,
				road_direction,
				depth_direction,
				frontage_interval.x,
				frontage_interval.y,
				depth_interval.x,
				depth_interval.y
			)
			_append_area_constrained_plot_polygons(
				plots,
				component_index,
				frontage_index,
				depth_index,
				polygon,
				component_center,
				road_direction,
				depth_direction,
				field_lookup,
				road_polylines,
				rng,
				plot_index_start
			)

	return plots


func _append_area_constrained_plot_polygons(
	plots: Array[FieldPlotData],
	component_index: int,
	frontage_index: int,
	depth_index: int,
	polygon: PackedVector2Array,
	component_center: Vector2,
	road_direction: Vector2,
	depth_direction: Vector2,
	field_lookup: Dictionary,
	road_polylines: Array,
	rng: RandomNumberGenerator,
	plot_index_start: int,
	split_depth: int = 0
) -> void:
	if polygon.size() < 3:
		return

	polygon = _clean_polygon(polygon)
	var area := absf(_get_polygon_signed_area(polygon))
	var safe_min_area := maxf(target_plot_area_min_m2, 25.0)
	var safe_max_area := maxf(target_plot_area_max_m2, safe_min_area)
	if area < safe_min_area * 0.35:
		return

	var bounds := _get_polygon_oriented_bounds(polygon, component_center, road_direction, depth_direction)
	var u_extent := float(bounds.get("max_u", 0.0)) - float(bounds.get("min_u", 0.0))
	var v_extent := float(bounds.get("max_v", 0.0)) - float(bounds.get("min_v", 0.0))
	if area > safe_max_area * 1.25 and split_depth < 4 and maxf(u_extent, v_extent) > 4.0:
		var split_axis := road_direction if u_extent >= v_extent else depth_direction
		var split_min := float(bounds.get("min_u", 0.0)) if u_extent >= v_extent else float(bounds.get("min_v", 0.0))
		var split_max := float(bounds.get("max_u", 0.0)) if u_extent >= v_extent else float(bounds.get("max_v", 0.0))
		var split_coord := lerpf(split_min, split_max, rng.randf_range(0.44, 0.56))
		var first := _clip_polygon_with_axis_max(polygon, component_center, split_axis, split_coord)
		var second := _clip_polygon_with_axis_min(polygon, component_center, split_axis, split_coord)
		if first.size() >= 3 and second.size() >= 3:
			_append_area_constrained_plot_polygons(
				plots, component_index, frontage_index, depth_index, first, component_center,
				road_direction, depth_direction, field_lookup, road_polylines, rng, plot_index_start, split_depth + 1
			)
			_append_area_constrained_plot_polygons(
				plots, component_index, frontage_index, depth_index, second, component_center,
				road_direction, depth_direction, field_lookup, road_polylines, rng, plot_index_start, split_depth + 1
			)
			return

	if not _is_candidate_polygon_valid(polygon, field_lookup, road_polylines):
		return

	var center := _find_polygon_interior_point(polygon)
	var footprint := _build_local_footprint(polygon, center, road_direction, depth_direction)
	if footprint.size() < 3:
		return

	var plot := FieldPlotData.new()
	plot.configure(
		_get_plot_id(component_index, frontage_index, depth_index, split_depth, plot_index_start + plots.size()),
		Vector3(center.x, 0.0, center.y),
		Vector3(road_direction.x, 0.0, road_direction.y),
		Vector3(depth_direction.x, 0.0, depth_direction.y),
		0.0,
		0.0,
		footprint
	)
	plots.append(plot)


func _build_random_intervals(
	min_value: float,
	max_value: float,
	min_extent: float,
	max_extent: float,
	preferred_extent: float,
	gap: float,
	rng: RandomNumberGenerator
) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	var total := max_value - min_value
	var safe_gap := maxf(gap, 0.0)
	var safe_min := maxf(min_extent, 0.25)
	var safe_max := maxf(max_extent, safe_min)
	if total <= safe_min + safe_gap:
		intervals.append(Vector2(min_value, max_value))
		return intervals

	var min_count := maxi(1, ceili((total + safe_gap) / (safe_max + safe_gap)))
	var max_count := maxi(min_count, floori((total + safe_gap) / (safe_min + safe_gap)))
	var preferred_count := maxi(1, roundi((total + safe_gap) / (maxf(preferred_extent, safe_min) + safe_gap)))
	var count_min := maxi(min_count, preferred_count - 1)
	var count_max := mini(max_count, preferred_count + 1)
	var segment_count := clampi(preferred_count, min_count, max_count)
	if count_max >= count_min:
		segment_count = rng.randi_range(count_min, count_max)

	var usable_total := total - safe_gap * float(segment_count - 1)
	if segment_count <= 1 or usable_total <= safe_min:
		intervals.append(Vector2(min_value, max_value))
		return intervals

	var lengths := _distribute_plot_lengths(usable_total, segment_count, safe_min, safe_max, rng)
	var start := min_value
	for length: float in lengths:
		var end := minf(start + length, max_value)
		if end - start >= 0.25:
			intervals.append(Vector2(start, end))
		start = end + safe_gap

	return intervals


func _build_component_outline(component: Array) -> PackedVector2Array:
	var component_lookup: Dictionary = {}
	for cell: Vector2i in component:
		component_lookup[cell] = true

	var edges: Array[Dictionary] = []
	for cell: Vector2i in component:
		var corners := _get_cell_corners(cell)
		if not component_lookup.has(cell + Vector2i(0, -1)):
			edges.append({"from": corners[0], "to": corners[1]})
		if not component_lookup.has(cell + Vector2i(1, 0)):
			edges.append({"from": corners[1], "to": corners[2]})
		if not component_lookup.has(cell + Vector2i(0, 1)):
			edges.append({"from": corners[2], "to": corners[3]})
		if not component_lookup.has(cell + Vector2i(-1, 0)):
			edges.append({"from": corners[3], "to": corners[0]})

	var best_loop := PackedVector2Array()
	var best_area := 0.0
	while not edges.is_empty():
		var first_edge := edges.pop_front() as Dictionary
		var start: Vector2 = first_edge["from"]
		var current: Vector2 = first_edge["to"]
		var loop := PackedVector2Array()
		loop.append(start)
		var safety := component.size() * 8 + 16
		while _point_key(current) != _point_key(start) and safety > 0:
			safety -= 1
			loop.append(current)
			var next_index := _find_edge_starting_at(edges, current)
			if next_index < 0:
				break
			var next_edge := edges.pop_at(next_index) as Dictionary
			current = next_edge["to"]

		var cleaned := _clean_polygon(loop)
		var area := absf(_get_polygon_signed_area(cleaned))
		if cleaned.size() >= 3 and area > best_area:
			best_loop = cleaned
			best_area = area

	return best_loop


func _build_component_bounds_outline(component: Array, center: Vector2, road_direction: Vector2, depth_direction: Vector2) -> PackedVector2Array:
	var bounds := _get_component_oriented_bounds(component, center, road_direction, depth_direction)
	var min_u: float = bounds["min_u"]
	var max_u: float = bounds["max_u"]
	var min_v: float = bounds["min_v"]
	var max_v: float = bounds["max_v"]
	return PackedVector2Array([
		center + road_direction * min_u + depth_direction * min_v,
		center + road_direction * max_u + depth_direction * min_v,
		center + road_direction * max_u + depth_direction * max_v,
		center + road_direction * min_u + depth_direction * max_v,
	])


func _find_edge_starting_at(edges: Array[Dictionary], point: Vector2) -> int:
	var key := _point_key(point)
	for index: int in range(edges.size()):
		var edge := edges[index]
		if _point_key(edge["from"]) == key:
			return index
	return -1


func _point_key(point: Vector2) -> String:
	return "%d,%d" % [roundi(point.x * 1000.0), roundi(point.y * 1000.0)]


func _clip_polygon_to_oriented_rect(
	polygon: PackedVector2Array,
	center: Vector2,
	u_axis: Vector2,
	v_axis: Vector2,
	min_u: float,
	max_u: float,
	min_v: float,
	max_v: float
) -> PackedVector2Array:
	var clipped := _clip_polygon_with_axis_min(polygon, center, u_axis, min_u)
	clipped = _clip_polygon_with_axis_max(clipped, center, u_axis, max_u)
	clipped = _clip_polygon_with_axis_min(clipped, center, v_axis, min_v)
	clipped = _clip_polygon_with_axis_max(clipped, center, v_axis, max_v)
	return _clean_polygon(clipped)


func _clip_polygon_with_axis_min(
	polygon: PackedVector2Array,
	center: Vector2,
	axis: Vector2,
	min_coordinate: float
) -> PackedVector2Array:
	return _clip_polygon_with_axis_threshold(polygon, center, axis, min_coordinate, true)


func _clip_polygon_with_axis_max(
	polygon: PackedVector2Array,
	center: Vector2,
	axis: Vector2,
	max_coordinate: float
) -> PackedVector2Array:
	return _clip_polygon_with_axis_threshold(polygon, center, axis, max_coordinate, false)


func _clip_polygon_with_axis_threshold(
	polygon: PackedVector2Array,
	center: Vector2,
	axis: Vector2,
	threshold: float,
	keep_greater: bool
) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	if polygon.size() < 3:
		return clipped

	var previous := polygon[polygon.size() - 1]
	var previous_coordinate := (previous - center).dot(axis)
	var previous_inside := previous_coordinate >= threshold if keep_greater else previous_coordinate <= threshold
	for current: Vector2 in polygon:
		var current_coordinate := (current - center).dot(axis)
		var current_inside := current_coordinate >= threshold if keep_greater else current_coordinate <= threshold
		if current_inside != previous_inside:
			var denominator := current_coordinate - previous_coordinate
			if absf(denominator) > 0.000001:
				var t := clampf((threshold - previous_coordinate) / denominator, 0.0, 1.0)
				clipped.append(previous + (current - previous) * t)
		if current_inside:
			clipped.append(current)
		previous = current
		previous_coordinate = current_coordinate
		previous_inside = current_inside

	return _clean_polygon(clipped)


func _clean_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for point: Vector2 in polygon:
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_squared_to(point) > 0.000001:
			cleaned.append(point)
	if cleaned.size() > 1 and cleaned[0].distance_squared_to(cleaned[cleaned.size() - 1]) <= 0.000001:
		cleaned.remove_at(cleaned.size() - 1)

	var simplified := PackedVector2Array()
	for index: int in range(cleaned.size()):
		var previous := cleaned[(index - 1 + cleaned.size()) % cleaned.size()]
		var current := cleaned[index]
		var next := cleaned[(index + 1) % cleaned.size()]
		var before := current - previous
		var after := next - current
		if before.length_squared() <= 0.000001 or after.length_squared() <= 0.000001:
			continue
		if absf(_cross_2d(before.normalized(), after.normalized())) <= 0.0001 and before.dot(after) > 0.0:
			continue
		simplified.append(current)
	return simplified


func _get_polygon_oriented_bounds(polygon: PackedVector2Array, center: Vector2, u_axis: Vector2, v_axis: Vector2) -> Dictionary:
	if polygon.size() < 3:
		return {}

	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF
	for point: Vector2 in polygon:
		var relative := point - center
		var u := relative.dot(u_axis)
		var v := relative.dot(v_axis)
		min_u = minf(min_u, u)
		max_u = maxf(max_u, u)
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)

	return {
		"min_u": min_u,
		"max_u": max_u,
		"min_v": min_v,
		"max_v": max_v,
	}


func _is_candidate_polygon_valid(polygon: PackedVector2Array, field_lookup: Dictionary, road_polylines: Array) -> bool:
	if polygon.size() < 3 or absf(_get_polygon_signed_area(polygon)) <= 0.001:
		return false
	if not _is_polygon_simple(polygon):
		return false

	var clearance := maxf(0.0, road_width * 0.5 + road_clearance)
	var center := _find_polygon_interior_point(polygon)
	for point: Vector2 in polygon:
		var inset_point := point.lerp(center, 0.02)
		if not field_lookup.has(_local_2d_to_cell(inset_point)):
			return false
		if _is_point_near_roads(point, road_polylines, clearance):
			return false

	if not field_lookup.has(_local_2d_to_cell(center)):
		return false
	if _is_point_near_roads(center, road_polylines, clearance):
		return false
	return true


func _find_polygon_interior_point(polygon: PackedVector2Array) -> Vector2:
	var centroid := _get_polygon_centroid(polygon)
	if _is_point_in_polygon(centroid, polygon):
		return centroid

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	var best_point := polygon[0]
	var best_distance := -INF
	for x_index: int in range(7):
		for y_index: int in range(7):
			var candidate := Vector2(
				lerpf(min_point.x, max_point.x, (float(x_index) + 0.5) / 7.0),
				lerpf(min_point.y, max_point.y, (float(y_index) + 0.5) / 7.0)
			)
			if not _is_point_in_polygon(candidate, polygon):
				continue
			var distance := _get_polygon_edge_distance(candidate, polygon)
			if distance > best_distance:
				best_distance = distance
				best_point = candidate
	return best_point


func _get_polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var signed_area := _get_polygon_signed_area(polygon)
	if absf(signed_area) <= 0.000001:
		var average := Vector2.ZERO
		for point: Vector2 in polygon:
			average += point
		return average / float(maxi(polygon.size(), 1))

	var cx := 0.0
	var cy := 0.0
	for index: int in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var cross := current.x * next.y - next.x * current.y
		cx += (current.x + next.x) * cross
		cy += (current.y + next.y) * cross
	var factor := 1.0 / (6.0 * signed_area)
	return Vector2(cx * factor, cy * factor)


func _build_local_footprint(
	polygon: PackedVector2Array,
	center: Vector2,
	road_direction: Vector2,
	depth_direction: Vector2
) -> PackedVector2Array:
	var footprint := PackedVector2Array()
	for point: Vector2 in polygon:
		var relative := point - center
		footprint.append(Vector2(relative.dot(road_direction), relative.dot(depth_direction)))
	return footprint


func _append_plot_bund_polylines(plot: FieldPlotData) -> void:
	var outline := plot.get_region_outline_2d()
	if outline.size() < 2:
		return

	for index: int in range(outline.size()):
		_append_unique_polyline(generated_bund_polylines, outline[index], outline[(index + 1) % outline.size()])
		_append_unique_polyline(generated_road_polylines, outline[index], outline[(index + 1) % outline.size()])


func _append_unique_polyline(polylines: Array, from_point: Vector2, to_point: Vector2) -> void:
	if from_point.distance_squared_to(to_point) <= 0.0001:
		return

	var forward_key := "%s>%s" % [_point_key(from_point), _point_key(to_point)]
	var reverse_key := "%s>%s" % [_point_key(to_point), _point_key(from_point)]
	for polyline: PackedVector2Array in polylines:
		if polyline.size() < 2:
			continue
		var existing_key := "%s>%s" % [_point_key(polyline[0]), _point_key(polyline[1])]
		if existing_key == forward_key or existing_key == reverse_key:
			return

	var polyline := PackedVector2Array()
	polyline.append(from_point)
	polyline.append(to_point)
	polylines.append(polyline)


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


func _get_polygon_edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var min_distance := INF
	for index: int in range(polygon.size()):
		min_distance = minf(min_distance, _distance_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()]))
	return min_distance


func _is_polygon_simple(polygon: PackedVector2Array) -> bool:
	for first_index: int in range(polygon.size()):
		var first_from := polygon[first_index]
		var first_to := polygon[(first_index + 1) % polygon.size()]
		for second_index: int in range(first_index + 1, polygon.size()):
			if abs(second_index - first_index) <= 1:
				continue
			if first_index == 0 and second_index == polygon.size() - 1:
				continue
			if _segments_intersect(first_from, first_to, polygon[second_index], polygon[(second_index + 1) % polygon.size()]):
				return false
	return true


func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _cross_2d(b - a, c - a)
	var ab_d := _cross_2d(b - a, d - a)
	var cd_a := _cross_2d(d - c, a - c)
	var cd_b := _cross_2d(d - c, b - c)
	if _opposite_signs(ab_c, ab_d) and _opposite_signs(cd_a, cd_b):
		return true
	if absf(ab_c) <= 0.000001 and _is_point_on_segment(c, a, b):
		return true
	if absf(ab_d) <= 0.000001 and _is_point_on_segment(d, a, b):
		return true
	if absf(cd_a) <= 0.000001 and _is_point_on_segment(a, c, d):
		return true
	if absf(cd_b) <= 0.000001 and _is_point_on_segment(b, c, d):
		return true
	return false


func _opposite_signs(a: float, b: float) -> bool:
	return (a < 0.0 and b > 0.0) or (a > 0.0 and b < 0.0)


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


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _get_polygon_signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _normalize_or_right(direction: Vector2) -> Vector2:
	if direction.length_squared() <= 0.0001:
		return Vector2.RIGHT
	return direction.normalized()


func _canonical_axis_direction(direction: Vector2) -> Vector2:
	var normalized := _normalize_or_right(direction)
	if absf(normalized.x) >= absf(normalized.y):
		return normalized if normalized.x >= 0.0 else -normalized
	return normalized if normalized.y >= 0.0 else -normalized


func _get_vertical_corridor_centers(min_u: float, max_u: float, safe_gap: float, rng: RandomNumberGenerator) -> Array[float]:
	var gap_centers: Array[float] = []
	var component_length := max_u - min_u
	if safe_gap <= 0.0 or component_length < min_plot_length:
		return gap_centers

	var split_intervals := _split_plot_interval_uneven(Vector2(min_u, max_u), safe_gap, rng)
	if split_intervals.size() < 2:
		return gap_centers

	for index: int in range(split_intervals.size() - 1):
		var from_interval: Vector2 = split_intervals[index]
		var to_interval: Vector2 = split_intervals[index + 1]
		gap_centers.append((from_interval.y + to_interval.x) * 0.5)

	return gap_centers


func _split_plot_interval(
	interval: Vector2,
	safe_gap: float,
	vertical_corridor_centers: Array[float],
	rng: RandomNumberGenerator
) -> Array[Vector2]:
	var length := interval.y - interval.x
	if length < min_plot_length:
		return []

	if safe_gap > 0.0 and not vertical_corridor_centers.is_empty():
		var corridor_intervals := _split_plot_interval_by_vertical_corridors(interval, safe_gap, vertical_corridor_centers)
		if not corridor_intervals.is_empty():
			return corridor_intervals

	return _split_plot_interval_uneven(interval, safe_gap, rng)


func _split_plot_interval_by_vertical_corridors(
	interval: Vector2,
	safe_gap: float,
	vertical_corridor_centers: Array[float]
) -> Array[Vector2]:
	var split_intervals: Array[Vector2] = []
	var gap_half_width := safe_gap * 0.5
	var segment_start := interval.x
	var used_gap := false

	for gap_center: float in vertical_corridor_centers:
		var gap_min := gap_center - gap_half_width
		var gap_max := gap_center + gap_half_width
		if gap_max <= interval.x + 0.001:
			continue
		if gap_min >= interval.y - 0.001:
			break

		used_gap = true
		var segment_end := clampf(gap_min, interval.x, interval.y)
		if segment_end - segment_start >= min_plot_length:
			split_intervals.append(Vector2(segment_start, segment_end))
		segment_start = maxf(segment_start, clampf(gap_max, interval.x, interval.y))

	if interval.y - segment_start >= min_plot_length:
		split_intervals.append(Vector2(segment_start, interval.y))

	if used_gap:
		return split_intervals
	var empty_intervals: Array[Vector2] = []
	return empty_intervals


func _split_plot_interval_uneven(interval: Vector2, safe_gap: float, rng: RandomNumberGenerator) -> Array[Vector2]:
	var length := interval.y - interval.x
	if length < min_plot_length:
		return []

	var safe_min_length := maxf(min_plot_length, 0.001)
	var safe_max_length := maxf(max_plot_length, min_plot_length)
	if length <= safe_max_length:
		return _single_plot_interval(interval)

	var min_segment_count := maxi(1, ceili((length + safe_gap) / (safe_max_length + safe_gap)))
	var max_segment_count := floori((length + safe_gap) / (safe_min_length + safe_gap))
	if max_segment_count < min_segment_count:
		return _single_plot_interval(interval)

	var segment_count := min_segment_count
	var choice_max := mini(max_segment_count, min_segment_count + 2)
	if choice_max > min_segment_count:
		segment_count = rng.randi_range(min_segment_count, choice_max)

	var plot_total_length := length - safe_gap * float(segment_count - 1)
	if _is_forced_equal_split(plot_total_length, segment_count, safe_min_length, safe_max_length):
		if segment_count < max_segment_count:
			segment_count += 1
		elif segment_count > min_segment_count:
			segment_count -= 1
		plot_total_length = length - safe_gap * float(segment_count - 1)

	if segment_count <= 1 or plot_total_length < safe_min_length:
		return _single_plot_interval(interval)

	var segment_lengths := _distribute_plot_lengths(plot_total_length, segment_count, safe_min_length, safe_max_length, rng)
	var split_intervals: Array[Vector2] = []
	var start_u := interval.x
	for segment_length: float in segment_lengths:
		var end_u := start_u + segment_length
		split_intervals.append(Vector2(start_u, end_u))
		start_u = end_u + safe_gap

	return split_intervals


func _pick_high_variance_extent(min_extent: float, max_extent: float, rng: RandomNumberGenerator) -> float:
	var safe_min := maxf(min_extent, 0.001)
	var safe_max := maxf(max_extent, safe_min)
	if safe_max <= safe_min + 0.001:
		return safe_min

	var roll := rng.randf()
	var shaped := pow(rng.randf(), 2.25)
	var t := shaped if roll < 0.5 else 1.0 - shaped
	return lerpf(safe_min, safe_max, t)


func _distribute_plot_lengths(
	total_length: float,
	segment_count: int,
	safe_min_length: float,
	safe_max_length: float,
	rng: RandomNumberGenerator
) -> Array[float]:
	var lengths: Array[float] = []
	if segment_count <= 0:
		return lengths

	var capacity := maxf(safe_max_length - safe_min_length, 0.0)
	var remaining_extra := clampf(total_length - safe_min_length * float(segment_count), 0.0, capacity * float(segment_count))
	for _segment_index: int in range(segment_count):
		lengths.append(safe_min_length)

	if remaining_extra <= 0.001 or capacity <= 0.001:
		return lengths

	var weights: Array[float] = []
	for _segment_index: int in range(segment_count):
		weights.append(pow(rng.randf_range(0.08, 1.0), 2.4))

	var active_indices: Array[int] = []
	for segment_index: int in range(segment_count):
		active_indices.append(segment_index)

	var safety := segment_count * 4
	while remaining_extra > 0.001 and not active_indices.is_empty() and safety > 0:
		safety -= 1
		var total_weight := 0.0
		for segment_index: int in active_indices:
			total_weight += weights[segment_index]
		if total_weight <= 0.001:
			break

		var distributed_this_pass := 0.0
		for active_position: int in range(active_indices.size() - 1, -1, -1):
			var segment_index := active_indices[active_position]
			var available := safe_max_length - lengths[segment_index]
			if available <= 0.001:
				active_indices.remove_at(active_position)
				continue

			var share := remaining_extra * weights[segment_index] / total_weight
			var added := minf(available, share)
			lengths[segment_index] += added
			distributed_this_pass += added
			if lengths[segment_index] >= safe_max_length - 0.001:
				active_indices.remove_at(active_position)

		remaining_extra -= distributed_this_pass
		if distributed_this_pass <= 0.001:
			break

	if remaining_extra > 0.001:
		for segment_index: int in range(segment_count):
			var available := safe_max_length - lengths[segment_index]
			if available <= 0.001:
				continue
			var added := minf(available, remaining_extra)
			lengths[segment_index] += added
			remaining_extra -= added
			if remaining_extra <= 0.001:
				break

	return lengths


func _is_forced_equal_split(total_length: float, segment_count: int, safe_min_length: float, safe_max_length: float) -> bool:
	if segment_count <= 1:
		return false

	var epsilon := 0.001
	return (
		absf(total_length - safe_min_length * float(segment_count)) <= epsilon
		or absf(total_length - safe_max_length * float(segment_count)) <= epsilon
	)


func _single_plot_interval(interval: Vector2) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	intervals.append(interval)
	return intervals


func _build_plot_footprint(plot_length: float, plot_width: float) -> PackedVector2Array:
	# field_shape_variation is deprecated for generated village paddies.
	return _make_rectangle_footprint(plot_length, plot_width)


func _make_rectangle_footprint(plot_length: float, plot_width: float) -> PackedVector2Array:
	var half_length := maxf(plot_length, 0.0) * 0.5
	var half_width := maxf(plot_width, 0.0) * 0.5
	return PackedVector2Array([
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
	])


func _append_vertical_split_gap_roads(
	split_intervals: Array[Vector2],
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	band_center_v: float,
	band_width: float
) -> void:
	if split_intervals.size() < 2:
		return

	var band_min_v := band_center_v - band_width * 0.5
	var band_max_v := band_center_v + band_width * 0.5
	for index: int in range(split_intervals.size() - 1):
		var from_interval: Vector2 = split_intervals[index]
		var to_interval: Vector2 = split_intervals[index + 1]
		var gap_center_u := (from_interval.y + to_interval.x) * 0.5
		_append_generated_road(
			component_center + row_direction * gap_center_u + lateral_direction * band_min_v,
			component_center + row_direction * gap_center_u + lateral_direction * band_max_v
		)


func _append_vertical_corridor_roads(
	vertical_corridor_centers: Array[float],
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	min_v: float,
	max_v: float,
	safe_sample_step: float,
	field_lookup: Dictionary,
	road_polylines: Array
) -> void:
	if vertical_corridor_centers.is_empty():
		return

	var step := maxf(safe_sample_step, 0.25)
	var half_step := step * 0.5
	for gap_center_u: float in vertical_corridor_centers:
		var in_segment := false
		var segment_start_v := 0.0
		var segment_end_v := 0.0
		var sample_v := min_v + half_step
		while sample_v <= max_v - half_step + 0.001:
			var sample_point := component_center + row_direction * gap_center_u + lateral_direction * sample_v
			var valid := _is_point_valid_for_field(sample_point, field_lookup, road_polylines)
			if valid:
				if not in_segment:
					segment_start_v = sample_v - half_step
					in_segment = true
				segment_end_v = sample_v + half_step
			elif in_segment:
				_append_vertical_corridor_road_segment(
					component_center,
					row_direction,
					lateral_direction,
					gap_center_u,
					segment_start_v,
					segment_end_v
				)
				in_segment = false

			sample_v += step

		if in_segment:
			_append_vertical_corridor_road_segment(
				component_center,
				row_direction,
				lateral_direction,
				gap_center_u,
				segment_start_v,
				segment_end_v
			)


func _append_vertical_corridor_road_segment(
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	gap_center_u: float,
	segment_start_v: float,
	segment_end_v: float
) -> void:
	if segment_end_v - segment_start_v < maxf(field_road_gap_width * 0.5, 0.25):
		return

	_append_generated_road(
		component_center + row_direction * gap_center_u + lateral_direction * segment_start_v,
		component_center + row_direction * gap_center_u + lateral_direction * segment_end_v
	)


func _append_horizontal_row_gap_roads(
	intervals: Array[Vector2],
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	band_max_v: float,
	component_max_v: float,
	safe_gap: float
) -> void:
	if intervals.is_empty() or safe_gap <= 0.0 or band_max_v + safe_gap > component_max_v + 0.001:
		return

	var gap_center_v := band_max_v + safe_gap * 0.5
	for interval: Vector2 in intervals:
		if interval.y - interval.x < min_plot_length:
			continue
		_append_generated_road(
			component_center + row_direction * interval.x + lateral_direction * gap_center_v,
			component_center + row_direction * interval.y + lateral_direction * gap_center_v
		)


func _append_generated_road(from_point: Vector2, to_point: Vector2) -> void:
	if from_point.distance_squared_to(to_point) <= 0.0001:
		return

	var polyline := PackedVector2Array()
	polyline.append(from_point)
	polyline.append(to_point)
	generated_road_polylines.append(polyline)


func _get_valid_u_intervals(
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	min_u: float,
	max_u: float,
	band_center_v: float,
	band_width: float,
	safe_sample_step: float,
	field_lookup: Dictionary,
	road_polylines: Array
) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	var half_step := safe_sample_step * 0.5
	var sample_u := min_u + half_step
	var interval_start := 0.0
	var interval_end := 0.0
	var in_interval := false

	while sample_u <= max_u - half_step + 0.001:
		var valid := _is_band_sample_valid(
			component_center,
			row_direction,
			lateral_direction,
			sample_u,
			band_center_v,
			band_width,
			field_lookup,
			road_polylines
		)

		if valid:
			if not in_interval:
				interval_start = sample_u - half_step
				in_interval = true
			interval_end = sample_u + half_step
		elif in_interval:
			intervals.append(Vector2(interval_start, interval_end))
			in_interval = false

		sample_u += safe_sample_step

	if in_interval:
		intervals.append(Vector2(interval_start, interval_end))

	return intervals


func _is_band_sample_valid(
	component_center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	sample_u: float,
	band_center_v: float,
	band_width: float,
	field_lookup: Dictionary,
	road_polylines: Array
) -> bool:
	var v_offsets := [-0.48, 0.0, 0.48]
	for v_factor: float in v_offsets:
		var sample_point := component_center + row_direction * sample_u + lateral_direction * (band_center_v + band_width * v_factor)
		if not _is_point_valid_for_field(sample_point, field_lookup, road_polylines):
			return false
	return true


func _is_plot_valid(
	center: Vector2,
	row_direction: Vector2,
	lateral_direction: Vector2,
	plot_length: float,
	plot_width: float,
	field_lookup: Dictionary,
	road_polylines: Array
) -> bool:
	var sample_offsets := [-0.46, 0.0, 0.46]
	for u_factor: float in sample_offsets:
		for v_factor: float in sample_offsets:
			var sample_point := center + row_direction * plot_length * u_factor + lateral_direction * plot_width * v_factor
			if not _is_point_valid_for_field(sample_point, field_lookup, road_polylines):
				return false
	return true


func _is_point_valid_for_field(point: Vector2, field_lookup: Dictionary, road_polylines: Array) -> bool:
	if not field_lookup.has(_local_2d_to_cell(point)):
		return false
	var clearance := maxf(0.0, road_width * 0.5 + road_clearance)
	return not _is_point_near_roads(point, road_polylines, clearance)


func _bias_direction_horizontal(direction: Vector2) -> Vector2:
	var bias := clampf(horizontal_split_bias, 0.0, 1.0)
	if bias <= 0.0:
		return direction

	var horizontal_target := Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT
	var biased := direction.lerp(horizontal_target, bias)
	if biased.length_squared() <= 0.0001:
		return horizontal_target
	return biased.normalized()


func _normalize_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var unique_cells: Dictionary = {}
	for cell: Vector2i in value:
		unique_cells[cell] = true

	var normalized: Array[Vector2i] = []
	for key: Variant in unique_cells.keys():
		normalized.append(key)
	normalized.sort_custom(_compare_cells)
	return normalized


func _to_cell_lookup(cells: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for cell: Vector2i in cells:
		lookup[cell] = true
	return lookup


func _get_cell_components(cells: Array[Vector2i], lookup: Dictionary) -> Array:
	var components: Array = []
	var visited: Dictionary = {}

	for cell: Vector2i in cells:
		if visited.has(cell):
			continue

		var component: Array[Vector2i] = []
		var stack: Array[Vector2i] = [cell]
		visited[cell] = true

		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			component.append(current)

			for offset: Vector2i in NEIGHBOR_OFFSETS:
				var neighbor := current + offset
				if not lookup.has(neighbor) or visited.has(neighbor):
					continue

				visited[neighbor] = true
				stack.append(neighbor)

		component.sort_custom(_compare_cells)
		components.append(component)

	components.sort_custom(_compare_components)
	return components


func _get_component_center(component: Array) -> Vector2:
	var total := Vector2.ZERO
	for cell: Vector2i in component:
		total += _cell_to_local_2d_center(cell)
	return total / float(component.size())


func _get_component_oriented_bounds(component: Array, center: Vector2, row_direction: Vector2, lateral_direction: Vector2) -> Dictionary:
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF

	for cell: Vector2i in component:
		for corner: Vector2 in _get_cell_corners(cell):
			var relative := corner - center
			min_u = minf(min_u, relative.dot(row_direction))
			max_u = maxf(max_u, relative.dot(row_direction))
			min_v = minf(min_v, relative.dot(lateral_direction))
			max_v = maxf(max_v, relative.dot(lateral_direction))

	return {
		"min_u": min_u,
		"max_u": max_u,
		"min_v": min_v,
		"max_v": max_v,
	}


func _build_road_segment_buckets(road_polylines: Array) -> void:
	_road_segments.clear()
	_road_segment_buckets.clear()
	_road_bucket_size = maxf(maxf(cell_size, road_width + road_clearance), 0.25)

	for polyline: PackedVector2Array in road_polylines:
		if polyline.is_empty():
			continue

		if polyline.size() == 1:
			_append_road_segment({
				"single": true,
				"point": polyline[0],
				"from": polyline[0],
				"to": polyline[0],
			})
			continue

		for index: int in range(polyline.size() - 1):
			var from_point := polyline[index]
			var to_point := polyline[index + 1]
			if from_point.distance_squared_to(to_point) <= 0.0001:
				continue
			_append_road_segment({
				"single": false,
				"from": from_point,
				"to": to_point,
			})


func _append_road_segment(segment: Dictionary) -> void:
	var segment_index := _road_segments.size()
	_road_segments.append(segment)

	var from_point: Vector2 = segment.get("from", Vector2.ZERO)
	var to_point: Vector2 = segment.get("to", from_point)
	var min_point := Vector2(minf(from_point.x, to_point.x), minf(from_point.y, to_point.y))
	var max_point := Vector2(maxf(from_point.x, to_point.x), maxf(from_point.y, to_point.y))
	var min_bucket := _road_bucket_for_point(min_point)
	var max_bucket := _road_bucket_for_point(max_point)

	for bucket_x: int in range(min_bucket.x, max_bucket.x + 1):
		for bucket_y: int in range(min_bucket.y, max_bucket.y + 1):
			var bucket_key := Vector2i(bucket_x, bucket_y)
			var bucket: Array = _road_segment_buckets.get(bucket_key, [])
			bucket.append(segment_index)
			_road_segment_buckets[bucket_key] = bucket


func _road_bucket_for_point(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _road_bucket_size), floori(point.y / _road_bucket_size))


func _get_nearby_road_segment_indices(point: Vector2, clearance: float) -> Array[int]:
	var indices: Array[int] = []
	if _road_segment_buckets.is_empty():
		return indices

	var center_bucket := _road_bucket_for_point(point)
	var bucket_radius := ceili(maxf(clearance, 0.0) / _road_bucket_size) + 1
	var seen: Dictionary = {}
	for bucket_x: int in range(center_bucket.x - bucket_radius, center_bucket.x + bucket_radius + 1):
		for bucket_y: int in range(center_bucket.y - bucket_radius, center_bucket.y + bucket_radius + 1):
			var bucket_key := Vector2i(bucket_x, bucket_y)
			var bucket_variant: Variant = _road_segment_buckets.get(bucket_key)
			if not (bucket_variant is Array):
				continue

			for segment_index_variant: Variant in (bucket_variant as Array):
				var segment_index := int(segment_index_variant)
				if seen.has(segment_index):
					continue
				seen[segment_index] = true
				indices.append(segment_index)

	return indices


func _get_nearest_road_from_segments(point: Vector2, segment_indices: Array[int] = []) -> Dictionary:
	var nearest := {}
	var best_distance_squared := INF

	if segment_indices.is_empty():
		for index: int in range(_road_segments.size()):
			var segment := _road_segments[index]
			var candidate := _get_nearest_road_from_segment(point, segment)
			var distance := float(candidate.get("distance", INF))
			if distance * distance < best_distance_squared:
				best_distance_squared = distance * distance
				nearest = candidate
		return nearest

	for segment_index: int in segment_indices:
		var segment := _road_segments[segment_index]
		var candidate := _get_nearest_road_from_segment(point, segment)
		var distance := float(candidate.get("distance", INF))
		var distance_squared := distance * distance
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			nearest = candidate

	return nearest


func _get_nearest_road_from_segment(point: Vector2, segment: Dictionary) -> Dictionary:
	var from_point: Vector2 = segment.get("from", Vector2.ZERO)
	var to_point: Vector2 = segment.get("to", from_point)
	var closest := from_point
	var tangent := Vector2.ZERO
	if not bool(segment.get("single", false)):
		closest = _closest_point_on_segment(point, from_point, to_point)
		var tangent_delta := to_point - from_point
		if tangent_delta.length_squared() > 0.0001:
			tangent = tangent_delta.normalized()

	var distance_squared := point.distance_squared_to(closest)
	return {
		"point": closest,
		"tangent": tangent,
		"distance": sqrt(distance_squared),
	}


func _get_road_segment_distance_squared(point: Vector2, segment: Dictionary) -> float:
	var from_point: Vector2 = segment.get("from", Vector2.ZERO)
	if bool(segment.get("single", false)):
		return point.distance_squared_to(from_point)

	var to_point: Vector2 = segment.get("to", from_point)
	var closest := _closest_point_on_segment(point, from_point, to_point)
	return point.distance_squared_to(closest)


func _get_nearest_road_tangent(point: Vector2, road_polylines: Array) -> Vector2:
	var nearest := _get_nearest_road(point, road_polylines)
	if nearest.is_empty():
		return Vector2.ZERO
	return nearest.get("tangent", Vector2.ZERO)


func _get_nearest_road(point: Vector2, road_polylines: Array) -> Dictionary:
	if not _road_segments.is_empty():
		return _get_nearest_road_from_segments(point)

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

	if not _road_segments.is_empty():
		var segment_indices := _get_nearby_road_segment_indices(point, clearance)
		if segment_indices.is_empty():
			return false

		var clearance_squared := clearance * clearance
		for segment_index: int in segment_indices:
			if _get_road_segment_distance_squared(point, _road_segments[segment_index]) <= clearance_squared:
				return true
		return false

	var nearest := _get_nearest_road(point, road_polylines)
	if nearest.is_empty():
		return false

	return float(nearest.get("distance", INF)) <= clearance


func _local_2d_to_cell(point: Vector2) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2i(
		floori((point.x - origin.x) / safe_cell_size),
		floori((point.y - origin.z) / safe_cell_size)
	)


func _cell_to_local_2d_center(cell: Vector2i) -> Vector2:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2(
		origin.x + (float(cell.x) + 0.5) * safe_cell_size,
		origin.z + (float(cell.y) + 0.5) * safe_cell_size
	)


func _cell_to_local_2d_min(cell: Vector2i) -> Vector2:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2(
		origin.x + float(cell.x) * safe_cell_size,
		origin.z + float(cell.y) * safe_cell_size
	)


func _get_cell_corners(cell: Vector2i) -> Array[Vector2]:
	var cell_min := _cell_to_local_2d_min(cell)
	var safe_cell_size := maxf(cell_size, 0.1)
	return [
		cell_min,
		cell_min + Vector2(safe_cell_size, 0.0),
		cell_min + Vector2(safe_cell_size, safe_cell_size),
		cell_min + Vector2(0.0, safe_cell_size),
	]


func _get_plot_id(component_index: int, row_index: int, interval_index: int, segment_index: int, plot_index: int) -> StringName:
	return StringName("field_%03d_%03d_%03d_%03d_%03d" % [component_index, row_index, interval_index, segment_index, plot_index])


func _component_seed(component_index: int, component: Array) -> int:
	var first_cell: Vector2i = component[0]
	var mixed := int(generation_seed)
	mixed = _mix_int(mixed, component_index + 1)
	mixed = _mix_int(mixed, first_cell.x)
	mixed = _mix_int(mixed, first_cell.y)
	return absi(mixed)


func _mix_int(seed: int, value: int) -> int:
	return int((seed * 1664525 + value * 1013904223 + 0x9e3779b9) & 0x7fffffff)


static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func _compare_components(a: Array, b: Array) -> bool:
	if a.is_empty():
		return false
	if b.is_empty():
		return true
	return _compare_cells(a[0], b[0])
