@tool
extends Resource
class_name CropTypeData

@export var crop_id: StringName = &"field"
@export var display_name: String = "Field"
@export_multiline var description: String = ""
@export var field_scene: PackedScene
@export var season_growth_rules: Dictionary = {}
@export var season_to_ground_state: Dictionary = {}
@export var season_calendar: Array = []

@export_group("Ground States")
@export var dry_ground_state: FieldGroundStateData
@export var wet_ground_state: FieldGroundStateData
@export var flooded_ground_state: FieldGroundStateData
@export var muddy_ground_state: FieldGroundStateData


func get_ground_state_id(snapshot: Dictionary) -> StringName:
	var flood_level := float(snapshot.get("flood_level", 0.0))
	if flood_level >= 0.35:
		return &"flooded"

	var mud_level := float(snapshot.get("mud_level", 0.0))
	if mud_level >= 0.45:
		return &"muddy"

	var rain_intensity := float(snapshot.get("rain_intensity", 0.0))
	if rain_intensity >= 0.2:
		return &"wet"

	var weather_id := StringName(snapshot.get("weather_id", &"clear"))
	match weather_id:
		&"flood", &"flooded":
			return &"flooded"
		&"rain", &"storm", &"monsoon":
			return &"wet"

	var calendar_month := int(snapshot.get("calendar_month", 0))
	var month_ground_state := get_ground_state_id_for_month(calendar_month)
	if month_ground_state != &"":
		return month_ground_state

	var season_id := StringName(snapshot.get("season_id", &"dry"))
	if season_to_ground_state.has(season_id):
		return StringName(season_to_ground_state[season_id])

	return &"dry"


func get_crop_stage_id(snapshot: Dictionary) -> StringName:
	var calendar_month := int(snapshot.get("calendar_month", 0))
	var month_stage := get_crop_stage_id_for_month(calendar_month)
	if month_stage != &"":
		return month_stage

	var season_id := StringName(snapshot.get("season_id", &"dry"))
	if season_growth_rules.has(season_id):
		return StringName(season_growth_rules[season_id])

	return &"empty"


func get_season_id_for_month(month: int) -> StringName:
	var window := get_calendar_window_for_month(month)
	if window.is_empty():
		return &""
	return StringName(window.get("season_id", &""))


func get_crop_stage_id_for_month(month: int) -> StringName:
	var window := get_calendar_window_for_month(month)
	if window.is_empty():
		return &""

	var stage_by_month: Variant = window.get("stage_by_month", {})
	var month_stage: Variant = _get_month_dictionary_value(stage_by_month, month)
	if month_stage != null:
		return StringName(month_stage)

	return StringName(window.get("default_stage", &"empty"))


func get_ground_state_id_for_month(month: int) -> StringName:
	var window := get_calendar_window_for_month(month)
	if window.is_empty():
		return &""

	var ground_state_by_month: Variant = window.get("ground_state_by_month", {})
	var month_ground_state: Variant = _get_month_dictionary_value(ground_state_by_month, month)
	if month_ground_state != null:
		return StringName(month_ground_state)

	return StringName(window.get("default_ground_state", &""))


func get_calendar_window_for_month(month: int) -> Dictionary:
	if month < 1 or month > 12:
		return {}

	for window_variant: Variant in season_calendar:
		if not (window_variant is Dictionary):
			continue

		var window := window_variant as Dictionary
		var start_month := int(window.get("start_month", 1))
		var end_month := int(window.get("end_month", 12))
		if _is_month_in_range(month, start_month, end_month):
			return window

	return {}


func get_ground_state_data(ground_state_id: StringName) -> FieldGroundStateData:
	match ground_state_id:
		&"wet":
			return wet_ground_state if wet_ground_state else dry_ground_state
		&"flooded":
			return flooded_ground_state if flooded_ground_state else wet_ground_state
		&"muddy":
			return muddy_ground_state if muddy_ground_state else wet_ground_state
		_:
			return dry_ground_state


func _get_month_dictionary_value(dictionary_variant: Variant, month: int) -> Variant:
	if not (dictionary_variant is Dictionary):
		return null

	var dictionary := dictionary_variant as Dictionary
	if dictionary.has(month):
		return dictionary[month]
	var month_key := str(month)
	if dictionary.has(month_key):
		return dictionary[month_key]
	var month_name_key := StringName(month_key)
	if dictionary.has(month_name_key):
		return dictionary[month_name_key]
	return null


func _is_month_in_range(month: int, start_month: int, end_month: int) -> bool:
	var safe_start := clampi(start_month, 1, 12)
	var safe_end := clampi(end_month, 1, 12)
	if safe_start <= safe_end:
		return month >= safe_start and month <= safe_end
	return month >= safe_start or month <= safe_end
