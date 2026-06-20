extends "res://modules/units/human/human_npc.gd"
class_name TroopSoldierNPC

@export_group("Formation Visual")
@export var formation_visual_only := true
@export_range(0.1, 4.0, 0.05, "or_greater") var formation_walk_animation_scale: float = 1.0

var _formation_walking := false
var _formation_speed_scale := 1.0


func _ready() -> void:
	super._ready()
	add_to_group(&"troop_soldiers")
	if formation_visual_only:
		_set_state(STATE_IDLE)


func _physics_process(delta: float) -> void:
	if not formation_visual_only:
		super._physics_process(delta)
		return

	_state_time += delta
	_set_state(STATE_WALK if _formation_walking else STATE_IDLE)
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
