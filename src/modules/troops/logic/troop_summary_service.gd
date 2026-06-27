extends "res://modules/troops/logic/troop_service.gd"
class_name TroopSummaryService

var summary_builder: Resource


func set_summary_builder(builder: Resource) -> void:
	summary_builder = builder


func build_troop_summary() -> Dictionary:
	var troop = _troop()
	if not troop:
		return {}
	troop._sync_camp_storage_from_node()
	var mission_summary: Dictionary = troop._get_mission_summary()
	var camp_transfer_summary: Dictionary = troop._get_nearby_camp_transfer_summary()
	var deserter_summary: Dictionary = troop._get_nearby_deserter_summary()
	var summary: Dictionary = {
		"entity_type": &"troop",
		"troop_id": troop.troop_id,
		"display_name": troop.display_name,
		"team_id": troop.team_id,
		"controllable": troop.controllable,
		"soldier_count": troop.get_soldier_count(),
		"state": troop._state,
		"troop_mode": troop.get_troop_mode(),
		"movement_mode": troop.get_movement_mode(),
		"selected": troop._selected,
		"has_destination": troop._has_destination,
		"destination": troop._destination,
		"path_distance_m": float(troop._last_path_result.get("distance_m", 0.0)),
		"estimated_seconds": float(troop._last_path_result.get("estimated_seconds", 0.0)),
		"failure_reason": StringName(troop._last_path_result.get("failure_reason", &"")),
		"carried_food_kg": troop.carried_food_kg,
		"carried_wood_kg": troop.carried_wood_kg,
		"cargo_trolley_count": troop.cargo_trolley_count,
		"cow_count": troop.cow_count,
		"carry_capacity_kg": troop.get_total_carry_capacity_kg(),
		"current_load_kg": troop.get_current_load_kg(),
		"free_capacity_kg": troop.get_free_carry_capacity_kg(),
		"active_soldier_count": troop._get_formation_soldier_count(),
		"busy_carrier_soldiers": troop.get_busy_carrier_soldiers(),
		"available_carrier_soldiers": troop.get_available_carrier_soldiers(),
		"camp_established": troop._camp_established,
		"camp_food_kg": troop.camp_food_kg,
		"camp_wood_kg": troop.camp_wood_kg,
		"camp_wood_invested_kg": troop._camp_wood_invested_kg,
		"camp_total_wood_cost_kg": troop.get_camp_total_wood_cost_kg(),
		"camp_soldiers_per_living_hut": troop.camp_soldiers_per_living_hut,
		"camp_living_hut_count": troop.get_camp_living_hut_count(),
		"camp_living_hut_wood_cost_kg": troop.camp_living_hut_wood_cost_kg,
		"camp_pack_range_m": troop.camp_pack_range_m,
		"camp_pack_in_range": troop.is_camp_pack_in_range(),
		"camp_position": troop.get_camp_world_position(),
		"cargo_trolley_wood_cost_kg": troop.cargo_trolley_wood_cost_kg,
		"cargo_trolley_craft_seconds": troop.cargo_trolley_craft_seconds,
		"cargo_trolley_crafting": troop._cargo_trolley_crafting,
		"cargo_trolley_craft_remaining_seconds": troop._cargo_trolley_craft_remaining_seconds,
		"cargo_trolley_craft_total_seconds": troop._cargo_trolley_craft_total_seconds,
		"idle_cargo_trolley_count": troop._get_idle_cargo_trolley_count(),
	}
	summary.merge(mission_summary, true)
	summary.merge(camp_transfer_summary, true)
	summary.merge(deserter_summary, true)
	summary.merge(build_combat_summary(), true)
	summary.merge(troop._get_corpse_debug_summary(), true)
	return summary


func build_combat_summary() -> Dictionary:
	var troop = _troop()
	if not troop or not summary_builder:
		return {}
	return summary_builder.build_combat_summary(troop)


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
