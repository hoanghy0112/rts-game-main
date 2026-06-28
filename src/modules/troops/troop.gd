extends Node3D
class_name Troop

signal selected_changed(selected: bool)
signal state_changed(state: StringName)
signal destination_changed(summary: Dictionary)
signal logistics_changed(summary: Dictionary)
signal mode_changed(summary: Dictionary)
signal combat_changed(summary: Dictionary)

const DEFAULT_SOLDIER_SCENE: PackedScene = preload("res://modules/units/troop_soldier/troop_soldier.tscn")
const CampScript = preload("res://modules/troops/camp.gd")
const TroopStatWorkerScript = preload("res://modules/troops/troop_stat_worker.gd")
const TroopCorpseManagerScript = preload("res://modules/troops/troop_corpse_manager.gd")
const TroopSpatialIndexScript = preload("res://modules/troops/troop_spatial_index.gd")
const DefaultTroopFormationStrategyScript = preload("res://modules/troops/logic/troop_grid_formation_strategy.gd")
const DefaultTroopMovementLogicScript = preload("res://modules/troops/logic/troop_movement_logic.gd")
const DefaultTroopCombatPositioningLogicScript = preload("res://modules/troops/logic/troop_combat_positioning_logic.gd")
const DefaultTroopSummaryBuilderScript = preload("res://modules/troops/logic/troop_summary_builder.gd")
const DefaultTroopSoldierBehaviorSetScript = preload("res://modules/units/troop_soldier/logic/troop_soldier_behavior_set.gd")
const DefaultTroopRuntimeContextScript = preload("res://modules/troops/logic/troop_runtime_context.gd")
const DefaultTroopServiceSetScript = preload("res://modules/troops/logic/troop_service_set.gd")

const STATE_IDLE := &"idle"
const STATE_MOVING := &"moving"
const STATE_BLOCKED := &"blocked"
const STATE_FIGHTING := &"fighting"

const COMBAT_RELATION_COMING := &"coming"
const COMBAT_RELATION_FIGHTING := &"fighting"

const MODE_REST := &"rest"
const MODE_TRAINING := &"training"
const MODE_DEFENSIVE := &"defensive"
const MODE_ATTACK := &"attack"

const MOVEMENT_WALKING := &"walking"
const MOVEMENT_RUNNING := &"running"

const TEAM_PLAYER := &"player"
const TEAM_ENEMY := &"enemy"
const TEAM_DESERTER := &"deserter"
const ALLY_ROUTE_LINE_COLOR := Color(0.12, 0.42, 1.0, 0.88)
const ENEMY_ROUTE_LINE_COLOR := Color(1.0, 0.12, 0.08, 0.88)
const ALLY_SOLDIER_ROBE_COLOR := Color(0.10, 0.26, 0.72, 1.0)
const ALLY_SOLDIER_ROBE_SHADOW_COLOR := Color(0.03, 0.08, 0.24, 1.0)
const ALLY_SOLDIER_TRIM_COLOR := Color(0.52, 0.70, 1.0, 1.0)
const ALLY_SOLDIER_PANTS_COLOR := Color(0.08, 0.12, 0.20, 1.0)
const ALLY_SOLDIER_WRAP_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ALLY_SOLDIER_HAT_COLOR := Color(0.03, 0.05, 0.10, 1.0)
const ALLY_SOLDIER_ACCENT_COLOR := Color(0.23, 0.52, 1.0, 1.0)
const ENEMY_SOLDIER_ROBE_COLOR := Color(0.42, 0.05, 0.04, 1.0)
const ENEMY_SOLDIER_ROBE_SHADOW_COLOR := Color(0.16, 0.02, 0.02, 1.0)
const ENEMY_SOLDIER_TRIM_COLOR := Color(0.94, 0.52, 0.24, 1.0)
const ENEMY_SOLDIER_PANTS_COLOR := Color(0.16, 0.12, 0.11, 1.0)
const ENEMY_SOLDIER_WRAP_COLOR := Color(0.56, 0.47, 0.39, 1.0)
const ENEMY_SOLDIER_HAT_COLOR := Color(0.05, 0.04, 0.035, 1.0)
const ENEMY_SOLDIER_ACCENT_COLOR := Color(0.98, 0.18, 0.08, 1.0)
const DESERTER_SOLDIER_ROBE_COLOR := Color(0.34, 0.52, 0.54, 1.0)
const DESERTER_SOLDIER_ROBE_SHADOW_COLOR := Color(0.08, 0.24, 0.28, 1.0)
const DESERTER_SOLDIER_TRIM_COLOR := Color(0.76, 0.56, 0.38, 1.0)
const DESERTER_SOLDIER_PANTS_COLOR := Color(0.78, 0.34, 0.18, 1.0)
const DESERTER_SOLDIER_WRAP_COLOR := Color(0.86, 0.82, 0.74, 1.0)
const DESERTER_SOLDIER_HAT_COLOR := Color(0.05, 0.09, 0.13, 1.0)
const DESERTER_SOLDIER_ACCENT_COLOR := Color(0.7, 0.12, 0.08, 1.0)

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"
const SELECTABLE_CAMP_TYPE := &"camp"

const SOLDIER_CONTAINER_NAME := "Soldiers"
const RING_NODE_NAME := "TroopRing"
const MANAGEMENT_FLAG_NODE_NAME := "TroopManagementFlag"
const MANAGEMENT_FLAG_SPRITE_NAME := "Gonfalon"
const SELECTION_PROXY_NAME := "TroopFlagClickProxy"
const SELECTION_HIGHLIGHT_NAME := "TroopSelectionHighlight"
const ATTACK_ZONE_NODE_NAME := "TroopAttackZone"
const FLAG_BORDER_NODE_NAME := "FlagHoverBorder"
const UNIT_HOVER_BORDER_NAME := "TroopUnitHoverBorder"
const UNIT_SELECTION_MARKER_NAME := "TroopUnitSelectionMarker"
const UNIT_SELECTION_PROXY_NAME := "TroopUnitClickProxy"
const ROUTE_VISUAL_NAME := "TroopRouteVisual"
const SOLDIER_BATCH_RENDERER_NAME := "TroopSoldierBatchRenderer"
const LIVE_ANIMATION_SOURCE_META := &"troop_live_animation_source"
const LIVE_CORPSE_NODE_META := &"troop_live_corpse_node"
const COMBAT_DEBUG_LINES_NODE_NAME := "TroopCombatDebugLines"
const CARRIER_CONTAINER_NAME := "CarrierTasks"
const CAMP_NODE_NAME := "TroopCamp"
const MANAGEMENT_FLAG_TEXTURE_WIDTH := 96
const MANAGEMENT_FLAG_TEXTURE_HEIGHT := 144
const MANAGEMENT_FLAG_BORDER_PIXEL_SIZE_MULTIPLIER := 1.08

const RESOURCE_FOOD := &"food"
const RESOURCE_WOOD := &"wood"
const RESOURCE_COW := &"cow"
const TASK_TO_TARGET := &"to_target"
const TASK_WORKING := &"working"
const TASK_RETURNING := &"returning"
const MISSION_NONE := &"none"
const MISSION_FOOD := &"food"
const MISSION_WOOD := &"wood"
const MISSION_TO_TARGET := &"to_target"
const MISSION_WORKING := &"working"
const MISSION_RETURNING := &"returning"
const MISSION_COMPLETE := &"complete"

@export_group("Identity")
@export var troop_id: StringName = &"troop_01"
@export var display_name := "Troop"
@export var team_id: StringName = TEAM_PLAYER:
	set(value):
		team_id = StringName(value)
		_apply_team_outfit_defaults()
		if is_inside_tree():
			_apply_outfit_to_soldiers()
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
			if _suppress_formation_rebuild:
				_refresh_formation_slot_metas()
			else:
				rebuild_formation()
@export_range(0.2, 16.0, 0.05, "or_greater") var formation_spacing: float = 4.35:
	set(value):
		formation_spacing = maxf(value, 0.2)
		if is_inside_tree():
			rebuild_formation()
@export_range(0.1, 8.0, 0.05, "or_greater") var soldier_scale: float = 1.0:
	set(value):
		soldier_scale = maxf(value, 0.1)
		if is_inside_tree():
			rebuild_formation()

@export_group("Dependency Injection")
@export var formation_strategy: Resource
@export var movement_logic: Resource
@export var combat_positioning_logic: Resource
@export var summary_builder: Resource
@export var soldier_behavior_set: Resource
@export var service_set: Resource

@export_group("Soldier Outfit")
@export var soldier_robe_color: Color = ALLY_SOLDIER_ROBE_COLOR:
	set(value):
		soldier_robe_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_robe_shadow_color: Color = ALLY_SOLDIER_ROBE_SHADOW_COLOR:
	set(value):
		soldier_robe_shadow_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_trim_color: Color = ALLY_SOLDIER_TRIM_COLOR:
	set(value):
		soldier_trim_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_pants_color: Color = ALLY_SOLDIER_PANTS_COLOR:
	set(value):
		soldier_pants_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_wrap_color: Color = ALLY_SOLDIER_WRAP_COLOR:
	set(value):
		soldier_wrap_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_hat_color: Color = ALLY_SOLDIER_HAT_COLOR:
	set(value):
		soldier_hat_color = value
		if is_inside_tree():
			_apply_outfit_to_soldiers()
@export var soldier_accent_color: Color = ALLY_SOLDIER_ACCENT_COLOR:
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
@export var hand_flags_enabled := false:
	set(value):
		hand_flags_enabled = value
		if is_inside_tree():
			rebuild_formation()
@export_range(-45.0, 45.0, 0.5) var carried_flag_roll_degrees: float = -8.0:
	set(value):
		carried_flag_roll_degrees = value
		if is_inside_tree():
			rebuild_formation()
@export var management_flag_offset: Vector3 = Vector3(0.0, 0.16, 0.0):
	set(value):
		management_flag_offset = value
		if is_inside_tree():
			_rebuild_management_flag()
@export_range(2.0, 14.0, 0.05, "or_greater") var management_flag_pole_height: float = 7.2:
	set(value):
		management_flag_pole_height = maxf(value, 2.0)
		if is_inside_tree():
			_rebuild_management_flag()
@export_range(0.01, 0.5, 0.005, "or_greater") var management_flag_pole_radius: float = 0.055:
	set(value):
		management_flag_pole_radius = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_management_flag()
@export var management_flag_banner_size: Vector2 = Vector2(1.8, 2.9):
	set(value):
		management_flag_banner_size = Vector2(maxf(value.x, 0.2), maxf(value.y, 0.2))
		if is_inside_tree():
			_rebuild_management_flag()
@export var management_flag_face_camera := true
@export_range(0.0001, 0.2, 0.00005, "or_greater") var management_flag_pixel_size: float = 0.00075:
	set(value):
		management_flag_pixel_size = maxf(value, 0.0001)
		if is_inside_tree():
			_update_management_flag_camera_scale(true)
@export_range(0.0001, 0.2, 0.00005, "or_greater") var management_flag_min_pixel_size: float = 0.00028:
	set(value):
		management_flag_min_pixel_size = maxf(value, 0.0001)
		if is_inside_tree():
			_update_management_flag_camera_scale(true)
@export_range(1.0, 2000.0, 1.0, "or_greater") var management_flag_near_camera_distance_m: float = 32.0:
	set(value):
		management_flag_near_camera_distance_m = maxf(value, 1.0)
		if is_inside_tree():
			_update_management_flag_camera_scale(true)
@export_range(1.0, 4000.0, 1.0, "or_greater") var management_flag_far_camera_distance_m: float = 260.0:
	set(value):
		management_flag_far_camera_distance_m = maxf(value, 1.0)
		if is_inside_tree():
			_update_management_flag_camera_scale(true)

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
			_rebuild_selection_highlight()

@export_range(0.0, 16.0, 0.05, "or_greater") var selection_highlight_surface_offset: float = 0.28:
	set(value):
		selection_highlight_surface_offset = maxf(value, 0.0)
		if is_inside_tree():
			_rebuild_selection_highlight()
@export_range(0.1, 4.0, 0.05, "or_greater") var selection_highlight_radius_multiplier: float = 1.18:
	set(value):
		selection_highlight_radius_multiplier = maxf(value, 0.1)
		if is_inside_tree():
			_rebuild_selection_highlight()
@export_range(0.05, 2.0, 0.01, "or_greater") var unit_selection_marker_radius: float = 0.58:
	set(value):
		unit_selection_marker_radius = maxf(value, 0.05)
		if is_inside_tree():
			_rebuild_unit_selection_markers()
@export_range(0.0, 2.0, 0.005, "or_greater") var attack_zone_surface_offset: float = 0.026:
	set(value):
		attack_zone_surface_offset = maxf(value, 0.0)
		if is_inside_tree():
			_update_attack_zone_indicator()
@export_range(0.0, 1.0, 0.01) var attack_zone_inner_alpha: float = 0.025:
	set(value):
		attack_zone_inner_alpha = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_rebuild_attack_zone_indicator()
@export_range(0.0, 1.0, 0.01) var attack_zone_outer_alpha: float = 0.0:
	set(value):
		attack_zone_outer_alpha = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_rebuild_attack_zone_indicator()
@export_range(0.01, 2.0, 0.01, "or_greater") var attack_zone_border_width: float = 0.22:
	set(value):
		attack_zone_border_width = maxf(value, 0.01)
		if is_inside_tree():
			_rebuild_attack_zone_indicator()
@export_range(0.0, 1.0, 0.01) var attack_zone_border_alpha: float = 0.72:
	set(value):
		attack_zone_border_alpha = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_rebuild_attack_zone_indicator()

@export_group("Selection")
@export_flags_3d_physics var selection_collision_layer: int = 1 << 5:
	set(value):
		selection_collision_layer = value
		if is_inside_tree():
			_rebuild_selection_proxy()
			_rebuild_unit_selection_proxies()
@export_range(0.1, 4.0, 0.05, "or_greater") var unit_selection_proxy_radius: float = 0.85:
	set(value):
		unit_selection_proxy_radius = maxf(value, 0.1)
		if is_inside_tree():
			_rebuild_unit_selection_proxies()
@export_range(0.5, 8.0, 0.05, "or_greater") var unit_selection_proxy_height: float = 2.6:
	set(value):
		unit_selection_proxy_height = maxf(value, 0.5)
		if is_inside_tree():
			_rebuild_unit_selection_proxies()

@export_group("Movement")
@export var movement_map: Resource
@export_file("*.res", "*.tres") var movement_map_path := ""
@export_node_path("Node3D") var terrain_path: NodePath
@export_node_path("Node") var time_system_path: NodePath
@export_range(0.1, 40.0, 0.1, "or_greater") var movement_speed_mps: float = 4.5
@export_range(1.0, 4.0, 0.05, "or_greater") var running_speed_multiplier: float = 3.0
@export_range(0.1, 32.0, 0.1, "or_greater") var arrival_radius: float = 1.25
@export_range(0, 64, 1, "or_greater") var nearest_walkable_search_radius_cells: int = 12
@export var path_smoothing_enabled := true
@export_range(0.0, 3.0, 0.05, "or_greater") var path_corner_radius_cells: float = 1.35
@export_range(0, 16, 1, "or_greater") var path_corner_samples: int = 8
@export_range(0.0, 12.0, 0.05, "or_greater") var route_steering_lookahead_m: float = 3.0
@export_range(5.0, 360.0, 1.0, "or_greater") var formation_turn_rate_degrees: float = 85.0
@export_range(5.0, 180.0, 1.0, "or_greater") var formation_turn_slowdown_angle_degrees: float = 72.0
@export_range(0.05, 1.0, 0.01) var formation_min_turn_speed_multiplier: float = 0.32
@export_range(0.5, 24.0, 0.1, "or_greater") var formation_slot_follow_speed: float = 4.2
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
@export_range(0.0, 8.0, 0.05, "or_greater") var formation_collision_distance: float = 2.64
@export_range(0.0, 16.0, 0.05, "or_greater") var formation_collision_push_speed: float = 3.2
@export_range(0.05, 2.0, 0.05, "or_greater") var route_refresh_interval: float = 0.25
@export_range(1, 512, 1, "or_greater") var soldier_path_queries_per_tick: int = 64
@export var route_debug_visuals_enabled: bool = true:
	set(value):
		route_debug_visuals_enabled = value
		if is_inside_tree():
			if route_debug_visuals_enabled:
				_update_route_visual()
			else:
				_clear_route_visual()
@export var individual_route_debug_visuals_enabled: bool = false:
	set(value):
		individual_route_debug_visuals_enabled = value
		if is_inside_tree():
			_update_route_visual()

@export_group("Combat Debug")
@export var combat_debug_lines_enabled: bool = false:
	set(value):
		_set_combat_debug_lines_enabled(value)
	get:
		return _combat_debug_lines_enabled_value
@export var combat_debug_line_color: Color = Color(1.0, 0.22, 0.08, 0.92):
	set(value):
		combat_debug_line_color = value
		if _combat_debug_line_material:
			_combat_debug_line_material.albedo_color = combat_debug_line_color
@export var combat_debug_line_coming_color: Color = Color(0.36, 0.78, 1.0, 0.86):
	set(value):
		combat_debug_line_coming_color = value
		if _combat_debug_line_coming_material:
			_combat_debug_line_coming_material.albedo_color = combat_debug_line_coming_color
@export_range(0.0, 6.0, 0.05, "or_greater") var combat_debug_line_height: float = 1.35

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
			_sync_independent_camp_settings()
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_living_hut_wood_cost_kg: float = 100.0:
	set(value):
		camp_living_hut_wood_cost_kg = maxf(value, 0.0)
		if is_inside_tree():
			_emit_logistics_changed()
@export_range(0.1, 8.0, 0.05, "or_greater") var camp_building_scale: float = 2.1:
	set(value):
		camp_building_scale = maxf(value, 0.1)
		if is_inside_tree() and _camp_established:
			_sync_independent_camp_settings()
@export_range(1.0, 256.0, 0.5, "or_greater") var camp_pack_range_m: float = 36.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_food_kg: float = 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var camp_wood_kg: float = 0.0
@export_range(0.1, 20.0, 0.1, "or_greater") var carrier_speed_mps: float = 3.2
@export_range(0.05, 8.0, 0.05, "or_greater") var carrier_arrival_radius: float = 0.55
@export_range(0.0, 10.0, 0.05, "or_greater") var carrier_work_seconds: float = 1.0
@export_range(0.2, 16.0, 0.05, "or_greater") var carrier_formation_spacing: float = 3.75
@export_range(0.5, 8.0, 0.05, "or_greater") var carrier_resource_icon_height: float = 2.45
@export_range(0.05, 2.0, 0.05, "or_greater") var carrier_resource_icon_size: float = 0.34
@export_range(1.0, 32.0, 0.1, "or_greater") var carrier_turn_responsiveness: float = 14.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var carried_food_kg: float = 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var carried_wood_kg: float = 0.0
@export_range(0, 64, 1, "or_greater") var cargo_trolley_count: int = 0
@export_range(0, 64, 1, "or_greater") var cow_count: int = 0

@export_group("Mission")
@export var is_mission_troop := false
@export_range(0.05, 1.0, 0.01) var deserter_persuasion_chance: float = 0.65
@export_range(1.0, 512.0, 1.0, "or_greater") var deserter_persuasion_range_m: float = 200.0
@export_range(200.0, 2000.0, 1.0, "or_greater") var deserter_min_spawn_distance_m: float = 200.0
@export_range(200.0, 2000.0, 1.0, "or_greater") var deserter_max_spawn_distance_m: float = 2000.0

@export_group("Soldier Stats")
@export_range(1.0, 1000.0, 1.0, "or_greater") var base_soldier_strength: float = 40.0
@export_range(0.0, 500.0, 1.0, "or_greater") var soldier_strength_variance: float = 6.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var base_soldier_damage: float = 8.0
@export_range(0.0, 500.0, 0.1, "or_greater") var soldier_damage_variance: float = 1.2
@export_range(0.0, 100.0, 0.1) var base_soldier_morale: float = 72.0
@export_range(0.0, 100.0, 0.1) var soldier_morale_variance: float = 10.0
@export_range(1.0, 1000.0, 0.1, "or_greater") var base_soldier_endurance: float = 80.0
@export_range(0.0, 500.0, 0.1, "or_greater") var soldier_endurance_variance: float = 8.0
@export_range(0.1, 30.0, 0.1, "or_greater") var base_soldier_run_speed: float = 3.1
@export_range(0.0, 20.0, 0.1, "or_greater") var soldier_run_speed_variance: float = 0.35
@export var combat_seed: int = 24101

@export_group("Combat")
@export_range(1.0, 256.0, 0.5, "or_greater") var detection_range_m: float = 34.0
@export_range(1.0, 512.0, 0.5, "or_greater") var ai_chase_detection_range_m: float = 96.0
@export_range(1.0, 256.0, 0.5, "or_greater") var defensive_engagement_range_m: float = 18.0
@export_range(1.0, 256.0, 0.5, "or_greater") var combat_range_m: float = 18.0
@export_range(0.05, 10.0, 0.05, "or_greater") var combat_scan_interval: float = 0.35
@export_range(0.02, 0.5, 0.01) var combat_engagement_zone_refresh_interval: float = 0.08
@export_range(0.05, 10.0, 0.05, "or_greater") var attack_interval: float = 1.1
@export_range(0.4, 16.0, 0.05, "or_greater") var combat_spear_range_m: float = 1.9
@export_range(0.15, 8.0, 0.05, "or_greater") var soldier_personal_space_radius: float = 2.88
@export_range(0.15, 8.0, 0.05, "or_greater") var enemy_personal_space_radius: float = 3.28
@export_range(0.2, 12.0, 0.05, "or_greater") var combat_frontline_width_per_soldier: float = 4.4
@export_range(0.1, 24.0, 0.1, "or_greater") var combat_slot_follow_speed: float = 4.2
@export_range(0.0, 12.0, 0.05, "or_greater") var combat_separation_strength: float = 6.2
@export_range(0.0, 2.0, 0.01, "or_greater") var combat_attack_shuffle_radius: float = 0.0
@export_range(0.05, 4.0, 0.01, "or_greater") var combat_attack_shuffle_interval: float = 0.35
@export_range(0.01, 4.0, 0.01, "or_greater") var combat_attack_shuffle_speed: float = 0.55
@export_range(0.0, 0.5, 0.001) var combat_logic_interval: float = 0.033
@export_range(0.02, 1.0, 0.01) var combat_target_reassignment_interval: float = 0.45
@export_range(0.05, 2.0, 0.01) var combat_rebalance_interval: float = 1.20
@export_range(1, 512, 1, "or_greater") var combat_target_assignment_budget_per_tick: int = 32
@export_range(1, 1024, 1, "or_greater") var combat_attacker_updates_per_tick: int = 256
@export_range(0, 4096, 1, "or_greater") var combat_active_attacker_limit: int = 64
@export_range(0, 4096, 1, "or_greater") var combat_full_participation_soldier_threshold: int = 120
@export_range(1, 512, 1, "or_greater") var combat_separation_updates_per_tick: int = 2
@export_range(16, 4096, 1, "or_greater") var combat_pair_checks_budget_per_tick: int = 16
@export_range(0.02, 2.0, 0.01) var combat_steering_refresh_interval: float = 1.0
@export_range(0.0, 1.0, 0.01) var combat_steering_refresh_jitter: float = 0.35
@export_range(1, 64, 1, "or_greater") var combat_max_separation_neighbors: int = 12
@export_range(4, 96, 1, "or_greater") var combat_target_search_candidates: int = 24
@export_range(4, 96, 1, "or_greater") var combat_assignment_candidates: int = 24
@export_range(1, 16, 1, "or_greater") var combat_max_attackers_per_target: int = 4
@export_range(0.02, 1.0, 0.01) var combat_spatial_rebuild_interval: float = 0.20
@export_range(0.0, 100000.0, 10.0, "or_greater") var combat_target_load_penalty: float = 9000.0
@export_range(0.0, 100000.0, 10.0, "or_greater") var combat_target_stickiness_bonus: float = 4500.0
@export_range(0.2, 16.0, 0.05, "or_greater") var combat_socket_radius: float = 1.75
@export_range(0.05, 4.0, 0.05, "or_greater") var combat_socket_arrival_radius: float = 0.65
@export_range(0.05, 10.0, 0.05, "or_greater") var chase_repath_interval: float = 0.75
@export_range(1.0, 4.0, 0.05, "or_greater") var combat_engagement_break_range_multiplier: float = 1.45
@export_range(0.0, 5.0, 0.05, "or_greater") var combat_engagement_break_grace_seconds: float = 1.0
@export_range(0.0, 10.0, 0.05, "or_greater") var rest_engagement_delay: float = 2.5
@export_range(0.0, 10.0, 0.05, "or_greater") var training_engagement_delay: float = 2.0
@export_range(0.0, 10.0, 0.05, "or_greater") var defensive_engagement_delay: float = 0.25
@export_range(0.0, 10.0, 0.05, "or_greater") var attack_engagement_delay: float = 0.1
@export_range(0.0, 100.0, 0.05, "or_greater") var walk_endurance_loss_per_second: float = 0.24
@export_range(0.0, 100.0, 0.05, "or_greater") var run_endurance_loss_per_second: float = 0.9
@export_range(0.0, 100.0, 0.05, "or_greater") var fight_endurance_loss_per_second: float = 0.7
@export_range(0.0, 100.0, 0.05, "or_greater") var attack_mode_endurance_loss_per_second: float = 0.45
@export_range(0.01, 1.0, 0.01) var endurance_rate_scale: float = 0.2
@export_range(0.0, 100.0, 0.05, "or_greater") var rest_endurance_recovery_per_second: float = 7.5
@export_range(0.0, 100.0, 0.05, "or_greater") var defensive_endurance_recovery_per_second: float = 2.2
@export_range(0.0, 100.0, 0.05, "or_greater") var training_endurance_loss_per_second: float = 0.35
@export_range(0.0, 20.0, 0.01, "or_greater") var training_strength_gain_per_second: float = 0.025
@export_range(0.0, 20.0, 0.01, "or_greater") var training_damage_gain_per_second: float = 0.01
@export_range(0.0, 20.0, 0.01, "or_greater") var training_morale_gain_per_second: float = 0.025
@export_range(0.0, 20.0, 0.01, "or_greater") var training_max_endurance_gain_per_second: float = 0.035
@export_range(1.0, 5000.0, 1.0, "or_greater") var training_strength_soft_cap: float = 95.0
@export_range(0.1, 5000.0, 0.1, "or_greater") var training_damage_soft_cap: float = 22.0
@export_range(0.0, 100.0, 0.1) var training_morale_soft_cap: float = 96.0
@export_range(1.0, 5000.0, 1.0, "or_greater") var training_endurance_soft_cap: float = 155.0
@export_range(0.0, 20.0, 0.01, "or_greater") var fighting_growth_multiplier: float = 5.0
@export_range(0.0, 1.0, 0.01) var low_endurance_ratio: float = 0.25
@export_range(0.0, 60.0, 0.1, "or_greater") var low_endurance_morale_delay: float = 4.0
@export_range(0.0, 100.0, 0.05, "or_greater") var low_endurance_morale_loss_per_second: float = 0.25
@export_range(0.0, 100.0, 0.05, "or_greater") var outnumbered_morale_loss_per_second: float = 0.35
@export_range(0.0, 100.0, 0.05, "or_greater") var food_shortage_morale_loss_per_second: float = 0.35
@export_range(0.0, 100.0, 0.05, "or_greater") var food_shortage_endurance_loss_per_second: float = 0.7
@export_range(0.0, 100.0, 0.1) var desertion_morale_threshold: float = 24.0
@export_range(0.0, 1.0, 0.001) var desertion_chance_per_second: float = 0.025
@export_range(0.05, 2.0, 0.05, "or_greater") var desertion_check_interval_seconds: float = 0.5
@export var survivor_rout_enabled := true
@export_range(1, 64, 1, "or_greater") var survivor_rout_active_threshold: int = 5
@export_range(0, 64, 1, "or_greater") var survivor_rout_min_active_soldiers: int = 3
@export_range(0.05, 1.0, 0.01) var survivor_rout_fraction: float = 0.4
@export_range(1.0, 4.0, 0.05, "or_greater") var survivor_rout_speed_multiplier: float = 1.5
@export_range(0.0, 20.0, 0.01, "or_greater") var food_kg_per_soldier_per_day: float = 1.2
@export_range(0.0, 1000.0, 0.1, "or_greater") var starvation_endurance_loss_per_day: float = 12.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var starvation_health_loss_per_day: float = 6.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var starvation_death_start_days: float = 10.0
@export_range(0.0, 1.0, 0.001) var starvation_death_base_chance_per_day: float = 0.02
@export_range(0.0, 1.0, 0.001) var starvation_death_extra_chance_per_day: float = 0.04
@export_range(0.0, 1.0, 0.001) var starvation_death_max_chance_per_day: float = 0.65
@export_range(0.05, 10.0, 0.05, "or_greater") var starvation_update_interval_seconds: float = 1.0

@export_group("Performance")
@export_range(0.02, 1.0, 0.01) var unit_selection_proxy_refresh_interval: float = 0.25
@export_range(0.02, 1.0, 0.01) var idle_formation_target_refresh_interval: float = 0.20
@export_range(0.02, 1.0, 0.01) var formation_slot_refresh_interval: float = 0.10
@export_range(0.01, 2.0, 0.01, "or_greater") var formation_slot_target_epsilon_m: float = 0.12
@export_range(0.0, 180.0, 1.0, "or_greater") var formation_turn_target_refresh_degrees: float = 6.0
@export var formation_moving_slot_correction_enabled := false
@export var formation_moving_separation_enabled := true
@export_range(1, 64, 1, "or_greater") var formation_collision_neighbor_limit: int = 12
@export_range(1, 512, 1, "or_greater") var formation_separation_updates_per_tick: int = 16
@export_range(1, 4096, 1, "or_greater") var formation_pair_checks_budget_per_tick: int = 32
@export_range(0.0, 0.2, 0.005) var formation_separation_refresh_interval: float = 0.033
@export var stat_worker_enabled := true
@export_range(1, 5000, 1, "or_greater") var stat_worker_min_soldiers: int = 80
@export_range(0.02, 2.0, 0.01, "or_greater") var stat_update_interval_seconds: float = 0.20
@export_range(100, 20000, 50, "or_greater") var stat_apply_budget_usec: int = 800
@export_range(1, 1000, 1, "or_greater") var stat_apply_max_soldiers_per_frame: int = 96
@export var troop_perf_monitoring_enabled := true
@export var soldier_perf_monitoring_enabled := false:
	set(value):
		soldier_perf_monitoring_enabled = value
		if is_inside_tree():
			_set_soldier_perf_monitoring_enabled(value)
@export_range(0.0, 0.5, 0.01) var soldier_idle_pose_update_interval: float = 0.08:
	set(value):
		soldier_idle_pose_update_interval = maxf(value, 0.0)
		if is_inside_tree():
			_set_soldier_idle_pose_update_interval(soldier_idle_pose_update_interval)
@export_range(0.0, 0.2, 0.005) var soldier_active_pose_update_interval: float = 0.033:
	set(value):
		soldier_active_pose_update_interval = maxf(value, 0.0)
		if is_inside_tree():
			_set_soldier_active_pose_update_interval(soldier_active_pose_update_interval)
@export_range(0.0, 0.5, 0.01) var soldier_render_idle_sync_interval: float = 0.08
@export_range(0.0, 0.2, 0.005) var soldier_render_moving_sync_interval: float = 0.0
@export_range(0.0, 0.2, 0.005) var soldier_render_active_sync_interval: float = 0.0
@export_range(1, 6, 1, "or_greater") var soldier_render_active_sync_frame_stride: int = 1
@export_range(1, 12, 1, "or_greater") var soldier_render_idle_sync_frame_stride: int = 4
@export_range(1, 512, 1, "or_greater") var combat_render_dirty_soldiers_per_sync: int = 192
@export_range(1, 512, 1, "or_greater") var soldier_visual_logic_updates_per_tick: int = 48
@export_range(1, 512, 1, "or_greater") var combat_visual_logic_updates_per_tick: int = 128
@export_range(1, 512, 1, "or_greater") var combat_visual_priority_updates_per_tick: int = 128
@export_range(1, 512, 1, "or_greater") var combat_visual_stance_updates_per_tick: int = 128
@export_range(0.2, 5.0, 0.05, "or_greater") var combat_visual_thrust_interval: float = 1.35
@export_range(0.05, 2.0, 0.05, "or_greater") var combat_visual_thrust_duration: float = 0.42
@export_range(0, 4096, 1, "or_greater") var combat_source_corpse_limit: int = 0
@export_range(1, 128, 1, "or_greater") var departed_soldier_removal_budget_per_frame: int = 3
@export var soldier_render_batching_enabled := false:
	set(value):
		soldier_render_batching_enabled = value
		if is_inside_tree():
			_configure_soldier_batch_renderer()

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
@export_range(0.25, 32.0, 0.25, "or_greater") var route_dash_length: float = 1.25:
	set(value):
		route_dash_length = maxf(value, 0.25)
		if is_inside_tree():
			_apply_route_visual_settings()
			_update_route_visual()
@export_range(0.0, 32.0, 0.25, "or_greater") var route_dash_gap: float = 0.5:
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
var _soldier_batch_renderer: Node
var _ring_instance: MeshInstance3D
var _management_flag: Node3D
var _management_flag_sprite: Sprite3D
var _management_flag_border_sprite: Sprite3D
var _last_management_flag_pixel_size := -1.0
var _selection_proxy: StaticBody3D
var _selection_highlight: MeshInstance3D
var _attack_zone_indicator: MeshInstance3D
var _attack_zone_radius := -1.0
var _route_visual: Node
var _combat_debug_line_mesh: MeshInstance3D
var _combat_debug_line_material: StandardMaterial3D
var _combat_debug_line_coming_material: StandardMaterial3D
var _combat_debug_lines_enabled_value := false
var _combat_debug_line_pair_count := 0
var _combat_debug_line_coming_pair_count := 0
var _combat_debug_line_fighting_pair_count := 0
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
var _route_visual_command_id := 0
var _last_ring_world_width := -1.0
var _last_turn_delta := 0.0
var _last_turn_intensity := 0.0
var _formation_motion_time := 0.0
var _suppress_formation_rebuild := false
var _formation_destination_yaw_active := false
var _formation_destination_yaw := 0.0
var _explicit_formation_destination_yaw_for_next_move := false
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
var _manual_attack_target: Node
var _combat_scan_remaining := 0.0
var _chase_repath_remaining := 0.0
var _engagement_windup_remaining := 0.0
var _engagement_zone_check_remaining := 0.0
var _engagement_zone_cached_enemy_id := 0
var _engagement_zone_cached_result := false
var _combat_engagement_break_grace_remaining := 0.0
var _combat_action_remaining := 0.0
var _last_target_instance_id := 0
var _combat_logic_accumulator := 0.0
var _combat_target_reassign_remaining := 0.0
var _combat_soldier_targets: Dictionary = {}
var _combat_soldier_target_statuses: Dictionary = {}
var _combat_target_attackers: Dictionary = {}
var _combat_soldier_offsets: Dictionary = {}
var _combat_soldier_lock_positions: Dictionary = {}
var _combat_soldier_shuffle_offsets: Dictionary = {}
var _combat_soldier_shuffle_timers: Dictionary = {}
var _combat_soldier_attack_timers: Dictionary = {}
var _combat_visual_thrust_timers: Dictionary = {}
var _combat_soldier_steering_cache: Dictionary = {}
var _combat_soldier_spacing_refresh_times: Dictionary = {}
var _combat_soldier_socket_indices: Dictionary = {}
var _combat_soldier_socket_positions: Dictionary = {}
var _combat_soldier_socket_directions: Dictionary = {}
var _combat_soldier_move_targets: Dictionary = {}
var _combat_touched_soldiers: Dictionary = {}
var _combat_animation_drain_soldiers: Dictionary = {}
var _combat_visual_stepped_soldiers: Dictionary = {}
var _combat_render_dirty_soldiers: Dictionary = {}
var _combat_assignment_cursor := 0
var _combat_update_cursor := 0
var _combat_scatter_active := false
var _hold_scattered_positions_after_combat := false
var _regroup_scattered_positions_on_move := false
var _formation_soldiers_cache: Array[Node] = []
var _formation_soldiers_cache_dirty := true
var _active_soldiers_cache: Array[Node] = []
var _active_min_run_speed_cache := 0.0
var _active_max_run_speed_cache := 0.0
var _soldier_cache_dirty := true
var _combat_stat_cache: Dictionary = {}
var _combat_stat_cache_dirty := true
var _unit_selection_proxy_dirty := true
var _unit_selection_proxy_refresh_remaining := 0.0
var _idle_formation_targets_dirty := true
var _idle_formation_target_refresh_remaining := 0.0
var _soldier_render_sync_remaining := 0.0
var _soldier_render_sync_frame_cursor := 0
var _soldier_render_has_synced := false
var _soldier_render_local_space_enabled := false
var _soldier_render_sync_skip_count := 0
var _soldier_visual_logic_cursor := 0
var _combat_visual_logic_cursor := 0
var _combat_visual_stance_cursor := 0
var _combat_visual_stance_update_count := 0
var _combat_visual_thrust_count := 0
var _combat_source_corpse_count := 0
var _soldier_motion_facing_positions: Dictionary = {}
var _soldier_logic_sleep_refresh_remaining := 0.0
var _pending_departed_soldiers: Array[Node] = []
var _pending_departed_soldier_ids: Dictionary = {}
var _departed_soldier_removal_queued := false
var _spatial_neighbor_buffer: Array[Node3D] = []
var _spatial_neighbor_buffer_secondary: Array[Node3D] = []
var _combat_target_candidate_buffer: Array[Node3D] = []
var _combat_underloaded_defender_buffer: Array[Node3D] = []
var _combat_attacker_spatial_index = TroopSpatialIndexScript.new()
var _combat_defender_spatial_index = TroopSpatialIndexScript.new()
var _moving_formation_spatial_index = TroopSpatialIndexScript.new()
var _combat_attacker_spatial_rebuild_remaining := 0.0
var _combat_attacker_spatial_cached_count := -1
var _combat_defender_spatial_rebuild_remaining := 0.0
var _combat_defender_spatial_cached_count := -1
var _combat_defender_spatial_cached_enemy_id := 0
var _combat_frontline_sort_position := Vector3.ZERO
var _combat_attacker_ids: Dictionary = {}
var _combat_defender_ids: Dictionary = {}
var _combat_target_loads: Dictionary = {}
var _moving_formation_targets_dirty := true
var _formation_slot_target_refresh_remaining := 0.0
var _formation_slot_last_target_yaw := 0.0
var _formation_slot_target_cache: Dictionary = {}
var _formation_slot_target_cursor := 0
var _formation_separation_cursor := 0
var _formation_separation_refresh_remaining := 0.0
var _formation_pushes: Dictionary = {}
var _separation_pair_checks_remaining := -1
var _combat_perf_active_cache_rebuilds := 0
var _combat_perf_target_candidate_scans := 0
var _combat_perf_separation_pair_checks := 0
var _combat_perf_steering_updates := 0
var _formation_target_write_count := 0
var _formation_target_skip_count := 0
var _moving_formation_pair_checks := 0
var _spatial_grid_rebuilds := 0
var _combat_socket_clamp_count := 0
var _combat_perf_target_candidate_scan_window := 0
var _combat_perf_separation_pair_check_window := 0
var _combat_perf_steering_update_window := 0
var _combat_perf_rate_window_seconds := 0.0
var _combat_perf_target_scans_per_second := 0
var _combat_perf_pair_checks_per_second := 0
var _combat_perf_steering_updates_per_second := 0
var _perf_last_physics_usec := 0
var _perf_max_physics_usec := 0
var _perf_last_combat_tick_usec := 0
var _perf_max_combat_tick_usec := 0
var _perf_last_combat_collect_usec := 0
var _perf_max_combat_collect_usec := 0
var _perf_last_combat_spatial_usec := 0
var _perf_max_combat_spatial_usec := 0
var _perf_last_combat_assign_usec := 0
var _perf_max_combat_assign_usec := 0
var _perf_last_combat_motion_usec := 0
var _perf_max_combat_motion_usec := 0
var _perf_last_formation_separation_usec := 0
var _perf_max_formation_separation_usec := 0
var _perf_last_combat_summary_usec := 0
var _perf_max_combat_summary_usec := 0
var _perf_stat_worker_wait_count := 0
var _stat_worker_completed_job_polls := 0
var _stat_worker_blocking_waits := 0
var _dead_soldier_count_cache := 0
var _deserted_soldier_count := 0
var _deserter_origin_team_id: StringName = &""
var _deserter_troop: Troop
var _manual_move_override_active := false
var _low_endurance_seconds := 0.0
var _desertion_check_remaining := 0.0
var _food_shortage_ratio := 0.0
var _starvation_update_elapsed := 0.0
var _starvation_accumulated_game_days := 0.0
var _starvation_weighted_shortage_days := 0.0
var _stat_update_remaining := 0.0
var _stat_effect_has_pending := false
var _stat_accumulated_endurance_delta := 0.0
var _stat_accumulated_morale_delta := 0.0
var _stat_accumulated_training_strength := 0.0
var _stat_accumulated_training_damage := 0.0
var _stat_accumulated_training_morale := 0.0
var _stat_accumulated_training_max_endurance := 0.0
var _stat_accumulated_fight_damage := 0.0
var _stat_accumulated_fight_max_endurance := 0.0
var _stat_accumulated_starvation_days := 0.0
var _stat_accumulated_starvation_weighted_shortage_days := 0.0
var _stat_worker_in_flight := false
var _stat_worker_task_id: int = -1
var _stat_worker_job_id := 0
var _stat_worker: RefCounted
var _stat_worker_soldier_map: Dictionary = {}
var _stat_pending_apply_batches: Array[Dictionary] = []
var _stat_last_worker_usec := 0
var _stat_max_worker_usec := 0
var _stat_total_worker_usec := 0
var _stat_completed_jobs := 0
var _stat_started_jobs := 0
var _stat_last_apply_usec := 0
var _stat_max_apply_usec := 0
var _stat_total_apply_usec := 0
var _stat_apply_frames := 0
var _stat_last_apply_count := 0
var _stat_skipped_results := 0
var _stat_last_effect_label := ""
var _stat_last_job_used_worker := false
var _survivor_rout_triggered := false
var _last_combat_emit_time := 0.0
var _was_in_combat := false
var _defeated_presentation_active := false
var _hovered := false
var _mission_parent: Node
var _mission_source: Node
var _mission_type: StringName = MISSION_NONE
var _mission_state: StringName = MISSION_NONE
var _mission_requested_amount_kg := 0.0
var _mission_amount_kg := 0.0
var _mission_target := Vector3.ZERO
var _mission_source_cell := Vector2i.ZERO
var _mission_paused := false
var _mission_internal_command := false
var _mission_work_remaining := 0.0
var _mission_repath_remaining := 0.0
var _mission_child_troops: Array[Node] = []
var _troop_dependencies_ready := false
var _troop_context: RefCounted
var _troop_services: Resource
var _troop_presentation_service: Resource
var _troop_formation_service: Resource
var _troop_movement_service: Resource
var _troop_combat_service: Resource
var _troop_summary_service: Resource


func _ensure_troop_dependencies() -> void:
	if _troop_dependencies_ready:
		_ensure_dependency_defaults()
		return
	if formation_strategy:
		formation_strategy = formation_strategy.duplicate(true)
	if movement_logic:
		movement_logic = movement_logic.duplicate(true)
	if combat_positioning_logic:
		combat_positioning_logic = combat_positioning_logic.duplicate(true)
	if summary_builder:
		summary_builder = summary_builder.duplicate(true)
	if soldier_behavior_set:
		if soldier_behavior_set.has_method("duplicate_for_runtime"):
			soldier_behavior_set = soldier_behavior_set.call("duplicate_for_runtime") as Resource
		else:
			soldier_behavior_set = soldier_behavior_set.duplicate(true)
			if soldier_behavior_set.has_method("ensure_defaults"):
				soldier_behavior_set.call("ensure_defaults")
	if service_set:
		if service_set.has_method("duplicate_for_runtime"):
			service_set = service_set.call("duplicate_for_runtime") as Resource
		else:
			service_set = service_set.duplicate(true)
	_ensure_dependency_defaults()
	_configure_troop_services()
	_troop_dependencies_ready = true


func _ensure_dependency_defaults() -> void:
	if not formation_strategy:
		formation_strategy = DefaultTroopFormationStrategyScript.new()
	if not movement_logic:
		movement_logic = DefaultTroopMovementLogicScript.new()
	if not combat_positioning_logic:
		combat_positioning_logic = DefaultTroopCombatPositioningLogicScript.new()
	if not summary_builder:
		summary_builder = DefaultTroopSummaryBuilderScript.new()
	if not soldier_behavior_set:
		soldier_behavior_set = DefaultTroopSoldierBehaviorSetScript.new()
		soldier_behavior_set.ensure_defaults()
	if not service_set:
		service_set = DefaultTroopServiceSetScript.new()
	if service_set.has_method("ensure_defaults"):
		service_set.call("ensure_defaults")


func _configure_troop_services() -> void:
	_ensure_dependency_defaults()
	_troop_services = service_set
	if not _troop_context:
		_troop_context = DefaultTroopRuntimeContextScript.new()
	if _troop_context.has_method("setup"):
		_troop_context.call("setup", self)
	if _troop_services and _troop_services.has_method("configure_legacy_dependencies"):
		_troop_services.call(
			"configure_legacy_dependencies",
			formation_strategy,
			movement_logic,
			combat_positioning_logic,
			summary_builder
		)
	if _troop_services and _troop_services.has_method("configure"):
		_troop_services.call("configure", _troop_context)
	if _troop_services:
		_troop_presentation_service = _troop_services.get("presentation_service") as Resource
		_troop_formation_service = _troop_services.get("formation_service") as Resource
		_troop_movement_service = _troop_services.get("movement_service") as Resource
		_troop_combat_service = _troop_services.get("combat_service") as Resource
		_troop_summary_service = _troop_services.get("summary_service") as Resource
	else:
		_troop_presentation_service = null
		_troop_formation_service = null
		_troop_movement_service = null
		_troop_combat_service = null
		_troop_summary_service = null


func _get_troop_services() -> Resource:
	if not _troop_services:
		_configure_troop_services()
	return _troop_services


func _get_presentation_service() -> Resource:
	if not _troop_presentation_service:
		_configure_troop_services()
	return _troop_presentation_service


func _get_formation_service() -> Resource:
	if not _troop_formation_service:
		_configure_troop_services()
	return _troop_formation_service


func _get_movement_service() -> Resource:
	if not _troop_movement_service:
		_configure_troop_services()
	return _troop_movement_service


func _get_combat_service() -> Resource:
	if not _troop_combat_service:
		_configure_troop_services()
	return _troop_combat_service


func _get_summary_service() -> Resource:
	if not _troop_summary_service:
		_configure_troop_services()
	return _troop_summary_service


func _get_formation_strategy() -> Resource:
	_ensure_dependency_defaults()
	return formation_strategy


func _get_movement_logic() -> Resource:
	_ensure_dependency_defaults()
	return movement_logic


func _get_combat_positioning_logic() -> Resource:
	_ensure_dependency_defaults()
	return combat_positioning_logic


func _get_summary_builder() -> Resource:
	_ensure_dependency_defaults()
	return summary_builder


func _ready() -> void:
	add_to_group(&"troops")
	if is_mission_troop:
		add_to_group(&"mission_troops")
	if team_id == TEAM_DESERTER:
		add_to_group(&"deserter_troops")
	_ensure_troop_dependencies()
	_rng.seed = _get_combat_seed()
	_resolve_dependencies()
	var services := _get_troop_services()
	if services and services.has_method("ready"):
		services.call("ready")
	_load_movement_map()
	_combat_scan_remaining = _get_combat_scan_phase_seconds()
	_stat_update_remaining = _get_stat_update_phase_seconds()
	rebuild_formation()
	call_deferred("_prewarm_soldier_batch_renderer")
	_rebuild_management_flag()
	_snap_to_surface()
	_rebuild_cargo_trolley_visuals()
	if _combat_debug_lines_enabled_value:
		_ensure_combat_debug_lines()
		_update_combat_debug_lines()
	_emit_destination_changed()
	_emit_logistics_changed()
	_emit_mode_changed()
	_emit_combat_changed()


func _physics_process(delta: float) -> void:
	var services := _get_troop_services()
	if services and services.has_method("physics_tick"):
		services.call("physics_tick", delta)


func _process(delta: float) -> void:
	var services := _get_troop_services()
	if services and services.has_method("process_tick"):
		services.call("process_tick", delta)


func _exit_tree() -> void:
	var services := _get_troop_services()
	if services and services.has_method("exit_tree"):
		services.call("exit_tree")
	remove_from_group(&"troops")
	remove_from_group(&"mission_troops")
	remove_from_group(&"deserter_troops")


func rebuild_formation() -> void:
	var service := _get_formation_service()
	if service and service.has_method("rebuild_formation"):
		service.call("rebuild_formation")


func set_selected(selected: bool) -> void:
	if selected and is_defeated():
		selected = false
	if _selected == selected:
		return
	_selected = selected
	_update_hover_visuals()
	_update_attack_zone_indicator()
	selected_changed.emit(_selected)


func is_selected() -> bool:
	return _selected


func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_update_hover_visuals()


func is_hovered() -> bool:
	return _hovered


func set_move_destination(world_position: Vector3, manual_command: bool = true) -> bool:
	var service = _get_movement_service()
	if not service:
		return false
	return service.set_move_destination(world_position, manual_command)


func stop_movement() -> void:
	var service = _get_movement_service()
	if service and service.has_method("stop_movement"):
		service.stop_movement()


func clear_destination() -> void:
	stop_movement()


func has_destination() -> bool:
	return _has_destination


func get_destination() -> Vector3:
	return _destination


func set_formation_destination(
	world_center: Vector3,
	right_axis: Vector3,
	width_m: float,
	manual_command: bool = true
) -> bool:
	var service = _get_movement_service()
	if not service:
		return false
	return service.set_formation_destination(world_center, right_axis, width_m, manual_command)


func command_attack_troop(enemy: Node) -> bool:
	var service = _get_combat_service()
	if not service:
		return false
	return service.command_attack_troop(enemy)


func has_attack_target() -> bool:
	return _is_valid_enemy(_manual_attack_target)


func get_attack_target() -> Node:
	return _manual_attack_target if _is_valid_enemy(_manual_attack_target) else null


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
	_start_mission_troop(village, target, MISSION_FOOD, amount, int(assignment["soldiers"]), {})
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
	_start_mission_troop(
		forest_region,
		target,
		MISSION_WOOD,
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

	_sync_camp_storage_from_node()
	var camp := _get_owned_camp()
	var available_wood := camp_wood_kg if camp else carried_wood_kg
	if available_wood + 0.001 < cargo_trolley_wood_cost_kg:
		return false
	if camp and camp.has_method("withdraw_wood_kg"):
		camp.call("withdraw_wood_kg", cargo_trolley_wood_cost_kg)
		_sync_camp_storage_from_node()
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
	var starting_food := maxf(carried_food_kg, 0.0)
	var starting_wood := maxf(carried_wood_kg, 0.0)
	carried_food_kg = 0.0
	carried_wood_kg = 0.0
	_camp_wood_invested_kg = cost
	_camp_established = true
	_camp_world_position = _snap_world_point(global_position)
	camp_food_kg = starting_food
	camp_wood_kg = starting_wood
	_spawn_independent_camp(cost, starting_food, starting_wood)
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()
	return true


func pack_camp() -> bool:
	if not _camp_established:
		return false
	if not is_camp_pack_in_range():
		return false

	_sync_camp_storage_from_node()
	carried_food_kg += maxf(camp_food_kg, 0.0)
	carried_wood_kg += maxf(camp_wood_kg, 0.0)
	carried_wood_kg += _camp_wood_invested_kg
	camp_food_kg = 0.0
	camp_wood_kg = 0.0
	_camp_wood_invested_kg = 0.0
	_camp_established = false
	_clear_independent_camp()
	_rebuild_cargo_trolley_visuals()
	_emit_logistics_changed()
	return true


func get_total_carry_capacity_kg() -> float:
	return _get_capacity_for_carrier_soldiers(get_active_soldier_count() + get_busy_carrier_soldiers())


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
	return _busy_carrier_soldiers + _get_mission_child_soldier_count()


func get_camp_living_hut_count() -> int:
	var soldiers_per_hut := maxi(camp_soldiers_per_living_hut, 1)
	return maxi(ceili(float(maxi(get_soldier_count(), 1)) / float(soldiers_per_hut)), 1)


func get_camp_total_wood_cost_kg() -> float:
	return float(get_camp_living_hut_count()) * maxf(camp_living_hut_wood_cost_kg, 0.0)


func is_camp_pack_in_range() -> bool:
	if not _camp_established:
		return false
	var camp := _get_owned_camp()
	if camp and camp.has_method("is_troop_in_range"):
		return bool(camp.call("is_troop_in_range", self))
	return global_position.distance_to(_camp_world_position) <= maxf(camp_pack_range_m, 0.1)


func get_camp_world_position() -> Vector3:
	if is_instance_valid(_camp_node):
		return _camp_node.global_position
	return _camp_world_position


func get_camp_summary() -> Dictionary:
	_sync_camp_storage_from_node()
	return {
		"camp_established": _camp_established,
		"camp_food_kg": camp_food_kg,
		"camp_wood_kg": camp_wood_kg,
		"camp_wood_invested_kg": _camp_wood_invested_kg,
		"camp_position": get_camp_world_position(),
		"camp_pack_range_m": camp_pack_range_m,
		"camp_range_m": camp_pack_range_m,
		"camp_pack_in_range": is_camp_pack_in_range(),
		"camp_soldiers_per_living_hut": camp_soldiers_per_living_hut,
		"camp_living_hut_count": get_camp_living_hut_count(),
		"camp_living_hut_wood_cost_kg": camp_living_hut_wood_cost_kg,
		"camp_total_wood_cost_kg": get_camp_total_wood_cost_kg(),
	}


func get_troop_summary() -> Dictionary:
	var services := _get_troop_services()
	if services and services.has_method("build_troop_summary"):
		return services.call("build_troop_summary") as Dictionary
	return {}


func get_soldier_count() -> int:
	var current_count := _get_formation_soldier_count() + get_busy_carrier_soldiers()
	return current_count


func add_recruited_soldiers(count: int, spawn_world_position: Vector3 = Vector3(1.0e20, 1.0e20, 1.0e20)) -> int:
	var requested := maxi(count, 0)
	if requested <= 0:
		return 0

	_ensure_scene_nodes()
	if not _soldier_container:
		return 0

	var scene := soldier_scene if soldier_scene else DEFAULT_SOLDIER_SCENE
	var added := 0
	var start_index := _get_formation_soldier_count()
	var spawn_origin := spawn_world_position
	if absf(spawn_origin.x) > 1.0e19 or absf(spawn_origin.y) > 1.0e19 or absf(spawn_origin.z) > 1.0e19:
		spawn_origin = global_position

	for offset_index: int in range(requested):
		var instance := scene.instantiate()
		if not (instance is Node3D):
			instance.free()
			continue
		var soldier := instance as Node3D
		var soldier_index := start_index + added
		soldier.name = "Soldier_%03d" % soldier_index
		_soldier_container.add_child(soldier)
		soldier.owner = null
		soldier.top_level = true
		var angle := TAU * float(offset_index) / float(maxi(requested, 1))
		var radius := maxf(formation_spacing * 0.45, 1.2)
		soldier.global_position = _snap_world_point(spawn_origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		soldier.rotation.y = rotation.y
		_configure_visual_soldier(soldier, soldier_index)
		added += 1

	if added <= 0:
		return 0

	_refresh_transferred_formation()
	if _camp_established:
		_sync_independent_camp_settings()
	_mark_combat_stats_dirty()
	_emit_logistics_changed()
	_emit_combat_changed()
	return added


func continue_mission() -> bool:
	if not is_mission_troop or not _is_mission_active():
		return false
	_mission_paused = false
	match _mission_state:
		MISSION_TO_TARGET, MISSION_WORKING:
			return _mission_set_destination(_mission_target)
		MISSION_RETURNING:
			return _mission_set_destination(_get_mission_parent_position())
		_:
			return false


func take_food_from_nearby_camp(amount_kg: float) -> float:
	var camp := _get_primary_in_range_camp()
	return take_food_from_camp(camp, amount_kg)


func take_food_from_camp(camp: Node, amount_kg: float) -> float:
	if not camp or not camp.has_method("withdraw_food_kg"):
		return 0.0
	if not _is_friendly_camp_in_range(camp):
		return 0.0
	var amount := minf(maxf(amount_kg, 0.0), get_free_carry_capacity_kg())
	if amount <= 0.0:
		return 0.0
	var moved := maxf(float(camp.call("withdraw_food_kg", amount)), 0.0)
	carried_food_kg += moved
	_sync_camp_storage_from_node()
	_emit_logistics_changed()
	return moved


func deposit_food_to_nearby_camp(amount_kg: float) -> float:
	var camp := _get_primary_in_range_camp()
	return deposit_food_to_camp(camp, amount_kg)


func deposit_food_to_camp(camp: Node, amount_kg: float) -> float:
	if not camp or not camp.has_method("deposit_food_kg"):
		return 0.0
	if not _is_friendly_camp_in_range(camp):
		return 0.0
	var amount := minf(maxf(amount_kg, 0.0), maxf(carried_food_kg, 0.0))
	if amount <= 0.0:
		return 0.0
	carried_food_kg = maxf(carried_food_kg - amount, 0.0)
	var moved := maxf(float(camp.call("deposit_food_kg", amount)), 0.0)
	_sync_camp_storage_from_node()
	_emit_logistics_changed()
	return moved


func take_wood_from_nearby_camp(amount_kg: float) -> float:
	var camp := _get_primary_in_range_camp()
	return take_wood_from_camp(camp, amount_kg)


func take_wood_from_camp(camp: Node, amount_kg: float) -> float:
	if not camp or not camp.has_method("withdraw_wood_kg"):
		return 0.0
	if not _is_friendly_camp_in_range(camp):
		return 0.0
	var amount := minf(maxf(amount_kg, 0.0), get_free_carry_capacity_kg())
	if amount <= 0.0:
		return 0.0
	var moved := maxf(float(camp.call("withdraw_wood_kg", amount)), 0.0)
	carried_wood_kg += moved
	_sync_camp_storage_from_node()
	_emit_logistics_changed()
	return moved


func deposit_wood_to_nearby_camp(amount_kg: float) -> float:
	var camp := _get_primary_in_range_camp()
	return deposit_wood_to_camp(camp, amount_kg)


func deposit_wood_to_camp(camp: Node, amount_kg: float) -> float:
	if not camp or not camp.has_method("deposit_wood_kg"):
		return 0.0
	if not _is_friendly_camp_in_range(camp):
		return 0.0
	var amount := minf(maxf(amount_kg, 0.0), maxf(carried_wood_kg, 0.0))
	if amount <= 0.0:
		return 0.0
	carried_wood_kg = maxf(carried_wood_kg - amount, 0.0)
	var moved := maxf(float(camp.call("deposit_wood_kg", amount)), 0.0)
	_sync_camp_storage_from_node()
	_emit_logistics_changed()
	return moved


func persuade_nearby_deserters() -> int:
	if team_id == TEAM_DESERTER:
		return 0
	var persuaded := 0
	for deserter_troop: Node in _get_nearby_deserter_troops():
		if not (deserter_troop is Troop):
			continue
		var deserters := deserter_troop as Troop
		var soldiers := deserters._get_active_soldiers()
		for soldier: Node in soldiers:
			if not (soldier is Node3D):
				continue
			if _rng.randf() > clampf(deserter_persuasion_chance, 0.0, 1.0):
				continue
			deserters._remove_soldier_for_transfer(soldier as Node3D)
			_adopt_transferred_soldier(soldier as Node3D, _get_formation_soldier_count(), _get_formation_soldier_count() + 1)
			persuaded += 1
		deserters._refresh_transferred_formation()
		if deserters.get_active_soldier_count() <= 0:
			deserters.queue_free()
	if persuaded > 0:
		_refresh_transferred_formation()
		_emit_combat_changed()
	return persuaded


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


func get_active_soldier_world_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for soldier: Node in _get_active_soldiers():
		if soldier is Node3D:
			positions.append((soldier as Node3D).global_position)
	return positions


func get_engagement_sample_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(global_position)
	var active_count := maxi(get_active_soldier_count(), 1)
	var columns := mini(maxi(formation_columns, 1), active_count)
	var rows := ceili(float(active_count) / float(columns))
	var half_width := maxf(float(columns - 1) * formation_spacing * 0.5, formation_spacing)
	var half_depth := maxf(float(rows - 1) * formation_spacing * 0.5, formation_spacing)
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	points.append(global_position + right * half_width + forward * half_depth)
	points.append(global_position - right * half_width + forward * half_depth)
	points.append(global_position + right * half_width - forward * half_depth)
	points.append(global_position - right * half_width - forward * half_depth)
	return points


func get_management_flag_world_position() -> Vector3:
	if is_instance_valid(_management_flag_sprite):
		return _management_flag_sprite.global_position
	return _management_flag.global_position if is_instance_valid(_management_flag) else Vector3.ZERO


func get_route_dash_count() -> int:
	return int(_route_visual.call("get_dash_count")) if _route_visual and _route_visual.has_method("get_dash_count") else 0


func has_destination_marker() -> bool:
	return bool(_route_visual.call("has_destination_flag")) if _route_visual and _route_visual.has_method("has_destination_flag") else false


func has_selection_indicator() -> bool:
	return is_instance_valid(_management_flag) and is_instance_valid(_selection_proxy)


func has_selection_highlight() -> bool:
	return false


func has_attack_zone_indicator() -> bool:
	return is_instance_valid(_attack_zone_indicator) and _attack_zone_indicator.visible


func get_attack_zone_radius() -> float:
	return _attack_zone_radius if has_attack_zone_indicator() else 0.0


func get_attack_zone_corners() -> PackedVector3Array:
	var bounds := _get_attack_zone_bounds()
	if bounds.is_empty():
		return PackedVector3Array()
	var min_x := float(bounds.get("min_x", 0.0)) - float(bounds.get("range", 0.0))
	var max_x := float(bounds.get("max_x", 0.0)) + float(bounds.get("range", 0.0))
	var min_z := float(bounds.get("min_z", 0.0)) - float(bounds.get("range", 0.0))
	var max_z := float(bounds.get("max_z", 0.0)) + float(bounds.get("range", 0.0))
	return PackedVector3Array([
		_formation_slot_to_world(Vector3(min_x, 0.0, min_z)),
		_formation_slot_to_world(Vector3(max_x, 0.0, min_z)),
		_formation_slot_to_world(Vector3(max_x, 0.0, max_z)),
		_formation_slot_to_world(Vector3(min_x, 0.0, max_z)),
	])


func is_world_position_in_attack_zone(world_position: Vector3, range_override: float = -1.0) -> bool:
	return _get_distance_to_attack_zone(world_position, range_override) <= 0.0


func has_management_flag() -> bool:
	return is_instance_valid(_management_flag) and is_instance_valid(_selection_proxy)


func has_unit_hover_borders() -> bool:
	for soldier: Node in _get_formation_soldiers():
		var border := soldier.get_node_or_null(UNIT_HOVER_BORDER_NAME) as MeshInstance3D
		if border and border.visible:
			return true
	return false


func has_unit_selection_markers() -> bool:
	for soldier: Node in _get_formation_soldiers():
		var marker := soldier.get_node_or_null(UNIT_SELECTION_MARKER_NAME) as MeshInstance3D
		if marker and marker.visible:
			return true
	return false


func get_combat_lock_position_for_soldier(soldier: Node) -> Vector3:
	if not is_instance_valid(soldier):
		return Vector3.ZERO
	return _combat_soldier_lock_positions.get(soldier.get_instance_id(), Vector3.ZERO)


func has_combat_lock_for_soldier(soldier: Node) -> bool:
	return is_instance_valid(soldier) and _combat_soldier_lock_positions.has(soldier.get_instance_id())


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
	return int(_get_combat_stat_cache().get("active_soldier_count", 0))


func get_dead_soldier_count() -> int:
	return int(_get_combat_stat_cache().get("dead_soldier_count", 0))


func get_deserted_soldier_count() -> int:
	return _deserted_soldier_count


func is_defeated() -> bool:
	return get_active_soldier_count() <= 0


func get_average_strength() -> float:
	return float(_get_combat_stat_cache().get("average_strength", 0.0))


func get_average_max_strength() -> float:
	return float(_get_combat_stat_cache().get("average_max_strength", 0.0))


func get_average_damage() -> float:
	return float(_get_combat_stat_cache().get("average_damage", 0.0))


func get_average_morale() -> float:
	return float(_get_combat_stat_cache().get("average_morale", 0.0))


func get_average_endurance() -> float:
	return float(_get_combat_stat_cache().get("average_endurance", 0.0))


func get_average_max_endurance() -> float:
	return float(_get_combat_stat_cache().get("average_max_endurance", 0.0))


func get_average_run_speed() -> float:
	return _get_average_soldier_value(&"run_speed")


func get_average_starving_days() -> float:
	return float(_get_combat_stat_cache().get("average_starving_days", 0.0))


func get_minimum_run_speed() -> float:
	return _get_minimum_active_run_speed_live()


func get_maximum_run_speed() -> float:
	return _get_maximum_active_run_speed_live()


func _ensure_scene_nodes() -> void:
	var service = _get_presentation_service()
	if service and service.has_method("ensure_scene_nodes"):
		service.ensure_scene_nodes()


func _configure_soldier_batch_renderer() -> void:
	if not _soldier_batch_renderer:
		return
	if _soldier_batch_renderer.has_method("set_batching_enabled"):
		_soldier_batch_renderer.call("set_batching_enabled", soldier_render_batching_enabled)


func _refresh_soldier_batch_renderer_soldiers() -> void:
	if not _soldier_batch_renderer:
		return
	_configure_soldier_batch_renderer()
	if _soldier_batch_renderer.has_method("set_soldiers"):
		_soldier_batch_renderer.call("set_soldiers", _get_formation_soldiers())
	_force_full_soldier_render_sync()


func _force_full_soldier_render_sync() -> void:
	_soldier_render_has_synced = false
	_soldier_render_sync_remaining = 0.0
	_soldier_render_sync_frame_cursor = 0


func _prewarm_soldier_batch_renderer() -> void:
	if not is_inside_tree() or not _soldier_batch_renderer or not soldier_render_batching_enabled:
		return
	_configure_soldier_batch_renderer()
	if _soldier_batch_renderer.has_method("set_local_space_enabled"):
		_soldier_batch_renderer.call("set_local_space_enabled", true)
	_soldier_render_local_space_enabled = true
	if _soldier_batch_renderer.has_method("sync"):
		_soldier_batch_renderer.call("sync", true)
		_soldier_render_has_synced = true
		_soldier_render_sync_remaining = maxf(soldier_render_idle_sync_interval, 0.0)
		_soldier_render_sync_frame_cursor = 0


func _sync_soldier_batch_renderer(delta: float = 0.0) -> void:
	if not _soldier_batch_renderer:
		return
	var has_active_independent_motion := _has_active_soldier_independent_motion()
	var render_local_space := _state == STATE_MOVING and not _combat_scatter_active and not has_active_independent_motion
	if _should_throttle_active_soldier_render_sync(has_active_independent_motion):
		if _soldier_render_has_synced:
			var active_stride := 1 if (_state == STATE_FIGHTING or _combat_scatter_active) else maxi(soldier_render_active_sync_frame_stride, 1)
			if active_stride > 1:
				_soldier_render_sync_frame_cursor = (_soldier_render_sync_frame_cursor + 1) % active_stride
				if _soldier_render_sync_frame_cursor != 0:
					_soldier_render_sync_skip_count += 1
					return
			_soldier_render_sync_remaining -= maxf(delta, 0.0)
			if _soldier_render_sync_remaining > 0.0:
				_soldier_render_sync_skip_count += 1
				return
		_soldier_render_sync_remaining = _get_active_soldier_render_sync_interval()
		_soldier_render_sync_frame_cursor = 0
	elif _should_throttle_soldier_render_sync(has_active_independent_motion):
		if _soldier_render_has_synced and not has_active_independent_motion:
			_soldier_render_sync_skip_count += 1
			return
		var stride := maxi(soldier_render_idle_sync_frame_stride, 1)
		if _soldier_render_has_synced and stride > 1:
			_soldier_render_sync_frame_cursor = (_soldier_render_sync_frame_cursor + 1) % stride
			if _soldier_render_sync_frame_cursor != 0:
				_soldier_render_sync_skip_count += 1
				return
		_soldier_render_sync_remaining -= maxf(delta, 0.0)
		if _soldier_render_sync_remaining > 0.0:
			_soldier_render_sync_skip_count += 1
			return
		_soldier_render_sync_remaining = maxf(soldier_render_idle_sync_interval, 0.0)
	else:
		_soldier_render_sync_remaining = 0.0
		_soldier_render_sync_frame_cursor = 0
	_configure_soldier_batch_renderer()
	if _soldier_batch_renderer.has_method("set_local_space_enabled"):
		_soldier_batch_renderer.call("set_local_space_enabled", render_local_space)
	if _soldier_batch_renderer.has_method("sync"):
		var active_sync := _state == STATE_MOVING or _state == STATE_FIGHTING or _combat_scatter_active or has_active_independent_motion
		var combat_partial_sync := (
			_state == STATE_FIGHTING
			and _soldier_render_has_synced
			and not _combat_render_dirty_soldiers.is_empty()
			and _soldier_batch_renderer.has_method("sync_dirty_soldiers")
		)
		if combat_partial_sync:
			var dirty_ids := _get_render_dirty_soldiers_for_sync()
			_soldier_batch_renderer.call("sync_dirty_soldiers", dirty_ids)
			_clear_render_dirty_soldiers_for_sync(dirty_ids)
		elif _state == STATE_FIGHTING and _soldier_render_has_synced and _combat_render_dirty_soldiers.is_empty():
			_soldier_render_sync_skip_count += 1
			return
		else:
			var force_transform_sync := active_sync and not render_local_space
			_soldier_batch_renderer.call("sync", force_transform_sync)
			_combat_render_dirty_soldiers.clear()
		_soldier_render_has_synced = true


func _get_render_dirty_soldiers_for_sync() -> Dictionary:
	if _state != STATE_FIGHTING:
		return _combat_render_dirty_soldiers
	var budget := maxi(combat_render_dirty_soldiers_per_sync, 1)
	if _combat_render_dirty_soldiers.size() <= budget:
		return _combat_render_dirty_soldiers
	var dirty_ids := {}
	var copied := 0
	for key: Variant in _combat_render_dirty_soldiers.keys():
		dirty_ids[key] = true
		copied += 1
		if copied >= budget:
			break
	return dirty_ids


func _clear_render_dirty_soldiers_for_sync(dirty_ids: Dictionary) -> void:
	if dirty_ids == _combat_render_dirty_soldiers:
		_combat_render_dirty_soldiers.clear()
		return
	for key: Variant in dirty_ids.keys():
		_combat_render_dirty_soldiers.erase(key)


func _should_throttle_active_soldier_render_sync(has_active_independent_motion: bool = false) -> bool:
	return _state == STATE_MOVING or _state == STATE_FIGHTING or _combat_scatter_active or has_active_independent_motion


func _get_active_soldier_render_sync_interval() -> float:
	if _state == STATE_MOVING and not _combat_scatter_active and not _has_active_soldier_independent_motion():
		return maxf(soldier_render_moving_sync_interval, 0.0)
	return maxf(soldier_render_active_sync_interval, 0.0)


func _should_throttle_soldier_render_sync(has_active_independent_motion: bool = false) -> bool:
	if soldier_render_idle_sync_interval <= 0.0:
		return false
	if _state == STATE_MOVING or _state == STATE_FIGHTING:
		return false
	if _combat_scatter_active:
		return false
	if has_active_independent_motion:
		return false
	return true


func _has_active_soldier_independent_motion() -> bool:
	for soldier: Node in _get_formation_soldiers():
		if not _is_soldier_active(soldier):
			continue
		if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")):
			return true
	return false


func _update_soldier_logic_sleeping(delta: float) -> void:
	var troop_can_sleep := (
		(_state == STATE_IDLE or _state == STATE_BLOCKED)
		and not _combat_scatter_active
	)
	var troop_combat_sleep := _state == STATE_FIGHTING
	if troop_combat_sleep:
		_soldier_logic_sleep_refresh_remaining -= maxf(delta, 0.0)
		if _soldier_logic_sleep_refresh_remaining > 0.0:
			return
		_soldier_logic_sleep_refresh_remaining = 0.2
	else:
		_soldier_logic_sleep_refresh_remaining = 0.0
	for soldier: Node in _get_formation_soldiers():
		if not soldier.has_method("set_logic_sleeping"):
			continue
		var should_sleep := (troop_can_sleep or troop_combat_sleep) and _is_soldier_active(soldier) and not soldier.has_meta(&"troop_carrier_active")
		if should_sleep and soldier.has_method("can_logic_sleep"):
			should_sleep = bool(soldier.call("can_logic_sleep"))
		soldier.call("set_logic_sleeping", should_sleep)


func _step_formation_soldier_logic(delta: float) -> void:
	if not _soldier_container:
		return
	if _state == STATE_FIGHTING and not _combat_touched_soldiers.is_empty():
		_step_combat_animation_drain_soldiers(delta, _combat_visual_stepped_soldiers)
		return
	var soldiers: Array = _get_combat_touched_soldier_nodes() if _state == STATE_FIGHTING and not _combat_touched_soldiers.is_empty() else _get_formation_soldiers()
	var stepped_soldier_ids := {}
	for soldier: Node in soldiers:
		if not is_instance_valid(soldier):
			continue
		if not soldier.is_inside_tree():
			continue
		if not _is_soldier_active(soldier):
			continue
		if soldier.has_meta(&"troop_carrier_active"):
			continue
		if soldier.has_method("is_logic_sleeping") and bool(soldier.call("is_logic_sleeping")):
			continue
		if soldier.has_method("step_formation_logic"):
			soldier.call("step_formation_logic", delta)
			stepped_soldier_ids[soldier.get_instance_id()] = true
			_update_soldier_live_animation_source_after_step(soldier)
			if _state == STATE_FIGHTING:
				_mark_soldier_render_dirty(soldier)
	_step_combat_animation_drain_soldiers(delta, stepped_soldier_ids)


func _step_combat_animation_drain_soldiers(delta: float, stepped_soldier_ids: Dictionary) -> void:
	if _combat_animation_drain_soldiers.is_empty():
		return
	for key: Variant in _combat_animation_drain_soldiers.keys():
		if stepped_soldier_ids.has(key):
			continue
		var soldier := _get_node_from_instance_id_key(key)
		if not soldier or not _is_soldier_active(soldier) or soldier.has_meta(&"troop_carrier_active"):
			_combat_animation_drain_soldiers.erase(key)
			continue
		if soldier.has_method("set_logic_sleeping"):
			soldier.call("set_logic_sleeping", false)
		if soldier.has_method("step_formation_logic"):
			soldier.call("step_formation_logic", delta)
			_update_soldier_live_animation_source_after_step(soldier)
		if _soldier_should_use_live_animation_source(soldier):
			_mark_soldier_render_dirty(soldier)
		else:
			_combat_animation_drain_soldiers.erase(key)


func _step_combat_soldier_visual_logic(delta: float) -> void:
	_combat_visual_stepped_soldiers.clear()
	var soldiers := _get_combat_touched_soldier_nodes()
	var soldier_count := soldiers.size()
	if soldier_count <= 0:
		_combat_visual_logic_cursor = 0
		return
	var start := clampi(_combat_visual_logic_cursor, 0, maxi(soldier_count - 1, 0))
	var stepped_ids := {}
	var priority_budget := mini(maxi(combat_visual_priority_updates_per_tick, 1), soldier_count)
	for offset_index: int in range(soldier_count):
		if priority_budget <= 0:
			break
		var soldier: Node = soldiers[(start + offset_index) % soldier_count]
		if _should_skip_visual_soldier_step(soldier):
			continue
		if soldier.has_method("needs_full_rate_combat_visual") and bool(soldier.call("needs_full_rate_combat_visual")):
			_step_visual_soldier(soldier, delta)
			stepped_ids[soldier.get_instance_id()] = true
			_combat_visual_stepped_soldiers[soldier.get_instance_id()] = true
			priority_budget -= 1

	var standard_budget := mini(maxi(combat_visual_logic_updates_per_tick, 1), soldier_count)
	var stepped := 0
	var scanned := 0
	while stepped < standard_budget and scanned < soldier_count:
		var soldier: Node = soldiers[(start + scanned) % soldier_count]
		scanned += 1
		if _should_skip_visual_soldier_step(soldier):
			continue
		if stepped_ids.has(soldier.get_instance_id()):
			continue
		_step_visual_soldier(soldier, delta)
		_combat_visual_stepped_soldiers[soldier.get_instance_id()] = true
		stepped += 1
	_combat_visual_logic_cursor = (start + maxi(scanned, 1)) % soldier_count


func _should_skip_visual_soldier_step(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return true
	if not soldier.is_inside_tree():
		return true
	if not _is_soldier_active(soldier):
		return true
	if soldier.has_meta(&"troop_carrier_active"):
		return true
	if soldier.has_method("is_logic_sleeping") and bool(soldier.call("is_logic_sleeping")):
		return true
	return false


func _step_visual_soldier(soldier: Node, delta: float) -> void:
	if not soldier.has_method("step_formation_logic"):
		return
	soldier.call("step_formation_logic", delta)
	_update_soldier_live_animation_source_after_step(soldier)
	if _state == STATE_FIGHTING or (_state == STATE_MOVING and not _combat_scatter_active):
		_mark_soldier_render_dirty(soldier)


func _align_moving_soldiers_to_frame_displacement() -> void:
	var active_ids := {}
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		var soldier := soldier_node as Node3D
		var soldier_id := soldier.get_instance_id()
		active_ids[soldier_id] = true
		var previous_variant: Variant = _soldier_motion_facing_positions.get(soldier_id)
		var current_position := soldier.global_position
		if _state == STATE_MOVING and previous_variant is Vector3 and not soldier.has_meta(&"troop_carrier_active"):
			var displacement := current_position - (previous_variant as Vector3)
			displacement.y = 0.0
			if displacement.length_squared() > 0.000225:
				var direction := displacement.normalized()
				soldier.rotation.y = atan2(-direction.x, -direction.z)
				if soldier.has_method("set_formation_facing_direction"):
					soldier.call("set_formation_facing_direction", direction)
		_soldier_motion_facing_positions[soldier_id] = current_position
	for key: Variant in _soldier_motion_facing_positions.keys():
		if not active_ids.has(key):
			_soldier_motion_facing_positions.erase(key)


func _wake_soldier_logic() -> void:
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("set_logic_sleeping"):
			soldier.call("set_logic_sleeping", false)


func _get_logic_sleeping_soldier_count() -> int:
	var count := 0
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("is_logic_sleeping") and bool(soldier.call("is_logic_sleeping")):
			count += 1
	return count


func _get_soldier_render_batch_summary() -> Dictionary:
	if not _soldier_batch_renderer:
		return {
			"soldier_render_batching_enabled": soldier_render_batching_enabled,
			"soldier_render_batch_count": 0,
			"soldier_render_batched_instance_count": 0,
			"soldier_render_hidden_source_mesh_count": 0,
			"soldier_render_cached_source_mesh_count": 0,
			"soldier_render_last_sync_ms": 0.0,
			"soldier_render_max_sync_ms": 0.0,
			"soldier_render_last_transform_writes": 0,
			"soldier_render_max_transform_writes": 0,
			"soldier_render_last_source_reads": 0,
			"soldier_render_sync_count": 0,
			"soldier_render_sync_skip_count": _soldier_render_sync_skip_count,
		}
	return {
		"soldier_render_batching_enabled": soldier_render_batching_enabled,
		"soldier_render_batch_count": int(_soldier_batch_renderer.call("get_batch_count")) if _soldier_batch_renderer.has_method("get_batch_count") else 0,
		"soldier_render_batched_instance_count": int(_soldier_batch_renderer.call("get_batched_instance_count")) if _soldier_batch_renderer.has_method("get_batched_instance_count") else 0,
		"soldier_render_hidden_source_mesh_count": int(_soldier_batch_renderer.call("get_hidden_source_mesh_count")) if _soldier_batch_renderer.has_method("get_hidden_source_mesh_count") else 0,
		"soldier_render_cached_source_mesh_count": int(_soldier_batch_renderer.call("get_cached_source_mesh_count")) if _soldier_batch_renderer.has_method("get_cached_source_mesh_count") else 0,
		"soldier_render_last_sync_ms": float(int(_soldier_batch_renderer.call("get_last_sync_usec")) if _soldier_batch_renderer.has_method("get_last_sync_usec") else 0) / 1000.0,
		"soldier_render_max_sync_ms": float(int(_soldier_batch_renderer.call("get_max_sync_usec")) if _soldier_batch_renderer.has_method("get_max_sync_usec") else 0) / 1000.0,
		"soldier_render_last_transform_writes": int(_soldier_batch_renderer.call("get_last_sync_transform_writes")) if _soldier_batch_renderer.has_method("get_last_sync_transform_writes") else 0,
		"soldier_render_max_transform_writes": int(_soldier_batch_renderer.call("get_max_sync_transform_writes")) if _soldier_batch_renderer.has_method("get_max_sync_transform_writes") else 0,
		"soldier_render_last_source_reads": int(_soldier_batch_renderer.call("get_last_sync_source_reads")) if _soldier_batch_renderer.has_method("get_last_sync_source_reads") else 0,
		"soldier_render_sync_count": int(_soldier_batch_renderer.call("get_sync_count")) if _soldier_batch_renderer.has_method("get_sync_count") else 0,
		"soldier_render_sync_skip_count": _soldier_render_sync_skip_count,
	}


func _spawn_independent_camp(wood_invested: float, starting_food: float, starting_wood: float) -> void:
	_clear_independent_camp()
	var camp := CampScript.new() as Camp
	camp.name = "%s_Camp" % String(troop_id)
	camp.configure_from_troop(self, wood_invested, starting_food, starting_wood)
	camp.top_level = true
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(camp)
	else:
		add_child(camp)
	camp.owner = null
	camp.global_position = _camp_world_position
	_camp_node = camp
	_connect_camp_signals(camp)
	_sync_camp_storage_from_node()


func _clear_independent_camp() -> void:
	if (
		_cargo_trolley_visual_container
		and is_instance_valid(_cargo_trolley_visual_container)
		and _camp_node
		and _cargo_trolley_visual_container.get_parent() == _camp_node
	):
		_clear_cargo_trolley_visuals()
	if _camp_node and is_instance_valid(_camp_node):
		_camp_node.remove_from_group(&"camps")
		if _camp_node.get_parent():
			_camp_node.get_parent().remove_child(_camp_node)
		_camp_node.free()
	_camp_node = null


func _connect_camp_signals(camp: Node) -> void:
	if not camp:
		return
	var callable := Callable(self, "_on_owned_camp_changed")
	if camp.has_signal(&"logistics_changed") and not camp.is_connected(&"logistics_changed", callable):
		camp.connect(&"logistics_changed", callable)


func _on_owned_camp_changed(_summary: Dictionary = {}) -> void:
	_sync_camp_storage_from_node()
	_emit_logistics_changed()


func _get_owned_camp() -> Node:
	if _camp_node and is_instance_valid(_camp_node) and not _camp_node.is_queued_for_deletion():
		return _camp_node
	return null


func _sync_independent_camp_settings() -> void:
	var camp := _get_owned_camp()
	if camp:
		if _object_has_property(camp, &"camp_range_m"):
			camp.set("camp_range_m", camp_pack_range_m)
		if _object_has_property(camp, &"camp_building_scale"):
			camp.set("camp_building_scale", maxf(camp_building_scale, 0.1))
		if _object_has_property(camp, &"team_flag_color"):
			camp.set("team_flag_color", team_flag_color)
		if _object_has_property(camp, &"camp_flag_color"):
			camp.set("camp_flag_color", troop_flag_color)


func _sync_camp_storage_from_node() -> void:
	var camp := _get_owned_camp()
	if not camp:
		return
	if _object_has_property(camp, &"food_kg"):
		camp_food_kg = maxf(float(camp.get("food_kg")), 0.0)
	if _object_has_property(camp, &"wood_kg"):
		camp_wood_kg = maxf(float(camp.get("wood_kg")), 0.0)
	if _object_has_property(camp, &"invested_wood_kg"):
		_camp_wood_invested_kg = maxf(float(camp.get("invested_wood_kg")), 0.0)


func _get_nearby_camps_in_range() -> Array[Node]:
	var camps: Array[Node] = []
	var tree := get_tree()
	if not tree:
		return camps
	for camp: Node in tree.get_nodes_in_group(&"camps"):
		if not is_instance_valid(camp) or camp.is_queued_for_deletion():
			continue
		var camp_team: Variant = camp.get("team_id")
		if camp_team == null or StringName(camp_team) != team_id:
			continue
		if camp.has_method("is_troop_in_range") and not bool(camp.call("is_troop_in_range", self)):
			continue
		camps.append(camp)
	camps.sort_custom(func(a: Node, b: Node) -> bool:
		if not (a is Node3D) or not (b is Node3D):
			return false
		return global_position.distance_squared_to((a as Node3D).global_position) < global_position.distance_squared_to((b as Node3D).global_position)
	)
	return camps


func _is_friendly_camp_in_range(camp: Node) -> bool:
	if not camp or not is_instance_valid(camp) or camp.is_queued_for_deletion():
		return false
	var camp_team: Variant = camp.get("team_id")
	if camp_team == null or str(camp_team) != str(team_id):
		return false
	if camp.has_method("is_troop_in_range"):
		return bool(camp.call("is_troop_in_range", self))
	if camp is Node3D:
		return global_position.distance_to((camp as Node3D).global_position) <= maxf(camp_pack_range_m, 0.1)
	return false


func _get_primary_in_range_camp() -> Node:
	var camps := _get_nearby_camps_in_range()
	return camps[0] if not camps.is_empty() else null


func _consume_food_from_nearby_camps(amount_kg: float) -> float:
	var remaining := maxf(amount_kg, 0.0)
	var consumed := 0.0
	for camp: Node in _get_nearby_camps_in_range():
		if remaining <= 0.0:
			break
		if not camp.has_method("withdraw_food_kg"):
			continue
		var moved := maxf(float(camp.call("withdraw_food_kg", remaining)), 0.0)
		remaining = maxf(remaining - moved, 0.0)
		consumed += moved
	_sync_camp_storage_from_node()
	return consumed


func _deposit_to_primary_camp(resource_type: StringName, amount_kg: float) -> float:
	var camp := _get_primary_in_range_camp()
	if not camp:
		return 0.0
	match resource_type:
		MISSION_FOOD, RESOURCE_FOOD:
			if camp.has_method("deposit_food_kg"):
				return maxf(float(camp.call("deposit_food_kg", amount_kg)), 0.0)
		MISSION_WOOD, RESOURCE_WOOD:
			if camp.has_method("deposit_wood_kg"):
				return maxf(float(camp.call("deposit_wood_kg", amount_kg)), 0.0)
	return 0.0


func _get_nearby_camp_transfer_summary() -> Dictionary:
	var camp := _get_primary_in_range_camp()
	if not camp:
		return {
			"nearby_camp_in_range": false,
			"nearby_camp_food_kg": 0.0,
			"nearby_camp_wood_kg": 0.0,
			"nearby_camp_range_m": 0.0,
		}
	return {
		"nearby_camp_in_range": true,
		"nearby_camp_food_kg": maxf(float(camp.get("food_kg")) if _object_has_property(camp, &"food_kg") else 0.0, 0.0),
		"nearby_camp_wood_kg": maxf(float(camp.get("wood_kg")) if _object_has_property(camp, &"wood_kg") else 0.0, 0.0),
		"nearby_camp_range_m": maxf(float(camp.get("camp_range_m")) if _object_has_property(camp, &"camp_range_m") else camp_pack_range_m, 0.0),
	}


func _get_deserter_spawn_position() -> Vector3:
	var direction := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	if _is_valid_enemy(_active_enemy):
		direction = global_position - (_active_enemy as Node3D).global_position
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var min_distance := maxf(deserter_min_spawn_distance_m, 0.0)
	var max_distance := maxf(deserter_max_spawn_distance_m, min_distance)
	return _snap_world_point(global_position + direction * _rng.randf_range(min_distance, max_distance))


func _get_nearby_deserter_troops() -> Array[Node]:
	var deserters: Array[Node] = []
	var tree := get_tree()
	if not tree:
		return deserters
	for node: Node in tree.get_nodes_in_group(&"deserter_troops"):
		var spatial := _as_valid_node3d(node)
		if not spatial or spatial == self or spatial.is_queued_for_deletion():
			continue
		if spatial.has_method("is_defeated") and bool(spatial.call("is_defeated")):
			continue
		if global_position.distance_to(spatial.global_position) <= maxf(deserter_persuasion_range_m, 0.1):
			deserters.append(spatial)
	return deserters


func _get_nearby_deserter_summary() -> Dictionary:
	var deserters := _get_nearby_deserter_troops()
	var soldier_total := 0
	for troop: Node in deserters:
		if troop.has_method("get_active_soldier_count"):
			soldier_total += maxi(int(troop.call("get_active_soldier_count")), 0)
	return {
		"can_persuade_deserters": team_id != TEAM_DESERTER and not deserters.is_empty(),
		"nearby_deserter_troop_count": deserters.size(),
		"nearby_deserter_count": soldier_total,
		"deserter_persuasion_range_m": deserter_persuasion_range_m,
	}


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
	_ensure_dependency_defaults()
	_set_troop_selectable_metadata(spatial)
	if spatial.has_method("configure_behavior_set"):
		spatial.call("configure_behavior_set", soldier_behavior_set)
	var supports_formation_animation := spatial.has_method("set_formation_walking")
	spatial.process_mode = Node.PROCESS_MODE_INHERIT if supports_formation_animation else Node.PROCESS_MODE_DISABLED
	if supports_formation_animation:
		spatial.call("set_formation_walking", _state == STATE_MOVING, _get_soldier_path_speed(spatial))
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
			float(stats.get("max_endurance", base_soldier_endurance)),
			float(stats.get("run_speed", base_soldier_run_speed))
		)
	if spatial.has_method("set_activity_mode"):
		spatial.call("set_activity_mode", _get_soldier_activity_mode())
	if spatial.has_method("configure_outfit_palette"):
		spatial.call("configure_outfit_palette", _make_outfit_palette())
	if spatial.has_method("set_soldier_perf_monitoring_enabled"):
		spatial.call("set_soldier_perf_monitoring_enabled", soldier_perf_monitoring_enabled)
	elif _object_has_property(spatial, &"soldier_perf_monitoring_enabled"):
		spatial.set("soldier_perf_monitoring_enabled", soldier_perf_monitoring_enabled)
	if _object_has_property(spatial, &"idle_pose_update_interval"):
		spatial.set("idle_pose_update_interval", soldier_idle_pose_update_interval)
	if _object_has_property(spatial, &"active_pose_update_interval"):
		spatial.set("active_pose_update_interval", soldier_active_pose_update_interval)
	if _object_has_property(spatial, &"use_terrain_height"):
		spatial.set("use_terrain_height", false)
	if spatial.has_method("disable_formation_physics"):
		spatial.call("disable_formation_physics")
	if spatial.has_method("strip_formation_runtime_helpers"):
		spatial.call("strip_formation_runtime_helpers")
	if spatial is CollisionObject3D:
		var collision := spatial as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false
	_track_soldier_mutation_signals(spatial)


func _track_soldier_mutation_signals(soldier: Node) -> void:
	if not soldier:
		return
	if soldier.has_signal(&"health_changed"):
		var health_callable := Callable(self, "_on_soldier_health_changed").bind(soldier)
		if not soldier.is_connected(&"health_changed", health_callable):
			soldier.connect(&"health_changed", health_callable)
	if soldier.has_signal(&"combat_stats_changed"):
		var stats_callable := Callable(self, "_on_soldier_combat_stats_changed").bind(soldier)
		if not soldier.is_connected(&"combat_stats_changed", stats_callable):
			soldier.connect(&"combat_stats_changed", stats_callable)
	for signal_name: StringName in [&"died", &"deserted"]:
		if soldier.has_signal(signal_name):
			var membership_callable := Callable(self, "_on_soldier_membership_changed").bind(soldier)
			if not soldier.is_connected(signal_name, membership_callable):
				soldier.connect(signal_name, membership_callable)


func _on_soldier_health_changed(_current: Variant = null, _maximum: Variant = null, _soldier: Variant = null) -> void:
	_mark_combat_stats_dirty()


func _on_soldier_combat_stats_changed(_summary: Variant = null, _soldier: Variant = null) -> void:
	_mark_combat_stats_dirty()
	_soldier_cache_dirty = true


func _on_soldier_membership_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	var soldier := _extract_membership_changed_soldier(_a, _b, _c)
	var defer_dead_render_compaction := (
		soldier
		and not _should_compact_after_departed_soldiers()
		and soldier.has_method("is_alive")
		and not bool(soldier.call("is_alive"))
	)
	if soldier and _should_remove_from_current_soldiers(soldier):
		_queue_departed_soldier_removal(soldier)
	_invalidate_soldier_cache()
	if soldier:
		_mark_soldier_render_dirty(soldier)
		if not defer_dead_render_compaction:
			_force_full_soldier_render_sync()
	_mark_unit_selection_proxies_dirty()
	_emit_combat_changed()


func _queue_departed_soldier_removal(soldier: Node) -> void:
	if not is_instance_valid(soldier):
		return
	var soldier_id := soldier.get_instance_id()
	if _pending_departed_soldier_ids.has(soldier_id):
		return
	_pending_departed_soldier_ids[soldier_id] = true
	_pending_departed_soldiers.append(soldier)
	_schedule_pending_departed_soldier_removal()


func _schedule_pending_departed_soldier_removal(delay_seconds: float = 0.0) -> void:
	if _departed_soldier_removal_queued:
		return
	_departed_soldier_removal_queued = true
	if delay_seconds <= 0.0 or not is_inside_tree():
		call_deferred("_process_pending_departed_soldier_removals")
		return
	var timer := get_tree().create_timer(delay_seconds, false)
	timer.timeout.connect(Callable(self, "_process_pending_departed_soldier_removals"), CONNECT_ONE_SHOT)


func _process_pending_departed_soldier_removals() -> void:
	_departed_soldier_removal_queued = false
	if _pending_departed_soldiers.is_empty():
		return
	var budget := maxi(departed_soldier_removal_budget_per_frame, 1)
	var soldiers_to_remove: Array[Node] = []
	var soldiers_to_wait: Array[Node] = []
	while budget > 0 and not _pending_departed_soldiers.is_empty():
		var soldier: Node = _pending_departed_soldiers.pop_front()
		if is_instance_valid(soldier):
			if _should_wait_for_soldier_departure_pose(soldier):
				soldiers_to_wait.append(soldier)
				_set_soldier_live_animation_source(soldier, true)
				continue
			_pending_departed_soldier_ids.erase(soldier.get_instance_id())
			if _should_remove_from_current_soldiers(soldier):
				soldiers_to_remove.append(soldier)
				budget -= 1
		else:
			for key: Variant in _pending_departed_soldier_ids.keys():
				if not is_instance_id_valid(int(key)):
					_pending_departed_soldier_ids.erase(key)
	for soldier: Node in soldiers_to_wait:
		if is_instance_valid(soldier):
			_pending_departed_soldiers.append(soldier)
	if not soldiers_to_remove.is_empty():
		_remove_departed_soldiers(soldiers_to_remove)
	if not _pending_departed_soldiers.is_empty():
		_schedule_pending_departed_soldier_removal(0.08)


func _extract_membership_changed_soldier(a: Variant, b: Variant, c: Variant) -> Node:
	for candidate: Variant in [c, b, a]:
		if candidate is Node:
			return candidate as Node
	return null


func _should_remove_from_current_soldiers(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_alive") and not bool(soldier.call("is_alive")):
		return true
	if soldier.has_method("is_deserted") and bool(soldier.call("is_deserted")):
		return true
	return false


func _should_wait_for_soldier_departure_pose(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if not soldier.has_method("is_alive") or bool(soldier.call("is_alive")):
		return false
	if soldier.has_method("is_death_pose_finalized"):
		return not bool(soldier.call("is_death_pose_finalized"))
	return false


func _apply_outfit_to_soldiers() -> void:
	if not _soldier_container:
		return
	var palette := _make_outfit_palette()
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("configure_outfit_palette"):
			soldier.call("configure_outfit_palette", palette)
	if _soldier_batch_renderer and _soldier_batch_renderer.has_method("mark_dirty"):
		_soldier_batch_renderer.call("mark_dirty")
	_soldier_render_has_synced = false


func _apply_team_outfit_defaults() -> void:
	if team_id == TEAM_ENEMY:
		soldier_robe_color = ENEMY_SOLDIER_ROBE_COLOR
		soldier_robe_shadow_color = ENEMY_SOLDIER_ROBE_SHADOW_COLOR
		soldier_trim_color = ENEMY_SOLDIER_TRIM_COLOR
		soldier_pants_color = ENEMY_SOLDIER_PANTS_COLOR
		soldier_wrap_color = ENEMY_SOLDIER_WRAP_COLOR
		soldier_hat_color = ENEMY_SOLDIER_HAT_COLOR
		soldier_accent_color = ENEMY_SOLDIER_ACCENT_COLOR
	elif team_id == TEAM_DESERTER:
		soldier_robe_color = DESERTER_SOLDIER_ROBE_COLOR
		soldier_robe_shadow_color = DESERTER_SOLDIER_ROBE_SHADOW_COLOR
		soldier_trim_color = DESERTER_SOLDIER_TRIM_COLOR
		soldier_pants_color = DESERTER_SOLDIER_PANTS_COLOR
		soldier_wrap_color = DESERTER_SOLDIER_WRAP_COLOR
		soldier_hat_color = DESERTER_SOLDIER_HAT_COLOR
		soldier_accent_color = DESERTER_SOLDIER_ACCENT_COLOR
	else:
		soldier_robe_color = ALLY_SOLDIER_ROBE_COLOR
		soldier_robe_shadow_color = ALLY_SOLDIER_ROBE_SHADOW_COLOR
		soldier_trim_color = ALLY_SOLDIER_TRIM_COLOR
		soldier_pants_color = ALLY_SOLDIER_PANTS_COLOR
		soldier_wrap_color = ALLY_SOLDIER_WRAP_COLOR
		soldier_hat_color = ALLY_SOLDIER_HAT_COLOR
		soldier_accent_color = ALLY_SOLDIER_ACCENT_COLOR


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
	var service = _get_formation_service()
	if not service:
		return global_transform * slot
	return service.slot_to_world(self, slot)


func _get_formation_position(index: int, columns: int, rows: int) -> Vector3:
	var service = _get_formation_service()
	if not service:
		return Vector3.ZERO
	return service.get_formation_position(self, index, columns, rows)


func _get_formation_slot_for_index(index: int, columns: int, rows: int) -> Vector3:
	var service = _get_formation_service()
	if not service:
		return Vector3.ZERO
	return service.get_slot_for_index(self, index, columns, rows)


func _get_formation_natural_offset(index: int, columns: int, rows: int) -> Vector3:
	var service = _get_formation_service()
	if not service:
		return Vector3.ZERO
	return service.get_natural_offset(self, index, columns, rows)


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
	_mark_idle_formation_targets_dirty()
	_clear_formation_target_cache()


func _refresh_active_formation_slot_metas() -> void:
	var soldiers := _get_active_soldiers()
	var total := soldiers.size()
	if total <= 0:
		return
	if not _active_formation_needs_compaction(soldiers):
		return
	var columns := mini(maxi(formation_columns, 1), total)
	var rows := maxi(ceili(float(total) / float(maxi(columns, 1))), 1)
	for index: int in range(total):
		var soldier := soldiers[index]
		if not (soldier is Node3D):
			continue
		var soldier_spatial := soldier as Node3D
		soldier_spatial.set_meta(&"troop_formation_index", index)
		soldier_spatial.set_meta(&"troop_formation_slot", _get_formation_slot_for_index(index, columns, rows))
		soldier_spatial.set_meta(&"troop_formation_phase", float(index) * 1.618)
	_mark_idle_formation_targets_dirty()
	_clear_formation_target_cache()


func _prepare_formation_for_manual_move_command(path_index: int = 0, reassign_slots: bool = true) -> void:
	if _path_points.size() <= 1:
		return
	var safe_path_index := clampi(path_index, 0, _path_points.size() - 1)
	var yaw := _formation_destination_yaw if _formation_destination_yaw_active else _get_yaw_for_direction(_get_formation_path_direction(safe_path_index))
	_set_formation_anchor_yaw_for_command(yaw)
	if reassign_slots:
		_assign_current_soldiers_to_path_slots_once(safe_path_index)
	_last_turn_delta = 0.0
	_last_turn_intensity = 0.0


func _assign_current_soldiers_to_path_slots_once(path_index: int) -> void:
	var soldiers := _get_active_soldiers()
	if soldiers.size() <= 1:
		return

	var route_basis := _get_formation_assignment_basis(path_index)
	var anchor := global_position
	var soldier_records: Array[Dictionary] = []
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var local_position := route_basis.inverse() * (soldier.global_position - anchor)
		soldier_records.append({
			"soldier": soldier,
			"x": local_position.x,
			"z": local_position.z,
		})
	if soldier_records.size() <= 1:
		return

	var total := soldier_records.size()
	var columns := mini(maxi(formation_columns, 1), total)
	var rows := maxi(ceili(float(total) / float(maxi(columns, 1))), 1)
	var slot_records: Array[Dictionary] = []
	for index: int in range(total):
		var slot := _get_formation_slot_for_index(index, columns, rows)
		slot_records.append({
			"index": index,
			"slot": slot,
			"x": slot.x,
			"z": slot.z,
		})

	soldier_records.sort_custom(Callable(self, "_sort_formation_path_assignment_record"))
	slot_records.sort_custom(Callable(self, "_sort_formation_path_assignment_record"))
	for index: int in range(total):
		var soldier := soldier_records[index].get("soldier") as Node3D
		if not soldier:
			continue
		var slot_record := slot_records[index]
		var slot_index := int(slot_record.get("index", index))
		soldier.set_meta(&"troop_formation_index", slot_index)
		soldier.set_meta(&"troop_formation_slot", slot_record.get("slot", Vector3.ZERO))
		soldier.set_meta(&"troop_formation_phase", float(slot_index) * 1.618)
	_mark_idle_formation_targets_dirty()
	_clear_formation_target_cache()


func _set_formation_anchor_yaw_for_command(yaw: float) -> void:
	rotation.y = yaw


func _get_formation_assignment_basis(path_index: int) -> Basis:
	if _formation_destination_yaw_active:
		return Basis(Vector3.UP, _formation_destination_yaw)
	return _get_formation_path_basis(path_index)


func _get_yaw_for_direction(direction: Vector3) -> float:
	var horizontal := direction
	horizontal.y = 0.0
	if horizontal.length_squared() <= 0.0001:
		return rotation.y
	horizontal = horizontal.normalized()
	return atan2(-horizontal.x, -horizontal.z)


func _set_formation_destination_yaw_from_manual_move(requested_world_position: Vector3) -> void:
	var direction := _destination - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = requested_world_position - global_position
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = _get_formation_path_direction(_get_moving_retarget_formation_path_index())
	if direction.length_squared() <= 0.0001:
		return
	_formation_destination_yaw = _get_yaw_for_direction(direction)
	_formation_destination_yaw_active = true


func _sort_formation_path_assignment_record(a: Variant, b: Variant) -> bool:
	var record_a := a as Dictionary
	var record_b := b as Dictionary
	var z_a := float(record_a.get("z", 0.0))
	var z_b := float(record_b.get("z", 0.0))
	if absf(z_a - z_b) > 0.001:
		return z_a < z_b
	var x_a := float(record_a.get("x", 0.0))
	var x_b := float(record_b.get("x", 0.0))
	return x_a < x_b


func _active_formation_needs_compaction(soldiers: Array[Node]) -> bool:
	if not _soldier_container:
		return false
	if soldiers.size() != _soldier_container.get_child_count():
		return true
	var seen_indices := {}
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			return true
		var soldier := soldier_node as Node3D
		var index := int(soldier.get_meta(&"troop_formation_index", -1))
		if index < 0 or index >= soldiers.size() or seen_indices.has(index):
			return true
		seen_indices[index] = true
	return seen_indices.size() != soldiers.size()


func _set_formation_columns_preserving_soldiers(columns: int) -> void:
	var safe_columns := maxi(columns, 1)
	if formation_columns == safe_columns:
		_refresh_formation_slot_metas()
		return
	_suppress_formation_rebuild = true
	formation_columns = safe_columns
	_suppress_formation_rebuild = false
	_refresh_formation_slot_metas()


func _get_formation_columns_for_width(width_m: float) -> int:
	var active_count := maxi(get_active_soldier_count(), 1)
	var service = _get_formation_service()
	if not service:
		return active_count
	return service.get_columns_for_width(self, width_m, active_count)


func _get_yaw_for_formation_right_axis(right_axis: Vector3) -> float:
	var horizontal_right := right_axis
	horizontal_right.y = 0.0
	if horizontal_right.length_squared() <= 0.0001:
		return rotation.y
	horizontal_right = horizontal_right.normalized()
	var forward := Vector3(horizontal_right.z, 0.0, -horizontal_right.x)
	if forward.length_squared() <= 0.0001:
		return rotation.y
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _get_attack_zone_bounds(range_override: float = -1.0) -> Dictionary:
	var inverse := global_transform.affine_inverse()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var has_position := false
	for soldier: Node in _get_active_soldiers():
		if not (soldier is Node3D):
			continue
		var local_position := inverse * (soldier as Node3D).global_position
		min_x = minf(min_x, local_position.x)
		max_x = maxf(max_x, local_position.x)
		min_z = minf(min_z, local_position.z)
		max_z = maxf(max_z, local_position.z)
		has_position = true
	if not has_position:
		min_x = 0.0
		max_x = 0.0
		min_z = 0.0
		max_z = 0.0
	var range_m := range_override if range_override >= 0.0 else _get_mode_engagement_range()
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
		"range": maxf(range_m, 0.1),
	}


func _get_distance_to_attack_zone(world_position: Vector3, range_override: float = -1.0) -> float:
	var bounds := _get_attack_zone_bounds(range_override)
	if bounds.is_empty():
		return INF
	var local_position := global_transform.affine_inverse() * world_position
	var closest_x := clampf(local_position.x, float(bounds.get("min_x", 0.0)), float(bounds.get("max_x", 0.0)))
	var closest_z := clampf(local_position.z, float(bounds.get("min_z", 0.0)), float(bounds.get("max_z", 0.0)))
	var dx := local_position.x - closest_x
	var dz := local_position.z - closest_z
	return sqrt(dx * dx + dz * dz) - float(bounds.get("range", 0.0))


func _is_enemy_inside_engagement_zone(enemy: Node, range_override: float = -1.0) -> bool:
	if not _is_valid_enemy(enemy):
		return false
	var bounds := _get_attack_zone_bounds(range_override)
	if bounds.is_empty():
		return false
	var inverse := global_transform.affine_inverse()
	var min_x := float(bounds.get("min_x", 0.0))
	var max_x := float(bounds.get("max_x", 0.0))
	var min_z := float(bounds.get("min_z", 0.0))
	var max_z := float(bounds.get("max_z", 0.0))
	var range_m := maxf(float(bounds.get("range", 0.0)), 0.0)
	var range_squared := range_m * range_m
	for point: Vector3 in _get_enemy_attack_sample_points(enemy):
		var local_position := inverse * point
		var closest_x := clampf(local_position.x, min_x, max_x)
		var closest_z := clampf(local_position.z, min_z, max_z)
		var dx := local_position.x - closest_x
		var dz := local_position.z - closest_z
		if dx * dx + dz * dz <= range_squared:
			return true
	return false


func _is_enemy_inside_engagement_zone_cached(enemy: Node, delta: float) -> bool:
	if not _is_valid_enemy(enemy):
		_engagement_zone_cached_enemy_id = 0
		_engagement_zone_cached_result = false
		_engagement_zone_check_remaining = 0.0
		return false
	var enemy_id := enemy.get_instance_id()
	_engagement_zone_check_remaining -= maxf(delta, 0.0)
	if enemy_id != _engagement_zone_cached_enemy_id or _engagement_zone_check_remaining <= 0.0:
		_engagement_zone_cached_enemy_id = enemy_id
		_engagement_zone_cached_result = _is_enemy_inside_engagement_zone(enemy)
		_engagement_zone_check_remaining = maxf(combat_engagement_zone_refresh_interval, 0.02)
	return _engagement_zone_cached_result


func _should_continue_engagement(enemy: Node, enemy_in_engagement_zone: bool, delta: float) -> bool:
	if enemy_in_engagement_zone:
		_combat_engagement_break_grace_remaining = maxf(combat_engagement_break_grace_seconds, 0.0)
		return true

	var combat_committed := _state == STATE_FIGHTING or _was_in_combat or _combat_scatter_active
	if not combat_committed:
		_combat_engagement_break_grace_remaining = 0.0
		return false

	if _is_enemy_inside_engagement_zone(enemy, _get_combat_engagement_break_range_m()):
		_combat_engagement_break_grace_remaining = maxf(combat_engagement_break_grace_seconds, 0.0)
		return true

	_combat_engagement_break_grace_remaining = maxf(
		_combat_engagement_break_grace_remaining - maxf(delta, 0.0),
		0.0
	)
	return _combat_engagement_break_grace_remaining > 0.0


func _get_combat_engagement_break_range_m() -> float:
	var engagement_range := _get_mode_engagement_range()
	var spacing_margin := maxf(
		maxf(combat_spear_range_m, combat_socket_radius) * 2.0,
		maxf(formation_spacing, 0.5)
	)
	return maxf(
		engagement_range * maxf(combat_engagement_break_range_multiplier, 1.0),
		engagement_range + spacing_margin
	)


func _get_enemy_attack_sample_points(enemy: Node) -> PackedVector3Array:
	var points := PackedVector3Array()
	var enemy_node := _as_valid_node(enemy)
	if enemy_node and enemy_node.has_method("get_engagement_sample_points"):
		var engagement_value: Variant = enemy_node.call("get_engagement_sample_points")
		if engagement_value is PackedVector3Array:
			for point: Vector3 in engagement_value:
				points.append(point)
		elif engagement_value is Array:
			for point_variant: Variant in engagement_value as Array:
				if point_variant is Vector3:
					points.append(point_variant as Vector3)
	if points.is_empty() and enemy_node and enemy_node.has_method("get_active_soldier_world_positions"):
		var value: Variant = enemy_node.call("get_active_soldier_world_positions")
		if value is PackedVector3Array:
			for point: Vector3 in value:
				points.append(point)
		elif value is Array:
			for point_variant: Variant in value as Array:
				if point_variant is Vector3:
					points.append(point_variant as Vector3)
	var enemy_spatial := _as_valid_node3d(enemy_node)
	if enemy_spatial:
		points.append(enemy_spatial.global_position)
	return points


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
	pole.material_override = _make_flag_material(Color(0.42, 0.28, 0.12, 1.0))
	flag.add_child(pole)

	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(carried_flag_banner_size.x, carried_flag_banner_size.y, 0.035)
	banner.mesh = banner_mesh
	banner.position = Vector3(carried_flag_banner_size.x * 0.5, carried_flag_pole_height * 0.82, 0.0)
	banner.material_override = _make_flag_material(banner_color)
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
	stripe.material_override = _make_flag_material(accent_color)
	flag.add_child(stripe)
	return flag


func _rebuild_ring() -> void:
	_clear_ring()


func _clear_ring() -> void:
	if _ring_instance and is_instance_valid(_ring_instance):
		if _ring_instance.get_parent():
			_ring_instance.get_parent().remove_child(_ring_instance)
		_ring_instance.free()
	_ring_instance = null


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
	_rebuild_management_flag()


func _clear_selection_proxy() -> void:
	if _selection_proxy and is_instance_valid(_selection_proxy):
		if _selection_proxy.get_parent():
			_selection_proxy.get_parent().remove_child(_selection_proxy)
		_selection_proxy.free()
	_selection_proxy = null


func _rebuild_management_flag() -> void:
	_clear_management_flag()
	if is_defeated():
		return

	_management_flag = Node3D.new()
	_management_flag.name = MANAGEMENT_FLAG_NODE_NAME
	_management_flag.top_level = true
	add_child(_management_flag)
	_management_flag.owner = null

	var flag_center := _get_management_flag_sprite_center()
	var initial_pixel_size := _get_management_flag_camera_scaled_pixel_size()
	var border := _create_management_flag_sprite(
		FLAG_BORDER_NODE_NAME,
		_build_management_gonfalon_texture(Color(1.0, 0.82, 0.28, 1.0), Color(1.0, 0.82, 0.28, 1.0)),
		initial_pixel_size * MANAGEMENT_FLAG_BORDER_PIXEL_SIZE_MULTIPLIER,
		29
	)
	border.position = flag_center
	border.visible = false
	_management_flag.add_child(border)
	_management_flag_border_sprite = border

	var sprite := _create_management_flag_sprite(
		MANAGEMENT_FLAG_SPRITE_NAME,
		_build_management_gonfalon_texture(troop_flag_color, team_flag_color),
		initial_pixel_size,
		30
	)
	sprite.position = flag_center
	_management_flag.add_child(sprite)
	_management_flag_sprite = sprite

	_add_management_flag_proxy(flag_center)
	_update_management_flag_position()
	_update_hover_visuals()
	_update_management_flag_facing()
	_update_management_flag_camera_scale(true)


func _clear_management_flag() -> void:
	_clear_selection_proxy()
	if _management_flag and is_instance_valid(_management_flag):
		if _management_flag.get_parent():
			_management_flag.get_parent().remove_child(_management_flag)
		_management_flag.free()
	_management_flag = null
	_management_flag_sprite = null
	_management_flag_border_sprite = null
	_last_management_flag_pixel_size = -1.0


func _add_management_flag_proxy(banner_center: Vector3) -> void:
	if not _management_flag:
		return
	_selection_proxy = StaticBody3D.new()
	_selection_proxy.name = SELECTION_PROXY_NAME
	_selection_proxy.collision_layer = selection_collision_layer
	_selection_proxy.collision_mask = 0
	_selection_proxy.input_ray_pickable = true
	_set_troop_selectable_metadata(_selection_proxy)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		management_flag_banner_size.x + 0.28,
		management_flag_banner_size.y + 0.24,
		0.34
	)
	shape.shape = box
	shape.position = banner_center
	_selection_proxy.add_child(shape)
	_management_flag.add_child(_selection_proxy)
	_selection_proxy.owner = null


func _get_management_flag_sprite_center() -> Vector3:
	return Vector3(0.0, management_flag_pole_height * 0.82, 0.0)


func _create_management_flag_sprite(
	sprite_name: String,
	texture: Texture2D,
	pixel_size_value: float,
	render_priority_value: int
) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = true
	sprite.pixel_size = maxf(pixel_size_value, 0.0001)
	_set_property_if_present(sprite, &"billboard", BaseMaterial3D.BILLBOARD_ENABLED)
	_set_property_if_present(sprite, &"fixed_size", true)
	_set_property_if_present(sprite, &"no_depth_test", true)
	_set_property_if_present(sprite, &"shaded", false)
	_set_property_if_present(sprite, &"double_sided", true)
	_set_property_if_present(sprite, &"transparent", true)
	_set_property_if_present(sprite, &"render_priority", render_priority_value)
	return sprite


func _update_management_flag_camera_scale(force: bool = false) -> void:
	if not is_instance_valid(_management_flag_sprite):
		return
	var pixel_size := _get_management_flag_camera_scaled_pixel_size()
	if (
		not force
		and _last_management_flag_pixel_size >= 0.0
		and absf(pixel_size - _last_management_flag_pixel_size) <= 0.00000001
	):
		return
	_management_flag_sprite.pixel_size = pixel_size
	if is_instance_valid(_management_flag_border_sprite):
		_management_flag_border_sprite.pixel_size = pixel_size * MANAGEMENT_FLAG_BORDER_PIXEL_SIZE_MULTIPLIER
	_last_management_flag_pixel_size = pixel_size


func _get_management_flag_camera_scaled_pixel_size() -> float:
	var near_size := maxf(management_flag_pixel_size, 0.0001)
	var far_size := maxf(management_flag_min_pixel_size, 0.0001)
	var lower_size := minf(near_size, far_size)
	var upper_size := maxf(near_size, far_size)
	var camera := _get_active_camera_3d()
	if not camera:
		return clampf(near_size, lower_size, upper_size)

	var near_distance := maxf(management_flag_near_camera_distance_m, 0.001)
	var far_distance := maxf(management_flag_far_camera_distance_m, 0.001)
	var distance_span := maxf(absf(far_distance - near_distance), 0.001)
	var distance := _get_management_flag_camera_distance(camera)
	var t := clampf((distance - near_distance) / distance_span, 0.0, 1.0)
	if far_distance < near_distance:
		t = 1.0 - t
	return clampf(lerpf(near_size, far_size, t), lower_size, upper_size)


func _get_management_flag_camera_distance(camera: Camera3D) -> float:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return maxf(camera.size, 0.001)
	var flag_position := get_management_flag_world_position()
	var forward := -camera.global_transform.basis.z.normalized()
	var depth := (flag_position - camera.global_position).dot(forward)
	if depth > camera.near:
		return depth
	return camera.global_position.distance_to(flag_position)


func _get_active_camera_3d() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null


func _add_unit_selection_proxy(soldier: Node3D) -> void:
	if not soldier:
		return
	_remove_unit_selection_proxy(soldier)
	_set_troop_selectable_metadata(soldier)

	var proxy := StaticBody3D.new()
	proxy.name = UNIT_SELECTION_PROXY_NAME
	proxy.collision_layer = selection_collision_layer
	proxy.collision_mask = 0
	proxy.input_ray_pickable = true
	_set_troop_selectable_metadata(proxy)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(unit_selection_proxy_radius * soldier_scale, 0.18)
	capsule.height = maxf(unit_selection_proxy_height * soldier_scale, capsule.radius * 2.0 + 0.05)
	shape.shape = capsule
	shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	proxy.add_child(shape)
	soldier.add_child(proxy)
	proxy.owner = null


func _remove_unit_selection_proxy(soldier: Node) -> void:
	if not soldier:
		return
	var proxy := soldier.get_node_or_null(UNIT_SELECTION_PROXY_NAME)
	if proxy:
		if proxy.get_parent():
			proxy.get_parent().remove_child(proxy)
		proxy.free()


func _rebuild_unit_selection_proxies() -> void:
	for soldier_node: Node in _get_formation_soldiers():
		if not (soldier_node is Node3D) or not _is_soldier_active(soldier_node):
			_remove_unit_selection_proxy(soldier_node)
			var marker := soldier_node.get_node_or_null(UNIT_SELECTION_MARKER_NAME) as MeshInstance3D
			if marker:
				marker.visible = false
			continue

		_set_troop_selectable_metadata(soldier_node)
		var proxy := soldier_node.get_node_or_null(UNIT_SELECTION_PROXY_NAME) as StaticBody3D
		if not proxy:
			_add_unit_selection_proxy(soldier_node as Node3D)
			continue
		proxy.collision_layer = selection_collision_layer
		proxy.collision_mask = 0
		proxy.input_ray_pickable = true
		_set_troop_selectable_metadata(proxy)
	_unit_selection_proxy_dirty = false
	_unit_selection_proxy_refresh_remaining = maxf(unit_selection_proxy_refresh_interval, 0.02)


func _mark_unit_selection_proxies_dirty() -> void:
	_unit_selection_proxy_dirty = true


func _refresh_unit_selection_proxies_if_needed(delta: float, force: bool = false) -> void:
	if force:
		_rebuild_unit_selection_proxies()
		return
	_unit_selection_proxy_refresh_remaining = maxf(_unit_selection_proxy_refresh_remaining - delta, 0.0)
	if not _unit_selection_proxy_dirty:
		return
	if _unit_selection_proxy_refresh_remaining > 0.0:
		return
	_rebuild_unit_selection_proxies()


func _set_troop_selectable_metadata(node: Node) -> void:
	if not node:
		return
	node.set_meta(SELECTABLE_TYPE_META, SELECTABLE_TROOP_TYPE)
	node.set_meta(SELECTABLE_NODE_PATH_META, get_path() if is_inside_tree() else NodePath("."))


func _add_management_flag_border(banner_center: Vector3) -> void:
	if not _management_flag:
		return
	var thickness := maxf(minf(management_flag_banner_size.x, management_flag_banner_size.y) * 0.07, 0.045)
	var color := _get_hover_border_color()
	var z := 0.07
	var half_w := management_flag_banner_size.x * 0.5
	var half_h := management_flag_banner_size.y * 0.5
	_add_flag_border_strip(
		"Top",
		Vector3(management_flag_banner_size.x + thickness * 2.0, thickness, 0.07),
		banner_center + Vector3(0.0, half_h + thickness * 0.5, z),
		color
	)
	_add_flag_border_strip(
		"Bottom",
		Vector3(management_flag_banner_size.x + thickness * 2.0, thickness, 0.07),
		banner_center + Vector3(0.0, -half_h - thickness * 0.5, z),
		color
	)
	_add_flag_border_strip(
		"Left",
		Vector3(thickness, management_flag_banner_size.y, 0.07),
		banner_center + Vector3(-half_w - thickness * 0.5, 0.0, z),
		color
	)
	_add_flag_border_strip(
		"Right",
		Vector3(thickness, management_flag_banner_size.y, 0.07),
		banner_center + Vector3(half_w + thickness * 0.5, 0.0, z),
		color
	)


func _add_flag_border_strip(strip_name: String, size: Vector3, position_value: Vector3, color: Color) -> void:
	var strip := MeshInstance3D.new()
	strip.name = "%s_%s" % [FLAG_BORDER_NODE_NAME, strip_name]
	var mesh := BoxMesh.new()
	mesh.size = size
	strip.mesh = mesh
	strip.position = position_value
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	strip.material_override = _make_hover_border_material(color)
	strip.visible = false
	_management_flag.add_child(strip)


func _rebuild_selection_highlight() -> void:
	if _selection_highlight and is_instance_valid(_selection_highlight):
		if _selection_highlight.get_parent():
			_selection_highlight.get_parent().remove_child(_selection_highlight)
		_selection_highlight.free()
	_selection_highlight = null


func _build_selection_highlight_mesh(radius: float) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.25)
	var segments := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var team_color := Color(team_flag_color.r, team_flag_color.g, team_flag_color.b, 0.18)
	var selected_color := Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, 0.22)
	var outer_color := Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, 0.0)

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	colors.append(team_color)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * safe_radius * 0.42)
		normals.append(Vector3.UP)
		colors.append(selected_color)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * safe_radius)
		normals.append(Vector3.UP)
		colors.append(outer_color)

	for index: int in range(segments):
		var next_index := (index + 1) % segments
		var inner_a := 1 + index
		var inner_b := 1 + next_index
		var outer_a := 1 + segments + index
		var outer_b := 1 + segments + next_index
		indices.append(0)
		indices.append(inner_a)
		indices.append(inner_b)
		indices.append(inner_a)
		indices.append(outer_a)
		indices.append(outer_b)
		indices.append(inner_a)
		indices.append(outer_b)
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


func _update_ring_material() -> void:
	_update_hover_visuals()


func _update_selection_highlight_material() -> void:
	if not _selection_highlight:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 19
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.78)
	material.emission_enabled = true
	material.emission = Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, 1.0)
	material.emission_energy_multiplier = 0.08
	_selection_highlight.material_override = material


func _update_selection_highlight_visibility() -> void:
	_update_hover_visuals()


func _rebuild_attack_zone_indicator() -> void:
	_clear_attack_zone_indicator()


func _clear_attack_zone_indicator() -> void:
	if _attack_zone_indicator and is_instance_valid(_attack_zone_indicator):
		if _attack_zone_indicator.get_parent():
			_attack_zone_indicator.get_parent().remove_child(_attack_zone_indicator)
		_attack_zone_indicator.free()
	_attack_zone_indicator = null
	_attack_zone_radius = -1.0


func _update_attack_zone_indicator() -> void:
	_clear_attack_zone_indicator()


func _build_attack_zone_mesh(radius: float) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.1)
	var border_width := minf(maxf(attack_zone_border_width, safe_radius * 0.012), safe_radius * 0.48)
	var fill_radius := maxf(safe_radius - border_width, safe_radius * 0.52)
	var segments := 128
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var center_color := Color(team_flag_color.r, team_flag_color.g, team_flag_color.b, attack_zone_inner_alpha)
	var fill_edge_color := Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, attack_zone_outer_alpha)
	var border_color := Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, attack_zone_border_alpha)

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	colors.append(center_color)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * fill_radius)
		normals.append(Vector3.UP)
		colors.append(fill_edge_color)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * fill_radius)
		normals.append(Vector3.UP)
		colors.append(border_color)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * safe_radius)
		normals.append(Vector3.UP)
		colors.append(border_color)

	for index: int in range(segments):
		var next_index := (index + 1) % segments
		var fill_a := 1 + index
		var fill_b := 1 + next_index
		var border_inner_a := 1 + segments + index
		var border_inner_b := 1 + segments + next_index
		var border_outer_a := 1 + segments * 2 + index
		var border_outer_b := 1 + segments * 2 + next_index
		indices.append(0)
		indices.append(fill_a)
		indices.append(fill_b)
		indices.append(border_inner_a)
		indices.append(border_outer_a)
		indices.append(border_outer_b)
		indices.append(border_inner_a)
		indices.append(border_outer_b)
		indices.append(border_inner_b)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_attack_zone_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.render_priority = -1
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return material


func _update_defeated_presentation() -> void:
	var defeated := is_defeated()
	if defeated == _defeated_presentation_active:
		if not defeated:
			_update_hover_visuals()
		return

	_defeated_presentation_active = defeated
	if defeated:
		_selected = false
		_hovered = false
		_clear_route_visual()
		_clear_ring()
		_clear_management_flag()
		_rebuild_unit_selection_proxies()
		_rebuild_selection_highlight()
		_clear_attack_zone_indicator()
		_update_unit_selection_markers()
		selected_changed.emit(false)
	else:
		_rebuild_management_flag()
		_rebuild_unit_selection_proxies()


func _update_hover_visuals() -> void:
	var active := (_hovered or _selected) and not is_defeated()
	var color := _get_hover_border_color()
	if _management_flag and is_instance_valid(_management_flag):
		for child: Node in _management_flag.get_children():
			if child is Sprite3D and String(child.name).begins_with(FLAG_BORDER_NODE_NAME):
				var sprite := child as Sprite3D
				sprite.visible = active
				sprite.modulate = color
			elif child is MeshInstance3D and String(child.name).begins_with(FLAG_BORDER_NODE_NAME):
				var strip := child as MeshInstance3D
				strip.visible = active
				strip.material_override = _make_hover_border_material(color)
	_update_unit_selection_markers()


func _update_unit_hover_borders() -> void:
	for soldier_node: Node in _get_formation_soldiers():
		if not (soldier_node is Node3D):
			continue
		var soldier := soldier_node as Node3D
		var border := soldier.get_node_or_null(UNIT_HOVER_BORDER_NAME) as MeshInstance3D
		if border:
			border.visible = false
	_update_unit_selection_markers()


func _update_unit_selection_markers() -> void:
	var active := _selected and not is_defeated()
	for soldier_node: Node in _get_formation_soldiers():
		if not (soldier_node is Node3D):
			continue
		var soldier := soldier_node as Node3D
		var border := soldier.get_node_or_null(UNIT_HOVER_BORDER_NAME) as MeshInstance3D
		if border:
			border.visible = false
		var marker := soldier.get_node_or_null(UNIT_SELECTION_MARKER_NAME) as MeshInstance3D
		if active and _is_soldier_active(soldier):
			if not marker:
				marker = _create_unit_selection_marker()
				soldier.add_child(marker)
				marker.owner = null
			marker.visible = true
			marker.material_override = _make_unit_selection_marker_material(_get_unit_selection_marker_color())
		elif marker:
			marker.visible = false


func _rebuild_unit_selection_markers() -> void:
	for soldier_node: Node in _get_formation_soldiers():
		var marker := soldier_node.get_node_or_null(UNIT_SELECTION_MARKER_NAME) as MeshInstance3D
		if marker:
			if marker.get_parent():
				marker.get_parent().remove_child(marker)
			marker.free()
	_update_unit_selection_markers()


func _create_unit_hover_border() -> MeshInstance3D:
	var border := MeshInstance3D.new()
	border.name = UNIT_HOVER_BORDER_NAME
	border.mesh = _build_unit_border_mesh()
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	border.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return border


func _build_unit_border_mesh() -> ArrayMesh:
	var min_point := Vector3(-0.48, 0.05, -0.48)
	var max_point := Vector3(0.48, 1.85, 0.48)
	var corners := [
		Vector3(min_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, max_point.z),
	]
	var edges := [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	var vertices := PackedVector3Array()
	for edge: Vector2i in edges:
		vertices.append(corners[edge.x])
		vertices.append(corners[edge.y])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _create_unit_selection_marker() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = UNIT_SELECTION_MARKER_NAME
	marker.mesh = _build_unit_selection_marker_mesh()
	marker.position = Vector3(0.0, 0.012, 0.0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return marker


func _build_unit_selection_marker_mesh() -> ArrayMesh:
	var radius := maxf(unit_selection_marker_radius, 0.05)
	var segments := 40
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	colors.append(Color.WHITE)
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * radius)
		normals.append(Vector3.UP)
		colors.append(Color.WHITE)

	for index: int in range(segments):
		var next_index := (index + 1) % segments
		indices.append(0)
		indices.append(1 + index)
		indices.append(1 + next_index)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_unit_selection_marker_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.render_priority = 0
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(color.r, color.g, color.b, color.a)
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.02
	return material


func _update_management_flag_facing() -> void:
	if not management_flag_face_camera or not is_instance_valid(_management_flag):
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
	if not camera:
		return
	var to_camera := camera.global_position - _management_flag.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-to_camera.x, -to_camera.z)
	var next_rotation := _management_flag.global_rotation
	next_rotation.x = 0.0
	next_rotation.y = target_yaw
	next_rotation.z = 0.0
	_management_flag.global_rotation = next_rotation


func _update_management_flag_position() -> void:
	if not is_instance_valid(_management_flag):
		return
	var center := _get_unit_centroid_world_position()
	_management_flag.global_position = center + global_transform.basis * management_flag_offset


func _get_unit_centroid_world_position() -> Vector3:
	var soldiers := _get_active_soldiers()
	if soldiers.is_empty():
		soldiers = _get_formation_soldiers()

	var total := Vector3.ZERO
	var count := 0
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			continue
		total += (soldier_node as Node3D).global_position
		count += 1

	if count <= 0:
		return global_position

	return _snap_world_point(total / float(count))


func _sync_movement_anchor_to_flag_point() -> void:
	var center := _get_unit_centroid_world_position()
	var offset := center - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.0004:
		return
	global_position.x = center.x
	global_position.z = center.z
	_snap_to_surface()
	_update_management_flag_position()


func _get_hover_border_color() -> Color:
	if _selected:
		return Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, 0.96)
	return Color(1.0, 0.82, 0.28, 0.92)


func _get_unit_selection_marker_color() -> Color:
	if _selected:
		return Color(selected_ring_color.r, selected_ring_color.g, selected_ring_color.b, 0.86)
	return Color(1.0, 0.82, 0.28, 0.46)


func _make_hover_border_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 25
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.35
	return material


func _make_flag_material(color: Color) -> StandardMaterial3D:
	var material := _make_material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_management_gonfalon_texture(banner_color: Color, accent_color: Color) -> Texture2D:
	var image := Image.create(MANAGEMENT_FLAG_TEXTURE_WIDTH, MANAGEMENT_FLAG_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	_fill_management_flag_image_rect(image, Rect2i(15, 12, 5, 122), Color(0.35, 0.22, 0.1, 1.0))
	_fill_management_flag_image_rect(image, Rect2i(10, 16, 72, 6), Color(0.42, 0.28, 0.12, 1.0))
	_fill_management_flag_image_rect(image, Rect2i(12, 130, 12, 5), Color(0.24, 0.14, 0.06, 1.0))

	var outline := banner_color.darkened(0.35)
	var banner_top := 22
	var banner_bottom := 130
	var accent_top := 84
	var accent_bottom := 101
	for y: int in range(banner_top, banner_bottom):
		for x: int in range(26, 82):
			if not _is_management_gonfalon_pixel(x, y):
				continue
			var color := banner_color
			if y >= accent_top and y <= accent_bottom:
				color = accent_color
			if _is_management_gonfalon_outline_pixel(x, y):
				color = outline
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)


func _is_management_gonfalon_pixel(x: int, y: int) -> bool:
	var left := 26
	var right := 81
	var top := 22
	var bottom := 129
	if x < left or x > right or y < top or y > bottom:
		return false
	var tail_start := 106
	if y < tail_start:
		return true
	var t := float(y - tail_start) / float(maxi(bottom - tail_start, 1))
	var notch_half_width := roundi(11.0 * t)
	var center := 54
	return abs(x - center) > notch_half_width


func _is_management_gonfalon_outline_pixel(x: int, y: int) -> bool:
	if not _is_management_gonfalon_pixel(x, y):
		return false
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _is_management_gonfalon_pixel(x + offset.x, y + offset.y):
			return true
	return false


func _fill_management_flag_image_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


func _set_property_if_present(object: Object, property_name: StringName, value: Variant) -> void:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			object.set(String(property_name), value)
			return


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
	var service = _get_movement_service()
	if service and service.has_method("follow_path"):
		service.follow_path(delta)


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
	if _formation_destination_yaw_active:
		rotation.y = _formation_destination_yaw
		_formation_destination_yaw_active = false
	if _should_gate_movement_completion_for_formation() and not _formation_soldiers_ready_for_arrival():
		_issue_final_formation_targets_if_needed()
		_current_path_index = _path_points.size()
		return
	_path_points.clear()
	_current_path_index = 0
	_has_destination = false
	_manual_move_override_active = false
	_regroup_scattered_positions_on_move = false
	_clear_route_visual()
	_set_state(STATE_IDLE)
	_face_soldiers_to_yaw(rotation.y)
	_mark_idle_formation_targets_dirty()
	_emit_destination_changed()


func _should_gate_movement_completion_for_formation() -> bool:
	if is_mission_troop and _is_mission_active():
		return false
	return not _get_active_soldiers().is_empty()


func _formation_soldiers_ready_for_arrival() -> bool:
	var tolerance := maxf(arrival_radius * 0.32, 0.18)
	var tolerance_squared := tolerance * tolerance
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("has_independent_motion") and bool(soldier_node.call("has_independent_motion")):
			return false
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var desired := _snap_world_point(_formation_slot_to_world(slot))
		desired.y = soldier.global_position.y
		var arrival_target := _get_cached_soldier_arrival_target(soldier, desired)
		var offset := soldier.global_position - arrival_target
		offset.y = 0.0
		if offset.length_squared() > tolerance_squared:
			return false
	return true


func _issue_final_formation_targets_if_needed() -> void:
	var arrival := maxf(arrival_radius * 0.32, 0.18)
	var arrival_squared := arrival * arrival
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("has_independent_motion") and bool(soldier_node.call("has_independent_motion")):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var desired := _snap_world_point(_formation_slot_to_world(slot))
		desired.y = soldier.global_position.y
		var offset := desired - soldier.global_position
		offset.y = 0.0
		if offset.length_squared() <= arrival_squared:
			continue
		var speed := _get_idle_formation_slot_speed(soldier)
		var command_result := _command_soldier_path_target(soldier, desired, speed, arrival)
		_cache_formation_soldier_target_result(soldier.get_instance_id(), desired, speed, arrival, command_result)


func _get_cached_soldier_arrival_target(soldier: Node3D, desired: Vector3) -> Vector3:
	var soldier_id := soldier.get_instance_id()
	var cached_variant: Variant = _formation_slot_target_cache.get(soldier_id)
	if not (cached_variant is Dictionary):
		return desired
	var cached := cached_variant as Dictionary
	if not cached.has("target"):
		return desired
	var cached_target: Vector3 = cached.get("target", desired)
	var target_delta := cached_target - desired
	target_delta.y = 0.0
	var epsilon := maxf(formation_slot_target_epsilon_m, 0.05)
	if target_delta.length_squared() > epsilon * epsilon:
		return desired
	if cached.has("reachable") and not bool(cached.get("reachable", true)):
		return soldier.global_position
	if cached.has("resolved_destination"):
		var resolved: Vector3 = cached.get("resolved_destination", desired)
		resolved.y = soldier.global_position.y
		return resolved
	return desired


func _cache_formation_soldier_target_result(
	soldier_id: int,
	desired: Vector3,
	speed: float,
	arrival: float,
	command_result: Dictionary
) -> void:
	_formation_slot_target_cache[soldier_id] = {
		"target": desired,
		"resolved_destination": command_result.get("resolved_destination", desired),
		"speed": speed,
		"arrival": arrival,
		"reachable": bool(command_result.get("reachable", false)),
		"failure_reason": command_result.get("failure_reason", &""),
	}


func _face_soldiers_to_yaw(yaw: float) -> void:
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("has_independent_motion") and bool(soldier_node.call("has_independent_motion")):
			continue
		(soldier_node as Node3D).rotation.y = yaw


func _prime_formation_motion_facing(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	direction = direction.normalized()
	var yaw := atan2(-direction.x, -direction.z)
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("has_independent_motion") and bool(soldier_node.call("has_independent_motion")):
			continue
		if soldier_node.has_method("set_formation_facing_direction"):
			soldier_node.call("set_formation_facing_direction", direction)
		(soldier_node as Node3D).rotation.y = yaw


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


func _command_soldier_path_target(
	soldier: Node,
	world_position: Vector3,
	speed_mps: float,
	arrival_radius_m: float
) -> Dictionary:
	var spatial := soldier as Node3D
	var destination := _snap_world_point(world_position)
	if spatial:
		destination.y = spatial.global_position.y

	_load_movement_map()
	if _movement_map and soldier.has_method("set_independent_path_target"):
		return soldier.call(
			"set_independent_path_target",
			destination,
			_movement_map,
			maxf(speed_mps, 0.1),
			maxf(arrival_radius_m, 0.05),
			nearest_walkable_search_radius_cells,
			path_smoothing_enabled,
			path_corner_radius_cells,
			path_corner_samples
		) as Dictionary

	if soldier.has_method("set_independent_move_target"):
		soldier.call("set_independent_move_target", destination, maxf(speed_mps, 0.1), maxf(arrival_radius_m, 0.05))
		return {
			"reachable": true,
			"failure_reason": &"",
			"points": [spatial.global_position if spatial else destination, destination],
			"requested_destination": destination,
			"resolved_destination": destination,
		}

	return {
		"reachable": false,
		"failure_reason": &"missing_soldier_move_api",
		"points": [spatial.global_position if spatial else destination],
		"requested_destination": destination,
		"resolved_destination": destination,
	}


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
	if not _route_visual:
		return
	if not _has_destination or not _can_show_route_visual():
		_clear_route_visual()
		return
	_apply_route_visual_settings()
	if individual_route_debug_visuals_enabled and _route_visual.has_method("set_routes"):
		_route_visual.call(
			"set_routes",
			_get_individual_route_records(),
			troop_flag_color,
			team_flag_color,
			_get_route_visual_line_color(),
			_get_route_visual_key(&"individual")
		)
		return
	var points := _get_remaining_route_points()
	if _route_visual.has_method("set_route"):
		_route_visual.call(
			"set_route",
			points,
			_destination,
			troop_flag_color,
			team_flag_color,
			_get_route_visual_line_color(),
			_get_route_visual_key(&"shared")
		)


func _clear_route_visual() -> void:
	if _route_visual and _route_visual.has_method("clear_route"):
		_route_visual.call("clear_route")


func set_combat_debug_lines_enabled(enabled: bool) -> void:
	_set_combat_debug_lines_enabled(enabled)


func are_combat_debug_lines_enabled() -> bool:
	return _combat_debug_lines_enabled_value


func get_combat_target_relation_for_soldier(soldier: Node) -> Dictionary:
	var key := _get_valid_node_instance_id(soldier)
	if key <= 0:
		return {}
	var target_variant: Variant = _combat_soldier_targets.get(key)
	var target := _as_valid_node3d(target_variant)
	if not target:
		return {}
	return {
		"target": target,
		"status": _get_combat_relation_status_by_key(key, target),
	}


func get_combat_attackers_targeting_soldier(target: Node) -> Array[Dictionary]:
	var target_id := _get_valid_node_instance_id(target)
	if target_id <= 0:
		return []
	var target_spatial := _as_valid_node3d(target)
	if not target_spatial:
		return []
	var attackers_variant: Variant = _combat_target_attackers.get(target_id)
	if not (attackers_variant is Dictionary):
		return []
	var attackers := attackers_variant as Dictionary
	var relationships: Array[Dictionary] = []
	for attacker_key: Variant in attackers.keys():
		var attacker := _as_valid_node3d(_get_node_from_instance_id_key(attacker_key))
		if not attacker or not _is_soldier_active(attacker):
			continue
		relationships.append({
			"attacker": attacker,
			"status": _get_combat_relation_status_by_key(attacker_key, target_spatial),
		})
	return relationships


func get_combat_fighting_attacker_targeting(target: Node) -> Node3D:
	var target_spatial := _as_valid_node3d(target)
	if not target_spatial:
		return null
	var target_id := target_spatial.get_instance_id()
	var attackers_variant: Variant = _combat_target_attackers.get(target_id)
	if not (attackers_variant is Dictionary):
		return null
	var attackers := attackers_variant as Dictionary
	var best_attacker: Node3D
	var best_distance_squared := INF
	for attacker_key: Variant in attackers.keys():
		if _get_combat_relation_status_by_key(attacker_key, target_spatial) != COMBAT_RELATION_FIGHTING:
			continue
		var attacker := _as_valid_node3d(_get_node_from_instance_id_key(attacker_key))
		if not attacker or not _is_soldier_active(attacker):
			continue
		var distance_squared := attacker.global_position.distance_squared_to(target_spatial.global_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_attacker = attacker
	return best_attacker


func _set_combat_debug_lines_enabled(enabled: bool) -> void:
	_combat_debug_lines_enabled_value = enabled
	if not is_inside_tree():
		return
	if _combat_debug_lines_enabled_value:
		_ensure_combat_debug_lines()
		_update_combat_debug_lines()
	else:
		_clear_combat_debug_lines()


func _ensure_combat_debug_lines() -> MeshInstance3D:
	if is_instance_valid(_combat_debug_line_mesh):
		_combat_debug_line_mesh.visible = combat_debug_lines_enabled
		return _combat_debug_line_mesh
	_combat_debug_line_mesh = get_node_or_null(COMBAT_DEBUG_LINES_NODE_NAME) as MeshInstance3D
	if not _combat_debug_line_mesh:
		_combat_debug_line_mesh = MeshInstance3D.new()
		_combat_debug_line_mesh.name = COMBAT_DEBUG_LINES_NODE_NAME
		add_child(_combat_debug_line_mesh)
	_combat_debug_line_mesh.top_level = true
	_combat_debug_line_mesh.global_transform = Transform3D.IDENTITY
	_combat_debug_line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_combat_debug_line_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_combat_debug_line_mesh.mesh = ImmediateMesh.new()
	_ensure_combat_debug_line_material()
	_combat_debug_line_mesh.visible = combat_debug_lines_enabled
	return _combat_debug_line_mesh


func _ensure_combat_debug_line_material() -> StandardMaterial3D:
	if _combat_debug_line_material:
		return _combat_debug_line_material
	_combat_debug_line_material = StandardMaterial3D.new()
	_combat_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_combat_debug_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_combat_debug_line_material.albedo_color = combat_debug_line_color
	_combat_debug_line_material.no_depth_test = true
	return _combat_debug_line_material


func _ensure_combat_debug_line_coming_material() -> StandardMaterial3D:
	if _combat_debug_line_coming_material:
		return _combat_debug_line_coming_material
	_combat_debug_line_coming_material = StandardMaterial3D.new()
	_combat_debug_line_coming_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_combat_debug_line_coming_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_combat_debug_line_coming_material.albedo_color = combat_debug_line_coming_color
	_combat_debug_line_coming_material.no_depth_test = true
	return _combat_debug_line_coming_material


func _update_combat_debug_lines() -> void:
	if not combat_debug_lines_enabled:
		_clear_combat_debug_lines()
		return
	var mesh_instance := _ensure_combat_debug_lines()
	var immediate := mesh_instance.mesh as ImmediateMesh
	if not immediate:
		immediate = ImmediateMesh.new()
		mesh_instance.mesh = immediate
	immediate.clear_surfaces()
	mesh_instance.global_transform = Transform3D.IDENTITY
	mesh_instance.visible = true
	_combat_debug_line_pair_count = 0
	_combat_debug_line_coming_pair_count = 0
	_combat_debug_line_fighting_pair_count = 0
	if _state != STATE_FIGHTING or _combat_soldier_targets.is_empty():
		return
	_add_combat_debug_line_surface(immediate, COMBAT_RELATION_COMING, _ensure_combat_debug_line_coming_material())
	_add_combat_debug_line_surface(immediate, COMBAT_RELATION_FIGHTING, _ensure_combat_debug_line_material())


func _add_combat_debug_line_surface(immediate: ImmediateMesh, status_filter: StringName, material: Material) -> void:
	var began_surface := false
	for key: Variant in _combat_soldier_targets.keys():
		var attacker_node := _as_valid_node3d(_get_node_from_instance_id_key(key))
		if not attacker_node or not _is_soldier_active(attacker_node):
			continue
		var defender_variant: Variant = _combat_soldier_targets.get(key)
		var defender := _as_valid_node3d(defender_variant)
		if not defender:
			continue
		if not defender.is_inside_tree():
			continue
		var status := _get_combat_relation_status_by_key(key, defender)
		if status != status_filter:
			continue
		if not began_surface:
			immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
			began_surface = true
		var start := attacker_node.global_position
		var end := defender.global_position
		start.y += maxf(combat_debug_line_height, 0.0)
		end.y += maxf(combat_debug_line_height, 0.0)
		immediate.surface_add_vertex(start)
		immediate.surface_add_vertex(end)
		_combat_debug_line_pair_count += 1
		if status == COMBAT_RELATION_FIGHTING:
			_combat_debug_line_fighting_pair_count += 1
		else:
			_combat_debug_line_coming_pair_count += 1
	if began_surface:
		immediate.surface_end()


func _clear_combat_debug_lines() -> void:
	_combat_debug_line_pair_count = 0
	_combat_debug_line_coming_pair_count = 0
	_combat_debug_line_fighting_pair_count = 0
	if not is_instance_valid(_combat_debug_line_mesh):
		return
	var immediate := _combat_debug_line_mesh.mesh as ImmediateMesh
	if immediate:
		immediate.clear_surfaces()
	_combat_debug_line_mesh.visible = false


func _can_show_route_visual() -> bool:
	return route_debug_visuals_enabled and _state != STATE_FIGHTING and not is_defeated()


func _get_route_visual_line_color() -> Color:
	if team_id == TEAM_ENEMY:
		return ENEMY_ROUTE_LINE_COLOR
	return ALLY_ROUTE_LINE_COLOR


func _get_route_visual_key(mode: StringName) -> StringName:
	return StringName("%s:%d" % [String(mode), _route_visual_command_id])


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


func _get_individual_route_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for soldier_node: Node in _get_active_soldiers():
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if not soldier_node.has_method("get_independent_route_points"):
			continue
		var route_points: Array = soldier_node.call("get_independent_route_points", true) as Array
		if route_points.size() < 2:
			continue
		records.append({
			"id": soldier_node.get_instance_id(),
			"points": route_points,
			"current_position": route_points[0],
			"destination": route_points.back(),
		})
	return records


func _set_state(next_state: StringName) -> void:
	if _state == next_state:
		return
	_state = next_state
	if _state == STATE_MOVING or _state == STATE_FIGHTING:
		_wake_soldier_logic()
		_soldier_render_has_synced = false
		_soldier_render_sync_remaining = 0.0
		_soldier_render_sync_frame_cursor = 0
	if _state == STATE_IDLE or _state == STATE_BLOCKED:
		_soldier_render_has_synced = false
		_soldier_render_sync_frame_cursor = 0
	_update_formation_soldier_locomotion()
	_update_soldier_activity_modes()
	if (_state == STATE_IDLE or _state == STATE_BLOCKED) and not _hold_scattered_positions_after_combat:
		_mark_idle_formation_targets_dirty()
	state_changed.emit(_state)


func _settle_soldiers_at_current_formation_slots() -> void:
	if not _soldier_container:
		return
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		soldier.global_position = _snap_world_point(_formation_slot_to_world(slot))
		soldier.rotation.y = rotation.y
		if soldier.has_method("clear_independent_motion"):
			soldier.call("clear_independent_motion")
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", false, _get_soldier_path_speed(soldier))


func _update_formation_soldier_locomotion() -> void:
	if not _soldier_container:
		return
	var walking := _state == STATE_MOVING
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", walking, _get_soldier_path_speed(soldier))
		if not walking and soldier.has_method("clear_formation_facing_direction"):
			soldier.call("clear_formation_facing_direction")


func _update_formation_soldier_slots(delta: float) -> void:
	if not _soldier_container:
		return

	if _combat_scatter_active and _state != STATE_MOVING:
		return
	if _state == STATE_MOVING and _combat_scatter_active:
		_combat_scatter_active = false

	if _state == STATE_MOVING:
		_formation_motion_time += delta * maxf(_get_current_movement_speed_mps(), 0.1)
		var moving_separation_enabled := formation_moving_separation_enabled or _formation_destination_yaw_active
		_moving_formation_targets_dirty = false
		_formation_slot_last_target_yaw = rotation.y
		_formation_slot_target_refresh_remaining = maxf(formation_slot_refresh_interval, 0.02)
		if moving_separation_enabled:
			_formation_separation_refresh_remaining -= delta
			if _formation_separation_refresh_remaining <= 0.0:
				_formation_separation_refresh_remaining = maxf(formation_separation_refresh_interval, 0.0)
				_apply_moving_formation_separation(delta, _get_moving_separation_route_direction())
		return

	if _state == STATE_IDLE or _state == STATE_BLOCKED:
		if _hold_scattered_positions_after_combat:
			return
		if _idle_formation_targets_dirty:
			_idle_formation_targets_dirty = false
			_idle_formation_target_refresh_remaining = maxf(idle_formation_target_refresh_interval, 0.02)
			_issue_idle_formation_targets()
			return
		_idle_formation_target_refresh_remaining -= delta
		if _idle_formation_target_refresh_remaining <= 0.0:
			_idle_formation_target_refresh_remaining = maxf(idle_formation_target_refresh_interval, 0.02)
			if _idle_formation_needs_refresh():
				_issue_idle_formation_targets()


func _issue_formation_path_to_soldiers(_moving_retarget: bool = false) -> void:
	if not _soldier_container:
		return
	for soldier_node: Node in _soldier_container.get_children():
		if not (soldier_node is Node3D) or not _is_soldier_active(soldier_node):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("clear_independent_motion"):
			soldier_node.call("clear_independent_motion")
		if soldier_node.has_method("set_formation_walking"):
			soldier_node.call("set_formation_walking", true, _get_formation_path_follow_speed())
	_mark_moving_formation_targets_dirty()
	_moving_formation_targets_dirty = false
	_formation_slot_last_target_yaw = rotation.y
	_formation_slot_target_refresh_remaining = maxf(formation_slot_refresh_interval, 0.02)
	if formation_moving_slot_correction_enabled or _formation_destination_yaw_active or _regroup_scattered_positions_on_move:
		_issue_moving_formation_slot_targets(true)


func _issue_moving_formation_slot_targets(force_refresh: bool = false) -> void:
	if not _soldier_container:
		return
	var arrival := maxf(arrival_radius * 0.32, 0.18)
	var tolerance := arrival
	var tolerance_squared := tolerance * tolerance
	var target_epsilon := maxf(formation_slot_target_epsilon_m, 0.01)
	var target_epsilon_squared := target_epsilon * target_epsilon
	var soldiers := _get_active_soldiers()
	if soldiers.is_empty():
		return
	var update_limit := soldiers.size() if force_refresh else mini(maxi(formation_separation_updates_per_tick, 1), soldiers.size())
	var start := clampi(_formation_slot_target_cursor, 0, maxi(soldiers.size() - 1, 0))
	for offset_index: int in range(update_limit):
		var soldier_node: Node = soldiers[(start + offset_index) % soldiers.size()]
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var soldier_id := soldier.get_instance_id()
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var desired := _snap_world_point(_formation_slot_to_world(slot))
		desired.y = soldier.global_position.y
		var offset := desired - soldier.global_position
		offset.y = 0.0
		var has_motion := soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion"))
		if offset.length_squared() <= tolerance_squared:
			if has_motion and soldier.has_method("clear_independent_motion"):
				soldier.call("clear_independent_motion")
			_formation_slot_target_cache.erase(soldier_id)
			_formation_target_skip_count += 1
			if soldier.has_method("set_formation_walking"):
				soldier.call("set_formation_walking", true, _get_formation_path_follow_speed())
			continue
		var speed := _get_idle_formation_slot_speed(soldier)
		var cached_variant: Variant = _formation_slot_target_cache.get(soldier_id)
		var cached := cached_variant as Dictionary if cached_variant is Dictionary else {}
		var target_changed := true
		var cached_unreachable := cached.has("reachable") and not bool(cached.get("reachable", true))
		if cached.has("target"):
			var cached_target: Vector3 = cached.get("target", desired)
			var target_delta := cached_target - desired
			target_delta.y = 0.0
			target_changed = (
				target_delta.length_squared() > target_epsilon_squared
				or absf(float(cached.get("speed", speed)) - speed) > 0.02
				or absf(float(cached.get("arrival", arrival)) - arrival) > 0.01
			)
		if not force_refresh and not target_changed and (has_motion or cached_unreachable):
			_formation_target_skip_count += 1
			continue
		var command_result := _command_soldier_path_target(soldier, desired, speed, arrival)
		var reachable := bool(command_result.get("reachable", false))
		_cache_formation_soldier_target_result(soldier_id, desired, speed, arrival, command_result)
		if reachable:
			_formation_target_write_count += 1
		else:
			_formation_target_skip_count += 1
	_formation_slot_target_cursor = (start + update_limit) % soldiers.size()


func _get_moving_retarget_formation_path_index() -> int:
	if _path_points.size() <= 1:
		return 0

	var lookahead := maxf(route_steering_lookahead_m, maxf(arrival_radius * 0.65, 0.1))
	var fallback_index := _path_points.size() - 1
	for index: int in range(1, _path_points.size()):
		var to_point := _path_points[index] - global_position
		to_point.y = 0.0
		if to_point.length() >= lookahead:
			return index
	return fallback_index


func _get_formation_path_basis(path_index: int) -> Basis:
	var direction := _get_formation_path_direction(path_index)
	var yaw := atan2(-direction.x, -direction.z)
	return Basis(Vector3.UP, yaw)


func _get_formation_path_direction(path_index: int) -> Vector3:
	if _path_points.size() <= 1:
		var fallback := -global_transform.basis.z
		fallback.y = 0.0
		return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.FORWARD

	var safe_index := clampi(path_index, 0, _path_points.size() - 1)
	var anchor := _path_points[safe_index]
	var next_index := mini(safe_index + 1, _path_points.size() - 1)
	var previous_index := maxi(safe_index - 1, 0)
	var direction := Vector3.FORWARD
	if next_index != safe_index:
		direction = _path_points[next_index] - anchor
	else:
		direction = anchor - _path_points[previous_index]
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD


func _issue_idle_formation_targets() -> void:
	if not _soldier_container:
		return
	var arrival := maxf(arrival_radius * 0.32, 0.18)
	var arrival_squared := arrival * arrival
	var soldiers := _get_active_soldiers()
	for soldier_node: Node in soldiers:
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var base_desired := _snap_world_point(_formation_slot_to_world(slot))
		var to_base := base_desired - soldier.global_position
		to_base.y = 0.0
		if to_base.length_squared() <= arrival_squared:
			if soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion")) and soldier.has_method("clear_independent_motion"):
				soldier.call("clear_independent_motion")
			_formation_slot_target_cache.erase(soldier.get_instance_id())
			continue

		var speed := _get_idle_formation_slot_speed(soldier)
		var desired := base_desired
		var command_result := _command_soldier_path_target(soldier, desired, speed, arrival)
		_cache_formation_soldier_target_result(soldier.get_instance_id(), desired, speed, arrival, command_result)
		if not bool(command_result.get("reachable", false)) and not (soldier.has_method("set_independent_path_target") or soldier.has_method("set_independent_move_target")):
			var to_desired := desired - soldier.global_position
			to_desired.y = 0.0
			if to_desired.length() > arrival:
				soldier.global_position += to_desired.normalized() * minf(speed * get_physics_process_delta_time(), to_desired.length())


func _get_soft_formation_separation_offset_from_grid(soldier: Node3D, soldier_grid: Dictionary, cell_size: float) -> Vector3:
	if formation_collision_distance <= 0.0 or soldier_grid.is_empty():
		return Vector3.ZERO
	var offset := Vector3.ZERO
	_get_spatial_neighbors_into(
		soldier_grid,
		soldier.global_position,
		cell_size,
		maxi(formation_collision_neighbor_limit, 1) + 1,
		_spatial_neighbor_buffer
	)
	for ally_node: Node3D in _spatial_neighbor_buffer:
		if ally_node == soldier:
			continue
		offset += _get_pair_separation(soldier, ally_node, formation_collision_distance)
	var max_offset := maxf(formation_collision_distance, 0.0) * 0.35
	if max_offset > 0.0 and offset.length_squared() > max_offset * max_offset:
		offset = offset.normalized() * max_offset
	return offset


func _idle_formation_needs_refresh() -> bool:
	for soldier_node: Node in _get_active_soldiers():
		if not (soldier_node is Node3D):
			continue
		if soldier_node.has_meta(&"troop_carrier_active"):
			continue
		if soldier_node.has_method("has_independent_motion") and bool(soldier_node.call("has_independent_motion")):
			return true
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		var desired := _snap_world_point(_formation_slot_to_world(slot))
		desired.y = soldier.global_position.y
		var arrival_target := _get_cached_soldier_arrival_target(soldier, desired)
		var offset := soldier.global_position - arrival_target
		offset.y = 0.0
		if offset.length_squared() > 0.09:
			return true
	return false


func _get_moving_separation_route_direction() -> Vector3:
	var direction := Vector3.ZERO
	if _state == STATE_MOVING and not _path_points.is_empty() and _current_path_index < _path_points.size():
		direction = _get_route_steering_target() - global_position
		direction.y = 0.0
	if direction.length_squared() <= 0.0001 and _state == STATE_MOVING and not _path_points.is_empty():
		direction = _get_formation_path_direction(_get_moving_retarget_formation_path_index())
	if direction.length_squared() <= 0.0001:
		direction = -global_transform.basis.z
		direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD


func _project_separation_direction_to_route_side(direction: Vector3, route_direction: Vector3, a: Node3D, b: Node3D) -> Vector3:
	direction.y = 0.0
	route_direction.y = 0.0
	if direction.length_squared() <= 0.0001 or route_direction.length_squared() <= 0.0001:
		return direction
	var route := route_direction.normalized()
	var side := Vector3(-route.z, 0.0, route.x)
	var side_amount := direction.dot(side)
	if absf(side_amount) <= 0.05:
		var fallback := _get_deterministic_pair_direction(a, b)
		side_amount = fallback.dot(side)
		if absf(side_amount) <= 0.05:
			side_amount = 1.0
	var side_sign := 1.0 if side_amount >= 0.0 else -1.0
	return side * side_sign


func _apply_moving_formation_separation(delta: float, route_direction: Vector3 = Vector3.ZERO) -> void:
	if delta <= 0.0 or formation_collision_distance <= 0.0 or formation_collision_push_speed <= 0.0:
		return
	var perf_started := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	var soldiers: Array[Node3D] = []
	for soldier_node: Node in _get_active_soldiers():
		if soldier_node is Node3D and not soldier_node.has_meta(&"troop_carrier_active"):
			soldiers.append(soldier_node as Node3D)
	if soldiers.size() < 2:
		return

	var min_distance := maxf(formation_collision_distance, 0.05)
	var min_distance_squared := min_distance * min_distance
	var pushes := _formation_pushes
	pushes.clear()
	_rebuild_spatial_index(_moving_formation_spatial_index, soldiers, min_distance)
	var update_budget := mini(maxi(formation_separation_updates_per_tick, 1), soldiers.size())
	var pair_budget := maxi(formation_pair_checks_budget_per_tick, 1)
	var pair_checks_this_tick := 0
	var start := clampi(_formation_separation_cursor, 0, maxi(soldiers.size() - 1, 0))
	var processed := 0
	while processed < update_budget and pair_checks_this_tick < pair_budget:
		var a := soldiers[(start + processed) % soldiers.size()]
		processed += 1
		var a_id := a.get_instance_id()
		var neighbor_count := 0
		_query_spatial_index(
			_moving_formation_spatial_index,
			a.global_position,
			maxi(formation_collision_neighbor_limit, 1) + 1,
			_spatial_neighbor_buffer
		)
		for b: Node3D in _spatial_neighbor_buffer:
			if pair_checks_this_tick >= pair_budget:
				break
			var b_id := b.get_instance_id()
			if b_id <= a_id:
				continue
			neighbor_count += 1
			if neighbor_count > formation_collision_neighbor_limit:
				break
			pair_checks_this_tick += 1
			_moving_formation_pair_checks += 1
			var separation := a.global_position - b.global_position
			separation.y = 0.0
			var distance_squared := separation.length_squared()
			if distance_squared >= min_distance_squared:
				continue

			var direction := Vector3.ZERO
			var distance := 0.0
			if distance_squared <= 0.0001:
				direction = _get_deterministic_pair_direction(a, b)
			else:
				distance = sqrt(distance_squared)
				direction = separation / distance
			if route_direction.length_squared() > 0.0001:
				direction = _project_separation_direction_to_route_side(direction, route_direction, a, b)
			var overlap := min_distance - distance
			var push := direction * overlap * 0.5
			pushes[a_id] = pushes.get(a_id, Vector3.ZERO) + push
			pushes[b_id] = pushes.get(b_id, Vector3.ZERO) - push
	_formation_separation_cursor = (start + maxi(processed, 1)) % soldiers.size()

	var max_step := formation_collision_push_speed * delta
	for soldier: Node3D in soldiers:
		var correction: Vector3 = pushes.get(soldier.get_instance_id(), Vector3.ZERO)
		correction.y = 0.0
		if correction.length_squared() <= 0.000001:
			continue
		if correction.length() > max_step:
			correction = correction.normalized() * max_step
		soldier.global_position = _snap_world_point(soldier.global_position + correction)
	if troop_perf_monitoring_enabled:
		_perf_last_formation_separation_usec = Time.get_ticks_usec() - perf_started
		_perf_max_formation_separation_usec = maxi(_perf_max_formation_separation_usec, _perf_last_formation_separation_usec)


func _get_deterministic_pair_direction(a: Node3D, b: Node3D) -> Vector3:
	var seed := absi(hash("%s:%s" % [a.name, b.name]))
	var angle := TAU * float(seed % 1024) / 1024.0
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


func _clear_formation_motion_commands() -> void:
	if not _soldier_container:
		return
	for soldier: Node in _soldier_container.get_children():
		if soldier.has_method("clear_independent_motion"):
			soldier.call("clear_independent_motion")
		elif soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", false, _get_soldier_path_speed(soldier))


func _update_food_and_modes(delta: float) -> void:
	var active_count := get_active_soldier_count()
	if active_count <= 0:
		_food_shortage_ratio = 0.0
		return

	_update_food_supply(delta, active_count)
	var fighting := _state == STATE_FIGHTING and _is_valid_enemy(_active_enemy)
	var running := _state == STATE_MOVING and get_movement_mode() == MOVEMENT_RUNNING
	if get_troop_mode() == MODE_TRAINING:
		_train_soldiers(delta)
	if fighting:
		if get_troop_mode() == MODE_ATTACK:
			_drain_soldier_endurance(attack_mode_endurance_loss_per_second * delta)
	elif not running:
		_restore_soldier_endurance(_get_noncombat_endurance_recovery_rate() * delta)

	if _food_shortage_ratio > 0.0:
		if fighting or running:
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
		_manual_attack_target = null
		_was_in_combat = false
		_combat_action_remaining = 0.0
		_combat_logic_accumulator = 0.0
		_combat_target_reassign_remaining = 0.0
		_combat_engagement_break_grace_remaining = 0.0
		_clear_independent_combat(true)
		if _state == STATE_FIGHTING:
			_set_state(STATE_IDLE)
		return

	if _manual_move_override_active and _state == STATE_MOVING:
		_manual_attack_target = null
		var immediate_enemy := _find_enemy_inside_engagement_zone()
		if immediate_enemy:
			_active_enemy = immediate_enemy
		_combat_scan_remaining -= delta
		if _combat_scan_remaining <= 0.0:
			_combat_scan_remaining = maxf(combat_scan_interval, 0.05)
			_refresh_active_enemy()
		if _is_valid_enemy(_active_enemy) and _is_enemy_inside_engagement_zone_cached(_active_enemy, delta):
			_path_points.clear()
			_current_path_index = 0
			_has_destination = false
			_manual_move_override_active = false
			_regroup_scattered_positions_on_move = false
			_clear_formation_motion_commands()
			_clear_route_visual()
			_set_state(STATE_IDLE)
			_emit_destination_changed()
		else:
			_active_enemy = null
			_was_in_combat = false
			_combat_action_remaining = 0.0
			_combat_logic_accumulator = 0.0
			_combat_engagement_break_grace_remaining = 0.0
			_engagement_zone_cached_enemy_id = 0
			_engagement_zone_cached_result = false
			return

	var manual_attack_valid := _is_valid_enemy(_manual_attack_target)
	var immediate_enemy := _find_enemy_inside_engagement_zone()
	if immediate_enemy:
		_active_enemy = immediate_enemy
	elif manual_attack_valid:
		_active_enemy = _manual_attack_target
	else:
		_manual_attack_target = null
		_combat_scan_remaining -= delta
		if _combat_scan_remaining <= 0.0:
			_combat_scan_remaining = maxf(combat_scan_interval, 0.05)
			_refresh_active_enemy()
	if immediate_enemy:
		_combat_scan_remaining = maxf(combat_scan_interval, 0.05)

	var enemy := _active_enemy
	var active_enemy_is_manual_attack := manual_attack_valid and enemy == _manual_attack_target
	if not _is_valid_enemy(enemy):
		_active_enemy = null
		if enemy == _manual_attack_target:
			_manual_attack_target = null
		_engagement_zone_cached_enemy_id = 0
		_engagement_zone_cached_result = false
		if _was_in_combat or _combat_scatter_active:
			_clear_independent_combat(true)
		_was_in_combat = false
		_combat_engagement_break_grace_remaining = 0.0
		if _state == STATE_FIGHTING:
			_set_state(STATE_IDLE)
		return

	_apply_enemy_pressure(delta)
	_update_desertions(delta)
	_try_survivor_rout()

	var enemy_id := enemy.get_instance_id()
	if _last_target_instance_id != enemy_id:
		_last_target_instance_id = enemy_id
		_engagement_windup_remaining = _get_mode_engagement_delay()
		_combat_action_remaining = 0.0
		_combat_logic_accumulator = 0.0
		_combat_target_reassign_remaining = 0.0
		_engagement_zone_check_remaining = 0.0
		_engagement_zone_cached_result = false
		_combat_engagement_break_grace_remaining = 0.0
	else:
		_engagement_windup_remaining = maxf(_engagement_windup_remaining - delta, 0.0)

	var enemy_in_engagement_zone := _should_continue_engagement(
		enemy,
		_is_enemy_inside_engagement_zone_cached(enemy, delta),
		delta
	)
	var should_chase := _should_chase_active_enemy(enemy, enemy_in_engagement_zone)
	if should_chase and not enemy_in_engagement_zone:
		_chase_repath_remaining -= delta
		if _chase_repath_remaining <= 0.0:
			_chase_repath_remaining = maxf(chase_repath_interval, 0.05)
			var was_committed_to_combat := _state == STATE_FIGHTING or _was_in_combat or _combat_scatter_active
			if not _repath_to_attack_target(enemy) and not active_enemy_is_manual_attack and not was_committed_to_combat:
				_active_enemy = null
				_was_in_combat = false
				_combat_action_remaining = 0.0
				_combat_logic_accumulator = 0.0
				_combat_engagement_break_grace_remaining = 0.0
				_engagement_zone_cached_enemy_id = 0
				_engagement_zone_cached_result = false
				_clear_independent_combat(true)
				if _state == STATE_BLOCKED:
					_set_state(STATE_IDLE)
				return

	var can_fight := enemy_in_engagement_zone and _engagement_windup_remaining <= 0.0
	if can_fight:
		if _state == STATE_MOVING:
			_path_points.clear()
			_current_path_index = 0
			_has_destination = false
			_manual_move_override_active = false
			_regroup_scattered_positions_on_move = false
			_clear_formation_motion_commands()
			_clear_route_visual()
			_emit_destination_changed()
		elif _state != STATE_FIGHTING:
			_clear_formation_motion_commands()
		_hold_scattered_positions_after_combat = false
		_set_state(STATE_FIGHTING)
		_combat_logic_accumulator += delta
		var logic_interval := maxf(combat_logic_interval, 0.0)
		if logic_interval <= 0.0 or _combat_logic_accumulator >= logic_interval:
			var combat_delta := _combat_logic_accumulator
			_combat_logic_accumulator = 0.0
			_resolve_combat_tick(enemy, combat_delta)
		_was_in_combat = true
	elif _state == STATE_FIGHTING:
		_clear_independent_combat(true)
		_was_in_combat = false
		_combat_logic_accumulator = 0.0
		_combat_engagement_break_grace_remaining = 0.0
		_set_state(STATE_IDLE)


func _resolve_combat_tick(enemy: Node, delta: float) -> void:
	var perf_started := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	var attackers := _get_active_soldiers()
	var defenders := _get_enemy_active_soldiers(enemy)
	var perf_after_collect := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	if attackers.is_empty() or defenders.is_empty():
		_end_combat_with_inactive_target(enemy)
		return

	var combat_attackers := attackers
	_combat_scatter_active = true
	_drain_soldier_endurance(fight_endurance_loss_per_second * delta)
	_grow_soldiers_from_fighting(delta)
	_build_node_id_set_into(attackers, _combat_attacker_ids)
	_build_node_id_set_into(defenders, _combat_defender_ids)
	_prune_combat_assignments(_combat_attacker_ids, _combat_defender_ids)
	var cell_size := _get_combat_spatial_cell_size()
	_maybe_rebuild_combat_attacker_spatial_index(combat_attackers, cell_size, delta)
	_maybe_rebuild_combat_defender_spatial_index(enemy, defenders, cell_size, delta)
	var perf_after_spatial := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	_combat_target_reassign_remaining -= delta
	var should_rebalance := _combat_soldier_targets.is_empty() or _combat_target_reassign_remaining <= 0.0
	if should_rebalance:
		_combat_target_reassign_remaining = maxf(maxf(combat_rebalance_interval, combat_target_reassignment_interval), 0.02)
	_assign_combat_targets_budgeted(
		combat_attackers,
		defenders,
		_combat_defender_spatial_index,
		_combat_defender_ids,
		should_rebalance
	)
	var perf_after_assign := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	var combat_motion_delta := minf(maxf(delta, 0.0), 0.05)
	var steering_updates_remaining := maxi(combat_separation_updates_per_tick, 1)
	_separation_pair_checks_remaining = maxi(combat_pair_checks_budget_per_tick, 1)
	var steering_now_usec := Time.get_ticks_usec()
	_refresh_close_combat_spacing_targets(combat_attackers, _combat_attacker_spatial_index, steering_now_usec)
	var attacker_count := combat_attackers.size()
	var update_limit := mini(maxi(combat_attacker_updates_per_tick, 1), attacker_count)
	var update_start := clampi(_combat_update_cursor, 0, maxi(attacker_count - 1, 0))
	for offset_index: int in range(update_limit):
		var index := (update_start + offset_index) % attacker_count
		var attacker_spatial := _as_valid_node3d(combat_attackers[index])
		if not attacker_spatial:
			continue
		var defender := _get_assigned_combat_target(attacker_spatial, defenders, _combat_defender_ids)
		if not defender:
			continue
		var forced_defender := _get_enemy_fighting_attacker_targeting_soldier(enemy, attacker_spatial)
		if forced_defender:
			defender = _force_combat_soldier_to_retaliate(attacker_spatial, forced_defender, _combat_target_loads)

		var in_spear_range := _is_combat_pair_in_fight_range(attacker_spatial, defender)
		var locked := _is_combat_soldier_locked_to(attacker_spatial, defender)
		if locked and not in_spear_range:
			_unlock_combat_soldier(attacker_spatial)
			locked = false
		if locked and _has_close_combat_ally_for_lock(attacker_spatial, _combat_attacker_spatial_index):
			_unlock_combat_soldier(attacker_spatial)
			locked = false
		if locked:
			_update_locked_combat_shuffle(attacker_spatial, defender, combat_motion_delta)
			in_spear_range = _is_combat_pair_in_fight_range(attacker_spatial, defender)
		else:
			var steering_result := _get_budgeted_combat_desired_position(
				attacker_spatial,
				defender,
				index,
				combat_attackers.size(),
				_combat_attacker_spatial_index,
				_combat_defender_spatial_index,
				steering_now_usec,
				steering_updates_remaining > 0
			)
			var desired_position: Vector3 = steering_result.get("position", attacker_spatial.global_position)
			if bool(steering_result.get("refreshed", false)):
				steering_updates_remaining -= 1
			_move_combat_soldier_toward(attacker_spatial, defender, desired_position, combat_motion_delta)
			in_spear_range = _is_combat_pair_in_fight_range(attacker_spatial, defender)
			if (
				_is_combat_attack_position_good_enough(attacker_spatial, defender, in_spear_range)
				and not _has_close_combat_ally_for_lock(attacker_spatial, _combat_attacker_spatial_index)
			):
				_lock_combat_soldier(attacker_spatial, defender)
				locked = true

		if attacker_spatial.has_method("set_combat_focus_target"):
			attacker_spatial.call("set_combat_focus_target", defender)
		_face_soldier_toward(attacker_spatial, defender, delta)
		_set_combat_relation_status(attacker_spatial, defender, _get_combat_relation_status_for_pair(attacker_spatial, defender))
		var settled_in_combat := _is_combat_pair_actively_fighting(attacker_spatial, defender)
		var keep_combat_animation := settled_in_combat or _should_hold_soldier_combat_animation(attacker_spatial, defender)
		if keep_combat_animation:
			_set_soldier_live_animation_source(attacker_spatial, true)
		if attacker_spatial.has_method("set_independent_combat"):
			attacker_spatial.call("set_independent_combat", keep_combat_animation, defender if keep_combat_animation else null, settled_in_combat)
		elif attacker_spatial.has_method("set_formation_attacking"):
			attacker_spatial.call("set_formation_attacking", keep_combat_animation, defender if keep_combat_animation else null)
		if not keep_combat_animation and _soldier_should_use_live_animation_source(attacker_spatial):
			_mark_soldier_combat_animation_drain(attacker_spatial)
		_mark_soldier_combat_touched(attacker_spatial)

		if locked or settled_in_combat:
			_face_passive_defender_toward_attacker(defender, attacker_spatial, delta)
		if settled_in_combat:
			_update_soldier_attack(attacker_spatial, defender, delta)
		else:
			_reset_soldier_attack_delay(attacker_spatial)
	_enforce_combat_target_capacity(combat_attackers, defenders, _combat_defender_spatial_index, _combat_defender_ids)
	_combat_update_cursor = (update_start + update_limit) % attacker_count
	_separation_pair_checks_remaining = -1
	if troop_perf_monitoring_enabled:
		var perf_after_motion := Time.get_ticks_usec()
		_perf_last_combat_collect_usec = perf_after_collect - perf_started
		_perf_last_combat_spatial_usec = perf_after_spatial - perf_after_collect
		_perf_last_combat_assign_usec = perf_after_assign - perf_after_spatial
		_perf_last_combat_motion_usec = perf_after_motion - perf_after_assign
		_perf_max_combat_collect_usec = maxi(_perf_max_combat_collect_usec, _perf_last_combat_collect_usec)
		_perf_max_combat_spatial_usec = maxi(_perf_max_combat_spatial_usec, _perf_last_combat_spatial_usec)
		_perf_max_combat_assign_usec = maxi(_perf_max_combat_assign_usec, _perf_last_combat_assign_usec)
		_perf_max_combat_motion_usec = maxi(_perf_max_combat_motion_usec, _perf_last_combat_motion_usec)
		_perf_last_combat_tick_usec = perf_after_motion - perf_started
		_perf_max_combat_tick_usec = maxi(_perf_max_combat_tick_usec, _perf_last_combat_tick_usec)


func _end_combat_with_inactive_target(enemy: Node) -> void:
	if enemy == _active_enemy:
		_active_enemy = null
	if enemy == _manual_attack_target:
		_manual_attack_target = null
	_last_target_instance_id = 0
	_engagement_zone_cached_enemy_id = 0
	_engagement_zone_cached_result = false
	_combat_engagement_break_grace_remaining = 0.0
	_was_in_combat = false
	_clear_independent_combat(true)
	if _state == STATE_FIGHTING:
		_set_state(STATE_IDLE)


func _get_frontline_sorted_combat_attackers(attackers: Array[Node], enemy: Node) -> Array[Node]:
	var enemy_spatial := _as_valid_node3d(enemy)
	if attackers.size() <= 1 or not enemy_spatial:
		return attackers
	_combat_frontline_sort_position = enemy_spatial.global_position
	var sorted: Array[Node] = attackers.duplicate()
	sorted.sort_custom(Callable(self, "_compare_combat_frontline_attackers"))
	return sorted


func _get_frontline_combat_attackers_for_tick(attackers: Array[Node], enemy: Node, limit: int) -> Array[Node]:
	var enemy_spatial := _as_valid_node3d(enemy)
	if attackers.size() <= 1 or limit <= 0 or attackers.size() <= limit or not enemy_spatial:
		return _get_frontline_sorted_combat_attackers(attackers, enemy)
	var enemy_position := enemy_spatial.global_position
	var selected: Array[Node] = []
	var scores: Array[float] = []
	var safe_limit := mini(maxi(limit, 1), attackers.size())
	for attacker_variant: Variant in attackers:
		var spatial := _as_valid_node3d(attacker_variant)
		if not spatial:
			continue
		var target_variant: Variant = _combat_soldier_targets.get(spatial.get_instance_id())
		var sticky_bonus := 1000000000.0 if _as_valid_node3d(target_variant) else 0.0
		var score := spatial.global_position.distance_squared_to(enemy_position) - sticky_bonus
		score += float(spatial.get_instance_id() % 1024) * 0.000001
		var insert_at := selected.size()
		while insert_at > 0 and score < float(scores[insert_at - 1]):
			insert_at -= 1
		if insert_at >= safe_limit:
			continue
		selected.insert(insert_at, spatial)
		scores.insert(insert_at, score)
		if selected.size() > safe_limit:
			selected.pop_back()
			scores.pop_back()
	return selected


func _compare_combat_frontline_attackers(a: Node, b: Node) -> bool:
	var a_spatial := _as_valid_node3d(a)
	if not a_spatial:
		return false
	var b_spatial := _as_valid_node3d(b)
	if not b_spatial:
		return true
	var a_score := a_spatial.global_position.distance_squared_to(_combat_frontline_sort_position)
	var b_score := b_spatial.global_position.distance_squared_to(_combat_frontline_sort_position)
	if is_equal_approx(a_score, b_score):
		return a_spatial.get_instance_id() < b_spatial.get_instance_id()
	return a_score < b_score


func _maybe_rebuild_combat_defender_spatial_index(enemy: Node, defenders: Array[Node], cell_size: float, delta: float) -> void:
	_combat_defender_spatial_rebuild_remaining -= maxf(delta, 0.0)
	var enemy_id := enemy.get_instance_id() if is_instance_valid(enemy) else 0
	var needs_rebuild := (
		_combat_defender_spatial_cached_count != defenders.size()
		or _combat_defender_spatial_cached_enemy_id != enemy_id
		or _combat_defender_spatial_rebuild_remaining <= 0.0
	)
	if not needs_rebuild:
		return
	_rebuild_spatial_index(_combat_defender_spatial_index, defenders, cell_size)
	_combat_defender_spatial_cached_count = defenders.size()
	_combat_defender_spatial_cached_enemy_id = enemy_id
	_combat_defender_spatial_rebuild_remaining = maxf(combat_spatial_rebuild_interval, 0.02)


func _maybe_rebuild_combat_attacker_spatial_index(attackers: Array[Node], cell_size: float, delta: float) -> void:
	_combat_attacker_spatial_rebuild_remaining -= maxf(delta, 0.0)
	var needs_rebuild := (
		_combat_attacker_spatial_cached_count != attackers.size()
		or _combat_attacker_spatial_rebuild_remaining <= 0.0
	)
	if not needs_rebuild:
		return
	_rebuild_spatial_index(_combat_attacker_spatial_index, attackers, cell_size)
	_combat_attacker_spatial_cached_count = attackers.size()
	_combat_attacker_spatial_rebuild_remaining = maxf(minf(combat_spatial_rebuild_interval, combat_steering_refresh_interval), 0.02)


func _repath_to_attack_target(enemy: Node) -> bool:
	if not _is_valid_enemy(enemy):
		return false
	var destination := _get_attack_target_destination(enemy as Node3D)
	if _state == STATE_MOVING and _has_destination and _active_enemy == enemy:
		var destination_delta := destination - _destination
		destination_delta.y = 0.0
		var repath_epsilon := maxf(maxf(arrival_radius, 0.1), combat_spear_range_m * 0.15)
		if destination_delta.length_squared() <= repath_epsilon * repath_epsilon:
			return true
	return set_move_destination(destination, false)


func _get_attack_target_destination(enemy: Node3D) -> Vector3:
	var enemy_position := enemy.global_position
	var away := global_position - enemy_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -global_transform.basis.z
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()

	var engagement_range := _get_mode_engagement_range()
	var standoff := clampf(
		maxf(combat_spear_range_m * 1.2, formation_spacing * 1.2),
		maxf(formation_spacing, 0.5),
		maxf(engagement_range * 0.85, formation_spacing)
	)
	return _snap_world_point(enemy_position + away * standoff)


func _build_node_id_set(nodes: Array[Node]) -> Dictionary:
	var ids := {}
	_build_node_id_set_into(nodes, ids)
	return ids


func _build_node_id_set_into(nodes: Array, ids: Dictionary) -> void:
	ids.clear()
	for node: Variant in nodes:
		var valid_node := _as_valid_node(node)
		if valid_node:
			ids[valid_node.get_instance_id()] = true


func _prune_combat_assignments(attacker_ids: Dictionary, defender_ids: Dictionary) -> void:
	for key: Variant in _combat_soldier_targets.keys():
		var target: Variant = _combat_soldier_targets.get(key)
		var target_id := _get_valid_node_instance_id(target)
		if not attacker_ids.has(key) or not defender_ids.has(target_id):
			_release_combat_assignment(key, not attacker_ids.has(key))
			_combat_target_reassign_remaining = 0.0


func _release_combat_assignment(key: Variant, forget_offset: bool = false) -> void:
	var target_variant: Variant = _combat_soldier_targets.get(key)
	var target_id := _get_valid_node_instance_id(target_variant)
	if target_id > 0:
		_remove_combat_attacker_from_target(key, target_id)
	_combat_soldier_targets.erase(key)
	_combat_soldier_target_statuses.erase(key)
	_combat_soldier_attack_timers.erase(key)
	_combat_visual_thrust_timers.erase(key)
	_combat_soldier_lock_positions.erase(key)
	_combat_soldier_shuffle_offsets.erase(key)
	_combat_soldier_shuffle_timers.erase(key)
	_combat_soldier_steering_cache.erase(key)
	_combat_soldier_spacing_refresh_times.erase(key)
	_combat_soldier_socket_indices.erase(key)
	_combat_soldier_socket_positions.erase(key)
	_combat_soldier_socket_directions.erase(key)
	_combat_soldier_move_targets.erase(key)
	if forget_offset:
		_combat_soldier_offsets.erase(key)


func _assign_combat_targets_budgeted(
	attackers: Array[Node],
	defenders: Array[Node],
	defender_index = null,
	defender_ids: Dictionary = {},
	force_rebalance: bool = false
) -> void:
	if attackers.is_empty() or defenders.is_empty():
		return
	var budget := mini(maxi(combat_target_assignment_budget_per_tick, 1), attackers.size())
	var active_assignment_limit := _get_combat_active_assignment_limit(attackers.size(), defenders.size())
	var load_by_defender := _combat_target_loads
	_get_combat_target_loads_into(defenders, load_by_defender)
	var use_underloaded_fallback := active_assignment_limit >= attackers.size()
	if use_underloaded_fallback:
		_get_underloaded_combat_defenders_into(defenders, load_by_defender, _combat_underloaded_defender_buffer)
	else:
		_combat_underloaded_defender_buffer.clear()
	var current_assignments := _combat_soldier_targets.size()
	var visited := 0
	var processed := 0
	var start := clampi(_combat_assignment_cursor, 0, maxi(attackers.size() - 1, 0))
	while visited < attackers.size() and processed < budget:
		var index := (start + visited) % attackers.size()
		visited += 1
		var attacker := _as_valid_node3d(attackers[index])
		if not attacker:
			continue
		processed += 1
		var key := attacker.get_instance_id()
		var existing_target: Variant = _combat_soldier_targets.get(key)
		var existing_target_spatial := _as_valid_node3d(existing_target)
		var existing_valid := existing_target_spatial != null and defender_ids.has(existing_target_spatial.get_instance_id())
		if (
			existing_valid
			and _should_keep_combat_assignment(attacker, existing_target_spatial, load_by_defender, force_rebalance)
		):
			continue
		if not existing_valid and current_assignments >= active_assignment_limit:
			continue
		if existing_valid:
			var existing_id := existing_target_spatial.get_instance_id()
			load_by_defender[existing_id] = maxi(int(load_by_defender.get(existing_id, 0)) - 1, 0)
			current_assignments = maxi(current_assignments - 1, 0)
		_release_combat_assignment(key)
		var best_target := _find_best_combat_target(
			attacker,
			defenders,
			load_by_defender,
			defender_index,
			null,
			false
		)
		if not best_target and defender_index and use_underloaded_fallback:
			best_target = _find_sampled_underloaded_combat_target(
				attacker,
				_combat_underloaded_defender_buffer,
				load_by_defender
			)
		var defender_capacity := defenders.size() * maxi(combat_max_attackers_per_target, 1)
		if not best_target and active_assignment_limit > defender_capacity:
			best_target = _find_best_combat_target(
				attacker,
				defenders,
				load_by_defender,
				defender_index,
				null,
				true
			)
		if best_target:
			_assign_combat_target_to_soldier(attacker, best_target, load_by_defender)
			current_assignments += 1
	_combat_assignment_cursor = (start + maxi(visited, 1)) % attackers.size()
	_enforce_combat_target_capacity(attackers, defenders, defender_index, defender_ids)


func _get_combat_active_assignment_limit(attacker_count: int, defender_count: int) -> int:
	var defender_capacity := maxi(defender_count, 1) * maxi(combat_max_attackers_per_target, 1)
	return mini(attacker_count, defender_capacity)


func _assign_combat_targets(
	attackers: Array[Node],
	defenders: Array[Node],
	defender_index = null,
	defender_ids: Dictionary = {}
) -> void:
	var load_by_defender := _combat_target_loads
	_get_combat_target_loads_into(defenders, load_by_defender)
	for attacker_variant: Variant in attackers:
		var attacker_spatial := _as_valid_node3d(attacker_variant)
		if not attacker_spatial:
			continue
		var key := attacker_spatial.get_instance_id()
		var existing_target: Variant = _combat_soldier_targets.get(key)
		var existing_target_spatial := _as_valid_node3d(existing_target)
		if (
			existing_target_spatial != null
			and defender_ids.has(existing_target_spatial.get_instance_id())
			and _should_keep_combat_assignment(attacker_spatial, existing_target_spatial, load_by_defender, false)
		):
			continue
		_release_combat_assignment(key)
		var best_target := _find_best_combat_target(attacker_spatial, defenders, load_by_defender, defender_index)
		if best_target:
			_assign_combat_target_to_soldier(attacker_spatial, best_target, load_by_defender)
	_enforce_combat_target_capacity(attackers, defenders, defender_index, defender_ids)


func _enforce_combat_target_capacity(
	attackers: Array[Node],
	defenders: Array[Node],
	defender_index = null,
	defender_ids: Dictionary = {}
) -> void:
	var max_load := maxi(combat_max_attackers_per_target, 1)
	if _get_max_combat_target_load() <= max_load:
		return
	var valid_defender_ids := defender_ids
	if valid_defender_ids.is_empty():
		valid_defender_ids = _build_node_id_set(defenders)
	var load_by_defender := _combat_target_loads
	_get_combat_target_loads_into(defenders, load_by_defender)
	var attackers_by_defender := {}
	for attacker_node: Variant in attackers:
		var attacker := _as_valid_node3d(attacker_node)
		if not attacker:
			continue
		var key := attacker.get_instance_id()
		var target_variant: Variant = _combat_soldier_targets.get(key)
		var target_id := _get_valid_node_instance_id(target_variant)
		if target_id <= 0 or not valid_defender_ids.has(target_id):
			continue
		var target_attackers: Array = attackers_by_defender.get(target_id, [])
		target_attackers.append(attacker)
		attackers_by_defender[target_id] = target_attackers
	for defender_node: Variant in defenders:
		var defender := _as_valid_node3d(defender_node)
		if not defender:
			continue
		var defender_id := defender.get_instance_id()
		var target_attackers: Array = attackers_by_defender.get(defender_id, [])
		while target_attackers.size() > max_load:
			var attacker := _pop_farthest_combat_attacker_from_target(target_attackers, defender)
			if not attacker:
				break
			load_by_defender[defender_id] = maxi(int(load_by_defender.get(defender_id, 0)) - 1, 0)
			_release_combat_assignment(attacker.get_instance_id())
			var replacement := _find_best_combat_target(attacker, defenders, load_by_defender, defender_index, null, false)
			if not replacement:
				_assign_combat_target_to_soldier(attacker, defender, load_by_defender)
				target_attackers.append(attacker)
				break
			_assign_combat_target_to_soldier(attacker, replacement, load_by_defender)
		attackers_by_defender[defender_id] = target_attackers


func _pop_farthest_combat_attacker_from_target(attackers: Array, target: Node3D) -> Node3D:
	var best_index := -1
	var best_distance_squared := -1.0
	for index: int in range(attackers.size()):
		var attacker := _as_valid_node3d(attackers[index])
		if not attacker:
			continue
		var distance_squared := attacker.global_position.distance_squared_to(target.global_position)
		if distance_squared > best_distance_squared:
			best_distance_squared = distance_squared
			best_index = index
	if best_index < 0:
		return null
	var attacker := _as_valid_node3d(attackers[best_index])
	attackers.remove_at(best_index)
	return attacker


func _get_combat_target_loads(defenders: Array[Node]) -> Dictionary:
	var load_by_defender := {}
	_get_combat_target_loads_into(defenders, load_by_defender)
	return load_by_defender


func _get_combat_target_loads_into(defenders: Array, load_by_defender: Dictionary) -> void:
	load_by_defender.clear()
	for defender_variant: Variant in defenders:
		var defender := _as_valid_node(defender_variant)
		if not defender:
			continue
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


func _get_underloaded_combat_defenders_into(
	defenders: Array,
	load_by_defender: Dictionary,
	out_defenders: Array[Node3D]
) -> void:
	out_defenders.clear()
	var max_load := maxi(combat_max_attackers_per_target, 1)
	for defender_node: Variant in defenders:
		var defender := _as_valid_node3d(defender_node)
		if not defender:
			continue
		if int(load_by_defender.get(defender.get_instance_id(), 0)) < max_load:
			out_defenders.append(defender)


func _get_max_combat_target_load() -> int:
	var loads := {}
	var maximum := 0
	for target_variant: Variant in _combat_soldier_targets.values():
		if not is_instance_valid(target_variant):
			continue
		var target_id := _get_valid_node_instance_id(target_variant)
		if target_id <= 0:
			continue
		var load := int(loads.get(target_id, 0)) + 1
		loads[target_id] = load
		maximum = maxi(maximum, load)
	return maximum


func _get_combat_relation_status_count(status: StringName) -> int:
	var count := 0
	for key: Variant in _combat_soldier_targets.keys():
		var defender_variant: Variant = _combat_soldier_targets.get(key)
		var defender := _as_valid_node3d(defender_variant)
		if not defender:
			continue
		if _get_combat_relation_status_by_key(key, defender) == status:
			count += 1
	return count


func _should_keep_combat_assignment(
	attacker: Node3D,
	defender: Node3D,
	load_by_defender: Dictionary,
	force_rebalance: bool
) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	if not force_rebalance:
		return true
	var target_load := int(load_by_defender.get(defender.get_instance_id(), 0))
	if target_load <= maxi(combat_max_attackers_per_target, 1):
		return true
	if _is_combat_soldier_locked_to(attacker, defender):
		return true
	return false


func _assign_combat_target_to_soldier(attacker: Node3D, defender: Node3D, load_by_defender: Dictionary) -> void:
	var key := attacker.get_instance_id()
	var defender_id := defender.get_instance_id()
	_set_combat_relation_status(attacker, defender, _get_combat_relation_status_for_pair(attacker, defender))
	_combat_soldier_steering_cache.erase(key)
	_combat_soldier_lock_positions.erase(key)
	_combat_soldier_shuffle_offsets.erase(key)
	_combat_soldier_shuffle_timers.erase(key)
	_combat_soldier_move_targets.erase(key)
	_combat_soldier_socket_indices[key] = int(load_by_defender.get(defender_id, 0))
	_combat_soldier_socket_positions.erase(key)
	_combat_soldier_socket_directions[key] = _make_combat_socket_direction(
		attacker,
		defender,
		int(_combat_soldier_socket_indices[key]),
		maxi(combat_max_attackers_per_target, 1)
	)
	load_by_defender[defender_id] = int(load_by_defender.get(defender_id, 0)) + 1
	_mark_soldier_combat_touched(attacker)


func _get_valid_node_instance_id(value: Variant) -> int:
	var node := _as_valid_node(value)
	if not node:
		return 0
	return node.get_instance_id()


func _as_valid_node(value: Variant) -> Node:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	return value as Node


func _as_valid_node3d(value: Variant) -> Node3D:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	return value as Node3D


func _set_combat_relation_status(attacker: Node3D, defender: Node3D, status: StringName) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	var key := attacker.get_instance_id()
	var defender_id := defender.get_instance_id()
	var previous_target: Variant = _combat_soldier_targets.get(key)
	var previous_target_id := _get_valid_node_instance_id(previous_target)
	if previous_target_id > 0 and previous_target_id != defender_id:
		_remove_combat_attacker_from_target(key, previous_target_id)
	_combat_soldier_targets[key] = defender
	_combat_soldier_target_statuses[key] = status
	var attackers_variant: Variant = _combat_target_attackers.get(defender_id)
	var attackers := attackers_variant as Dictionary if attackers_variant is Dictionary else {}
	attackers[key] = status
	_combat_target_attackers[defender_id] = attackers


func _remove_combat_attacker_from_target(attacker_key: Variant, defender_id: int) -> void:
	var attackers_variant: Variant = _combat_target_attackers.get(defender_id)
	if not (attackers_variant is Dictionary):
		return
	var attackers := attackers_variant as Dictionary
	attackers.erase(attacker_key)
	if attackers.is_empty():
		_combat_target_attackers.erase(defender_id)
	else:
		_combat_target_attackers[defender_id] = attackers


func _get_combat_relation_status_for_pair(attacker: Node3D, defender: Node3D) -> StringName:
	if _is_combat_pair_in_fight_range(attacker, defender):
		return COMBAT_RELATION_FIGHTING
	return COMBAT_RELATION_COMING


func _get_combat_relation_status_by_key(key: Variant, defender: Node3D = null) -> StringName:
	if is_instance_valid(defender):
		var attacker := _as_valid_node3d(_get_node_from_instance_id_key(key))
		if attacker:
			return _get_combat_relation_status_for_pair(attacker, defender)
	var stored: Variant = _combat_soldier_target_statuses.get(key, COMBAT_RELATION_COMING)
	if stored is StringName:
		return stored
	return COMBAT_RELATION_COMING


func _find_best_combat_target(
	attacker: Node3D,
	defenders: Array[Node],
	load_by_defender: Dictionary,
	defender_index = null,
	current_target: Node3D = null,
	allow_overflow: bool = false
) -> Node3D:
	var candidates: Array = defenders
	if defender_index:
		_query_spatial_index(
			defender_index,
			attacker.global_position,
			mini(maxi(combat_assignment_candidates, 4), maxi(combat_target_search_candidates, 4)),
			_combat_target_candidate_buffer
		)
		if not _combat_target_candidate_buffer.is_empty():
			candidates = _combat_target_candidate_buffer
	var best_target: Node3D
	var best_score := INF
	var max_load := maxi(combat_max_attackers_per_target, 1)
	for defender_node: Variant in candidates:
		var defender := _as_valid_node3d(defender_node)
		if not defender:
			continue
		_combat_perf_target_candidate_scans += 1
		_combat_perf_target_candidate_scan_window += 1
		var defender_id := defender.get_instance_id()
		var load := int(load_by_defender.get(defender_id, 0))
		if not allow_overflow and load >= max_load and defender != current_target:
			continue
		var distance_squared := attacker.global_position.distance_squared_to(defender.global_position)
		var score := (
			distance_squared
			+ _get_combat_lane_penalty(attacker, defender) * 0.001
			+ float(load) * 0.000001
		)
		if allow_overflow:
			score += float(load) * maxf(combat_target_load_penalty, 0.0)
		if defender == current_target:
			score -= maxf(combat_target_stickiness_bonus, 0.0)
		if score < best_score:
			best_score = score
			best_target = defender
	return best_target


func _find_sampled_underloaded_combat_target(
	attacker: Node3D,
	candidates: Array[Node3D],
	load_by_defender: Dictionary
) -> Node3D:
	var candidate_count := candidates.size()
	if candidate_count <= 0:
		return null
	var max_load := maxi(combat_max_attackers_per_target, 1)
	var sample_limit := mini(
		candidate_count,
		maxi(maxi(combat_assignment_candidates, combat_target_search_candidates), 8)
	)
	var start := int(attacker.get_instance_id() % candidate_count)
	var best_target: Node3D
	var best_score := INF
	for offset_index: int in range(sample_limit):
		var defender := candidates[(start + offset_index) % candidate_count]
		if not is_instance_valid(defender):
			continue
		_combat_perf_target_candidate_scans += 1
		_combat_perf_target_candidate_scan_window += 1
		var load := int(load_by_defender.get(defender.get_instance_id(), 0))
		if load >= max_load:
			continue
		var distance_squared := attacker.global_position.distance_squared_to(defender.global_position)
		var score := (
			distance_squared
			+ _get_combat_lane_penalty(attacker, defender) * 0.001
			+ float(load) * 0.000001
		)
		if score < best_score:
			best_score = score
			best_target = defender
	if best_target:
		return best_target
	for offset_index: int in range(candidate_count):
		var defender := candidates[(start + sample_limit + offset_index) % candidate_count]
		if not is_instance_valid(defender):
			continue
		_combat_perf_target_candidate_scans += 1
		_combat_perf_target_candidate_scan_window += 1
		if int(load_by_defender.get(defender.get_instance_id(), 0)) < max_load:
			return defender
	return null


func _get_combat_lane_penalty(attacker: Node3D, defender: Node3D) -> float:
	var axis := Vector3.ZERO
	if _is_valid_enemy(_active_enemy):
		axis = (_active_enemy as Node3D).global_position - global_position
	else:
		axis = defender.global_position - attacker.global_position
	axis.y = 0.0
	if axis.length_squared() <= 0.0001:
		return 0.0
	axis = axis.normalized()
	var side := Vector3(-axis.z, 0.0, axis.x)
	var enemy_origin := (_active_enemy as Node3D).global_position if _is_valid_enemy(_active_enemy) else defender.global_position
	var attacker_lane := (attacker.global_position - global_position).dot(side)
	var defender_lane := (defender.global_position - enemy_origin).dot(side)
	var lane_delta := absf(attacker_lane - defender_lane)
	return lane_delta * lane_delta * 0.18


func _get_enemy_fighting_attacker_targeting_soldier(enemy: Node, soldier: Node3D) -> Node3D:
	if not is_instance_valid(enemy) or not enemy.has_method("get_combat_fighting_attacker_targeting"):
		return null
	var attacker: Variant = enemy.call("get_combat_fighting_attacker_targeting", soldier)
	var attacker_spatial := _as_valid_node3d(attacker)
	if not attacker_spatial:
		return null
	if not _combat_defender_ids.has(attacker_spatial.get_instance_id()):
		return null
	if not _is_combat_pair_in_fight_range(soldier, attacker_spatial):
		return null
	return attacker_spatial


func _force_combat_soldier_to_retaliate(
	soldier: Node3D,
	forced_target: Node3D,
	load_by_defender: Dictionary
) -> Node3D:
	var key := soldier.get_instance_id()
	var forced_target_id := forced_target.get_instance_id()
	var current_target: Variant = _combat_soldier_targets.get(key)
	var current_target_id := _get_valid_node_instance_id(current_target)
	if current_target_id != forced_target_id:
		if current_target_id > 0 and load_by_defender.has(current_target_id):
			load_by_defender[current_target_id] = maxi(int(load_by_defender.get(current_target_id, 0)) - 1, 0)
		_release_combat_assignment(key)
		_assign_combat_target_to_soldier(soldier, forced_target, load_by_defender)
	_lock_combat_soldier(soldier, forced_target)
	return forced_target


func _get_assigned_combat_target(
	attacker: Node3D,
	defenders: Array[Node],
	defender_ids: Dictionary = {}
) -> Node3D:
	var key := attacker.get_instance_id()
	var target_variant: Variant = _combat_soldier_targets.get(key)
	var target := _as_valid_node3d(target_variant)
	if target and defender_ids.has(target.get_instance_id()):
		return target
	_release_combat_assignment(key)
	return null


func _get_soldier_engagement_position(attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	var service = _get_combat_service()
	if not service:
		return defender.global_position
	return service.get_soldier_engagement_position(self, attacker, defender, index, total)


func _clamp_combat_socket_position(defender: Node3D, desired_position: Vector3, y_position: float) -> Vector3:
	var desired := desired_position
	desired.y = y_position
	var spear_range := maxf(combat_spear_range_m, 0.2)
	var from_defender := desired - defender.global_position
	from_defender.y = 0.0
	var clamp_margin := clampf(spear_range * 0.04, 0.06, 0.18)
	var max_socket_distance := maxf(spear_range - clamp_margin, 0.2)
	if from_defender.length_squared() <= max_socket_distance * max_socket_distance:
		return desired
	if from_defender.length_squared() <= 0.000001:
		return desired
	desired = defender.global_position + from_defender.normalized() * max_socket_distance
	desired.y = y_position
	_combat_socket_clamp_count += 1
	return desired


func _get_combat_socket_direction(attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	var service = _get_combat_service()
	if not service:
		return Vector3.FORWARD
	return service.get_combat_socket_direction(self, attacker, defender, index, total)


func _make_combat_socket_direction(attacker: Node3D, defender: Node3D, socket_index: int, total: int) -> Vector3:
	var service = _get_combat_service()
	if not service:
		return Vector3.FORWARD
	return service.make_combat_socket_direction(self, attacker, defender, socket_index, total)


func _get_combat_surround_slot_angle(slot: int, max_slots: int) -> float:
	var service = _get_combat_service()
	if not service:
		return 0.0
	return service.get_combat_surround_slot_angle(slot, max_slots)


func _is_combat_socket_reached(attacker: Node3D) -> bool:
	var socket_variant: Variant = _combat_soldier_socket_positions.get(attacker.get_instance_id())
	if not (socket_variant is Vector3):
		return false
	var target_position: Vector3 = socket_variant
	target_position.y = attacker.global_position.y
	return attacker.global_position.distance_squared_to(target_position) <= pow(maxf(combat_socket_arrival_radius, 0.05), 2.0)


func _refresh_close_combat_spacing_targets(attackers: Array[Node], attacker_index, now_usec: int) -> void:
	if attackers.size() < 2 or attacker_index == null:
		return
	if _separation_pair_checks_remaining == 0:
		return
	var min_distance := _get_combat_lock_ally_spacing_m()
	if min_distance <= 0.0:
		return
	var min_distance_squared := min_distance * min_distance
	var start := clampi(_combat_update_cursor, 0, maxi(attackers.size() - 1, 0))
	var processed := 0
	while processed < attackers.size() and _separation_pair_checks_remaining != 0:
		var attacker_node := _as_valid_node3d(attackers[(start + processed) % attackers.size()])
		processed += 1
		if not attacker_node:
			continue
		var a := attacker_node
		var a_id := a.get_instance_id()
		_query_spatial_index(
			attacker_index,
			a.global_position,
			maxi(combat_max_separation_neighbors, 1) + 1,
			_spatial_neighbor_buffer
		)
		var neighbor_count := 0
		for b: Node3D in _spatial_neighbor_buffer:
			if _separation_pair_checks_remaining == 0:
				break
			if not is_instance_valid(b):
				continue
			var b_id := b.get_instance_id()
			if b_id <= a_id:
				continue
			neighbor_count += 1
			if neighbor_count > combat_max_separation_neighbors:
				break
			_separation_pair_checks_remaining -= 1
			_combat_perf_separation_pair_checks += 1
			_combat_perf_separation_pair_check_window += 1
			var separation := a.global_position - b.global_position
			separation.y = 0.0
			var distance_squared := separation.length_squared()
			if distance_squared >= min_distance_squared:
				continue
			_request_combat_spacing_target_refresh(a, now_usec, true)
			_request_combat_spacing_target_refresh(b, now_usec, true)


func _request_combat_spacing_target_refresh(soldier: Node3D, now_usec: int, force: bool = false) -> void:
	if not is_instance_valid(soldier):
		return
	var key := soldier.get_instance_id()
	var next_refresh_usec := int(_combat_soldier_spacing_refresh_times.get(key, 0))
	if not force and now_usec < next_refresh_usec:
		return
	_combat_soldier_steering_cache.erase(key)
	_combat_soldier_move_targets.erase(key)
	if _combat_soldier_lock_positions.has(key):
		_unlock_combat_soldier(soldier)
	_combat_soldier_spacing_refresh_times[key] = now_usec + _get_combat_steering_refresh_delay_usec(key, now_usec)
	_mark_soldier_combat_touched(soldier)


func _get_combat_steering_refresh_delay_usec(key: Variant, now_usec: int) -> int:
	var base_seconds := maxf(combat_steering_refresh_interval, 0.02)
	var jitter := clampf(combat_steering_refresh_jitter, 0.0, 1.0)
	if jitter <= 0.0:
		return int(base_seconds * 1000000.0)
	var cycle := int(float(now_usec) / maxf(base_seconds * 1000000.0, 1.0))
	var seed := float(absi(hash("%s:%s:%d" % [str(troop_id), str(key), cycle])) % 10000) / 10000.0
	var factor := lerpf(1.0 - jitter * 0.5, 1.0 + jitter * 0.5, seed)
	return int(base_seconds * maxf(factor, 0.05) * 1000000.0)


func _get_combat_lock_ally_spacing_m() -> float:
	var spear_range := maxf(combat_spear_range_m, 0.2)
	var clamp_margin := clampf(spear_range * 0.04, 0.06, 0.18)
	var max_socket_distance := maxf(spear_range - clamp_margin, 0.2)
	var surround_spacing := max_socket_distance * sqrt(2.0) * 0.95
	var configured_spacing := maxf(formation_collision_distance, 0.0)
	if configured_spacing > 0.0:
		return maxf(minf(configured_spacing, surround_spacing), 0.35)
	return maxf(surround_spacing, 0.35)


func _has_close_combat_ally_for_lock(soldier: Node3D, attacker_index) -> bool:
	if not is_instance_valid(soldier) or attacker_index == null:
		return false
	var min_distance := _get_combat_lock_ally_spacing_m()
	if min_distance <= 0.0:
		return false
	var min_distance_squared := min_distance * min_distance
	_query_spatial_index(
		attacker_index,
		soldier.global_position,
		maxi(combat_max_separation_neighbors, 1) + 1,
		_spatial_neighbor_buffer_secondary
	)
	for ally_node: Node3D in _spatial_neighbor_buffer_secondary:
		if ally_node == soldier or not is_instance_valid(ally_node):
			continue
		var separation := soldier.global_position - ally_node.global_position
		separation.y = 0.0
		if separation.length_squared() < min_distance_squared:
			return true
	return false


func _is_combat_attack_position_good_enough(attacker: Node3D, defender: Node3D, in_spear_range: bool) -> bool:
	if not in_spear_range:
		return false
	if _is_combat_socket_reached(attacker):
		return true
	var key := attacker.get_instance_id()
	var socket_variant: Variant = _combat_soldier_socket_positions.get(key)
	if not (socket_variant is Vector3):
		return true
	var socket_position: Vector3 = socket_variant
	socket_position.y = attacker.global_position.y
	var relaxed_radius := maxf(
		maxf(combat_socket_arrival_radius, 0.05),
		minf(maxf(combat_socket_radius, 0.2) * 0.65, maxf(soldier_personal_space_radius, enemy_personal_space_radius))
	)
	if attacker.global_position.distance_squared_to(socket_position) <= relaxed_radius * relaxed_radius:
		return true
	if _is_combat_surround_coverage_good_enough(attacker, defender):
		return true
	var from_defender := attacker.global_position - defender.global_position
	from_defender.y = 0.0
	var desired_from_defender := socket_position - defender.global_position
	desired_from_defender.y = 0.0
	if from_defender.length_squared() <= 0.0001 or desired_from_defender.length_squared() <= 0.0001:
		return false
	var direction_alignment := from_defender.normalized().dot(desired_from_defender.normalized())
	var radial_error := absf(from_defender.length() - desired_from_defender.length())
	if direction_alignment >= 0.35 and radial_error <= relaxed_radius:
		return true
	return false


func _is_combat_surround_coverage_good_enough(attacker: Node3D, defender: Node3D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	if not _is_combat_pair_in_fight_range(attacker, defender):
		return false
	var required_slots := mini(maxi(combat_max_attackers_per_target, 1), 4)
	if required_slots < 3:
		return false
	var attacker_in_surround := false
	var directions: Array[Vector3] = []
	for key: Variant in _combat_soldier_targets.keys():
		var target_variant: Variant = _combat_soldier_targets.get(key)
		var target := _as_valid_node3d(target_variant)
		if target != defender:
			continue
		var soldier := _as_valid_node3d(_get_node_from_instance_id_key(key))
		if not soldier or not _is_soldier_active(soldier) or not _is_combat_pair_in_fight_range(soldier, defender):
			continue
		if soldier == attacker:
			attacker_in_surround = true
		var offset := soldier.global_position - defender.global_position
		offset.y = 0.0
		if offset.length_squared() <= 0.0001:
			continue
		var direction := offset.normalized()
		var duplicate_direction := false
		for existing: Vector3 in directions:
			if direction.dot(existing) > 0.45:
				duplicate_direction = true
				break
		if duplicate_direction:
			continue
		directions.append(direction)
	return attacker_in_surround and directions.size() >= required_slots


func _get_budgeted_combat_desired_position(
	attacker: Node3D,
	defender: Node3D,
	index: int,
	total: int,
	attacker_index,
	defender_index,
	now_usec: int,
	can_refresh: bool
) -> Dictionary:
	var key := attacker.get_instance_id()
	var cached_variant: Variant = _combat_soldier_steering_cache.get(key)
	var cached := cached_variant as Dictionary if cached_variant is Dictionary else {}
	var target_id := defender.get_instance_id()
	var refresh_usec := int(cached.get("refresh_usec", 0))
	var cached_target_id := int(cached.get("target_id", 0))
	if cached_target_id == target_id and cached.has("position") and now_usec < refresh_usec:
		var cached_position: Vector3 = cached.get("position", attacker.global_position)
		cached_position = _clamp_combat_socket_position(defender, cached_position, attacker.global_position.y)
		_combat_soldier_socket_positions[key] = cached_position
		return {
			"position": cached_position,
			"refreshed": false,
		}

	var fallback := _get_soldier_engagement_position(attacker, defender, index, total)
	if not can_refresh and cached_target_id == target_id and cached.has("position"):
		var cached_position: Vector3 = cached.get("position", fallback)
		cached_position = _clamp_combat_socket_position(defender, cached_position, attacker.global_position.y)
		_combat_soldier_socket_positions[key] = cached_position
		return {
			"position": cached_position,
			"refreshed": false,
		}
	if not can_refresh:
		return {
			"position": fallback,
			"refreshed": false,
		}

	var separation := _get_soft_separation_offset_from_indexes(attacker, attacker_index, defender_index)
	var to_socket := fallback - attacker.global_position
	to_socket.y = 0.0
	var separation_scale := clampf(
		to_socket.length() / maxf(combat_socket_radius, 0.5),
		0.0,
		1.0
	)
	var desired := fallback + separation * separation_scale
	desired = _clamp_combat_socket_position(defender, desired, attacker.global_position.y)
	_combat_soldier_socket_positions[key] = desired
	_combat_soldier_steering_cache[key] = {
		"position": desired,
		"target_id": target_id,
		"refresh_usec": now_usec + _get_combat_steering_refresh_delay_usec(key, now_usec),
	}
	_combat_perf_steering_updates += 1
	_combat_perf_steering_update_window += 1
	return {
		"position": desired,
		"refreshed": true,
	}


func _get_combat_offset_for_soldier(attacker: Node3D, index: int, total: int) -> Vector2:
	var service = _get_combat_service()
	if not service:
		return Vector2.ZERO
	return service.get_combat_offset_for_soldier(self, attacker, index, total)


func _get_soft_separation_offset(attacker: Node3D, attackers: Array[Node], defenders: Array[Node]) -> Vector3:
	var cell_size := _get_combat_spatial_cell_size()
	return _get_soft_separation_offset_from_grids(
		attacker,
		_build_spatial_grid(attackers, cell_size),
		_build_spatial_grid(defenders, cell_size),
		cell_size
	)


func _get_soft_separation_offset_from_grids(
	attacker: Node3D,
	attacker_grid: Dictionary,
	defender_grid: Dictionary,
	cell_size: float
) -> Vector3:
	var offset := Vector3.ZERO
	var ally_limit := maxi(combat_max_separation_neighbors, 1) + 1
	_get_spatial_neighbors_into(attacker_grid, attacker.global_position, cell_size, ally_limit, _spatial_neighbor_buffer)
	for ally_node: Node3D in _spatial_neighbor_buffer:
		if ally_node == attacker or not is_instance_valid(ally_node):
			continue
		offset += _get_pair_separation(attacker, ally_node, soldier_personal_space_radius + soldier_personal_space_radius)
	_get_spatial_neighbors_into(
		defender_grid,
		attacker.global_position,
		cell_size,
		maxi(combat_max_separation_neighbors, 1),
		_spatial_neighbor_buffer_secondary
	)
	for enemy_node: Node3D in _spatial_neighbor_buffer_secondary:
		if not is_instance_valid(enemy_node):
			continue
		offset += _get_pair_separation(attacker, enemy_node, soldier_personal_space_radius + enemy_personal_space_radius)
	var max_offset := maxf(combat_separation_strength, 0.0) * 0.22
	if max_offset > 0.0 and offset.length() > max_offset:
		offset = offset.normalized() * max_offset
	return offset


func _get_soft_separation_offset_from_indexes(
	attacker: Node3D,
	attacker_index,
	defender_index
) -> Vector3:
	var offset := Vector3.ZERO
	var ally_limit := maxi(combat_max_separation_neighbors, 1) + 1
	_query_spatial_index(attacker_index, attacker.global_position, ally_limit, _spatial_neighbor_buffer)
	for ally_node: Node3D in _spatial_neighbor_buffer:
		if ally_node == attacker or not is_instance_valid(ally_node):
			continue
		offset += _get_pair_separation(attacker, ally_node, soldier_personal_space_radius + soldier_personal_space_radius)
	_query_spatial_index(
		defender_index,
		attacker.global_position,
		maxi(combat_max_separation_neighbors, 1),
		_spatial_neighbor_buffer_secondary
	)
	for enemy_node: Node3D in _spatial_neighbor_buffer_secondary:
		if not is_instance_valid(enemy_node):
			continue
		offset += _get_pair_separation(attacker, enemy_node, soldier_personal_space_radius + enemy_personal_space_radius)
	var max_offset := maxf(combat_separation_strength, 0.0) * 0.22
	if max_offset > 0.0 and offset.length() > max_offset:
		offset = offset.normalized() * max_offset
	return offset


func _get_combat_spatial_cell_size() -> float:
	return maxf(maxf(soldier_personal_space_radius, enemy_personal_space_radius) * 2.0, 0.5)


func _build_spatial_grid(nodes: Array, cell_size: float) -> Dictionary:
	var grid := {}
	_build_spatial_grid_into(nodes, cell_size, grid)
	return grid


func _rebuild_spatial_index(index, nodes: Array, cell_size: float) -> void:
	if not index:
		return
	index.rebuild(nodes, cell_size)
	_spatial_grid_rebuilds += 1


func _query_spatial_index(
	index,
	position_value: Vector3,
	max_count: int,
	neighbors: Array[Node3D]
) -> void:
	if not index:
		neighbors.clear()
		return
	index.query(position_value, max_count, neighbors)


func _build_spatial_grid_into(nodes: Array, cell_size: float, grid: Dictionary) -> void:
	grid.clear()
	var safe_cell_size := maxf(cell_size, 0.1)
	for node: Variant in nodes:
		var spatial := _as_valid_node3d(node)
		if not spatial:
			continue
		var cell := _get_spatial_cell(spatial.global_position, safe_cell_size)
		var bucket: Array = grid.get(cell, [])
		bucket.append(spatial)
		grid[cell] = bucket


func _get_spatial_neighbors(grid: Dictionary, position_value: Vector3, cell_size: float, max_count: int) -> Array[Node3D]:
	var neighbors: Array[Node3D] = []
	_get_spatial_neighbors_into(grid, position_value, cell_size, max_count, neighbors)
	return neighbors


func _get_spatial_neighbors_into(
	grid: Dictionary,
	position_value: Vector3,
	cell_size: float,
	max_count: int,
	neighbors: Array[Node3D]
) -> void:
	neighbors.clear()
	if grid.is_empty():
		return
	var center := _get_spatial_cell(position_value, maxf(cell_size, 0.1))
	var limit := maxi(max_count, 1)
	for x: int in range(center.x - 1, center.x + 2):
		for y: int in range(center.y - 1, center.y + 2):
			var bucket_variant: Variant = grid.get(Vector2i(x, y))
			if not (bucket_variant is Array):
				continue
			var bucket := bucket_variant as Array
			for node: Variant in bucket:
				var spatial := _as_valid_node3d(node)
				if not spatial:
					continue
				neighbors.append(spatial)
				if neighbors.size() >= limit:
					return


func _get_spatial_cell(position_value: Vector3, cell_size: float) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 0.1)
	return Vector2i(floori(position_value.x / safe_cell_size), floori(position_value.z / safe_cell_size))


func _get_pair_separation(subject: Node3D, other: Node3D, minimum_distance: float) -> Vector3:
	if _separation_pair_checks_remaining == 0:
		return Vector3.ZERO
	if _separation_pair_checks_remaining > 0:
		_separation_pair_checks_remaining -= 1
	_combat_perf_separation_pair_checks += 1
	_combat_perf_separation_pair_check_window += 1
	var away := subject.global_position - other.global_position
	away.y = 0.0
	var minimum_distance_squared := minimum_distance * minimum_distance
	var distance_squared := away.length_squared()
	if distance_squared >= minimum_distance_squared:
		return Vector3.ZERO
	if distance_squared <= 0.000001:
		var angle := TAU * float(absi(hash("%s:%s" % [String(subject.name), String(other.name)])) % 1000) / 1000.0
		away = Vector3(cos(angle), 0.0, sin(angle))
		distance_squared = 0.000001
	var distance := sqrt(distance_squared)
	var strength := clampf((minimum_distance - distance) / maxf(minimum_distance, 0.001), 0.0, 1.0)
	return away / distance * strength * maxf(combat_separation_strength, 0.0) * 0.18


func _move_combat_soldier_toward(soldier: Node3D, defender: Node3D, desired_global_position: Vector3, delta: float) -> void:
	var current := soldier.global_position
	var desired := desired_global_position
	desired.y = current.y
	var to_desired := desired - current
	to_desired.y = 0.0
	var distance := to_desired.length()
	if soldier.has_method("set_independent_path_target") or soldier.has_method("set_independent_move_target"):
		var arrival := clampf(maxf(combat_socket_arrival_radius, 0.05) * 0.55, 0.18, maxf(combat_socket_arrival_radius, 0.05))
		var speed := _get_combat_slot_follow_speed_for_frame()
		var key := soldier.get_instance_id()
		var target_id := defender.get_instance_id()
		var cached_variant: Variant = _combat_soldier_move_targets.get(key)
		var cached := cached_variant as Dictionary if cached_variant is Dictionary else {}
		var should_write := true
		if cached.has("target") and int(cached.get("target_id", 0)) == target_id:
			var cached_target: Vector3 = cached.get("target", desired)
			var delta_to_cached := cached_target - desired
			delta_to_cached.y = 0.0
			var epsilon := maxf(arrival * 0.45, 0.12)
			var has_motion := soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion"))
			var cached_unreachable := cached.has("reachable") and not bool(cached.get("reachable", true))
			should_write = (
				delta_to_cached.length_squared() > epsilon * epsilon
				or absf(float(cached.get("speed", speed)) - speed) > 0.02
				or absf(float(cached.get("arrival", arrival)) - arrival) > 0.01
				or (not has_motion and not cached_unreachable and distance > arrival)
			)
		if should_write:
			var command_result := _command_soldier_path_target(soldier, desired, speed, arrival)
			var reachable := bool(command_result.get("reachable", false))
			_combat_soldier_move_targets[key] = {
				"target": desired,
				"resolved_destination": command_result.get("resolved_destination", desired),
				"speed": speed,
				"arrival": arrival,
				"target_id": target_id,
				"reachable": reachable,
				"failure_reason": command_result.get("failure_reason", &""),
			}
			if reachable and soldier.has_method("set_combat_focus_target"):
				soldier.call("set_combat_focus_target", defender)
	elif distance > 0.001:
		var max_step := _get_combat_slot_follow_speed_for_frame() * minf(maxf(delta, 0.0), 0.05)
		var next_position := current + to_desired / distance * minf(max_step, distance)
		next_position.y = current.y
		soldier.global_position = next_position
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", distance > 0.08, _get_combat_slot_follow_speed_for_frame())
	_face_soldier_toward(soldier, defender, delta)


func _get_combat_slot_follow_speed_for_frame() -> float:
	var physics_delta := maxf(get_physics_process_delta_time(), 1.0 / 60.0)
	var max_visible_step := maxf(combat_socket_arrival_radius, 0.05) * 0.75
	return minf(maxf(combat_slot_follow_speed, 0.1), max_visible_step / physics_delta)


func _update_combat_perf_rate_window(delta: float) -> void:
	if not troop_perf_monitoring_enabled:
		return
	_combat_perf_rate_window_seconds += maxf(delta, 0.0)
	if _combat_perf_rate_window_seconds < 1.0:
		return
	var divisor := maxf(_combat_perf_rate_window_seconds, 0.001)
	_combat_perf_target_scans_per_second = int(round(float(_combat_perf_target_candidate_scan_window) / divisor))
	_combat_perf_pair_checks_per_second = int(round(float(_combat_perf_separation_pair_check_window) / divisor))
	_combat_perf_steering_updates_per_second = int(round(float(_combat_perf_steering_update_window) / divisor))
	_combat_perf_target_candidate_scan_window = 0
	_combat_perf_separation_pair_check_window = 0
	_combat_perf_steering_update_window = 0
	_combat_perf_rate_window_seconds = 0.0


func _is_combat_pair_actively_fighting(attacker: Node3D, defender: Node3D) -> bool:
	return _get_combat_relation_status_for_pair(attacker, defender) == COMBAT_RELATION_FIGHTING


func _should_hold_soldier_combat_animation(attacker: Node3D, defender: Node3D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	if not _is_combat_pair_in_break_range(attacker, defender):
		return false
	if not attacker.has_method("get_state"):
		return false
	var state := StringName(attacker.call("get_state"))
	return state == &"standing_fighting" or state == &"fighting"


func _is_combat_pair_in_fight_range(attacker: Node3D, defender: Node3D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	return _horizontal_distance(attacker.global_position, defender.global_position) <= _get_combat_pair_fight_range_m()


func _is_combat_pair_in_break_range(attacker: Node3D, defender: Node3D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return false
	return _horizontal_distance(attacker.global_position, defender.global_position) <= _get_combat_pair_break_range_m()


func _get_combat_pair_fight_range_m() -> float:
	return maxf(combat_spear_range_m, 0.2)


func _get_combat_pair_break_range_m() -> float:
	var fight_range := _get_combat_pair_fight_range_m()
	var slack := maxf(maxf(combat_socket_arrival_radius, 0.05), 0.35)
	return maxf(fight_range + slack, fight_range * 1.12)


func _is_combat_soldier_locked_to(soldier: Node3D, defender: Node3D) -> bool:
	var key := soldier.get_instance_id()
	if not _combat_soldier_lock_positions.has(key):
		return false
	var target_variant: Variant = _combat_soldier_targets.get(key)
	var target := _as_valid_node3d(target_variant)
	return target != null and target == defender


func _lock_combat_soldier(soldier: Node3D, defender: Node3D) -> void:
	var key := soldier.get_instance_id()
	if not _combat_soldier_lock_positions.has(key):
		_combat_soldier_lock_positions[key] = soldier.global_position
		_combat_soldier_shuffle_offsets[key] = Vector3.ZERO
		_combat_soldier_shuffle_timers[key] = 0.0
	_set_combat_relation_status(soldier, defender, _get_combat_relation_status_for_pair(soldier, defender))
	if soldier.has_method("clear_independent_motion"):
		soldier.call("clear_independent_motion")
	_combat_soldier_move_targets.erase(key)
	_face_soldier_toward(soldier, defender, 1.0)


func _unlock_combat_soldier(soldier: Node3D) -> void:
	var key := soldier.get_instance_id()
	_combat_soldier_lock_positions.erase(key)
	_combat_soldier_shuffle_offsets.erase(key)
	_combat_soldier_shuffle_timers.erase(key)
	var target_variant: Variant = _combat_soldier_targets.get(key)
	var target := _as_valid_node3d(target_variant)
	if target:
		_set_combat_relation_status(soldier, target, COMBAT_RELATION_COMING)


func _update_locked_combat_shuffle(soldier: Node3D, defender: Node3D, delta: float) -> void:
	var key := soldier.get_instance_id()
	if not _combat_soldier_lock_positions.has(key):
		_lock_combat_soldier(soldier, defender)
	var lock_position: Vector3 = _combat_soldier_lock_positions.get(key, soldier.global_position)
	var timer := float(_combat_soldier_shuffle_timers.get(key, 0.0)) - delta
	if timer <= 0.0:
		timer = maxf(combat_attack_shuffle_interval, 0.05) * _rng.randf_range(0.75, 1.25)
		_combat_soldier_shuffle_offsets[key] = _make_combat_shuffle_offset()
	_combat_soldier_shuffle_timers[key] = timer

	var offset: Vector3 = _combat_soldier_shuffle_offsets.get(key, Vector3.ZERO)
	var desired := lock_position + offset
	desired.y = soldier.global_position.y
	var to_desired := desired - soldier.global_position
	to_desired.y = 0.0
	var distance := to_desired.length()
	if distance > 0.001:
		var max_step := maxf(combat_attack_shuffle_speed, 0.01) * minf(maxf(delta, 0.0), 0.05)
		soldier.global_position += to_desired / distance * minf(max_step, distance)

	var from_lock := soldier.global_position - lock_position
	from_lock.y = 0.0
	var radius := maxf(combat_attack_shuffle_radius, 0.0)
	var from_lock_distance := from_lock.length()
	if radius > 0.0 and from_lock_distance > radius:
		var correction := from_lock.normalized() * (radius - from_lock_distance)
		var max_correction := maxf(combat_attack_shuffle_speed, 0.01) * minf(maxf(delta, 0.0), 0.05)
		if correction.length() > max_correction:
			correction = correction.normalized() * max_correction
		soldier.global_position += correction
		soldier.global_position.y = desired.y
	elif radius <= 0.0 and from_lock_distance > 0.001:
		var correction_to_lock := -from_lock
		var max_lock_correction := maxf(combat_attack_shuffle_speed, 0.01) * minf(maxf(delta, 0.0), 0.05)
		if correction_to_lock.length() > max_lock_correction:
			correction_to_lock = correction_to_lock.normalized() * max_lock_correction
		soldier.global_position += correction_to_lock

	if soldier.has_method("set_formation_walking"):
		soldier.call("set_formation_walking", false, maxf(combat_attack_shuffle_speed, 0.01))
	_face_soldier_toward(soldier, defender, delta)


func _make_combat_shuffle_offset() -> Vector3:
	var radius := maxf(combat_attack_shuffle_radius, 0.0)
	if radius <= 0.0:
		return Vector3.ZERO
	var angle := _rng.randf() * TAU
	var distance := sqrt(_rng.randf()) * radius
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _face_soldier_toward(soldier: Node3D, target: Node3D, delta: float) -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - soldier.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-to_target.x, -to_target.z)
	soldier.rotation.y = lerp_angle(soldier.rotation.y, target_yaw, clampf(delta * 10.0, 0.0, 1.0))


func _face_passive_defender_toward_attacker(defender: Node3D, attacker: Node3D, delta: float) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker):
		return
	if defender.has_method("is_formation_attacking") and bool(defender.call("is_formation_attacking")):
		return
	if defender.has_method("set_combat_focus_target"):
		defender.call("set_combat_focus_target", attacker)
	_face_soldier_toward(defender, attacker, delta)


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
		_combat_visual_thrust_count += 1
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


func _should_chase_active_enemy(enemy: Node, enemy_in_engagement_zone: bool) -> bool:
	if enemy_in_engagement_zone or not _is_valid_enemy(enemy):
		return false
	if _is_valid_enemy(_manual_attack_target) and _manual_attack_target == enemy:
		return true
	return _has_uncommanded_chase_authority()


func _has_uncommanded_chase_authority() -> bool:
	return get_troop_mode() == MODE_ATTACK


func _get_enemy_scan_range() -> float:
	var range := maxf(detection_range_m, 0.1)
	if _has_uncommanded_chase_authority():
		range = maxf(range, ai_chase_detection_range_m)
	return range


func _refresh_active_enemy() -> void:
	var engagement_enemy := _find_enemy_inside_engagement_zone()
	if engagement_enemy:
		_active_enemy = engagement_enemy
		return

	var scan_range := _get_enemy_scan_range()
	var active_enemy_spatial := _as_valid_node3d(_active_enemy)
	if (
		active_enemy_spatial != null
		and _is_valid_enemy(active_enemy_spatial)
		and (
			global_position.distance_to(active_enemy_spatial.global_position) <= scan_range
			or _is_enemy_inside_engagement_zone(active_enemy_spatial)
		)
	):
		return

	var best_enemy: Node
	var best_distance_squared := INF
	var tree := get_tree()
	if not tree:
		return
	for node: Node in tree.get_nodes_in_group(&"troops"):
		var spatial := _as_valid_node3d(node)
		if not spatial or spatial == self or spatial.is_queued_for_deletion():
			continue
		if not _is_valid_enemy(spatial):
			continue
		var distance_squared := global_position.distance_squared_to(spatial.global_position)
		if distance_squared > scan_range * scan_range and not _is_enemy_inside_engagement_zone(spatial):
			continue
		if distance_squared < best_distance_squared:
			best_enemy = spatial
			best_distance_squared = distance_squared
	_active_enemy = best_enemy
	if not _active_enemy:
		_last_target_instance_id = 0


func _find_enemy_inside_engagement_zone() -> Node:
	var tree := get_tree()
	if not tree:
		return null
	var best_enemy: Node
	var best_distance_squared := INF
	for node: Node in tree.get_nodes_in_group(&"troops"):
		var spatial := _as_valid_node3d(node)
		if not spatial or spatial == self or spatial.is_queued_for_deletion():
			continue
		if not _is_valid_enemy(spatial) or not _is_enemy_inside_engagement_zone(spatial):
			continue
		var distance_squared := global_position.distance_squared_to(spatial.global_position)
		if distance_squared < best_distance_squared:
			best_enemy = spatial
			best_distance_squared = distance_squared
	return best_enemy


func _is_valid_enemy(enemy: Variant) -> bool:
	var enemy_node := _as_valid_node(enemy)
	if not enemy_node or enemy_node == self:
		return false
	if not (enemy_node is Node3D):
		return false
	if enemy_node.is_queued_for_deletion():
		return false
	if enemy_node.has_method("is_defeated") and bool(enemy_node.call("is_defeated")):
		return false
	var enemy_team := StringName(enemy_node.get("team_id"))
	if enemy_team == TEAM_DESERTER:
		return false
	if enemy_team == team_id:
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
	if team_id == TEAM_DESERTER:
		return
	if desertion_chance_per_second <= 0.0:
		return
	var soldiers := _get_active_soldiers()
	var leaving: Array[Node] = []
	for soldier: Node in soldiers:
		var morale_value := _get_soldier_stat(soldier, &"morale")
		if morale_value >= desertion_morale_threshold:
			continue
		var morale_pressure := clampf((desertion_morale_threshold - morale_value) / maxf(desertion_morale_threshold, 1.0), 0.0, 1.0)
		var probability := desertion_chance_per_second * morale_pressure * delta
		if _rng.randf() < probability:
			leaving.append(soldier)
	if not leaving.is_empty():
		_desert_soldiers(leaving)


func _update_desertions(delta: float) -> void:
	if team_id == TEAM_DESERTER or desertion_chance_per_second <= 0.0:
		return
	_desertion_check_remaining -= maxf(delta, 0.0)
	if _desertion_check_remaining > 0.0:
		return
	var interval := maxf(desertion_check_interval_seconds, 0.05)
	_desertion_check_remaining = interval
	_try_desertions(interval)


func _try_survivor_rout() -> void:
	if team_id == TEAM_DESERTER:
		return
	if not survivor_rout_enabled:
		return
	if not _is_valid_enemy(_active_enemy):
		return
	var threshold := maxi(survivor_rout_active_threshold, 1)
	if soldier_count <= threshold:
		return
	var active_count := get_active_soldier_count()
	if active_count <= 0:
		return
	if active_count > threshold:
		return
	var min_remaining := clampi(survivor_rout_min_active_soldiers, 0, threshold)
	if active_count <= min_remaining:
		if _survivor_rout_triggered or active_count <= 1:
			var final_soldiers := _select_survivor_rout_soldiers(active_count)
			if not final_soldiers.is_empty():
				_desert_soldiers(final_soldiers, maxf(survivor_rout_speed_multiplier, 1.0))
				_survivor_rout_triggered = true
		return
	if _survivor_rout_triggered:
		return

	var max_rout_count := active_count - min_remaining
	var desired_count := clampi(ceili(float(active_count) * clampf(survivor_rout_fraction, 0.05, 1.0)), 1, max_rout_count)
	var soldiers := _select_survivor_rout_soldiers(desired_count)
	if not soldiers.is_empty():
		_desert_soldiers(soldiers, maxf(survivor_rout_speed_multiplier, 1.0))
	_survivor_rout_triggered = not soldiers.is_empty()


func _select_survivor_rout_soldiers(count: int) -> Array[Node]:
	var selected: Array[Node] = []
	if count <= 0:
		return selected
	var soldiers := _get_active_soldiers()
	for include_flag_holders: bool in [false, true]:
		for index: int in range(soldiers.size() - 1, -1, -1):
			if selected.size() >= count:
				return selected
			var soldier := soldiers[index]
			if not (soldier is Node3D) or selected.has(soldier):
				continue
			if _is_flag_holder(soldier as Node3D) and not include_flag_holders:
				continue
			selected.append(soldier)
	return selected


func _desert_soldier(soldier: Node, speed_multiplier: float = 1.0) -> void:
	if not (soldier is Node3D):
		return
	_desert_soldiers([soldier], speed_multiplier)


func _desert_soldiers(soldiers: Array, speed_multiplier: float = 1.0) -> void:
	if not _soldier_container or soldiers.is_empty():
		return
	var valid_soldiers: Array[Node3D] = []
	for soldier: Variant in soldiers:
		var soldier_spatial := _as_valid_node3d(soldier)
		if soldier_spatial:
			valid_soldiers.append(soldier_spatial)
	if valid_soldiers.is_empty():
		return

	_remove_departed_soldiers(valid_soldiers)


func _get_or_create_deserter_troop(initial_soldier_count: int) -> Troop:
	if (
		is_instance_valid(_deserter_troop)
		and not _deserter_troop.is_queued_for_deletion()
		and _deserter_troop.get_parent()
	):
		return _deserter_troop
	var deserter_troop := Troop.new()
	_copy_configuration_to_child_troop(deserter_troop)
	deserter_troop.troop_id = StringName("%s_deserters_%d" % [String(troop_id), Time.get_ticks_msec()])
	deserter_troop.display_name = "Deserters"
	deserter_troop.team_id = TEAM_DESERTER
	deserter_troop.controllable = false
	deserter_troop.hand_flags_enabled = false
	deserter_troop.is_mission_troop = false
	deserter_troop.troop_mode = String(MODE_DEFENSIVE)
	deserter_troop.soldier_count = maxi(initial_soldier_count, 2)
	deserter_troop._deserter_origin_team_id = team_id
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(deserter_troop)
	else:
		add_child(deserter_troop)
	deserter_troop.owner = null
	deserter_troop.top_level = true
	deserter_troop.global_position = _get_deserter_spawn_position()
	deserter_troop.add_to_group(&"deserter_troops")
	deserter_troop._clear_children(deserter_troop._soldier_container)
	_deserter_troop = deserter_troop
	return deserter_troop


func _snap_deserter_soldiers_to_formation() -> void:
	if team_id != TEAM_DESERTER:
		return
	for soldier_node: Node in _get_formation_soldiers():
		if not (soldier_node is Node3D):
			continue
		var soldier := soldier_node as Node3D
		var slot: Vector3 = soldier.get_meta(&"troop_formation_slot", Vector3.ZERO)
		soldier.global_position = _snap_world_point(_formation_slot_to_world(slot))
		soldier.rotation.y = rotation.y
		if soldier.has_method("clear_independent_motion"):
			soldier.call("clear_independent_motion")
		if soldier.has_method("set_formation_walking"):
			soldier.call("set_formation_walking", false, _get_soldier_path_speed(soldier))


func _update_combat_soldier_animation(delta: float = 0.0) -> void:
	var fighting := _state == STATE_FIGHTING and _is_valid_enemy(_active_enemy)
	if fighting:
		for key: Variant in _combat_touched_soldiers.keys():
			var soldier := _get_node_from_instance_id_key(key)
			if soldier and not _is_soldier_active(soldier):
				_clear_soldier_combat_visual(soldier)
				_forget_combat_soldier_key(key, true)
		_update_assigned_combat_visuals(delta)
		_step_combat_soldier_visual_logic(delta)
		return
	_combat_visual_stepped_soldiers.clear()
	for key: Variant in _combat_touched_soldiers.keys():
		var soldier := _get_node_from_instance_id_key(key)
		if soldier:
			_clear_soldier_combat_visual(soldier)
	_combat_touched_soldiers.clear()
	if _combat_animation_drain_soldiers.is_empty():
		_combat_render_dirty_soldiers.clear()


func _update_assigned_combat_visuals(delta: float) -> void:
	if _combat_soldier_targets.is_empty():
		_combat_visual_stance_cursor = 0
		return
	var keys := _combat_soldier_targets.keys()
	var key_count := keys.size()
	if key_count <= 0:
		_combat_visual_stance_cursor = 0
		return
	var update_limit := mini(maxi(combat_visual_stance_updates_per_tick, 1), key_count)
	var start := clampi(_combat_visual_stance_cursor, 0, maxi(key_count - 1, 0))
	for offset_index: int in range(update_limit):
		var key: Variant = keys[(start + offset_index) % key_count]
		var soldier := _as_valid_node3d(_get_node_from_instance_id_key(key))
		var defender_variant: Variant = _combat_soldier_targets.get(key)
		var defender := _as_valid_node3d(defender_variant)
		if not defender:
			_forget_combat_soldier_key(key, true)
			continue
		if not soldier or not _is_soldier_active(soldier) or not defender.is_inside_tree():
			_forget_combat_soldier_key(key, true)
			continue
		var rotation_before := soldier.rotation.y
		_face_soldier_toward(soldier, defender, 1.0)
		var changed_for_render := absf(wrapf(soldier.rotation.y - rotation_before, -PI, PI)) > 0.002
		var moving_to_socket := soldier.has_method("has_independent_motion") and bool(soldier.call("has_independent_motion"))
		var visual_in_range := _is_combat_pair_actively_fighting(soldier, defender)
		if moving_to_socket and not visual_in_range:
			if soldier.has_method("is_formation_attacking") and bool(soldier.call("is_formation_attacking")):
				if _should_hold_soldier_combat_animation(soldier, defender):
					_set_soldier_live_animation_source(soldier, true)
				else:
					changed_for_render = true
					if soldier.has_method("set_independent_combat"):
						soldier.call("set_independent_combat", false)
					elif soldier.has_method("set_formation_attacking"):
						soldier.call("set_formation_attacking", false)
			if soldier.has_method("set_combat_focus_target"):
				soldier.call("set_combat_focus_target", defender)
		if visual_in_range and soldier.has_method("set_independent_combat"):
			if soldier.has_method("is_formation_attacking") and not bool(soldier.call("is_formation_attacking")):
				changed_for_render = true
			_set_soldier_live_animation_source(soldier, true)
			soldier.call("set_independent_combat", true, defender, true)
		elif visual_in_range and soldier.has_method("set_formation_attacking"):
			if soldier.has_method("is_formation_attacking") and not bool(soldier.call("is_formation_attacking")):
				changed_for_render = true
			_set_soldier_live_animation_source(soldier, true)
			soldier.call("set_formation_attacking", true, defender)
		elif soldier.has_method("set_combat_focus_target"):
			soldier.call("set_combat_focus_target", defender)
			if not _soldier_should_use_live_animation_source(soldier):
				_set_soldier_live_animation_source(soldier, false)
		if visual_in_range:
			changed_for_render = _maybe_trigger_visual_soldier_thrust(soldier, defender, key, delta) or changed_for_render
		if changed_for_render:
			_mark_soldier_render_dirty(soldier)
		_combat_visual_stance_update_count += 1
	_combat_visual_stance_cursor = (start + update_limit) % key_count


func _maybe_trigger_visual_soldier_thrust(soldier: Node, defender: Node3D, key: Variant, delta: float) -> bool:
	if not soldier.has_method("trigger_spear_thrust"):
		return false
	if soldier.has_method("is_spear_thrust_active") and bool(soldier.call("is_spear_thrust_active")):
		return false
	var remaining := float(_combat_visual_thrust_timers.get(key, _get_initial_visual_thrust_delay(soldier)))
	remaining -= maxf(delta, 0.0)
	if remaining > 0.0:
		_combat_visual_thrust_timers[key] = remaining
		return false
	_set_soldier_live_animation_source(soldier, true)
	soldier.call("trigger_spear_thrust", defender, maxf(combat_visual_thrust_duration, 0.05))
	_combat_visual_thrust_timers[key] = _get_visual_thrust_interval(soldier)
	_combat_visual_thrust_count += 1
	return true


func _get_initial_visual_thrust_delay(soldier: Node) -> float:
	var seed := float(absi(hash("visual:%s:%s" % [String(troop_id), String(soldier.name)])) % 1000) / 1000.0
	return seed * minf(maxf(combat_visual_thrust_interval, 0.2) * 0.35, 0.45)


func _get_visual_thrust_interval(soldier: Node) -> float:
	var seed := float(absi(hash("visual-interval:%s:%s" % [String(troop_id), String(soldier.name)])) % 1000) / 1000.0
	return maxf(combat_visual_thrust_interval, 0.2) * lerpf(0.78, 1.26, seed)


func _mark_soldier_combat_touched(soldier: Node) -> void:
	if _is_live_combat_node(soldier):
		_combat_touched_soldiers[soldier.get_instance_id()] = true
		_mark_soldier_render_dirty(soldier)


func _mark_soldier_combat_animation_drain(soldier: Node) -> void:
	if not _is_live_combat_node(soldier):
		return
	var key := soldier.get_instance_id()
	_combat_animation_drain_soldiers[key] = true
	if soldier.has_method("set_logic_sleeping"):
		soldier.call("set_logic_sleeping", false)
	_set_soldier_live_animation_source(soldier, true)


func _mark_soldier_render_dirty(soldier: Node) -> void:
	if _is_live_combat_node(soldier):
		_combat_render_dirty_soldiers[soldier.get_instance_id()] = true


func _set_soldier_live_animation_source(soldier: Node, enabled: bool) -> void:
	if not (soldier is Node3D) or not is_instance_valid(soldier):
		return
	var soldier_spatial := soldier as Node3D
	if enabled:
		soldier_spatial.set_meta(LIVE_ANIMATION_SOURCE_META, true)
		if _soldier_batch_renderer and _soldier_batch_renderer.has_method("restore_sources_for_soldier"):
			_soldier_batch_renderer.call("restore_sources_for_soldier", soldier_spatial)
	else:
		if soldier_spatial.has_meta(LIVE_ANIMATION_SOURCE_META):
			soldier_spatial.remove_meta(LIVE_ANIMATION_SOURCE_META)
		if soldier_render_batching_enabled and _soldier_batch_renderer and _soldier_batch_renderer.has_method("hide_sources_for_soldier"):
			_soldier_batch_renderer.call("hide_sources_for_soldier", soldier_spatial)
	_soldier_render_sync_remaining = 0.0
	_soldier_render_sync_frame_cursor = 0
	_mark_soldier_render_dirty(soldier_spatial)


func _update_soldier_live_animation_source_after_step(soldier: Node) -> void:
	if not is_instance_valid(soldier):
		return
	var key := soldier.get_instance_id()
	if _soldier_should_use_live_animation_source(soldier):
		if not soldier.has_meta(LIVE_ANIMATION_SOURCE_META):
			_set_soldier_live_animation_source(soldier, true)
		return
	_combat_animation_drain_soldiers.erase(key)
	if soldier.has_meta(LIVE_ANIMATION_SOURCE_META):
		_set_soldier_live_animation_source(soldier, false)


func _soldier_should_use_live_animation_source(soldier: Node) -> bool:
	if _should_wait_for_soldier_departure_pose(soldier):
		return true
	if not soldier.has_method("get_state"):
		return false
	var state := StringName(soldier.call("get_state"))
	return state == &"standing_fighting" or state == &"fighting"


func _is_live_combat_node(value: Variant) -> bool:
	var node := _as_valid_node(value)
	return node != null and not node.is_queued_for_deletion() and node.is_inside_tree()


func _get_node_from_instance_id_key(key: Variant) -> Node:
	var object_id := int(key)
	if not is_instance_id_valid(object_id):
		return null
	var object := instance_from_id(object_id)
	if _is_live_combat_node(object):
		return object as Node
	return null


func _get_combat_touched_soldier_nodes() -> Array[Node]:
	var soldiers: Array[Node] = []
	for key: Variant in _combat_touched_soldiers.keys():
		var soldier := _get_node_from_instance_id_key(key)
		if soldier:
			soldiers.append(soldier)
		else:
			_forget_combat_soldier_key(key, true)
	return soldiers


func _forget_combat_soldier_key(key: Variant, forget_offset: bool = false) -> void:
	var soldier := _get_node_from_instance_id_key(key)
	if soldier:
		_clear_soldier_combat_visual(soldier)
	_release_combat_assignment(key, forget_offset)
	_combat_touched_soldiers.erase(key)
	if not _combat_animation_drain_soldiers.has(key):
		_combat_render_dirty_soldiers.erase(key)


func _clear_soldier_combat_visual(soldier: Node) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("set_independent_combat"):
		soldier.call("set_independent_combat", false)
	elif soldier.has_method("set_formation_attacking"):
		soldier.call("set_formation_attacking", false)
	if _soldier_should_use_live_animation_source(soldier):
		_mark_soldier_combat_animation_drain(soldier)
	else:
		_combat_animation_drain_soldiers.erase(soldier.get_instance_id())
		_set_soldier_live_animation_source(soldier, false)


func _update_soldier_activity_modes() -> void:
	for soldier: Node in _get_formation_soldiers():
		if _is_soldier_active(soldier) and soldier.has_method("set_activity_mode"):
			soldier.call("set_activity_mode", _get_soldier_activity_mode())


func _get_soldier_activity_mode() -> StringName:
	if _state == STATE_MOVING or _state == STATE_FIGHTING:
		return &"none"
	match get_troop_mode():
		MODE_REST:
			return &"rest"
		MODE_TRAINING:
			return &"training"
		_:
			return &"idle"


func _clear_independent_combat(regroup: bool) -> void:
	_separation_pair_checks_remaining = -1
	_combat_soldier_targets.clear()
	_combat_soldier_target_statuses.clear()
	_combat_target_attackers.clear()
	_combat_soldier_lock_positions.clear()
	_combat_soldier_shuffle_offsets.clear()
	_combat_soldier_shuffle_timers.clear()
	_combat_soldier_attack_timers.clear()
	_combat_visual_thrust_timers.clear()
	_combat_soldier_steering_cache.clear()
	_combat_soldier_spacing_refresh_times.clear()
	_combat_soldier_socket_indices.clear()
	_combat_soldier_socket_positions.clear()
	_combat_soldier_socket_directions.clear()
	_combat_soldier_move_targets.clear()
	_combat_assignment_cursor = 0
	_combat_update_cursor = 0
	_combat_visual_stance_cursor = 0
	_combat_visual_stepped_soldiers.clear()
	_combat_logic_accumulator = 0.0
	_combat_target_reassign_remaining = 0.0
	_combat_attacker_spatial_rebuild_remaining = 0.0
	_combat_attacker_spatial_cached_count = -1
	_combat_defender_spatial_rebuild_remaining = 0.0
	_combat_defender_spatial_cached_count = -1
	_combat_defender_spatial_cached_enemy_id = 0
	if regroup:
		_combat_soldier_offsets.clear()
		_combat_scatter_active = false
		_hold_scattered_positions_after_combat = true
	for key: Variant in _combat_touched_soldiers.keys():
		var soldier := _get_node_from_instance_id_key(key)
		if soldier:
			_clear_soldier_combat_visual(soldier)
			if regroup and soldier.has_method("clear_independent_motion"):
				soldier.call("clear_independent_motion")
	_combat_touched_soldiers.clear()
	if _combat_animation_drain_soldiers.is_empty():
		_combat_render_dirty_soldiers.clear()
	if regroup:
		_cleanup_deferred_dead_soldiers_after_combat()


func _update_food_supply(delta: float, active_count: int) -> void:
	var game_days := _get_game_days_for_delta(delta)
	var needed := float(active_count) * maxf(food_kg_per_soldier_per_day, 0.0) * game_days
	if needed <= 0.0:
		_food_shortage_ratio = 0.0
		_queue_starvation_update(0.0, game_days, delta)
		return

	var carried_consumed := minf(needed, maxf(carried_food_kg, 0.0))
	carried_food_kg = maxf(carried_food_kg - carried_consumed, 0.0)
	var remaining_needed := maxf(needed - carried_consumed, 0.0)
	var camp_consumed := _consume_food_from_nearby_camps(remaining_needed)
	var consumed := carried_consumed + camp_consumed
	_food_shortage_ratio = clampf((needed - consumed) / needed, 0.0, 1.0)
	_queue_starvation_update(_food_shortage_ratio, game_days, delta)


func _queue_starvation_update(shortage_ratio: float, game_days: float, delta: float) -> void:
	var days := maxf(game_days, 0.0)
	if days <= 0.0:
		return
	_starvation_update_elapsed += maxf(delta, 0.0)
	_starvation_accumulated_game_days += days
	_starvation_weighted_shortage_days += clampf(shortage_ratio, 0.0, 1.0) * days
	if _starvation_update_elapsed < maxf(starvation_update_interval_seconds, 0.05):
		return

	var accumulated_days := _starvation_accumulated_game_days
	var average_shortage := (
		clampf(_starvation_weighted_shortage_days / accumulated_days, 0.0, 1.0)
		if accumulated_days > 0.0
		else 0.0
	)
	_starvation_update_elapsed = 0.0
	_starvation_accumulated_game_days = 0.0
	_starvation_weighted_shortage_days = 0.0
	_apply_starvation_to_soldiers(average_shortage, accumulated_days)


func _apply_starvation_to_soldiers(shortage_ratio: float, game_days: float) -> void:
	var ratio := clampf(shortage_ratio, 0.0, 1.0)
	if _should_queue_stat_effects():
		_queue_starvation_stat_effect(ratio, maxf(game_days, 0.0))
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("apply_starvation"):
			soldier.call(
				"apply_starvation",
				ratio,
				maxf(game_days, 0.0),
				starvation_endurance_loss_per_day,
				starvation_health_loss_per_day,
				starvation_death_start_days,
				starvation_death_base_chance_per_day,
				starvation_death_extra_chance_per_day,
				starvation_death_max_chance_per_day,
				_rng.randf()
			)
			changed = true
		elif ratio > 0.0:
			if soldier.has_method("reduce_endurance"):
				soldier.call("reduce_endurance", starvation_endurance_loss_per_day * ratio * maxf(game_days, 0.0))
				changed = true
			if soldier.has_method("apply_damage"):
				soldier.call("apply_damage", starvation_health_loss_per_day * ratio * maxf(game_days, 0.0), &"starvation")
				changed = true
	if changed:
		_mark_combat_stats_dirty()


func _queue_starvation_stat_effect(shortage_ratio: float, game_days: float) -> void:
	var days := maxf(game_days, 0.0)
	if days <= 0.0:
		return
	_stat_accumulated_starvation_days += days
	_stat_accumulated_starvation_weighted_shortage_days += clampf(shortage_ratio, 0.0, 1.0) * days
	_mark_stat_effect_pending("starvation")


func _mark_stat_effect_pending(label: String) -> void:
	if not _stat_effect_has_pending:
		_stat_update_remaining = minf(_stat_update_remaining, _get_stat_update_phase_seconds())
	_stat_effect_has_pending = true
	if _stat_last_effect_label.is_empty():
		_stat_last_effect_label = label
	elif not _stat_last_effect_label.contains(label):
		_stat_last_effect_label = "%s,%s" % [_stat_last_effect_label, label]


func _queue_endurance_stat_effect(amount: float) -> void:
	if is_zero_approx(amount):
		return
	_stat_accumulated_endurance_delta += amount
	_mark_stat_effect_pending("endurance")


func _queue_morale_stat_effect(amount: float) -> void:
	if is_zero_approx(amount):
		return
	_stat_accumulated_morale_delta += amount
	_mark_stat_effect_pending("morale")


func _queue_training_stat_effect(
	strength_amount: float,
	damage_amount: float,
	morale_amount: float,
	endurance_max_amount: float
) -> void:
	if (
		is_zero_approx(strength_amount)
		and is_zero_approx(damage_amount)
		and is_zero_approx(morale_amount)
		and is_zero_approx(endurance_max_amount)
	):
		return
	_stat_accumulated_training_strength += strength_amount
	_stat_accumulated_training_damage += damage_amount
	_stat_accumulated_training_morale += morale_amount
	_stat_accumulated_training_max_endurance += endurance_max_amount
	_mark_stat_effect_pending("training")


func _queue_fight_growth_stat_effect(damage_amount: float, endurance_max_amount: float) -> void:
	if is_zero_approx(damage_amount) and is_zero_approx(endurance_max_amount):
		return
	_stat_accumulated_fight_damage += damage_amount
	_stat_accumulated_fight_max_endurance += endurance_max_amount
	_mark_stat_effect_pending("fight_growth")


func _get_game_days_for_delta(delta: float) -> float:
	var game_minutes_per_second := 12.0
	if _time_system and _object_has_property(_time_system, &"game_minutes_per_real_second"):
		game_minutes_per_second = maxf(float(_time_system.get("game_minutes_per_real_second")), 0.0)
	return delta * game_minutes_per_second / 1440.0


func _train_soldiers(delta: float) -> void:
	if _should_queue_stat_effects():
		_queue_training_stat_effect(
			training_strength_gain_per_second * delta,
			training_damage_gain_per_second * delta,
			training_morale_gain_per_second * delta,
			training_max_endurance_gain_per_second * _get_endurance_rate_scale() * delta
		)
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("train_stats_with_caps"):
			soldier.call(
				"train_stats_with_caps",
				training_strength_gain_per_second * delta,
				training_damage_gain_per_second * delta,
				training_morale_gain_per_second * delta,
				training_max_endurance_gain_per_second * _get_endurance_rate_scale() * delta,
				training_strength_soft_cap,
				training_damage_soft_cap,
				training_morale_soft_cap,
				training_endurance_soft_cap
			)
			changed = true
		elif soldier.has_method("train_stats"):
			soldier.call(
				"train_stats",
				training_strength_gain_per_second * delta,
				training_damage_gain_per_second * delta,
				training_morale_gain_per_second * delta,
				training_max_endurance_gain_per_second * _get_endurance_rate_scale() * delta
			)
			changed = true
	if changed:
		_mark_combat_stats_dirty()


func _grow_soldiers_from_fighting(delta: float) -> void:
	var multiplier := maxf(fighting_growth_multiplier, 0.0)
	if multiplier <= 0.0:
		return
	if _should_queue_stat_effects():
		_queue_fight_growth_stat_effect(
			training_damage_gain_per_second * multiplier * delta,
			training_max_endurance_gain_per_second * multiplier * _get_endurance_rate_scale() * delta
		)
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("apply_fight_growth"):
			soldier.call(
				"apply_fight_growth",
				training_damage_gain_per_second * multiplier * delta,
				training_max_endurance_gain_per_second * multiplier * _get_endurance_rate_scale() * delta,
				training_damage_soft_cap,
				training_endurance_soft_cap
			)
			changed = true
	if changed:
		_mark_combat_stats_dirty()


func _restore_soldier_endurance(amount: float) -> void:
	if amount <= 0.0:
		return
	var scaled_amount := amount * _get_endurance_rate_scale()
	if scaled_amount <= 0.0 or _get_average_endurance_ratio() >= 0.999:
		return
	if _should_queue_stat_effects():
		_queue_endurance_stat_effect(scaled_amount)
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("restore_endurance"):
			soldier.call("restore_endurance", scaled_amount)
			changed = true
	if changed:
		_mark_combat_stats_dirty()


func _drain_soldier_endurance(amount: float) -> void:
	if amount <= 0.0:
		return
	var scaled_amount := amount * _get_endurance_rate_scale()
	if _should_queue_stat_effects():
		_queue_endurance_stat_effect(-scaled_amount)
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("reduce_endurance"):
			soldier.call("reduce_endurance", scaled_amount)
			changed = true
	if changed:
		_mark_combat_stats_dirty()


func _get_noncombat_endurance_recovery_rate() -> float:
	match get_troop_mode():
		MODE_REST:
			return rest_endurance_recovery_per_second
		_:
			return defensive_endurance_recovery_per_second


func _get_endurance_rate_scale() -> float:
	return clampf(endurance_rate_scale, 0.01, 1.0)


func _change_all_morale(amount: float) -> void:
	if is_zero_approx(amount):
		return
	if _should_queue_stat_effects():
		_queue_morale_stat_effect(amount)
		return
	var changed := false
	for soldier: Node in _get_active_soldiers():
		if soldier.has_method("change_morale"):
			soldier.call("change_morale", amount)
			changed = true
	if changed:
		_mark_combat_stats_dirty()


func _should_queue_stat_effects() -> bool:
	return get_active_soldier_count() >= maxi(stat_worker_min_soldiers, 1)


func _update_stat_jobs(delta: float) -> void:
	if _stat_effect_has_pending:
		_stat_update_remaining -= maxf(delta, 0.0)
	if _stat_effect_has_pending and not _stat_worker_in_flight and _stat_update_remaining <= 0.0:
		_start_stat_job()
		_stat_update_remaining = maxf(stat_update_interval_seconds, 0.02)
		_apply_pending_stat_results()


func _start_stat_job() -> void:
	var request := _build_stat_job_request()
	if request.is_empty():
		_clear_pending_stat_effects()
		return

	_stat_started_jobs += 1
	_stat_last_job_used_worker = bool(request.get("use_worker", false))
	if bool(request.get("use_worker", false)):
		_stat_worker = TroopStatWorkerScript.new()
		_stat_worker_task_id = WorkerThreadPool.add_task(Callable(_stat_worker, "run").bind(request))
		_stat_worker_in_flight = true
		return

	var started := Time.get_ticks_usec()
	var result: Dictionary = TroopStatWorkerScript.calculate(request)
	result["worker_usec"] = Time.get_ticks_usec() - started
	_accept_stat_job_result(result)


func _build_stat_job_request() -> Dictionary:
	var soldiers := _get_active_soldiers()
	if soldiers.is_empty():
		return {}

	var soldier_snapshots: Array[Dictionary] = []
	var soldier_map := {}
	for soldier: Node in soldiers:
		if not is_instance_valid(soldier) or not soldier.has_method("apply_stat_job_result"):
			continue
		var snapshot := _make_stat_soldier_snapshot(soldier)
		if snapshot.is_empty():
			continue
		var soldier_id := int(snapshot.get("id", 0))
		if soldier_id == 0:
			continue
		soldier_snapshots.append(snapshot)
		soldier_map[soldier_id] = soldier
	if soldier_snapshots.is_empty():
		return {}

	_stat_worker_job_id += 1
	_stat_worker_soldier_map[_stat_worker_job_id] = soldier_map
	var effect_label := _stat_last_effect_label
	var effects := _consume_stat_effects()
	return {
		"job_id": _stat_worker_job_id,
		"soldiers": soldier_snapshots,
		"soldier_count": soldier_snapshots.size(),
		"effects": effects,
		"effect_label": effect_label,
		"use_worker": stat_worker_enabled and soldier_snapshots.size() >= maxi(stat_worker_min_soldiers, 1),
	}


func _make_stat_soldier_snapshot(soldier: Node) -> Dictionary:
	if not is_instance_valid(soldier):
		return {}
	return {
		"id": soldier.get_instance_id(),
		"health": _get_soldier_stat(soldier, &"strength"),
		"max_strength": _get_soldier_stat(soldier, &"max_strength"),
		"damage": _get_soldier_stat(soldier, &"damage"),
		"morale": _get_soldier_stat(soldier, &"morale"),
		"endurance": _get_soldier_stat(soldier, &"endurance"),
		"max_endurance": _get_soldier_stat(soldier, &"max_endurance"),
		"starving_days": _get_soldier_stat(soldier, &"starving_days"),
		"death_roll": _rng.randf(),
	}


func _consume_stat_effects() -> Dictionary:
	var starvation_days := maxf(_stat_accumulated_starvation_days, 0.0)
	var starvation_ratio := (
		clampf(_stat_accumulated_starvation_weighted_shortage_days / starvation_days, 0.0, 1.0)
		if starvation_days > 0.0
		else 0.0
	)
	var effects := {
		"endurance_delta": _stat_accumulated_endurance_delta,
		"morale_delta": _stat_accumulated_morale_delta,
		"training_strength": _stat_accumulated_training_strength,
		"training_damage": _stat_accumulated_training_damage,
		"training_morale": _stat_accumulated_training_morale,
		"training_max_endurance": _stat_accumulated_training_max_endurance,
		"training_strength_soft_cap": training_strength_soft_cap,
		"training_damage_soft_cap": training_damage_soft_cap,
		"training_morale_soft_cap": training_morale_soft_cap,
		"training_endurance_soft_cap": training_endurance_soft_cap,
		"fight_damage": _stat_accumulated_fight_damage,
		"fight_max_endurance": _stat_accumulated_fight_max_endurance,
		"fight_damage_soft_cap": training_damage_soft_cap,
		"fight_endurance_soft_cap": training_endurance_soft_cap,
		"starvation_days": starvation_days,
		"starvation_ratio": starvation_ratio,
		"starvation_endurance_loss_per_day": starvation_endurance_loss_per_day,
		"starvation_health_loss_per_day": starvation_health_loss_per_day,
		"starvation_death_start_days": starvation_death_start_days,
		"starvation_death_base_chance_per_day": starvation_death_base_chance_per_day,
		"starvation_death_extra_chance_per_day": starvation_death_extra_chance_per_day,
		"starvation_death_max_chance_per_day": starvation_death_max_chance_per_day,
	}
	_clear_pending_stat_effects()
	return effects


func _clear_pending_stat_effects() -> void:
	_stat_effect_has_pending = false
	_stat_accumulated_endurance_delta = 0.0
	_stat_accumulated_morale_delta = 0.0
	_stat_accumulated_training_strength = 0.0
	_stat_accumulated_training_damage = 0.0
	_stat_accumulated_training_morale = 0.0
	_stat_accumulated_training_max_endurance = 0.0
	_stat_accumulated_fight_damage = 0.0
	_stat_accumulated_fight_max_endurance = 0.0
	_stat_accumulated_starvation_days = 0.0
	_stat_accumulated_starvation_weighted_shortage_days = 0.0
	_stat_last_effect_label = ""


func _poll_completed_stat_job() -> void:
	if not _stat_worker_in_flight or _stat_worker_task_id < 0:
		return
	if not WorkerThreadPool.is_task_completed(_stat_worker_task_id):
		return
	_stat_worker_completed_job_polls += 1
	WorkerThreadPool.wait_for_task_completion(_stat_worker_task_id)
	if _stat_worker:
		_accept_stat_job_result(_stat_worker.result)
	_stat_worker = null
	_stat_worker_task_id = -1
	_stat_worker_in_flight = false


func _accept_stat_job_result(result: Dictionary) -> void:
	var worker_usec := int(result.get("worker_usec", 0))
	_stat_last_worker_usec = worker_usec
	_stat_max_worker_usec = maxi(_stat_max_worker_usec, worker_usec)
	_stat_total_worker_usec += worker_usec
	_stat_completed_jobs += 1
	var job_id := int(result.get("job_id", 0))
	_stat_pending_apply_batches.append({
		"job_id": job_id,
		"results": result.get("results", []),
		"soldier_map": _stat_worker_soldier_map.get(job_id, {}),
		"index": 0,
		"effect_label": String(result.get("effect_label", "")),
	})
	_stat_worker_soldier_map.erase(job_id)


func _apply_pending_stat_results() -> void:
	if _stat_pending_apply_batches.is_empty():
		_stat_last_apply_count = 0
		return

	var started := Time.get_ticks_usec()
	var budget := maxi(stat_apply_budget_usec, 100)
	var max_count := maxi(stat_apply_max_soldiers_per_frame, 1)
	var applied := 0
	while not _stat_pending_apply_batches.is_empty():
		var batch: Dictionary = _stat_pending_apply_batches[0]
		var results: Array = batch.get("results", [])
		var index := int(batch.get("index", 0))
		var soldier_map: Dictionary = batch.get("soldier_map", {})
		while index < results.size():
			var result_variant: Variant = results[index]
			index += 1
			if result_variant is Dictionary:
				var result := result_variant as Dictionary
				var soldier_id := int(result.get("id", 0))
				var soldier: Variant = soldier_map.get(soldier_id)
				if is_instance_valid(soldier) and (soldier as Node).has_method("apply_stat_job_result"):
					(soldier as Node).call("apply_stat_job_result", result)
					applied += 1
					_mark_combat_stats_dirty()
				else:
					_stat_skipped_results += 1
			if applied >= max_count or Time.get_ticks_usec() - started >= budget:
				batch["index"] = index
				_stat_pending_apply_batches[0] = batch
				_record_stat_apply_metrics(Time.get_ticks_usec() - started, applied)
				return
		_stat_pending_apply_batches.pop_front()
		if Time.get_ticks_usec() - started >= budget:
			_record_stat_apply_metrics(Time.get_ticks_usec() - started, applied)
			return
	_record_stat_apply_metrics(Time.get_ticks_usec() - started, applied)


func _record_stat_apply_metrics(apply_usec: int, applied_count: int) -> void:
	_stat_last_apply_usec = apply_usec
	_stat_max_apply_usec = maxi(_stat_max_apply_usec, apply_usec)
	_stat_total_apply_usec += apply_usec
	_stat_apply_frames += 1
	_stat_last_apply_count = applied_count


func _wait_for_stat_worker() -> void:
	if not _stat_worker_in_flight or _stat_worker_task_id < 0:
		return
	_perf_stat_worker_wait_count += 1
	_stat_worker_blocking_waits += 1
	WorkerThreadPool.wait_for_task_completion(_stat_worker_task_id)
	_stat_worker = null
	_stat_worker_task_id = -1
	_stat_worker_in_flight = false


func _get_stat_update_phase_seconds() -> float:
	var interval := maxf(stat_update_interval_seconds, 0.02)
	var hash_value := absi(hash(String(troop_id)))
	return interval * (float(hash_value % 1000) / 1000.0)


func _get_combat_scan_phase_seconds() -> float:
	var interval := maxf(combat_scan_interval, 0.05)
	var hash_value := absi(hash("combat_scan:%s" % String(troop_id)))
	return interval * (float(hash_value % 1000) / 1000.0)


func get_stat_job_debug_summary() -> Dictionary:
	var avg_worker := float(_stat_total_worker_usec) / float(maxi(_stat_completed_jobs, 1))
	var avg_apply := float(_stat_total_apply_usec) / float(maxi(_stat_apply_frames, 1))
	var soldier_perf := get_soldier_perf_summary()
	var summary := {
		"troop_id": troop_id,
		"display_name": display_name,
		"stat_worker_enabled": stat_worker_enabled,
		"stat_worker_min_soldiers": stat_worker_min_soldiers,
		"active_soldier_count": get_active_soldier_count(),
		"job_in_flight": _stat_worker_in_flight,
		"pending_effects": _stat_effect_has_pending,
		"pending_apply_batches": _stat_pending_apply_batches.size(),
		"pending_apply_results": _get_pending_stat_apply_result_count(),
		"update_remaining": _stat_update_remaining,
		"last_worker_ms": float(_stat_last_worker_usec) / 1000.0,
		"avg_worker_ms": avg_worker / 1000.0,
		"max_worker_ms": float(_stat_max_worker_usec) / 1000.0,
		"last_apply_ms": float(_stat_last_apply_usec) / 1000.0,
		"avg_apply_ms": avg_apply / 1000.0,
		"max_apply_ms": float(_stat_max_apply_usec) / 1000.0,
		"last_apply_count": _stat_last_apply_count,
		"started_jobs": _stat_started_jobs,
		"completed_jobs": _stat_completed_jobs,
		"skipped_results": _stat_skipped_results,
		"last_effect_label": _stat_last_effect_label,
		"last_job_used_worker": _stat_last_job_used_worker,
		"soldier_perf_monitoring_enabled": soldier_perf_monitoring_enabled,
		"soldier_perf_sampled_count": int(soldier_perf.get("sampled_soldier_count", 0)),
		"soldier_perf_last_physics_ms": float(soldier_perf.get("last_physics_total_usec", 0)) / 1000.0,
		"soldier_perf_max_physics_ms": float(soldier_perf.get("max_physics_usec", 0)) / 1000.0,
		"soldier_perf_last_pose_ms": float(soldier_perf.get("last_pose_total_usec", 0)) / 1000.0,
		"soldier_perf_max_pose_ms": float(soldier_perf.get("max_pose_usec", 0)) / 1000.0,
		"combat_perf_active_cache_rebuilds": _combat_perf_active_cache_rebuilds,
		"combat_perf_target_candidate_scans": _combat_perf_target_candidate_scans,
		"combat_perf_separation_pair_checks": _combat_perf_separation_pair_checks,
		"combat_perf_steering_updates": _combat_perf_steering_updates,
		"formation_target_write_count": _formation_target_write_count,
		"formation_target_skip_count": _formation_target_skip_count,
		"moving_formation_pair_checks": _moving_formation_pair_checks,
		"spatial_grid_rebuilds": _spatial_grid_rebuilds,
		"combat_socket_clamp_count": _combat_socket_clamp_count,
		"logic_sleeping_soldier_count": _get_logic_sleeping_soldier_count(),
		"combat_perf_target_scans_per_second": _combat_perf_target_scans_per_second,
		"combat_perf_pair_checks_per_second": _combat_perf_pair_checks_per_second,
		"combat_perf_steering_updates_per_second": _combat_perf_steering_updates_per_second,
		"combat_max_target_load": _get_max_combat_target_load(),
		"combat_socket_assignment_count": _combat_soldier_socket_indices.size(),
		"perf_last_physics_ms": float(_perf_last_physics_usec) / 1000.0,
		"perf_max_physics_ms": float(_perf_max_physics_usec) / 1000.0,
		"perf_last_combat_tick_ms": float(_perf_last_combat_tick_usec) / 1000.0,
		"perf_max_combat_tick_ms": float(_perf_max_combat_tick_usec) / 1000.0,
		"perf_last_formation_separation_ms": float(_perf_last_formation_separation_usec) / 1000.0,
		"perf_max_formation_separation_ms": float(_perf_max_formation_separation_usec) / 1000.0,
		"perf_last_combat_summary_ms": float(_perf_last_combat_summary_usec) / 1000.0,
		"perf_max_combat_summary_ms": float(_perf_max_combat_summary_usec) / 1000.0,
		"perf_stat_worker_wait_count": _perf_stat_worker_wait_count,
		"stat_worker_completed_job_polls": _stat_worker_completed_job_polls,
		"stat_worker_blocking_waits": _stat_worker_blocking_waits,
	}
	summary.merge(_get_soldier_render_batch_summary(), true)
	return summary


func get_soldier_perf_summary() -> Dictionary:
	var sampled_count := 0
	var last_physics_total := 0
	var last_pose_total := 0
	var max_last_physics := 0
	var max_last_pose := 0
	var max_physics := 0
	var max_pose := 0
	for soldier: Node in _get_formation_soldiers():
		if not soldier.has_method("get_perf_summary"):
			continue
		var summary: Dictionary = soldier.call("get_perf_summary") as Dictionary
		sampled_count += 1
		var last_physics := int(summary.get("perf_last_physics_usec", 0))
		var last_pose := int(summary.get("perf_last_pose_usec", 0))
		last_physics_total += last_physics
		last_pose_total += last_pose
		max_last_physics = maxi(max_last_physics, last_physics)
		max_last_pose = maxi(max_last_pose, last_pose)
		max_physics = maxi(max_physics, int(summary.get("perf_max_physics_usec", 0)))
		max_pose = maxi(max_pose, int(summary.get("perf_max_pose_usec", 0)))
	return {
		"soldier_perf_monitoring_enabled": soldier_perf_monitoring_enabled,
		"sampled_soldier_count": sampled_count,
		"last_physics_total_usec": last_physics_total,
		"last_pose_total_usec": last_pose_total,
		"max_last_physics_usec": max_last_physics,
		"max_last_pose_usec": max_last_pose,
		"max_physics_usec": max_physics,
		"max_pose_usec": max_pose,
	}


func reset_soldier_perf_counters() -> void:
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("reset_perf_counters"):
			soldier.call("reset_perf_counters")


func _set_soldier_perf_monitoring_enabled(enabled: bool) -> void:
	for soldier: Node in _get_formation_soldiers():
		if soldier.has_method("set_soldier_perf_monitoring_enabled"):
			soldier.call("set_soldier_perf_monitoring_enabled", enabled)
		elif _object_has_property(soldier, &"soldier_perf_monitoring_enabled"):
			soldier.set("soldier_perf_monitoring_enabled", enabled)


func _set_soldier_idle_pose_update_interval(interval: float) -> void:
	for soldier: Node in _get_formation_soldiers():
		if _object_has_property(soldier, &"idle_pose_update_interval"):
			soldier.set("idle_pose_update_interval", maxf(interval, 0.0))


func _set_soldier_active_pose_update_interval(interval: float) -> void:
	for soldier: Node in _get_formation_soldiers():
		if _object_has_property(soldier, &"active_pose_update_interval"):
			soldier.set("active_pose_update_interval", maxf(interval, 0.0))


func reset_stat_job_debug_counters() -> void:
	_stat_last_worker_usec = 0
	_stat_max_worker_usec = 0
	_stat_total_worker_usec = 0
	_stat_completed_jobs = 0
	_stat_started_jobs = 0
	_stat_last_apply_usec = 0
	_stat_max_apply_usec = 0
	_stat_total_apply_usec = 0
	_stat_apply_frames = 0
	_stat_last_apply_count = 0
	_stat_skipped_results = 0
	_stat_worker_completed_job_polls = 0
	_stat_worker_blocking_waits = 0
	_combat_perf_active_cache_rebuilds = 0
	_combat_perf_target_candidate_scans = 0
	_combat_perf_separation_pair_checks = 0
	_combat_perf_steering_updates = 0
	_combat_visual_stance_update_count = 0
	_combat_visual_thrust_count = 0
	_formation_target_write_count = 0
	_formation_target_skip_count = 0
	_moving_formation_pair_checks = 0
	_spatial_grid_rebuilds = 0
	_combat_socket_clamp_count = 0
	if _combat_attacker_spatial_index:
		_combat_attacker_spatial_index.reset_rebuild_count()
	if _combat_defender_spatial_index:
		_combat_defender_spatial_index.reset_rebuild_count()
	if _moving_formation_spatial_index:
		_moving_formation_spatial_index.reset_rebuild_count()


func reset_perf_debug_counters() -> void:
	reset_stat_job_debug_counters()
	reset_soldier_perf_counters()
	if _soldier_batch_renderer and _soldier_batch_renderer.has_method("reset_perf_counters"):
		_soldier_batch_renderer.call("reset_perf_counters")
	_combat_perf_active_cache_rebuilds = 0
	_combat_perf_target_candidate_scans = 0
	_combat_perf_separation_pair_checks = 0
	_combat_perf_steering_updates = 0
	_combat_visual_stance_update_count = 0
	_combat_visual_thrust_count = 0
	_combat_perf_target_candidate_scan_window = 0
	_combat_perf_separation_pair_check_window = 0
	_combat_perf_steering_update_window = 0
	_combat_perf_rate_window_seconds = 0.0
	_combat_perf_target_scans_per_second = 0
	_combat_perf_pair_checks_per_second = 0
	_combat_perf_steering_updates_per_second = 0
	_perf_last_physics_usec = 0
	_perf_max_physics_usec = 0
	_perf_last_combat_tick_usec = 0
	_perf_max_combat_tick_usec = 0
	_perf_last_combat_collect_usec = 0
	_perf_max_combat_collect_usec = 0
	_perf_last_combat_spatial_usec = 0
	_perf_max_combat_spatial_usec = 0
	_perf_last_combat_assign_usec = 0
	_perf_max_combat_assign_usec = 0
	_perf_last_combat_motion_usec = 0
	_perf_max_combat_motion_usec = 0
	_perf_last_formation_separation_usec = 0
	_perf_max_formation_separation_usec = 0
	_perf_last_combat_summary_usec = 0
	_perf_max_combat_summary_usec = 0
	_soldier_render_sync_skip_count = 0
	_perf_stat_worker_wait_count = 0


func _get_pending_stat_apply_result_count() -> int:
	var count := 0
	for batch: Dictionary in _stat_pending_apply_batches:
		var results: Array = batch.get("results", [])
		count += maxi(results.size() - int(batch.get("index", 0)), 0)
	return count


func _get_current_movement_speed_mps() -> float:
	var service = _get_movement_service()
	if not service:
		return maxf(movement_speed_mps, 0.1)
	return service.get_current_movement_speed_mps(self)


func _get_soldier_path_queries_per_tick() -> int:
	return maxi(soldier_path_queries_per_tick, 1)


func _get_soldier_path_speed(soldier: Node) -> float:
	var service = _get_movement_service()
	if not service:
		return maxf(movement_speed_mps, 0.1)
	return service.get_soldier_path_speed(self, soldier)


func _get_soldier_slot_follow_speed(soldier: Node) -> float:
	var service = _get_movement_service()
	if not service:
		return maxf(formation_slot_follow_speed, 0.1)
	return service.get_soldier_slot_follow_speed(self, soldier)


func _get_formation_path_follow_speed() -> float:
	var service = _get_movement_service()
	if not service:
		return maxf(movement_speed_mps, 0.1)
	return service.get_formation_path_follow_speed(self)


func _get_idle_formation_slot_speed(soldier: Node) -> float:
	var service = _get_movement_service()
	if not service:
		return maxf(formation_slot_follow_speed, 0.1)
	return service.get_idle_formation_slot_speed(self, soldier)


func _get_soldier_run_speed(soldier: Node) -> float:
	if is_instance_valid(soldier):
		if soldier is TroopSoldierNPC:
			return maxf((soldier as TroopSoldierNPC).run_speed, 0.1)
		if _object_has_property(soldier, &"run_speed"):
			return maxf(float(soldier.get("run_speed")), 0.1)
		if soldier.has_method("get_combat_summary"):
			var summary: Dictionary = soldier.call("get_combat_summary") as Dictionary
			if summary.has("run_speed"):
				return maxf(float(summary.get("run_speed", base_soldier_run_speed)), 0.1)
	return maxf(base_soldier_run_speed, 0.1)


func _get_minimum_active_run_speed_live(soldiers: Array[Node] = []) -> float:
	if soldiers.is_empty():
		_refresh_soldier_cache_if_needed()
		return maxf(_active_min_run_speed_cache, maxf(base_soldier_run_speed, 0.1))
	var active_soldiers := soldiers
	if active_soldiers.is_empty():
		return maxf(base_soldier_run_speed, 0.1)
	var minimum := INF
	for soldier: Node in active_soldiers:
		minimum = minf(minimum, _get_soldier_run_speed(soldier))
	return minimum if minimum < INF else maxf(base_soldier_run_speed, 0.1)


func _get_maximum_active_run_speed_live() -> float:
	_refresh_soldier_cache_if_needed()
	return maxf(_active_max_run_speed_cache, maxf(base_soldier_run_speed, 0.1))


func _get_movement_endurance_loss_rate() -> float:
	var service = _get_movement_service()
	if not service:
		return 0.0
	return service.get_movement_endurance_loss_rate(self)


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
		"run_speed": maxf(base_soldier_run_speed + stat_rng.randf_range(-soldier_run_speed_variance, soldier_run_speed_variance), 0.1),
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
	_update_soldier_activity_modes()
	_rebuild_attack_zone_indicator()
	_emit_mode_changed()
	_emit_combat_changed()


func _get_formation_soldiers() -> Array[Node]:
	if not _soldier_container:
		return []
	_refresh_formation_soldier_cache_if_needed()
	return _formation_soldiers_cache


func _refresh_formation_soldier_cache_if_needed() -> void:
	if not _formation_soldiers_cache_dirty:
		return
	_formation_soldiers_cache = _soldier_container.get_children()
	_formation_soldiers_cache_dirty = false


func _get_active_soldiers() -> Array[Node]:
	_refresh_soldier_cache_if_needed()
	return _active_soldiers_cache


func _invalidate_soldier_cache() -> void:
	_formation_soldiers_cache_dirty = true
	_soldier_cache_dirty = true
	_mark_combat_stats_dirty()
	_mark_idle_formation_targets_dirty()


func _mark_idle_formation_targets_dirty() -> void:
	_idle_formation_targets_dirty = true


func _mark_moving_formation_targets_dirty() -> void:
	_moving_formation_targets_dirty = true
	_formation_slot_target_refresh_remaining = 0.0


func _clear_formation_target_cache() -> void:
	_formation_slot_target_cache.clear()
	_formation_slot_target_cursor = 0
	_mark_moving_formation_targets_dirty()


func _refresh_soldier_cache_if_needed() -> void:
	if not _soldier_cache_dirty:
		return
	_combat_perf_active_cache_rebuilds += 1
	_active_soldiers_cache.clear()
	_dead_soldier_count_cache = 0
	var minimum_run_speed := INF
	var maximum_run_speed := 0.0
	for soldier: Node in _get_formation_soldiers():
		if _is_soldier_active(soldier):
			_active_soldiers_cache.append(soldier)
			var run_speed := _get_soldier_run_speed(soldier)
			minimum_run_speed = minf(minimum_run_speed, run_speed)
			maximum_run_speed = maxf(maximum_run_speed, run_speed)
		elif soldier.has_method("is_alive") and not bool(soldier.call("is_alive")):
			_dead_soldier_count_cache += 1
	_active_min_run_speed_cache = minimum_run_speed if minimum_run_speed < INF else maxf(base_soldier_run_speed, 0.1)
	_active_max_run_speed_cache = maxf(maximum_run_speed, maxf(base_soldier_run_speed, 0.1))
	_soldier_cache_dirty = false


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
	if soldier is TroopSoldierNPC:
		var troop_soldier := soldier as TroopSoldierNPC
		match key:
			&"strength":
				return troop_soldier.get_strength()
			&"max_strength":
				return troop_soldier.max_strength
			&"damage":
				return troop_soldier.damage
			&"morale":
				return troop_soldier.morale
			&"endurance":
				return troop_soldier.endurance
			&"max_endurance":
				return troop_soldier.max_endurance
			&"run_speed":
				return troop_soldier.run_speed
			&"starving_days":
				return troop_soldier.starving_days
	match key:
		&"strength":
			if soldier.has_method("get_strength"):
				return float(soldier.call("get_strength"))
		&"max_strength":
			if _object_has_property(soldier, &"max_strength"):
				return float(soldier.get("max_strength"))
		&"damage":
			if _object_has_property(soldier, &"damage"):
				return float(soldier.get("damage"))
		&"morale":
			if _object_has_property(soldier, &"morale"):
				return float(soldier.get("morale"))
		&"endurance":
			if _object_has_property(soldier, &"endurance"):
				return float(soldier.get("endurance"))
		&"max_endurance":
			if _object_has_property(soldier, &"max_endurance"):
				return float(soldier.get("max_endurance"))
		&"run_speed":
			if _object_has_property(soldier, &"run_speed"):
				return float(soldier.get("run_speed"))
		&"starving_days":
			if soldier.has_method("get_starving_days"):
				return float(soldier.call("get_starving_days"))
			if _object_has_property(soldier, &"starving_days"):
				return float(soldier.get("starving_days"))
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


func _mark_combat_stats_dirty() -> void:
	_combat_stat_cache_dirty = true


func _get_combat_stat_cache(force_refresh: bool = false) -> Dictionary:
	if not force_refresh and not _combat_stat_cache_dirty:
		return _combat_stat_cache

	var started := Time.get_ticks_usec() if troop_perf_monitoring_enabled else 0
	var soldiers := _get_active_soldiers()
	var active_count := soldiers.size()
	var strength_total := 0.0
	var max_strength_total := 0.0
	var damage_total := 0.0
	var morale_total := 0.0
	var endurance_total := 0.0
	var max_endurance_total := 0.0
	var run_speed_total := 0.0
	var starving_days_total := 0.0
	var minimum_run_speed := INF
	var maximum_run_speed := 0.0

	for soldier: Node in soldiers:
		var strength := 0.0
		var max_strength_value := 0.0
		var damage_value := 0.0
		var morale_value := 0.0
		var endurance_value := 0.0
		var max_endurance_value := 0.0
		var run_speed_value := 0.0
		var starving_days_value := 0.0
		if soldier is TroopSoldierNPC:
			var troop_soldier := soldier as TroopSoldierNPC
			strength = troop_soldier.get_strength()
			max_strength_value = troop_soldier.max_strength
			damage_value = troop_soldier.damage
			morale_value = troop_soldier.morale
			endurance_value = troop_soldier.endurance
			max_endurance_value = troop_soldier.max_endurance
			run_speed_value = troop_soldier.run_speed
			starving_days_value = troop_soldier.starving_days
		else:
			strength = _get_soldier_stat(soldier, &"strength")
			max_strength_value = _get_soldier_stat(soldier, &"max_strength")
			damage_value = _get_soldier_stat(soldier, &"damage")
			morale_value = _get_soldier_stat(soldier, &"morale")
			endurance_value = _get_soldier_stat(soldier, &"endurance")
			max_endurance_value = _get_soldier_stat(soldier, &"max_endurance")
			run_speed_value = _get_soldier_stat(soldier, &"run_speed")
			starving_days_value = _get_soldier_stat(soldier, &"starving_days")

		strength_total += strength
		max_strength_total += max_strength_value
		damage_total += damage_value
		morale_total += morale_value
		endurance_total += endurance_value
		max_endurance_total += max_endurance_value
		run_speed_total += run_speed_value
		starving_days_total += starving_days_value
		minimum_run_speed = minf(minimum_run_speed, run_speed_value)
		maximum_run_speed = maxf(maximum_run_speed, run_speed_value)

	var divisor := float(maxi(active_count, 1))
	var fallback_speed := maxf(base_soldier_run_speed, 0.1)
	_combat_stat_cache = {
		"active_soldier_count": active_count,
		"dead_soldier_count": _dead_soldier_count_cache,
		"deserted_soldier_count": _deserted_soldier_count,
		"average_strength": strength_total / divisor if active_count > 0 else 0.0,
		"average_max_strength": max_strength_total / divisor if active_count > 0 else 0.0,
		"average_damage": damage_total / divisor if active_count > 0 else 0.0,
		"average_morale": morale_total / divisor if active_count > 0 else 0.0,
		"average_endurance": endurance_total / divisor if active_count > 0 else 0.0,
		"average_max_endurance": max_endurance_total / divisor if active_count > 0 else 0.0,
		"average_run_speed": run_speed_total / divisor if active_count > 0 else 0.0,
		"average_starving_days": starving_days_total / divisor if active_count > 0 else 0.0,
		"minimum_run_speed": minimum_run_speed if minimum_run_speed < INF else fallback_speed,
		"maximum_run_speed": maxf(maximum_run_speed, fallback_speed),
	}
	_combat_stat_cache_dirty = false
	if troop_perf_monitoring_enabled:
		_perf_last_combat_summary_usec = Time.get_ticks_usec() - started
		_perf_max_combat_summary_usec = maxi(_perf_max_combat_summary_usec, _perf_last_combat_summary_usec)
	return _combat_stat_cache


func _get_average_endurance_ratio() -> float:
	var stats := _get_combat_stat_cache()
	var max_endurance_value := float(stats.get("average_max_endurance", 0.0))
	if max_endurance_value <= 0.0:
		return 0.0
	return clampf(float(stats.get("average_endurance", 0.0)) / max_endurance_value, 0.0, 1.0)


func _get_combat_summary() -> Dictionary:
	var services := _get_troop_services()
	if services and services.has_method("build_combat_summary"):
		return services.call("build_combat_summary") as Dictionary
	return {}


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


func _start_mission_troop(
	source: Node,
	target: Vector3,
	mission_type: StringName,
	requested_amount: float,
	assigned_soldiers: int,
	extra: Dictionary
) -> void:
	var soldiers := mini(maxi(assigned_soldiers, 0), get_available_carrier_soldiers())
	if soldiers <= 0:
		return

	var selected := _select_available_carrier_soldiers(soldiers)
	if selected.is_empty():
		return

	var mission := Troop.new()
	_copy_configuration_to_child_troop(mission)
	mission.is_mission_troop = true
	mission.hand_flags_enabled = false
	mission.movement_speed_mps = maxf(carrier_speed_mps, 0.1)
	mission.troop_id = StringName("%s_%s_mission_%d" % [String(troop_id), String(mission_type), Time.get_ticks_msec()])
	mission.display_name = "%s %s Party" % [display_name, _get_mission_type_label(mission_type)]
	mission.soldier_count = maxi(selected.size(), 2)
	mission.global_transform = global_transform
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(mission)
	else:
		add_child(mission)
	mission.owner = null
	mission.top_level = true
	mission.global_position = _snap_world_point(global_position)
	mission._clear_children(mission._soldier_container)
	var task_trolley_count := _get_trolley_count_for_carrier_soldiers(selected.size())
	for index: int in range(selected.size()):
		var soldier := selected[index]
		_remove_soldier_for_transfer(soldier)
		mission._adopt_transferred_soldier(soldier, index, selected.size())
		mission._attach_resource_icon(soldier, mission_type)
		if index < task_trolley_count:
			mission._attach_trolley_hint(soldier)
	mission._initialize_mission(self, source, target, mission_type, requested_amount, extra)
	_mission_child_troops.append(mission)
	_refresh_transferred_formation()
	_emit_logistics_changed()
	_emit_combat_changed()


func _copy_configuration_to_child_troop(child: Troop) -> void:
	var properties := [
		"team_id", "controllable", "troop_mode", "movement_mode", "soldier_scene",
		"formation_columns", "formation_spacing", "soldier_scale",
		"soldier_robe_color", "soldier_robe_shadow_color", "soldier_trim_color",
		"soldier_pants_color", "soldier_wrap_color", "soldier_hat_color", "soldier_accent_color",
		"team_flag_color", "troop_flag_color", "selection_collision_layer",
		"movement_speed_mps", "running_speed_multiplier", "arrival_radius",
		"nearest_walkable_search_radius_cells", "path_smoothing_enabled",
		"path_corner_radius_cells", "path_corner_samples", "route_steering_lookahead_m",
		"route_debug_visuals_enabled",
		"movement_map", "movement_map_path", "terrain_path", "time_system_path",
		"soldier_carry_capacity_kg", "cargo_trolley_capacity_kg", "cow_trolley_capacity_kg",
		"cargo_trolley_required_soldiers", "carrier_speed_mps", "carrier_arrival_radius",
		"carrier_work_seconds", "carrier_formation_spacing", "carrier_resource_icon_height",
		"carrier_resource_icon_size", "carrier_turn_responsiveness",
		"base_soldier_strength", "soldier_strength_variance", "base_soldier_damage",
		"soldier_damage_variance", "base_soldier_morale", "soldier_morale_variance",
		"base_soldier_endurance", "soldier_endurance_variance", "base_soldier_run_speed",
		"soldier_run_speed_variance", "combat_seed", "detection_range_m", "ai_chase_detection_range_m",
		"defensive_engagement_range_m", "combat_range_m", "combat_scan_interval",
		"attack_interval", "combat_spear_range_m", "soldier_personal_space_radius",
		"enemy_personal_space_radius", "combat_frontline_width_per_soldier",
		"combat_slot_follow_speed", "combat_separation_strength", "combat_attack_shuffle_radius",
		"combat_attack_shuffle_interval", "combat_attack_shuffle_speed", "combat_logic_interval",
		"combat_target_reassignment_interval", "combat_rebalance_interval",
		"combat_target_assignment_budget_per_tick", "combat_attacker_updates_per_tick",
		"combat_active_attacker_limit", "combat_full_participation_soldier_threshold",
		"combat_separation_updates_per_tick",
		"combat_pair_checks_budget_per_tick", "combat_steering_refresh_interval",
		"combat_steering_refresh_jitter",
		"combat_max_separation_neighbors", "combat_target_search_candidates",
		"combat_assignment_candidates", "combat_max_attackers_per_target",
		"combat_spatial_rebuild_interval",
		"combat_target_load_penalty", "combat_target_stickiness_bonus",
		"combat_socket_radius", "combat_socket_arrival_radius", "chase_repath_interval",
		"combat_engagement_break_range_multiplier", "combat_engagement_break_grace_seconds",
		"walk_endurance_loss_per_second", "run_endurance_loss_per_second",
		"fight_endurance_loss_per_second", "attack_mode_endurance_loss_per_second",
		"endurance_rate_scale", "rest_endurance_recovery_per_second",
		"defensive_endurance_recovery_per_second", "training_endurance_loss_per_second",
		"food_shortage_morale_loss_per_second", "food_shortage_endurance_loss_per_second",
		"desertion_morale_threshold", "desertion_chance_per_second",
		"desertion_check_interval_seconds", "survivor_rout_enabled",
		"survivor_rout_active_threshold", "survivor_rout_min_active_soldiers",
		"survivor_rout_fraction", "survivor_rout_speed_multiplier", "food_kg_per_soldier_per_day",
		"starvation_endurance_loss_per_day", "starvation_health_loss_per_day",
		"starvation_death_start_days", "starvation_death_base_chance_per_day",
		"starvation_death_extra_chance_per_day", "starvation_death_max_chance_per_day",
		"deserter_persuasion_chance", "deserter_persuasion_range_m",
		"deserter_min_spawn_distance_m", "deserter_max_spawn_distance_m",
		"soldier_idle_pose_update_interval", "soldier_render_idle_sync_interval",
		"soldier_render_moving_sync_interval", "soldier_render_active_sync_interval",
		"soldier_render_idle_sync_frame_stride", "combat_render_dirty_soldiers_per_sync",
		"formation_separation_refresh_interval",
		"soldier_visual_logic_updates_per_tick", "combat_visual_logic_updates_per_tick",
		"combat_visual_priority_updates_per_tick", "combat_visual_stance_updates_per_tick",
		"combat_visual_thrust_interval", "combat_visual_thrust_duration",
		"combat_source_corpse_limit",
		"departed_soldier_removal_budget_per_frame",
	]
	for property_name: String in properties:
		if _object_has_property(self, StringName(property_name)) and _object_has_property(child, StringName(property_name)):
			child.set(property_name, get(property_name))


func _initialize_mission(parent_troop: Node, source: Node, target: Vector3, mission_type: StringName, requested_amount: float, extra: Dictionary) -> void:
	_mission_parent = parent_troop
	_mission_source = source
	_mission_type = mission_type
	_mission_state = MISSION_TO_TARGET
	_mission_requested_amount_kg = maxf(requested_amount, 0.0)
	_mission_amount_kg = 0.0
	_mission_target = _snap_world_point(target)
	_mission_source_cell = extra.get("cell", Vector2i.ZERO)
	_mission_paused = false
	_mission_work_remaining = 0.0
	_mission_repath_remaining = 0.0
	_mission_set_destination(_mission_target)
	_emit_logistics_changed()


func _update_mission_task(delta: float) -> void:
	if not is_mission_troop or not _is_mission_active() or _mission_paused:
		return
	if _state == STATE_FIGHTING:
		return
	match _mission_state:
		MISSION_TO_TARGET:
			if not _has_destination and global_position.distance_to(_mission_target) <= maxf(carrier_arrival_radius, arrival_radius):
				_collect_mission_resource()
				_mission_work_remaining = maxf(carrier_work_seconds, 0.0)
				_mission_state = MISSION_WORKING
				_emit_logistics_changed()
			elif not _has_destination:
				_mission_set_destination(_mission_target)
		MISSION_WORKING:
			_mission_work_remaining = maxf(_mission_work_remaining - delta, 0.0)
			if _mission_work_remaining <= 0.0:
				_mission_state = MISSION_RETURNING
				_mission_set_destination(_get_mission_parent_position())
				_emit_logistics_changed()
		MISSION_RETURNING:
			if not is_instance_valid(_mission_parent):
				return
			var parent_position := _get_mission_parent_position()
			if not _has_destination and global_position.distance_to(parent_position) <= maxf(carrier_arrival_radius, arrival_radius):
				_deliver_mission_resource()
				if _mission_parent is Troop:
					(_mission_parent as Troop)._merge_mission_troop(self)
				return
			_mission_repath_remaining = maxf(_mission_repath_remaining - delta, 0.0)
			if not _has_destination or _mission_repath_remaining <= 0.0:
				_mission_repath_remaining = 1.5
				_mission_set_destination(parent_position)


func _mission_set_destination(destination: Vector3) -> bool:
	_mission_internal_command = true
	var accepted := set_move_destination(destination, false)
	if not accepted:
		_destination = _snap_world_point(destination)
		_path_points = [_snap_world_point(global_position), _destination]
		_current_path_index = 1
		_has_destination = true
		_last_path_result = {
			"reachable": true,
			"distance_m": global_position.distance_to(_destination),
			"estimated_seconds": global_position.distance_to(_destination) / maxf(_get_current_movement_speed_mps(), 0.1),
			"failure_reason": &"",
		}
		_manual_move_override_active = false
		_clear_route_visual()
		_set_state(STATE_MOVING)
		_issue_formation_path_to_soldiers()
		_emit_destination_changed()
		accepted = true
	_mission_internal_command = false
	return accepted


func _collect_mission_resource() -> void:
	if _mission_amount_kg > 0.0 or not is_instance_valid(_mission_source):
		return
	match _mission_type:
		MISSION_FOOD:
			if _mission_source.has_method("withdraw_food_kg"):
				_mission_amount_kg = maxf(float(_mission_source.call("withdraw_food_kg", _mission_requested_amount_kg)), 0.0)
		MISSION_WOOD:
			if _mission_source.has_method("harvest_wood_cell"):
				_mission_amount_kg = maxf(float(_mission_source.call("harvest_wood_cell", _mission_source_cell, _mission_requested_amount_kg)), 0.0)


func _deliver_mission_resource() -> void:
	if _mission_amount_kg <= 0.0:
		return
	if not (_mission_parent is Troop):
		return
	var parent_troop := _mission_parent as Troop
	var remaining := _mission_amount_kg
	var deposited := parent_troop._deposit_to_primary_camp(_mission_type, remaining)
	remaining = maxf(remaining - deposited, 0.0)
	match _mission_type:
		MISSION_FOOD:
			var carried := minf(remaining, parent_troop.get_free_carry_capacity_kg())
			parent_troop.carried_food_kg += carried
		MISSION_WOOD:
			var carried := minf(remaining, parent_troop.get_free_carry_capacity_kg())
			parent_troop.carried_wood_kg += carried
	_mission_amount_kg = 0.0
	parent_troop._sync_camp_storage_from_node()
	parent_troop._emit_logistics_changed()


func _merge_mission_troop(mission: Troop) -> void:
	if not is_instance_valid(mission):
		return
	_mission_child_troops.erase(mission)
	var soldiers := mission._get_formation_soldiers()
	for index: int in range(soldiers.size()):
		var soldier := soldiers[index]
		if not (soldier is Node3D):
			continue
		mission._remove_soldier_for_transfer(soldier as Node3D)
		_adopt_transferred_soldier(soldier as Node3D, _get_formation_soldier_count(), _get_formation_soldier_count() + 1)
	mission._mission_state = MISSION_COMPLETE
	mission.remove_from_group(&"mission_troops")
	mission.queue_free()
	_refresh_transferred_formation()
	_emit_logistics_changed()
	_emit_combat_changed()


func _is_mission_active() -> bool:
	return _mission_state != MISSION_NONE and _mission_state != MISSION_COMPLETE


func _get_mission_parent_position() -> Vector3:
	if not is_instance_valid(_mission_parent):
		return global_position
	if _mission_parent is Node3D:
		return (_mission_parent as Node3D).global_position
	return global_position


func _get_mission_child_soldier_count() -> int:
	var count := 0
	for index: int in range(_mission_child_troops.size() - 1, -1, -1):
		var child := _mission_child_troops[index]
		if not is_instance_valid(child):
			_mission_child_troops.remove_at(index)
			continue
		if child.has_method("get_active_soldier_count"):
			count += maxi(int(child.call("get_active_soldier_count")), 0)
	return count


func _step_child_mission_troops_for_manual_call(delta: float) -> void:
	for index: int in range(_mission_child_troops.size() - 1, -1, -1):
		var child := _mission_child_troops[index]
		if not is_instance_valid(child):
			_mission_child_troops.remove_at(index)
			continue
		if child.has_method("_physics_process"):
			child.call("_physics_process", delta)


func _get_mission_summary() -> Dictionary:
	return {
		"mission_active": _is_mission_active(),
		"is_mission_troop": is_mission_troop,
		"mission_type": _mission_type,
		"mission_state": _mission_state,
		"mission_paused": _mission_paused,
		"mission_label": _get_mission_label(),
		"mission_amount_kg": _mission_amount_kg,
		"mission_requested_amount_kg": _mission_requested_amount_kg,
		"can_continue_mission": is_mission_troop and _is_mission_active() and _mission_paused,
		"mission_child_soldiers": _get_mission_child_soldier_count(),
	}


func _get_mission_label() -> String:
	if not _is_mission_active():
		return ""
	var state_text := ""
	match _mission_state:
		MISSION_TO_TARGET:
			state_text = "going"
		MISSION_WORKING:
			state_text = "collecting"
		MISSION_RETURNING:
			state_text = "returning"
		_:
			state_text = String(_mission_state).replace("_", " ")
	if _mission_paused:
		state_text = "%s, paused" % state_text
	return "%s mission: %s (%s)" % [_get_mission_type_label(_mission_type), state_text, _format_weight_for_summary(_mission_amount_kg)]


func _get_mission_type_label(mission_type: StringName) -> String:
	match mission_type:
		MISSION_WOOD, RESOURCE_WOOD:
			return "Wood"
		_:
			return "Food"


func _format_weight_for_summary(value: float) -> String:
	if value >= 1000.0:
		return "%.1ft" % (value / 1000.0)
	return "%.0fkg" % value


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
	_invalidate_soldier_cache()
	_refresh_soldier_batch_renderer_soldiers()
	_mark_unit_selection_proxies_dirty()
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


func _remove_hand_flags_from_soldier(soldier: Node3D) -> void:
	if not soldier:
		return
	for flag_name: String in ["TeamFlag", "TroopFlag"]:
		var flag := soldier.find_child(flag_name, true, false)
		if flag:
			if flag.get_parent():
				flag.get_parent().remove_child(flag)
			flag.free()


func _remove_soldier_for_transfer(soldier: Node3D) -> void:
	if not soldier:
		return
	_forget_combat_soldier_key(soldier.get_instance_id(), true)
	_remove_unit_selection_proxy(soldier)
	_clear_carrier_decoration(soldier)
	var previous_transform := soldier.global_transform if soldier.is_inside_tree() else soldier.transform
	soldier.set_meta(&"troop_transfer_transform", previous_transform)
	if soldier.get_parent():
		soldier.get_parent().remove_child(soldier)
	soldier.owner = null
	soldier.top_level = true
	soldier.transform = previous_transform
	_invalidate_soldier_cache()
	_refresh_soldier_batch_renderer_soldiers()
	_mark_unit_selection_proxies_dirty()


func _remove_departed_soldier(soldier: Node) -> void:
	_remove_departed_soldiers([soldier])


func _remove_departed_soldiers(soldiers: Array) -> int:
	if not _soldier_container or soldiers.is_empty():
		return 0
	var removed := 0
	var structural_removal := _should_compact_after_departed_soldiers()
	for soldier_variant: Variant in soldiers:
		if not (soldier_variant is Node3D):
			continue
		var soldier := soldier_variant as Node3D
		if not is_instance_valid(soldier):
			continue
		if soldier.get_parent() != _soldier_container:
			continue
		_forget_combat_soldier_key(soldier.get_instance_id(), true)
		_remove_unit_selection_proxy(soldier)
		_clear_carrier_decoration(soldier)
		_remove_hand_flags_from_soldier(soldier)
		var dead_soldier := soldier.has_method("is_alive") and not bool(soldier.call("is_alive"))
		if dead_soldier and _should_wait_for_soldier_departure_pose(soldier):
			_set_soldier_live_animation_source(soldier, true)
			_queue_departed_soldier_removal(soldier)
			continue
		if dead_soldier:
			if _soldier_batch_renderer and _soldier_batch_renderer.has_method("restore_sources_for_soldier"):
				_soldier_batch_renderer.call("restore_sources_for_soldier", soldier)
			var registered_corpse := _register_soldier_corpse_if_dead(soldier)
			if registered_corpse and (soldier.get_parent() != _soldier_container or soldier.has_meta(LIVE_CORPSE_NODE_META)):
				removed += 1
				continue
		var can_defer_dead_removal := (
			not structural_removal
			and dead_soldier
			and not _can_capture_soldier_corpse(soldier)
		)
		if can_defer_dead_removal:
			soldier.set_meta(&"troop_pending_combat_removal", true)
			_mark_soldier_render_dirty(soldier)
			removed += 1
			continue
		_soldier_container.remove_child(soldier)
		soldier.queue_free()
		removed += 1
	if removed <= 0:
		return 0
	if structural_removal:
		_refresh_transferred_formation()
	else:
		_invalidate_soldier_cache()
		_mark_unit_selection_proxies_dirty()
	if structural_removal:
		_combat_render_dirty_soldiers.clear()
		_rebuild_ring()
		_rebuild_selection_proxy()
	_emit_combat_changed()
	return removed


func _should_compact_after_departed_soldiers() -> bool:
	return _state != STATE_FIGHTING and not _combat_scatter_active


func _cleanup_deferred_dead_soldiers_after_combat() -> void:
	_combat_source_corpse_count = 0
	if not _soldier_container:
		return
	var removed := 0
	for child: Node in _soldier_container.get_children():
		if not child.has_meta(&"troop_pending_combat_removal"):
			continue
		if child is Node3D:
			_remove_unit_selection_proxy(child as Node3D)
		_soldier_container.remove_child(child)
		child.queue_free()
		removed += 1
	if removed <= 0:
		return
	_invalidate_soldier_cache()
	if _soldier_batch_renderer and _soldier_batch_renderer.has_method("set_soldiers_preserving_hidden_sources"):
		_soldier_batch_renderer.call("set_soldiers_preserving_hidden_sources", _get_formation_soldiers())
	else:
		_refresh_soldier_batch_renderer_soldiers()
	_force_full_soldier_render_sync()
	_mark_unit_selection_proxies_dirty()


func _can_capture_soldier_corpse(soldier: Node3D) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_alive") and bool(soldier.call("is_alive")):
		return false
	if _should_wait_for_soldier_departure_pose(soldier):
		return false
	var manager := _get_or_create_corpse_manager()
	if not manager or not manager.has_method("register_soldier_corpse"):
		return false
	if manager.has_method("has_corpse_capacity") and not bool(manager.call("has_corpse_capacity")):
		return false
	return true


func _register_soldier_corpse_if_dead(soldier: Node3D) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_alive") and bool(soldier.call("is_alive")):
		return false
	if _should_wait_for_soldier_departure_pose(soldier):
		return false
	var manager := _get_or_create_corpse_manager()
	if not manager or not manager.has_method("register_soldier_corpse"):
		return false
	return bool(manager.call("register_soldier_corpse", soldier))


func _get_or_create_corpse_manager() -> Node:
	var parent_node := get_parent()
	if not parent_node:
		var tree := get_tree()
		if tree:
			parent_node = tree.current_scene if tree.current_scene else tree.root
	if not parent_node:
		return null
	var existing := parent_node.get_node_or_null("TroopCorpseManager")
	if existing:
		return existing
	var manager := TroopCorpseManagerScript.new()
	manager.name = "TroopCorpseManager"
	manager.top_level = true
	parent_node.add_child(manager)
	manager.owner = null
	return manager


func _get_corpse_debug_summary() -> Dictionary:
	var parent_node := get_parent()
	if not parent_node:
		return {
			"corpse_count": 0,
			"corpse_batch_count": 0,
			"corpse_live_count": 0,
			"corpse_mesh_part_count": 0,
			"corpse_skipped_count": 0,
			"corpse_skipped_mesh_part_count": 0,
			"corpse_max_visible_count": 0,
			"corpse_max_visible_mesh_part_count": 0,
			"corpse_max_visible_batch_count": 0,
		}
	var manager := parent_node.get_node_or_null("TroopCorpseManager")
	if manager and manager.has_method("get_debug_summary"):
		return manager.call("get_debug_summary") as Dictionary
	return {
		"corpse_count": 0,
		"corpse_batch_count": 0,
		"corpse_live_count": 0,
		"corpse_mesh_part_count": 0,
		"corpse_skipped_count": 0,
		"corpse_skipped_mesh_part_count": 0,
		"corpse_max_visible_count": 0,
		"corpse_max_visible_mesh_part_count": 0,
		"corpse_max_visible_batch_count": 0,
	}


func _adopt_transferred_soldier(soldier: Node3D, index: int, total: int) -> void:
	if not soldier:
		return
	_ensure_scene_nodes()
	var previous_transform := Transform3D.IDENTITY
	if soldier.has_meta(&"troop_transfer_transform"):
		previous_transform = soldier.get_meta(&"troop_transfer_transform") as Transform3D
		soldier.remove_meta(&"troop_transfer_transform")
	elif soldier.is_inside_tree():
		previous_transform = soldier.global_transform
	else:
		previous_transform = soldier.transform
	if soldier.get_parent():
		soldier.get_parent().remove_child(soldier)
	_soldier_container.add_child(soldier)
	soldier.owner = null
	soldier.top_level = true
	soldier.global_transform = previous_transform
	soldier.name = "Soldier_%03d" % index
	var columns := mini(maxi(formation_columns, 1), maxi(total, 1))
	var rows := maxi(ceili(float(maxi(total, 1)) / float(columns)), 1)
	var slot := _get_formation_slot_for_index(index, columns, rows)
	soldier.set_meta(&"troop_formation_index", index)
	soldier.set_meta(&"troop_formation_slot", slot)
	soldier.set_meta(&"troop_formation_phase", float(index) * 1.618)
	_set_troop_selectable_metadata(soldier)
	_ensure_dependency_defaults()
	if soldier.has_method("configure_behavior_set"):
		soldier.call("configure_behavior_set", soldier_behavior_set)
	if not hand_flags_enabled:
		_remove_hand_flags_from_soldier(soldier)
	if soldier.has_method("set_activity_mode"):
		soldier.call("set_activity_mode", _get_soldier_activity_mode())
	if soldier.has_method("clear_independent_motion"):
		soldier.call("clear_independent_motion")
	if soldier.has_method("set_independent_combat"):
		soldier.call("set_independent_combat", false)
	if soldier.has_method("mark_deserter_group_member") and team_id == TEAM_DESERTER:
		soldier.call("mark_deserter_group_member")
	elif soldier.has_method("mark_returned_from_desertion"):
		soldier.call("mark_returned_from_desertion")
	if soldier.has_method("set_formation_walking"):
		soldier.call("set_formation_walking", _state == STATE_MOVING, _get_soldier_path_speed(soldier))
	_track_soldier_mutation_signals(soldier)
	_add_unit_selection_proxy(soldier)
	_invalidate_soldier_cache()
	_refresh_soldier_batch_renderer_soldiers()
	_unit_selection_proxy_dirty = false


func _refresh_transferred_formation() -> void:
	var soldiers := _get_formation_soldiers()
	var total := maxi(soldiers.size(), 1)
	var columns := mini(maxi(formation_columns, 1), total)
	var rows := maxi(ceili(float(total) / float(columns)), 1)
	for index: int in range(soldiers.size()):
		var soldier := soldiers[index]
		if not (soldier is Node3D):
			continue
		var soldier_spatial := soldier as Node3D
		soldier_spatial.set_meta(&"troop_formation_index", index)
		soldier_spatial.set_meta(&"troop_formation_slot", _get_formation_slot_for_index(index, columns, rows))
		soldier_spatial.set_meta(&"troop_formation_phase", float(index) * 1.618)
		_set_troop_selectable_metadata(soldier_spatial)
		if not hand_flags_enabled:
			_remove_hand_flags_from_soldier(soldier_spatial)
		_add_unit_selection_proxy(soldier_spatial)
		_track_soldier_mutation_signals(soldier_spatial)
	_invalidate_soldier_cache()
	_refresh_soldier_batch_renderer_soldiers()
	_unit_selection_proxy_dirty = false
	_rebuild_ring()
	_rebuild_selection_proxy()
	_update_formation_soldier_locomotion()
	_emit_destination_changed()


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
		visual.remove_child(existing)
		existing.free()

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
		soldier.call("set_formation_walking", _state == STATE_MOVING, _get_soldier_path_speed(soldier))
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
	var return_result := _command_soldier_path_target(
		soldier,
		_formation_slot_to_world(slot),
		_get_idle_formation_slot_speed(soldier),
		maxf(arrival_radius * 0.32, 0.18)
	)
	_cache_formation_soldier_target_result(
		soldier.get_instance_id(),
		_formation_slot_to_world(slot),
		_get_idle_formation_slot_speed(soldier),
		maxf(arrival_radius * 0.32, 0.18),
		return_result
	)
	if not bool(return_result.get("reachable", false)):
		_update_formation_soldier_slots(0.0)
	_track_soldier_mutation_signals(soldier)
	_invalidate_soldier_cache()
	_refresh_soldier_batch_renderer_soldiers()
	_mark_unit_selection_proxies_dirty()


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
	if _has_no_signal_listeners(&"destination_changed"):
		return
	destination_changed.emit(get_troop_summary())


func _emit_logistics_changed() -> void:
	if _has_no_signal_listeners(&"logistics_changed"):
		return
	logistics_changed.emit(get_troop_summary())


func _emit_mode_changed() -> void:
	if _has_no_signal_listeners(&"mode_changed"):
		return
	mode_changed.emit(get_troop_summary())


func _emit_combat_changed() -> void:
	if _has_no_signal_listeners(&"combat_changed"):
		return
	combat_changed.emit(get_troop_summary())


func _has_no_signal_listeners(signal_name: StringName) -> bool:
	return get_signal_connection_list(signal_name).is_empty()


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
	if node == _soldier_container:
		_invalidate_soldier_cache()
		_refresh_soldier_batch_renderer_soldiers()
		_mark_unit_selection_proxies_dirty()


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false
