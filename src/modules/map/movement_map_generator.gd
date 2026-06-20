@tool
extends Node
class_name MovementMapGenerator

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")

const MIN_TERRAIN_SPEED_MULTIPLIER := 0.45
const WATER_EMPTY_EPSILON := 0.001
const WATER_ALPHA_EPSILON := 0.001
const INVALID_TERRAIN_HEIGHT := 1.0e30

@export_node_path("Node3D") var terrain_path: NodePath
@export_node_path("Node3D") var water_system_path: NodePath
@export var forest_region_paths: Array[NodePath] = []
@export var village_region_paths: Array[NodePath] = []
@export var auto_discover_regions := true
@export_file("*.res", "*.tres") var movement_map_path: String = ""
@export_range(0.5, 256.0, 0.5, "or_greater") var sample_size_meters: float = 16.0
@export_range(1, 8192, 1, "or_greater") var max_grid_size: int = 4096
@export_range(1024, 4194304, 1024, "or_greater") var max_generated_cells: int = 4194304
@export_range(0.0, 89.0, 0.1) var max_walkable_slope_degrees: float = 35.0
@export_range(0.01, 1.0, 0.01) var shallow_water_speed_multiplier: float = 0.35
@export_range(0.01, 1.0, 0.01) var forest_speed_multiplier: float = 0.65
@export_range(1.0, 4.0, 0.01, "or_greater") var road_speed_multiplier: float = 1.35
@export var last_generation_summary := ""
@export_tool_button("Generate Now") var generate_now_button: Callable = generate_movement_map_now

var generate_now := false:
	set(value):
		if value is bool and value:
			generate_movement_map_now()
		generate_now = false

var _last_generated_data: Resource


func generate_movement_map_now() -> void:
	var error := generate_and_save()
	if error == OK:
		print("MovementMapGenerator saved %s. %s" % [_get_resolved_movement_map_path(), last_generation_summary])
	else:
		push_error("MovementMapGenerator Generate Now failed: %d" % error)
	notify_property_list_changed()


func generate_and_save() -> int:
	var data := generate_movement_map()
	if not data:
		return ERR_CANT_CREATE

	var output_path := _get_resolved_movement_map_path()
	var path_error := _validate_resource_path(output_path)
	if path_error != OK:
		return path_error

	var error := ResourceSaver.save(data, output_path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("MovementMapGenerator could not save %s: %d" % [output_path, error])
		return error

	_last_generated_data = data
	_refresh_matching_overlays(output_path)
	return OK


func generate_movement_map() -> Resource:
	var terrain := _get_node_from_path(terrain_path) as Node3D
	if not terrain:
		push_warning("MovementMapGenerator terrain_path does not resolve to a Node3D.")
		return null

	var bounds_info := _calculate_terrain_world_bounds(terrain)
	if not bool(bounds_info.get("valid", false)):
		push_warning("MovementMapGenerator could not calculate Terrain3D bounds.")
		return null

	var world_rect := bounds_info.get("rect", Rect2()) as Rect2
	var requested_sample := maxf(sample_size_meters, 0.1)
	var effective_sample := _calculate_effective_sample_size(world_rect)
	var width := maxi(ceili(world_rect.size.x / effective_sample), 1)
	var height := maxi(ceili(world_rect.size.y / effective_sample), 1)
	var safe_max_grid_size := maxi(max_grid_size, 1)
	var safe_max_generated_cells := maxi(max_generated_cells, 1)
	while width > safe_max_grid_size or height > safe_max_grid_size or width * height > safe_max_generated_cells:
		var grid_scale := maxf(float(width) / float(safe_max_grid_size), float(height) / float(safe_max_grid_size))
		var cell_scale := sqrt(float(width * height) / float(safe_max_generated_cells))
		effective_sample *= maxf(maxf(grid_scale, cell_scale), 1.01)
		width = maxi(ceili(world_rect.size.x / effective_sample), 1)
		height = maxi(ceili(world_rect.size.y / effective_sample), 1)

	last_generation_summary = _format_generation_summary(width, height, requested_sample, effective_sample)

	var data: Resource = MovementMapDataScript.new()
	data.set("origin", world_rect.position)
	data.set("cell_size_meters", effective_sample)
	data.call("resize_map", width, height, 1.0, 0)
	var speed_multipliers: PackedFloat32Array = data.get("speed_multipliers") as PackedFloat32Array
	var flag_array: PackedByteArray = data.get("flags") as PackedByteArray

	var terrain_data := _get_terrain_data(terrain)
	var terrain_info := _build_terrain_cell_info(terrain_data, world_rect, width, height, effective_sample)
	var terrain_speeds: PackedFloat32Array = terrain_info.get("speeds", PackedFloat32Array()) as PackedFloat32Array
	var terrain_flags: PackedByteArray = terrain_info.get("flags", PackedByteArray()) as PackedByteArray
	var water_info := _collect_water_info(_get_node_from_path(water_system_path) as Node3D, effective_sample)
	var forest_sources := _collect_forest_sources()
	var village_sources := _collect_village_sources()
	var water_mask := _build_water_mask(world_rect, width, height, effective_sample, water_info)
	var forest_mask := _build_forest_mask(world_rect, width, height, effective_sample, forest_sources)
	var road_mask := _build_village_road_mask(world_rect, width, height, effective_sample, village_sources)

	for index: int in range(width * height):
		var flags_value := int(terrain_flags[index])
		var speed := terrain_speeds[index]
		var is_water := water_mask[index] != 0

		if is_water:
			flags_value |= MovementMapDataScript.FLAG_RIVER
			if speed > 0.0:
				speed *= shallow_water_speed_multiplier

		if forest_mask[index] != 0:
			flags_value |= MovementMapDataScript.FLAG_FOREST
			if speed > 0.0:
				speed *= forest_speed_multiplier

		if road_mask[index] != 0:
			flags_value |= MovementMapDataScript.FLAG_ROAD
			if speed > 0.0 and not is_water:
				speed = maxf(speed, road_speed_multiplier)

		flag_array[index] = clampi(flags_value, 0, 255)
		speed_multipliers[index] = speed

	data.set("flags", flag_array)
	data.set("speed_multipliers", speed_multipliers)
	_last_generated_data = data
	return data


func get_last_generated_data() -> Resource:
	return _last_generated_data


func _format_generation_summary(width: int, height: int, requested_sample: float, effective_sample: float) -> String:
	var summary := "%dx%d cells (%d total) at %.2fm effective samples" % [width, height, width * height, effective_sample]
	if not is_equal_approx(requested_sample, effective_sample):
		summary += " (requested %.2fm; raised by max_grid_size/max_generated_cells)" % requested_sample
	return summary


func _refresh_matching_overlays(saved_path: String) -> void:
	var root := _get_discovery_root()
	if root:
		_refresh_matching_overlays_recursive(root, saved_path)


func _refresh_matching_overlays_recursive(node: Node, saved_path: String) -> void:
	if not node:
		return

	if node != self and node.has_method("reload_movement_map") and _object_has_property(node, &"movement_map_path"):
		if String(node.get("movement_map_path")) == saved_path:
			node.call("reload_movement_map", true)

	for child: Node in node.get_children():
		_refresh_matching_overlays_recursive(child, saved_path)


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if not object:
		return false
	for property_info: Dictionary in object.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func get_default_movement_map_path() -> String:
	var scene_path := ""
	if owner and not owner.scene_file_path.is_empty():
		scene_path = owner.scene_file_path
	elif get_tree() and get_tree().current_scene and not get_tree().current_scene.scene_file_path.is_empty():
		scene_path = get_tree().current_scene.scene_file_path
	if scene_path.is_empty():
		return "res://movement_map.res"
	return "%s_movement_map.res" % scene_path.get_basename()


func _get_node_from_path(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _get_resolved_movement_map_path() -> String:
	if not movement_map_path.is_empty():
		return movement_map_path
	return get_default_movement_map_path()


func _validate_resource_path(path: String) -> int:
	if path.is_empty() or (not path.begins_with("res://") and not path.begins_with("user://")):
		push_error("MovementMapGenerator movement_map_path must be a res:// or user:// resource path.")
		return ERR_INVALID_PARAMETER
	var extension := path.get_extension().to_lower()
	if extension != "res" and extension != "tres":
		push_error("MovementMapGenerator movement_map_path must end in .res or .tres.")
		return ERR_INVALID_PARAMETER
	return OK


func _calculate_effective_sample_size(bounds: Rect2) -> float:
	var safe_sample := maxf(sample_size_meters, 0.1)
	var safe_max_grid_size := maxi(max_grid_size, 1)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return safe_sample
	return maxf(
		safe_sample,
		maxf(bounds.size.x, bounds.size.y) / float(safe_max_grid_size)
	)


func _calculate_terrain_world_bounds(terrain: Node3D) -> Dictionary:
	var terrain_data := _get_terrain_data(terrain)
	if not terrain_data or not terrain_data.has_method("get_region_locations"):
		return {"valid": false, "rect": Rect2()}

	var locations: Variant = terrain_data.call("get_region_locations")
	if not (locations is Array) and not (locations is PackedVector2Array):
		return {"valid": false, "rect": Rect2()}

	var region_world_size := 1024.0
	if terrain.has_method("get_region_size") and terrain.has_method("get_vertex_spacing"):
		region_world_size = maxf(float(terrain.call("get_region_size")) * float(terrain.call("get_vertex_spacing")), 0.001)
	else:
		region_world_size = maxf(float(terrain.get("region_size")) * float(terrain.get("vertex_spacing")), 0.001)

	var has_bounds := false
	var rect := Rect2()
	for location_variant: Variant in locations:
		var location := _variant_to_vector2(location_variant)
		var min_point := Vector3(location.x * region_world_size, 0.0, location.y * region_world_size)
		var max_point := min_point + Vector3(region_world_size, 0.0, region_world_size)
		var region_rect := _world_rect_for_local_points(terrain, [
			Vector2(min_point.x, min_point.z),
			Vector2(max_point.x, min_point.z),
			Vector2(max_point.x, max_point.z),
			Vector2(min_point.x, max_point.z),
		])
		if not has_bounds:
			rect = region_rect
			has_bounds = true
		else:
			rect = rect.merge(region_rect)

	return {"valid": has_bounds, "rect": rect}


func _world_rect_for_local_points(terrain: Node3D, points: Array[Vector2]) -> Rect2:
	var has_bounds := false
	var rect := Rect2()
	for point: Vector2 in points:
		var world := terrain.global_transform * Vector3(point.x, 0.0, point.y) if terrain.is_inside_tree() else terrain.transform * Vector3(point.x, 0.0, point.y)
		var world_2d := Vector2(world.x, world.z)
		if not has_bounds:
			rect = Rect2(world_2d, Vector2.ZERO)
			has_bounds = true
		else:
			rect = rect.expand(world_2d)
	return rect


func _variant_to_vector2(value: Variant) -> Vector2:
	if value is Vector2i:
		var point_i := value as Vector2i
		return Vector2(point_i.x, point_i.y)
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO


func _get_terrain_data(terrain: Node3D) -> Object:
	if not is_instance_valid(terrain):
		return null
	var terrain_data: Variant = terrain.get("data")
	if not (terrain_data is Object):
		return null
	return terrain_data as Object


func _build_terrain_cell_info(terrain_data: Object, world_rect: Rect2, width: int, height: int, cell_size: float) -> Dictionary:
	var cell_count := width * height
	var speeds := PackedFloat32Array()
	var flags := PackedByteArray()
	speeds.resize(cell_count)
	flags.resize(cell_count)
	if not _terrain_data_can_sample_height(terrain_data):
		return {"speeds": speeds, "flags": flags}

	var center_heights := PackedFloat32Array()
	center_heights.resize(cell_count)

	for y: int in range(height):
		var center_z := world_rect.position.y + (float(y) + 0.5) * cell_size
		for x: int in range(width):
			center_heights[y * width + x] = _get_terrain_height_fast(
				terrain_data,
				Vector2(world_rect.position.x + (float(x) + 0.5) * cell_size, center_z)
			)

	var safe_cell_size := maxf(cell_size, 0.001)
	for y: int in range(height):
		for x: int in range(width):
			var index := y * width + x
			var center_height := center_heights[index]
			if not _is_valid_cached_terrain_height(center_height):
				continue

			var west_index := index - 1 if x > 0 else index
			var east_index := index + 1 if x < width - 1 else index
			var north_index := index - width if y > 0 else index
			var south_index := index + width if y < height - 1 else index
			var west_height := center_heights[west_index]
			var east_height := center_heights[east_index]
			var north_height := center_heights[north_index]
			var south_height := center_heights[south_index]
			if (
				not _is_valid_cached_terrain_height(west_height)
				or not _is_valid_cached_terrain_height(east_height)
				or not _is_valid_cached_terrain_height(north_height)
				or not _is_valid_cached_terrain_height(south_height)
			):
				continue

			var x_distance := safe_cell_size * float(east_index - west_index)
			var z_distance := safe_cell_size * float((south_index - north_index) / width) if width > 0 else safe_cell_size
			var dh_dx := 0.0 if x_distance <= 0.001 else absf(east_height - west_height) / x_distance
			var dh_dz := 0.0 if z_distance <= 0.001 else absf(south_height - north_height) / z_distance
			var grade := sqrt(dh_dx * dh_dx + dh_dz * dh_dz)
			var slope_degrees := rad_to_deg(atan(grade))
			if slope_degrees > max_walkable_slope_degrees:
				flags[index] = MovementMapDataScript.FLAG_STEEP_SLOPE
				continue

			var slope_ratio := 0.0
			if max_walkable_slope_degrees > 0.001:
				slope_ratio = clampf(slope_degrees / max_walkable_slope_degrees, 0.0, 1.0)
			speeds[index] = lerpf(1.0, MIN_TERRAIN_SPEED_MULTIPLIER, slope_ratio)

	return {"speeds": speeds, "flags": flags}


func _terrain_data_can_sample_height(terrain_data: Object) -> bool:
	if not terrain_data or not terrain_data.has_method("get_height"):
		return false
	if terrain_data.has_method("get_region_count") and int(terrain_data.call("get_region_count")) <= 0:
		return false
	return true


func _get_terrain_height_fast(terrain_data: Object, world_point: Vector2) -> float:
	var height := float(terrain_data.call("get_height", Vector3(world_point.x, 0.0, world_point.y)))
	if is_nan(height) or absf(height) > 1.0e20:
		return INVALID_TERRAIN_HEIGHT
	return height


func _is_valid_cached_terrain_height(height: float) -> bool:
	return not is_nan(height) and absf(height) < 1.0e20


func _sample_terrain_cell(terrain_data: Object, world_point: Vector2, cell_size: float) -> Dictionary:
	var center_height: Variant = _get_terrain_height(terrain_data, world_point)
	if center_height == null:
		return {"speed": 0.0, "flags": 0}

	var delta := maxf(cell_size * 0.5, 0.1)
	var east_height: Variant = _get_terrain_height(terrain_data, world_point + Vector2(delta, 0.0))
	var west_height: Variant = _get_terrain_height(terrain_data, world_point + Vector2(-delta, 0.0))
	var north_height: Variant = _get_terrain_height(terrain_data, world_point + Vector2(0.0, -delta))
	var south_height: Variant = _get_terrain_height(terrain_data, world_point + Vector2(0.0, delta))
	if east_height == null or west_height == null or north_height == null or south_height == null:
		return {"speed": 0.0, "flags": 0}

	var dh_dx := absf(float(east_height) - float(west_height)) / (delta * 2.0)
	var dh_dz := absf(float(south_height) - float(north_height)) / (delta * 2.0)
	var grade := sqrt(dh_dx * dh_dx + dh_dz * dh_dz)
	var slope_degrees := rad_to_deg(atan(grade))
	if slope_degrees > max_walkable_slope_degrees:
		return {"speed": 0.0, "flags": MovementMapDataScript.FLAG_STEEP_SLOPE}

	var slope_ratio := 0.0
	if max_walkable_slope_degrees > 0.001:
		slope_ratio = clampf(slope_degrees / max_walkable_slope_degrees, 0.0, 1.0)
	var speed := lerpf(1.0, MIN_TERRAIN_SPEED_MULTIPLIER, slope_ratio)
	return {"speed": speed, "flags": 0}


func _get_terrain_height(terrain_data: Object, world_point: Vector2) -> Variant:
	if not terrain_data or not terrain_data.has_method("get_height"):
		return null
	if terrain_data.has_method("get_region_count") and int(terrain_data.call("get_region_count")) <= 0:
		return null
	var height := float(terrain_data.call("get_height", Vector3(world_point.x, 0.0, world_point.y)))
	if is_nan(height) or absf(height) > 1.0e20:
		return null
	return height


func _collect_water_info(water_system: Node3D, effective_sample_size: float) -> Dictionary:
	var info := {
		"has_baked_map": false,
		"image": null,
		"aabb_position": Vector3.ZERO,
		"aabb_size": Vector3.ZERO,
		"alpha_is_meaningful": false,
		"rivers": [],
	}
	if not is_instance_valid(water_system):
		return info

	var map_texture: Texture2D
	if water_system.has_method("get_system_map"):
		map_texture = water_system.call("get_system_map") as Texture2D
	else:
		map_texture = water_system.get("system_map") as Texture2D
	if map_texture:
		var image := map_texture.get_image()
		var aabb := _get_water_system_aabb(water_system)
		if image and image.get_width() > 0 and image.get_height() > 0 and aabb.size.length_squared() > 0.0:
			info["has_baked_map"] = true
			info["image"] = image
			info["aabb_position"] = aabb.position
			info["aabb_size"] = aabb.size
			info["alpha_is_meaningful"] = _water_map_alpha_is_meaningful(image)
			return info

	info["rivers"] = _collect_river_sources(water_system, effective_sample_size)
	return info


func _get_water_system_aabb(water_system: Node3D) -> AABB:
	if water_system.has_method("get_system_map_coordinates"):
		var coords_variant: Variant = water_system.call("get_system_map_coordinates")
		if coords_variant is Transform3D:
			var coords := coords_variant as Transform3D
			return AABB(coords.basis.x, coords.basis.y)

	var aabb_variant: Variant = water_system.get("_system_aabb")
	if aabb_variant is AABB:
		return aabb_variant as AABB
	return AABB()


func _is_water_blocked(world_point: Vector2, water_info: Dictionary) -> bool:
	if bool(water_info.get("has_baked_map", false)):
		return _is_water_blocked_by_baked_map(world_point, water_info)

	var rivers: Array = water_info.get("rivers", [])
	for river_variant: Variant in rivers:
		var river := river_variant as Dictionary
		var bounds := river.get("bounds", Rect2()) as Rect2
		if not bounds.has_point(world_point):
			continue
		if _is_point_inside_river(world_point, river):
			return true
	return false


func _build_water_mask(world_rect: Rect2, width: int, height: int, cell_size: float, water_info: Dictionary) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width * height)
	if bool(water_info.get("has_baked_map", false)):
		return _build_baked_water_mask(mask, world_rect, width, height, cell_size, water_info)
	return _build_river_water_mask(mask, world_rect, width, height, cell_size, water_info)


func _build_baked_water_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	water_info: Dictionary
) -> PackedByteArray:
	var image := water_info.get("image") as Image
	if not image:
		return mask

	var aabb_position := water_info.get("aabb_position", Vector3.ZERO) as Vector3
	var aabb_size := water_info.get("aabb_size", Vector3.ZERO) as Vector3
	var longest_axis := maxf(maxf(aabb_size.x, aabb_size.y), aabb_size.z)
	if longest_axis <= 0.001:
		return mask

	var image_width := image.get_width()
	var image_height := image.get_height()
	if image_width <= 0 or image_height <= 0:
		return mask

	var alpha_is_meaningful := bool(water_info.get("alpha_is_meaningful", false))
	for y: int in range(height):
		var world_y := world_rect.position.y + (float(y) + 0.5) * cell_size
		var uv_y := (world_y - aabb_position.z) / longest_axis
		if uv_y < 0.0 or uv_y > 1.0:
			continue
		var pixel_y := clampi(floori(uv_y * float(image_height)), 0, image_height - 1)
		for x: int in range(width):
			var world_x := world_rect.position.x + (float(x) + 0.5) * cell_size
			var uv_x := (world_x - aabb_position.x) / longest_axis
			if uv_x < 0.0 or uv_x > 1.0:
				continue
			var pixel_x := clampi(floori(uv_x * float(image_width)), 0, image_width - 1)
			var pixel := image.get_pixel(pixel_x, pixel_y)
			if alpha_is_meaningful:
				if pixel.a > WATER_ALPHA_EPSILON:
					mask[y * width + x] = 1
			elif pixel.r + pixel.g + pixel.b > WATER_EMPTY_EPSILON:
				mask[y * width + x] = 1
	return mask


func _build_river_water_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	water_info: Dictionary
) -> PackedByteArray:
	var rivers: Array = water_info.get("rivers", [])
	for river_variant: Variant in rivers:
		var river := river_variant as Dictionary
		var bounds := river.get("bounds", Rect2()) as Rect2
		var cell_bounds := _movement_cell_bounds_for_world_rect(bounds, world_rect, width, height, cell_size)
		if not cell_bounds.has_area():
			continue
		for y: int in range(cell_bounds.position.y, cell_bounds.end.y):
			for x: int in range(cell_bounds.position.x, cell_bounds.end.x):
				var index := y * width + x
				if mask[index] != 0:
					continue
				var world_point := world_rect.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size
				if _is_point_inside_river(world_point, river):
					mask[index] = 1
	return mask


func _is_water_blocked_by_baked_map(world_point: Vector2, water_info: Dictionary) -> bool:
	var image := water_info.get("image") as Image
	if not image:
		return false

	var aabb_position := water_info.get("aabb_position", Vector3.ZERO) as Vector3
	var aabb_size := water_info.get("aabb_size", Vector3.ZERO) as Vector3
	var longest_axis := maxf(maxf(aabb_size.x, aabb_size.y), aabb_size.z)
	if longest_axis <= 0.001:
		return false

	var uv := Vector2(world_point.x - aabb_position.x, world_point.y - aabb_position.z) / longest_axis
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return false

	var x := clampi(floori(uv.x * float(image.get_width())), 0, image.get_width() - 1)
	var y := clampi(floori(uv.y * float(image.get_height())), 0, image.get_height() - 1)
	var pixel := image.get_pixel(x, y)
	if bool(water_info.get("alpha_is_meaningful", false)):
		return pixel.a > WATER_ALPHA_EPSILON
	return pixel.r + pixel.g + pixel.b > WATER_EMPTY_EPSILON


func _water_map_alpha_is_meaningful(image: Image) -> bool:
	if not image:
		return false
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a < 1.0 - WATER_ALPHA_EPSILON:
				return true
	return false


func _collect_river_sources(water_system: Node, effective_sample_size: float) -> Array[Dictionary]:
	var rivers: Array[Dictionary] = []
	_collect_river_sources_recursive(water_system, effective_sample_size, rivers)
	return rivers


func _collect_river_sources_recursive(node: Node, effective_sample_size: float, rivers: Array[Dictionary]) -> void:
	if not node:
		return
	var curve := node.get("curve") as Curve3D
	if curve and curve.get_point_count() > 0:
		var river := _build_river_source(node as Node3D, curve, node.get("widths"), effective_sample_size)
		if not river.is_empty():
			rivers.append(river)

	for child: Node in node.get_children():
		_collect_river_sources_recursive(child, effective_sample_size, rivers)


func _build_river_source(node: Node3D, curve: Curve3D, widths_variant: Variant, effective_sample_size: float) -> Dictionary:
	if not node:
		return {}

	var widths: Array[float] = []
	if widths_variant is Array:
		for width_variant: Variant in widths_variant:
			widths.append(maxf(float(width_variant), 0.0))
	if widths.is_empty():
		widths.append(1.0)

	var baked_length := maxf(curve.get_baked_length(), 0.0)
	var spacing := maxf(effective_sample_size * 0.5, 4.0)
	var sample_count := maxi(ceili(baked_length / spacing) + 1, 2)
	var points := PackedVector2Array()
	var point_widths := PackedFloat32Array()
	var bounds := Rect2()
	var has_bounds := false
	var max_radius := 0.5

	for index: int in range(sample_count):
		var ratio := float(index) / float(sample_count - 1)
		var distance := baked_length * ratio
		var local_point := curve.sample_baked(distance, false)
		var world := node.global_transform * local_point if node.is_inside_tree() else node.transform * local_point
		var point := Vector2(world.x, world.z)
		var width := _interpolate_width(widths, ratio)
		points.append(point)
		point_widths.append(width)
		max_radius = maxf(max_radius, width * 0.5)
		if not has_bounds:
			bounds = Rect2(point, Vector2.ZERO)
			has_bounds = true
		else:
			bounds = bounds.expand(point)

	if not has_bounds:
		return {}

	return {
		"points": points,
		"widths": point_widths,
		"bounds": bounds.grow(max_radius + effective_sample_size),
	}


func _interpolate_width(widths: Array[float], ratio: float) -> float:
	if widths.is_empty():
		return 1.0
	if widths.size() == 1:
		return widths[0]
	var scaled := clampf(ratio, 0.0, 1.0) * float(widths.size() - 1)
	var index := clampi(floori(scaled), 0, widths.size() - 1)
	var next_index := mini(index + 1, widths.size() - 1)
	return lerpf(widths[index], widths[next_index], scaled - float(index))


func _is_point_inside_river(world_point: Vector2, river: Dictionary) -> bool:
	var points := river.get("points", PackedVector2Array()) as PackedVector2Array
	var widths := river.get("widths", PackedFloat32Array()) as PackedFloat32Array
	if points.is_empty():
		return false
	if points.size() == 1:
		var radius := maxf((widths[0] if not widths.is_empty() else 1.0) * 0.5, 0.01)
		return world_point.distance_squared_to(points[0]) <= radius * radius

	for index: int in range(points.size() - 1):
		var radius := maxf(_segment_width_at_point(world_point, points[index], points[index + 1], widths, index) * 0.5, 0.01)
		if _distance_to_segment(world_point, points[index], points[index + 1]) <= radius:
			return true
	return false


func _segment_width_at_point(point: Vector2, from_point: Vector2, to_point: Vector2, widths: PackedFloat32Array, index: int) -> float:
	if widths.is_empty():
		return 1.0
	var start_width := widths[clampi(index, 0, widths.size() - 1)]
	var end_width := widths[clampi(index + 1, 0, widths.size() - 1)]
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return start_width
	var weight := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return lerpf(start_width, end_width, weight)


func _collect_forest_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for region: Node in _get_regions(forest_region_paths, "ForestRegion"):
		var data := _get_region_runtime_data(region)
		if data.is_empty():
			continue
		sources.append({
			"global_transform": data.get("global_transform", Transform3D.IDENTITY),
			"inverse": (data.get("global_transform", Transform3D.IDENTITY) as Transform3D).affine_inverse(),
			"origin": data.get("origin", Vector3.ZERO),
			"cell_size": maxf(float(data.get("cell_size", 4.0)), 0.1),
			"cells": _variant_to_cell_lookup(data.get("forest_cells", [])),
		})
	return sources


func _collect_village_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for region: Node in _get_regions(village_region_paths, "VillageRegion"):
		var data := _get_village_runtime_data(region)
		if data.is_empty():
			continue

		var transform := data.get("global_transform", Transform3D.IDENTITY) as Transform3D
		var field_generation := data.get("field_generation", {}) as Dictionary
		var road_lines: Array[Dictionary] = []
		_append_road_lines(road_lines, data.get("road_polylines", []), maxf(float(data.get("road_width", 3.2)), 0.05))
		var field_width := maxf(maxf(float(data.get("field_road_gap_width", 1.2)), float(data.get("field_bund_gap", 0.35))), 0.05)
		_append_road_lines(road_lines, field_generation.get("field_road_polylines", []), field_width)

		sources.append({
			"global_transform": transform,
			"inverse": transform.affine_inverse(),
			"origin": data.get("origin", Vector3.ZERO),
			"cell_size": maxf(float(data.get("cell_size", 4.0)), 0.1),
			"road_cells": _variant_to_cell_lookup(data.get("road_cells", [])),
			"road_lines": road_lines,
		})
	return sources


func _get_region_runtime_data(region: Node) -> Dictionary:
	if not region:
		return {}
	if region.has_method("to_runtime_data"):
		var runtime_data: Variant = region.call("to_runtime_data")
		return runtime_data if runtime_data is Dictionary else {}
	return {}


func _get_village_runtime_data(region: Node) -> Dictionary:
	if region and region.has_method("get_macro_detail_data"):
		var macro_data: Variant = region.call("get_macro_detail_data")
		if macro_data is Dictionary:
			return macro_data as Dictionary
	return _get_region_runtime_data(region)


func _append_road_lines(lines: Array[Dictionary], polylines_variant: Variant, width: float) -> void:
	if not (polylines_variant is Array):
		return
	for polyline_variant: Variant in polylines_variant:
		if polyline_variant is PackedVector2Array:
			var polyline := polyline_variant as PackedVector2Array
			if not polyline.is_empty():
				lines.append({"polyline": polyline, "width": width})


func _get_regions(paths: Array[NodePath], class_name_value: String) -> Array[Node]:
	var regions: Array[Node] = []
	for path: NodePath in paths:
		var node := get_node_or_null(path)
		if node and not regions.has(node):
			regions.append(node)

	if regions.is_empty() and auto_discover_regions:
		_collect_regions_by_class(_get_discovery_root(), class_name_value, regions)
	return regions


func _get_discovery_root() -> Node:
	if is_inside_tree():
		var tree := get_tree()
		if tree and tree.current_scene:
			return tree.current_scene
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


func _variant_to_cell_lookup(cells_variant: Variant) -> Dictionary:
	var lookup: Dictionary = {}
	if not (cells_variant is Array):
		return lookup
	for cell_variant: Variant in cells_variant:
		if cell_variant is Vector2i:
			lookup[cell_variant as Vector2i] = true
	return lookup


func _is_point_in_forest(world_point: Vector2, forest_sources: Array[Dictionary]) -> bool:
	for source: Dictionary in forest_sources:
		var local_point := _world_to_source_local_2d(world_point, source)
		var cell := _local_point_to_cell(local_point, source.get("origin", Vector3.ZERO), float(source.get("cell_size", 4.0)))
		var cells := source.get("cells", {}) as Dictionary
		if cells.has(cell):
			return true
	return false


func _build_forest_mask(world_rect: Rect2, width: int, height: int, cell_size: float, forest_sources: Array[Dictionary]) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width * height)
	if forest_sources.is_empty():
		return mask

	for source: Dictionary in forest_sources:
		var cells := source.get("cells", {}) as Dictionary
		for cell_variant: Variant in cells.keys():
			if cell_variant is Vector2i:
				mask = _mark_source_cell_mask(mask, world_rect, width, height, cell_size, source, cell_variant as Vector2i)
	return mask


func _mark_source_cell_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	source: Dictionary,
	source_cell: Vector2i
) -> PackedByteArray:
	var origin := source.get("origin", Vector3.ZERO) as Vector3
	var source_cell_size := maxf(float(source.get("cell_size", 4.0)), 0.1)
	var min_local := Vector2(
		origin.x + float(source_cell.x) * source_cell_size,
		origin.z + float(source_cell.y) * source_cell_size
	)
	var max_local := min_local + Vector2(source_cell_size, source_cell_size)
	var world_a := _source_local_to_world_2d(min_local, source)
	var world_b := _source_local_to_world_2d(Vector2(max_local.x, min_local.y), source)
	var world_c := _source_local_to_world_2d(max_local, source)
	var world_d := _source_local_to_world_2d(Vector2(min_local.x, max_local.y), source)
	var bounds := Rect2(world_a, Vector2.ZERO).expand(world_b).expand(world_c).expand(world_d).grow(cell_size)
	var cell_bounds := _movement_cell_bounds_for_world_rect(bounds, world_rect, width, height, cell_size)
	if not cell_bounds.has_area():
		return mask

	for y: int in range(cell_bounds.position.y, cell_bounds.end.y):
		for x: int in range(cell_bounds.position.x, cell_bounds.end.x):
			var index := y * width + x
			if mask[index] != 0:
				continue
			var sample_world := world_rect.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size
			var sample_local := _world_to_source_local_2d(sample_world, source)
			if _local_point_to_cell(sample_local, origin, source_cell_size) == source_cell:
				mask[index] = 1
	return mask


func _build_village_road_mask(world_rect: Rect2, width: int, height: int, cell_size: float, village_sources: Array[Dictionary]) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width * height)
	if village_sources.is_empty():
		return mask

	for source: Dictionary in village_sources:
		var road_cells := source.get("road_cells", {}) as Dictionary
		for road_cell_variant: Variant in road_cells.keys():
			if road_cell_variant is Vector2i:
				mask = _mark_road_cell_mask(mask, world_rect, width, height, cell_size, source, road_cell_variant as Vector2i)

	for source: Dictionary in village_sources:
		var road_lines: Array = source.get("road_lines", [])
		for line_variant: Variant in road_lines:
			var line := line_variant as Dictionary
			var polyline := line.get("polyline", PackedVector2Array()) as PackedVector2Array
			var road_width := maxf(float(line.get("width", 1.0)), 0.05)
			if polyline.size() == 1:
				mask = _mark_road_point_mask(mask, world_rect, width, height, cell_size, source, polyline[0], road_width)
				continue
			for index: int in range(polyline.size() - 1):
				mask = _mark_road_segment_mask(mask, world_rect, width, height, cell_size, source, polyline[index], polyline[index + 1], road_width)

	return mask


func _mark_road_cell_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	source: Dictionary,
	road_cell: Vector2i
) -> PackedByteArray:
	var origin := source.get("origin", Vector3.ZERO) as Vector3
	var source_cell_size := maxf(float(source.get("cell_size", 4.0)), 0.1)
	var min_local := Vector2(
		origin.x + float(road_cell.x) * source_cell_size,
		origin.z + float(road_cell.y) * source_cell_size
	)
	var max_local := min_local + Vector2(source_cell_size, source_cell_size)
	var world_a := _source_local_to_world_2d(min_local, source)
	var world_b := _source_local_to_world_2d(Vector2(max_local.x, min_local.y), source)
	var world_c := _source_local_to_world_2d(max_local, source)
	var world_d := _source_local_to_world_2d(Vector2(min_local.x, max_local.y), source)
	var bounds := Rect2(world_a, Vector2.ZERO).expand(world_b).expand(world_c).expand(world_d).grow(cell_size)
	var cell_bounds := _movement_cell_bounds_for_world_rect(bounds, world_rect, width, height, cell_size)
	if not cell_bounds.has_area():
		return mask

	for y: int in range(cell_bounds.position.y, cell_bounds.end.y):
		for x: int in range(cell_bounds.position.x, cell_bounds.end.x):
			var index := y * width + x
			if mask[index] != 0:
				continue
			var sample_world := world_rect.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size
			var sample_local := _world_to_source_local_2d(sample_world, source)
			if _local_point_to_cell(sample_local, origin, source_cell_size) == road_cell:
				mask[index] = 1
	return mask


func _mark_road_point_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	source: Dictionary,
	local_point: Vector2,
	road_width: float
) -> PackedByteArray:
	var radius := road_width * 0.5
	var world_point := _source_local_to_world_2d(local_point, source)
	var bounds := Rect2(world_point, Vector2.ZERO).grow(radius + cell_size)
	var cell_bounds := _movement_cell_bounds_for_world_rect(bounds, world_rect, width, height, cell_size)
	if not cell_bounds.has_area():
		return mask

	var radius_squared := radius * radius
	for y: int in range(cell_bounds.position.y, cell_bounds.end.y):
		for x: int in range(cell_bounds.position.x, cell_bounds.end.x):
			var index := y * width + x
			if mask[index] != 0:
				continue
			var sample_world := world_rect.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size
			var sample_local := _world_to_source_local_2d(sample_world, source)
			if sample_local.distance_squared_to(local_point) <= radius_squared:
				mask[index] = 1
	return mask


func _mark_road_segment_mask(
	mask: PackedByteArray,
	world_rect: Rect2,
	width: int,
	height: int,
	cell_size: float,
	source: Dictionary,
	local_from: Vector2,
	local_to: Vector2,
	road_width: float
) -> PackedByteArray:
	var radius := road_width * 0.5
	var world_from := _source_local_to_world_2d(local_from, source)
	var world_to := _source_local_to_world_2d(local_to, source)
	var bounds := Rect2(world_from, Vector2.ZERO).expand(world_to).grow(radius + cell_size)
	var cell_bounds := _movement_cell_bounds_for_world_rect(bounds, world_rect, width, height, cell_size)
	if not cell_bounds.has_area():
		return mask

	var radius_squared := radius * radius
	for y: int in range(cell_bounds.position.y, cell_bounds.end.y):
		for x: int in range(cell_bounds.position.x, cell_bounds.end.x):
			var index := y * width + x
			if mask[index] != 0:
				continue
			var sample_world := world_rect.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size
			var sample_local := _world_to_source_local_2d(sample_world, source)
			if _distance_squared_to_segment(sample_local, local_from, local_to) <= radius_squared:
				mask[index] = 1
	return mask


func _movement_cell_bounds_for_world_rect(bounds: Rect2, world_rect: Rect2, width: int, height: int, cell_size: float) -> Rect2i:
	if width <= 0 or height <= 0 or cell_size <= 0.0 or not world_rect.intersects(bounds, true):
		return Rect2i()

	var clipped := world_rect.intersection(bounds)
	var start_x := clampi(floori((clipped.position.x - world_rect.position.x) / cell_size), 0, width - 1)
	var start_y := clampi(floori((clipped.position.y - world_rect.position.y) / cell_size), 0, height - 1)
	var end_x := clampi(floori((clipped.end.x - world_rect.position.x) / cell_size), 0, width - 1)
	var end_y := clampi(floori((clipped.end.y - world_rect.position.y) / cell_size), 0, height - 1)
	return Rect2i(Vector2i(start_x, start_y), Vector2i(end_x - start_x + 1, end_y - start_y + 1))


func _is_point_on_village_road(world_point: Vector2, village_sources: Array[Dictionary]) -> bool:
	for source: Dictionary in village_sources:
		var local_point := _world_to_source_local_2d(world_point, source)
		var origin := source.get("origin", Vector3.ZERO) as Vector3
		var cell_size := float(source.get("cell_size", 4.0))
		var road_cells := source.get("road_cells", {}) as Dictionary
		if road_cells.has(_local_point_to_cell(local_point, origin, cell_size)):
			return true

		var road_lines: Array = source.get("road_lines", [])
		for line_variant: Variant in road_lines:
			var line := line_variant as Dictionary
			var polyline := line.get("polyline", PackedVector2Array()) as PackedVector2Array
			var width := maxf(float(line.get("width", 1.0)), 0.05)
			if _distance_to_polyline(local_point, polyline) <= width * 0.5:
				return true
	return false


func _world_to_source_local_2d(world_point: Vector2, source: Dictionary) -> Vector2:
	var inverse := source.get("inverse", Transform3D.IDENTITY) as Transform3D
	var local := inverse * Vector3(world_point.x, 0.0, world_point.y)
	return Vector2(local.x, local.z)


func _source_local_to_world_2d(local_point: Vector2, source: Dictionary) -> Vector2:
	var transform := source.get("global_transform", Transform3D.IDENTITY) as Transform3D
	var world := transform * Vector3(local_point.x, 0.0, local_point.y)
	return Vector2(world.x, world.z)


func _local_point_to_cell(local_point: Vector2, origin: Vector3, cell_size: float) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2i(
		floori((local_point.x - origin.x) / safe_cell_size),
		floori((local_point.y - origin.z) / safe_cell_size)
	)


func _distance_to_polyline(point: Vector2, polyline: PackedVector2Array) -> float:
	if polyline.is_empty():
		return INF
	if polyline.size() == 1:
		return point.distance_to(polyline[0])
	var best := INF
	for index: int in range(polyline.size() - 1):
		best = minf(best, _distance_to_segment(point, polyline[index], polyline[index + 1]))
	return best


func _distance_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	return sqrt(_distance_squared_to_segment(point, from_point, to_point))


func _distance_squared_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	var segment := to_point - from_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_squared_to(from_point)
	var weight := clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(from_point + segment * weight)
