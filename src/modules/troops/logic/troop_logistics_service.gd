extends "res://modules/troops/logic/troop_service.gd"
class_name TroopLogisticsService


func physics_tick(delta: float) -> void:
	update_transport_and_modes(delta)
	update_mission_task(delta)


func update_transport_and_modes(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_cargo_trolley_crafting(delta)
	troop._update_carrier_tasks(delta)
	troop._update_food_and_modes(delta)


func update_mission_task(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_mission_task(delta)


func post_physics_tick(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	if not Engine.is_in_physics_frame():
		troop._step_child_mission_troops_for_manual_call(delta)


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
