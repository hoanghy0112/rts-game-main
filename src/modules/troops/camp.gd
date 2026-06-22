extends Node3D
class_name Camp

signal selected_changed(selected: bool)
signal logistics_changed(summary: Dictionary)

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_CAMP_TYPE := &"camp"
const CAMP_CLICK_PROXY_NAME := "CampClickProxy"
const CAMP_FLAG_NAME := "CampFlag"
const FLAG_BORDER_NODE_NAME := "CampFlagHoverBorder"
const RANGE_RING_NAME := "CampRange"

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
@export_range(1.0, 512.0, 0.5, "or_greater") var camp_range_m: float = 18.0:
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
@export_flags_3d_physics var selection_collision_layer: int = 1 << 5:
	set(value):
		selection_collision_layer = value
		if is_inside_tree():
			_rebuild_visuals()
@export_range(0.0, 8.0, 0.01, "or_greater") var range_surface_offset: float = 0.46

var _selected := false
var _hovered := false
var _visual_root: Node3D
var _ready_to_emit := false


func _ready() -> void:
	add_to_group(&"camps")
	_ready_to_emit = true
	_rebuild_visuals()
	_emit_logistics_changed_if_ready()


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
	return flag.global_position if flag else global_position + Vector3(0.0, 6.0 * camp_building_scale, 0.0)


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

	var ring := MeshInstance3D.new()
	ring.name = RANGE_RING_NAME
	ring.mesh = _build_ring_mesh(camp_range_m)
	ring.position.y = range_surface_offset
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ring.material_override = _make_range_material()
	_visual_root.add_child(ring)

	var s := maxf(camp_building_scale, 0.1)
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

	_add_flag_border(flag, s)
	_add_selection_proxy(s)
	_update_hover_visuals()


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


func _create_flag(flag_name: String, banner_color: Color, accent_color: Color, s: float) -> Node3D:
	var flag := Node3D.new()
	flag.name = flag_name
	var pole := _make_cylinder("Pole", 0.045 * s, 2.65 * s, Color(0.42, 0.28, 0.12, 1.0), 8)
	pole.position = Vector3(0.0, 1.32 * s, 0.0)
	pole.material_override = _make_flag_material(Color(0.42, 0.28, 0.12, 1.0))
	flag.add_child(pole)
	var banner := _make_box("Banner", Vector3(1.25, 0.76, 0.045) * s, banner_color)
	banner.position = Vector3(0.63 * s, 2.13 * s, 0.0)
	banner.material_override = _make_flag_material(banner_color)
	flag.add_child(banner)
	var stripe := _make_box("TeamStripe", Vector3(1.28, 0.18, 0.055) * s, accent_color)
	stripe.position = banner.position + Vector3(0.0, -0.25 * s, 0.03 * s)
	stripe.material_override = _make_flag_material(accent_color)
	flag.add_child(stripe)
	return flag


func _add_flag_border(flag: Node3D, s: float) -> void:
	var color := _get_hover_color()
	var center := Vector3(0.63 * s, 2.13 * s, 0.06 * s)
	var width := 1.25 * s
	var height := 0.76 * s
	var t := maxf(0.055 * s, 0.025)
	for data: Dictionary in [
		{"name": "Top", "size": Vector3(width + t * 2.0, t, t), "pos": center + Vector3(0.0, height * 0.5 + t * 0.5, 0.0)},
		{"name": "Bottom", "size": Vector3(width + t * 2.0, t, t), "pos": center + Vector3(0.0, -height * 0.5 - t * 0.5, 0.0)},
		{"name": "Left", "size": Vector3(t, height, t), "pos": center + Vector3(-width * 0.5 - t * 0.5, 0.0, 0.0)},
		{"name": "Right", "size": Vector3(t, height, t), "pos": center + Vector3(width * 0.5 + t * 0.5, 0.0, 0.0)},
	]:
		var strip := _make_box("%s_%s" % [FLAG_BORDER_NODE_NAME, String(data["name"])], data["size"] as Vector3, color)
		strip.position = data["pos"] as Vector3
		strip.visible = false
		strip.material_override = _make_hover_material(color)
		flag.add_child(strip)


func _add_selection_proxy(s: float) -> void:
	var proxy := StaticBody3D.new()
	proxy.name = CAMP_CLICK_PROXY_NAME
	proxy.collision_layer = selection_collision_layer
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_CAMP_TYPE)
	proxy.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(5.25 * s, 2.0)
	cylinder.height = 4.6 * s
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.1 * s, 0.0)
	proxy.add_child(shape)
	_visual_root.add_child(proxy)


func _update_hover_visuals() -> void:
	var active := _hovered or _selected
	var color := _get_hover_color()
	for node: Node in find_children("%s*" % FLAG_BORDER_NODE_NAME, "MeshInstance3D", true, false):
		var strip := node as MeshInstance3D
		strip.visible = active
		strip.material_override = _make_hover_material(color)


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
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 21
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 0.82, 0.28, 0.32)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.18, 1.0)
	material.emission_energy_multiplier = 0.14
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


func _clear_visuals() -> void:
	if _visual_root and is_instance_valid(_visual_root):
		if _visual_root.get_parent():
			_visual_root.get_parent().remove_child(_visual_root)
		_visual_root.free()
	_visual_root = null


func _emit_logistics_changed_if_ready() -> void:
	if _ready_to_emit:
		logistics_changed.emit(get_management_summary())
