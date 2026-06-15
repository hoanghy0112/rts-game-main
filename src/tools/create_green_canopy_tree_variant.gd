@tool
extends SceneTree

const SOURCE_MESH_PATH := "res://assets/models/forest/plants/forest_canopy_tree_01_mesh.res"
const TARGET_MESH_PATH := "res://assets/models/forest/plants/forest_canopy_tree_green_01_mesh.res"
const TARGET_SCENE_PATH := "res://assets/models/forest/plants/forest_canopy_tree_green_01.tscn"
const TARGET_PROXY_PATH := "res://assets/models/forest/proxies/forest_canopy_tree_green_01_far_proxy.tscn"

const GREEN_TINT := Color(0.86, 1.08, 0.82, 1.0)
const PROXY_CANOPY_COLOR := Color(0.16, 0.48, 0.15, 1.0)
const PROXY_BACKLIGHT_COLOR := Color(0.18, 0.32, 0.13, 1.0)
const PROXY_SOFT_BACKLIGHT_COLOR := Color(0.20, 0.36, 0.14, 1.0)


func _init() -> void:
	var errors: Array[String] = []
	var source_mesh := ResourceLoader.load(SOURCE_MESH_PATH) as ArrayMesh
	if not source_mesh:
		_fail("Could not load source mesh: %s." % SOURCE_MESH_PATH)
		return

	var variant_mesh := source_mesh.duplicate(true) as ArrayMesh
	if not variant_mesh:
		_fail("Could not duplicate source mesh: %s." % SOURCE_MESH_PATH)
		return

	variant_mesh.resource_name = "ForestCanopyTreeGreen01_Mesh"
	var tinted_surface_count := _tint_foliage_surfaces(variant_mesh)
	if tinted_surface_count == 0:
		errors.append("No foliage surfaces were tinted in %s." % SOURCE_MESH_PATH)

	var mesh_error := ResourceSaver.save(variant_mesh, TARGET_MESH_PATH)
	if mesh_error != OK:
		errors.append("Could not save %s: %s." % [TARGET_MESH_PATH, error_string(mesh_error)])

	var saved_mesh := ResourceLoader.load(TARGET_MESH_PATH) as Mesh
	if not saved_mesh:
		errors.append("Could not reload %s." % TARGET_MESH_PATH)
	else:
		var scene_error := _save_tree_scene(saved_mesh)
		if scene_error != OK:
			errors.append("Could not save %s: %s." % [TARGET_SCENE_PATH, error_string(scene_error)])

	var proxy_error := _save_proxy_scene()
	if proxy_error != OK:
		errors.append("Could not save %s: %s." % [TARGET_PROXY_PATH, error_string(proxy_error)])

	if errors.is_empty():
		print("Created greener canopy tree variant.")
		quit(0)
	else:
		for error: String in errors:
			push_error(error)
		quit(1)


func _tint_foliage_surfaces(mesh: ArrayMesh) -> int:
	var tinted_count := 0
	for surface_index: int in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface_index)
		if not _should_tint_surface(mesh, surface_index, material):
			continue

		var tinted_material := material.duplicate(true) as Material if material else null
		if not tinted_material:
			continue

		if tinted_material is StandardMaterial3D:
			var standard_material := tinted_material as StandardMaterial3D
			standard_material.resource_name = "%s Greener" % _material_display_name(material, surface_index)
			standard_material.albedo_color = _tinted_color(standard_material.albedo_color)
			if standard_material.backlight_enabled:
				standard_material.backlight = _tinted_color(standard_material.backlight)
		mesh.surface_set_material(surface_index, tinted_material)
		tinted_count += 1
	return tinted_count


func _should_tint_surface(mesh: ArrayMesh, surface_index: int, material: Material) -> bool:
	var surface_name := mesh.surface_get_name(surface_index).to_lower()
	var material_name := _material_display_name(material, surface_index).to_lower()
	for bark_token: String in ["bark", "trunk", "wood", "stem"]:
		if surface_name.contains(bark_token) or material_name.contains(bark_token):
			return false
	return true


func _material_display_name(material: Material, surface_index: int) -> String:
	if material and not material.resource_name.is_empty():
		return material.resource_name
	return "Surface %02d" % surface_index


func _tinted_color(color: Color) -> Color:
	return Color(
		clampf(color.r * GREEN_TINT.r, 0.0, 1.5),
		clampf(color.g * GREEN_TINT.g, 0.0, 1.5),
		clampf(color.b * GREEN_TINT.b, 0.0, 1.5),
		color.a
	)


func _save_tree_scene(mesh: Mesh) -> Error:
	var root := Node3D.new()
	root.name = "ForestCanopyTreeGreen01"

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlantMesh"
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	mesh_instance.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return pack_error

	var save_error := ResourceSaver.save(packed, TARGET_SCENE_PATH)
	root.free()
	return save_error


func _save_proxy_scene() -> Error:
	var root := Node3D.new()
	root.name = "ForestCanopyTreeGreen01FarProxy"

	var trunk_material := StandardMaterial3D.new()
	trunk_material.resource_name = "Proxy Trunk"
	trunk_material.albedo_color = Color(0.35, 0.22, 0.11, 1.0)
	trunk_material.roughness = 0.92

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.203
	trunk_mesh.bottom_radius = 0.319
	trunk_mesh.height = 2.552
	trunk_mesh.radial_segments = 7
	trunk_mesh.rings = 1

	var canopy_material := StandardMaterial3D.new()
	canopy_material.resource_name = "Proxy Canopy"
	canopy_material.albedo_color = PROXY_CANOPY_COLOR
	canopy_material.roughness = 0.95
	canopy_material.backlight_enabled = true
	canopy_material.backlight = PROXY_BACKLIGHT_COLOR

	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.856
	canopy_mesh.height = 3.3408
	canopy_mesh.radial_segments = 12
	canopy_mesh.rings = 6

	var soft_canopy_material := StandardMaterial3D.new()
	soft_canopy_material.resource_name = "Proxy Soft Canopy"
	soft_canopy_material.albedo_color = Color(
		PROXY_CANOPY_COLOR.r,
		PROXY_CANOPY_COLOR.g,
		PROXY_CANOPY_COLOR.b,
		0.34
	)
	soft_canopy_material.roughness = 0.95
	soft_canopy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	soft_canopy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	soft_canopy_material.backlight_enabled = true
	soft_canopy_material.backlight = PROXY_SOFT_BACKLIGHT_COLOR

	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.position = Vector3(0.0, 1.276, 0.0)
	trunk.material_override = trunk_material
	trunk.mesh = trunk_mesh
	root.add_child(trunk)
	trunk.owner = root

	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.position = Vector3(0.0, 3.5728, 0.0)
	canopy.scale = Vector3(1.08, 0.86, 1.08)
	canopy.material_override = canopy_material
	canopy.mesh = canopy_mesh
	root.add_child(canopy)
	canopy.owner = root

	var soft_canopy := MeshInstance3D.new()
	soft_canopy.name = "SoftCanopy"
	soft_canopy.position = Vector3(0.0, 3.5728, 0.0)
	soft_canopy.scale = Vector3(1.25, 0.98, 1.25)
	soft_canopy.material_override = soft_canopy_material
	soft_canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	soft_canopy.mesh = canopy_mesh
	root.add_child(soft_canopy)
	soft_canopy.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return pack_error

	var save_error := ResourceSaver.save(packed, TARGET_PROXY_PATH)
	root.free()
	return save_error


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
