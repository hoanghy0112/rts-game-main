extends Node3D
class_name Troop

signal selected_changed(selected: bool)
signal state_changed(state: StringName)
signal destination_changed(summary: Dictionary)
signal logistics_changed(summary: Dictionary)
signal mode_changed(summary: Dictionary)
signal combat_changed(summary: Dictionary)

const DEFAULT_SOLDIER_SCENE: PackedScene = preload("res://modules/units/troop_soldier/troop_soldier.tscn")
const TroopRouteVisualScript = preload("res://modules/troops/troop_route_visual.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")

const STATE_IDLE := &"idle"
const STATE_MOVING := &"moving"
const STATE_BLOCKED := &"blocked"
const STATE_FIGHTING := &"fighting"

const MODE_REST := &"rest"
const MODE_TRAINING := &"training"
const MODE_DEFENSIVE := &"defensive"
const MODE_ATTACK := &"attack"

const MOVEMENT_WALKING := &"walking"
const MOVEMENT_RUNNING := &"running"

const TEAM_PLAYER := &"player"
const TEAM_ENEMY := &"enemy"

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"
const SELECTABLE_CAMP_TYPE := &"camp"

const SOLDIER_CONTAINER_NAME := "Soldiers"
const RING_NODE_NAME := "TroopRing"
const SELECTION_PROXY_NAME := "TroopClickProxy"
const ROUTE_VISUAL_NAME := "TroopRouteVisual"
const CARRIER_CONTAINER_NAME := "CarrierTasks"
const CAMP_NODE_NAME := "TroopCamp"

const RESOURCE_FOOD := &"food"
const RESOURCE_WOOD := &"wood"
const RESOURCE_COW := &"cow"
const TASK_TO_TARGET := &"to_target"
const TASK_WORKING := &"working"
const TASK_RETURNING := &"returning"

@export_group("Identity")
@export var troop_id: StringName = &"troop_01"
@export var display_name := "Troop"
@export var team_id: StringName = TEAM_PLAYER
@export var controllable := true

@export_group("Mode")
@export_enum("rest", "training", "defensive", "attack") var troop_mode := "defensive":
	set(value):
		troop_mode = String(_normalize_troop_mode(value))
		if is_inside_tree():
			_on_mode_updated()
@export_enum("walking", "running") var movement_mode := "walking":
	set(value):
		movement_mode = String(_normalize_movement_mode(value))
		if is_inside_tree():
			_on_mode_updated()

@export_group("Formation")
@export_range(2, 256, 1, "or_greater") var soldier_count: int = 12:
	set(value):
		soldier_count = maxi(value, 2)
		if is_inside_tree():
			rebuild_formation()
@export var soldier_scene: PackedScene = DEFAULT_SOLDIER_SCENE:
	set(value):
		soldier_scene = value
		if is_inside_tree():
			rebuild_formation()
@export_range(1, 32, 1, "or_greater") var formation_columns: int = 4:
	set(value):
		formation_columns = maxi(value, 1)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.2, 16.0, 0.05, "or_greater") var formation_spacing: float = 1.45:
	set(value):
		formation_spacing = maxf(value, 0.2)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.1, 8.0, 0.05, "or_greater") var soldier_scale: float = 1.0:
	set(value):
		soldier_scale = maxf(value, 0.1)
		if is_inside_tree():
			rebuild_formation()

@export_group("Soldier Outfit")
@export var soldier_robe_color: Color = Color(0.34, 0.52, 0.54, 1.0):
	set(value):
		soldier_robe_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_robe_shadow_color: Color = Color(0.08, 0.24, 0.28, 1.0):
	set(value):
		soldier_robe_shadow_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_trim_color: Color = Color(0.76, 0.56, 0.38, 1.0):
	set(value):
		soldier_trim_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_pants_color: Color = Color(0.78, 0.34, 0.18, 1.0):
	set(value):
		soldier_pants_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_wrap_color: Color = Color(0.86, 0.82, 0.74, 1.0):
	set(value):
		soldier_wrap_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_hat_color: Color = Color(0.05, 0.09, 0.13, 1.0):
	set(value):
		soldier_hat_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_accent_color: Color = Color(0.7, 0.12, 0.08, 1.0):
	set(value):
		soldier_accent_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()

@export_group("Flags")
@export var team_flag_color: Color = Color(0.1, 0.28, 0.82, 1.0):
	set(value):
		team_flag_color = value
		if is_inside_tree():
			rebuild_formation()
@export var troop_flag_color: Color = Color(0.78, 0.1, 0.08, 1.0):
	set(value):
		troop_flag_color = value
		if is_inside_tree():
			rebuild_formation()
@export var carried_flag_mount_offset: Vector3 = Vector3(0.18, 0.22, 0.0):
	set(value):
		carried_flag_mount_offset = value
		if is_inside_tree():
			rebuild_formation()
@export_range(0.5, 8.0, 0.05, "or_greater") var carried_flag_pole_height: float = 2.45:
	set(value):
		carried_flag_pole_height = maxf(value, 0.5)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.01, 0.5, 0.005, "or_greater") var carried_flag_pole_radius: float = 0.04:
	set(value):
		carried_flag_pole_radius = maxf(value, 0.01)
		if is_inside_tree():
			rebuild_formation()
@export var carried_flag_banner_size: Vector2 = Vector2(1.12, 0.66):
	set(value):
		carried_flag_banner_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		if is_inside_tree():
			rebuild_formation()
@export_range(-45.0, 45.0, 0.5) var carried_flag_roll_degrees: float = -8.0:
	set(value):
		carried_flag_roll_degrees = value
		if is_inside_tree():
			rebuild_formation()

@export_group("Visibility")
@export_range(0.0, 128.0, 0.1, "or_greater") var ring_radius: float = 0.0:
	set(value):
		ring_radius = maxf(value, 0.0)
		if is_inside_tree():
			_rebuild_ring()
			_rebuild_selection_proxy()
@export_range(0.01, 16.0, 0.01, "or_greater") var ring_width: float = 0.16:
	set(value):
		ring_width = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_ring()
@export_range(1.0, 12.0, 0.1, "or_greater") var ring_screen_width_px: float = 2.25:
	set(value):
		ring_screen_width_px = maxf(value, 1.0)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.01, 2.0, 0.01, "or_greater") var ring_min_world_width: float = 0.04:
	set(value):
		ring_min_world_width = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.05, 12.0, 0.05, "or_greater") var ring_max_world_width: float = 4.0:
	set(value):
		ring_max_world_width = maxf(value, 0.05)
		if is_inside_tree():
			_rebuild_ring()
@export_range(0.0, 8.0, 0.01, "or_greater") var ring_surface_offset: float = 0.42
@export var ring_color: Color = Color(0.18, 0.82, 0.95, 0.58):
	set(value):
		ring_color = value
		if is_inside_tree():
			_update_ring_material()
@export var selected_ring_color: Color = Color(1.0, 0.82, 0.28, 0.78):
	set(value):
		selected_ring_color = value
		if is_inside_tree():
			_update_ring_material()

@export_group("Selection")
@export_flags_3d_physics var selection_collision_layer: int = 1 << 5:
	set(value):
		selection_collision_layer = value
		if is_inside_tree():
			_rebuild_selection_proxy()

@export_group("Movement")
@export var movement_map: Resource
@export_file("*.res", "*.tres") var movement_map_path := ""
@export_node_path("Node3D") var terrain_path: NodePath
@export_node_path("Node") var time_system_path: NodePath
@export_range(0.1, 40.0, 0.1, "or_greater") var movement_speed_mps: float = 4.5
@export_range(1.0, 4.0, 0.05, "or_greater") var running_speed_multiplier: float = 1.65
@export_range(0.1, 32.0, 0.1, "or_greater") var arrival_radius: float = 1.25
@export_range(0, 64, 1, "or_greater") var nearest_walkable_search_radius_cells: int = 12
@export var path_smoothing_enabled := true
@export_range(0.0, 3.0, 0.05, "or_greater") var path_corner_radius_cells: float = 1.35
@export_range(0, 16, 1, "or_greater") var path_corner_samples: int = 8
@export_range(0.0, 12.0, 0.05, "or_greater") var route_steering_lookahead_m: float = 3.0
@export_range(5.0, 360.0, 1.0, "or_greater") var formation_turn_rate_degrees: float = 85.0
@export_range(5.0, 180.0, 1.0, "or_greater") var formation_turn_slowdown_angle_degrees: float = 72.0
@export_range(0.05, 1.0, 0.01) var formation_min_turn_speed_multiplier: float = 0.32
@export_range(0.5, 24.0, 0.1, "or_greater") var formation_slot_follow_speed: float = 5.5
@export_range(0.0, 4.0, 0.05, "or_greater") var formation_turn_inner_lag: float = 1.15
@export_range(0.0, 1.0, 0.01, "or_greater") var formation_natural_unevenness: float = 0.16:
	set(value):
		formation_natural_unevenness = maxf(value, 0.0)
		if is_inside_tree():
			_refresh_formation_slot_metas()
@export_range(0.0, 3.0, 0.05, "or_greater") var formation_turn_scatter: float = 0.0:
	set(value):
		formation_turn_scatter = maxf(value, 0.0)
		if is_inside_tree():
			_refresh_formation_slot_metas()
@export_range(0.0, 4.0, 0.05, "or_greater") var formation_walkout_stagger: float = 0.75
@export_range(0.05, 2.0, 0.05, "or_greater") var route_refresh_interval: float = 0.25

@export_group("Logistics")
@export_range(1.0, 1000.0, 1.0, "or_greater") var soldier_carry_capacity_kg: float = 20.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var cargo_trolley_capacity_kg: float = 200.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var cow_trolley_capacity_kg: float = 300.0
@export_range(1, 16, 1, "or_greater") var cargo_trolley_required_soldiers: int = 2
@export_range(0.0, 10000.0, 1.0, "or_greater") var cargo_trolley_wood_cost_kg: float = 40.0
@export_range(0.0, 60.0, 0.1, "or_greater") var cargo_trolley_craft_seconds: float = 5.0
@export_range(0.1, 8.0, 0.05, "or_greater") var cargo_trolley_visual_scale: float = 1.0:
	set(value):
		cargo_trolley_visual_scale = maxf(value, 0.1)
		if is_inside_tree():
			_rebuild_cargo_trolley_visuals()
@export_range(1, 256, 1, "or_greater") var camp_soldiers_per_living_hut: int = 20:
	set(value):
		camp_soldiers_per_living_hut = maxi(value, 1)
		if is_inside_tree():
			_emit_logistics_changed()
			if _camp_established:
				_rebuild_camp_visual()
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_living_hut_wood_cost_kg: float = 100.0:
	set(value):
		camp_living_hut_wood_cost_kg = maxf(value, 0.0)
		if is_inside_tree():
			_emit_logistics_changed()
@export_range(0.1, 8.0, 0.05, "or_greater") var camp_building_scale: float = 3.0:
	set(value):
		camp_building_scale = maxf(value, 0.1)
		if is_inside_tree() and _camp_established:
			_rebuild_camp_visual()
@export_range(1.0, 256.0, 0.5, "or_greater") var camp_pack_range_m: float = 18.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_food_kg: float = 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_wood_kg: float = 0.0
@export_range(0.1, 20.0, 0.1, "or_greater") var carrier_speed_mps: float = 3.2
@export_range(0.05, 8.0, 0.05, "or_greater") var carrier_arrival_radius: float = 0.55
@export_range(0.0, 10.0, 0.05, "or_greater") var carrier_work_seconds: float = 1.0
@export_range(0.2, 8.0, 0.05, "or_greater") var carrier_formation_spacing: float = 1.25
@export_range(0.5, 8.0, 0.05, "or_greater") var carrier_resource_icon_height: float = 2.45
@export_range(0.05, 2.0, 0.05, "or_greater") var carrier_resource_icon_size: float = 0.34
@export_range(1.0, 32.0, 0.1, "or_greater") var carrier_turn_responsiveness: float = 14.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var carried_food_kg: float = 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var carried_wood_kg: float = 0.0
@export_range(0, 64, 1, "or_greater") var cargo_trolley_count: int = 0
@export_range(0, 64, 1, "or_greater") var cow_count: int = 0

@export_group("Soldier Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var base_soldier_strength: float = 40.0
@export_range(0.0, 500.0, 1.0, "or_greater") var soldier_strength_variance: float = 6.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var base_soldier_damage: float = 8.0
@export_range(0.0, 500.0, 0.1, "or_greater") var soldier_damage_variance: float = 1.2
@export_range(0.0, 100.0, 0.1) var base_soldier_morale: float = 72.0
@export_range(0.0, 100.0, 0.1) var soldier_morale_variance: float = 10.0
@export_range(1.0, 1000.0, 0.1, "or_greater") var base_soldier_endurance: float = 80.0
@export_range(0.0, 500.0, 0.1, "or_greater") var soldier_endurance_variance: float = 8.0
@export var combat_seed: int = 24101

@export_group("Combat")
@export_range(1.0, 256.0, 0.5, "or_greater") var detection_range_m: float = 34.0
@export_range(1.0, 256.0, 0.5, "or_greater") var defensive_engagement_range_m: float = 18.0
@export_range(1.0, 256.0, 0.5, "or_greater") var combat_range_m: float = 18.0
@export_range(0.05, 10.0, 0.05, "or_greater") var combat_scan_interval: float = 0.35
@export_range(0.05, 10.0, 0.05, "or_greater") var attack_interval: float = 1.1
@export_range(0.4, 12.0, 0.05, "or_greater") var combat_spear_range_m: float = 2.35
@export_range(0.15, 4.0, 0.05, "or_greater") var soldier_personal_space_radius: float = 0.72
@export_range(0.15, 4.0, 0.05, "or_greater") var enemy_personal_space_radius: float = 0.82
@export_range(0.2, 6.0, 0.05, "or_greater") var combat_frontline_width_per_soldier: float = 1.1
@export_range(0.1, 24.0, 0.1, "or_greater") var combat_slot_follow_speed: float = 4.4
@export_range(0.0, 12.0, 0.05, "or_greater") var combat_separation_strength: float = 6.2
@export_range(0.05, 10.0, 0.05, "or_greater") var chase_repath_interval: float = 0.75
@export_range(0.0, 10.0, 0.05, "or_greater") var rest_engagement_delay: float = 2.5
@export_range(0.0, 10.0, 0.05, "or_greater") var training_engagement_delay: float = 2.0
@export_range(0.0, 10.0, 0.05, "or_greater") var defensive_engagement_delay: float = 0.25
@export_range(0.0, 10.0, 0.05, "or_greater") var attack_engagement_delay: float = 0.1
@export_range(0.0, 100.0, 0.05, "or_greater") var walk_endurance_loss_per_second: float = 0.24
@export_range(0.0, 100.0, 0.05, "or_greater") var run_endurance_loss_per_second: float = 0.9
@export_range(0.0, 100.0, 0.05, "or_greater") var fight_endurance_loss_per_second: float = 0.7
@export_range(0.0, 100.0, 0.05, "or_greater") var attack_mode_endurance_loss_per_second: float = 0.45
@export_range(0.0, 100.0, 0.05, "or_greater") var rest_endurance_recovery_per_second: float = 7.5
@export_range(0.0, 100.0, 0.05, "or_greater") var defensive_endurance_recovery_per_second: float = 2.2
@export_range(0.0, 100.0, 0.05, "or_greater") var training_endurance_loss_per_second: float = 0.35
@export_range(0.0, 20.0, 0.01, "or_greater") var training_strength_gain_per_second: float = 0.025
@export_range(0.0, 20.0, 0.01, "or_greater") var training_damage_gain_per_second: float = 0.01
@export_range(0.0, 20.0, 0.01, "or_greater") var training_morale_gain_per_second: float = 0.025
@export_range(0.0, 20.0, 0.01, "or_greater") var training_max_endurance_gain_per_second: float = 0.035
@export_range(0.0, 1.0, 0.01) var low_endurance_ratio: float = 0.25
@export_range(0.0, 60.0, 0.1, "or_greater") var low_endurance_morale_delay: float = 4.0
@export_range(0.0, 100.0, 0.05, "or_greater") var low_endurance_morale_loss_per_second: float = 0.25
@export_range(0.0, 100.0, 0.05, "or_greater") var outnumbered_morale_loss_per_second: float = 0.35
@export_range(0.0, 100.0, 0.05, "or_greater") var food_shortage_morale_loss_per_second: float = 0.35
@export_range(0.0, 100.0, 0.05, "or_greater") var food_shortage_endurance_loss_per_second: float = 0.7
@export_range(0.0, 100.0, 0.1) var desertion_morale_threshold: float = 24.0
@export_range(0.0, 1.0, 0.001) var desertion_chance_per_second: float = 0.025
@export_range(0.0, 20.0, 0.01, "or_greater") var food_kg_per_soldier_per_day: float = 1.2

@export_group("Route Visual")
@export_range(0.01, 8.0, 0.01, "or_greater") var route_line_width: float = 0.16:
	set(value):
		route_line_width = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(1.0, 12.0, 0.1, "or_greater") var route_line_screen_width_px: float = 2.0:
	set(value):
		route_line_screen_width_px = maxf(value, 1.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 2.0, 0.01, "or_greater") var route_line_min_world_width: float = 0.04:
	set(value):
		route_line_min_world_width = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.05, 12.0, 0.05, "or_greater") var route_line_max_world_width: float = 4.0:
	set(value):
		route_line_max_world_width = maxf(value, 0.05)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 2.0, 0.01, "or_greater") var route_line_height: float = 0.035:
	set(value):
		route_line_height = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.25, 32.0, 0.25, "or_greater") var route_dash_length: float = 5.0:
	set(value):
		route_dash_length = maxf(value, 0.25)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.0, 32.0, 0.25, "or_greater") var route_dash_gap: float = 3.0:
	set(value):
		route_dash_gap = maxf(value, 0.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.0, 8.0, 0.01, "or_greater") var route_surface_offset: float = 0.35:
	set(value):
		route_surface_offset = maxf(value, 0.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(1.0, 12.0, 0.05, "or_greater") var destination_flag_pole_height: float = 4.2:
	set(value):
		destination_flag_pole_height = maxf(value, 1.0)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.01, 0.5, 0.005, "or_greater") var destination_flag_pole_radius: float = 0.08:
	set(value):
		destination_flag_pole_radius = maxf(value, 0.01)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export var destination_flag_banner_size: Vector2 = Vector2(1.65, 0.94):
	set(value):
		destination_flag_banner_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()

var _soldier_container: Node3D
var _ring_instance: MeshInstance3D
var _selection_proxy: StaticBody3D
var _route_visual: Node
var _terrain: Node3D
var _movement_map: Resource
var _selected := false
var _state: StringName = STATE_IDLE
var _path_points: Array[Vector3] = []
var _current_path_index := 0
var _has_destination := false
var _destination := Vector3.ZERO
var _last_path_result: Dictionary = {}
var _route_refresh_remaining := 0.0
var _last_ring_world_width := -1.0
var _last_turn_delta := 0.0
var _last_turn_intensity := 0.0
var _formation_motion_time := 0.0
var _carrier_container: Node3D
var _carrier_tasks: Array[Dictionary] = []
var _busy_carrier_soldiers := 0
var _cargo_trolley_visual_container: Node3D
var _cargo_trolley_crafting := false
var _cargo_trolley_craft_remaining_seconds := 0.0
var _cargo_trolley_craft_total_seconds := 0.0
var _cargo_trolley_craft_emit_tick := -1
var _camp_node: Node3D
var _camp_established := false
var _camp_wood_invested_kg := 0.0
var _camp_world_position := Vector3.ZERO
var _time_system: Node
var _rng := RandomNumberGenerator.new()
var _active_enemy: Node
var _combat_scan_remaining := 0.0
var _chase_repath_remaining := 0.0
var _engagement_windup_remaining := 0.0
var _combat_action_remaining := 0.0
var _last_target_instance_id := 0
var _combat_soldier_targets: Dictionary = {}
var _combat_soldier_offsets: Dictionary = {}
var _combat_soldier_attack_timers: Dictionary = {}
var _combat_scatter_active := false
var _manual_move_override_active := false
var _low_endurance_seconds := 0.0
var _food_shortage_ratio := 0.0
var _deserted_soldier_count := 0
var _last_combat_emit_time := 0.0
var _was_in_combat := false


func _ready() -> void:
	add_to_group(&"troops")
	_rng.seed = _get_combat_seed()
	_resolve_dependencies()
	_ensure_scene_nodes()
	_load_movement_map()
	rebuild_formation()
	_rebuild_ring()
	_rebuild_selection_proxy()
	_update_ring_material()
	_snap_to_surface()
	_rebuild_cargo_trolley_visuals()
	_emit_destination_changed()
	_emit_logistics_changed()
	_emit_mode_changed()
	_emit_combat_changed()


func _physics_process(delta: float) -> void:
	_update_cargo_trolley_crafting(delta)
	_update_carrier_tasks(delta)
	_update_food_and_modes(delta)
	_update_combat_ai(delta)

	if _state == STATE_MOVING:
		_follow_path(delta)
		_route_refresh_remaining -= delta
		if _route_refresh_remaining <= 0.0:
			_route_refresh_remaining = maxf(route_refresh_interval, 0.05)
			_update_route_visual()
	else:
		_last_turn_delta = 0.0
		_last_turn_intensity = 0.0
	_update_formation_soldier_slots(delta)
	_update_combat_soldier_animation()
	_maybe_emit_combat_changed(delta)


func _process(_delta: float) -> void:
	_update_screen_constant_ring_width()


func rebuild_formation() -> void:
	_ensure_scene_nodes()
	_combat_soldier_targets.clear()
	_combat_soldier_offsets.clear()
	_combat_soldier_attack_timers.clear()
	_combat_scatter_active = false
	_clear_children(_soldier_container)

	var scene := soldier_scene if soldier_scene else DEFAULT_SOLDIER_SCENE
	var columns := mini(maxi(formation_columns, 1), soldier_count)
	var rows := ceili(float(soldier_count) / float(columns))
	for index: int in range(soldier_count):
		var soldier := scene.instantiate()
		if not (soldier is Node3D):
			soldier.free()
			continue

		var spatial := soldier as Node3D
		spatial.name = "Soldier_%03d" % index
		_configure_visual_soldier(spatial, index)
		_soldier_container.add_child(spatial)
		spatial.owner = null
		var slot := _get_formation_slot_for_index(index, columns, rows)
		spatial.top_level = true
		spatial.global_position = _snap_world_point(_formation_slot_to_world(slot))
		spatial.set_meta(&"troop_formation_slot", slot)
		spatial.set_meta(&"troop_formation_index", index)
		spatial.set_meta(&"troop_formation_phase", float(index) * 1.618)
		spatial.rotation.y = rotation.y
		spatial.scale = Vector3.ONE * soldier_scale

		if index == 0:
			_attach_flag_to_soldier(spatial, "TeamFlag", team_flag_color, troop_flag_color)
		elif index == 1:
			_attach_flag_to_soldier(spatial, "TroopFlag", troop_flag_color, team_flag_color)

	_rebuild_ring()
	_rebuild_selection_proxy()
	_update_formation_soldier_locomotion()
	_emit_destination_changed()


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_update_ring_material()
	selected_changed.emit(_selected)


func is_selected() -> bool:
	return _selected


func set_move_destination(world_position: Vector3, manual_command: bool = true) -> bool:
	if manual_command:
		_clear_independent_combat(true)
	_load_movement_map()
	if not _movement_map:
		_last_path_result = MovementMapPathfinderScript.find_path(null, global_position, world_position)
		_set_state(STATE_BLOCKED)
		_manual_move_override_active = false
		_emit_destination_changed()
		return false

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		_movement_map,
		global_position,
		world_position,
		maxf(_get_current_movement_speed_mps(), 0.1),
		nearest_walkable_search_radius_cells,
		path_smoothing_enabled,
		path_corner_radius_cells,
		path_corner_samples
	)
	_last_path_result = result
	if not bool(result.get("reachable", false)):
		_path_points.clear()
		_current_path_index = 0
		_has_destination = false
		_clear_route_visual()
		_set_state(STATE_BLOCKED)
		_manual_move_override_active = false
		_emit_destination_changed()
		return false

	_path_points = _snap_path_points(result.get("points", []) as Array)
	_current_path_index = 1 if _path_points.size() > 1 else 0
	_destination = _snap_world_point(result.get("resolved_destination", world_position) as Vector3)
	_has_destination = true
	_route_refresh_remaining = 0.0
	_manual_move_override_active = manual_command
	_update_route_visual()
	_set_state(STATE_MOVING)
	_issue_formation_path_to_soldiers()
	_emit_destination_changed()
	return true


func stop_movement() -> void:
	_path_points.clear()
	_current_path_index = 0
	_has_destination = false
	_manual_move_override_active = false
	_last_path_result.clear()
	_clear_route_visual()
	_clear_formation_motion_commands()
	_set_state(STATE_IDLE)
	_emit_destination_changed()


func clear_destination() -> void:
	stop_movement()


func has_destination() -> bool:
	return _has_destination


func get_destination() -> Vector3:
	return _destination


func begin_food_collection(village: Node, requested_kg: float) -> bool:
	if not village or not village.has_method("withdraw_food_kg"):
		return false

	var available_food := _get_source_food_kg(village)
	var amount := minf(minf(maxf(requested_kg, 0.0), available_food), get_free_carry_capacity_kg())
	if amount <= 0.0:
		return false

	var assignment := _allocate_carriers_for_amount(amount)
	if int(assignment.get("soldiers", 0)) <= 0:
		return false
	amount = minf(amount, maxf(float(assignment.get("capacity_kg", 0.0)), 0.0))
	if amount <= 0.0:
		return false

	var target := global_position
	if village.has_method("get_village_storage_world_position"):
		var target_variant: Variant = village.call("get_village_storage_world_position")
		if target_variant is Vector3:
			target = target_variant
	_start_carrier_task(village, target, RESOURCE_FOOD, amount, int(assignment["soldiers"]), {})
	return true


func begin_wood_collection(forest_region: Node, forest_cell: Vector2i, soldier_count_requested: int) -> bool:
	if not forest_region or not forest_region.has_method("harvest_wood_cell"):
		return false
	if forest_region.has_method("is_tree_cell") and not bool(forest_region.call("is_tree_cell", forest_cell)):
		return false

	var available_soldiers := get_available_carrier_soldiers()
	if available_soldiers <= 0:
		return false

	var assigned_soldiers := clampi(soldier_count_requested, 1, available_soldiers)
	if assigned_soldiers <= 0:
		return false

	var amount := minf(_get_capacity_for_carrier_soldiers(assigned_soldiers), get_free_carry_capacity_kg())
	if amount <= 0.0:
		return false

	var target := _get_forest_cell_world_position(forest_region, forest_cell)
	_start_carrier_task(
		forest_region,
		target,
		RESOURCE_WOOD,
		amount,
		assigned_soldiers,
		{"cell": forest_cell}
	)
	return true


func pickup_cow_from_forest(forest_region: Node, cow_cell: Vector2i) -> bool:
	if not forest_region or not forest_region.has_method("pickup_cow_cell"):
		return false
	if forest_region.has_method("is_cow_cell") and not bool(forest_region.call("is_cow_cell", cow_cell)):
		return false
	if get_available_carrier_soldiers() <= 0:
		return false

	var target := _get_forest_cell_world_position(forest_region, cow_cell)
	_start_carrier_task(
		forest_region,
		target,
		RESOURCE_COW,
		1.0,
		1,
		{"cell": cow_cell}
	)
	return true


func craft_cargo_trolley() -> bool:
	if _cargo_trolley_crafting:
		return false

	var available_wood := camp_wood_kg if _camp_established else carried_wood_kg
	if available_wood + 0.001 < cargo_trolley_wood_cost_kg:
		return false
	if _camp_established:
		camp_wood_kg = maxf(camp_wood_kg - cargo_trolley_wood_cost_kg, 0.0)
	else:
		carried_wood_kg = maxf(carried_wood_kg - cargo_trolley_wood_cost_kg, 0.0)

	_cargo_trolley_crafting = true
	_cargo_trolley_craft_total_seconds = maxf(cargo_trolley_craft_seconds, 0.0)
	_cargo_trolley_craft_remaining_seconds = _cargo_trolley_craft_total_seconds
	_cargo_trolley_craft_emit_tick = ceili(_cargo_trolley_craft_remaining_seconds)
	_rebuild_cargo_trolley_visuals()
	if _cargo_trolley_craft_remaining_seconds <= 0.0:
		_complete_cargo_trolley_craft()
		return true

	_emit_logistics_changed()
	return true


func establish_camp() -> bool:
	if _camp_established:
		return false

	var cost := get_camp_total_wood_cost_kg()
	if carried_wood_kg + 0.001 < cost:
		return false

	carried_wood_kg = maxf(carried_wood_kg - cost, 0.0)
	camp_food_kg += maxf(carried_food_kg, 0.0)
	camp_wood_kg += maxf(carried_wood_kg, 0.0)
	carried_food_kg = 0.0
	carried_wood_kg = 0.0
	_camp_wood_invested_kg = cost
	_camp_established = true
	_camp_world_position = _snap_world_point(global_position)
	_rebuild_camp_visual()
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()
	return true


func pack_camp() -> bool:
	if not _camp_established:
		return false
	if not is_camp_pack_in_range():
		return false

	carried_food_kg += maxf(camp_food_kg, 0.0)
	carried_wood_kg += maxf(camp_wood_kg, 0.0)
	carried_wood_kg += _camp_wood_invested_kg
	camp_food_kg = 0.0
	camp_wood_kg = 0.0
	_camp_wood_invested_kg = 0.0
	_camp_established = false
	_clear_camp_visual()
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()
	return true


func get_total_carry_capacity_kg() -> float:
	return _get_capacity_for_carrier_soldiers(get_active_soldier_count() + _busy_carrier_soldiers)


func _get_capacity_for_carrier_soldiers(soldiers: int) -> float:
	var assigned_soldiers := maxi(soldiers, 0)
	var effective_trolleys := mini(maxi(cargo_trolley_count, 0), int(floor(float(assigned_soldiers) / float(maxi(cargo_trolley_required_soldiers, 1)))))
	var cow_trolleys := mini(maxi(cow_count, 0), effective_trolleys)
	var plain_trolleys := effective_trolleys - cow_trolleys
	var trolley_crew := effective_trolleys * maxi(cargo_trolley_required_soldiers, 1)
	var foot_soldiers := maxi(assigned_soldiers - trolley_crew, 0)
	return (
		float(foot_soldiers) * soldier_carry_capacity_kg
		+ float(plain_trolleys) * cargo_trolley_capacity_kg
		+ float(cow_trolleys) * cow_trolley_capacity_kg
	)


func _get_trolley_count_for_carrier_soldiers(soldiers: int) -> int:
	var crew_size := maxi(cargo_trolley_required_soldiers, 1)
	return mini(maxi(cargo_trolley_count, 0), int(floor(float(maxi(soldiers, 0)) / float(crew_size))))


func _get_active_trolley_count() -> int:
	var count := 0
	for task: Dictionary in _carrier_tasks:
		count += maxi(int(task.get("trolleys", 0)), 0)
	return mini(count, maxi(cargo_trolley_count, 0))


func _get_idle_cargo_trolley_count() -> int:
	return maxi(cargo_trolley_count - _get_active_trolley_count(), 0)


func get_current_load_kg() -> float:
	return maxf(carried_food_kg, 0.0) + maxf(carried_wood_kg, 0.0)


func get_free_carry_capacity_kg() -> float:
	return maxf(get_total_carry_capacity_kg() - get_current_load_kg(), 0.0)


func get_available_carrier_soldiers() -> int:
	return get_active_soldier_count()


func get_busy_carrier_soldiers() -> int:
	return _busy_carrier_soldiers


func get_camp_living_hut_count() -> int:
	var soldiers_per_hut := maxi(camp_soldiers_per_living_hut, 1)
	return maxi(ceili(float(maxi(get_soldier_count(), 1)) / float(soldiers_per_hut)), 1)


func get_camp_total_wood_cost_kg() -> float:
	return float(get_camp_living_hut_count()) * maxf(camp_living_hut_wood_cost_kg, 0.0)


func is_camp_pack_in_range() -> bool:
	if not _camp_established:
		return false
	return global_position.distance_to(_camp_world_position) <= maxf(camp_pack_range_m, 0.1)


func get_camp_world_position() -> Vector3:
	if is_instance_valid(_camp_node):
		return _camp_node.global_position
	return _camp_world_position


func get_camp_summary() -> Dictionary:
	return {
		"camp_established": _camp_established,
		"camp_food_kg": camp_food_kg,
		"camp_wood_kg": camp_wood_kg,
		"camp_wood_invested_kg": _camp_wood_invested_kg,
		"camp_position": get_camp_world_position(),
		"camp_pack_range_m": camp_pack_range_m,
		"camp_pack_in_range": is_camp_pack_in_range(),
		"camp_soldiers_per_living_hut": camp_soldiers_per_living_hut,
		"camp_living_hut_count": get_camp_living_hut_count(),
		"camp_living_hut_wood_cost_kg": camp_living_hut_wood_cost_kg,
		"camp_total_wood_cost_kg": get_camp_total_wood_cost_kg(),
	}


func get_troop_summary() -> Dictionary:
	var summary := {
		"troop_id": troop_id,
		"display_name": display_name,
		"team_id": team_id,
		"controllable": controllable,
		"soldier_count": get_soldier_count(),
		"state": _state,
		"troop_mode": get_troop_mode(),
		"movement_mode": get_movement_mode(),
		"selected": _selected,
		"has_destination": _has_destination,
		"destination": _destination,
		"path_distance_m": float(_last_path_result.get("distance_m", 0.0)),
		"estimated_seconds": float(_last_path_result.get("estimated_seconds", 0.0)),
		"failure_reason": StringName(_last_path_result.get("failure_reason", &"")),
		"carried_food_kg": carried_food_kg,
		"carried_wood_kg": carried_wood_kg,
		"cargo_trolley_count": cargo_trolley_count,
		"cow_count": cow_count,
		"carry_capacity_kg": get_total_carry_capacity_kg(),
		"current_load_kg": get_current_load_kg(),
		"free_capacity_kg": get_free_carry_capacity_kg(),
		"active_soldier_count": _get_formation_soldier_count(),
		"busy_carrier_soldiers": _busy_carrier_soldiers,
		"available_carrier_soldiers": get_available_carrier_soldiers(),
		"camp_established": _camp_established,
		"camp_food_kg": camp_food_kg,
		"camp_wood_kg": camp_wood_kg,
		"camp_wood_invested_kg": _camp_wood_invested_kg,
		"camp_total_wood_cost_kg": get_camp_total_wood_cost_kg(),
		"camp_soldiers_per_living_hut": camp_soldiers_per_living_hut,
		"camp_living_hut_count": get_camp_living_hut_count(),
		"camp_living_hut_wood_cost_kg": camp_living_hut_wood_cost_kg,
		"camp_pack_range_m": camp_pack_range_m,
		"camp_pack_in_range": is_camp_pack_in_range(),
		"camp_position": get_camp_world_position(),
		"cargo_trolley_wood_cost_kg": cargo_trolley_wood_cost_kg,
		"cargo_trolley_craft_seconds": cargo_trolley_craft_seconds,
		"cargo_trolley_crafting": _cargo_trolley_crafting,
		"cargo_trolley_craft_remaining_seconds": _cargo_trolley_craft_remaining_seconds,
		"cargo_trolley_craft_total_seconds": _cargo_trolley_craft_total_seconds,
		"idle_cargo_trolley_count": _get_idle_cargo_trolley_count(),
	}
	summary.merge(_get_combat_summary(), true)
	return summary


func get_soldier_count() -> int:
	return soldier_count


func _get_formation_soldier_count() -> int:
	if not _soldier_container:
		return 0
	return _soldier_container.get_child_count()


func get_flag_holder_count() -> int:
	if not _soldier_container:
		return 0
	var count := 0
	for soldier: Node in _soldier_container.get_children():
		if soldier.find_child("TeamFlag", true, false) or soldier.find_child("TroopFlag", true, false):
			count += 1
	return count


func get_selection_proxy() -> StaticBody3D:
	return _selection_proxy


func get_route_dash_count() -> int:
	return int(_route_visual.call("get_dash_count")) if _route_visual and _route_visual.has_method("get_dash_count") else 0


func has_destination_marker() -> bool:
	return bool(_route_visual.call("has_destination_flag")) if _route_visual and _route_visual.has_method("has_destination_flag") else false


func set_troop_mode(mode: Variant) -> void:
	var next_mode := _normalize_troop_mode(mode)
	if StringName(troop_mode) == next_mode:
		return
	troop_mode = String(next_mode)


func get_troop_mode() -> StringName:
	return _normalize_troop_mode(troop_mode)


func set_movement_mode(mode: Variant) -> void:
	var next_mode := _normalize_movement_mode(mode)
	if StringName(movement_mode) == next_mode:
		return
	movement_mode = String(next_mode)


func get_movement_mode() -> StringName:
	return _normalize_movement_mode(movement_mode)


func get_active_soldier_count() -> int:
	var count := 0
	for soldier: Node in _get_formation_soldiers():
		if _is_soldier_active(soldier):
			count += 1
	return count


func get_dead_soldier_count() -> int:
	var count := 0
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("is_alive") and not bool(soldier.call("is_alive")):
			count += 1
	return count


func get_deserted_soldier_count() -> int:
	return _deserted_soldier_count


func is_defeated() -> bool:
	return get_active_soldier_count() <= 0


func get_average_strength() -> float:
	return _get_average_soldier_value(&"strength")


func get_average_damage() -> float:
	return _get_average_soldier_value(&"damage")


func get_average_morale() -> float:
	return _get_average_soldier_value(&"morale")


func get_average_endurance() -> float:
	return _get_average_soldier_value(&"endurance")


func get_average_max_endurance() -> float:
	return _get_average_soldier_value(&"max_endurance")


func _ensure_scene_nodes() -> void:
	_soldier_container = get_node_or_null(SOLDIER_CONTAINER_NAME) as Node3D
	if not _soldier_container:
		_soldier_container = Node3D.new()
		_soldier_container.name = SOLDIER_CONTAINER_NAME
		add_child(_soldier_container)
		_soldier_container.owner = null

	_route_visual = get_node_or_null(ROUTE_VISUAL_NAME)
	if not _route_visual:
		_route_visual = TroopRouteVisualScript.new()
		_route_visual.name = ROUTE_VISUAL_NAME
		add_child(_route_visual)
		_route_visual.owner = null
	if _route_visual.has_method("configure_terrain"):
		_route_visual.call("configure_terrain", _terrain)
	_apply_route_visual_settings()

	_carrier_container = get_node_or_null(CARRIER_CONTAINER_NAME) as Node3D
	if not _carrier_container:
		_carrier_container = Node3D.new()
		_carrier_container.name = CARRIER_CONTAINER_NAME
		add_child(_carrier_container)
		_carrier_container.owner = null
	_carrier_container.top_level = true
	_carrier_container.global_transform = Transform3D.IDENTITY


func _resolve_dependencies() -> void:
	_terrain = get_node_or_null(terrain_path) as Node3D if not terrain_path.is_empty() else null
	_time_system = get_node_or_null(time_system_path) if not time_system_path.is_empty() else null
	if not _time_system:
		_time_system = get_node_or_null("../GameTimeSystem")


func _load_movement_map() -> void:
	_movement_map = movement_map
	if _movement_map or movement_map_path.is_empty() or not ResourceLoader.exists(movement_map_path):
		return
	_movement_map = ResourceLoader.load(movement_map_path, "", ResourceLoader.CACHE_MODE_REUSE)


func _configure_visual_soldier(spatial: Node3D, soldier_index: int = 0) -> void:
	var supports_formation_animation := spatial.has_method("set_formation_walking")
	spatial.process_mode = Node.PROCESS_MODE_INHERIT if supports_formation_animation else Node.PROCESS_MODE_DISABLED
	if supports_formation_animation:
		spatial.call("set_formation_walking", _state == STATE_MOVING, _get_current_movement_speed_mps())
	elif spatial.has_method("clear_move_target"):
		spatial.call("clear_move_target")
	if spatial.has_method("configure_combat_stats"):
		var stats := _make_soldier_stats(soldier_index)
		spatial.call(
			"configure_combat_stats",
			float(stats.get("strength", base_soldier_strength)),
			float(stats.get("damage", base_soldier_damage)),
			float(stats.get("morale", base_soldier_morale)),
			float(stats.get("endurance", base_soldier_endurance)),
			float(stats.get("max_endurance", base_soldier_endurance))
		)
	if spatial.has_method("configure_outfit_palette"):
		spatial.call("configure_outfit_palette", _make_outfit_palette())
	if _object_has_property(spatial, &"use_terrain_height"):
		spatial.set("use_terrain_height", false)
	if spatial is CollisionObject3D:
		var collision := spatial as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false


func _apply_outfit_to_soldiers() -> void:
	if not _soldier_container:
		return
	var palette := _make_outfit_palette()
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("configure_outfit_palette"):
			soldier.call("configure_outfit_palette", palette)


func _make_outfit_palette() -> Dictionary:
	return {
		"robe": soldier_robe_color,
		"robe_shadow": soldier_robe_shadow_color,
		"trim": soldier_trim_color,
		"pants": soldier_pants_color,
		"wraps": soldier_wrap_color,
		"hat": soldier_hat_color,
		"accent": soldier_accent_color,
	}


func _formation_slot_to_world(slot: Vector3) -> Vector3:
	return global_transform * slot


func _get_formation_position(index: int, columns: int, rows: int) -> Vector3:
	var column := index % columns
	var row := int(index / columns)
	var width := float(columns - 1) * formation_spacing
	var depth := float(rows - 1) * formation_spacing
	return Vector3(
		float(column) * formation_spacing - width * 0.5,
		0.0,
		float(row) * formation_spacing - depth * 0.5
	)


func _get_formation_slot_for_index(index: int, columns: int, rows: int) -> Vector3:
	return _get_formation_position(index, columns, rows) + _get_formation_natural_offset(index, columns, rows)


func _get_formation_natural_offset(index: int, columns: int, rows: int) -> Vector3:
	var amount := maxf(maxf(formation_natural_unevenness, 0.0), maxf(formation_turn_scatter, 0.0) * 0.12) * formation_spacing
	if amount <= 0.001:
		return Vector3.ZERO

	var column := index % maxi(columns, 1)
	var row := int(index / maxi(columns, 1))
	var edge_softness := 1.0
	if columns > 1:
		edge_softness -= absf((float(column) / float(columns - 1)) * 2.0 - 1.0) * 0.18
	if rows > 1:
		edge_softness -= absf((float(row) / float(rows - 1)) * 2.0 - 1.0) * 0.12
	edge_softness = clampf(edge_softness, 0.65, 1.0)

	var x_offset := sin(float(index + 1) * 12.9898) * amount * 0.42 * edge_softness
	var z_offset := cos(float(index + 1) * 78.233) * amount * 0.30 * edge_softness
	return Vector3(x_offset, 0.0, z_offset)


func _refresh_formation_slot_metas() -> void:
	if not _soldier_container:
		return
	var columns := mini(maxi(formation_columns, 1), soldier_count)
	var rows := maxi(ceili(float(soldier_count) / float(maxi(columns, 1))), 1)
	for soldier_node: Node in _soldier_container.get_children():
		if not (soldier_node is Node3D):
			continue
		var soldier := soldier_node as Node3D
		var index := int(soldier.get_meta(&"troop_formation_index", soldier.get_index()))
		soldier.set_meta(&"troop_formation_slot", _get_formation_slot_for_index(index, columns, rows))


func _attach_flag_to_soldier(
	soldier: Node3D,
	flag_name: String,
	banner_color: Color,
	accent_color: Color
) -> void:
	var parent := soldier
	if soldier.has_method("get_right_hand_socket"):
		var socket: Variant = soldier.call("get_right_hand_socket")
		if socket is Node3D:
			parent = socket as Node3D

	var flag := _create_flag(flag_name, banner_color, accent_color)
	parent.add_child(flag)
	flag.owner = null
	flag.position = carried_flag_mount_offset
	flag.rotation = Vector3(0.0, 0.0, deg_to_rad(carried_flag_roll_degrees))


func _create_flag(flag_name: String, banner_color: Color, accent_color: Color) -> Node3D:
	var flag := Node3D.new()
	flag.name = flag_name

	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = carried_flag_pole_radius
	pole_mesh.bottom_radius = carried_flag_pole_radius
	pole_mesh.height = carried_flag_pole_height
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, carried_flag_pole_height * 0.5, 0.0)
	pole.material_override = _make_material(Color(0.42, 0.28, 0.12, 1.0))
	flag.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(carried_flag_banner_size.x, carried_flag_banner_size.y, 0.035)
	banner.mesh = banner_mesh
	banner.position = Vector3(carried_flag_banner_size.x * 0.5, carried_flag_pole_height * 0.82, 0.0)
	banner.material_override = _make_material(banner_color)
	flag.add_child(banner)

	var stripe := MeshInstance3D.new()
	stripe.name = "AccentStripe"
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(carried_flag_banner_size.x * 1.03, carried_flag_banner_size.y * 0.22, 0.04)
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(
		carried_flag_banner_size.x * 0.5,
		banner.position.y - carried_flag_banner_size.y * 0.32,
		0.024
	)
	stripe.material_override = _make_material(accent_color)
	flag.add_child(stripe)
	return flag


func _rebuild_ring() -> void:
	if _ring_instance and is_instance_valid(_ring_instance):
		remove_child(_ring_instance)
		_ring_instance.free()

	_ring_instance = MeshInstance3D.new()
	_ring_instance.name = RING_NODE_NAME
	_ring_instance.mesh = _build_ring_mesh(_get_effective_ring_radius())
	_last_ring_world_width = _get_current_ring_world_width()
	_ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ring_instance.position.y = ring_surface_offset
	add_child(_ring_instance)
	_ring_instance.owner = null
	_update_ring_material()


func _build_ring_mesh(radius: float) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.1)
	var half_width := maxf(_get_current_ring_world_width(), 0.01) * 0.5
	var inner_radius := maxf(safe_radius - half_width, 0.05)
	var outer_radius := safe_radius + half_width
	var segments := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * outer_radius)
		vertices.append(direction * inner_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		colors.append(Color.WHITE)
		colors.append(Color.WHITE)

	for index: int in range(segments):
		var next_index := (index + 1) % segments
		var outer_a := index * 2
		var inner_a := outer_a + 1
		var outer_b := next_index * 2
		var inner_b := outer_b + 1
		indices.append(outer_a)
		indices.append(inner_a)
		indices.append(outer_b)
		indices.append(outer_b)
		indices.append(inner_a)
		indices.append(inner_b)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _rebuild_selection_proxy() -> void:
	if _selection_proxy and is_instance_valid(_selection_proxy):
		remove_child(_selection_proxy)
		_selection_proxy.free()

	_selection_proxy = StaticBody3D.new()
	_selection_proxy.name = SELECTION_PROXY_NAME
	_selection_proxy.collision_layer = selection_collision_layer
	_selection_proxy.collision_mask = 0
	_selection_proxy.input_ray_pickable = true
	_selection_proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_TROOP_TYPE)
	_selection_proxy.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _get_effective_ring_radius() + maxf(formation_spacing * 0.75, ring_width)
	cylinder.height = 5.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.0, 0.0)
	_selection_proxy.add_child(shape)
	add_child(_selection_proxy)
	_selection_proxy.owner = null


func _update_ring_material() -> void:
	if not _ring_instance:
		return

	var color := selected_ring_color if _selected else ring_color
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 22
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.25 if _selected else 0.12
	_ring_instance.material_override = material


func _get_effective_ring_radius() -> float:
	if ring_radius > 0.0:
		return ring_radius
	var columns := mini(maxi(formation_columns, 1), soldier_count)
	var rows := ceili(float(soldier_count) / float(columns))
	var width := maxf(float(columns - 1) * formation_spacing, formation_spacing)
	var depth := maxf(float(rows - 1) * formation_spacing, formation_spacing)
	return Vector2(width, depth).length() * 0.5 + formation_spacing * 1.35


func _update_screen_constant_ring_width() -> void:
	if not _ring_instance or not is_instance_valid(_ring_instance):
		return
	var width := _get_current_ring_world_width()
	var change_threshold := maxf(_last_ring_world_width * 0.08, 0.015)
	if _last_ring_world_width < 0.0 or absf(width - _last_ring_world_width) > change_threshold:
		_rebuild_ring()


func _get_current_ring_world_width() -> float:
	return _world_units_for_screen_pixels(
		global_position,
		ring_screen_width_px,
		ring_width,
		ring_min_world_width,
		ring_max_world_width
	)


func _world_units_for_screen_pixels(
	world_position: Vector3,
	pixel_width: float,
	fallback_world_width: float,
	min_world_width: float,
	max_world_width: float
) -> float:
	var viewport := get_viewport()
	if not viewport:
		return fallback_world_width
	var viewport_height := viewport.get_visible_rect().size.y
	if viewport_height <= 0.0:
		return fallback_world_width

	var camera := viewport.get_camera_3d()
	if not camera:
		return fallback_world_width

	var units_per_pixel := 0.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		units_per_pixel = camera.size / viewport_height
	else:
		var forward := -camera.global_transform.basis.z.normalized()
		var depth := (world_position - camera.global_position).dot(forward)
		if depth <= camera.near:
			return fallback_world_width
		units_per_pixel = 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height

	var lower_limit := minf(min_world_width, max_world_width)
	var upper_limit := maxf(min_world_width, max_world_width)
	return clampf(maxf(pixel_width, 1.0) * units_per_pixel, lower_limit, upper_limit)


func _follow_path(delta: float) -> void:
	if _current_path_index >= _path_points.size():
		_finish_movement()
		return

	_advance_reached_path_points()
	if _current_path_index >= _path_points.size():
		_finish_movement()
		return

	var target := _get_route_steering_target()
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= 0.001:
		target = _path_points[_current_path_index]
		to_target = target - global_position
		to_target.y = 0.0
		distance = to_target.length()
		if distance <= 0.001:
			return

	var direction := to_target / distance
	var turn_multiplier := _turn_toward_direction(direction, delta)
	var current_speed := _get_current_movement_speed_mps()
	global_position += direction * minf(current_speed * turn_multiplier * delta, distance)
	_drain_soldier_endurance(_get_movement_endurance_loss_rate() * delta)
	_snap_to_surface()
	_advance_reached_path_points()
	if _current_path_index >= _path_points.size():
		_finish_movement()


func _advance_reached_path_points() -> void:
	while _current_path_index < _path_points.size():
		var waypoint := _path_points[_current_path_index]
		var to_waypoint := waypoint - global_position
		to_waypoint.y = 0.0
		var radius := _get_path_waypoint_radius(_current_path_index)
		if to_waypoint.length() > radius and not _has_passed_path_waypoint(_current_path_index):
			return
		_current_path_index += 1


func _get_path_waypoint_radius(index: int) -> float:
	if index >= _path_points.size() - 1:
		return maxf(arrival_radius, 0.1)
	return minf(maxf(arrival_radius * 0.45, 0.25), maxf(formation_spacing * 0.42, 0.25))


func _has_passed_path_waypoint(index: int) -> bool:
	if index <= 0 or index >= _path_points.size() - 1:
		return false
	var previous := _path_points[index - 1]
	var current := _path_points[index]
	var segment := current - previous
	segment.y = 0.0
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return false
	var from_current := global_position - current
	from_current.y = 0.0
	return from_current.dot(segment) > 0.0


func _get_route_steering_target() -> Vector3:
	var lookahead := maxf(route_steering_lookahead_m, maxf(arrival_radius * 0.65, 0.1))
	var anchor := global_position
	for index: int in range(_current_path_index, _path_points.size()):
		var waypoint := _path_points[index]
		var segment := waypoint - anchor
		segment.y = 0.0
		var segment_length := segment.length()
		if segment_length <= 0.001:
			anchor = waypoint
			continue
		if segment_length >= lookahead:
			var target := anchor + segment / segment_length * lookahead
			target.y = waypoint.y
			return _snap_world_point(target)
		lookahead -= segment_length
		anchor = waypoint
	return _destination


func _finish_movement() -> void:
	if _has_destination:
		global_position.x = _destination.x
		global_position.z = _destination.z
		_snap_to_surface()
	_path_points.clear()
	_current_path_index = 0
	_has_destination = false
	_manual_move_override_active = false
	_clear_route_visual()
	_set_state(STATE_IDLE)
	_emit_destination_changed()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0))


func _turn_toward_direction(direction: Vector3, delta: float) -> float:
	if direction.length_squared() <= 0.0001:
		_last_turn_delta = 0.0
		_last_turn_intensity = 0.0
		return 1.0

	var target_yaw := atan2(-direction.x, -direction.z)
	var turn_delta := wrapf(target_yaw - rotation.y, -PI, PI)
	var max_step := deg_to_rad(maxf(formation_turn_rate_degrees, 1.0)) * delta
	rotation.y += clampf(turn_delta, -max_step, max_step)
	_last_turn_delta = turn_delta

	var slowdown_angle := deg_to_rad(maxf(formation_turn_slowdown_angle_degrees, 1.0))
	_last_turn_intensity = clampf(absf(turn_delta) / slowdown_angle, 0.0, 1.0)
	var min_multiplier := clampf(formation_min_turn_speed_multiplier, 0.05, 1.0)
	return lerpf(1.0, min_multiplier, _last_turn_intensity)


func _snap_path_points(raw_points: Array) -> Array[Vector3]:
	var snapped: Array[Vector3] = []
	for point_variant: Variant in raw_points:
		if point_variant is Vector3:
			snapped.append(_snap_world_point(point_variant as Vector3))
	return snapped


func _snap_world_point(point: Vector3) -> Vector3:
	var result := point
	var height: Variant = _get_surface_height(point)
	if height != null:
		result.y = float(height)
	return result


func _snap_to_surface() -> void:
	var height: Variant = _get_surface_height(global_position)
	if height == null:
		return
	var snapped := global_position
	snapped.y = float(height)
	global_position = snapped


func _get_surface_height(world_position: Vector3) -> Variant:
	if not is_instance_valid(_terrain):
		return null
	if _terrain.has_method("get_height"):
		var height: Variant = _terrain.call("get_height", world_position)
		if height is float or height is int:
			return float(height)

	var data: Variant = _terrain.get("data")
	if data and data is Object and (data as Object).has_method("get_height"):
		var data_height: Variant = (data as Object).call("get_height", world_position)
		if data_height is float or data_height is int:
			return float(data_height)
	return null


func _update_route_visual() -> void:
	if not _route_visual or not _has_destination:
		return
	_apply_route_visual_settings()
	var points := _get_remaining_route_points()
	if _route_visual.has_method("set_route"):
		_route_visual.call("set_route", points, _destination, troop_flag_color, team_flag_color)


func _clear_route_visual() -> void:
	if _route_visual and _route_visual.has_method("clear_route"):
		_route_visual.call("clear_route")


func _apply_route_visual_settings() -> void:
	if not _route_visual:
		return
	_set_route_visual_property(&"route_width", route_line_width)
	_set_route_visual_property(&"route_screen_width_px", route_line_screen_width_px)
	_set_route_visual_property(&"route_min_world_width", route_line_min_world_width)
	_set_route_visual_property(&"route_max_world_width", route_line_max_world_width)
	_set_route_visual_property(&"route_height", route_line_height)
	_set_route_visual_property(&"dash_length", route_dash_length)
	_set_route_visual_property(&"dash_gap", route_dash_gap)
	_set_route_visual_property(&"surface_offset", route_surface_offset)
	_set_route_visual_property(&"destination_flag_pole_height", destination_flag_pole_height)
	_set_route_visual_property(&"destination_flag_pole_radius", destination_flag_pole_radius)
	_set_route_visual_property(&"destination_flag_banner_size", destination_flag_banner_size)


func _set_route_visual_property(property_name: StringName, value: Variant) -> void:
	if _route_visual and _object_has_property(_route_visual, property_name):
		_route_visual.set(String(property_name), value)


func _get_remaining_route_points() -> Array[Vector3]:
	var points: Array[Vector3] = [global_position]
	for index: int in range(_current_path_index, _path_points.size()):
		points.append(_path_points[index])
	if points.back().distance_squared_to(_destination) > 0.01:
		points.append(_destination)
	return points


func _set_state(next_state: StringName) -> void:
	if _state == next_state:
		return
	_state = next_state
	_update_formation_soldier_locomotion()
	state_changed.emit(_state)


func _update_formation_soldier_locomotion() -> void:
	if not _soldier_container:
		return
	var walking := _state == STATE_MOVING
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", walking, _get_current_movement_speed_mps())


func _update_formation_soldier_slots(delta: float) -> void:
	if not _soldier_container:
		return

	if _combat_scatter_active and _state != STATE_MOVING:
		for soldier_node: Node in _soldier_container.get_children():
			if soldier_node.has_method("set_formation_walking"):
				soldier_node.call("set_formation_walking", false, _get_current_movement_speed_mps())
		return
	if _state == STATE_MOVING and _combat_scatter_active:
		_combat_scatter_active = false

	if _state == STATE_MOVING:
		_formation_motion_time += delta * maxf(movement_speed_mps, 0.1)
		return

	if _state == STATE_IDLE or _state == STATE_BLOCKED:
		_issue_idle_formation_targets()


func _issue_formation_path_to_soldiers() -> void:
	if not _soldier_container or _path_points.is_empty():
		return
	var speed := _get_current_movement_speed_mps()
	var arrival := maxf(arrival_radius * 0.38, 0.24)
	for soldier_node: Node in _soldier_container.get_children():
		if not (soldier_node is Node3D) or not _is_soldier_active(soldier_node):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		if soldier.has_method("follow_formation_path"):
			soldier.call("follow_formation_path", _path_points, slot, speed, arrival)
		elif soldier.has_method("set_independent_move_target"):
			soldier.call("set_independent_move_target", _formation_slot_to_world(slot), speed, arrival)


func _issue_idle_formation_targets() -> void:
	if not _soldier_container:
		return
	var speed := maxf(formation_slot_follow_speed, 0.1)
	var arrival := maxf(arrival_radius * 0.32, 0.18)
	var soldiers := _get_active_soldiers()
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var desired := _snap_world_point(_formation_slot_to_world(slot))
		desired += _get_soft_separation_offset(soldier, soldiers, [])
		if soldier.has_method("set_independent_move_target"):
			soldier.call("set_independent_move_target", desired, speed, arrival)
		else:
			var to_desired := desired - soldier.global_position
			to_desired.y = 0.0
			if to_desired.length() > arrival:
				soldier.global_position += to_desired.normalized() * minf(speed * get_physics_process_delta_time(), to_desired.length())


func _clear_formation_motion_commands() -> void:
	if not _soldier_container:
		return
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("clear_independent_motion"):
			soldier.call("clear_independent_motion")
		elif soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", false, _get_current_movement_speed_mps())


func _update_food_and_modes(delta: float) -> void:
	var active_count := get_active_soldier_count()
	if active_count <= 0:
		_food_shortage_ratio = 0.0
		return

	_update_food_supply(delta, active_count)
	match get_troop_mode():
		MODE_REST:
			_restore_soldier_endurance(rest_endurance_recovery_per_second * delta)
		MODE_TRAINING:
			_drain_soldier_endurance(training_endurance_loss_per_second * delta)
			_train_soldiers(delta)
		MODE_DEFENSIVE:
			_restore_soldier_endurance(defensive_endurance_recovery_per_second * delta)
		MODE_ATTACK:
			if _is_valid_enemy(_active_enemy):
				_drain_soldier_endurance(attack_mode_endurance_loss_per_second * delta)

	if _food_shortage_ratio > 0.0:
		_drain_soldier_endurance(food_shortage_endurance_loss_per_second * _food_shortage_ratio * delta)
		_change_all_morale(-food_shortage_morale_loss_per_second * _food_shortage_ratio * delta)

	var average_endurance_ratio := _get_average_endurance_ratio()
	if average_endurance_ratio > 0.0 and average_endurance_ratio < low_endurance_ratio:
		_low_endurance_seconds += delta
		if _low_endurance_seconds >= low_endurance_morale_delay:
			_change_all_morale(-low_endurance_morale_loss_per_second * delta)
	else:
		_low_endurance_seconds = 0.0


func _update_combat_ai(delta: float) -> void:
	if is_defeated():
		_active_enemy = null
		_was_in_combat = false
		_combat_action_remaining = 0.0
		_clear_independent_combat(true)
		if _state == STATE_FIGHTING:
			_set_state(STATE_IDLE)
		return

	if _manual_move_override_active and _state == STATE_MOVING:
		_active_enemy = null
		_was_in_combat = false
		_combat_action_remaining = 0.0
		return

	_combat_scan_remaining -= delta
	if _combat_scan_remaining <= 0.0:
		_combat_scan_remaining = maxf(combat_scan_interval, 0.05)
		_refresh_active_enemy()

	var enemy := _active_enemy
	if not _is_valid_enemy(enemy):
		_active_enemy = null
		if _was_in_combat:
			_clear_independent_combat(false)
		_was_in_combat = false
		if _state == STATE_FIGHTING:
			_set_state(STATE_IDLE)
		return

	_apply_enemy_pressure(delta)
	_try_desertions(delta)

	var enemy_id := enemy.get_instance_id()
	if _last_target_instance_id != enemy_id:
		_last_target_instance_id = enemy_id
		_engagement_windup_remaining = _get_mode_engagement_delay()
		_combat_action_remaining = 0.0
	else:
		_engagement_windup_remaining = maxf(_engagement_windup_remaining - delta, 0.0)

	var distance := global_position.distance_to((enemy as Node3D).global_position)
	var engagement_range := _get_mode_engagement_range()
	if get_troop_mode() == MODE_ATTACK and distance > maxf(combat_range_m, 0.1):
		_chase_repath_remaining -= delta
		if _chase_repath_remaining <= 0.0:
			_chase_repath_remaining = maxf(chase_repath_interval, 0.05)
			set_move_destination((enemy as Node3D).global_position, false)

	var can_fight := distance <= engagement_range and _engagement_windup_remaining <= 0.0
	if can_fight:
		if _state == STATE_MOVING:
			_path_points.clear()
			_current_path_index = 0
			_has_destination = false
			_manual_move_override_active = false
			_clear_route_visual()
			_emit_destination_changed()
		_set_state(STATE_FIGHTING)
		_resolve_combat_tick(enemy, delta)
		_was_in_combat = true
	elif _state == STATE_FIGHTING:
		_clear_independent_combat(false)
		_was_in_combat = false
		_set_state(STATE_IDLE)


func _resolve_combat_tick(enemy: Node, delta: float) -> void:
	var attackers := _get_active_soldiers()
	var defenders := _get_enemy_active_soldiers(enemy)
	if attackers.is_empty() or defenders.is_empty():
		_clear_independent_combat(false)
		return

	_combat_scatter_active = true
	_drain_soldier_endurance(fight_endurance_loss_per_second * delta)
	_prune_combat_assignments(attackers, defenders)
	_assign_combat_targets(attackers, defenders)
	for index: int in range(attackers.size()):
		var attacker := attackers[index]
		if not (attacker is Node3D):
			continue
		var attacker_spatial := attacker as Node3D
		var defender := _get_assigned_combat_target(attacker_spatial, defenders)
		if not defender:
			continue

		var desired_position := _get_soldier_engagement_position(attacker_spatial, defender, index, attackers.size())
		desired_position += _get_soft_separation_offset(attacker_spatial, attackers, defenders)
		_move_combat_soldier_toward(attacker_spatial, desired_position, delta)

		var distance_to_target := _horizontal_distance(attacker_spatial.global_position, defender.global_position)
		var in_spear_range := distance_to_target <= maxf(combat_spear_range_m, 0.2)
		if attacker.has_method("set_independent_combat"):
			attacker.call("set_independent_combat", true, defender, in_spear_range)
		elif attacker.has_method("set_formation_attacking"):
			attacker.call("set_formation_attacking", in_spear_range, defender)

		if in_spear_range:
			_update_soldier_attack(attacker, defender, delta)
		else:
			_reset_soldier_attack_delay(attacker)


func _prune_combat_assignments(attackers: Array[Node], defenders: Array[Node]) -> void:
	var attacker_ids := {}
	for attacker: Node in attackers:
		attacker_ids[attacker.get_instance_id()] = true

	var defender_ids := {}
	for defender: Node in defenders:
		defender_ids[defender.get_instance_id()] = true

	for key: Variant in _combat_soldier_targets.keys():
		var target: Variant = _combat_soldier_targets.get(key)
		var target_id := _get_valid_node_instance_id(target)
		if not attacker_ids.has(key) or not defender_ids.has(target_id):
			_combat_soldier_targets.erase(key)
			_combat_soldier_attack_timers.erase(key)
			if not attacker_ids.has(key):
				_combat_soldier_offsets.erase(key)


func _assign_combat_targets(attackers: Array[Node], defenders: Array[Node]) -> void:
	var load_by_defender := _get_combat_target_loads(defenders)
	for attacker: Node in attackers:
		if not (attacker is Node3D):
			continue
		var key := attacker.get_instance_id()
		var existing_target: Variant = _combat_soldier_targets.get(key)
		if is_instance_valid(existing_target) and defenders.has(existing_target):
			continue
		var best_target := _find_best_combat_target(attacker as Node3D, defenders, load_by_defender)
		if best_target:
			_combat_soldier_targets[key] = best_target
			var best_id := best_target.get_instance_id()
			load_by_defender[best_id] = int(load_by_defender.get(best_id, 0)) + 1


func _get_combat_target_loads(defenders: Array[Node]) -> Dictionary:
	var load_by_defender := {}
	for defender: Node in defenders:
		load_by_defender[defender.get_instance_id()] = 0
	for target_variant: Variant in _combat_soldier_targets.values():
		if not is_instance_valid(target_variant):
			continue
		var target := target_variant as Node
		if not target:
			continue
		var target_id := target.get_instance_id()
		if load_by_defender.has(target_id):
			load_by_defender[target_id] = int(load_by_defender[target_id]) + 1
	return load_by_defender


func _get_valid_node_instance_id(value: Variant) -> int:
	if not is_instance_valid(value):
		return 0
	var node := value as Node
	if not node:
		return 0
	return node.get_instance_id()


func _find_best_combat_target(attacker: Node3D, defenders: Array[Node], load_by_defender: Dictionary) -> Node3D:
	var best_target: Node3D
	var best_score := INF
	for defender_node: Node in defenders:
		if not (defender_node is Node3D):
			continue
		var defender := defender_node as Node3D
		var defender_id := defender.get_instance_id()
		var load := int(load_by_defender.get(defender_id, 0))
		var distance_squared := attacker.global_position.distance_squared_to(defender.global_position)
		var score := float(load) * 10000.0 + distance_squared
		if score < best_score:
			best_score = score
			best_target = defender
	return best_target


func _get_assigned_combat_target(attacker: Node3D, defenders: Array[Node]) -> Node3D:
	var key := attacker.get_instance_id()
	var target_variant: Variant = _combat_soldier_targets.get(key)
	if is_instance_valid(target_variant) and defenders.has(target_variant):
		return target_variant as Node3D
	var load_by_defender := _get_combat_target_loads(defenders)
	var best_target := _find_best_combat_target(attacker, defenders, load_by_defender)
	if best_target:
		_combat_soldier_targets[key] = best_target
	return best_target


func _get_soldier_engagement_position(attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	var target_position := defender.global_position
	var away := attacker.global_position - target_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = global_position - target_position
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		var angle := TAU * float(index) / float(maxi(total, 1))
		away = Vector3(cos(angle), 0.0, sin(angle))
	away = away.normalized()

	var side := Vector3(-away.z, 0.0, away.x)
	var offset := _get_combat_offset_for_soldier(attacker, index, total)
	var standoff := clampf(
		soldier_personal_space_radius + enemy_personal_space_radius + 0.18 + offset.y,
		0.45,
		maxf(combat_spear_range_m * 0.86, 0.5)
	)
	var desired := target_position + away * standoff + side * offset.x
	var from_target := desired - target_position
	from_target.y = 0.0
	var max_distance := maxf(combat_spear_range_m * 0.94, standoff)
	if from_target.length() > max_distance:
		desired = target_position + from_target.normalized() * max_distance
	desired.y = attacker.global_position.y
	return desired


func _get_combat_offset_for_soldier(attacker: Node3D, index: int, total: int) -> Vector2:
	var key := attacker.get_instance_id()
	if _combat_soldier_offsets.has(key):
		return _combat_soldier_offsets[key] as Vector2
	var centered := float(index) - float(maxi(total - 1, 0)) * 0.5
	var seed := float(absi(hash("%s:%s" % [String(troop_id), String(attacker.name)])) % 10000) / 10000.0
	var lateral_jitter := (seed - 0.5) * maxf(combat_frontline_width_per_soldier, 0.1) * 0.35
	var depth_jitter := (float(absi(hash("depth:%s" % String(attacker.name))) % 1000) / 1000.0 - 0.5) * 0.34
	var offset := Vector2(centered * maxf(combat_frontline_width_per_soldier, 0.1) * 0.32 + lateral_jitter, depth_jitter)
	_combat_soldier_offsets[key] = offset
	return offset


func _get_soft_separation_offset(attacker: Node3D, attackers: Array[Node], defenders: Array[Node]) -> Vector3:
	var offset := Vector3.ZERO
	for ally_node: Node in attackers:
		if ally_node == attacker or not (ally_node is Node3D):
			continue
		offset += _get_pair_separation(attacker, ally_node as Node3D, soldier_personal_space_radius + soldier_personal_space_radius)
	for enemy_node: Node in defenders:
		if not (enemy_node is Node3D):
			continue
		offset += _get_pair_separation(attacker, enemy_node as Node3D, soldier_personal_space_radius + enemy_personal_space_radius)
	var max_offset := maxf(combat_separation_strength, 0.0) * 0.22
	if max_offset > 0.0 and offset.length() > max_offset:
		offset = offset.normalized() * max_offset
	return offset


func _get_pair_separation(subject: Node3D, other: Node3D, minimum_distance: float) -> Vector3:
	var away := subject.global_position - other.global_position
	away.y = 0.0
	var distance := away.length()
	if distance >= minimum_distance:
		return Vector3.ZERO
	if distance <= 0.001:
		var angle := TAU * float(absi(hash("%s:%s" % [String(subject.name), String(other.name)])) % 1000) / 1000.0
		away = Vector3(cos(angle), 0.0, sin(angle))
		distance = 0.001
	var strength := clampf((minimum_distance - distance) / maxf(minimum_distance, 0.001), 0.0, 1.0)
	return away.normalized() * strength * maxf(combat_separation_strength, 0.0) * 0.18


func _move_combat_soldier_toward(soldier: Node3D, desired_global_position: Vector3, delta: float) -> void:
	var current := soldier.global_position
	var desired := desired_global_position
	desired.y = current.y
	var to_desired := desired - current
	to_desired.y = 0.0
	var distance := to_desired.length()
	if soldier.has_method("set_independent_move_target"):
		soldier.call("set_independent_move_target", desired, maxf(combat_slot_follow_speed, 0.1), 0.14)
	elif distance > 0.001:
		var max_step := maxf(combat_slot_follow_speed, 0.1) * delta
		var next_position := current + to_desired / distance * minf(max_step, distance)
		next_position.y = current.y
		soldier.global_position = next_position
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", distance > 0.08, maxf(combat_slot_follow_speed, 0.1))


func _update_soldier_attack(attacker: Node, defender: Node3D, delta: float) -> void:
	var key := attacker.get_instance_id()
	var remaining := float(_combat_soldier_attack_timers.get(key, _get_initial_attack_delay(attacker)))
	remaining -= delta
	if remaining > 0.0:
		_combat_soldier_attack_timers[key] = remaining
		return

	_apply_soldier_damage(attacker, defender)
	if attacker.has_method("trigger_spear_thrust"):
		attacker.call("trigger_spear_thrust", defender, maxf(attack_interval * 0.72, 0.22))
	_combat_soldier_attack_timers[key] = _get_soldier_attack_interval(attacker)


func _reset_soldier_attack_delay(attacker: Node) -> void:
	var key := attacker.get_instance_id()
	if not _combat_soldier_attack_timers.has(key):
		_combat_soldier_attack_timers[key] = _get_initial_attack_delay(attacker)


func _apply_soldier_damage(attacker: Node, defender: Node) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	if not attacker.has_method("get_effective_damage"):
		return
	var damage_amount := maxf(float(attacker.call("get_effective_damage")), 0.0)
	if defender.has_method("apply_strength_damage"):
		defender.call("apply_strength_damage", damage_amount, &"combat")
	elif defender.has_method("apply_damage"):
		defender.call("apply_damage", damage_amount, &"combat")


func _get_initial_attack_delay(attacker: Node) -> float:
	var seed := float(absi(hash("%s:%s" % [String(troop_id), String(attacker.name)])) % 1000) / 1000.0
	return seed * maxf(attack_interval, 0.05) * 0.45


func _get_soldier_attack_interval(attacker: Node) -> float:
	var seed := float(absi(hash("attack:%s:%s" % [String(troop_id), String(attacker.name)])) % 1000) / 1000.0
	return maxf(attack_interval, 0.05) * lerpf(0.82, 1.24, seed)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)


func _refresh_active_enemy() -> void:
	if _is_valid_enemy(_active_enemy) and global_position.distance_to((_active_enemy as Node3D).global_position) <= detection_range_m:
		return

	var best_enemy: Node
	var best_distance_squared := INF
	var tree := get_tree()
	if not tree:
		return
	for node: Node in tree.get_nodes_in_group(&"troops"):
		if node == self or not (node is Node3D):
			continue
		if not _is_valid_enemy(node):
			continue
		var distance_squared := global_position.distance_squared_to((node as Node3D).global_position)
		if distance_squared > detection_range_m * detection_range_m:
			continue
		if distance_squared < best_distance_squared:
			best_enemy = node
			best_distance_squared = distance_squared
	_active_enemy = best_enemy
	if not _active_enemy:
		_last_target_instance_id = 0


func _is_valid_enemy(enemy: Variant) -> bool:
	if not is_instance_valid(enemy) or enemy == self or not (enemy is Node3D):
		return false
	if enemy.has_method("is_defeated") and bool(enemy.call("is_defeated")):
		return false
	if StringName(enemy.get("team_id")) == team_id:
		return false
	return true


func _apply_enemy_pressure(delta: float) -> void:
	if not _is_valid_enemy(_active_enemy):
		return
	var own_count := maxf(float(get_active_soldier_count()), 1.0)
	var enemy_count := own_count
	if _active_enemy.has_method("get_active_soldier_count"):
		enemy_count = maxf(float(_active_enemy.call("get_active_soldier_count")), 0.0)
	if enemy_count > own_count:
		var pressure := clampf(enemy_count / own_count - 1.0, 0.0, 3.0)
		_change_all_morale(-outnumbered_morale_loss_per_second * pressure * delta)


func _try_desertions(delta: float) -> void:
	if desertion_chance_per_second <= 0.0:
		return
	var soldiers := _get_active_soldiers()
	for soldier: Node in soldiers:
		var morale_value := _get_soldier_stat(soldier, &"morale")
		if morale_value >= desertion_morale_threshold:
			continue
		var morale_pressure := clampf((desertion_morale_threshold - morale_value) / maxf(desertion_morale_threshold, 1.0), 0.0, 1.0)
		var probability := desertion_chance_per_second * morale_pressure * delta
		if _rng.randf() < probability:
			_desert_soldier(soldier)


func _desert_soldier(soldier: Node) -> void:
	if not _soldier_container or not (soldier is Node3D):
		return
	var deserter := soldier as Node3D
	var previous_transform := deserter.global_transform
	_soldier_container.remove_child(deserter)
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(deserter)
	else:
		add_child(deserter)
	deserter.owner = null
	deserter.global_transform = previous_transform
	_deserted_soldier_count += 1

	var run_direction := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	if _is_valid_enemy(_active_enemy):
		run_direction = global_position - (_active_enemy as Node3D).global_position
	if deserter.has_method("mark_deserted"):
		deserter.call("mark_deserted", run_direction)
	_rebuild_ring()
	_rebuild_selection_proxy()
	_emit_combat_changed()


func _update_combat_soldier_animation() -> void:
	var fighting := _state == STATE_FIGHTING and _is_valid_enemy(_active_enemy)
	if fighting:
		for soldier: Node in _get_formation_soldiers():
			if not _is_soldier_active(soldier):
				if soldier.has_method("set_independent_combat"):
					soldier.call("set_independent_combat", false)
				elif soldier.has_method("set_formation_attacking"):
					soldier.call("set_formation_attacking", false)
		return
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("set_independent_combat"):
			soldier.call("set_independent_combat", false)
		elif soldier.has_method("set_formation_attacking"):
			soldier.call("set_formation_attacking", false)


func _clear_independent_combat(regroup: bool) -> void:
	_combat_soldier_targets.clear()
	_combat_soldier_attack_timers.clear()
	if regroup:
		_combat_soldier_offsets.clear()
		_combat_scatter_active = false
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("set_independent_combat"):
			soldier.call("set_independent_combat", false)
		elif soldier.has_method("set_formation_attacking"):
			soldier.call("set_formation_attacking", false)


func _update_food_supply(delta: float, active_count: int) -> void:
	var needed := float(active_count) * maxf(food_kg_per_soldier_per_day, 0.0) * _get_game_days_for_delta(delta)
	if needed <= 0.0:
		_food_shortage_ratio = 0.0
		return

	var available := maxf(carried_food_kg, 0.0) + (maxf(camp_food_kg, 0.0) if _camp_established else 0.0)
	var consumed := minf(needed, available)
	if consumed <= carried_food_kg:
		carried_food_kg = maxf(carried_food_kg - consumed, 0.0)
	else:
		var remaining := consumed - maxf(carried_food_kg, 0.0)
		carried_food_kg = 0.0
		camp_food_kg = maxf(camp_food_kg - remaining, 0.0)
	_food_shortage_ratio = clampf((needed - consumed) / needed, 0.0, 1.0)


func _get_game_days_for_delta(delta: float) -> float:
	var game_minutes_per_second := 12.0
	if _time_system and _object_has_property(_time_system, &"game_minutes_per_real_second"):
		game_minutes_per_second = maxf(float(_time_system.get("game_minutes_per_real_second")), 0.0)
	return delta * game_minutes_per_second / 1440.0


func _train_soldiers(delta: float) -> void:
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("train_stats"):
			soldier.call(
				"train_stats",
				training_strength_gain_per_second * delta,
				training_damage_gain_per_second * delta,
				training_morale_gain_per_second * delta,
				training_max_endurance_gain_per_second * delta
			)


func _restore_soldier_endurance(amount: float) -> void:
	if amount <= 0.0:
		return
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("restore_endurance"):
			soldier.call("restore_endurance", amount)


func _drain_soldier_endurance(amount: float) -> void:
	if amount <= 0.0:
		return
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("reduce_endurance"):
			soldier.call("reduce_endurance", amount)


func _change_all_morale(amount: float) -> void:
	if is_zero_approx(amount):
		return
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("change_morale"):
			soldier.call("change_morale", amount)


func _get_current_movement_speed_mps() -> float:
	var speed := maxf(movement_speed_mps, 0.1)
	if get_movement_mode() == MOVEMENT_RUNNING:
		speed *= maxf(running_speed_multiplier, 1.0)
	return speed


func _get_movement_endurance_loss_rate() -> float:
	return run_endurance_loss_per_second if get_movement_mode() == MOVEMENT_RUNNING else walk_endurance_loss_per_second


func _get_mode_engagement_delay() -> float:
	match get_troop_mode():
		MODE_REST:
			return maxf(rest_engagement_delay, 0.0)
		MODE_TRAINING:
			return maxf(training_engagement_delay, 0.0)
		MODE_ATTACK:
			return maxf(attack_engagement_delay, 0.0)
		_:
			return maxf(defensive_engagement_delay, 0.0)


func _get_mode_engagement_range() -> float:
	match get_troop_mode():
		MODE_ATTACK:
			return maxf(combat_range_m, 0.1)
		MODE_DEFENSIVE, MODE_REST, MODE_TRAINING:
			return maxf(defensive_engagement_range_m, 0.1)
		_:
			return maxf(combat_range_m, 0.1)


func _make_soldier_stats(index: int) -> Dictionary:
	var stat_rng := RandomNumberGenerator.new()
	stat_rng.seed = _get_combat_seed() + int(index) * 7919
	var max_endurance_value := maxf(base_soldier_endurance + stat_rng.randf_range(-soldier_endurance_variance, soldier_endurance_variance), 1.0)
	return {
		"strength": maxf(base_soldier_strength + stat_rng.randf_range(-soldier_strength_variance, soldier_strength_variance), 1.0),
		"damage": maxf(base_soldier_damage + stat_rng.randf_range(-soldier_damage_variance, soldier_damage_variance), 0.1),
		"morale": clampf(base_soldier_morale + stat_rng.randf_range(-soldier_morale_variance, soldier_morale_variance), 0.0, 100.0),
		"endurance": max_endurance_value,
		"max_endurance": max_endurance_value,
	}


func _get_combat_seed() -> int:
	return maxi(combat_seed + absi(hash(String(troop_id))) % 100000, 1)


func _normalize_troop_mode(value: Variant) -> StringName:
	var mode := StringName(String(value).to_lower())
	match mode:
		MODE_REST, MODE_TRAINING, MODE_DEFENSIVE, MODE_ATTACK:
			return mode
		_:
			return MODE_DEFENSIVE


func _normalize_movement_mode(value: Variant) -> StringName:
	var mode := StringName(String(value).to_lower())
	match mode:
		MOVEMENT_RUNNING:
			return MOVEMENT_RUNNING
		_:
			return MOVEMENT_WALKING


func _on_mode_updated() -> void:
	_engagement_windup_remaining = _get_mode_engagement_delay()
	_update_formation_soldier_locomotion()
	_emit_mode_changed()
	_emit_combat_changed()


func _get_formation_soldiers() -> Array[Node]:
	if not _soldier_container:
		return []
	return _soldier_container.get_children()


func _get_active_soldiers() -> Array[Node]:
	var soldiers: Array[Node] = []
	for soldier: Node in _get_formation_soldiers():
		if _is_soldier_active(soldier):
			soldiers.append(soldier)
	return soldiers


func _get_enemy_active_soldiers(enemy: Node) -> Array[Node]:
	if not is_instance_valid(enemy) or not enemy.has_method("_get_active_soldiers"):
		return []
	return enemy.call("_get_active_soldiers") as Array[Node]


func _is_soldier_active(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_combat_active"):
		return bool(soldier.call("is_combat_active"))
	if soldier.has_method("is_alive"):
		return bool(soldier.call("is_alive"))
	return true


func _get_soldier_stat(soldier: Node, key: StringName) -> float:
	if not is_instance_valid(soldier):
		return 0.0
	if soldier.has_method("get_combat_summary"):
		var summary: Dictionary = soldier.call("get_combat_summary") as Dictionary
		return float(summary.get(String(key), 0.0))
	return 0.0


func _get_average_soldier_value(key: StringName) -> float:
	var soldiers := _get_active_soldiers()
	if soldiers.is_empty():
		return 0.0
	var total := 0.0
	for soldier: Node in soldiers:
		total += _get_soldier_stat(soldier, key)
	return total / float(soldiers.size())


func _get_average_endurance_ratio() -> float:
	var max_endurance_value := get_average_max_endurance()
	if max_endurance_value <= 0.0:
		return 0.0
	return clampf(get_average_endurance() / max_endurance_value, 0.0, 1.0)


func _get_combat_summary() -> Dictionary:
	return {
		"active_soldier_count": get_active_soldier_count(),
		"dead_soldier_count": get_dead_soldier_count(),
		"deserted_soldier_count": get_deserted_soldier_count(),
		"average_strength": get_average_strength(),
		"average_damage": get_average_damage(),
		"average_morale": get_average_morale(),
		"average_endurance": get_average_endurance(),
		"average_max_endurance": get_average_max_endurance(),
		"food_shortage_ratio": _food_shortage_ratio,
		"combat_target": _active_enemy.get_path() if _is_valid_enemy(_active_enemy) else NodePath(""),
		"in_combat": _state == STATE_FIGHTING,
		"combat_scatter_active": _combat_scatter_active,
		"combat_assigned_target_count": _combat_soldier_targets.size(),
		"engagement_windup_seconds": _engagement_windup_remaining,
		"defeated": is_defeated(),
	}


func _get_source_food_kg(village: Node) -> float:
	if not village:
		return 0.0
	if village.has_method("get_village_storage_summary"):
		var storage_summary: Dictionary = village.call("get_village_storage_summary") as Dictionary
		return maxf(float(storage_summary.get("storage_food_kg", 0.0)), 0.0)
	if village.has_method("get_village_food_summary"):
		var food_summary: Dictionary = village.call("get_village_food_summary") as Dictionary
		return maxf(float(food_summary.get("storage_food_kg", food_summary.get("total_reserve_kg", 0.0))), 0.0)
	return 0.0


func _allocate_carriers_for_amount(amount_kg: float) -> Dictionary:
	var remaining := maxf(amount_kg, 0.0)
	var available_soldiers := get_available_carrier_soldiers()
	if remaining <= 0.0 or available_soldiers <= 0:
		return {"soldiers": 0, "capacity_kg": 0.0}

	var soldiers := 0
	var capacity := 0.0
	var crew_size := maxi(cargo_trolley_required_soldiers, 1)
	var usable_trolleys := mini(maxi(cargo_trolley_count, 0), int(floor(float(available_soldiers) / float(crew_size))))
	var cow_trolleys := mini(maxi(cow_count, 0), usable_trolleys)
	var plain_trolleys := usable_trolleys - cow_trolleys

	while cow_trolleys > 0 and capacity + 0.001 < remaining:
		cow_trolleys -= 1
		soldiers += crew_size
		capacity += cow_trolley_capacity_kg

	while plain_trolleys > 0 and capacity + 0.001 < remaining:
		plain_trolleys -= 1
		soldiers += crew_size
		capacity += cargo_trolley_capacity_kg

	while soldiers < available_soldiers and capacity + 0.001 < remaining:
		soldiers += 1
		capacity += soldier_carry_capacity_kg

	return {
		"soldiers": soldiers,
		"capacity_kg": capacity,
	}


func _get_forest_cell_world_position(forest_region: Node, forest_cell: Vector2i) -> Vector3:
	if forest_region and forest_region.has_method("get_cell_world_position"):
		var world_variant: Variant = forest_region.call("get_cell_world_position", forest_cell)
		if world_variant is Vector3:
			return world_variant as Vector3
	if forest_region and forest_region.has_method("cell_to_local_center"):
		var local_variant: Variant = forest_region.call("cell_to_local_center", forest_cell)
		if local_variant is Vector3 and forest_region is Node3D:
			return (forest_region as Node3D).to_global(local_variant as Vector3)
	return global_position


func _start_carrier_task(
	source: Node,
	target: Vector3,
	resource_type: StringName,
	requested_amount: float,
	assigned_soldiers: int,
	extra: Dictionary
) -> void:
	var soldiers := mini(maxi(assigned_soldiers, 0), get_available_carrier_soldiers())
	if soldiers <= 0:
		return

	_ensure_scene_nodes()
	var snapped_target := _snap_world_point(target)
	var task_trolley_count := _get_trolley_count_for_carrier_soldiers(soldiers)
	var visuals := _claim_carrier_soldiers(soldiers, resource_type, task_trolley_count)
	soldiers = visuals.size()
	if soldiers <= 0:
		return
	task_trolley_count = _get_trolley_count_for_carrier_soldiers(soldiers)

	_busy_carrier_soldiers += soldiers
	_carrier_tasks.append({
		"source": source,
		"target": snapped_target,
		"resource_type": resource_type,
		"requested_amount_kg": maxf(requested_amount, 0.0),
		"amount_kg": 0.0,
		"soldiers": soldiers,
		"trolleys": task_trolley_count,
		"visuals": visuals,
		"state": TASK_TO_TARGET,
		"work_remaining": 0.0,
		"extra": extra.duplicate(true),
	})
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()


func _claim_carrier_soldiers(soldiers: int, resource_type: StringName, trolley_count: int) -> Array[Node3D]:
	var claimed: Array[Node3D] = []
	if not _soldier_container or not _carrier_container:
		return claimed

	var selected := _select_available_carrier_soldiers(soldiers)
	for index: int in range(selected.size()):
		var soldier := selected[index]
		var previous_transform := soldier.global_transform
		_soldier_container.remove_child(soldier)
		_carrier_container.add_child(soldier)
		soldier.owner = null
		soldier.global_transform = previous_transform
		soldier.set_meta(&"troop_carrier_active", true)
		soldier.set_meta(&"troop_carrier_original_name", String(soldier.name))
		_prepare_carrier_visual(soldier, index, selected.size(), resource_type, trolley_count)
		claimed.append(soldier)
	return claimed


func _select_available_carrier_soldiers(soldiers: int) -> Array[Node3D]:
	var selected: Array[Node3D] = []
	if not _soldier_container:
		return selected

	var children := _soldier_container.get_children()
	for include_flag_holders: bool in [false, true]:
		for index: int in range(children.size() - 1, -1, -1):
			if selected.size() >= soldiers:
				return selected
			var child := children[index]
			if not (child is Node3D):
				continue
			var soldier := child as Node3D
			if selected.has(soldier):
				continue
			if not _is_soldier_active(soldier):
				continue
			if _is_flag_holder(soldier) and not include_flag_holders:
				continue
			selected.append(soldier)
	return selected


func _prepare_carrier_visual(visual: Node3D, index: int, total: int, resource_type: StringName, trolley_count: int = 0) -> void:
	_configure_carrier_visual(visual)
	_clear_carrier_decoration(visual)
	if not visual.has_meta(&"troop_carrier_original_name"):
		visual.set_meta(&"troop_carrier_original_name", String(visual.name))
	visual.name = "Carrier_%03d" % int(visual.get_meta(&"troop_formation_index", index))

	var pack := Node3D.new()
	pack.name = "CarrierPack"
	visual.add_child(pack)
	pack.position = Vector3(0.0, 0.95, 0.24)

	var bundle := MeshInstance3D.new()
	bundle.name = "Bundle"
	var bundle_mesh := BoxMesh.new()
	bundle_mesh.size = Vector3(0.32, 0.32, 0.22)
	bundle.mesh = bundle_mesh
	bundle.material_override = _make_material(Color(0.42, 0.28, 0.14, 1.0))
	pack.add_child(bundle)

	if index < trolley_count:
		_attach_trolley_hint(visual)

	_attach_resource_icon(visual, resource_type)
	if visual.has_method("set_formation_walking"):
		visual.call("set_formation_walking", true, carrier_speed_mps)


func _clear_carrier_decoration(visual: Node3D) -> void:
	for node_name: String in ["CarrierPack", "TrolleyHint", "ResourceIcon"]:
		var child := visual.get_node_or_null(node_name)
		if child:
			visual.remove_child(child)
			child.free()


func _is_flag_holder(soldier: Node3D) -> bool:
	return soldier.find_child("TeamFlag", true, false) != null or soldier.find_child("TroopFlag", true, false) != null


func _create_carrier_visual(index: int, total: int, resource_type: StringName) -> Node3D:
	var scene := soldier_scene if soldier_scene else DEFAULT_SOLDIER_SCENE
	var instance := scene.instantiate()
	var visual: Node3D
	if instance is Node3D:
		visual = instance as Node3D
	else:
		instance.free()
		visual = Node3D.new()
	visual.name = "Carrier_%03d" % index
	_prepare_carrier_visual(visual, index, total, resource_type, 0)
	return visual


func _configure_carrier_visual(node: Node) -> void:
	if node is Node3D:
		var supports_formation_animation := node.has_method("set_formation_walking")
		(node as Node3D).process_mode = Node.PROCESS_MODE_INHERIT if supports_formation_animation else Node.PROCESS_MODE_DISABLED
		if supports_formation_animation:
			node.call("set_formation_walking", false, carrier_speed_mps)
	if node is CollisionObject3D:
		var collision := node as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	for child: Node in node.get_children():
		_configure_carrier_visual(child)


func _attach_trolley_hint(visual: Node3D) -> void:
	var trolley: Node3D = _create_cargo_trolley_model("TrolleyHint", 0.72, false)
	visual.add_child(trolley)
	trolley.position = Vector3(0.0, 0.28, 0.62)


func _rebuild_cargo_trolley_visuals() -> void:
	_clear_cargo_trolley_visuals()

	var idle_count := _get_idle_cargo_trolley_count()
	var crafting_count := 1 if _cargo_trolley_crafting else 0
	var total_count := idle_count + crafting_count
	if total_count <= 0:
		return

	var parent := _camp_node if _camp_established and is_instance_valid(_camp_node) else self
	_cargo_trolley_visual_container = Node3D.new()
	_cargo_trolley_visual_container.name = "CargoTrolleyVisuals"
	parent.add_child(_cargo_trolley_visual_container)
	_cargo_trolley_visual_container.owner = null

	for index: int in range(idle_count):
		var trolley: Node3D = _create_cargo_trolley_model("CargoTrolley_%02d" % index, 1.0, false)
		trolley.position = _get_cargo_trolley_visual_position(index, total_count)
		trolley.rotation.y = deg_to_rad(-8.0 + float((index * 17) % 29))
		_cargo_trolley_visual_container.add_child(trolley)

	if _cargo_trolley_crafting:
		var craft_index := idle_count
		var crafting: Node3D = _create_cargo_trolley_model("CraftingCargoTrolley", 1.0, true)
		crafting.position = _get_cargo_trolley_visual_position(craft_index, total_count)
		crafting.rotation.y = deg_to_rad(11.0)
		_cargo_trolley_visual_container.add_child(crafting)
		_add_cargo_trolley_craft_marker(crafting)


func _clear_cargo_trolley_visuals() -> void:
	if _cargo_trolley_visual_container and is_instance_valid(_cargo_trolley_visual_container):
		if _cargo_trolley_visual_container.get_parent():
			_cargo_trolley_visual_container.get_parent().remove_child(_cargo_trolley_visual_container)
		_cargo_trolley_visual_container.free()
	_cargo_trolley_visual_container = null


func _get_cargo_trolley_visual_position(index: int, total: int) -> Vector3:
	var columns := clampi(ceili(sqrt(float(maxi(total, 1)))), 1, 4)
	var row := int(index / columns)
	var column := index % columns
	var spacing_x := 1.45 * maxf(cargo_trolley_visual_scale, 0.1)
	var spacing_z := 1.15 * maxf(cargo_trolley_visual_scale, 0.1)
	var x := (float(column) - float(columns - 1) * 0.5) * spacing_x
	var z := float(row) * spacing_z
	if _camp_established:
		var camp_scale := _get_camp_visual_scale()
		return Vector3(-2.65 * camp_scale + x, 0.15 * camp_scale, -3.15 * camp_scale - z)
	return Vector3(x, 0.18, _get_effective_ring_radius() + 1.2 + z)


func _create_cargo_trolley_model(node_name: String, scale_multiplier: float, under_construction: bool) -> Node3D:
	var trolley := Node3D.new()
	trolley.name = node_name
	var s := maxf(cargo_trolley_visual_scale, 0.1) * maxf(scale_multiplier, 0.1)

	var tray := _make_camp_box("Tray", Vector3(0.92 * s, 0.18 * s, 0.52 * s), Color(0.36, 0.24, 0.12, 1.0))
	tray.position = Vector3(0.0, 0.38 * s, 0.0)
	trolley.add_child(tray)

	var front_rail := _make_camp_box("FrontRail", Vector3(0.96 * s, 0.12 * s, 0.08 * s), Color(0.26, 0.17, 0.08, 1.0))
	front_rail.position = Vector3(0.0, 0.54 * s, -0.3 * s)
	trolley.add_child(front_rail)
	var rear_rail := _make_camp_box("RearRail", Vector3(0.96 * s, 0.12 * s, 0.08 * s), Color(0.26, 0.17, 0.08, 1.0))
	rear_rail.position = Vector3(0.0, 0.54 * s, 0.3 * s)
	trolley.add_child(rear_rail)

	for side_x: float in [-0.52, 0.52]:
		var side_rail := _make_camp_box("SideRail", Vector3(0.08 * s, 0.12 * s, 0.62 * s), Color(0.28, 0.18, 0.08, 1.0))
		side_rail.position = Vector3(side_x * s, 0.54 * s, 0.0)
		trolley.add_child(side_rail)

	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.035 * s
	handle_mesh.bottom_radius = 0.035 * s
	handle_mesh.height = 0.88 * s
	handle_mesh.radial_segments = 8
	handle.mesh = handle_mesh
	handle.rotation.x = PI * 0.5
	handle.position = Vector3(0.0, 0.48 * s, -0.78 * s)
	handle.material_override = _make_material(Color(0.28, 0.18, 0.08, 1.0))
	trolley.add_child(handle)

	for wheel_x: float in [-0.48, 0.48]:
		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel"
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.18 * s
		wheel_mesh.bottom_radius = 0.18 * s
		wheel_mesh.height = 0.08 * s
		wheel_mesh.radial_segments = 14
		wheel.mesh = wheel_mesh
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(wheel_x * s, 0.18 * s, 0.03 * s)
		wheel.material_override = _make_material(Color(0.1, 0.07, 0.04, 1.0))
		trolley.add_child(wheel)

	if under_construction:
		var missing := _make_camp_box("UnfinishedSide", Vector3(0.36 * s, 0.08 * s, 0.5 * s), Color(0.6, 0.42, 0.2, 1.0))
		missing.position = Vector3(0.0, 0.72 * s, 0.0)
		missing.rotation.y = deg_to_rad(17.0)
		trolley.add_child(missing)
	else:
		for log_index: int in range(2):
			var cargo_log := MeshInstance3D.new()
			cargo_log.name = "CargoLog_%d" % log_index
			var cargo_log_mesh := CylinderMesh.new()
			cargo_log_mesh.top_radius = 0.07 * s
			cargo_log_mesh.bottom_radius = 0.07 * s
			cargo_log_mesh.height = 0.72 * s
			cargo_log_mesh.radial_segments = 8
			cargo_log.mesh = cargo_log_mesh
			cargo_log.rotation.z = PI * 0.5
			cargo_log.position = Vector3(0.0, 0.62 * s, (float(log_index) - 0.5) * 0.18 * s)
			cargo_log.material_override = _make_material(Color(0.48, 0.28, 0.11, 1.0))
			trolley.add_child(cargo_log)

	return trolley


func _add_cargo_trolley_craft_marker(trolley: Node3D) -> void:
	var total := maxf(_cargo_trolley_craft_total_seconds, 0.001)
	var progress := clampf(1.0 - _cargo_trolley_craft_remaining_seconds / total, 0.0, 1.0)
	var s := maxf(cargo_trolley_visual_scale, 0.1)
	var marker := _make_camp_box("CraftProgress", Vector3(maxf(progress, 0.08) * 0.72 * s, 0.06 * s, 0.08 * s), Color(0.95, 0.72, 0.18, 1.0))
	marker.position = Vector3((progress - 1.0) * 0.36 * s, 1.02 * s, 0.0)
	trolley.add_child(marker)


func _attach_resource_icon(visual: Node3D, resource_type: StringName) -> void:
	var existing := visual.get_node_or_null("ResourceIcon")
	if existing:
		existing.queue_free()

	var icon := Node3D.new()
	icon.name = "ResourceIcon"
	icon.position = Vector3(0.0, carrier_resource_icon_height, 0.0)
	visual.add_child(icon)

	match resource_type:
		RESOURCE_WOOD:
			_build_wood_resource_icon(icon)
		RESOURCE_COW:
			_build_cow_resource_icon(icon)
		_:
			_build_food_resource_icon(icon)


func _build_food_resource_icon(icon: Node3D) -> void:
	var size := maxf(carrier_resource_icon_size, 0.05)
	var grain := MeshInstance3D.new()
	grain.name = "Food"
	var grain_mesh := SphereMesh.new()
	grain_mesh.radius = size * 0.5
	grain_mesh.height = size
	grain_mesh.radial_segments = 12
	grain_mesh.rings = 6
	grain.mesh = grain_mesh
	grain.material_override = _make_resource_icon_material(Color(0.96, 0.76, 0.22, 1.0))
	icon.add_child(grain)

	var mark := MeshInstance3D.new()
	mark.name = "FoodMark"
	var mark_mesh := CylinderMesh.new()
	mark_mesh.top_radius = size * 0.18
	mark_mesh.bottom_radius = size * 0.18
	mark_mesh.height = size * 0.16
	mark_mesh.radial_segments = 10
	mark.mesh = mark_mesh
	mark.rotation.x = PI * 0.5
	mark.position = Vector3(size * 0.2, 0.0, size * 0.38)
	mark.material_override = _make_resource_icon_material(Color(0.45, 0.28, 0.08, 1.0))
	icon.add_child(mark)


func _build_wood_resource_icon(icon: Node3D) -> void:
	var size := maxf(carrier_resource_icon_size, 0.05)
	for index: int in range(2):
		var log_mesh_instance := MeshInstance3D.new()
		log_mesh_instance.name = "WoodLog_%d" % index
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = size * 0.16
		log_mesh.bottom_radius = size * 0.16
		log_mesh.height = size * 0.92
		log_mesh.radial_segments = 10
		log_mesh_instance.mesh = log_mesh
		log_mesh_instance.rotation.z = PI * 0.5
		log_mesh_instance.rotation.y = deg_to_rad(14.0 if index == 0 else -14.0)
		log_mesh_instance.position = Vector3(0.0, (float(index) - 0.5) * size * 0.26, (float(index) - 0.5) * size * 0.18)
		log_mesh_instance.material_override = _make_resource_icon_material(Color(0.48, 0.28, 0.11, 1.0))
		icon.add_child(log_mesh_instance)


func _build_cow_resource_icon(icon: Node3D) -> void:
	var size := maxf(carrier_resource_icon_size, 0.05)
	var body := MeshInstance3D.new()
	body.name = "Cow"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(size * 0.9, size * 0.48, size * 0.42)
	body.mesh = body_mesh
	body.material_override = _make_resource_icon_material(Color(0.92, 0.88, 0.78, 1.0))
	icon.add_child(body)

	var spot := MeshInstance3D.new()
	spot.name = "CowSpot"
	var spot_mesh := BoxMesh.new()
	spot_mesh.size = Vector3(size * 0.28, size * 0.24, size * 0.05)
	spot.mesh = spot_mesh
	spot.position = Vector3(size * 0.14, size * 0.04, size * 0.24)
	spot.material_override = _make_resource_icon_material(Color(0.08, 0.07, 0.06, 1.0))
	icon.add_child(spot)


func _make_resource_icon_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 28
	return material


func _get_carrier_departure_offset(index: int, total: int) -> Vector3:
	var columns := maxi(ceili(sqrt(float(maxi(total, 1)))), 1)
	var row := int(index / columns)
	var column := index % columns
	var rows := maxi(ceili(float(total) / float(columns)), 1)
	var spacing := maxf(carrier_formation_spacing, 0.2)
	return Vector3(
		(float(column) - float(columns - 1) * 0.5) * spacing,
		0.0,
		(float(row) - float(rows - 1) * 0.5) * spacing
	)


func _update_cargo_trolley_crafting(delta: float) -> void:
	if not _cargo_trolley_crafting:
		return

	_cargo_trolley_craft_remaining_seconds = maxf(_cargo_trolley_craft_remaining_seconds - delta, 0.0)
	var current_tick := ceili(_cargo_trolley_craft_remaining_seconds)
	if current_tick != _cargo_trolley_craft_emit_tick:
		_cargo_trolley_craft_emit_tick = current_tick
		_rebuild_cargo_trolley_visuals()
		_emit_logistics_changed()
	if _cargo_trolley_craft_remaining_seconds <= 0.0:
		_complete_cargo_trolley_craft()


func _complete_cargo_trolley_craft() -> void:
	if not _cargo_trolley_crafting:
		return
	_cargo_trolley_crafting = false
	_cargo_trolley_craft_remaining_seconds = 0.0
	_cargo_trolley_craft_total_seconds = 0.0
	_cargo_trolley_craft_emit_tick = -1
	cargo_trolley_count += 1
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()


func _update_carrier_tasks(delta: float) -> void:
	if _carrier_tasks.is_empty():
		return

	var changed := false
	for index: int in range(_carrier_tasks.size() - 1, -1, -1):
		var task := _carrier_tasks[index]
		var complete := _update_carrier_task(task, delta)
		_carrier_tasks[index] = task
		if complete:
			_finish_carrier_task(task)
			_carrier_tasks.remove_at(index)
			changed = true
	if changed:
		_rebuild_cargo_trolley_visuals()
		_emit_logistics_changed()


func _update_carrier_task(task: Dictionary, delta: float) -> bool:
	var state := StringName(task.get("state", TASK_TO_TARGET))
	match state:
		TASK_TO_TARGET:
			var target: Vector3 = task.get("target", global_position)
			if _move_carrier_visuals(task, target, delta):
				_collect_carrier_resource(task)
				task["work_remaining"] = maxf(carrier_work_seconds, 0.0)
				task["state"] = TASK_WORKING
		TASK_WORKING:
			var remaining := maxf(float(task.get("work_remaining", 0.0)) - delta, 0.0)
			task["work_remaining"] = remaining
			if remaining <= 0.0:
				task["state"] = TASK_RETURNING
		TASK_RETURNING:
			if _move_carrier_visuals(task, global_position, delta):
				_receive_carrier_resource(task)
				return true
	return false


func _move_carrier_visuals(task: Dictionary, destination: Vector3, delta: float) -> bool:
	var visuals := task.get("visuals", []) as Array[Node3D]
	if visuals.is_empty():
		return true

	var all_arrived := true
	for index: int in range(visuals.size()):
		var visual := visuals[index]
		if not is_instance_valid(visual):
			continue

		var local_destination := _snap_world_point(destination + _get_carrier_departure_offset(index, visuals.size()))
		var to_target := local_destination - visual.global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > carrier_arrival_radius:
			all_arrived = false
			var direction := to_target / distance
			if visual.has_method("set_formation_walking"):
				visual.call("set_formation_walking", true, carrier_speed_mps)
			visual.global_position += direction * minf(maxf(carrier_speed_mps, 0.1) * delta, distance)
			var snapped := _snap_world_point(visual.global_position)
			visual.global_position.y = snapped.y
			var target_yaw := atan2(-direction.x, -direction.z)
			visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(delta * carrier_turn_responsiveness, 0.0, 1.0))
		else:
			visual.global_position = local_destination
			if visual.has_method("set_formation_walking"):
				visual.call("set_formation_walking", false, carrier_speed_mps)
	return all_arrived


func _collect_carrier_resource(task: Dictionary) -> void:
	if float(task.get("amount_kg", 0.0)) > 0.0:
		return

	var source := task.get("source") as Node
	if not is_instance_valid(source):
		task["requested_amount_kg"] = 0.0
		return

	var requested := maxf(float(task.get("requested_amount_kg", 0.0)), 0.0)
	var resource_type := StringName(task.get("resource_type", &""))
	var extra := task.get("extra", {}) as Dictionary
	match resource_type:
		RESOURCE_FOOD:
			if source.has_method("withdraw_food_kg"):
				task["amount_kg"] = maxf(float(source.call("withdraw_food_kg", requested)), 0.0)
		RESOURCE_WOOD:
			if source.has_method("harvest_wood_cell"):
				task["amount_kg"] = maxf(float(source.call("harvest_wood_cell", extra.get("cell", Vector2i.ZERO), requested)), 0.0)
		RESOURCE_COW:
			if source.has_method("pickup_cow_cell") and bool(source.call("pickup_cow_cell", extra.get("cell", Vector2i.ZERO))):
				task["amount_kg"] = 1.0


func _receive_carrier_resource(task: Dictionary) -> void:
	var resource_type := StringName(task.get("resource_type", &""))
	match resource_type:
		RESOURCE_FOOD:
			var amount := minf(maxf(float(task.get("amount_kg", 0.0)), 0.0), get_free_carry_capacity_kg())
			if _camp_established:
				camp_food_kg += amount
			else:
				carried_food_kg += amount
		RESOURCE_WOOD:
			var amount := minf(maxf(float(task.get("amount_kg", 0.0)), 0.0), get_free_carry_capacity_kg())
			if _camp_established:
				camp_wood_kg += amount
			else:
				carried_wood_kg += amount
		RESOURCE_COW:
			if float(task.get("amount_kg", 0.0)) > 0.0:
				cow_count += 1
	_emit_logistics_changed()


func _finish_carrier_task(task: Dictionary) -> void:
	_busy_carrier_soldiers = maxi(_busy_carrier_soldiers - int(task.get("soldiers", 0)), 0)
	var visuals := task.get("visuals", []) as Array[Node3D]
	for visual: Node3D in visuals:
		if is_instance_valid(visual):
			_return_carrier_soldier_to_formation(visual)


func _return_carrier_soldier_to_formation(soldier: Node3D) -> void:
	if not _soldier_container or not is_instance_valid(soldier):
		return

	_clear_carrier_decoration(soldier)
	if soldier.has_method("set_formation_walking"):
		soldier.call("set_formation_walking", _state == STATE_MOVING, _get_current_movement_speed_mps())
	var original_name := String(soldier.get_meta(&"troop_carrier_original_name", String(soldier.name)))
	soldier.name = original_name
	soldier.remove_meta(&"troop_carrier_active")
	soldier.remove_meta(&"troop_carrier_original_name")

	var previous_transform := soldier.global_transform
	if soldier.get_parent():
		soldier.get_parent().remove_child(soldier)
	_soldier_container.add_child(soldier)
	soldier.owner = null
	soldier.top_level = true
	soldier.global_transform = previous_transform
	var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
	if soldier.has_method("set_independent_move_target"):
		soldier.call("set_independent_move_target", _formation_slot_to_world(slot), maxf(formation_slot_follow_speed, 0.1), maxf(arrival_radius * 0.32, 0.18))
	else:
		_update_formation_soldier_slots(0.0)


func _rebuild_camp_visual() -> void:
	_clear_camp_visual()
	_camp_node = Node3D.new()
	_camp_node.name = CAMP_NODE_NAME
	add_child(_camp_node)
	_camp_node.owner = null
	_camp_node.top_level = true
	_camp_node.global_position = _camp_world_position

	var range_ring := MeshInstance3D.new()
	range_ring.name = "CampPackRange"
	range_ring.mesh = _build_ring_mesh(camp_pack_range_m)
	range_ring.position.y = ring_surface_offset + 0.04
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	range_ring.material_override = _make_camp_range_material()
	_camp_node.add_child(range_ring)

	var camp_scale := _get_camp_visual_scale()
	var living_hut_count := get_camp_living_hut_count()
	var living_hut_columns := _get_camp_living_hut_columns(living_hut_count)
	var living_hut_rows := ceili(float(living_hut_count) / float(maxi(living_hut_columns, 1)))
	var camp_footprint_size := Vector3(
		maxf(12.5, float(living_hut_columns) * 3.45 * camp_scale + 6.5 * camp_scale),
		0.08,
		maxf(9.0, float(living_hut_rows) * 2.8 * camp_scale + 6.8 * camp_scale)
	)

	_add_camp_storage_hut(Vector3(-2.85 * camp_scale, 0.0, -1.7 * camp_scale), camp_scale)
	_add_camp_supply_rack(Vector3(1.55 * camp_scale, 0.0, -1.85 * camp_scale), camp_scale)
	_add_camp_fire(Vector3(0.25 * camp_scale, 0.0, 0.65 * camp_scale), camp_scale)

	var hut_colors: Array[Color] = [
		Color(0.62, 0.54, 0.38, 1.0),
		Color(0.52, 0.46, 0.34, 1.0),
		Color(0.68, 0.58, 0.42, 1.0),
		Color(0.58, 0.50, 0.36, 1.0),
	]
	for hut_index: int in range(living_hut_count):
		_add_camp_tent(
			_get_camp_living_hut_position(hut_index, living_hut_count),
			deg_to_rad(-12.0 + float((hut_index * 13) % 31)),
			"LivingHut_%02d" % hut_index,
			hut_colors[hut_index % hut_colors.size()]
		)

	var flag_x := camp_footprint_size.x * 0.42
	var flag_z := -camp_footprint_size.z * 0.34
	var watch_post := _make_camp_box("WatchPost", Vector3(0.48, 2.6, 0.48) * camp_scale, Color(0.38, 0.24, 0.1, 1.0))
	watch_post.position = Vector3(flag_x, 1.32 * camp_scale, flag_z)
	_camp_node.add_child(watch_post)

	var flag := _create_flag("CampFlag", troop_flag_color, team_flag_color)
	flag.position = Vector3(flag_x, 3.08 * camp_scale, flag_z)
	flag.scale = Vector3.ONE * 1.75 * camp_scale
	_camp_node.add_child(flag)

	var proxy := StaticBody3D.new()
	proxy.name = "CampClickProxy"
	proxy.collision_layer = selection_collision_layer
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	proxy.set_meta(SELECTABLE_TYPE_META, SELECTABLE_CAMP_TYPE)
	proxy.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(7.0, maxf(camp_footprint_size.x, camp_footprint_size.z) * 0.58)
	cylinder.height = 5.5 * camp_scale
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.25 * camp_scale, 0.0)
	proxy.add_child(shape)
	_camp_node.add_child(proxy)


func _get_camp_visual_scale() -> float:
	return maxf(camp_building_scale, 0.1)


func _get_camp_living_hut_columns(hut_count: int) -> int:
	return clampi(ceili(sqrt(float(maxi(hut_count, 1)))), 1, 4)


func _get_camp_living_hut_position(index: int, hut_count: int) -> Vector3:
	var scale := _get_camp_visual_scale()
	var columns := _get_camp_living_hut_columns(hut_count)
	var column := index % columns
	var row := int(index / columns)
	var x := (float(column) - float(columns - 1) * 0.5) * 2.95 * scale
	if row % 2 == 1:
		x += 0.42 * scale
	var z := 2.1 * scale + float(row) * 2.55 * scale
	return Vector3(x, 0.0, z)


func _add_camp_tent(position: Vector3, yaw: float, node_name: String, color: Color) -> void:
	if not _camp_node:
		return
	var scale := _get_camp_visual_scale()
	var tent := Node3D.new()
	tent.name = node_name
	tent.position = position
	tent.rotation.y = yaw
	_camp_node.add_child(tent)

	for x: float in [-0.72, 0.72]:
		for z: float in [-0.5, 0.5]:
			var stilt := _make_camp_cylinder("Stilt", 0.045 * scale, 0.58 * scale, Color(0.32, 0.2, 0.09, 1.0), 8)
			stilt.position = Vector3(x * scale, 0.29 * scale, z * scale)
			tent.add_child(stilt)

	var body := _make_camp_box("WovenBody", Vector3(1.72, 0.9, 1.18) * scale, color.darkened(0.1))
	body.position = Vector3(0.0, 0.92 * scale, 0.0)
	tent.add_child(body)

	for x: float in [-0.54, 0.0, 0.54]:
		var slat := _make_camp_box("WallSlat", Vector3(0.035, 0.78, 1.24) * scale, Color(0.43, 0.3, 0.14, 1.0))
		slat.position = Vector3(x * scale, 0.92 * scale, 0.0)
		tent.add_child(slat)

	var door := _make_camp_box("DoorMat", Vector3(0.46, 0.66, 0.035) * scale, Color(0.24, 0.16, 0.08, 1.0))
	door.position = Vector3(0.0, 0.78 * scale, -0.61 * scale)
	tent.add_child(door)

	var roof := MeshInstance3D.new()
	roof.name = "ThatchedRoof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.28, 0.96, 1.72) * scale
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, 1.54 * scale, 0.0)
	roof.rotation.y = PI * 0.5
	roof.material_override = _make_material(Color(0.55, 0.47, 0.28, 1.0))
	tent.add_child(roof)

	var ridge := _make_camp_cylinder("RoofRidge", 0.035 * scale, 1.92 * scale, Color(0.28, 0.18, 0.08, 1.0), 8)
	ridge.position = Vector3(0.0, 1.98 * scale, 0.0)
	ridge.rotation.x = PI * 0.5
	tent.add_child(ridge)

	for side_z: float in [-0.8, 0.8]:
		var eave := _make_camp_box("EaveBeam", Vector3(2.2, 0.06, 0.08) * scale, Color(0.34, 0.22, 0.1, 1.0))
		eave.position = Vector3(0.0, 1.18 * scale, side_z * scale)
		tent.add_child(eave)


func _add_camp_storage_hut(position: Vector3, scale: float) -> void:
	if not _camp_node:
		return
	var storage := Node3D.new()
	storage.name = "CampStorage"
	storage.position = position
	storage.rotation.y = deg_to_rad(5.0)
	_camp_node.add_child(storage)

	for x: float in [-0.86, 0.86]:
		for z: float in [-0.64, 0.64]:
			var stilt := _make_camp_cylinder("StorageStilt", 0.06 * scale, 0.78 * scale, Color(0.3, 0.18, 0.08, 1.0), 8)
			stilt.position = Vector3(x * scale, 0.39 * scale, z * scale)
			storage.add_child(stilt)

	var deck := _make_camp_box("RaisedDeck", Vector3(2.24, 0.16, 1.7) * scale, Color(0.34, 0.23, 0.12, 1.0))
	deck.position = Vector3(0.0, 0.78 * scale, 0.0)
	storage.add_child(deck)

	var body := _make_camp_box("StorageBody", Vector3(1.88, 1.0, 1.26) * scale, Color(0.5, 0.38, 0.22, 1.0))
	body.position = Vector3(0.0, 1.36 * scale, 0.0)
	storage.add_child(body)

	for x: float in [-0.58, 0.0, 0.58]:
		var slat := _make_camp_box("StorageSlat", Vector3(0.04, 0.9, 1.32) * scale, Color(0.34, 0.23, 0.12, 1.0))
		slat.position = Vector3(x * scale, 1.36 * scale, 0.0)
		storage.add_child(slat)

	var door := _make_camp_box("StorageDoor", Vector3(0.52, 0.72, 0.04) * scale, Color(0.22, 0.14, 0.07, 1.0))
	door.position = Vector3(0.0, 1.22 * scale, -0.66 * scale)
	storage.add_child(door)

	var roof := MeshInstance3D.new()
	roof.name = "StorageThatchedRoof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.72, 1.04, 2.04) * scale
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, 2.08 * scale, 0.0)
	roof.rotation.y = PI * 0.5
	roof.material_override = _make_material(Color(0.62, 0.53, 0.31, 1.0))
	storage.add_child(roof)

	var sack := _make_camp_box("FoodSack", Vector3(0.34, 0.32, 0.28) * scale, Color(0.68, 0.58, 0.4, 1.0))
	sack.position = Vector3(-0.62 * scale, 0.98 * scale, -0.82 * scale)
	storage.add_child(sack)
	var wood_bundle := _make_camp_cylinder("WoodBundle", 0.08 * scale, 0.82 * scale, Color(0.46, 0.26, 0.1, 1.0), 8)
	wood_bundle.position = Vector3(0.62 * scale, 1.0 * scale, -0.82 * scale)
	wood_bundle.rotation.z = PI * 0.5
	storage.add_child(wood_bundle)

	var flag := _create_flag("CampStorageFlag", troop_flag_color, team_flag_color)
	flag.position = Vector3(1.18 * scale, 2.94 * scale, -0.68 * scale)
	flag.scale = Vector3.ONE * 1.28 * scale
	storage.add_child(flag)


func _add_camp_supply_rack(position: Vector3, scale: float) -> void:
	if not _camp_node:
		return
	var rack := Node3D.new()
	rack.name = "CampSupplyRack"
	rack.position = position
	rack.rotation.y = deg_to_rad(-11.0)
	_camp_node.add_child(rack)

	for x: float in [-0.62, 0.62]:
		var post := _make_camp_cylinder("RackPost", 0.045 * scale, 1.2 * scale, Color(0.28, 0.18, 0.08, 1.0), 8)
		post.position = Vector3(x * scale, 0.6 * scale, 0.0)
		rack.add_child(post)

	var top_beam := _make_camp_box("RackTopBeam", Vector3(1.52, 0.08, 0.08) * scale, Color(0.32, 0.21, 0.1, 1.0))
	top_beam.position = Vector3(0.0, 1.18 * scale, 0.0)
	rack.add_child(top_beam)

	for index: int in range(4):
		var log := _make_camp_cylinder("StackedLog_%d" % index, 0.075 * scale, 1.22 * scale, Color(0.45, 0.27, 0.11, 1.0), 8)
		log.position = Vector3(0.0, (0.16 + float(index) * 0.11) * scale, (-0.3 + float(index % 2) * 0.18) * scale)
		log.rotation.z = PI * 0.5
		rack.add_child(log)

	var crate := _make_camp_box("ToolCrate", Vector3(0.56, 0.36, 0.42) * scale, Color(0.31, 0.2, 0.09, 1.0))
	crate.position = Vector3(0.0, 0.18 * scale, 0.48 * scale)
	rack.add_child(crate)


func _add_camp_fire(position: Vector3, scale: float) -> void:
	if not _camp_node:
		return
	var fire := Node3D.new()
	fire.name = "CampFire"
	fire.position = position
	_camp_node.add_child(fire)

	for index: int in range(8):
		var angle := TAU * float(index) / 8.0
		var stone := _make_camp_cylinder("FireStone_%d" % index, 0.08 * scale, 0.1 * scale, Color(0.22, 0.2, 0.17, 1.0), 7)
		stone.position = Vector3(cos(angle) * 0.42 * scale, 0.05 * scale, sin(angle) * 0.42 * scale)
		fire.add_child(stone)

	for index: int in range(3):
		var log := _make_camp_cylinder("FireLog_%d" % index, 0.055 * scale, 0.78 * scale, Color(0.37, 0.22, 0.09, 1.0), 8)
		log.position = Vector3(0.0, 0.13 * scale, 0.0)
		log.rotation.z = PI * 0.5
		log.rotation.y = TAU * float(index) / 3.0
		fire.add_child(log)

	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var flame_mesh := PrismMesh.new()
	flame_mesh.size = Vector3(0.38, 0.72, 0.38) * scale
	flame.mesh = flame_mesh
	flame.position = Vector3(0.0, 0.58 * scale, 0.0)
	flame.material_override = _make_material(Color(1.0, 0.48, 0.1, 0.88))
	fire.add_child(flame)


func _make_camp_box(node_name: String, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	return instance


func _make_camp_cylinder(node_name: String, radius: float, height: float, color: Color, radial_segments: int = 10) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = maxi(radial_segments, 3)
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	return instance


func _make_camp_range_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 21
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 0.82, 0.28, 0.32)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.18, 1.0)
	material.emission_energy_multiplier = 0.14
	return material


func _clear_camp_visual() -> void:
	if (
		_cargo_trolley_visual_container
		and is_instance_valid(_cargo_trolley_visual_container)
		and _camp_node
		and _cargo_trolley_visual_container.get_parent() == _camp_node
	):
		_clear_cargo_trolley_visuals()
	if _camp_node and is_instance_valid(_camp_node):
		remove_child(_camp_node)
		_camp_node.free()
	_camp_node = null


func _emit_destination_changed() -> void:
	destination_changed.emit(get_troop_summary())


func _emit_logistics_changed() -> void:
	logistics_changed.emit(get_troop_summary())


func _emit_mode_changed() -> void:
	mode_changed.emit(get_troop_summary())


func _emit_combat_changed() -> void:
	combat_changed.emit(get_troop_summary())


func _maybe_emit_combat_changed(delta: float) -> void:
	_last_combat_emit_time += delta
	if _last_combat_emit_time < 0.35:
		return
	_last_combat_emit_time = 0.0
	_emit_combat_changed()


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _clear_children(node: Node) -> void:
	if not node:
		return
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false
