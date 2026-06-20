@abstract
class_name AbstractField
extends Node3D

var plot_data: FieldPlotData
var crop_type: CropTypeData


@abstract
func configure_field(new_plot_data: FieldPlotData, new_crop_type: CropTypeData) -> void


@abstract
func apply_crop_state() -> void


@abstract
func rebuild_visuals() -> void


@abstract
func get_ground_state_id() -> StringName
