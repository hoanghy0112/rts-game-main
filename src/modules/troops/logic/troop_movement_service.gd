extends "res://modules/troops/logic/troop_service.gd"
class_name TroopMovementService

const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")

var movement_logic: Resource
var _pending_soldier_move_commands: Array[Dictionary] = []


func set_movement_logic(logic: Resource) -> void:
	movement_logic = logic


func physics_tick(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	if troop._state == troop.STATE_MOVING:
		_process_pending_soldier_move_commands(troop)
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
	_pending_soldier_move_commands.clear()
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
		troop._clear_formation_motion_commands()
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
		troop._clear_formation_motion_commands()
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
	troop._route_visual_command_id += 1
	troop._manual_move_override_active = manual_command
	troop._set_state(troop.STATE_MOVING)
	troop._hold_scattered_positions_after_combat = false
	troop._regroup_scattered_positions_on_move = should_regroup_scattered_positions
	_queue_soldier_move_commands(troop)
	_process_pending_soldier_move_commands(troop)
	troop._update_route_visual()
	troop._prime_formation_motion_facing(troop._get_formation_path_direction(troop._get_moving_retarget_formation_path_index()))
	troop._emit_destination_changed()
	return true


func stop_movement() -> void:
	var troop = _troop()
	if not troop:
		return
	_pending_soldier_move_commands.clear()
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
	if not troop._has_destination:
		return
	troop._sync_movement_anchor_to_flag_point()
	troop._advance_reached_path_points()
	if troop._formation_destination_yaw_active:
		troop.rotation.y = troop._formation_destination_yaw
		troop._last_turn_delta = 0.0
		troop._last_turn_intensity = 0.0
	else:
		troop._last_turn_delta = 0.0
		troop._last_turn_intensity = 0.0
	troop._drain_soldier_endurance(troop._get_movement_endurance_loss_rate() * delta)
	troop._snap_to_surface()
	if _pending_soldier_move_commands.is_empty() and not _any_soldier_has_independent_motion(troop):
		troop._finish_movement()


func _queue_soldier_move_commands(troop: Node) -> void:
	_pending_soldier_move_commands.clear()
	var soldiers: Array = troop._get_active_soldiers()
	if soldiers.is_empty():
		return
	var yaw := float(troop.rotation.y)
	if troop._formation_destination_yaw_active:
		yaw = float(troop._formation_destination_yaw)
	var basis := Basis(Vector3.UP, yaw)
	var arrival := maxf(float(troop.arrival_radius) * 0.32, 0.18)
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("clear_independent_motion"):
			soldier_node.call("clear_independent_motion")
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var destination: Vector3 = troop._snap_world_point(troop._destination + basis * slot)
		_pending_soldier_move_commands.append({
			"soldier": soldier,
			"destination": destination,
			"speed": troop._get_soldier_slot_follow_speed(soldier),
			"arrival": arrival,
		})


func _process_pending_soldier_move_commands(troop: Node) -> void:
	if _pending_soldier_move_commands.is_empty():
		return
	var budget := _get_soldier_path_query_budget(troop)
	var processed := 0
	while processed < budget and not _pending_soldier_move_commands.is_empty():
		processed += 1
		var command: Dictionary = _pending_soldier_move_commands.pop_front()
		var soldier := command.get("soldier") as Node
		if not is_instance_valid(soldier) or not troop._is_soldier_active(soldier):
			continue
		if soldier.has_meta(&"troop_carrier_active"):
			continue
		var destination: Vector3 = command.get("destination", Vector3.ZERO)
		var speed := maxf(float(command.get("speed", 1.0)), 0.1)
		var arrival := maxf(float(command.get("arrival", 0.24)), 0.05)
		if soldier.has_method("set_independent_path_target"):
			soldier.call(
				"set_independent_path_target",
				destination,
				troop._movement_map,
				speed,
				arrival,
				troop.nearest_walkable_search_radius_cells,
				troop.path_smoothing_enabled,
				troop.path_corner_radius_cells,
				troop.path_corner_samples
			)
		elif soldier.has_method("set_independent_move_target"):
			soldier.call("set_independent_move_target", destination, speed, arrival)


func _get_soldier_path_query_budget(troop: Node) -> int:
	if troop and troop.has_method("_get_soldier_path_queries_per_tick"):
		return maxi(int(troop.call("_get_soldier_path_queries_per_tick")), 1)
	if troop and troop.get("soldier_path_queries_per_tick") != null:
		return maxi(int(troop.get("soldier_path_queries_per_tick")), 1)
	return 64


func _any_soldier_has_independent_motion(troop: Node) -> bool:
	for soldier: Node in troop._get_active_soldiers():
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			return true
	return false


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
