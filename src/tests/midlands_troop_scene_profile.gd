extends SceneTree

const MIDLANDS_SCENE: PackedScene = preload("res://maps/midlands/midlands.tscn")

const WARMUP_FRAMES := 24
const PHASE_WARMUP_FRAMES := 20
const SAMPLE_FRAMES := 120
const COMBAT_SNAPSHOT_FRAMES := 120
const COMBAT_END_TIMEOUT_FRAMES := 10800
const ARRIVAL_TIMEOUT_FRAMES := 720
const SCENE_SETTLE_TIMEOUT_FRAMES := 1800
const SCENE_SETTLE_STABLE_FRAMES := 90
const FACING_ERROR_DEGREES := 70.0
const JUMP_DISTANCE_M := 0.45

var _original_max_fps := 0
var _scene: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_max_fps = Engine.max_fps
	Engine.max_fps = 0

	var failures: Array[String] = []
	var scene := MIDLANDS_SCENE.instantiate()
	_scene = scene
	root.add_child(scene)
	await _wait_for_scene_runtime_settled(scene)
	await _wait_frames(WARMUP_FRAMES)
	await _check_midlands_forest_culling(scene, failures)

	var player := scene.get_node_or_null("Troop_01")
	var spawner := scene.get_node_or_null("EnemyTroopSpawner")
	var enemies: Array[Node] = []
	if spawner and spawner.has_method("spawn_enemies"):
		var spawned_variant: Variant = spawner.call("spawn_enemies")
		if spawned_variant is Array:
			enemies = spawned_variant as Array[Node]
	await _wait_frames(WARMUP_FRAMES)
	if enemies.is_empty() and spawner and spawner.has_method("get_spawned_troops"):
		var spawned_variant: Variant = spawner.call("get_spawned_troops")
		if spawned_variant is Array:
			enemies = spawned_variant as Array[Node]

	if not player:
		failures.append("Midlands player troop was not found")
	if enemies.is_empty():
		failures.append("Midlands enemy troop was not spawned")

	if not failures.is_empty():
		await _finish(failures)
		return

	var enemy := enemies[0]
	_enable_perf(player)
	_enable_perf(enemy)
	_reset_perf(player)
	_reset_perf(enemy)

	await _sample_phase("idle_initial", player, enemy)

	var click_destination := (player as Node3D).global_position + Vector3(10.0, 0.0, 0.0)
	var move_accepted := false
	if player.has_method("set_move_destination"):
		move_accepted = bool(player.call("set_move_destination", click_destination))
	if not move_accepted:
		failures.append("Midlands player troop rejected ordinary movement")
	else:
		await _wait_frames(8)
		_reset_perf(player)
		await _sample_phase("moving_click", player, enemy)
		await _wait_for_idle(player)
		_reset_perf(player)
		await _sample_phase("idle_after_click_move", player, enemy)

	var short_destination := (player as Node3D).global_position + Vector3(14.0, 0.0, 8.0)
	move_accepted = false
	if player.has_method("set_formation_destination"):
		move_accepted = bool(player.call("set_formation_destination", short_destination, Vector3.RIGHT, 42.0))
	elif player.has_method("set_move_destination"):
		move_accepted = bool(player.call("set_move_destination", short_destination))
	if not move_accepted:
		failures.append("Midlands player troop rejected short formation movement")
	else:
		await _wait_frames(8)
		_reset_perf(player)
		await _sample_phase("moving_formation_drag", player, enemy)
		await _wait_for_idle(player)
		_reset_perf(player)
		await _sample_phase("idle_after_formation_drag", player, enemy)

	var attack_accepted := false
	if player.has_method("command_attack_troop"):
		attack_accepted = bool(player.call("command_attack_troop", enemy))
	if enemy.has_method("command_attack_troop"):
		enemy.call("command_attack_troop", player)
	if not attack_accepted:
		failures.append("Midlands player troop rejected attack command")
	else:
		await _wait_frames(8)
		_reset_perf(player)
		_reset_perf(enemy)
		await _sample_phase("attack_approach", player, enemy)
		await _wait_for_fighting(player)
		_reset_perf(player)
		_reset_perf(enemy)
		await _sample_combat_until_end(player, enemy)

	await _finish(failures)


func _enable_perf(troop: Node) -> void:
	if _object_has_property(troop, &"troop_perf_monitoring_enabled"):
		troop.set("troop_perf_monitoring_enabled", true)
	if _object_has_property(troop, &"soldier_perf_monitoring_enabled"):
		troop.set("soldier_perf_monitoring_enabled", false)


func _reset_perf(troop: Node) -> void:
	if troop.has_method("reset_perf_debug_counters"):
		troop.call("reset_perf_debug_counters")


func _sample_phase(
	label: String,
	player: Node,
	enemy: Node,
	sample_frames: int = SAMPLE_FRAMES,
	warmup_frames: int = PHASE_WARMUP_FRAMES,
	print_prefix: String = "[MIDLANDS_PROFILE] "
) -> Dictionary:
	for _warmup_index: int in range(warmup_frames):
		await physics_frame
	_reset_perf(player)
	_reset_perf(enemy)
	var previous_positions := _get_soldier_positions(player)
	var total_process_ms := 0.0
	var total_physics_ms := 0.0
	var max_process_ms := 0.0
	var max_physics_ms := 0.0
	var total_draw_calls := 0
	var total_render_objects := 0
	var total_primitives := 0
	var max_draw_calls := 0
	var max_render_objects := 0
	var max_primitives := 0
	var facing_checks := 0
	var facing_errors := 0
	var idle_jump_count := 0
	var max_idle_jump := 0.0
	var max_soldier_step := 0.0

	for _index: int in range(sample_frames):
		await physics_frame
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var draw_calls := _get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var render_objects := _get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var primitives := _get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		total_process_ms += process_ms
		total_physics_ms += physics_ms
		max_process_ms = maxf(max_process_ms, process_ms)
		max_physics_ms = maxf(max_physics_ms, physics_ms)
		total_draw_calls += draw_calls
		total_render_objects += render_objects
		total_primitives += primitives
		max_draw_calls = maxi(max_draw_calls, draw_calls)
		max_render_objects = maxi(max_render_objects, render_objects)
		max_primitives = maxi(max_primitives, primitives)

		var current_positions := _get_soldier_positions(player)
		var state := _get_troop_state(player)
		for soldier: Node3D in current_positions.keys():
			var current_position: Vector3 = current_positions[soldier]
			var previous_variant: Variant = previous_positions.get(soldier)
			if not (previous_variant is Vector3):
				continue
			var previous_position := previous_variant as Vector3
			var displacement := current_position - previous_position
			displacement.y = 0.0
			var step := displacement.length()
			max_soldier_step = maxf(max_soldier_step, step)
			if state == &"moving" and step > 0.015:
				facing_checks += 1
				if _get_facing_angle_degrees(soldier, displacement / step) > FACING_ERROR_DEGREES:
					facing_errors += 1
			if (state == &"idle" or state == &"blocked") and not _has_independent_motion(soldier) and step > JUMP_DISTANCE_M:
				idle_jump_count += 1
				max_idle_jump = maxf(max_idle_jump, step)
		previous_positions = current_positions

	var player_summary := _get_summary(player)
	var enemy_summary := _get_summary(enemy)
	var map_summary := _get_map_render_summary()
	var metrics := {
		"label": label,
		"sample_frames": sample_frames,
		"avg_process_ms": total_process_ms / float(maxi(sample_frames, 1)),
		"max_process_ms": max_process_ms,
		"avg_physics_ms": total_physics_ms / float(maxi(sample_frames, 1)),
		"max_physics_ms": max_physics_ms,
		"fps": Engine.get_frames_per_second(),
		"avg_draw_calls": total_draw_calls / maxi(sample_frames, 1),
		"max_draw_calls": max_draw_calls,
		"avg_render_objects": total_render_objects / maxi(sample_frames, 1),
		"max_render_objects": max_render_objects,
		"avg_primitives": total_primitives / maxi(sample_frames, 1),
		"max_primitives": max_primitives,
		"video_mem_mb": _bytes_to_mb(_get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_mem_mb": _bytes_to_mb(_get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_mem_mb": _bytes_to_mb(_get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		"forest_visible_multimeshes": int(map_summary.get("forest_visible_multimeshes", 0)),
		"forest_culled_multimeshes": int(map_summary.get("forest_culled_multimeshes", 0)),
		"forest_culling_enabled": bool(map_summary.get("forest_culling_enabled", false)),
		"forest_cull_distance_m": float(map_summary.get("forest_cull_distance_m", 0.0)),
		"forest_min_distance_m": float(map_summary.get("forest_min_distance_m", 0.0)),
		"forest_max_distance_m": float(map_summary.get("forest_max_distance_m", 0.0)),
		"forest_avg_distance_m": float(map_summary.get("forest_avg_distance_m", 0.0)),
		"forest_within_cull_distance": int(map_summary.get("forest_within_cull_distance", 0)),
		"forest_within_hysteresis": int(map_summary.get("forest_within_hysteresis", 0)),
		"forest_beyond_hysteresis": int(map_summary.get("forest_beyond_hysteresis", 0)),
		"player_state": String(_get_troop_state(player)),
		"enemy_state": String(_get_troop_state(enemy)),
		"player_active_soldiers": int(player_summary.get("active_soldier_count", 0)),
		"enemy_active_soldiers": int(enemy_summary.get("active_soldier_count", 0)),
		"player_dead_soldiers": int(player_summary.get("dead_soldier_count", 0)),
		"enemy_dead_soldiers": int(enemy_summary.get("dead_soldier_count", 0)),
		"corpse_count": int(player_summary.get("corpse_count", 0)),
		"corpse_batch_count": int(player_summary.get("corpse_batch_count", 0)),
		"corpse_mesh_part_count": int(player_summary.get("corpse_mesh_part_count", 0)),
		"corpse_skipped_count": int(player_summary.get("corpse_skipped_count", 0)),
		"corpse_skipped_mesh_part_count": int(player_summary.get("corpse_skipped_mesh_part_count", 0)),
		"corpse_max_visible_count": int(player_summary.get("corpse_max_visible_count", 0)),
		"corpse_max_visible_mesh_part_count": int(player_summary.get("corpse_max_visible_mesh_part_count", 0)),
		"corpse_max_visible_batch_count": int(player_summary.get("corpse_max_visible_batch_count", 0)),
		"player_troop_physics_ms": float(player_summary.get("perf_max_physics_usec", 0.0)) / 1000.0,
		"enemy_troop_physics_ms": float(enemy_summary.get("perf_max_physics_usec", 0.0)) / 1000.0,
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
		"render_sync_max_ms": float(player_summary.get("soldier_render_max_sync_ms", 0.0)),
		"render_sync_count": int(player_summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(player_summary.get("soldier_render_sync_skip_count", 0)),
		"render_reads": int(player_summary.get("soldier_render_last_source_reads", 0)),
		"render_writes": int(player_summary.get("soldier_render_last_transform_writes", 0)),
		"formation_writes": int(player_summary.get("formation_target_write_count", 0)),
		"formation_skips": int(player_summary.get("formation_target_skip_count", 0)),
		"moving_pair_checks": int(player_summary.get("moving_formation_pair_checks", 0)),
		"spatial_rebuilds": int(player_summary.get("spatial_grid_rebuilds", 0)),
		"socket_clamps": int(player_summary.get("combat_socket_clamp_count", 0)),
		"target_scans": int(player_summary.get("combat_perf_target_candidate_scans", 0)),
		"combat_pair_checks": int(player_summary.get("combat_perf_separation_pair_checks", 0)),
		"combat_steering": int(player_summary.get("combat_perf_steering_updates", 0)),
		"player_assigned_targets": int(player_summary.get("combat_assigned_target_count", 0)),
		"enemy_assigned_targets": int(enemy_summary.get("combat_assigned_target_count", 0)),
		"player_locked_attackers": int(player_summary.get("combat_locked_attacker_count", 0)),
		"enemy_locked_attackers": int(enemy_summary.get("combat_locked_attacker_count", 0)),
		"player_visual_stance_updates": int(player_summary.get("combat_visual_stance_update_count", 0)),
		"enemy_visual_stance_updates": int(enemy_summary.get("combat_visual_stance_update_count", 0)),
		"player_visual_thrusts": int(player_summary.get("combat_visual_thrust_count", 0)),
		"enemy_visual_thrusts": int(enemy_summary.get("combat_visual_thrust_count", 0)),
		"player_max_target_load": int(player_summary.get("combat_max_target_load", 0)),
		"enemy_max_target_load": int(enemy_summary.get("combat_max_target_load", 0)),
		"sleeping_soldiers": int(player_summary.get("logic_sleeping_soldier_count", 0)),
		"independent_motions": _count_independent_motions(player),
		"facing_checks": facing_checks,
		"facing_errors": facing_errors,
		"idle_jump_count": idle_jump_count,
		"max_idle_jump": max_idle_jump,
		"max_soldier_step": max_soldier_step,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	print(print_prefix, JSON.stringify(metrics))
	return metrics


func _sample_combat_until_end(player: Node, enemy: Node) -> Dictionary:
	var elapsed_frames := 0
	var snapshot_index := 0
	var latest_metrics := {}
	var combat_finished := _is_combat_finished(player, enemy)
	while not combat_finished and elapsed_frames < COMBAT_END_TIMEOUT_FRAMES:
		var metrics := await _sample_phase(
			"combat_%03d" % snapshot_index,
			player,
			enemy,
			COMBAT_SNAPSHOT_FRAMES,
			0,
			"[MIDLANDS_COMBAT_SNAPSHOT] "
		)
		elapsed_frames += COMBAT_SNAPSHOT_FRAMES
		metrics["combat_elapsed_seconds"] = float(elapsed_frames) / float(Engine.physics_ticks_per_second)
		metrics["combat_finished"] = _is_combat_finished(player, enemy)
		print("[MIDLANDS_COMBAT_STATE] ", JSON.stringify(metrics))
		latest_metrics = metrics
		snapshot_index += 1
		combat_finished = bool(metrics.get("combat_finished", false))

	if latest_metrics.is_empty():
		latest_metrics = await _sample_phase("combat", player, enemy)
	latest_metrics["label"] = "combat"
	latest_metrics["combat_finished"] = combat_finished
	latest_metrics["combat_elapsed_seconds"] = float(elapsed_frames) / float(Engine.physics_ticks_per_second)
	print("[MIDLANDS_PROFILE] ", JSON.stringify(latest_metrics))
	return latest_metrics


func _is_combat_finished(player: Node, enemy: Node) -> bool:
	var player_summary := _get_summary(player)
	var enemy_summary := _get_summary(enemy)
	return (
		int(player_summary.get("active_soldier_count", 1)) <= 0
		or int(enemy_summary.get("active_soldier_count", 1)) <= 0
		or (_get_troop_state(player) != &"fighting" and _get_troop_state(enemy) != &"fighting")
	)


func _get_rendering_info(counter: int) -> int:
	return int(RenderingServer.get_rendering_info(counter))


func _bytes_to_mb(value: int) -> float:
	return snappedf(float(maxi(value, 0)) / (1024.0 * 1024.0), 0.01)


func _get_map_render_summary() -> Dictionary:
	var summary := {}
	var scene := _scene
	if not scene:
		return summary

	var forest_region := scene.get_node_or_null("ForestRegion")
	if forest_region and forest_region.has_method("get_runtime_render_summary"):
		var forest_summary := forest_region.call("get_runtime_render_summary") as Dictionary
		summary["forest_visible_multimeshes"] = int(forest_summary.get("runtime_visible_multimesh_count", 0))
		summary["forest_culled_multimeshes"] = int(forest_summary.get("runtime_culled_multimesh_count", 0))
		summary["forest_culling_enabled"] = bool(forest_summary.get("runtime_camera_culling_enabled", false))
		summary["forest_cull_distance_m"] = float(forest_summary.get("runtime_cull_distance_meters", 0.0))
		summary["forest_min_distance_m"] = float(forest_summary.get("runtime_min_multimesh_distance_m", 0.0))
		summary["forest_max_distance_m"] = float(forest_summary.get("runtime_max_multimesh_distance_m", 0.0))
		summary["forest_avg_distance_m"] = float(forest_summary.get("runtime_avg_multimesh_distance_m", 0.0))
		summary["forest_within_cull_distance"] = int(forest_summary.get("runtime_within_cull_distance_count", 0))
		summary["forest_within_hysteresis"] = int(forest_summary.get("runtime_within_hysteresis_count", 0))
		summary["forest_beyond_hysteresis"] = int(forest_summary.get("runtime_beyond_hysteresis_count", 0))

	return summary


func _check_midlands_forest_culling(scene: Node, failures: Array[String]) -> void:
	var forest_region := scene.get_node_or_null("ForestRegion")
	if not forest_region or not forest_region.has_method("get_runtime_render_summary"):
		failures.append("Midlands forest culling check could not find ForestRegion summary")
		return
	if forest_region.has_method("_apply_runtime_camera_culling"):
		forest_region.call("_apply_runtime_camera_culling", true)
	await _wait_frames(4)
	if forest_region.has_method("_apply_runtime_camera_culling"):
		forest_region.call("_apply_runtime_camera_culling", true)
	var raw_summary := forest_region.call("get_runtime_render_summary") as Dictionary
	var summary := {
		"forest_visible_multimeshes": int(raw_summary.get("runtime_visible_multimesh_count", 0)),
		"forest_culled_multimeshes": int(raw_summary.get("runtime_culled_multimesh_count", 0)),
		"forest_culling_enabled": bool(raw_summary.get("runtime_camera_culling_enabled", false)),
		"forest_cull_distance_m": float(raw_summary.get("runtime_cull_distance_meters", 0.0)),
		"forest_min_distance_m": float(raw_summary.get("runtime_min_multimesh_distance_m", 0.0)),
		"forest_max_distance_m": float(raw_summary.get("runtime_max_multimesh_distance_m", 0.0)),
		"forest_avg_distance_m": float(raw_summary.get("runtime_avg_multimesh_distance_m", 0.0)),
		"forest_within_cull_distance": int(raw_summary.get("runtime_within_cull_distance_count", 0)),
		"forest_within_hysteresis": int(raw_summary.get("runtime_within_hysteresis_count", 0)),
		"forest_beyond_hysteresis": int(raw_summary.get("runtime_beyond_hysteresis_count", 0)),
	}
	print("[MIDLANDS_CULLING_CHECK] ", JSON.stringify(summary))
	if not bool(summary.get("forest_culling_enabled", false)):
		failures.append("Midlands forest camera culling should be enabled")
	if int(summary.get("forest_visible_multimeshes", 0)) <= 0:
		failures.append("Midlands forest culling check found no visible forest multimeshes")
	if int(summary.get("forest_culled_multimeshes", 0)) <= 0:
		failures.append("Midlands forest culling should hide far runtime multimeshes at the starting camera")
	if int(summary.get("forest_beyond_hysteresis", 0)) <= 0:
		failures.append("Midlands forest culling should have runtime multimeshes beyond the culling hysteresis band")


func _wait_for_idle(troop: Node) -> void:
	for _index: int in range(ARRIVAL_TIMEOUT_FRAMES):
		await physics_frame
		if _get_troop_state(troop) == &"idle":
			return


func _wait_for_fighting(troop: Node) -> void:
	for _index: int in range(ARRIVAL_TIMEOUT_FRAMES):
		await physics_frame
		if _get_troop_state(troop) == &"fighting":
			return


func _wait_frames(frames: int) -> void:
	for _index: int in range(frames):
		await process_frame
		await physics_frame


func _wait_for_scene_runtime_settled(scene: Node) -> void:
	var stable_frames := 0
	var previous_key := ""
	for _index: int in range(SCENE_SETTLE_TIMEOUT_FRAMES):
		await process_frame
		await physics_frame
		var key := _get_scene_runtime_settle_key(scene)
		if key == previous_key and key != "":
			stable_frames += 1
		else:
			stable_frames = 0
			previous_key = key
		if stable_frames >= SCENE_SETTLE_STABLE_FRAMES:
			return


func _get_scene_runtime_settle_key(scene: Node) -> String:
	var village_runtime := scene.get_node_or_null("VillageRegion/__VillageRuntimeInstances")
	var forest_runtime := scene.get_node_or_null("ForestRegion/__ForestRuntimeInstances")
	if not village_runtime or not forest_runtime:
		return ""
	return "%d:%d" % [village_runtime.get_child_count(), forest_runtime.get_child_count()]


func _get_troop_state(troop: Node) -> StringName:
	var summary := _get_summary(troop)
	return StringName(summary.get("state", &""))


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


func _has_independent_motion(soldier: Node) -> bool:
	return soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion"))


func _count_independent_motions(troop: Node) -> int:
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return 0
	var count := 0
	for soldier: Node in soldiers.get_children():
		if _has_independent_motion(soldier):
			count += 1
	return count


func _get_facing_angle_degrees(soldier: Node3D, direction: Vector3) -> float:
	var forward := -soldier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001 or direction.length_squared() <= 0.0001:
		return 0.0
	return rad_to_deg(acos(clampf(forward.normalized().dot(direction.normalized()), -1.0, 1.0)))


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if not object:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false


func _finish(failures: Array[String]) -> void:
	Engine.max_fps = _original_max_fps
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
		for _index: int in range(4):
			await process_frame
			await physics_frame
	if failures.is_empty():
		print("Midlands troop scene profile completed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
