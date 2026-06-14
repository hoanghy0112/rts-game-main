extends SceneTree

const FieldPlotGeneratorScript = preload("res://modules/village/fields/field_plot_generator.gd")
const FieldTerrainRegistryScript = preload("res://modules/village/fields/field_terrain_registry.gd")
const RiceFieldScene = preload("res://modules/village/fields/rice_field.tscn")
const RiceDensePlantsScene = preload("res://modules/village/fields/rice/dense_plants/rice_dense_plants_particles.tscn")
const ForestDenseGrassScene = preload("res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.tscn")
const ForestFlowerGrassScene = preload("res://assets/models/forest/grass/flower_dense/forest_flower_grass_particles.tscn")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const VILLAGE_RUNTIME_CONTAINER_NAME := "__VillageRuntimeInstances"
const RICE_DENSE_LAYER_META := &"village_rice_dense_plants_layer"
const BALANCED_DENSE_PARTICLE_BUDGET := 739332


func _init() -> void:
	var failures: Array[String] = []
	_run_checks(failures)
	if failures.is_empty():
		print("Field generation headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_expect(FieldTerrainRegistryScript != null, "field terrain registry script failed to preload", failures)
	_expect(RiceFieldScene != null, "rice field scene failed to preload", failures)
	_expect(VillageRegionScript != null, "village region script failed to preload", failures)
	_expect(_draft_scene_loads_with_startup_safe_terrain(), "draft scene should load with runtime terrain edits disabled for startup", failures)
	_expect(_balanced_render_defaults_are_configured(), "balanced render defaults should be configured", failures)
	_expect(_rice_field_rebuilds_far_view_meshes(), "rice field should rebuild procedural far-view meshes", failures)
	_expect(_dense_rice_resources_load(), "dense rice particle resources should load and expose configure API", failures)
	_expect(_dense_vegetation_resources_match_balanced_budget(), "dense vegetation particle resources should match the balanced budget", failures)
	_expect(_dense_vegetation_shaders_are_static(), "dense vegetation shaders should not contain wind, time-based animation paths, or blended blade rendering", failures)
	_expect(_village_region_creates_single_rice_particle_layer(), "village region should create one dense rice particle layer", failures)

	var field_cells := _make_field_cells(20, 14)
	var roads := _make_road_polylines()
	var first := _generate_plots(12345, field_cells, roads)
	var second := _generate_plots(12345, field_cells, roads)
	var different := _generate_plots(54321, field_cells, roads)

	_expect(not first.is_empty(), "expected generated plots", failures)
	_expect(_plot_signature(first) == _plot_signature(second), "same seed must generate identical plots and footprints", failures)
	_expect(_plot_signature(first) != _plot_signature(different), "different seed should change deterministic layout", failures)
	_expect(_has_size_variation(first), "expected multiple distinct plot widths and lengths", failures)
	_expect(_has_rectangular_footprints(first), "all generated footprints should be four-point local rectangles", failures)

	for plot: FieldPlotData in first:
		_expect(_is_footprint_valid(plot), "invalid footprint for %s" % [str(plot.id)], failures)
		_expect(_has_road_clearance(plot, roads, 2.6), "road clearance failed for %s" % [str(plot.id)], failures)

	_expect(_field_mask_is_dense(field_cells, first), "field mask has samples outside plots and the bund/field-road mask", failures)


func _draft_scene_loads_with_startup_safe_terrain() -> bool:
	var draft_scene := load("res://modules/draft/draft.tscn")
	if not (draft_scene is PackedScene):
		return false

	var draft := (draft_scene as PackedScene).instantiate()
	if not draft:
		return false

	var village_region := draft.get_node_or_null("VillageRegion")
	var valid := village_region != null and not bool(village_region.get("apply_runtime_terrain_edits"))
	draft.free()
	return valid


func _balanced_render_defaults_are_configured() -> bool:
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	var environment_source := FileAccess.get_file_as_string("res://modules/environment/environment_rig.tscn")
	return (
		project_source.contains('run/main_scene="res://modules/loading/boot.tscn"')
		and project_source.contains("run/max_fps=60")
		and project_source.contains("anti_aliasing/quality/msaa_3d=0")
		and project_source.contains("anti_aliasing/quality/screen_space_aa=0")
		and project_source.contains("anti_aliasing/quality/use_taa=true")
		and environment_source.contains("sdfgi_enabled = false")
		and environment_source.contains("volumetric_fog_density = 0.0")
		and environment_source.contains("directional_shadow_max_distance = 220.0")
	)


func _rice_field_rebuilds_far_view_meshes() -> bool:
	var field := RiceFieldScene.instantiate() as RiceField
	if not field:
		return false

	var footprint := PackedVector2Array([
		Vector2(-4.0, -2.4),
		Vector2(4.0, -2.4),
		Vector2(4.0, 2.4),
		Vector2(-4.0, 2.4),
	])
	var plot := FieldPlotData.new()
	plot.configure(
		&"visual_polygon_check",
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.FORWARD,
		8.0,
		4.8,
		footprint
	)
	plot.stage = &"flooded_green"
	field.configure_field(plot, null, null)
	field.apply_environment({"rain_intensity": 0.35})
	field.rebuild_visuals()

	var ground_mesh := field.get_node_or_null("VisualRoot/Ground") as MeshInstance3D
	var water_mesh := field.get_node_or_null("VisualRoot/Water") as MeshInstance3D
	var bund_edges_mesh := field.get_node_or_null("VisualRoot/BundEdges") as MeshInstance3D
	var canopy_mesh := field.get_node_or_null("VisualRoot/CropCanopy") as MeshInstance3D
	var row_bands_mesh := field.get_node_or_null("VisualRoot/RowBands") as MeshInstance3D
	var crop_multimesh := field.get_node_or_null("VisualRoot/CropMultiMesh") as MultiMeshInstance3D
	var valid := (
		ground_mesh != null and ground_mesh.mesh != null and ground_mesh.mesh.get_surface_count() == 1
		and water_mesh != null and water_mesh.mesh != null and water_mesh.visible
		and bund_edges_mesh != null and bund_edges_mesh.mesh != null and bund_edges_mesh.visible
		and canopy_mesh == null
		and row_bands_mesh == null
		and crop_multimesh == null
		and _has_only_surface_visual_children(field)
	)
	field.free()
	return valid


func _dense_rice_resources_load() -> bool:
	if not RiceDensePlantsScene:
		return false

	var instance := RiceDensePlantsScene.instantiate()
	if not instance:
		return false

	var normal_grass := ForestDenseGrassScene.instantiate() if ForestDenseGrassScene else null
	var process_material := instance.get("process_material") as ShaderMaterial
	var min_scale := Vector3.ZERO
	var max_scale := Vector3.ZERO
	var position_offset := Vector3.ZERO
	if process_material:
		min_scale = process_material.get_shader_parameter("min_scale")
		max_scale = process_material.get_shader_parameter("max_scale")
		position_offset = process_material.get_shader_parameter("position_offset")

	var rice_draw_distance := float(instance.get("min_draw_distance"))
	var normal_grass_draw_distance := float(normal_grass.get("min_draw_distance")) if normal_grass else 0.0
	var valid := (
		instance.has_method("configure_from_plot_mask")
		and instance.has_method("configure_from_plots")
		and is_equal_approx(float(instance.get("instance_spacing")), 0.625)
		and is_equal_approx(float(instance.get("cell_width")), 120.0)
		and int(instance.get("grid_width")) == 3
		and int(instance.get("rows")) == 192
		and is_equal_approx(rice_draw_distance, 180.0)
		and rice_draw_distance > normal_grass_draw_distance
		and int(instance.get("amount")) == 36864
		and int(instance.get("particle_count")) == 331776
		and int(instance.get("process_fixed_fps")) == 1
		and process_material != null
		and is_equal_approx(min_scale.x, 0.045 * 1.5)
		and is_equal_approx(min_scale.z, 0.045 * 1.5)
		and is_equal_approx(max_scale.x, 0.085 * 1.5)
		and is_equal_approx(max_scale.z, 0.085 * 1.5)
		and is_equal_approx(min_scale.y, 1.5)
		and is_equal_approx(max_scale.y, 1.5)
		and is_equal_approx(min_scale.y, max_scale.y)
		and is_equal_approx(position_offset.y, 0.75)
	)
	if normal_grass:
		normal_grass.free()
	instance.free()

	return (
		valid
		and ResourceLoader.load("res://modules/village/fields/rice/dense_plants/rice_dense_plants_particles.gd") != null
		and ResourceLoader.load("res://modules/village/fields/rice/dense_plants/rice_dense_plants_particles.gdshader") != null
		and ResourceLoader.load("res://modules/village/fields/rice/dense_plants/rice_dense_plants_blade.gdshader") != null
		and ResourceLoader.load("res://modules/village/fields/rice/dense_plants/rice_dense_plants_process_material.tres") != null
		and ResourceLoader.load("res://modules/village/fields/rice/dense_plants/rice_dense_plants_material.tres") != null
	)


func _dense_vegetation_resources_match_balanced_budget() -> bool:
	var rice := RiceDensePlantsScene.instantiate() if RiceDensePlantsScene else null
	var smooth_grass := ForestDenseGrassScene.instantiate() if ForestDenseGrassScene else null
	var flower_grass := ForestFlowerGrassScene.instantiate() if ForestFlowerGrassScene else null
	if not rice or not smooth_grass or not flower_grass:
		if rice:
			rice.free()
		if smooth_grass:
			smooth_grass.free()
		if flower_grass:
			flower_grass.free()
		return false

	var total_particles := int(rice.get("particle_count")) + int(smooth_grass.get("particle_count")) + int(flower_grass.get("particle_count"))
	var valid := (
		is_equal_approx(float(rice.get("instance_spacing")), 0.625)
		and int(rice.get("rows")) == 192
		and int(rice.get("amount")) == 36864
		and int(rice.get("particle_count")) == 331776
		and int(rice.get("process_fixed_fps")) == 1
		and is_equal_approx(float(smooth_grass.get("instance_spacing")), 0.375)
		and is_equal_approx(float(smooth_grass.get("cell_width")), 64.0)
		and int(smooth_grass.get("grid_width")) == 3
		and int(smooth_grass.get("rows")) == 170
		and int(smooth_grass.get("amount")) == 28900
		and int(smooth_grass.get("particle_count")) == 260100
		and int(smooth_grass.get("process_fixed_fps")) == 1
		and is_equal_approx(float(flower_grass.get("instance_spacing")), 0.4375)
		and is_equal_approx(float(flower_grass.get("cell_width")), 56.0)
		and int(flower_grass.get("grid_width")) == 3
		and int(flower_grass.get("rows")) == 128
		and int(flower_grass.get("amount")) == 16384
		and int(flower_grass.get("particle_count")) == 147456
		and int(flower_grass.get("process_fixed_fps")) == 1
		and total_particles == BALANCED_DENSE_PARTICLE_BUDGET
	)

	rice.free()
	smooth_grass.free()
	flower_grass.free()
	return valid


func _dense_vegetation_shaders_are_static() -> bool:
	var shader_paths := [
		"res://modules/village/fields/rice/dense_plants/rice_dense_plants_particles.gdshader",
		"res://modules/village/fields/rice/dense_plants/rice_dense_plants_blade.gdshader",
		"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_particles.gdshader",
		"res://assets/models/forest/grass/smooth_dense/forest_dense_grass_blade.gdshader",
		"res://assets/models/forest/grass/flower_dense/forest_flower_grass_blade.gdshader",
	]
	var forbidden_tokens := [
		"TIME",
		"wind_strength",
		"wind_speed",
		"wind_direction",
		"CUSTOM[2]",
		"INSTANCE_CUSTOM[2]",
		"blend_mix",
	]
	for shader_path: String in shader_paths:
		var source := FileAccess.get_file_as_string(shader_path)
		if source.is_empty():
			return false
		for token: String in forbidden_tokens:
			if source.contains(token):
				return false
	return true


func _village_region_creates_single_rice_particle_layer() -> bool:
	var region := VillageRegionScript.new() as VillageRegion
	if not region:
		return false

	region.field_cells = _make_field_cells(6, 4)
	region.generation_seed = 2468
	root.add_child(region)
	region.rebuild_runtime_preview()

	var container := region.get_node_or_null(VILLAGE_RUNTIME_CONTAINER_NAME)
	var dense_layers := _get_nodes_with_meta(container, RICE_DENSE_LAYER_META) if container else []
	var emitters := _count_descendants_of_type(container, "GPUParticles3D") if container else 0
	var valid := (
		container != null
		and container.get_parent() == region
		and dense_layers.size() == 1
		and emitters == 9
		and _dense_rice_layer_has_mask(dense_layers[0])
		and not _has_runtime_rice_plant_nodes(container)
	)

	region.clear_runtime_instances()
	root.remove_child(region)
	region.free()
	return valid


func _has_only_surface_visual_children(field: Node) -> bool:
	var visual_root := field.get_node_or_null("VisualRoot")
	if not visual_root:
		return false

	var expected := {
		"Ground": true,
		"Water": true,
		"BundEdges": true,
	}
	for child: Node in visual_root.get_children():
		if not expected.has(child.name):
			return false
	return visual_root.get_child_count() == expected.size()


func _dense_rice_layer_has_mask(layer: Node) -> bool:
	return (
		layer != null
		and bool(layer.get_meta(RICE_DENSE_LAYER_META, false))
		and layer.has_method("has_rice_mask")
		and bool(layer.call("has_rice_mask"))
		and layer.has_method("get_mask_plot_count")
		and int(layer.call("get_mask_plot_count")) > 0
	)


func _get_nodes_with_meta(root_node: Node, meta_key: StringName) -> Array[Node]:
	var matches: Array[Node] = []
	if not root_node:
		return matches

	if bool(root_node.get_meta(meta_key, false)):
		matches.append(root_node)
	for child: Node in root_node.get_children(true):
		matches.append_array(_get_nodes_with_meta(child, meta_key))
	return matches


func _count_descendants_of_type(root_node: Node, class_name_value: String) -> int:
	if not root_node:
		return 0

	var count := 0
	for child: Node in root_node.get_children(true):
		if child.is_class(class_name_value):
			count += 1
		count += _count_descendants_of_type(child, class_name_value)
	return count


func _has_runtime_rice_plant_nodes(root_node: Node) -> bool:
	for child: Node in root_node.get_children(true):
		var child_name := String(child.name).to_lower()
		if child_name.begins_with("rice_") or child_name.contains("seedling") or child_name.contains("tillering"):
			return true
		if _has_runtime_rice_plant_nodes(child):
			return true
	return false


func _generate_plots(seed: int, field_cells: Array[Vector2i], roads: Array) -> Array[FieldPlotData]:
	var generator := FieldPlotGeneratorScript.new()
	generator.cell_size = 4.0
	generator.origin = Vector3.ZERO
	generator.generation_seed = seed
	generator.min_plot_width = 4.8
	generator.max_plot_width = 11.2
	generator.bund_gap = 0.35
	generator.field_road_gap_width = 1.2
	generator.min_plot_length = 8.0
	generator.max_plot_length = 24.0
	generator.sample_step = 0.8
	generator.road_width = 3.2
	generator.road_clearance = 1.0
	generator.horizontal_split_bias = 1.0
	generator.field_shape_variation = 0.65
	return generator.generate(field_cells, roads)


func _make_field_cells(width: int, height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(width):
		for y: int in range(height):
			cells.append(Vector2i(x, y))
	return cells


func _make_road_polylines() -> Array:
	var roads: Array = []
	var road := PackedVector2Array()
	road.append(Vector2(-4.0, -2.0))
	road.append(Vector2(-4.0, 58.0))
	roads.append(road)
	return roads


func _plot_signature(plots: Array[FieldPlotData]) -> String:
	var parts: Array[String] = []
	for plot: FieldPlotData in plots:
		var footprint_parts: Array[String] = []
		for point: Vector2 in plot.footprint:
			footprint_parts.append("%.3f,%.3f" % [point.x, point.y])
		parts.append("%s|%.3f,%.3f|%.3f|%.3f|%s" % [
			str(plot.id),
			plot.center.x,
			plot.center.z,
			plot.length,
			plot.width,
			";".join(footprint_parts),
		])
	return "\n".join(parts)


func _has_size_variation(plots: Array[FieldPlotData]) -> bool:
	var lengths: Dictionary = {}
	var widths: Dictionary = {}
	for plot: FieldPlotData in plots:
		lengths[roundi(plot.length * 10.0)] = true
		widths[roundi(plot.width * 10.0)] = true
	return lengths.size() > 1 and widths.size() > 1


func _has_rectangular_footprints(plots: Array[FieldPlotData]) -> bool:
	if plots.is_empty():
		return false

	for plot: FieldPlotData in plots:
		if not _is_rectangular_footprint(plot):
			return false
	return true


func _is_rectangular_footprint(plot: FieldPlotData) -> bool:
	if plot.footprint.size() != 4:
		return false
	if plot.area <= 0.001:
		return false
	if absf(plot.area - plot.length * plot.width) > 0.01:
		return false
	return _is_orthogonal_footprint(plot.footprint)


func _is_orthogonal_footprint(footprint: PackedVector2Array) -> bool:
	for index: int in range(footprint.size()):
		var edge := footprint[(index + 1) % footprint.size()] - footprint[index]
		if edge.length_squared() <= 0.000001:
			continue
		if absf(edge.x) > 0.001 and absf(edge.y) > 0.001:
			return false
	return true


func _is_footprint_valid(plot: FieldPlotData) -> bool:
	if not _is_rectangular_footprint(plot):
		return false

	var half_length := plot.length * 0.5
	var half_width := plot.width * 0.5
	for point: Vector2 in plot.footprint:
		if absf(point.x) > half_length + 0.001 or absf(point.y) > half_width + 0.001:
			return false

	if not plot.contains_local_point(Vector2.ZERO):
		return false
	return _is_polygon_simple(plot.footprint)


func _has_road_clearance(plot: FieldPlotData, roads: Array, clearance: float) -> bool:
	for point: Vector2 in plot.get_region_outline_2d():
		if _distance_to_roads(point, roads) <= clearance - 0.001:
			return false
	return true


func _field_mask_is_dense(field_cells: Array[Vector2i], plots: Array[FieldPlotData]) -> bool:
	var field_lookup: Dictionary = {}
	for cell: Vector2i in field_cells:
		field_lookup[cell] = true

	var sample_step := 0.8
	for cell: Vector2i in field_cells:
		var min_point := Vector2(float(cell.x) * 4.0, float(cell.y) * 4.0)
		var x := min_point.x + sample_step * 0.5
		while x < min_point.x + 4.0:
			var y := min_point.y + sample_step * 0.5
			while y < min_point.y + 4.0:
				var point := Vector2(x, y)
				if not _is_inside_any_plot(point, plots) and not field_lookup.has(_point_to_cell(point)):
					return false
				y += sample_step
			x += sample_step
	return true


func _is_inside_any_plot(point: Vector2, plots: Array[FieldPlotData]) -> bool:
	for plot: FieldPlotData in plots:
		if plot.contains_region_point(point):
			return true
	return false


func _point_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 4.0), floori(point.y / 4.0))


func _distance_to_roads(point: Vector2, roads: Array) -> float:
	var best := INF
	for road: PackedVector2Array in roads:
		for index: int in range(road.size() - 1):
			best = minf(best, _distance_to_segment(point, road[index], road[index + 1]))
	return best


func _is_polygon_simple(polygon: PackedVector2Array) -> bool:
	for first_index: int in range(polygon.size()):
		var first_from := polygon[first_index]
		var first_to := polygon[(first_index + 1) % polygon.size()]
		for second_index: int in range(first_index + 1, polygon.size()):
			if abs(second_index - first_index) <= 1:
				continue
			if first_index == 0 and second_index == polygon.size() - 1:
				continue
			if _segments_intersect(first_from, first_to, polygon[second_index], polygon[(second_index + 1) % polygon.size()]):
				return false
	return true


func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _cross_2d(b - a, c - a)
	var ab_d := _cross_2d(b - a, d - a)
	var cd_a := _cross_2d(d - c, a - c)
	var cd_b := _cross_2d(d - c, b - c)
	if _opposite_signs(ab_c, ab_d) and _opposite_signs(cd_a, cd_b):
		return true
	if absf(ab_c) <= 0.000001 and _is_point_on_segment(c, a, b):
		return true
	if absf(ab_d) <= 0.000001 and _is_point_on_segment(d, a, b):
		return true
	if absf(cd_a) <= 0.000001 and _is_point_on_segment(a, c, d):
		return true
	if absf(cd_b) <= 0.000001 and _is_point_on_segment(b, c, d):
		return true
	return false


func _opposite_signs(a: float, b: float) -> bool:
	return (a < 0.0 and b > 0.0) or (a > 0.0 and b < 0.0)


func _is_point_on_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> bool:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_squared_to(from_point) <= 0.000001
	var weight := (point - from_point).dot(segment) / length_squared
	if weight < -0.0001 or weight > 1.0001:
		return false
	var closest := from_point + segment * clampf(weight, 0.0, 1.0)
	return point.distance_squared_to(closest) <= 0.000001


func _distance_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from_point)
	var weight := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from_point + segment * weight)


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
