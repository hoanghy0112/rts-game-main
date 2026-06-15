extends SceneTree

const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const MacroDetailAtlasScript = preload("res://modules/map/macro_detail_atlas.gd")
const MacroDetailOverlayScript = preload("res://modules/map/macro_detail_overlay.gd")


class FakeTerrainMaterial:
	extends RefCounted

	var world_background := 0


class FakeTerrainData:
	extends RefCounted

	var _height_maps: Texture2DArray

	func _init() -> void:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBAF)
		image.fill(Color(2.0, 0.0, 0.0, 1.0))
		_height_maps = Texture2DArray.new()
		_height_maps.create_from_images([image])

	func get_region_map() -> PackedInt32Array:
		var region_map := PackedInt32Array()
		region_map.resize(1024)
		for index: int in range(region_map.size()):
			region_map[index] = 1
		return region_map

	func get_region_locations() -> PackedVector2Array:
		var region_locations := PackedVector2Array()
		region_locations.resize(1024)
		return region_locations

	func get_height_maps_rid() -> RID:
		return _height_maps.get_rid()


class FakeTerrain:
	extends Node3D

	var vertex_spacing := 2.0
	var region_size := 8.0
	var data: FakeTerrainData
	var material: FakeTerrainMaterial

	func _init() -> void:
		data = FakeTerrainData.new()
		material = FakeTerrainMaterial.new()


func _init() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Macro detail atlas headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	var scene_root := Node3D.new()
	scene_root.name = "MacroDetailTestRoot"
	root.add_child(scene_root)

	var forest := ForestRegionScript.new() as ForestRegion
	forest.name = "Forest"
	forest.async_runtime_preview_on_ready = false
	forest.set_forest_data(
		[Vector2i(0, 0), Vector2i(1, 0)],
		{
			"0,0": [&"forest_tree_01"],
			"1,0": [&"forest_smooth_grass_01"],
		}
	)
	scene_root.add_child(forest)

	var village := VillageRegionScript.new() as VillageRegion
	village.name = "Village"
	village.async_runtime_preview_on_ready = false
	village.set_cell_arrays(
		[Vector2i(3, 0)],
		[Vector2i(5, 0)],
		[Vector2i(7, 0)]
	)
	scene_root.add_child(village)

	var atlas := MacroDetailAtlasScript.new()
	atlas.name = "Atlas"
	atlas.auto_discover_regions = false
	atlas.auto_rebuild_on_ready = false
	atlas.sample_size_meters = 2.0
	atlas.forest_region_paths = [NodePath("../Forest")]
	atlas.village_region_paths = [NodePath("../Village")]
	scene_root.add_child(atlas)
	atlas.rebuild()

	_expect(atlas.has_atlas(), "atlas should produce a texture", failures)
	_expect(atlas.get_image() != null and atlas.get_image().get_width() > 0, "atlas image should be non-empty", failures)
	_expect(_sample_alpha(atlas, Vector2(2.0, 2.0)) > 0.05, "forest tree cell should write alpha", failures)
	_expect(_sample_alpha(atlas, Vector2(14.0, 2.0)) <= 0.01, "house-only cell should not write macro overlay alpha", failures)
	var field_pixel := _sample_pixel(atlas, Vector2(22.0, 2.0))
	_expect(field_pixel.a > 0.05, "field cells should write macro overlay alpha", failures)
	_expect(_is_grass_like(field_pixel), "field cells should use the grass macro palette", failures)
	_expect(_sample_alpha(atlas, Vector2(30.0, 2.0)) <= 0.01, "road-only cell should not write macro overlay alpha", failures)

	var first_signature := _image_signature(atlas.get_image())
	atlas.rebuild()
	_expect(_image_signature(atlas.get_image()) == first_signature, "same inputs should rebuild identical atlas pixels", failures)

	var overlay := MacroDetailOverlayScript.new()
	overlay.name = "Overlay"
	overlay.atlas_path = NodePath("../Atlas")
	overlay.mesh_subdivisions = 2
	overlay.fallback_mesh_spacing = 4.0
	scene_root.add_child(overlay)
	overlay.rebuild_overlay()
	_expect(overlay.get_chunk_count() > 0, "overlay should build at least one chunk from atlas bounds", failures)
	_expect(_overlay_chunks_use_visibility_fade(overlay), "overlay chunks should use fade margins for map transition", failures)
	_expect(is_equal_approx(_overlay_chunk_first_x_spacing(overlay), 4.0), "overlay fallback mesh spacing should be dense and fixed", failures)

	var fake_terrain := FakeTerrain.new()
	fake_terrain.name = "Terrain"
	scene_root.add_child(fake_terrain)

	var terrain_overlay := MacroDetailOverlayScript.new()
	terrain_overlay.name = "TerrainOverlay"
	terrain_overlay.atlas_path = NodePath("../Atlas")
	terrain_overlay.terrain_path = NodePath("../Terrain")
	terrain_overlay.fallback_mesh_spacing = 4.0
	terrain_overlay.surface_offset = 0.17
	scene_root.add_child(terrain_overlay)
	terrain_overlay.rebuild_overlay()
	var terrain_material := _overlay_first_material(terrain_overlay)
	_expect(is_equal_approx(_overlay_chunk_first_x_spacing(terrain_overlay), 2.0), "overlay mesh spacing should follow Terrain3D vertex spacing", failures)
	_expect(terrain_material != null and bool(terrain_material.get_shader_parameter("terrain_height_enabled")), "overlay material should receive Terrain3D height uniforms", failures)
	_expect(terrain_material != null and is_equal_approx(float(terrain_material.get_shader_parameter("_vertex_spacing")), 2.0), "overlay material should receive Terrain3D vertex spacing", failures)
	_expect(terrain_material != null and is_equal_approx(float(terrain_material.get_shader_parameter("surface_offset")), 0.17), "overlay material should pass surface offset to height shader", failures)

	root.remove_child(scene_root)
	scene_root.free()


func _sample_alpha(atlas: Node, world_point: Vector2) -> float:
	return _sample_pixel(atlas, world_point).a


func _sample_pixel(atlas: Node, world_point: Vector2) -> Color:
	var image := atlas.call("get_image") as Image
	if not image:
		return Color.TRANSPARENT
	var origin := atlas.call("get_origin") as Vector2
	var sample_size := float(atlas.call("get_sample_size"))
	var x := clampi(floori((world_point.x - origin.x) / sample_size), 0, image.get_width() - 1)
	var y := clampi(floori((world_point.y - origin.y) / sample_size), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


func _is_grass_like(color: Color) -> bool:
	return color.g > color.r and color.g > color.b and color.b < 0.22


func _image_signature(image: Image) -> String:
	if not image:
		return ""
	var mixed := int(2166136261)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			mixed = _mix_hash(mixed, roundi(pixel.r * 255.0))
			mixed = _mix_hash(mixed, roundi(pixel.g * 255.0))
			mixed = _mix_hash(mixed, roundi(pixel.b * 255.0))
			mixed = _mix_hash(mixed, roundi(pixel.a * 255.0))
	return str(mixed)


func _overlay_chunks_use_visibility_fade(overlay: Node) -> bool:
	for child: Node in overlay.get_children(true):
		if not bool(child.get_meta(&"macro_detail_overlay_chunk", false)):
			continue
		if not (child is GeometryInstance3D):
			return false
		var instance := child as GeometryInstance3D
		var mesh_instance := child as MeshInstance3D
		var material := mesh_instance.material_override as ShaderMaterial if mesh_instance else null
		return (
			mesh_instance != null
			and mesh_instance.position.length() > 0.0
			and material != null
			and is_equal_approx(instance.visibility_range_begin, 0.0)
			and is_equal_approx(instance.visibility_range_begin_margin, 0.0)
			and is_equal_approx(instance.visibility_range_end, 8000.0)
			and is_equal_approx(instance.visibility_range_end_margin, 512.0)
			and is_equal_approx(float(material.get_shader_parameter("near_hide_distance")), 0.0)
			and is_equal_approx(float(material.get_shader_parameter("near_fade_distance")), 0.0)
			and instance.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		)
	return false


func _overlay_chunk_first_x_spacing(overlay: Node) -> float:
	var chunk := _overlay_first_chunk(overlay)
	if not chunk or not chunk.mesh:
		return -1.0

	var arrays := chunk.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if vertices.size() < 2:
		return -1.0
	return absf(vertices[1].x - vertices[0].x)


func _overlay_first_material(overlay: Node) -> ShaderMaterial:
	var chunk := _overlay_first_chunk(overlay)
	if not chunk:
		return null
	return chunk.material_override as ShaderMaterial


func _overlay_first_chunk(overlay: Node) -> MeshInstance3D:
	for child: Node in overlay.get_children(true):
		if bool(child.get_meta(&"macro_detail_overlay_chunk", false)) and child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _mix_hash(current: int, value: int) -> int:
	return int((current ^ value) * 16777619) & 0x7fffffff


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
