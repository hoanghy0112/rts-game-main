@tool
extends Resource
class_name RiverStyleData

enum SHADER_TYPES { WATER, LAVA, CUSTOM }

@export var style_id: StringName = &"water_river"
@export var display_name: String = "Water River"

@export_group("Shader")
@export_enum("Water", "Lava", "Custom") var shader_type: int = SHADER_TYPES.WATER
@export var custom_shader: Shader

@export_group("Material")
@export_range(-16.0, 16.0, 0.01) var normal_scale: float = 1.0
@export var normal_bump_texture: Texture2D
@export var uv_scale: Vector3 = Vector3.ONE
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.2
@export_range(0.0, 1.0, 0.01) var edge_fade: float = 0.25

@export_group("Water Albedo")
@export var albedo_color: Projection
@export_range(0.0, 200.0, 0.01) var albedo_depth: float = 10.0
@export var albedo_depth_curve: float = 0.25

@export_group("Water Transparency")
@export_range(0.0, 200.0, 0.01) var transparency_clarity: float = 10.0
@export var transparency_depth_curve: float = 0.25
@export_range(-1.0, 1.0, 0.01) var transparency_refraction: float = 0.05

@export_group("Flow")
@export_range(0.0, 10.0, 0.01) var flow_speed: float = 1.0
@export_range(0.0, 8.0, 0.01) var flow_base: float = 0.0
@export_range(0.0, 8.0, 0.01) var flow_steepness: float = 2.0
@export_range(0.0, 8.0, 0.01) var flow_distance: float = 1.0
@export_range(0.0, 8.0, 0.01) var flow_pressure: float = 1.0
@export_range(0.0, 8.0, 0.01) var flow_max: float = 4.0

@export_group("Foam")
@export var foam_color: Color = Color(0.9, 0.9, 0.9, 1.0)
@export_range(0.0, 4.0, 0.01) var foam_amount: float = 2.0
@export_range(0.0, 8.0, 0.01) var foam_steepness: float = 2.0
@export_range(0.0, 1.0, 0.01) var foam_smoothness: float = 0.3

@export_group("Lava Emission")
@export var emission_color: Projection
@export_range(0.0, 20.0, 0.01) var emission_energy: float = 4.0
@export_range(0.0, 200.0, 0.01) var emission_depth: float = 3.0
@export var emission_depth_curve: float = 0.25
@export var emission_texture: Texture2D

@export_group("Custom Shader")
@export var custom_shader_parameters: Dictionary = {}

@export_group("Shape Defaults")
@export var apply_shape_defaults: bool = true
@export_range(1, 8, 1) var shape_step_length_divs: int = 1
@export_range(1, 8, 1) var shape_step_width_divs: int = 1
@export_range(0.1, 5.0, 0.01) var shape_smoothness: float = 0.5
@export var apply_default_width_to_new_rivers: bool = false
@export_range(0.01, 100.0, 0.01, "or_greater") var default_width: float = 1.0

@export_group("LOD Defaults")
@export var apply_lod_defaults: bool = true
@export_range(5.0, 200.0, 0.01) var lod_lod0_distance: float = 50.0

@export_group("Baking Defaults")
@export var apply_baking_defaults: bool = true
@export_enum("64", "128", "256", "512", "1024") var baking_resolution: int = 2
@export_range(0.0, 100.0, 0.01) var baking_raycast_distance: float = 10.0
@export_flags_3d_physics var baking_raycast_layers: int = 1
@export_range(0.0, 1.0, 0.01) var baking_dilate: float = 0.6
@export_range(0.0, 1.0, 0.01) var baking_flowmap_blur: float = 0.04
@export_range(0.0, 1.0, 0.01) var baking_foam_cutoff: float = 0.9
@export_range(0.0, 1.0, 0.01) var baking_foam_offset: float = 0.1
@export_range(0.0, 1.0, 0.01) var baking_foam_blur: float = 0.02


func _init() -> void:
	albedo_color = create_gradient_projection(Color(0.0, 0.8, 1.0), Color(0.15, 0.2, 0.5))
	emission_color = create_gradient_projection(Color(1.0, 1.0, 0.0), Color(1.0, 0.5, 0.0))


static func create_gradient_projection(near_color: Color, far_color: Color) -> Projection:
	var gradient := Projection()
	gradient[0] = Vector4(near_color.r, near_color.g, near_color.b, near_color.a)
	gradient[1] = Vector4(far_color.r, far_color.g, far_color.b, far_color.a)
	return gradient


func get_shader_parameters() -> Dictionary:
	var parameters: Dictionary = {
		&"normal_scale": normal_scale,
		&"uv_scale": uv_scale,
		&"roughness": roughness,
		&"edge_fade": edge_fade,
		&"flow_speed": flow_speed,
		&"flow_base": flow_base,
		&"flow_steepness": flow_steepness,
		&"flow_distance": flow_distance,
		&"flow_pressure": flow_pressure,
		&"flow_max": flow_max,
	}
	if normal_bump_texture != null:
		parameters[&"normal_bump_texture"] = normal_bump_texture

	if shader_type == SHADER_TYPES.WATER or shader_type == SHADER_TYPES.CUSTOM:
		parameters[&"albedo_color"] = albedo_color
		parameters[&"albedo_depth"] = albedo_depth
		parameters[&"albedo_depth_curve"] = albedo_depth_curve
		parameters[&"transparency_clarity"] = transparency_clarity
		parameters[&"transparency_depth_curve"] = transparency_depth_curve
		parameters[&"transparency_refraction"] = transparency_refraction
		parameters[&"foam_color"] = foam_color
		parameters[&"foam_amount"] = foam_amount
		parameters[&"foam_steepness"] = foam_steepness
		parameters[&"foam_smoothness"] = foam_smoothness

	if shader_type == SHADER_TYPES.LAVA or shader_type == SHADER_TYPES.CUSTOM:
		parameters[&"emission_color"] = emission_color
		parameters[&"emission_energy"] = emission_energy
		parameters[&"emission_depth"] = emission_depth
		parameters[&"emission_depth_curve"] = emission_depth_curve
		if emission_texture != null:
			parameters[&"emission_texture"] = emission_texture

	for parameter_name in custom_shader_parameters:
		parameters[StringName(str(parameter_name))] = custom_shader_parameters[parameter_name]

	return parameters
