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
var min_plot_width: float = 2.4
var max_plot_width: float = 5.6
var bund_gap: float = 0.35
var field_road_gap_width: float = 1.2
var min_plot_length: float = 4.0
var max_plot_length: float = 12.0
var sample_step: float = 1.0
var road_width: float = 3.2
var road_clearance: float = 1.0
var horizontal_split_bias: float = 1.0
var generated_road_polylines: Array = []
var _road_segments: Array[Dictionary] = []
var _road_segment_buckets: Dictionary = {}
var _road_bucket_size := 4.0


func generate(field_cells: Array[Vector2i], road_polylines: Array) -> Array[FieldPlotData]:
	var plots: Array[FieldPlotData] = []
	generated_road_polylines.clear()
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
		var row_direction := _get_nearest_road_tangent(component_center, road_polylines)
		if row_direction.length_squared() <= 0.0001:
			row_direction = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		row_direction = row_direction.normalized()
		row_direction = _bias_direction_horizontal(row_direction)

		var lateral_direction := Vector2(-row_direction.y, row_direction.x).normalized()
		var bounds := _get_component_oriented_bounds(component, component_center, row_direction, lateral_direction)
		var min_u: float = bounds["min_u"]
		var max_u: float = bounds["max_u"]
		var min_v: float = bounds["min_v"]
		var max_v: float = bounds["max_v"]
		var safe_min_width := maxf(min_plot_width, 0.1)
		var safe_max_width := maxf(max_plot_width, safe_min_width)
		var safe_gap := maxf(maxf(field_road_gap_width, bund_gap), 0.0)
		var safe_sample_step := maxf(sample_step, minf(cell_size, safe_min_width) * 0.25)
		var vertical_corridor_centers := _get_vertical_corridor_centers(min_u, max_u, safe_gap)
		_append_vertical_corridor_roads(
			vertical_corridor_centers,
			component_center,
			row_direction,
			lateral_direction,
			min_v,
			max_v,
			safe_sample_step,
			field_lookup,
			road_polylines
		)
		var row_index := 0
		var band_min_v := min_v

		while band_min_v <= max_v:
			var band_width := rng.randf_range(safe_min_width, safe_max_width)
			var band_max_v := band_min_v + band_width
			var band_center_v := (band_min_v + band_max_v) * 0.5
			var intervals := _get_valid_u_intervals(
				component_center,
				row_direction,
				lateral_direction,
				min_u,
				max_u,
				band_center_v,
				band_width,
				safe_sample_step,
				field_lookup,
				road_polylines
			)

			for interval_index: int in range(intervals.size()):
				var interval: Vector2 = intervals[interval_index]
				if interval.y - interval.x < min_plot_length:
					continue

				var split_intervals := _split_plot_interval(interval, safe_gap, vertical_corridor_centers)
				_append_vertical_split_gap_roads(
					split_intervals,
					component_center,
					row_direction,
					lateral_direction,
					band_center_v,
					band_width
				)

				for segment_index: int in range(split_intervals.size()):
					var split_interval: Vector2 = split_intervals[segment_index]
					var plot_length := split_interval.y - split_interval.x
					var center_u := (split_interval.x + split_interval.y) * 0.5
					var center_2d := component_center + row_direction * center_u + lateral_direction * band_center_v
					if not _is_plot_valid(center_2d, row_direction, lateral_direction, plot_length, band_width, field_lookup, road_polylines):
						continue

					var plot := FieldPlotData.new()
					plot.configure(
						_get_plot_id(component_index, row_index, interval_index, segment_index, plot_index),
						Vector3(center_2d.x, 0.0, center_2d.y),
						Vector3(row_direction.x, 0.0, row_direction.y),
						Vector3(lateral_direction.x, 0.0, lateral_direction.y),
						plot_length,
						band_width
					)
					plots.append(plot)
					plot_index += 1

			_append_horizontal_row_gap_roads(
				intervals,
				component_center,
				row_direction,
				lateral_direction,
				band_max_v,
				max_v,
				safe_gap
			)

			row_index += 1
			band_min_v = band_max_v + safe_gap

	return plots


func _get_vertical_corridor_centers(min_u: float, max_u: float, safe_gap: float) -> Array[float]:
	var gap_centers: Array[float] = []
	var safe_max_length := maxf(max_plot_length, min_plot_length)
	var component_length := max_u - min_u
	if safe_gap <= 0.0 or component_length <= safe_max_length + safe_gap:
		return gap_centers

	var gap_center := min_u + safe_max_length + safe_gap * 0.5
	var last_allowed_center := max_u - min_plot_length - safe_gap * 0.5
	while gap_center <= last_allowed_center + 0.001:
		gap_centers.append(gap_center)
		gap_center += safe_max_length + safe_gap

	return gap_centers


func _split_plot_interval(interval: Vector2, safe_gap: float, vertical_corridor_centers: Array[float]) -> Array[Vector2]:
	var length := interval.y - interval.x
	if length < min_plot_length:
		return []

	if safe_gap > 0.0 and not vertical_corridor_centers.is_empty():
		var corridor_intervals := _split_plot_interval_by_vertical_corridors(interval, safe_gap, vertical_corridor_centers)
		if not corridor_intervals.is_empty():
			return corridor_intervals

	return _split_plot_interval_evenly(interval, safe_gap)


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


func _split_plot_interval_evenly(interval: Vector2, safe_gap: float) -> Array[Vector2]:
	var length := interval.y - interval.x
	if length < min_plot_length:
		return []

	var safe_max_length := maxf(max_plot_length, min_plot_length)
	if safe_gap <= 0.0 or length <= safe_max_length:
		return _single_plot_interval(interval)

	var segment_count := ceili((length + safe_gap) / (safe_max_length + safe_gap))
	while segment_count > 1:
		var candidate_length := (length - safe_gap * float(segment_count - 1)) / float(segment_count)
		if candidate_length >= min_plot_length:
			break
		segment_count -= 1

	if segment_count <= 1:
		return _single_plot_interval(interval)

	var segment_length := (length - safe_gap * float(segment_count - 1)) / float(segment_count)
	var split_intervals: Array[Vector2] = []
	var start_u := interval.x
	for _segment_index: int in range(segment_count):
		var end_u := start_u + segment_length
		split_intervals.append(Vector2(start_u, end_u))
		start_u = end_u + safe_gap

	return split_intervals


func _single_plot_interval(interval: Vector2) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	intervals.append(interval)
	return intervals


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
