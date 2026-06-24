extends "res://modules/units/troop_soldier/logic/troop_soldier_walk_logic.gd"
class_name TroopSoldierRunLogic


func get_run_speed(soldier) -> float:
	return maxf(float(soldier.run_speed), 0.1)


func begin_direct_move(soldier, world_position: Vector3, run: bool = true) -> void:
	if not soldier.formation_visual_only:
		soldier._call_human_set_move_target(world_position, run)
		return
	apply_formation_walking(soldier, true, get_run_speed(soldier) if run else soldier.walk_speed)
