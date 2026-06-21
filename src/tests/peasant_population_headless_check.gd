extends SceneTree

const VillageCellData = preload("res://addons/village_brush/village_cell_data.gd")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const HumanScene: PackedScene = preload("res://modules/units/human/human.tscn")
const PeasantScene: PackedScene = preload("res://modules/units/peasant/peasant.tscn")


func _init() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Peasant population headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_check_default_peasant_scene_loads(failures)
	_check_humans_face_move_direction(failures)
	_check_peasant_house_patrol_fallback(failures)
	_check_peasant_stalled_move_recovers(failures)
	_check_runtime_data_exports_peasant_settings(failures)
	_check_initial_population_matches_target(failures)
	_check_seeded_population_is_deterministic(failures)
	_check_dead_peasant_refills_by_spawn_rate(failures)


func _check_default_peasant_scene_loads(failures: Array[String]) -> void:
	var peasant := PeasantScene.instantiate()
	_expect(peasant is CharacterBody3D, "Peasant scene should instantiate a CharacterBody3D root", failures)
	_expect(peasant.has_method("apply_damage"), "Peasant scene should expose health damage API", failures)
	_expect(peasant.has_method("use_tool"), "Peasant scene should expose tool action API", failures)
	_expect(peasant.has_method("attack_target"), "Peasant scene should keep legacy timed action wrapper API", failures)
	peasant.free()


func _check_humans_face_move_direction(failures: Array[String]) -> void:
	var human := HumanScene.instantiate() as CharacterBody3D
	human.rotation.y = 0.0
	human.call("_face_direction", Vector3(0.0, 0.0, -1.0), 1.0)
	_expect(absf(angle_difference(human.rotation.y, 0.0)) <= 0.001, "human moving toward -Z should face forward", failures)

	human.rotation.y = 0.0
	human.call("_face_direction", Vector3(0.0, 0.0, 1.0), 1.0)
	_expect(absf(angle_difference(human.rotation.y, PI)) <= 0.001, "human moving toward +Z should turn around instead of walking backward", failures)
	human.free()


func _check_peasant_house_patrol_fallback(failures: Array[String]) -> void:
	var peasant := PeasantScene.instantiate() as CharacterBody3D
	peasant.position = Vector3.ZERO
	peasant.set("field_task_chance", 0.0)
	peasant.set("tool_practice_chance", 0.0)
	peasant.set("target_jitter_radius", 0.0)
	peasant.set("min_roam_target_distance", 2.0)
	peasant.set("house_patrol_radius", 6.0)
	peasant.call(
		"configure_village_context",
		null,
		null,
		{
			"house_world_points": [Vector3.ZERO],
			"road_world_points": [],
			"field_world_points": [],
			"roam_radius": 0.0,
		},
		2468
	)
	peasant.call("_choose_next_behavior")

	_expect(peasant.call("has_active_move_target"), "peasant should pick a fallback patrol target when only its house anchor is available", failures)
	var offset := (peasant.call("get_move_target") as Vector3) - peasant.position
	offset.y = 0.0
	_expect(offset.length() >= 2.0, "fallback patrol target should not be inside the immediate house stop radius", failures)
	peasant.free()


func _check_peasant_stalled_move_recovers(failures: Array[String]) -> void:
	var peasant := PeasantScene.instantiate() as CharacterBody3D
	peasant.set("behavior_enabled", false)
	peasant.set("move_stall_seconds", 0.2)
	peasant.set("move_stall_min_progress", 0.01)
	var stalled_callable := Callable(peasant, "_on_move_target_stalled")
	if peasant.has_signal("move_target_stalled") and not peasant.is_connected("move_target_stalled", stalled_callable):
		peasant.connect("move_target_stalled", stalled_callable)
	peasant.call("set_move_target", Vector3(10.0, 0.0, 0.0), false)

	for _step: int in range(8):
		peasant.call("_update_move_progress", 10.0, 0.05)

	_expect(not bool(peasant.call("has_active_move_target")), "stalled peasant should clear a blocked roaming target instead of staying stuck", failures)
	peasant.free()


func _check_runtime_data_exports_peasant_settings(failures: Array[String]) -> void:
	var region := _make_region(5, 12345)
	var data := region.to_runtime_data()
	_expect(data.get("peasant_scene") != null, "runtime data should include peasant_scene", failures)
	_expect(int(data.get("peasant_target_count", -1)) == 5, "runtime data should include peasant target count", failures)
	_expect(is_equal_approx(float(data.get("peasant_spawn_rate_per_minute", -1.0)), 120.0), "runtime data should include peasant spawn rate", failures)
	_expect(is_equal_approx(float(data.get("peasant_death_rate_per_minute", -1.0)), 0.0), "runtime data should include peasant death rate", failures)
	region.free()


func _check_initial_population_matches_target(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var region := _make_region(5, 9876)
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var peasants := _collect_named_children(region, "Peasant_")
	_expect(peasants.size() == 5, "runtime rebuild should spawn exact peasant target count", failures)
	_expect(_all_peasants_alive(peasants), "initial peasants should be alive", failures)
	_expect(_all_peasants_near_houses(region, peasants), "initial peasants should spawn near generated houses", failures)

	region.clear_runtime_instances()
	root.remove_child(scene_root)
	scene_root.free()


func _check_seeded_population_is_deterministic(failures: Array[String]) -> void:
	var first_positions := _spawn_positions_for_seed(24680)
	var second_positions := _spawn_positions_for_seed(24680)
	var different_positions := _spawn_positions_for_seed(24681)

	_expect(first_positions == second_positions, "same generation seed should produce identical peasant spawn positions", failures)
	_expect(first_positions != different_positions, "different generation seed should change peasant spawn positions", failures)


func _check_dead_peasant_refills_by_spawn_rate(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var region := _make_region(3, 13579)
	region.peasant_spawn_rate_per_minute = 60.0
	region.peasant_death_cleanup_seconds = 0.0
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var peasants := _collect_named_children(region, "Peasant_")
	_expect(peasants.size() == 3, "refill test should start with target peasant count", failures)
	if not peasants.is_empty():
		peasants[0].call("apply_damage", 999.0, &"test_damage")

	_expect(int(region.call("_get_alive_peasant_count")) == 2, "dead peasant should leave an alive population vacancy", failures)
	region.call("_update_runtime_peasant_population", 60.0)
	_expect(int(region.call("_get_alive_peasant_count")) == 3, "spawn rate should refill dead peasant vacancy", failures)

	region.clear_runtime_instances()
	root.remove_child(scene_root)
	scene_root.free()


func _spawn_positions_for_seed(seed: int) -> Array[Vector3]:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var region := _make_region(4, seed)
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var positions: Array[Vector3] = []
	for peasant: Node3D in _collect_named_children(region, "Peasant_"):
		positions.append(_rounded_position(peasant.position))

	region.clear_runtime_instances()
	root.remove_child(scene_root)
	scene_root.free()
	return positions


func _make_region(target_count: int, seed: int) -> VillageRegion:
	var region := VillageRegionScript.new() as VillageRegion
	region.name = "VillageRegion"
	region.async_runtime_preview_on_ready = false
	region.auto_apply_terrain_textures = false
	region.house_scene = _make_test_house_scene()
	region.peasant_scene = PeasantScene
	region.peasant_target_count = target_count
	region.peasant_spawn_rate_per_minute = 120.0
	region.peasant_death_rate_per_minute = 0.0
	region.peasant_house_spawn_radius = 2.0
	region.peasant_roam_radius = 16.0
	region.house_max_count = 4
	region.house_density = 1.0
	region.house_min_spacing = 0.0
	region.house_size_spacing_multiplier = 1.0
	region.house_footprint_padding = 0.0
	region.house_region_margin = 0.0
	region.house_road_clearance = 0.0
	region.generation_seed = seed
	region.set_cell_arrays(_make_rect_cells(0, 7, 0, 7), _make_rect_cells(8, 10, 0, 3), _make_rect_cells(0, 7, -1, -1))
	return region


func _collect_named_children(region: VillageRegion, prefix: String) -> Array[Node3D]:
	var collected: Array[Node3D] = []
	var container := region.get_node_or_null("__VillageRuntimeInstances")
	if not container:
		return collected

	for child: Node in container.get_children():
		if child is Node3D and child.name.begins_with(prefix):
			collected.append(child as Node3D)
	return collected


func _all_peasants_alive(peasants: Array[Node3D]) -> bool:
	for peasant: Node3D in peasants:
		if not peasant.has_method("is_alive") or not bool(peasant.call("is_alive")):
			return false
	return true


func _all_peasants_near_houses(region: VillageRegion, peasants: Array[Node3D]) -> bool:
	var houses := _collect_named_children(region, "House_")
	if houses.is_empty():
		return false

	var max_distance := region.peasant_house_spawn_radius + 0.25
	var max_distance_squared := max_distance * max_distance
	for peasant: Node3D in peasants:
		var near_house := false
		for house: Node3D in houses:
			var offset := peasant.position - house.position
			offset.y = 0.0
			if offset.length_squared() <= max_distance_squared:
				near_house = true
				break
		if not near_house:
			return false
	return true


func _rounded_position(position: Vector3) -> Vector3:
	return Vector3(
		snappedf(position.x, 0.001),
		snappedf(position.y, 0.001),
		snappedf(position.z, 0.001)
	)


func _make_rect_cells(min_x: int, max_x: int, min_y: int, max_y: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(min_x, max_x + 1):
		for y: int in range(min_y, max_y + 1):
			cells.append(Vector2i(x, y))
	return VillageCellData.normalize_cells(cells)


func _make_test_house_scene() -> PackedScene:
	var root_node := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	mesh_instance.mesh = box
	root_node.add_child(mesh_instance)
	mesh_instance.owner = root_node

	var scene := PackedScene.new()
	var error := scene.pack(root_node)
	root_node.free()
	return scene if error == OK else null


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
