extends Node

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY: float = 1.0
const MIN_SENSITIVITY: float = 0.1
const MAX_SENSITIVITY: float = 5.0

signal mouse_sensitivity_changed(value: float)
signal move_sensitivity_changed(value: float)

var mouse_sensitivity: float = DEFAULT_SENSITIVITY
var move_sensitivity: float = DEFAULT_SENSITIVITY

func _ready() -> void:
	load_settings()

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = _clamp_sensitivity(value)
	mouse_sensitivity_changed.emit(mouse_sensitivity)
	save_settings()

func set_move_sensitivity(value: float) -> void:
	move_sensitivity = _clamp_sensitivity(value)
	move_sensitivity_changed.emit(move_sensitivity)
	save_settings()

func get_mouse_sensitivity() -> float:
	return mouse_sensitivity

func get_move_sensitivity() -> float:
	return move_sensitivity

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "move_sensitivity", move_sensitivity)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	mouse_sensitivity = _clamp_sensitivity(
		float(config.get_value("controls", "mouse_sensitivity", DEFAULT_SENSITIVITY))
	)
	move_sensitivity = _clamp_sensitivity(
		float(config.get_value("controls", "move_sensitivity", DEFAULT_SENSITIVITY))
	)

func _clamp_sensitivity(value: float) -> float:
	return clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
