extends "res://modules/units/human/human_npc.gd"
class_name PeasantNPC

@export_group("Peasant Behavior")
@export var behavior_enabled := true
@export_range(0.25, 30.0, 0.05, "or_greater") var min_idle_seconds: float = 1.0
@export_range(0.25, 30.0, 0.05, "or_greater") var max_idle_seconds: float = 3.5
@export_range(0.25, 30.0, 0.05, "or_greater") var min_task_seconds: float = 2.0
@export_range(0.25, 30.0, 0.05, "or_greater") var max_task_seconds: float = 5.0
@export_range(0.0, 1.0, 0.01) var field_task_chance: float = 0.42
@export_range(0.0, 1.0, 0.01) var run_chance: float = 0.08
@export_range(0.0, 1.0, 0.01) var tool_practice_chance: float = 0.04
@export_range(0.0, 256.0, 0.1, "or_greater") var roam_radius: float = 72.0
@export_range(0.0, 16.0, 0.1, "or_greater") var target_jitter_radius: float = 1.6
@export_range(0.5, 32.0, 0.1, "or_greater") var min_roam_target_distance: float = 2.0
@export_range(1.0, 64.0, 0.1, "or_greater") var house_patrol_radius: float = 8.0

var _village_region: Node
var _anchors: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _decision_timer := 0.0
var _pending_field_task := false
var _home_position := Vector3.ZERO
var _configured := false


func _ready() -> void:
	super._ready()
	add_to_group(&"peasants")
	if not _configured:
		_rng.randomize()
		_home_position = global_position
		_reset_decision_timer()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_behavior(delta)


func configure_village_context(
	village_region: Node,
	terrain: Node3D,
	anchors: Dictionary,
	seed: int
) -> void:
	_village_region = village_region
	_anchors = anchors.duplicate(true)
	if _anchors.has("roam_radius"):
		roam_radius = maxf(float(_anchors["roam_radius"]), 0.0)
	_rng.seed = absi(seed)
	_home_position = position
	if is_inside_tree():
		_home_position = global_position
	_configured = true
	configure_surface_height_source(terrain)
	_reset_decision_timer()


func _update_behavior(delta: float) -> void:
	if not behavior_enabled or not is_alive():
		return

	if _pending_field_task and not has_active_move_target() and get_state() == STATE_IDLE:
		_pending_field_task = false
		play_field_task(_rng.randf_range(min_task_seconds, max_task_seconds))
		_reset_decision_timer()
		return

	if has_active_move_target() or get_state() == STATE_FIELD_TASK or get_state() == STATE_TOOL_ACTION:
		return

	_decision_timer -= delta
	if _decision_timer > 0.0:
		return

	_choose_next_behavior()


func _choose_next_behavior() -> void:
	if _rng.randf() < tool_practice_chance:
		use_tool()
		_reset_decision_timer()
		return

	var use_field := _rng.randf() < field_task_chance and not _get_candidate_points(&"field_world_points").is_empty()
	var target := Vector3(INF, INF, INF)
	if use_field:
		target = _pick_anchor_point(&"field_world_points")
		_pending_field_task = true
	else:
		var roll := _rng.randf()
		if roll < 0.45 and not _get_candidate_points(&"road_world_points").is_empty():
			target = _pick_anchor_point(&"road_world_points")
		elif roll < 0.75 and not _get_candidate_points(&"field_world_points").is_empty():
			target = _pick_anchor_point(&"field_world_points")
		else:
			target = _pick_anchor_point(&"house_world_points")
		_pending_field_task = false

	if target.x == INF:
		target = _make_house_patrol_target()
		_pending_field_task = false
	if target.x == INF:
		_reset_decision_timer()
		return

	target += _random_horizontal_offset(target_jitter_radius)
	if not use_field and _is_target_too_close(target):
		target = _make_house_patrol_target()
	if target.x == INF:
		_reset_decision_timer()
		return

	set_move_target(target, _rng.randf() < run_chance)
	_reset_decision_timer()


func _pick_anchor_point(key: StringName) -> Vector3:
	var points := _get_candidate_points(key)
	if points.is_empty():
		points = _get_candidate_points(&"house_world_points")
	if points.is_empty():
		return Vector3(INF, INF, INF)

	var index := _rng.randi_range(0, points.size() - 1)
	return points[index]


func _get_candidate_points(key: StringName) -> Array[Vector3]:
	var points := _get_filtered_points(key)
	if not points.is_empty():
		return points
	if key != &"house_world_points":
		return _get_nearest_points(key, 4)
	return _get_nearest_points(key, 2)


func _get_filtered_points(key: StringName) -> Array[Vector3]:
	var all_points: Array = _anchors.get(key, [])
	var filtered: Array[Vector3] = []
	var safe_radius := maxf(roam_radius, 0.0)
	var radius_squared := safe_radius * safe_radius
	for point_variant: Variant in all_points:
		if not (point_variant is Vector3):
			continue
		var point := point_variant as Vector3
		var offset := point - _home_position
		offset.y = 0.0
		if safe_radius <= 0.0 or offset.length_squared() <= radius_squared:
			filtered.append(point)
	return filtered


func _get_nearest_points(key: StringName, max_count: int) -> Array[Vector3]:
	var all_points: Array = _anchors.get(key, [])
	var nearest: Array[Vector3] = []
	var nearest_distances: Array[float] = []
	var origin := _get_current_world_position()
	for point_variant: Variant in all_points:
		if not (point_variant is Vector3):
			continue

		var point := point_variant as Vector3
		var offset := point - origin
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		var inserted := false
		for index: int in range(nearest.size()):
			if distance_squared < nearest_distances[index]:
				nearest.insert(index, point)
				nearest_distances.insert(index, distance_squared)
				inserted = true
				break
		if not inserted:
			nearest.append(point)
			nearest_distances.append(distance_squared)

		if nearest.size() > max_count:
			nearest.resize(max_count)
			nearest_distances.resize(max_count)

	return nearest


func _make_house_patrol_target() -> Vector3:
	var origin := _home_position
	if origin == Vector3.ZERO:
		origin = _get_current_world_position()

	var radius := maxf(house_patrol_radius, min_roam_target_distance + target_jitter_radius)
	for _attempt: int in range(8):
		var target := origin + _random_horizontal_offset(radius)
		if not _is_target_too_close(target):
			return target
	return Vector3(INF, INF, INF)


func _is_target_too_close(target: Vector3) -> bool:
	var offset := target - _get_current_world_position()
	offset.y = 0.0
	return offset.length_squared() < min_roam_target_distance * min_roam_target_distance


func _get_current_world_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position


func _random_horizontal_offset(radius: float) -> Vector3:
	var safe_radius := maxf(radius, 0.0)
	if safe_radius <= 0.0:
		return Vector3.ZERO

	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(0.0, safe_radius)
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _reset_decision_timer() -> void:
	var max_wait := maxf(max_idle_seconds, min_idle_seconds)
	_decision_timer = _rng.randf_range(min_idle_seconds, max_wait)
