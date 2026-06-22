extends SceneTree

const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")

const SOLDIERS_PER_SIDE := 500
const FORMATION_COLUMNS := 25
const WARMUP_FRAMES := 20
const FIGHTING_TIMEOUT_FRAMES := 900
const SAMPLE_FRAMES := 120
const MAX_SOLDIER_STEP_M := 0.75

var _original_max_fps := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_max_fps = Engine.max_fps
	Engine.max_fps = 0

	var failures: Array[String] = []
	var movement_map := _make_map(192, 128)
	var player := _make_troop(&"profile_500_player", &"player", Vector3(74.0, 0.0, 64.0), movement_map)
	var enemy := _make_troop(&"profile_500_enemy", &"enemy", Vector3(118.0, 0.0, 64.0), movement_map)
	root.add_child(player)
	root.add_child(enemy)
	await _wait_frames(WARMUP_FRAMES)

	if player.has_method("command_attack_troop"):
		player.call("command_attack_troop", enemy)
	if enemy.has_method("command_attack_troop"):
		enemy.call("command_attack_troop", player)

	var reached_fighting := await _wait_for_fighting(player, enemy)
	if not reached_fighting:
		failures.append("500v500 profile did not reach fighting state")
	else:
		_reset_perf(player)
		_reset_perf(enemy)
		var metrics := await _sample_combat(player, enemy)
		print("[PROFILE_500V500] ", JSON.stringify(metrics))
		if int(metrics.get("player_render_sync_count", 0)) <= 0 or int(metrics.get("enemy_render_sync_count", 0)) <= 0:
			failures.append("500v500 active combat did not sync dirty soldier transforms")
		if float(metrics.get("max_soldier_step_m", 0.0)) > MAX_SOLDIER_STEP_M:
			failures.append(
				"500v500 combat step %.3fm exceeded %.3fm"
				% [float(metrics.get("max_soldier_step_m", 0.0)), MAX_SOLDIER_STEP_M]
			)

	Engine.max_fps = _original_max_fps
	if failures.is_empty():
		print("Troop 500v500 combat profile completed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _make_troop(troop_id: StringName, team_id: StringName, position: Vector3, movement_map: Resource) -> Node3D:
	var troop := TroopScene.instantiate() as Node3D
	troop.name = String(troop_id)
	troop.set("troop_id", troop_id)
	troop.set("display_name", String(troop_id))
	troop.set("team_id", team_id)
	troop.set("controllable", team_id == &"player")
	troop.set("soldier_count", SOLDIERS_PER_SIDE)
	troop.set("formation_columns", FORMATION_COLUMNS)
	troop.set("movement_map", movement_map)
	troop.set("movement_speed_mps", 5.4)
	troop.set("formation_slot_follow_speed", 6.2)
	troop.set("detection_range_m", 120.0)
	troop.set("defensive_engagement_range_m", 80.0)
	troop.set("combat_range_m", 80.0)
	troop.set("combat_spear_range_m", 9.4)
	troop.set("attack_engagement_delay", 0.0)
	troop.set("defensive_engagement_delay", 0.0)
	troop.set("combat_logic_interval", 0.16)
	troop.set("troop_perf_monitoring_enabled", true)
	troop.set("soldier_perf_monitoring_enabled", false)
	troop.set("survivor_rout_enabled", false)
	troop.set("carried_food_kg", 2000.0)
	troop.position = position
	return troop


func _make_map(width: int, height: int) -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2.ZERO
	data.cell_size_meters = 1.0
	data.resize_map(width, height, 1.0, 0)
	return data


func _wait_for_fighting(player: Node, enemy: Node) -> bool:
	for _index: int in range(FIGHTING_TIMEOUT_FRAMES):
		await _wait_frames(1)
		if _get_troop_state(player) == &"fighting" and _get_troop_state(enemy) == &"fighting":
			return true
	return false


func _sample_combat(player: Node, enemy: Node) -> Dictionary:
	var previous_positions := _get_soldier_positions(player)
	var total_process_ms := 0.0
	var total_physics_ms := 0.0
	var max_process_ms := 0.0
	var max_physics_ms := 0.0
	var max_soldier_step := 0.0
	var max_step_detail := {}
	for frame_index: int in range(SAMPLE_FRAMES):
		await _wait_frames(1)
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total_process_ms += process_ms
		total_physics_ms += physics_ms
		max_process_ms = maxf(max_process_ms, process_ms)
		max_physics_ms = maxf(max_physics_ms, physics_ms)
		var current_positions := _get_soldier_positions(player)
		for soldier: Node3D in current_positions.keys():
			var previous_variant: Variant = previous_positions.get(soldier)
			if not (previous_variant is Vector3):
				continue
			var delta_position: Vector3 = current_positions[soldier] - (previous_variant as Vector3)
			delta_position.y = 0.0
			var step_distance := delta_position.length()
			if step_distance > max_soldier_step:
				max_soldier_step = step_distance
				max_step_detail = _make_step_detail(player, soldier, previous_variant as Vector3, current_positions[soldier], frame_index)
		previous_positions = current_positions

	var player_summary := _get_summary(player)
	var enemy_summary := _get_summary(enemy)
	return {
		"frames": SAMPLE_FRAMES,
		"avg_process_ms": total_process_ms / float(SAMPLE_FRAMES),
		"max_process_ms": max_process_ms,
		"avg_physics_ms": total_physics_ms / float(SAMPLE_FRAMES),
		"max_physics_ms": max_physics_ms,
		"fps": Engine.get_frames_per_second(),
		"max_soldier_step_m": max_soldier_step,
		"max_step_detail": max_step_detail,
		"player_troop_max_physics_ms": float(player_summary.get("perf_max_physics_usec", 0.0)) / 1000.0,
		"enemy_troop_max_physics_ms": float(enemy_summary.get("perf_max_physics_usec", 0.0)) / 1000.0,
		"player_combat_tick_max_ms": float(player_summary.get("perf_max_combat_tick_usec", 0.0)) / 1000.0,
		"enemy_combat_tick_max_ms": float(enemy_summary.get("perf_max_combat_tick_usec", 0.0)) / 1000.0,
		"player_combat_collect_max_ms": float(player_summary.get("perf_max_combat_collect_usec", 0.0)) / 1000.0,
		"enemy_combat_collect_max_ms": float(enemy_summary.get("perf_max_combat_collect_usec", 0.0)) / 1000.0,
		"player_combat_spatial_max_ms": float(player_summary.get("perf_max_combat_spatial_usec", 0.0)) / 1000.0,
		"enemy_combat_spatial_max_ms": float(enemy_summary.get("perf_max_combat_spatial_usec", 0.0)) / 1000.0,
		"player_combat_assign_max_ms": float(player_summary.get("perf_max_combat_assign_usec", 0.0)) / 1000.0,
		"enemy_combat_assign_max_ms": float(enemy_summary.get("perf_max_combat_assign_usec", 0.0)) / 1000.0,
		"player_combat_motion_max_ms": float(player_summary.get("perf_max_combat_motion_usec", 0.0)) / 1000.0,
		"enemy_combat_motion_max_ms": float(enemy_summary.get("perf_max_combat_motion_usec", 0.0)) / 1000.0,
		"player_summary_max_ms": float(player_summary.get("perf_max_combat_summary_usec", 0.0)) / 1000.0,
		"enemy_summary_max_ms": float(enemy_summary.get("perf_max_combat_summary_usec", 0.0)) / 1000.0,
		"player_render_sync_max_ms": float(player_summary.get("soldier_render_max_sync_ms", 0.0)),
		"enemy_render_sync_max_ms": float(enemy_summary.get("soldier_render_max_sync_ms", 0.0)),
		"player_render_sync_last_ms": float(player_summary.get("soldier_render_last_sync_ms", 0.0)),
		"enemy_render_sync_last_ms": float(enemy_summary.get("soldier_render_last_sync_ms", 0.0)),
		"player_render_sync_count": int(player_summary.get("soldier_render_sync_count", 0)),
		"enemy_render_sync_count": int(enemy_summary.get("soldier_render_sync_count", 0)),
		"player_render_writes": int(player_summary.get("soldier_render_max_transform_writes", 0)),
		"enemy_render_writes": int(enemy_summary.get("soldier_render_max_transform_writes", 0)),
		"player_render_last_writes": int(player_summary.get("soldier_render_last_transform_writes", 0)),
		"enemy_render_last_writes": int(enemy_summary.get("soldier_render_last_transform_writes", 0)),
		"player_render_last_reads": int(player_summary.get("soldier_render_last_source_reads", 0)),
		"enemy_render_last_reads": int(enemy_summary.get("soldier_render_last_source_reads", 0)),
		"player_render_sync_skips": int(player_summary.get("soldier_render_sync_skip_count", 0)),
		"enemy_render_sync_skips": int(enemy_summary.get("soldier_render_sync_skip_count", 0)),
		"player_render_dirty": int(player_summary.get("combat_render_dirty_soldier_count", 0)),
		"enemy_render_dirty": int(enemy_summary.get("combat_render_dirty_soldier_count", 0)),
		"player_pair_checks": int(player_summary.get("combat_perf_separation_pair_checks", 0)),
		"enemy_pair_checks": int(enemy_summary.get("combat_perf_separation_pair_checks", 0)),
		"player_steering": int(player_summary.get("combat_perf_steering_updates", 0)),
		"enemy_steering": int(enemy_summary.get("combat_perf_steering_updates", 0)),
		"player_target_scans": int(player_summary.get("combat_perf_target_candidate_scans", 0)),
		"enemy_target_scans": int(enemy_summary.get("combat_perf_target_candidate_scans", 0)),
		"player_spatial_rebuilds": int(player_summary.get("spatial_grid_rebuilds", 0)),
		"enemy_spatial_rebuilds": int(enemy_summary.get("spatial_grid_rebuilds", 0)),
		"player_sleeping_soldiers": int(player_summary.get("logic_sleeping_soldier_count", 0)),
		"enemy_sleeping_soldiers": int(enemy_summary.get("logic_sleeping_soldier_count", 0)),
		"player_assigned_targets": int(player_summary.get("combat_assigned_target_count", 0)),
		"enemy_assigned_targets": int(enemy_summary.get("combat_assigned_target_count", 0)),
		"player_locked_attackers": int(player_summary.get("combat_locked_attacker_count", 0)),
		"enemy_locked_attackers": int(enemy_summary.get("combat_locked_attacker_count", 0)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}


func _make_step_detail(troop: Node, soldier: Node3D, previous_position: Vector3, current_position: Vector3, frame_index: int) -> Dictionary:
	var detail := {
		"frame": frame_index,
		"soldier": soldier.name,
		"previous": _round_vector(previous_position),
		"current": _round_vector(current_position),
		"has_independent_motion": false,
		"has_combat_lock": false,
		"lock_distance_m": 0.0,
		"slot": Vector3.ZERO,
	}
	if soldier.has_method("has_independent_motion"):
		detail["has_independent_motion"] = bool(soldier.call("has_independent_motion"))
	if soldier.has_method("get_independent_motion_debug_summary"):
		detail["independent_motion"] = soldier.call("get_independent_motion_debug_summary")
	if soldier.has_meta(&"troop_formation_slot"):
		detail["slot"] = _round_vector(soldier.get_meta(&"troop_formation_slot", Vector3.ZERO))
	if troop.has_method("has_combat_lock_for_soldier"):
		var has_lock := bool(troop.call("has_combat_lock_for_soldier", soldier))
		detail["has_combat_lock"] = has_lock
		if has_lock and troop.has_method("get_combat_lock_position_for_soldier"):
			var lock_position: Vector3 = troop.call("get_combat_lock_position_for_soldier", soldier)
			var lock_delta := current_position - lock_position
			lock_delta.y = 0.0
			detail["lock_position"] = _round_vector(lock_position)
			detail["lock_distance_m"] = lock_delta.length()
	return detail


func _round_vector(value: Vector3) -> Vector3:
	return Vector3(
		snappedf(value.x, 0.001),
		snappedf(value.y, 0.001),
		snappedf(value.z, 0.001)
	)


func _wait_frames(frames: int) -> void:
	for _index: int in range(frames):
		await process_frame
		await physics_frame


func _reset_perf(troop: Node) -> void:
	if troop.has_method("reset_perf_debug_counters"):
		troop.call("reset_perf_debug_counters")


func _get_troop_state(troop: Node) -> StringName:
	return StringName(_get_summary(troop).get("state", &""))


func _get_summary(troop: Node) -> Dictionary:
	if troop and troop.has_method("get_troop_summary"):
		return troop.call("get_troop_summary") as Dictionary
	return {}


func _get_soldier_positions(troop: Node) -> Dictionary:
	var positions := {}
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return positions
	for soldier_node: Node in soldiers.get_children():
		if soldier_node is Node3D and _is_soldier_alive(soldier_node):
			var soldier := soldier_node as Node3D
			positions[soldier] = soldier.global_position
	return positions


func _is_soldier_alive(soldier: Node) -> bool:
	if soldier.has_method("is_alive"):
		return bool(soldier.call("is_alive"))
	return true
