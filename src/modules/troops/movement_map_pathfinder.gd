extends RefCounted
class_name MovementMapPathfinder

const FAILURE_NO_MAP := &"no_map"
const FAILURE_INVALID_MAP := &"invalid_map"
const FAILURE_NO_START := &"no_start"
const FAILURE_NO_TARGET := &"no_target"
const FAILURE_UNREACHABLE := &"unreachable"
const FAILURE_NONE := &""

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


static func find_path(
	movement_map: Resource,
	start_world: Vector3,
	target_world: Vector3,
	base_speed_mps: float = 1.0,
	nearest_search_radius_cells: int = 10,
	smooth_path: bool = true,
	corner_radius_cells: float = 1.35,
	corner_samples: int = 8
) -> Dictionary:
	var data := movement_map as MovementMapData
	if not data:
		return _make_failure(FAILURE_NO_MAP, start_world, target_world)

	if not _is_valid_data(data):
		return _make_failure(FAILURE_INVALID_MAP, start_world, target_world)

	var requested_target_cell := data.world_to_cell(target_world)
	var start_cell := _find_nearest_walkable_cell(
		data,
		data.world_to_cell(start_world),
		maxi(nearest_search_radius_cells, 0)
	)
	if not data.is_valid_cell(start_cell):
		return _make_failure(FAILURE_NO_START, start_world, target_world)

	var target_cell := _find_nearest_walkable_cell(
		data,
		requested_target_cell,
		maxi(nearest_search_radius_cells, 0)
	)
	if not data.is_valid_cell(target_cell):
		return _make_failure(FAILURE_NO_TARGET, start_world, target_world)

	var resolved_destination := _resolve_destination(data, target_cell, requested_target_cell, target_world)
	if start_cell == target_cell:
		var direct_cells: Array[Vector2i] = [start_cell]
		var direct_points: Array[Vector3] = [start_world, resolved_destination]
		var direct_speed := maxf(base_speed_mps * data.get_speed_multiplier_cell(start_cell), 0.001)
		var direct_seconds := _calculate_distance(direct_points) / direct_speed
		return _make_success(data, direct_cells, direct_points, target_world, resolved_destination, direct_seconds)

	var width := data.width
	var height := data.height
	var cell_count := width * height
	var start_id := _cell_to_id(start_cell, width)
	var target_id := _cell_to_id(target_cell, width)
	var max_speed_multiplier := _get_max_speed_multiplier(data)
	var safe_base_speed := maxf(base_speed_mps, 0.001)

	var g_scores := PackedFloat32Array()
	g_scores.resize(cell_count)
	var came_from := PackedInt32Array()
	came_from.resize(cell_count)
	var closed := PackedByteArray()
	closed.resize(cell_count)
	for index: int in range(cell_count):
		g_scores[index] = INF
		came_from[index] = -1
		closed[index] = 0

	var open_ids: Array[int] = []
	var open_priorities: Array[float] = []
	g_scores[start_id] = 0.0
	_heap_push(open_ids, open_priorities, start_id, 0.0)

	while not open_ids.is_empty():
		var current_id := _heap_pop(open_ids, open_priorities)
		if closed[current_id] != 0:
			continue
		if current_id == target_id:
			var cells := _reconstruct_cells(came_from, current_id, width)
			var raw_points := _cells_to_points(data, cells, start_world, resolved_destination)
			var points := _smooth_path_points(data, raw_points, smooth_path, corner_radius_cells, corner_samples)
			return _make_success(
				data,
				cells,
				points,
				target_world,
				resolved_destination,
				g_scores[current_id]
			)

		closed[current_id] = 1
		var current_cell := _id_to_cell(current_id, width)
		for offset: Vector2i in NEIGHBOR_OFFSETS:
			var neighbor_cell := current_cell + offset
			if not data.is_valid_cell(neighbor_cell):
				continue
			if not _is_walkable(data, neighbor_cell):
				continue
			if offset.x != 0 and offset.y != 0:
				if (
					not _is_walkable(data, current_cell + Vector2i(offset.x, 0))
					or not _is_walkable(data, current_cell + Vector2i(0, offset.y))
				):
					continue

			var neighbor_id := _cell_to_id(neighbor_cell, width)
			if closed[neighbor_id] != 0:
				continue

			var movement_cost := _movement_cost(data, current_cell, neighbor_cell, safe_base_speed)
			if is_inf(movement_cost):
				continue

			var tentative_g := g_scores[current_id] + movement_cost
			if tentative_g >= g_scores[neighbor_id]:
				continue

			came_from[neighbor_id] = current_id
			g_scores[neighbor_id] = tentative_g
			var priority := tentative_g + _heuristic_cost(
				data,
				neighbor_cell,
				target_cell,
				safe_base_speed,
				max_speed_multiplier
			)
			_heap_push(open_ids, open_priorities, neighbor_id, priority)

	return _make_failure(FAILURE_UNREACHABLE, start_world, resolved_destination)


static func _is_valid_data(data: MovementMapData) -> bool:
	var cell_count := data.width * data.height
	return (
		data.width > 0
		and data.height > 0
		and data.cell_size_meters > 0.0
		and data.speed_multipliers.size() >= cell_count
	)


static func _find_nearest_walkable_cell(
	data: MovementMapData,
	source_cell: Vector2i,
	max_radius: int
) -> Vector2i:
	var clamped_source := Vector2i(
		clampi(source_cell.x, 0, maxi(data.width - 1, 0)),
		clampi(source_cell.y, 0, maxi(data.height - 1, 0))
	)
	if data.is_valid_cell(source_cell) and _is_walkable(data, source_cell):
		return source_cell
	if _is_walkable(data, clamped_source):
		return clamped_source

	var best_cell := Vector2i(-1, -1)
	var best_distance_squared := INF
	for radius: int in range(1, max_radius + 1):
		for y: int in range(clamped_source.y - radius, clamped_source.y + radius + 1):
			for x: int in range(clamped_source.x - radius, clamped_source.x + radius + 1):
				if abs(x - clamped_source.x) != radius and abs(y - clamped_source.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if not _is_walkable(data, candidate):
					continue
				var distance_squared := Vector2(
					float(candidate.x - source_cell.x),
					float(candidate.y - source_cell.y)
				).length_squared()
				if distance_squared < best_distance_squared:
					best_cell = candidate
					best_distance_squared = distance_squared
		if data.is_valid_cell(best_cell):
			return best_cell
	return best_cell


static func _resolve_destination(
	data: MovementMapData,
	target_cell: Vector2i,
	requested_target_cell: Vector2i,
	target_world: Vector3
) -> Vector3:
	if target_cell == requested_target_cell and data.is_valid_cell(requested_target_cell):
		return target_world

	var center := data.cell_to_world_center(target_cell)
	return Vector3(center.x, target_world.y, center.y)


static func _is_walkable(data: MovementMapData, cell: Vector2i) -> bool:
	var index := data.get_cell_index(cell)
	if index < 0 or index >= data.speed_multipliers.size():
		return false
	return data.speed_multipliers[index] > 0.0


static func _movement_cost(
	data: MovementMapData,
	from_cell: Vector2i,
	to_cell: Vector2i,
	base_speed_mps: float
) -> float:
	var from_speed := data.get_speed_multiplier_cell(from_cell)
	var to_speed := data.get_speed_multiplier_cell(to_cell)
	var speed_multiplier := (from_speed + to_speed) * 0.5
	if speed_multiplier <= 0.0:
		return INF

	var distance := Vector2(
		float(from_cell.x - to_cell.x),
		float(from_cell.y - to_cell.y)
	).length() * data.cell_size_meters
	return distance / maxf(base_speed_mps * speed_multiplier, 0.001)


static func _heuristic_cost(
	data: MovementMapData,
	from_cell: Vector2i,
	to_cell: Vector2i,
	base_speed_mps: float,
	max_speed_multiplier: float
) -> float:
	var distance := Vector2(
		float(from_cell.x - to_cell.x),
		float(from_cell.y - to_cell.y)
	).length() * data.cell_size_meters
	return distance / maxf(base_speed_mps * max_speed_multiplier, 0.001)


static func _get_max_speed_multiplier(data: MovementMapData) -> float:
	var result := 1.0
	for speed: float in data.speed_multipliers:
		result = maxf(result, speed)
	return result


static func _reconstruct_cells(
	came_from: PackedInt32Array,
	current_id: int,
	width: int
) -> Array[Vector2i]:
	var ids: Array[int] = []
	var cursor := current_id
	while cursor >= 0:
		ids.append(cursor)
		cursor = came_from[cursor]
	ids.reverse()

	var cells: Array[Vector2i] = []
	for id: int in ids:
		cells.append(_id_to_cell(id, width))
	return cells


static func _cells_to_points(
	data: MovementMapData,
	cells: Array[Vector2i],
	start_world: Vector3,
	resolved_destination: Vector3
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	points.append(start_world)
	for index: int in range(1, maxi(cells.size() - 1, 1)):
		var center := data.cell_to_world_center(cells[index])
		points.append(Vector3(center.x, start_world.y, center.y))
	points.append(resolved_destination)
	return _dedupe_points(points)


static func _smooth_path_points(
	data: MovementMapData,
	raw_points: Array[Vector3],
	smooth_path: bool,
	corner_radius_cells: float,
	corner_samples: int
) -> Array[Vector3]:
	var points := _dedupe_points(raw_points)
	if not smooth_path or points.size() <= 2:
		return points

	var simplified := _simplify_path_points(data, points)
	return _round_path_corners(data, simplified, corner_radius_cells, corner_samples)


static func _simplify_path_points(data: MovementMapData, points: Array[Vector3]) -> Array[Vector3]:
	if points.size() <= 2:
		return points

	var simplified: Array[Vector3] = [points[0]]
	var anchor_index := 0
	while anchor_index < points.size() - 1:
		var next_index := points.size() - 1
		while next_index > anchor_index + 1:
			if _has_walkable_line(data, points[anchor_index], points[next_index]):
				break
			next_index -= 1

		simplified.append(points[next_index])
		anchor_index = next_index
	return _dedupe_points(simplified)


static func _round_path_corners(
	data: MovementMapData,
	points: Array[Vector3],
	corner_radius_cells: float,
	corner_samples: int
) -> Array[Vector3]:
	var safe_samples := maxi(corner_samples, 0)
	var radius_world := maxf(corner_radius_cells, 0.0) * maxf(data.cell_size_meters, 0.001)
	if points.size() <= 2 or radius_world <= 0.01 or safe_samples <= 0:
		return points

	var rounded: Array[Vector3] = [points[0]]
	for index: int in range(1, points.size() - 1):
		var previous := points[index - 1]
		var corner := points[index]
		var next := points[index + 1]
		var incoming := corner - previous
		var outgoing := next - corner
		incoming.y = 0.0
		outgoing.y = 0.0

		var incoming_length := incoming.length()
		var outgoing_length := outgoing.length()
		if incoming_length <= 0.01 or outgoing_length <= 0.01:
			rounded.append(corner)
			continue

		var incoming_direction := incoming / incoming_length
		var outgoing_direction := outgoing / outgoing_length
		var turn_dot := incoming_direction.dot(outgoing_direction)
		if absf(turn_dot) > 0.985:
			rounded.append(corner)
			continue

		var corner_radius := minf(radius_world, minf(incoming_length * 0.45, outgoing_length * 0.45))
		var entry := corner - incoming_direction * corner_radius
		var exit := corner + outgoing_direction * corner_radius
		entry.y = corner.y
		exit.y = corner.y

		if not _is_curve_walkable(data, entry, corner, exit, safe_samples):
			rounded.append(corner)
			continue

		for sample_index: int in range(safe_samples + 1):
			var t := float(sample_index) / float(safe_samples)
			rounded.append(_quadratic_bezier(entry, corner, exit, t))

	rounded.append(points.back())
	return _dedupe_points(rounded)


static func _is_curve_walkable(
	data: MovementMapData,
	entry: Vector3,
	control: Vector3,
	exit: Vector3,
	corner_samples: int
) -> bool:
	var sample_count := maxi(corner_samples * 3, 6)
	var previous := entry
	if not _is_walkable_world_point(data, previous):
		return false

	for sample_index: int in range(1, sample_count + 1):
		var t := float(sample_index) / float(sample_count)
		var current := _quadratic_bezier(entry, control, exit, t)
		if not _is_walkable_world_point(data, current):
			return false
		if not _has_walkable_line(data, previous, current):
			return false
		previous = current
	return true


static func _quadratic_bezier(start: Vector3, control: Vector3, end: Vector3, t: float) -> Vector3:
	var inverse := 1.0 - t
	return start * inverse * inverse + control * 2.0 * inverse * t + end * t * t


static func _has_walkable_line(data: MovementMapData, start: Vector3, end: Vector3) -> bool:
	if not _is_walkable_world_point(data, start) or not _is_walkable_world_point(data, end):
		return false

	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var distance := start_2d.distance_to(end_2d)
	var step_length := maxf(data.cell_size_meters * 0.2, 0.05)
	var steps := maxi(ceili(distance / step_length), 1)
	var previous_cell := data.world_to_cell(start)
	for step: int in range(1, steps + 1):
		var t := float(step) / float(steps)
		var point := start.lerp(end, t)
		var cell := data.world_to_cell(point)
		if not _is_walkable(data, cell):
			return false
		if cell != previous_cell:
			if not _is_cell_transition_walkable(data, previous_cell, cell):
				return false
			previous_cell = cell
	return true


static func _is_cell_transition_walkable(data: MovementMapData, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var delta := to_cell - from_cell
	if absi(delta.x) <= 1 and absi(delta.y) <= 1:
		if delta.x != 0 and delta.y != 0:
			return (
				_is_walkable(data, Vector2i(from_cell.x, to_cell.y))
				and _is_walkable(data, Vector2i(to_cell.x, from_cell.y))
			)
		return true

	var steps := maxi(absi(delta.x), absi(delta.y))
	var previous := from_cell
	for step: int in range(1, steps + 1):
		var t := float(step) / float(steps)
		var cell := Vector2i(
			roundi(lerpf(float(from_cell.x), float(to_cell.x), t)),
			roundi(lerpf(float(from_cell.y), float(to_cell.y), t))
		)
		if not _is_walkable(data, cell):
			return false
		if cell != previous and not _is_cell_transition_walkable(data, previous, cell):
			return false
		previous = cell
	return true


static func _is_walkable_world_point(data: MovementMapData, point: Vector3) -> bool:
	return _is_walkable(data, data.world_to_cell(point))


static func _dedupe_points(points: Array[Vector3]) -> Array[Vector3]:
	var deduped: Array[Vector3] = []
	for point: Vector3 in points:
		if deduped.is_empty() or deduped.back().distance_squared_to(point) > 0.01:
			deduped.append(point)
	return deduped


static func _make_success(
	data: MovementMapData,
	cells: Array[Vector2i],
	points: Array[Vector3],
	requested_destination: Vector3,
	resolved_destination: Vector3,
	estimated_seconds: float
) -> Dictionary:
	return {
		"reachable": true,
		"failure_reason": FAILURE_NONE,
		"cells": cells,
		"points": points,
		"requested_destination": requested_destination,
		"resolved_destination": resolved_destination,
		"distance_m": _calculate_distance(points),
		"estimated_seconds": maxf(estimated_seconds, 0.0),
		"cell_size_meters": data.cell_size_meters,
	}


static func _make_failure(
	reason: StringName,
	start_world: Vector3,
	target_world: Vector3
) -> Dictionary:
	return {
		"reachable": false,
		"failure_reason": reason,
		"cells": [],
		"points": [start_world],
		"requested_destination": target_world,
		"resolved_destination": target_world,
		"distance_m": 0.0,
		"estimated_seconds": 0.0,
		"cell_size_meters": 0.0,
	}


static func _calculate_distance(points: Array[Vector3]) -> float:
	var total := 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


static func _cell_to_id(cell: Vector2i, width: int) -> int:
	return cell.y * width + cell.x


static func _id_to_cell(id: int, width: int) -> Vector2i:
	return Vector2i(id % width, int(id / width))


static func _heap_push(ids: Array[int], priorities: Array[float], id: int, priority: float) -> void:
	ids.append(id)
	priorities.append(priority)
	var index := ids.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if priorities[parent] <= priorities[index]:
			return
		_swap_heap_entries(ids, priorities, parent, index)
		index = parent


static func _heap_pop(ids: Array[int], priorities: Array[float]) -> int:
	var result: int = ids[0]
	var last_id: int = ids.pop_back()
	var last_priority: float = priorities.pop_back()
	if ids.is_empty():
		return result

	ids[0] = last_id
	priorities[0] = last_priority
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < ids.size() and priorities[left] < priorities[smallest]:
			smallest = left
		if right < ids.size() and priorities[right] < priorities[smallest]:
			smallest = right
		if smallest == index:
			break
		_swap_heap_entries(ids, priorities, index, smallest)
		index = smallest
	return result


static func _swap_heap_entries(
	ids: Array[int],
	priorities: Array[float],
	first: int,
	second: int
) -> void:
	var temp_id := ids[first]
	var temp_priority := priorities[first]
	ids[first] = ids[second]
	priorities[first] = priorities[second]
	ids[second] = temp_id
	priorities[second] = temp_priority
