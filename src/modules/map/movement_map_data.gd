extends Resource
class_name MovementMapData

const FLAG_RIVER := 1
const FLAG_STEEP_SLOPE := 2
const FLAG_FOREST := 4
const FLAG_ROAD := 8

@export var origin: Vector2 = Vector2.ZERO
@export_range(0.01, 1024.0, 0.01, "or_greater") var cell_size_meters: float = 16.0
@export var width: int = 0
@export var height: int = 0
@export var speed_multipliers: PackedFloat32Array = PackedFloat32Array()
@export var flags: PackedByteArray = PackedByteArray()


func resize_map(new_width: int, new_height: int, default_speed: float = 1.0, default_flags: int = 0) -> void:
	width = maxi(new_width, 0)
	height = maxi(new_height, 0)
	var cell_count := width * height
	speed_multipliers.resize(cell_count)
	flags.resize(cell_count)
	for index: int in range(cell_count):
		speed_multipliers[index] = default_speed
		flags[index] = clampi(default_flags, 0, 255)


func world_to_cell(world_position: Variant) -> Vector2i:
	var world_point := Vector2.ZERO
	if world_position is Vector3:
		var point3 := world_position as Vector3
		world_point = Vector2(point3.x, point3.z)
	elif world_position is Vector2:
		world_point = world_position as Vector2
	else:
		return Vector2i(-1, -1)

	var safe_cell_size := maxf(cell_size_meters, 0.001)
	return Vector2i(
		floori((world_point.x - origin.x) / safe_cell_size),
		floori((world_point.y - origin.y) / safe_cell_size)
	)


func cell_to_world_center(cell: Vector2i) -> Vector2:
	var safe_cell_size := maxf(cell_size_meters, 0.001)
	return origin + Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * safe_cell_size


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_cell_index(cell: Vector2i) -> int:
	if not is_valid_cell(cell):
		return -1
	return cell.y * width + cell.x


func is_walkable_cell(cell: Vector2i) -> bool:
	var index := get_cell_index(cell)
	if index < 0 or index >= speed_multipliers.size():
		return false
	return speed_multipliers[index] > 0.0


func get_speed_multiplier_cell(cell: Vector2i) -> float:
	var index := get_cell_index(cell)
	if index < 0 or index >= speed_multipliers.size():
		return 0.0
	return speed_multipliers[index]


func get_flags_cell(cell: Vector2i) -> int:
	var index := get_cell_index(cell)
	if index < 0 or index >= flags.size():
		return 0
	return int(flags[index])
