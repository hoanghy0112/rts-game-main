extends Node

signal atlas_changed

const DEFAULT_SAMPLE_SIZE := 2.0
const MIN_ALPHA := 0.01
const TREE_CATEGORIES := {
	0: true,
	1: true,
	2: true,
	3: true,
}
const GRASS_CATEGORY := 5
const SMOOTH_GRASS_PLANT_ID := &"forest_smooth_grass_01"
const FIELD_GRASS_STRENGTH := 0.36

@export_node_path("Node3D") var terrain_path: NodePath
@export var forest_region_paths: Array[NodePath] = []
@export var village_region_paths: Array[NodePath] = []
@export var auto_discover_regions := true
@export_range(0.5, 32.0, 0.5, "or_greater") var sample_size_meters: float = DEFAULT_SAMPLE_SIZE
@export_range(64, 4096, 1, "or_greater") var max_texture_size: int = 2048
@export var auto_rebuild_on_ready := true

var _image: Image
var _texture: ImageTexture
var _near_hide_mask_image: Image
var _near_hide_mask_texture: ImageTexture
var _world_rect := Rect2()
var _atlas_origin := Vector2.ZERO
var _effective_sample_size := DEFAULT_SAMPLE_SIZE
var _rebuild_queued := false


func _ready() -> void:
	_connect_source_signals()
	if auto_rebuild_on_ready:
		rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	var sources := _collect_source_data()
	var bounds_info := _calculate_world_bounds(sources)
	if not bool(bounds_info.get("valid", false)):
		_clear_atlas()
		return

	_world_rect = bounds_info.get("rect", Rect2())
	_effective_sample_size = _calculate_effective_sample_size(_world_rect)
	_atlas_origin = _world_rect.position
	var texture_size := Vector2i(
		maxi(ceili(_world_rect.size.x / _effective_sample_size), 1),
		maxi(ceili(_world_rect.size.y / _effective_sample_size), 1)
	)

	_image = Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_near_hide_mask_image = Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_R8)
	_near_hide_mask_image.fill(Color.BLACK)
	for forest_data: Dictionary in sources.get("forests", []):
		_rasterize_forest(forest_data)
	for village_data: Dictionary in sources.get("villages", []):
		_rasterize_village(village_data)

	_texture = ImageTexture.create_from_image(_image)
	_near_hide_mask_texture = ImageTexture.create_from_image(_near_hide_mask_image)
	atlas_changed.emit()


func mark_dirty_region(_world_region: Rect2 = Rect2()) -> void:
	_schedule_rebuild()


func get_texture() -> Texture2D:
	return _texture


func get_image() -> Image:
	return _image


func get_near_hide_mask_texture() -> Texture2D:
	return _near_hide_mask_texture


func get_near_hide_mask_image() -> Image:
	return _near_hide_mask_image


func get_origin() -> Vector2:
	return _atlas_origin


func get_sample_size() -> float:
	return _effective_sample_size


func get_world_rect() -> Rect2:
	return _world_rect


func has_atlas() -> bool:
	return _texture != null and _image != null and _image.get_width() > 0 and _image.get_height() > 0


func _schedule_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _clear_atlas() -> void:
	_image = null
	_texture = null
	_near_hide_mask_image = null
	_near_hide_mask_texture = null
	_world_rect = Rect2()
	_atlas_origin = Vector2.ZERO
	atlas_changed.emit()


func _connect_source_signals() -> void:
	for source: Node in _get_forest_regions() + _get_village_regions():
		_connect_source_signal(source, &"cells_changed")
		_connect_source_signal(source, &"resources_changed")


func _connect_source_signal(source: Node, signal_name: StringName) -> void:
	if not source or not source.has_signal(signal_name):
		return
	var callable := Callable(self, "_on_source_macro_detail_changed").bind(source, signal_name)
	if not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)


func _on_source_macro_detail_changed(source: Node, signal_name: StringName) -> void:
	if signal_name == &"cells_changed" and _source_macro_overlay_disabled(source):
		return
	_schedule_rebuild()


func _source_macro_overlay_disabled(source: Node) -> bool:
	if not source or not source.has_method("should_trigger_macro_overlay"):
		return false
	return not bool(source.call("should_trigger_macro_overlay"))


func _collect_source_data() -> Dictionary:
	var forests: Array[Dictionary] = []
	for forest: Node in _get_forest_regions():
		var data := _get_node_macro_data(forest)
		if not data.is_empty():
			forests.append(data)

	var villages: Array[Dictionary] = []
	for village: Node in _get_village_regions():
		var data := _get_node_macro_data(village)
		if not data.is_empty():
			villages.append(data)

	return {
		"forests": forests,
		"villages": villages,
	}


func _get_node_macro_data(node: Node) -> Dictionary:
	if not node:
		return {}
	if node.has_method("get_macro_detail_data"):
		var data: Variant = node.call("get_macro_detail_data")
		return data if data is Dictionary else {}
	if node.has_method("to_runtime_data"):
		var data: Variant = node.call("to_runtime_data")
		return data if data is Dictionary else {}
	return {}


func _get_forest_regions() -> Array[Node]:
	var regions: Array[Node] = []
	for path: NodePath in forest_region_paths:
		var node := get_node_or_null(path)
		if node and not regions.has(node):
			regions.append(node)
	if regions.is_empty() and auto_discover_regions:
		_collect_regions_by_class(_get_discovery_root(), "ForestRegion", regions)
	return regions


func _get_village_regions() -> Array[Node]:
	var regions: Array[Node] = []
	for path: NodePath in village_region_paths:
		var node := get_node_or_null(path)
		if node and not regions.has(node):
			regions.append(node)
	if regions.is_empty() and auto_discover_regions:
		_collect_regions_by_class(_get_discovery_root(), "VillageRegion", regions)
	return regions


func _get_discovery_root() -> Node:
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	if owner:
		return owner
	return get_parent()


func _collect_regions_by_class(root: Node, class_name_value: String, regions: Array[Node]) -> void:
	if not root:
		return
	if _node_matches_script_class(root, class_name_value) and not regions.has(root):
		regions.append(root)
	for child: Node in root.get_children():
		_collect_regions_by_class(child, class_name_value, regions)


func _node_matches_script_class(node: Node, class_name_value: String) -> bool:
	if node.is_class(class_name_value):
		return true
	var script := node.get_script() as Script
	if not script:
		return false
	match class_name_value:
		"ForestRegion":
			return script.resource_path == "res://addons/forest_brush/forest_region.gd"
		"VillageRegion":
			return script.resource_path == "res://addons/village_brush/village_region.gd"
		_:
			return false


func _calculate_world_bounds(sources: Dictionary) -> Dictionary:
	var has_bounds := false
	var bounds := Rect2()
	for forest_data: Dictionary in sources.get("forests", []):
		var transform := forest_data.get("global_transform", Transform3D.IDENTITY) as Transform3D
		var origin := forest_data.get("origin", Vector3.ZERO) as Vector3
		var cell_size := maxf(float(forest_data.get("cell_size", 4.0)), 0.1)
		for cell: Vector2i in _variant_to_cells(forest_data.get("forest_cells", [])):
			var rect := _world_rect_for_cell(transform, origin, cell_size, cell)
			var merged := _merge_bounds(bounds, has_bounds, rect)
			bounds = merged.get("rect", Rect2())
			has_bounds = bool(merged.get("valid", false))

	for village_data: Dictionary in sources.get("villages", []):
		var transform := village_data.get("global_transform", Transform3D.IDENTITY) as Transform3D
		var origin := village_data.get("origin", Vector3.ZERO) as Vector3
		var cell_size := maxf(float(village_data.get("cell_size", 4.0)), 0.1)
		for key: String in ["house_cells", "field_cells", "road_cells"]:
			for cell: Vector2i in _variant_to_cells(village_data.get(key, [])):
				var rect := _world_rect_for_cell(transform, origin, cell_size, cell)
				var merged := _merge_bounds(bounds, has_bounds, rect)
				bounds = merged.get("rect", Rect2())
				has_bounds = bool(merged.get("valid", false))
		var field_generation := village_data.get("field_generation", {}) as Dictionary
		for plot_variant: Variant in field_generation.get("plots", []):
			if plot_variant is FieldPlotData:
				var rect := _world_rect_for_region_polygon(transform, (plot_variant as FieldPlotData).get_region_outline_2d())
				var merged := _merge_bounds(bounds, has_bounds, rect)
				bounds = merged.get("rect", Rect2())
				has_bounds = bool(merged.get("valid", false))

	if has_bounds:
		bounds = bounds.grow(maxf(_effective_sample_size, sample_size_meters) * 2.0)
	return {
		"valid": has_bounds,
		"rect": bounds,
	}


func _merge_bounds(current: Rect2, has_current: bool, addition: Rect2) -> Dictionary:
	if addition.size.x < 0.001 and addition.size.y < 0.001:
		return {
			"valid": has_current,
			"rect": current,
		}
	if not has_current:
		return {
			"valid": true,
			"rect": addition,
		}
	return {
		"valid": true,
		"rect": current.merge(addition),
	}


func _calculate_effective_sample_size(bounds: Rect2) -> float:
	var safe_sample := maxf(sample_size_meters, 0.5)
	var max_dimension := maxf(bounds.size.x, bounds.size.y)
	if max_dimension <= 0.0:
		return safe_sample
	return maxf(safe_sample, max_dimension / float(maxi(max_texture_size, 1)))


func _rasterize_forest(data: Dictionary) -> void:
	var transform := data.get("global_transform", Transform3D.IDENTITY) as Transform3D
	var inverse := transform.affine_inverse()
	var origin := data.get("origin", Vector3.ZERO) as Vector3
	var cell_size := maxf(float(data.get("cell_size", 4.0)), 0.1)
	var density_multiplier := maxf(float(data.get("density_multiplier", 1.0)), 0.0)
	var palette: Variant = data.get("palette")
	var cell_plant_ids := data.get("cell_plant_ids", {}) as Dictionary
	var forest_cells := _variant_to_cells(data.get("forest_cells", []))
	var forest_cell_lookup: Dictionary = {}
	for cell: Vector2i in forest_cells:
		forest_cell_lookup[cell] = true
	for cell: Vector2i in forest_cells:
		var plant_ids := _plant_ids_for_cell(cell, cell_plant_ids)
		var style := _forest_style_for_plant_ids(plant_ids, palette, density_multiplier)
		var color := style.get("color", Color(0.08, 0.24, 0.07, 1.0)) as Color
		var strength := float(style.get("strength", 0.55))
		var seed := _hash_string("|".join(_string_array_from_ids(plant_ids)))
		_rasterize_forest_cell(transform, inverse, origin, cell_size, cell, color, strength, seed, forest_cell_lookup)


func _rasterize_village(data: Dictionary) -> void:
	var transform := data.get("global_transform", Transform3D.IDENTITY) as Transform3D
	var inverse := transform.affine_inverse()
	var origin := data.get("origin", Vector3.ZERO) as Vector3
	var cell_size := maxf(float(data.get("cell_size", 4.0)), 0.1)

	var field_generation := data.get("field_generation", {}) as Dictionary
	var crop_type := field_generation.get("crop_type") as CropTypeData
	var field_seed := int(data.get("generation_seed", 0))
	var plots: Array = field_generation.get("plots", [])
	var rasterized_plots := false
	for plot_index: int in range(plots.size()):
		var plot := plots[plot_index] as FieldPlotData
		if not plot:
			continue
		var style := _field_style_for_plot(plot, crop_type, field_seed + plot_index * 4099)
		_rasterize_field_plot(
			transform,
			inverse,
			plot,
			style.get("color", Color(0.24, 0.43, 0.16, 1.0)) as Color,
			float(style.get("strength", 0.52)),
			int(style.get("seed", field_seed + plot_index))
		)
		rasterized_plots = true

	if not rasterized_plots:
		var fallback_style := _field_style_for_stage(_field_stage_for_macro(crop_type), crop_type, field_seed)
		for cell: Vector2i in _variant_to_cells(data.get("field_cells", [])):
			_rasterize_cell(
				transform,
				inverse,
				origin,
				cell_size,
				cell,
				fallback_style.get("color", Color(0.24, 0.43, 0.16, 1.0)) as Color,
				float(fallback_style.get("strength", 0.48)),
				field_seed + cell.x * 92821 + cell.y * 68917
			)


func _rasterize_cell(
	transform: Transform3D,
	inverse: Transform3D,
	origin: Vector3,
	cell_size: float,
	cell: Vector2i,
	color: Color,
	strength: float,
	seed: int,
	write_near_hide_mask: bool = false
) -> void:
	var world_rect := _world_rect_for_cell(transform, origin, cell_size, cell)
	var pixel_bounds := _pixel_bounds_for_world_rect(world_rect)
	var cell_min := Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size) + Vector2(origin.x, origin.z)
	var cell_max := cell_min + Vector2.ONE * cell_size
	for y: int in range(pixel_bounds.position.y, pixel_bounds.end.y):
		for x: int in range(pixel_bounds.position.x, pixel_bounds.end.x):
			var world_point := _pixel_to_world_point(x, y)
			var region_point := _world_to_region_point(inverse, world_point)
			if region_point.x < cell_min.x or region_point.y < cell_min.y or region_point.x >= cell_max.x or region_point.y >= cell_max.y:
				continue
			var noise := _noise_01(x, y, seed)
			var alpha := strength * (0.68 + 0.32 * noise)
			var tinted := _adjust_color(color, (noise - 0.5) * 0.16)
			_blend_pixel(x, y, tinted, alpha)
			if write_near_hide_mask and alpha > MIN_ALPHA:
				_write_near_hide_mask_pixel(x, y)


func _rasterize_forest_cell(
	transform: Transform3D,
	inverse: Transform3D,
	origin: Vector3,
	cell_size: float,
	cell: Vector2i,
	color: Color,
	strength: float,
	seed: int,
	forest_cell_lookup: Dictionary
) -> void:
	var world_rect := _world_rect_for_cell(transform, origin, cell_size, cell)
	var pixel_bounds := _pixel_bounds_for_world_rect(world_rect)
	var cell_min := Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size) + Vector2(origin.x, origin.z)
	var cell_max := cell_min + Vector2.ONE * cell_size
	var edge_feather := minf(maxf(_effective_sample_size, cell_size * 0.16), cell_size * 0.45)
	for y: int in range(pixel_bounds.position.y, pixel_bounds.end.y):
		for x: int in range(pixel_bounds.position.x, pixel_bounds.end.x):
			var world_point := _pixel_to_world_point(x, y)
			var region_point := _world_to_region_point(inverse, world_point)
			if region_point.x < cell_min.x or region_point.y < cell_min.y or region_point.x >= cell_max.x or region_point.y >= cell_max.y:
				continue
			var edge_alpha := _forest_exposed_edge_alpha(region_point, cell_min, cell_max, cell, edge_feather, forest_cell_lookup)
			if edge_alpha <= MIN_ALPHA:
				continue
			var noise := _noise_01(x, y, seed)
			var alpha := strength * edge_alpha * (0.68 + 0.32 * noise)
			var tinted := _adjust_color(color, (noise - 0.5) * 0.16)
			_blend_pixel(x, y, tinted, alpha)
			if alpha > MIN_ALPHA:
				_write_near_hide_mask_pixel(x, y)


func _forest_exposed_edge_alpha(
	region_point: Vector2,
	cell_min: Vector2,
	cell_max: Vector2,
	cell: Vector2i,
	edge_feather: float,
	forest_cell_lookup: Dictionary
) -> float:
	if edge_feather <= 0.001:
		return 1.0

	var alpha := 1.0
	if not forest_cell_lookup.has(cell + Vector2i(-1, 0)):
		alpha = minf(alpha, clampf((region_point.x - cell_min.x) / edge_feather, 0.0, 1.0))
	if not forest_cell_lookup.has(cell + Vector2i(1, 0)):
		alpha = minf(alpha, clampf((cell_max.x - region_point.x) / edge_feather, 0.0, 1.0))
	if not forest_cell_lookup.has(cell + Vector2i(0, -1)):
		alpha = minf(alpha, clampf((region_point.y - cell_min.y) / edge_feather, 0.0, 1.0))
	if not forest_cell_lookup.has(cell + Vector2i(0, 1)):
		alpha = minf(alpha, clampf((cell_max.y - region_point.y) / edge_feather, 0.0, 1.0))
	return alpha


func _rasterize_field_plot(
	transform: Transform3D,
	inverse: Transform3D,
	plot: FieldPlotData,
	color: Color,
	strength: float,
	seed: int
) -> void:
	var outline := plot.get_region_outline_2d()
	if outline.size() < 3:
		return

	var world_rect := _world_rect_for_region_polygon(transform, outline).grow(_effective_sample_size * 1.5)
	var pixel_bounds := _pixel_bounds_for_world_rect(world_rect)
	var edge_feather := maxf(_effective_sample_size * 1.35, 0.75)
	for y: int in range(pixel_bounds.position.y, pixel_bounds.end.y):
		for x: int in range(pixel_bounds.position.x, pixel_bounds.end.x):
			var world_point := _pixel_to_world_point(x, y)
			var region_point := _world_to_region_point(inverse, world_point)
			if not plot.contains_region_point(region_point):
				continue

			var local_point := plot.to_plot_local_2d(region_point)
			var edge_distance := maxf(plot.get_region_edge_distance(region_point), 0.0)
			var edge := clampf(edge_distance / edge_feather, 0.0, 1.0)
			var noise := _noise_01(x, y, seed)
			var row_band := 0.5 + 0.5 * sin(local_point.y * 1.35 + float(seed % 113) * 0.11)
			var length_band := 0.5 + 0.5 * sin(local_point.x * 0.18 + float(seed % 71) * 0.17)
			var variation := noise * 0.48 + row_band * 0.36 + length_band * 0.16
			var alpha := strength * edge * (0.58 + 0.42 * variation)
			var tinted := _adjust_color(color, (variation - 0.5) * 0.18)
			_blend_pixel(x, y, tinted, alpha)


func _rasterize_polyline(
	transform: Transform3D,
	inverse: Transform3D,
	polyline: PackedVector2Array,
	width: float,
	color: Color,
	strength: float
) -> void:
	if polyline.size() < 2:
		return
	var world_rect := _world_rect_for_region_polygon(transform, polyline).grow(width)
	var pixel_bounds := _pixel_bounds_for_world_rect(world_rect)
	var radius := width * 0.5
	var seed := _hash_string(str(polyline.size()) + ":" + str(width))
	for y: int in range(pixel_bounds.position.y, pixel_bounds.end.y):
		for x: int in range(pixel_bounds.position.x, pixel_bounds.end.x):
			var world_point := _pixel_to_world_point(x, y)
			var region_point := _world_to_region_point(inverse, world_point)
			var distance := _distance_to_polyline(region_point, polyline)
			if distance > radius:
				continue
			var edge := 1.0 - clampf(distance / maxf(radius, 0.001), 0.0, 1.0)
			var noise := _noise_01(x, y, seed)
			_blend_pixel(x, y, _adjust_color(color, (noise - 0.5) * 0.1), strength * (0.42 + edge * 0.58))


func _blend_pixel(x: int, y: int, color: Color, alpha: float) -> void:
	if not _image:
		return
	var source_alpha := clampf(color.a * alpha, 0.0, 1.0)
	if source_alpha <= MIN_ALPHA:
		return
	var existing := _image.get_pixel(x, y)
	var out_alpha := source_alpha + existing.a * (1.0 - source_alpha)
	if out_alpha <= MIN_ALPHA:
		return
	var existing_weight := existing.a * (1.0 - source_alpha)
	var out_color := Color(
		(color.r * source_alpha + existing.r * existing_weight) / out_alpha,
		(color.g * source_alpha + existing.g * existing_weight) / out_alpha,
		(color.b * source_alpha + existing.b * existing_weight) / out_alpha,
		out_alpha
	)
	_image.set_pixel(x, y, out_color)


func _write_near_hide_mask_pixel(x: int, y: int) -> void:
	if _near_hide_mask_image:
		_near_hide_mask_image.set_pixel(x, y, Color.WHITE)


func _forest_style_for_plant_ids(plant_ids: Array[StringName], palette: Variant, density_multiplier: float) -> Dictionary:
	if plant_ids.is_empty():
		plant_ids = [&"forest_smooth_grass_01"]
	var color_sum := Color(0.0, 0.0, 0.0, 1.0)
	var total_weight := 0.0
	var total_strength := 0.0
	for plant_id: StringName in plant_ids:
		var plant_type := _get_plant_type_by_id(palette, plant_id)
		var category := int(plant_type.get("category")) if plant_type else GRASS_CATEGORY
		var weight := 1.0
		var color := _plant_macro_color(plant_id, category)
		var strength := 0.42
		if TREE_CATEGORIES.has(category):
			weight = 2.2
			strength = 0.76
		elif category == GRASS_CATEGORY:
			weight = 0.85
			strength = 0.34
		color_sum.r += color.r * weight
		color_sum.g += color.g * weight
		color_sum.b += color.b * weight
		total_weight += weight
		total_strength += strength * weight
	if total_weight <= 0.0:
		return {
			"color": Color(0.10, 0.28, 0.09, 1.0),
			"strength": 0.45,
		}
	var density_boost := clampf(0.74 + minf(density_multiplier, 4.0) * 0.08, 0.74, 1.0)
	return {
		"color": Color(color_sum.r / total_weight, color_sum.g / total_weight, color_sum.b / total_weight, 1.0),
		"strength": clampf((total_strength / total_weight) * density_boost, 0.08, 0.92),
	}


func _plant_macro_color(plant_id: StringName, category: int) -> Color:
	var noise := _hash_string(str(plant_id))
	var hue_shift := float(noise % 1000) / 1000.0
	if TREE_CATEGORIES.has(category):
		return Color(0.045 + hue_shift * 0.025, 0.18 + hue_shift * 0.08, 0.055 + hue_shift * 0.035, 1.0)
	if category == GRASS_CATEGORY:
		if str(plant_id).contains("flower"):
			return Color(0.32, 0.37, 0.13, 1.0)
		return Color(0.15 + hue_shift * 0.04, 0.34 + hue_shift * 0.10, 0.10, 1.0)
	return Color(0.11, 0.27, 0.10, 1.0)


func _field_style_for_plot(plot: FieldPlotData, crop_type: CropTypeData, seed: int) -> Dictionary:
	var stage := plot.stage
	if stage == &"" or stage == &"empty":
		stage = _field_stage_for_macro(crop_type)
	return _field_style_for_stage(stage, crop_type, _hash_string(str(plot.id) + ":" + str(seed)))


func _field_stage_for_macro(crop_type: CropTypeData) -> StringName:
	if crop_type and crop_type.crop_id == &"rice":
		return &"flooded_green"
	return &"growth"


func _field_style_for_stage(_stage: StringName, _crop_type: CropTypeData, seed: int) -> Dictionary:
	var grass_color := _plant_macro_color(SMOOTH_GRASS_PLANT_ID, GRASS_CATEGORY)
	var hue_noise := (float(seed & 0xffff) / 65535.0) - 0.5
	var color := _adjust_color(grass_color, hue_noise * 0.05)
	return {
		"color": color,
		"strength": FIELD_GRASS_STRENGTH,
		"seed": seed,
	}


func _adjust_color(color: Color, amount: float) -> Color:
	if amount >= 0.0:
		return color.lightened(amount)
	return color.darkened(-amount)


func _get_plant_type_by_id(palette: Variant, plant_id: StringName) -> Object:
	if not palette:
		return null
	var plant_types: Variant = palette.get("plant_types")
	if not (plant_types is Array):
		return null
	for plant_type: Variant in plant_types:
		if plant_type is Object and StringName((plant_type as Object).get("id")) == plant_id:
			return plant_type as Object
	return null


func _plant_ids_for_cell(cell: Vector2i, cell_plant_ids: Dictionary) -> Array[StringName]:
	var raw: Variant = null
	if cell_plant_ids.has(cell):
		raw = cell_plant_ids[cell]
	else:
		raw = cell_plant_ids.get("%d,%d" % [cell.x, cell.y], [])
	var ids: Array[StringName] = []
	if raw is Array:
		for value: Variant in raw:
			ids.append(StringName(value))
	elif raw is PackedStringArray:
		for value: String in raw:
			ids.append(StringName(value))
	elif raw != null:
		ids.append(StringName(raw))
	return ids


func _variant_to_cells(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for cell_variant: Variant in value:
		if cell_variant is Vector2i:
			cells.append(cell_variant as Vector2i)
	return cells


func _world_rect_for_cell(transform: Transform3D, origin: Vector3, cell_size: float, cell: Vector2i) -> Rect2:
	var min_point := origin + Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)
	var max_point := min_point + Vector3(cell_size, 0.0, cell_size)
	return _world_rect_for_points([
		Vector2(min_point.x, min_point.z),
		Vector2(max_point.x, min_point.z),
		Vector2(max_point.x, max_point.z),
		Vector2(min_point.x, max_point.z),
	], transform)


func _world_rect_for_region_polygon(transform: Transform3D, polygon: PackedVector2Array) -> Rect2:
	var points: Array[Vector2] = []
	for point: Vector2 in polygon:
		points.append(point)
	return _world_rect_for_points(points, transform)


func _world_rect_for_points(points: Array[Vector2], transform: Transform3D) -> Rect2:
	var has_bounds := false
	var rect := Rect2()
	for point: Vector2 in points:
		var world := transform * Vector3(point.x, 0.0, point.y)
		var world_2d := Vector2(world.x, world.z)
		if not has_bounds:
			rect = Rect2(world_2d, Vector2.ZERO)
			has_bounds = true
		else:
			rect = rect.expand(world_2d)
	return rect


func _pixel_bounds_for_world_rect(world_rect: Rect2) -> Rect2i:
	var image_size := Vector2i(_image.get_width(), _image.get_height())
	var min_x := clampi(floori((world_rect.position.x - _atlas_origin.x) / _effective_sample_size) - 1, 0, image_size.x)
	var min_y := clampi(floori((world_rect.position.y - _atlas_origin.y) / _effective_sample_size) - 1, 0, image_size.y)
	var max_x := clampi(ceili((world_rect.end.x - _atlas_origin.x) / _effective_sample_size) + 1, 0, image_size.x)
	var max_y := clampi(ceili((world_rect.end.y - _atlas_origin.y) / _effective_sample_size) + 1, 0, image_size.y)
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)


func _pixel_to_world_point(x: int, y: int) -> Vector2:
	return _atlas_origin + Vector2(float(x) + 0.5, float(y) + 0.5) * _effective_sample_size


func _world_to_region_point(inverse: Transform3D, world_point: Vector2) -> Vector2:
	var local := inverse * Vector3(world_point.x, 0.0, world_point.y)
	return Vector2(local.x, local.z)


func _distance_to_polyline(point: Vector2, polyline: PackedVector2Array) -> float:
	var best := INF
	for index: int in range(polyline.size() - 1):
		best = minf(best, _distance_to_segment(point, polyline[index], polyline[index + 1]))
	return best


func _distance_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from_point)
	var t := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from_point + segment * t)


func _string_array_from_ids(ids: Array[StringName]) -> Array[String]:
	var values: Array[String] = []
	for id: StringName in ids:
		values.append(str(id))
	values.sort()
	return values


func _noise_01(x: int, y: int, seed: int) -> float:
	var mixed := _mix_hash(seed, x)
	mixed = _mix_hash(mixed, y)
	return float(mixed & 0xffff) / 65535.0


func _hash_string(value: String) -> int:
	var mixed := int(2166136261)
	for index: int in range(value.length()):
		mixed = _mix_hash(mixed, value.unicode_at(index))
	return mixed


func _mix_hash(current: int, value: int) -> int:
	return int((current ^ value) * 16777619) & 0x7fffffff
