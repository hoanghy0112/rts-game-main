extends SceneTree

const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")

const SOLDIER_COUNT := 96
const FORMATION_COLUMNS := 12
const MOVE_SAMPLE_FRAMES := 90
const IDLE_SAMPLE_FRAMES := 90
const ATTACK_TIMEOUT_FRAMES := 720
const COMBAT_SETTLE_SAMPLE_FRAMES := 45
const MAX_MOVING_STEP_M := 0.42
const MAX_IDLE_STEP_M := 0.05
const MAX_COMBAT_TRANSITION_STEP_M := 0.62
const MAX_FACING_ERROR_RATIO := 0.12
const FACING_ERROR_DEGREES := 80.0
const MIN_WALK_POSE_RANGE := 0.08

var _original_max_fps := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_max_fps = Engine.max_fps
	Engine.max_fps = 0

	var failures: Array[String] = []
	var movement_map := _make_map(128, 96)
	var mover := _make_troop(&"smooth_mover", &"player", Vector3(18.0, 0.0, 42.0), movement_map)
	root.add_child(mover)
	await _wait_frames(8)

	if not bool(mover.call("set_move_destination", Vector3(42.0, 0.0, 42.0))):
		failures.append("smoothness troop rejected reachable move destination")
	else:
		await _wait_frames(4)
		_reset_perf(mover)
		var moving_metrics := await _sample_motion(mover, MOVE_SAMPLE_FRAMES, true)
		_print_metrics("moving", moving_metrics)
		_assert_active_render_sync("moving", moving_metrics, failures)
		if float(moving_metrics.get("walk_pose_range", 0.0)) < MIN_WALK_POSE_RANGE:
			failures.append(
				"moving soldiers did not animate walking pose; range %.3f below %.3f"
				% [float(moving_metrics.get("walk_pose_range", 0.0)), MIN_WALK_POSE_RANGE]
			)
		if float(moving_metrics.get("max_step_m", 0.0)) > MAX_MOVING_STEP_M:
			failures.append("moving soldier source step jumped %.3fm; budget %.3fm" % [float(moving_metrics["max_step_m"]), MAX_MOVING_STEP_M])
		var facing_checks := int(moving_metrics.get("facing_checks", 0))
		var facing_errors := int(moving_metrics.get("facing_errors", 0))
		if facing_checks > 0 and float(facing_errors) / float(facing_checks) > MAX_FACING_ERROR_RATIO:
			failures.append("moving facing error ratio %.3f exceeded %.3f" % [float(facing_errors) / float(facing_checks), MAX_FACING_ERROR_RATIO])
		var reached_idle := await _wait_for_state(mover, &"idle", 900)
		if not reached_idle:
			failures.append("movement troop did not settle to idle before stand-by smoothness sample")
		else:
			await _wait_frames(30)
			_reset_perf(mover)
			var idle_metrics := await _sample_motion(mover, IDLE_SAMPLE_FRAMES, false)
			_print_metrics("idle_after_move", idle_metrics)
			if float(idle_metrics.get("max_step_m", 0.0)) > MAX_IDLE_STEP_M:
				failures.append("stand-by soldier drift/jump %.3fm; budget %.3fm" % [float(idle_metrics["max_step_m"]), MAX_IDLE_STEP_M])
			if int(idle_metrics.get("independent_motions", 0)) > 0:
				failures.append("stand-by formation kept %d independent soldier motions" % int(idle_metrics["independent_motions"]))
			var formation_drag_accepted := false
			if mover.has_method("set_formation_destination"):
				formation_drag_accepted = bool(mover.call(
					"set_formation_destination",
					Vector3(68.0, 0.0, 56.0),
					Vector3(0.72, 0.0, 0.69),
					36.0
				))
			if not formation_drag_accepted:
				failures.append("smoothness troop rejected reachable formation drag destination")
			else:
				await _wait_frames(4)
				_reset_perf(mover)
				var formation_drag_metrics := await _sample_motion(mover, MOVE_SAMPLE_FRAMES, true)
				_print_metrics("formation_drag", formation_drag_metrics)
				_assert_active_render_sync("formation_drag", formation_drag_metrics, failures)
				if float(formation_drag_metrics.get("max_step_m", 0.0)) > MAX_MOVING_STEP_M:
					failures.append(
						"formation-drag soldier source step jumped %.3fm; budget %.3fm"
						% [float(formation_drag_metrics["max_step_m"]), MAX_MOVING_STEP_M]
					)
				var drag_facing_checks := int(formation_drag_metrics.get("facing_checks", 0))
				var drag_facing_errors := int(formation_drag_metrics.get("facing_errors", 0))
				if drag_facing_checks > 0 and float(drag_facing_errors) / float(drag_facing_checks) > MAX_FACING_ERROR_RATIO:
					failures.append(
						"formation-drag facing error ratio %.3f exceeded %.3f"
						% [float(drag_facing_errors) / float(drag_facing_checks), MAX_FACING_ERROR_RATIO]
					)

	var attacker := _make_troop(&"smooth_attacker", &"player", Vector3(18.0, 0.0, 24.0), movement_map)
	var defender := _make_troop(&"smooth_defender", &"enemy", Vector3(76.0, 0.0, 24.0), movement_map)
	root.add_child(attacker)
	root.add_child(defender)
	await _wait_frames(8)
	_reset_perf(attacker)
	_reset_perf(defender)
	var combat_metrics := await _sample_attack_transition(attacker, defender)
	_print_metrics("attack_transition", combat_metrics)
	_assert_active_render_sync("attack_transition", combat_metrics, failures)
	if not bool(combat_metrics.get("reached_fighting", false)):
		failures.append("attack transition did not reach fighting state")
	if float(combat_metrics.get("max_transition_step_m", 0.0)) > MAX_COMBAT_TRANSITION_STEP_M:
		failures.append(
			"combat-start soldier source step jumped %.3fm; budget %.3fm"
			% [float(combat_metrics["max_transition_step_m"]), MAX_COMBAT_TRANSITION_STEP_M]
		)

	_free_test_node(mover)
	_free_test_node(attacker)
	_free_test_node(defender)

	var autonomous_player := _make_troop(&"auto_chase_player", &"player", Vector3(20.0, 0.0, 40.0), movement_map)
	var autonomous_enemy := _make_troop(&"auto_chase_enemy", &"enemy", Vector3(110.0, 0.0, 40.0), movement_map)
	autonomous_player.set("soldier_count", 24)
	autonomous_player.set("formation_columns", 6)
	autonomous_enemy.set("soldier_count", 24)
	autonomous_enemy.set("formation_columns", 6)
	autonomous_enemy.set("controllable", false)
	autonomous_enemy.set("troop_mode", "attack")
	autonomous_enemy.set("detection_range_m", 34.0)
	autonomous_enemy.set("chase_repath_interval", 0.05)
	root.add_child(autonomous_player)
	root.add_child(autonomous_enemy)
	await _wait_frames(8)
	var autonomous_metrics := await _sample_autonomous_enemy_chase(autonomous_enemy)
	_print_metrics("autonomous_enemy_chase", autonomous_metrics)
	if not bool(autonomous_metrics.get("acquired_target", false)):
		failures.append("autonomous enemy did not acquire a player troop beyond normal detection range")
	if not bool(autonomous_metrics.get("started_moving", false)):
		failures.append("autonomous enemy did not start moving toward the acquired player troop")
	if float(autonomous_metrics.get("max_moving_step_m", 0.0)) > MAX_MOVING_STEP_M:
		failures.append(
			"autonomous enemy soldier source step jumped %.3fm; budget %.3fm"
			% [float(autonomous_metrics["max_moving_step_m"]), MAX_MOVING_STEP_M]
		)
	if float(autonomous_metrics.get("max_fighting_step_m", 0.0)) > MAX_COMBAT_TRANSITION_STEP_M:
		failures.append(
			"autonomous enemy combat transition step jumped %.3fm; budget %.3fm"
			% [float(autonomous_metrics["max_fighting_step_m"]), MAX_COMBAT_TRANSITION_STEP_M]
		)
	var sampled_moving_frames := int(autonomous_metrics.get("sampled_moving_frames", 0))
	var render_sync_count := int(autonomous_metrics.get("render_sync_count", 0))
	if sampled_moving_frames > 0 and render_sync_count < int(float(sampled_moving_frames) * 0.75):
		failures.append(
			"autonomous enemy moving render sync was sparse (%d syncs over %d moving frames)"
			% [render_sync_count, sampled_moving_frames]
		)

	_free_test_node(autonomous_player)
	_free_test_node(autonomous_enemy)

	var regrouper := _make_troop(&"idle_regrouper", &"player", Vector3(24.0, 0.0, 72.0), movement_map)
	regrouper.set("soldier_count", 48)
	regrouper.set("formation_columns", 8)
	root.add_child(regrouper)
	await _wait_frames(8)
	_scatter_soldiers_from_slots(regrouper)
	await _wait_frames(1)
	_reset_perf(regrouper)
	if regrouper.has_method("_issue_idle_formation_targets"):
		regrouper.call("_issue_idle_formation_targets")
	var regroup_metrics := await _sample_idle_independent_regroup(regrouper, 80)
	_print_metrics("idle_independent_regroup", regroup_metrics)
	if int(regroup_metrics.get("sampled_independent_frames", 0)) <= 0:
		failures.append("idle regroup setup did not start independent formation-slot motion")
	if float(regroup_metrics.get("max_step_m", 0.0)) > MAX_MOVING_STEP_M:
		failures.append(
			"idle regroup soldier source step jumped %.3fm; budget %.3fm"
			% [float(regroup_metrics["max_step_m"]), MAX_MOVING_STEP_M]
		)
	var regroup_frames := int(regroup_metrics.get("sampled_independent_frames", 0))
	var regroup_sync_count := int(regroup_metrics.get("render_sync_count", 0))
	if regroup_frames > 0 and regroup_sync_count < int(float(regroup_frames) * 0.75):
		failures.append(
			"idle regroup render sync was sparse (%d syncs over %d independent-motion frames)"
			% [regroup_sync_count, regroup_frames]
		)
	if int(regroup_metrics.get("render_sync_skips", 0)) > 0 and regroup_sync_count <= 0:
		failures.append("idle regroup skipped all render syncs while soldiers were walking to formation")

	Engine.max_fps = _original_max_fps
	if failures.is_empty():
		print("Troop smoothness headless check passed.")
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
	troop.set("soldier_count", SOLDIER_COUNT)
	troop.set("formation_columns", FORMATION_COLUMNS)
	troop.set("movement_map", movement_map)
	troop.set("troop_perf_monitoring_enabled", true)
	troop.set("soldier_perf_monitoring_enabled", false)
	troop.set("carried_food_kg", 1000.0)
	troop.position = position
	return troop


func _make_map(width: int, height: int) -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2.ZERO
	data.cell_size_meters = 1.0
	data.resize_map(width, height, 1.0, 0)
	return data


func _sample_motion(troop: Node, frame_count: int, check_facing: bool) -> Dictionary:
	var previous_positions := _get_soldier_positions(troop)
	var max_step := 0.0
	var facing_checks := 0
	var facing_errors := 0
	var min_walk_pose := INF
	var max_walk_pose := -INF
	for _index: int in range(frame_count):
		await _wait_frames(1)
		var current_positions := _get_soldier_positions(troop)
		var walk_pose: Variant = _get_primary_walk_pose_value(troop)
		if walk_pose != null:
			min_walk_pose = minf(min_walk_pose, float(walk_pose))
			max_walk_pose = maxf(max_walk_pose, float(walk_pose))
		for soldier: Node3D in current_positions.keys():
			var previous_variant: Variant = previous_positions.get(soldier)
			if not (previous_variant is Vector3):
				continue
			var previous_position := previous_variant as Vector3
			var current_position: Vector3 = current_positions[soldier]
			var delta_position := current_position - previous_position
			delta_position.y = 0.0
			var step := delta_position.length()
			max_step = maxf(max_step, step)
			if check_facing and step > 0.015:
				facing_checks += 1
				if _get_facing_angle_degrees(soldier, delta_position / step) > FACING_ERROR_DEGREES:
					facing_errors += 1
		previous_positions = current_positions
	var summary := _get_summary(troop)
	var walk_pose_range := 0.0
	if min_walk_pose < INF and max_walk_pose > -INF:
		walk_pose_range = max_walk_pose - min_walk_pose
	return {
		"max_step_m": max_step,
		"facing_checks": facing_checks,
		"facing_errors": facing_errors,
		"render_sync_count": int(summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(summary.get("soldier_render_sync_skip_count", 0)),
		"render_sync_max_ms": float(summary.get("soldier_render_max_sync_ms", 0.0)),
		"render_writes": int(summary.get("soldier_render_max_transform_writes", 0)),
		"independent_motions": _count_independent_motions(troop),
		"walk_pose_range": walk_pose_range,
		"state": String(summary.get("state", &"")),
	}


func _sample_attack_transition(attacker: Node, defender: Node) -> Dictionary:
	var accepted := false
	if attacker.has_method("command_attack_troop"):
		accepted = bool(attacker.call("command_attack_troop", defender))
	if defender.has_method("command_attack_troop"):
		defender.call("command_attack_troop", attacker)
	if not accepted:
		return {"reached_fighting": false, "render_sync_count": 0, "render_sync_skips": 0}

	var previous_positions := _get_soldier_positions(attacker)
	var previous_state := _get_troop_state(attacker)
	var reached_fighting := false
	var combat_frames := 0
	var max_transition_step := 0.0
	var max_step := 0.0
	for _index: int in range(ATTACK_TIMEOUT_FRAMES):
		await _wait_frames(1)
		var current_state := _get_troop_state(attacker)
		var current_positions := _get_soldier_positions(attacker)
		var transition_window := current_state == &"fighting" and (previous_state != &"fighting" or combat_frames < COMBAT_SETTLE_SAMPLE_FRAMES)
		for soldier: Node3D in current_positions.keys():
			var previous_variant: Variant = previous_positions.get(soldier)
			if not (previous_variant is Vector3):
				continue
			var current_position: Vector3 = current_positions[soldier]
			var previous_position := previous_variant as Vector3
			var delta_position := current_position - previous_position
			delta_position.y = 0.0
			var step := delta_position.length()
			max_step = maxf(max_step, step)
			if transition_window:
				max_transition_step = maxf(max_transition_step, step)
		previous_positions = current_positions
		previous_state = current_state
		if current_state == &"fighting":
			reached_fighting = true
			combat_frames += 1
			if combat_frames >= COMBAT_SETTLE_SAMPLE_FRAMES:
				break
	var summary := _get_summary(attacker)
	return {
		"reached_fighting": reached_fighting,
		"max_step_m": max_step,
		"max_transition_step_m": max_transition_step,
		"render_sync_count": int(summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(summary.get("soldier_render_sync_skip_count", 0)),
		"render_sync_max_ms": float(summary.get("soldier_render_max_sync_ms", 0.0)),
		"state": String(summary.get("state", &"")),
	}


func _sample_autonomous_enemy_chase(enemy: Node) -> Dictionary:
	var previous_positions := _get_soldier_positions(enemy)
	var started_moving := false
	var acquired_target := false
	var sampled_moving_frames := 0
	var max_step := 0.0
	var max_moving_step := 0.0
	var max_fighting_step := 0.0
	for _index: int in range(420):
		await _wait_frames(1)
		var summary := _get_summary(enemy)
		var state := StringName(summary.get("state", &""))
		var target_path := NodePath(summary.get("combat_target", NodePath("")))
		acquired_target = acquired_target or not target_path.is_empty()
		if state == &"moving" or state == &"fighting":
			if not started_moving:
				started_moving = true
				_reset_perf(enemy)
				previous_positions = _get_soldier_positions(enemy)
			else:
				var current_positions := _get_soldier_positions(enemy)
				for soldier: Node3D in current_positions.keys():
					var previous_variant: Variant = previous_positions.get(soldier)
					if not (previous_variant is Vector3):
						continue
					var delta_position: Vector3 = current_positions[soldier] - (previous_variant as Vector3)
					delta_position.y = 0.0
					var step := delta_position.length()
					max_step = maxf(max_step, step)
					if state == &"moving":
						max_moving_step = maxf(max_moving_step, step)
					elif state == &"fighting":
						max_fighting_step = maxf(max_fighting_step, step)
				previous_positions = current_positions
			sampled_moving_frames += 1
			if sampled_moving_frames >= 120:
				break
	var final_summary := _get_summary(enemy)
	return {
		"acquired_target": acquired_target,
		"started_moving": started_moving,
		"sampled_moving_frames": sampled_moving_frames,
		"max_step_m": max_step,
		"max_moving_step_m": max_moving_step,
		"max_fighting_step_m": max_fighting_step,
		"render_sync_count": int(final_summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(final_summary.get("soldier_render_sync_skip_count", 0)),
		"state": String(final_summary.get("state", &"")),
	}


func _sample_idle_independent_regroup(troop: Node, frame_count: int) -> Dictionary:
	var previous_positions := _get_soldier_positions(troop)
	var max_step := 0.0
	var sampled_independent_frames := 0
	for _index: int in range(frame_count):
		await _wait_frames(1)
		var current_positions := _get_soldier_positions(troop)
		var independent_count := _count_independent_motions(troop)
		if independent_count > 0:
			sampled_independent_frames += 1
		for soldier: Node3D in current_positions.keys():
			var previous_variant: Variant = previous_positions.get(soldier)
			if not (previous_variant is Vector3):
				continue
			var delta_position: Vector3 = current_positions[soldier] - (previous_variant as Vector3)
			delta_position.y = 0.0
			max_step = maxf(max_step, delta_position.length())
		previous_positions = current_positions
	var summary := _get_summary(troop)
	return {
		"sampled_independent_frames": sampled_independent_frames,
		"max_step_m": max_step,
		"render_sync_count": int(summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(summary.get("soldier_render_sync_skip_count", 0)),
		"state": String(summary.get("state", &"")),
		"independent_motions": _count_independent_motions(troop),
	}


func _assert_active_render_sync(label: String, metrics: Dictionary, failures: Array[String]) -> void:
	var skips := int(metrics.get("render_sync_skips", 0))
	if skips > 0 and label != "moving" and int(metrics.get("render_sync_count", 0)) <= 0:
		failures.append("%s skipped all active soldier render syncs; visible movement will stutter" % label)
	var sync_count := int(metrics.get("render_sync_count", 0))
	if sync_count <= 0:
		failures.append("%s did not sync batched soldier transforms while active" % label)


func _wait_for_state(troop: Node, state: StringName, max_frames: int) -> bool:
	for _index: int in range(max_frames):
		await _wait_frames(1)
		if _get_troop_state(troop) == state:
			return true
	return false


func _wait_frames(frames: int) -> void:
	for _index: int in range(frames):
		await process_frame
		await physics_frame


func _reset_perf(troop: Node) -> void:
	if troop.has_method("reset_perf_debug_counters"):
		troop.call("reset_perf_debug_counters")


func _free_test_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.free()


func _scatter_soldiers_from_slots(troop: Node) -> void:
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return
	var index := 0
	for soldier_node: Node in soldiers.get_children():
		if not (soldier_node is Node3D) or not _is_soldier_alive(soldier_node):
			continue
		var soldier := soldier_node as Node3D
		var lateral := 7.0 if index % 2 == 0 else -7.0
		var depth := 3.0 * float((index % 5) - 2)
		soldier.global_position += Vector3(lateral, 0.0, depth)
		if soldier.has_method("clear_independent_motion"):
			soldier.call("clear_independent_motion")
		index += 1


func _get_summary(troop: Node) -> Dictionary:
	if troop and troop.has_method("get_troop_summary"):
		return troop.call("get_troop_summary") as Dictionary
	return {}


func _get_troop_state(troop: Node) -> StringName:
	return StringName(_get_summary(troop).get("state", &""))


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


func _count_independent_motions(troop: Node) -> int:
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return 0
	var count := 0
	for soldier: Node in soldiers.get_children():
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			count += 1
	return count


func _get_facing_angle_degrees(soldier: Node3D, direction: Vector3) -> float:
	var forward := -soldier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001 or direction.length_squared() <= 0.0001:
		return 0.0
	forward = forward.normalized()
	var flat_direction := direction
	flat_direction.y = 0.0
	flat_direction = flat_direction.normalized()
	return rad_to_deg(acos(clampf(forward.dot(flat_direction), -1.0, 1.0)))


func _get_primary_walk_pose_value(troop: Node) -> Variant:
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return null
	for soldier_node: Node in soldiers.get_children():
		if not (soldier_node is Node3D) or not _is_soldier_alive(soldier_node):
			continue
		var left_leg := soldier_node.get_node_or_null("VisualRoot/Armature/LeftLeg") as Node3D
		var right_leg := soldier_node.get_node_or_null("VisualRoot/Armature/RightLeg") as Node3D
		if left_leg and right_leg:
			return left_leg.rotation.x - right_leg.rotation.x
	return null


func _print_metrics(label: String, metrics: Dictionary) -> void:
	print("[SMOOTHNESS] %s %s" % [label, JSON.stringify(metrics)])
