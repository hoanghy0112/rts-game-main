@tool
extends Node
class_name SeasonWeatherSystem

signal environment_changed(snapshot: Dictionary)

@export var season_id: StringName = &"dry":
	set(value):
		season_id = value
		_emit_environment_changed_if_ready()

@export_range(1, 12, 1) var calendar_month: int = 1:
	set(value):
		calendar_month = clampi(value, 1, 12)
		_apply_calendar_season_default()
		_emit_environment_changed_if_ready()

@export var update_season_from_calendar: bool = true:
	set(value):
		update_season_from_calendar = value
		_apply_calendar_season_default()
		_emit_environment_changed_if_ready()

@export var month_to_season: Dictionary = {
	1: &"lua_chiem",
	2: &"lua_chiem",
	3: &"lua_chiem",
	4: &"lua_chiem",
	5: &"lua_chiem",
	6: &"lua_mua",
	7: &"lua_mua",
	8: &"lua_mua",
	9: &"lua_mua",
	10: &"lua_mua",
	11: &"lua_chiem",
	12: &"lua_chiem",
}

@export var weather_id: StringName = &"clear":
	set(value):
		weather_id = value
		_apply_weather_defaults(value)
		_emit_environment_changed_if_ready()

@export_range(0.0, 1.0, 0.01) var rain_intensity: float = 0.0:
	set(value):
		rain_intensity = clampf(value, 0.0, 1.0)
		_emit_environment_changed_if_ready()

@export_range(0.0, 1.0, 0.01) var mud_level: float = 0.0:
	set(value):
		mud_level = clampf(value, 0.0, 1.0)
		_emit_environment_changed_if_ready()

@export_range(0.0, 1.0, 0.01) var flood_level: float = 0.0:
	set(value):
		flood_level = clampf(value, 0.0, 1.0)
		_emit_environment_changed_if_ready()

@export var temperature: float = 28.0:
	set(value):
		temperature = value
		_emit_environment_changed_if_ready()

@export var wind_direction: Vector2 = Vector2.RIGHT:
	set(value):
		wind_direction = value.normalized() if value.length_squared() > 0.0001 else Vector2.RIGHT
		_emit_environment_changed_if_ready()

@export_range(0.0, 1.0, 0.01) var wind_intensity: float = 0.0:
	set(value):
		wind_intensity = clampf(value, 0.0, 1.0)
		_emit_environment_changed_if_ready()

var _ready_to_emit := false
var _applying_defaults := false


func _ready() -> void:
	_apply_calendar_season_default()
	_ready_to_emit = true


func set_season(new_season_id: StringName) -> void:
	if season_id == new_season_id:
		return
	season_id = new_season_id


func set_calendar_month(new_month: int) -> void:
	calendar_month = new_month


func get_calendar_month() -> int:
	return calendar_month


func set_weather(new_weather_id: StringName) -> void:
	if weather_id == new_weather_id:
		return
	weather_id = new_weather_id


func get_current_snapshot() -> Dictionary:
	return {
		"season_id": season_id,
		"calendar_month": calendar_month,
		"weather_id": weather_id,
		"rain_intensity": rain_intensity,
		"mud_level": mud_level,
		"flood_level": flood_level,
		"temperature": temperature,
		"wind_direction": wind_direction,
		"wind_intensity": wind_intensity,
	}


func get_snapshot_at(_world_position: Vector3) -> Dictionary:
	return get_current_snapshot()


func _apply_calendar_season_default() -> void:
	if _applying_defaults or not update_season_from_calendar:
		return
	if not month_to_season.has(calendar_month):
		return

	var mapped_season := StringName(month_to_season[calendar_month])
	if mapped_season == season_id:
		return

	_applying_defaults = true
	season_id = mapped_season
	_applying_defaults = false


func _apply_weather_defaults(new_weather_id: StringName) -> void:
	if _applying_defaults:
		return

	_applying_defaults = true
	match new_weather_id:
		&"rain":
			rain_intensity = 0.45
			mud_level = 0.35
			flood_level = 0.0
			wind_intensity = maxf(wind_intensity, 0.2)
		&"storm", &"monsoon":
			rain_intensity = 0.85
			mud_level = 0.65
			flood_level = 0.25
			wind_intensity = maxf(wind_intensity, 0.65)
		&"flood", &"flooded":
			rain_intensity = 0.7
			mud_level = 0.75
			flood_level = 0.7
			wind_intensity = maxf(wind_intensity, 0.35)
		_:
			rain_intensity = 0.0
			mud_level = 0.0
			flood_level = 0.0
			wind_intensity = minf(wind_intensity, 0.2)
	_applying_defaults = false


func _emit_environment_changed_if_ready() -> void:
	if _applying_defaults or not _ready_to_emit:
		return
	environment_changed.emit(get_current_snapshot())
