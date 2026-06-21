extends SceneTree

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")
const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")
const TroopSelectionControllerScript = preload("res://modules/troops/troop_selection_controller.gd")
const TroopEnemySpawnerScript = preload("res://modules/troops/troop_enemy_spawner.gd")
const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const TroopDrawerScene: PackedScene = preload("res://modules/troops/troop_management_drawer.tscn")
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
	await _check_killed_soldiers_disappear(failures)
	await _check_troop_route_visuals(failures)
	await _check_troop_modes_and_combat_stats(failures)
	await _check_troop_combat_resolution(failures)
	await _check_troop_desertion(failures)
	await _check_enemy_spawner(failures)
	await _check_automatic_logistics_commands(failures)
	await _check_carrier_visuals_are_independent_and_labeled(failures)
	await _check_troop_logistics_tasks(failures)
	_check_forest_region_gathering_api(failures)
	await _check_camera_recovers_from_consumed_right_release(failures)
	_check_drawer_loads(failures)
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
	_expect(float(troop.get("path_corner_radius_cells")) >= 1.0, "troop should expose broad path corner smoothing", failures)
	_expect(int(troop.get("path_corner_samples")) >= 8, "troop should expose dense curved path samples", failures)
	_expect(float(troop.get("route_steering_lookahead_m")) > 0.0, "troop should expose curved route steering lookahead", failures)
	_expect(float(troop.get("formation_turn_rate_degrees")) > 0.0, "troop should expose formation turn smoothing speed", failures)
	_expect(float(troop.get("formation_turn_inner_lag")) >= 0.0, "troop should expose formation corner lag tuning", failures)
	_expect(float(troop.get("formation_natural_unevenness")) >= 0.0, "troop should expose stable formation unevenness tuning", failures)
	_expect(int(troop.get("camp_soldiers_per_living_hut")) == 20, "troop camps should use one living hut per 20 soldiers by default", failures)
	_expect(_approx(float(troop.get("camp_living_hut_wood_cost_kg")), 100.0, 0.001), "troop living huts should cost 100kg wood by default", failures)
	_expect(_approx(float(troop.get("camp_building_scale")), 3.0, 0.001), "troop camps should use larger 3d camp buildings by default", failures)
	_expect(_approx(float(troop.get("cargo_trolley_craft_seconds")), 5.0, 0.001), "troop trolleys should take 5 seconds to craft by default", failures)
	_expect(int(troop.call("get_camp_living_hut_count")) == 1, "small troops should still need one living hut", failures)
	_expect(_approx(float(troop.call("get_camp_total_wood_cost_kg")), 100.0, 0.001), "one camp living hut should cost 100kg wood", failures)
	var first_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	_expect(first_soldier != null, "troop should create a first soldier node", failures)
	if first_soldier:
		_expect(first_soldier.has_method("get_right_hand_socket"), "troop soldier should inherit the human unit API", failures)
		_expect(first_soldier.has_method("set_formation_walking"), "troop soldier should expose formation walking animation control", failures)
		_expect((first_soldier as Node3D).top_level, "formation soldiers should own world movement instead of inheriting troop movement", failures)
		_expect(first_soldier.has_method("follow_formation_path"), "troop soldier should receive formation path commands", failures)
		_expect(first_soldier.has_method("set_independent_move_target"), "troop soldier should receive independent world move targets", failures)
		_expect(first_soldier.has_method("set_independent_combat"), "troop soldier should expose independent combat control", failures)
		_expect(first_soldier.has_method("trigger_spear_thrust"), "troop soldier should expose procedural spear thrust animation", failures)
		_expect(first_soldier.find_child("LowPolySpear", true, false) != null, "troop soldier should carry a long spear", failures)
	troop.set("soldier_count", 40)
	await process_frame
	_expect(int(troop.call("get_camp_living_hut_count")) == 2, "forty soldiers should require two living huts", failures)
	_expect(_approx(float(troop.call("get_camp_total_wood_cost_kg")), 200.0, 0.001), "two camp living huts should cost 200kg wood", failures)
	var proxy := troop.call("get_selection_proxy") as StaticBody3D
	_expect(proxy != null, "troop should create a selection proxy", failures)
	if proxy:
		_expect(proxy.has_meta(&"troop_selectable_type"), "selection proxy should carry troop metadata", failures)

	root.remove_child(troop)
	troop.free()


func _check_killed_soldiers_disappear(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 3)
	troop.set("base_soldier_strength", 10.0)
	troop.set("soldier_strength_variance", 0.0)
	root.add_child(troop)
	await process_frame

	var soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	_expect(soldier != null, "soldier disappearance check should find a soldier", failures)
	if soldier and soldier.has_method("apply_strength_damage"):
		soldier.call("apply_strength_damage", 999.0, &"test")
		await process_frame
		_expect(not is_instance_valid(soldier) or not (soldier as Node3D).visible, "killed soldiers should disappear from view", failures)
		var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
		_expect(int(summary.get("active_soldier_count", 0)) == 2, "killed disappeared soldiers should leave active troop count", failures)

	root.remove_child(troop)
	troop.free()


func _check_troop_route_visuals(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("movement_map", _make_map(8, 8))
	troop.set("position", Vector3(0.5, 0.0, 0.5))
	root.add_child(troop)
	await process_frame

	var accepted: bool = bool(troop.call("set_move_destination", Vector3(6.5, 0.0, 6.5)))
	_expect(accepted, "troop should accept a reachable movement order", failures)
	_expect(bool(troop.call("has_destination")), "troop should store a destination after a move order", failures)
	_expect(int(troop.call("get_route_dash_count")) > 0, "troop should draw dashed route visuals", failures)
	_expect(bool(troop.call("has_destination_marker")), "troop should draw a destination flag", failures)
	var moving_soldier := troop.get_node_or_null("Soldiers/Soldier_000")
	if moving_soldier and moving_soldier.has_method("is_formation_walking"):
		_expect(bool(moving_soldier.call("is_formation_walking")), "troop soldier should play walking animation while troop moves", failures)
	if moving_soldier and moving_soldier.has_method("has_independent_motion"):
		_expect(bool(moving_soldier.call("has_independent_motion")), "troop soldier should own a formation path command while troop moves", failures)
	if moving_soldier is Node3D:
		var before_anchor_shift := (moving_soldier as Node3D).global_position
		troop.global_position += Vector3(2.0, 0.0, 0.0)
		_expect(
			(moving_soldier as Node3D).global_position.distance_to(before_anchor_shift) < 0.001,
			"formation soldiers should not slide when only the troop anchor moves",
			failures
		)
		troop.global_position -= Vector3(2.0, 0.0, 0.0)
	troop.call("clear_destination")
	_expect(not bool(troop.call("has_destination")), "clear destination should remove active destination", failures)
	_expect(int(troop.call("get_route_dash_count")) == 0, "clear destination should clear route dashes", failures)
	if moving_soldier and moving_soldier.has_method("is_formation_walking"):
		_expect(not bool(moving_soldier.call("is_formation_walking")), "troop soldier should stop walking animation when troop movement clears", failures)

	root.remove_child(troop)
	troop.free()


func _check_troop_modes_and_combat_stats(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 5)
	troop.set("carried_food_kg", 100.0)
	troop.set("base_soldier_endurance", 60.0)
	troop.set("soldier_endurance_variance", 0.0)
	troop.set("base_soldier_damage", 5.0)
	troop.set("soldier_damage_variance", 0.0)
	root.add_child(troop)
	await process_frame

	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary.get("active_soldier_count", 0)) == 5, "troop summary should count active soldiers", failures)
	_expect(float(summary.get("average_endurance", 0.0)) > 0.0, "troop summary should expose average soldier endurance", failures)

	troop.call("set_troop_mode", &"training")
	var damage_before := float((troop.call("get_troop_summary") as Dictionary).get("average_damage", 0.0))
	var max_endurance_before := float((troop.call("get_troop_summary") as Dictionary).get("average_max_endurance", 0.0))
	troop.call("_physics_process", 1.0)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(StringName(summary.get("troop_mode", &"")) == &"training", "troop should store selected training mode", failures)
	_expect(float(summary.get("average_damage", 0.0)) > damage_before, "training mode should increase soldier damage", failures)
	_expect(float(summary.get("average_max_endurance", 0.0)) > max_endurance_before, "training mode should increase max endurance", failures)

	troop.call("set_movement_mode", &"running")
	_expect(StringName((troop.call("get_troop_summary") as Dictionary).get("movement_mode", &"")) == &"running", "troop should store selected running mode", failures)

	troop.set("carried_food_kg", 0.0)
	troop.set("food_kg_per_soldier_per_day", 1000.0)
	troop.call("_physics_process", 1.0)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(float(summary.get("food_shortage_ratio", 0.0)) > 0.0, "food shortage should be reported when troop has no food", failures)

	root.remove_child(troop)
	troop.free()


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
	for _index: int in range(8):
		_step_troop_with_soldiers(player, 0.2)
		_step_troop_with_soldiers(enemy, 0.2)
	var enemy_summary: Dictionary = enemy.call("get_troop_summary") as Dictionary
	var player_summary: Dictionary = player.call("get_troop_summary") as Dictionary
	_expect(bool(player_summary.get("in_combat", false)), "attacking troop should enter combat against enemy team", failures)
	_expect(float(enemy_summary.get("average_strength", enemy_strength_before)) < enemy_strength_before, "combat should reduce enemy soldier strength", failures)
	_expect(bool(player_summary.get("combat_scatter_active", false)), "fighting soldiers should break formation into scattered positions", failures)
	_expect(int(player_summary.get("combat_assigned_target_count", 0)) > 0, "combat should assign individual soldier targets", failures)
	_expect(_count_damaged_soldiers(enemy) > 1, "messy combat should damage more than one enemy soldier", failures)
	_expect(_count_soldiers_away_from_slots(player, 0.18) > 1, "combat should move multiple soldiers away from formation slots", failures)
	_expect(_minimum_soldier_spacing(player) > 0.42, "combat spacing should keep allied soldiers from overlapping", failures)
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
	var player_positions_after_fight := _soldier_local_positions(player)
	enemy.call("queue_free")
	await process_frame
	_step_troop_with_soldiers(player, 0.2)
	player_summary = player.call("get_troop_summary") as Dictionary
	_expect(bool(player_summary.get("combat_scatter_active", false)), "soldiers should remain scattered after combat ends", failures)
	_expect(_positions_close(player_positions_after_fight, _soldier_local_positions(player), 0.15), "ended combat should not immediately reform soldiers", failures)
	_expect(bool(player.call("set_move_destination", Vector3(16.0, 0.0, 8.0))), "manual move after combat should be accepted", failures)
	player_summary = player.call("get_troop_summary") as Dictionary
	_expect(not bool(player_summary.get("combat_scatter_active", true)), "manual movement should clear scattered combat positions and regroup", failures)
	_expect(_any_soldier_has_independent_motion(player), "manual movement after combat should make soldiers walk back by independent commands", failures)

	if is_instance_valid(enemy) and enemy.get_parent():
		root.remove_child(enemy)
		enemy.free()
	root.remove_child(player)
	player.free()


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
	_expect(int(summary.get("deserted_soldier_count", 0)) > 0, "low morale soldiers should be able to desert from the troop", failures)
	_expect(int(summary.get("active_soldier_count", 0)) < 3, "deserted soldiers should leave the active formation", failures)

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

	var started_food: bool = bool(troop.call("begin_food_collection", village, 20.0))
	_expect(started_food, "troop should start a food carrier task for visual checks", failures)
	var summary_after_start: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(int(summary_after_start.get("active_soldier_count", 0)) == 3, "collector soldiers should leave an empty slot in the troop formation", failures)
	_expect(int(summary_after_start.get("busy_carrier_soldiers", 0)) == 1, "collector soldiers should count as away while gathering", failures)

	var carrier_container := troop.get_node_or_null("CarrierTasks") as Node3D
	_expect(carrier_container != null, "carrier task visuals should be grouped under CarrierTasks", failures)
	if not carrier_container:
		root.remove_child(village)
		village.free()
		root.remove_child(troop)
		troop.free()
		return

	_expect(carrier_container.top_level, "carrier visuals should be top-level so troop movement does not drag them", failures)
	_expect(carrier_container.get_child_count() > 0, "carrier task should spawn at least one carrier visual", failures)
	if carrier_container.get_child_count() <= 0:
		root.remove_child(village)
		village.free()
		root.remove_child(troop)
		troop.free()
		return

	var carrier := carrier_container.get_child(0) as Node3D
	_expect(carrier.find_child("ResourceIcon", true, false) != null, "collecting soldiers should show a resource icon", failures)
	var before_troop_move := carrier.global_position
	troop.global_position += Vector3(20.0, 0.0, 0.0)
	_expect(
		carrier.global_position.distance_to(before_troop_move) < 0.001,
		"collecting soldiers should keep their world position when the troop moves",
		failures
	)

	troop.call("_physics_process", 0.2)
	_expect(
		carrier.global_position.distance_to(before_troop_move) > 0.01,
		"collecting soldiers should move independently toward the resource",
		failures
	)
	if carrier.has_method("is_formation_walking"):
		_expect(bool(carrier.call("is_formation_walking")), "collecting soldiers should play walking animation while moving", failures)
	var expected_yaw := -PI * 0.5
	_expect(
		absf(angle_difference(carrier.rotation.y, expected_yaw)) < 0.45,
		"collecting soldiers should face their movement direction",
		failures
	)

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
	_expect(started_food, "troop should start a village food carrier task", failures)
	_step_troop_logistics(troop, 8)
	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_food_kg", 0.0)), 45.0, 0.001), "food carrier task should add withdrawn food to troop load", failures)
	_expect(_approx(village.storage_food_kg, 55.0, 0.001), "food carrier task should withdraw from village storage", failures)

	var forest := FakeForest.new()
	forest.position = Vector3(10.0, 0.0, 0.0)
	root.add_child(forest)
	var started_wood: bool = bool(troop.call("begin_wood_collection", forest, Vector2i(0, 0), 2))
	_expect(started_wood, "troop should start a forest wood carrier task", failures)
	_step_troop_logistics(troop, 8)
	summary = troop.call("get_troop_summary") as Dictionary
	_expect(_approx(float(summary.get("carried_wood_kg", 0.0)), 40.0, 0.001), "wood carrier task should add one 20kg load per assigned soldier", failures)
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
	_expect(troop.find_child("TrolleyHint", true, false) != null, "collecting with a trolley should show a trolley model with the carriers", failures)
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
	var camp_proxy := troop.get_node_or_null("TroopCamp/CampClickProxy")
	_expect(camp_proxy != null and StringName(camp_proxy.get_meta(&"troop_selectable_type", &"")) == &"camp", "camp should expose a selectable camp proxy", failures)
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


func _step_troop_with_soldiers(troop: Node, delta: float) -> void:
	if is_instance_valid(troop):
		troop.call("_physics_process", delta)
	for soldier: Node in _get_soldier_nodes(troop):
		if is_instance_valid(soldier) and soldier.has_method("_physics_process"):
			soldier.call("_physics_process", delta)


func _approx(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _color_close(actual: Color, expected: Color, tolerance: float = 0.01) -> bool:
	return (
		absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance
		and absf(actual.a - expected.a) <= tolerance
	)


func _get_soldier_nodes(troop: Node) -> Array[Node]:
	var soldiers_container := troop.get_node_or_null("Soldiers")
	if not soldiers_container:
		return []
	return soldiers_container.get_children()


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


func _any_soldier_has_independent_motion(troop: Node) -> bool:
	for soldier: Node in _get_soldier_nodes(troop):
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			return true
	return false


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
