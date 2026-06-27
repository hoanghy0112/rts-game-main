extends CanvasLayer
class_name TroopBackgroundJobsDebugPanel

@export var force_visible := false
@export_range(0.05, 2.0, 0.05, "or_greater") var refresh_interval_seconds: float = 0.25
@export var movement_map_overlay_enabled := false
@export var route_visuals_enabled := true
@export var tile_grid_enabled := true

@onready var _root_control: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _frame_label: Label = %FrameLabel
@onready var _aggregate_label: Label = %AggregateLabel
@onready var _selected_label: Label = %SelectedLabel
@onready var _pause_button: Button = %PauseButton
@onready var _reset_button: Button = %ResetButton
@onready var _selected_only_check_box: CheckBox = %SelectedOnlyCheckBox
@onready var _soldier_perf_check_box: CheckBox = %SoldierPerfCheckBox
@onready var _combat_lines_check_box: CheckBox = %CombatLinesCheckBox
@onready var _movement_map_check_box: CheckBox = %MovementMapCheckBox
@onready var _route_visuals_check_box: CheckBox = %RouteVisualsCheckBox
@onready var _tile_grid_check_box: CheckBox = %TileGridCheckBox

var _selected_troop: Node
var _refresh_remaining := 0.0
var _paused := false
var _soldier_perf_enabled := false
var _combat_lines_enabled := false
var _movement_map_overlay_enabled := false
var _route_visuals_enabled := true
var _tile_grid_enabled := true


func _ready() -> void:
	_cache_nodes()
	var should_show := force_visible or OS.is_debug_build()
	if _root_control:
		_root_control.visible = should_show
	if _pause_button and not _pause_button.pressed.is_connected(_on_pause_pressed):
		_pause_button.pressed.connect(_on_pause_pressed)
	if _reset_button and not _reset_button.pressed.is_connected(_on_reset_pressed):
		_reset_button.pressed.connect(_on_reset_pressed)
	if _selected_only_check_box and not _selected_only_check_box.toggled.is_connected(_on_selected_only_toggled):
		_selected_only_check_box.toggled.connect(_on_selected_only_toggled)
	if _soldier_perf_check_box:
		_soldier_perf_enabled = _soldier_perf_check_box.button_pressed
		if not _soldier_perf_check_box.toggled.is_connected(_on_soldier_perf_toggled):
			_soldier_perf_check_box.toggled.connect(_on_soldier_perf_toggled)
		_sync_soldier_perf_monitoring()
	if _combat_lines_check_box:
		_combat_lines_enabled = _combat_lines_check_box.button_pressed
		if not _combat_lines_check_box.toggled.is_connected(_on_combat_lines_toggled):
			_combat_lines_check_box.toggled.connect(_on_combat_lines_toggled)
		_sync_combat_debug_lines()
	if _movement_map_check_box:
		_movement_map_check_box.button_pressed = movement_map_overlay_enabled
		_movement_map_overlay_enabled = _movement_map_check_box.button_pressed
		if not _movement_map_check_box.toggled.is_connected(_on_movement_map_toggled):
			_movement_map_check_box.toggled.connect(_on_movement_map_toggled)
		_sync_movement_map_overlay()
	if _route_visuals_check_box:
		_route_visuals_check_box.button_pressed = route_visuals_enabled
		_route_visuals_enabled = _route_visuals_check_box.button_pressed
		if not _route_visuals_check_box.toggled.is_connected(_on_route_visuals_toggled):
			_route_visuals_check_box.toggled.connect(_on_route_visuals_toggled)
		_sync_route_visuals()
	if _tile_grid_check_box:
		_tile_grid_check_box.button_pressed = tile_grid_enabled
		_tile_grid_enabled = _tile_grid_check_box.button_pressed
		if not _tile_grid_check_box.toggled.is_connected(_on_tile_grid_toggled):
			_tile_grid_check_box.toggled.connect(_on_tile_grid_toggled)
		_sync_tile_grid()
	refresh()


func _process(delta: float) -> void:
	if not _root_control or not _root_control.visible or _paused:
		return
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = maxf(refresh_interval_seconds, 0.05)
	refresh()


func set_selected_troop(troop: Node) -> void:
	_selected_troop = troop
	refresh()


func get_selected_troop() -> Node:
	return _selected_troop if is_instance_valid(_selected_troop) else null


func refresh() -> void:
	if not _cache_nodes():
		return
	var summaries := _collect_summaries()
	_title_label.text = "Runtime Debug"
	if _frame_label:
		_frame_label.text = _format_frame_summary()
	_aggregate_label.text = _format_aggregate(summaries)
	_selected_label.text = _format_selected_summary()


func _collect_summaries() -> Array[Dictionary]:
	_sync_soldier_perf_monitoring()
	_sync_combat_debug_lines()
	_sync_route_visuals()
	_sync_movement_map_overlay()
	_sync_tile_grid()
	var summaries: Array[Dictionary] = []
	var tree := get_tree()
	if not tree:
		return summaries
	var selected_only := _selected_only_check_box != null and _selected_only_check_box.button_pressed
	if selected_only:
		if is_instance_valid(_selected_troop) and _selected_troop.has_method("get_stat_job_debug_summary"):
			summaries.append(_selected_troop.call("get_stat_job_debug_summary") as Dictionary)
		return summaries
	for node: Node in tree.get_nodes_in_group(&"troops"):
		if node.has_method("get_stat_job_debug_summary"):
			summaries.append(node.call("get_stat_job_debug_summary") as Dictionary)
	return summaries


func _format_frame_summary() -> String:
	var fps := float(Engine.get_frames_per_second())
	var frame_ms := 1000.0 / maxf(fps, 0.001)
	var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resource_count := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var active_3d_objects := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var draw_calls := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return (
		"FPS %.0f   Frame %.2fms   Process %.2fms   Physics %.2fms\n"
		+ "Draws %d   Prims %d   Nodes %d   Resources %d   3D bodies %d"
	) % [
		fps,
		frame_ms,
		process_ms,
		physics_ms,
		draw_calls,
		primitives,
		node_count,
		resource_count,
		active_3d_objects,
	]


func _format_aggregate(summaries: Array[Dictionary]) -> String:
	var troops := summaries.size()
	var active_soldiers := 0
	var in_flight := 0
	var pending_batches := 0
	var pending_results := 0
	var started_jobs := 0
	var completed_jobs := 0
	var skipped_results := 0
	var last_apply_count := 0
	var max_worker_ms := 0.0
	var max_apply_ms := 0.0
	var avg_worker_sum := 0.0
	var avg_apply_sum := 0.0
	var last_troop_physics_ms := 0.0
	var max_troop_physics_ms := 0.0
	var last_combat_tick_ms := 0.0
	var max_combat_tick_ms := 0.0
	var last_formation_ms := 0.0
	var max_formation_ms := 0.0
	var last_combat_summary_ms := 0.0
	var max_combat_summary_ms := 0.0
	var soldier_sampled_count := 0
	var soldier_last_physics_ms := 0.0
	var soldier_max_physics_ms := 0.0
	var soldier_last_pose_ms := 0.0
	var soldier_max_pose_ms := 0.0
	var active_cache_rebuilds := 0
	var target_candidate_scans := 0
	var separation_pair_checks := 0
	var steering_updates := 0
	var target_scans_per_second := 0
	var pair_checks_per_second := 0
	var steering_updates_per_second := 0
	var worker_wait_count := 0
	var worker_completed_polls := 0
	var worker_blocking_waits := 0
	var render_batch_count := 0
	var render_batched_instances := 0
	var render_hidden_source_meshes := 0
	var render_cached_source_meshes := 0
	var render_last_sync_ms := 0.0
	var render_max_sync_ms := 0.0
	var render_transform_writes := 0
	var render_max_transform_writes := 0
	var render_source_reads := 0
	for summary: Dictionary in summaries:
		active_soldiers += int(summary.get("active_soldier_count", 0))
		in_flight += 1 if bool(summary.get("job_in_flight", false)) else 0
		pending_batches += int(summary.get("pending_apply_batches", 0))
		pending_results += int(summary.get("pending_apply_results", 0))
		started_jobs += int(summary.get("started_jobs", 0))
		completed_jobs += int(summary.get("completed_jobs", 0))
		skipped_results += int(summary.get("skipped_results", 0))
		last_apply_count += int(summary.get("last_apply_count", 0))
		max_worker_ms = maxf(max_worker_ms, float(summary.get("max_worker_ms", 0.0)))
		max_apply_ms = maxf(max_apply_ms, float(summary.get("max_apply_ms", 0.0)))
		avg_worker_sum += float(summary.get("avg_worker_ms", 0.0))
		avg_apply_sum += float(summary.get("avg_apply_ms", 0.0))
		last_troop_physics_ms += float(summary.get("perf_last_physics_ms", 0.0))
		max_troop_physics_ms = maxf(max_troop_physics_ms, float(summary.get("perf_max_physics_ms", 0.0)))
		last_combat_tick_ms += float(summary.get("perf_last_combat_tick_ms", 0.0))
		max_combat_tick_ms = maxf(max_combat_tick_ms, float(summary.get("perf_max_combat_tick_ms", 0.0)))
		last_formation_ms += float(summary.get("perf_last_formation_separation_ms", 0.0))
		max_formation_ms = maxf(max_formation_ms, float(summary.get("perf_max_formation_separation_ms", 0.0)))
		last_combat_summary_ms += float(summary.get("perf_last_combat_summary_ms", 0.0))
		max_combat_summary_ms = maxf(max_combat_summary_ms, float(summary.get("perf_max_combat_summary_ms", 0.0)))
		soldier_sampled_count += int(summary.get("soldier_perf_sampled_count", 0))
		soldier_last_physics_ms += float(summary.get("soldier_perf_last_physics_ms", 0.0))
		soldier_max_physics_ms = maxf(soldier_max_physics_ms, float(summary.get("soldier_perf_max_physics_ms", 0.0)))
		soldier_last_pose_ms += float(summary.get("soldier_perf_last_pose_ms", 0.0))
		soldier_max_pose_ms = maxf(soldier_max_pose_ms, float(summary.get("soldier_perf_max_pose_ms", 0.0)))
		active_cache_rebuilds += int(summary.get("combat_perf_active_cache_rebuilds", 0))
		target_candidate_scans += int(summary.get("combat_perf_target_candidate_scans", 0))
		separation_pair_checks += int(summary.get("combat_perf_separation_pair_checks", 0))
		steering_updates += int(summary.get("combat_perf_steering_updates", 0))
		target_scans_per_second += int(summary.get("combat_perf_target_scans_per_second", 0))
		pair_checks_per_second += int(summary.get("combat_perf_pair_checks_per_second", 0))
		steering_updates_per_second += int(summary.get("combat_perf_steering_updates_per_second", 0))
		worker_wait_count += int(summary.get("perf_stat_worker_wait_count", 0))
		worker_completed_polls += int(summary.get("stat_worker_completed_job_polls", 0))
		worker_blocking_waits += int(summary.get("stat_worker_blocking_waits", 0))
		render_batch_count += int(summary.get("soldier_render_batch_count", 0))
		render_batched_instances += int(summary.get("soldier_render_batched_instance_count", 0))
		render_hidden_source_meshes += int(summary.get("soldier_render_hidden_source_mesh_count", 0))
		render_cached_source_meshes += int(summary.get("soldier_render_cached_source_mesh_count", 0))
		render_last_sync_ms += float(summary.get("soldier_render_last_sync_ms", 0.0))
		render_max_sync_ms = maxf(render_max_sync_ms, float(summary.get("soldier_render_max_sync_ms", 0.0)))
		render_transform_writes += int(summary.get("soldier_render_last_transform_writes", 0))
		render_max_transform_writes = maxi(render_max_transform_writes, int(summary.get("soldier_render_max_transform_writes", 0)))
		render_source_reads += int(summary.get("soldier_render_last_source_reads", 0))
	var avg_worker_ms := avg_worker_sum / float(maxi(troops, 1))
	var avg_apply_ms := avg_apply_sum / float(maxi(troops, 1))
	return (
		"Troops %d   Soldiers %d\n"
		+ "Troop tick %.2fms max %.2fms   Combat %.2fms max %.2fms\n"
		+ "Formation %.2fms max %.2fms   Summary %.2fms max %.2fms\n"
		+ "Soldier sample %s x%d   Phys %.2fms max %.2fms   Pose %.2fms max %.2fms\n"
		+ "Cache rebuilds %d   Target scans %d (%d/s)   Pair checks %d (%d/s)\n"
		+ "Steering %d (%d/s)   Render batches %d inst %d hidden %d cached %d\n"
		+ "Render sync %.2fms max %.2fms   Writes %d max %d reads %d\n"
		+ "Worker polls %d   Blocking waits %d   Worker waits %d\n"
		+ "In flight %d   Apply batches %d   Results %d\n"
		+ "Jobs %d / %d   Skipped %d\n"
		+ "Worker avg %.2fms max %.2fms\n"
		+ "Apply avg %.2fms max %.2fms   Last count %d"
	) % [
		troops,
		active_soldiers,
		last_troop_physics_ms,
		max_troop_physics_ms,
		last_combat_tick_ms,
		max_combat_tick_ms,
		last_formation_ms,
		max_formation_ms,
		last_combat_summary_ms,
		max_combat_summary_ms,
		"on" if _soldier_perf_enabled else "off",
		soldier_sampled_count,
		soldier_last_physics_ms,
		soldier_max_physics_ms,
		soldier_last_pose_ms,
		soldier_max_pose_ms,
		active_cache_rebuilds,
		target_candidate_scans,
		target_scans_per_second,
		separation_pair_checks,
		pair_checks_per_second,
		steering_updates,
		steering_updates_per_second,
		render_batch_count,
		render_batched_instances,
		render_hidden_source_meshes,
		render_cached_source_meshes,
		render_last_sync_ms,
		render_max_sync_ms,
		render_transform_writes,
		render_max_transform_writes,
		render_source_reads,
		worker_completed_polls,
		worker_blocking_waits,
		worker_wait_count,
		in_flight,
		pending_batches,
		pending_results,
		completed_jobs,
		started_jobs,
		skipped_results,
		avg_worker_ms,
		max_worker_ms,
		avg_apply_ms,
		max_apply_ms,
		last_apply_count,
	]


func _format_selected_summary() -> String:
	if not is_instance_valid(_selected_troop) or not _selected_troop.has_method("get_stat_job_debug_summary"):
		return "Selected\nNone"
	var summary := _selected_troop.call("get_stat_job_debug_summary") as Dictionary
	return (
		"Selected  %s\n"
		+ "Troop tick %.2f / %.2fms   Combat %.2f / %.2fms\n"
		+ "Formation %.2f / %.2fms   Summary %.2f / %.2fms\n"
		+ "Soldier sample %s x%d   Phys %.2f / %.2fms   Pose %.2f / %.2fms\n"
		+ "Cache rebuilds %d   Target scans %d (%d/s)   Pair checks %d (%d/s)\n"
		+ "Steering %d (%d/s)   Render batches %d inst %d hidden %d cached %d\n"
		+ "Render sync %.2f / %.2fms   Writes %d / %d reads %d\n"
		+ "Worker polls %d   Blocking waits %d   Worker waits %d\n"
		+ "Soldiers %d   Worker %s   In flight %s\n"
		+ "Pending effects %s   Results %d   Next %.2fs\n"
		+ "Last worker %.2fms   Last apply %.2fms x%d\n"
		+ "Last worker job %s"
	) % [
		String(summary.get("troop_id", "")),
		float(summary.get("perf_last_physics_ms", 0.0)),
		float(summary.get("perf_max_physics_ms", 0.0)),
		float(summary.get("perf_last_combat_tick_ms", 0.0)),
		float(summary.get("perf_max_combat_tick_ms", 0.0)),
		float(summary.get("perf_last_formation_separation_ms", 0.0)),
		float(summary.get("perf_max_formation_separation_ms", 0.0)),
		float(summary.get("perf_last_combat_summary_ms", 0.0)),
		float(summary.get("perf_max_combat_summary_ms", 0.0)),
		"on" if bool(summary.get("soldier_perf_monitoring_enabled", false)) else "off",
		int(summary.get("soldier_perf_sampled_count", 0)),
		float(summary.get("soldier_perf_last_physics_ms", 0.0)),
		float(summary.get("soldier_perf_max_physics_ms", 0.0)),
		float(summary.get("soldier_perf_last_pose_ms", 0.0)),
		float(summary.get("soldier_perf_max_pose_ms", 0.0)),
		int(summary.get("combat_perf_active_cache_rebuilds", 0)),
		int(summary.get("combat_perf_target_candidate_scans", 0)),
		int(summary.get("combat_perf_target_scans_per_second", 0)),
		int(summary.get("combat_perf_separation_pair_checks", 0)),
		int(summary.get("combat_perf_pair_checks_per_second", 0)),
		int(summary.get("combat_perf_steering_updates", 0)),
		int(summary.get("combat_perf_steering_updates_per_second", 0)),
		int(summary.get("soldier_render_batch_count", 0)),
		int(summary.get("soldier_render_batched_instance_count", 0)),
		int(summary.get("soldier_render_hidden_source_mesh_count", 0)),
		int(summary.get("soldier_render_cached_source_mesh_count", 0)),
		float(summary.get("soldier_render_last_sync_ms", 0.0)),
		float(summary.get("soldier_render_max_sync_ms", 0.0)),
		int(summary.get("soldier_render_last_transform_writes", 0)),
		int(summary.get("soldier_render_max_transform_writes", 0)),
		int(summary.get("soldier_render_last_source_reads", 0)),
		int(summary.get("stat_worker_completed_job_polls", 0)),
		int(summary.get("stat_worker_blocking_waits", 0)),
		int(summary.get("perf_stat_worker_wait_count", 0)),
		int(summary.get("active_soldier_count", 0)),
		"on" if bool(summary.get("stat_worker_enabled", false)) else "off",
		"yes" if bool(summary.get("job_in_flight", false)) else "no",
		"yes" if bool(summary.get("pending_effects", false)) else "no",
		int(summary.get("pending_apply_results", 0)),
		float(summary.get("update_remaining", 0.0)),
		float(summary.get("last_worker_ms", 0.0)),
		float(summary.get("last_apply_ms", 0.0)),
		int(summary.get("last_apply_count", 0)),
		"threaded" if bool(summary.get("last_job_used_worker", false)) else "main",
	]


func _on_pause_pressed() -> void:
	_paused = not _paused
	if _pause_button:
		_pause_button.text = "Resume" if _paused else "Pause"
	if not _paused:
		refresh()


func _on_reset_pressed() -> void:
	var tree := get_tree()
	if not tree:
		return
	for node: Node in tree.get_nodes_in_group(&"troops"):
		if node.has_method("reset_perf_debug_counters"):
			node.call("reset_perf_debug_counters")
		else:
			if node.has_method("reset_stat_job_debug_counters"):
				node.call("reset_stat_job_debug_counters")
			if node.has_method("reset_soldier_perf_counters"):
				node.call("reset_soldier_perf_counters")
	refresh()


func _on_selected_only_toggled(_enabled: bool) -> void:
	refresh()


func _on_soldier_perf_toggled(enabled: bool) -> void:
	_soldier_perf_enabled = enabled
	_sync_soldier_perf_monitoring()
	refresh()


func _on_combat_lines_toggled(enabled: bool) -> void:
	_combat_lines_enabled = enabled
	_sync_combat_debug_lines()
	refresh()


func _on_movement_map_toggled(enabled: bool) -> void:
	_movement_map_overlay_enabled = enabled
	_sync_movement_map_overlay()
	refresh()


func _on_route_visuals_toggled(enabled: bool) -> void:
	_route_visuals_enabled = enabled
	_sync_route_visuals()
	refresh()


func _on_tile_grid_toggled(enabled: bool) -> void:
	_tile_grid_enabled = enabled
	_sync_tile_grid()
	refresh()


func _sync_soldier_perf_monitoring() -> void:
	var tree := get_tree()
	if not tree or not _soldier_perf_check_box:
		return
	_soldier_perf_enabled = _soldier_perf_check_box.button_pressed
	for node: Node in tree.get_nodes_in_group(&"troops"):
		_set_troop_soldier_perf_enabled(node, _soldier_perf_enabled)


func _set_troop_soldier_perf_enabled(troop: Node, enabled: bool) -> void:
	if not is_instance_valid(troop):
		return
	if _object_has_property(troop, &"soldier_perf_monitoring_enabled"):
		if bool(troop.get("soldier_perf_monitoring_enabled")) != enabled:
			troop.set("soldier_perf_monitoring_enabled", enabled)
	elif troop.has_method("set_soldier_perf_monitoring_enabled"):
		troop.call("set_soldier_perf_monitoring_enabled", enabled)


func _sync_combat_debug_lines() -> void:
	var tree := get_tree()
	if not tree or not _combat_lines_check_box:
		return
	_combat_lines_enabled = _combat_lines_check_box.button_pressed
	for node: Node in tree.get_nodes_in_group(&"troops"):
		_set_troop_combat_debug_lines_enabled(node, _combat_lines_enabled)


func _set_troop_combat_debug_lines_enabled(troop: Node, enabled: bool) -> void:
	if not is_instance_valid(troop):
		return
	if troop.has_method("are_combat_debug_lines_enabled") and bool(troop.call("are_combat_debug_lines_enabled")) == enabled:
		return
	if troop.has_method("set_combat_debug_lines_enabled"):
		troop.call("set_combat_debug_lines_enabled", enabled)
	elif _object_has_property(troop, &"combat_debug_lines_enabled"):
		if bool(troop.get("combat_debug_lines_enabled")) != enabled:
			troop.set("combat_debug_lines_enabled", enabled)


func _sync_movement_map_overlay() -> void:
	var tree := get_tree()
	if not tree or not _movement_map_check_box:
		return
	_movement_map_overlay_enabled = _movement_map_check_box.button_pressed
	for node: Node in tree.get_nodes_in_group(&"movement_map_overlays"):
		if _object_has_property(node, &"overlay_visible"):
			if bool(node.get("overlay_visible")) != _movement_map_overlay_enabled:
				node.set("overlay_visible", _movement_map_overlay_enabled)
		elif _object_has_property(node, &"show_movement_map"):
			if bool(node.get("show_movement_map")) != _movement_map_overlay_enabled:
				node.set("show_movement_map", _movement_map_overlay_enabled)


func _sync_route_visuals() -> void:
	var tree := get_tree()
	if not tree or not _route_visuals_check_box:
		return
	_route_visuals_enabled = _route_visuals_check_box.button_pressed
	for node: Node in tree.get_nodes_in_group(&"troops"):
		if _object_has_property(node, &"route_debug_visuals_enabled"):
			if bool(node.get("route_debug_visuals_enabled")) != _route_visuals_enabled:
				node.set("route_debug_visuals_enabled", _route_visuals_enabled)


func _sync_tile_grid() -> void:
	var tree := get_tree()
	if not tree or not _tile_grid_check_box:
		return
	_tile_grid_enabled = _tile_grid_check_box.button_pressed
	for node: Node in tree.get_nodes_in_group(&"simplified_terrain_debug"):
		if _object_has_property(node, &"show_tile_grid"):
			if bool(node.get("show_tile_grid")) != _tile_grid_enabled:
				node.set("show_tile_grid", _tile_grid_enabled)


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(String(property.get("name", ""))) == property_name:
			return true
	return false


func _cache_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _title_label:
		_title_label = get_node_or_null("Root/Panel/Margin/Rows/TitleLabel") as Label
	if not _frame_label:
		_frame_label = get_node_or_null("Root/Panel/Margin/Rows/FrameLabel") as Label
	if not _aggregate_label:
		_aggregate_label = get_node_or_null("Root/Panel/Margin/Rows/AggregateLabel") as Label
	if not _selected_label:
		_selected_label = get_node_or_null("Root/Panel/Margin/Rows/SelectedLabel") as Label
	if not _pause_button:
		_pause_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/PauseButton") as Button
	if not _reset_button:
		_reset_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/ResetButton") as Button
	if not _selected_only_check_box:
		_selected_only_check_box = get_node_or_null("Root/Panel/Margin/Rows/SelectedOnlyCheckBox") as CheckBox
	if not _soldier_perf_check_box:
		_soldier_perf_check_box = get_node_or_null("Root/Panel/Margin/Rows/SoldierPerfCheckBox") as CheckBox
	if not _combat_lines_check_box:
		_combat_lines_check_box = get_node_or_null("Root/Panel/Margin/Rows/CombatLinesCheckBox") as CheckBox
	if not _movement_map_check_box:
		_movement_map_check_box = get_node_or_null("Root/Panel/Margin/Rows/MovementMapCheckBox") as CheckBox
	if not _route_visuals_check_box:
		_route_visuals_check_box = get_node_or_null("Root/Panel/Margin/Rows/RouteVisualsCheckBox") as CheckBox
	if not _tile_grid_check_box:
		_tile_grid_check_box = get_node_or_null("Root/Panel/Margin/Rows/TileGridCheckBox") as CheckBox
	return _root_control != null and _title_label != null and _frame_label != null and _aggregate_label != null and _selected_label != null
