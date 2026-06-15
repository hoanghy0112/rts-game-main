extends SceneTree

const PALETTE_PATH := "res://assets/models/forest/default_forest_palette.tres"
const TERRAIN_ASSETS_PATH := "res://assets/resources/assets.tres"
const FOREST_REGION_SCRIPT := "res://addons/forest_brush/forest_region.gd"
const RUNTIME_CONTAINER_NAME := "__ForestRuntimeInstances"
const ForestRegionData = preload("res://addons/forest_brush/forest_region_data.gd")
const CATEGORY_TREE := 0
const CATEGORY_FERN := 4
const CATEGORY_GRASS := 5
const DEFAULT_TREE_LOW_POLY_DISTANCE := 450.0
const LOD_FADE_BEGIN_RATIO := 0.88
const RENDER_STRATEGY_MULTIMESH := 0
const RENDER_STRATEGY_DENSE_GRASS_PARTICLES := 1
const DENSE_GRASS_ID := "forest_smooth_grass_01"
const DENSE_FLOWER_GRASS_ID := "forest_flower_grass_01"
const DENSE_PARTICLE_PLANT_IDS := [
	DENSE_FLOWER_GRASS_ID,
	DENSE_GRASS_ID,
]
const DENSE_GRASS_SCENE := "res://assets/models/forest/grass/smooth_dense/forest_smooth_grass_01.tscn"
const DENSE_GRASS_PARTICLE_SCENE := "res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.tscn"
const DENSE_FLOWER_GRASS_SCENE := "res://assets/models/forest/plants/forest_flower_grass_01.tscn"
const DENSE_FLOWER_GRASS_PARTICLE_SCENE := "res://assets/models/forest/grass/flower_dense/forest_flower_grass_particles.tscn"
const DENSE_PARTICLE_PLANT_CONFIG := {
		DENSE_FLOWER_GRASS_ID: {
			"scene": DENSE_FLOWER_GRASS_SCENE,
			"particle_scene": DENSE_FLOWER_GRASS_PARTICLE_SCENE,
			"requires_terrain_asset": false,
			"near_visible_distance": 92.0,
			"mid_visible_distance": 240.0,
			"far_visible_distance": 440.0,
			"particle_instance_spacing": 0.4375,
			"particle_cell_width": 56.0,
			"particle_grid_width": 3,
			"particle_rows": 128,
			"particle_amount": 16384,
			"particle_count": 147456,
			"particle_process_fixed_fps": 1,
			"particle_min_draw_distance": 84.0,
		},
		DENSE_GRASS_ID: {
			"scene": DENSE_GRASS_SCENE,
			"particle_scene": DENSE_GRASS_PARTICLE_SCENE,
			"requires_terrain_asset": true,
			"near_visible_distance": 120.0,
			"mid_visible_distance": 240.0,
			"far_visible_distance": 360.0,
			"particle_instance_spacing": 0.375,
			"particle_cell_width": 64.0,
			"particle_grid_width": 3,
			"particle_rows": 170,
			"particle_amount": 28900,
			"particle_count": 260100,
			"particle_process_fixed_fps": 1,
			"particle_min_draw_distance": 96.0,
		},
	}
const DENSE_GRASS_PARTICLE_RESOURCES := [
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.gd",
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.gdshader",
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_blade.gdshader",
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_process_material.tres",
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_material.tres",
	"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.tscn",
	"res://assets/models/forest/grass/smooth_dense/forest_smooth_grass_01.tscn",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_blade.gdshader",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_clump_mesh.gd",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_clump_mesh.tres",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_process_material.tres",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_material.tres",
	"res://assets/models/forest/grass/flower_dense/forest_flower_grass_particles.tscn",
]
const EXCLUDED_FOREST_SCENES := [
	"res://assets/models/forest/plants/forest_grass_01.tscn",
	"res://assets/models/forest/plants/forest_grass_02.tscn",
]
const EXCLUDED_FOREST_IDS := [
	"forest_grass_01",
	"forest_grass_02",
]
const ADDON_RESOURCES := [
	"res://addons/forest_brush/plugin.gd",
	"res://addons/forest_brush/forest_region.gd",
	"res://addons/forest_brush/forest_region_data.gd",
	"res://addons/forest_brush/forest_region_gizmo.gd",
	"res://addons/forest_brush/forest_palette_data.gd",
	"res://addons/forest_brush/forest_plant_type_data.gd",
	"res://addons/forest_brush/dock/forest_brush_dock.gd",
	"res://addons/forest_brush/dock/forest_brush_dock.tscn",
]


func _init() -> void:
	var errors: Array[String] = []
	var palette := ResourceLoader.load(PALETTE_PATH)
	var terrain_assets := ResourceLoader.load(TERRAIN_ASSETS_PATH)

	if not palette:
		errors.append("Could not load forest palette: %s" % PALETTE_PATH)
	if not terrain_assets:
		errors.append("Could not load Terrain3D assets: %s" % TERRAIN_ASSETS_PATH)

	for resource_path: String in ADDON_RESOURCES:
		if not ResourceLoader.load(resource_path):
			errors.append("Could not load addon resource: %s" % resource_path)
	for resource_path: String in DENSE_GRASS_PARTICLE_RESOURCES:
		if not ResourceLoader.load(resource_path):
			errors.append("Could not load dense grass resource: %s" % resource_path)
	_validate_dense_grass_shaders_are_static(errors)

	if palette:
		_validate_excluded_assets_removed(palette, terrain_assets, errors)
		for plant_type: Variant in palette.get("plant_types"):
			_validate_plant_type(plant_type, terrain_assets, errors)
		_validate_dense_particle_palette_entries(palette, errors)
		_validate_region_data_storage(errors)
		_validate_region_legacy_wrappers(palette, errors)
		_validate_region_generation(palette, errors)

	if errors.is_empty():
		print("Forest asset validation passed.")
		quit(0)
	else:
		for error: String in errors:
			push_error(error)
		quit(1)


func _validate_plant_type(plant_type: Variant, terrain_assets: Resource, errors: Array[String]) -> void:
	if not plant_type:
		errors.append("Palette contains an empty plant type.")
		return

	var plant_id := StringName(plant_type.get("id"))
	var render_strategy := int(plant_type.get("render_strategy"))
	var scene := plant_type.get("scene") as PackedScene
	if not scene:
		errors.append("Plant %s has no scene." % plant_id)
		return

	_validate_scene_has_mesh_parts(scene, errors)
	_validate_terrain3d_scene_shape(scene, errors)
	_validate_scene_raw_bounds(scene, int(plant_type.get("category")), errors)

	for lod_property: String in ["lod1_scene", "lod2_scene", "billboard_scene"]:
		var lod_scene := plant_type.get(lod_property) as PackedScene
		if lod_scene:
			_validate_scene_has_mesh_parts(lod_scene, errors)

	if render_strategy == RENDER_STRATEGY_DENSE_GRASS_PARTICLES:
		_validate_dense_grass_plant_type(plant_type, terrain_assets, errors)
		return

	if int(plant_type.get("category")) == CATEGORY_TREE:
		var far_scene := plant_type.get("lod2_scene") as PackedScene
		if not far_scene:
			errors.append("Tree plant %s has no far proxy LOD scene." % plant_id)
		elif not far_scene.resource_path.contains("/proxies/"):
			errors.append("Tree plant %s far LOD is not a generated proxy: %s." % [plant_id, far_scene.resource_path])
		elif terrain_assets and _terrain_assets_has_scene(terrain_assets, far_scene.resource_path):
			errors.append("Tree far proxy %s should not be registered as a Terrain3D manual mesh asset." % far_scene.resource_path)

	if render_strategy != RENDER_STRATEGY_MULTIMESH:
		errors.append("Plant %s should default to chunked MultiMesh render strategy." % plant_id)


func _validate_dense_grass_plant_type(
	plant_type: Variant,
	terrain_assets: Resource,
	errors: Array[String]
) -> void:
	var plant_id := str(plant_type.get("id"))
	var dense_config: Dictionary = DENSE_PARTICLE_PLANT_CONFIG.get(plant_id, {})
	if dense_config.is_empty():
		errors.append("Plant %s is not an approved dense particle renderer." % plant_id)
		return

	if int(plant_type.get("category")) != CATEGORY_GRASS:
		errors.append("%s must be in the grass category." % plant_id)
	if not bool(plant_type.get("default_selected")):
		errors.append("%s must be selected by default." % plant_id)

	var scene := plant_type.get("scene") as PackedScene
	var expected_scene := str(dense_config.get("scene", ""))
	if not scene or scene.resource_path != expected_scene:
		errors.append("%s must use %s as its fallback mesh scene." % [plant_id, expected_scene])

	var particle_scene := plant_type.get("dense_particle_scene") as PackedScene
	var expected_particle_scene := str(dense_config.get("particle_scene", ""))
	if not particle_scene or particle_scene.resource_path != expected_particle_scene:
		errors.append("%s must use %s as its particle scene." % [plant_id, expected_particle_scene])
	elif not _dense_particle_scene_has_runtime_api(particle_scene):
		errors.append("%s particle scene does not expose configure_from_region()." % plant_id)
	else:
		_validate_dense_particle_scene_settings(plant_id, particle_scene, dense_config, errors)

	_validate_dense_particle_distances(plant_id, plant_type, dense_config, errors)

	if not bool(dense_config.get("requires_terrain_asset", false)):
		return
	var terrain_mesh_id := int(plant_type.get("terrain3d_mesh_id"))
	if terrain_mesh_id < 0:
		errors.append("%s must have a Terrain3D mesh id." % plant_id)
	elif terrain_assets:
		if not _terrain_assets_has_mesh_id(terrain_assets, terrain_mesh_id):
			errors.append("%s Terrain3D mesh id %d is not registered." % [plant_id, terrain_mesh_id])
		if scene and not _terrain_assets_has_scene(terrain_assets, scene.resource_path):
			errors.append("%s is not registered in %s." % [scene.resource_path, TERRAIN_ASSETS_PATH])


func _validate_dense_particle_palette_entries(
	palette: Resource,
	errors: Array[String]
) -> void:
	for plant_id: String in DENSE_PARTICLE_PLANT_IDS:
		var dense_plant := _get_plant_type_by_id(palette, plant_id)
		if not dense_plant:
			errors.append("Palette is missing %s." % plant_id)
			continue
		if int(dense_plant.get("render_strategy")) != RENDER_STRATEGY_DENSE_GRASS_PARTICLES:
			errors.append("%s must use dense grass particle render strategy." % plant_id)


func _dense_particle_scene_has_runtime_api(scene: PackedScene) -> bool:
	var instance := scene.instantiate()
	if not instance:
		return false
	var has_api := instance.has_method("configure_from_region")
	instance.free()
	return has_api


func _validate_dense_particle_distances(
	plant_id: String,
	plant_type: Variant,
	dense_config: Dictionary,
	errors: Array[String]
) -> void:
	var expected_near := float(dense_config.get("near_visible_distance", -1.0))
	var expected_mid := float(dense_config.get("mid_visible_distance", -1.0))
	var expected_far := float(dense_config.get("far_visible_distance", -1.0))
	if expected_near >= 0.0 and not is_equal_approx(float(plant_type.get("near_visible_distance")), expected_near):
		errors.append("%s near visible distance should be %.1fm." % [plant_id, expected_near])
	if expected_mid >= 0.0 and not is_equal_approx(float(plant_type.get("mid_visible_distance")), expected_mid):
		errors.append("%s mid visible distance should be %.1fm." % [plant_id, expected_mid])
	if expected_far >= 0.0 and not is_equal_approx(float(plant_type.get("far_visible_distance")), expected_far):
		errors.append("%s far visible distance should be %.1fm." % [plant_id, expected_far])


func _validate_dense_particle_scene_settings(
	plant_id: String,
	scene: PackedScene,
	dense_config: Dictionary,
	errors: Array[String]
) -> void:
	var instance := scene.instantiate()
	if not instance:
		errors.append("%s particle scene could not be instantiated for setting validation." % plant_id)
		return

	var expected_cell_width := float(dense_config.get("particle_cell_width", -1.0))
	var expected_instance_spacing := float(dense_config.get("particle_instance_spacing", -1.0))
	var expected_grid_width := int(dense_config.get("particle_grid_width", -1))
	var expected_rows := int(dense_config.get("particle_rows", -1))
	var expected_amount := int(dense_config.get("particle_amount", -1))
	var expected_particle_count := int(dense_config.get("particle_count", -1))
	var expected_process_fixed_fps := int(dense_config.get("particle_process_fixed_fps", -1))
	var expected_draw_distance := float(dense_config.get("particle_min_draw_distance", -1.0))
	if expected_instance_spacing >= 0.0 and not is_equal_approx(float(instance.get("instance_spacing")), expected_instance_spacing):
		errors.append("%s particle scene instance_spacing should be %.4fm." % [plant_id, expected_instance_spacing])
	if expected_cell_width >= 0.0 and not is_equal_approx(float(instance.get("cell_width")), expected_cell_width):
		errors.append("%s particle scene cell_width should be %.1fm." % [plant_id, expected_cell_width])
	if expected_grid_width >= 0 and int(instance.get("grid_width")) != expected_grid_width:
		errors.append("%s particle scene grid_width should be %d." % [plant_id, expected_grid_width])
	if expected_rows >= 0 and int(instance.get("rows")) != expected_rows:
		errors.append("%s particle scene rows should be %d." % [plant_id, expected_rows])
	if expected_amount >= 0 and int(instance.get("amount")) != expected_amount:
		errors.append("%s particle scene amount should be %d." % [plant_id, expected_amount])
	if expected_particle_count >= 0 and int(instance.get("particle_count")) != expected_particle_count:
		errors.append("%s particle scene particle_count should be %d." % [plant_id, expected_particle_count])
	if expected_process_fixed_fps >= 0 and int(instance.get("process_fixed_fps")) != expected_process_fixed_fps:
		errors.append("%s particle scene process_fixed_fps should be %d." % [plant_id, expected_process_fixed_fps])
	if expected_draw_distance >= 0.0 and not is_equal_approx(float(instance.get("min_draw_distance")), expected_draw_distance):
		errors.append("%s particle scene min_draw_distance should be %.1fm." % [plant_id, expected_draw_distance])

	instance.free()


func _validate_dense_grass_shaders_are_static(errors: Array[String]) -> void:
	var shader_paths := [
		"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.gdshader",
		"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_blade.gdshader",
		"res://assets/models/forest/grass/flower_dense/forest_flower_grass_blade.gdshader",
	]
	var forbidden_tokens := [
		"TIME",
		"wind_strength",
		"wind_speed",
		"wind_direction",
		"CUSTOM[2]",
		"INSTANCE_CUSTOM[2]",
		"blend_mix",
	]

	for shader_path: String in shader_paths:
		var source := FileAccess.get_file_as_string(shader_path)
		if source.is_empty():
			errors.append("Could not read dense grass shader: %s" % shader_path)
			continue
		for token: String in forbidden_tokens:
			if source.contains(token):
				errors.append("%s should not contain %s." % [shader_path, token])


func _validate_excluded_assets_removed(palette: Resource, terrain_assets: Resource, errors: Array[String]) -> void:
	var palette_ids: Array[String] = []
	for plant_type: Variant in palette.get("plant_types"):
		if plant_type:
			palette_ids.append(str(plant_type.get("id")))

	for excluded_id: String in EXCLUDED_FOREST_IDS:
		if palette_ids.has(excluded_id):
			errors.append("%s should not be available in the ForestRegion palette." % excluded_id)

	if not terrain_assets:
		return

	for excluded_scene: String in EXCLUDED_FOREST_SCENES:
		if _terrain_assets_has_scene(terrain_assets, excluded_scene):
			errors.append("%s should not be registered as a Terrain3D mesh asset." % excluded_scene)


func _validate_scene_has_mesh_parts(scene: PackedScene, errors: Array[String]) -> void:
	var instance := scene.instantiate()
	if not (instance is Node3D):
		errors.append("%s must instantiate a Node3D root." % scene.resource_path)
		if instance:
			instance.free()
		return

	var parts := _get_scene_parts(instance)
	if parts.is_empty():
		errors.append("%s exposes no Mesh parts." % scene.resource_path)

	instance.free()


func _validate_terrain3d_scene_shape(scene: PackedScene, errors: Array[String]) -> void:
	var instance := scene.instantiate()
	if not (instance is Node3D):
		if instance:
			instance.free()
		return

	var parts := _get_scene_parts(instance)
	if parts.size() != 1:
		errors.append("%s must expose exactly one combined MeshInstance3D for Terrain3D manual placement." % scene.resource_path)
		instance.free()
		return

	var mesh_instance := parts[0] as MeshInstance3D
	if not mesh_instance or not mesh_instance.mesh:
		errors.append("%s has an invalid Terrain3D mesh node." % scene.resource_path)
		instance.free()
		return

	if mesh_instance.mesh.has_method("surface_get_primitive_type"):
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			if mesh_instance.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				errors.append("%s surface %d is not triangle geometry." % [scene.resource_path, surface_index])
	elif not (mesh_instance.mesh is PrimitiveMesh):
		errors.append("%s mesh type cannot be verified as triangle geometry." % scene.resource_path)

	instance.free()


func _validate_scene_raw_bounds(scene: PackedScene, category: int, errors: Array[String]) -> void:
	var instance := scene.instantiate()
	if not (instance is Node3D):
		if instance:
			instance.free()
		return

	var limit := _max_raw_dimension_for_category(category)
	var raw_bounds := AABB()
	var has_bounds := false
	var parts := _get_scene_parts(instance)
	for part: Variant in parts:
		if not (part is MeshInstance3D):
			continue
		var mesh_instance := part as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		var mesh_bounds := mesh_instance.mesh.get_aabb()
		if not has_bounds:
			raw_bounds = mesh_bounds
			has_bounds = true
		else:
			raw_bounds = raw_bounds.merge(mesh_bounds)

	if has_bounds and maxf(raw_bounds.size.x, maxf(raw_bounds.size.y, raw_bounds.size.z)) > limit:
		errors.append("%s has raw mesh bounds larger than %.2fm after normalization: %s." % [scene.resource_path, limit, raw_bounds])

	instance.free()


func _max_raw_dimension_for_category(category: int) -> float:
	match category:
		CATEGORY_TREE:
			return 16.0
		CATEGORY_FERN:
			return 3.5
		CATEGORY_GRASS:
			return 2.5
		_:
			return 10.0


func _get_scene_parts(instance: Node) -> Array:
	if instance.has_method("get_multimesh_parts"):
		var parts: Variant = instance.call("get_multimesh_parts")
		if parts is Array:
			return parts

	var parts: Array = []
	_collect_mesh_parts(instance, parts)
	return parts


func _collect_mesh_parts(node: Node, parts: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		parts.append(node)
	for child: Node in node.get_children():
		_collect_mesh_parts(child, parts)


func _terrain_assets_has_scene(terrain_assets: Resource, scene_path: String) -> bool:
	if terrain_assets.has_method("get_mesh_count") and terrain_assets.has_method("get_mesh_asset"):
		for index: int in range(int(terrain_assets.call("get_mesh_count"))):
			var mesh_asset: Variant = terrain_assets.call("get_mesh_asset", index)
			if mesh_asset and _mesh_asset_scene_path(mesh_asset) == scene_path:
				return true
		return false

	var mesh_list: Variant = terrain_assets.get("mesh_list")
	if mesh_list is Array:
		for mesh_asset: Variant in mesh_list:
			if mesh_asset and _mesh_asset_scene_path(mesh_asset) == scene_path:
				return true

	return false


func _terrain_assets_has_mesh_id(terrain_assets: Resource, mesh_id: int) -> bool:
	if terrain_assets.has_method("get_mesh_count") and terrain_assets.has_method("get_mesh_asset"):
		for index: int in range(int(terrain_assets.call("get_mesh_count"))):
			var mesh_asset: Variant = terrain_assets.call("get_mesh_asset", index)
			if mesh_asset is Object and int((mesh_asset as Object).get("id")) == mesh_id:
				return true
		return false

	var mesh_list: Variant = terrain_assets.get("mesh_list")
	if mesh_list is Array:
		for mesh_asset: Variant in mesh_list:
			if mesh_asset is Object and int((mesh_asset as Object).get("id")) == mesh_id:
				return true

	return false


func _mesh_asset_scene_path(mesh_asset: Variant) -> String:
	var scene: Variant = null
	if mesh_asset is Object:
		scene = (mesh_asset as Object).get("scene_file")
	if scene is PackedScene:
		return (scene as PackedScene).resource_path
	return ""


func _get_plant_type_by_id(palette: Resource, plant_id: String) -> Variant:
	for plant_type: Variant in palette.get("plant_types"):
		if plant_type and str(plant_type.get("id")) == plant_id:
			return plant_type
	return null


func _validate_region_data_storage(errors: Array[String]) -> void:
	var cells: Array[Vector2i] = [
		Vector2i(-5, -1),
		Vector2i(-4, -1),
		Vector2i(-3, -1),
		Vector2i(-2, -1),
		Vector2i(-1, -1),
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(3, 0),
		Vector2i(4, 0),
		Vector2i(4, 1),
	]
	var plant_map := {
		"-5,-1": [&"tree_a"],
		"-4,-1": [&"tree_a"],
		"-3,-1": [&"grass_a", &"tree_a"],
		"-2,-1": [&"grass_a", &"tree_a"],
		"0,0": [&"tree_a"],
		"1,0": [&"tree_a"],
		"3,0": [&"tree_a"],
		"4,0": [&"grass_a"],
		"4,1": [&"tree_a", &"grass_a"],
	}

	var data := ForestRegionData.new()
	data.encode_from_cells(cells, plant_map, 4)
	var normalized_cells := ForestRegionData.normalize_cells(cells)
	var normalized_map := ForestRegionData.normalize_cell_plant_ids(plant_map, normalized_cells)
	if data.to_cells() != normalized_cells:
		errors.append("ForestRegionData did not round-trip painted cells.")
	if not _cell_plant_maps_equal(data.to_cell_plant_ids(), normalized_map):
		errors.append("ForestRegionData did not round-trip per-cell plant IDs.")
	if not data.has_cell(Vector2i(-5, -1)):
		errors.append("ForestRegionData lost a negative cell.")
	if data.get_cell_plant_ids(Vector2i(-3, -1)) != [&"grass_a", &"tree_a"]:
		errors.append("ForestRegionData changed mixed plant set ordering.")

	var reversed_cells := ForestRegionData.copy_cells(cells)
	reversed_cells.reverse()
	var reordered_map := {
		"4,1": [&"tree_a", &"grass_a"],
		"4,0": [&"grass_a"],
		"3,0": [&"tree_a"],
		"1,0": [&"tree_a"],
		"0,0": [&"tree_a"],
		"-2,-1": [&"grass_a", &"tree_a"],
		"-3,-1": [&"grass_a", &"tree_a"],
		"-4,-1": [&"tree_a"],
		"-5,-1": [&"tree_a"],
	}
	var deterministic_data := ForestRegionData.new()
	deterministic_data.encode_from_cells(reversed_cells, reordered_map, 4)
	if deterministic_data.row_runs != data.row_runs or not _plant_sets_equal(deterministic_data.plant_sets, data.plant_sets):
		errors.append("ForestRegionData encoding is not deterministic.")

	var erase_result := data.erase_cells([Vector2i(-5, -1), Vector2i(4, 1)])
	if not bool(erase_result.get("changed", false)):
		errors.append("ForestRegionData erase patch reported no change.")
	if data.has_cell(Vector2i(-5, -1)) or data.has_cell(Vector2i(4, 1)):
		errors.append("ForestRegionData erase patch did not remove cells.")
	var repaint_result := data.paint_cells([Vector2i(-5, -1), Vector2i(4, 1)], [&"flower_a"])
	var repaint_chunks := repaint_result.get("changed_chunks", [])
	if not (repaint_chunks is Array and (repaint_chunks as Array).size() == 2):
		errors.append("ForestRegionData repaint across chunk boundary did not report both dirty chunks.")
	if data.get_cell_plant_ids(Vector2i(-5, -1)) != [&"flower_a"]:
		errors.append("ForestRegionData repaint did not store new plant IDs.")

	_validate_region_data_storage_size(errors)


func _validate_region_data_storage_size(errors: Array[String]) -> void:
	var synthetic_cells: Array[Vector2i] = []
	var synthetic_map: Dictionary = {}
	for x: int in range(-64, 64):
		for y: int in range(-32, 32):
			var cell := Vector2i(x, y)
			synthetic_cells.append(cell)
			synthetic_map[ForestRegionData.cell_key(cell)] = [&"tree_a"] if y % 2 == 0 else [&"tree_a", &"grass_a"]

	var compact_bytes := ForestRegionData.compact_storage_bytes_for(synthetic_cells, synthetic_map, 8)
	var legacy_bytes := ForestRegionData.legacy_storage_bytes_for(synthetic_cells, synthetic_map)
	if compact_bytes >= legacy_bytes:
		errors.append("ForestRegionData compact encoding is not smaller than legacy arrays: compact=%d legacy=%d." % [compact_bytes, legacy_bytes])


func _validate_region_legacy_wrappers(palette: Resource, errors: Array[String]) -> void:
	var region_script := ResourceLoader.load(FOREST_REGION_SCRIPT) as Script
	if not region_script:
		errors.append("Could not load ForestRegion script for legacy wrapper test.")
		return

	var region := region_script.new() as Node3D
	if not region:
		errors.append("Could not instantiate ForestRegion for legacy wrapper test.")
		return

	var cells: Array[Vector2i] = [Vector2i(-9, -1), Vector2i(-8, -1), Vector2i(0, 0), Vector2i(8, 0)]
	var plant_map := {
		"-9,-1": [&"legacy_tree"],
		"-8,-1": [&"legacy_tree"],
		"0,0": [&"legacy_grass", &"legacy_tree"],
		"8,0": [&"legacy_tree"],
	}
	region.set("palette", palette)
	region.set("cell_plant_ids", plant_map)
	region.set("forest_cells", cells)

	var actual_cells: Array[Vector2i] = []
	var raw_cells: Variant = region.get("forest_cells")
	if raw_cells is Array:
		for cell_variant: Variant in raw_cells:
			if cell_variant is Vector2i:
				actual_cells.append(cell_variant as Vector2i)

	var normalized_cells := ForestRegionData.normalize_cells(cells)
	var normalized_map := ForestRegionData.normalize_cell_plant_ids(plant_map, normalized_cells)
	if actual_cells != normalized_cells:
		errors.append("ForestRegion legacy forest_cells wrapper did not normalize into region_data.")
	if not _cell_plant_maps_equal(region.get("cell_plant_ids"), normalized_map):
		errors.append("ForestRegion legacy cell_plant_ids wrapper did not survive reverse load order.")

	var data: Variant = region.get("region_data")
	if not data or int(data.get_cell_count()) != normalized_cells.size():
		errors.append("ForestRegion legacy wrappers did not populate compact region_data.")

	region.free()


func _validate_region_generation(palette: Resource, errors: Array[String]) -> void:
	var region_script := ResourceLoader.load(FOREST_REGION_SCRIPT) as Script
	if not region_script:
		errors.append("Could not load ForestRegion script.")
		return

	var region := region_script.new() as Node3D
	if not region:
		errors.append("Could not instantiate ForestRegion.")
		return

	var tree_ids := _get_plant_ids_by_categories(palette, [CATEGORY_TREE])
	var grass_ids := _get_plant_ids_by_categories(palette, [CATEGORY_FERN, CATEGORY_GRASS])
	var expected_dense_ids := _get_expected_dense_particle_ids()
	if tree_ids.is_empty():
		errors.append("Palette has no tree plant IDs for tree-only smoke test.")
		return
	if grass_ids.is_empty():
		errors.append("Palette has no grass or fern plant IDs for grass-only smoke test.")
		return
	for dense_plant_id: StringName in expected_dense_ids:
		if not _palette_has_plant_id(palette, dense_plant_id):
			errors.append("Palette has no %s plant ID for dense grass smoke test." % dense_plant_id)
			return

	var mixed_ids: Array[StringName] = [tree_ids[0]]
	for dense_plant_id: StringName in expected_dense_ids:
		mixed_ids.append(dense_plant_id)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(7, 0)]
	var cell_plant_map := {
		"0,0": [tree_ids[0]],
		"1,0": [expected_dense_ids[0]],
		"2,0": [expected_dense_ids[1]],
		"7,0": mixed_ids,
	}
	for x: int in range(3, 7):
		var cell := Vector2i(x, 0)
		cells.append(cell)
		cell_plant_map[ForestRegionData.cell_key(cell)] = [tree_ids[0]]
	for x: int in range(8, 16):
		var cell := Vector2i(x, 0)
		cells.append(cell)
		cell_plant_map[ForestRegionData.cell_key(cell)] = [tree_ids[0]]

	root.add_child(region)
	region.set("palette", palette)
	region.set("density_multiplier", 8.0)
	region.call("set_forest_data", cells, cell_plant_map)
	region.call("rebuild_runtime_preview")

	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		errors.append("ForestRegion did not create %s." % RUNTIME_CONTAINER_NAME)
	elif container.get_child_count(true) == 0:
		errors.append("ForestRegion created an empty runtime container.")
	else:
		_validate_runtime_container(container, errors)
		_validate_tree_low_poly_distance(region, tree_ids[0], errors)
		_validate_dirty_chunk_runtime_rebuild(region, tree_ids[0], errors)

	root.remove_child(region)
	region.free()


func _get_plant_ids_by_categories(palette: Resource, categories: Array[int]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for plant_type: Variant in palette.get("plant_types"):
		if plant_type and categories.has(int(plant_type.get("category"))):
			ids.append(StringName(plant_type.get("id")))
	return ids


func _palette_has_plant_id(palette: Resource, plant_id: StringName) -> bool:
	for plant_type: Variant in palette.get("plant_types"):
		if plant_type and StringName(plant_type.get("id")) == plant_id:
			return true
	return false


func _get_expected_dense_particle_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for plant_id: String in DENSE_PARTICLE_PLANT_IDS:
		ids.append(StringName(plant_id))
	return ids


func _validate_runtime_container(container: Node, errors: Array[String]) -> void:
	var multimesh_count := 0
	var dense_layer_count := 0
	var dense_particle_emitters := 0
	var dense_layer_ids: Dictionary = {}
	var chunk_keys: Dictionary = {}
	for child: Node in container.get_children(true):
		if bool(child.get_meta("forest_dense_grass_layer", false)):
			dense_layer_count += 1
			var dense_plant_id := StringName(child.get_meta("forest_plant_id", &""))
			dense_layer_ids[dense_plant_id] = true
			if not DENSE_PARTICLE_PLANT_IDS.has(str(dense_plant_id)):
				errors.append("%s has invalid dense grass plant metadata." % child.name)
			dense_particle_emitters += _validate_dense_particle_emitters(child, errors)
		if child is MultiMeshInstance3D:
			var instance := child as MultiMeshInstance3D
			if not instance.multimesh:
				errors.append("%s has no MultiMesh resource." % instance.name)
			elif instance.multimesh.instance_count <= 0:
				errors.append("%s has no MultiMesh instances." % instance.name)
			elif instance.multimesh.custom_aabb.size.length_squared() <= 0.0:
				errors.append("%s has no MultiMesh custom AABB." % instance.name)
			if instance.custom_aabb.size.length_squared() <= 0.0:
				errors.append("%s has no GeometryInstance custom AABB." % instance.name)
			var chunk_key := str(instance.get_meta("forest_chunk_key", ""))
			if chunk_key.is_empty():
				errors.append("%s has no forest chunk metadata." % instance.name)
			else:
				chunk_keys[chunk_key] = true
			multimesh_count += 1
	if multimesh_count == 0:
		errors.append("ForestRegion runtime output is not chunked MultiMeshInstance3D.")
	elif chunk_keys.size() < 2:
		errors.append("ForestRegion runtime output did not split instances across chunks.")
	if dense_layer_count != DENSE_PARTICLE_PLANT_IDS.size():
		errors.append("ForestRegion should create %d dense grass particle layers." % DENSE_PARTICLE_PLANT_IDS.size())
	for expected_dense_id: StringName in _get_expected_dense_particle_ids():
		if not dense_layer_ids.has(expected_dense_id):
			errors.append("ForestRegion did not create dense grass particle layer for %s." % expected_dense_id)
	if dense_particle_emitters == 0:
		errors.append("ForestRegion dense grass layer created no GPUParticles3D emitters.")
	elif dense_particle_emitters > DENSE_PARTICLE_PLANT_IDS.size() * 64:
		errors.append("ForestRegion dense grass output is too node-heavy: %d emitters." % dense_particle_emitters)


func _validate_tree_low_poly_distance(region: Node3D, tree_id: StringName, errors: Array[String]) -> void:
	if not is_equal_approx(float(region.get("tree_low_poly_distance")), DEFAULT_TREE_LOW_POLY_DISTANCE):
		errors.append("ForestRegion tree_low_poly_distance should default to %.1fm." % DEFAULT_TREE_LOW_POLY_DISTANCE)

	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return

	var tree_lod1_found := false
	var tree_lod2_found := false
	var expected_lod2_begin := DEFAULT_TREE_LOW_POLY_DISTANCE * LOD_FADE_BEGIN_RATIO
	for child: Node in container.get_children(true):
		if not (child is GeometryInstance3D):
			continue

		var instance := child as GeometryInstance3D
		var instance_name := str(instance.name)
		if instance_name.begins_with("%s_L1_" % str(tree_id)):
			tree_lod1_found = true
			if not is_equal_approx(instance.visibility_range_end, DEFAULT_TREE_LOW_POLY_DISTANCE):
				errors.append("%s should keep full tree LOD visible to %.1fm." % [instance.name, DEFAULT_TREE_LOW_POLY_DISTANCE])
		elif instance_name.begins_with("%s_L2_" % str(tree_id)):
			tree_lod2_found = true
			if not is_equal_approx(instance.visibility_range_begin, expected_lod2_begin):
				errors.append("%s low-poly LOD should begin at %.1fm." % [instance.name, expected_lod2_begin])

	if not tree_lod1_found:
		errors.append("ForestRegion did not create a full-detail tree LOD using tree_low_poly_distance.")
	if not tree_lod2_found:
		errors.append("ForestRegion did not create a low-poly tree LOD using tree_low_poly_distance.")


func _validate_dense_particle_emitters(node: Node, errors: Array[String]) -> int:
	var emitter_count := 0
	for child: Node in node.get_children(true):
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			if particles.amount <= 0:
				errors.append("%s has no particle amount." % particles.name)
			if particles.fixed_fps != 1:
				errors.append("%s fixed_fps should be 1 for static balanced dense grass." % particles.name)
			if not particles.process_material:
				errors.append("%s has no particle process material." % particles.name)
			if not particles.draw_pass_1:
				errors.append("%s has no particle mesh draw pass." % particles.name)
			elif particles.draw_pass_1.get_surface_count() <= 0:
				errors.append("%s particle mesh draw pass has no surfaces." % particles.name)
			emitter_count += 1
		emitter_count += _validate_dense_particle_emitters(child, errors)
	return emitter_count


func _validate_dirty_chunk_runtime_rebuild(region: Node3D, tree_id: StringName, errors: Array[String]) -> void:
	var container := region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		return

	var before_nodes := _get_runtime_instances_by_chunk(container)
	var dirty_cells: Array[Vector2i] = [Vector2i(8, 1)]
	var dirty_plant_ids: Array[StringName] = [tree_id]
	var paint_result := bool(region.call("paint_cells", dirty_cells, dirty_plant_ids, 0))
	if not paint_result:
		errors.append("ForestRegion dirty chunk smoke edit did not change data.")
		return
	if not region.is_inside_tree():
		var dirty_chunks: Array[Vector2i] = [Vector2i(1, 0)]
		region.call("rebuild_runtime_chunks", dirty_chunks)

	container = region.get_node_or_null(RUNTIME_CONTAINER_NAME)
	if not container:
		errors.append("ForestRegion lost runtime container after dirty chunk edit.")
		return

	var untouched_replaced := _has_invalid_node(before_nodes.get("0,0", []))
	var touched_replaced := _has_invalid_node(before_nodes.get("1,0", []))
	var after_nodes := _get_runtime_instances_by_chunk(container)
	if untouched_replaced:
		errors.append("ForestRegion dirty rebuild replaced an untouched chunk.")
	if not touched_replaced:
		errors.append("ForestRegion dirty rebuild did not free touched chunk instances.")
	if not after_nodes.has("1,0") or (after_nodes["1,0"] as Array).is_empty():
		errors.append("ForestRegion dirty rebuild did not recreate touched chunk instances.")


func _get_runtime_instances_by_chunk(container: Node) -> Dictionary:
	var nodes_by_chunk: Dictionary = {}
	for child: Node in container.get_children(true):
		if not (child is MultiMeshInstance3D):
			continue
		var chunk_key := str(child.get_meta("forest_chunk_key", ""))
		if chunk_key.is_empty():
			continue
		var nodes: Array[Node] = []
		if nodes_by_chunk.has(chunk_key):
			nodes = nodes_by_chunk[chunk_key]
		nodes.append(child)
		nodes_by_chunk[chunk_key] = nodes
	return nodes_by_chunk


func _has_invalid_node(value: Variant) -> bool:
	if not (value is Array):
		return false
	for node_variant: Variant in value:
		if not is_instance_valid(node_variant):
			return true
	return false


func _plant_sets_equal(a: Array[PackedStringArray], b: Array[PackedStringArray]) -> bool:
	if a.size() != b.size():
		return false
	for index: int in range(a.size()):
		if a[index] != b[index]:
			return false
	return true


func _cell_plant_maps_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a.keys():
		if not b.has(key):
			return false
		if ForestRegionData.normalize_plant_ids(a[key]) != ForestRegionData.normalize_plant_ids(b[key]):
			return false
	return true
