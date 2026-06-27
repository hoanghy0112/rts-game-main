extends "res://modules/troops/logic/troop_service.gd"
class_name TroopPresentationService

const TroopRouteVisualScript = preload("res://modules/troops/troop_route_visual.gd")
const TroopSoldierBatchRendererScript = preload("res://modules/troops/troop_soldier_batch_renderer.gd")


func ready() -> void:
	ensure_scene_nodes()


func physics_tick(delta: float) -> void:
	update_pre_movement(delta)
	update_world_indicators()


func update_pre_movement(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._process_pending_departed_soldier_removals()
	troop._refresh_unit_selection_proxies_if_needed(delta)
	troop._update_defeated_presentation()


func update_world_indicators() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_management_flag_position()
	troop._update_attack_zone_indicator()


func process_tick(delta: float) -> void:
	var troop = _troop()
	if not troop:
		return
	troop._update_management_flag_position()
	troop._update_attack_zone_indicator()
	troop._update_management_flag_facing()
	troop._update_management_flag_camera_scale()
	troop._sync_soldier_batch_renderer(delta)


func exit_tree() -> void:
	var troop = _troop()
	if not troop:
		return
	troop._clear_combat_debug_lines()
	troop._clear_independent_camp()


func ensure_scene_nodes() -> void:
	var troop = _troop()
	if not troop:
		return

	troop._soldier_container = troop.get_node_or_null(troop.SOLDIER_CONTAINER_NAME) as Node3D
	if not troop._soldier_container:
		troop._soldier_container = Node3D.new()
		troop._soldier_container.name = troop.SOLDIER_CONTAINER_NAME
		troop.add_child(troop._soldier_container)
		troop._soldier_container.owner = null

	troop._soldier_batch_renderer = troop.get_node_or_null(troop.SOLDIER_BATCH_RENDERER_NAME)
	if not troop._soldier_batch_renderer:
		troop._soldier_batch_renderer = TroopSoldierBatchRendererScript.new()
		troop._soldier_batch_renderer.name = troop.SOLDIER_BATCH_RENDERER_NAME
		troop.add_child(troop._soldier_batch_renderer)
		troop._soldier_batch_renderer.owner = null
	troop._configure_soldier_batch_renderer()

	troop._route_visual = troop.get_node_or_null(troop.ROUTE_VISUAL_NAME)
	if not troop._route_visual:
		troop._route_visual = TroopRouteVisualScript.new()
		troop._route_visual.name = troop.ROUTE_VISUAL_NAME
		troop.add_child(troop._route_visual)
		troop._route_visual.owner = null
	if troop._route_visual.has_method("configure_terrain"):
		troop._route_visual.call("configure_terrain", troop._terrain)
	troop._apply_route_visual_settings()

	troop._carrier_container = troop.get_node_or_null(troop.CARRIER_CONTAINER_NAME) as Node3D
	if not troop._carrier_container:
		troop._carrier_container = Node3D.new()
		troop._carrier_container.name = troop.CARRIER_CONTAINER_NAME
		troop.add_child(troop._carrier_container)
		troop._carrier_container.owner = null
	troop._carrier_container.top_level = true
	troop._carrier_container.global_transform = Transform3D.IDENTITY


func _troop():
	if context and context.is_valid():
		return context.troop
	return null
