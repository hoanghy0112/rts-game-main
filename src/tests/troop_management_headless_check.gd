extends SceneTree

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")
const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")
const TroopSelectionControllerScript = preload("res://modules/troops/troop_selection_controller.gd")
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
	await _check_troop_route_visuals(failures)
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
	troop.call("clear_destination")
	_expect(not bool(troop.call("has_destination")), "clear destination should remove active destination", failures)
	_expect(int(troop.call("get_route_dash_count")) == 0, "clear destination should clear route dashes", failures)
	if moving_soldier and moving_soldier.has_method("is_formation_walking"):
		_expect(not bool(moving_soldier.call("is_formation_walking")), "troop soldier should stop walking animation when troop movement clears", failures)

	root.remove_child(troop)
	troop.free()


func _check_automatic_logistics_commands(failures: Array[String]) -> void:
	var controller := TroopSelectionControllerScript.new()
	root.add_child(controller)

	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 6)
	troop.set("carrier_speed_mps", 500.0)
	troop.set("carrier_work_seconds", 0.0)
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


func _approx(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
