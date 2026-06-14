@tool
extends AbstractField
class_name RiceField

@export var dry_material: Material
@export var wet_material: Material
@export var flooded_material: Material
@export var muddy_material: Material
@export var water_material: Material
@export var bund_material: Material
@export_range(0.03, 1.0, 0.01, "or_greater") var bund_edge_width: float = 0.14

var _current_snapshot: Dictionary = {}
var _current_ground_state_id: StringName = &"dry"
var _current_stage_id: StringName = &"empty"
var _visual_root: Node3D
var _ground_mesh: MeshInstance3D
var _water_mesh: MeshInstance3D
var _bund_edge_mesh: MeshInstance3D


func _ready() -> void:
	_resolve_nodes()
	rebuild_visuals()
	set_process(false)


func _exit_tree() -> void:
	if season_weather and season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.disconnect(_on_environment_changed)


func configure_field(new_plot_data: FieldPlotData, new_crop_type: CropTypeData, new_season_weather: SeasonWeatherSystem) -> void:
	plot_data = new_plot_data
	crop_type = new_crop_type

	if season_weather and season_weather != new_season_weather and season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.disconnect(_on_environment_changed)

	season_weather = new_season_weather
	if season_weather and not season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.connect(_on_environment_changed)

	if season_weather:
		apply_environment(season_weather.get_snapshot_at(global_position))
	else:
		apply_environment({})

	rebuild_visuals()


func apply_environment(snapshot: Dictionary) -> void:
	_current_snapshot = snapshot.duplicate()
	_current_ground_state_id = get_ground_state_id(_current_snapshot)

	if plot_data:
		plot_data.water_level = float(_current_snapshot.get("rain_intensity", 0.0))
		plot_data.flood_level = float(_current_snapshot.get("flood_level", 0.0))
		plot_data.mud_level = float(_current_snapshot.get("mud_level", 0.0))
		plot_data.ground_state_id = _current_ground_state_id
		plot_data.ground_state_data = crop_type.get_ground_state_data(_current_ground_state_id) if crop_type else null
		plot_data.stage = crop_type.get_crop_stage_id(_current_snapshot) if crop_type else plot_data.stage
		if plot_data.stage == &"":
			plot_data.stage = &"empty"
		_current_stage_id = plot_data.stage

	_apply_ground_material()
	_apply_water_visual()
	_apply_bund_material()


func rebuild_visuals() -> void:
	_resolve_nodes()
	if not plot_data or not _visual_root:
		return

	_visual_root.scale = Vector3.ONE
	var footprint := _get_visual_footprint()
	var surface_mesh := _build_surface_mesh(footprint)

	if _ground_mesh:
		_ground_mesh.scale = Vector3.ONE
		_ground_mesh.mesh = surface_mesh
	if _water_mesh:
		_water_mesh.scale = Vector3.ONE
		_water_mesh.mesh = surface_mesh
	if _bund_edge_mesh:
		_bund_edge_mesh.scale = Vector3.ONE
		_bund_edge_mesh.mesh = _build_bund_edge_mesh(footprint)

	_apply_ground_material()
	_apply_water_visual()
	_apply_bund_material()


func get_ground_state_id(snapshot: Dictionary) -> StringName:
	if crop_type:
		return crop_type.get_ground_state_id(snapshot)

	var flood := float(snapshot.get("flood_level", 0.0))
	if flood >= 0.35:
		return &"flooded"

	var mud := float(snapshot.get("mud_level", 0.0))
	if mud >= 0.45:
		return &"muddy"

	var rain := float(snapshot.get("rain_intensity", 0.0))
	if rain >= 0.2:
		return &"wet"

	return &"dry"


func get_current_ground_state_id() -> StringName:
	return _current_ground_state_id


func get_current_stage_id() -> StringName:
	return _current_stage_id


func _on_environment_changed(snapshot: Dictionary) -> void:
	apply_environment(snapshot)
	rebuild_visuals()


func _resolve_nodes() -> void:
	if not _visual_root:
		_visual_root = get_node_or_null("VisualRoot") as Node3D
	if not _ground_mesh:
		_ground_mesh = get_node_or_null("VisualRoot/Ground") as MeshInstance3D
	if not _water_mesh:
		_water_mesh = get_node_or_null("VisualRoot/Water") as MeshInstance3D
	if not _bund_edge_mesh:
		_bund_edge_mesh = get_node_or_null("VisualRoot/BundEdges") as MeshInstance3D


func _apply_ground_material() -> void:
	_resolve_nodes()
	if not _ground_mesh:
		return

	var ground_material := _get_material_for_ground_state(_current_ground_state_id)
	if ground_material:
		_ground_mesh.material_override = ground_material


func _apply_water_visual() -> void:
	_resolve_nodes()
	if not _water_mesh:
		return

	var rain := float(_current_snapshot.get("rain_intensity", 0.0))
	var flood := float(_current_snapshot.get("flood_level", 0.0))
	_water_mesh.visible = _current_ground_state_id == &"wet" or _current_ground_state_id == &"flooded" or rain >= 0.2 or flood > 0.08
	if water_material:
		_water_mesh.material_override = water_material


func _apply_bund_material() -> void:
	_resolve_nodes()
	if not _bund_edge_mesh:
		return

	_bund_edge_mesh.visible = _bund_edge_mesh.mesh != null
	if bund_material:
		_bund_edge_mesh.material_override = bund_material


func _build_bund_edge_mesh(footprint: PackedVector2Array) -> ArrayMesh:
	if footprint.size() < 3:
		return null

	var bounds := _get_footprint_bounds(footprint)
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var min_dimension := minf(max_point.x - min_point.x, max_point.y - min_point.y)
	if min_dimension <= 0.001:
		return null

	var strip_width := minf(maxf(bund_edge_width, 0.01), min_dimension * 0.28)
	var orientation := 1.0 if _get_polygon_signed_area(footprint) >= 0.0 else -1.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for index: int in range(footprint.size()):
		var from_point := footprint[index]
		var to_point := footprint[(index + 1) % footprint.size()]
		var edge := to_point - from_point
		var edge_length := edge.length()
		if edge_length <= 0.001:
			continue

		var edge_direction := edge / edge_length
		var inward := Vector2(-edge_direction.y, edge_direction.x) * orientation
		_append_local_quad(
			vertices,
			normals,
			uvs,
			indices,
			from_point,
			to_point,
			to_point + inward * strip_width,
			from_point + inward * strip_width
		)

	return _make_array_mesh(vertices, normals, uvs, indices)


func _build_surface_mesh(footprint: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	if footprint.size() < 3:
		footprint = _get_visual_footprint()
	if footprint.size() < 3:
		footprint = PackedVector2Array([
			Vector2(-0.5, -0.5),
			Vector2(0.5, -0.5),
			Vector2(0.5, 0.5),
			Vector2(-0.5, 0.5),
		])

	var indices := Geometry2D.triangulate_polygon(footprint)
	if indices.is_empty():
		var fallback_length := maxf(plot_data.length, 0.1) if plot_data else 1.0
		var fallback_width := maxf(plot_data.width, 0.1) if plot_data else 1.0
		footprint = _make_rectangle_footprint(fallback_length, fallback_width)
		indices = Geometry2D.triangulate_polygon(footprint)

	var bounds := _get_footprint_bounds(footprint)
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var bounds_size := max_point - min_point
	bounds_size.x = maxf(bounds_size.x, 0.001)
	bounds_size.y = maxf(bounds_size.y, 0.001)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for point: Vector2 in footprint:
		vertices.append(Vector3(point.x, 0.0, point.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2((point.x - min_point.x) / bounds_size.x, (point.y - min_point.y) / bounds_size.y))

	return _make_array_mesh(vertices, normals, uvs, indices)


func _make_array_mesh(
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


func _append_local_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2
) -> void:
	var start_index := vertices.size()
	vertices.append(Vector3(a.x, 0.0, a.y))
	vertices.append(Vector3(b.x, 0.0, b.y))
	vertices.append(Vector3(c.x, 0.0, c.y))
	vertices.append(Vector3(d.x, 0.0, d.y))

	for _vertex_index: int in range(4):
		normals.append(Vector3.UP)
	uvs.append(a)
	uvs.append(b)
	uvs.append(c)
	uvs.append(d)

	indices.append(start_index)
	indices.append(start_index + 1)
	indices.append(start_index + 2)
	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 3)


func _get_visual_footprint() -> PackedVector2Array:
	var footprint := plot_data.get_local_outline_2d() if plot_data else PackedVector2Array()
	if footprint.size() >= 3:
		return footprint

	var length := maxf(plot_data.length, 0.1) if plot_data else 1.0
	var width := maxf(plot_data.width, 0.1) if plot_data else 1.0
	return _make_rectangle_footprint(length, width)


func _make_rectangle_footprint(rect_length: float, rect_width: float) -> PackedVector2Array:
	var half_length := maxf(rect_length, 0.0) * 0.5
	var half_width := maxf(rect_width, 0.0) * 0.5
	return PackedVector2Array([
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
	])


func _get_footprint_bounds(footprint: PackedVector2Array) -> Dictionary:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in footprint:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return {
		"min": min_point,
		"max": max_point,
	}


func _get_material_for_ground_state(ground_state_id: StringName) -> Material:
	if crop_type:
		var state_data := crop_type.get_ground_state_data(ground_state_id)
		if state_data and state_data.material:
			return state_data.material

	match ground_state_id:
		&"wet":
			return wet_material if wet_material else dry_material
		&"flooded":
			return flooded_material if flooded_material else wet_material
		&"muddy":
			return muddy_material if muddy_material else wet_material
		_:
			return dry_material


func _get_polygon_signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5
