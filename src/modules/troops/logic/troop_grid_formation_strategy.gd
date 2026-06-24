extends "res://modules/troops/logic/troop_formation_strategy.gd"
class_name TroopGridFormationStrategy


func get_formation_position(troop, index: int, columns: int, rows: int) -> Vector3:
	var safe_columns: int = maxi(columns, 1)
	var column := index % safe_columns
	var row := int(index / safe_columns)
	var spacing: float = maxf(float(troop.formation_spacing), 0.1)
	var width := float(maxi(columns - 1, 0)) * spacing
	var depth := float(maxi(rows - 1, 0)) * spacing
	return Vector3(
		float(column) * spacing - width * 0.5,
		0.0,
		float(row) * spacing - depth * 0.5
	)


func get_natural_offset(troop, index: int, columns: int, rows: int) -> Vector3:
	var spacing: float = maxf(float(troop.formation_spacing), 0.1)
	var unevenness: float = maxf(float(troop.formation_natural_unevenness), 0.0)
	var turn_scatter: float = maxf(float(troop.formation_turn_scatter), 0.0)
	var amount := maxf(unevenness, turn_scatter * 0.12) * spacing
	if amount <= 0.001:
		return Vector3.ZERO

	var safe_columns := maxi(columns, 1)
	var column := index % safe_columns
	var row := int(index / safe_columns)
	var edge_softness := 1.0
	if columns > 1:
		edge_softness -= absf((float(column) / float(columns - 1)) * 2.0 - 1.0) * 0.18
	if rows > 1:
		edge_softness -= absf((float(row) / float(rows - 1)) * 2.0 - 1.0) * 0.12
	edge_softness = clampf(edge_softness, 0.65, 1.0)

	var x_offset := sin(float(index + 1) * 12.9898) * amount * 0.42 * edge_softness
	var z_offset := cos(float(index + 1) * 78.233) * amount * 0.30 * edge_softness
	return Vector3(x_offset, 0.0, z_offset)
