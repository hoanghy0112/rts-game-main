extends "res://modules/troops/logic/troop_service.gd"
class_name TroopCombatService

var combat_positioning_logic: Resource


func set_combat_positioning_logic(logic: Resource) -> void:
	combat_positioning_logic = logic


func physics_tick(delta: float) -> void:
	update_perf_rate_window(delta)
	update_ai(delta)
	update_soldier_animation(delta)
	maybe_emit_changed(delta)
	update_debug_lines()


func update_perf_rate_window(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_combat_perf_rate_window(delta)


func update_ai(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_combat_ai(delta)


func update_soldier_animation(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_combat_soldier_animation(delta)


func maybe_emit_changed(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._maybe_emit_combat_changed(delta)


func update_debug_lines() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_combat_debug_lines()


func command_attack_troop(enemy: Node) -> bool:
	var troop = _troop()
	if not troop:
		return false
	if not troop._is_valid_enemy(enemy):
		return false
	if troop.is_mission_troop and troop._is_mission_active():
		troop._mission_paused = true
	troop._manual_attack_target = enemy
	troop._active_enemy = enemy
	troop._manual_move_override_active = false
	troop._chase_repath_remaining = 0.0
	troop._engagement_windup_remaining = 0.0
	troop._engagement_zone_check_remaining = 0.0
	troop._engagement_zone_cached_enemy_id = 0
	troop._engagement_zone_cached_result = false
	troop._last_target_instance_id = enemy.get_instance_id()
	troop._combat_logic_accumulator = 0.0
	troop._combat_target_reassign_remaining = 0.0
	troop._clear_independent_combat(true)
	troop._regroup_scattered_positions_on_move = false
	if not troop._is_enemy_inside_engagement_zone(enemy):
		return troop._repath_to_attack_target(enemy)
	troop._clear_formation_motion_commands()
	troop._hold_scattered_positions_after_combat = false
	troop._clear_route_visual()
	troop._set_state(troop.STATE_FIGHTING)
	troop._emit_combat_changed()
	return true


func get_soldier_engagement_position(troop: Node, attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	return combat_positioning_logic.get_soldier_engagement_position(troop, attacker, defender, index, total)


func get_combat_socket_direction(troop: Node, attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	return combat_positioning_logic.get_combat_socket_direction(troop, attacker, defender, index, total)


func make_combat_socket_direction(troop: Node, attacker: Node3D, defender: Node3D, socket_index: int, total: int) -> Vector3:
	return combat_positioning_logic.make_combat_socket_direction(troop, attacker, defender, socket_index, total)


func get_combat_surround_slot_angle(slot: int, max_slots: int) -> float:
	return combat_positioning_logic.get_combat_surround_slot_angle(slot, max_slots)


func get_combat_offset_for_soldier(troop: Node, attacker: Node3D, index: int, total: int) -> Vector2:
	return combat_positioning_logic.get_combat_offset_for_soldier(troop, attacker, index, total)


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
