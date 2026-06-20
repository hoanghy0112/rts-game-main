extends CanvasLayer
class_name TroopManagementDrawer

@onready var _root_control: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _state_label: Label = %StateLabel
@onready var _destination_label: Label = %DestinationLabel
@onready var _path_label: Label = %PathLabel
@onready var _eta_label: Label = %EtaLabel
@onready var _failure_label: Label = %FailureLabel
@onready var _stop_button: Button = %StopButton
@onready var _clear_button: Button = %ClearButton

var _troop: Node


func _ready() -> void:
	_cache_control_nodes()
	if _stop_button and not _stop_button.pressed.is_connected(_on_stop_pressed):
		_stop_button.pressed.connect(_on_stop_pressed)
	if _clear_button and not _clear_button.pressed.is_connected(_on_clear_pressed):
		_clear_button.pressed.connect(_on_clear_pressed)
	hide_drawer()


func _exit_tree() -> void:
	_unbind_troop()


func show_troop(troop: Node) -> void:
	_bind_troop(troop)
	if _cache_control_nodes():
		_root_control.visible = true
	refresh()


func hide_drawer() -> void:
	if _cache_control_nodes():
		_root_control.visible = false


func refresh() -> void:
	if not _cache_control_nodes() or not _troop or not _troop.has_method("get_troop_summary"):
		return

	var summary: Dictionary = _troop.call("get_troop_summary") as Dictionary
	var display_name := String(summary.get("display_name", "Troop"))
	var troop_id := String(summary.get("troop_id", ""))
	var soldier_count := int(summary.get("soldier_count", 0))
	var state := String(summary.get("state", &"idle")).capitalize()
	var has_destination := bool(summary.get("has_destination", false))
	var destination: Vector3 = summary.get("destination", Vector3.ZERO)
	var distance := float(summary.get("path_distance_m", 0.0))
	var eta := float(summary.get("estimated_seconds", 0.0))
	var failure_reason := String(summary.get("failure_reason", &""))

	_title_label.text = display_name
	_subtitle_label.text = "%s  %d soldiers" % [troop_id, soldier_count]
	_state_label.text = "State  %s" % state
	if has_destination:
		_destination_label.text = "Destination  %.0f, %.0f" % [destination.x, destination.z]
		_path_label.text = "Route  %s" % _format_meters(distance)
		_eta_label.text = "ETA  %s" % _format_seconds(eta)
	else:
		_destination_label.text = "Destination  None"
		_path_label.text = "Route  -"
		_eta_label.text = "ETA  -"

	_failure_label.visible = not failure_reason.is_empty()
	_failure_label.text = "Last order  %s" % failure_reason.replace("_", " ")
	_stop_button.disabled = not has_destination
	_clear_button.disabled = not has_destination and failure_reason.is_empty()


func _bind_troop(troop: Node) -> void:
	if _troop == troop:
		return
	_unbind_troop()
	_troop = troop
	_connect_troop_signal(&"selected_changed")
	_connect_troop_signal(&"state_changed")
	_connect_troop_signal(&"destination_changed")


func _unbind_troop() -> void:
	if not _troop:
		return
	_disconnect_troop_signal(&"selected_changed")
	_disconnect_troop_signal(&"state_changed")
	_disconnect_troop_signal(&"destination_changed")
	_troop = null


func _connect_troop_signal(signal_name: StringName) -> void:
	var callable := Callable(self, "_on_troop_changed")
	if _troop and _troop.has_signal(signal_name) and not _troop.is_connected(signal_name, callable):
		_troop.connect(signal_name, callable)


func _disconnect_troop_signal(signal_name: StringName) -> void:
	var callable := Callable(self, "_on_troop_changed")
	if _troop and _troop.has_signal(signal_name) and _troop.is_connected(signal_name, callable):
		_troop.disconnect(signal_name, callable)


func _on_troop_changed(_value: Variant = null) -> void:
	refresh()


func _on_stop_pressed() -> void:
	if _troop and _troop.has_method("stop_movement"):
		_troop.call("stop_movement")
	refresh()


func _on_clear_pressed() -> void:
	if _troop and _troop.has_method("clear_destination"):
		_troop.call("clear_destination")
	refresh()


func _cache_control_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _title_label:
		_title_label = get_node_or_null("Root/Panel/Margin/Rows/TitleLabel") as Label
	if not _subtitle_label:
		_subtitle_label = get_node_or_null("Root/Panel/Margin/Rows/SubtitleLabel") as Label
	if not _state_label:
		_state_label = get_node_or_null("Root/Panel/Margin/Rows/StateLabel") as Label
	if not _destination_label:
		_destination_label = get_node_or_null("Root/Panel/Margin/Rows/DestinationLabel") as Label
	if not _path_label:
		_path_label = get_node_or_null("Root/Panel/Margin/Rows/PathLabel") as Label
	if not _eta_label:
		_eta_label = get_node_or_null("Root/Panel/Margin/Rows/EtaLabel") as Label
	if not _failure_label:
		_failure_label = get_node_or_null("Root/Panel/Margin/Rows/FailureLabel") as Label
	if not _stop_button:
		_stop_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/StopButton") as Button
	if not _clear_button:
		_clear_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/ClearButton") as Button
	return (
		_root_control != null
		and _title_label != null
		and _subtitle_label != null
		and _state_label != null
		and _destination_label != null
		and _path_label != null
		and _eta_label != null
		and _failure_label != null
		and _stop_button != null
		and _clear_button != null
	)


func _format_meters(value: float) -> String:
	if value >= 1000.0:
		return "%.1f km" % (value / 1000.0)
	return "%.0f m" % value


func _format_seconds(value: float) -> String:
	if value >= 60.0:
		return "%.1f min" % (value / 60.0)
	return "%.0f sec" % value
