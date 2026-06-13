extends Node

const SETTINGS_PATH := "user://settings.cfg"

signal mouse_sensitivity_changed(value: float)

var mouse_sensitivity: float = 1.0

func _ready() -> void:
	load_settings()

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.1, 5.0)
	mouse_sensitivity_changed.emit(mouse_sensitivity)
	save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	mouse_sensitivity = float(config.get_value("controls", "mouse_sensitivity", 1.0))
