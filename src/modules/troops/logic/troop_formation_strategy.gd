extends Resource
class_name TroopFormationStrategy


func slot_to_world(troop, slot: Vector3) -> Vector3:
	return troop.global_transform * slot


func get_formation_position(_troop, _index: int, _columns: int, _rows: int) -> Vector3:
	return Vector3.ZERO


func get_slot_for_index(troop, index: int, columns: int, rows: int) -> Vector3:
	return get_formation_position(troop, index, columns, rows) + get_natural_offset(troop, index, columns, rows)


func get_natural_offset(_troop, _index: int, _columns: int, _rows: int) -> Vector3:
	return Vector3.ZERO


func get_columns_for_width(troop, width_m: float, active_count: int) -> int:
	var spacing: float = maxf(float(troop.formation_spacing), 0.1)
	var width_columns := int(round(maxf(width_m, 0.0) / spacing)) + 1
	return clampi(width_columns, 1, maxi(active_count, 1))
