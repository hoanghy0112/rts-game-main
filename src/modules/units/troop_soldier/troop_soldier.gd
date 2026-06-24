extends "res://modules/units/human/human_npc.gd"
class_name TroopSoldierNPC

signal combat_stats_changed(summary: Dictionary)
signal deserted(soldier: Node)

const ACTIVITY_IDLE := &"idle"
const ACTIVITY_REST := &"rest"
const ACTIVITY_TRAINING := &"training"
const ACTIVITY_NONE := &"none"
const CORPSE_SPEAR_SCENE: PackedScene = preload("res://modules/units/human/low_poly_spear.tscn")
const TroopSoldierBehaviorSetScript = preload("res://modules/units/troop_soldier/logic/troop_soldier_behavior_set.gd")
const SPEAR_TIP_LOCAL_Y := 0.526

@export_group("Formation Visual")
@export var formation_visual_only := true
@export_range(0.1, 4.0, 0.05, "or_greater") var formation_walk_animation_scale: float = 1.0

@export_group("Performance")
@export_range(0.0, 1.0, 0.01) var combat_stats_signal_interval: float = 0.25
@export_range(0.0, 0.5, 0.01) var idle_pose_update_interval: float = 0.08
@export_range(0.0, 0.2, 0.005) var active_pose_update_interval: float = 0.033
@export var disable_corpse_processing := true
@export var soldier_perf_monitoring_enabled := false

@export_group("Dependency Injection")
@export var behavior_set: Resource

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
var _combat_focus_target: Node3D
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
var _formation_facing_direction := Vector3.ZERO
var _formation_frame_motion := Vector3.ZERO
var _deserted := false
var _desert_direction := Vector3.ZERO
var _desert_speed_multiplier := 1.0
var _corpse_state_applied := false
var _corpse_roll := PI * 0.5
var _activity_mode: StringName = ACTIVITY_IDLE
var _activity_variant: StringName = ACTIVITY_NONE
var _held_spear: Node3D
var _corpse_spear: Node3D
var _combat_stats_emit_elapsed := 0.0
var _combat_stats_emit_pending := false
var _behavior_dependencies_ready := false
var _perf_last_physics_usec := 0
var _perf_max_physics_usec := 0
var _perf_last_pose_usec := 0
var _perf_max_pose_usec := 0
var _idle_pose_elapsed := 0.0
var _active_pose_elapsed := 0.0
var _stationary_pose_applied := false
var _combat_idle_pose_applied := false
var _logic_sleeping := false
var _has_visual_facing_position := false
var _last_visual_facing_position := Vector3.ZERO


func _ready() -> void:
	_ensure_behavior_dependencies()
	_sync_combat_stats_to_human()
	super._ready()
	_spear_phase_seed = float(absi(hash(name)) % 1000) * 0.001 * TAU
	_idle_pose_elapsed = idle_pose_update_interval * float(absi(hash("%s:pose" % name)) % 1000) / 1000.0
	_active_pose_elapsed = active_pose_update_interval * float(absi(hash("%s:active_pose" % name)) % 1000) / 1000.0
	_held_spear = get_node_or_null("VisualRoot/Armature/RightArm/RightHandSocket/LongSpear/LowPolySpear") as Node3D
	if not _outfit_palette.is_empty():
		_apply_outfit_palette()
	add_to_group(&"troop_soldiers")
	if formation_visual_only:
		_set_state(STATE_IDLE)
		disable_formation_physics()


func _ensure_behavior_dependencies() -> void:
	if _behavior_dependencies_ready and behavior_set:
		return
	if behavior_set:
		if behavior_set.has_method("duplicate_for_runtime"):
			behavior_set = behavior_set.call("duplicate_for_runtime") as Resource
		else:
			behavior_set = behavior_set.duplicate(true)
			if behavior_set.has_method("ensure_defaults"):
				behavior_set.call("ensure_defaults")
	else:
		behavior_set = TroopSoldierBehaviorSetScript.new()
		behavior_set.ensure_defaults()
	_behavior_dependencies_ready = true


func configure_behavior_set(next_behavior_set: Resource) -> void:
	if next_behavior_set and next_behavior_set.has_method("duplicate_for_runtime"):
		behavior_set = next_behavior_set.call("duplicate_for_runtime") as Resource
	elif next_behavior_set:
		behavior_set = next_behavior_set.duplicate(true)
	else:
		behavior_set = null
	_behavior_dependencies_ready = false
	_ensure_behavior_dependencies()


func _physics_process(delta: float) -> void:
	if formation_visual_only:
		step_formation_logic(delta)
		return
	var perf_started := Time.get_ticks_usec() if soldier_perf_monitoring_enabled else 0
	if _combat_stats_emit_pending:
		_update_combat_stats_signal(delta)
	super._physics_process(delta)
	_finish_perf_sample(perf_started)


func step_formation_logic(delta: float) -> void:
	if not formation_visual_only:
		return
	if not is_inside_tree():
		return
	_state_time += delta
	var previous_visual_position := _last_visual_facing_position
	var had_previous_visual_position := _has_visual_facing_position
	var perf_started := Time.get_ticks_usec() if soldier_perf_monitoring_enabled else 0
	if _combat_stats_emit_pending:
		_update_combat_stats_signal(delta)
	_spear_thrust_remaining = maxf(_spear_thrust_remaining - delta, 0.0)
	_hit_reaction_remaining = maxf(_hit_reaction_remaining - delta, 0.0)
	if not is_alive():
		_formation_walking = false
		_formation_attacking = false
		_independent_motion_active = false
		_has_independent_target = false
		_update_monitored_procedural_pose(delta)
		_has_visual_facing_position = false
		_finish_perf_sample(perf_started)
		return
	var moving_independently := _update_independent_motion(delta)
	if _formation_attacking:
		_formation_attack_time += delta
		if is_instance_valid(_combat_target) and _combat_target.is_inside_tree():
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
	_update_formation_visual_pose(delta, moving_independently)
	_apply_actual_visual_motion_facing(previous_visual_position, had_previous_visual_position, moving_independently)
	_last_visual_facing_position = global_position
	_has_visual_facing_position = true
	_finish_perf_sample(perf_started)


func _queue_combat_stats_changed(force: bool = false) -> void:
	if _has_no_combat_stats_listeners():
		_combat_stats_emit_elapsed = 0.0
		_combat_stats_emit_pending = false
		return
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


func _has_no_combat_stats_listeners() -> bool:
	return get_signal_connection_list(&"combat_stats_changed").is_empty()


func _update_combat_stats_signal(delta: float) -> void:
	if not _combat_stats_emit_pending:
		return
	if _has_no_combat_stats_listeners():
		_combat_stats_emit_elapsed = 0.0
		_combat_stats_emit_pending = false
		return
	if combat_stats_signal_interval <= 0.0:
		_queue_combat_stats_changed(true)
		return
	_combat_stats_emit_elapsed += maxf(delta, 0.0)
	if _combat_stats_emit_elapsed >= combat_stats_signal_interval:
		_queue_combat_stats_changed(true)


func set_soldier_perf_monitoring_enabled(enabled: bool) -> void:
	soldier_perf_monitoring_enabled = enabled
	if not enabled:
		_perf_last_physics_usec = 0
		_perf_max_physics_usec = 0
		_perf_last_pose_usec = 0
		_perf_max_pose_usec = 0


func reset_perf_counters() -> void:
	_perf_last_physics_usec = 0
	_perf_max_physics_usec = 0
	_perf_last_pose_usec = 0
	_perf_max_pose_usec = 0


func get_perf_summary() -> Dictionary:
	return {
		"soldier_perf_monitoring_enabled": soldier_perf_monitoring_enabled,
		"perf_last_physics_usec": _perf_last_physics_usec,
		"perf_max_physics_usec": _perf_max_physics_usec,
		"perf_last_pose_usec": _perf_last_pose_usec,
		"perf_max_pose_usec": _perf_max_pose_usec,
	}


func can_logic_sleep() -> bool:
	var combat_idle := _formation_attacking and _spear_thrust_remaining <= 0.0 and _hit_reaction_remaining <= 0.0
	return (
		formation_visual_only
		and is_alive()
		and not _deserted
		and not _formation_walking
		and (not _formation_attacking or combat_idle)
		and (not _formation_attacking or _combat_idle_pose_applied)
		and not _independent_motion_active
		and not _has_independent_target
		and _spear_thrust_remaining <= 0.0
		and _hit_reaction_remaining <= 0.0
	)


func set_logic_sleeping(enabled: bool) -> void:
	if not enabled:
		_wake_logic()
		return
	if _logic_sleeping:
		return
	if not can_logic_sleep():
		return
	if _combat_stats_emit_pending:
		_queue_combat_stats_changed(true)
	_logic_sleeping = true
	if not formation_visual_only:
		set_physics_process(false)


func is_logic_sleeping() -> bool:
	return _logic_sleeping


func _wake_logic() -> void:
	if not _logic_sleeping:
		return
	_logic_sleeping = false
	if not formation_visual_only:
		set_physics_process(true)


func disable_formation_physics() -> void:
	velocity = Vector3.ZERO
	_disable_collision_recursive(self)
	set_physics_process(false)


func strip_formation_runtime_helpers() -> void:
	if not formation_visual_only:
		return
	for path: NodePath in [
		^"CollisionShape3D",
		^"NavigationAgent3D",
		^"AnimationPlayer",
		^"AnimationTree",
	]:
		var node := get_node_or_null(path)
		if node:
			node.get_parent().remove_child(node)
			node.free()
	_animation_player = null
	_animation_tree = null


func _update_monitored_procedural_pose(delta: float) -> void:
	if not soldier_perf_monitoring_enabled:
		_update_procedural_pose(delta)
		return
	var started := Time.get_ticks_usec()
	_update_procedural_pose(delta)
	_perf_last_pose_usec = Time.get_ticks_usec() - started
	_perf_max_pose_usec = maxi(_perf_max_pose_usec, _perf_last_pose_usec)


func _update_formation_visual_pose(delta: float, moving_independently: bool) -> void:
	var needs_full_rate := (
		_formation_walking
		or moving_independently
		or _formation_attacking
		or _spear_thrust_remaining > 0.0
		or _hit_reaction_remaining > 0.0
	)
	if needs_full_rate:
		_stationary_pose_applied = false
		var force_full_rate := _spear_thrust_remaining > 0.0 or _hit_reaction_remaining > 0.0 or active_pose_update_interval <= 0.0
		if force_full_rate:
			_active_pose_elapsed = 0.0
			_idle_pose_elapsed = 0.0
			_update_monitored_procedural_pose(delta * formation_walk_animation_scale * _formation_speed_scale)
			return
		_active_pose_elapsed += delta
		if _active_pose_elapsed < active_pose_update_interval:
			if soldier_perf_monitoring_enabled:
				_perf_last_pose_usec = 0
			return
		var pose_delta := _active_pose_elapsed * formation_walk_animation_scale * _formation_speed_scale
		_active_pose_elapsed = 0.0
		_idle_pose_elapsed = 0.0
		_update_monitored_procedural_pose(pose_delta)
		return

	_active_pose_elapsed = 0.0
	if not _stationary_pose_applied:
		_update_monitored_procedural_pose(1.0)
	_idle_pose_elapsed = 0.0
	if soldier_perf_monitoring_enabled:
		_perf_last_pose_usec = 0


func _apply_actual_visual_motion_facing(previous_position: Vector3, has_previous_position: bool, moving_independently: bool) -> void:
	if not has_previous_position:
		return
	if is_instance_valid(_combat_focus_target):
		return
	if not (_formation_walking or moving_independently):
		return
	var displacement := global_position - previous_position
	displacement.y = 0.0
	if displacement.length_squared() <= 0.000225:
		return
	rotation.y = atan2(-displacement.x, -displacement.z)


func _finish_perf_sample(perf_started: int) -> void:
	if not soldier_perf_monitoring_enabled:
		return
	_perf_last_physics_usec = Time.get_ticks_usec() - perf_started
	_perf_max_physics_usec = maxi(_perf_max_physics_usec, _perf_last_physics_usec)


func set_formation_walking(active: bool, speed_mps: float = 1.0) -> void:
	_ensure_behavior_dependencies()
	behavior_set.walk_logic.apply_formation_walking(self, active, speed_mps)


func is_formation_walking() -> bool:
	return _formation_walking


func set_formation_facing_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		_formation_facing_direction = Vector3.ZERO
		return
	_formation_facing_direction = direction.normalized()


func set_combat_focus_target(target: Node3D = null) -> void:
	_combat_focus_target = target if is_instance_valid(target) else null


func set_formation_frame_motion(motion: Vector3) -> void:
	motion.y = 0.0
	_formation_frame_motion = motion


func clear_formation_facing_direction() -> void:
	_formation_facing_direction = Vector3.ZERO
	_formation_frame_motion = Vector3.ZERO


func set_move_target(_world_position: Vector3, run: bool = false) -> void:
	_ensure_behavior_dependencies()
	if run:
		behavior_set.run_logic.begin_direct_move(self, _world_position, true)
	else:
		behavior_set.walk_logic.begin_direct_move(self, _world_position, false)


func clear_move_target() -> void:
	_ensure_behavior_dependencies()
	behavior_set.walk_logic.clear_direct_move(self)


func _call_human_set_move_target(world_position: Vector3, run: bool = false) -> void:
	super.set_move_target(world_position, run)


func _call_human_clear_move_target() -> void:
	super.clear_move_target()


func configure_combat_stats(
	strength_value: float,
	damage_value: float,
	morale_value: float,
	endurance_value: float,
	max_endurance_value: float,
	run_speed_value: float = -1.0
) -> void:
	_wake_logic()
	var previous_max_strength := maxf(max_strength, 1.0)
	var previous_health := get_health()
	var health_ratio := clampf(previous_health / previous_max_strength, 0.0, 1.0)
	var was_full_strength := previous_health <= 0.0 or previous_health >= previous_max_strength - 0.001
	max_strength = maxf(strength_value, 1.0)
	damage = maxf(damage_value, 0.1)
	morale = clampf(morale_value, 0.0, 100.0)
	max_endurance = maxf(max_endurance_value, 1.0)
	endurance = clampf(endurance_value, 0.0, max_endurance)
	if run_speed_value > 0.0:
		run_speed = maxf(run_speed_value, 0.1)
	_health = max_strength if was_full_strength else clampf(max_strength * health_ratio, 0.0, max_strength)
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
	_ensure_behavior_dependencies()
	behavior_set.walk_logic.follow_formation_path(
		self,
		path_points,
		slot_offset,
		speed_mps,
		arrival_radius_m,
		initial_path_index,
		final_yaw_active,
		final_yaw
	)


func set_independent_move_target(world_position: Vector3, speed_mps: float, arrival_radius_m: float = 0.24) -> void:
	_ensure_behavior_dependencies()
	behavior_set.walk_logic.set_independent_move_target(self, world_position, speed_mps, arrival_radius_m)


func clear_independent_motion() -> void:
	_ensure_behavior_dependencies()
	behavior_set.walk_logic.clear_independent_motion(self)


func has_independent_motion() -> bool:
	return _independent_motion_active


func get_independent_motion_debug_summary() -> Dictionary:
	return {
		"active": _independent_motion_active,
		"speed": _independent_speed,
		"arrival_radius": _independent_arrival_radius,
		"has_target": _has_independent_target,
		"target": _independent_target,
		"path_point_count": _independent_path_points.size(),
		"path_index": _independent_path_index,
	}


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
	_activity_variant = ACTIVITY_NONE


func get_activity_mode() -> StringName:
	return _activity_mode


func get_activity_variant() -> StringName:
	return _activity_variant


func force_activity_variant_for_test(_variant: StringName, _duration: float = 60.0) -> void:
	_activity_variant = ACTIVITY_NONE


func set_formation_attacking(active: bool, target: Node3D = null) -> void:
	set_independent_combat(active, target, true)


func set_independent_combat(active: bool, target: Node3D = null, in_range: bool = false) -> void:
	_ensure_behavior_dependencies()
	behavior_set.fight_logic.set_independent_combat(self, active, target, in_range)


func is_formation_attacking() -> bool:
	return _formation_attacking


func has_combat_target() -> bool:
	return is_instance_valid(_combat_target) and _combat_target.is_inside_tree()


func get_combat_target() -> Node3D:
	return _combat_target if is_instance_valid(_combat_target) and _combat_target.is_inside_tree() else null


func trigger_spear_thrust(target: Node3D = null, duration: float = -1.0) -> void:
	_ensure_behavior_dependencies()
	behavior_set.fight_logic.trigger_spear_thrust(self, target, duration)


func is_spear_thrust_active() -> bool:
	_ensure_behavior_dependencies()
	return behavior_set.fight_logic.is_spear_thrust_active(self)


func needs_full_rate_combat_visual() -> bool:
	_ensure_behavior_dependencies()
	return behavior_set.fight_logic.needs_full_rate_combat_visual(self)


func apply_strength_damage(amount: float, reason: StringName = &"combat") -> void:
	if amount > 0.0:
		_wake_logic()
	if amount > 0.0 and is_alive():
		_hit_reaction_duration = 0.32
		_hit_reaction_remaining = _hit_reaction_duration
	var was_alive := is_alive()
	var previous_health := get_health()
	apply_damage(amount, reason)
	if not is_alive():
		_enter_inactive_dead_state()
	if not is_equal_approx(previous_health, get_health()) or was_alive != is_alive():
		_queue_combat_stats_changed(not is_alive())


func restore_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	_wake_logic()
	var previous := endurance
	endurance = clampf(endurance + amount, 0.0, max_endurance)
	if is_equal_approx(previous, endurance):
		return
	_queue_combat_stats_changed()


func reduce_endurance(amount: float) -> void:
	if amount <= 0.0 or not is_combat_active():
		return
	_wake_logic()
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
	_wake_logic()
	morale = clampf(morale + amount, 0.0, 100.0)
	_queue_combat_stats_changed()


func train_stats(strength_amount: float, damage_amount: float, morale_amount: float, endurance_max_amount: float) -> void:
	if not is_combat_active():
		return
	_wake_logic()
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
	_wake_logic()
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
	_wake_logic()
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
	var should_wake_for_visual := false

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
		_wake_logic()
		var reason := StringName(result.get("death_reason", &"starvation"))
		kill(reason)
		return

	if not is_equal_approx(next_health, previous_health):
		var damage_reason := StringName(result.get("death_reason", &""))
		if next_health < previous_health and damage_reason != &"starvation":
			should_wake_for_visual = true
			_hit_reaction_duration = 0.32
			_hit_reaction_remaining = _hit_reaction_duration
		_health = next_health
		health_changed.emit(_health, max_health)
		changed = true

	if should_wake_for_visual:
		_wake_logic()
	if changed or previous_alive != is_alive():
		_queue_combat_stats_changed(_logic_sleeping or previous_alive != is_alive())


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
	_wake_logic()
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
	_wake_logic()
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
	_enter_inactive_dead_state()
	_queue_combat_stats_changed(true)


func _update_procedural_pose(delta: float) -> void:
	if not formation_visual_only:
		super._update_procedural_pose(delta)
		return
	# Formation soldiers fully drive their own pose. Running the base human pose
	# first writes the same limb transforms twice for every soldier.
	if not is_alive():
		return
	if _formation_walking:
		_combat_idle_pose_applied = false
		_apply_walk_pose(delta)
		return
	if not _formation_attacking and _hit_reaction_remaining <= 0.0:
		if not _stationary_pose_applied:
			_stationary_pose_applied = true
			_apply_static_stationary_pose(maxf(delta, 1.0))
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
		_model_root.position.y = sin(_state_time * 1.4) * 0.025
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
	if _formation_attacking and _spear_thrust_remaining <= 0.0 and _hit_reaction_remaining <= 0.0:
		_combat_idle_pose_applied = true


func _apply_walk_pose(delta: float) -> void:
	var speed_scale := clampf(_formation_speed_scale, 0.7, 2.4)
	var phase := _state_time * lerpf(5.2, 8.4, clampf((speed_scale - 0.7) / 1.7, 0.0, 1.0)) + _spear_phase_seed
	var stride := sin(phase)
	var counter_stride := -stride
	var lift := absf(sin(phase))
	var weight := clampf(delta * 14.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, -0.035, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, stride * 0.018, weight)
		_model_root.position.y = lerpf(_model_root.position.y, lift * 0.045, weight)
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, -0.045 + lift * 0.025, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, stride * 0.035, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, counter_stride * 0.018, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.14 + counter_stride * 0.24, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, -0.18 + stride * 0.22, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, stride * 0.34, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, counter_stride * 0.34, weight)
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, -0.03 + lift * 0.05, weight)
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, stride * 0.025, weight)
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, -0.045, weight)


func _update_activity_state(_delta: float) -> void:
	_activity_variant = ACTIVITY_NONE


func _apply_activity_pose(delta: float) -> void:
	_apply_static_stationary_pose(delta)


func _apply_static_stationary_pose(delta: float) -> void:
	var weight := clampf(delta * 10.0, 0.0, 1.0)
	if _model_root:
		_model_root.rotation.x = lerp_angle(_model_root.rotation.x, 0.0, weight)
		_model_root.rotation.z = lerp_angle(_model_root.rotation.z, 0.0, weight)
		_model_root.position.y = 0.0
	if _torso:
		_torso.rotation.x = lerp_angle(_torso.rotation.x, 0.0, weight)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, 0.0, weight)
		_torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, weight)
	if _right_arm:
		_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, -0.10, weight)
	if _left_arm:
		_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, -0.06, weight)
	if _left_leg:
		_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, 0.0, weight)
	if _right_leg:
		_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, 0.0, weight)
	if _right_hand_socket:
		_right_hand_socket.rotation.x = lerp_angle(_right_hand_socket.rotation.x, 0.02, weight)
		_right_hand_socket.rotation.y = lerp_angle(_right_hand_socket.rotation.y, 0.0, weight)
		_right_hand_socket.rotation.z = lerp_angle(_right_hand_socket.rotation.z, 0.0, weight)


func _update_independent_motion(delta: float) -> bool:
	_ensure_behavior_dependencies()
	return behavior_set.walk_logic.update_independent_motion(self, delta)


func _get_current_independent_target() -> Variant:
	_ensure_behavior_dependencies()
	return behavior_set.walk_logic.get_current_independent_target(self)


func _advance_completed_path_targets() -> bool:
	_ensure_behavior_dependencies()
	return behavior_set.walk_logic.advance_completed_path_targets(self)


func _get_offset_path_point(path_index: int) -> Vector3:
	_ensure_behavior_dependencies()
	return behavior_set.walk_logic.get_offset_path_point(self, path_index)


func _enter_corpse_state() -> void:
	if _corpse_state_applied:
		visible = true
		_logic_sleeping = false
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
		_disable_collision_recursive(self)
		_apply_corpse_pose()
		if disable_corpse_processing:
			set_physics_process(false)
		return
	_corpse_state_applied = true
	_corpse_roll = PI * 0.5
	if absi(hash(name)) % 2 == 0:
		_corpse_roll = -PI * 0.5
	visible = true
	_logic_sleeping = false
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


func _enter_inactive_dead_state() -> void:
	_corpse_state_applied = true
	visible = false
	_logic_sleeping = false
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
	if is_instance_valid(_held_spear):
		_held_spear.visible = false
	if self is CollisionObject3D:
		var collision := self as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	_disable_collision_recursive(self)
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
