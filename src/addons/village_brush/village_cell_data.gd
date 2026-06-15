@tool
extends Resource
class_name VillageCellData

const RUN_FIELD_COUNT := 3
const RUN_ROW := 0
const RUN_START_COLUMN := 1
const RUN_LENGTH := 2

@export var house_runs: PackedInt32Array = PackedInt32Array():
	set(value):
		house_runs = value
		_invalidate_cache()

@export var field_runs: PackedInt32Array = PackedInt32Array():
	set(value):
		field_runs = value
		_invalidate_cache()

@export var road_runs: PackedInt32Array = PackedInt32Array():
	set(value):
		road_runs = value
		_invalidate_cache()

var _cache_valid := false
var _house_cells_cache: Array[Vector2i] = []
var _field_cells_cache: Array[Vector2i] = []
var _road_cells_cache: Array[Vector2i] = []


static func normalize_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var unique_cells: Dictionary = {}
	for cell: Vector2i in value:
		unique_cells[cell] = true

	var normalized: Array[Vector2i] = []
	for key: Variant in unique_cells.keys():
		var cell: Vector2i = key
		normalized.append(cell)
	normalized.sort_custom(_compare_cells)
	return normalized


static func copy_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var copied: Array[Vector2i] = []
	for cell: Vector2i in value:
		copied.append(cell)
	return copied


static func encode_cells_to_runs(cells: Array[Vector2i]) -> PackedInt32Array:
	var row_sorted := normalize_cells(cells)
	row_sorted.sort_custom(_compare_cells_by_row)

	var runs := PackedInt32Array()
	var active_y := 0
	var active_start_x := 0
	var active_count := 0
	var has_active_run := false

	for cell: Vector2i in row_sorted:
		var can_extend := (
			has_active_run
			and cell.y == active_y
			and cell.x == active_start_x + active_count
		)
		if can_extend:
			active_count += 1
			continue

		if has_active_run:
			_append_run(runs, active_y, active_start_x, active_count)

		active_y = cell.y
		active_start_x = cell.x
		active_count = 1
		has_active_run = true

	if has_active_run:
		_append_run(runs, active_y, active_start_x, active_count)

	return runs


static func decode_runs_to_cells(runs: PackedInt32Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var run_count := int(runs.size() / RUN_FIELD_COUNT)
	for run_index: int in range(run_count):
		var offset := run_index * RUN_FIELD_COUNT
		var y := runs[offset + RUN_ROW]
		var start_x := runs[offset + RUN_START_COLUMN]
		var count := maxi(runs[offset + RUN_LENGTH], 0)
		for x_offset: int in range(count):
			cells.append(Vector2i(start_x + x_offset, y))
	return normalize_cells(cells)


static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func _compare_cells_by_row(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


static func _append_run(target: PackedInt32Array, y: int, start_x: int, count: int) -> void:
	if count <= 0:
		return
	target.append(y)
	target.append(start_x)
	target.append(count)


func duplicate_data() -> Resource:
	var data: Variant = get_script().new()
	data.house_runs = house_runs.duplicate()
	data.field_runs = field_runs.duplicate()
	data.road_runs = road_runs.duplicate()
	return data


func encode_from_cells(
	house_cells: Array[Vector2i],
	field_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> void:
	house_runs = encode_cells_to_runs(house_cells)
	field_runs = encode_cells_to_runs(field_cells)
	road_runs = encode_cells_to_runs(road_cells)
	_invalidate_cache()


func clear() -> void:
	house_runs = PackedInt32Array()
	field_runs = PackedInt32Array()
	road_runs = PackedInt32Array()
	_invalidate_cache()


func is_empty() -> bool:
	return house_runs.is_empty() and field_runs.is_empty() and road_runs.is_empty()


func get_cell_count() -> int:
	_ensure_cache()
	return _house_cells_cache.size() + _field_cells_cache.size() + _road_cells_cache.size()


func get_compact_storage_bytes() -> int:
	return var_to_bytes({
		"house_runs": house_runs,
		"field_runs": field_runs,
		"road_runs": road_runs,
	}).size()


func to_house_cells() -> Array[Vector2i]:
	_ensure_cache()
	return copy_cells(_house_cells_cache)


func to_field_cells() -> Array[Vector2i]:
	_ensure_cache()
	return copy_cells(_field_cells_cache)


func to_road_cells() -> Array[Vector2i]:
	_ensure_cache()
	return copy_cells(_road_cells_cache)


func _ensure_cache() -> void:
	if _cache_valid:
		return

	_house_cells_cache = decode_runs_to_cells(house_runs)
	_field_cells_cache = decode_runs_to_cells(field_runs)
	_road_cells_cache = decode_runs_to_cells(road_runs)
	_cache_valid = true


func _invalidate_cache() -> void:
	_cache_valid = false
