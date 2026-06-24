extends SceneTree

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")
const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")
const TroopSelectionControllerScript = preload("res://modules/troops/troop_selection_controller.gd")
const TroopEnemySpawnerScript = preload("res://modules/troops/troop_enemy_spawner.gd")
const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const TroopDrawerScene: PackedScene = preload("res://modules/troops/troop_management_drawer.tscn")
const TroopJobsDebugPanelScene: PackedScene = preload("res://modules/troops/troop_background_jobs_debug_panel.tscn")
const RTSCameraScene: PackedScene = preload("res://modules/camera/rts_camera.tscn")


class FakeVillage:
	extends Node3D

	var storage_food_kg := 100.0

	func get_village_storage_summary() -> Dictionary:
		return {
			"storage_food_kg": storage_food_kg,
			"storage_world_position": global_position,
		}

	func get_village_storage_world_position() -> Vector3:
		return global_position

	func withdraw_food_kg(amount_kg: float) -> float:
		var withdrawn := minf(maxf(amount_kg, 0.0), storage_food_kg)
		storage_food_kg -= withdrawn
		return withdrawn


class FakeForest:
	extends Node3D

	var tree_cells := {Vector2i(0, 0): true}
	var cow_cells := {Vector2i(1, 0): true}

	func is_tree_cell(cell: Vector2i) -> bool:
		return tree_cells.has(cell)

	func get_tree_cells() -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for cell: Vector2i in tree_cells.keys():
			cells.append(cell)
		return cells

	func is_cow_cell(cell: Vector2i) -> bool:
		return cow_cells.has(cell)

	func harvest_wood_cell(cell: Vector2i, amount_kg: float) -> float:
		if not tree_cells.has(cell):
			return 0.0
		tree_cells.erase(cell)
		return minf(maxf(amount_kg, 0.0), 240.0)

	func pickup_cow_cell(cell: Vector2i) -> bool:
		if not cow_cells.has(cell):
			return false
		cow_cells.erase(cell)
		return true

	func get_cell_world_position(cell: Vector2i) -> Vector3:
		return global_position + Vector3(float(cell.x) * 4.0, 0.0, float(cell.y) * 4.0)


func _init() -> void:
	_run_deferred_checks.call_deferred()


func _run_deferred_checks() -> void:
	var failures: Array[String] = []
	await process_frame
	await _run_checks(failures)
	if failures.is_empty():
		print("Troop management headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_check_pathfinder_avoids_blocked_cells(failures)
	_check_pathfinder_smooths_open_routes(failures)
	_check_pathfinder_reports_unreachable(failures)
	await _check_troop_scene_and_exports(failures)
	await _check_killed_soldiers_remain_as_corpses(failures)
	await _check_troop_route_visuals(failures)
	await _check_destination_arrival_settles_soldiers(failures)
	await _check_manual_move_uses_flag_point_as_anchor(failures)
	await _check_simple_move_preserves_formation_slots(failures)
	await _check_moving_retarget_skips_startup_reform(failures)
	await _check_moving_compacts_missing_formation_slots(failures)
	await _check_formation_drag_command(failures)
	await _check_enemy_route_visuals_are_hidden(failures)
	await _check_troop_modes_and_combat_stats(failures)
	await _check_large_troop_stat_worker_path(failures)
	await _check_endurance_running_and_noncombat_recovery(failures)
	await _check_soldier_activity_pose_states(failures)
	await _check_troop_combat_resolution(failures)
	await _check_large_combat_uses_bounded_work(failures)
	await _check_combat_socket_targets_stay_local(failures)
	await _check_combat_debug_lines_only_show_near_fights(failures)
	await _check_combat_surround_sockets_and_facing(failures)
	await _check_combat_target_capacity(failures)
	await _check_normal_combat_assigns_all_attackers_with_capacity(failures)
	await _check_large_default_combat_assigns_all_when_capacity_exists(failures)
	await _check_combat_state_forgets_departed_soldiers(failures)
	await _check_flag_hover_and_defeated_indicators(failures)
	await _check_enemy_selection_and_read_only_drawer(failures)
	await _check_attack_target_command_and_survivor_rout(failures)
	await _check_troop_desertion(failures)
	await _check_enemy_spawner(failures)
	await _check_automatic_logistics_commands(failures)
	await _check_carrier_visuals_are_independent_and_labeled(failures)
	await _check_troop_logistics_tasks(failures)
	_check_forest_region_gathering_api(failures)
	await _check_camera_recovers_from_consumed_right_release(failures)
	_check_drawer_loads(failures)
	await _check_background_jobs_debug_panel(failures)
	_check_scene_wiring("res://modules/draft/draft.tscn", failures)
	_check_scene_wiring("res://maps/midlands/midlands.tscn", failures)


func _check_pathfinder_avoids_blocked_cells(failures: Array[String]) -> void:
	var data := _make_map(6, 4)
	_set_blocked(data, Vector2i(2, 0))
	_set_blocked(data, Vector2i(2, 1))
	_set_blocked(data, Vector2i(2, 3))

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		data,
		Vector3(0.5, 0.0, 1.5),
		Vector3(5.5, 0.0, 1.5),
		1.0,
		4
	)
	_expect(bool(result.get("reachable", false)), "pathfinder should route through the wall gap", failures)
	var cells: Array = result.get("cells", [])
	_expect(cells.has(Vector2i(2, 2)), "pathfinder should use the only walkable wall gap", failures)
	for cell: Vector2i in cells:
		_expect(data.is_walkable_cell(cell), "pathfinder route should not include blocked cells", failures)
	var points: Array = result.get("points", [])
	for point: Vector3 in points:
		_expect(data.is_walkable_cell(data.world_to_cell(point)), "smoothed path points should remain on walkable cells", failures)


func _check_pathfinder_smooths_open_routes(failures: Array[String]) -> void:
	var data := _make_map(8, 8)
	var result: Dictionary = MovementMapPathfinderScript.find_path(
		data,
		Vector3(0.5, 0.0, 0.5),
		Vector3(6.5, 0.0, 6.5),
		1.0,
		4
	)
	_expect(bool(result.get("reachable", false)), "pathfinder should accept an open diagonal route", failures)
	var points: Array = result.get("points", [])
	_expect(points.size() == 2, "open routes should be smoothed to a direct path", failures)


func _check_pathfinder_reports_unreachable(failures: Array[String]) -> void:
	var data := _make_map(5, 3)
	for y: int in range(3):
		_set_blocked(data, Vector2i(2, y))

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		data,
		Vector3(0.5, 0.0, 1.5),
		Vector3(4.5, 0.0, 1.5),
		1.0,
		3
	)
	_expect(not bool(result.get("reachable", true)), "pathfinder should reject unreachable targets", failures)
	_expect(
		StringName(result.get("failure_reason", &"")) == MovementMapPathfinderScript.FAILURE_UNREACHABLE,
		"unreachable path should report the unreachable failure reason",
		failures
	)


func _check_troop_scene_and_exports(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 8)
	troop.set("formation_columns", 4)
	troop.set("team_flag_color", Color.BLUE)
	troop.set("troop_flag_color", Color.RED)
	root.add_child(troop)
	await process_frame

	_expect(int(troop.call("get_soldier_count")) == 8, "troop should rebuild exported soldier count", failures)
	_expect(int(troop.call("get_flag_holder_count")) == 2, "troop should create two flag holders", failures)
	_expect(_flag_uses_unshaded_materials(troop, "TeamFlag"), "team hand flag should ignore scene lighting", failures)
	_expect(_flag_uses_unshaded_materials(troop, "TroopFlag"), "troop hand flag should ignore scene lighting", failures)
	_expect(float(troop.get("path_corner_radius_cells")) >= 1.0, "troop should expose broad path corner smoothing", failures)
	_expect(int(troop.get("path_corner_samples")) >= 8, "troop should expose dense curved path samples", failures)
	_expect(float(troop.get("route_steering_lookahead_m")) > 0.0, "troop should expose curved route steering lookahead", failures)
	_expect(float(troop.get("formation_turn_rate_degrees")) > 0.0, "troop should expose formation turn smoothing speed", failures)
	_expect(float(troop.get("formation_turn_inner_lag")) >= 0.0, "troop should expose formation corner lag tuning", failures)
	_expect(float(troop.get("formation_natural_unevenness")) >= 0.0, "troop should expose stable formation unevenness tuning", failures)
	_expect(_approx(float(troop.get("formation_spacing")), 4.35, 0.001), "troop formation spacing should default to 1.5x the current movement spacing", failures)
	_expect(_approx(float(troop.get("formation_collision_distance")), 2.64, 0.001), "moving formation collision spacing should default to 1.5x the current distance", failures)
	_expect(_approx(float(troop.get("carrier_formation_spacing")), 3.75, 0.001), "carrier formation spacing should default to 1.5x the current spacing", failures)
	_expect(_approx(float(troop.get("combat_spear_range_m")), 9.4, 0.001), "combat spear range should default to 2x the current fighting spacing", failures)
	_expect(_approx(float(troop.get("soldier_personal_space_radius")), 2.88, 0.001), "soldier combat personal space should default to 2x the current fighting spacing", failures)
	_expect(_approx(float(troop.get("enemy_personal_space_radius")), 3.28, 0.001), "enemy combat personal space should default to 2x the current fighting spacing", failures)
	_expect(_approx(float(troop.get("combat_frontline_width_per_soldier")), 4.4, 0.001), "combat frontline spacing should default to 2x the current fighting spacing", failures)
	_expect(float(troop.get("combat_logic_interval")) > 0.0, "troops should expose a lower-frequency combat logic interval", failures)
	_expect(float(troop.get("combat_target_reassignment_interval")) > 0.0, "troops should expose throttled combat target reassignment", failures)
	_expect(float(troop.get("combat_rebalance_interval")) > 0.0, "troops should expose throttled combat target rebalancing", failures)
	_expect(int(troop.get("combat_target_assignment_budget_per_tick")) > 0, "troops should expose a per-tick combat target assignment budget", failures)
	_expect(int(troop.get("combat_separation_updates_per_tick")) > 0, "troops should expose a per-tick combat separation update budget", failures)
	_expect(int(troop.get("combat_pair_checks_budget_per_tick")) > 0, "troops should expose a per-tick combat pair-check budget", failures)
	_expect(float(troop.get("combat_steering_refresh_interval")) > 0.0, "troops should expose cached combat steering refresh timing", failures)
	_expect(float(troop.get("formation_slot_refresh_interval")) > 0.0, "troops should expose moving formation target refresh timing", failures)
	_expect(float(troop.get("formation_slot_target_epsilon_m")) > 0.0, "troops should expose moving formation target epsilon", failures)
	_expect(float(troop.get("formation_turn_target_refresh_degrees")) >= 0.0, "troops should expose moving formation turn refresh threshold", failures)
	_expect(int(troop.get("formation_separation_updates_per_tick")) > 0, "troops should expose a moving formation separation update budget", failures)
	_expect(int(troop.get("formation_pair_checks_budget_per_tick")) > 0, "troops should expose a moving formation pair-check budget", failures)
	_expect(int(troop.get("combat_max_separation_neighbors")) >= 8, "combat separation should cap nearby neighbor checks", failures)
	_expect(int(troop.get("combat_target_search_candidates")) >= 12, "combat target search should cap candidate scans", failures)
	_expect(int(troop.get("combat_assignment_candidates")) >= 8, "combat assignment should cap nearby target candidates", failures)
	_expect(int(troop.get("combat_max_attackers_per_target")) == 4, "combat should default to four attackers per defender", failures)
	_expect(float(troop.get("combat_socket_radius")) > 0.0, "combat should expose defender attack socket radius", failures)
	_expect(float(troop.get("combat_socket_arrival_radius")) > 0.0, "combat should expose socket arrival tolerance", failures)
	_expect(bool(troop.get("soldier_render_batching_enabled")), "soldier render batching should be enabled by default", failures)
	_expect(float(troop.get("unit_selection_proxy_refresh_interval")) > 0.0, "unit selection proxies should expose a throttled refresh interval", failures)
	_expect(float(troop.get("unit_selection_proxy_radius")) >= 0.8, "soldier selection proxies should use a wider click target", failures)
	_expect(float(troop.get("unit_selection_proxy_height")) >= 2.5, "soldier selection proxies should use a taller click target", failures)
	_expect(int(troop.get("survivor_rout_active_threshold")) == 5, "survivor rout should trigger when only 4-5 active soldiers remain", failures)
	_expect(_approx(float(troop.get("survivor_rout_speed_multiplier")), 1.5, 0.001), "survivor rout should flee at 1.5x running speed", failures)
	_expect(_approx(float(troop.get("endurance_rate_scale")), 0.2, 0.001), "endurance rates should be five times slower by default", failures)
	_expect(_approx(float(troop.get("running_speed_multiplier")), 3.0, 0.001), "running movement should default to 3x soldier run speed", failures)
	_expect(float(troop.get("base_soldier_run_speed")) > 0.0, "troops should expose a base soldier run speed stat", failures)
	_expect(float(troop.get("training_strength_soft_cap")) > float(troop.get("base_soldier_strength")), "training should expose a higher HP soft cap", failures)
	_expect(_approx(float(troop.get("fighting_growth_multiplier")), 5.0, 0.001), "fighting stat growth should default to five times training", failures)
	_expect(troop.has_method("has_attack_zone_indicator"), "troop should expose attack-zone indicator visibility", failures)
	_expect(troop.has_method("get_attack_zone_corners"), "troop should expose formation-footprint attack zone corners", failures)
	_expect(troop.has_method("is_world_position_in_attack_zone"), "troop should expose formation-footprint attack zone hit tests", failures)
	var management_flag_size: Vector2 = troop.get("management_flag_banner_size")
	_expect(management_flag_size.y > management_flag_size.x, "management flag banner should be taller than it is wide", failures)
	_expect(management_flag_size.y >= 1.8, "management flag banner should be larger than the old compact flag", failures)
	_expect(int(troop.get("camp_soldiers_per_living_hut")) == 20, "troop camps should use one living hut per 20 soldiers by default", failures)
	_expect(_approx(float(troop.get("camp_living_hut_wood_cost_kg")), 100.0, 0.001), "troop living huts should cost 100kg wood by default", failures)
	_expect(_approx(float(troop.get("camp_building_scale")), 2.1, 0.001), "troop camps should use the reduced 0.7x building scale by default", failures)
	_expect(_approx(float(troop.get("cargo_trolley_craft_seconds")), 5.0, 0.001), "troop trolleys should take 5 seconds to craft by default", failures)
	_expect(int(troop.call("get_camp_living_hut_count")) == 1, "small troops should still need one living hut", failures)
	_expect(_approx(float(troop.call("get_camp_total_wood_cost_kg")), 100.0, 0.001), "one camp living hut should cost 100kg wood", failures)
	var first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	_expect(first_soldier != null, "troop should create a first soldier node", failures)
	var unit_proxy: StaticBody3D = null
	if first_soldier:
		_expect(first_soldier.has_method("get_right_hand_socket"), "troop soldier should inherit the human unit API", failures)
		_expect(first_soldier.has_method("set_formation_walking"), "troop soldier should expose formation walking animation control", failures)
		_expect((first_soldier as Node3D).top_level, "formation soldiers should own world movement instead of inheriting troop movement", failures)
		_expect(first_soldier.has_method("follow_formation_path"), "troop soldier should retain the fallback formation path API", failures)
		_expect(first_soldier.has_method("set_independent_move_target"), "troop soldier should receive independent world move targets", failures)
		_expect(first_soldier.has_method("set_independent_combat"), "troop soldier should expose independent combat control", failures)
		_expect(first_soldier.has_method("set_combat_focus_target"), "troop soldier should expose combat focus facing while walking to sockets", failures)
		_expect(first_soldier.has_method("trigger_spear_thrust"), "troop soldier should expose procedural spear thrust animation", failures)
		_expect(first_soldier.has_method("set_activity_mode"), "troop soldier should expose procedural activity mode control", failures)
		_expect(first_soldier.has_method("get_activity_variant"), "troop soldier should expose its current activity variant", failures)
		_expect(first_soldier.has_method("train_stats_with_caps"), "troop soldier should support soft-capped training growth", failures)
		_expect(first_soldier.has_method("apply_fight_growth"), "troop soldier should support fighting stat growth", failures)
		var carried_spear := first_soldier.find_child("LowPolySpear", true, false) as Node3D
		_expect(carried_spear != null, "troop soldier should carry a long spear", failures)
		if carried_spear:
			_expect(_approx(_get_spear_visual_length_m(carried_spear), 1.9, 0.01), "troop soldier spear should be 1.9m long", failures)
			_expect(absf(_get_spear_shaft_center_grip_offset_m(carried_spear)) <= 0.03, "troop soldier should hold the spear near the shaft midpoint", failures)
		var soldier_summary: Dictionary = first_soldier.call("get_combat_summary") as Dictionary
		_expect(float(soldier_summary.get("run_speed", 0.0)) > 0.0, "soldier summaries should expose running speed", failures)
		var first_mesh := _find_first_mesh_instance(first_soldier)
		var render_summary: Dictionary = troop.call("get_troop_summary") as Dictionary
		var batch_renderer := troop.get_node_or_null("TroopSoldierBatchRenderer")
		_expect(batch_renderer != null, "troops should create a soldier batch renderer", failures)
		if batch_renderer:
			_expect(bool(batch_renderer.get("multimesh_buffer_sync_enabled")), "soldier batch renderer should use packed buffer sync once transform-space changes force full syncs", failures)
		_expect(int(render_summary.get("soldier_render_batch_count", 0)) > 0, "soldier batch renderer should create mesh-part batches", failures)
		_expect(int(render_summary.get("soldier_render_batched_instance_count", 0)) >= int(render_summary.get("soldier_render_batch_count", 0)), "soldier batch renderer should publish visible batched instances", failures)
		_expect(int(render_summary.get("soldier_render_hidden_source_mesh_count", 0)) > 0, "soldier batch renderer should hide source mesh instances while batching", failures)
		if first_mesh:
			_expect(not first_mesh.visible, "source soldier meshes should be hidden while render batching is enabled", failures)
			troop.set("soldier_render_batching_enabled", false)
			await process_frame
			_expect(first_mesh.visible, "source soldier meshes should be restored when render batching is disabled", failures)
			troop.set("soldier_render_batching_enabled", true)
			await process_frame
		unit_proxy = first_soldier.get_node_or_null("TroopUnitClickProxy") as StaticBody3D
		_expect(unit_proxy != null, "troop soldiers should expose unit click proxies for troop selection", failures)
		if unit_proxy:
			_expect(unit_proxy.has_meta(&"troop_selectable_type"), "unit click proxies should carry troop metadata", failures)
			var proxy_shape_node := unit_proxy.get_child(0) as CollisionShape3D
			var proxy_shape: CapsuleShape3D = null
			if proxy_shape_node:
				proxy_shape = proxy_shape_node.shape as CapsuleShape3D
			_expect(proxy_shape != null and proxy_shape.radius >= 0.8, "unit click proxy should be wide enough for easy soldier picking", failures)
			_expect(proxy_shape != null and proxy_shape.height >= 2.5, "unit click proxy should be tall enough for easy soldier picking", failures)
	troop.set("soldier_count", 40)
	await process_frame
	_expect(int(troop.call("get_camp_living_hut_count")) == 2, "forty soldiers should require two living huts", failures)
	_expect(_approx(float(troop.call("get_camp_total_wood_cost_kg")), 200.0, 0.001), "two camp living huts should cost 200kg wood", failures)
	_expect(bool(troop.call("has_management_flag")), "troop should create a management flag", failures)
	_expect(_flag_uses_unshaded_materials(troop, "TroopManagementFlag"), "management flag should ignore scene lighting", failures)
	var proxy := troop.call("get_selection_proxy") as StaticBody3D
	_expect(proxy != null, "troop should create a flag selection proxy", failures)
	if proxy:
		_expect(proxy.name == "TroopFlagClickProxy", "troop selection proxy should be attached to the management flag", failures)
		_expect(proxy.has_meta(&"troop_selectable_type"), "flag selection proxy should carry troop metadata", failures)
	unit_proxy = null
	var rebuilt_first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	if rebuilt_first_soldier:
		unit_proxy = rebuilt_first_soldier.get_node_or_null("TroopUnitClickProxy") as StaticBody3D
	var controller := TroopSelectionControllerScript.new()
	root.add_child(controller)
	if unit_proxy:
		_expect(controller.call("_get_troop_for_selectable", unit_proxy) == troop, "unit click proxy should resolve to the owning troop", failures)
	if proxy:
		_expect(controller.call("_get_troop_for_selectable", proxy) == troop, "flag click proxy should resolve to the owning troop", failures)
	if rebuilt_first_soldier:
		_expect(controller.call("_get_troop_for_selectable", rebuilt_first_soldier) == troop, "soldier metadata should resolve to the owning troop", failures)

	if rebuilt_first_soldier is Node3D:
		var camera := Camera3D.new()
		camera.name = "SelectionTestCamera"
		root.add_child(camera)
		var soldier_world := (rebuilt_first_soldier as Node3D).global_position + Vector3(0.0, 1.1, 0.0)
		camera.global_position = soldier_world + Vector3(0.0, 12.0, 16.0)
		camera.look_at(soldier_world, Vector3.UP)
		camera.current = true
		controller.set("camera_path", controller.get_path_to(camera))
		await process_frame
		var soldier_screen := camera.unproject_position(soldier_world)
		_expect(controller.call("_get_troop_at", soldier_screen) == troop, "clicking a soldier should pick the owning troop", failures)
		root.remove_child(camera)
		camera.free()
	root.remove_child(controller)
	controller.free()

	root.remove_child(troop)
	troop.free()


func _check_killed_soldiers_remain_as_corpses(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 3)
	troop.set("base_soldier_strength", 10.0)
	troop.set("soldier_strength_variance", 0.0)
	root.add_child(troop)
	await process_frame

	var soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	var corpses_before := _get_global_corpse_count()
	_expect(soldier != null, "soldier corpse check should find a soldier", failures)
	if soldier and soldier.has_method("apply_strength_damage"):
		soldier.call("apply_strength_damage", 999.0, &"test")
		await process_frame
		var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
		_expect(not is_instance_valid(soldier) or soldier.get_parent() == null, "killed soldiers should leave the current troop instead of staying as corpses", failures)
		_expect(int(summary.get("active_soldier_count", 0)) == 2, "killed soldiers should reduce the current troop count", failures)
		_expect(int(summary.get("dead_soldier_count", 0)) == 0, "troops should not keep a displayed dead-soldier bucket", failures)
		_expect(int(summary.get("corpse_count", 0)) > corpses_before, "killed soldiers should be registered with the render-only corpse manager", failures)
		_expect(int(summary.get("corpse_batch_count", 0)) > 0, "corpse manager should batch corpse mesh rendering", failures)

	root.remove_child(troop)
	troop.free()


func _check_troop_route_visuals(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("movement_map", _make_map(8, 8))
	troop.set("position", Vector3(0.5, 0.0, 0.5))
	troop.set("formation_separation_updates_per_tick", 2)
	troop.set("formation_pair_checks_budget_per_tick", 1)
	troop.set("formation_moving_separation_enabled", true)
	root.add_child(troop)
	await process_frame

	var accepted: bool = bool(troop.call("set_move_destination", Vector3(6.5, 0.0, 6.5)))
	_expect(accepted, "troop should accept a reachable movement order", failures)
	_expect(bool(troop.call("has_destination")), "troop should store a destination after a move order", failures)
	_expect(int(troop.call("get_route_dash_count")) > 0, "troop should draw dashed route visuals", failures)
	_expect(bool(troop.call("has_destination_marker")), "troop should draw a destination flag", failures)
	_expect(_flag_uses_unshaded_materials(troop, "TroopDestinationFlag"), "destination flag should ignore scene lighting", failures)
	var moving_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	if moving_soldier and moving_soldier.has_method("is_formation_walking"):
		_expect(bool(moving_soldier.call("is_formation_walking")), "troop soldier should play walking animation while troop moves", failures)
	_expect(_all_soldier_route_paths_empty(troop), "moving troops should not issue per-soldier route paths", failures)
	if moving_soldier is Node3D:
		var before_anchor_shift := (moving_soldier as Node3D).global_position
		troop.global_position += Vector3(2.0, 0.0, 0.0)
		_expect(
			(moving_soldier as Node3D).global_position.distance_to(before_anchor_shift) < 0.001,
			"formation soldiers should not slide when only the troop anchor moves",
			failures
		)
		troop.global_position -= Vector3(2.0, 0.0, 0.0)
	var overlap_a := troop.get_node_or_null("Soldiers/Soldier_000") as Node3D
	var overlap_b := troop.get_node_or_null("Soldiers/Soldier_001") as Node3D
	if overlap_a and overlap_b:
		overlap_b.global_position = overlap_a.global_position + Vector3(0.04, 0.0, 0.0)
		var separation_summary_before: Dictionary = troop.call("get_troop_summary") as Dictionary
		var separation_checks_before := int(separation_summary_before.get("moving_formation_pair_checks", 0))
		var spacing_before := _minimum_soldier_spacing(troop)
		troop.call("_physics_process", 0.2)
		var spacing_after := _minimum_soldier_spacing(troop)
		var separation_summary_after: Dictionary = troop.call("get_troop_summary") as Dictionary
		var separation_checks_delta := int(separation_summary_after.get("moving_formation_pair_checks", 0)) - separation_checks_before
		_expect(spacing_after > spacing_before, "moving formation separation should push overlapping soldiers apart", failures)
		_expect(separation_checks_delta <= int(troop.get("formation_pair_checks_budget_per_tick")), "moving formation separation should respect the pair-check budget", failures)
	troop.call("clear_destination")
	_expect(not bool(troop.call("has_destination")), "clear destination should remove active destination", failures)
	_expect(int(troop.call("get_route_dash_count")) == 0, "clear destination should clear route dashes", failures)
	if moving_soldier and moving_soldier.has_method("is_formation_walking"):
		_expect(not bool(moving_soldier.call("is_formation_walking")), "troop soldier should stop walking animation when troop movement clears", failures)

	root.remove_child(troop)
	troop.free()


func _check_destination_arrival_settles_soldiers(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 8)
	troop.set("formation_columns", 4)
	troop.set("formation_slot_follow_speed", 12.0)
	troop.set("movement_map", _make_map(32, 32))
	troop.set("position", Vector3(2.5, 0.0, 2.5))
	root.add_child(troop)
	await process_frame

	_expect(bool(troop.call("set_move_destination", Vector3(18.5, 0.0, 2.5))), "arrival settle check should accept a movement order", failures)
	for _step: int in range(120):
		_step_troop_with_soldiers(troop, 0.1)
		if not bool(troop.call("has_destination")):
			break

	_expect(not bool(troop.call("has_destination")), "arrival settle check should reach the destination", failures)
	var positions_at_arrival := _soldier_local_positions(troop)
	_step_troop_with_soldiers(troop, 0.1)
	var max_settle_step := _max_soldier_displacement(positions_at_arrival, _soldier_local_positions(troop))
	_expect(max_settle_step <= 0.05, "arrival completion should not leave soldiers correcting into formation afterward", failures)
	_expect(not _any_soldier_has_independent_motion(troop), "arrival completion should wait until soldier path commands are done", failures)
	_expect(_count_soldiers_away_from_slots(troop, 0.55) == 0, "arrival settle should eventually place soldiers near their final formation slots", failures)

	root.remove_child(troop)
	troop.free()


func _check_manual_move_uses_flag_point_as_anchor(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 8)
	troop.set("formation_columns", 4)
	troop.set("movement_map", _make_map(48, 48))
	troop.set("position", Vector3(4.5, 0.0, 4.5))
	root.add_child(troop)
	await process_frame

	for soldier: Node in _get_active_soldier_nodes(troop):
		if soldier is Node3D:
			(soldier as Node3D).global_position += Vector3(6.0, 0.0, 0.0)
	troop.call("_update_management_flag_position")
	var flag_position: Vector3 = troop.call("get_management_flag_world_position")
	var root_before := (troop as Node3D).global_position
	_expect(root_before.distance_to(flag_position) > 4.0, "anchor sync setup should leave the root behind the visible flag point", failures)

	_expect(bool(troop.call("set_move_destination", Vector3(30.5, 0.0, 4.5))), "manual anchor sync move should accept a destination", failures)
	var root_after := (troop as Node3D).global_position
	var root_to_flag := root_after - flag_position
	root_to_flag.y = 0.0
	_expect(root_to_flag.length() <= 0.08, "manual movement should start pathing from the management flag point", failures)

	var centroid_after := _average_soldier_world_position(troop)
	var centroid_delta := centroid_after - flag_position
	centroid_delta.y = 0.0
	_expect(centroid_delta.length() <= 0.08, "syncing the movement anchor should not drag soldiers backward", failures)

	root.remove_child(troop)
	troop.free()


func _check_moving_retarget_skips_startup_reform(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("formation_columns", 3)
	troop.set("movement_map", _make_map(48, 48))
	troop.set("route_steering_lookahead_m", 4.0)
	troop.set("position", Vector3(12.5, 0.0, 36.5))
	root.add_child(troop)
	await process_frame

	_expect(bool(troop.call("set_move_destination", Vector3(12.5, 0.0, 8.5))), "initial moving-retarget setup should accept a destination", failures)
	_step_troop_with_soldiers(troop, 0.2)
	_expect(bool(troop.call("has_destination")), "moving-retarget setup should leave the troop moving", failures)

	var first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	_expect(first_soldier != null, "moving-retarget check should find a soldier", failures)
	var slots_before_retarget := {}
	for soldier: Node in _get_active_soldier_nodes(troop):
		if soldier is Node3D:
			slots_before_retarget[soldier.get_instance_id()] = (soldier as Node3D).get_meta(&"troop_formation_slot", Vector3.ZERO)
	_expect(bool(troop.call("set_move_destination", Vector3(12.5, 0.0, 44.5))), "moving retarget should accept an opposite-direction destination", failures)
	if first_soldier:
		var path_points: Array = first_soldier.get("_independent_path_points")
		_expect(path_points.is_empty(), "moving retarget should not issue a per-soldier route path", failures)
		if first_soldier is Node3D:
			_expect((first_soldier as Node3D).has_meta(&"troop_formation_slot"), "opposite-direction retarget should keep a live formation slot", failures)
	var changed_retarget_slots := 0
	for soldier: Node in _get_active_soldier_nodes(troop):
		if not (soldier is Node3D):
			continue
		var old_slot: Vector3 = slots_before_retarget.get(soldier.get_instance_id(), Vector3.ZERO)
		var new_slot: Vector3 = (soldier as Node3D).get_meta(&"troop_formation_slot", Vector3.ZERO)
		if old_slot.distance_to(new_slot) > 0.05:
			changed_retarget_slots += 1
	_expect(changed_retarget_slots == 0, "ordinary moving retarget should preserve soldier formation slots", failures)
	_step_troop_with_soldiers(troop, 0.1)
	_expect(_all_soldier_route_paths_empty(troop), "moving retarget should continue using the formation anchor instead of soldier route paths", failures)

	root.remove_child(troop)
	troop.free()


func _check_simple_move_preserves_formation_slots(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("formation_columns", 3)
	troop.set("movement_map", _make_map(48, 48))
	troop.set("position", Vector3(12.5, 0.0, 12.5))
	root.add_child(troop)
	await process_frame

	var before_slots := {}
	for soldier: Node in _get_active_soldier_nodes(troop):
		if soldier is Node3D:
			before_slots[soldier.get_instance_id()] = (soldier as Node3D).get_meta(&"troop_formation_slot", Vector3.ZERO)

	_expect(bool(troop.call("set_move_destination", Vector3(12.5, 0.0, 36.5))), "ordinary move should accept a destination", failures)
	if troop is Node3D:
		var yaw_delta := wrapf((troop as Node3D).rotation.y - PI, -PI, PI)
		_expect(absf(yaw_delta) > 2.5, "ordinary move should not snap troop yaw to the route on command", failures)

	var changed_slots := 0
	var command_slots := {}
	for soldier: Node in _get_active_soldier_nodes(troop):
		if not (soldier is Node3D):
			continue
		var soldier_spatial := soldier as Node3D
		var assigned_slot: Vector3 = soldier_spatial.get_meta(&"troop_formation_slot", Vector3.ZERO)
		command_slots[soldier.get_instance_id()] = assigned_slot
		var before_slot: Vector3 = before_slots.get(soldier.get_instance_id(), assigned_slot)
		if before_slot.distance_to(assigned_slot) > 0.05:
			changed_slots += 1
	_expect(changed_slots == 0, "ordinary move should preserve soldier formation slots", failures)
	_expect(_all_soldier_route_paths_empty(troop), "ordinary move should use the formation anchor instead of per-soldier route paths", failures)

	_step_troop_with_soldiers(troop, 0.25)
	for soldier: Node in _get_active_soldier_nodes(troop):
		if not (soldier is Node3D):
			continue
		var stable_slot: Vector3 = (soldier as Node3D).get_meta(&"troop_formation_slot", Vector3.ZERO)
		var command_slot: Vector3 = command_slots.get(soldier.get_instance_id(), stable_slot)
		_expect(stable_slot.distance_to(command_slot) <= 0.001, "ordinary move slots should stay stable while moving", failures)

	root.remove_child(troop)
	troop.free()


func _check_moving_compacts_missing_formation_slots(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("formation_columns", 3)
	troop.set("movement_map", _make_map(32, 32))
	troop.set("base_soldier_strength", 10.0)
	troop.set("soldier_strength_variance", 0.0)
	troop.set("position", Vector3(4.5, 0.0, 4.5))
	root.add_child(troop)
	await process_frame

	var missing_soldier := troop.get_node_or_null("Soldiers/Soldier_001")
	_expect(missing_soldier != null, "missing-slot compaction setup should find a soldier to remove", failures)
	if missing_soldier and missing_soldier.has_method("apply_strength_damage"):
		missing_soldier.call("apply_strength_damage", 999.0, &"test")
	_expect(_get_active_soldier_nodes(troop).size() == 5, "missing-slot compaction setup should leave five active soldiers", failures)
	_expect(bool(troop.call("set_move_destination", Vector3(22.5, 0.0, 4.5))), "missing-slot compaction should still accept a movement order", failures)
	_expect(_active_formation_indices_are_compact(troop), "movement start should compact active soldier formation indices after losses", failures)

	root.remove_child(troop)
	troop.free()


func _check_formation_drag_command(failures: Array[String]) -> void:
	var controller := TroopSelectionControllerScript.new()
	root.add_child(controller)

	var troop := TroopScene.instantiate()
	troop.set("team_id", &"player")
	troop.set("controllable", true)
	troop.set("soldier_count", 8)
	troop.set("formation_columns", 2)
	troop.set("base_soldier_run_speed", 2.0)
	troop.set("soldier_run_speed_variance", 0.0)
	troop.set("formation_slot_follow_speed", 12.0)
	troop.set("movement_map", _make_map(24, 24))
	troop.set("position", Vector3(1.5, 0.0, 1.5))
	root.add_child(troop)
	await process_frame

	var first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	var first_soldier_id := first_soldier.get_instance_id() if first_soldier else 0
	controller.call("_select_troop", troop)
	controller.set("_formation_drag_active", true)
	controller.set("_formation_drag_start_world", Vector3(4.0, 0.0, 10.0))
	controller.set("_formation_drag_current_world", Vector3(18.0, 0.0, 10.0))
	controller.call("_update_formation_drag_preview")
	_expect(controller.find_child("FormationDragPreview", true, false) != null, "formation drag should show a terrain preview mesh", failures)
	controller.call("_reset_formation_drag_state")
	_expect(controller.find_child("FormationDragPreview", true, false) == null, "formation drag reset should clear the terrain preview mesh", failures)

	var accepted := bool(controller.call(
		"_issue_formation_drag_command",
		Vector3(4.0, 0.0, 10.0),
		Vector3(18.0, 0.0, 10.0)
	))
	_expect(accepted, "formation drag command should issue a reachable formation move", failures)
	_expect(int(troop.get("formation_columns")) == 4, "formation drag width should update formation columns without rebuilding soldiers", failures)
	var first_after := troop.get_node_or_null("Soldiers/Soldier_000")
	_expect(first_after != null and first_after.get_instance_id() == first_soldier_id, "formation drag should preserve existing soldier nodes", failures)
	_expect(bool(troop.call("has_destination")), "formation drag should create a movement destination", failures)
	for _step: int in range(120):
		if not bool(troop.call("has_destination")):
			break
		_step_troop_with_soldiers(troop, 0.1)
	_expect(not bool(troop.call("has_destination")), "formation drag movement should be able to finish", failures)
	_expect(_approx(troop.rotation.y, 0.0, 0.05), "horizontal formation drag should leave the troop facing perpendicular to the frontage line", failures)
	var positions_before_settle := _soldier_local_positions(troop)
	_step_troop_with_soldiers(troop, 0.1)
	var settle_displacement := _max_soldier_displacement(positions_before_settle, _soldier_local_positions(troop))
	_expect(settle_displacement <= 0.05, "formation drag completion should not leave a post-arrival correction step", failures)
	_expect(not _any_soldier_has_independent_motion(troop), "formation drag completion should wait for soldiers to reach their final slots", failures)
	_expect(_count_soldiers_away_from_slots(troop, 0.55) == 0, "formation drag completion should leave soldiers in the final command-time formation", failures)

	root.remove_child(troop)
	troop.free()
	root.remove_child(controller)
	controller.free()


func _check_enemy_route_visuals_are_hidden(failures: Array[String]) -> void:
	var enemy := TroopScene.instantiate()
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("movement_map", _make_map(16, 16))
	enemy.set("position", Vector3(1.5, 0.0, 1.5))
	root.add_child(enemy)
	await process_frame

	var accepted: bool = bool(enemy.call("set_move_destination", Vector3(12.5, 0.0, 12.5)))
	_expect(accepted, "enemy troop should still accept internal movement orders", failures)
	_expect(bool(enemy.call("has_destination")), "enemy internal movement should store a destination", failures)
	_expect(int(enemy.call("get_route_dash_count")) == 0, "enemy troops should not draw route dashes", failures)
	_expect(not bool(enemy.call("has_destination_marker")), "enemy troops should not draw destination flags", failures)

	var player := TroopScene.instantiate()
	player.set("team_id", &"player")
	player.set("soldier_count", 3)
	player.set("movement_map", _make_map(16, 16))
	player.set("position", Vector3(10.5, 0.0, 1.5))
	root.add_child(player)
	enemy.call("clear_destination")
	enemy.set("troop_mode", "attack")
	enemy.set("detection_range_m", 80.0)
	enemy.set("combat_range_m", 3.0)
	enemy.set("chase_repath_interval", 0.05)
	enemy.call("_physics_process", 0.2)
	_expect(int(enemy.call("get_route_dash_count")) == 0, "enemy auto-chase should not draw route dashes", failures)
	_expect(not bool(enemy.call("has_destination_marker")), "enemy auto-chase should not draw a destination flag", failures)

	root.remove_child(player)
	player.free()
	root.remove_child(enemy)
	enemy.free()


func _check_troop_modes_and_combat_stats(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 5)
	troop.set("carried_food_kg", 100.0)
	troop.set("base_soldier_strength", 40.0)
	troop.set("soldier_strength_variance", 0.0)
	troop.set("base_soldier_endurance", 60.0)
	troop.set("soldier_endurance_variance", 0.0)
	troop.set("base_soldier_damage", 5.0)
	troop.set("soldier_damage_variance", 0.0)
	troop.set("base_soldier_morale", 72.0)
	troop.set("soldier_morale_variance", 0.0)
	troop.set("base_soldier_run_speed", 2.0)
	troop.set("soldier_run_speed_variance", 0.0)
	troop.set("training_damage_gain_per_second", 1.0)
	troop.set("training_damage_soft_cap", 6.0)
	troop.set("training_strength_gain_per_second", 1.0)
	troop.set("training_strength_soft_cap", 42.0)
	troop.set("training_morale_gain_per_second", 1.0)
	troop.set("training_morale_soft_cap", 80.0)
	troop.set("training_max_endurance_gain_per_second", 1.0)
	troop.set("training_endurance_soft_cap", 70.0)
	root.add_child(troop)
	await process_frame

	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("active_soldier_count", 0)) == 5, "troop summary should count active soldiers", failures)
	_expect(float(summary.get("average_endurance", 0.0)) > 0.0, "troop summary should expose average soldier endurance", failures)
	_expect(_approx(float(summary.get("average_run_speed", 0.0)), 2.0, 0.001), "troop summary should expose average soldier run speed", failures)
	_expect(_approx(float(summary.get("minimum_run_speed", 0.0)), 2.0, 0.001), "troop summary should expose minimum soldier run speed", failures)

	troop.call("set_troop_mode", &"training")
	var strength_before := float((troop.call("get_troop_summary") as Dictionary).get("average_max_strength", 0.0))
	var damage_before := float((troop.call("get_troop_summary") as Dictionary).get("average_damage", 0.0))
	var morale_before := float((troop.call("get_troop_summary") as Dictionary).get("average_morale", 0.0))
	var max_endurance_before := float((troop.call("get_troop_summary") as Dictionary).get("average_max_endurance", 0.0))
	troop.call("_physics_process", 1.0)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(StringName(summary.get("troop_mode", &"")) == &"training", "troop should store selected training mode", failures)
	_expect(float(summary.get("average_max_strength", 0.0)) > strength_before, "training mode should increase soldier max HP", failures)
	_expect(float(summary.get("average_damage", 0.0)) > damage_before, "training mode should increase soldier damage", failures)
	_expect(float(summary.get("average_morale", 0.0)) > morale_before, "training mode should increase soldier morale", failures)
	_expect(float(summary.get("average_max_endurance", 0.0)) > max_endurance_before, "training mode should increase max endurance", failures)
	var first_training_gain := float(summary.get("average_damage", 0.0)) - damage_before
	var damage_after_first_training := float(summary.get("average_damage", 0.0))
	troop.call("_physics_process", 1.0)
	var damage_after_second_training := float((troop.call("get_troop_summary") as Dictionary).get("average_damage", 0.0))
	var second_training_gain := damage_after_second_training - damage_after_first_training
	_expect(second_training_gain < first_training_gain, "training stat gains should slow down near the soft cap", failures)

	troop.call("set_movement_mode", &"running")
	_expect(StringName((troop.call("get_troop_summary") as Dictionary).get("movement_mode", &"")) == &"running", "troop should store selected running mode", failures)

	troop.set("carried_food_kg", 0.0)
	troop.set("food_kg_per_soldier_per_day", 1000.0)
	troop.call("_physics_process", 1.0)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(float(summary.get("food_shortage_ratio", 0.0)) > 0.0, "food shortage should be reported when troop has no food", failures)

	root.remove_child(troop)
	troop.free()


func _check_large_troop_stat_worker_path(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("troop_id", &"worker_stat_probe")
	troop.set("soldier_count", 96)
	troop.set("stat_worker_enabled", true)
	troop.set("stat_worker_min_soldiers", 16)
	troop.set("stat_update_interval_seconds", 0.05)
	troop.set("stat_apply_budget_usec", 2000)
	troop.set("stat_apply_max_soldiers_per_frame", 96)
	troop.set("starvation_update_interval_seconds", 0.05)
	troop.set("food_kg_per_soldier_per_day", 1000.0)
	troop.set("carried_food_kg", 0.0)
	root.add_child(troop)
	await process_frame

	var completed := false
	for _index: int in range(20):
		troop.call("_physics_process", 0.1)
		await process_frame
		var summary := troop.call("get_stat_job_debug_summary") as Dictionary
		if int(summary.get("completed_jobs", 0)) > 0:
			completed = true
			break

	var debug_summary := troop.call("get_stat_job_debug_summary") as Dictionary
	_expect(int(debug_summary.get("started_jobs", 0)) > 0, "large troop stat scheduler should start a worker job", failures)
	_expect(completed, "large troop stat scheduler should complete a worker job", failures)
	_expect(bool(debug_summary.get("last_job_used_worker", false)), "large troop stat scheduler should use WorkerThreadPool when enabled", failures)
	_expect(float(debug_summary.get("last_worker_ms", 0.0)) >= 0.0, "large troop stat scheduler should record worker timing", failures)

	root.remove_child(troop)
	troop.free()


func _check_endurance_running_and_noncombat_recovery(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 4)
	troop.set("carried_food_kg", 100.0)
	troop.set("base_soldier_endurance", 80.0)
	troop.set("soldier_endurance_variance", 0.0)
	troop.set("movement_map", _make_map(24, 24))
	troop.set("position", Vector3(1.0, 0.0, 1.0))
	root.add_child(troop)
	await process_frame

	var speed_soldiers := _get_soldier_nodes(troop)
	if speed_soldiers.size() >= 2:
		speed_soldiers[0].set("run_speed", 2.0)
		speed_soldiers[1].set("run_speed", 4.0)
	troop.call("set_movement_mode", &"walking")
	_expect(_approx(float(troop.call("_get_current_movement_speed_mps")), 2.0, 0.001), "walking troop speed should use the slowest active soldier run speed", failures)
	_expect(bool(troop.call("set_move_destination", Vector3(5.0, 0.0, 1.0))), "walking speed model should accept a destination", failures)
	if speed_soldiers.size() >= 2:
		_expect(_approx(float(troop.call("_get_formation_path_follow_speed")), 2.0, 0.001), "walking formation anchor should use the shared formation speed", failures)
		_expect(_all_soldier_route_paths_empty(troop), "walking soldiers should not own per-soldier command routes", failures)
	troop.call("clear_destination")
	troop.call("set_movement_mode", &"running")
	_expect(_approx(float(troop.call("_get_current_movement_speed_mps")), 6.0, 0.001), "running troop anchor speed should use 3x the slowest active soldier run speed", failures)
	_expect(bool(troop.call("set_move_destination", Vector3(7.0, 0.0, 1.0))), "running speed model should accept a destination", failures)
	if speed_soldiers.size() >= 2:
		_expect(_approx(float(troop.call("_get_formation_path_follow_speed")), 6.0, 0.001), "running formation anchor should use the shared running formation speed", failures)
		_expect(_all_soldier_route_paths_empty(troop), "running soldiers should not own per-soldier command routes", failures)
	troop.call("clear_destination")

	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.has_method("reduce_endurance"):
			soldier.call("reduce_endurance", 20.0)
	var tired_endurance := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	troop.call("set_troop_mode", &"attack")
	troop.call("_physics_process", 1.0)
	var recovered_endurance := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	_expect(recovered_endurance > tired_endurance, "attack mode without combat should recover endurance instead of draining it", failures)

	troop.call("set_movement_mode", &"walking")
	_expect(bool(troop.call("set_move_destination", Vector3(8.0, 0.0, 1.0))), "walking endurance check should accept a destination", failures)
	var walking_before := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	troop.call("_physics_process", 1.0)
	var walking_after := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	_expect(walking_after >= walking_before, "walking without combat should not drain endurance", failures)

	troop.call("clear_destination")
	troop.call("set_movement_mode", &"running")
	_expect(bool(troop.call("set_move_destination", Vector3(14.0, 0.0, 1.0))), "running endurance check should accept a destination", failures)
	var running_before := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	troop.call("_physics_process", 1.0)
	var running_after := float((troop.call("get_troop_summary") as Dictionary).get("average_endurance", 0.0))
	_expect(running_after < running_before, "running should gradually drain endurance", failures)
	_expect(running_before - running_after < 0.5, "running endurance drain should use the five-times-slower rate scale", failures)

	root.remove_child(troop)
	troop.free()


func _check_soldier_activity_pose_states(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 3)
	root.add_child(troop)
	await process_frame

	var soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	var second_soldier := troop.get_node_or_null("Soldiers/Soldier_001")
	_expect(soldier != null, "activity animation check should find a soldier", failures)
	if not soldier:
		root.remove_child(troop)
		troop.free()
		return

	troop.call("set_troop_mode", &"training")
	_step_troop_with_soldiers(troop, 0.25)
	_expect(StringName(soldier.call("get_activity_mode")) == &"training", "training troops should put soldiers in training activity mode", failures)
	var training_variant := StringName(soldier.call("get_activity_variant"))
	_expect(training_variant == &"none", "training mode should not choose a stationary animation variant", failures)
	if second_soldier:
		_expect(StringName(second_soldier.call("get_activity_variant")) == &"none", "every soldier in a training troop should stay on a static pose", failures)

	var visual_root := soldier.get_node_or_null("VisualRoot") as Node3D
	var hand_socket: Node3D = soldier.call("get_right_hand_socket") as Node3D
	if soldier.has_method("force_activity_variant_for_test"):
		soldier.call("force_activity_variant_for_test", &"training_spear", 2.0)
		_expect(StringName(soldier.call("get_activity_variant")) == &"none", "forced training variants should be ignored", failures)
		_step_troop_with_soldiers(troop, 0.6)
		if hand_socket:
			var training_hand_rotation := hand_socket.rotation
			var training_root_y := visual_root.position.y if visual_root else 0.0
			_step_troop_with_soldiers(troop, 0.6)
			_expect(
				hand_socket.rotation.distance_to(training_hand_rotation) < 0.002 and absf((visual_root.position.y if visual_root else 0.0) - training_root_y) < 0.001,
				"forced training variants should still keep a static stationary pose",
				failures
			)

	if soldier.has_method("set_independent_combat") and soldier.has_method("trigger_spear_thrust"):
		soldier.call("set_independent_combat", true, null, true)
		soldier.call("trigger_spear_thrust", null, 1.0)
		soldier.call("_physics_process", 0.45)
		if hand_socket:
			_expect(hand_socket.rotation.x > 0.02, "combat spear thrust should still drive the spear forward", failures)
		soldier.call("set_independent_combat", false, null, false)

	troop.call("set_troop_mode", &"rest")
	_step_troop_with_soldiers(troop, 0.25)
	_expect(StringName(soldier.call("get_activity_mode")) == &"rest", "rest mode should put soldiers in rest activity mode", failures)
	var rest_variant := StringName(soldier.call("get_activity_variant"))
	_expect(rest_variant == &"none", "rest mode should not choose a stationary animation variant", failures)
	if soldier.has_method("force_activity_variant_for_test") and hand_socket:
		soldier.call("force_activity_variant_for_test", &"rest_lay", 2.0)
		_expect(StringName(soldier.call("get_activity_variant")) == &"none", "forced rest variants should be ignored", failures)
		_step_troop_with_soldiers(troop, 0.6)
		var rest_hand_rotation := hand_socket.rotation
		var rest_root_y := visual_root.position.y if visual_root else 0.0
		_step_troop_with_soldiers(troop, 0.6)
		_expect(
			hand_socket.rotation.distance_to(rest_hand_rotation) < 0.002 and absf((visual_root.position.y if visual_root else 0.0) - rest_root_y) < 0.001,
			"forced rest variants should still keep a static stationary pose",
			failures
		)

	troop.call("set_troop_mode", &"defensive")
	_step_troop_with_soldiers(troop, 0.25)
	_expect(StringName(soldier.call("get_activity_mode")) == &"idle", "non-fighting defensive mode should use idle activity", failures)
	var idle_variant := StringName(soldier.call("get_activity_variant"))
	_expect(idle_variant == &"none", "idle activity should not choose an animated variant", failures)
	if soldier.has_method("force_activity_variant_for_test") and hand_socket:
		soldier.call("force_activity_variant_for_test", &"idle_look", 2.0)
		_expect(StringName(soldier.call("get_activity_variant")) == &"none", "forced idle variants should be ignored", failures)
		_step_troop_with_soldiers(troop, 0.6)
		var idle_hand_rotation := hand_socket.rotation
		var idle_root_y := visual_root.position.y if visual_root else 0.0
		_step_troop_with_soldiers(troop, 0.6)
		_expect(
			hand_socket.rotation.distance_to(idle_hand_rotation) < 0.002 and absf((visual_root.position.y if visual_root else 0.0) - idle_root_y) < 0.001,
			"idle soldiers should keep a static pose without body or spear drift",
			failures
		)

	root.remove_child(troop)
	troop.free()

	var enemy := TroopScene.instantiate()
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("troop_mode", "attack")
	enemy.set("soldier_count", 2)
	root.add_child(enemy)
	await process_frame

	var enemy_soldier := enemy.get_node_or_null("Soldiers/Soldier_000")
	_expect(enemy_soldier != null, "enemy idle animation check should find a soldier", failures)
	if enemy_soldier:
		var enemy_hand_socket: Node3D = enemy_soldier.call("get_right_hand_socket") as Node3D
		if enemy_soldier.has_method("force_activity_variant_for_test"):
			enemy_soldier.call("force_activity_variant_for_test", &"idle_spear", 2.0)
			_expect(StringName(enemy_soldier.call("get_activity_variant")) == &"none", "forced enemy idle variants should be ignored", failures)
		_step_troop_with_soldiers(enemy, 0.6)
		_expect(StringName(enemy_soldier.call("get_activity_mode")) == &"idle", "non-fighting enemy attack-mode troops should use idle activity", failures)
		if enemy_hand_socket:
			var enemy_idle_rotation := enemy_hand_socket.rotation
			_step_troop_with_soldiers(enemy, 0.6)
			_expect(
				enemy_hand_socket.rotation.distance_to(enemy_idle_rotation) < 0.002,
				"enemy idle soldiers should keep the same static pose",
				failures
			)

	root.remove_child(enemy)
	enemy.free()


func _check_troop_combat_resolution(failures: Array[String]) -> void:
	var player := TroopScene.instantiate()
	player.set("troop_id", &"combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", 4)
	player.set("carried_food_kg", 100.0)
	player.set("combat_seed", 11)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("troop_mode", "attack")
	player.set("movement_map", _make_map(24, 24))
	player.set("position", Vector3(6.0, 0.0, 8.0))
	player.set("detection_range_m", 80.0)
	player.set("combat_range_m", 80.0)
	player.set("combat_spear_range_m", 2.6)
	player.set("combat_slot_follow_speed", 24.0)
	player.set("combat_frontline_width_per_soldier", 1.25)
	player.set("attack_engagement_delay", 0.0)
	player.set("attack_interval", 0.1)
	player.set("training_damage_gain_per_second", 0.2)
	player.set("training_max_endurance_gain_per_second", 0.2)
	player.set("training_damage_soft_cap", 20.0)
	player.set("training_endurance_soft_cap", 120.0)
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 4)
	enemy.set("carried_food_kg", 100.0)
	enemy.set("combat_seed", 12)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("troop_mode", "defensive")
	enemy.set("movement_map", _make_map(24, 24))
	enemy.set("detection_range_m", 80.0)
	enemy.set("defensive_engagement_range_m", 80.0)
	enemy.set("combat_spear_range_m", 2.6)
	enemy.set("combat_slot_follow_speed", 24.0)
	enemy.set("combat_frontline_width_per_soldier", 1.25)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.set("attack_interval", 0.1)
	enemy.position = Vector3(10.0, 0.0, 8.0)
	root.add_child(enemy)
	await process_frame

	var enemy_strength_before := float((enemy.call("get_troop_summary") as Dictionary).get("average_strength", 0.0))
	var player_damage_before := float((player.call("get_troop_summary") as Dictionary).get("average_damage", 0.0))
	var player_endurance_cap_before := float((player.call("get_troop_summary") as Dictionary).get("average_max_endurance", 0.0))
	for _index: int in range(8):
		_step_troop_with_soldiers(player, 0.2)
		_step_troop_with_soldiers(enemy, 0.2)
	var enemy_summary: Dictionary = enemy.call("get_troop_summary") as Dictionary
	var player_summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(bool(player_summary.get("in_combat", false)), "attacking troop should enter combat against enemy team", failures)
	_expect(float(enemy_summary.get("average_strength", enemy_strength_before)) < enemy_strength_before, "combat should reduce enemy soldier strength", failures)
	_expect(float(player_summary.get("average_damage", 0.0)) > player_damage_before, "fighting should increase attacker damage", failures)
	_expect(float(player_summary.get("average_max_endurance", 0.0)) > player_endurance_cap_before, "fighting should increase attacker max endurance", failures)
	_expect(bool(player_summary.get("combat_scatter_active", false)), "fighting should enter combat scatter control", failures)
	_expect(int(player_summary.get("combat_assigned_target_count", 0)) > 0, "combat should assign individual soldier targets", failures)
	_expect(int(player_summary.get("combat_locked_attacker_count", 0)) > 0, "combat soldiers should lock positions after reaching spear range", failures)
	_expect(int(player_summary.get("combat_visual_stance_update_count", 0)) > 0, "combat should update visible soldier combat stances", failures)
	_expect(int(player_summary.get("combat_visual_thrust_count", 0)) > 0, "combat should trigger visible spear thrusts while fighting", failures)
	_expect(_count_damaged_soldiers(enemy) > 1, "messy combat should damage more than one enemy soldier", failures)
	_expect(_minimum_soldier_spacing(player) > 0.42, "combat spacing should keep allied soldiers from overlapping", failures)
	var target_ids_before := _combat_target_ids(player)
	var lock_positions_before := _combat_lock_positions(player)
	for _index: int in range(4):
		_step_troop_with_soldiers(player, 0.2)
		_step_troop_with_soldiers(enemy, 0.2)
	_expect(_combat_targets_match(player, target_ids_before), "combat soldiers should keep stable assigned targets while targets stay alive", failures)
	_expect(
		_combat_soldiers_within_shuffle_radius(player, lock_positions_before, float(player.get("combat_attack_shuffle_radius")) + 0.05),
		"locked combat soldiers should not drift beyond their attack shuffle radius",
		failures
	)
	var any_attacking := false
	var soldiers := player.get_node_or_null("Soldiers")
	if soldiers:
		for child: Node in soldiers.get_children():
			if child.has_method("is_formation_attacking") and bool(child.call("is_formation_attacking")):
				any_attacking = true
				if child.has_method("get_right_hand_socket"):
					var socket := child.call("get_right_hand_socket") as Node3D
					if socket:
						_expect(absf(socket.rotation.y) < 0.22, "spear thrust should stay aligned toward the target instead of sweeping sideways", failures)
				break
	_expect(any_attacking, "troop soldiers should play attack animation while fighting", failures)
	var away_after_fight := _count_soldiers_away_from_slots(player, 0.18)
	enemy.call("queue_free")
	await process_frame
	_step_troop_with_soldiers(player, 0.2)
	player_summary = player.call("get_troop_summary") as Dictionary
	_expect(not bool(player_summary.get("combat_scatter_active", true)), "soldiers should clear combat scatter after combat ends", failures)
	if away_after_fight > 0:
		_expect(not _any_soldier_has_independent_motion(player), "ended combat should hold scattered soldiers instead of automatically regrouping", failures)
	for _index: int in range(8):
		_step_troop_with_soldiers(player, 0.2)
	if away_after_fight > 0:
		_expect(_count_soldiers_away_from_slots(player, 0.35) >= away_after_fight, "ended combat should not pull soldiers back toward formation slots without a new command", failures)
	_expect(bool(player.call("set_move_destination", Vector3(16.0, 0.0, 8.0))), "manual move after combat should be accepted", failures)
	player_summary = player.call("get_troop_summary") as Dictionary
	_expect(not bool(player_summary.get("combat_scatter_active", true)), "manual movement should clear scattered combat positions and regroup", failures)
	if _count_soldiers_away_from_slots(player, 0.35) > 0:
		_expect(_any_soldier_has_independent_motion(player), "manual movement after combat should make displaced soldiers walk back by independent commands", failures)

	if is_instance_valid(enemy) and enemy.get_parent():
		root.remove_child(enemy)
		enemy.free()
	root.remove_child(player)
	player.free()


func _check_large_combat_uses_bounded_work(failures: Array[String]) -> void:
	var soldier_total := 150
	var assignment_budget := 16
	var steering_budget := 12
	var pair_budget := 160
	var target_candidates := 12
	var separation_neighbors := 8
	var player := TroopScene.instantiate()
	player.set("troop_id", &"bounded_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", soldier_total)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 101)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("detection_range_m", 100.0)
	player.set("combat_range_m", 100.0)
	player.set("combat_spear_range_m", 2.8)
	player.set("combat_logic_interval", 0.08)
	player.set("combat_target_reassignment_interval", 0.5)
	player.set("combat_target_assignment_budget_per_tick", assignment_budget)
	player.set("combat_separation_updates_per_tick", steering_budget)
	player.set("combat_pair_checks_budget_per_tick", pair_budget)
	player.set("combat_steering_refresh_interval", 0.5)
	player.set("combat_max_separation_neighbors", separation_neighbors)
	player.set("combat_target_search_candidates", target_candidates)
	player.set("formation_collision_neighbor_limit", separation_neighbors)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"bounded_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", soldier_total)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 102)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("detection_range_m", 100.0)
	enemy.set("defensive_engagement_range_m", 100.0)
	enemy.set("combat_spear_range_m", 2.8)
	enemy.set("combat_logic_interval", 0.08)
	enemy.set("combat_target_reassignment_interval", 0.5)
	enemy.set("combat_target_assignment_budget_per_tick", assignment_budget)
	enemy.set("combat_separation_updates_per_tick", steering_budget)
	enemy.set("combat_pair_checks_budget_per_tick", pair_budget)
	enemy.set("combat_steering_refresh_interval", 0.5)
	enemy.set("combat_max_separation_neighbors", separation_neighbors)
	enemy.set("combat_target_search_candidates", target_candidates)
	enemy.set("formation_collision_neighbor_limit", separation_neighbors)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(5.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	var before_summary: Dictionary = player.call("get_troop_summary") as Dictionary
	var scans_before := int(before_summary.get("combat_perf_target_candidate_scans", 0))
	var separation_before := int(before_summary.get("combat_perf_separation_pair_checks", 0))
	var assigned_before := int(before_summary.get("combat_assigned_target_count", 0))
	var steering_before := int(before_summary.get("combat_perf_steering_updates", 0))
	player.call("_physics_process", 0.2)
	var after_summary: Dictionary = player.call("get_troop_summary") as Dictionary
	var target_scans := int(after_summary.get("combat_perf_target_candidate_scans", 0)) - scans_before
	var separation_checks := int(after_summary.get("combat_perf_separation_pair_checks", 0)) - separation_before
	var assigned_delta := int(after_summary.get("combat_assigned_target_count", 0)) - assigned_before
	var steering_delta := int(after_summary.get("combat_perf_steering_updates", 0)) - steering_before
	var old_budgetless_scan_floor := soldier_total * target_candidates
	var bounded_target_limit := assignment_budget * target_candidates
	var bounded_separation_limit := mini(pair_budget, steering_budget * (separation_neighbors * 2 + 2))
	_expect(assigned_delta <= assignment_budget, "large combat tick should only assign targets within the per-tick budget", failures)
	_expect(steering_delta <= steering_budget, "large combat tick should only refresh steering within the per-tick budget", failures)
	_expect(target_scans <= bounded_target_limit, "large combat target assignment should scan only the budgeted spatial candidates", failures)
	_expect(target_scans < old_budgetless_scan_floor, "large combat target assignment should avoid scanning every attacker in one tick", failures)
	_expect(separation_checks <= bounded_separation_limit, "large combat separation should only check budgeted nearby capped neighbors", failures)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_combat_socket_targets_stay_local(failures: Array[String]) -> void:
	var soldier_total := 96
	var player := TroopScene.instantiate()
	player.set("troop_id", &"socket_local_player")
	player.set("team_id", &"player")
	player.set("soldier_count", soldier_total)
	player.set("formation_columns", 12)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 401)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("combat_range_m", 100.0)
	player.set("combat_spear_range_m", 2.8)
	player.set("combat_frontline_width_per_soldier", 4.4)
	player.set("combat_target_assignment_budget_per_tick", 128)
	player.set("combat_separation_updates_per_tick", 128)
	player.set("combat_pair_checks_budget_per_tick", 512)
	player.set("combat_target_search_candidates", 24)
	player.set("combat_assignment_candidates", 24)
	player.set("combat_rebalance_interval", 0.05)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"socket_local_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 32)
	enemy.set("formation_columns", 8)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 402)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(5.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	player.call("_resolve_combat_tick", enemy, 0.2)
	var summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("combat_socket_assignment_count", 0)) > 0, "socket locality setup should assign combat sockets", failures)
	var max_socket_distance := _max_combat_socket_distance_to_target(player)
	_expect(
		max_socket_distance <= float(player.get("combat_spear_range_m")) + 0.02,
		"large combat socket targets should stay local to their defender instead of using whole-troop lateral offsets; max %.2fm" % max_socket_distance,
		failures
	)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_combat_debug_lines_only_show_near_fights(failures: Array[String]) -> void:
	var player := TroopScene.instantiate()
	player.set("troop_id", &"debug_line_player")
	player.set("team_id", &"player")
	player.set("soldier_count", 2)
	player.set("formation_columns", 2)
	player.set("troop_mode", "attack")
	player.set("combat_spear_range_m", 3.0)
	player.set("combat_socket_arrival_radius", 0.25)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"debug_line_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 2)
	enemy.set("formation_columns", 2)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_spear_range_m", 3.0)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	var attackers := _get_active_soldier_nodes(player)
	var defenders := _get_active_soldier_nodes(enemy)
	_expect(attackers.size() >= 2 and defenders.size() >= 2, "combat debug line setup should have two soldiers per side", failures)
	if attackers.size() < 2 or defenders.size() < 2:
		root.remove_child(enemy)
		enemy.free()
		root.remove_child(player)
		player.free()
		return

	var near_attacker := attackers[0] as Node3D
	var far_attacker := attackers[1] as Node3D
	var near_defender := defenders[0] as Node3D
	var far_defender := defenders[1] as Node3D
	near_attacker.global_position = Vector3(0.0, 0.0, 0.0)
	near_defender.global_position = Vector3(2.2, 0.0, 0.0)
	far_attacker.global_position = Vector3(0.0, 0.0, 10.0)
	far_defender.global_position = Vector3(18.0, 0.0, 10.0)
	player.call("_set_state", &"fighting")
	player.call("set_combat_debug_lines_enabled", true)
	var load_by_defender := {
		near_defender.get_instance_id(): 0,
		far_defender.get_instance_id(): 0,
	}
	player.call("_assign_combat_target_to_soldier", near_attacker, near_defender, load_by_defender)
	player.call("_lock_combat_soldier", near_attacker, near_defender)
	player.call("_assign_combat_target_to_soldier", far_attacker, far_defender, load_by_defender)
	player.call("_lock_combat_soldier", far_attacker, far_defender)
	player.call("_update_combat_debug_lines")
	var summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(bool(player.call("_is_combat_pair_actively_fighting", near_attacker, near_defender)), "near locked pair should count as an active fight", failures)
	_expect(not bool(player.call("_is_combat_pair_actively_fighting", far_attacker, far_defender)), "far locked pair should not count as an active fight", failures)
	_expect(
		int(summary.get("combat_debug_line_pair_count", 0)) == 1,
		"combat debug lines should draw only active near fighting pairs, not far movement assignments",
		failures
	)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_combat_surround_sockets_and_facing(failures: Array[String]) -> void:
	var player := TroopScene.instantiate()
	player.set("troop_id", &"surround_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", 4)
	player.set("formation_columns", 4)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 501)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("combat_range_m", 80.0)
	player.set("combat_spear_range_m", 3.2)
	player.set("combat_socket_radius", 1.7)
	player.set("combat_socket_arrival_radius", 0.32)
	player.set("combat_slot_follow_speed", 30.0)
	player.set("combat_max_attackers_per_target", 4)
	player.set("combat_target_assignment_budget_per_tick", 8)
	player.set("combat_separation_updates_per_tick", 8)
	player.set("combat_pair_checks_budget_per_tick", 64)
	player.set("combat_assignment_candidates", 8)
	player.set("combat_target_search_candidates", 8)
	player.set("combat_rebalance_interval", 0.05)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"surround_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 1)
	enemy.set("formation_columns", 1)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 502)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(3.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	var attackers := _get_active_soldier_nodes(player)
	var defenders := _get_active_soldier_nodes(enemy)
	_expect(attackers.size() >= 4 and defenders.size() >= 1, "surround socket setup should have enough combat soldiers", failures)
	var defender := defenders[0] as Node3D
	var load_by_defender := {defender.get_instance_id(): 0}
	for index: int in range(mini(4, attackers.size())):
		var attacker := attackers[index] as Node3D
		player.call("_assign_combat_target_to_soldier", attacker, defender, load_by_defender)
		var socket_position: Vector3 = player.call("_get_soldier_engagement_position", attacker, defender, index, 4)
		player.call("_move_combat_soldier_toward", attacker, defender, socket_position, 0.2)
	_expect(_combat_sockets_include_opposed_slots(player), "four attackers on one defender should reserve opposed surround sockets", failures)
	_expect(_combat_sockets_include_side_slots(player), "four attackers on one defender should reserve side surround sockets", failures)
	for _index: int in range(8):
		for soldier: Node in attackers:
			if soldier.has_method("step_formation_logic"):
				soldier.call("step_formation_logic", 0.12)
	_expect(_combat_soldiers_face_assigned_targets(player, deg_to_rad(35.0)), "combat soldiers should face assigned defenders while entering and holding sockets", failures)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_combat_target_capacity(failures: Array[String]) -> void:
	var soldier_total := 16
	var max_attackers := 4
	var player := TroopScene.instantiate()
	player.set("troop_id", &"capacity_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", soldier_total)
	player.set("formation_columns", 8)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 201)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("combat_max_attackers_per_target", max_attackers)
	player.set("combat_target_assignment_budget_per_tick", 64)
	player.set("combat_assignment_candidates", 16)
	player.set("combat_target_search_candidates", 16)
	player.set("combat_rebalance_interval", 0.05)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"capacity_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 5)
	enemy.set("formation_columns", 5)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 202)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(4.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	player.call("_resolve_combat_tick", enemy, 0.2)
	var summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("combat_assigned_target_count", 0)) == soldier_total, "capacity combat should assign every attacker when enough defender capacity exists", failures)
	_expect(int(summary.get("combat_socket_assignment_count", 0)) == soldier_total, "capacity combat should reserve one attack socket per assigned attacker", failures)
	_expect(
		int(summary.get("combat_max_target_load", 0)) <= max_attackers,
		"capacity combat should not put more than four attackers on one defender while alternatives exist",
		failures
	)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_normal_combat_assigns_all_attackers_with_capacity(failures: Array[String]) -> void:
	var soldier_total := 120
	var defender_total := 40
	var max_attackers := 4
	var player := TroopScene.instantiate()
	player.set("troop_id", &"normal_full_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", soldier_total)
	player.set("formation_columns", 12)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 601)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("combat_active_attacker_limit", 64)
	player.set("combat_full_participation_soldier_threshold", 220)
	player.set("combat_max_attackers_per_target", max_attackers)
	player.set("combat_target_assignment_budget_per_tick", 256)
	player.set("combat_assignment_candidates", 64)
	player.set("combat_target_search_candidates", 64)
	player.set("combat_rebalance_interval", 0.05)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"normal_full_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", defender_total)
	enemy.set("formation_columns", 10)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 602)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("combat_max_attackers_per_target", max_attackers)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(4.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	player.call("_resolve_combat_tick", enemy, 0.2)
	var summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(
		int(summary.get("combat_assigned_target_count", 0)) == soldier_total,
		"normal-sized combat should assign every attacker when defender socket capacity exists instead of stopping at the stress cap",
		failures
	)
	_expect(
		int(summary.get("combat_max_target_load", 0)) <= max_attackers,
		"normal-sized combat should still respect max attackers per defender",
		failures
	)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_large_default_combat_assigns_all_when_capacity_exists(failures: Array[String]) -> void:
	var soldier_total := 160
	var defender_total := 40
	var max_attackers := 4
	var player := TroopScene.instantiate()
	player.set("troop_id", &"large_default_full_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", soldier_total)
	player.set("formation_columns", 16)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 611)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("base_soldier_damage", 1.0)
	player.set("soldier_damage_variance", 0.0)
	player.set("combat_max_attackers_per_target", max_attackers)
	player.set("combat_target_assignment_budget_per_tick", 256)
	player.set("combat_assignment_candidates", 64)
	player.set("combat_target_search_candidates", 64)
	player.set("combat_rebalance_interval", 0.05)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"large_default_full_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", defender_total)
	enemy.set("formation_columns", 10)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 612)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("base_soldier_damage", 1.0)
	enemy.set("soldier_damage_variance", 0.0)
	enemy.set("combat_max_attackers_per_target", max_attackers)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(4.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	player.call("_resolve_combat_tick", enemy, 0.2)
	var summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(
		int(summary.get("combat_assigned_target_count", 0)) == soldier_total,
		"default large combat should assign every attacker when defender socket capacity exists instead of stopping at the active-attacker cap",
		failures
	)
	_expect(
		int(summary.get("combat_max_target_load", 0)) <= max_attackers,
		"default large combat should still cap attackers per defender",
		failures
	)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(player)
	player.free()


func _check_combat_state_forgets_departed_soldiers(failures: Array[String]) -> void:
	var player := TroopScene.instantiate()
	player.set("troop_id", &"departed_combat_player")
	player.set("team_id", &"player")
	player.set("soldier_count", 8)
	player.set("formation_columns", 4)
	player.set("troop_mode", "attack")
	player.set("combat_seed", 701)
	player.set("base_soldier_strength", 100.0)
	player.set("soldier_strength_variance", 0.0)
	player.set("combat_target_assignment_budget_per_tick", 32)
	player.set("combat_assignment_candidates", 16)
	player.set("combat_target_search_candidates", 16)
	player.set("attack_engagement_delay", 0.0)
	player.position = Vector3.ZERO
	root.add_child(player)

	var enemy := TroopScene.instantiate()
	enemy.set("troop_id", &"departed_combat_enemy")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 8)
	enemy.set("formation_columns", 4)
	enemy.set("troop_mode", "defensive")
	enemy.set("combat_seed", 702)
	enemy.set("base_soldier_strength", 100.0)
	enemy.set("soldier_strength_variance", 0.0)
	enemy.set("defensive_engagement_delay", 0.0)
	enemy.position = Vector3(4.0, 0.0, 0.0)
	root.add_child(enemy)
	await process_frame

	player.call("_resolve_combat_tick", enemy, 0.2)
	var targets: Dictionary = player.get("_combat_soldier_targets")
	_expect(not targets.is_empty(), "departed combat setup should assign at least one soldier target", failures)
	_expect(_dictionary_has_no_node_values(player.get("_combat_touched_soldiers")), "combat touched bookkeeping should store soldier ids instead of Node references", failures)
	_expect(_dictionary_has_no_node_values(player.get("_combat_render_dirty_soldiers")), "combat render-dirty bookkeeping should store soldier ids instead of Node references", failures)
	if not targets.is_empty():
		var soldier_id := int(targets.keys()[0])
		var soldier := _get_soldier_by_instance_id(player, soldier_id) as Node3D
		_expect(soldier != null, "departed combat setup should find the assigned soldier node", failures)
		if soldier:
			player.call("_remove_departed_soldier", soldier)
			_expect(not (player.get("_combat_soldier_targets") as Dictionary).has(soldier_id), "departed soldiers should be removed from combat target assignments", failures)
			_expect(not (player.get("_combat_touched_soldiers") as Dictionary).has(soldier_id), "departed soldiers should be removed from combat touched bookkeeping", failures)
			_expect(not (player.get("_combat_render_dirty_soldiers") as Dictionary).has(soldier_id), "departed soldiers should be removed from combat render-dirty bookkeeping", failures)
			_expect(not (player.get("_combat_soldier_socket_positions") as Dictionary).has(soldier_id), "departed soldiers should be removed from combat socket positions", failures)
			_expect(not (player.get("_combat_soldier_socket_indices") as Dictionary).has(soldier_id), "departed soldiers should be removed from combat socket indices", failures)
			player.call("_update_combat_soldier_animation")
	await process_frame

	if is_instance_valid(enemy) and enemy.get_parent():
		root.remove_child(enemy)
		enemy.free()
	if is_instance_valid(player) and player.get_parent():
		root.remove_child(player)
		player.free()


func _check_flag_hover_and_defeated_indicators(failures: Array[String]) -> void:
	var friendly := TroopScene.instantiate()
	friendly.set("team_id", &"player")
	friendly.set("soldier_count", 3)
	root.add_child(friendly)
	await process_frame

	_expect(bool(friendly.call("has_management_flag")), "friendly troops should show a management flag", failures)
	_expect(not bool(friendly.call("has_selection_highlight")), "friendly troops should not show the old ground highlight", failures)
	_expect(friendly.find_child("TroopRing", true, false) == null, "friendly troops should not create the old selection circle", failures)
	_expect(friendly.find_child("TroopSelectionHighlight", true, false) == null, "friendly troops should not create the old selection background", failures)
	friendly.call("set_hovered", true)
	_expect(bool(friendly.call("is_hovered")), "hovered friendly troops should remember hover state", failures)
	_expect(not bool(friendly.call("has_unit_hover_borders")), "hovered friendly troops should not use unit box borders", failures)
	_expect(not bool(friendly.call("has_unit_selection_markers")), "hovered friendly troops should not show unit ground markers until selected", failures)
	friendly.call("set_hovered", false)
	_expect(not bool(friendly.call("has_unit_selection_markers")), "unhovered friendly troops should hide unit ground markers", failures)
	friendly.call("set_selected", true)
	_expect(not bool(friendly.call("has_selection_highlight")), "selected friendly troops should not show the old ground highlight", failures)
	_expect(not bool(friendly.call("has_attack_zone_indicator")), "selected friendly troops should not draw the old attack range circle", failures)
	_expect(friendly.find_child("TroopAttackZone", true, false) == null, "selected friendly troops should not create a TroopAttackZone mesh", failures)
	_expect(not bool(friendly.call("has_unit_hover_borders")), "selected friendly troops should not use unit box borders", failures)
	_expect(bool(friendly.call("has_unit_selection_markers")), "selected friendly troops should show unit ground markers", failures)
	var friendly_marker := friendly.find_child("TroopUnitSelectionMarker", true, false) as MeshInstance3D
	_expect(friendly_marker != null and friendly_marker.position.y <= 0.015, "unit ground markers should sit below the unit body", failures)
	if friendly_marker:
		var marker_material := friendly_marker.material_override as StandardMaterial3D
		_expect(marker_material != null and not marker_material.no_depth_test, "unit ground markers should depth-test behind unit geometry", failures)
		_expect(_mesh_uses_solid_vertex_color(friendly_marker.mesh), "unit ground markers should use a solid color instead of a gradient", failures)
		_expect(marker_material.albedo_color.a > 0.75, "selected unit ground markers should be stronger than hover markers", failures)
	var friendly_soldiers := _get_soldier_nodes(friendly)
	if friendly_soldiers.size() >= 3:
		(friendly_soldiers[0] as Node3D).global_position = Vector3(2.0, 0.0, 4.0)
		(friendly_soldiers[1] as Node3D).global_position = Vector3(8.0, 0.0, 4.0)
		(friendly_soldiers[2] as Node3D).global_position = Vector3(8.0, 0.0, 10.0)
		friendly.call("_process", 0.0)
		var flag_position: Vector3 = friendly.call("get_management_flag_world_position")
		var center := _average_soldier_world_position(friendly)
		var horizontal_delta := flag_position - center
		horizontal_delta.y = 0.0
		_expect(horizontal_delta.length() <= 0.05, "management flag should stay centered over the troop's units", failures)
		var attack_corners: PackedVector3Array = friendly.call("get_attack_zone_corners")
		_expect(attack_corners.size() == 4, "attack zone should be exposed as four expanded formation corners", failures)
		_expect(bool(friendly.call("is_world_position_in_attack_zone", Vector3(8.0, 0.0, 10.0))), "attack zone should include active soldier corner positions", failures)
		_expect(bool(friendly.call("is_world_position_in_attack_zone", Vector3(14.0, 0.0, 10.0))), "attack zone should include points within range of a formation corner", failures)
		_expect(not bool(friendly.call("is_world_position_in_attack_zone", Vector3(28.0, 0.0, 10.0))), "attack zone should exclude points beyond the expanded formation footprint", failures)
	friendly.call("set_troop_mode", &"attack")
	_expect(not bool(friendly.call("has_attack_zone_indicator")), "attack-mode troops should still avoid drawing an attack range circle", failures)
	friendly.call("set_selected", false)
	_expect(not bool(friendly.call("has_attack_zone_indicator")), "deselected friendly troops should hide their attack zone", failures)
	_expect(not bool(friendly.call("has_unit_selection_markers")), "deselected friendly troops should hide unit ground markers", failures)

	var enemy := TroopScene.instantiate()
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 2)
	enemy.set("base_soldier_strength", 5.0)
	enemy.set("soldier_strength_variance", 0.0)
	root.add_child(enemy)
	await process_frame

	_expect(bool(enemy.call("has_management_flag")), "enemy troops should show a management flag for inspection", failures)
	_expect(enemy.find_child("TroopRing", true, false) == null, "enemy troops should not create the old selection circle", failures)
	_expect(enemy.find_child("TroopSelectionHighlight", true, false) == null, "enemy troops should not create the old selection background", failures)
	enemy.call("set_hovered", true)
	_expect(not bool(enemy.call("has_unit_hover_borders")), "hovered enemy troops should not use unit box borders", failures)
	_expect(not bool(enemy.call("has_unit_selection_markers")), "hovered enemy troops should not show unit ground markers until selected", failures)
	enemy.call("set_hovered", false)
	enemy.call("set_selected", true)
	_expect(not bool(enemy.call("has_selection_highlight")), "selected enemy troops should not show the old ground highlight", failures)
	_expect(not bool(enemy.call("has_attack_zone_indicator")), "selected enemy troops should not draw the old attack range circle", failures)
	_expect(not bool(enemy.call("has_unit_hover_borders")), "selected enemy troops should not use unit box borders", failures)
	_expect(bool(enemy.call("has_unit_selection_markers")), "selected enemy troops should show unit ground markers", failures)
	for soldier: Node in _get_soldier_nodes(enemy):
		if soldier.has_method("apply_strength_damage"):
			soldier.call("apply_strength_damage", 999.0, &"test")
	enemy.call("_physics_process", 0.1)
	await process_frame
	var enemy_summary: Dictionary = enemy.call("get_troop_summary") as Dictionary
	_expect(bool(enemy_summary.get("defeated", false)), "enemy troop should report defeated after every soldier dies", failures)
	_expect(not bool(enemy.call("has_selection_indicator")), "defeated enemy troops should remove flag click proxy", failures)
	_expect(not bool(enemy.call("has_management_flag")), "defeated enemy troops should remove the management flag", failures)
	_expect(not bool(enemy.call("has_unit_hover_borders")), "defeated enemy troops should hide unit borders", failures)
	_expect(not bool(enemy.call("has_unit_selection_markers")), "defeated enemy troops should hide unit ground markers", failures)
	_expect(not bool(enemy.call("has_attack_zone_indicator")), "defeated enemy troops should hide their attack zone", failures)
	_expect(enemy.find_child("TroopUnitClickProxy", true, false) == null, "defeated enemy troops should remove unit click proxies", failures)
	_expect(not bool(enemy.call("has_selection_highlight")), "defeated selected troops should not show the old ground highlight", failures)
	_expect(_visible_soldier_count(enemy) == 0, "defeated enemy troops should not keep visible corpse soldiers", failures)
	_expect(int(enemy_summary.get("dead_soldier_count", 0)) == 0, "defeated enemy troops should not expose dead soldier counts", failures)

	root.remove_child(enemy)
	enemy.free()
	root.remove_child(friendly)
	friendly.free()


func _check_enemy_selection_and_read_only_drawer(failures: Array[String]) -> void:
	var drawer := TroopDrawerScene.instantiate()
	root.add_child(drawer)
	var controller := TroopSelectionControllerScript.new()
	controller.troop_drawer_path = drawer.get_path()
	root.add_child(controller)

	var enemy := TroopScene.instantiate()
	enemy.set("display_name", "Enemy Inspect")
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 3)
	root.add_child(enemy)
	var friendly := TroopScene.instantiate()
	friendly.set("display_name", "Friendly Inspect")
	friendly.set("team_id", &"player")
	friendly.set("controllable", true)
	friendly.set("soldier_count", 3)
	root.add_child(friendly)
	await process_frame

	_expect(bool(controller.call("_is_selectable_troop", enemy)), "enemy troops should be selectable for inspection", failures)
	_expect(not bool(controller.call("_is_commandable_troop", enemy)), "enemy troops should not be commandable", failures)
	controller.call("_select_troop", enemy)
	_expect(controller.get("_selected_troop") == enemy, "enemy selection should keep the non-controllable troop selected", failures)
	var enemy_title := drawer.find_child("TitleLabel", true, false) as Label
	var enemy_subtitle := drawer.find_child("SubtitleLabel", true, false) as Label
	var enemy_stats := drawer.find_child("StatsLabel", true, false) as Label
	var mode_option := drawer.find_child("TroopModeOption", true, false) as OptionButton
	var collect_button := drawer.find_child("CollectWoodButton", true, false) as Button
	_expect(enemy_title != null and enemy_title.text == "Enemy Inspect", "enemy drawer should show the enemy display name", failures)
	_expect(enemy_subtitle != null and enemy_subtitle.text.contains("Team Enemy"), "enemy drawer should show team information", failures)
	_expect(enemy_stats != null and enemy_stats.text.contains("Troops") and enemy_stats.text.contains("soldiers"), "enemy drawer should show current troop count", failures)
	_expect(enemy_stats != null and not enemy_stats.text.contains("active") and not enemy_stats.text.contains("dead"), "enemy drawer should not show active/total/dead buckets", failures)
	if mode_option:
		_expect(not (mode_option.get_parent() as Control).visible, "enemy drawer should hide troop controls", failures)
	if collect_button:
		_expect(not (collect_button.get_parent() as Control).visible, "enemy drawer should hide logistics controls", failures)

	controller.call("_select_troop", friendly)
	var friendly_stats := drawer.find_child("StatsLabel", true, false) as Label
	_expect(controller.get("_selected_troop") == friendly, "friendly selection should still work", failures)
	_expect(
		friendly_stats != null
		and friendly_stats.text.contains("HP")
		and friendly_stats.text.contains("DMG")
		and friendly_stats.text.contains("MOR")
		and friendly_stats.text.contains("END")
		and friendly_stats.text.contains("RUN"),
		"friendly drawer should show average health, damage, morale, endurance, and running speed",
		failures
	)
	if mode_option:
		_expect((mode_option.get_parent() as Control).visible, "friendly drawer should show troop controls", failures)

	for node: Node in [friendly, enemy, controller, drawer]:
		root.remove_child(node)
		node.free()


func _check_attack_target_command_and_survivor_rout(failures: Array[String]) -> void:
	var controller := TroopSelectionControllerScript.new()
	root.add_child(controller)

	var attacker := TroopScene.instantiate()
	attacker.set("team_id", &"player")
	attacker.set("controllable", true)
	attacker.set("soldier_count", 8)
	attacker.set("movement_map", _make_map(48, 48))
	attacker.set("position", Vector3(2.0, 0.0, 8.0))
	attacker.set("defensive_engagement_range_m", 8.0)
	attacker.set("combat_range_m", 8.0)
	attacker.set("defensive_engagement_delay", 0.0)
	root.add_child(attacker)

	var enemy := TroopScene.instantiate()
	enemy.set("team_id", &"enemy")
	enemy.set("controllable", false)
	enemy.set("soldier_count", 8)
	enemy.set("movement_map", _make_map(48, 48))
	enemy.set("position", Vector3(30.0, 0.0, 8.0))
	enemy.set("defensive_engagement_range_m", 8.0)
	enemy.set("combat_range_m", 8.0)
	root.add_child(enemy)
	await process_frame

	controller.call("_select_troop", attacker)
	_expect(bool(controller.call("_try_issue_attack_target", enemy)), "right-click enemy command should issue a moving attack target", failures)
	_expect(bool(attacker.call("has_attack_target")), "attack command should keep the enemy troop as a live target", failures)
	var first_destination: Vector3 = attacker.call("get_destination")
	_expect(first_destination.distance_to((enemy as Node3D).global_position) > 1.0, "attack target movement should path to a standoff point instead of the enemy center", failures)

	enemy.position = Vector3(34.0, 0.0, 8.0)
	attacker.call("_physics_process", 1.0)
	var second_destination: Vector3 = attacker.call("get_destination")
	_expect(second_destination.distance_to(first_destination) > 0.5, "attack target movement should repath when the enemy troop moves", failures)

	enemy.position = Vector3(5.0, 0.0, 8.0)
	attacker.call("_physics_process", 1.0)
	var summary: Dictionary = attacker.call("get_troop_summary") as Dictionary
	_expect(bool(summary.get("in_combat", false)), "attack target movement should stop pathing and fight when the enemy closes distance", failures)
	_expect(not bool(summary.get("has_destination", true)), "attack target movement should not keep moving over an enemy that moved into range", failures)

	for index: int in [3, 4, 5]:
		var soldier := attacker.get_node_or_null("Soldiers/Soldier_%03d" % index)
		if soldier and soldier.has_method("apply_strength_damage"):
			soldier.call("apply_strength_damage", 999.0, &"test")
	attacker.call("_physics_process", 0.1)
	summary = attacker.call("get_troop_summary") as Dictionary
	_expect(bool(summary.get("survivor_rout_triggered", false)), "troops reduced to 4-5 active soldiers should rout some survivors", failures)
	_expect(int(summary.get("active_soldier_count", 0)) == 3, "survivor rout should leave a small active core instead of routing the whole troop", failures)
	_expect(int(summary.get("deserted_soldier_count", 0)) == 0, "survivor rout should not keep a deserter count", failures)
	_expect(get_nodes_in_group(&"deserter_troops").is_empty(), "survivor rout should not spawn managed deserter troops", failures)

	var remaining_active := _get_active_soldier_nodes(attacker)
	var final_survivor: Node = null
	for soldier: Node in remaining_active:
		if soldier is Node3D and _is_test_flag_holder(soldier as Node3D):
			final_survivor = soldier
			break
	if not final_survivor and not remaining_active.is_empty():
		final_survivor = remaining_active[0]
	_expect(final_survivor != null, "final survivor setup should keep an active soldier after the first rout", failures)
	_expect(final_survivor is Node3D and _is_test_flag_holder(final_survivor as Node3D), "final survivor setup should preserve a flag holder", failures)
	for soldier: Node in remaining_active:
		if soldier == final_survivor:
			continue
		if soldier.has_method("apply_strength_damage"):
			soldier.call("apply_strength_damage", 999.0, &"test")
	attacker.call("_physics_process", 0.1)
	summary = attacker.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("active_soldier_count", -1)) == 0, "final survivor rout should empty the original troop", failures)
	_expect(bool(summary.get("defeated", false)), "original troop should be defeated after the final survivor rout", failures)
	if final_survivor:
		_expect(final_survivor.get_parent() != attacker.get_node_or_null("Soldiers"), "final flag holder should transfer out instead of staying killable in the defeated troop", failures)

	for node: Node in [enemy, attacker, controller]:
		if is_instance_valid(node) and node.get_parent():
			node.get_parent().remove_child(node)
			node.free()


func _check_troop_desertion(failures: Array[String]) -> void:
	var small := TroopScene.instantiate()
	small.set("troop_id", &"small_morale")
	small.set("team_id", &"player")
	small.set("soldier_count", 3)
	small.set("base_soldier_morale", 2.0)
	small.set("soldier_morale_variance", 0.0)
	small.set("desertion_morale_threshold", 50.0)
	small.set("desertion_chance_per_second", 1.0)
	small.set("detection_range_m", 80.0)
	small.set("combat_seed", 300)
	root.add_child(small)

	var large := TroopScene.instantiate()
	large.set("troop_id", &"large_pressure")
	large.set("team_id", &"enemy")
	large.set("controllable", false)
	large.set("soldier_count", 10)
	large.set("detection_range_m", 80.0)
	large.position = Vector3(5.0, 0.0, 0.0)
	root.add_child(large)
	await process_frame

	for _index: int in range(10):
		small.call("_physics_process", 0.5)
	var summary: Dictionary = small.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("deserted_soldier_count", 0)) == 0, "low morale departures should not keep a deserter count", failures)
	_expect(int(summary.get("active_soldier_count", 0)) < 3, "low morale departures should leave the current formation", failures)
	_expect(get_nodes_in_group(&"deserter_troops").is_empty(), "low morale departures should not create managed deserter troops", failures)

	root.remove_child(large)
	large.free()
	root.remove_child(small)
	small.free()


func _check_enemy_spawner(failures: Array[String]) -> void:
	var spawner := TroopEnemySpawnerScript.new()
	spawner.spawn_seed = 123
	spawner.min_enemy_troops = 2
	spawner.max_enemy_troops = 2
	spawner.min_soldiers_per_troop = 4
	spawner.max_soldiers_per_troop = 6
	spawner.movement_map = _make_map(8, 8)
	root.add_child(spawner)
	await process_frame

	var spawned: Array = spawner.call("get_spawned_troops") as Array
	_expect(spawned.size() == 2, "enemy spawner should create deterministic enemy troop count", failures)
	for troop_variant: Variant in spawned:
		var troop := troop_variant as Node
		_expect(troop != null and StringName(troop.get("team_id")) == &"enemy", "spawned troops should use enemy team id", failures)
		_expect(troop != null and not bool(troop.get("controllable")), "spawned enemy troops should not be player-commandable", failures)
		if troop:
			_expect(_color_close(troop.get("ring_color") as Color, spawner.enemy_ring_color), "spawned enemy troops should use enemy ring color", failures)
			var first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
			_expect(first_soldier != null, "spawned enemy troops should create soldiers", failures)
			if first_soldier and first_soldier.has_method("get_outfit_summary"):
				var outfit: Dictionary = first_soldier.call("get_outfit_summary") as Dictionary
				_expect(_color_close(outfit.get("robe", Color.TRANSPARENT) as Color, spawner.enemy_robe_color), "spawned enemy soldiers should use the dark red outfit palette", failures)

	for troop_variant: Variant in spawned:
		var troop := troop_variant as Node
		if troop and troop.get_parent():
			troop.get_parent().remove_child(troop)
			troop.free()
	root.remove_child(spawner)
	spawner.free()


func _check_automatic_logistics_commands(failures: Array[String]) -> void:
	var controller := TroopSelectionControllerScript.new()
	root.add_child(controller)

	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("carrier_speed_mps", 500.0)
	troop.set("carrier_work_seconds", 0.0)
	troop.set("food_kg_per_soldier_per_day", 0.0)
	root.add_child(troop)

	var near_village := FakeVillage.new()
	near_village.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(near_village)
	var far_village := FakeVillage.new()
	far_village.position = Vector3(80.0, 0.0, 0.0)
	root.add_child(far_village)

	var near_forest := FakeForest.new()
	near_forest.position = Vector3(10.0, 0.0, 0.0)
	root.add_child(near_forest)
	var far_forest := FakeForest.new()
	far_forest.position = Vector3(100.0, 0.0, 0.0)
	root.add_child(far_forest)
	await process_frame

	var started_food: bool = bool(controller.call("_issue_nearest_food_collection", troop, 30.0))
	_expect(started_food, "collect food button command should find the nearest village storage", failures)
	_step_troop_logistics(troop, 8)
	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_food_kg", 0.0)), 30.0, 0.001), "automatic food collection should add food to troop load", failures)
	_expect(_approx(near_village.storage_food_kg, 70.0, 0.001), "automatic food collection should withdraw from the nearest village", failures)
	_expect(_approx(far_village.storage_food_kg, 100.0, 0.001), "automatic food collection should ignore farther villages", failures)

	var started_wood: bool = bool(controller.call("_issue_nearest_wood_collection", troop, 2))
	_expect(started_wood, "collect wood button command should find the nearest forest tree", failures)
	_step_troop_logistics(troop, 8)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_wood_kg", 0.0)), 40.0, 0.001), "automatic wood collection should add assigned soldiers' wood load", failures)
	_expect(not near_forest.tree_cells.has(Vector2i(0, 0)), "automatic wood collection should harvest the nearest tree cell", failures)
	_expect(far_forest.tree_cells.has(Vector2i(0, 0)), "automatic wood collection should ignore farther forests", failures)

	for node: Node in [far_forest, near_forest, far_village, near_village, troop, controller]:
		root.remove_child(node)
		node.free()


func _check_carrier_visuals_are_independent_and_labeled(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 4)
	troop.set("carrier_speed_mps", 1.5)
	troop.set("carrier_work_seconds", 0.5)
	root.add_child(troop)

	var village := FakeVillage.new()
	village.position = Vector3(12.0, 0.0, 0.0)
	root.add_child(village)
	await process_frame

	var missions_before := get_nodes_in_group(&"mission_troops")
	var started_food: bool = bool(troop.call("begin_food_collection", village, 20.0))
	_expect(started_food, "troop should start a food mission troop for visual checks", failures)
	var summary_after_start: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary_after_start.get("active_soldier_count", 0)) == 3, "collector soldiers should leave an empty slot in the troop formation", failures)
	_expect(int(summary_after_start.get("busy_carrier_soldiers", 0)) == 1, "collector soldiers should count as away while gathering", failures)

	var mission_troop: Node3D = null
	for candidate: Node in get_nodes_in_group(&"mission_troops"):
		if missions_before.has(candidate):
			continue
		if candidate is Node3D:
			mission_troop = candidate as Node3D
			break
	_expect(mission_troop != null, "collection should spawn an independent mission troop", failures)
	if not mission_troop:
		root.remove_child(village)
		village.free()
		root.remove_child(troop)
		troop.free()
		return

	_expect(mission_troop.top_level, "mission troop should be top-level so parent troop movement does not drag it", failures)
	_expect(mission_troop.has_method("get_troop_summary"), "mission troop should expose the normal troop summary", failures)
	_expect(bool((mission_troop.call("get_troop_summary") as Dictionary).get("mission_active", false)), "mission troop summary should report an active mission", failures)
	var soldiers := mission_troop.get_node_or_null("Soldiers")
	_expect(soldiers != null and soldiers.get_child_count() > 0, "mission troop should own the assigned soldiers", failures)
	if not soldiers or soldiers.get_child_count() <= 0:
		root.remove_child(village)
		village.free()
		root.remove_child(troop)
		troop.free()
		return

	var carrier := soldiers.get_child(0) as Node3D
	_expect(carrier.find_child("ResourceIcon", true, false) != null, "mission soldiers should show a resource icon", failures)
	_expect(carrier.find_child("TeamFlag", true, false) == null and carrier.find_child("TroopFlag", true, false) == null, "mission soldiers should not carry hand flags", failures)
	_expect(mission_troop.has_method("has_management_flag") and bool(mission_troop.call("has_management_flag")), "mission troop should still use the management flag for selection", failures)
	var before_troop_move := mission_troop.global_position
	troop.global_position += Vector3(20.0, 0.0, 0.0)
	_expect(
		mission_troop.global_position.distance_to(before_troop_move) < 0.001,
		"mission troop should keep its world position when the parent troop moves",
		failures
	)

	mission_troop.call("_physics_process", 0.2)
	_expect(
		mission_troop.global_position.distance_to(before_troop_move) > 0.01,
		"mission troop should move independently toward the resource",
		failures
	)
	if carrier.has_method("is_formation_walking"):
		_expect(bool(carrier.call("is_formation_walking")), "mission soldiers should play walking animation while moving", failures)
	if is_instance_valid(mission_troop) and mission_troop.get_parent():
		mission_troop.get_parent().remove_child(mission_troop)
		mission_troop.free()
	root.remove_child(village)
	village.free()
	root.remove_child(troop)
	troop.free()


func _check_troop_logistics_tasks(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("carrier_speed_mps", 500.0)
	troop.set("carrier_work_seconds", 0.0)
	troop.set("food_kg_per_soldier_per_day", 0.0)
	root.add_child(troop)

	var village := FakeVillage.new()
	village.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(village)
	await process_frame

	var started_food: bool = bool(troop.call("begin_food_collection", village, 45.0))
	_expect(started_food, "troop should start a village food mission", failures)
	_step_troop_logistics(troop, 8)
	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_food_kg", 0.0)), 45.0, 0.001), "food mission should add withdrawn food to troop load", failures)
	_expect(_approx(village.storage_food_kg, 55.0, 0.001), "food mission should withdraw from village storage", failures)

	var forest := FakeForest.new()
	forest.position = Vector3(10.0, 0.0, 0.0)
	root.add_child(forest)
	var started_wood: bool = bool(troop.call("begin_wood_collection", forest, Vector2i(0, 0), 2))
	_expect(started_wood, "troop should start a forest wood mission", failures)
	_step_troop_logistics(troop, 8)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_wood_kg", 0.0)), 40.0, 0.001), "wood mission should add one 20kg load per assigned soldier", failures)
	_expect(not forest.tree_cells.has(Vector2i(0, 0)), "wood harvest should remove the cut tree cell from the source", failures)
	_expect(bool(troop.call("craft_cargo_trolley")), "troop should craft a trolley when carrying enough wood", failures)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(bool(summary.get("cargo_trolley_crafting", false)), "crafting a trolley should enter a timed build state", failures)
	_expect(int(summary.get("cargo_trolley_count", 0)) == 0, "crafting should not add the trolley immediately", failures)
	_expect(_approx(float(summary.get("carried_wood_kg", -1.0)), 0.0, 0.001), "starting trolley crafting should consume its wood cost", failures)
	_expect(troop.find_child("CraftingCargoTrolley", true, false) != null, "crafting should show an unfinished trolley model", failures)
	_step_troop_logistics(troop, 49)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("cargo_trolley_count", 0)) == 0, "trolley should still be under construction before 5 seconds", failures)
	_step_troop_logistics(troop, 2)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(not bool(summary.get("cargo_trolley_crafting", true)), "trolley crafting should finish after its build time", failures)
	_expect(int(summary.get("cargo_trolley_count", 0)) == 1, "finished trolley craft should increment trolley count", failures)
	_expect(float(summary.get("carry_capacity_kg", 0.0)) > 120.0, "crafted trolley should increase troop carry capacity", failures)
	_expect(troop.find_child("CargoTrolley_00", true, false) != null, "finished trolley should remain visible as a 3d model", failures)
	forest.tree_cells[Vector2i(2, 0)] = true
	var started_trolley_wood: bool = bool(troop.call("begin_wood_collection", forest, Vector2i(2, 0), 2))
	_expect(started_trolley_wood, "two selected soldiers should be able to collect wood with a crafted trolley", failures)
	_expect(_find_node_in_group_with_child(&"mission_troops", "TrolleyHint") != null, "collecting with a trolley should show a trolley model with the mission troop", failures)
	_step_troop_logistics(troop, 8)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_wood_kg", 0.0)), 200.0, 0.001), "two-soldier trolley wood task should carry 200kg", failures)

	troop.set("carried_food_kg", 15.0)
	troop.set("carried_wood_kg", 110.0)
	_expect(bool(troop.call("establish_camp")), "troop should establish camp when carrying enough wood", failures)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(bool(summary.get("camp_established", false)), "camp should be marked established", failures)
	_expect(int(summary.get("camp_living_hut_count", 0)) == 1, "six test soldiers should establish one living hut", failures)
	_expect(_approx(float(summary.get("camp_total_wood_cost_kg", 0.0)), 100.0, 0.001), "one living hut camp should cost 100kg wood", failures)
	_expect(_approx(float(summary.get("carried_wood_kg", -1.0)), 0.0, 0.001), "camp construction should consume living hut wood", failures)
	_expect(_approx(float(summary.get("carried_food_kg", -1.0)), 0.0, 0.001), "camp construction should move carried food into camp storage", failures)
	_expect(_approx(float(summary.get("camp_food_kg", -1.0)), 15.0, 0.001), "camp storage should keep troop food after establishment", failures)
	_expect(_approx(float(summary.get("camp_wood_kg", -1.0)), 10.0, 0.001), "camp storage should keep leftover troop wood after establishment", failures)
	var camp_proxy := _find_node_in_group_with_child(&"camps", "CampClickProxy")
	_expect(camp_proxy != null and StringName(camp_proxy.get_meta(&"troop_selectable_type", &"")) == &"camp", "camp should expose a selectable camp proxy", failures)
	_expect(_flag_uses_unshaded_materials(root, "CampFlag"), "camp flag should ignore scene lighting", failures)
	var camp_position: Vector3 = summary.get("camp_position", troop.global_position)
	troop.global_position += Vector3(40.0, 0.0, 0.0)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(bool(summary.get("camp_established", false)), "camp should persist when the troop moves away", failures)
	_expect(not bool(summary.get("camp_pack_in_range", true)), "camp should not be packable when the troop is outside camp range", failures)
	_expect(not bool(troop.call("pack_camp")), "camp packing should fail outside its range", failures)
	troop.global_position = camp_position
	_expect(bool(troop.call("pack_camp")), "troop should pack an established camp", failures)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(not bool(summary.get("camp_established", true)), "packed camp should clear camp state", failures)
	_expect(_approx(float(summary.get("carried_food_kg", 0.0)), 15.0, 0.001), "packing camp should return camp food to the troop", failures)
	_expect(_approx(float(summary.get("carried_wood_kg", 0.0)), 110.0, 0.001), "packing camp should return stored and invested camp wood", failures)

	var started_cow: bool = bool(troop.call("pickup_cow_from_forest", forest, Vector2i(1, 0)))
	_expect(started_cow, "troop should start a cow pickup task", failures)
	_step_troop_logistics(troop, 8)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("cow_count", 0)) == 1, "cow pickup task should add one cow to the troop", failures)
	_expect(not forest.cow_cells.has(Vector2i(1, 0)), "cow pickup should remove the cow cell from the source", failures)

	root.remove_child(forest)
	forest.free()
	root.remove_child(village)
	village.free()
	root.remove_child(troop)
	troop.free()


func _check_forest_region_gathering_api(failures: Array[String]) -> void:
	var forest := ForestRegionScript.new() as ForestRegion
	forest.async_runtime_preview_on_ready = false
	forest.set_forest_data(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		{
			"0,0": [&"forest_tree_01"],
			"1,0": [&"forest_cow_01"],
			"2,0": [&"forest_tree_01", &"forest_cow_01"],
		}
	)
	_expect(bool(forest.call("is_tree_cell", Vector2i(0, 0))), "ForestRegion should classify tree cells as wood sources", failures)
	var tree_cells: Array = forest.call("get_tree_cells") as Array
	_expect(tree_cells.has(Vector2i(0, 0)), "ForestRegion should expose tree cells for automatic wood collection", failures)
	_expect(bool(forest.call("is_cow_cell", Vector2i(1, 0))), "ForestRegion should classify cow plant cells as cow sources", failures)
	var harvested := float(forest.call("harvest_wood_cell", Vector2i(2, 0), 20.0))
	_expect(_approx(harvested, 20.0, 0.001), "ForestRegion wood harvest should return requested wood up to cell yield", failures)
	_expect(not bool(forest.call("is_tree_cell", Vector2i(2, 0))), "ForestRegion harvest should remove tree visuals from the cell", failures)
	_expect(bool(forest.call("is_cow_cell", Vector2i(2, 0))), "ForestRegion harvest should leave cow plants in mixed cells", failures)
	_expect(bool(forest.call("pickup_cow_cell", Vector2i(2, 0))), "ForestRegion should pick up cows from mixed cells", failures)
	_expect(not bool(forest.call("is_cow_cell", Vector2i(2, 0))), "ForestRegion cow pickup should remove cow visuals", failures)
	forest.free()


func _check_camera_recovers_from_consumed_right_release(failures: Array[String]) -> void:
	var camera_rig := RTSCameraScene.instantiate()
	root.add_child(camera_rig)
	await process_frame

	camera_rig.set("_right_mouse_pressed", true)
	camera_rig.set("_is_rotating", true)
	camera_rig.call("cancel_right_drag_rotation")
	_expect(not bool(camera_rig.get("_right_mouse_pressed")), "camera formation-drag cancel should clear right mouse state", failures)
	_expect(not bool(camera_rig.get("_is_rotating")), "camera formation-drag cancel should clear rotation state", failures)

	camera_rig.set("_right_mouse_pressed", true)
	camera_rig.set("_is_rotating", true)
	camera_rig.call("_process", 0.016)
	_expect(
		not bool(camera_rig.get("_right_mouse_pressed")),
		"camera should clear stale right mouse state when release is consumed",
		failures
	)
	_expect(
		not bool(camera_rig.get("_is_rotating")),
		"camera should leave right-drag rotation when right mouse is no longer pressed",
		failures
	)

	root.remove_child(camera_rig)
	camera_rig.free()


func _check_drawer_loads(failures: Array[String]) -> void:
	var drawer := TroopDrawerScene.instantiate()
	_expect(drawer is CanvasLayer, "troop drawer scene should instantiate a CanvasLayer", failures)
	_expect(drawer.has_method("show_troop"), "troop drawer should expose show_troop", failures)
	_expect(drawer.has_signal(&"collect_wood_requested"), "troop drawer should expose collect wood command signal", failures)
	_expect(drawer.find_child("CollectWoodButton", true, false) != null, "troop drawer should show a collect wood button", failures)
	_expect(drawer.find_child("TroopModeOption", true, false) != null, "troop drawer should show a troop mode selector", failures)
	_expect(drawer.find_child("MovementModeOption", true, false) != null, "troop drawer should show a movement mode selector", failures)
	drawer.free()


func _check_background_jobs_debug_panel(failures: Array[String]) -> void:
	var panel := TroopJobsDebugPanelScene.instantiate()
	panel.set("force_visible", true)
	root.add_child(panel)
	await process_frame
	_expect(panel is CanvasLayer, "background jobs debug panel should instantiate a CanvasLayer", failures)
	_expect(panel.has_method("set_selected_troop"), "background jobs debug panel should accept selected troops", failures)
	_expect(panel.has_method("refresh"), "background jobs debug panel should expose refresh", failures)
	_expect(panel.find_child("FrameLabel", true, false) != null, "background jobs debug panel should show frame metrics", failures)
	_expect(panel.find_child("AggregateLabel", true, false) != null, "background jobs debug panel should show aggregate metrics", failures)
	_expect(panel.find_child("SelectedLabel", true, false) != null, "background jobs debug panel should show selected troop metrics", failures)
	_expect(panel.find_child("SoldierPerfCheckBox", true, false) != null, "background jobs debug panel should expose soldier profiling toggle", failures)

	var controller := TroopSelectionControllerScript.new()
	controller.background_jobs_debug_panel_path = panel.get_path()
	root.add_child(controller)
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 3)
	root.add_child(troop)
	await process_frame
	controller.call("_select_troop", troop)
	_expect(panel.call("get_selected_troop") == troop, "troop selection controller should update the background jobs debug panel selection", failures)
	var summary: Dictionary = troop.call("get_stat_job_debug_summary") as Dictionary
	_expect(summary.has("last_worker_ms") and summary.has("pending_apply_results"), "troop should expose stat job debug summary fields", failures)
	_expect(summary.has("perf_last_physics_ms") and summary.has("combat_perf_separation_pair_checks"), "troop should expose runtime profiling summary fields", failures)
	_expect(summary.has("formation_target_write_count") and summary.has("moving_formation_pair_checks"), "troop should expose moving formation profiling fields", failures)
	_expect(summary.has("spatial_grid_rebuilds") and summary.has("combat_socket_clamp_count"), "troop should expose spatial/socket profiling fields", failures)
	_expect(summary.has("logic_sleeping_soldier_count"), "troop should expose sleeping soldier count", failures)
	_expect(troop.has_method("reset_perf_debug_counters"), "troop should reset runtime profiling counters", failures)

	for node: Node in [troop, controller, panel]:
		if is_instance_valid(node) and node.get_parent():
			node.get_parent().remove_child(node)
			node.free()


func _check_scene_wiring(scene_path: String, failures: Array[String]) -> void:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s should load as a PackedScene" % scene_path, failures)
	if not scene:
		return

	var instance := scene.instantiate()
	_expect(instance != null, "%s should instantiate" % scene_path, failures)
	if not instance:
		return

	_expect(
		instance.find_child("TroopSelectionController", true, false) != null,
		"%s should include a troop selection controller" % scene_path,
		failures
	)
	_expect(
		instance.find_child("TroopManagementDrawer", true, false) != null,
		"%s should include a troop management drawer" % scene_path,
		failures
	)
	_expect(
		instance.find_child("TroopBackgroundJobsDebugPanel", true, false) != null,
		"%s should include the background jobs debug panel" % scene_path,
		failures
	)
	var troop := instance.find_child("Troop_01", true, false)
	_expect(troop != null, "%s should include a default troop instance" % scene_path, failures)
	if troop:
		_expect(not String(troop.get("movement_map_path")).is_empty(), "%s troop should have a movement map path" % scene_path, failures)
		var terrain_path: NodePath = troop.get("terrain_path")
		_expect(not terrain_path.is_empty(), "%s troop should have a terrain path" % scene_path, failures)
		_expect(StringName(troop.get("team_id")) == &"player", "%s default troop should belong to player team" % scene_path, failures)
	_expect(
		instance.find_child("EnemyTroopSpawner", true, false) != null,
		"%s should include an enemy troop spawner" % scene_path,
		failures
	)

	instance.free()


func _make_map(width: int, height: int) -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2.ZERO
	data.cell_size_meters = 1.0
	data.resize_map(width, height, 1.0, 0)
	return data


func _set_blocked(data: MovementMapData, cell: Vector2i) -> void:
	var index := data.get_cell_index(cell)
	if index >= 0:
		data.speed_multipliers[index] = 0.0


func _step_troop_logistics(troop: Node, steps: int) -> void:
	for _index: int in range(steps):
		troop.call("_physics_process", 0.1)
		for mission: Node in get_nodes_in_group(&"mission_troops"):
			if not is_instance_valid(mission) or mission.is_queued_for_deletion():
				continue
			if mission.has_method("get_troop_summary"):
				var summary := mission.call("get_troop_summary") as Dictionary
				if not bool(summary.get("mission_active", false)):
					continue
			if mission.has_method("_physics_process"):
				mission.call("_physics_process", 0.1)


func _step_troop_with_soldiers(troop: Node, delta: float) -> void:
	if is_instance_valid(troop):
		troop.call("_physics_process", delta)
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.has_method("step_formation_logic"):
			continue
		if is_instance_valid(soldier) and soldier.has_method("_physics_process"):
			soldier.call("_physics_process", delta)


func _find_first_mesh_instance(root_node: Node) -> MeshInstance3D:
	if not root_node:
		return null
	if root_node is MeshInstance3D:
		return root_node as MeshInstance3D
	var matches := root_node.find_children("*", "MeshInstance3D", true, false)
	for match: Node in matches:
		if match is MeshInstance3D:
			return match as MeshInstance3D
	return null


func _approx(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _find_node_in_group_with_child(group_name: StringName, child_name: String) -> Node:
	for node: Node in get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		var child := node.find_child(child_name, true, false)
		if child:
			return child
	return null


func _get_spear_visual_length_m(spear: Node3D) -> float:
	if not spear:
		return 0.0
	var min_y := INF
	var max_y := -INF
	for child: Node in spear.get_children():
		var mesh_instance := child as MeshInstance3D
		if not mesh_instance:
			continue
		var cylinder := mesh_instance.mesh as CylinderMesh
		if not cylinder:
			continue
		var mesh_scale := mesh_instance.transform.basis.get_scale()
		var half_height := cylinder.height * absf(mesh_scale.y) * 0.5
		var center_y := mesh_instance.transform.origin.y
		min_y = minf(min_y, center_y - half_height)
		max_y = maxf(max_y, center_y + half_height)
	if min_y == INF or max_y == -INF:
		return 0.0
	return (max_y - min_y) * absf(spear.transform.basis.get_scale().y)


func _get_spear_shaft_center_grip_offset_m(spear: Node3D) -> float:
	if not spear:
		return INF
	var shaft := spear.get_node_or_null("Shaft") as MeshInstance3D
	if not shaft:
		return INF
	return spear.transform.origin.y + shaft.transform.origin.y * absf(spear.transform.basis.get_scale().y)


func _color_close(actual: Color, expected: Color, tolerance: float = 0.01) -> bool:
	return (
		absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance
		and absf(actual.a - expected.a) <= tolerance
	)


func _flag_uses_unshaded_materials(root_node: Node, flag_name: String) -> bool:
	var flag := root_node.find_child(flag_name, true, false)
	if not flag:
		return false
	if not _flag_surface_uses_unshaded_material(flag, "Pole"):
		return false
	if not _flag_surface_uses_unshaded_material(flag, "Banner"):
		return false
	if _flag_surface_uses_unshaded_material(flag, "AccentStripe"):
		return true
	return _flag_surface_uses_unshaded_material(flag, "TeamStripe")


func _flag_surface_uses_unshaded_material(flag: Node, surface_name: String) -> bool:
	var surface := flag.find_child(surface_name, true, false) as MeshInstance3D
	if not surface:
		return false
	var material := surface.material_override as StandardMaterial3D
	return (
		material != null
		and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and material.cull_mode == BaseMaterial3D.CULL_DISABLED
	)


func _mesh_uses_solid_vertex_color(mesh: Mesh) -> bool:
	if not (mesh is ArrayMesh):
		return false
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return false
	var expected := colors[0]
	for color: Color in colors:
		if not _color_close(color, expected, 0.001):
			return false
	return true


func _attack_zone_has_faint_fill_and_clear_border(mesh: Mesh) -> bool:
	if not (mesh is ArrayMesh):
		return false
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return false
	var min_alpha := 1.0
	var max_alpha := 0.0
	for color: Color in colors:
		min_alpha = minf(min_alpha, color.a)
		max_alpha = maxf(max_alpha, color.a)
	return min_alpha <= 0.05 and max_alpha >= 0.55


func _get_soldier_nodes(troop: Node) -> Array[Node]:
	var soldiers_container := troop.get_node_or_null("Soldiers")
	if not soldiers_container:
		return []
	return soldiers_container.get_children()


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


func _active_formation_indices_are_compact(troop: Node) -> bool:
	var soldiers := _get_active_soldier_nodes(troop)
	var seen_indices := {}
	for expected_index: int in range(soldiers.size()):
		var soldier := soldiers[expected_index]
		if not (soldier is Node3D):
			return false
		var index := int((soldier as Node3D).get_meta(&"troop_formation_index", -1))
		if index < 0 or index >= soldiers.size() or seen_indices.has(index):
			return false
		seen_indices[index] = true
	return seen_indices.size() == soldiers.size()


func _is_test_flag_holder(soldier: Node3D) -> bool:
	return soldier.find_child("TeamFlag", true, false) != null or soldier.find_child("TroopFlag", true, false) != null


func _average_soldier_world_position(troop: Node) -> Vector3:
	var soldiers := _get_soldier_nodes(troop)
	if soldiers.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	var count := 0
	for soldier: Node in soldiers:
		if soldier is Node3D:
			total += (soldier as Node3D).global_position
			count += 1
	return total / float(maxi(count, 1))


func _count_damaged_soldiers(troop: Node) -> int:
	var count := 0
	for soldier: Node in _get_soldier_nodes(troop):
		if not soldier.has_method("get_combat_summary"):
			continue
		var summary: Dictionary = soldier.call("get_combat_summary") as Dictionary
		if float(summary.get("strength", 0.0)) < float(summary.get("max_strength", 0.0)) - 0.01:
			count += 1
	return count


func _count_soldiers_away_from_slots(troop: Node, threshold: float) -> int:
	var count := 0
	for soldier: Node in _get_soldier_nodes(troop):
		if not (soldier is Node3D):
			continue
		var spatial := soldier as Node3D
		var slot: Vector3 = spatial.get_meta(&"troop_formation_slot", spatial.position)
		var delta := spatial.global_position - _troop_slot_to_world(troop, slot)
		delta.y = 0.0
		if delta.length() > threshold:
			count += 1
	return count


func _get_global_corpse_count() -> int:
	var manager := root.get_node_or_null("TroopCorpseManager")
	if manager and manager.has_method("get_corpse_count"):
		return int(manager.call("get_corpse_count"))
	return 0


func _minimum_soldier_spacing(troop: Node) -> float:
	var soldiers := _get_soldier_nodes(troop)
	var minimum := INF
	for index: int in range(soldiers.size()):
		if not (soldiers[index] is Node3D):
			continue
		var a := soldiers[index] as Node3D
		for other_index: int in range(index + 1, soldiers.size()):
			if not (soldiers[other_index] is Node3D):
				continue
			var b := soldiers[other_index] as Node3D
			var a_pos := a.global_position
			var b_pos := b.global_position
			a_pos.y = 0.0
			b_pos.y = 0.0
			minimum = minf(minimum, a_pos.distance_to(b_pos))
	return minimum if minimum < INF else 0.0


func _soldier_local_positions(troop: Node) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier is Node3D:
			positions.append((soldier as Node3D).global_position)
	return positions


func _max_soldier_displacement(before: Array[Vector3], after: Array[Vector3]) -> float:
	var count := mini(before.size(), after.size())
	var maximum := 0.0
	for index: int in range(count):
		var delta := before[index] - after[index]
		delta.y = 0.0
		maximum = maxf(maximum, delta.length())
	return maximum


func _all_soldiers_near_troop_root(troop: Node, max_distance: float) -> bool:
	if not (troop is Node3D):
		return false
	var root_position := (troop as Node3D).global_position
	for soldier: Node in _get_soldier_nodes(troop):
		if not (soldier is Node3D):
			continue
		var soldier_position := (soldier as Node3D).global_position
		soldier_position.y = root_position.y
		if soldier_position.distance_to(root_position) > max_distance:
			return false
	return true


func _any_soldier_has_independent_motion(troop: Node) -> bool:
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			return true
	return false


func _all_soldier_route_paths_empty(troop: Node) -> bool:
	for soldier: Node in _get_soldier_nodes(troop):
		var path_points: Array = soldier.get("_independent_path_points")
		if not path_points.is_empty():
			return false
	return true


func _combat_target_ids(troop: Node) -> Dictionary:
	var target_ids := {}
	for soldier: Node in _get_soldier_nodes(troop):
		if not soldier.has_method("get_combat_target"):
			continue
		var target := soldier.call("get_combat_target") as Node
		if is_instance_valid(target):
			target_ids[soldier.get_instance_id()] = target.get_instance_id()
	return target_ids


func _combat_lock_positions(troop: Node) -> Dictionary:
	var positions := {}
	for soldier: Node in _get_soldier_nodes(troop):
		if troop.has_method("has_combat_lock_for_soldier") and bool(troop.call("has_combat_lock_for_soldier", soldier)):
			positions[soldier.get_instance_id()] = troop.call("get_combat_lock_position_for_soldier", soldier)
	return positions


func _max_combat_socket_distance_to_target(troop: Node) -> float:
	var positions: Dictionary = troop.get("_combat_soldier_socket_positions")
	var targets: Dictionary = troop.get("_combat_soldier_targets")
	var maximum := 0.0
	for key: Variant in positions.keys():
		var position_variant: Variant = positions.get(key)
		var target_variant: Variant = targets.get(key)
		if not (position_variant is Vector3):
			continue
		if not (target_variant is Node3D) or not is_instance_valid(target_variant):
			continue
		var socket_position := position_variant as Vector3
		var target_position := (target_variant as Node3D).global_position
		socket_position.y = target_position.y
		maximum = maxf(maximum, socket_position.distance_to(target_position))
	return maximum


func _combat_sockets_include_opposed_slots(troop: Node) -> bool:
	var vectors := _loaded_combat_socket_vectors(troop)
	if vectors.size() < 4:
		return false
	for a: Vector3 in vectors:
		for b: Vector3 in vectors:
			if a == b:
				continue
			if a.dot(b) <= -0.72:
				return true
	return false


func _combat_sockets_include_side_slots(troop: Node) -> bool:
	var vectors := _loaded_combat_socket_vectors(troop)
	if vectors.size() < 4:
		return false
	var targets: Dictionary = troop.get("_combat_soldier_targets")
	var defenders: Array[Node3D] = []
	for target_variant: Variant in targets.values():
		if target_variant is Node3D and is_instance_valid(target_variant) and not defenders.has(target_variant):
			defenders.append(target_variant as Node3D)
	if defenders.is_empty():
		return false
	var defender := defenders[0]
	var approach := (troop as Node3D).global_position - defender.global_position
	approach.y = 0.0
	if approach.length_squared() <= 0.0001:
		approach = Vector3.LEFT
	approach = approach.normalized()
	var side := Vector3(-approach.z, 0.0, approach.x)
	var left_count := 0
	var right_count := 0
	for direction: Vector3 in vectors:
		var side_dot := direction.dot(side)
		if side_dot > 0.5:
			left_count += 1
		elif side_dot < -0.5:
			right_count += 1
	return left_count > 0 and right_count > 0


func _loaded_combat_socket_vectors(troop: Node) -> Array:
	var positions: Dictionary = troop.get("_combat_soldier_socket_positions")
	var targets: Dictionary = troop.get("_combat_soldier_targets")
	var vectors_by_target := {}
	for key: Variant in positions.keys():
		var position_variant: Variant = positions.get(key)
		var target_variant: Variant = targets.get(key)
		if not (position_variant is Vector3):
			continue
		if not (target_variant is Node3D) or not is_instance_valid(target_variant):
			continue
		var target := target_variant as Node3D
		var from_target := (position_variant as Vector3) - target.global_position
		from_target.y = 0.0
		if from_target.length_squared() <= 0.0001:
			continue
		var target_id := target.get_instance_id()
		var target_vectors: Array = vectors_by_target.get(target_id, [])
		target_vectors.append(from_target.normalized())
		vectors_by_target[target_id] = target_vectors
	var best: Array = []
	for vectors_variant: Variant in vectors_by_target.values():
		var vectors := vectors_variant as Array
		if vectors.size() > best.size():
			best = vectors
	return best


func _combat_soldiers_face_assigned_targets(troop: Node, max_angle: float) -> bool:
	var targets: Dictionary = troop.get("_combat_soldier_targets")
	var checked := 0
	for key: Variant in targets.keys():
		var soldier := _get_soldier_by_instance_id(troop, int(key)) as Node3D
		var target := targets.get(key) as Node3D
		if not is_instance_valid(soldier) or not is_instance_valid(target):
			continue
		var to_target := target.global_position - soldier.global_position
		to_target.y = 0.0
		if to_target.length_squared() <= 0.0001:
			continue
		var forward := -soldier.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() <= 0.0001:
			return false
		var angle := forward.normalized().angle_to(to_target.normalized())
		if angle > max_angle:
			return false
		checked += 1
	return checked > 0


func _combat_targets_match(troop: Node, expected: Dictionary) -> bool:
	for soldier_id: Variant in expected.keys():
		var soldier := _get_soldier_by_instance_id(troop, int(soldier_id))
		if not soldier or not soldier.has_method("get_combat_target"):
			return false
		var target := soldier.call("get_combat_target") as Node
		if not is_instance_valid(target) or target.get_instance_id() != int(expected[soldier_id]):
			return false
	return not expected.is_empty()


func _combat_soldiers_within_shuffle_radius(troop: Node, lock_positions: Dictionary, radius: float) -> bool:
	if lock_positions.is_empty():
		return false
	for soldier_id: Variant in lock_positions.keys():
		var soldier := _get_soldier_by_instance_id(troop, int(soldier_id))
		if not (soldier is Node3D):
			return false
		var lock_position: Vector3 = lock_positions[soldier_id]
		var delta := (soldier as Node3D).global_position - lock_position
		delta.y = 0.0
		if delta.length() > radius:
			return false
	return true


func _get_soldier_by_instance_id(troop: Node, instance_id: int) -> Node:
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.get_instance_id() == instance_id:
			return soldier
	return null


func _dictionary_has_no_node_values(dictionary: Dictionary) -> bool:
	for value: Variant in dictionary.values():
		if value is Node:
			return false
	return true


func _visible_soldier_count(troop: Node) -> int:
	var count := 0
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier is Node3D and (soldier as Node3D).visible:
			count += 1
	return count


func _troop_slot_to_world(troop: Node, slot: Vector3) -> Vector3:
	if troop is Node3D:
		return (troop as Node3D).global_transform * slot
	return slot


func _positions_close(before: Array[Vector3], after: Array[Vector3], tolerance: float) -> bool:
	if before.size() != after.size():
		return false
	for index: int in range(before.size()):
		var delta := before[index] - after[index]
		delta.y = 0.0
		if delta.length() > tolerance:
			return false
	return true


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
