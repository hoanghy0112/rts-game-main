extends Node3D

const OVERLAY_SHADER: Shader = preload("res://modules/map/macro_detail_overlay.gdshader")
const CHUNK_META := &"macro_detail_overlay_chunk"

@export_node_path("Node") var atlas_path: NodePath
@export_node_path("Node3D") var terrain_path: NodePath
@export_range(64.0, 1024.0, 16.0, "or_greater") var chunk_size_meters: float = 256.0
@export_range(2, 32, 1, "or_greater") var mesh_subdivisions: int = 12
@export_range(0.25, 16.0, 0.25, "or_greater") var fallback_mesh_spacing: float = 2.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var begin_distance: float = 0.0
@export_range(0.0, 50000.0, 1.0, "or_greater") var end_distance: float = 8000.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var begin_fade_margin: float = 0.0
@export_range(0.0, 4096.0, 1.0, "or_greater") var end_fade_margin: float = 512.0
@export_range(0.0, 4.0, 0.01, "or_greater") var surface_offset: float = 0.08
@export_range(0.0, 1.0, 0.01) var overlay_strength: float = 0.82
@export_range(0.0, 10000.0, 1.0, "or_greater") var near_hide_distance: float = 920.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var near_fade_distance: float = 240.0

var _atlas
var _terrain: Node3D
var _material: ShaderMaterial
var _chunks: Array[MeshInstance3D] = []
var _terrain_height_enabled := false
var _waiting_for_terrain_height := false


func _ready() -> void:
	set_process(false)
	_resolve_dependencies()
	_configure_material()
	if _atlas and _atlas.has_signal(&"atlas_changed"):
		var callable := Callable(self, "_on_atlas_changed")
		if not _atlas.is_connected(&"atlas_changed", callable):
			_atlas.connect(&"atlas_changed", callable)
	_rebuild_chunks.call_deferred()


func _exit_tree() -> void:
	_set_waiting_for_terrain_height(false)
	_clear_chunks()
	if _atlas and _atlas.has_signal(&"atlas_changed"):
		var callable := Callable(self, "_on_atlas_changed")
		if _atlas.is_connected(&"atlas_changed", callable):
			_atlas.disconnect(&"atlas_changed", callable)


func rebuild_overlay() -> void:
	_resolve_dependencies()
	_configure_material()
	_rebuild_chunks()


func get_chunk_count() -> int:
	return _chunks.size()


func _process(_delta: float) -> void:
	if not _waiting_for_terrain_height:
		set_process(false)
		return

	var was_height_enabled := _terrain_height_enabled
	_resolve_dependencies()
	_configure_material()
	if _terrain_height_enabled and not was_height_enabled:
		_rebuild_chunks()


func _on_atlas_changed() -> void:
	_rebuild_chunks()


func _resolve_dependencies() -> void:
	_atlas = get_node_or_null(atlas_path) if not atlas_path.is_empty() else null
	_terrain = get_node_or_null(terrain_path) as Node3D if not terrain_path.is_empty() else null


func _configure_material() -> void:
	if not _material:
		_material = ShaderMaterial.new()
		_material.shader = OVERLAY_SHADER
	_material.set_shader_parameter("overlay_strength", overlay_strength)
	_material.set_shader_parameter("surface_offset", surface_offset)
	if _atlas and _atlas.has_method("get_texture"):
		var texture := _atlas.call("get_texture") as Texture2D
		if texture:
			_material.set_shader_parameter("macro_detail_texture", texture)
	var near_hide_mask_texture: Texture2D
	if _atlas and _atlas.has_method("get_near_hide_mask_texture"):
		near_hide_mask_texture = _atlas.call("get_near_hide_mask_texture") as Texture2D
	_material.set_shader_parameter("near_hide_mask_enabled", near_hide_mask_texture != null)
	if near_hide_mask_texture:
		_material.set_shader_parameter("near_hide_mask_texture", near_hide_mask_texture)
	_material.set_shader_parameter("near_hide_distance", near_hide_distance)
	_material.set_shader_parameter("near_fade_distance", near_fade_distance)
	_upload_terrain_height_parameters()
	_update_terrain_height_retry_state()


func _rebuild_chunks() -> void:
	_clear_chunks()
	if not _atlas or not _atlas.has_method("has_atlas") or not bool(_atlas.call("has_atlas")):
		return

	_configure_material()
	var rect: Rect2 = _atlas.call("get_world_rect") as Rect2
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var x: float = rect.position.x
	while x < rect.end.x:
		var z: float = rect.position.y
		var chunk_width := minf(chunk_size_meters, rect.end.x - x)
		while z < rect.end.y:
			var chunk_depth := minf(chunk_size_meters, rect.end.y - z)
			_create_chunk(Rect2(Vector2(x, z), Vector2(chunk_width, chunk_depth)))
			z += chunk_size_meters
		x += chunk_size_meters


func _create_chunk(world_rect: Rect2) -> void:
	var chunk_origin := Vector3(
		world_rect.position.x + world_rect.size.x * 0.5,
		0.0,
		world_rect.position.y + world_rect.size.y * 0.5
	)
	var mesh := _build_chunk_mesh(world_rect, chunk_origin)
	if not mesh:
		return

	var instance := MeshInstance3D.new()
	instance.name = "MacroDetail_%d_%d" % [roundi(world_rect.position.x), roundi(world_rect.position.y)]
	instance.position = chunk_origin
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_begin = begin_distance
	instance.visibility_range_begin_margin = begin_fade_margin if begin_distance > 0.0 else 0.0
	instance.visibility_range_end = end_distance
	instance.visibility_range_end_margin = end_fade_margin
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.set_meta(CHUNK_META, true)
	add_child(instance, false, INTERNAL_MODE_BACK)
	instance.owner = null
	_chunks.append(instance)


func _build_chunk_mesh(world_rect: Rect2, chunk_origin: Vector3) -> ArrayMesh:
	var mesh_spacing := _get_overlay_mesh_spacing()
	var x_segments := maxi(ceili(world_rect.size.x / mesh_spacing), 1)
	var z_segments := maxi(ceili(world_rect.size.y / mesh_spacing), 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var atlas_rect: Rect2 = _atlas.call("get_world_rect") as Rect2

	for z_index: int in range(z_segments + 1):
		var z_ratio := float(z_index) / float(z_segments)
		for x_index: int in range(x_segments + 1):
			var x_ratio := float(x_index) / float(x_segments)
			var world_x := world_rect.position.x + world_rect.size.x * x_ratio
			var world_z := world_rect.position.y + world_rect.size.y * z_ratio
			vertices.append(Vector3(
				world_x - chunk_origin.x,
				-chunk_origin.y,
				world_z - chunk_origin.z
			))
			normals.append(Vector3.UP)
			uvs.append(Vector2(
				(world_x - atlas_rect.position.x) / maxf(atlas_rect.size.x, 0.001),
				(world_z - atlas_rect.position.y) / maxf(atlas_rect.size.y, 0.001)
			))

	var row_width := x_segments + 1
	for z_index: int in range(z_segments):
		for x_index: int in range(x_segments):
			var top_left := z_index * row_width + x_index
			var top_right := top_left + 1
			var bottom_left := top_left + row_width
			var bottom_right := bottom_left + 1
			indices.append(top_left)
			indices.append(bottom_left)
			indices.append(top_right)
			indices.append(top_right)
			indices.append(bottom_left)
			indices.append(bottom_right)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _get_overlay_mesh_spacing() -> float:
	var terrain_spacing := _get_terrain_vertex_spacing()
	if terrain_spacing > 0.0:
		return terrain_spacing
	return maxf(fallback_mesh_spacing, 0.25)


func _get_terrain_vertex_spacing() -> float:
	if not is_instance_valid(_terrain):
		return 0.0

	var spacing := float(_terrain.get("vertex_spacing"))
	if is_nan(spacing) or spacing <= 0.0:
		return 0.0
	return spacing


func _upload_terrain_height_parameters() -> void:
	if not _material:
		return

	_terrain_height_enabled = false
	_material.set_shader_parameter("terrain_height_enabled", false)
	_material.set_shader_parameter("_vertex_spacing", maxf(_get_overlay_mesh_spacing(), 0.25))
	_material.set_shader_parameter("_vertex_density", 1.0 / maxf(_get_overlay_mesh_spacing(), 0.25))

	if not is_instance_valid(_terrain):
		return

	var terrain_data := _terrain.get("data") as Object
	var terrain_material := _terrain.get("material") as Object
	if not terrain_data or not terrain_material or not terrain_data.has_method("get_height_maps_rid"):
		return

	var height_maps_rid := terrain_data.call("get_height_maps_rid") as RID
	if not height_maps_rid.is_valid():
		return

	var vertex_spacing := maxf(_get_terrain_vertex_spacing(), 0.25)
	var region_size := maxf(float(_terrain.get("region_size")), 1.0)
	_terrain_height_enabled = true
	_material.set_shader_parameter("terrain_height_enabled", true)
	_material.set_shader_parameter("_background_mode", int(terrain_material.get("world_background")))
	_material.set_shader_parameter("_vertex_spacing", vertex_spacing)
	_material.set_shader_parameter("_vertex_density", 1.0 / vertex_spacing)
	_material.set_shader_parameter("_region_size", region_size)
	_material.set_shader_parameter("_region_texel_size", 1.0 / region_size)
	_material.set_shader_parameter("_region_map_size", 32)

	var material_rid := _material.get_rid()
	if terrain_data.has_method("get_region_map"):
		RenderingServer.material_set_param(material_rid, "_region_map", terrain_data.call("get_region_map"))
	if terrain_data.has_method("get_region_locations"):
		RenderingServer.material_set_param(material_rid, "_region_locations", terrain_data.call("get_region_locations"))
	RenderingServer.material_set_param(material_rid, "_height_maps", height_maps_rid)


func _update_terrain_height_retry_state() -> void:
	_set_waiting_for_terrain_height(not terrain_path.is_empty() and not _terrain_height_enabled)


func _set_waiting_for_terrain_height(waiting: bool) -> void:
	_waiting_for_terrain_height = waiting
	if is_inside_tree():
		set_process(waiting)


func _get_terrain_height(world_position: Vector3) -> float:
	if not is_instance_valid(_terrain):
		return _fallback_height()

	var terrain_data := _terrain.get("data") as Object
	if not terrain_data or not terrain_data.has_method("get_height"):
		return _fallback_height()

	var height := float(terrain_data.call("get_height", world_position))
	if is_nan(height) or absf(height) > 1.0e20:
		return _fallback_height()
	return height


func _fallback_height() -> float:
	return global_position.y if is_inside_tree() else position.y


func _clear_chunks() -> void:
	for chunk: MeshInstance3D in _chunks:
		if not is_instance_valid(chunk):
			continue
		var parent := chunk.get_parent()
		if parent:
			parent.remove_child(chunk)
		chunk.free()
	_chunks.clear()

	var stale_children: Array[Node] = []
	for child: Node in get_children():
		if bool(child.get_meta(CHUNK_META, false)):
			stale_children.append(child)
	for child: Node in stale_children:
		remove_child(child)
		child.free()
