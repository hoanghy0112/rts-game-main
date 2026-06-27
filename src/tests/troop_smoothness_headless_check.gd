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
const MIN_ANIMATION_BONE_RANGE := 0.001

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
		_assert_animation_player_walk("moving", moving_metrics, failures)
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
				_assert_animation_player_walk("formation_drag", formation_drag_metrics, failures)
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
				var override_direction := Vector3(18.0, 0.0, 0.0)
				var override_destination := (mover as Node3D).global_position + override_direction
				if not bool(mover.call("set_move_destination", override_destination)):
					failures.append("plain move after formation drag was rejected")
				else:
					var override_yaw_error := _get_yaw_error_degrees((mover as Node3D).rotation.y, override_direction)
					if override_yaw_error > 4.0:
						failures.append(
							"plain move after formation drag kept stale formation yaw; error %.2f degrees"
							% override_yaw_error
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
	if bool(autonomous_metrics.get("render_batching_enabled", false)) and sampled_moving_frames > 0 and render_sync_count < int(float(sampled_moving_frames) * 0.75):
		failures.append(
			"autonomous enemy moving render sync was sparse (%d syncs over %d moving frames)"
			% [render_sync_count, sampled_moving_frames]
		)

	_free_test_node(autonomous_player)
	_free_test_node(autonomous_enemy)

	var defensive_zone_player := _make_troop(&"defensive_zone_player", &"player", Vector3(84.0, 0.0, 58.0), movement_map)
	var defensive_zone_enemy := _make_troop(&"defensive_zone_enemy", &"enemy", Vector3(20.0, 0.0, 58.0), movement_map)
	defensive_zone_player.set("soldier_count", 24)
	defensive_zone_player.set("formation_columns", 6)
	defensive_zone_enemy.set("soldier_count", 24)
	defensive_zone_enemy.set("formation_columns", 6)
	defensive_zone_enemy.set("controllable", false)
	defensive_zone_enemy.set("troop_mode", "defensive")
	defensive_zone_enemy.set("detection_range_m", 8.0)
	defensive_zone_enemy.set("ai_chase_detection_range_m", 96.0)
	defensive_zone_enemy.set("defensive_engagement_range_m", 10.0)
	defensive_zone_enemy.set("combat_range_m", 10.0)
	defensive_zone_enemy.set("defensive_engagement_delay", 0.0)
	defensive_zone_enemy.set("combat_scan_interval", 60.0)
	defensive_zone_enemy.set("chase_repath_interval", 0.05)
	root.add_child(defensive_zone_player)
	root.add_child(defensive_zone_enemy)
	await _wait_frames(8)
	await _wait_frames(90)
	var defensive_far_summary := _get_summary(defensive_zone_enemy)
	if not NodePath(defensive_far_summary.get("combat_target", NodePath(""))).is_empty():
		failures.append("non-controllable defensive enemy should not acquire a troop only because it is inside AI chase range")
	if StringName(defensive_far_summary.get("state", &"")) != &"idle":
		failures.append("non-controllable defensive enemy should stay idle before a player enters its attack zone")
	(defensive_zone_player as Node3D).global_position = (defensive_zone_enemy as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
	if not await _wait_for_state(defensive_zone_enemy, &"fighting", 180):
		failures.append("non-controllable defensive enemy did not fight when a player troop entered its attack zone")
	else:
		var defensive_zone_summary := _get_summary(defensive_zone_enemy)
		var defensive_zone_target := NodePath(defensive_zone_summary.get("combat_target", NodePath("")))
		if defensive_zone_target != defensive_zone_player.get_path():
			failures.append("non-controllable defensive enemy did not target the player troop inside its attack zone")

	_free_test_node(defensive_zone_player)
	_free_test_node(defensive_zone_enemy)

	var auto_guard := _make_troop(&"manual_move_auto_guard", &"player", Vector3(20.0, 0.0, 64.0), movement_map)
	var auto_intruder := _make_troop(&"manual_move_auto_intruder", &"enemy", Vector3(52.0, 0.0, 64.0), movement_map)
	auto_guard.set("defensive_engagement_range_m", 10.0)
	auto_guard.set("combat_range_m", 10.0)
	auto_guard.set("combat_scan_interval", 0.01)
	auto_guard.set("defensive_engagement_delay", 0.0)
	auto_intruder.set("defensive_engagement_range_m", 10.0)
	auto_intruder.set("combat_range_m", 10.0)
	root.add_child(auto_guard)
	root.add_child(auto_intruder)
	await _wait_frames(8)
	if not bool(auto_guard.call("set_move_destination", Vector3(80.0, 0.0, 64.0))):
		failures.append("manual move auto-fight setup rejected reachable move destination")
	else:
		await _wait_frames(4)
		(auto_intruder as Node3D).global_position = (auto_guard as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
		if not await _wait_for_state(auto_guard, &"fighting", 180):
			failures.append("manual moving troop did not auto-fight when an enemy entered engagement range")
		else:
			var auto_summary := _get_summary(auto_guard)
			if bool(auto_summary.get("has_destination", true)):
				failures.append("manual moving troop kept its move destination after auto-fight engaged")
			if not bool(auto_guard.call("_should_continue_engagement", auto_intruder, false, 0.2)):
				failures.append("committed combat dropped on a single false engagement-zone sample")

	_free_test_node(auto_guard)
	_free_test_node(auto_intruder)

	var idle_guard := _make_troop(&"idle_auto_guard", &"player", Vector3(20.0, 0.0, 70.0), movement_map)
	var far_intruder := _make_troop(&"idle_far_intruder", &"enemy", Vector3(48.0, 0.0, 70.0), movement_map)
	var close_intruder := _make_troop(&"idle_close_intruder", &"enemy", Vector3(100.0, 0.0, 70.0), movement_map)
	idle_guard.set("defensive_engagement_range_m", 10.0)
	idle_guard.set("combat_range_m", 10.0)
	idle_guard.set("defensive_engagement_delay", 0.0)
	far_intruder.set("defensive_engagement_range_m", 10.0)
	far_intruder.set("combat_range_m", 10.0)
	close_intruder.set("defensive_engagement_range_m", 10.0)
	close_intruder.set("combat_range_m", 10.0)
	root.add_child(idle_guard)
	root.add_child(far_intruder)
	root.add_child(close_intruder)
	await _wait_frames(40)
	(close_intruder as Node3D).global_position = (idle_guard as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
	if not await _wait_for_state(idle_guard, &"fighting", 120):
		failures.append("idle troop did not proactively fight when a new enemy entered engagement range")
	else:
		var idle_summary := _get_summary(idle_guard)
		var target_path := NodePath(idle_summary.get("combat_target", NodePath("")))
		if target_path != close_intruder.get_path():
			failures.append("idle troop did not prioritize the enemy inside engagement range over a stale detected target")

	_free_test_node(idle_guard)
	_free_test_node(far_intruder)
	_free_test_node(close_intruder)

	var enemy_guard := _make_troop(&"enemy_unified_auto_guard", &"enemy", Vector3(20.0, 0.0, 76.0), movement_map)
	var enemy_far_target := _make_troop(&"enemy_unified_far_target", &"player", Vector3(86.0, 0.0, 76.0), movement_map)
	var enemy_close_intruder := _make_troop(&"enemy_unified_close_intruder", &"player", Vector3(116.0, 0.0, 76.0), movement_map)
	for troop: Node in [enemy_guard, enemy_far_target, enemy_close_intruder]:
		troop.set("soldier_count", 24)
		troop.set("formation_columns", 6)
		troop.set("defensive_engagement_range_m", 10.0)
		troop.set("combat_range_m", 10.0)
		troop.set("defensive_engagement_delay", 0.0)
	enemy_guard.set("controllable", false)
	enemy_guard.set("troop_mode", "defensive")
	enemy_guard.set("combat_scan_interval", 60.0)
	enemy_guard.set("chase_repath_interval", 0.05)
	root.add_child(enemy_guard)
	root.add_child(enemy_far_target)
	root.add_child(enemy_close_intruder)
	await _wait_frames(8)
	if not bool(enemy_guard.call("command_attack_troop", enemy_far_target)):
		failures.append("enemy unified auto-fight setup rejected a reachable attack target")
	else:
		await _wait_frames(4)
		(enemy_close_intruder as Node3D).global_position = (enemy_guard as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
		if not await _wait_for_state(enemy_guard, &"fighting", 180):
			failures.append("enemy troop did not proactively fight when a player troop entered its engagement range")
		else:
			var enemy_guard_summary := _get_summary(enemy_guard)
			var enemy_guard_target_path := NodePath(enemy_guard_summary.get("combat_target", NodePath("")))
			if enemy_guard_target_path != enemy_close_intruder.get_path():
				failures.append("enemy troop did not use unified close-range target priority over a stale attack target")

	_free_test_node(enemy_guard)
	_free_test_node(enemy_far_target)
	_free_test_node(enemy_close_intruder)

	var line_player := _make_troop(&"line_status_player", &"player", Vector3(20.0, 0.0, 82.0), movement_map)
	var line_enemy := _make_troop(&"line_status_enemy", &"enemy", Vector3(24.0, 0.0, 82.0), movement_map)
	line_player.set("soldier_count", 2)
	line_player.set("formation_columns", 2)
	line_player.set("combat_spear_range_m", 2.5)
	line_enemy.set("soldier_count", 2)
	line_enemy.set("formation_columns", 2)
	root.add_child(line_player)
	root.add_child(line_enemy)
	await _wait_frames(8)
	var line_attackers := _get_active_soldier_nodes(line_player)
	var line_defenders := _get_active_soldier_nodes(line_enemy)
	if line_attackers.is_empty() or line_defenders.is_empty():
		failures.append("combat line status setup did not spawn active soldiers")
	else:
		var line_attacker := line_attackers[0] as Node3D
		var line_defender := line_defenders[0] as Node3D
		line_attacker.global_position = Vector3(20.0, 0.0, 82.0)
		line_defender.global_position = Vector3(21.4, 0.0, 82.0)
		line_player.call("_set_state", &"fighting")
		line_player.call("set_combat_debug_lines_enabled", true)
		var line_load_by_defender := {
			line_defender.get_instance_id(): 0,
		}
		line_player.call("_assign_combat_target_to_soldier", line_attacker, line_defender, line_load_by_defender)
		line_player.call("_update_combat_debug_lines")
		var in_range_relation: Dictionary = line_player.call("get_combat_target_relation_for_soldier", line_attacker) as Dictionary
		var in_range_summary := _get_summary(line_player)
		if StringName(in_range_relation.get("status", &"")) != &"fighting":
			failures.append("assigned soldier in spear range should immediately report fighting, even before socket lock")
		if int(in_range_summary.get("combat_debug_line_fighting_pair_count", 0)) != 1:
			failures.append("combat debug red line should appear for assigned soldier in spear range")
		var unlocked_defender_strength_before := _get_soldier_strength(line_defender)
		line_player.call("_resolve_combat_tick", line_enemy, 10.0)
		var unlocked_defender_strength_after := _get_soldier_strength(line_defender)
		if unlocked_defender_strength_after >= unlocked_defender_strength_before:
			failures.append("assigned soldier in spear range did not deal damage before socket lock")
		line_player.call("_lock_combat_soldier", line_attacker, line_defender)
		line_player.call("_update_combat_debug_lines")
		var fighting_relation: Dictionary = line_player.call("get_combat_target_relation_for_soldier", line_attacker) as Dictionary
		var fighting_summary := _get_summary(line_player)
		if StringName(fighting_relation.get("status", &"")) != &"fighting":
			failures.append("locked in-range soldier target relation should become fighting")
		if int(fighting_summary.get("combat_debug_line_fighting_pair_count", 0)) < 1:
			failures.append("combat debug red line should keep counting assigned in-range fighting pairs")
		var defender_strength_before := _get_soldier_strength(line_defender)
		line_player.call("_update_soldier_attack", line_attacker, line_defender, 10.0)
		var defender_strength_after := _get_soldier_strength(line_defender)
		if defender_strength_after >= defender_strength_before:
			failures.append("locked red-line fighting pair did not deal soldier damage")

	_free_test_node(line_player)
	_free_test_node(line_enemy)

	var surround_player := _make_troop(&"four_surround_player", &"player", Vector3(30.0, 0.0, 88.0), movement_map)
	var surround_enemy := _make_troop(&"four_surround_enemy", &"enemy", Vector3(34.0, 0.0, 88.0), movement_map)
	surround_player.set("soldier_count", 4)
	surround_player.set("formation_columns", 4)
	surround_player.set("base_soldier_strength", 1000.0)
	surround_player.set("soldier_strength_variance", 0.0)
	surround_player.set("combat_range_m", 24.0)
	surround_player.set("combat_spear_range_m", 3.2)
	surround_player.set("combat_socket_radius", 1.7)
	surround_player.set("combat_socket_arrival_radius", 0.32)
	surround_player.set("combat_slot_follow_speed", 1.0)
	surround_player.set("combat_max_attackers_per_target", 4)
	surround_player.set("combat_attacker_updates_per_tick", 8)
	surround_player.set("combat_target_assignment_budget_per_tick", 8)
	surround_player.set("combat_rebalance_interval", 0.05)
	surround_player.set("combat_logic_interval", 0.0)
	surround_player.set("attack_interval", 0.08)
	surround_player.set("base_soldier_damage", 2.0)
	surround_player.set("soldier_damage_variance", 0.0)
	surround_player.set("attack_engagement_delay", 0.0)
	surround_enemy.set("soldier_count", 1)
	surround_enemy.set("formation_columns", 1)
	surround_enemy.set("defensive_engagement_range_m", 24.0)
	surround_enemy.set("combat_spear_range_m", 3.2)
	surround_enemy.set("base_soldier_strength", 1000.0)
	surround_enemy.set("soldier_strength_variance", 0.0)
	surround_enemy.set("base_soldier_damage", 0.1)
	surround_enemy.set("soldier_damage_variance", 0.0)
	surround_enemy.set("defensive_engagement_delay", 0.0)
	root.add_child(surround_player)
	root.add_child(surround_enemy)
	await _wait_frames(8)
	var surround_attackers := _get_active_soldier_nodes(surround_player)
	var surround_defenders := _get_active_soldier_nodes(surround_enemy)
	if surround_attackers.size() < 4 or surround_defenders.is_empty():
		failures.append("four-surround combat setup did not spawn expected active soldiers")
	else:
		var surround_defender := surround_defenders[0] as Node3D
		surround_defender.global_position = Vector3(34.0, 0.0, 88.0)
		var surround_offsets := [
			Vector3(2.35, 0.0, 0.0),
			Vector3(0.0, 0.0, -2.35),
			Vector3(0.0, 0.0, 2.35),
			Vector3(-2.35, 0.0, 0.0),
		]
		for index: int in range(4):
			var surround_attacker := surround_attackers[index] as Node3D
			surround_attacker.global_position = surround_defender.global_position + surround_offsets[index]
		var defender_strength_before := _get_soldier_strength(surround_defender)
		if not bool(surround_player.call("command_attack_troop", surround_enemy)):
			failures.append("four-surround combat setup rejected attack command")
		else:
			await _wait_frames(12)
			var fighting_count := 0
			var animated_count := 0
			for index: int in range(4):
				var surround_attacker := surround_attackers[index]
				var relation: Dictionary = surround_player.call("get_combat_target_relation_for_soldier", surround_attacker) as Dictionary
				if StringName(relation.get("status", &"")) == &"fighting":
					fighting_count += 1
				if surround_attacker.has_method("is_formation_attacking") and bool(surround_attacker.call("is_formation_attacking")):
					animated_count += 1
			var surround_summary := _get_summary(surround_player)
			if fighting_count != 4:
				failures.append("four attackers surrounding one defender should all report fighting status; got %d" % fighting_count)
			if animated_count != 4:
				failures.append("four attackers surrounding one defender should all use fighting animation; got %d" % animated_count)
			await _wait_frames(36)
			surround_summary = _get_summary(surround_player)
			if int(surround_summary.get("combat_visual_thrust_count", 0)) < 4:
				failures.append("four attackers surrounding one defender should all produce attack thrusts")
			var defender_survived := is_instance_valid(surround_defender)
			var defender_strength_after := _get_soldier_strength(surround_defender) if defender_survived else -INF
			if defender_survived and defender_strength_after >= defender_strength_before:
				failures.append("four-surround fighting did not deal damage to the defender")
			if defender_survived:
				var stability_metrics := await _sample_surround_combat_stability(
					surround_player,
					surround_attackers.slice(0, 4),
					surround_defender,
					360
				)
				_print_metrics("four_surround_stability", stability_metrics)
				if int(stability_metrics.get("min_fighting_count", 0)) < 4:
					failures.append(
						"four-surround combat dropped fighting status during sustained combat; min=%d"
						% int(stability_metrics.get("min_fighting_count", 0))
					)
				if int(stability_metrics.get("min_animated_count", 0)) < 4:
					failures.append(
						"four-surround combat dropped fighting animation during sustained combat; min=%d"
						% int(stability_metrics.get("min_animated_count", 0))
					)
				if int(stability_metrics.get("thrust_delta", 0)) < 4:
					failures.append("four-surround combat stopped producing attack thrusts during sustained combat")
				if float(stability_metrics.get("strength_delta", 0.0)) <= 0.0:
					failures.append("four-surround combat stopped dealing damage during sustained combat")

	_free_test_node(surround_player)
	_free_test_node(surround_enemy)

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
	if bool(regroup_metrics.get("render_batching_enabled", false)) and regroup_frames > 0 and regroup_sync_count < int(float(regroup_frames) * 0.75):
		failures.append(
			"idle regroup render sync was sparse (%d syncs over %d independent-motion frames)"
			% [regroup_sync_count, regroup_frames]
		)
	if bool(regroup_metrics.get("render_batching_enabled", false)) and int(regroup_metrics.get("render_sync_skips", 0)) > 0 and regroup_sync_count <= 0:
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
	var min_animation_bone := INF
	var max_animation_bone := -INF
	var saw_walk_animation := false
	var primary_animation_name := ""
	var primary_animation_playing := false
	for _index: int in range(frame_count):
		await _wait_frames(1)
		var current_positions := _get_soldier_positions(troop)
		var animation_sample := _get_primary_animation_sample(troop)
		if not animation_sample.is_empty():
			var animation_name := String(animation_sample.get("animation", ""))
			if not animation_name.is_empty():
				primary_animation_name = animation_name
				saw_walk_animation = saw_walk_animation or animation_name.contains("Walk")
			primary_animation_playing = primary_animation_playing or bool(animation_sample.get("playing", false))
			var animation_bone_value: Variant = animation_sample.get("bone_value", null)
			if animation_bone_value != null:
				min_animation_bone = minf(min_animation_bone, float(animation_bone_value))
				max_animation_bone = maxf(max_animation_bone, float(animation_bone_value))
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
	var animation_bone_range := 0.0
	if min_animation_bone < INF and max_animation_bone > -INF:
		animation_bone_range = max_animation_bone - min_animation_bone
	return {
		"max_step_m": max_step,
		"facing_checks": facing_checks,
		"facing_errors": facing_errors,
		"render_batching_enabled": bool(summary.get("soldier_render_batching_enabled", false)),
		"render_sync_count": int(summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(summary.get("soldier_render_sync_skip_count", 0)),
		"render_sync_max_ms": float(summary.get("soldier_render_max_sync_ms", 0.0)),
		"render_writes": int(summary.get("soldier_render_max_transform_writes", 0)),
		"independent_motions": _count_independent_motions(troop),
		"animation": primary_animation_name,
		"animation_bone_range": animation_bone_range,
		"animation_playing": primary_animation_playing,
		"saw_walk_animation": saw_walk_animation,
		"state": String(summary.get("state", &"")),
	}


func _sample_attack_transition(attacker: Node, defender: Node) -> Dictionary:
	var accepted := false
	if attacker.has_method("command_attack_troop"):
		accepted = bool(attacker.call("command_attack_troop", defender))
	if defender.has_method("command_attack_troop"):
		defender.call("command_attack_troop", attacker)
	if not accepted:
		return {
			"reached_fighting": false,
			"render_batching_enabled": _is_render_batching_enabled(attacker),
			"render_sync_count": 0,
			"render_sync_skips": 0,
		}

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
		"render_batching_enabled": bool(summary.get("soldier_render_batching_enabled", false)),
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
		"render_batching_enabled": bool(final_summary.get("soldier_render_batching_enabled", false)),
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
		"render_batching_enabled": bool(summary.get("soldier_render_batching_enabled", false)),
		"render_sync_count": int(summary.get("soldier_render_sync_count", 0)),
		"render_sync_skips": int(summary.get("soldier_render_sync_skip_count", 0)),
		"state": String(summary.get("state", &"")),
		"independent_motions": _count_independent_motions(troop),
	}


func _sample_surround_combat_stability(
	troop: Node,
	attackers: Array,
	defender: Node3D,
	frame_count: int
) -> Dictionary:
	var min_fighting_count := attackers.size()
	var min_animated_count := attackers.size()
	var first_strength := _get_soldier_strength(defender)
	var first_summary := _get_summary(troop)
	var first_thrust_count := int(first_summary.get("combat_visual_thrust_count", 0))
	var final_strength := first_strength
	var final_thrust_count := first_thrust_count
	var sampled_windows := 0
	for frame_index: int in range(frame_count):
		await _wait_frames(1)
		if not is_instance_valid(defender):
			break
		if frame_index % 30 != 29:
			continue
		sampled_windows += 1
		var fighting_count := 0
		var animated_count := 0
		for attacker_variant: Variant in attackers:
			if typeof(attacker_variant) != TYPE_OBJECT or not is_instance_valid(attacker_variant):
				continue
			var attacker := attacker_variant as Node
			if not attacker:
				continue
			var relation: Dictionary = troop.call("get_combat_target_relation_for_soldier", attacker) as Dictionary
			if StringName(relation.get("status", &"")) == &"fighting":
				fighting_count += 1
			if attacker.has_method("is_formation_attacking") and bool(attacker.call("is_formation_attacking")):
				animated_count += 1
		min_fighting_count = mini(min_fighting_count, fighting_count)
		min_animated_count = mini(min_animated_count, animated_count)
		final_strength = _get_soldier_strength(defender)
		final_thrust_count = int(_get_summary(troop).get("combat_visual_thrust_count", 0))
	return {
		"sampled_windows": sampled_windows,
		"min_fighting_count": min_fighting_count,
		"min_animated_count": min_animated_count,
		"strength_delta": first_strength - final_strength,
		"thrust_delta": final_thrust_count - first_thrust_count,
		"final_strength": final_strength,
		"final_thrust_count": final_thrust_count,
		"state": String(_get_summary(troop).get("state", &"")),
		"assigned_count": int(_get_summary(troop).get("combat_assigned_target_count", 0)),
	}


func _assert_active_render_sync(label: String, metrics: Dictionary, failures: Array[String]) -> void:
	if not bool(metrics.get("render_batching_enabled", false)):
		return
	var skips := int(metrics.get("render_sync_skips", 0))
	if skips > 0 and label != "moving" and int(metrics.get("render_sync_count", 0)) <= 0:
		failures.append("%s skipped all active soldier render syncs; visible movement will stutter" % label)
	var sync_count := int(metrics.get("render_sync_count", 0))
	if sync_count <= 0:
		failures.append("%s did not sync batched soldier transforms while active" % label)


func _assert_animation_player_walk(label: String, metrics: Dictionary, failures: Array[String]) -> void:
	if not bool(metrics.get("animation_playing", false)):
		failures.append("%s soldier AnimationPlayer was not playing" % label)
	if not bool(metrics.get("saw_walk_animation", false)):
		failures.append(
			"%s soldier did not use the imported walk animation; current=%s"
			% [label, String(metrics.get("animation", ""))]
		)
	var bone_range := float(metrics.get("animation_bone_range", 0.0))
	if bone_range < MIN_ANIMATION_BONE_RANGE:
		failures.append(
			"%s imported skeleton did not move through AnimationPlayer; bone range %.6f below %.6f"
			% [label, bone_range, MIN_ANIMATION_BONE_RANGE]
		)


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


func _is_render_batching_enabled(troop: Node) -> bool:
	return bool(_get_summary(troop).get("soldier_render_batching_enabled", false))


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


func _get_soldier_nodes(troop: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return nodes
	for soldier: Node in soldiers.get_children():
		nodes.append(soldier)
	return nodes


func _get_active_soldier_nodes(troop: Node) -> Array[Node]:
	var active: Array[Node] = []
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.has_method("is_combat_active"):
			if bool(soldier.call("is_combat_active")):
				active.append(soldier)
		elif soldier.has_method("is_alive"):
			if bool(soldier.call("is_alive")):
				active.append(soldier)
		else:
			active.append(soldier)
	return active


func _is_soldier_alive(soldier: Node) -> bool:
	if soldier.has_method("is_alive"):
		return bool(soldier.call("is_alive"))
	return true


func _get_soldier_strength(soldier: Node) -> float:
	if not soldier:
		return 0.0
	if soldier.has_method("get_combat_summary"):
		var summary: Dictionary = soldier.call("get_combat_summary") as Dictionary
		return float(summary.get("strength", 0.0))
	if soldier.has_method("get_strength"):
		return float(soldier.call("get_strength"))
	return 0.0


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


func _get_yaw_error_degrees(yaw: float, direction: Vector3) -> float:
	var flat_direction := direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.0001:
		return 0.0
	flat_direction = flat_direction.normalized()
	var expected_yaw := atan2(-flat_direction.x, -flat_direction.z)
	return rad_to_deg(absf(angle_difference(yaw, expected_yaw)))


func _get_primary_animation_sample(troop: Node) -> Dictionary:
	var soldiers := troop.get_node_or_null("Soldiers") if troop else null
	if not soldiers:
		return {}
	for soldier_node: Node in soldiers.get_children():
		if not (soldier_node is Node3D) or not _is_soldier_alive(soldier_node):
			continue
		var player := soldier_node.get_node_or_null("VisualRoot/ExternalModelSocket/PersonAnimated/AnimationPlayer") as AnimationPlayer
		var skeleton := soldier_node.get_node_or_null("VisualRoot/ExternalModelSocket/PersonAnimated/Armature/Skeleton3D") as Skeleton3D
		if not player or not skeleton:
			continue
		return {
			"animation": player.current_animation,
			"playing": player.is_playing(),
			"bone_value": _get_skeleton_animation_value(skeleton),
		}
	return {}


func _get_skeleton_animation_value(skeleton: Skeleton3D) -> Variant:
	var bone_names := [
		"Hand.R",
		"Hand.L",
		"UpperLeg.R",
		"UpperLeg.L",
		"LowerLeg.R",
		"LowerLeg.L",
	]
	var value := 0.0
	var weight := 1.0
	var found_bone := false
	for bone_name: String in bone_names:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone_index)
		value += weight * (
			pose.origin.x
			+ pose.origin.y * 1.37
			+ pose.origin.z * 1.91
			+ pose.basis.x.x * 0.31
			+ pose.basis.x.y * 0.37
			+ pose.basis.x.z * 0.41
			+ pose.basis.y.x * 0.43
			+ pose.basis.y.y * 0.47
			+ pose.basis.y.z * 0.53
			+ pose.basis.z.x * 0.59
			+ pose.basis.z.y * 0.61
			+ pose.basis.z.z * 0.67
		)
		weight += 0.17
		found_bone = true
	return value if found_bone else null


func _print_metrics(label: String, metrics: Dictionary) -> void:
	print("[SMOOTHNESS] %s %s" % [label, JSON.stringify(metrics)])
