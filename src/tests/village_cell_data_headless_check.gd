extends SceneTree

const VillageCellData = preload("res://addons/village_brush/village_cell_data.gd")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")


class FakeTerrainRegion:
	extends Resource


class FakeTerrainAssets:
	extends RefCounted

	func get_texture_count() -> int:
		return 6


class FakeTerrainData:
	extends RefCounted

	var original_region := FakeTerrainRegion.new()
	var copied_region := FakeTerrainRegion.new()
	var active_regions: Array = []
	var base_id_calls := 0
	var overlay_ids: Dictionary = {}
	var updated_map_types: Dictionary = {}

	func _init() -> void:
		active_regions = [original_region]

	func get_regionp(_world_position: Vector3) -> Object:
		return original_region

	func get_regions_active(copy_regions: bool = false, include_deleted: bool = false) -> Array:
		if copy_regions and include_deleted:
			return [copied_region]
		return [original_region]

	func remove_region(region: Variant, _update_maps: bool = false) -> void:
		active_regions.erase(region)

	func add_region(region: Variant, _update_maps: bool = false) -> int:
		if not active_regions.has(region):
			active_regions.append(region)
		return OK

	func get_height(_world_position: Vector3) -> float:
		return 0.0

	func get_control(_world_position: Vector3) -> int:
		return 0

	func set_control(_world_position: Vector3, _control: int) -> void:
		pass

	func set_control_base_id(_world_position: Vector3, _texture_id: int) -> void:
		base_id_calls += 1

	func set_control_overlay_id(_world_position: Vector3, texture_id: int) -> void:
		overlay_ids[texture_id] = true

	func set_control_blend(_world_position: Vector3, _blend: float) -> void:
		pass

	func set_control_auto(_world_position: Vector3, _enabled: bool) -> void:
		pass

	func get_texture_id(_world_position: Vector3) -> Vector3:
		return Vector3(1.0, 0.0, 0.0)

	func update_maps(map_type: int, _update_a: bool, _update_b: bool) -> void:
		updated_map_types[map_type] = true


class FakeTerrain:
	extends Node3D

	var data := FakeTerrainData.new()
	var assets := FakeTerrainAssets.new()


func _init() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Village cell data headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_check_dense_rectangle_round_trip(failures)
	_check_sparse_negative_round_trip(failures)
	_check_empty_layers(failures)
	_check_region_set_cell_arrays_with_cell_data(failures)
	_check_village_region_defaults(failures)
	_check_village_brush_dock_house_density_control(failures)
	_check_house_density_controls_placement_count(failures)
	_check_auto_texture_without_height_edits(failures)
	_check_migrated_scene("res://modules/draft/draft.tscn", failures)
	_check_migrated_scene("res://modules/map/map_rig.tscn", failures)
	_expect(ResourceLoader.load("res://addons/village_brush/plugin.gd") != null, "village brush plugin script should load", failures)
	_expect(ResourceLoader.load("res://addons/village_brush/village_region_gizmo.gd") != null, "village region gizmo script should load", failures)


func _check_dense_rectangle_round_trip(failures: Array[String]) -> void:
	var data := VillageCellData.new()
	var cells := _make_rect_cells(-4, 5, -3, 2)
	var empty_cells: Array[Vector2i] = []
	data.encode_from_cells(cells, empty_cells, empty_cells)

	_expect_cells_equal(data.to_house_cells(), cells, "dense rectangle house cells should round-trip", failures)
	_expect(data.house_runs.size() == 18, "dense rectangle should encode as one run per row", failures)


func _check_sparse_negative_round_trip(failures: Array[String]) -> void:
	var data := VillageCellData.new()
	var house_cells: Array[Vector2i] = [
		Vector2i(-5, -2),
		Vector2i(-4, -2),
		Vector2i(-2, -2),
		Vector2i(1, 0),
		Vector2i(3, 0),
		Vector2i(4, 0),
		Vector2i(-1, 5),
	]
	var field_cells: Array[Vector2i] = [
		Vector2i(-3, 1),
		Vector2i(-2, 1),
		Vector2i(0, 1),
		Vector2i(2, 4),
	]
	var road_cells: Array[Vector2i] = [
		Vector2i(-7, -4),
		Vector2i(-7, -3),
		Vector2i(2, -3),
		Vector2i(3, -3),
		Vector2i(5, 8),
	]
	data.encode_from_cells(house_cells, field_cells, road_cells)

	_expect_cells_equal(data.to_house_cells(), house_cells, "sparse house cells should round-trip", failures)
	_expect_cells_equal(data.to_field_cells(), field_cells, "sparse field cells should round-trip", failures)
	_expect_cells_equal(data.to_road_cells(), road_cells, "sparse road cells should round-trip", failures)


func _check_empty_layers(failures: Array[String]) -> void:
	var data := VillageCellData.new()
	var empty_cells: Array[Vector2i] = []
	data.encode_from_cells(empty_cells, empty_cells, empty_cells)
	_expect(data.is_empty(), "empty layers should remain empty", failures)
	_expect(data.to_house_cells().is_empty(), "empty house layer should decode empty", failures)
	_expect(data.to_field_cells().is_empty(), "empty field layer should decode empty", failures)
	_expect(data.to_road_cells().is_empty(), "empty road layer should decode empty", failures)


func _check_region_set_cell_arrays_with_cell_data(failures: Array[String]) -> void:
	var house_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2)]
	var field_cells: Array[Vector2i] = [Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1)]
	var road_cells: Array[Vector2i] = [Vector2i(3, -1), Vector2i(3, 0)]

	var legacy_region := VillageRegionScript.new() as VillageRegion
	legacy_region.set_cell_arrays(house_cells, field_cells, road_cells)
	var legacy_data := legacy_region.to_runtime_data()

	var compact_data := VillageCellData.new()
	var region := VillageRegionScript.new() as VillageRegion
	region.cell_data = compact_data
	region.set_cell_arrays(house_cells, field_cells, road_cells)
	var runtime_data := region.to_runtime_data()

	_expect(region.house_cells.is_empty(), "region with cell_data should keep inline house cells empty", failures)
	_expect(region.field_cells.is_empty(), "region with cell_data should keep inline field cells empty", failures)
	_expect(region.road_cells.is_empty(), "region with cell_data should keep inline road cells empty", failures)
	_expect_cells_equal(
		_variant_to_cells(runtime_data.get("house_cells", [])),
		_variant_to_cells(legacy_data.get("house_cells", [])),
		"cell_data runtime house cells should match legacy",
		failures
	)
	_expect_cells_equal(
		_variant_to_cells(runtime_data.get("field_cells", [])),
		_variant_to_cells(legacy_data.get("field_cells", [])),
		"cell_data runtime field cells should match legacy",
		failures
	)
	_expect_cells_equal(
		_variant_to_cells(runtime_data.get("road_cells", [])),
		_variant_to_cells(legacy_data.get("road_cells", [])),
		"cell_data runtime road cells should match legacy",
		failures
	)

	legacy_region.free()
	region.free()


func _check_village_region_defaults(failures: Array[String]) -> void:
	var region := VillageRegionScript.new() as VillageRegion
	if not region:
		failures.append("VillageRegion should instantiate for default checks")
		return

	_expect(int(region.get("road_texture_id")) == 2, "VillageRegion road texture default should be Rocky Sand Road id 2", failures)
	_expect(int(region.get("house_sand_texture_id")) == 2, "VillageRegion house clearing texture default should be Rocky Sand Road id 2", failures)
	_expect(is_equal_approx(float(region.get("house_min_spacing")), 3.0), "VillageRegion house min spacing default should be denser", failures)
	_expect(is_equal_approx(float(region.get("house_size_spacing_multiplier")), 1.05), "VillageRegion house size spacing multiplier default should be denser", failures)
	_expect(int(region.get("house_max_count")) == 32, "VillageRegion house max count default should match village balance", failures)
	_expect(is_equal_approx(float(region.get("house_density")), 2.0), "VillageRegion house density default should match village balance", failures)
	_expect(bool(region.get("auto_apply_terrain_textures")), "VillageRegion should auto-apply terrain textures by default", failures)
	_expect(not bool(region.get("auto_apply_field_road_textures")), "VillageRegion should not auto-paint the expensive field-road texture mask by default", failures)
	region.free()


func _check_village_brush_dock_house_density_control(failures: Array[String]) -> void:
	var dock_source := FileAccess.get_file_as_string("res://addons/village_brush/dock/village_brush_dock.gd")
	var plugin_source := FileAccess.get_file_as_string("res://addons/village_brush/plugin.gd")
	_expect(dock_source.contains("signal house_density_changed"), "Village Brush dock should expose a house density changed signal", failures)
	_expect(dock_source.contains("House Density"), "Village Brush dock should show a House Density control", failures)
	_expect(dock_source.contains("_house_density_spinbox.value = _region.house_density"), "Village Brush dock should sync the selected region house density", failures)
	_expect(dock_source.contains("house_density_changed.emit(value)"), "Village Brush dock should emit house density edits", failures)
	_expect(plugin_source.contains("_dock.house_density_changed.connect(_on_dock_house_density_changed)"), "Village Brush plugin should listen for house density edits", failures)
	_expect(plugin_source.contains('undo.add_do_property(_region, "house_density", clamped_density)'), "Village Brush plugin should apply dock density to VillageRegion.house_density", failures)


func _check_house_density_controls_placement_count(failures: Array[String]) -> void:
	var low_density_count := _count_generated_houses_for_density(1.0)
	var high_density_count := _count_generated_houses_for_density(2.0)
	_expect(low_density_count > 0, "house density test should generate baseline houses", failures)
	_expect(high_density_count > low_density_count, "higher house_density should generate more houses", failures)


func _count_generated_houses_for_density(density: float) -> int:
	var region := VillageRegionScript.new() as VillageRegion
	region.house_scene = _make_test_house_scene()
	region.cell_size = 4.0
	region.house_max_count = 8
	region.house_density = density
	region.house_min_spacing = 0.0
	region.house_size_spacing_multiplier = 1.0
	region.house_footprint_padding = 0.0
	region.house_region_margin = 0.0
	region.house_road_clearance = 0.0
	region.set_cell_arrays(_make_rect_cells(0, 11, 0, 11), [], [])

	var rng := RandomNumberGenerator.new()
	rng.seed = 24680
	var placements: Array = region.call("_build_house_placements", [], rng)
	var count := placements.size()
	region.free()
	return count


func _check_auto_texture_without_height_edits(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var terrain := FakeTerrain.new()
	terrain.name = "Terrain"
	scene_root.add_child(terrain)

	var region := VillageRegionScript.new() as VillageRegion
	region.name = "VillageRegion"
	region.async_runtime_preview_on_ready = false
	region.apply_runtime_terrain_edits = false
	region.auto_apply_terrain_textures = true
	region.terrain_path = NodePath("../Terrain")
	region.house_scene = _make_test_house_scene()
	region.house_max_count = 2
	region.house_density = 1.0
	region.house_min_spacing = 0.0
	region.house_size_spacing_multiplier = 1.0
	region.house_footprint_padding = 0.0
	region.house_region_margin = 0.0
	region.house_road_clearance = 0.0
	region.set_cell_arrays(
		_make_rect_cells(0, 5, 0, 5),
		[],
		[Vector2i(-5, -5), Vector2i(-4, -5)]
	)
	scene_root.add_child(region)
	region.rebuild_runtime_preview()

	var terrain_data := terrain.data
	_expect(terrain_data.base_id_calls > 0, "auto terrain texture path should write Terrain3D control values", failures)
	_expect(terrain_data.overlay_ids.has(2), "auto terrain texture path should paint road/house texture id 2", failures)
	_expect(not terrain_data.updated_map_types.has(Terrain3DRegion.TYPE_HEIGHT), "texture-only auto path should not update Terrain3D height maps", failures)
	_expect(not bool(region.get("_runtime_field_terrain_shape_applied")), "texture-only auto path should not shape fields", failures)

	region.clear_runtime_instances()
	scene_root.remove_child(region)
	region.free()
	root.remove_child(scene_root)
	scene_root.free()


func _check_migrated_scene(scene_path: String, failures: Array[String]) -> void:
	var packed_scene := load(scene_path)
	if not (packed_scene is PackedScene):
		failures.append("%s should load as a PackedScene" % scene_path)
		return

	var scene := (packed_scene as PackedScene).instantiate()
	if not scene:
		failures.append("%s should instantiate" % scene_path)
		return

	var region := scene.get_node_or_null("VillageRegion") as VillageRegion
	if not region:
		failures.append("%s should contain VillageRegion" % scene_path)
		scene.free()
		return

	_expect(region.cell_data != null, "%s VillageRegion should use external cell_data" % scene_path, failures)
	_expect(region.house_cells.is_empty(), "%s should not keep inline house cells" % scene_path, failures)
	_expect(region.field_cells.is_empty(), "%s should not keep inline field cells" % scene_path, failures)
	_expect(region.road_cells.is_empty(), "%s should not keep inline road cells" % scene_path, failures)
	_expect(int(region.get("road_texture_id")) == 2, "%s road texture should be Rocky Sand Road id 2" % scene_path, failures)
	_expect(int(region.get("house_sand_texture_id")) == 2, "%s house clearing texture should be Rocky Sand Road id 2" % scene_path, failures)
	_expect(int(region.get("house_max_count")) == 32, "%s should override house max count to 32" % scene_path, failures)
	_expect(is_equal_approx(float(region.get("house_density")), 2.0), "%s should use village balance house density" % scene_path, failures)
	_expect(bool(region.get("auto_apply_terrain_textures")), "%s should auto-apply road and house terrain textures" % scene_path, failures)
	_expect(not bool(region.get("auto_apply_field_road_textures")), "%s should not auto-paint field-road texture masks by default" % scene_path, failures)
	_expect(region.get_house_cells().size() == 351, "%s should decode migrated house cells" % scene_path, failures)
	_expect(region.get_field_cells().size() == 1746, "%s should decode migrated field cells" % scene_path, failures)
	_expect(region.get_road_cells().size() == 155, "%s should decode migrated road cells" % scene_path, failures)
	scene.free()


func _make_rect_cells(min_x: int, max_x: int, min_y: int, max_y: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(min_x, max_x + 1):
		for y: int in range(min_y, max_y + 1):
			cells.append(Vector2i(x, y))
	return VillageCellData.normalize_cells(cells)


func _expect_cells_equal(
	actual: Array[Vector2i],
	expected: Array[Vector2i],
	message: String,
	failures: Array[String]
) -> void:
	var normalized_expected := VillageCellData.normalize_cells(expected)
	if actual != normalized_expected:
		failures.append("%s: expected %s, got %s" % [message, str(normalized_expected), str(actual)])


func _variant_to_cells(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells

	for cell_variant: Variant in value:
		if cell_variant is Vector2i:
			var cell: Vector2i = cell_variant
			cells.append(cell)
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
