extends CanvasLayer
class_name TroopBackgroundJobsDebugPanel

@export var force_visible := false
@export_range(0.05, 2.0, 0.05, "or_greater") var refresh_interval_seconds: float = 0.25

@onready var _root_control: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _aggregate_label: Label = %AggregateLabel
@onready var _selected_label: Label = %SelectedLabel
@onready var _pause_button: Button = %PauseButton
@onready var _reset_button: Button = %ResetButton
@onready var _selected_only_check_box: CheckBox = %SelectedOnlyCheckBox

var _selected_troop: Node
var _refresh_remaining := 0.0
var _paused := false


func _ready() -> void:
	_cache_nodes()
	var should_show := force_visible or OS.is_debug_build()
	if _root_control:
		_root_control.visible = should_show
	if _pause_button and not _pause_button.pressed.is_connected(_on_pause_pressed):
		_pause_button.pressed.connect(_on_pause_pressed)
	if _reset_button and not _reset_button.pressed.is_connected(_on_reset_pressed):
		_reset_button.pressed.connect(_on_reset_pressed)
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
	_title_label.text = "Background Jobs"
	_aggregate_label.text = _format_aggregate(summaries)
	_selected_label.text = _format_selected_summary()


func _collect_summaries() -> Array[Dictionary]:
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
	var avg_worker_ms := avg_worker_sum / float(maxi(troops, 1))
	var avg_apply_ms := avg_apply_sum / float(maxi(troops, 1))
	return (
		"Troops %d   Soldiers %d\n"
		+ "In flight %d   Apply batches %d   Results %d\n"
		+ "Jobs %d / %d   Skipped %d\n"
		+ "Worker avg %.2fms max %.2fms\n"
		+ "Apply avg %.2fms max %.2fms   Last count %d"
	) % [
		troops,
		active_soldiers,
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
		+ "Active %d   Worker %s   In flight %s\n"
		+ "Pending effects %s   Results %d   Next %.2fs\n"
		+ "Last worker %.2fms   Last apply %.2fms x%d\n"
		+ "Last worker job %s"
	) % [
		String(summary.get("troop_id", "")),
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
		if node.has_method("reset_stat_job_debug_counters"):
			node.call("reset_stat_job_debug_counters")
	refresh()


func _cache_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _title_label:
		_title_label = get_node_or_null("Root/Panel/Margin/Rows/TitleLabel") as Label
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
	return _root_control != null and _title_label != null and _aggregate_label != null and _selected_label != null
