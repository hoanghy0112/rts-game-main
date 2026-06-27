extends CharacterBody3D
class_name HumanNPC

signal health_changed(current: float, maximum: float)
signal state_changed(state: StringName)
signal died(reason: StringName)
signal move_target_stalled(target: Vector3)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_RUN := &"run"
const STATE_FIELD_TASK := &"field_task"
const STATE_TOOL_ACTION := &"tool_action"
const STATE_DEAD := &"dead"
const INITIAL_EXTERNAL_SKELETON_SYNC_FRAMES := 4

@export_group("Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var max_health: float = 40.0
@export_range(0.1, 20.0, 0.1, "or_greater") var walk_speed: float = 1.45
@export_range(0.1, 30.0, 0.1, "or_greater") var run_speed: float = 3.1
@export_range(0.1, 100.0, 0.1, "or_greater") var acceleration: float = 12.0
@export_range(0.01, 4.0, 0.01, "or_greater") var stop_distance: float = 0.35
@export_range(0.1, 30.0, 0.1, "or_greater") var turn_speed: float = 9.0

@export_group("Movement Recovery")
@export_range(0.2, 5.0, 0.05, "or_greater") var move_stall_seconds: float = 1.15
@export_range(0.005, 1.0, 0.005, "or_greater") var move_stall_min_progress: float = 0.06
@export_range(0.0, 4.0, 0.05, "or_greater") var move_stall_recovery_side_speed: float = 0.85

@export_group("Combat")
@export_range(0.0, 1000.0, 1.0, "or_greater") var attack_damage: float = 8.0
@export_range(0.05, 20.0, 0.05, "or_greater") var attack_cooldown: float = 1.1

@export_group("Surface")
@export var use_terrain_height := true
@export_range(-4.0, 4.0, 0.01) var terrain_height_offset: float = 0.02

@export_group("Node Paths")
@export_node_path("Node3D") var model_root_path: NodePath = ^"VisualRoot"
@export_node_path("Node3D") var external_model_root_path: NodePath = ^"VisualRoot/ExternalModelSocket"
@export_node_path("Skeleton3D") var external_skeleton_path: NodePath = ^"VisualRoot/ExternalModelSocket/AnimatedHumanoid/PersonAnimated/Armature/Skeleton3D"
@export_node_path("Node3D") var torso_path: NodePath = ^"VisualRoot/Armature/Torso"
@export_node_path("Node3D") var head_path: NodePath = ^"VisualRoot/Armature/Head"
@export_node_path("Node3D") var left_arm_path: NodePath = ^"VisualRoot/Armature/LeftArm"
@export_node_path("Node3D") var right_arm_path: NodePath = ^"VisualRoot/Armature/RightArm"
@export_node_path("Node3D") var left_leg_path: NodePath = ^"VisualRoot/Armature/LeftLeg"
@export_node_path("Node3D") var right_leg_path: NodePath = ^"VisualRoot/Armature/RightLeg"
@export_node_path("Node3D") var right_hand_socket_path: NodePath = ^"VisualRoot/Armature/RightArm/RightHandSocket"
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"AnimationPlayer"
@export_node_path("AnimationTree") var animation_tree_path: NodePath = ^"AnimationTree"

@export_group("Imported Skeleton")
@export var sync_compatibility_armature_to_external_skeleton := true
@export var continuous_compatibility_skeleton_sync := true

var _health: float
var _state: StringName = STATE_IDLE
var _move_target := Vector3.ZERO
var _has_move_target := false
var _move_run := false
var _timed_state_remaining := 0.0
var _timed_state_duration := 0.0
var _state_time := 0.0
var _surface_height_source: Node3D
var _move_last_distance := INF
var _move_stall_timer := 0.0
var _move_stall_notified := false
var _move_recovery_side := 1.0
var _compatibility_bone_nodes: Array[Node3D] = []
var _compatibility_bone_indices: Array[int] = []
var _compatibility_bone_basis_offsets: Array[Basis] = []
var _compatibility_skeleton_sync_frames_remaining := 0

@onready var _model_root := get_node_or_null(model_root_path) as Node3D
@onready var _external_model_root := get_node_or_null(external_model_root_path) as Node3D
@onready var _external_skeleton := get_node_or_null(external_skeleton_path) as Skeleton3D
@onready var _torso := get_node_or_null(torso_path) as Node3D
@onready var _head := get_node_or_null(head_path) as Node3D
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
	set_process(false)
	_health = clampf(_health, 0.0, maxf(max_health, 1.0))
	if _health <= 0.0:
		_health = maxf(max_health, 1.0)
	_resolve_animation_player()
	_resolve_external_skeleton()
	_configure_compatibility_bone_targets()
	_disable_external_scene_helpers()
	add_to_group(&"human_npcs")
	_set_state(STATE_IDLE)
	_sync_animation_player()
	_sync_compatibility_armature_to_external_skeleton()
	_schedule_compatibility_skeleton_sync()


func _process(_delta: float) -> void:
	if not sync_compatibility_armature_to_external_skeleton or not _external_skeleton:
		set_process(false)
		return

	_sync_compatibility_armature_to_external_skeleton()
	call_deferred("_sync_compatibility_armature_to_external_skeleton")
	if _compatibility_skeleton_sync_frames_remaining > 0:
		_compatibility_skeleton_sync_frames_remaining -= 1
	if _compatibility_skeleton_sync_frames_remaining <= 0 and not continuous_compatibility_skeleton_sync:
		set_process(false)


func _physics_process(delta: float) -> void:
	_state_time += delta
	_update_timed_state(delta)
	_update_movement(delta)
	_update_animation_pose(delta)


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
	_reset_move_progress_tracking()
	_set_state(STATE_RUN if run else STATE_WALK)


func clear_move_target() -> void:
	_has_move_target = false
	_reset_move_progress_tracking()
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
	_reset_move_progress_tracking()
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
	_reset_move_progress_tracking()
	_timed_state_duration = maxf(duration if duration > 0.0 else attack_cooldown, 0.05)
	_timed_state_remaining = _timed_state_duration
	var was_tool_action := _state == STATE_TOOL_ACTION
	_set_state(STATE_TOOL_ACTION)
	if was_tool_action:
		_sync_animation_player(true)


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
	_reset_move_progress_tracking()
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
	_reset_move_progress_tracking()
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
			_reset_move_progress_tracking()
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			_set_state(STATE_IDLE)
		else:
			var direction := to_target / distance
			var speed := run_speed if _move_run else walk_speed
			var recovering := _update_move_progress(distance, delta)
			if not _has_move_target:
				velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
				velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
				velocity.y = 0.0
				if _state == STATE_WALK or _state == STATE_RUN:
					_set_state(STATE_IDLE)
				move_and_slide()
				_snap_to_surface()
				return
			var desired_velocity := direction * speed
			if recovering and move_stall_recovery_side_speed > 0.0:
				var side := Vector3(-direction.z, 0.0, direction.x) * _move_recovery_side
				desired_velocity = (desired_velocity + side * move_stall_recovery_side_speed).limit_length(speed)
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


func _update_move_progress(distance: float, delta: float) -> bool:
	if _move_last_distance == INF or distance <= _move_last_distance - move_stall_min_progress:
		_move_last_distance = distance
		_move_stall_timer = 0.0
		_move_stall_notified = false
		return false

	_move_stall_timer += delta
	if _move_stall_timer < move_stall_seconds:
		return false

	if not _move_stall_notified:
		_move_stall_notified = true
		_move_recovery_side *= -1.0
		move_target_stalled.emit(_move_target)
	return true


func _reset_move_progress_tracking() -> void:
	_move_last_distance = INF
	_move_stall_timer = 0.0
	_move_stall_notified = false


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


func _update_animation_pose(_delta: float) -> void:
	if _uses_imported_animation_player():
		_update_animation_player_driven_pose()


func _set_state(next_state: StringName) -> void:
	if _state == next_state:
		return

	_state = next_state
	_state_time = 0.0
	state_changed.emit(_state)
	_sync_animation_player()


func _resolve_animation_player() -> void:
	if _animation_player and _animation_player.get_animation_list().size() > 0:
		return

	var search_roots: Array[Node] = []
	if _external_model_root:
		search_roots.append(_external_model_root)
	if _model_root and _model_root != _external_model_root:
		search_roots.append(_model_root)

	for root in search_roots:
		var found := _find_animation_player_with_clips(root)
		if found:
			_animation_player = found
			return


func _find_animation_player_with_clips(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		var player := root as AnimationPlayer
		if player.get_animation_list().size() > 0:
			return player

	for child in root.get_children():
		var found := _find_animation_player_with_clips(child)
		if found:
			return found

	return null


func _resolve_external_skeleton() -> void:
	if _external_skeleton:
		return
	if _external_model_root:
		_external_skeleton = _find_external_skeleton(_external_model_root)


func _find_external_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D

	for child in root.get_children():
		var found := _find_external_skeleton(child)
		if found:
			return found

	return null


func _configure_compatibility_bone_targets() -> void:
	_compatibility_bone_nodes.clear()
	_compatibility_bone_indices.clear()
	_compatibility_bone_basis_offsets.clear()
	if not _external_skeleton:
		return

	_register_compatibility_bone_target(_torso, &"Chest")
	_register_compatibility_bone_target(_head, &"Head")
	_register_compatibility_bone_target(_left_arm, &"UpperArm.L")
	_register_compatibility_bone_target(_right_arm, &"UpperArm.R")
	_register_compatibility_bone_target(_left_leg, &"UpperLeg.L")
	_register_compatibility_bone_target(_right_leg, &"UpperLeg.R")
	_register_compatibility_bone_target(_right_hand_socket, &"Hand.R")


func _register_compatibility_bone_target(target: Node3D, bone_name: StringName) -> void:
	if not target:
		return

	var bone_index := _external_skeleton.find_bone(String(bone_name))
	if bone_index < 0:
		push_warning("Missing imported humanoid bone '%s' for %s" % [String(bone_name), target.get_path()])
		return

	var bone_rest_transform := _external_skeleton.global_transform * _external_skeleton.get_bone_global_rest(bone_index)
	var bone_rest_basis := bone_rest_transform.basis.orthonormalized()
	var target_basis := target.global_transform.basis.orthonormalized()
	_compatibility_bone_nodes.append(target)
	_compatibility_bone_indices.append(bone_index)
	_compatibility_bone_basis_offsets.append(bone_rest_basis.inverse() * target_basis)


func _sync_compatibility_armature_to_external_skeleton() -> void:
	if not sync_compatibility_armature_to_external_skeleton or not _external_skeleton:
		return

	for index in range(_compatibility_bone_nodes.size()):
		var target := _compatibility_bone_nodes[index]
		if not is_instance_valid(target):
			continue
		var bone_index := _compatibility_bone_indices[index]
		var bone_global_transform := _external_skeleton.global_transform * _external_skeleton.get_bone_global_pose(bone_index)
		var corrected_basis := bone_global_transform.basis.orthonormalized()
		if index < _compatibility_bone_basis_offsets.size():
			corrected_basis *= _compatibility_bone_basis_offsets[index]
		target.global_transform = Transform3D(
			corrected_basis,
			bone_global_transform.origin
		)


func _uses_imported_animation_player() -> bool:
	if not _external_skeleton:
		_resolve_external_skeleton()
	if not _animation_player:
		_resolve_animation_player()
	return _external_skeleton != null and _animation_player != null and _animation_player.get_animation_list().size() > 0


func _update_animation_player_driven_pose() -> void:
	_sync_animation_playback_speed()
	_sync_compatibility_armature_to_external_skeleton()


func _sync_animation_playback_speed() -> void:
	if not _animation_player:
		return

	var target_speed := _get_animation_playback_speed_scale()
	if absf(_animation_player.speed_scale - target_speed) <= 0.001:
		return
	_animation_player.speed_scale = target_speed


func _get_animation_playback_speed_scale() -> float:
	match _state:
		STATE_RUN:
			return clampf(run_speed / maxf(walk_speed, 0.1), 1.0, 2.4)
		STATE_TOOL_ACTION:
			var animation_name := _get_animation_name_for_state(_state)
			if animation_name != &"":
				var animation := _animation_player.get_animation(String(animation_name))
				if animation and _timed_state_duration > 0.0:
					return clampf(animation.length / maxf(_timed_state_duration, 0.05), 0.2, 2.5)
			return 1.0
		_:
			return 1.0


func _schedule_compatibility_skeleton_sync(frames: int = INITIAL_EXTERNAL_SKELETON_SYNC_FRAMES) -> void:
	if not sync_compatibility_armature_to_external_skeleton or not _external_skeleton:
		return

	if not continuous_compatibility_skeleton_sync:
		_compatibility_skeleton_sync_frames_remaining = maxi(
			_compatibility_skeleton_sync_frames_remaining,
			maxi(frames, 1)
		)
	set_process(true)
	call_deferred("_sync_compatibility_armature_to_external_skeleton")


func _disable_external_scene_helpers() -> void:
	if _external_model_root:
		_disable_external_scene_helpers_recursive(_external_model_root)


func _disable_external_scene_helpers_recursive(root: Node) -> void:
	if root is Camera3D:
		var camera := root as Camera3D
		camera.current = false
		camera.visible = false
	elif root is Light3D:
		var light := root as Light3D
		light.visible = false
		light.light_energy = 0.0

	for child in root.get_children():
		_disable_external_scene_helpers_recursive(child)


func _sync_animation_player(force_restart: bool = false) -> void:
	if not _animation_player:
		_resolve_animation_player()
	if not _animation_player:
		return

	var animation_name := _get_animation_name_for_state(_state)
	if animation_name == &"":
		if _state == STATE_DEAD:
			_animation_player.stop(false)
		return

	var animation_name_string := String(animation_name)
	var animation := _animation_player.get_animation(animation_name_string)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR if _should_loop_animation(_state) else Animation.LOOP_NONE
	_sync_animation_playback_speed()
	if not force_restart and _animation_player.current_animation == animation_name_string and _animation_player.is_playing():
		return

	_animation_player.play(animation_name_string)


func _get_animation_name_for_state(state: StringName) -> StringName:
	for animation_name in _get_animation_candidates_for_state(state):
		if _animation_player.has_animation(String(animation_name)):
			return animation_name
	return &""


func _get_animation_candidates_for_state(state: StringName) -> Array[StringName]:
	match state:
		STATE_IDLE:
			return [&"Armature|Standing", &"Standing", &"Armature|_Default", &"_Default"]
		STATE_WALK:
			return [&"Armature|Walk", &"Walk"]
		STATE_RUN:
			return [&"Armature|Run", &"Run"]
		STATE_FIELD_TASK:
			return [&"spear-soldier/Training", &"Training", &"Armature|CrouchSwing", &"CrouchSwing", &"Armature|CrouchIdle", &"CrouchIdle"]
		STATE_TOOL_ACTION:
			return [&"spear-soldier/Fight", &"spear-soldier/Fighting", &"Fight", &"Fighting", &"Armature|Swing", &"Swing", &"Armature|Punch", &"Punch"]
		_:
			return []


func _should_loop_animation(state: StringName) -> bool:
	return state == STATE_IDLE or state == STATE_WALK or state == STATE_RUN or state == STATE_FIELD_TASK
