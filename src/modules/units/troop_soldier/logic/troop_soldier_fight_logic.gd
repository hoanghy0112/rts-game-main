extends Resource
class_name TroopSoldierFightLogic

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_TOOL_ACTION := &"tool_action"


func set_independent_combat(soldier, active: bool, target: Node3D = null, in_range: bool = false) -> void:
	var next_attacking: bool = active and soldier.is_combat_active()
	var next_target: Node3D = target if next_attacking and is_instance_valid(target) else null
	var next_in_range: bool = next_attacking and in_range
	if soldier._formation_attacking == next_attacking and soldier._combat_target == next_target and soldier._combat_in_range == next_in_range:
		return
	if next_attacking or soldier._logic_sleeping:
		soldier._wake_logic()
	soldier._formation_attacking = next_attacking
	soldier._combat_idle_pose_applied = false
	if soldier._formation_attacking and soldier._formation_attack_time <= 0.0:
		soldier._formation_attack_time = float(absi(hash(soldier.name)) % 1000) * 0.001 * maxf(float(soldier.attack_cooldown), 0.05)
	soldier._combat_target = next_target
	soldier._combat_in_range = next_in_range
	soldier._combat_focus_target = next_target
	if not soldier._formation_attacking:
		soldier._spear_thrust_remaining = 0.0
		soldier._spear_thrust_duration = 0.0
	else:
		soldier._stationary_pose_applied = false
		soldier._combat_idle_pose_applied = false
	if is_instance_valid(soldier._combat_target) and soldier._combat_target.is_inside_tree():
		var to_target: Vector3 = soldier._combat_target.global_position - soldier.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			soldier._face_direction(to_target.normalized(), 1.0)
	if soldier.formation_visual_only:
		soldier._set_state(STATE_TOOL_ACTION if soldier._formation_attacking else (STATE_WALK if soldier._formation_walking else STATE_IDLE))


func trigger_spear_thrust(soldier, target: Node3D = null, duration: float = -1.0) -> void:
	if not soldier.is_combat_active():
		return
	soldier._wake_logic()
	if target:
		soldier._combat_target = target
		if target.is_inside_tree():
			var to_target: Vector3 = target.global_position - soldier.global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.0001:
				soldier._face_direction(to_target.normalized(), 1.0)
	soldier._spear_thrust_duration = maxf(duration if duration > 0.0 else float(soldier.attack_cooldown) * 0.72, 0.18)
	soldier._spear_thrust_remaining = soldier._spear_thrust_duration
	soldier._formation_attacking = true
	soldier._stationary_pose_applied = false
	soldier._combat_idle_pose_applied = false
	if soldier.formation_visual_only:
		soldier._timed_state_duration = soldier._spear_thrust_duration
		soldier._timed_state_remaining = soldier._spear_thrust_remaining
		soldier._set_state(STATE_TOOL_ACTION)


func is_spear_thrust_active(soldier) -> bool:
	return soldier._spear_thrust_remaining > 0.0


func needs_full_rate_combat_visual(soldier) -> bool:
	return (
		soldier._independent_motion_active
		or soldier._spear_thrust_remaining > 0.0
		or soldier._hit_reaction_remaining > 0.0
	)
