extends SceneTree

const VillageBalanceConfigScript = preload("res://modules/village/village_balance_config.gd")
const DefaultVillageBalance: Resource = preload("res://modules/village/default_village_balance.tres")
const VillageCellData = preload("res://addons/village_brush/village_cell_data.gd")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const PeasantScene: PackedScene = preload("res://modules/units/peasant/peasant.tscn")
const VillageInfoDrawerScene: PackedScene = preload("res://modules/village/village_info_drawer.tscn")
const VillageSelectionControllerScript = preload("res://modules/village/village_selection_controller.gd")
const GameTimeSystemScene: PackedScene = preload("res://modules/time/game_time_system.tscn")
const GameDateDisplayScene: PackedScene = preload("res://modules/time/game_date_display.tscn")
const RUNTIME_CONTAINER_NAME := "__VillageRuntimeInstances"
const SELECTABLE_TYPE_META := &"village_selectable_type"


func _init() -> void:
	_run_deferred_checks.call_deferred()


func _run_deferred_checks() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Village food headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_check_balance_defaults(failures)
	_check_food_records_and_daily_math(failures)
	_check_time_system_advances_food(failures)
	_check_ui_and_controller_load(failures)
	_check_scene_wiring("res://modules/draft/draft.tscn", failures)
	_check_scene_wiring("res://maps/midlands/midlands.tscn", failures)


func _check_balance_defaults(failures: Array[String]) -> void:
	var config := DefaultVillageBalance
	_expect(config.get_script() == VillageBalanceConfigScript, "default village balance should use VillageBalanceConfig script", failures)
	_expect(is_equal_approx(float(config.get("rice_kg_per_square_meter_per_year")), 0.1), "rice production default should be 0.1 kg/m2/year", failures)
	_expect(is_equal_approx(float(config.get("daily_rice_kg_per_farmer")), 1.0), "daily farmer rice consumption default should be 1.0 kg", failures)
	_expect(int(config.get("house_min_villagers")) == 3, "house min villagers default should be 3", failures)
	_expect(int(config.get("house_max_villagers")) == 4, "house max villagers default should be 4", failures)
	_expect(is_equal_approx(float(config.get("default_food_reserve_kg_per_house")), 30.0), "default house reserve should be 30 kg", failures)
	_expect(int(config.get("food_days_per_year")) == 360, "food simulation year should stay at 360 days", failures)
	_expect(int(config.get("residential_house_max_count")) == 32, "residential max house default should be 32", failures)
	_expect(is_equal_approx(float(config.get("residential_house_density")), 2.0), "residential density default should be 2.0", failures)

	var region := VillageRegionScript.new() as VillageRegion
	_expect(region.get("balance_config") == DefaultVillageBalance, "VillageRegion should use the default balance config", failures)
	_expect(region.house_max_count == int(config.get("residential_house_max_count")), "VillageRegion house max default should match balance config", failures)
	_expect(is_equal_approx(region.house_density, float(config.get("residential_house_density"))), "VillageRegion house density default should match balance config", failures)
	region.free()


func _check_food_records_and_daily_math(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var region := _make_region(4, 24680)
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var records := region.get_house_food_records()
	var summary := region.get_village_food_summary()
	_expect(not records.is_empty(), "runtime rebuild should create house food records", failures)
	_expect(int(summary.get("house_count", 0)) == records.size(), "summary house count should match records", failures)
	_expect(int(summary.get("farmer_count", 0)) == 4, "summary farmer count should use live spawned peasants", failures)
	_expect(is_equal_approx(float(summary.get("daily_consumption_kg", -1.0)), 4.0), "daily consumption should be live peasants times 1 kg", failures)
	_expect(_summary_has_required_keys(summary), "village summary should expose required food keys", failures)

	var first_record := records[0]
	var first_id: StringName = first_record.get("id", &"")
	var fetched_record := region.get_house_food_record(first_id)
	_expect(not fetched_record.is_empty(), "house food record should be fetchable by stable id", failures)
	_expect(StringName(fetched_record.get("id", &"")) == first_id, "fetched house record should preserve id", failures)

	var resident_signature := _resident_signature(records)
	var matching_region := _make_region(4, 24680)
	scene_root.add_child(matching_region)
	matching_region.rebuild_runtime_preview()
	_expect(_resident_signature(matching_region.get_house_food_records()) == resident_signature, "same seed should create deterministic house residents", failures)
	_expect(_all_residents_in_range(records, 3, 4), "house records should contain 3-4 deterministic residents", failures)

	var expected_area := _sum_macro_field_area(region)
	_expect(_approx(float(summary.get("field_area_m2", 0.0)), expected_area, 0.01), "field area should come from generated plot area", failures)
	var expected_production := expected_area * float(DefaultVillageBalance.get("rice_kg_per_square_meter_per_year")) / float(DefaultVillageBalance.get("food_days_per_year"))
	_expect(_approx(float(summary.get("daily_production_kg", -1.0)), expected_production, 0.001), "daily production should be area times annual rice yield divided by food days", failures)

	var before_reserve := float(summary.get("total_reserve_kg", 0.0))
	var before_storage := float(summary.get("storage_food_kg", 0.0))
	var withdrawn := region.withdraw_food_kg(15.0)
	var after_withdraw_summary := region.get_village_food_summary()
	_expect(_approx(withdrawn, 15.0, 0.001), "village storage should withdraw requested food when available", failures)
	_expect(_approx(float(after_withdraw_summary.get("storage_food_kg", 0.0)), before_storage - 15.0, 0.001), "storage withdrawal should reduce central food storage", failures)
	var deposited := region.deposit_food_kg(5.0)
	summary = region.get_village_food_summary()
	_expect(_approx(deposited, 5.0, 0.001), "village storage should accept deposited food", failures)
	_expect(_approx(float(summary.get("storage_food_kg", 0.0)), before_storage - 10.0, 0.001), "storage deposit should update central food storage", failures)
	before_reserve = float(summary.get("total_reserve_kg", 0.0))
	region.advance_food_days(1)
	var after_summary := region.get_village_food_summary()
	var expected_after_reserve := before_reserve + expected_production - float(summary.get("daily_consumption_kg", 0.0))
	_expect(_approx(float(after_summary.get("total_reserve_kg", 0.0)), expected_after_reserve, 0.001), "advance_food_days should add production then deduct consumption", failures)
	_expect(int(after_summary.get("food_days_elapsed", 0)) == 1, "food day counter should advance", failures)
	_expect(_approx(float(after_summary.get("shortage_kg", -1.0)), 0.0, 0.001), "well-stocked village should not report shortage after one day", failures)
	_expect(_has_selectable_metadata(region), "generated village should expose troop-style flag selection while houses stay non-clickable", failures)
	_expect(_has_no_village_selection_ring(region), "generated village should not draw a selection ring around houses", failures)
	_expect(_village_flag_faces_camera_without_resizing(region, scene_root), "village flag should face the camera without resizing while camera zoom changes", failures)
	_expect(_has_centered_storage_hut(region), "generated village should place a scaled hut storage at the house-region center", failures)
	_expect(_houses_clear_centered_storage(region), "generated houses should not overlap the central village storage", failures)

	matching_region.clear_runtime_instances()
	scene_root.remove_child(matching_region)
	matching_region.free()
	region.clear_runtime_instances()
	scene_root.remove_child(region)
	region.free()
	root.remove_child(scene_root)
	scene_root.free()


func _check_time_system_advances_food(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var time_system := GameTimeSystemScene.instantiate()
	time_system.name = "GameTimeSystem"
	time_system.set("auto_advance", false)
	scene_root.add_child(time_system)

	var region := _make_region(4, 13579)
	region.time_system_path = NodePath("../GameTimeSystem")
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var before_summary := region.get_village_food_summary()
	time_system.call("advance_days", 2)
	var after_summary := region.get_village_food_summary()
	_expect(int(after_summary.get("food_days_elapsed", 0)) == int(before_summary.get("food_days_elapsed", 0)) + 2, "GameTimeSystem day changes should advance village food days", failures)
	_expect(int(after_summary.get("day_of_month", 0)) == 3, "food summary should carry current date fields from GameTimeSystem", failures)

	region.clear_runtime_instances()
	scene_root.remove_child(region)
	region.free()
	scene_root.remove_child(time_system)
	time_system.free()
	root.remove_child(scene_root)
	scene_root.free()


func _check_ui_and_controller_load(failures: Array[String]) -> void:
	var drawer := VillageInfoDrawerScene.instantiate()
	_expect(drawer != null and drawer.has_method("show_village_summary"), "VillageInfoDrawer scene should expose summary API", failures)
	if drawer:
		drawer.free()

	var date_display := GameDateDisplayScene.instantiate()
	_expect(date_display != null and date_display.has_method("bind_to_time_system"), "GameDateDisplay scene should expose time binding API", failures)
	if date_display:
		date_display.free()

	var time_system := GameTimeSystemScene.instantiate()
	_expect(time_system != null and time_system.has_method("advance_days"), "GameTimeSystem scene should expose day advancement API", failures)
	if time_system:
		time_system.free()

	var controller := VillageSelectionControllerScript.new()
	_expect(controller != null and controller.has_method("_pick_selectable"), "VillageSelectionController script should instantiate", failures)
	controller.free()


func _check_scene_wiring(scene_path: String, failures: Array[String]) -> void:
	var packed_scene := load(scene_path)
	if not (packed_scene is PackedScene):
		failures.append("%s should load as a PackedScene" % scene_path)
		return

	var scene := (packed_scene as PackedScene).instantiate()
	if not scene:
		failures.append("%s should instantiate" % scene_path)
		return

	var region := scene.get_node_or_null("VillageRegion")
	var drawer := scene.get_node_or_null("VillageInfoDrawer")
	var controller := scene.get_node_or_null("VillageSelectionController")
	var time_system := scene.get_node_or_null("GameTimeSystem")
	var date_display := scene.get_node_or_null("GameDateDisplay")
	_expect(region is VillageRegion, "%s should contain VillageRegion" % scene_path, failures)
	_expect(drawer != null and drawer.has_method("show_village_summary"), "%s should contain VillageInfoDrawer" % scene_path, failures)
	_expect(controller != null and controller.has_method("_pick_selectable"), "%s should contain VillageSelectionController" % scene_path, failures)
	_expect(time_system != null and time_system.has_method("get_current_snapshot"), "%s should contain GameTimeSystem" % scene_path, failures)
	_expect(date_display != null and date_display.has_method("bind_to_time_system"), "%s should contain GameDateDisplay" % scene_path, failures)
	if region:
		_expect(region.get("time_system_path") == NodePath("../GameTimeSystem"), "%s VillageRegion should point at GameTimeSystem" % scene_path, failures)
	if drawer:
		_expect(drawer.get("village_region_path") == NodePath("../VillageRegion"), "%s drawer should point at VillageRegion" % scene_path, failures)
	if date_display:
		_expect(date_display.get("time_system_path") == NodePath("../GameTimeSystem"), "%s date display should point at GameTimeSystem" % scene_path, failures)
	if controller:
		_expect(controller.get("village_region_path") == NodePath("../VillageRegion"), "%s controller should point at VillageRegion" % scene_path, failures)
		_expect(controller.get("info_drawer_path") == NodePath("../VillageInfoDrawer"), "%s controller should point at VillageInfoDrawer" % scene_path, failures)
		_expect(controller.get("camera_path") == NodePath("../RTSCameraRig/Camera3D"), "%s controller should point at the RTS camera" % scene_path, failures)
	scene.free()


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
	region.set_cell_arrays(
		_make_rect_cells(0, 7, 0, 7),
		_make_rect_cells(9, 20, 0, 11),
		_make_rect_cells(0, 7, -1, -1)
	)
	return region


func _summary_has_required_keys(summary: Dictionary) -> bool:
	for key: String in [
		"house_count",
		"farmer_count",
		"total_reserve_kg",
		"daily_production_kg",
		"daily_consumption_kg",
		"daily_net_kg",
		"field_area_m2",
		"food_days_remaining",
		"storage_food_kg",
		"storage_world_position",
	]:
		if not summary.has(key):
			return false
	return true


func _sum_macro_field_area(region: VillageRegion) -> float:
	var macro_data := region.get_macro_detail_data()
	var field_generation := macro_data.get("field_generation", {}) as Dictionary
	var plots: Array = field_generation.get("plots", [])
	var total := 0.0
	for plot_variant: Variant in plots:
		if plot_variant is FieldPlotData:
			total += maxf((plot_variant as FieldPlotData).area, 0.0)
	return total


func _resident_signature(records: Array[Dictionary]) -> PackedInt32Array:
	var signature := PackedInt32Array()
	for record: Dictionary in records:
		signature.append(int(record.get("resident_count", 0)))
	return signature


func _all_residents_in_range(records: Array[Dictionary], min_count: int, max_count: int) -> bool:
	for record: Dictionary in records:
		var residents := int(record.get("resident_count", 0))
		if residents < min_count or residents > max_count:
			return false
	return true


func _has_selectable_metadata(region: VillageRegion) -> bool:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return false

	var flag := container.get_node_or_null("VillageFlag")
	if not flag or StringName(flag.get_meta(SELECTABLE_TYPE_META, &"")) != &"flag":
		return false
	if not _has_collision_proxy_with_type(flag, &"flag"):
		return false
	if not (flag is Node3D):
		return false

	var expected_center := _runtime_house_center(container)
	var flag_spatial := flag as Node3D
	var actual_center := Vector2(flag_spatial.global_position.x, flag_spatial.global_position.z)
	if actual_center.distance_to(expected_center) > 0.05:
		return false

	var pole := flag.get_node_or_null("Pole") as MeshInstance3D
	if not pole or not (pole.mesh is CylinderMesh):
		return false
	var pole_mesh := pole.mesh as CylinderMesh
	if pole_mesh.height < 11.0 or pole_mesh.top_radius < 0.17:
		return false

	var banner := flag.get_node_or_null("Banner") as MeshInstance3D
	if not banner or not (banner.mesh is BoxMesh):
		return false
	var banner_mesh := banner.mesh as BoxMesh
	if banner_mesh.size.x < 5.0 or banner_mesh.size.y < 2.9:
		return false

	var stripe := flag.get_node_or_null("AccentStripe") as MeshInstance3D
	if not stripe or not (stripe.mesh is BoxMesh):
		return false

	var banner_material := banner.material_override as StandardMaterial3D
	if (
		not banner_material
		or banner_material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
		or banner_material.cull_mode != BaseMaterial3D.CULL_DISABLED
	):
		return false

	var houses := _collect_named_children(container, "House_")
	if houses.is_empty():
		return false

	for house: Node3D in houses:
		if house.has_meta(SELECTABLE_TYPE_META):
			return false
		if _has_collision_proxy_with_type(house, &"house"):
			return false
		if _has_named_descendant(house, "VillageHouseClickProxy"):
			return false
		if _has_named_descendant(house, "VillageFlagClickProxy"):
			return false
	return true


func _has_no_village_selection_ring(region: VillageRegion) -> bool:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return false
	if container.get_node_or_null("VillageSelectionRing") != null:
		return false
	for child: Node in _collect_descendants(container):
		if String(child.name).begins_with("VillageRingClickProxy_") or String(child.name) == "VillageCenterClickProxy":
			return false
	return true


func _village_flag_faces_camera_without_resizing(region: VillageRegion, scene_root: Node3D) -> bool:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return false

	var icon := container.get_node_or_null("VillageFlag") as Node3D
	if not icon:
		return false

	var camera := Camera3D.new()
	scene_root.add_child(camera)
	camera.owner = null
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 64.0
	camera.global_position = icon.global_position + Vector3(32.0, 80.0, 40.0)
	camera.look_at(icon.global_position, Vector3.UP)
	camera.current = true

	region._update_village_selection_icon_camera_lock()
	var first_scale := icon.scale.x
	var first_rotation_y := icon.rotation.y

	camera.size = 128.0
	region._update_village_selection_icon_camera_lock()
	var second_scale := icon.scale.x
	var second_rotation_y := icon.rotation.y

	scene_root.remove_child(camera)
	camera.free()

	return (
		_approx(first_scale, 1.0, 0.001)
		and _approx(second_scale, first_scale, 0.001)
		and _approx(second_rotation_y, first_rotation_y, 0.001)
	)


func _has_centered_storage_hut(region: VillageRegion) -> bool:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return false

	var storage := container.get_node_or_null("VillageStorage") as Node3D
	if not storage:
		return false

	var expected_center := _runtime_house_center(container)
	var actual_center := Vector2(storage.global_position.x, storage.global_position.z)
	if actual_center.distance_to(expected_center) > 0.05:
		return false

	var storage_hut := storage.get_node_or_null("StorageHut") as Node3D
	return storage_hut != null and storage_hut.scale.x >= 2.0


func _houses_clear_centered_storage(region: VillageRegion) -> bool:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return false

	var storage := container.get_node_or_null("VillageStorage") as Node3D
	if not storage:
		return false

	var houses := _collect_named_children(container, "House_")
	if houses.is_empty():
		return false

	var storage_center := Vector2(storage.global_position.x, storage.global_position.z)
	var minimum_distance := maxf(region.cell_size * 1.25, 5.0)
	for house: Node3D in houses:
		var house_center := Vector2(house.global_position.x, house.global_position.z)
		if house_center.distance_to(storage_center) < minimum_distance:
			return false
	return true


func _runtime_house_center(container: Node) -> Vector2:
	var houses := _collect_named_children(container, "House_")
	if houses.is_empty():
		return Vector2.ZERO
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for house: Node3D in houses:
		var position := Vector2(house.global_position.x, house.global_position.z)
		min_point.x = minf(min_point.x, position.x)
		min_point.y = minf(min_point.y, position.y)
		max_point.x = maxf(max_point.x, position.x)
		max_point.y = maxf(max_point.y, position.y)
	return min_point.lerp(max_point, 0.5)


func _has_collision_proxy_with_type(root_node: Node, expected_type: StringName) -> bool:
	if root_node is CollisionObject3D and StringName(root_node.get_meta(SELECTABLE_TYPE_META, &"")) == expected_type:
		return true
	for child: Node in root_node.get_children():
		if _has_collision_proxy_with_type(child, expected_type):
			return true
	return false


func _has_collision_shape(root_node: Node) -> bool:
	if root_node is CollisionShape3D and (root_node as CollisionShape3D).shape:
		return true
	for child: Node in root_node.get_children():
		if _has_collision_shape(child):
			return true
	return false


func _has_named_descendant(root_node: Node, node_name: String) -> bool:
	if String(root_node.name) == node_name:
		return true
	for child: Node in root_node.get_children():
		if _has_named_descendant(child, node_name):
			return true
	return false


func _collect_descendants(root_node: Node) -> Array[Node]:
	var collected: Array[Node] = []
	for child: Node in root_node.get_children():
		collected.append(child)
		collected.append_array(_collect_descendants(child))
	return collected


func _collect_named_children(root_node: Node, prefix: String) -> Array[Node3D]:
	var collected: Array[Node3D] = []
	for child: Node in root_node.get_children():
		if child is Node3D and String(child.name).begins_with(prefix):
			collected.append(child as Node3D)
		collected.append_array(_collect_named_children(child, prefix))
	return collected


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


func _approx(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
