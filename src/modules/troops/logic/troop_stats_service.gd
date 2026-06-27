extends "res://modules/troops/logic/troop_service.gd"
class_name TroopStatsService


func pre_physics_tick() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._poll_completed_stat_job()
	troop._apply_pending_stat_results()


func physics_tick(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_stat_jobs(delta)


func exit_tree() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._wait_for_stat_worker()


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
