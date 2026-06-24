extends Node3D
class_name Camp

signal selected_changed(selected: bool)
signal logistics_changed(summary: Dictionary)

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_CAMP_TYPE := &"camp"
const CAMP_CLICK_PROXY_NAME := "CampClickProxy"
const CAMP_FLAG_NAME := "CampFlag"
const CAMP_FLAG_SPRITE_NAME := "Gonfalon"
const FLAG_BORDER_NODE_NAME := "CampFlagHoverBorder"
const RANGE_RING_NAME := "CampRange"
const FLAG_TEXTURE_WIDTH := 96
const FLAG_TEXTURE_HEIGHT := 144
const FLAG_BORDER_PIXEL_SIZE_MULTIPLIER := 1.08

@export_group("Identity")
@export var camp_id: StringName = &"camp"
@export var display_name := "Camp"
@export var team_id: StringName = &"player"
@export var controllable := true

@export_group("Storage")
@export_range(0.0, 100000.0, 1.0, "or_greater") var food_kg: float = 0.0:
	set(value):
		food_kg = maxf(value, 0.0)
		_emit_logistics_changed_if_ready()
@export_range(0.0, 100000.0, 1.0, "or_greater") var wood_kg: float = 0.0:
	set(value):
		wood_kg = maxf(value, 0.0)
		_emit_logistics_changed_if_ready()
@export_range(0.0, 100000.0, 1.0, "or_greater") var invested_wood_kg: float = 0.0:
	set(value):
		invested_wood_kg = maxf(value, 0.0)
		_emit_logistics_changed_if_ready()

@export_group("Range")
@export_range(1.0, 512.0, 0.5, "or_greater") var camp_range_m: float = 36.0:
	set(value):
		camp_range_m = maxf(value, 1.0)
		if is_inside_tree():
			_rebuild_visuals()

@export_group("Visuals")
@export_range(0.1, 8.0, 0.05, "or_greater") var camp_building_scale: float = 2.1:
	set(value):
		camp_building_scale = maxf(value, 0.1)
		if is_inside_tree():
			_rebuild_visuals()
@export var team_flag_color: Color = Color(0.1, 0.28, 0.82, 1.0):
	set(value):
		team_flag_color = value
		if is_inside_tree():
			_rebuild_visuals()
@export var camp_flag_color: Color = Color(0.78, 0.1, 0.08, 1.0):
	set(value):
		camp_flag_color = value
		if is_inside_tree():
			_rebuild_visuals()
@export var affect_zone_color: Color = Color(1.0, 0.82, 0.28, 1.0):
	set(value):
		affect_zone_color = Color(value.r, value.g, value.b, 1.0)
		if is_inside_tree():
			_rebuild_visuals()
@export_range(0.0001, 0.2, 0.00005, "or_greater") var camp_flag_pixel_size: float = 0.00075:
	set(value):
		camp_flag_pixel_size = maxf(value, 0.0001)
		if is_inside_tree():
			_update_flag_camera_scale(true)
@export_range(0.0001, 0.2, 0.00005, "or_greater") var camp_flag_min_pixel_size: float = 0.00028:
	set(value):
		camp_flag_min_pixel_size = maxf(value, 0.0001)
		if is_inside_tree():
			_update_flag_camera_scale(true)
@export_range(1.0, 2000.0, 1.0, "or_greater") var camp_flag_near_camera_distance_m: float = 32.0:
	set(value):
		camp_flag_near_camera_distance_m = maxf(value, 1.0)
		if is_inside_tree():
			_update_flag_camera_scale(true)
@export_range(1.0, 4000.0, 1.0, "or_greater") var camp_flag_far_camera_distance_m: float = 260.0:
	set(value):
		camp_flag_far_camera_distance_m = maxf(value, 1.0)
		if is_inside_tree():
			_update_flag_camera_scale(true)
@export_range(0.05, 16.0, 0.005, "or_greater") var camp_flag_proxy_width_m: float = 0.10625:
	set(value):
		camp_flag_proxy_width_m = maxf(value, 0.05)
		if is_inside_tree():
			_rebuild_visuals()
@export_range(0.05, 18.0, 0.005, "or_greater") var camp_flag_proxy_height_m: float = 0.18125:
	set(value):
		camp_flag_proxy_height_m = maxf(value, 0.05)
		if is_inside_tree():
			_rebuild_visuals()
@export_flags_3d_physics var selection_collision_layer: int = 1 << 5:
	set(value):
		selection_collision_layer = value
		if is_inside_tree():
			_rebuild_visuals()
@export_range(0.0, 8.0, 0.01, "or_greater") var range_surface_offset: float = 0.46

var _selected := false
var _hovered := false
var _visual_root: Node3D
var _flag_sprite: Sprite3D
var _flag_border_sprite: Sprite3D
var _last_flag_pixel_size := -1.0
var _ready_to_emit := false


func _ready() -> void:
	add_to_group(&"camps")
	_ready_to_emit = true
	_rebuild_visuals()
	_emit_logistics_changed_if_ready()


func _process(_delta: float) -> void:
	_update_flag_camera_scale()


func _exit_tree() -> void:
	remove_from_group(&"camps")


func configure_from_troop(troop: Node, wood_invested: float, starting_food: float, starting_wood: float) -> void:
	if troop:
		var troop_id_value: Variant = troop.get("troop_id")
		camp_id = StringName("%s_camp" % String(troop_id_value if troop_id_value != null else name))
		display_name = "%s Camp" % String(troop.get("display_name") if troop.get("display_name") != null else "Troop")
		var team_value: Variant = troop.get("team_id")
		if team_value != null:
			team_id = StringName(team_value)
		var controllable_value: Variant = troop.get("controllable")
		if controllable_value is bool:
			controllable = bool(controllable_value)
		_copy_troop_color(troop, &"team_flag_color", true)
		_copy_troop_color(troop, &"troop_flag_color", false)
		_copy_troop_float(troop, &"camp_pack_range_m", &"camp_range_m")
		_copy_troop_float(troop, &"camp_building_scale", &"camp_building_scale")
		var layer_value: Variant = troop.get("selection_collision_layer")
		if layer_value is int:
			selection_collision_layer = int(layer_value)
	invested_wood_kg = wood_invested
	food_kg = starting_food
	wood_kg = starting_wood
	if is_inside_tree():
		_rebuild_visuals()
		_emit_logistics_changed_if_ready()


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_update_hover_visuals()
	selected_changed.emit(_selected)


func is_selected() -> bool:
	return _selected


func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_update_hover_visuals()


func is_hovered() -> bool:
	return _hovered


func is_troop_in_range(troop: Node) -> bool:
	if not (troop is Node3D):
		return false
	return global_position.distance_to((troop as Node3D).global_position) <= maxf(camp_range_m, 0.1)


func withdraw_food_kg(amount_kg: float) -> float:
	var amount := minf(maxf(amount_kg, 0.0), food_kg)
	food_kg = maxf(food_kg - amount, 0.0)
	return amount


func deposit_food_kg(amount_kg: float) -> float:
	var amount := maxf(amount_kg, 0.0)
	food_kg += amount
	return amount


func withdraw_wood_kg(amount_kg: float) -> float:
	var amount := minf(maxf(amount_kg, 0.0), wood_kg)
	wood_kg = maxf(wood_kg - amount, 0.0)
	return amount


func deposit_wood_kg(amount_kg: float) -> float:
	var amount := maxf(amount_kg, 0.0)
	wood_kg += amount
	return amount


func get_management_summary() -> Dictionary:
	return {
		"entity_type": &"camp",
		"troop_id": camp_id,
		"display_name": display_name,
		"team_id": team_id,
		"controllable": controllable,
		"selected": _selected,
		"state": &"camp",
		"camp_established": true,
		"camp_food_kg": food_kg,
		"camp_wood_kg": wood_kg,
		"camp_wood_invested_kg": invested_wood_kg,
		"camp_pack_range_m": camp_range_m,
		"camp_range_m": camp_range_m,
		"camp_position": global_position,
		"camp_building_scale": camp_building_scale,
		"read_only": not controllable,
	}


func get_troop_summary() -> Dictionary:
	return get_management_summary()


func get_management_flag_world_position() -> Vector3:
	var flag := find_child(CAMP_FLAG_NAME, true, false) as Node3D
	if flag:
		var sprite := flag.get_node_or_null(CAMP_FLAG_SPRITE_NAME) as Node3D
		return sprite.global_position if sprite else flag.global_position
	return global_position + Vector3(0.0, 6.0 * camp_building_scale, 0.0)


func _copy_troop_color(troop: Node, property_name: StringName, team_color: bool) -> void:
	var value: Variant = troop.get(String(property_name))
	if value is Color:
		if team_color:
			team_flag_color = value as Color
		else:
			camp_flag_color = value as Color


func _copy_troop_float(troop: Node, source_property: StringName, target_property: StringName, multiplier: float = 1.0) -> void:
	var value: Variant = troop.get(String(source_property))
	if value is float or value is int:
		set(String(target_property), maxf(float(value) * multiplier, 0.0))


func _rebuild_visuals() -> void:
	_clear_visuals()
	_visual_root = Node3D.new()
	_visual_root.name = "CampVisuals"
	add_child(_visual_root)
	_visual_root.owner = null

	var s := maxf(camp_building_scale, 0.1)
	var ring := MeshInstance3D.new()
	ring.name = RANGE_RING_NAME
	ring.mesh = _build_ring_mesh(camp_range_m)
	ring.position.y = range_surface_offset + 0.02
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ring.material_override = _make_range_material()
	_visual_root.add_child(ring)

	_add_storage_hut(Vector3(-2.2 * s, 0.0, -1.25 * s), s)
	_add_supply_rack(Vector3(1.5 * s, 0.0, -1.35 * s), s)
	_add_fire(Vector3(0.1 * s, 0.0, 0.8 * s), s)
	for index: int in range(3):
		_add_living_hut(Vector3((float(index) - 1.0) * 2.5 * s, 0.0, 2.45 * s), deg_to_rad(-10.0 + float(index) * 8.0), s)

	var watch_post := _make_box("WatchPost", Vector3(0.42, 2.3, 0.42) * s, Color(0.38, 0.24, 0.1, 1.0))
	watch_post.position = Vector3(4.1 * s, 1.16 * s, -2.55 * s)
	_visual_root.add_child(watch_post)

	var flag := _create_flag(CAMP_FLAG_NAME, camp_flag_color, team_flag_color, s)
	flag.position = Vector3(4.1 * s, 2.75 * s, -2.55 * s)
	_visual_root.add_child(flag)

	_add_selection_proxy(flag, s)
	_update_hover_visuals()
	_update_flag_camera_scale(true)


func _add_storage_hut(position_value: Vector3, s: float) -> void:
	var hut := Node3D.new()
	hut.name = "CampStorage"
	hut.position = position_value
	_visual_root.add_child(hut)
	var body := _make_box("StorageBody", Vector3(1.82, 1.0, 1.24) * s, Color(0.5, 0.38, 0.22, 1.0))
	body.position = Vector3(0.0, 1.14 * s, 0.0)
	hut.add_child(body)
	var roof := MeshInstance3D.new()
	roof.name = "StorageRoof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.55, 0.94, 1.86) * s
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, 1.84 * s, 0.0)
	roof.rotation.y = PI * 0.5
	roof.material_override = _make_material(Color(0.62, 0.53, 0.31, 1.0))
	hut.add_child(roof)
	var sack := _make_box("FoodSack", Vector3(0.34, 0.32, 0.28) * s, Color(0.68, 0.58, 0.4, 1.0))
	sack.position = Vector3(-0.58 * s, 0.48 * s, -0.78 * s)
	hut.add_child(sack)
	var wood := _make_cylinder("WoodBundle", 0.08 * s, 0.78 * s, Color(0.46, 0.26, 0.1, 1.0), 8)
	wood.position = Vector3(0.58 * s, 0.5 * s, -0.78 * s)
	wood.rotation.z = PI * 0.5
	hut.add_child(wood)


func _add_supply_rack(position_value: Vector3, s: float) -> void:
	var rack := Node3D.new()
	rack.name = "CampSupplyRack"
	rack.position = position_value
	rack.rotation.y = deg_to_rad(-11.0)
	_visual_root.add_child(rack)
	var beam := _make_box("RackBeam", Vector3(1.5, 0.08, 0.08) * s, Color(0.32, 0.21, 0.1, 1.0))
	beam.position = Vector3(0.0, 1.18 * s, 0.0)
	rack.add_child(beam)
	for index: int in range(4):
		var log := _make_cylinder("StackedLog_%d" % index, 0.075 * s, 1.2 * s, Color(0.45, 0.27, 0.11, 1.0), 8)
		log.position = Vector3(0.0, (0.16 + float(index) * 0.11) * s, (-0.3 + float(index % 2) * 0.18) * s)
		log.rotation.z = PI * 0.5
		rack.add_child(log)


func _add_fire(position_value: Vector3, s: float) -> void:
	var fire := Node3D.new()
	fire.name = "CampFire"
	fire.position = position_value
	_visual_root.add_child(fire)
	for index: int in range(7):
		var angle := TAU * float(index) / 7.0
		var stone := _make_cylinder("FireStone_%d" % index, 0.08 * s, 0.1 * s, Color(0.22, 0.2, 0.17, 1.0), 7)
		stone.position = Vector3(cos(angle) * 0.38 * s, 0.05 * s, sin(angle) * 0.38 * s)
		fire.add_child(stone)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var flame_mesh := PrismMesh.new()
	flame_mesh.size = Vector3(0.34, 0.62, 0.34) * s
	flame.mesh = flame_mesh
	flame.position = Vector3(0.0, 0.52 * s, 0.0)
	flame.material_override = _make_material(Color(1.0, 0.48, 0.1, 0.88))
	fire.add_child(flame)


func _add_living_hut(position_value: Vector3, yaw: float, s: float) -> void:
	var hut := Node3D.new()
	hut.name = "LivingHut"
	hut.position = position_value
	hut.rotation.y = yaw
	_visual_root.add_child(hut)
	var body := _make_box("WovenBody", Vector3(1.56, 0.84, 1.06) * s, Color(0.58, 0.5, 0.36, 1.0))
	body.position = Vector3(0.0, 0.82 * s, 0.0)
	hut.add_child(body)
	var roof := MeshInstance3D.new()
	roof.name = "ThatchedRoof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.04, 0.86, 1.54) * s
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, 1.42 * s, 0.0)
	roof.rotation.y = PI * 0.5
	roof.material_override = _make_material(Color(0.55, 0.47, 0.28, 1.0))
	hut.add_child(roof)


func _create_flag(flag_name: String, banner_color: Color, accent_color: Color, _s: float) -> Node3D:
	var flag := Node3D.new()
	flag.name = flag_name

	var sprite_position := Vector3(0.0, camp_flag_proxy_height_m * 0.5, 0.0)
	var initial_pixel_size := _get_flag_camera_scaled_pixel_size()
	var border := _create_flag_sprite(
		FLAG_BORDER_NODE_NAME,
		_build_gonfalon_texture(Color(1.0, 0.82, 0.28, 1.0), Color(1.0, 0.82, 0.28, 1.0)),
		initial_pixel_size * FLAG_BORDER_PIXEL_SIZE_MULTIPLIER,
		29
	)
	border.position = sprite_position
	border.visible = false
	flag.add_child(border)
	_flag_border_sprite = border

	var sprite := _create_flag_sprite(
		CAMP_FLAG_SPRITE_NAME,
		_build_gonfalon_texture(banner_color, accent_color),
		initial_pixel_size,
		30
	)
	sprite.position = sprite_position
	flag.add_child(sprite)
	_flag_sprite = sprite
	return flag


func _create_flag_sprite(
	sprite_name: String,
	texture: Texture2D,
	pixel_size_value: float,
	render_priority_value: int
) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = true
	sprite.pixel_size = maxf(pixel_size_value, 0.0001)
	_set_property_if_present(sprite, &"billboard", BaseMaterial3D.BILLBOARD_ENABLED)
	_set_property_if_present(sprite, &"fixed_size", true)
	_set_property_if_present(sprite, &"no_depth_test", true)
	_set_property_if_present(sprite, &"shaded", false)
	_set_property_if_present(sprite, &"double_sided", true)
	_set_property_if_present(sprite, &"transparent", true)
	_set_property_if_present(sprite, &"render_priority", render_priority_value)
	return sprite


func _add_selection_proxy(flag: Node3D, _s: float) -> void:
	if not flag:
		return
	var proxy := StaticBody3D.new()
	proxy.name = CAMP_CLICK_PROXY_NAME
	proxy.collision_layer = selection_collision_layer
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_CAMP_TYPE)
	proxy.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(camp_flag_proxy_width_m, 0.05),
		maxf(camp_flag_proxy_height_m, 0.05),
		1.2
	)
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	proxy.add_child(shape)
	flag.add_child(proxy)


func _update_hover_visuals() -> void:
	var active := _hovered or _selected
	var color := _get_hover_color()
	for node: Node in find_children("%s*" % FLAG_BORDER_NODE_NAME, "Sprite3D", true, false):
		var border := node as Sprite3D
		border.visible = active
		border.modulate = color


func _update_flag_camera_scale(force: bool = false) -> void:
	if not is_instance_valid(_flag_sprite):
		return
	var pixel_size := _get_flag_camera_scaled_pixel_size()
	if (
		not force
		and _last_flag_pixel_size >= 0.0
		and absf(pixel_size - _last_flag_pixel_size) <= 0.00000001
	):
		return
	_flag_sprite.pixel_size = pixel_size
	if is_instance_valid(_flag_border_sprite):
		_flag_border_sprite.pixel_size = pixel_size * FLAG_BORDER_PIXEL_SIZE_MULTIPLIER
	_last_flag_pixel_size = pixel_size


func _get_flag_camera_scaled_pixel_size() -> float:
	var near_size := maxf(camp_flag_pixel_size, 0.0001)
	var far_size := maxf(camp_flag_min_pixel_size, 0.0001)
	var lower_size := minf(near_size, far_size)
	var upper_size := maxf(near_size, far_size)
	var camera := _get_active_camera()
	if not camera:
		return clampf(near_size, lower_size, upper_size)

	var near_distance := maxf(camp_flag_near_camera_distance_m, 0.001)
	var far_distance := maxf(camp_flag_far_camera_distance_m, 0.001)
	var distance_span := maxf(absf(far_distance - near_distance), 0.001)
	var distance := _get_flag_camera_distance(camera)
	var t := clampf((distance - near_distance) / distance_span, 0.0, 1.0)
	if far_distance < near_distance:
		t = 1.0 - t
	return clampf(lerpf(near_size, far_size, t), lower_size, upper_size)


func _get_flag_camera_distance(camera: Camera3D) -> float:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return maxf(camera.size, 0.001)
	var flag_position := _get_cached_flag_world_position()
	var forward := -camera.global_transform.basis.z.normalized()
	var depth := (flag_position - camera.global_position).dot(forward)
	if depth > camera.near:
		return depth
	return camera.global_position.distance_to(flag_position)


func _get_cached_flag_world_position() -> Vector3:
	if is_instance_valid(_flag_sprite):
		return _flag_sprite.global_position
	return get_management_flag_world_position()


func _get_active_camera() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null


func _build_ring_mesh(radius: float) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.1)
	var half_width := 0.08
	var inner_radius := maxf(safe_radius - half_width, 0.05)
	var outer_radius := safe_radius + half_width
	var segments := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * outer_radius)
		vertices.append(direction * inner_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		colors.append(Color.WHITE)
		colors.append(Color.WHITE)
	for index: int in range(segments):
		var next_index := (index + 1) % segments
		var outer_a := index * 2
		var inner_a := outer_a + 1
		var outer_b := next_index * 2
		var inner_b := outer_b + 1
		indices.append(outer_a)
		indices.append(inner_a)
		indices.append(outer_b)
		indices.append(outer_b)
		indices.append(inner_a)
		indices.append(inner_b)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_box(node_name: String, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	return instance


func _make_cylinder(node_name: String, radius: float, height: float, color: Color, radial_segments: int = 10) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = maxi(radial_segments, 3)
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	return instance


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _make_flag_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_range_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 21
	material.albedo_color = affect_zone_color
	material.emission_enabled = true
	material.emission = Color(affect_zone_color.r, affect_zone_color.g, affect_zone_color.b, 1.0)
	material.emission_energy_multiplier = 0.2
	return material


func _make_hover_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 25
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.35
	return material


func _get_hover_color() -> Color:
	if _selected:
		return Color(1.0, 0.82, 0.28, 0.96)
	return Color(1.0, 0.82, 0.28, 0.74)


func _build_gonfalon_texture(banner_color: Color, accent_color: Color) -> Texture2D:
	var image := Image.create(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	_fill_image_rect(image, Rect2i(15, 12, 5, 122), Color(0.35, 0.22, 0.1, 1.0))
	_fill_image_rect(image, Rect2i(10, 16, 72, 6), Color(0.42, 0.28, 0.12, 1.0))
	_fill_image_rect(image, Rect2i(12, 130, 12, 5), Color(0.24, 0.14, 0.06, 1.0))

	var outline := banner_color.darkened(0.35)
	var banner_top := 22
	var banner_bottom := 130
	var accent_top := 84
	var accent_bottom := 101
	for y: int in range(banner_top, banner_bottom):
		for x: int in range(26, 82):
			if not _is_gonfalon_pixel(x, y):
				continue
			var color := banner_color
			if y >= accent_top and y <= accent_bottom:
				color = accent_color
			if _is_gonfalon_outline_pixel(x, y):
				color = outline
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)


func _is_gonfalon_pixel(x: int, y: int) -> bool:
	var left := 26
	var right := 81
	var top := 22
	var bottom := 129
	if x < left or x > right or y < top or y > bottom:
		return false
	var tail_start := 106
	if y < tail_start:
		return true
	var t := float(y - tail_start) / float(maxi(bottom - tail_start, 1))
	var notch_half_width := roundi(11.0 * t)
	var center := 54
	return abs(x - center) > notch_half_width


func _is_gonfalon_outline_pixel(x: int, y: int) -> bool:
	if not _is_gonfalon_pixel(x, y):
		return false
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _is_gonfalon_pixel(x + offset.x, y + offset.y):
			return true
	return false


func _fill_image_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


func _set_property_if_present(object: Object, property_name: StringName, value: Variant) -> void:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			object.set(String(property_name), value)
			return


func _clear_visuals() -> void:
	if _visual_root and is_instance_valid(_visual_root):
		if _visual_root.get_parent():
			_visual_root.get_parent().remove_child(_visual_root)
		_visual_root.free()
	_visual_root = null
	_flag_sprite = null
	_flag_border_sprite = null
	_last_flag_pixel_size = -1.0


func _emit_logistics_changed_if_ready() -> void:
	if _ready_to_emit:
		logistics_changed.emit(get_management_summary())
