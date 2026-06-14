@abstract
class_name AbstractField
extends Node3D

var plot_data: FieldPlotData
var crop_type: CropTypeData
var season_weather: SeasonWeatherSystem


@abstract
func configure_field(new_plot_data: FieldPlotData, new_crop_type: CropTypeData, new_season_weather: SeasonWeatherSystem) -> void


@abstract
func apply_environment(snapshot: Dictionary) -> void


@abstract
func rebuild_visuals() -> void


@abstract
func get_ground_state_id(snapshot: Dictionary) -> StringName
