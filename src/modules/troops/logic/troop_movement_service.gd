extends "res://modules/troops/logic/troop_service.gd"
class_name TroopMovementService

const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")

var movement_logic: Resource


func set_movement_logic(logic: Resource) -> void:
	movement_logic = logic


func physics_tick(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	if troop._state == troop.STATE_MOVING:
		follow_path(delta)
		troop._route_refresh_remaining -= delta
		if troop._route_refresh_remaining <= 0.0:
			troop._route_refresh_remaining = maxf(troop.route_refresh_interval, 0.05)
			troop._update_route_visual()
	else:
		troop._last_turn_delta = 0.0
		troop._last_turn_intensity = 0.0


func set_move_destination(world_position: Vector3, manual_command: bool = true) -> bool:
	var troop = _troop()
	if not troop:
		return false
	var was_moving_with_destination: bool = troop._state == troop.STATE_MOVING and troop._has_destination and not troop._path_points.is_empty()
	var should_regroup_scattered_positions: bool = manual_command and troop._hold_scattered_positions_after_combat
	if manual_command:
		if troop.is_mission_troop and troop._is_mission_active() and not troop._mission_internal_command:
			troop._mission_paused = true
		troop._manual_attack_target = null
		troop._clear_independent_combat(true)
		should_regroup_scattered_positions = should_regroup_scattered_positions or troop._hold_scattered_positions_after_combat
		troop._hold_scattered_positions_after_combat = false
		troop._sync_movement_anchor_to_flag_point()
	troop._load_movement_map()
	if not troop._movement_map:
		troop._last_path_result = MovementMapPathfinderScript.find_path(null, troop.global_position, world_position)
		troop._set_state(troop.STATE_BLOCKED)
		if not troop._explicit_formation_destination_yaw_for_next_move:
			troop._formation_destination_yaw_active = false
		troop._manual_move_override_active = false
		troop._emit_destination_changed()
		return false

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		troop._movement_map,
		troop.global_position,
		world_position,
		maxf(troop._get_current_movement_speed_mps(), 0.1),
		troop.nearest_walkable_search_radius_cells,
		troop.path_smoothing_enabled,
		troop.path_corner_radius_cells,
		troop.path_corner_samples
	)
	troop._last_path_result = result
	if not bool(result.get("reachable", false)):
		troop._path_points.clear()
		troop._current_path_index = 0
		troop._has_destination = false
		if not troop._explicit_formation_destination_yaw_for_next_move:
			troop._formation_destination_yaw_active = false
		troop._clear_route_visual()
		troop._set_state(troop.STATE_BLOCKED)
		troop._manual_move_override_active = false
		troop._emit_destination_changed()
		return false

	troop._path_points = troop._snap_path_points(result.get("points", []) as Array)
	troop._current_path_index = 1 if troop._path_points.size() > 1 else 0
	troop._destination = troop._snap_world_point(result.get("resolved_destination", world_position) as Vector3)
	troop._refresh_active_formation_slot_metas()
	var had_explicit_formation_yaw: bool = troop._formation_destination_yaw_active
	if manual_command:
		if troop._explicit_formation_destination_yaw_for_next_move and troop._formation_destination_yaw_active:
			var reassignment_path_index: int = troop._get_moving_retarget_formation_path_index()
			troop._prepare_formation_for_manual_move_command(reassignment_path_index)
		elif not troop._explicit_formation_destination_yaw_for_next_move and had_explicit_formation_yaw:
			troop._formation_destination_yaw_active = false
			var override_path_index: int = troop._get_moving_retarget_formation_path_index()
			troop._set_formation_anchor_yaw_for_command(troop._get_yaw_for_direction(troop._get_formation_path_direction(override_path_index)))
			troop._last_turn_delta = 0.0
			troop._last_turn_intensity = 0.0
		elif not troop._explicit_formation_destination_yaw_for_next_move:
			troop._formation_destination_yaw_active = false
	elif not troop._explicit_formation_destination_yaw_for_next_move:
		troop._formation_destination_yaw_active = false
	troop._has_destination = true
	troop._route_refresh_remaining = 0.0
	troop._manual_move_override_active = manual_command
	troop._update_route_visual()
	troop._set_state(troop.STATE_MOVING)
	troop._hold_scattered_positions_after_combat = false
	troop._regroup_scattered_positions_on_move = should_regroup_scattered_positions
	troop._issue_formation_path_to_soldiers(was_moving_with_destination)
	troop._prime_formation_motion_facing(troop._get_formation_path_direction(troop._get_moving_retarget_formation_path_index()))
	troop._emit_destination_changed()
	return true


func stop_movement() -> void:
	var troop = _troop()
	if not troop:
		return
	if troop.is_mission_troop and troop._is_mission_active() and not troop._mission_internal_command:
		troop._mission_paused = true
	troop._manual_attack_target = null
	troop._path_points.clear()
	troop._current_path_index = 0
	troop._has_destination = false
	troop._manual_move_override_active = false
	troop._last_path_result.clear()
	troop._clear_route_visual()
	troop._clear_formation_motion_commands()
	troop._hold_scattered_positions_after_combat = false
	troop._regroup_scattered_positions_on_move = false
	troop._set_state(troop.STATE_IDLE)
	troop._emit_destination_changed()


func set_formation_destination(
	world_center: Vector3,
	right_axis: Vector3,
	width_m: float,
	manual_command: bool = true
) -> bool:
	var troop = _troop()
	if not troop:
		return false
	var horizontal_right := right_axis
	horizontal_right.y = 0.0
	if horizontal_right.length_squared() <= 0.0001:
		return set_move_destination(world_center, manual_command)

	horizontal_right = horizontal_right.normalized()
	var previous_columns: int = troop.formation_columns
	var next_columns: int = troop._get_formation_columns_for_width(width_m)
	troop._set_formation_columns_preserving_soldiers(next_columns)
	troop._formation_destination_yaw = troop._get_yaw_for_formation_right_axis(horizontal_right)
	troop._formation_destination_yaw_active = true

	troop._explicit_formation_destination_yaw_for_next_move = true
	var accepted := set_move_destination(world_center, manual_command)
	troop._explicit_formation_destination_yaw_for_next_move = false
	if not accepted:
		troop._formation_destination_yaw_active = false
		troop._set_formation_columns_preserving_soldiers(previous_columns)
	return accepted


func follow_path(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	if troop._current_path_index >= troop._path_points.size():
		troop._finish_movement()
		return

	var previous_transform: Transform3D = troop.global_transform
	troop._advance_reached_path_points()
	if troop._current_path_index >= troop._path_points.size():
		troop._finish_movement()
		return

	var target: Vector3 = troop._get_route_steering_target()
	var to_target: Vector3 = target - troop.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance <= 0.001:
		target = troop._path_points[troop._current_path_index]
		to_target = target - troop.global_position
		to_target.y = 0.0
		distance = to_target.length()
		if distance <= 0.001:
			return

	var direction: Vector3 = to_target / distance
	var turn_multiplier := 1.0
	if troop._formation_destination_yaw_active:
		troop.rotation.y = troop._formation_destination_yaw
		troop._last_turn_delta = 0.0
		troop._last_turn_intensity = 0.0
	else:
		troop._last_turn_delta = 0.0
		troop._last_turn_intensity = 0.0
	var move_delta := minf(maxf(delta, 0.0), 0.05)
	var current_speed: float = troop._get_current_movement_speed_mps()
	troop.global_position += direction * minf(current_speed * turn_multiplier * move_delta, distance)
	troop._drain_soldier_endurance(troop._get_movement_endurance_loss_rate() * delta)
	troop._snap_to_surface()
	troop._carry_formation_soldiers_between_transforms(previous_transform, troop.global_transform)
	troop._advance_reached_path_points()
	if troop._current_path_index >= troop._path_points.size():
		troop._finish_movement()


func get_current_movement_speed_mps(troop: Node) -> float:
	return movement_logic.get_current_movement_speed_mps(troop)


func get_soldier_path_speed(troop: Node, soldier: Node) -> float:
	return movement_logic.get_soldier_path_speed(troop, soldier)


func get_soldier_slot_follow_speed(troop: Node, soldier: Node) -> float:
	return movement_logic.get_soldier_slot_follow_speed(troop, soldier)


func get_formation_path_follow_speed(troop: Node) -> float:
	return movement_logic.get_formation_path_follow_speed(troop)


func get_idle_formation_slot_speed(troop: Node, soldier: Node) -> float:
	return movement_logic.get_idle_formation_slot_speed(troop, soldier)


func get_movement_endurance_loss_rate(troop: Node) -> float:
	return movement_logic.get_movement_endurance_loss_rate(troop)


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
