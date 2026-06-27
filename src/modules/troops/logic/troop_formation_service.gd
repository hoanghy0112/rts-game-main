extends "res://modules/troops/logic/troop_service.gd"
class_name TroopFormationService

var formation_strategy: Resource


func set_formation_strategy(strategy: Resource) -> void:
	formation_strategy = strategy


func get_formation_strategy() -> Resource:
	return formation_strategy


func physics_tick(delta: float) -> void:
	update_slots(delta)
	step_soldier_logic(delta)
	align_moving_soldiers()
	update_soldier_logic_sleeping(delta)
	step_child_mission_troops_for_manual_call(delta)


func update_slots(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_formation_soldier_slots(delta)


func step_soldier_logic(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._step_formation_soldier_logic(delta)


func align_moving_soldiers() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._align_moving_soldiers_to_frame_displacement()


func update_soldier_logic_sleeping(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_soldier_logic_sleeping(delta)


func step_child_mission_troops_for_manual_call(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	if not Engine.is_in_physics_frame():
		troop._step_child_mission_troops_for_manual_call(delta)


func rebuild_formation() -> void:
	var troop = _troop()
	if not troop:
		return

	troop._ensure_scene_nodes()
	troop._combat_soldier_targets.clear()
	troop._combat_soldier_target_statuses.clear()
	troop._combat_target_attackers.clear()
	troop._combat_soldier_offsets.clear()
	troop._combat_soldier_lock_positions.clear()
	troop._combat_soldier_shuffle_offsets.clear()
	troop._combat_soldier_shuffle_timers.clear()
	troop._combat_soldier_attack_timers.clear()
	troop._combat_visual_thrust_timers.clear()
	troop._combat_soldier_steering_cache.clear()
	troop._combat_soldier_spacing_refresh_times.clear()
	troop._combat_soldier_socket_indices.clear()
	troop._combat_soldier_socket_positions.clear()
	troop._combat_soldier_socket_directions.clear()
	troop._combat_soldier_move_targets.clear()
	troop._combat_touched_soldiers.clear()
	troop._combat_render_dirty_soldiers.clear()
	troop._soldier_motion_facing_positions.clear()
	troop._combat_attacker_spatial_rebuild_remaining = 0.0
	troop._combat_attacker_spatial_cached_count = -1
	troop._combat_defender_spatial_rebuild_remaining = 0.0
	troop._combat_defender_spatial_cached_count = -1
	troop._combat_defender_spatial_cached_enemy_id = 0
	troop._clear_formation_target_cache()
	troop._combat_assignment_cursor = 0
	troop._combat_update_cursor = 0
	troop._combat_visual_stance_cursor = 0
	troop._combat_source_corpse_count = 0
	troop._combat_scatter_active = false
	troop._survivor_rout_triggered = false
	troop._clear_children(troop._soldier_container)
	troop._invalidate_soldier_cache()

	var scene = troop.soldier_scene if troop.soldier_scene else troop.DEFAULT_SOLDIER_SCENE
	var columns: int = mini(maxi(troop.formation_columns, 1), troop.soldier_count)
	var rows: int = ceili(float(troop.soldier_count) / float(columns))
	for index: int in range(troop.soldier_count):
		var soldier = scene.instantiate()
		if not (soldier is Node3D):
			soldier.free()
			continue

		var spatial := soldier as Node3D
		spatial.name = "Soldier_%03d" % index
		troop._configure_visual_soldier(spatial, index)
		troop._soldier_container.add_child(spatial)
		spatial.owner = null
		var slot: Vector3 = troop._get_formation_slot_for_index(index, columns, rows)
		spatial.top_level = true
		spatial.global_position = troop._snap_world_point(troop._formation_slot_to_world(slot))
		spatial.set_meta(&"troop_formation_slot", slot)
		spatial.set_meta(&"troop_formation_index", index)
		spatial.set_meta(&"troop_formation_phase", float(index) * 1.618)
		spatial.rotation.y = troop.rotation.y
		troop._add_unit_selection_proxy(spatial)

		if troop.hand_flags_enabled:
			if index == 0:
				troop._attach_flag_to_soldier(spatial, "TeamFlag", troop.team_flag_color, troop.troop_flag_color)
			elif index == 1:
				troop._attach_flag_to_soldier(spatial, "TroopFlag", troop.troop_flag_color, troop.team_flag_color)

	troop._invalidate_soldier_cache()
	troop._refresh_soldier_batch_renderer_soldiers()
	troop._unit_selection_proxy_dirty = false
	troop._rebuild_management_flag()
	troop._update_hover_visuals()
	troop._update_formation_soldier_locomotion()
	troop._emit_destination_changed()


func slot_to_world(troop: Node, slot: Vector3) -> Vector3:
	return formation_strategy.slot_to_world(troop, slot)


func get_formation_position(troop: Node, index: int, columns: int, rows: int) -> Vector3:
	return formation_strategy.get_formation_position(troop, index, columns, rows)


func get_slot_for_index(troop: Node, index: int, columns: int, rows: int) -> Vector3:
	return formation_strategy.get_slot_for_index(troop, index, columns, rows)


func get_natural_offset(troop: Node, index: int, columns: int, rows: int) -> Vector3:
	return formation_strategy.get_natural_offset(troop, index, columns, rows)


func get_columns_for_width(troop: Node, width_m: float, active_count: int) -> int:
	return formation_strategy.get_columns_for_width(troop, width_m, active_count)


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
