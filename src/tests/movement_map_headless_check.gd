extends SceneTree

const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const MovementMapGeneratorScript = preload("res://modules/map/movement_map_generator.gd")
const MovementMapOverlayScript = preload("res://modules/map/movement_map_overlay.gd")

const SAVE_PATH := "res://.godot/movement_map_headless_check.res"


class FakeTerrainData:
	extends RefCounted

	func get_region_locations() -> Array:
		return [Vector2i(0, 0)]

	func get_region_count() -> int:
		return 1

	func get_height(world_position: Vector3) -> float:
		if world_position.x < 0.0 or world_position.z < 0.0 or world_position.x >= 64.0 or world_position.z >= 64.0:
			return 1.0e30
		if world_position.x >= 48.0:
			return (world_position.x - 48.0) * 4.0
		return 0.0


class FakeTerrain:
	extends Node3D

	var data := FakeTerrainData.new()

	func get_region_size() -> int:
		return 64

	func get_vertex_spacing() -> float:
		return 1.0


class FakeWaterSystem:
	extends Node3D

	var _map: ImageTexture

	func _init() -> void:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		image.set_pixel(1, 1, Color(0.0, 0.0, 0.0, 1.0))
		_map = ImageTexture.create_from_image(image)

	func get_system_map() -> ImageTexture:
		return _map

	func get_system_map_coordinates() -> Transform3D:
		return Transform3D(Vector3.ZERO, Vector3(64.0, 1.0, 64.0), Vector3(64.0, 1.0, 64.0), Vector3.ZERO)


func _init() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Movement map headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	scene_root.name = "MovementMapTestRoot"
	root.add_child(scene_root)

	var terrain := FakeTerrain.new()
	terrain.name = "Terrain"
	scene_root.add_child(terrain)

	var water := FakeWaterSystem.new()
	water.name = "WaterSystem"
	scene_root.add_child(water)

	var forest := ForestRegionScript.new() as ForestRegion
	forest.name = "Forest"
	forest.async_runtime_preview_on_ready = false
	forest.cell_size = 8.0
	forest.set_forest_data([Vector2i(3, 1)], {"3,1": [&"forest_tree_01"]})
	scene_root.add_child(forest)

	var village := VillageRegionScript.new() as VillageRegion
	village.name = "Village"
	village.async_runtime_preview_on_ready = false
	village.auto_apply_terrain_textures = false
	village.cell_size = 8.0
	village.road_width = 4.0
	village.set_cell_arrays([], [], [Vector2i(1, 1), Vector2i(4, 1), Vector2i(6, 1)])
	scene_root.add_child(village)

	var generator = MovementMapGeneratorScript.new()
	generator.name = "Generator"
	generator.terrain_path = NodePath("../Terrain")
	generator.water_system_path = NodePath("../WaterSystem")
	var forest_paths: Array[NodePath] = [NodePath("../Forest")]
	var village_paths: Array[NodePath] = [NodePath("../Village")]
	generator.forest_region_paths = forest_paths
	generator.village_region_paths = village_paths
	generator.auto_discover_regions = false
	generator.movement_map_path = SAVE_PATH
	generator.sample_size_meters = 1.0
	generator.max_grid_size = 64
	generator.max_generated_cells = 64
	generator.max_walkable_slope_degrees = 35.0
	scene_root.add_child(generator)

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	var generate_button_variant: Variant = generator.get("generate_now_button")
	_expect(generate_button_variant is Callable, "generate_now_button should expose the inspector button callable", failures)
	if generate_button_variant is Callable:
		var generate_button := generate_button_variant as Callable
		_expect(generate_button.is_valid(), "generate_now_button inspector button callable should be valid", failures)
		if generate_button.is_valid():
			generate_button.call()

	_expect(ResourceLoader.exists(SAVE_PATH), "generate_now button should save movement data", failures)
	_expect(generator.get("generate_now") is bool, "legacy generate_now should remain bool-compatible", failures)
	_expect(not generator.last_generation_summary.is_empty(), "generate_now button should update the generation summary", failures)

	var data = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	_expect(data != null, "saved movement data should reload", failures)
	if not data:
		root.remove_child(scene_root)
		scene_root.free()
		return

	_expect(data.width == 8 and data.height == 8, "saved dimensions should match generated grid", failures)
	_expect(is_equal_approx(data.origin.x, 0.0) and is_equal_approx(data.origin.y, 0.0), "saved origin should match terrain bounds", failures)
	_expect(is_equal_approx(data.cell_size_meters, 8.0), "saved cell size should match effective sample size", failures)

	var water_cell = data.world_to_cell(Vector2(12.0, 12.0))
	var forest_cell = data.world_to_cell(Vector2(28.0, 12.0))
	var road_cell = data.world_to_cell(Vector2(36.0, 12.0))
	var steep_road_cell = data.world_to_cell(Vector2(52.0, 12.0))
	var normal_cell = data.world_to_cell(Vector2(36.0, 36.0))

	_expect(data.is_walkable_cell(water_cell), "shallow water cells should be walkable", failures)
	_expect(data.get_speed_multiplier_cell(water_cell) < data.get_speed_multiplier_cell(forest_cell), "shallow water cells should be slower than forest terrain", failures)
	_expect((data.get_flags_cell(water_cell) & MovementMapDataScript.FLAG_RIVER) != 0, "water cells should carry the river flag", failures)
	_expect((data.get_flags_cell(water_cell) & MovementMapDataScript.FLAG_ROAD) != 0, "road over water should retain the road flag", failures)
	_expect(data.get_speed_multiplier_cell(water_cell) < data.get_speed_multiplier_cell(road_cell), "road over shallow water should not receive the road speed boost", failures)

	_expect(not data.is_walkable_cell(steep_road_cell), "excessive slope cells should be blocked", failures)
	_expect((data.get_flags_cell(steep_road_cell) & MovementMapDataScript.FLAG_STEEP_SLOPE) != 0, "steep cells should carry the steep slope flag", failures)
	_expect((data.get_flags_cell(steep_road_cell) & MovementMapDataScript.FLAG_ROAD) != 0, "road over slope should retain the road flag", failures)

	_expect(data.is_walkable_cell(forest_cell), "forest cells should remain walkable", failures)
	_expect(data.get_speed_multiplier_cell(forest_cell) < data.get_speed_multiplier_cell(normal_cell), "forest cells should be slower than normal terrain", failures)
	_expect((data.get_flags_cell(forest_cell) & MovementMapDataScript.FLAG_FOREST) != 0, "forest cells should carry the forest flag", failures)

	_expect(data.is_walkable_cell(road_cell), "road cells should be walkable when terrain permits", failures)
	_expect(data.get_speed_multiplier_cell(road_cell) > 1.0, "road cells should boost speed", failures)
	_expect((data.get_flags_cell(road_cell) & MovementMapDataScript.FLAG_ROAD) != 0, "road cells should carry the road flag", failures)

	_expect(data.cell_to_world_center(road_cell).distance_to(Vector2(36.0, 12.0)) <= 0.001, "cell center query should round-trip road cell center", failures)

	var overlay = MovementMapOverlayScript.new()
	overlay.name = "Overlay"
	overlay.movement_map = data
	overlay.chunk_size_meters = 32.0
	overlay.fallback_mesh_spacing = 8.0
	scene_root.add_child(overlay)
	overlay.rebuild_overlay()
	_expect(overlay.get_chunk_count() > 0, "overlay should create chunks from movement data", failures)
	_expect(_overlay_chunks_visible(overlay) == false, "overlay chunks should start hidden", failures)
	overlay.show_movement_map = true
	_expect(_overlay_chunks_visible(overlay) == true, "show_movement_map should show chunks", failures)
	overlay.show_movement_map = false
	_expect(_overlay_chunks_visible(overlay) == false, "show_movement_map should hide chunks", failures)
	overlay.overlay_visible = true
	_expect(_overlay_chunks_visible(overlay) == true, "overlay_visible alias should show chunks", failures)

	root.remove_child(scene_root)
	scene_root.free()


func _overlay_chunks_visible(overlay: Node) -> bool:
	var found := false
	for child: Node in overlay.get_children(true):
		if bool(child.get_meta(&"movement_map_overlay_chunk", false)):
			found = true
			if not child.visible:
				return false
	return found


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
