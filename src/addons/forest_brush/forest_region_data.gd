@tool
extends Resource
class_name ForestRegionData

const RUN_FIELD_COUNT := 6
const RUN_CHUNK_X := 0
const RUN_CHUNK_Y := 1
const RUN_LOCAL_ROW := 2
const RUN_START_COLUMN := 3
const RUN_LENGTH := 4
const RUN_PLANT_SET_INDEX := 5

@export_range(1, 128, 1, "or_greater") var chunk_size_cells: int = 8:
	set(value):
		chunk_size_cells = maxi(value, 1)
		_invalidate_cache()

@export var plant_sets: Array[PackedStringArray] = []:
	set(value):
		plant_sets = _copy_plant_sets(value)
		_invalidate_cache()

@export var row_runs: PackedInt32Array = PackedInt32Array():
	set(value):
		row_runs = value
		_invalidate_cache()

var _cache_valid := false
var _cell_plant_ids_by_cell: Dictionary = {}
var _chunk_cells: Dictionary = {}


static func normalize_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var unique_cells: Dictionary = {}
	for cell: Vector2i in value:
		unique_cells[cell] = true

	var normalized: Array[Vector2i] = []
	for key: Variant in unique_cells.keys():
		normalized.append(key as Vector2i)
	normalized.sort_custom(_compare_cells)
	return normalized


static func normalize_cell_plant_ids(value: Dictionary, valid_cells: Array[Vector2i] = []) -> Dictionary:
	var valid_cell_lookup: Dictionary = {}
	for cell: Vector2i in valid_cells:
		valid_cell_lookup[cell_key(cell)] = true

	var normalized: Dictionary = {}
	for key: Variant in value.keys():
		var key_string := cell_key_from_variant(key)
		if key_string.is_empty():
			continue
		if not valid_cell_lookup.is_empty() and not valid_cell_lookup.has(key_string):
			continue

		var plant_ids := normalize_plant_ids(value[key])
		if not plant_ids.is_empty():
			normalized[key_string] = plant_ids

	return normalized


static func normalize_plant_ids(value: Variant) -> Array[StringName]:
	var plant_ids: Array[StringName] = []
	if value is PackedStringArray:
		for plant_id_string: String in value:
			var plant_id := StringName(plant_id_string)
			if plant_id != &"" and not plant_ids.has(plant_id):
				plant_ids.append(plant_id)
	elif value is Array:
		for plant_id_variant: Variant in value:
			var plant_id := StringName(plant_id_variant)
			if plant_id != &"" and not plant_ids.has(plant_id):
				plant_ids.append(plant_id)
	elif value is StringName or value is String:
		var single_id := StringName(value)
		if single_id != &"":
			plant_ids.append(single_id)
	return plant_ids


static func copy_cells(value: Array[Vector2i]) -> Array[Vector2i]:
	var copied: Array[Vector2i] = []
	for cell: Vector2i in value:
		copied.append(cell)
	return copied


static func copy_cell_plant_ids(value: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for key: Variant in value.keys():
		copied[str(key)] = normalize_plant_ids(value[key])
	return copied


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func cell_key_from_variant(value: Variant) -> String:
	if value is Vector2i:
		return cell_key(value as Vector2i)
	var key_string := str(value)
	return key_string if key_string.contains(",") else ""


static func cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i

	var key_string := cell_key_from_variant(value)
	var parts := key_string.split(",", false, 1)
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func is_cell_key_valid(value: Variant) -> bool:
	if value is Vector2i:
		return true

	var key_string := cell_key_from_variant(value)
	var parts := key_string.split(",", false, 1)
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()


static func get_chunk_coord_for_cell(cell: Vector2i, encoded_chunk_size: int) -> Vector2i:
	var safe_chunk_size := maxi(encoded_chunk_size, 1)
	return Vector2i(
		floori(float(cell.x) / float(safe_chunk_size)),
		floori(float(cell.y) / float(safe_chunk_size))
	)


static func compact_storage_bytes_for(
	cells: Array[Vector2i],
	cell_plant_ids: Dictionary,
	encoded_chunk_size: int
) -> int:
	var script := load("res://addons/forest_brush/forest_region_data.gd") as Script
	var data: Variant = script.new()
	data.encode_from_cells(cells, cell_plant_ids, encoded_chunk_size)
	return data.get_compact_storage_bytes()


static func legacy_storage_bytes_for(cells: Array[Vector2i], cell_plant_ids: Dictionary) -> int:
	return var_to_bytes({
		"forest_cells": copy_cells(cells),
		"cell_plant_ids": copy_cell_plant_ids(cell_plant_ids),
	}).size()


static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func _compare_chunks(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func _compare_run_records(a: Dictionary, b: Dictionary) -> bool:
	var a_chunk := a.get("chunk", Vector2i.ZERO) as Vector2i
	var b_chunk := b.get("chunk", Vector2i.ZERO) as Vector2i
	if a_chunk.x != b_chunk.x:
		return a_chunk.x < b_chunk.x
	if a_chunk.y != b_chunk.y:
		return a_chunk.y < b_chunk.y
	var a_row := int(a.get("row", 0))
	var b_row := int(b.get("row", 0))
	if a_row != b_row:
		return a_row < b_row
	return int(a.get("column", 0)) < int(b.get("column", 0))


func duplicate_data() -> Resource:
	var data: Variant = get_script().new()
	data.chunk_size_cells = chunk_size_cells
	data.plant_sets = _copy_plant_sets(plant_sets)
	data.row_runs = row_runs.duplicate()
	return data


func encode_from_cells(
	cells: Array[Vector2i],
	cell_plant_ids: Dictionary,
	encoded_chunk_size: int = -1
) -> void:
	if encoded_chunk_size > 0:
		chunk_size_cells = encoded_chunk_size

	var normalized_cells := normalize_cells(cells)
	var normalized_plant_map := normalize_cell_plant_ids(cell_plant_ids, normalized_cells)
	var cell_entries: Dictionary = {}
	for cell: Vector2i in normalized_cells:
		cell_entries[cell] = _to_packed_strings(normalized_plant_map.get(cell_key(cell), []))

	_encode_cell_entries(cell_entries)


func clear() -> void:
	plant_sets.clear()
	row_runs = PackedInt32Array()
	_invalidate_cache()


func is_empty() -> bool:
	return row_runs.is_empty()


func get_cell_count() -> int:
	_ensure_cache()
	return _cell_plant_ids_by_cell.size()


func get_run_count() -> int:
	return row_runs.size() / RUN_FIELD_COUNT


func get_compact_storage_bytes() -> int:
	return var_to_bytes({
		"chunk_size_cells": chunk_size_cells,
		"plant_sets": plant_sets,
		"row_runs": row_runs,
	}).size()


func to_cells() -> Array[Vector2i]:
	_ensure_cache()
	var cells: Array[Vector2i] = []
	for key: Variant in _cell_plant_ids_by_cell.keys():
		cells.append(key as Vector2i)
	cells.sort_custom(_compare_cells)
	return cells


func to_cell_plant_ids() -> Dictionary:
	_ensure_cache()
	var result: Dictionary = {}
	var cells := to_cells()
	for cell: Vector2i in cells:
		var plant_ids := get_cell_plant_ids(cell)
		if not plant_ids.is_empty():
			result[cell_key(cell)] = plant_ids
	return result


func has_cell(cell: Vector2i) -> bool:
	_ensure_cache()
	return _cell_plant_ids_by_cell.has(cell)


func get_cell_plant_ids(cell: Vector2i) -> Array[StringName]:
	_ensure_cache()
	var raw_ids: Variant = _cell_plant_ids_by_cell.get(cell, PackedStringArray())
	return normalize_plant_ids(raw_ids)


func get_chunks() -> Array[Vector2i]:
	_ensure_cache()
	var chunks: Array[Vector2i] = []
	for key: Variant in _chunk_cells.keys():
		chunks.append(key as Vector2i)
	chunks.sort_custom(_compare_chunks)
	return chunks


func get_cells_in_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	_ensure_cache()
	var cells: Array[Vector2i] = []
	var chunk_record: Variant = _chunk_cells.get(chunk_coord)
	if chunk_record is Dictionary:
		for key: Variant in (chunk_record as Dictionary).keys():
			cells.append(key as Vector2i)
	cells.sort_custom(_compare_cells)
	return cells


func paint_cells(cells: Array[Vector2i], plant_ids: Array[StringName]) -> Dictionary:
	var normalized_cells := normalize_cells(cells)
	var normalized_plant_ids := normalize_plant_ids(plant_ids)
	return _patch_cells(normalized_cells, normalized_plant_ids, false)


func erase_cells(cells: Array[Vector2i]) -> Dictionary:
	return _patch_cells(normalize_cells(cells), [], true)


func set_cells(cells: Array[Vector2i], plant_ids: Array[StringName]) -> Dictionary:
	return paint_cells(cells, plant_ids)


func get_changed_chunks_for_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var chunk_lookup: Dictionary = {}
	for cell: Vector2i in cells:
		chunk_lookup[get_chunk_coord_for_cell(cell, chunk_size_cells)] = true
	return _lookup_to_chunks(chunk_lookup)


func _patch_cells(cells: Array[Vector2i], plant_ids: Array[StringName], erase: bool) -> Dictionary:
	if cells.is_empty():
		return {
			"changed": false,
			"changed_cells": [],
			"changed_chunks": [],
		}

	_ensure_cache()

	var changed_cells: Array[Vector2i] = []
	var changed_chunk_lookup: Dictionary = {}
	var packed_ids := _to_packed_strings(plant_ids)
	for cell: Vector2i in cells:
		var had_cell := _cell_plant_ids_by_cell.has(cell)
		var before_ids: Array[StringName] = []
		if had_cell:
			before_ids = get_cell_plant_ids(cell)
		var changed := false
		if erase:
			if had_cell:
				_cell_plant_ids_by_cell.erase(cell)
				changed = true
		elif not had_cell or before_ids != plant_ids:
			_cell_plant_ids_by_cell[cell] = packed_ids
			changed = true

		if changed:
			changed_cells.append(cell)
			changed_chunk_lookup[get_chunk_coord_for_cell(cell, chunk_size_cells)] = true

	if changed_cells.is_empty():
		return {
			"changed": false,
			"changed_cells": [],
			"changed_chunks": [],
		}

	_encode_cell_entries(_cell_plant_ids_by_cell)
	return {
		"changed": true,
		"changed_cells": changed_cells,
		"changed_chunks": _lookup_to_chunks(changed_chunk_lookup),
	}


func _ensure_cache() -> void:
	if _cache_valid:
		return

	_cell_plant_ids_by_cell.clear()
	_chunk_cells.clear()

	var safe_chunk_size := maxi(chunk_size_cells, 1)
	var run_count := row_runs.size() / RUN_FIELD_COUNT
	for run_index: int in range(run_count):
		var offset := run_index * RUN_FIELD_COUNT
		var chunk_coord := Vector2i(row_runs[offset + RUN_CHUNK_X], row_runs[offset + RUN_CHUNK_Y])
		var local_row := row_runs[offset + RUN_LOCAL_ROW]
		var start_column := row_runs[offset + RUN_START_COLUMN]
		var run_length := maxi(row_runs[offset + RUN_LENGTH], 0)
		var plant_set_index := row_runs[offset + RUN_PLANT_SET_INDEX]
		var plant_ids := _get_packed_plant_set(plant_set_index)
		for column_offset: int in range(run_length):
			var cell := Vector2i(
				chunk_coord.x * safe_chunk_size + start_column + column_offset,
				chunk_coord.y * safe_chunk_size + local_row
			)
			_cell_plant_ids_by_cell[cell] = plant_ids
			var chunk_record: Dictionary = _chunk_cells.get(chunk_coord, {})
			chunk_record[cell] = true
			_chunk_cells[chunk_coord] = chunk_record

	_cache_valid = true


func _encode_cell_entries(cell_entries: Dictionary) -> void:
	var cells: Array[Vector2i] = []
	for key: Variant in cell_entries.keys():
		if key is Vector2i:
			cells.append(key as Vector2i)
	cells.sort_custom(_compare_cells)

	var next_plant_sets: Array[PackedStringArray] = []
	var plant_set_indices_by_key: Dictionary = {}
	var records: Array[Dictionary] = []
	var safe_chunk_size := maxi(chunk_size_cells, 1)

	for cell: Vector2i in cells:
		var packed_ids := _to_packed_strings(cell_entries[cell])
		var plant_set_key := _plant_set_key(packed_ids)
		var plant_set_index := int(plant_set_indices_by_key.get(plant_set_key, -1))
		if plant_set_index < 0:
			plant_set_index = next_plant_sets.size()
			next_plant_sets.append(packed_ids)
			plant_set_indices_by_key[plant_set_key] = plant_set_index

		var chunk_coord := get_chunk_coord_for_cell(cell, safe_chunk_size)
		records.append({
			"chunk": chunk_coord,
			"row": cell.y - chunk_coord.y * safe_chunk_size,
			"column": cell.x - chunk_coord.x * safe_chunk_size,
			"plant_set_index": plant_set_index,
		})

	records.sort_custom(_compare_run_records)

	var next_row_runs := PackedInt32Array()
	var active_chunk := Vector2i.ZERO
	var active_row := 0
	var active_column := 0
	var active_length := 0
	var active_plant_set_index := -1
	var has_active_run := false

	for record: Dictionary in records:
		var chunk_coord := record.get("chunk", Vector2i.ZERO) as Vector2i
		var row := int(record.get("row", 0))
		var column := int(record.get("column", 0))
		var plant_set_index := int(record.get("plant_set_index", -1))
		var can_extend := (
			has_active_run
			and chunk_coord == active_chunk
			and row == active_row
			and plant_set_index == active_plant_set_index
			and column == active_column + active_length
		)

		if can_extend:
			active_length += 1
			continue

		if has_active_run:
			_append_run(next_row_runs, active_chunk, active_row, active_column, active_length, active_plant_set_index)

		active_chunk = chunk_coord
		active_row = row
		active_column = column
		active_length = 1
		active_plant_set_index = plant_set_index
		has_active_run = true

	if has_active_run:
		_append_run(next_row_runs, active_chunk, active_row, active_column, active_length, active_plant_set_index)

	plant_sets = next_plant_sets
	row_runs = next_row_runs
	_invalidate_cache()


func _append_run(
	target: PackedInt32Array,
	chunk_coord: Vector2i,
	local_row: int,
	start_column: int,
	run_length: int,
	plant_set_index: int
) -> void:
	target.append(chunk_coord.x)
	target.append(chunk_coord.y)
	target.append(local_row)
	target.append(start_column)
	target.append(run_length)
	target.append(plant_set_index)


func _lookup_to_chunks(chunk_lookup: Dictionary) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	for key: Variant in chunk_lookup.keys():
		chunks.append(key as Vector2i)
	chunks.sort_custom(_compare_chunks)
	return chunks


func _get_packed_plant_set(plant_set_index: int) -> PackedStringArray:
	if plant_set_index < 0 or plant_set_index >= plant_sets.size():
		return PackedStringArray()
	return plant_sets[plant_set_index]


func _plant_set_key(plant_ids: PackedStringArray) -> String:
	var key_parts: Array[String] = []
	for plant_id: String in plant_ids:
		key_parts.append("%d:%s" % [plant_id.length(), plant_id])
	return "|".join(key_parts)


func _to_packed_strings(value: Variant) -> PackedStringArray:
	var plant_ids := normalize_plant_ids(value)
	var packed := PackedStringArray()
	for plant_id: StringName in plant_ids:
		packed.append(str(plant_id))
	return packed


func _copy_plant_sets(value: Array[PackedStringArray]) -> Array[PackedStringArray]:
	var copied: Array[PackedStringArray] = []
	for plant_set: PackedStringArray in value:
		copied.append(plant_set.duplicate())
	return copied


func _invalidate_cache() -> void:
	_cache_valid = false
