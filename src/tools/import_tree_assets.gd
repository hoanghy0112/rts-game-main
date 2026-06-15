extends SceneTree

const PALETTE_PATH := "res://assets/models/forest/default_forest_palette.tres"
const SOURCE_DIR := "res://assets/models/forest/source/trees/imported-tree"
const PLANTS_DIR := "res://assets/models/forest/plants"
const PROXIES_DIR := "res://assets/models/forest/proxies"
const ATTRIBUTION_PATH := "res://assets/models/forest/ATTRIBUTION.md"

const CATEGORY_TREE := 0

const SOURCES := [
	{
		"source": "%s/tree.glb" % SOURCE_DIR,
		"id": "forest_tree_01",
		"display_name": "Forest Tree 01",
		"target_height": 5.8,
		"foliage_tint": Color(0.34, 0.68, 0.2, 1.0),
		"trunk_tint": Color(0.5, 0.32, 0.18, 1.0),
	},
	{
		"source": "%s/jabami_anime_tree_v3.glb" % SOURCE_DIR,
		"id": "forest_anime_tree_01",
		"display_name": "Forest Anime Tree 01",
		"target_height": 5.6,
	},
	{
		"source": "%s/tree_low-poly.glb" % SOURCE_DIR,
		"id": "forest_low_poly_tree_01",
		"display_name": "Forest Low Poly Tree 01",
		"target_height": 5.2,
	},
	{
		"source": "%s/lowpoly_tree_game_asset.glb" % SOURCE_DIR,
		"id": "forest_game_tree_01",
		"display_name": "Forest Game Tree 01",
		"target_height": 4.8,
	},
]


func _init() -> void:
	var errors: Array[String] = []
	_ensure_directory(PLANTS_DIR, errors)
	_ensure_directory(PROXIES_DIR, errors)

	var generated: Array[Dictionary] = []
	for config: Dictionary in SOURCES:
		_generate_from_source(config, generated, errors)

	if errors.is_empty():
		_update_palette(generated, errors)
		_update_attribution(generated, errors)

	if errors.is_empty():
		print("Imported %d tree models." % generated.size())
		quit(0)
	else:
		for error: String in errors:
			push_error(error)
		quit(1)


func _generate_from_source(config: Dictionary, generated: Array[Dictionary], errors: Array[String]) -> void:
	var source_path := str(config.get("source", ""))
	var source_root := _instantiate_source(source_path, errors)
	if not source_root:
		return

	var parts: Array[Dictionary] = []
	_collect_mesh_parts(source_root, Transform3D.IDENTITY, true, parts)
	if parts.is_empty():
		errors.append("No mesh parts found in %s." % source_path)
		source_root.free()
		return

	var bounds := _calculate_bounds(parts)
	if bounds.size.y <= 0.0001:
		errors.append("%s has invalid bounds." % source_path)
		source_root.free()
		return

	var plant_id := str(config.get("id", "forest_tree"))
	var root_name := plant_id.to_pascal_case()
	var scene_path := "%s/%s.tscn" % [PLANTS_DIR, plant_id]
	var proxy_path := "%s/%s_far_proxy.tscn" % [PROXIES_DIR, plant_id]
	var target_height := float(config.get("target_height", 5.0))
	var normalized_parts := _normalize_parts(parts, bounds, target_height)

	var save_error := _save_plant_scene(root_name, scene_path, normalized_parts, config)
	if save_error != OK:
		errors.append("Could not save %s: %s." % [scene_path, error_string(save_error)])
		source_root.free()
		return

	var canopy_color := _sample_color_from_parts(parts, Color(0.18, 0.42, 0.16, 1.0))
	save_error = _save_tree_proxy_scene("%sFarProxy" % root_name, proxy_path, target_height, bounds.size, canopy_color)
	if save_error != OK:
		errors.append("Could not save %s: %s." % [proxy_path, error_string(save_error)])
		source_root.free()
		return

	generated.append({
		"id": plant_id,
		"display_name": str(config.get("display_name", root_name)),
		"scene_path": scene_path,
		"proxy_path": proxy_path,
		"source_path": source_path,
	})
	source_root.free()


func _instantiate_source(source_path: String, errors: Array[String]) -> Node:
	var resource := ResourceLoader.load(source_path)
	if not resource:
		errors.append("Could not load source model: %s." % source_path)
		return null

	if resource is PackedScene:
		return (resource as PackedScene).instantiate()

	if resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = resource as Mesh
		return mesh_instance

	errors.append("Unsupported source resource type for %s: %s." % [source_path, resource.get_class()])
	return null


func _collect_mesh_parts(node: Node, parent_transform: Transform3D, is_root: bool, parts: Array[Dictionary]) -> void:
	var current_transform := parent_transform
	if node is Node3D and not is_root:
		current_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			parts.append({
				"mesh": mesh_instance.mesh,
				"transform": current_transform,
				"material_override": mesh_instance.material_override,
				"cast_shadow": mesh_instance.cast_shadow,
				"source_name": "%s %s" % [mesh_instance.name, mesh_instance.mesh.resource_name],
			})

	for child: Node in node.get_children():
		_collect_mesh_parts(child, current_transform, false, parts)


func _calculate_bounds(parts: Array[Dictionary]) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	for part: Dictionary in parts:
		var mesh := part.get("mesh") as Mesh
		if not mesh:
			continue
		var part_bounds := _transform_aabb(mesh.get_aabb(), part.get("transform", Transform3D.IDENTITY))
		if not has_bounds:
			bounds = part_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(part_bounds)
	return bounds


func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var points: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]

	var min_point: Vector3 = transform * points[0]
	var max_point: Vector3 = min_point
	for index: int in range(1, points.size()):
		var point: Vector3 = transform * points[index]
		min_point = min_point.min(point)
		max_point = max_point.max(point)

	return AABB(min_point, max_point - min_point)


func _normalize_parts(parts: Array[Dictionary], bounds: AABB, target_height: float) -> Array[Dictionary]:
	var scale := target_height / bounds.size.y
	var xz_center := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y,
		bounds.position.z + bounds.size.z * 0.5
	)

	var normalized: Array[Dictionary] = []
	for part: Dictionary in parts:
		var transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		transform.origin -= xz_center
		transform.origin *= scale
		transform.basis = transform.basis.scaled(Vector3.ONE * scale)
		normalized.append({
			"mesh": part.get("mesh"),
			"transform": transform,
			"material_override": part.get("material_override"),
			"cast_shadow": part.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON),
			"source_name": part.get("source_name", ""),
		})
	return normalized


func _save_plant_scene(
	root_name: String,
	scene_path: String,
	parts: Array[Dictionary],
	config: Dictionary
) -> Error:
	var root := Node3D.new()
	root.name = root_name

	var combined_mesh := ArrayMesh.new()
	combined_mesh.resource_name = "%s_Mesh" % root_name
	var cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	for index: int in range(parts.size()):
		var part := parts[index]
		var mesh := part.get("mesh") as Mesh
		if not mesh:
			continue

		var baked_mesh := _bake_mesh_transform(mesh, part.get("transform", Transform3D.IDENTITY), "%s_Part_%02d" % [root_name, index])
		if not baked_mesh:
			continue
		var material_override := part.get("material_override") as Material
		if not material_override and not _mesh_has_usable_material(baked_mesh):
			material_override = _make_fallback_material(str(part.get("source_name", "")), index)
		_append_mesh_surfaces(combined_mesh, baked_mesh, material_override, str(part.get("source_name", "")), config)
		cast_shadow = int(part.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))

	if combined_mesh.get_surface_count() == 0:
		root.free()
		return ERR_CANT_CREATE

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlantMesh"
	mesh_instance.mesh = combined_mesh
	mesh_instance.cast_shadow = cast_shadow
	root.add_child(mesh_instance)
	mesh_instance.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return pack_error

	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	return save_error


func _bake_mesh_transform(mesh: Mesh, transform: Transform3D, resource_name: String) -> ArrayMesh:
	if not (mesh is ArrayMesh):
		return null

	var source_mesh := mesh as ArrayMesh
	var baked_mesh := ArrayMesh.new()
	baked_mesh.resource_name = resource_name
	var normal_basis := transform.basis.inverse().transposed()

	for surface_index: int in range(source_mesh.get_surface_count()):
		if source_mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue

		var source_arrays := source_mesh.surface_get_arrays(surface_index)
		if source_arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		if not (source_arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			continue

		var vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)

		var baked_vertices := PackedVector3Array()
		baked_vertices.resize(vertices.size())
		for vertex_index: int in range(vertices.size()):
			baked_vertices[vertex_index] = transform * vertices[vertex_index]
		arrays[Mesh.ARRAY_VERTEX] = baked_vertices

		if source_arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]
			if normals.size() == vertices.size():
				var baked_normals := PackedVector3Array()
				baked_normals.resize(normals.size())
				for normal_index: int in range(normals.size()):
					baked_normals[normal_index] = (normal_basis * normals[normal_index]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = baked_normals

		if source_arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var tangents: PackedFloat32Array = source_arrays[Mesh.ARRAY_TANGENT]
			if tangents.size() >= vertices.size() * 4:
				var baked_tangents := PackedFloat32Array()
				baked_tangents.resize(tangents.size())
				for tangent_index: int in range(vertices.size()):
					var offset := tangent_index * 4
					var tangent := Vector3(tangents[offset], tangents[offset + 1], tangents[offset + 2])
					tangent = (normal_basis * tangent).normalized()
					baked_tangents[offset] = tangent.x
					baked_tangents[offset + 1] = tangent.y
					baked_tangents[offset + 2] = tangent.z
					baked_tangents[offset + 3] = tangents[offset + 3]
				arrays[Mesh.ARRAY_TANGENT] = baked_tangents

		for array_index: int in [
			Mesh.ARRAY_COLOR,
			Mesh.ARRAY_TEX_UV,
			Mesh.ARRAY_TEX_UV2,
			Mesh.ARRAY_BONES,
			Mesh.ARRAY_WEIGHTS,
			Mesh.ARRAY_INDEX,
		]:
			arrays[array_index] = source_arrays[array_index]

		var surface_count_before := baked_mesh.get_surface_count()
		baked_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		if baked_mesh.get_surface_count() == surface_count_before:
			continue
		var baked_surface_index := baked_mesh.get_surface_count() - 1
		baked_mesh.surface_set_material(baked_surface_index, source_mesh.surface_get_material(surface_index))
		var surface_name := source_mesh.surface_get_name(surface_index)
		if not surface_name.is_empty():
			baked_mesh.surface_set_name(baked_surface_index, surface_name)

	if baked_mesh.get_surface_count() == 0:
		return null
	return baked_mesh


func _append_mesh_surfaces(
	combined_mesh: ArrayMesh,
	source_mesh: ArrayMesh,
	material_override: Material,
	source_name: String,
	config: Dictionary
) -> void:
	for surface_index: int in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var surface_count_before := combined_mesh.get_surface_count()
		combined_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		if combined_mesh.get_surface_count() == surface_count_before:
			continue

		var combined_surface_index := combined_mesh.get_surface_count() - 1
		var surface_name := source_mesh.surface_get_name(surface_index)
		var material := material_override
		if not material:
			material = source_mesh.surface_get_material(surface_index)
		if material:
			material = _apply_material_tint(material, "%s %s" % [source_name, surface_name], config)
			combined_mesh.surface_set_material(combined_surface_index, material)

		if not surface_name.is_empty():
			combined_mesh.surface_set_name(combined_surface_index, surface_name)


func _apply_material_tint(material: Material, material_name: String, config: Dictionary) -> Material:
	var tint: Variant = _get_material_tint(material_name, config)
	if tint == null or not (material is StandardMaterial3D):
		return material

	var tinted := (material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
	tinted.albedo_color = tint as Color
	if material.resource_name.is_empty():
		tinted.resource_name = material_name.strip_edges()
	return tinted


func _get_material_tint(material_name: String, config: Dictionary) -> Variant:
	var lower_name := material_name.to_lower()
	if (
		(lower_name.contains("trunk") or lower_name.contains("bark") or lower_name.contains("wood"))
		and config.has("trunk_tint")
	):
		return config.get("trunk_tint")
	if (
		(lower_name.contains("branch") or lower_name.contains("leaf") or lower_name.contains("leav") or lower_name.contains("canopy"))
		and config.has("foliage_tint")
	):
		return config.get("foliage_tint")
	return null


func _mesh_has_usable_material(mesh: Mesh) -> bool:
	if not mesh:
		return false
	for surface_index: int in range(mesh.get_surface_count()):
		if _material_is_usable(mesh.surface_get_material(surface_index)):
			return true
	return false


func _material_is_usable(material: Material) -> bool:
	if not material:
		return false
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if standard.albedo_texture:
			return true
		var color := standard.albedo_color
		if color.a <= 0.05:
			return false
		var near_default_white := (
			absf(color.r - 1.0) < 0.025
			and absf(color.g - 1.0) < 0.025
			and absf(color.b - 1.0) < 0.025
		)
		return not near_default_white
	return true


func _make_fallback_material(source_name: String, index: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Forest Tree Fallback %02d" % index
	material.roughness = 0.9
	material.backlight_enabled = true
	material.backlight = Color(0.14, 0.22, 0.1, 1.0)

	var lower_name := source_name.to_lower()
	var base_color := Color(0.24, 0.46, 0.16, 1.0)
	if lower_name.contains("trunk") or lower_name.contains("bark") or lower_name.contains("wood") or lower_name.contains("stem"):
		base_color = Color(0.34, 0.22, 0.12, 1.0)

	var variation := float(absi(_hash_string("%s:%d" % [source_name, index])) % 17) / 100.0
	material.albedo_color = base_color.lightened(variation)
	return material


func _hash_string(value: String) -> int:
	var mixed := int(2166136261)
	for index: int in range(value.length()):
		mixed = int((mixed ^ value.unicode_at(index)) * 16777619)
	return mixed


func _save_tree_proxy_scene(root_name: String, scene_path: String, height: float, source_size: Vector3, canopy_color: Color) -> Error:
	var root := Node3D.new()
	root.name = root_name

	var trunk_height := height * 0.44
	var canopy_radius := clampf(height * 0.23, 0.7, 2.2)
	var source_width := maxf(source_size.x, source_size.z)
	if source_width > 0.001:
		canopy_radius = clampf(source_width * (height / maxf(source_size.y, 0.001)) * 0.38, height * 0.16, height * 0.32)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = height * 0.035
	trunk_mesh.bottom_radius = height * 0.055
	trunk_mesh.height = trunk_height
	trunk_mesh.radial_segments = 7
	trunk_mesh.rings = 1

	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = canopy_radius
	canopy_mesh.height = canopy_radius * 1.8
	canopy_mesh.radial_segments = 12
	canopy_mesh.rings = 6

	var trunk_material := StandardMaterial3D.new()
	trunk_material.resource_name = "Proxy Trunk"
	trunk_material.albedo_color = Color(0.35, 0.22, 0.11, 1.0)
	trunk_material.roughness = 0.92

	var canopy_material := StandardMaterial3D.new()
	canopy_material.resource_name = "Proxy Canopy"
	canopy_material.albedo_color = canopy_color
	canopy_material.roughness = 0.95
	canopy_material.backlight_enabled = true
	canopy_material.backlight = Color(0.18, 0.28, 0.12, 1.0)

	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_material
	trunk.position = Vector3(0.0, trunk_height * 0.5, 0.0)
	root.add_child(trunk)
	trunk.owner = root

	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = canopy_mesh
	canopy.material_override = canopy_material
	canopy.position = Vector3(0.0, trunk_height + canopy_radius * 0.55, 0.0)
	canopy.scale = Vector3(1.08, 0.86, 1.08)
	root.add_child(canopy)
	canopy.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return pack_error

	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	return save_error


func _sample_color_from_parts(parts: Array[Dictionary], fallback: Color) -> Color:
	for part: Dictionary in parts:
		var material := part.get("material_override") as StandardMaterial3D
		if material and material.albedo_color.g >= material.albedo_color.r:
			return material.albedo_color
	return fallback


func _update_palette(generated: Array[Dictionary], errors: Array[String]) -> void:
	var palette := ResourceLoader.load(PALETTE_PATH) as ForestPaletteData
	var plant_script := ResourceLoader.load("res://addons/forest_brush/forest_plant_type_data.gd") as Script
	if not palette or not plant_script:
		errors.append("Could not load forest palette resources.")
		return

	var plant_types := palette.plant_types.duplicate()
	for plant: Dictionary in generated:
		var plant_type := _find_plant_type(plant_types, StringName(str(plant.get("id", ""))))
		if not plant_type:
			plant_type = plant_script.new() as ForestPlantTypeData
			plant_types.append(plant_type)
		plant_type.id = StringName(str(plant.get("id", "")))
		plant_type.display_name = str(plant.get("display_name", "Forest Tree"))
		plant_type.description = "Tree model imported from %s." % str(plant.get("source_path", ""))
		plant_type.category = CATEGORY_TREE
		plant_type.scene = ResourceLoader.load(str(plant.get("scene_path", ""))) as PackedScene
		plant_type.lod2_scene = ResourceLoader.load(str(plant.get("proxy_path", ""))) as PackedScene
		_apply_tree_defaults(plant_type)

	palette.plant_types = plant_types
	var save_error := ResourceSaver.save(palette, PALETTE_PATH)
	if save_error != OK:
		errors.append("Could not save %s: %s." % [PALETTE_PATH, error_string(save_error)])


func _find_plant_type(plant_types: Array[ForestPlantTypeData], plant_id: StringName) -> ForestPlantTypeData:
	for plant_type: ForestPlantTypeData in plant_types:
		if plant_type and plant_type.id == plant_id:
			return plant_type
	return null


func _apply_tree_defaults(plant_type: Resource) -> void:
	plant_type.set("default_selected", true)
	plant_type.set("density_per_cell", 0.075)
	plant_type.set("density_jitter", 0.35)
	plant_type.set("min_scale", 0.85)
	plant_type.set("max_scale", 1.2)
	plant_type.set("cell_edge_margin", 0.18)
	plant_type.set("near_visible_distance", 120.0)
	plant_type.set("mid_visible_distance", 300.0)
	plant_type.set("far_visible_distance", 920.0)
	plant_type.set("mid_keep_ratio", 0.95)
	plant_type.set("far_keep_ratio", 0.55)
	plant_type.set("far_scale_multiplier", 1.28)
	plant_type.set("terrain3d_mesh_id", -1)


func _update_attribution(generated: Array[Dictionary], errors: Array[String]) -> void:
	var absolute_path := ProjectSettings.globalize_path(ATTRIBUTION_PATH)
	var text := FileAccess.get_file_as_string(absolute_path)
	if text.is_empty():
		text = "# Forest Assets\n"

	var lines := text.rstrip("\n").split("\n")
	if not text.contains("## Imported Tree Sources"):
		lines.append("")
		lines.append("## Imported Tree Sources")
		lines.append("")

	for plant: Dictionary in generated:
		var source_line := "- `%s`" % str(plant.get("source_path", ""))
		if not text.contains(source_line):
			lines.append(source_line)

	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if not file:
		errors.append("Could not write %s." % ATTRIBUTION_PATH)
		return
	file.store_string("\n".join(lines) + "\n")


func _ensure_directory(path: String, errors: Array[String]) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if make_error != OK:
		errors.append("Could not create %s: %s." % [path, error_string(make_error)])
