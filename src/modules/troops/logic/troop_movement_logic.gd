extends Resource
class_name TroopMovementLogic


func get_current_movement_speed_mps(troop) -> float:
	if troop.is_mission_troop and troop._is_mission_active():
		return maxf(float(troop.carrier_speed_mps), 0.1)
	var soldiers: Array = troop._get_active_soldiers()
	var active_count := soldiers.size()
	var minimum_run_speed: float = troop._get_minimum_active_run_speed_live(soldiers)
	var fallback_speed := maxf(float(troop.movement_speed_mps), 0.1) if active_count <= 0 else 0.1
	var speed := maxf(minimum_run_speed, fallback_speed)
	if troop.get_movement_mode() == troop.MOVEMENT_RUNNING:
		speed *= maxf(float(troop.running_speed_multiplier), 1.0)
	return speed


func get_soldier_path_speed(troop, soldier: Node) -> float:
	if troop.is_mission_troop and troop._is_mission_active():
		return maxf(float(troop.carrier_speed_mps), 0.1)
	if troop.get_movement_mode() == troop.MOVEMENT_RUNNING:
		return maxf(troop._get_soldier_run_speed(soldier) * maxf(float(troop.running_speed_multiplier), 1.0), 0.1)
	return maxf(troop._get_minimum_active_run_speed_live(), 0.1)


func get_soldier_slot_follow_speed(troop, soldier: Node) -> float:
	return maxf(maxf(float(troop.formation_slot_follow_speed), 0.1), get_soldier_path_speed(troop, soldier))


func get_formation_path_follow_speed(troop) -> float:
	return maxf(get_current_movement_speed_mps(troop), 0.1)


func get_idle_formation_slot_speed(troop, soldier: Node) -> float:
	return get_soldier_slot_follow_speed(troop, soldier)


func get_movement_endurance_loss_rate(troop) -> float:
	return float(troop.run_endurance_loss_per_second) if troop.get_movement_mode() == troop.MOVEMENT_RUNNING else 0.0
