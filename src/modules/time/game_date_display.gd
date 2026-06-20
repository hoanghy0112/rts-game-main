@tool
extends CanvasLayer
class_name GameDateDisplay

@export var time_system_path: NodePath = NodePath("../GameTimeSystem")

@onready var _root_control: Control = %Root
@onready var _date_label: Label = %DateLabel
@onready var _time_label: Label = %TimeLabel

var _time_system: Node


func _ready() -> void:
	_cache_control_nodes()
	if Engine.is_editor_hint():
		_apply_time_snapshot(_make_preview_snapshot())
		return

	var time_node := get_node_or_null(time_system_path)
	if time_node:
		bind_to_time_system(time_node)
	else:
		_apply_time_snapshot(_make_preview_snapshot())


func _exit_tree() -> void:
	_unbind_time_system()


func bind_to_time_system(time_system: Node) -> void:
	if _time_system == time_system:
		return

	_unbind_time_system()
	_time_system = time_system
	if not _time_system:
		return

	var callable := Callable(self, "_on_time_changed")
	if _time_system.has_signal("time_changed") and not _time_system.is_connected("time_changed", callable):
		_time_system.connect("time_changed", callable)

	if _time_system.has_method("get_current_snapshot"):
		var snapshot: Variant = _time_system.call("get_current_snapshot")
		if snapshot is Dictionary:
			_apply_time_snapshot(snapshot as Dictionary)


func _unbind_time_system() -> void:
	if not _time_system:
		return

	var callable := Callable(self, "_on_time_changed")
	if _time_system.has_signal("time_changed") and _time_system.is_connected("time_changed", callable):
		_time_system.disconnect("time_changed", callable)
	_time_system = null


func _on_time_changed(snapshot: Dictionary) -> void:
	_apply_time_snapshot(snapshot)


func _apply_time_snapshot(snapshot: Dictionary) -> void:
	if not _cache_control_nodes():
		return

	_date_label.text = String(snapshot.get("date_label", "Year 1, Month 01, Day 01"))
	_time_label.text = String(snapshot.get("time_label", "06:00"))


func _cache_control_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _date_label:
		_date_label = get_node_or_null("Root/Panel/Margin/Rows/DateLabel") as Label
	if not _time_label:
		_time_label = get_node_or_null("Root/Panel/Margin/Rows/TimeLabel") as Label
	return _root_control != null and _date_label != null and _time_label != null


func _make_preview_snapshot() -> Dictionary:
	return {
		"date_label": "Year 1, Month 01, Day 01",
		"time_label": "06:00",
	}
