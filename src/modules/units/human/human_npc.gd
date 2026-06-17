extends CharacterBody3D
class_name HumanNPC

signal health_changed(current: float, maximum: float)
signal state_changed(state: StringName)
signal died(reason: StringName)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_RUN := &"run"
const STATE_FIELD_TASK := &"field_task"
const STATE_TOOL_ACTION := &"tool_action"
const STATE_DEAD := &"dead"

@export_group("Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var max_health: float = 40.0
@export_range(0.1, 20.0, 0.1, "or_greater") var walk_speed: float = 1.45
@export_range(0.1, 30.0, 0.1, "or_greater") var run_speed: float = 3.1
@export_range(0.1, 100.0, 0.1, "or_greater") var acceleration: float = 12.0
@export_range(0.01, 4.0, 0.01, "or_greater") var stop_distance: float = 0.35
@export_range(0.1, 30.0, 0.1, "or_greater") var turn_speed: float = 9.0

@export_group("Combat")
@export_range(0.0, 1000.0, 1.0, "or_greater") var attack_damage: float = 8.0
@export_range(0.05, 20.0, 0.05, "or_greater") var attack_cooldown: float = 1.1

@export_group("Surface")
@export var use_terrain_height := true
@export_range(-4.0, 4.0, 0.01) var terrain_height_offset: float = 0.02

@export_group("Node Paths")
@export_node_path("Node3D") var model_root_path: NodePath = ^"VisualRoot"
@export_node_path("Node3D") var torso_path: NodePath = ^"VisualRoot/Armature/Torso"
@export_node_path("Node3D") var left_arm_path: NodePath = ^"VisualRoot/Armature/LeftArm"
@export_node_path("Node3D") var right_arm_path: NodePath = ^"VisualRoot/Armature/RightArm"
@export_node_path("Node3D") var left_leg_path: NodePath = ^"VisualRoot/Armature/LeftLeg"
@export_node_path("Node3D") var right_leg_path: NodePath = ^"VisualRoot/Armature/RightLeg"
@export_node_path("Node3D") var right_hand_socket_path: NodePath = ^"VisualRoot/Armature/RightArm/RightHandSocket"
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"AnimationPlayer"
@export_node_path("AnimationTree") var animation_tree_path: NodePath = ^"AnimationTree"

var _health: float
var _state: StringName = STATE_IDLE
var _move_target := Vector3.ZERO
var _has_move_target := false
var _move_run := false
var _timed_state_remaining := 0.0
var _timed_state_duration := 0.0
var _state_time := 0.0
var _animation_phase := 0.0
var _surface_height_source: Node3D

@onready var _model_root := get_node_or_null(model_root_path) as Node3D
@onready var _torso := get_node_or_null(torso_path) as Node3D
@onready var _left_arm := get_node_or_null(left_arm_path) as Node3D
@onready var _right_arm := get_node_or_null(right_arm_path) as Node3D
@onready var _left_leg := get_node_or_null(left_leg_path) as Node3D
@onready var _right_leg := get_node_or_null(right_leg_path) as Node3D
@onready var _right_hand_socket := get_node_or_null(right_hand_socket_path) as Node3D
@onready var _animation_player := get_node_or_null(animation_player_path) as AnimationPlayer
@onready var _animation_tree := get_node_or_null(animation_tree_path) as AnimationTree


func _init() -> void:
	_health = maxf(max_health, 1.0)


func _ready() -> void:
	_health = clampf(_health, 0.0, maxf(max_health, 1.0))
	if _health <= 0.0:
		_health = maxf(max_health, 1.0)
	add_to_group(&"human_npcs")
	_set_state(STATE_IDLE)
	_sync_animation_player()


func _physics_process(delta: float) -> void:
	_state_time += delta
	_update_timed_state(delta)
	_update_movement(delta)
	_update_procedural_pose(delta)


func configure_surface_height_source(source: Node3D) -> void:
	_surface_height_source = source
	_snap_to_surface()


func set_move_target(world_position: Vector3, run: bool = false) -> void:
	if not is_alive():
		return

	_move_target = world_position
	_has_move_target = true
	_move_run = run
	_timed_state_remaining = 0.0
	_timed_state_duration = 0.0
	_set_state(STATE_RUN if run else STATE_WALK)


func clear_move_target() -> void:
	_has_move_target = false
	if is_alive() and _state != STATE_FIELD_TASK and _state != STATE_TOOL_ACTION:
		_set_state(STATE_IDLE)


func has_active_move_target() -> bool:
	return _has_move_target


func get_move_target() -> Vector3:
	return _move_target


func play_field_task(duration: float = 2.4) -> void:
	if not is_alive():
		return

	_has_move_target = false
	_timed_state_duration = maxf(duration, 0.05)
	_timed_state_remaining = _timed_state_duration
	_set_state(STATE_FIELD_TASK)


func use_tool(target: Node3D = null, duration: float = -1.0) -> void:
	if not is_alive():
		return

	if target:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			_face_direction(to_target.normalized(), 1.0)

	_has_move_target = false
	_timed_state_duration = maxf(duration if duration > 0.0 else attack_cooldown, 0.05)
	_timed_state_remaining = _timed_state_duration
	_set_state(STATE_TOOL_ACTION)


func attack_target(target: Node3D = null) -> void:
	use_tool(target)


func apply_damage(amount: float, reason: StringName = &"damage") -> void:
	if amount <= 0.0 or not is_alive():
		return

	_health = maxf(_health - amount, 0.0)
	health_changed.emit(_health, max_health)
	if _health <= 0.0:
		kill(reason)


func kill(reason: StringName = &"death") -> void:
	if _state == STATE_DEAD:
		return

	_health = 0.0
	_has_move_target = false
	_timed_state_remaining = 0.0
	_timed_state_duration = 0.0
	velocity = Vector3.ZERO
	_set_state(STATE_DEAD)
	health_changed.emit(_health, max_health)
	died.emit(reason)


func revive_at(world_position: Vector3) -> void:
	global_position = world_position
	_health = maxf(max_health, 1.0)
	_has_move_target = false
	_timed_state_remaining = 0.0
	_timed_state_duration = 0.0
	velocity = Vector3.ZERO
	_set_state(STATE_IDLE)
	health_changed.emit(_health, max_health)
	_snap_to_surface()


func is_alive() -> bool:
	return _state != STATE_DEAD and _health > 0.0


func get_health() -> float:
	return _health


func get_state() -> StringName:
	return _state


func get_right_hand_socket() -> Node3D:
	return _right_hand_socket


func _update_timed_state(delta: float) -> void:
	if _timed_state_remaining <= 0.0:
		return

	_timed_state_remaining = maxf(_timed_state_remaining - delta, 0.0)
	if _timed_state_remaining > 0.0:
		return
	if not is_alive():
		return
	_timed_state_duration = 0.0
	if _state == STATE_FIELD_TASK or _state == STATE_TOOL_ACTION:
		_set_state(STATE_IDLE)


func _update_movement(delta: float) -> void:
	if not is_alive():
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return

	var can_move := _state != STATE_FIELD_TASK and _state != STATE_TOOL_ACTION
	if _has_move_target and can_move:
		var to_target := _move_target - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance <= stop_distance:
			_has_move_target = false
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			_set_state(STATE_IDLE)
		else:
			var direction := to_target / distance
			var speed := run_speed if _move_run else walk_speed
			var desired_velocity := direction * speed
			velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
			velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)
			velocity.y = 0.0
			_face_direction(direction, delta)
			_set_state(STATE_RUN if _move_run else STATE_WALK)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		velocity.y = 0.0
		if _state == STATE_WALK or _state == STATE_RUN:
			_set_state(STATE_IDLE)

	move_and_slide()
	_snap_to_surface()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _snap_to_surface() -> void:
	if not use_terrain_height or not is_instance_valid(_surface_height_source):
		return

	var current_position := position
	if is_inside_tree():
		current_position = global_position
	var height: Variant = _get_surface_height(current_position)
	if height == null:
		return

	var snapped := current_position
	snapped.y = float(height) + terrain_height_offset
	if is_inside_tree():
		global_position = snapped
	else:
		position = snapped


func _get_surface_height(world_position: Vector3) -> Variant:
	var source := _surface_height_source
	if not is_instance_valid(source):
		return null
	if source.has_method("get_height"):
		var source_height: Variant = source.call("get_height", world_position)
		if source_height is float or source_height is int:
			return float(source_height)

	var data: Variant = source.get("data")
	if data and data is Object and (data as Object).has_method("get_height"):
		var data_height: Variant = (data as Object).call("get_height", world_position)
		if data_height is float or data_height is int:
			return float(data_height)

	return null


func _update_procedural_pose(delta: float) -> void:
	var locomotion_speed := 0.0
	var locomotion_amplitude := 0.0
	if _state == STATE_WALK:
		locomotion_speed = 6.0
		locomotion_amplitude = 0.44
	elif _state == STATE_RUN:
		locomotion_speed = 9.5
		locomotion_amplitude = 0.72

	if locomotion_speed > 0.0:
		_animation_phase += delta * locomotion_speed
	else:
		_animation_phase = lerpf(_animation_phase, 0.0, clampf(delta * 5.0, 0.0, 1.0))

	var swing := sin(_animation_phase) * locomotion_amplitude
	var idle_bob := sin(_state_time * 1.4) * 0.025
	var torso_pitch := 0.0
	var torso_roll := 0.0
	var left_arm_pitch := -swing * 0.75
	var right_arm_pitch := swing * 0.45
	var left_leg_pitch := swing
	var right_leg_pitch := -swing
	var hand_pitch := 0.0
	var root_roll := 0.0

	if _state == STATE_FIELD_TASK:
		var task_wave := sin(_state_time * 7.0)
		torso_pitch = -0.34
		left_arm_pitch = -0.95 + task_wave * 0.16
		right_arm_pitch = -0.9 - task_wave * 0.12
		left_leg_pitch = 0.12
		right_leg_pitch = -0.12
	elif _state == STATE_TOOL_ACTION:
		var progress := 1.0 - clampf(_timed_state_remaining / maxf(_timed_state_duration, 0.05), 0.0, 1.0)
		var thrust := sin(progress * PI)
		torso_pitch = -0.18 * thrust
		right_arm_pitch = -1.45 * thrust
		left_arm_pitch = -0.28 * thrust
		hand_pitch = -0.35 * thrust
	elif _state == STATE_DEAD:
		root_roll = 1.45
		torso_pitch = 0.15
		left_arm_pitch = -0.25
		right_arm_pitch = 0.3
		left_leg_pitch = 0.2
		right_leg_pitch = -0.18

	if _model_root:
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, root_roll, clampf(delta * 7.0, 0.0, 1.0))
		_model_root.position.y = idle_bob if is_alive() else 0.0
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, torso_pitch, clampf(delta * 10.0, 0.0, 1.0))
		_torso.rotation.z = lerp_angle(_torso.rotation.z, torso_roll, clampf(delta * 10.0, 0.0, 1.0))
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, left_arm_pitch, clampf(delta * 12.0, 0.0, 1.0))
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, right_arm_pitch, clampf(delta * 12.0, 0.0, 1.0))
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, left_leg_pitch, clampf(delta * 12.0, 0.0, 1.0))
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, right_leg_pitch, clampf(delta * 12.0, 0.0, 1.0))
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, hand_pitch, clampf(delta * 12.0, 0.0, 1.0))


func _set_state(next_state: StringName) -> void:
	if _state == next_state:
		return

	_state = next_state
	_state_time = 0.0
	state_changed.emit(_state)
	_sync_animation_player()


func _sync_animation_player() -> void:
	if not _animation_player:
		return
	if not _animation_player.has_animation(String(_state)):
		return
	if _animation_player.current_animation == String(_state):
		return
	_animation_player.play(String(_state))
