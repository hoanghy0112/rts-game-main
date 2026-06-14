@tool
extends AbstractField
class_name RiceField

@export var dry_material: Material
@export var wet_material: Material
@export var flooded_material: Material
@export var muddy_material: Material
@export var crop_material: Material
@export var seedling_material: Material
@export var tillering_material: Material
@export var mature_material: Material
@export var stubble_material: Material
@export var water_material: Material
@export_range(0.15, 2.0, 0.01, "or_greater") var plant_spacing: float = 0.34
@export_range(0.15, 2.0, 0.01, "or_greater") var row_spacing: float = 0.30
@export_range(32, 4096, 1, "or_greater") var max_plant_instances: int = 3600
@export var hide_crops_when_zoomed_out: bool = true
@export_range(1.0, 512.0, 1.0, "or_greater") var crop_hide_camera_distance: float = 60.0
@export_range(0.05, 5.0, 0.05, "or_greater") var crop_visibility_check_interval: float = 0.25

var _current_snapshot: Dictionary = {}
var _current_ground_state_id: StringName = &"dry"
var _current_stage_id: StringName = &"empty"
var _visual_root: Node3D
var _ground_mesh: MeshInstance3D
var _water_mesh: MeshInstance3D
var _crop_multimesh: MultiMeshInstance3D
var _crop_scatter_key := ""
var _crop_visibility_elapsed := 0.0
var _crop_hidden_by_zoom := false


func _ready() -> void:
	_resolve_nodes()
	rebuild_visuals()
	set_process(not Engine.is_editor_hint())


func _exit_tree() -> void:
	if season_weather and season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.disconnect(_on_environment_changed)


func _process(delta: float) -> void:
	_crop_visibility_elapsed += delta
	if _crop_visibility_elapsed < crop_visibility_check_interval:
		return

	_crop_visibility_elapsed = 0.0
	_update_crop_visibility()


func configure_field(new_plot_data: FieldPlotData, new_crop_type: CropTypeData, new_season_weather: SeasonWeatherSystem) -> void:
	plot_data = new_plot_data
	crop_type = new_crop_type

	if season_weather and season_weather != new_season_weather and season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.disconnect(_on_environment_changed)

	season_weather = new_season_weather
	if season_weather and not season_weather.environment_changed.is_connected(_on_environment_changed):
		season_weather.environment_changed.connect(_on_environment_changed)

	if season_weather:
		apply_environment(season_weather.get_snapshot_at(global_position))
	else:
		apply_environment({})

	rebuild_visuals()


func apply_environment(snapshot: Dictionary) -> void:
	_current_snapshot = snapshot.duplicate()
	_current_ground_state_id = get_ground_state_id(_current_snapshot)

	if plot_data:
		plot_data.water_level = float(_current_snapshot.get("rain_intensity", 0.0))
		plot_data.flood_level = float(_current_snapshot.get("flood_level", 0.0))
		plot_data.mud_level = float(_current_snapshot.get("mud_level", 0.0))
		plot_data.ground_state_id = _current_ground_state_id
		plot_data.ground_state_data = crop_type.get_ground_state_data(_current_ground_state_id) if crop_type else null
		plot_data.stage = crop_type.get_crop_stage_id(_current_snapshot) if crop_type else &"empty"
		_current_stage_id = plot_data.stage

	_apply_ground_material()
	_apply_water_visual()
	_apply_crop_material()


func rebuild_visuals() -> void:
	_resolve_nodes()
	if not plot_data or not _visual_root:
		return

	_visual_root.scale = Vector3.ONE
	if _ground_mesh:
		_ground_mesh.scale = Vector3(maxf(plot_data.length, 0.1), 1.0, maxf(plot_data.width, 0.1))
	if _water_mesh:
		_water_mesh.scale = Vector3(maxf(plot_data.length, 0.1), 1.0, maxf(plot_data.width, 0.1))

	_rebuild_crop_multimesh()
	_apply_ground_material()
	_apply_crop_material()
	_apply_water_visual()


func get_ground_state_id(snapshot: Dictionary) -> StringName:
	if crop_type:
		return crop_type.get_ground_state_id(snapshot)

	var flood := float(snapshot.get("flood_level", 0.0))
	if flood >= 0.35:
		return &"flooded"

	var mud := float(snapshot.get("mud_level", 0.0))
	if mud >= 0.45:
		return &"muddy"

	var rain := float(snapshot.get("rain_intensity", 0.0))
	if rain >= 0.2:
		return &"wet"

	return &"dry"


func get_current_ground_state_id() -> StringName:
	return _current_ground_state_id


func _on_environment_changed(snapshot: Dictionary) -> void:
	apply_environment(snapshot)
	rebuild_visuals()


func _resolve_nodes() -> void:
	if not _visual_root:
		_visual_root = get_node_or_null("VisualRoot") as Node3D
	if not _ground_mesh:
		_ground_mesh = get_node_or_null("VisualRoot/Ground") as MeshInstance3D
	if not _water_mesh:
		_water_mesh = get_node_or_null("VisualRoot/Water") as MeshInstance3D
	if not _crop_multimesh:
		_crop_multimesh = get_node_or_null("VisualRoot/CropMultiMesh") as MultiMeshInstance3D


func _apply_ground_material() -> void:
	_resolve_nodes()
	if not _ground_mesh:
		return

	var ground_material := _get_material_for_ground_state(_current_ground_state_id)
	if ground_material:
		_ground_mesh.set_surface_override_material(0, ground_material)


func _apply_crop_material() -> void:
	_resolve_nodes()
	if not _crop_multimesh:
		return

	var material := _get_material_for_stage(_current_stage_id)
	if material:
		_crop_multimesh.material_override = material
	_update_crop_visibility()


func _apply_water_visual() -> void:
	_resolve_nodes()
	if not _water_mesh:
		return

	_water_mesh.visible = _current_ground_state_id == &"flooded" or float(_current_snapshot.get("flood_level", 0.0)) > 0.08
	if water_material:
		_water_mesh.set_surface_override_material(0, water_material)


func _rebuild_crop_multimesh() -> void:
	_resolve_nodes()
	if not plot_data or not _crop_multimesh:
		return

	var stage := _current_stage_id
	var scatter_key := "%s:%s:%.2f:%.2f" % [str(plot_data.id), str(stage), plot_data.length, plot_data.width]
	if scatter_key == _crop_scatter_key:
		return
	_crop_scatter_key = scatter_key

	if stage == &"empty":
		_crop_multimesh.multimesh = null
		_update_crop_visibility()
		return

	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh

	var length := maxf(plot_data.length, 0.1)
	var width := maxf(plot_data.width, 0.1)
	var safe_plant_spacing := _get_stage_plant_spacing(stage)
	var safe_row_spacing := _get_stage_row_spacing(stage)
	var usable_length := maxf(length - 0.5, 0.1)
	var usable_width := maxf(width - 0.4, 0.1)
	var column_count := maxi(1, floori(usable_length / safe_plant_spacing))
	var row_count := maxi(1, floori(usable_width / safe_row_spacing))
	var instance_count := mini(column_count * row_count, max_plant_instances)
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(str(plot_data.id).hash())

	var index := 0
	for row_index: int in range(row_count):
		if index >= instance_count:
			break
		var z := -usable_width * 0.5 + (float(row_index) + 0.5) * usable_width / float(row_count)
		for column_index: int in range(column_count):
			if index >= instance_count:
				break
			var x := -usable_length * 0.5 + (float(column_index) + 0.5) * usable_length / float(column_count)
			var jitter := Vector2(
				rng.randf_range(-safe_plant_spacing * 0.18, safe_plant_spacing * 0.18),
				rng.randf_range(-safe_row_spacing * 0.18, safe_row_spacing * 0.18)
			)
			var plant_height := _get_stage_height(stage) * rng.randf_range(0.86, 1.14)
			var plant_width := _get_stage_width(stage) * rng.randf_range(0.82, 1.18)
			var basis := Basis().rotated(Vector3.UP, rng.randf_range(-0.12, 0.12)).scaled(Vector3(plant_width, plant_height, plant_width))
			var transform := Transform3D(basis, Vector3(x + jitter.x, 0.06 + plant_height * 0.5, z + jitter.y))
			multimesh.set_instance_transform(index, transform)
			index += 1

	_crop_multimesh.multimesh = multimesh
	_update_crop_visibility()


func _update_crop_visibility() -> void:
	_resolve_nodes()
	if not _crop_multimesh:
		return

	var should_hide := false
	if hide_crops_when_zoomed_out and not Engine.is_editor_hint():
		var viewport := get_viewport()
		var camera := viewport.get_camera_3d() if viewport else null
		if camera:
			should_hide = camera.global_position.distance_to(global_position) >= crop_hide_camera_distance

	_crop_hidden_by_zoom = should_hide
	_crop_multimesh.visible = _crop_multimesh.multimesh != null and not _crop_hidden_by_zoom


func _get_material_for_ground_state(ground_state_id: StringName) -> Material:
	if crop_type:
		var state_data := crop_type.get_ground_state_data(ground_state_id)
		if state_data and state_data.material:
			return state_data.material

	match ground_state_id:
		&"wet":
			return wet_material if wet_material else dry_material
		&"flooded":
			return flooded_material if flooded_material else wet_material
		&"muddy":
			return muddy_material if muddy_material else wet_material
		_:
			return dry_material


func _get_material_for_stage(stage_id: StringName) -> Material:
	match stage_id:
		&"seedling":
			return seedling_material if seedling_material else crop_material
		&"tillering", &"flooded_green":
			return tillering_material if tillering_material else crop_material
		&"mature_gold":
			return mature_material if mature_material else crop_material
		&"harvested_stubble":
			return stubble_material if stubble_material else mature_material
		_:
			return crop_material


func _get_stage_height(stage_id: StringName) -> float:
	match stage_id:
		&"seedling":
			return 0.32
		&"tillering", &"flooded_green":
			return 0.72
		&"mature_gold":
			return 0.95
		&"harvested_stubble":
			return 0.24
		_:
			return 0.55


func _get_stage_width(stage_id: StringName) -> float:
	match stage_id:
		&"seedling":
			return 0.035
		&"harvested_stubble":
			return 0.055
		_:
			return 0.075


func _get_stage_plant_spacing(stage_id: StringName) -> float:
	match stage_id:
		&"harvested_stubble":
			return maxf(plant_spacing * 0.85, 0.15)
		_:
			return maxf(plant_spacing, 0.15)


func _get_stage_row_spacing(stage_id: StringName) -> float:
	match stage_id:
		&"harvested_stubble":
			return maxf(row_spacing * 0.9, 0.15)
		_:
			return maxf(row_spacing, 0.15)
