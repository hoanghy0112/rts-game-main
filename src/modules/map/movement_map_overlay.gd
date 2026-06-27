@tool
extends Node3D
class_name MovementMapOverlay

const OVERLAY_SHADER: Shader = preload("res://modules/map/movement_map_overlay.gdshader")
const CHUNK_META := &"movement_map_overlay_chunk"

var _movement_map: Resource

@export var movement_map: Resource:
	get:
		return _movement_map
	set(value):
		_set_movement_map(value, true)

@export_file("*.res", "*.tres") var movement_map_path: String = "":
	set(value):
		movement_map_path = value
		if is_inside_tree():
			reload_movement_map()

@export_node_path("Node3D") var terrain_path: NodePath
@export var show_movement_map := false:
	set(value):
		show_movement_map = value
		if show_movement_map and is_inside_tree() and movement_map and _chunks.is_empty():
			rebuild_overlay()
		else:
			_update_chunk_visibility()
@export var reload_map_now := false:
	set(value):
		reload_map_now = false
		if value:
			reload_movement_map()
			notify_property_list_changed()

@export_range(64.0, 1024.0, 16.0, "or_greater") var chunk_size_meters: float = 256.0
@export_range(0.25, 32.0, 0.25, "or_greater") var fallback_mesh_spacing: float = 8.0
@export_range(0.0, 4.0, 0.01, "or_greater") var surface_offset: float = 0.12
@export_range(0.0, 1.0, 0.01) var overlay_strength: float = 0.78
@export_range(1.0, 4.0, 0.01, "or_greater") var max_visual_speed_multiplier: float = 2.0

var _terrain: Node3D
var _material: ShaderMaterial
var _texture: ImageTexture
var _chunks: Array[MeshInstance3D] = []
var _terrain_height_enabled := false
var _waiting_for_terrain_height := false

var overlay_visible: bool:
	get:
		return show_movement_map
	set(value):
		show_movement_map = value


func _ready() -> void:
	add_to_group(&"movement_map_overlays")
	set_process(false)
	if not movement_map and not movement_map_path.is_empty():
		reload_movement_map(false)
	_resolve_dependencies()
	_configure_material()
	if show_movement_map:
		_rebuild_chunks.call_deferred()


func _exit_tree() -> void:
	remove_from_group(&"movement_map_overlays")
	_set_waiting_for_terrain_height(false)
	_clear_chunks()


func reload_movement_map(rebuild: bool = true) -> void:
	if movement_map_path.is_empty() or not ResourceLoader.exists(movement_map_path):
		_set_movement_map(null, rebuild)
		return

	var loaded: Resource = ResourceLoader.load(movement_map_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_set_movement_map(loaded, rebuild)


func _set_movement_map(value: Resource, rebuild: bool) -> void:
	_movement_map = value
	_texture = null
	if rebuild and is_inside_tree():
		if show_movement_map:
			rebuild_overlay()
		else:
			_clear_chunks()


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


func _resolve_dependencies() -> void:
	_terrain = get_node_or_null(terrain_path) as Node3D if not terrain_path.is_empty() else null


func _configure_material() -> void:
	if not _material:
		_material = ShaderMaterial.new()
		_material.shader = OVERLAY_SHADER
	_material.set_shader_parameter("overlay_strength", overlay_strength)
	_material.set_shader_parameter("surface_offset", surface_offset)
	_material.set_shader_parameter("max_speed_multiplier", max_visual_speed_multiplier)
	var texture := _get_texture()
	if texture:
		_material.set_shader_parameter("movement_map_texture", texture)
	_upload_terrain_height_parameters()
	_update_terrain_height_retry_state()


func _get_texture() -> Texture2D:
	if _texture:
		return _texture
	var map_width := _get_map_width()
	var map_height := _get_map_height()
	if not movement_map or map_width <= 0 or map_height <= 0:
		return null

	var speed_multipliers: PackedFloat32Array = movement_map.get("speed_multipliers") as PackedFloat32Array
	var flag_array: PackedByteArray = movement_map.get("flags") as PackedByteArray
	var image := Image.create(map_width, map_height, false, Image.FORMAT_RGBA8)
	var max_speed := maxf(max_visual_speed_multiplier, 0.001)
	for y: int in range(map_height):
		for x: int in range(map_width):
			var index: int = y * map_width + x
			var speed: float = speed_multipliers[index] if index < speed_multipliers.size() else 0.0
			var flag_value: int = flag_array[index] if index < flag_array.size() else 0
			image.set_pixel(x, y, Color(
				clampf(speed / max_speed, 0.0, 1.0),
				float(flag_value) / 255.0,
				0.0,
				1.0
			))
	_texture = ImageTexture.create_from_image(image)
	return _texture


func _rebuild_chunks() -> void:
	_clear_chunks()
	if not movement_map or _get_map_width() <= 0 or _get_map_height() <= 0:
		return

	_configure_material()
	var rect := _get_world_rect()
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
	_update_chunk_visibility()


func _get_world_rect() -> Rect2:
	if not movement_map:
		return Rect2()
	return Rect2(
		_get_map_origin(),
		Vector2(
			float(_get_map_width()) * _get_map_cell_size(),
			float(_get_map_height()) * _get_map_cell_size()
		)
	)


func _get_map_origin() -> Vector2:
	if not movement_map:
		return Vector2.ZERO
	var value: Variant = movement_map.get("origin")
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO


func _get_map_width() -> int:
	if not movement_map:
		return 0
	return int(movement_map.get("width"))


func _get_map_height() -> int:
	if not movement_map:
		return 0
	return int(movement_map.get("height"))


func _get_map_cell_size() -> float:
	if not movement_map:
		return 0.0
	return maxf(float(movement_map.get("cell_size_meters")), 0.0)


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
	instance.name = "MovementMap_%d_%d" % [roundi(world_rect.position.x), roundi(world_rect.position.y)]
	instance.position = chunk_origin
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visible = show_movement_map
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
	var map_rect := _get_world_rect()

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
				(world_x - map_rect.position.x) / maxf(map_rect.size.x, 0.001),
				(world_z - map_rect.position.y) / maxf(map_rect.size.y, 0.001)
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
	if movement_map and _get_map_cell_size() > 0.0:
		return minf(maxf(fallback_mesh_spacing, 0.25), _get_map_cell_size())
	return maxf(fallback_mesh_spacing, 0.25)


func _get_terrain_vertex_spacing() -> float:
	if not is_instance_valid(_terrain):
		return 0.0
	var spacing := 0.0
	if _terrain.has_method("get_vertex_spacing"):
		spacing = float(_terrain.call("get_vertex_spacing"))
	else:
		spacing = float(_terrain.get("vertex_spacing"))
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
	var region_size := 1.0
	if _terrain.has_method("get_region_size"):
		region_size = maxf(float(_terrain.call("get_region_size")), 1.0)
	else:
		region_size = maxf(float(_terrain.get("region_size")), 1.0)
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


func _update_chunk_visibility() -> void:
	for chunk: MeshInstance3D in _chunks:
		if is_instance_valid(chunk):
			chunk.visible = show_movement_map


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
