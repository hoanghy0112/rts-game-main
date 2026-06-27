extends Resource
class_name TroopServiceSet

const TroopPresentationServiceScript = preload("res://modules/troops/logic/troop_presentation_service.gd")
const TroopFormationServiceScript = preload("res://modules/troops/logic/troop_formation_service.gd")
const TroopMovementServiceScript = preload("res://modules/troops/logic/troop_movement_service.gd")
const TroopCombatServiceScript = preload("res://modules/troops/logic/troop_combat_service.gd")
const TroopLogisticsServiceScript = preload("res://modules/troops/logic/troop_logistics_service.gd")
const TroopStatsServiceScript = preload("res://modules/troops/logic/troop_stats_service.gd")
const TroopSummaryServiceScript = preload("res://modules/troops/logic/troop_summary_service.gd")

@export var presentation_service: Resource
@export var formation_service: Resource
@export var movement_service: Resource
@export var combat_service: Resource
@export var logistics_service: Resource
@export var stats_service: Resource
@export var summary_service: Resource

var context


func duplicate_for_runtime() -> Resource:
	var copy := duplicate(true)
	if copy.has_method("ensure_defaults"):
		copy.call("ensure_defaults")
	return copy


func ensure_defaults() -> void:
	if not presentation_service:
		presentation_service = TroopPresentationServiceScript.new()
	if not formation_service:
		formation_service = TroopFormationServiceScript.new()
	if not movement_service:
		movement_service = TroopMovementServiceScript.new()
	if not combat_service:
		combat_service = TroopCombatServiceScript.new()
	if not logistics_service:
		logistics_service = TroopLogisticsServiceScript.new()
	if not stats_service:
		stats_service = TroopStatsServiceScript.new()
	if not summary_service:
		summary_service = TroopSummaryServiceScript.new()


func configure_legacy_dependencies(
	formation_strategy: Resource,
	movement_logic: Resource,
	combat_positioning_logic: Resource,
	summary_builder: Resource
) -> void:
	ensure_defaults()
	if formation_service and formation_service.has_method("set_formation_strategy"):
		formation_service.call("set_formation_strategy", formation_strategy)
	if movement_service and movement_service.has_method("set_movement_logic"):
		movement_service.call("set_movement_logic", movement_logic)
	if combat_service and combat_service.has_method("set_combat_positioning_logic"):
		combat_service.call("set_combat_positioning_logic", combat_positioning_logic)
	if summary_service and summary_service.has_method("set_summary_builder"):
		summary_service.call("set_summary_builder", summary_builder)


func configure(runtime_context) -> void:
	context = runtime_context
	ensure_defaults()
	for service: Resource in _services():
		if service and service.has_method("configure"):
			service.call("configure", runtime_context)


func ready() -> void:
	if presentation_service and presentation_service.has_method("ready"):
		presentation_service.call("ready")


func physics_tick(delta: float) -> void:
	if not context or not context.is_valid():
		return
	var troop = context.troop
	var perf_started: int = Time.get_ticks_usec() if troop.troop_perf_monitoring_enabled else 0
	if combat_service and combat_service.has_method("update_perf_rate_window"):
		combat_service.call("update_perf_rate_window", delta)
	if stats_service and stats_service.has_method("pre_physics_tick"):
		stats_service.call("pre_physics_tick")
	if logistics_service and logistics_service.has_method("update_transport_and_modes"):
		logistics_service.call("update_transport_and_modes", delta)
	if combat_service and combat_service.has_method("update_ai"):
		combat_service.call("update_ai", delta)
	if presentation_service and presentation_service.has_method("update_pre_movement"):
		presentation_service.call("update_pre_movement", delta)
	if movement_service:
		movement_service.call("physics_tick", delta)
	if formation_service and formation_service.has_method("update_slots"):
		formation_service.call("update_slots", delta)
	if logistics_service and logistics_service.has_method("update_mission_task"):
		logistics_service.call("update_mission_task", delta)
	if presentation_service and presentation_service.has_method("update_world_indicators"):
		presentation_service.call("update_world_indicators")
	if combat_service and combat_service.has_method("update_soldier_animation"):
		combat_service.call("update_soldier_animation", delta)
	if formation_service and formation_service.has_method("step_soldier_logic"):
		formation_service.call("step_soldier_logic", delta)
	if formation_service and formation_service.has_method("align_moving_soldiers"):
		formation_service.call("align_moving_soldiers")
	if stats_service:
		stats_service.call("physics_tick", delta)
	if combat_service and combat_service.has_method("maybe_emit_changed"):
		combat_service.call("maybe_emit_changed", delta)
	if combat_service and combat_service.has_method("update_debug_lines"):
		combat_service.call("update_debug_lines")
	if formation_service and formation_service.has_method("update_soldier_logic_sleeping"):
		formation_service.call("update_soldier_logic_sleeping", delta)
	if formation_service and formation_service.has_method("step_child_mission_troops_for_manual_call"):
		formation_service.call("step_child_mission_troops_for_manual_call", delta)
	if troop.troop_perf_monitoring_enabled:
		troop._perf_last_physics_usec = Time.get_ticks_usec() - perf_started
		troop._perf_max_physics_usec = maxi(troop._perf_max_physics_usec, troop._perf_last_physics_usec)


func process_tick(delta: float) -> void:
	if presentation_service:
		presentation_service.call("process_tick", delta)


func exit_tree() -> void:
	if stats_service:
		stats_service.call("exit_tree")
	if presentation_service:
		presentation_service.call("exit_tree")


func build_troop_summary() -> Dictionary:
	if summary_service and summary_service.has_method("build_troop_summary"):
		return summary_service.call("build_troop_summary") as Dictionary
	return {}


func build_combat_summary() -> Dictionary:
	if summary_service and summary_service.has_method("build_combat_summary"):
		return summary_service.call("build_combat_summary") as Dictionary
	return {}


func _services() -> Array[Resource]:
	return [
		presentation_service,
		formation_service,
		movement_service,
		combat_service,
		logistics_service,
		stats_service,
		summary_service,
	]
