@tool
extends Node3D
class_name ForestDenseGrassParticles

@export var terrain: Node3D:
	set(value):
		if terrain == value:
			return
		terrain = value
		_create_grid()

@export var plant_id: StringName = &"forest_smooth_grass_01"

@export_range(0.125, 2.0, 0.015625) var instance_spacing: float = 1.125:
	set(value):
		instance_spacing = clamp(round(value * 64.0) * 0.015625, 0.125, 2.0)
		rows = maxi(int(cell_width / instance_spacing), 1)
		amount = rows * rows
		_set_offsets()
		_mark_static_process_parameters_dirty()

@export_range(8.0, 256.0, 1.0) var cell_width: float = 96.0:
	set(value):
		cell_width = clamp(value, 8.0, 256.0)
		rows = maxi(int(cell_width / instance_spacing), 1)
		amount = rows * rows
		min_draw_distance = 1.0
		_update_particle_aabbs()
		_set_offsets()
		_mark_static_process_parameters_dirty()

@export_range(1, 15, 2) var grid_width: int = 5:
	set(value):
		var odd_value := value if value % 2 == 1 else value + 1
		grid_width = clampi(odd_value, 1, 15)
		particle_count = 1
		min_draw_distance = 1.0
		_create_grid()

@export_storage var rows: int = 85

@export_storage var amount: int = 7225:
	set(value):
		amount = maxi(value, 1)
		particle_count = amount * grid_width * grid_width
		last_pos = Vector3.ZERO
		for particle_node: GPUParticles3D in particle_nodes:
			particle_node.amount = amount

@export_range(1, 256, 1) var process_fixed_fps: int = 1:
	set(value):
		process_fixed_fps = maxi(value, 1)
		for particle_node: GPUParticles3D in particle_nodes:
			particle_node.fixed_fps = process_fixed_fps
			particle_node.preprocess = 1.0 / float(process_fixed_fps)

@export_range(1.0, 64.0, 0.25, "or_greater") var reposition_threshold_meters: float = 8.0

@export var process_material: ShaderMaterial
@export var mesh: Mesh

@export var shadow_mode: GeometryInstance3D.ShadowCastingSetting = (
	GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
):
	set(value):
		shadow_mode = value
		for particle_node: GPUParticles3D in particle_nodes:
			particle_node.cast_shadow = value

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial")
var mesh_material_override: Material:
	set(value):
		mesh_material_override = value
		for particle_node: GPUParticles3D in particle_nodes:
			particle_node.material_override = mesh_material_override

@export_group("Info")
@export var min_draw_distance: float = 240.0:
	set(value):
		min_draw_distance = float(cell_width * grid_width) * 0.5
		_mark_static_process_parameters_dirty()

@export var particle_count: int = 180625:
	set(value):
		particle_count = amount * grid_width * grid_width

var offsets: Array[Vector3] = []
var last_pos: Vector3 = Vector3.ZERO
var particle_nodes: Array[GPUParticles3D] = []

var _mask_texture: Texture2D
var _mask_cell_min := Vector2i.ZERO
var _mask_texture_size := Vector2i.ONE
var _region_origin := Vector3.ZERO
var _region_cell_size := 4.0
var _region_world_to_local := Transform3D.IDENTITY
var _unique_materials := false
var _static_process_parameters_dirty := true


func _ready() -> void:
	_ensure_unique_materials()
	_create_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_destroy_grid()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(terrain):
		set_physics_process(false)
		return

	var camera := _get_terrain_camera()
	if _static_process_parameters_dirty:
		_upload_static_process_parameters()

	var threshold := maxf(reposition_threshold_meters, instance_spacing)
	if camera and last_pos.distance_squared_to(camera.global_position) > threshold * threshold:
		var pos := camera.global_position.snapped(Vector3.ONE)
		_position_grid(pos)
		_set_camera_position_parameter(pos)
		last_pos = camera.global_position


func configure_from_region(
	p_terrain: Node3D,
	region: Node3D,
	cells: Array[Vector2i],
	p_plant_id: StringName,
	p_cell_size: float,
	p_origin: Vector3
) -> void:
	_ensure_unique_materials()
	plant_id = p_plant_id
	_region_origin = p_origin
	_region_cell_size = maxf(p_cell_size, 0.1)
	_region_world_to_local = (
		region.global_transform.affine_inverse()
		if region.is_inside_tree()
		else region.transform.affine_inverse()
	)
	_set_mask_from_cells(cells)
	terrain = p_terrain
	if particle_nodes.is_empty():
		_create_grid()
	_apply_mask_parameters()
	_upload_static_process_parameters()


func _ensure_unique_materials() -> void:
	if _unique_materials:
		return
	if process_material:
		process_material = process_material.duplicate(true) as ShaderMaterial
	if mesh_material_override:
		mesh_material_override = mesh_material_override.duplicate(true) as Material
	_unique_materials = true


func _create_grid() -> void:
	_destroy_grid()
	if not process_material or not mesh:
		set_physics_process(false)
		return

	set_physics_process(is_instance_valid(terrain))
	_set_offsets()
	var particle_aabb := _get_particle_aabb()
	var half_grid := grid_width / 2
	for x: int in range(-half_grid, half_grid + 1):
		for z: int in range(-half_grid, half_grid + 1):
			var particle_node := GPUParticles3D.new()
			particle_node.lifetime = 600.0
			particle_node.amount = amount
			particle_node.explosiveness = 1.0
			particle_node.amount_ratio = 1.0
			particle_node.process_material = process_material
			particle_node.draw_pass_1 = mesh
			particle_node.speed_scale = 1.0
			particle_node.custom_aabb = particle_aabb
			particle_node.cast_shadow = shadow_mode
			particle_node.fixed_fps = process_fixed_fps
			particle_node.preprocess = 1.0 / float(process_fixed_fps)
			particle_node.use_fixed_seed = true
			if mesh_material_override:
				particle_node.material_override = mesh_material_override
			if not particle_nodes.is_empty() and (x > -half_grid or z > -half_grid):
				particle_node.seed = particle_nodes[0].seed
			add_child(particle_node, false, INTERNAL_MODE_BACK)
			particle_node.owner = null
			particle_node.emitting = true
			particle_nodes.append(particle_node)
	last_pos = Vector3.ZERO
	_apply_mask_parameters()
	_upload_static_process_parameters()


func _set_offsets() -> void:
	var half_grid := grid_width / 2
	offsets.clear()
	for x: int in range(-half_grid, half_grid + 1):
		for z: int in range(-half_grid, half_grid + 1):
			offsets.append(Vector3(
				float(x * rows) * instance_spacing,
				0.0,
				float(z * rows) * instance_spacing
			))


func _destroy_grid() -> void:
	for particle_node: GPUParticles3D in particle_nodes:
		if not is_instance_valid(particle_node):
			continue
		var parent := particle_node.get_parent()
		if parent:
			parent.remove_child(particle_node)
		particle_node.free()
	particle_nodes.clear()


func _position_grid(pos: Vector3) -> void:
	for index: int in range(particle_nodes.size()):
		var particle_node := particle_nodes[index]
		if not is_instance_valid(particle_node):
			continue
		var snap := Vector3(pos.x, 0.0, pos.z).snapped(Vector3.ONE) + offsets[index]
		particle_node.global_position = (snap / instance_spacing).round() * instance_spacing
		particle_node.reset_physics_interpolation()
		particle_node.restart(true)


func _upload_static_process_parameters() -> bool:
	if not process_material or not is_instance_valid(terrain):
		return false

	var process_rid := process_material.get_rid()
	if not process_rid.is_valid():
		return false

	var terrain_data := terrain.get("data") as Object
	var terrain_material := terrain.get("material") as Object
	if not terrain_data or not terrain_material:
		return false

	RenderingServer.material_set_param(process_rid, "_background_mode", int(terrain_material.get("world_background")))
	RenderingServer.material_set_param(process_rid, "_vertex_spacing", float(terrain.get("vertex_spacing")))
	RenderingServer.material_set_param(process_rid, "_vertex_density", 1.0 / float(terrain.get("vertex_spacing")))
	RenderingServer.material_set_param(process_rid, "_region_size", float(terrain.get("region_size")))
	RenderingServer.material_set_param(process_rid, "_region_texel_size", 1.0 / float(terrain.get("region_size")))
	RenderingServer.material_set_param(process_rid, "_region_map_size", 32)
	if terrain_data.has_method("get_region_map"):
		RenderingServer.material_set_param(process_rid, "_region_map", terrain_data.call("get_region_map"))
	if terrain_data.has_method("get_region_locations"):
		RenderingServer.material_set_param(process_rid, "_region_locations", terrain_data.call("get_region_locations"))
	if terrain_data.has_method("get_height_maps_rid"):
		RenderingServer.material_set_param(process_rid, "_height_maps", terrain_data.call("get_height_maps_rid"))
	if terrain_data.has_method("get_control_maps_rid"):
		RenderingServer.material_set_param(process_rid, "_control_maps", terrain_data.call("get_control_maps_rid"))
	if terrain_data.has_method("get_color_maps_rid"):
		RenderingServer.material_set_param(process_rid, "_color_maps", terrain_data.call("get_color_maps_rid"))
	RenderingServer.material_set_param(process_rid, "instance_spacing", instance_spacing)
	RenderingServer.material_set_param(process_rid, "instance_rows", rows)
	RenderingServer.material_set_param(process_rid, "max_dist", min_draw_distance)
	_apply_mask_parameters()
	_static_process_parameters_dirty = false
	return true


func _set_camera_position_parameter(pos: Vector3) -> void:
	if not process_material:
		return

	var process_rid := process_material.get_rid()
	if process_rid.is_valid():
		RenderingServer.material_set_param(process_rid, "camera_position", pos)


func _mark_static_process_parameters_dirty() -> void:
	_static_process_parameters_dirty = true


func _apply_mask_parameters() -> void:
	if not process_material:
		return

	var process_rid := process_material.get_rid()
	if not process_rid.is_valid():
		return

	var mask_rid := RID()
	if _mask_texture:
		mask_rid = _mask_texture.get_rid()
	var mask_enabled := mask_rid.is_valid()
	RenderingServer.material_set_param(process_rid, "forest_mask_enabled", mask_enabled)
	if mask_enabled:
		RenderingServer.material_set_param(process_rid, "forest_cell_mask", mask_rid)
	RenderingServer.material_set_param(process_rid, "forest_world_to_region", _region_world_to_local)
	RenderingServer.material_set_param(process_rid, "forest_origin", _region_origin)
	RenderingServer.material_set_param(process_rid, "forest_cell_size", _region_cell_size)
	RenderingServer.material_set_param(
		process_rid,
		"forest_mask_cell_min",
		Vector2(float(_mask_cell_min.x), float(_mask_cell_min.y))
	)
	RenderingServer.material_set_param(
		process_rid,
		"forest_mask_texture_size",
		Vector2(float(_mask_texture_size.x), float(_mask_texture_size.y))
	)


func _set_mask_from_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		_mask_texture = null
		_mask_cell_min = Vector2i.ZERO
		_mask_texture_size = Vector2i.ONE
		return

	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell: Vector2i in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	_mask_cell_min = min_cell
	_mask_texture_size = Vector2i(max_cell.x - min_cell.x + 3, max_cell.y - min_cell.y + 3)
	var image := Image.create(_mask_texture_size.x, _mask_texture_size.y, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for cell: Vector2i in cells:
		var pixel := cell - min_cell + Vector2i.ONE
		image.set_pixel(pixel.x, pixel.y, Color.WHITE)
	_mask_texture = ImageTexture.create_from_image(image)


func _update_particle_aabbs() -> void:
	var particle_aabb := _get_particle_aabb()
	for particle_node: GPUParticles3D in particle_nodes:
		particle_node.custom_aabb = particle_aabb


func _get_particle_aabb() -> AABB:
	var height_range := Vector2(32.0, -32.0)
	if is_instance_valid(terrain):
		var terrain_data := terrain.get("data") as Object
		if terrain_data and terrain_data.has_method("get_height_range"):
			var range_variant: Variant = terrain_data.call("get_height_range")
			if range_variant is Vector2:
				height_range = range_variant as Vector2

	var height := height_range.x - height_range.y
	var particle_aabb := AABB()
	particle_aabb.size = Vector3(cell_width, height, cell_width)
	particle_aabb.position = particle_aabb.size * -0.5
	particle_aabb.position.y = height_range.y
	return particle_aabb


func _get_terrain_camera() -> Camera3D:
	if is_instance_valid(terrain) and terrain.has_method("get_camera"):
		var camera_variant: Variant = terrain.call("get_camera")
		if camera_variant is Camera3D:
			return camera_variant as Camera3D
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null
