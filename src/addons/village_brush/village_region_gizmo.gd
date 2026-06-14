@tool
extends EditorNode3DGizmoPlugin

const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")

const SURFACE_OFFSET := 0.025
const EDGE_SEGMENTS := 1
const LARGE_REGION_CELL_LIMIT := 500
const SURFACE_CACHE_SCALE := 20.0
const HOUSE_COLOR := Color(1.0, 0.55, 0.18, 0.95)
const FIELD_COLOR := Color(0.24, 0.82, 0.48, 0.95)
const ROAD_COLOR := Color(0.72, 0.62, 0.46, 0.95)
const PREVIEW_COLOR := Color(0.15, 0.62, 1.0, 1.0)
const ERASE_PREVIEW_COLOR := Color(1.0, 0.2, 0.16, 1.0)

enum CellDrawStyle {
	HOUSE,
	FIELD,
	ROAD,
}

var _cell_material: StandardMaterial3D
var _preview_region_id := 0
var _preview_cells: Array[Vector2i] = []
var _preview_mode := 0
var _preview_visible := false
var _base_line_cache: Dictionary = {}
var _surface_point_cache_by_region: Dictionary = {}


func _init() -> void:
	_cell_material = StandardMaterial3D.new()
	_cell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cell_material.set_flag(BaseMaterial3D.FLAG_DISABLE_DEPTH_TEST, true)
	_cell_material.set_flag(BaseMaterial3D.FLAG_ALBEDO_FROM_VERTEX_COLOR, true)
	_cell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cell_material.albedo_color = Color.WHITE
	add_material("village_cell_lines", _cell_material)


func _get_gizmo_name() -> String:
	return "VillageRegion"


func _has_gizmo(node_3d: Node3D) -> bool:
	return node_3d is VillageRegionScript


func set_brush_preview(region: VillageRegionScript, cells: Array[Vector2i], mode: int, visible: bool) -> bool:
	if not is_instance_valid(region) or not visible:
		return clear_brush_preview(region)

	var region_id := region.get_instance_id()
	if (
		_preview_visible
		and _preview_region_id == region_id
		and _preview_mode == mode
		and _cells_equal(_preview_cells, cells)
	):
		return false

	_preview_region_id = region_id
	_preview_cells = _copy_cells(cells)
	_preview_mode = mode
	_preview_visible = true
	return true


func clear_brush_preview(region: VillageRegionScript = null) -> bool:
	if is_instance_valid(region) and _preview_region_id != region.get_instance_id():
		return false
	if not _preview_visible and _preview_region_id == 0:
		return false

	_preview_region_id = 0
	_preview_cells.clear()
	_preview_visible = false
	return true


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var region := gizmo.get_node_3d() as VillageRegionScript
	if not is_instance_valid(region):
		return

	var material := get_material("village_cell_lines", gizmo)
	var terrain := _get_terrain(region)
	_draw_cached_cells(gizmo, region, terrain, region.house_cells, material, HOUSE_COLOR, CellDrawStyle.HOUSE)
	_draw_cached_cells(gizmo, region, terrain, region.field_cells, material, FIELD_COLOR, CellDrawStyle.FIELD)
	_draw_cached_cells(gizmo, region, terrain, region.road_cells, material, ROAD_COLOR, CellDrawStyle.ROAD)

	if _preview_visible and _preview_region_id == region.get_instance_id():
		var preview_color := ERASE_PREVIEW_COLOR if _preview_mode == VillageRegionScript.PaintMode.ERASE else PREVIEW_COLOR
		var preview_style := CellDrawStyle.HOUSE
		match _preview_mode:
			VillageRegionScript.PaintMode.FIELD:
				preview_style = CellDrawStyle.FIELD
			VillageRegionScript.PaintMode.ROAD:
				preview_style = CellDrawStyle.ROAD
		_draw_cells(gizmo, region, terrain, _preview_cells, material, preview_color, preview_style)


func _draw_cached_cells(
	gizmo: EditorNode3DGizmo,
	region: VillageRegionScript,
	terrain: Node3D,
	cells: Array[Vector2i],
	material: Material,
	color: Color,
	draw_style: int
) -> void:
	if cells.is_empty():
		return

	var lines := _get_cached_cell_lines(region, terrain, cells, draw_style)
	if not lines.is_empty():
		gizmo.add_lines(lines, material, false, color)


func _draw_cells(
	gizmo: EditorNode3DGizmo,
	region: VillageRegionScript,
	terrain: Node3D,
	cells: Array[Vector2i],
	material: Material,
	color: Color,
	draw_style: int
) -> void:
	if cells.is_empty():
		return

	var surface_cache := _get_surface_point_cache(region, terrain)
	var lines := _build_cell_lines(region, terrain, cells, draw_style, surface_cache)
	if not lines.is_empty():
		gizmo.add_lines(lines, material, false, color)


func _get_cached_cell_lines(
	region: VillageRegionScript,
	terrain: Node3D,
	cells: Array[Vector2i],
	draw_style: int
) -> PackedVector3Array:
	var region_id := region.get_instance_id()
	var cache_signature := _get_cell_line_cache_signature(region, terrain, cells, draw_style)
	var cache := _base_line_cache.get(region_id, {}) as Dictionary
	var cache_key := str(draw_style)
	var cached_record: Variant = cache.get(cache_key)
	if cached_record is Dictionary:
		var record := cached_record as Dictionary
		var cached_lines: Variant = record.get("lines")
		if str(record.get("signature", "")) == cache_signature and cached_lines is PackedVector3Array:
			return cached_lines as PackedVector3Array

	var surface_cache := _get_surface_point_cache(region, terrain)
	var lines := _build_cell_lines(region, terrain, cells, draw_style, surface_cache)
	cache[cache_key] = {
		"signature": cache_signature,
		"lines": lines,
	}
	_base_line_cache[region_id] = cache
	return lines


func _build_cell_lines(
	region: VillageRegionScript,
	terrain: Node3D,
	cells: Array[Vector2i],
	draw_style: int,
	surface_cache: Dictionary
) -> PackedVector3Array:
	var lines := PackedVector3Array()
	if cells.size() > LARGE_REGION_CELL_LIMIT:
		_append_aggregate_cell_lines(lines, region, terrain, cells, surface_cache)
		return lines

	var half_size := region.cell_size * 0.5
	for cell: Vector2i in cells:
		var center := region.cell_to_local_center(cell)

		var nw := center + Vector3(-half_size, 0.0, -half_size)
		var ne := center + Vector3(half_size, 0.0, -half_size)
		var se := center + Vector3(half_size, 0.0, half_size)
		var sw := center + Vector3(-half_size, 0.0, half_size)

		_append_surface_line(lines, region, terrain, nw, ne, surface_cache)
		_append_surface_line(lines, region, terrain, ne, se, surface_cache)
		_append_surface_line(lines, region, terrain, se, sw, surface_cache)
		_append_surface_line(lines, region, terrain, sw, nw, surface_cache)
		match draw_style:
			CellDrawStyle.HOUSE:
				_append_surface_line(lines, region, terrain, nw, se, surface_cache)
				_append_surface_line(lines, region, terrain, ne, sw, surface_cache)
			CellDrawStyle.FIELD:
				var row_a := center + Vector3(0.0, 0.0, -half_size * 0.35)
				var row_b := center + Vector3(0.0, 0.0, half_size * 0.35)
				_append_surface_line(
					lines,
					region,
					terrain,
					row_a + Vector3(-half_size, 0.0, 0.0),
					row_a + Vector3(half_size, 0.0, 0.0),
					surface_cache
				)
				_append_surface_line(
					lines,
					region,
					terrain,
					row_b + Vector3(-half_size, 0.0, 0.0),
					row_b + Vector3(half_size, 0.0, 0.0),
					surface_cache
				)
			CellDrawStyle.ROAD:
				_append_surface_line(
					lines,
					region,
					terrain,
					center + Vector3(-half_size, 0.0, 0.0),
					center + Vector3(half_size, 0.0, 0.0),
					surface_cache
				)
				_append_surface_line(
					lines,
					region,
					terrain,
					center + Vector3(0.0, 0.0, -half_size),
					center + Vector3(0.0, 0.0, half_size),
					surface_cache
				)

	return lines


func _append_aggregate_cell_lines(
	lines: PackedVector3Array,
	region: VillageRegionScript,
	terrain: Node3D,
	cells: Array[Vector2i],
	surface_cache: Dictionary
) -> void:
	var lookup: Dictionary = {}
	for cell: Vector2i in cells:
		lookup[cell] = true

	var half_size := region.cell_size * 0.5
	for cell: Vector2i in cells:
		var center := region.cell_to_local_center(cell)
		var nw := center + Vector3(-half_size, 0.0, -half_size)
		var ne := center + Vector3(half_size, 0.0, -half_size)
		var se := center + Vector3(half_size, 0.0, half_size)
		var sw := center + Vector3(-half_size, 0.0, half_size)

		if not lookup.has(cell + Vector2i(0, -1)):
			_append_surface_line(lines, region, terrain, nw, ne, surface_cache)
		if not lookup.has(cell + Vector2i(1, 0)):
			_append_surface_line(lines, region, terrain, ne, se, surface_cache)
		if not lookup.has(cell + Vector2i(0, 1)):
			_append_surface_line(lines, region, terrain, se, sw, surface_cache)
		if not lookup.has(cell + Vector2i(-1, 0)):
			_append_surface_line(lines, region, terrain, sw, nw, surface_cache)


func _append_surface_line(
	lines: PackedVector3Array,
	region: VillageRegionScript,
	terrain: Node3D,
	from_local: Vector3,
	to_local: Vector3,
	surface_cache: Dictionary
) -> void:
	var previous := _to_surface_local(region, terrain, from_local, surface_cache)
	for index: int in range(1, EDGE_SEGMENTS + 1):
		var weight := float(index) / float(EDGE_SEGMENTS)
		var next := _to_surface_local(region, terrain, from_local.lerp(to_local, weight), surface_cache)
		lines.append(previous)
		lines.append(next)
		previous = next


func _to_surface_local(region: VillageRegionScript, terrain: Node3D, local_position: Vector3, surface_cache: Dictionary) -> Vector3:
	var cache_key := Vector3i(
		roundi(local_position.x * SURFACE_CACHE_SCALE),
		roundi(local_position.y * SURFACE_CACHE_SCALE),
		roundi(local_position.z * SURFACE_CACHE_SCALE)
	)
	var cached_position: Variant = surface_cache.get(cache_key)
	if cached_position is Vector3:
		return cached_position as Vector3

	var surface_position := local_position
	if not is_instance_valid(terrain) or not region.is_inside_tree():
		surface_position.y += SURFACE_OFFSET
		surface_cache[cache_key] = surface_position
		return surface_position

	var world_position := region.to_global(local_position)
	var terrain_height: Variant = _get_terrain_height(terrain, world_position)
	if terrain_height == null:
		surface_position.y += SURFACE_OFFSET
		surface_cache[cache_key] = surface_position
		return surface_position

	world_position.y = terrain_height + SURFACE_OFFSET
	surface_position = region.to_local(world_position)
	surface_cache[cache_key] = surface_position
	return surface_position


func _get_terrain(region: VillageRegionScript) -> Node3D:
	if not is_instance_valid(region) or region.terrain_path.is_empty():
		return null

	var terrain := region.get_node_or_null(region.terrain_path)
	if terrain is Node3D:
		return terrain
	return null


func _get_surface_point_cache(region: VillageRegionScript, terrain: Node3D) -> Dictionary:
	var region_id := region.get_instance_id()
	var signature := _get_surface_signature(region, terrain)
	var cache_record: Variant = _surface_point_cache_by_region.get(region_id)
	if cache_record is Dictionary:
		var record := cache_record as Dictionary
		if str(record.get("signature", "")) == signature:
			var cached_points: Variant = record.get("points")
			if cached_points is Dictionary:
				return cached_points as Dictionary

	var points: Dictionary = {}
	_surface_point_cache_by_region[region_id] = {
		"signature": signature,
		"points": points,
	}
	return points


func _get_cell_line_cache_signature(region: VillageRegionScript, terrain: Node3D, cells: Array[Vector2i], draw_style: int) -> String:
	return "%s|%d|%s" % [
		_get_surface_signature(region, terrain),
		draw_style,
		_get_cells_key(cells),
	]


func _get_surface_signature(region: VillageRegionScript, terrain: Node3D) -> String:
	var terrain_id := terrain.get_instance_id() if is_instance_valid(terrain) else 0
	return "%d|%.4f|%s|%s" % [
		terrain_id,
		region.cell_size,
		str(region.origin),
		_transform_signature(region.global_transform if region.is_inside_tree() else region.transform),
	]


func _transform_signature(transform: Transform3D) -> String:
	return "%s|%s|%s|%s" % [
		str(transform.basis.x),
		str(transform.basis.y),
		str(transform.basis.z),
		str(transform.origin),
	]


func _get_cells_key(cells: Array[Vector2i]) -> String:
	var mixed := int(2166136261)
	for cell: Vector2i in cells:
		mixed = int((mixed ^ cell.x) * 16777619)
		mixed = int((mixed ^ cell.y) * 16777619)
	return "%d:%d" % [cells.size(), mixed]


func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copied: Array[Vector2i] = []
	for cell: Vector2i in cells:
		copied.append(cell)
	return copied


func _cells_equal(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false

	for index: int in range(a.size()):
		if a[index] != b[index]:
			return false
	return true


func _get_terrain_height(terrain: Node3D, world_position: Vector3) -> Variant:
	var terrain_data: Variant = terrain.get("data")
	if not (terrain_data is Object):
		return null

	var terrain_data_object := terrain_data as Object
	if not terrain_data_object.has_method("get_height"):
		return null

	var height: float = terrain_data_object.call("get_height", world_position)
	if is_nan(height) or absf(height) > 1.0e20:
		return null

	return height
