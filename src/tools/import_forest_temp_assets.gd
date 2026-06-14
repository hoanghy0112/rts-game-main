extends SceneTree

const PALETTE_PATH := "res://assets/models/forest/default_forest_palette.tres"
const TERRAIN_ASSETS_PATH := "res://assets/resources/assets.tres"
const PLANTS_DIR := "res://assets/models/forest/plants"
const PROXIES_DIR := "res://assets/models/forest/proxies"
const ATTRIBUTION_PATH := "res://assets/models/forest/ATTRIBUTION.md"

const CATEGORY_TREE := 0
const CATEGORY_BAMBOO := 2
const CATEGORY_FERN := 4
const CATEGORY_GRASS := 5

const SOURCES := [
	{
		"source": "res://assets/models/forest/source/trees/canopy-tree/canopy_tree.glb",
		"display_prefix": "Forest Canopy Tree",
		"slug_prefix": "canopy_tree",
		"category": CATEGORY_TREE,
		"target_height": 5.8,
		"split_mode": "single",
	},
	{
		"source": "res://assets/models/forest/source/trees/highland-pine/highland_pine.glb",
		"display_prefix": "Forest Highland Pine",
		"slug_prefix": "highland_pine",
		"category": CATEGORY_TREE,
		"target_height": 5.6,
		"split_mode": "single",
	},
	{
		"source": "res://assets/models/forest/source/grass/flower-grass/flower_grass.glb",
		"display_prefix": "Forest Flower Grass",
		"slug_prefix": "flower_grass",
		"category": CATEGORY_GRASS,
		"target_height": 0.72,
		"split_mode": "single",
	},
]


func _init() -> void:
	var errors: Array[String] = []
	_ensure_directory(PLANTS_DIR, errors)
	_ensure_directory(PROXIES_DIR, errors)

	var generated: Array[Dictionary] = []
	var name_counts: Dictionary = {}
	for config: Dictionary in SOURCES:
		_generate_from_source(config, name_counts, generated, errors)

	generated.sort_custom(_sort_by_scene_path)
	var terrain_ids := _rewrite_terrain_assets(generated, errors)
	_rewrite_palette(generated, terrain_ids, errors)
	_rewrite_attribution(generated, errors)

	if errors.is_empty():
		print("Generated %d forest plant scenes." % generated.size())
		quit(0)
	else:
		for error: String in errors:
			push_error(error)
		quit(1)


func _generate_from_source(
	config: Dictionary,
	name_counts: Dictionary,
	generated: Array[Dictionary],
	errors: Array[String]
) -> void:
	var source_path := str(config.get("source", ""))
	var root := _instantiate_source(source_path, errors)
	if not root:
		return

	var candidates := _get_split_candidates(root, str(config.get("split_mode", "single")))
	if candidates.is_empty():
		errors.append("No mesh candidates found in %s." % source_path)
		root.free()
		return

	for candidate: Dictionary in candidates:
		var parts: Array[Dictionary] = []
		_collect_mesh_parts(
			candidate.get("node") as Node,
			Transform3D.IDENTITY,
			not bool(candidate.get("include_root_transform", false)),
			parts
		)
		if parts.is_empty():
			continue

		var display_prefix := str(config.get("display_prefix", "Forest Plant"))
		var display_index := int(name_counts.get(display_prefix, 0)) + 1
		name_counts[display_prefix] = display_index
		var display_name := "%s %02d" % [display_prefix, display_index]
		var slug := "forest_%s_%02d" % [str(config.get("slug_prefix", "plant")), display_index]
		var scene_path := "%s/%s.tscn" % [PLANTS_DIR, slug]
		var target_height := float(config.get("target_height", 1.0))
		var category := int(config.get("category", CATEGORY_TREE))

		var bounds := _calculate_bounds(parts)
		if bounds.size.y <= 0.0001:
			errors.append("%s has invalid bounds." % source_path)
			continue

		var normalized_parts := _normalize_parts(parts, bounds, target_height)
		var save_error := _save_plant_scene(slug.to_pascal_case(), scene_path, normalized_parts, category)
		if save_error != OK:
			errors.append("Could not save %s: %s." % [scene_path, error_string(save_error)])
			continue

		var proxy_path := ""
		if category == CATEGORY_TREE:
			var canopy_color := _sample_color_from_texture(
				str(config.get("canopy_texture", "")),
				_sample_color_from_parts(parts, Color(0.18, 0.42, 0.16, 1.0))
			)
			proxy_path = "%s/%s_far_proxy.tscn" % [PROXIES_DIR, slug]
			save_error = _save_tree_proxy_scene(
				"%sFarProxy" % slug.to_pascal_case(),
				proxy_path,
				target_height,
				bounds.size,
				canopy_color
			)
			if save_error != OK:
				errors.append("Could not save %s: %s." % [proxy_path, error_string(save_error)])
				proxy_path = ""

		generated.append({
			"id": slug,
			"display_name": display_name,
			"category": category,
			"scene_path": scene_path,
			"proxy_path": proxy_path,
			"source_path": source_path,
			"include_in_palette": bool(config.get("include_in_palette", true)),
			"include_in_terrain3d": bool(config.get("include_in_terrain3d", true)),
		})

	root.free()


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


func _get_split_candidates(root: Node, split_mode: String) -> Array[Dictionary]:
	if split_mode == "single":
		return [{
			"node": root,
			"include_root_transform": false,
		}]

	var split_roots := _find_top_level_mesh_roots(root)
	if split_roots.is_empty():
		return [{
			"node": root,
			"include_root_transform": false,
		}]

	var candidates: Array[Dictionary] = []
	for split_root: Node in split_roots:
		candidates.append({
			"node": split_root,
			"include_root_transform": true,
		})
	return candidates


func _find_top_level_mesh_roots(root: Node) -> Array[Node]:
	var current := root
	while true:
		var children := _children_with_mesh_descendants(current)
		if children.size() == 1 and not (children[0] is MeshInstance3D):
			current = children[0]
			continue
		return children
	return []


func _children_with_mesh_descendants(node: Node) -> Array[Node]:
	var children: Array[Node] = []
	for child: Node in node.get_children():
		if _has_mesh_descendant(child):
			children.append(child)
	return children


func _has_mesh_descendant(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return true
	for child: Node in node.get_children():
		if _has_mesh_descendant(child):
			return true
	return false


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


func _save_plant_scene(root_name: String, scene_path: String, parts: Array[Dictionary], category: int) -> Error:
	var root := Node3D.new()
	root.name = root_name

	var combined_mesh := ArrayMesh.new()
	combined_mesh.resource_name = "%s_Mesh" % root_name
	var cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _category_disables_shadows(category) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
			material_override = _make_fallback_material(category, str(part.get("source_name", "")), index)
		_append_mesh_surfaces(combined_mesh, baked_mesh, material_override)
		if not _category_disables_shadows(category):
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


func _append_mesh_surfaces(combined_mesh: ArrayMesh, source_mesh: ArrayMesh, material_override: Material) -> void:
	for surface_index: int in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var surface_count_before := combined_mesh.get_surface_count()
		combined_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		if combined_mesh.get_surface_count() == surface_count_before:
			continue

		var combined_surface_index := combined_mesh.get_surface_count() - 1
		var material := material_override
		if not material:
			material = source_mesh.surface_get_material(surface_index)
		if material:
			combined_mesh.surface_set_material(combined_surface_index, material)

		var surface_name := source_mesh.surface_get_name(surface_index)
		if not surface_name.is_empty():
			combined_mesh.surface_set_name(combined_surface_index, surface_name)


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


func _make_fallback_material(category: int, source_name: String, index: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Forest Fallback %02d" % index
	material.roughness = 0.9
	material.backlight_enabled = true
	material.backlight = Color(0.14, 0.22, 0.1, 1.0)

	var lower_name := source_name.to_lower()
	var base_color := Color(0.24, 0.46, 0.16, 1.0)
	if lower_name.contains("trunk") or lower_name.contains("bark") or lower_name.contains("wood") or lower_name.contains("stem"):
		base_color = Color(0.34, 0.22, 0.12, 1.0)
	elif category == CATEGORY_BAMBOO:
		base_color = Color(0.34, 0.48, 0.20, 1.0)
	elif category == CATEGORY_FERN:
		base_color = Color(0.13, 0.42, 0.18, 1.0)
	elif category == CATEGORY_GRASS:
		base_color = Color(0.32, 0.55, 0.18, 1.0)

	var variation := float(absi(_hash_string("%s:%d" % [source_name, index])) % 17) / 100.0
	material.albedo_color = base_color.lightened(variation)
	if category == CATEGORY_GRASS or category == CATEGORY_FERN:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
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

	var outer_material := StandardMaterial3D.new()
	outer_material.resource_name = "Proxy Soft Canopy"
	outer_material.albedo_color = Color(canopy_color.r, canopy_color.g, canopy_color.b, 0.34)
	outer_material.roughness = 1.0
	outer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	outer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	outer_material.backlight_enabled = true
	outer_material.backlight = Color(0.22, 0.32, 0.15, 1.0)

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

	var soft_canopy := MeshInstance3D.new()
	soft_canopy.name = "SoftCanopy"
	soft_canopy.mesh = canopy_mesh
	soft_canopy.material_override = outer_material
	soft_canopy.position = canopy.position
	soft_canopy.scale = Vector3(1.25, 0.98, 1.25)
	soft_canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(soft_canopy)
	soft_canopy.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return pack_error

	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	return save_error


func _rewrite_terrain_assets(generated: Array[Dictionary], errors: Array[String]) -> Dictionary:
	var file := FileAccess.open(TERRAIN_ASSETS_PATH, FileAccess.READ)
	if not file:
		errors.append("Could not read Terrain3D assets: %s." % TERRAIN_ASSETS_PATH)
		return {}
	var text := file.get_as_text()
	var parsed := _parse_terrain_assets_text(text)
	var used_ids: Dictionary = {}
	var mesh_subresources: Array[String] = []
	for block: Array[String] in parsed.get("kept_blocks", []):
		if _is_terrain_mesh_asset_block(block):
			var block_id := _subresource_id_from_header(block[0])
			if not block_id.is_empty():
				mesh_subresources.append(block_id)
			var existing_id := _terrain_mesh_id_from_block(block)
			if existing_id >= 0:
				used_ids[existing_id] = true

	var terrain_ids: Dictionary = {}
	var next_id := 5
	var new_ext_resources: Array[String] = []
	var new_blocks: Array[String] = []
	for plant: Dictionary in generated:
		if not bool(plant.get("include_in_terrain3d", true)):
			continue
		while used_ids.has(next_id):
			next_id += 1
		var scene_path := str(plant.get("scene_path", ""))
		var ext_id := "forest_scene_%02d" % (new_ext_resources.size() + 1)
		var subresource_id := "Terrain3DMeshAsset_%s" % str(plant.get("id", "plant"))
		new_ext_resources.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [scene_path, ext_id])
		new_blocks.append(_make_terrain_mesh_asset_block(plant, next_id, ext_id, subresource_id))
		mesh_subresources.append(subresource_id)
		terrain_ids[plant.get("id")] = next_id
		used_ids[next_id] = true
		next_id += 1

	var output_lines: Array[String] = []
	output_lines.append_array(parsed.get("header_lines", []))
	output_lines.append_array(parsed.get("kept_ext_resources", []))
	output_lines.append_array(new_ext_resources)
	output_lines.append("")
	output_lines.append_array(_flatten_blocks(parsed.get("kept_blocks", [])))
	output_lines.append_array(new_blocks)
	output_lines.append("[resource]")
	output_lines.append("mesh_list = Array[Terrain3DMeshAsset]([%s])" % _format_subresource_list(mesh_subresources))
	output_lines.append(str(parsed.get("texture_list_line", "texture_list = Array[Terrain3DTextureAsset]([])")))

	var write_file := FileAccess.open(TERRAIN_ASSETS_PATH, FileAccess.WRITE)
	if not write_file:
		errors.append("Could not write %s." % TERRAIN_ASSETS_PATH)
		return terrain_ids
	write_file.store_string("\n".join(output_lines) + "\n")
	return terrain_ids


func _rewrite_palette(generated: Array[Dictionary], terrain_ids: Dictionary, errors: Array[String]) -> void:
	var palette_script := ResourceLoader.load("res://addons/forest_brush/forest_palette_data.gd") as Script
	var plant_script := ResourceLoader.load("res://addons/forest_brush/forest_plant_type_data.gd") as Script
	if not palette_script or not plant_script:
		errors.append("Could not load forest palette scripts.")
		return

	var palette := palette_script.new() as ForestPaletteData
	palette.id = &"default_user_forest"
	palette.display_name = "Default User Forest"
	palette.description = "Forest Brush palette generated from user-provided tree and grass source assets copied into res://assets/models/forest/source."

	var plant_types: Array[ForestPlantTypeData] = []
	for plant: Dictionary in generated:
		if not bool(plant.get("include_in_palette", true)):
			continue
		var plant_type := plant_script.new() as ForestPlantTypeData
		var category := int(plant.get("category", CATEGORY_TREE))
		var scene_path := str(plant.get("scene_path", ""))
		var proxy_path := str(plant.get("proxy_path", ""))
		plant_type.id = StringName(str(plant.get("id", "plant")))
		plant_type.display_name = str(plant.get("display_name", "Forest Plant"))
		plant_type.description = "User-derived plant split from %s." % str(plant.get("source_path", ""))
		plant_type.category = category
		plant_type.scene = ResourceLoader.load(scene_path)
		if category == CATEGORY_TREE and not proxy_path.is_empty():
			plant_type.lod2_scene = ResourceLoader.load(proxy_path)
		_apply_plant_defaults(plant_type, category)
		plant_type.terrain3d_mesh_id = int(terrain_ids.get(plant.get("id"), -1))
		plant_types.append(plant_type)

	palette.plant_types = plant_types
	var save_error := ResourceSaver.save(palette, PALETTE_PATH)
	if save_error != OK:
		errors.append("Could not save %s: %s." % [PALETTE_PATH, error_string(save_error)])


func _apply_plant_defaults(plant_type: Resource, category: int) -> void:
	match category:
		CATEGORY_TREE:
			plant_type.set("density_per_cell", 0.22)
			plant_type.set("density_jitter", 0.35)
			plant_type.set("min_scale", 0.85)
			plant_type.set("max_scale", 1.25)
			plant_type.set("cell_edge_margin", 0.18)
			plant_type.set("near_visible_distance", 120.0)
			plant_type.set("mid_visible_distance", 300.0)
			plant_type.set("far_visible_distance", 920.0)
			plant_type.set("mid_keep_ratio", 0.95)
			plant_type.set("far_keep_ratio", 0.55)
			plant_type.set("far_scale_multiplier", 1.28)
		CATEGORY_BAMBOO:
			plant_type.set("density_per_cell", 0.42)
			plant_type.set("density_jitter", 0.32)
			plant_type.set("min_scale", 0.8)
			plant_type.set("max_scale", 1.25)
			plant_type.set("cell_edge_margin", 0.14)
			plant_type.set("near_visible_distance", 108.0)
			plant_type.set("mid_visible_distance", 260.0)
			plant_type.set("far_visible_distance", 720.0)
			plant_type.set("mid_keep_ratio", 0.9)
			plant_type.set("far_keep_ratio", 0.45)
			plant_type.set("far_scale_multiplier", 1.25)
		CATEGORY_FERN:
			plant_type.set("density_per_cell", 2.8)
			plant_type.set("density_jitter", 0.25)
			plant_type.set("min_scale", 0.75)
			plant_type.set("max_scale", 1.2)
			plant_type.set("surface_offset", 0.01)
			plant_type.set("cell_edge_margin", 0.08)
			plant_type.set("disable_shadows", true)
			plant_type.set("near_visible_distance", 64.0)
			plant_type.set("mid_visible_distance", 150.0)
			plant_type.set("far_visible_distance", 300.0)
			plant_type.set("mid_keep_ratio", 0.45)
			plant_type.set("far_keep_ratio", 0.14)
			plant_type.set("far_scale_multiplier", 1.6)
		_:
			plant_type.set("density_per_cell", 7.5)
			plant_type.set("density_jitter", 0.22)
			plant_type.set("min_scale", 0.7)
			plant_type.set("max_scale", 1.25)
			plant_type.set("surface_offset", 0.005)
			plant_type.set("cell_edge_margin", 0.04)
			plant_type.set("disable_shadows", true)
			plant_type.set("near_visible_distance", 46.0)
			plant_type.set("mid_visible_distance", 120.0)
			plant_type.set("far_visible_distance", 220.0)
			plant_type.set("mid_keep_ratio", 0.32)
			plant_type.set("far_keep_ratio", 0.08)
			plant_type.set("far_scale_multiplier", 1.8)


func _rewrite_attribution(generated: Array[Dictionary], errors: Array[String]) -> void:
	var lines: Array[String] = [
		"# Forest Assets",
		"",
		"Forest plant scenes in `plants/` and tree far-proxy scenes in `proxies/` are generated from user-provided temporary source packages copied into `source/`.",
		"",
		"## User-Provided Sources",
		"",
	]
	var seen_sources: Dictionary = {}
	for plant: Dictionary in generated:
		var source_path := str(plant.get("source_path", ""))
		if seen_sources.has(source_path):
			continue
		seen_sources[source_path] = true
		lines.append("- `%s`" % source_path)
	lines.append("")
	lines.append("The original temporary source folders are left untouched and are not referenced by project resources.")

	var file := FileAccess.open(ATTRIBUTION_PATH, FileAccess.WRITE)
	if not file:
		errors.append("Could not write %s." % ATTRIBUTION_PATH)
		return
	file.store_string("\n".join(lines) + "\n")


func _parse_terrain_assets_text(text: String) -> Dictionary:
	var header_lines: Array[String] = []
	var kept_ext_resources: Array[String] = []
	var kept_blocks: Array[Array] = []
	var texture_list_line := "texture_list = Array[Terrain3DTextureAsset]([])"
	var current_block: Array[String] = []
	var in_resource := false
	var saw_resource_body := false

	for raw_line: String in text.split("\n", false):
		var line := raw_line.rstrip("\r")
		if line.begins_with("[ext_resource"):
			_flush_terrain_block(current_block, kept_blocks)
			if not line.contains("res://assets/models/forest/"):
				kept_ext_resources.append(line)
			continue

		if line.begins_with("[sub_resource"):
			_flush_terrain_block(current_block, kept_blocks)
			current_block.append(line)
			in_resource = false
			continue

		if line == "[resource]":
			_flush_terrain_block(current_block, kept_blocks)
			in_resource = true
			saw_resource_body = true
			continue

		if not current_block.is_empty():
			current_block.append(line)
			continue

		if in_resource:
			if line.begins_with("texture_list = "):
				texture_list_line = line
			continue

		if not saw_resource_body and kept_ext_resources.is_empty():
			header_lines.append(line)

	_flush_terrain_block(current_block, kept_blocks)

	return {
		"header_lines": _trim_trailing_blank_lines(header_lines),
		"kept_ext_resources": kept_ext_resources,
		"kept_blocks": kept_blocks,
		"texture_list_line": texture_list_line,
	}


func _flush_terrain_block(current_block: Array[String], kept_blocks: Array[Array]) -> void:
	if current_block.is_empty():
		return
	if not _is_removed_forest_mesh_asset_block(current_block):
		kept_blocks.append(current_block.duplicate())
	current_block.clear()


func _is_removed_forest_mesh_asset_block(block: Array[String]) -> bool:
	if block.is_empty() or not _is_terrain_mesh_asset_block(block):
		return false
	var joined := "\n".join(block)
	return joined.contains("res://assets/models/forest/") or joined.contains("name = \"Forest ") or block[0].contains("_forest")


func _is_terrain_mesh_asset_block(block: Array[String]) -> bool:
	return not block.is_empty() and block[0].contains("type=\"Terrain3DMeshAsset\"")


func _subresource_id_from_header(header: String) -> String:
	var marker := "id=\""
	var start := header.find(marker)
	if start < 0:
		return ""
	start += marker.length()
	var end := header.find("\"", start)
	if end < 0:
		return ""
	return header.substr(start, end - start)


func _terrain_mesh_id_from_block(block: Array[String]) -> int:
	for line: String in block:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("id = "):
			return int(trimmed.trim_prefix("id = "))
	return -1


func _make_terrain_mesh_asset_block(plant: Dictionary, mesh_id: int, ext_id: String, subresource_id: String) -> String:
	var category := int(plant.get("category", CATEGORY_TREE))
	return "\n".join([
		"[sub_resource type=\"Terrain3DMeshAsset\" id=\"%s\"]" % subresource_id,
		"name = \"%s\"" % str(plant.get("display_name", "Forest Plant")),
		"id = %d" % mesh_id,
		"scene_file = ExtResource(\"%s\")" % ext_id,
		"density = %s" % _format_float(_terrain_density_for_category(category)),
		"last_lod = 0",
		"last_shadow_lod = 0",
		"lod0_range = %s" % _format_float(_terrain_lod_range_for_category(category)),
		"",
	])


func _flatten_blocks(blocks: Array) -> Array[String]:
	var lines: Array[String] = []
	for raw_block: Variant in blocks:
		var block := raw_block as Array
		for line: Variant in block:
			lines.append(str(line))
		lines.append("")
	return lines


func _format_subresource_list(ids: Array[String]) -> String:
	var entries: Array[String] = []
	for id: String in ids:
		entries.append("SubResource(\"%s\")" % id)
	return ", ".join(entries)


func _trim_trailing_blank_lines(lines: Array[String]) -> Array[String]:
	while not lines.is_empty() and lines[-1].is_empty():
		lines.pop_back()
	lines.append("")
	return lines


func _format_float(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%.1f" % value
	return str(value)


func _mesh_asset_scene_path(mesh_asset: Variant) -> String:
	if not (mesh_asset is Object):
		return ""
	var scene: Variant = (mesh_asset as Object).get("scene_file")
	if scene is PackedScene:
		return (scene as PackedScene).resource_path
	return ""


func _terrain_density_for_category(category: int) -> float:
	match category:
		CATEGORY_TREE:
			return 0.055
		CATEGORY_BAMBOO:
			return 0.09
		CATEGORY_FERN:
			return 0.26
		_:
			return 0.42


func _terrain_lod_range_for_category(category: int) -> float:
	match category:
		CATEGORY_TREE:
			return 128.0
		CATEGORY_BAMBOO:
			return 104.0
		CATEGORY_FERN:
			return 64.0
		_:
			return 48.0


func _category_disables_shadows(category: int) -> bool:
	return category == CATEGORY_GRASS or category == CATEGORY_FERN


func _sample_color_from_texture(texture_path: String, fallback: Color) -> Color:
	if texture_path.is_empty():
		return fallback
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(texture_path)) != OK:
		return fallback
	var step_x := maxi(1, image.get_width() / 32)
	var step_y := maxi(1, image.get_height() / 32)
	var total := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	for y: int in range(0, image.get_height(), step_y):
		for x: int in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			if color.a < 0.1:
				continue
			if color.g >= color.r * 1.02 and color.g >= color.b * 1.08:
				total += color
				count += 1
	if count == 0:
		return fallback
	var sampled := total / float(count)
	sampled.a = 1.0
	if sampled.g <= maxf(sampled.r, sampled.b):
		return fallback
	sampled.r = minf(sampled.r, sampled.g * 0.72)
	sampled.b = minf(sampled.b, sampled.g * 0.62)
	return sampled.darkened(0.08)


func _sample_color_from_parts(parts: Array[Dictionary], fallback: Color) -> Color:
	for part: Dictionary in parts:
		var material := part.get("material_override") as StandardMaterial3D
		if material and material.albedo_color.g >= material.albedo_color.r:
			return material.albedo_color
	return fallback


func _ensure_directory(path: String, errors: Array[String]) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if make_error != OK:
		errors.append("Could not create %s: %s." % [path, error_string(make_error)])


func _sort_by_scene_path(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("scene_path", "")) < str(b.get("scene_path", ""))
