extends Control

const DRAFT_SCENE_PATH := "res://modules/draft/draft.tscn"
const SLOW_LOAD_THRESHOLD_MS := 1000.0
const TARGET_FPS := 300

@onready var _status_label: Label = $StatusLabel

var _load_started_usec := 0


func _ready() -> void:
	Engine.max_fps = TARGET_FPS
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_mark_startup_phase("boot_ready")
	_load_started_usec = Time.get_ticks_usec()
	call_deferred("_load_draft_scene")


func _load_draft_scene() -> void:
	await get_tree().process_frame
	_mark_startup_phase("draft_resource_load_start")
	var resource_load_started_usec := Time.get_ticks_usec()
	var scene := ResourceLoader.load(DRAFT_SCENE_PATH) as PackedScene
	if not scene:
		_show_load_error("Loaded resource is not a scene: %s." % DRAFT_SCENE_PATH)
		return

	var load_ms := float(Time.get_ticks_usec() - resource_load_started_usec) / 1000.0
	if load_ms >= SLOW_LOAD_THRESHOLD_MS:
		_mark_startup_phase("draft_resource_slow", {
			"load_ms": "%.1f" % load_ms,
		})
	_mark_startup_phase("draft_resource_ready", {
		"load_ms": "%.1f" % (float(Time.get_ticks_usec() - _load_started_usec) / 1000.0),
	})

	var draft := scene.instantiate()
	if not draft:
		_show_load_error("Could not instantiate %s." % DRAFT_SCENE_PATH)
		return

	add_child(draft)
	_status_label.visible = false
	_mark_startup_phase("draft_instantiated")

	await get_tree().process_frame
	_mark_first_controllable_frame()


func _show_load_error(message: String) -> void:
	push_error(message)
	_status_label.text = message


func _mark_startup_phase(label: String, context: Dictionary = {}) -> void:
	var probe := get_node_or_null("/root/StartupPerformanceProbe")
	if probe and probe.has_method("mark_phase"):
		probe.call("mark_phase", label, context)


func _mark_first_controllable_frame() -> void:
	var probe := get_node_or_null("/root/StartupPerformanceProbe")
	if probe and probe.has_method("mark_first_controllable_frame"):
		probe.call("mark_first_controllable_frame", {})
