extends SceneTree

const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")

const SOLDIER_COUNT := 400
const FORMATION_COLUMNS := 20
const WARMUP_FRAMES := 20
const SAMPLE_FRAMES := 90
const MAX_TROOP_PHASE_PHYSICS_MS := 30.0
const MAX_SOLDIER_PHASE_PHYSICS_MS := 24.0
const MAX_IDLE_INDEPENDENT_MOTIONS := 0
const MAX_MOVING_FORMATION_TARGET_WRITES_PER_FRAME := SOLDIER_COUNT

var _original_max_fps := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_max_fps = Engine.max_fps
	Engine.max_fps = 0

	var failures: Array[String] = []
	var troop := _make_troop()
	root.add_child(troop)
	await process_frame
	await physics_frame

	if troop.has_method("get_soldier_count") and int(troop.call("get_soldier_count")) < SOLDIER_COUNT:
		failures.append("stress troop did not build the requested soldier count")
	if troop.has_method("get_soldier_perf_summary"):
		troop.set("soldier_perf_monitoring_enabled", true)
		troop.call("reset_soldier_perf_counters")
	else:
		failures.append("stress troop does not expose soldier perf instrumentation")

	if failures.is_empty():
		var idle_metrics := await _sample_phase("idle", troop)
		_assert_phase_budget("idle", idle_metrics, failures)
		var idle_independent_motions := int(idle_metrics.get("independent_motion_count", 0))
		if idle_independent_motions > MAX_IDLE_INDEPENDENT_MOTIONS:
			failures.append("idle formation kept %d soldiers in independent motion after settling" % idle_independent_motions)
		var idle_sleeping_soldiers := int(idle_metrics.get("logic_sleeping_soldier_count", 0))
		if idle_sleeping_soldiers < SOLDIER_COUNT:
			failures.append("idle formation should sleep all settled soldiers; sleeping=%d/%d" % [idle_sleeping_soldiers, SOLDIER_COUNT])
		if not bool(troop.call("set_move_destination", Vector3(42.5, 0.0, 7.5))):
			failures.append("stress troop should accept a reachable movement destination")
		else:
			var moving_metrics := await _sample_phase("moving", troop)
			_assert_phase_budget("moving", moving_metrics, failures)
			var moving_writes_per_frame := float(moving_metrics.get("formation_target_write_count", 0)) / float(SAMPLE_FRAMES)
			if moving_writes_per_frame >= float(MAX_MOVING_FORMATION_TARGET_WRITES_PER_FRAME):
				failures.append("moving formation wrote %.2f targets/frame; expected less than soldier count per frame" % moving_writes_per_frame)
			var pair_budget_total := int(troop.get("formation_pair_checks_budget_per_tick")) * SAMPLE_FRAMES
			if int(moving_metrics.get("moving_formation_pair_checks", 0)) > pair_budget_total:
				failures.append("moving formation pair checks exceeded budget window")
			troop.call("clear_destination")
			troop.call("_settle_soldiers_at_current_formation_slots")
		_set_synthetic_combat_pose(troop, true)
		var combat_metrics := await _sample_phase("combat_pose", troop)
		_assert_phase_budget("combat_pose", combat_metrics, failures)

	Engine.max_fps = _original_max_fps
	if failures.is_empty():
		print("Troop perf stress check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _make_troop() -> Node3D:
	var troop := TroopScene.instantiate() as Node3D
	troop.name = "StressTroop"
	troop.set("troop_id", &"stress_troop")
	troop.set("display_name", "Stress Troop")
	troop.set("team_id", &"player")
	troop.set("soldier_count", SOLDIER_COUNT)
	troop.set("formation_columns", FORMATION_COLUMNS)
	troop.set("troop_perf_monitoring_enabled", true)
	troop.set("soldier_perf_monitoring_enabled", false)
	troop.set("carried_food_kg", 1000.0)
	troop.set("movement_map", _make_map(64, 64))
	troop.position = Vector3(1.5, 0.0, 1.5)
	return troop


func _make_map(width: int, height: int) -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2.ZERO
	data.cell_size_meters = 1.0
	data.resize_map(width, height, 1.0, 0)
	return data


func _sample_phase(label: String, troop: Node) -> Dictionary:
	for _index: int in range(WARMUP_FRAMES):
		await physics_frame
	if troop.has_method("reset_perf_debug_counters"):
		troop.call("reset_perf_debug_counters")
	elif troop.has_method("reset_soldier_perf_counters"):
		troop.call("reset_soldier_perf_counters")

	var total_process_ms := 0.0
	var total_physics_ms := 0.0
	var max_process_ms := 0.0
	var max_physics_ms := 0.0
	for _index: int in range(SAMPLE_FRAMES):
		await physics_frame
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total_process_ms += process_ms
		total_physics_ms += physics_ms
		max_process_ms = maxf(max_process_ms, process_ms)
		max_physics_ms = maxf(max_physics_ms, physics_ms)

	var troop_summary := troop.call("get_troop_summary") as Dictionary
	var soldier_perf := troop.call("get_soldier_perf_summary") as Dictionary
	var sampled := int(soldier_perf.get("sampled_soldier_count", 0))
	var last_soldier_physics_ms := float(soldier_perf.get("last_physics_total_usec", 0)) / 1000.0
	var max_soldier_physics_ms := float(soldier_perf.get("max_physics_usec", 0)) / 1000.0
	var last_soldier_pose_ms := float(soldier_perf.get("last_pose_total_usec", 0)) / 1000.0
	var max_soldier_pose_ms := float(soldier_perf.get("max_pose_usec", 0)) / 1000.0
	var independent_motion_count := _count_independent_motions(troop)
	var render_sync_ms := float(troop_summary.get("soldier_render_last_sync_ms", 0.0))
	var render_sync_max_ms := float(troop_summary.get("soldier_render_max_sync_ms", 0.0))
	var render_writes := int(troop_summary.get("soldier_render_last_transform_writes", 0))
	var render_max_writes := int(troop_summary.get("soldier_render_max_transform_writes", 0))
	var render_reads := int(troop_summary.get("soldier_render_last_source_reads", 0))
	var render_cached_sources := int(troop_summary.get("soldier_render_cached_source_mesh_count", 0))
	var formation_writes := int(troop_summary.get("formation_target_write_count", 0))
	var formation_skips := int(troop_summary.get("formation_target_skip_count", 0))
	var moving_pair_checks := int(troop_summary.get("moving_formation_pair_checks", 0))
	var spatial_rebuilds := int(troop_summary.get("spatial_grid_rebuilds", 0))
	var socket_clamps := int(troop_summary.get("combat_socket_clamp_count", 0))
	var sleeping_soldiers := int(troop_summary.get("logic_sleeping_soldier_count", 0))
	var line := (
		"[PERF] phase=%s frames=%d avg_process_ms=%.3f max_process_ms=%.3f avg_physics_ms=%.3f max_physics_ms=%.3f "
		+ "troop_last_physics_ms=%.3f troop_max_physics_ms=%.3f soldier_sampled=%d soldier_last_physics_ms=%.3f "
		+ "soldier_max_single_physics_ms=%.3f soldier_last_pose_ms=%.3f soldier_max_single_pose_ms=%.3f "
		+ "independent_motions=%d render_sync_ms=%.3f render_sync_max_ms=%.3f render_writes=%d render_max_writes=%d "
		+ "render_reads=%d render_cached_sources=%d formation_writes=%d formation_skips=%d moving_pair_checks=%d "
		+ "spatial_rebuilds=%d socket_clamps=%d sleeping_soldiers=%d cache_rebuilds=%d "
		+ "target_scans=%d pair_checks=%d nodes=%d physics3d_active=%d"
	) % [
		String(label),
		SAMPLE_FRAMES,
		total_process_ms / float(SAMPLE_FRAMES),
		max_process_ms,
		total_physics_ms / float(SAMPLE_FRAMES),
		max_physics_ms,
		float(troop_summary.get("perf_last_physics_usec", 0)) / 1000.0,
		float(troop_summary.get("perf_max_physics_usec", 0)) / 1000.0,
		sampled,
		last_soldier_physics_ms,
		max_soldier_physics_ms,
		last_soldier_pose_ms,
		max_soldier_pose_ms,
		independent_motion_count,
		render_sync_ms,
		render_sync_max_ms,
		render_writes,
		render_max_writes,
		render_reads,
		render_cached_sources,
		formation_writes,
		formation_skips,
		moving_pair_checks,
		spatial_rebuilds,
		socket_clamps,
		sleeping_soldiers,
		int(troop_summary.get("combat_perf_active_cache_rebuilds", 0)),
		int(troop_summary.get("combat_perf_target_candidate_scans", 0)),
		int(troop_summary.get("combat_perf_separation_pair_checks", 0)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
	]
	print(line)
	return {
		"avg_process_ms": total_process_ms / float(SAMPLE_FRAMES),
		"max_process_ms": max_process_ms,
		"avg_physics_ms": total_physics_ms / float(SAMPLE_FRAMES),
		"max_physics_ms": max_physics_ms,
		"troop_last_physics_ms": float(troop_summary.get("perf_last_physics_usec", 0)) / 1000.0,
		"troop_max_physics_ms": float(troop_summary.get("perf_max_physics_usec", 0)) / 1000.0,
		"soldier_last_physics_ms": last_soldier_physics_ms,
		"soldier_max_single_physics_ms": max_soldier_physics_ms,
		"soldier_last_pose_ms": last_soldier_pose_ms,
		"soldier_max_single_pose_ms": max_soldier_pose_ms,
		"independent_motion_count": independent_motion_count,
		"render_sync_ms": render_sync_ms,
		"render_sync_max_ms": render_sync_max_ms,
		"render_writes": render_writes,
		"render_max_writes": render_max_writes,
		"render_reads": render_reads,
		"render_cached_sources": render_cached_sources,
		"formation_target_write_count": formation_writes,
		"formation_target_skip_count": formation_skips,
		"moving_formation_pair_checks": moving_pair_checks,
		"spatial_grid_rebuilds": spatial_rebuilds,
		"combat_socket_clamp_count": socket_clamps,
		"logic_sleeping_soldier_count": sleeping_soldiers,
	}


func _assert_phase_budget(label: String, metrics: Dictionary, failures: Array[String]) -> void:
	var troop_max_physics_ms := float(metrics.get("troop_max_physics_ms", 0.0))
	if troop_max_physics_ms > MAX_TROOP_PHASE_PHYSICS_MS:
		failures.append(
			"%s troop physics exceeded %.1fms budget: %.3fms"
			% [label, MAX_TROOP_PHASE_PHYSICS_MS, troop_max_physics_ms]
		)
	var soldier_last_physics_ms := float(metrics.get("soldier_last_physics_ms", 0.0))
	if soldier_last_physics_ms > MAX_SOLDIER_PHASE_PHYSICS_MS:
		failures.append(
			"%s sampled soldier physics exceeded %.1fms budget: %.3fms"
			% [label, MAX_SOLDIER_PHASE_PHYSICS_MS, soldier_last_physics_ms]
		)


func _count_independent_motions(troop: Node) -> int:
	var soldiers := troop.get_node_or_null("Soldiers")
	if not soldiers:
		return 0
	var count := 0
	for soldier: Node in soldiers.get_children():
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			count += 1
	return count


func _set_synthetic_combat_pose(troop: Node, active: bool) -> void:
	if troop.has_method("_set_state"):
		troop.call("_set_state", &"fighting" if active else &"idle")
	var soldiers := troop.get_node_or_null("Soldiers")
	if not soldiers:
		return
	for soldier: Node in soldiers.get_children():
		if soldier.has_method("set_independent_combat"):
			soldier.call("set_independent_combat", active, null, true)
