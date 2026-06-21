@tool
extends Node3D
class_name RicePaddyRenderer

const RICE_DENSE_PLANTS_SCENE := preload("res://modules/village/fields/rice/dense_plants/rice_dense_plants_particles.tscn")
const RICE_OVERLAY_SHADER: Shader = preload("res://modules/village/fields/rice_field_overlay.gdshader")
const RICE_PADDY_RENDERER_META := &"village_rice_paddy_renderer"
const RICE_DENSE_LAYER_META := &"village_rice_dense_plants_layer"
const RICE_FAR_OVERLAY_META := &"village_rice_paddy_far_overlay"
const PRESERVE_VISIBILITY_RANGE_META := &"village_preserve_visibility_range"

@export var bund_material: Material
@export var water_material: Material
@export var rice_overlay_enabled := false
@export var rice_overlay_material: Material
@export_range(0.15, 3.0, 0.05, "or_greater") var bund_base_width: float = 1.05
@export_range(0.05, 1.5, 0.05, "or_greater") var bund_top_width: float = 0.42
@export_range(0.05, 1.5, 0.05, "or_greater") var bund_height: float = 0.34
@export_range(0.0, 1.0, 0.01, "or_greater") var bund_surface_offset: float = 0.03
@export_range(0.0, 1.0, 0.01, "or_greater") var water_surface_offset: float = 0.075
@export_range(0.0, 1.0, 0.01, "or_greater") var rice_overlay_surface_offset: float = 0.105
@export_range(0.0, 3.0, 0.05, "or_greater") var rice_overlay_edge_inset: float = 0.35
@export_range(0.0, 10000.0, 1.0, "or_greater") var rice_overlay_begin_distance: float = 176.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var rice_overlay_begin_fade_margin: float = 32.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var rice_overlay_end_distance: float = 800.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var rice_overlay_end_fade_margin: float = 80.0
@export_range(0.05, 2.0, 0.05, "or_greater") var mask_sample_size: float = 1.0
@export_range(0.0, 3.0, 0.05, "or_greater") var rice_mask_edge_inset: float = 0.45

var _terrain: Node3D
var _region: Node3D
var _plots: Array[FieldPlotData] = []
var _bund_polylines: Array = []
var _bund_mesh: MeshInstance3D
var _water_mesh: MeshInstance3D
var _rice_overlay_mesh: MeshInstance3D
var _rice_layer: Node3D


func _ready() -> void:
	set_meta(RICE_PADDY_RENDERER_META, true)
	_resolve_nodes()


func configure_from_field_generation(p_terrain: Node3D, p_region: Node3D, field_generation: Dictionary) -> void:
	_terrain = p_terrain
	_region = p_region
	_plots.clear()
	for plot_variant: Variant in field_generation.get("plots", []):
		if plot_variant is FieldPlotData:
			_plots.append(plot_variant as FieldPlotData)
	_bund_polylines = (field_generation.get("field_bund_polylines", []) as Array).duplicate(true)
	if _bund_polylines.is_empty():
		_bund_polylines = (field_generation.get("field_road_polylines", []) as Array).duplicate(true)

	_resolve_nodes()
	_rebuild_bund_mesh()
	_rebuild_water_mesh()
	if rice_overlay_enabled:
		_rebuild_rice_overlay_mesh()
	else:
		_disable_rice_overlay_mesh()
	_configure_rice_layer()


func _resolve_nodes() -> void:
	if not _bund_mesh:
		_bund_mesh = get_node_or_null("Bunds") as MeshInstance3D
	if not _bund_mesh:
		_bund_mesh = MeshInstance3D.new()
		_bund_mesh.name = "Bunds"
		add_child(_bund_mesh, false, INTERNAL_MODE_BACK)
		_bund_mesh.owner = null
	if bund_material:
		_bund_mesh.material_override = bund_material

	if not _water_mesh:
		_water_mesh = get_node_or_null("Water") as MeshInstance3D
	if not _water_mesh:
		_water_mesh = MeshInstance3D.new()
		_water_mesh.name = "Water"
		add_child(_water_mesh, false, INTERNAL_MODE_BACK)
		_water_mesh.owner = null
	if water_material:
		_water_mesh.material_override = water_material

	if rice_overlay_enabled:
		if not _rice_overlay_mesh:
			_rice_overlay_mesh = get_node_or_null("RiceMacroOverlay") as MeshInstance3D
		if not _rice_overlay_mesh:
			_rice_overlay_mesh = MeshInstance3D.new()
			_rice_overlay_mesh.name = "RiceMacroOverlay"
			add_child(_rice_overlay_mesh, false, INTERNAL_MODE_BACK)
			_rice_overlay_mesh.owner = null
		_rice_overlay_mesh.set_meta(RICE_FAR_OVERLAY_META, true)
		_rice_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rice_overlay_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if rice_overlay_material:
			_rice_overlay_mesh.material_override = rice_overlay_material
		elif not _rice_overlay_mesh.material_override:
			var material := ShaderMaterial.new()
			material.shader = RICE_OVERLAY_SHADER
			_rice_overlay_mesh.material_override = material
		_apply_rice_overlay_visibility()
	else:
		_disable_rice_overlay_mesh()

	if not _rice_layer:
		_rice_layer = get_node_or_null("RiceDensePlantsParticles") as Node3D
	if not _rice_layer:
		_rice_layer = RICE_DENSE_PLANTS_SCENE.instantiate() as Node3D
		if _rice_layer:
			_rice_layer.name = "RiceDensePlantsParticles"
			add_child(_rice_layer, false, INTERNAL_MODE_BACK)
			_rice_layer.owner = null
	if _rice_layer:
		_rice_layer.set_meta(RICE_DENSE_LAYER_META, true)


func _rebuild_bund_mesh() -> void:
	if not _bund_mesh:
		return

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var base_half_width := maxf(bund_base_width, 0.05) * 0.5
	var top_half_width := minf(maxf(bund_top_width, 0.03), bund_base_width) * 0.5

	for polyline_variant: Variant in _bund_polylines:
		if not (polyline_variant is PackedVector2Array):
			continue
		var polyline := polyline_variant as PackedVector2Array
		for index: int in range(polyline.size() - 1):
			var from_point := polyline[index]
			var to_point := polyline[index + 1]
			var segment := to_point - from_point
			var length := segment.length()
			if length <= 0.001:
				continue

			var side := Vector2(-segment.y, segment.x) / length
			var from_base := _surface_point(from_point, bund_surface_offset)
			var to_base := _surface_point(to_point, bund_surface_offset)
			var from_top := _surface_point(from_point, bund_surface_offset + bund_height)
			var to_top := _surface_point(to_point, bund_surface_offset + bund_height)

			var from_left_base := from_base + Vector3(side.x, 0.0, side.y) * base_half_width
			var from_right_base := from_base - Vector3(side.x, 0.0, side.y) * base_half_width
			var to_left_base := to_base + Vector3(side.x, 0.0, side.y) * base_half_width
			var to_right_base := to_base - Vector3(side.x, 0.0, side.y) * base_half_width
			var from_left_top := from_top + Vector3(side.x, 0.0, side.y) * top_half_width
			var from_right_top := from_top - Vector3(side.x, 0.0, side.y) * top_half_width
			var to_left_top := to_top + Vector3(side.x, 0.0, side.y) * top_half_width
			var to_right_top := to_top - Vector3(side.x, 0.0, side.y) * top_half_width

			_append_quad(vertices, normals, uvs, indices, from_left_top, to_left_top, to_right_top, from_right_top)
			_append_quad(vertices, normals, uvs, indices, from_left_base, to_left_base, to_left_top, from_left_top)
			_append_quad(vertices, normals, uvs, indices, from_right_top, to_right_top, to_right_base, from_right_base)
			_append_quad(vertices, normals, uvs, indices, to_left_base, from_left_base, from_right_base, to_right_base)

	_bund_mesh.mesh = _make_mesh(vertices, normals, uvs, indices)
	_bund_mesh.visible = _bund_mesh.mesh != null


func _rebuild_water_mesh() -> void:
	if not _water_mesh:
		return

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for plot: FieldPlotData in _plots:
		var outline := plot.get_region_outline_2d()
		if outline.size() < 3:
			continue

		var polygon_indices := Geometry2D.triangulate_polygon(outline)
		if polygon_indices.is_empty():
			continue

		var center := Vector2(plot.center.x, plot.center.z)
		var center_surface := _surface_point(center, water_surface_offset)
		var start_index := vertices.size()
		for point: Vector2 in outline:
			var local := _surface_point(point, water_surface_offset)
			local.y = center_surface.y
			vertices.append(local)
			normals.append(Vector3.UP)
			uvs.append(point * 0.05)
		for polygon_index: int in polygon_indices:
			indices.append(start_index + polygon_index)

	_water_mesh.mesh = _make_mesh(vertices, normals, uvs, indices)
	_water_mesh.visible = _water_mesh.mesh != null


func _rebuild_rice_overlay_mesh() -> void:
	if not rice_overlay_enabled:
		_disable_rice_overlay_mesh()
		return
	if not _rice_overlay_mesh:
		return

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for plot: FieldPlotData in _plots:
		var outline := _get_overlay_outline(plot.get_region_outline_2d())
		if outline.size() < 3:
			continue

		var polygon_indices := Geometry2D.triangulate_polygon(outline)
		if polygon_indices.is_empty():
			continue

		var bounds := _get_outline_bounds(outline)
		var min_point: Vector2 = bounds.get("min", Vector2.ZERO)
		var max_point: Vector2 = bounds.get("max", min_point)
		var bounds_size := max_point - min_point
		bounds_size.x = maxf(bounds_size.x, 0.001)
		bounds_size.y = maxf(bounds_size.y, 0.001)

		var center := Vector2(plot.center.x, plot.center.z)
		var center_surface := _surface_point(center, rice_overlay_surface_offset)
		var start_index := vertices.size()
		for point: Vector2 in outline:
			var local := _surface_point(point, rice_overlay_surface_offset)
			local.y = center_surface.y
			vertices.append(local)
			normals.append(Vector3.UP)
			uvs.append(Vector2((point.x - min_point.x) / bounds_size.x, (point.y - min_point.y) / bounds_size.y))
		for polygon_index: int in polygon_indices:
			indices.append(start_index + polygon_index)

	_rice_overlay_mesh.mesh = _make_mesh(vertices, normals, uvs, indices)
	_rice_overlay_mesh.visible = _rice_overlay_mesh.mesh != null
	_apply_rice_overlay_visibility()


func _disable_rice_overlay_mesh() -> void:
	if not _rice_overlay_mesh:
		_rice_overlay_mesh = get_node_or_null("RiceMacroOverlay") as MeshInstance3D
	if not _rice_overlay_mesh:
		return

	_rice_overlay_mesh.visible = false
	_rice_overlay_mesh.mesh = null
	_rice_overlay_mesh.visibility_range_begin = 0.0
	_rice_overlay_mesh.visibility_range_begin_margin = 0.0
	_rice_overlay_mesh.visibility_range_end = 0.0
	_rice_overlay_mesh.visibility_range_end_margin = 0.0


func _configure_rice_layer() -> void:
	if not _rice_layer or not _rice_layer.has_method("configure_from_plot_mask"):
		return

	var mask_info := _build_rice_mask()
	_rice_layer.call(
		"configure_from_plot_mask",
		_terrain,
		_region if _region else self,
		mask_info.get("texture") as Texture2D,
		mask_info.get("origin", Vector2.ZERO),
		float(mask_info.get("sample_size", mask_sample_size)),
		mask_info.get("texture_size", Vector2i.ONE),
		int(mask_info.get("plot_count", _plots.size()))
	)


func _build_rice_mask() -> Dictionary:
	if _plots.is_empty():
		return {
			"texture": null,
			"origin": Vector2.ZERO,
			"sample_size": mask_sample_size,
			"texture_size": Vector2i.ONE,
			"plot_count": 0,
		}

	var bounds := _get_plot_bounds()
	var min_point: Vector2 = bounds.get("min", Vector2.ZERO)
	var max_point: Vector2 = bounds.get("max", min_point)
	var sample := maxf(mask_sample_size, 0.05)
	var texture_size := Vector2i(
		maxi(ceili((max_point.x - min_point.x) / sample) + 1, 1),
		maxi(ceili((max_point.y - min_point.y) / sample) + 1, 1)
	)
	var image := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)

	for plot: FieldPlotData in _plots:
		_rasterize_plot_mask(plot, image, min_point, sample)

	return {
		"texture": ImageTexture.create_from_image(image),
		"origin": min_point,
		"sample_size": sample,
		"texture_size": texture_size,
		"plot_count": _plots.size(),
	}


func _get_stage_code_at(region_point: Vector2) -> int:
	for plot: FieldPlotData in _plots:
		if plot.contains_region_point(region_point, rice_mask_edge_inset):
			return _stage_code(plot.stage)
	return 0


func _rasterize_plot_mask(plot: FieldPlotData, image: Image, origin: Vector2, sample: float) -> void:
	if plot == null:
		return

	var outline := plot.get_region_outline_2d()
	if outline.size() < 3:
		return

	var bounds := _get_outline_bounds(outline)
	var min_point: Vector2 = bounds.get("min", Vector2.ZERO)
	var max_point: Vector2 = bounds.get("max", min_point)
	var x_from := clampi(floori((min_point.x - origin.x) / sample) - 1, 0, image.get_width() - 1)
	var x_to := clampi(ceili((max_point.x - origin.x) / sample) + 1, 0, image.get_width() - 1)
	var y_from := clampi(floori((min_point.y - origin.y) / sample) - 1, 0, image.get_height() - 1)
	var y_to := clampi(ceili((max_point.y - origin.y) / sample) + 1, 0, image.get_height() - 1)
	var code := _stage_code(plot.stage)
	var color := Color(float(code) / 255.0, 0.0, 0.0, 1.0)

	for y: int in range(y_from, y_to + 1):
		for x: int in range(x_from, x_to + 1):
			var region_point := origin + Vector2((float(x) + 0.5) * sample, (float(y) + 0.5) * sample)
			if plot.contains_region_point(region_point, rice_mask_edge_inset):
				image.set_pixel(x, y, color)


func _stage_code(stage: StringName) -> int:
	match stage:
		&"seedling":
			return 1
		&"flooded_green":
			return 2
		&"tillering":
			return 3
		&"mature_gold":
			return 4
		&"harvested_stubble", &"stubble":
			return 5
		_:
			return 3


func _get_plot_bounds() -> Dictionary:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for plot: FieldPlotData in _plots:
		for point: Vector2 in plot.get_region_outline_2d():
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)
	if min_point.x == INF:
		min_point = Vector2.ZERO
		max_point = Vector2.ZERO
	return {
		"min": min_point - Vector2.ONE * mask_sample_size,
		"max": max_point + Vector2.ONE * mask_sample_size,
	}


func _get_overlay_outline(outline: PackedVector2Array) -> PackedVector2Array:
	if outline.size() < 3:
		return PackedVector2Array()

	var inset := maxf(rice_overlay_edge_inset, 0.0)
	if inset <= 0.001:
		return outline.duplicate()

	var centroid := Vector2.ZERO
	for point: Vector2 in outline:
		centroid += point
	centroid /= float(outline.size())

	var inset_outline := PackedVector2Array()
	for point: Vector2 in outline:
		var to_centroid := centroid - point
		var distance := to_centroid.length()
		if distance <= 0.001:
			inset_outline.append(point)
			continue
		inset_outline.append(point + to_centroid / distance * minf(inset, distance * 0.35))

	if Geometry2D.triangulate_polygon(inset_outline).is_empty():
		return outline.duplicate()
	return inset_outline


func _get_outline_bounds(outline: PackedVector2Array) -> Dictionary:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in outline:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	if min_point.x == INF:
		min_point = Vector2.ZERO
		max_point = Vector2.ZERO
	return {
		"min": min_point,
		"max": max_point,
	}


func _apply_rice_overlay_visibility() -> void:
	if not _rice_overlay_mesh:
		return

	var begin_distance := maxf(rice_overlay_begin_distance, 0.0)
	var end_distance := maxf(rice_overlay_end_distance, begin_distance)
	_rice_overlay_mesh.set_meta(PRESERVE_VISIBILITY_RANGE_META, true)
	_rice_overlay_mesh.visibility_range_begin = begin_distance
	_rice_overlay_mesh.visibility_range_begin_margin = clampf(rice_overlay_begin_fade_margin, 0.0, begin_distance)
	_rice_overlay_mesh.visibility_range_end = end_distance
	_rice_overlay_mesh.visibility_range_end_margin = clampf(rice_overlay_end_fade_margin, 0.0, end_distance)
	_rice_overlay_mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _surface_point(region_point: Vector2, offset: float) -> Vector3:
	var world_position := _region_local_to_world(Vector3(region_point.x, 0.0, region_point.y))
	var height: Variant = _get_terrain_height(world_position)
	if height != null:
		world_position.y = float(height) + offset
	else:
		world_position.y += offset
	return global_transform.affine_inverse() * world_position if is_inside_tree() else world_position


func _region_local_to_world(local_position: Vector3) -> Vector3:
	if _region:
		var transform := _region.global_transform if _region.is_inside_tree() else _region.transform
		return transform * local_position
	return local_position


func _get_terrain_height(world_position: Vector3) -> Variant:
	if not is_instance_valid(_terrain):
		return null
	var terrain_data := _terrain.get("data") as Object
	if not terrain_data or not terrain_data.has_method("get_height"):
		return null
	if terrain_data.has_method("get_region_count") and int(terrain_data.call("get_region_count")) <= 0:
		return null
	var height: float = terrain_data.call("get_height", world_position)
	if is_nan(height) or absf(height) > 1.0e20:
		return null
	return height


func _append_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3
) -> void:
	var start_index := vertices.size()
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() <= 0.0001:
		normal = Vector3.UP
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	vertices.append(d)
	for _vertex_index: int in range(4):
		normals.append(normal)
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(1.0, 0.0))
	uvs.append(Vector2(1.0, 1.0))
	uvs.append(Vector2(0.0, 1.0))
	indices.append(start_index)
	indices.append(start_index + 1)
	indices.append(start_index + 2)
	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 3)


func _make_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	if vertices.is_empty() or indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
