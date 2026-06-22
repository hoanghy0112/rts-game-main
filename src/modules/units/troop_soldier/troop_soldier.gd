extends "res://modules/units/human/human_npc.gd"
class_name TroopSoldierNPC

signal combat_stats_changed(summary: Dictionary)
signal deserted(soldier: Node)

const ACTIVITY_IDLE := &"idle"
const ACTIVITY_REST := &"rest"
const ACTIVITY_TRAINING := &"training"
const ACTIVITY_NONE := &"none"
const VARIANT_IDLE_LOOK := &"idle_look"
const VARIANT_IDLE_SPEAR := &"idle_spear"
const VARIANT_TRAINING_SPEAR := &"training_spear"
const VARIANT_REST_STAND := &"rest_stand"
const VARIANT_REST_SIT := &"rest_sit"
const VARIANT_REST_LAY := &"rest_lay"
const CORPSE_SPEAR_SCENE: PackedScene = preload("res://modules/units/human/low_poly_spear.tscn")
const SPEAR_TIP_LOCAL_Y := 0.526

@export_group("Formation Visual")
@export var formation_visual_only := true
@export_range(0.1, 4.0, 0.05, "or_greater") var formation_walk_animation_scale: float = 1.0

@export_group("Performance")
@export_range(0.0, 1.0, 0.01) var combat_stats_signal_interval: float = 0.25
@export var disable_corpse_processing := true

@export_group("Combat Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var max_strength: float = 40.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var damage: float = 8.0
@export_range(0.0, 100.0, 0.1) var morale: float = 72.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var endurance: float = 80.0
@export_range(1.0, 1000.0, 0.1, "or_greater") var max_endurance: float = 80.0
@export_range(0.0, 1000.0, 0.01, "or_greater") var starving_days: float = 0.0

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
var _independent_final_yaw_active := false
var _independent_final_yaw := 0.0
var _independent_target := Vector3.ZERO
var _has_independent_target := false
var _independent_speed := 1.0
var _independent_arrival_radius := 0.24
var _independent_motion_active := false
var _deserted := false
var _desert_direction := Vector3.ZERO
var _desert_speed_multiplier := 1.0
var _corpse_state_applied := false
var _corpse_roll := PI * 0.5
var _activity_mode: StringName = ACTIVITY_IDLE
var _activity_variant: StringName = VARIANT_IDLE_LOOK
var _activity_timer := 0.0
var _activity_duration := 0.0
var _activity_time := 0.0
var _activity_pick_index := 0
var _held_spear: Node3D
var _corpse_spear: Node3D
var _combat_stats_emit_elapsed := 0.0
var _combat_stats_emit_pending := false


func _ready() -> void:
	_sync_combat_stats_to_human()
	super._ready()
	_spear_phase_seed = float(absi(hash(name)) % 1000) * 0.001 * TAU
	_held_spear = get_node_or_null("VisualRoot/Armature/RightArm/RightHandSocket/LongSpear/LowPolySpear") as Node3D
	if not _outfit_palette.is_empty():
		_apply_outfit_palette()
	add_to_group(&"troop_soldiers")
	if formation_visual_only:
		_set_state(STATE_IDLE)
		_choose_next_activity_variant()


func _physics_process(delta: float) -> void:
	_update_combat_stats_signal(delta)
	if not formation_visual_only:
		super._physics_process(delta)
		return

	_state_time += delta
	_spear_thrust_remaining = maxf(_spear_thrust_remaining - delta, 0.0)
	_hit_reaction_remaining = maxf(_hit_reaction_remaining - delta, 0.0)
	if not is_alive():
		_formation_walking = false
		_formation_attacking = false
		_independent_motion_active = false
		_has_independent_target = false
		_update_procedural_pose(delta)
		return
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
		_update_activity_state(delta)
		_set_state(STATE_IDLE)
	_update_desertion_motion(delta)
	_update_procedural_pose(delta * formation_walk_animation_scale * _formation_speed_scale)


func _queue_combat_stats_changed(force: bool = false) -> void:
	if force or combat_stats_signal_interval <= 0.0:
		_combat_stats_emit_elapsed = 0.0
		_combat_stats_emit_pending = false
		combat_stats_changed.emit(get_combat_summary())
		return
	if _combat_stats_emit_elapsed >= combat_stats_signal_interval:
		_combat_stats_emit_elapsed = 0.0
		_combat_stats_emit_pending = false
		combat_stats_changed.emit(get_combat_summary())
		return
	_combat_stats_emit_pending = true


func _update_combat_stats_signal(delta: float) -> void:
	if combat_stats_signal_interval <= 0.0:
		if _combat_stats_emit_pending:
			_queue_combat_stats_changed(true)
		return
	_combat_stats_emit_elapsed += maxf(delta, 0.0)
	if _combat_stats_emit_pending and _combat_stats_emit_elapsed >= combat_stats_signal_interval:
		_queue_combat_stats_changed(true)


func set_formation_walking(active: bool, speed_mps: float = 1.0) -> void:
	if not is_alive():
		_formation_walking = false
		_formation_speed_scale = 1.0
		return
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
	max_endurance_value: float,
	run_speed_value: float = -1.0
) -> void:
	max_strength = maxf(strength_value, 1.0)
	damage = maxf(damage_value, 0.1)
	morale = clampf(morale_value, 0.0, 100.0)
	max_endurance = maxf(max_endurance_value, 1.0)
	endurance = clampf(endurance_value, 0.0, max_endurance)
	if run_speed_value > 0.0:
		run_speed = maxf(run_speed_value, 0.1)
	_sync_combat_stats_to_human()
	_queue_combat_stats_changed()


func configure_outfit_palette(palette: Dictionary) -> void:
	_outfit_palette = palette.duplicate(true)
	if has_node(model_root_path):
		_apply_outfit_palette()


func get_outfit_summary() -> Dictionary:
	return _outfit_palette.duplicate(true)


func follow_formation_path(
	path_points: Array,
	slot_offset: Vector3,
	speed_mps: float,
	arrival_radius_m: float = 0.28,
	initial_path_index: int = 0,
	final_yaw_active: bool = false,
	final_yaw: float = 0.0
) -> void:
	if not is_alive():
		clear_independent_motion()
		return
	_independent_path_points.clear()
	for point_variant: Variant in path_points:
		if point_variant is Vector3:
			_independent_path_points.append(point_variant as Vector3)
	_independent_path_index = (
		clampi(initial_path_index, 0, _independent_path_points.size() - 1)
		if not _independent_path_points.is_empty()
		else 0
	)
	_independent_slot_offset = slot_offset
	_independent_final_yaw_active = final_yaw_active
	_independent_final_yaw = final_yaw
	_independent_speed = maxf(speed_mps, 0.1)
	_independent_arrival_radius = maxf(arrival_radius_m, 0.05)
	_independent_motion_active = not _independent_path_points.is_empty()
	_has_independent_target = false
	if _independent_motion_active:
		_advance_completed_path_targets()
	set_formation_walking(_independent_motion_active, _independent_speed)


func set_independent_move_target(world_position: Vector3, speed_mps: float, arrival_radius_m: float = 0.24) -> void:
	if not is_alive():
		clear_independent_motion()
		return
	var arrival := maxf(arrival_radius_m, 0.05)
	var speed := maxf(speed_mps, 0.1)
	var to_target := world_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= arrival * arrival:
		if _independent_motion_active or _has_independent_target:
			clear_independent_motion()
		return
	if (
		_has_independent_target
		and _independent_motion_active
		and _independent_path_points.is_empty()
		and _independent_target.distance_squared_to(world_position) <= 0.0004
		and is_equal_approx(_independent_speed, speed)
		and is_equal_approx(_independent_arrival_radius, arrival)
	):
		return
	_independent_path_points.clear()
	_independent_path_index = 0
	_independent_final_yaw_active = false
	_independent_final_yaw = 0.0
	_independent_target = world_position
	_independent_speed = speed
	_independent_arrival_radius = arrival
	_has_independent_target = true
	_independent_motion_active = true
	set_formation_walking(true, _independent_speed)


func clear_independent_motion() -> void:
	_independent_path_points.clear()
	_independent_path_index = 0
	_independent_final_yaw_active = false
	_independent_final_yaw = 0.0
	_has_independent_target = false
	_independent_motion_active = false
	set_formation_walking(false)


func has_independent_motion() -> bool:
	return _independent_motion_active


func set_activity_mode(mode: Variant) -> void:
	var next_mode := StringName(String(mode).to_lower())
	match next_mode:
		ACTIVITY_REST, ACTIVITY_TRAINING, ACTIVITY_IDLE, ACTIVITY_NONE:
			pass
		_:
			next_mode = ACTIVITY_IDLE
	if _activity_mode == next_mode:
		return
	_activity_mode = next_mode
	_activity_timer = 0.0
	_activity_duration = 0.0
	_activity_time = 0.0
	_choose_next_activity_variant()


func get_activity_mode() -> StringName:
	return _activity_mode


func get_activity_variant() -> StringName:
	return _activity_variant


func force_activity_variant_for_test(variant: StringName, duration: float = 60.0) -> void:
	_activity_variant = variant
	_activity_duration = maxf(duration, 0.05)
	_activity_timer = _activity_duration
	_activity_time = 0.0


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
	var was_alive := is_alive()
	var previous_health := get_health()
	apply_damage(amount, reason)
	if not is_alive():
		_enter_corpse_state()
	if not is_equal_approx(previous_health, get_health()) or was_alive != is_alive():
		_queue_combat_stats_changed(not is_alive())


func restore_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	var previous := endurance
	endurance = clampf(endurance + amount, 0.0, max_endurance)
	if is_equal_approx(previous, endurance):
		return
	_queue_combat_stats_changed()


func reduce_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	var previous := endurance
	endurance = clampf(endurance - amount, 0.0, max_endurance)
	if is_equal_approx(previous, endurance):
		return
	_queue_combat_stats_changed()


func apply_starvation(
	shortage_ratio: float,
	game_days: float,
	endurance_loss_per_day: float,
	health_loss_per_day: float,
	death_start_days: float,
	base_death_chance_per_day: float,
	extra_death_chance_per_day: float,
	max_death_chance_per_day: float,
	death_roll: float
) -> void:
	if not is_alive():
		return
	var ratio := clampf(shortage_ratio, 0.0, 1.0)
	var days := maxf(game_days, 0.0)
	if ratio <= 0.0 or days <= 0.0:
		var previous_starving_days := starving_days
		starving_days = maxf(starving_days - days, 0.0)
		if is_equal_approx(previous_starving_days, starving_days):
			return
		_queue_combat_stats_changed()
		return

	starving_days += ratio * days
	reduce_endurance(maxf(endurance_loss_per_day, 0.0) * ratio * days)
	apply_strength_damage(maxf(health_loss_per_day, 0.0) * ratio * days, &"starvation")
	if not is_alive():
		return

	var death_start := maxf(death_start_days, 0.0)
	if starving_days < death_start:
		return
	var daily_chance := clampf(
		maxf(base_death_chance_per_day, 0.0) + maxf(starving_days - death_start, 0.0) * maxf(extra_death_chance_per_day, 0.0),
		0.0,
		clampf(max_death_chance_per_day, 0.0, 1.0)
	)
	var probability := clampf(daily_chance * days * ratio, 0.0, 1.0)
	if clampf(death_roll, 0.0, 1.0) < probability:
		kill(&"starvation")
	_queue_combat_stats_changed()


func change_morale(amount: float) -> void:
	if is_deserted():
		return
	morale = clampf(morale + amount, 0.0, 100.0)
	_queue_combat_stats_changed()


func train_stats(strength_amount: float, damage_amount: float, morale_amount: float, endurance_max_amount: float) -> void:
	if not is_combat_active():
		return
	_apply_training_growth(strength_amount, damage_amount, morale_amount, endurance_max_amount)
	_queue_combat_stats_changed()


func train_stats_with_caps(
	strength_amount: float,
	damage_amount: float,
	morale_amount: float,
	endurance_max_amount: float,
	strength_soft_cap: float,
	damage_soft_cap: float,
	morale_soft_cap: float,
	endurance_soft_cap: float
) -> void:
	if not is_combat_active():
		return
	_apply_training_growth(
		_get_soft_capped_gain(max_strength, strength_amount, strength_soft_cap),
		_get_soft_capped_gain(damage, damage_amount, damage_soft_cap),
		_get_soft_capped_gain(morale, morale_amount, morale_soft_cap),
		_get_soft_capped_gain(max_endurance, endurance_max_amount, endurance_soft_cap)
	)
	_queue_combat_stats_changed()


func apply_fight_growth(
	damage_amount: float,
	endurance_max_amount: float,
	damage_soft_cap: float,
	endurance_soft_cap: float
) -> void:
	if not is_combat_active():
		return
	_apply_training_growth(
		0.0,
		_get_soft_capped_gain(damage, damage_amount, damage_soft_cap),
		0.0,
		_get_soft_capped_gain(max_endurance, endurance_max_amount, endurance_soft_cap)
	)
	_queue_combat_stats_changed()


func apply_stat_job_result(result: Dictionary) -> void:
	if not is_alive():
		return

	var previous_health := get_health()
	var previous_alive := is_alive()
	var changed := false

	var next_max_strength := maxf(float(result.get("max_strength", max_strength)), 1.0)
	if not is_equal_approx(next_max_strength, max_strength):
		max_strength = next_max_strength
		max_health = max_strength
		changed = true

	var next_damage := maxf(float(result.get("damage", damage)), 0.1)
	if not is_equal_approx(next_damage, damage):
		damage = next_damage
		attack_damage = damage
		changed = true

	var next_morale := clampf(float(result.get("morale", morale)), 0.0, 100.0)
	if not is_equal_approx(next_morale, morale):
		morale = next_morale
		changed = true

	var next_max_endurance := maxf(float(result.get("max_endurance", max_endurance)), 1.0)
	if not is_equal_approx(next_max_endurance, max_endurance):
		max_endurance = next_max_endurance
		changed = true

	var next_endurance := clampf(float(result.get("endurance", endurance)), 0.0, max_endurance)
	if not is_equal_approx(next_endurance, endurance):
		endurance = next_endurance
		changed = true

	var next_starving_days := maxf(float(result.get("starving_days", starving_days)), 0.0)
	if not is_equal_approx(next_starving_days, starving_days):
		starving_days = next_starving_days
		changed = true

	var next_health := clampf(float(result.get("health", previous_health)), 0.0, max_strength)
	if bool(result.get("kill", false)) or next_health <= 0.0:
		var reason := StringName(result.get("death_reason", &"starvation"))
		kill(reason)
		return

	if not is_equal_approx(next_health, previous_health):
		if next_health < previous_health:
			_hit_reaction_duration = 0.32
			_hit_reaction_remaining = _hit_reaction_duration
		_health = next_health
		health_changed.emit(_health, max_health)
		changed = true

	if changed or previous_alive != is_alive():
		_queue_combat_stats_changed(previous_alive != is_alive())


func _apply_training_growth(strength_amount: float, damage_amount: float, morale_amount: float, endurance_max_amount: float) -> void:
	max_strength = maxf(max_strength + strength_amount, 1.0)
	max_health = max_strength
	damage = maxf(damage + damage_amount, 0.1)
	attack_damage = damage
	morale = clampf(morale + morale_amount, 0.0, 100.0)
	max_endurance = maxf(max_endurance + endurance_max_amount, 1.0)
	endurance = clampf(endurance, 0.0, max_endurance)


func _get_soft_capped_gain(current_value: float, amount: float, soft_cap: float) -> float:
	if amount <= 0.0:
		return 0.0
	if soft_cap <= current_value:
		return 0.0
	var remaining_ratio := clampf((soft_cap - current_value) / maxf(soft_cap, 0.001), 0.0, 1.0)
	return amount * remaining_ratio


func mark_deserted(run_direction: Vector3, speed_multiplier: float = 1.0) -> void:
	if _deserted:
		return
	_deserted = true
	_formation_attacking = false
	_formation_walking = true
	_desert_speed_multiplier = maxf(speed_multiplier, 1.0)
	_formation_speed_scale = clampf((run_speed * _desert_speed_multiplier) / maxf(walk_speed, 0.1), 0.7, 3.6)
	_desert_direction = run_direction
	_desert_direction.y = 0.0
	if _desert_direction.length_squared() <= 0.0001:
		_desert_direction = Vector3.FORWARD
	else:
		_desert_direction = _desert_direction.normalized()
	add_to_group(&"deserters")
	deserted.emit(self)
	_queue_combat_stats_changed()


func mark_deserter_group_member() -> void:
	_deserted = false
	_formation_attacking = false
	_formation_walking = false
	_desert_direction = Vector3.ZERO
	_desert_speed_multiplier = 1.0
	remove_from_group(&"deserters")
	_queue_combat_stats_changed()


func mark_returned_from_desertion() -> void:
	mark_deserter_group_member()


func is_deserted() -> bool:
	return _deserted


func is_combat_active() -> bool:
	return is_alive() and not _deserted


func get_starving_days() -> float:
	return starving_days


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
		"run_speed": run_speed,
		"starving_days": starving_days,
		"alive": is_alive(),
		"deserted": _deserted,
		"desert_speed_multiplier": _desert_speed_multiplier,
		"activity_mode": _activity_mode,
		"activity_variant": _activity_variant,
	}


func kill(reason: StringName = &"death") -> void:
	super.kill(reason)
	_enter_corpse_state()
	_queue_combat_stats_changed(true)


func _update_procedural_pose(delta: float) -> void:
	super._update_procedural_pose(delta)
	if not formation_visual_only:
		return
	if not is_alive():
		_apply_corpse_pose()
		return
	if not _formation_attacking and _hit_reaction_remaining <= 0.0:
		_apply_activity_pose(delta)
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
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, hit_kick * 0.2, clampf(delta * 10.0, 0.0, 1.0))
	if _torso:
		var torso_pitch := -0.06 + windup * 0.08 - drive * 0.30 + recover * 0.06 + hit_kick
		_torso.rotation.x = lerp_angle(_torso.rotation.x, torso_pitch, clampf(delta * 14.0, 0.0, 1.0))
		_torso.rotation.y = lerp_angle(_torso.rotation.y, 0.0, clampf(delta * 14.0, 0.0, 1.0))
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	if _right_arm:
		var right_pitch := -0.58 - windup * 0.18 + drive * 0.72 - recover * 0.12 + hit_kick * 0.18
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, right_pitch, clampf(delta * 16.0, 0.0, 1.0))
	if _left_arm:
		var left_pitch := -0.46 + drive * 0.22 - windup * 0.08 + hit_kick * 0.08
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, left_pitch, clampf(delta * 16.0, 0.0, 1.0))
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, stance_step + drive * 0.12 - hit_kick * 0.08, clampf(delta * 12.0, 0.0, 1.0))
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -stance_step - drive * 0.08 + hit_kick * 0.06, clampf(delta * 12.0, 0.0, 1.0))
	if _right_hand_socket:
		var hand_pitch := -0.18 + drive * 0.36 - windup * 0.10 + hit_kick * 0.08
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, hand_pitch, clampf(delta * 18.0, 0.0, 1.0))
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, clampf(delta * 18.0, 0.0, 1.0))
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, -0.06, clampf(delta * 18.0, 0.0, 1.0))


func _update_activity_state(delta: float) -> void:
	if _activity_mode == ACTIVITY_NONE:
		_activity_variant = ACTIVITY_NONE
		_activity_timer = 0.0
		_activity_duration = 0.0
		_activity_time = 0.0
		return
	_activity_time += delta
	if _activity_timer > 0.0:
		_activity_timer = maxf(_activity_timer - delta, 0.0)
	if _activity_timer <= 0.0:
		_choose_next_activity_variant()


func _choose_next_activity_variant() -> void:
	_activity_pick_index += 1
	var roll := _activity_roll("variant")
	match _activity_mode:
		ACTIVITY_TRAINING:
			_activity_variant = VARIANT_TRAINING_SPEAR
			_activity_duration = 2.4
		ACTIVITY_REST:
			if roll < 0.34:
				_activity_variant = VARIANT_REST_STAND
			elif roll < 0.68:
				_activity_variant = VARIANT_REST_SIT
			else:
				_activity_variant = VARIANT_REST_LAY
			_activity_duration = _activity_range("rest_duration", 15.0, 20.0)
		ACTIVITY_IDLE:
			if roll < 0.52:
				_activity_variant = VARIANT_IDLE_LOOK
			else:
				_activity_variant = VARIANT_IDLE_SPEAR
			_activity_duration = _activity_range("idle_duration", 2.4, 5.4)
		_:
			_activity_variant = ACTIVITY_NONE
			_activity_duration = 0.0
	_activity_timer = _activity_duration
	_activity_time = 0.0


func _activity_roll(label: String) -> float:
	var seed := "%s:%s:%d:%s" % [String(name), String(_activity_mode), _activity_pick_index, label]
	return float(absi(hash(seed)) % 10000) / 10000.0


func _activity_range(label: String, minimum: float, maximum: float) -> float:
	return lerpf(minimum, maximum, _activity_roll(label))


func _apply_activity_pose(delta: float) -> void:
	match _activity_variant:
		VARIANT_TRAINING_SPEAR:
			_apply_training_spear_pose(delta)
		VARIANT_REST_STAND:
			_apply_rest_stand_pose(delta)
		VARIANT_REST_SIT:
			_apply_rest_sit_pose(delta)
		VARIANT_REST_LAY:
			_apply_rest_lay_pose(delta)
		VARIANT_IDLE_SPEAR:
			_apply_idle_spear_pose(delta)
		_:
			_apply_idle_look_pose(delta)
	if _activity_variant != VARIANT_TRAINING_SPEAR and _activity_variant != VARIANT_IDLE_SPEAR and not _is_rest_activity_variant(_activity_variant):
		_relax_spear_socket(delta)


func _apply_training_spear_pose(delta: float) -> void:
	var cycle := fposmod(_activity_time, 2.4) / 2.4
	var draw_back := sin(_smooth_step_unit(clampf(cycle / 0.18, 0.0, 1.0)) * PI)
	var extend := _smooth_step_unit(clampf((cycle - 0.18) / 0.24, 0.0, 1.0))
	var recover := _smooth_step_unit(clampf((cycle - 0.62) / 0.28, 0.0, 1.0))
	var thrust := clampf(extend - recover, 0.0, 1.0)
	var brace := maxf(thrust, draw_back * 0.35)
	var reset_weight := clampf(delta * 14.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, reset_weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, 0.0, reset_weight)
		_model_root.position.y = lerpf(_model_root.position.y, 0.0, reset_weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, -0.04 + draw_back * 0.04 - thrust * 0.18, reset_weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, 0.0, reset_weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, reset_weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, -0.58 - draw_back * 0.10 + thrust * 0.52, reset_weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.44 + thrust * 0.16, reset_weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.18 + brace * 0.04, reset_weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -0.18 - brace * 0.03, reset_weight)
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, -0.06 - draw_back * 0.04 + thrust * 0.22, reset_weight)
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, reset_weight)
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, -0.035, reset_weight)


func _apply_rest_stand_pose(delta: float) -> void:
	var phase := _state_time * 0.45 + _spear_phase_seed
	var weight := clampf(delta * 7.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, sin(phase) * 0.012, weight)
		_model_root.position.y = lerpf(_model_root.position.y, 0.0, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, 0.02, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, sin(phase * 0.6) * 0.04, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, 0.18, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, 0.08, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.03, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -0.03, weight)
	_lower_spear_for_rest(delta, Vector3(0.72, 0.0, 0.28))


func _apply_rest_sit_pose(delta: float) -> void:
	var phase := _state_time * 0.35 + _spear_phase_seed
	var weight := clampf(delta * 7.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, 0.0, weight)
		_model_root.position.y = lerpf(_model_root.position.y, -0.16 + sin(phase) * 0.006, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, -0.12, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, sin(phase * 0.7) * 0.05, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, 0.16, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, 0.04, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.98, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, 0.92, weight)
	_lower_spear_for_rest(delta, Vector3(0.86, -0.04, 0.34))


func _apply_rest_lay_pose(delta: float) -> void:
	var phase := _state_time * 0.3 + _spear_phase_seed
	var weight := clampf(delta * 7.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, PI * 0.5, weight)
		_model_root.position.y = lerpf(_model_root.position.y, 0.05 + sin(phase) * 0.004, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, 0.06, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, 0.0, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, 0.30, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.18, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.16, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -0.12, weight)
	_lower_spear_for_rest(delta, Vector3(0.68, 0.08, 0.42))


func _apply_idle_look_pose(delta: float) -> void:
	var phase := _state_time * 0.75 + _spear_phase_seed
	var weight := clampf(delta * 5.5, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, sin(phase * 0.7) * 0.018, weight)
		_model_root.position.y = lerpf(_model_root.position.y, 0.0, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, sin(phase * 0.5) * 0.022, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, sin(phase) * 0.16, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, sin(phase * 0.6) * 0.014, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, -0.08 + sin(phase * 0.65) * 0.035, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.05 + cos(phase * 0.55) * 0.024, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.0, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, 0.0, weight)
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, 0.015 + sin(phase * 0.85) * 0.05, weight)
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, sin(phase * 0.45) * 0.045, weight)
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, cos(phase * 0.5) * 0.03, weight)


func _apply_idle_spear_pose(delta: float) -> void:
	var phase := _state_time * 0.9 + _spear_phase_seed
	var weight := clampf(delta * 5.5, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, 0.0, weight)
		_model_root.position.y = lerpf(_model_root.position.y, 0.0, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, sin(phase * 0.55) * 0.018, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, sin(phase * 0.35) * 0.055, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, -0.16 + sin(phase) * 0.052, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.10 + cos(phase) * 0.038, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.02, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -0.02, weight)
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, sin(phase) * 0.07, weight)
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, sin(phase * 0.6) * 0.052, weight)
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, cos(phase * 0.4) * 0.035, weight)


func _update_independent_motion(delta: float) -> bool:
	if _deserted or not is_alive() or not _independent_motion_active:
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
	if _independent_final_yaw_active and path_index >= _independent_path_points.size() - 1:
		var final_basis := Basis(Vector3.UP, _independent_final_yaw)
		var final_offset := final_basis * _independent_slot_offset
		var final_target := anchor + final_offset
		final_target.y = global_position.y
		return final_target
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


func _enter_corpse_state() -> void:
	if _corpse_state_applied:
		_apply_corpse_pose()
		return
	_corpse_state_applied = true
	_corpse_roll = PI * 0.5
	if absi(hash(name)) % 2 == 0:
		_corpse_roll = -PI * 0.5
	visible = true
	_independent_motion_active = false
	_has_independent_target = false
	_independent_path_points.clear()
	_formation_attacking = false
	_formation_walking = false
	_combat_target = null
	_combat_in_range = false
	_spear_thrust_remaining = 0.0
	_spear_thrust_duration = 0.0
	velocity = Vector3.ZERO
	_drop_corpse_spear()
	if self is CollisionObject3D:
		var collision := self as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	_disable_collision_recursive(self)
	_apply_corpse_pose()
	if disable_corpse_processing:
		set_physics_process(false)


func _apply_corpse_pose() -> void:
	if _model_root:
		_model_root.rotation.x = 0.0
		_model_root.rotation.z = _corpse_roll
		_model_root.position.y = 0.03
	if _torso:
		_torso.rotation.x = 0.12
		_torso.rotation.z = 0.0
	if _left_arm:
		_left_arm.rotation.x = -0.32
	if _right_arm:
		_right_arm.rotation.x = 0.24
	if _left_leg:
		_left_leg.rotation.x = 0.18
	if _right_leg:
		_right_leg.rotation.x = -0.16
	if _right_hand_socket:
		_right_hand_socket.rotation = Vector3.ZERO


func has_visible_held_spear() -> bool:
	return is_instance_valid(_held_spear) and _held_spear.visible


func has_dropped_corpse_spear() -> bool:
	return is_instance_valid(_corpse_spear) and _corpse_spear.visible


func get_dropped_corpse_spear() -> Node3D:
	return _corpse_spear if is_instance_valid(_corpse_spear) else null


func _drop_corpse_spear() -> void:
	if not is_instance_valid(_held_spear):
		_held_spear = get_node_or_null("VisualRoot/Armature/RightArm/RightHandSocket/LongSpear/LowPolySpear") as Node3D
	if is_instance_valid(_held_spear):
		_held_spear.visible = false
	if is_instance_valid(_corpse_spear):
		return
	var dropped := CORPSE_SPEAR_SCENE.instantiate() as Node3D
	if not dropped:
		return
	dropped.name = "DroppedCorpseSpear"
	dropped.top_level = true
	add_child(dropped)
	_corpse_spear = dropped

	var placement_angle := _corpse_random_unit("spear_angle") * TAU
	var horizontal := Vector3(cos(placement_angle), 0.0, sin(placement_angle)).normalized()
	var distance := lerpf(0.28, 0.82, _corpse_random_unit("spear_distance"))
	var ground_position := global_position + horizontal * distance
	ground_position.y = 0.045
	var roll := lerpf(-PI, PI, _corpse_random_unit("spear_roll"))
	var embedded := _corpse_random_unit("spear_embedded") < 0.36
	if embedded:
		var embed_angle := lerpf(deg_to_rad(32.0), deg_to_rad(68.0), _corpse_random_unit("spear_embed_angle"))
		var spear_axis := (horizontal * cos(embed_angle) + Vector3.DOWN * sin(embed_angle)).normalized()
		var spear_origin := ground_position - spear_axis * SPEAR_TIP_LOCAL_Y
		dropped.global_transform = Transform3D(_basis_from_local_y_axis(spear_axis, roll), spear_origin)
	else:
		var lie_axis := horizontal
		dropped.global_transform = Transform3D(_basis_from_local_y_axis(lie_axis, roll), ground_position)
	dropped.scale = Vector3(1.25, 1.0, 1.25)


func _disable_collision_recursive(node: Node) -> void:
	if node is CollisionObject3D:
		var collision := node as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child: Node in node.get_children():
		_disable_collision_recursive(child)


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
	global_position += _desert_direction * run_speed * _desert_speed_multiplier * delta
	_face_direction(_desert_direction, delta)


func _relax_spear_socket(delta: float) -> void:
	if not _right_hand_socket:
		return
	_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))


func _lower_spear_for_rest(delta: float, target_rotation: Vector3) -> void:
	if not _right_hand_socket:
		return
	var weight := clampf(delta * 7.0, 0.0, 1.0)
	_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, target_rotation.x, weight)
	_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, target_rotation.y, weight)
	_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, target_rotation.z, weight)


func _is_rest_activity_variant(variant: StringName) -> bool:
	return variant == VARIANT_REST_STAND or variant == VARIANT_REST_SIT or variant == VARIANT_REST_LAY


func _smooth_step_unit(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _corpse_random_unit(label: String) -> float:
	var seed := "%s:%s" % [String(name), label]
	return float(absi(hash(seed)) % 10000) / 10000.0


func _basis_from_local_y_axis(y_axis: Vector3, roll: float = 0.0) -> Basis:
	var y := y_axis.normalized()
	if y.length_squared() <= 0.0001:
		y = Vector3.UP
	var helper := Vector3.UP
	if absf(y.dot(helper)) > 0.94:
		helper = Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x, y, z)
	if absf(roll) > 0.0001:
		basis = basis.rotated(y, roll)
	return basis.orthonormalized()


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
