extends "res://modules/units/human/human_npc.gd"
class_name TroopSoldierNPC

signal combat_stats_changed(summary: Dictionary)
signal deserted(soldier: Node)

@export_group("Formation Visual")
@export var formation_visual_only := true
@export_range(0.1, 4.0, 0.05, "or_greater") var formation_walk_animation_scale: float = 1.0

@export_group("Combat Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var max_strength: float = 40.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var damage: float = 8.0
@export_range(0.0, 100.0, 0.1) var morale: float = 72.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var endurance: float = 80.0
@export_range(1.0, 1000.0, 0.1, "or_greater") var max_endurance: float = 80.0

var _formation_walking := false
var _formation_speed_scale := 1.0
var _formation_attacking := false
var _formation_attack_time := 0.0
var _combat_target: Node3D
var _combat_in_range := false
var _spear_thrust_remaining := 0.0
var _spear_thrust_duration := 0.0
var _spear_phase_seed := 0.0
var _hit_reaction_remaining := 0.0
var _hit_reaction_duration := 0.0
var _outfit_palette: Dictionary = {}
var _independent_path_points: Array[Vector3] = []
var _independent_path_index := 0
var _independent_slot_offset := Vector3.ZERO
var _independent_target := Vector3.ZERO
var _has_independent_target := false
var _independent_speed := 1.0
var _independent_arrival_radius := 0.24
var _independent_motion_active := false
var _deserted := false
var _desert_direction := Vector3.ZERO


func _ready() -> void:
	_sync_combat_stats_to_human()
	super._ready()
	_spear_phase_seed = float(absi(hash(name)) % 1000) * 0.001 * TAU
	if not _outfit_palette.is_empty():
		_apply_outfit_palette()
	add_to_group(&"troop_soldiers")
	if formation_visual_only:
		_set_state(STATE_IDLE)


func _physics_process(delta: float) -> void:
	if not formation_visual_only:
		super._physics_process(delta)
		return

	_state_time += delta
	_spear_thrust_remaining = maxf(_spear_thrust_remaining - delta, 0.0)
	_hit_reaction_remaining = maxf(_hit_reaction_remaining - delta, 0.0)
	var moving_independently := _update_independent_motion(delta)
	if _formation_attacking:
		_formation_attack_time += delta
		if is_instance_valid(_combat_target):
			var to_target := _combat_target.global_position - global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.0001:
				_face_direction(to_target.normalized(), delta)
		if _spear_thrust_remaining > 0.0:
			_timed_state_duration = maxf(_spear_thrust_duration, 0.05)
			_timed_state_remaining = _spear_thrust_remaining
		else:
			_timed_state_duration = 0.0
			_timed_state_remaining = 0.0
		_set_state(STATE_TOOL_ACTION)
	elif _formation_walking or moving_independently:
		_set_state(STATE_WALK)
	else:
		_timed_state_remaining = 0.0
		_timed_state_duration = 0.0
		_set_state(STATE_IDLE)
	_update_desertion_motion(delta)
	_update_procedural_pose(delta * formation_walk_animation_scale * _formation_speed_scale)


func set_formation_walking(active: bool, speed_mps: float = 1.0) -> void:
	_formation_walking = active
	_formation_speed_scale = clampf(speed_mps / maxf(walk_speed, 0.1), 0.7, 2.4)
	if formation_visual_only:
		_set_state(STATE_WALK if _formation_walking else STATE_IDLE)


func is_formation_walking() -> bool:
	return _formation_walking


func set_move_target(_world_position: Vector3, run: bool = false) -> void:
	if not formation_visual_only:
		super.set_move_target(_world_position, run)
		return
	set_formation_walking(true, run_speed if run else walk_speed)


func clear_move_target() -> void:
	if not formation_visual_only:
		super.clear_move_target()
		return
	set_formation_walking(false)


func configure_combat_stats(
	strength_value: float,
	damage_value: float,
	morale_value: float,
	endurance_value: float,
	max_endurance_value: float
) -> void:
	max_strength = maxf(strength_value, 1.0)
	damage = maxf(damage_value, 0.1)
	morale = clampf(morale_value, 0.0, 100.0)
	max_endurance = maxf(max_endurance_value, 1.0)
	endurance = clampf(endurance_value, 0.0, max_endurance)
	_sync_combat_stats_to_human()
	combat_stats_changed.emit(get_combat_summary())


func configure_outfit_palette(palette: Dictionary) -> void:
	_outfit_palette = palette.duplicate(true)
	if has_node(model_root_path):
		_apply_outfit_palette()


func get_outfit_summary() -> Dictionary:
	return _outfit_palette.duplicate(true)


func follow_formation_path(path_points: Array, slot_offset: Vector3, speed_mps: float, arrival_radius_m: float = 0.28) -> void:
	_independent_path_points.clear()
	for point_variant: Variant in path_points:
		if point_variant is Vector3:
			_independent_path_points.append(point_variant as Vector3)
	_independent_path_index = 0
	_independent_slot_offset = slot_offset
	_independent_speed = maxf(speed_mps, 0.1)
	_independent_arrival_radius = maxf(arrival_radius_m, 0.05)
	_independent_motion_active = not _independent_path_points.is_empty()
	_has_independent_target = false
	if _independent_motion_active:
		_advance_completed_path_targets()
	set_formation_walking(_independent_motion_active, _independent_speed)


func set_independent_move_target(world_position: Vector3, speed_mps: float, arrival_radius_m: float = 0.24) -> void:
	_independent_path_points.clear()
	_independent_path_index = 0
	_independent_target = world_position
	_independent_speed = maxf(speed_mps, 0.1)
	_independent_arrival_radius = maxf(arrival_radius_m, 0.05)
	_has_independent_target = true
	_independent_motion_active = true
	set_formation_walking(true, _independent_speed)


func clear_independent_motion() -> void:
	_independent_path_points.clear()
	_independent_path_index = 0
	_has_independent_target = false
	_independent_motion_active = false
	set_formation_walking(false)


func has_independent_motion() -> bool:
	return _independent_motion_active


func set_formation_attacking(active: bool, target: Node3D = null) -> void:
	set_independent_combat(active, target, true)


func set_independent_combat(active: bool, target: Node3D = null, in_range: bool = false) -> void:
	_formation_attacking = active and is_combat_active()
	if _formation_attacking and _formation_attack_time <= 0.0:
		_formation_attack_time = float(absi(hash(name)) % 1000) * 0.001 * maxf(attack_cooldown, 0.05)
	_combat_target = target if _formation_attacking and is_instance_valid(target) else null
	_combat_in_range = _formation_attacking and in_range
	if not _formation_attacking:
		_spear_thrust_remaining = 0.0
		_spear_thrust_duration = 0.0
	if is_instance_valid(_combat_target):
		var to_target := _combat_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			_face_direction(to_target.normalized(), 1.0)
	if formation_visual_only:
		_set_state(STATE_TOOL_ACTION if _formation_attacking else (STATE_WALK if _formation_walking else STATE_IDLE))


func is_formation_attacking() -> bool:
	return _formation_attacking


func has_combat_target() -> bool:
	return is_instance_valid(_combat_target)


func get_combat_target() -> Node3D:
	return _combat_target if is_instance_valid(_combat_target) else null


func trigger_spear_thrust(target: Node3D = null, duration: float = -1.0) -> void:
	if not is_combat_active():
		return
	if target:
		_combat_target = target
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			_face_direction(to_target.normalized(), 1.0)
	_spear_thrust_duration = maxf(duration if duration > 0.0 else attack_cooldown * 0.72, 0.18)
	_spear_thrust_remaining = _spear_thrust_duration
	_formation_attacking = true
	if formation_visual_only:
		_timed_state_duration = _spear_thrust_duration
		_timed_state_remaining = _spear_thrust_remaining
		_set_state(STATE_TOOL_ACTION)


func is_spear_thrust_active() -> bool:
	return _spear_thrust_remaining > 0.0


func apply_strength_damage(amount: float, reason: StringName = &"combat") -> void:
	if amount > 0.0 and is_alive():
		_hit_reaction_duration = 0.32
		_hit_reaction_remaining = _hit_reaction_duration
	apply_damage(amount, reason)
	if not is_alive():
		_disappear_after_death()
	combat_stats_changed.emit(get_combat_summary())


func restore_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	endurance = clampf(endurance + amount, 0.0, max_endurance)
	combat_stats_changed.emit(get_combat_summary())


func reduce_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	endurance = clampf(endurance - amount, 0.0, max_endurance)
	combat_stats_changed.emit(get_combat_summary())


func change_morale(amount: float) -> void:
	if is_deserted():
		return
	morale = clampf(morale + amount, 0.0, 100.0)
	combat_stats_changed.emit(get_combat_summary())


func train_stats(strength_amount: float, damage_amount: float, morale_amount: float, endurance_max_amount: float) -> void:
	if not is_combat_active():
		return
	max_strength = maxf(max_strength + strength_amount, 1.0)
	max_health = max_strength
	damage = maxf(damage + damage_amount, 0.1)
	attack_damage = damage
	morale = clampf(morale + morale_amount, 0.0, 100.0)
	max_endurance = maxf(max_endurance + endurance_max_amount, 1.0)
	endurance = clampf(endurance, 0.0, max_endurance)
	combat_stats_changed.emit(get_combat_summary())


func mark_deserted(run_direction: Vector3) -> void:
	if _deserted:
		return
	_deserted = true
	_formation_attacking = false
	_formation_walking = true
	_desert_direction = run_direction
	_desert_direction.y = 0.0
	if _desert_direction.length_squared() <= 0.0001:
		_desert_direction = Vector3.FORWARD
	else:
		_desert_direction = _desert_direction.normalized()
	add_to_group(&"deserters")
	deserted.emit(self)
	combat_stats_changed.emit(get_combat_summary())


func is_deserted() -> bool:
	return _deserted


func is_combat_active() -> bool:
	return is_alive() and not _deserted


func get_strength() -> float:
	return get_health()


func get_effective_damage() -> float:
	var morale_factor := lerpf(0.35, 1.0, clampf(morale / 100.0, 0.0, 1.0))
	var endurance_factor := lerpf(0.35, 1.0, clampf(endurance / maxf(max_endurance, 1.0), 0.0, 1.0))
	return damage * morale_factor * endurance_factor


func get_combat_summary() -> Dictionary:
	return {
		"strength": get_strength(),
		"max_strength": max_strength,
		"damage": damage,
		"effective_damage": get_effective_damage(),
		"morale": morale,
		"endurance": endurance,
		"max_endurance": max_endurance,
		"alive": is_alive(),
		"deserted": _deserted,
	}


func kill(reason: StringName = &"death") -> void:
	super.kill(reason)
	_disappear_after_death()


func _update_procedural_pose(delta: float) -> void:
	super._update_procedural_pose(delta)
	if not formation_visual_only:
		return
	if not is_alive():
		return
	if not _formation_attacking and _hit_reaction_remaining <= 0.0:
		_relax_spear_socket(delta)
		return

	var thrust_progress := 0.0
	if _spear_thrust_duration > 0.0 and _spear_thrust_remaining > 0.0:
		thrust_progress = 1.0 - clampf(_spear_thrust_remaining / _spear_thrust_duration, 0.0, 1.0)
	var windup := 1.0 - clampf(thrust_progress / 0.24, 0.0, 1.0)
	var drive := sin(clampf((thrust_progress - 0.12) / 0.56, 0.0, 1.0) * PI)
	var recover := clampf((thrust_progress - 0.68) / 0.32, 0.0, 1.0)
	var hit_ratio := 0.0
	if _hit_reaction_duration > 0.0 and _hit_reaction_remaining > 0.0:
		hit_ratio = clampf(_hit_reaction_remaining / _hit_reaction_duration, 0.0, 1.0)
	var hit_kick := sin(hit_ratio * PI) * 0.28
	var stance_step := 0.12 if _combat_in_range else 0.24

	if _model_root:
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, hit_kick * 0.2, clampf(delta * 10.0, 0.0, 1.0))
	if _torso:
		var torso_pitch := -0.06 + windup * 0.08 - drive * 0.30 + recover * 0.06 + hit_kick
		_torso.rotation.x = lerp_angle(_torso.rotation.x, torso_pitch, clampf(delta * 14.0, 0.0, 1.0))
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	if _right_arm:
		var right_pitch := -0.58 + windup * 0.32 - drive * 1.22 + recover * 0.24 + hit_kick * 0.18
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, right_pitch, clampf(delta * 16.0, 0.0, 1.0))
	if _left_arm:
		var left_pitch := -0.46 - drive * 0.36 + windup * 0.08 + hit_kick * 0.08
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, left_pitch, clampf(delta * 16.0, 0.0, 1.0))
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, stance_step + drive * 0.12 - hit_kick * 0.08, clampf(delta * 12.0, 0.0, 1.0))
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -stance_step - drive * 0.08 + hit_kick * 0.06, clampf(delta * 12.0, 0.0, 1.0))
	if _right_hand_socket:
		var hand_pitch := -0.18 - drive * 0.42 + windup * 0.12 + hit_kick * 0.08
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, hand_pitch, clampf(delta * 18.0, 0.0, 1.0))
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, clampf(delta * 18.0, 0.0, 1.0))
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, -0.06, clampf(delta * 18.0, 0.0, 1.0))


func _update_independent_motion(delta: float) -> bool:
	if _deserted or not _independent_motion_active:
		return false
	var target: Variant = _get_current_independent_target()
	if target == null:
		clear_independent_motion()
		return false

	var destination := target as Vector3
	var to_target := destination - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= _independent_arrival_radius:
		if _advance_completed_path_targets():
			return _update_independent_motion(delta)
		clear_independent_motion()
		return false

	var direction := to_target / distance
	var step := minf(maxf(_independent_speed, 0.1) * delta, distance)
	global_position += direction * step
	_face_direction(direction, delta)
	set_formation_walking(true, _independent_speed)
	return true


func _get_current_independent_target() -> Variant:
	if not _independent_path_points.is_empty():
		if _independent_path_index >= _independent_path_points.size():
			return null
		return _get_offset_path_point(_independent_path_index)
	if _has_independent_target:
		return _independent_target
	return null


func _advance_completed_path_targets() -> bool:
	if _independent_path_points.is_empty():
		return false
	while _independent_path_index < _independent_path_points.size():
		var target := _get_offset_path_point(_independent_path_index)
		var to_target := target - global_position
		to_target.y = 0.0
		if to_target.length() > _independent_arrival_radius:
			return true
		_independent_path_index += 1
	return false


func _get_offset_path_point(path_index: int) -> Vector3:
	var anchor := _independent_path_points[clampi(path_index, 0, _independent_path_points.size() - 1)]
	var direction := Vector3.FORWARD
	if _independent_path_points.size() > 1:
		var next_index := mini(path_index + 1, _independent_path_points.size() - 1)
		var previous_index := maxi(path_index - 1, 0)
		if next_index != path_index:
			direction = _independent_path_points[next_index] - anchor
		else:
			direction = anchor - _independent_path_points[previous_index]
		direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			direction = Vector3.FORWARD
		else:
			direction = direction.normalized()
	var yaw := atan2(-direction.x, -direction.z)
	var basis := Basis(Vector3.UP, yaw)
	var offset := basis * _independent_slot_offset
	var target := anchor + offset
	target.y = global_position.y
	return target


func _disappear_after_death() -> void:
	if not is_inside_tree():
		return
	visible = false
	_independent_motion_active = false
	_has_independent_target = false
	_independent_path_points.clear()
	_formation_attacking = false
	_formation_walking = false
	if self is CollisionObject3D:
		var collision := self as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	call_deferred("queue_free")


func _sync_combat_stats_to_human() -> void:
	max_strength = maxf(max_strength, 1.0)
	max_endurance = maxf(max_endurance, 1.0)
	endurance = clampf(endurance, 0.0, max_endurance)
	max_health = max_strength
	attack_damage = maxf(damage, 0.1)
	if _health <= 0.0 or _health > max_health:
		_health = max_health


func _update_desertion_motion(delta: float) -> void:
	if not _deserted or _desert_direction.length_squared() <= 0.0001:
		return
	global_position += _desert_direction * run_speed * delta
	_face_direction(_desert_direction, delta)


func _relax_spear_socket(delta: float) -> void:
	if not _right_hand_socket:
		return
	_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))


func _apply_outfit_palette() -> void:
	_apply_palette_color("robe", ["OuterRobe", "RightRobePanel"])
	_apply_palette_color("robe_shadow", ["LeftLapel", "RightLapel"])
	_apply_palette_color("trim", ["WaistSash", "FrontRobePanel"])
	_apply_palette_color("pants", ["LeftPantsOverlay", "RightPantsOverlay"])
	_apply_palette_color("wraps", ["LeftLegWrap", "RightLegWrap", "LeftFootWrap", "RightFootWrap"])
	_apply_palette_color("hat", ["WideHatBrim", "HatCap"])
	_apply_palette_color("accent", ["RedPlume", "TopKnot"])


func _apply_palette_color(key: String, node_names: Array[String]) -> void:
	if not _outfit_palette.has(key):
		return
	var value: Variant = _outfit_palette.get(key)
	if not (value is Color):
		return
	for node_name: String in node_names:
		_apply_material_color(node_name, value as Color)


func _apply_material_color(node_name: String, color: Color) -> void:
	var mesh_instance := find_child(node_name, true, false) as MeshInstance3D
	if not mesh_instance:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.0
	mesh_instance.set_surface_override_material(0, material)
