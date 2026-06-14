extends Node
class_name FieldTerrainRegistry

var _records: Dictionary = {}


func clear() -> void:
	_records.clear()


func register_field(plot_data: FieldPlotData, field_node: Node3D) -> void:
	if not plot_data or not is_instance_valid(field_node):
		return
	_records[plot_data.id] = {
		"plot_data": plot_data,
		"field_node": field_node,
	}


func get_ground_state_at(world_pos: Vector3) -> StringName:
	var record := _get_record_at(world_pos)
	if record.is_empty():
		return &""

	var plot_data := record["plot_data"] as FieldPlotData
	return plot_data.ground_state_id if plot_data else &""


func get_speed_multiplier_at(world_pos: Vector3, unit_type: StringName) -> float:
	var record := _get_record_at(world_pos)
	if record.is_empty():
		return 1.0

	var plot_data := record["plot_data"] as FieldPlotData
	if not plot_data or not plot_data.ground_state_data:
		return 1.0

	return plot_data.ground_state_data.get_speed_multiplier(unit_type)


func _get_record_at(world_pos: Vector3) -> Dictionary:
	for record: Dictionary in _records.values():
		var plot_data := record["plot_data"] as FieldPlotData
		var field_node := record["field_node"] as Node3D
		if not plot_data or not is_instance_valid(field_node):
			continue

		if _contains_world_position(plot_data, field_node, world_pos):
			return record

	return {}


func _contains_world_position(plot_data: FieldPlotData, field_node: Node3D, world_pos: Vector3) -> bool:
	var local_pos := field_node.to_local(world_pos)
	return (
		absf(local_pos.x) <= plot_data.length * 0.5
		and absf(local_pos.z) <= plot_data.width * 0.5
	)
