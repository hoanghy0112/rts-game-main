extends Node3D
class_name RTSCameraRig

const ACTION_CAMERA_UP: StringName = &"camera_up"
const ACTION_CAMERA_DOWN: StringName = &"camera_down"
const ACTION_CAMERA_LEFT: StringName = &"camera_left"
const ACTION_CAMERA_RIGHT: StringName = &"camera_right"
const MIN_PITCH: float = deg_to_rad(25.0)
const MAX_PITCH: float = deg_to_rad(75.0)
const DEFAULT_YAW: float = deg_to_rad(45.0)
const DEFAULT_PITCH: float = deg_to_rad(55.0)
const DEFAULT_DISTANCE: float = 32.0
const DEFAULT_SETTINGS_SENSITIVITY: float = 1.0
const CAMERA_NODE_NAME: StringName = &"Camera3D"
const DEFAULT_CAMERA_NEAR: float = 0.25
const DEFAULT_CAMERA_FAR: float = 16384.0
const METHOD_GET_MOUSE_SENSITIVITY: StringName = &"get_mouse_sensitivity"
const METHOD_GET_MOVE_SENSITIVITY: StringName = &"get_move_sensitivity"

@export_group("Movement")
@export var move_speed: float = 40.0
@export var move_lerp_speed: float = 12.0

@export_group("Zoom")
@export var zoom_step: float = 5.0
@export var min_distance: float = 8.0
@export var max_distance: float = 80.0
@export var zoom_lerp_speed: float = 14.0

@export_group("Rotation")
@export var rotate_sensitivity: float = 0.005
@export var pan_sensitivity: float = 0.01
@export var rotation_lerp_speed: float = 14.0

@export_group("Nodes")
@export var camera_path: NodePath = ^"Camera3D"

var _desired_target_position: Vector3 = Vector3.ZERO
var _current_target_position: Vector3 = Vector3.ZERO
var _desired_yaw: float = DEFAULT_YAW
var _current_yaw: float = DEFAULT_YAW
var _desired_pitch: float = DEFAULT_PITCH
var _current_pitch: float = DEFAULT_PITCH
var _desired_distance: float = DEFAULT_DISTANCE
var _current_distance: float = DEFAULT_DISTANCE
var _is_rotating: bool = false
var _is_middle_orbiting: bool = false
var _camera: Camera3D = null
var _settings_manager: Node = null


func _ready() -> void:
	_camera = _resolve_camera()
	_settings_manager = get_node_or_null("/root/SettingsManager")
	_current_target_position = global_position
	_desired_target_position = _current_target_position
	_desired_pitch = clampf(_desired_pitch, MIN_PITCH, MAX_PITCH)
	_current_pitch = _desired_pitch
	_desired_distance = _clamp_distance(_desired_distance)
	_current_distance = _desired_distance
	_apply_camera_transform()


func _process(delta: float) -> void:
	_handle_keyboard_movement(delta)
	_update_smoothed_state(delta)
	_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_keyboard_movement(delta: float) -> void:
	var input_vector := Input.get_vector(
		ACTION_CAMERA_LEFT,
		ACTION_CAMERA_RIGHT,
		ACTION_CAMERA_DOWN,
		ACTION_CAMERA_UP
	)

	if input_vector.is_zero_approx():
		return

	var right := _yaw_right(_desired_yaw)
	var forward := _yaw_forward(_desired_yaw)
	var target_y := _desired_target_position.y
	_desired_target_position += (
		(right * input_vector.x + forward * input_vector.y)
		* move_speed
		* _get_move_sensitivity()
		* delta
	)
	_desired_target_position.y = target_y


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_is_rotating = event.pressed
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_middle_orbiting = event.pressed
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_desired_distance = _clamp_distance(_desired_distance - zoom_step * _get_mouse_sensitivity())
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_desired_distance = _clamp_distance(_desired_distance + zoom_step * _get_mouse_sensitivity())
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_rotating:
		_orbit_target(event.relative, rotate_sensitivity)
		get_viewport().set_input_as_handled()
	elif _is_middle_orbiting:
		_orbit_target(event.relative, pan_sensitivity)
		get_viewport().set_input_as_handled()


func _update_smoothed_state(delta: float) -> void:
	_current_target_position = _current_target_position.lerp(
		_desired_target_position,
		_exponential_weight(move_lerp_speed, delta)
	)
	_current_yaw = lerp_angle(
		_current_yaw,
		_desired_yaw,
		_exponential_weight(rotation_lerp_speed, delta)
	)
	_current_pitch = lerpf(
		_current_pitch,
		_desired_pitch,
		_exponential_weight(rotation_lerp_speed, delta)
	)
	_current_distance = lerpf(
		_current_distance,
		_desired_distance,
		_exponential_weight(zoom_lerp_speed, delta)
	)


func _apply_camera_transform() -> void:
	if _camera == null:
		_camera = _resolve_camera()
		if _camera == null:
			return

	global_position = _current_target_position

	var horizontal_distance := cos(_current_pitch) * _current_distance
	var offset := Vector3(
		sin(_current_yaw) * horizontal_distance,
		sin(_current_pitch) * _current_distance,
		cos(_current_yaw) * horizontal_distance
	)

	_camera.global_position = _current_target_position + offset
	_camera.look_at(_current_target_position, Vector3.UP)


func _clamp_distance(value: float) -> float:
	var lower_limit := minf(min_distance, max_distance)
	var upper_limit := maxf(min_distance, max_distance)
	return clampf(value, lower_limit, upper_limit)


func _exponential_weight(speed: float, delta: float) -> float:
	return clampf(1.0 - exp(-maxf(speed, 0.0) * delta), 0.0, 1.0)


func _orbit_target(mouse_delta: Vector2, sensitivity: float) -> void:
	var scaled_sensitivity := sensitivity * _get_mouse_sensitivity()
	_desired_yaw = wrapf(_desired_yaw - mouse_delta.x * scaled_sensitivity, -PI, PI)
	_desired_pitch = clampf(
		_desired_pitch + mouse_delta.y * scaled_sensitivity,
		MIN_PITCH,
		MAX_PITCH
	)


func _resolve_camera() -> Camera3D:
	var configured_camera := get_node_or_null(camera_path) as Camera3D
	if configured_camera != null:
		_configure_camera(configured_camera)
		return configured_camera

	var named_camera := find_child(String(CAMERA_NODE_NAME), true, false) as Camera3D
	if named_camera != null:
		camera_path = get_path_to(named_camera)
		_configure_camera(named_camera)
		return named_camera

	var created_camera := Camera3D.new()
	created_camera.name = CAMERA_NODE_NAME
	created_camera.unique_name_in_owner = true
	add_child(created_camera)
	camera_path = NodePath(created_camera.name)
	_configure_camera(created_camera)
	return created_camera


func _configure_camera(camera: Camera3D) -> void:
	camera.current = true
	camera.near = DEFAULT_CAMERA_NEAR
	camera.far = DEFAULT_CAMERA_FAR


func _get_mouse_sensitivity() -> float:
	return _get_settings_sensitivity(METHOD_GET_MOUSE_SENSITIVITY)


func _get_move_sensitivity() -> float:
	return _get_settings_sensitivity(METHOD_GET_MOVE_SENSITIVITY)


func _get_settings_sensitivity(method_name: StringName) -> float:
	if _settings_manager == null or not is_instance_valid(_settings_manager):
		return DEFAULT_SETTINGS_SENSITIVITY
	if not _settings_manager.has_method(method_name):
		return DEFAULT_SETTINGS_SENSITIVITY

	return maxf(float(_settings_manager.call(method_name)), 0.0)


func _yaw_right(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _yaw_forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))
