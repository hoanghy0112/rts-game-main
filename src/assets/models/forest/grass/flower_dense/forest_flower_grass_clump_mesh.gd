@tool
extends ArrayMesh
class_name ForestFlowerGrassClumpMesh

const ROOT_Y := -0.45
const LEAF_KIND := 0.0
const STEM_KIND := 0.5
const FLOWER_KIND := 1.0


func _init() -> void:
	if get_surface_count() == 0:
		rebuild()


func rebuild() -> void:
	clear_surfaces()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	_add_leaf(vertices, normals, uvs, uv2s, indices, 0.0, deg_to_rad(-46.0), 0.94, 0.064, 0.21)
	_add_leaf(vertices, normals, uvs, uv2s, indices, 1.0, deg_to_rad(-18.0), 1.02, 0.058, 0.16)
	_add_leaf(vertices, normals, uvs, uv2s, indices, 2.0, deg_to_rad(18.0), 0.98, 0.061, 0.18)
	_add_leaf(vertices, normals, uvs, uv2s, indices, 3.0, deg_to_rad(48.0), 0.88, 0.053, 0.23)
	_add_leaf(vertices, normals, uvs, uv2s, indices, 4.0, deg_to_rad(82.0), 0.80, 0.047, 0.18)

	var branch_points: Array[Vector3] = [
		Vector3(0.0, ROOT_Y, 0.0),
		Vector3(0.022, -0.07, 0.015),
		Vector3(0.070, 0.36, 0.038),
		Vector3(0.110, 0.62, 0.046),
	]
	_add_strip(vertices, normals, uvs, uv2s, indices, branch_points, [0.017, 0.014, 0.011, 0.007], 0.0, STEM_KIND)
	_add_flower(vertices, normals, uvs, uv2s, indices, Vector3(0.122, 0.65, 0.052), 0.0, 0.078)
	_add_flower(vertices, normals, uvs, uv2s, indices, Vector3(0.044, 0.40, 0.074), 1.0, 0.058)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _add_leaf(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	leaf_id: float,
	angle: float,
	length: float,
	width: float,
	curve: float
) -> void:
	var direction := Vector3(sin(angle), 0.0, cos(angle))
	var side := Vector3(cos(angle), 0.0, -sin(angle))
	var points: Array[Vector3] = []
	var widths: Array[float] = []
	for step: int in range(4):
		var t := float(step) / 3.0
		var lift := ROOT_Y + length * t
		var spread := direction * (curve * t * t + 0.018 * sin(t * PI))
		points.append(Vector3.ZERO + spread + Vector3(0.0, lift, 0.0))
		widths.append(width * sin((1.0 - t) * PI * 0.5))
	_add_strip(vertices, normals, uvs, uv2s, indices, points, widths, leaf_id, LEAF_KIND, side)


func _add_strip(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	points: Array[Vector3],
	widths: Array[float],
	part_id: float,
	part_kind: float,
	custom_side := Vector3.ZERO
) -> void:
	var start_index := vertices.size()
	var side := custom_side
	if side.length_squared() <= 0.0001 and points.size() >= 2:
		var axis := (points[-1] - points[0]).normalized()
		side = axis.cross(Vector3.FORWARD).normalized()
		if side.length_squared() <= 0.0001:
			side = Vector3.RIGHT
	side = side.normalized()
	var normal := side.cross(Vector3.UP).normalized()
	if normal.length_squared() <= 0.0001:
		normal = Vector3.FORWARD

	for index: int in range(points.size()):
		var t := float(index) / maxf(float(points.size() - 1), 1.0)
		var half_width := widths[index]
		var point := points[index]
		vertices.append(point - side * half_width)
		vertices.append(point + side * half_width)
		normals.append(normal)
		normals.append(normal)
		uvs.append(Vector2(part_id, t))
		uvs.append(Vector2(part_id, t))
		uv2s.append(Vector2(part_kind, 0.0))
		uv2s.append(Vector2(part_kind, 0.0))

	for index: int in range(points.size() - 1):
		var a := start_index + index * 2
		var b := a + 1
		var c := a + 2
		var d := a + 3
		indices.append_array([a, c, b, b, c, d])


func _add_flower(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	center: Vector3,
	flower_id: float,
	radius: float
) -> void:
	var start_index := vertices.size()
	var normal := Vector3(0.0, 0.18, 1.0).normalized()
	var right := Vector3.RIGHT * radius
	var up := Vector3.UP * radius
	vertices.append(center - right)
	vertices.append(center + up)
	vertices.append(center + right)
	vertices.append(center - up)
	for index: int in range(4):
		normals.append(normal)
		uvs.append(Vector2(flower_id, 1.0))
		uv2s.append(Vector2(FLOWER_KIND, 0.0))
	indices.append_array([
		start_index,
		start_index + 1,
		start_index + 2,
		start_index,
		start_index + 2,
		start_index + 3,
	])
