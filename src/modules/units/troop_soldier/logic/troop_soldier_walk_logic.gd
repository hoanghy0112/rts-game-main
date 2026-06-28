extends Resource
class_name TroopSoldierWalkLogic

const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")
const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_STANDING_FIGHTING := &"standing_fighting"
const STATE_FIGHTING := &"fighting"


func apply_formation_walking(soldier, active: bool, speed_mps: float = 1.0) -> void:
	if not soldier.is_alive():
		soldier._formation_walking = false
		soldier._formation_speed_scale = 1.0
		soldier._formation_facing_direction = Vector3.ZERO
		soldier._formation_frame_motion = Vector3.ZERO
		return
	if active:
		soldier._wake_logic()
	else:
		soldier._formation_facing_direction = Vector3.ZERO
		soldier._formation_frame_motion = Vector3.ZERO
	soldier._formation_walking = active
	if active:
		soldier._stationary_pose_applied = false
	soldier._formation_speed_scale = clampf(speed_mps / maxf(float(soldier.walk_speed), 0.1), 0.7, 2.4)
	if soldier.formation_visual_only:
		var combat_animation_active: bool = (
			soldier._formation_attacking
			or soldier.get_state() == STATE_STANDING_FIGHTING
			or soldier.get_state() == STATE_FIGHTING
		)
		if combat_animation_active:
			return
		soldier._set_state(STATE_WALK if soldier._formation_walking else STATE_IDLE)


func begin_direct_move(soldier, world_position: Vector3, run: bool = false) -> void:
	if not soldier.formation_visual_only:
		soldier._call_human_set_move_target(world_position, run)
		return
	apply_formation_walking(soldier, true, soldier.run_speed if run else soldier.walk_speed)


func clear_direct_move(soldier) -> void:
	if not soldier.formation_visual_only:
		soldier._call_human_clear_move_target()
		return
	apply_formation_walking(soldier, false)


func follow_formation_path(
	soldier,
	path_points: Array,
	slot_offset: Vector3,
	speed_mps: float,
	arrival_radius_m: float = 0.28,
	initial_path_index: int = 0,
	final_yaw_active: bool = false,
	final_yaw: float = 0.0
) -> void:
	if not soldier.is_alive():
		clear_independent_motion(soldier)
		return
	soldier._wake_logic()
	soldier._independent_path_points.clear()
	for point_variant: Variant in path_points:
		if point_variant is Vector3:
			soldier._independent_path_points.append(point_variant as Vector3)
	soldier._independent_path_index = (
		clampi(initial_path_index, 0, soldier._independent_path_points.size() - 1)
		if not soldier._independent_path_points.is_empty()
		else 0
	)
	soldier._independent_slot_offset = slot_offset
	soldier._independent_final_yaw_active = final_yaw_active
	soldier._independent_final_yaw = final_yaw
	soldier._independent_speed = maxf(speed_mps, 0.1)
	soldier._independent_arrival_radius = maxf(arrival_radius_m, 0.05)
	soldier._independent_motion_active = not soldier._independent_path_points.is_empty()
	soldier._has_independent_target = false
	if soldier._independent_motion_active:
		advance_completed_path_targets(soldier)
	soldier.set_formation_walking(soldier._independent_motion_active, soldier._independent_speed)


func set_independent_move_target(soldier, world_position: Vector3, speed_mps: float, arrival_radius_m: float = 0.24) -> void:
	if not soldier.is_alive():
		clear_independent_motion(soldier)
		return
	soldier._wake_logic()
	var arrival := maxf(arrival_radius_m, 0.05)
	var speed := maxf(speed_mps, 0.1)
	var to_target: Vector3 = world_position - soldier.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= arrival * arrival:
		if soldier._independent_motion_active or soldier._has_independent_target:
			clear_independent_motion(soldier)
		return
	if soldier._has_independent_target and soldier._independent_motion_active and soldier._independent_path_points.is_empty():
		var target_delta: Vector3 = world_position - soldier._independent_target
		target_delta.y = 0.0
		var retarget_epsilon := clampf(arrival * 0.55, 0.08, 0.36)
		if (
			target_delta.length_squared() <= retarget_epsilon * retarget_epsilon
			and absf(float(soldier._independent_speed) - speed) <= 0.08
			and absf(float(soldier._independent_arrival_radius) - arrival) <= 0.04
		):
			soldier._independent_target = soldier._independent_target.lerp(world_position, 0.35)
			soldier.set_formation_walking(true, soldier._independent_speed)
			return
	if (
		soldier._has_independent_target
		and soldier._independent_motion_active
		and soldier._independent_path_points.is_empty()
		and soldier._independent_target.distance_squared_to(world_position) <= 0.0004
		and is_equal_approx(soldier._independent_speed, speed)
		and is_equal_approx(soldier._independent_arrival_radius, arrival)
	):
		return
	soldier._independent_path_points.clear()
	soldier._independent_path_index = 0
	soldier._independent_final_yaw_active = false
	soldier._independent_final_yaw = 0.0
	soldier._independent_target = world_position
	soldier._independent_speed = speed
	soldier._independent_arrival_radius = arrival
	soldier._has_independent_target = true
	soldier._independent_motion_active = true
	soldier.set_formation_walking(true, soldier._independent_speed)


func set_independent_path_target(
	soldier,
	world_position: Vector3,
	movement_map: Resource,
	speed_mps: float,
	arrival_radius_m: float = 0.24,
	nearest_search_radius_cells: int = 10,
	smooth_path: bool = true,
	corner_radius_cells: float = 1.35,
	corner_samples: int = 8
) -> Dictionary:
	if not soldier.is_alive():
		clear_independent_motion(soldier)
		return _make_path_command_result(false, MovementMapPathfinderScript.FAILURE_NO_START, world_position, [])

	var speed := maxf(speed_mps, 0.1)
	var result: Dictionary = MovementMapPathfinderScript.find_path(
		movement_map,
		soldier.global_position,
		world_position,
		speed,
		nearest_search_radius_cells,
		smooth_path,
		corner_radius_cells,
		corner_samples
	)
	if not bool(result.get("reachable", false)):
		clear_independent_motion(soldier)
		return result

	var points: Array = result.get("points", [])
	follow_formation_path(
		soldier,
		points,
		Vector3.ZERO,
		speed,
		arrival_radius_m,
		0,
		false,
		0.0
	)
	return result


func clear_independent_motion(soldier) -> void:
	soldier._independent_path_points.clear()
	soldier._independent_path_index = 0
	soldier._independent_final_yaw_active = false
	soldier._independent_final_yaw = 0.0
	soldier._has_independent_target = false
	soldier._independent_motion_active = false
	soldier._combat_focus_target = null
	soldier.set_formation_walking(false)


func update_independent_motion(soldier, delta: float) -> bool:
	if soldier._deserted or not soldier.is_alive() or not soldier._independent_motion_active:
		return false
	var target: Variant = get_current_independent_target(soldier)
	if target == null:
		clear_independent_motion(soldier)
		return false

	var destination := target as Vector3
	var to_target: Vector3 = destination - soldier.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance <= soldier._independent_arrival_radius:
		if advance_completed_path_targets(soldier):
			return update_independent_motion(soldier, delta)
		clear_independent_motion(soldier)
		return false

	var direction: Vector3 = to_target / distance
	var motion_delta := minf(maxf(delta, 0.0), 0.05)
	var step := minf(maxf(soldier._independent_speed, 0.1) * motion_delta, distance)
	soldier.global_position += direction * step
	var facing_direction: Vector3 = soldier._formation_frame_motion + direction * step
	var combat_focus_active: bool = is_instance_valid(soldier._combat_focus_target) and soldier._combat_focus_target.is_inside_tree()
	if combat_focus_active:
		var to_focus: Vector3 = soldier._combat_focus_target.global_position - soldier.global_position
		to_focus.y = 0.0
		if to_focus.length_squared() > 0.0001:
			facing_direction = to_focus.normalized()
	if facing_direction.length_squared() <= 0.0001:
		facing_direction = soldier._formation_facing_direction if soldier._formation_facing_direction.length_squared() > 0.0001 else direction
	if soldier.formation_visual_only and not combat_focus_active and facing_direction.length_squared() > 0.0001:
		var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
		soldier.rotation.y = target_yaw
	else:
		soldier._face_direction(facing_direction, delta)
	soldier.set_formation_walking(true, soldier._independent_speed)
	return true


func get_current_independent_target(soldier) -> Variant:
	if not soldier._independent_path_points.is_empty():
		if soldier._independent_path_index >= soldier._independent_path_points.size():
			return null
		return get_offset_path_point(soldier, soldier._independent_path_index)
	if soldier._has_independent_target:
		return soldier._independent_target
	return null


func get_remaining_route_points(soldier, include_current_position: bool = true) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if include_current_position:
		points.append(soldier.global_position)
	if not soldier._independent_path_points.is_empty():
		for index: int in range(soldier._independent_path_index, soldier._independent_path_points.size()):
			points.append(get_offset_path_point(soldier, index))
	elif soldier._has_independent_target:
		points.append(soldier._independent_target)
	return _dedupe_route_points(points)


func advance_completed_path_targets(soldier) -> bool:
	if soldier._independent_path_points.is_empty():
		return false
	while soldier._independent_path_index < soldier._independent_path_points.size():
		var target: Vector3 = get_offset_path_point(soldier, soldier._independent_path_index)
		var to_target: Vector3 = target - soldier.global_position
		to_target.y = 0.0
		if to_target.length() > soldier._independent_arrival_radius:
			return true
		soldier._independent_path_index += 1
	return false


func get_offset_path_point(soldier, path_index: int) -> Vector3:
	var anchor: Vector3 = soldier._independent_path_points[clampi(path_index, 0, soldier._independent_path_points.size() - 1)]
	var direction := Vector3.FORWARD
	if soldier._independent_final_yaw_active and path_index >= soldier._independent_path_points.size() - 1:
		var final_basis := Basis(Vector3.UP, soldier._independent_final_yaw)
		var final_offset: Vector3 = final_basis * soldier._independent_slot_offset
		var final_target: Vector3 = anchor + final_offset
		final_target.y = soldier.global_position.y
		return final_target
	if soldier._independent_path_points.size() > 1:
		var next_index := mini(path_index + 1, soldier._independent_path_points.size() - 1)
		var previous_index := maxi(path_index - 1, 0)
		if next_index != path_index:
			direction = soldier._independent_path_points[next_index] - anchor
		else:
			direction = anchor - soldier._independent_path_points[previous_index]
		direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			direction = Vector3.FORWARD
		else:
			direction = direction.normalized()
	var yaw := atan2(-direction.x, -direction.z)
	var basis := Basis(Vector3.UP, yaw)
	var offset: Vector3 = basis * soldier._independent_slot_offset
	var target: Vector3 = anchor + offset
	target.y = soldier.global_position.y
	return target


func _dedupe_route_points(points: Array[Vector3]) -> Array[Vector3]:
	var deduped: Array[Vector3] = []
	for point: Vector3 in points:
		if deduped.is_empty() or deduped.back().distance_squared_to(point) > 0.01:
			deduped.append(point)
	return deduped


func _make_path_command_result(
	reachable: bool,
	failure_reason: StringName,
	resolved_destination: Vector3,
	points: Array
) -> Dictionary:
	return {
		"reachable": reachable,
		"failure_reason": failure_reason,
		"points": points,
		"resolved_destination": resolved_destination,
	}
