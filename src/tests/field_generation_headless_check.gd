extends SceneTree

const FieldPlotGeneratorScript = preload("res://modules/village/fields/field_plot_generator.gd")
const FieldTerrainRegistryScript = preload("res://modules/village/fields/field_terrain_registry.gd")
const RTSCameraScene = preload("res://modules/camera/rts_camera.tscn")
const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const VILLAGE_RUNTIME_CONTAINER_NAME := "__VillageRuntimeInstances"
const VILLAGE_VISIBLE_DISTANCE_METERS := 800.0
const VILLAGE_VISIBILITY_FADE_MARGIN_METERS := 80.0
const FIELD_SIZE_MULTIPLIER := 4.0
const CAMERA_MAX_DISTANCE := 440.0
const CAMERA_MAX_ZOOM_MOVE_SCALE := 14.0


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
	_expect(VillageRegionScript != null, "village region script failed to preload", failures)
	_expect(_draft_scene_loads_with_startup_safe_terrain(), "draft scene should load with runtime terrain edits disabled for startup", failures)
	_expect(_balanced_render_defaults_are_configured(), "balanced render defaults should be configured", failures)
	_expect(_camera_zoom_defaults_are_configured(), "camera should allow 2x farther max zoom", failures)
	_expect(_village_field_size_defaults_are_scaled(), "village rice field plot defaults should be 4x larger", failures)
	_expect(_village_region_uses_macro_field_data_without_runtime_fields(), "village fields should be macro detail data without runtime field scenes", failures)
	_expect(_village_region_configures_house_visibility(), "village region should configure house distance fade", failures)

	var field_cells := _make_field_cells(20, 14)
	var roads := _make_road_polylines()
	var first_layout := _generate_layout(12345, field_cells, roads)
	var second_layout := _generate_layout(12345, field_cells, roads)
	var different_layout := _generate_layout(54321, field_cells, roads)
	var first: Array = first_layout.get("plots", [])
	var second: Array = second_layout.get("plots", [])
	var different: Array = different_layout.get("plots", [])

	_expect(not first.is_empty(), "expected generated plots", failures)
	_expect(_plot_signature(first) == _plot_signature(second), "same seed must generate identical plots and footprints", failures)
	_expect(_plot_signature(first) != _plot_signature(different), "different seed should change deterministic layout", failures)
	_expect(_has_size_variation(first), "expected multiple distinct plot widths and lengths", failures)
	_expect(_has_valid_polygon_footprints(first), "generated footprints should be valid simple polygons", failures)
	_expect(_has_target_area_distribution(first), "most generated plots should target 300-600 square meters", failures)
	_expect(_plots_follow_road_alignment(first, roads), "plot subdivision should align to the adjacent road direction", failures)
	_expect(_has_generated_bund_lines(first_layout), "field generation should emit paddy bund polylines", failures)

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
	var valid := (
		village_region != null
		and not bool(village_region.get("apply_runtime_terrain_edits"))
		and bool(village_region.get("auto_apply_terrain_textures"))
	)
	draft.free()
	return valid


func _balanced_render_defaults_are_configured() -> bool:
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	var environment_source := FileAccess.get_file_as_string("res://modules/environment/environment_rig.tscn")
	return (
		project_source.contains('run/main_scene="res://modules/loading/boot.tscn"')
		and project_source.contains("run/max_fps=300")
		and project_source.contains("window/vsync/vsync_mode=0")
		and int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)) == 0
		and int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)) == 0
		and bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false))
		and environment_source.contains("sdfgi_enabled = false")
		and environment_source.contains("volumetric_fog_density = 0.0")
		and environment_source.contains("directional_shadow_max_distance = 220.0")
	)


func _camera_zoom_defaults_are_configured() -> bool:
	var camera_rig := RTSCameraScene.instantiate() if RTSCameraScene else null
	if not camera_rig:
		return false

	var valid := (
		is_equal_approx(float(camera_rig.get("max_distance")), CAMERA_MAX_DISTANCE)
		and is_equal_approx(float(camera_rig.get("max_zoom_move_scale")), CAMERA_MAX_ZOOM_MOVE_SCALE)
	)
	camera_rig.free()
	return valid


func _village_field_size_defaults_are_scaled() -> bool:
	var region := VillageRegionScript.new() as VillageRegion
	if not region:
		return false

	var valid := (
		is_equal_approx(float(region.get("field_min_plot_width")), 4.8 * FIELD_SIZE_MULTIPLIER)
		and is_equal_approx(float(region.get("field_max_plot_width")), 11.2 * FIELD_SIZE_MULTIPLIER)
		and is_equal_approx(float(region.get("field_min_plot_length")), 8.0 * FIELD_SIZE_MULTIPLIER)
		and is_equal_approx(float(region.get("field_max_plot_length")), 24.0 * FIELD_SIZE_MULTIPLIER)
	)
	region.free()
	return valid


func _village_region_uses_macro_field_data_without_runtime_fields() -> bool:
	var region := VillageRegionScript.new() as VillageRegion
	if not region:
		return false

	region.set_cell_arrays([], _make_field_cells(16, 12), [])
	region.generation_seed = 2468
	region.auto_apply_terrain_textures = false
	root.add_child(region)
	region.rebuild_runtime_preview()

	var container := region.get_node_or_null(VILLAGE_RUNTIME_CONTAINER_NAME)
	var macro_data := region.get_macro_detail_data()
	var field_generation := macro_data.get("field_generation", {}) as Dictionary
	var plots: Array = field_generation.get("plots", [])
	var generated_cells: Array = field_generation.get("field_cells", [])
	var paddy_renderers := _get_nodes_with_meta(container, &"village_rice_paddy_renderer") if container else []
	var dense_layers := _get_nodes_with_meta(container, &"village_rice_dense_plants_layer") if container else []
	var emitters := _count_descendants_of_type(container, "GPUParticles3D") if container else 0
	var valid := (
		container != null
		and container.get_parent() == region
		and not plots.is_empty()
		and generated_cells.size() == region.get_field_cells().size()
		and paddy_renderers.size() == 1
		and dense_layers.size() == 1
		and emitters > 0
		and _rice_paddy_lod_is_configured(container)
		and _rice_paddy_far_overlay_is_disabled(container)
		and not _has_descendant_name_prefix(container, "Field_")
	)

	region.clear_runtime_instances()
	root.remove_child(region)
	region.free()
	return valid


func _village_region_configures_house_visibility() -> bool:
	var region := VillageRegionScript.new() as VillageRegion
	if not region:
		return false

	region.house_cells = _make_field_cells(10, 10)
	region.road_cells = _make_vertical_road_cells(-2, 0, 10)
	region.generation_seed = 1357
	region.auto_apply_terrain_textures = false
	root.add_child(region)
	region.rebuild_runtime_preview()

	var container := region.get_node_or_null(VILLAGE_RUNTIME_CONTAINER_NAME)
	var house_visibility_checked := false
	var valid := container != null
	if valid:
		for instance: GeometryInstance3D in _collect_geometry_instances(container):
			if not _has_ancestor_name_prefix(instance, "House_"):
				continue
			house_visibility_checked = true
			if not _geometry_visibility_matches(
				instance,
				0.0,
				0.0,
				VILLAGE_VISIBLE_DISTANCE_METERS,
				VILLAGE_VISIBILITY_FADE_MARGIN_METERS
			):
				valid = false
				break

	valid = valid and house_visibility_checked
	region.clear_runtime_instances()
	root.remove_child(region)
	region.free()
	return valid


func _collect_geometry_instances(root_node: Node) -> Array[GeometryInstance3D]:
	var instances: Array[GeometryInstance3D] = []
	if not root_node:
		return instances

	if root_node is GeometryInstance3D:
		instances.append(root_node as GeometryInstance3D)
	for child: Node in root_node.get_children(true):
		instances.append_array(_collect_geometry_instances(child))
	return instances


func _geometry_visibility_matches(
	instance: GeometryInstance3D,
	begin_distance: float,
	begin_margin: float,
	end_distance: float,
	end_margin: float
) -> bool:
	return (
		is_equal_approx(instance.visibility_range_begin, begin_distance)
		and is_equal_approx(instance.visibility_range_begin_margin, begin_margin)
		and is_equal_approx(instance.visibility_range_end, end_distance)
		and is_equal_approx(instance.visibility_range_end_margin, end_margin)
		and instance.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	)


func _has_ancestor_name_prefix(node: Node, prefix: String) -> bool:
	var current := node
	while current:
		if String(current.name).begins_with(prefix):
			return true
		current = current.get_parent()
	return false


func _has_descendant_name_prefix(root_node: Node, prefix: String) -> bool:
	if not root_node:
		return false
	for child: Node in root_node.get_children(true):
		if String(child.name).begins_with(prefix):
			return true
		if _has_descendant_name_prefix(child, prefix):
			return true
	return false


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


func _rice_paddy_lod_is_configured(root_node: Node) -> bool:
	if not root_node:
		return false

	return _rice_paddy_particles_lod_is_configured(root_node)


func _rice_paddy_particles_lod_is_configured(root_node: Node) -> bool:
	var particles_nodes := _collect_rice_particles(root_node)
	if particles_nodes.is_empty():
		return false

	for particles: GPUParticles3D in particles_nodes:
		if not bool(particles.get_meta(&"village_preserve_visibility_range", false)):
			return false
		if particles.visibility_range_begin > 0.001:
			return false
		if particles.visibility_range_end <= 0.0:
			return false
		if particles.visibility_range_end > VILLAGE_VISIBLE_DISTANCE_METERS:
			return false

	return true


func _rice_paddy_far_overlay_is_disabled(root_node: Node) -> bool:
	var overlays := _get_nodes_with_meta(root_node, &"village_rice_paddy_far_overlay")
	for overlay_node: Node in overlays:
		if overlay_node is MeshInstance3D:
			var overlay := overlay_node as MeshInstance3D
			if overlay.visible or overlay.mesh != null:
				return false
		elif overlay_node is GeometryInstance3D and (overlay_node as GeometryInstance3D).visible:
			return false
	return true


func _collect_rice_particles(root_node: Node) -> Array[GPUParticles3D]:
	var particles_nodes: Array[GPUParticles3D] = []
	for child: Node in root_node.get_children(true):
		if child is GPUParticles3D and _has_ancestor_name_prefix(child, "RiceDensePlantsParticles"):
			particles_nodes.append(child as GPUParticles3D)
		particles_nodes.append_array(_collect_rice_particles(child))
	return particles_nodes


func _generate_plots(seed: int, field_cells: Array[Vector2i], roads: Array) -> Array[FieldPlotData]:
	return _generate_layout(seed, field_cells, roads).get("plots", [])


func _generate_layout(seed: int, field_cells: Array[Vector2i], roads: Array) -> Dictionary:
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
	generator.target_plot_area_min_m2 = 300.0
	generator.target_plot_area_max_m2 = 600.0
	generator.preferred_plot_area_m2 = 450.0
	return {
		"plots": generator.generate(field_cells, roads),
		"field_road_polylines": generator.generated_road_polylines.duplicate(true),
		"field_bund_polylines": generator.generated_bund_polylines.duplicate(true),
	}


func _make_field_cells(width: int, height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(width):
		for y: int in range(height):
			cells.append(Vector2i(x, y))
	return cells


func _make_vertical_road_cells(x: int, y_from: int, y_count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(y_from, y_from + y_count):
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


func _has_valid_polygon_footprints(plots: Array) -> bool:
	if plots.is_empty():
		return false

	for plot: FieldPlotData in plots:
		if not _is_footprint_valid(plot):
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
	if plot.footprint.size() < 3:
		return false
	if plot.area <= 0.001:
		return false

	if not plot.contains_local_point(Vector2.ZERO):
		return false
	return _is_polygon_simple(plot.footprint)


func _has_target_area_distribution(plots: Array) -> bool:
	if plots.is_empty():
		return false

	var in_target := 0
	for plot: FieldPlotData in plots:
		if plot.area >= 300.0 and plot.area <= 600.0:
			in_target += 1
		elif plot.area > 900.0:
			return false
	return float(in_target) / float(plots.size()) >= 0.65


func _plots_follow_road_alignment(plots: Array, roads: Array) -> bool:
	for plot: FieldPlotData in plots:
		var row_direction := Vector2(plot.row_direction.x, plot.row_direction.z).normalized()
		var tangent := _nearest_road_tangent(Vector2(plot.center.x, plot.center.z), roads)
		if tangent.length_squared() <= 0.0001:
			continue
		if absf(row_direction.dot(tangent.normalized())) < 0.92:
			return false
	return true


func _has_generated_bund_lines(layout: Dictionary) -> bool:
	var bunds: Array = layout.get("field_bund_polylines", [])
	var plots: Array = layout.get("plots", [])
	return not plots.is_empty() and bunds.size() >= plots.size()


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


func _nearest_road_tangent(point: Vector2, roads: Array) -> Vector2:
	var best_tangent := Vector2.ZERO
	var best_distance := INF
	for road: PackedVector2Array in roads:
		for index: int in range(road.size() - 1):
			var from_point := road[index]
			var to_point := road[index + 1]
			var distance := _distance_to_segment(point, from_point, to_point)
			if distance < best_distance:
				best_distance = distance
				var tangent := to_point - from_point
				best_tangent = tangent.normalized() if tangent.length_squared() > 0.0001 else Vector2.ZERO
	return best_tangent


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
