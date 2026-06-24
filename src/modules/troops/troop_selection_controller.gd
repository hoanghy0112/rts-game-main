extends Node
class_name TroopSelectionController

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"
const SELECTABLE_CAMP_TYPE := &"camp"
const TEAM_PLAYER := &"player"
const VILLAGE_SELECTABLE_TYPE_META := &"village_selectable_type"
const VILLAGE_SELECTABLE_REGION_PATH_META := &"village_region_path"
const FORMATION_PREVIEW_NODE_NAME := "FormationDragPreview"
const CONTEXT_ACTION_MOVE_TO_CAMP := 1
const CONTEXT_ACTION_TAKE_CAMP_FOOD := 2
const CONTEXT_ACTION_GIVE_CAMP_FOOD := 3
const CONTEXT_ACTION_TAKE_CAMP_WOOD := 4
const CONTEXT_ACTION_GIVE_CAMP_WOOD := 5
const CONTEXT_ACTION_MOVE_TO_VILLAGE := 20
const CONTEXT_ACTION_COLLECT_VILLAGE_FOOD := 21
const DEFAULT_CONTEXT_TRANSFER_KG := 20.0

@export var troop_drawer_path: NodePath = NodePath("../TroopManagementDrawer")
@export var background_jobs_debug_panel_path: NodePath = NodePath("../TroopBackgroundJobsDebugPanel")
@export var camera_path: NodePath = NodePath("")
@export var forest_region_paths: Array[NodePath] = []
@export var village_region_paths: Array[NodePath] = []
@export_range(1.0, 20000.0, 1.0, "or_greater") var max_pick_distance: float = 5000.0
@export_range(1.0, 64.0, 0.5, "or_greater") var command_click_drag_threshold: float = 6.0
@export_range(0.5, 128.0, 0.1, "or_greater") var formation_drag_min_width_m: float = 4.35
@export_range(0.05, 4.0, 0.01, "or_greater") var formation_preview_circle_radius_m: float = 0.72
@export_range(8, 64, 1, "or_greater") var formation_preview_circle_segments: int = 24
@export_range(0.0, 4.0, 0.01, "or_greater") var formation_preview_height_m: float = 0.18
@export var formation_preview_color: Color = Color(0.42, 0.88, 1.0, 0.68)
@export var formation_preview_chevron_color: Color = Color(0.86, 1.0, 1.0, 0.9)
@export_range(1.0, 96.0, 1.0, "or_greater") var unit_screen_pick_radius_px: float = 28.0
@export_range(1.0, 160.0, 1.0, "or_greater") var camp_flag_screen_pick_radius_px: float = 44.0
@export_flags_3d_physics var troop_collision_mask: int = 1 << 5
@export_flags_3d_physics var destination_collision_mask: int = 0xFFFFFFFF
@export_flags_3d_physics var village_selection_collision_mask: int = 1

var _selected_troop: Node
var _hovered_troop: Node
var _pending_select_position := Vector2(INF, INF)
var _pending_hover_position := Vector2(INF, INF)
var _pending_command_position := Vector2(INF, INF)
var _pending_food_select_position := Vector2(INF, INF)
var _right_press_position := Vector2(INF, INF)
var _formation_drag_active := false
var _formation_drag_start_world: Variant = null
var _formation_drag_current_world: Variant = null
var _formation_preview: MeshInstance3D
var _food_collection_troop: Node
var _food_collection_amount_kg := 0.0
var _context_menu: PopupMenu
var _context_target: Node
var _context_target_type: StringName = &""


func _ready() -> void:
	_bind_drawer_signals()
	_ensure_context_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _physics_process(_delta: float) -> void:
	if is_finite(_pending_hover_position.x):
		var hover_position := _pending_hover_position
		_pending_hover_position = Vector2(INF, INF)
		_update_hovered_troop_at(hover_position)

	if is_finite(_pending_select_position.x):
		var select_position := _pending_select_position
		_pending_select_position = Vector2(INF, INF)
		_pick_troop(select_position)

	if is_finite(_pending_command_position.x):
		var command_position := _pending_command_position
		_pending_command_position = Vector2(INF, INF)
		_issue_move_command(command_position)

	if is_finite(_pending_food_select_position.x):
		var food_position := _pending_food_select_position
		_pending_food_select_position = Vector2(INF, INF)
		_issue_food_collection(food_position)


func _exit_tree() -> void:
	_clear_formation_drag_preview()
	_clear_context_menu_target()
	_set_hovered_troop(null)
	_select_troop(null)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if _is_pointer_over_ui():
		return

	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(_food_collection_troop):
			_pending_food_select_position = event.position
			get_viewport().set_input_as_handled()
			return
		_pending_select_position = event.position
		return

	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if event.pressed:
		_right_press_position = event.position
		_formation_drag_active = false
		_formation_drag_start_world = null
		_formation_drag_current_world = null
		if _can_selected_troop_accept_formation_drag():
			_formation_drag_start_world = _get_world_destination(event.position)
			_cancel_camera_right_drag_rotation()
			get_viewport().set_input_as_handled()
		return

	if not is_finite(_right_press_position.x):
		return
	var drag_distance := event.position.distance_to(_right_press_position)
	_right_press_position = Vector2(INF, INF)
	var should_issue_formation := (
		_can_selected_troop_accept_formation_drag()
		and drag_distance > command_click_drag_threshold
	)
	if should_issue_formation:
		var release_world: Variant = _get_world_destination(event.position)
		if _formation_drag_current_world != null:
			release_world = _formation_drag_current_world
		var accepted := _issue_formation_drag_command(_formation_drag_start_world, release_world)
		_reset_formation_drag_state()
		if accepted:
			get_viewport().set_input_as_handled()
		return
	_reset_formation_drag_state()
	if drag_distance > command_click_drag_threshold:
		return
	if not _selected_troop:
		return

	if _try_show_context_menu(event.position):
		get_viewport().set_input_as_handled()
		return

	_pending_command_position = event.position
	get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_pointer_over_ui():
		_pending_hover_position = Vector2(INF, INF)
		_set_hovered_troop(null)
		_reset_formation_drag_state()
		return
	_pending_hover_position = event.position
	if not is_finite(_right_press_position.x) or not _can_selected_troop_accept_formation_drag():
		return
	var drag_distance := event.position.distance_to(_right_press_position)
	if drag_distance < command_click_drag_threshold:
		return
	_formation_drag_active = true
	if _formation_drag_start_world == null:
		_formation_drag_start_world = _get_world_destination(_right_press_position)
	_formation_drag_current_world = _get_world_destination(event.position)
	_update_formation_drag_preview()
	_cancel_camera_right_drag_rotation()
	get_viewport().set_input_as_handled()


func _can_selected_troop_accept_formation_drag() -> bool:
	return _is_commandable_troop(_selected_troop) and _selected_troop.has_method("set_formation_destination")


func _issue_formation_drag_command(start_world: Variant, end_world: Variant) -> bool:
	if not _can_selected_troop_accept_formation_drag():
		return false
	if not (start_world is Vector3) or not (end_world is Vector3):
		return false
	var start := start_world as Vector3
	var end := end_world as Vector3
	var line := end - start
	line.y = 0.0
	var width := line.length()
	if width <= 0.001:
		return false
	var right_axis := line / width
	var center := start.lerp(end, 0.5)
	var accepted := bool(_selected_troop.call(
		"set_formation_destination",
		center,
		right_axis,
		maxf(width, maxf(formation_drag_min_width_m, 0.1))
	))
	if accepted:
		var drawer := _get_troop_drawer()
		if drawer and drawer.has_method("refresh"):
			drawer.call("refresh")
	return accepted


func _reset_formation_drag_state() -> void:
	_formation_drag_active = false
	_formation_drag_start_world = null
	_formation_drag_current_world = null
	_clear_formation_drag_preview()


func _update_formation_drag_preview() -> void:
	if not _formation_drag_active:
		_clear_formation_drag_preview()
		return
	if not (_formation_drag_start_world is Vector3) or not (_formation_drag_current_world is Vector3):
		_clear_formation_drag_preview()
		return
	var start := _formation_drag_start_world as Vector3
	var end := _formation_drag_current_world as Vector3
	var line := end - start
	line.y = 0.0
	if line.length_squared() <= 0.0001:
		_clear_formation_drag_preview()
		return
	var center := start.lerp(end, 0.5)
	center.y = maxf(start.y, end.y) + maxf(formation_preview_height_m, 0.0)
	var mesh := _build_formation_preview_mesh(start, end, center)
	if not _formation_preview or not is_instance_valid(_formation_preview):
		_formation_preview = MeshInstance3D.new()
		_formation_preview.name = FORMATION_PREVIEW_NODE_NAME
		_formation_preview.top_level = true
		_formation_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_formation_preview.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_formation_preview.material_override = _make_formation_preview_material()
		add_child(_formation_preview)
		_formation_preview.owner = null
	_formation_preview.global_position = center
	_formation_preview.global_rotation = Vector3.ZERO
	_formation_preview.mesh = mesh
	_formation_preview.visible = true


func _clear_formation_drag_preview() -> void:
	if _formation_preview and is_instance_valid(_formation_preview):
		if _formation_preview.get_parent():
			_formation_preview.get_parent().remove_child(_formation_preview)
		_formation_preview.free()
	_formation_preview = null


func _build_formation_preview_mesh(start: Vector3, end: Vector3, origin: Vector3) -> ArrayMesh:
	var right := end - start
	right.y = 0.0
	right = right.normalized()
	var forward := Vector3(right.z, 0.0, -right.x).normalized()
	var soldier_count := _get_selected_troop_preview_soldier_count()
	var spacing := _get_selected_troop_preview_spacing()
	var columns := _get_preview_columns_for_width(start.distance_to(end), soldier_count, spacing)
	var rows := maxi(ceili(float(soldier_count) / float(maxi(columns, 1))), 1)
	var width := float(maxi(columns - 1, 0)) * spacing
	var depth := float(maxi(rows - 1, 0)) * spacing
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for index: int in range(soldier_count):
		var column := index % maxi(columns, 1)
		var row := int(index / maxi(columns, 1))
		var x := float(column) * spacing - width * 0.5
		var z := float(row) * spacing - depth * 0.5
		var circle_center := origin + right * x + forward * z
		_append_preview_circle(
			vertices,
			normals,
			colors,
			indices,
			circle_center - origin,
			right,
			forward
		)

	var chevron_center := forward * (depth * 0.5 + maxf(spacing * 0.7, formation_preview_circle_radius_m * 1.6))
	_append_preview_chevron(
		vertices,
		normals,
		colors,
		indices,
		chevron_center,
		right,
		forward,
		spacing
	)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_preview_circle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	center: Vector3,
	right: Vector3,
	forward: Vector3
) -> void:
	var start_index := vertices.size()
	var radius := maxf(formation_preview_circle_radius_m, 0.05)
	var segments := maxi(formation_preview_circle_segments, 8)
	vertices.append(center)
	normals.append(Vector3.UP)
	colors.append(formation_preview_color)
	for segment: int in range(segments):
		var angle := TAU * float(segment) / float(segments)
		var point := center + right * cos(angle) * radius + forward * sin(angle) * radius
		vertices.append(point)
		normals.append(Vector3.UP)
		colors.append(formation_preview_color)
	for segment: int in range(segments):
		var next_segment := (segment + 1) % segments
		indices.append(start_index)
		indices.append(start_index + 1 + segment)
		indices.append(start_index + 1 + next_segment)


func _append_preview_chevron(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	center: Vector3,
	right: Vector3,
	forward: Vector3,
	spacing: float
) -> void:
	var length := maxf(spacing * 0.78, formation_preview_circle_radius_m * 2.2)
	var half_width := maxf(spacing * 0.48, formation_preview_circle_radius_m * 1.45)
	var thickness := maxf(formation_preview_circle_radius_m * 0.34, 0.12)
	var tip := center + forward * (length * 0.5)
	var left_tail := center - forward * (length * 0.5) - right * half_width
	var right_tail := center - forward * (length * 0.5) + right * half_width
	_append_preview_strip(vertices, normals, colors, indices, left_tail, tip, thickness)
	_append_preview_strip(vertices, normals, colors, indices, tip, right_tail, thickness)


func _append_preview_strip(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	start: Vector3,
	end: Vector3,
	thickness: float
) -> void:
	var segment := end - start
	segment.y = 0.0
	if segment.length_squared() <= 0.0001:
		return
	var side := Vector3(-segment.z, 0.0, segment.x).normalized() * (thickness * 0.5)
	var start_index := vertices.size()
	vertices.append(start + side)
	vertices.append(start - side)
	vertices.append(end - side)
	vertices.append(end + side)
	for _index: int in range(4):
		normals.append(Vector3.UP)
		colors.append(formation_preview_chevron_color)
	indices.append(start_index)
	indices.append(start_index + 1)
	indices.append(start_index + 2)
	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 3)


func _get_selected_troop_preview_soldier_count() -> int:
	if _selected_troop:
		if _selected_troop.has_method("get_active_soldier_count"):
			return maxi(int(_selected_troop.call("get_active_soldier_count")), 1)
		if _selected_troop.has_method("get_soldier_count"):
			return maxi(int(_selected_troop.call("get_soldier_count")), 1)
	return 1


func _get_selected_troop_preview_spacing() -> float:
	if _selected_troop and _object_has_property(_selected_troop, &"formation_spacing"):
		return maxf(float(_selected_troop.get("formation_spacing")), 0.1)
	return maxf(formation_drag_min_width_m, 0.1)


func _get_preview_columns_for_width(width_m: float, soldier_count: int, spacing: float) -> int:
	var width_columns := int(round(maxf(width_m, 0.0) / maxf(spacing, 0.1))) + 1
	return clampi(width_columns, 1, maxi(soldier_count, 1))


func _make_formation_preview_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 80
	material.vertex_color_use_as_albedo = true
	material.albedo_color = formation_preview_color
	material.emission_enabled = true
	material.emission = Color(formation_preview_color.r, formation_preview_color.g, formation_preview_color.b, 1.0)
	material.emission_energy_multiplier = 0.45
	return material


func _cancel_camera_right_drag_rotation() -> void:
	var camera := _get_camera()
	if not camera:
		return
	var current: Node = camera
	while current:
		if current.has_method("cancel_right_drag_rotation"):
			current.call("cancel_right_drag_rotation")
			return
		current = current.get_parent()


func _pick_troop(screen_position: Vector2) -> void:
	var troop := _get_troop_at(screen_position)
	_select_troop(troop)
	if troop:
		get_viewport().set_input_as_handled()


func _issue_move_command(screen_position: Vector2) -> void:
	if not _is_commandable_troop(_selected_troop):
		return
	var target_troop := _get_troop_at(screen_position)
	if _try_issue_attack_target(target_troop):
		return

	var destination: Variant = _get_world_destination(screen_position)
	if destination == null:
		return
	if _try_issue_forest_logistics(destination as Vector3):
		var logistics_drawer := _get_troop_drawer()
		if logistics_drawer and logistics_drawer.has_method("refresh"):
			logistics_drawer.call("refresh")
		return
	if _selected_troop.has_method("set_move_destination"):
		_selected_troop.call("set_move_destination", destination as Vector3)
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _issue_food_collection(screen_position: Vector2) -> void:
	var troop := _food_collection_troop
	if not _is_commandable_troop(troop):
		_clear_food_collection_targeting()
		return

	var village := _get_village_at(screen_position)
	if not village:
		return

	if troop.has_method("begin_food_collection"):
		troop.call("begin_food_collection", village, _food_collection_amount_kg)
	_clear_food_collection_targeting()
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _try_show_context_menu(screen_position: Vector2) -> bool:
	if not _is_commandable_troop(_selected_troop):
		return false

	var camp := _get_camp_at(screen_position)
	if camp and _is_friendly_camp(camp):
		_show_camp_context_menu(camp, screen_position)
		return true

	var village := _get_village_at(screen_position)
	if village:
		_show_village_context_menu(village, screen_position)
		return true

	return false


func _show_camp_context_menu(camp: Node, screen_position: Vector2) -> void:
	var menu := _ensure_context_menu()
	if not menu:
		return
	_context_target = camp
	_context_target_type = &"camp"
	menu.clear()
	_add_context_item("Move to Camp", CONTEXT_ACTION_MOVE_TO_CAMP)
	menu.add_separator()

	var in_range := _is_selected_troop_in_camp_range(camp)
	var summary := _get_selected_troop_summary()
	var free_capacity := float(summary.get("free_capacity_kg", 0.0))
	var carried_food := float(summary.get("carried_food_kg", 0.0))
	var carried_wood := float(summary.get("carried_wood_kg", 0.0))
	var camp_food := _get_object_float(camp, &"food_kg")
	var camp_wood := _get_object_float(camp, &"wood_kg")
	_add_context_item("Take Food", CONTEXT_ACTION_TAKE_CAMP_FOOD, not in_range or free_capacity <= 0.0 or camp_food <= 0.0)
	_add_context_item("Give Food", CONTEXT_ACTION_GIVE_CAMP_FOOD, not in_range or carried_food <= 0.0)
	_add_context_item("Take Wood", CONTEXT_ACTION_TAKE_CAMP_WOOD, not in_range or free_capacity <= 0.0 or camp_wood <= 0.0)
	_add_context_item("Give Wood", CONTEXT_ACTION_GIVE_CAMP_WOOD, not in_range or carried_wood <= 0.0)
	_popup_context_menu(screen_position)


func _show_village_context_menu(village: Node, screen_position: Vector2) -> void:
	var menu := _ensure_context_menu()
	if not menu:
		return
	_context_target = village
	_context_target_type = &"village"
	menu.clear()
	_add_context_item("Move to Village", CONTEXT_ACTION_MOVE_TO_VILLAGE)
	var summary := _get_selected_troop_summary()
	var free_capacity := float(summary.get("free_capacity_kg", 0.0))
	var food_available := _get_village_food_available_kg(village)
	_add_context_item("Collect Food", CONTEXT_ACTION_COLLECT_VILLAGE_FOOD, free_capacity <= 0.0 or food_available <= 0.0)
	_popup_context_menu(screen_position)


func _add_context_item(label: String, action_id: int, disabled: bool = false) -> void:
	if not _context_menu:
		return
	_context_menu.add_item(label, action_id)
	var index := _context_menu.item_count - 1
	_context_menu.set_item_disabled(index, disabled)


func _popup_context_menu(screen_position: Vector2) -> void:
	if not _context_menu:
		return
	var popup_position := Vector2i(roundi(screen_position.x), roundi(screen_position.y))
	_context_menu.popup(Rect2i(popup_position, Vector2i(1, 1)))


func _on_context_menu_id_pressed(action_id: int) -> void:
	var target := _context_target
	var target_type := _context_target_type
	_clear_context_menu_target()
	if not is_instance_valid(target) or not _is_commandable_troop(_selected_troop):
		return

	match action_id:
		CONTEXT_ACTION_MOVE_TO_CAMP:
			if target_type == &"camp":
				_issue_move_to_context_target(target)
		CONTEXT_ACTION_TAKE_CAMP_FOOD:
			if target_type == &"camp" and _selected_troop.has_method("take_food_from_camp"):
				_selected_troop.call("take_food_from_camp", target, _get_context_transfer_amount_kg())
		CONTEXT_ACTION_GIVE_CAMP_FOOD:
			if target_type == &"camp" and _selected_troop.has_method("deposit_food_to_camp"):
				_selected_troop.call("deposit_food_to_camp", target, _get_context_transfer_amount_kg())
		CONTEXT_ACTION_TAKE_CAMP_WOOD:
			if target_type == &"camp" and _selected_troop.has_method("take_wood_from_camp"):
				_selected_troop.call("take_wood_from_camp", target, _get_context_transfer_amount_kg())
		CONTEXT_ACTION_GIVE_CAMP_WOOD:
			if target_type == &"camp" and _selected_troop.has_method("deposit_wood_to_camp"):
				_selected_troop.call("deposit_wood_to_camp", target, _get_context_transfer_amount_kg())
		CONTEXT_ACTION_MOVE_TO_VILLAGE:
			if target_type == &"village":
				_issue_move_to_context_target(target)
		CONTEXT_ACTION_COLLECT_VILLAGE_FOOD:
			if target_type == &"village" and _selected_troop.has_method("begin_food_collection"):
				_selected_troop.call("begin_food_collection", target, _get_context_food_amount_kg())

	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _issue_move_to_context_target(target: Node) -> bool:
	if not _is_commandable_troop(_selected_troop) or not _selected_troop.has_method("set_move_destination"):
		return false
	var position := _get_context_target_world_position(target)
	return bool(_selected_troop.call("set_move_destination", position))


func _get_context_target_world_position(target: Node) -> Vector3:
	if target and target.has_method("get_village_storage_world_position"):
		var value: Variant = target.call("get_village_storage_world_position")
		if value is Vector3:
			return value as Vector3
	if target and target.has_method("get_management_flag_world_position"):
		var flag_position: Variant = target.call("get_management_flag_world_position")
		if flag_position is Vector3:
			var flag := flag_position as Vector3
			return Vector3(flag.x, 0.0, flag.z)
	if target is Node3D:
		return (target as Node3D).global_position
	return Vector3.ZERO


func _get_context_food_amount_kg() -> float:
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("get_food_collection_amount_kg"):
		return maxf(float(drawer.call("get_food_collection_amount_kg")), 1.0)
	return DEFAULT_CONTEXT_TRANSFER_KG


func _get_context_transfer_amount_kg() -> float:
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("get_camp_transfer_amount_kg"):
		return maxf(float(drawer.call("get_camp_transfer_amount_kg")), 1.0)
	return DEFAULT_CONTEXT_TRANSFER_KG


func _get_selected_troop_summary() -> Dictionary:
	if _selected_troop and _selected_troop.has_method("get_troop_summary"):
		return _selected_troop.call("get_troop_summary") as Dictionary
	return {}


func _clear_context_menu_target() -> void:
	_context_target = null
	_context_target_type = &""


func _try_issue_forest_logistics(world_position: Vector3) -> bool:
	if not _is_commandable_troop(_selected_troop):
		return false

	var forest_data := _get_forest_region_and_cell(world_position)
	if forest_data.is_empty():
		return false

	var region := forest_data.get("region") as Node
	var cell: Vector2i = forest_data.get("cell", Vector2i.ZERO)
	if not region:
		return false

	if region.has_method("is_cow_cell") and bool(region.call("is_cow_cell", cell)):
		if _selected_troop.has_method("pickup_cow_from_forest"):
			return bool(_selected_troop.call("pickup_cow_from_forest", region, cell))

	if region.has_method("is_tree_cell") and bool(region.call("is_tree_cell", cell)):
		var soldiers := 1
		var drawer := _get_troop_drawer()
		if drawer and drawer.has_method("get_wood_collection_soldiers"):
			soldiers = int(drawer.call("get_wood_collection_soldiers"))
		if _selected_troop.has_method("begin_wood_collection"):
			return bool(_selected_troop.call("begin_wood_collection", region, cell, soldiers))

	return false


func _select_troop(troop: Node) -> void:
	if troop and not _is_selectable_troop(troop):
		troop = null
	if _selected_troop == troop:
		if troop:
			_show_drawer(troop)
			_update_background_jobs_debug_panel(troop)
		return

	if is_instance_valid(_selected_troop):
		if _selected_troop.has_method("set_selected"):
			_selected_troop.call("set_selected", false)

	_selected_troop = troop
	if is_instance_valid(_selected_troop):
		if _selected_troop.has_method("set_selected"):
			_selected_troop.call("set_selected", true)
		_show_drawer(_selected_troop)
		_update_background_jobs_debug_panel(_selected_troop)
	else:
		var drawer := _get_troop_drawer()
		if drawer and drawer.has_method("hide_drawer"):
			drawer.call("hide_drawer")
		_update_background_jobs_debug_panel(null)


func _update_hovered_troop_at(screen_position: Vector2) -> void:
	_set_hovered_troop(_get_troop_at(screen_position))


func _set_hovered_troop(troop: Node) -> void:
	if troop and not _is_selectable_troop(troop):
		troop = null
	if _hovered_troop == troop:
		return
	if is_instance_valid(_hovered_troop) and _hovered_troop.has_method("set_hovered"):
		_hovered_troop.call("set_hovered", false)
	_hovered_troop = troop
	if is_instance_valid(_hovered_troop) and _hovered_troop.has_method("set_hovered"):
		_hovered_troop.call("set_hovered", true)
	_update_pointer_cursor()


func _update_pointer_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if is_instance_valid(_hovered_troop) else Input.CURSOR_ARROW)


func _show_drawer(troop: Node) -> void:
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("show_troop"):
		drawer.call("show_troop", troop)


func _get_troop_at(screen_position: Vector2) -> Node:
	var camera := _get_camera()
	if not camera:
		return null

	var world := camera.get_world_3d()
	if not world:
		return null

	var query := _make_ray_query(camera, screen_position, troop_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state := world.direct_space_state
	for _attempt: int in range(12):
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return _get_nearest_selectable_screen_target(screen_position, camera)

		var collider := result.get("collider") as Object
		var selectable := _find_selectable_node(collider)
		if selectable:
			return _get_troop_for_selectable(selectable)

		var rid: RID = result.get("rid", RID())
		if rid.is_valid():
			query.exclude.append(rid)
		else:
			return null
	return _get_nearest_selectable_screen_target(screen_position, camera)


func _get_camp_at(screen_position: Vector2) -> Node:
	var camera := _get_camera()
	if not camera:
		return null

	var world := camera.get_world_3d()
	if not world:
		return null

	var query := _make_ray_query(camera, screen_position, troop_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state := world.direct_space_state
	for _attempt: int in range(12):
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return _get_nearest_camp_screen_target(screen_position, camera)

		var collider := result.get("collider") as Object
		var selectable := _find_selectable_node(collider)
		if selectable and str(selectable.get_meta(SELECTABLE_TYPE_META, "")) == str(SELECTABLE_CAMP_TYPE):
			var camp := _get_troop_for_selectable(selectable)
			return camp if _is_camp_node(camp) else null

		var rid: RID = result.get("rid", RID())
		if rid.is_valid():
			query.exclude.append(rid)
		else:
			return null
	return _get_nearest_camp_screen_target(screen_position, camera)


func _get_nearest_selectable_screen_target(screen_position: Vector2, camera: Camera3D) -> Node:
	var nearest_troop := _get_nearest_troop_screen_target(screen_position, camera)
	return nearest_troop if nearest_troop else _get_nearest_camp_screen_target(screen_position, camera)


func _get_nearest_troop_screen_target(screen_position: Vector2, camera: Camera3D) -> Node:
	if not camera or unit_screen_pick_radius_px <= 0.0:
		return null
	var tree := get_tree()
	if not tree:
		return null

	var best_troop: Node
	var best_distance_squared := unit_screen_pick_radius_px * unit_screen_pick_radius_px
	for troop: Node in tree.get_nodes_in_group(&"troops"):
		if not _is_selectable_troop(troop):
			continue
		for world_position: Vector3 in _get_troop_screen_pick_points(troop):
			if not _is_world_position_projectable(camera, world_position):
				continue
			var projected := camera.unproject_position(world_position)
			var distance_squared := projected.distance_squared_to(screen_position)
			if distance_squared <= best_distance_squared:
				best_troop = troop
				best_distance_squared = distance_squared
	return best_troop


func _get_nearest_camp_screen_target(screen_position: Vector2, camera: Camera3D) -> Node:
	if not camera or camp_flag_screen_pick_radius_px <= 0.0:
		return null
	var tree := get_tree()
	if not tree:
		return null

	var best_camp: Node
	var best_distance_squared := camp_flag_screen_pick_radius_px * camp_flag_screen_pick_radius_px
	for camp: Node in tree.get_nodes_in_group(&"camps"):
		if not _is_camp_node(camp):
			continue
		var flag_position_variant: Variant = null
		if camp.has_method("get_management_flag_world_position"):
			flag_position_variant = camp.call("get_management_flag_world_position")
		if not (flag_position_variant is Vector3):
			continue
		var flag_position := flag_position_variant as Vector3
		if not _is_world_position_projectable(camera, flag_position):
			continue
		var projected := camera.unproject_position(flag_position)
		var distance_squared := projected.distance_squared_to(screen_position)
		if distance_squared <= best_distance_squared:
			best_camp = camp
			best_distance_squared = distance_squared
	return best_camp


func _get_troop_screen_pick_points(troop: Node) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if troop.has_method("get_management_flag_world_position"):
		var flag_position: Variant = troop.call("get_management_flag_world_position")
		if flag_position is Vector3:
			points.append(flag_position as Vector3)

	var soldiers := troop.get_node_or_null("Soldiers")
	if soldiers:
		for soldier: Node in soldiers.get_children():
			if not (soldier is Node3D):
				continue
			if soldier.get_node_or_null("TroopUnitClickProxy") == null:
				continue
			var soldier_position := (soldier as Node3D).global_position
			points.append(soldier_position + Vector3(0.0, 1.1, 0.0))
	return points


func _is_world_position_projectable(camera: Camera3D, world_position: Vector3) -> bool:
	var forward := -camera.global_transform.basis.z.normalized()
	return (world_position - camera.global_position).dot(forward) > camera.near


func _get_world_destination(screen_position: Vector2) -> Variant:
	var camera := _get_camera()
	if not camera:
		return null

	var world := camera.get_world_3d()
	if not world:
		return _intersect_ground_plane(camera, screen_position)

	var query := _make_ray_query(camera, screen_position, destination_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state := world.direct_space_state
	for _attempt: int in range(16):
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			break

		var collider := result.get("collider") as Object
		if _find_selectable_node(collider):
			var rid: RID = result.get("rid", RID())
			if rid.is_valid():
				query.exclude.append(rid)
				continue

		var position: Variant = result.get("position")
		if position is Vector3:
			return position
		break

	return _intersect_ground_plane(camera, screen_position)


func _get_village_at(screen_position: Vector2) -> Node:
	var camera := _get_camera()
	if not camera:
		return null

	var world := camera.get_world_3d()
	if not world:
		return null

	var query := _make_ray_query(camera, screen_position, village_selection_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state := world.direct_space_state
	for _attempt: int in range(12):
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return null

		var collider := result.get("collider") as Object
		var selectable := _find_village_selectable_node(collider)
		var village := _get_village_for_selectable(selectable)
		if village:
			return village

		var rid: RID = result.get("rid", RID())
		if rid.is_valid():
			query.exclude.append(rid)
		else:
			return null
	return null


func _make_ray_query(
	camera: Camera3D,
	screen_position: Vector2,
	mask: int
) -> PhysicsRayQueryParameters3D:
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * max_pick_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = mask
	return query


func _intersect_ground_plane(camera: Camera3D, screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if is_zero_approx(direction.y):
		return null
	var distance := -origin.y / direction.y
	if distance < 0.0 or distance > max_pick_distance:
		return null
	return origin + direction * distance


func _find_selectable_node(object: Object) -> Node:
	if not (object is Node):
		return null

	var current := object as Node
	while current:
		if current.has_meta(SELECTABLE_TYPE_META):
			return current
		current = current.get_parent()
	return null


func _get_troop_for_selectable(selectable: Node) -> Node:
	if not selectable:
		return null
	var selectable_type := StringName(selectable.get_meta(SELECTABLE_TYPE_META, &""))
	if selectable_type != SELECTABLE_TROOP_TYPE and selectable_type != SELECTABLE_CAMP_TYPE:
		return null

	var troop_path: NodePath = selectable.get_meta(SELECTABLE_NODE_PATH_META, NodePath(""))
	if not troop_path.is_empty():
		var troop := get_node_or_null(troop_path)
		if _is_selectable_troop(troop):
			return troop

	var current := selectable
	while current:
		if _is_selectable_troop(current):
			return current
		current = current.get_parent()
	return null


func _try_issue_attack_target(target_troop: Node) -> bool:
	if not _is_commandable_troop(_selected_troop):
		return false
	if not _is_enemy_troop(_selected_troop, target_troop):
		return false
	if not _selected_troop.has_method("command_attack_troop"):
		return false

	var accepted := bool(_selected_troop.call("command_attack_troop", target_troop))
	if accepted:
		var drawer := _get_troop_drawer()
		if drawer and drawer.has_method("refresh"):
			drawer.call("refresh")
	return accepted


func _is_camp_node(node: Node) -> bool:
	if not node or not node.has_method("get_troop_summary"):
		return false
	var summary: Dictionary = node.call("get_troop_summary") as Dictionary
	return str(summary.get("entity_type", "")) == "camp"


func _is_friendly_camp(camp: Node) -> bool:
	if not _is_camp_node(camp) or not _selected_troop:
		return false
	var camp_team: Variant = camp.get("team_id")
	var troop_team: Variant = _selected_troop.get("team_id")
	if camp_team == null or troop_team == null:
		return false
	return str(camp_team) == str(troop_team)


func _is_selected_troop_in_camp_range(camp: Node) -> bool:
	if not _selected_troop or not camp:
		return false
	if camp.has_method("is_troop_in_range"):
		return bool(camp.call("is_troop_in_range", _selected_troop))
	if camp is Node3D and _selected_troop is Node3D:
		return (camp as Node3D).global_position.distance_to((_selected_troop as Node3D).global_position) <= 0.1
	return false


func _is_enemy_troop(source: Node, target: Node) -> bool:
	if not source or not target or source == target:
		return false
	if not _is_selectable_troop(target):
		return false
	var source_team: Variant = source.get("team_id")
	var target_team: Variant = target.get("team_id")
	if source_team == null or target_team == null:
		return false
	return StringName(source_team) != StringName(target_team)


func _is_selectable_troop(troop: Node) -> bool:
	if not troop or not troop.has_method("get_troop_summary"):
		return false
	if troop.has_method("is_defeated") and bool(troop.call("is_defeated")):
		return false
	return true


func _is_commandable_troop(troop: Node) -> bool:
	if not troop or not troop.has_method("set_move_destination"):
		return false
	var controllable: Variant = troop.get("controllable")
	if controllable is bool and not bool(controllable):
		return false
	var team: Variant = troop.get("team_id")
	if team != null and StringName(team) != TEAM_PLAYER:
		return false
	return true


func _find_village_selectable_node(object: Object) -> Node:
	if not (object is Node):
		return null

	var current := object as Node
	while current:
		if current.has_meta(VILLAGE_SELECTABLE_TYPE_META):
			return current
		current = current.get_parent()
	return null


func _get_village_for_selectable(selectable: Node) -> Node:
	if not selectable:
		return null

	var region_path: NodePath = selectable.get_meta(VILLAGE_SELECTABLE_REGION_PATH_META, NodePath(""))
	if not region_path.is_empty():
		var region := get_node_or_null(region_path)
		if region and region.has_method("withdraw_food_kg"):
			return region

	var current := selectable
	while current:
		if current.has_method("withdraw_food_kg"):
			return current
		current = current.get_parent()
	return null


func _get_object_float(object: Object, property_name: StringName, fallback: float = 0.0) -> float:
	if not object:
		return fallback
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == str(property_name):
			return maxf(float(object.get(str(property_name))), 0.0)
	return fallback


func _get_forest_region_and_cell(world_position: Vector3) -> Dictionary:
	for region: Node in _get_forest_regions():
		if not region.has_method("world_to_cell"):
			continue
		var cell_variant: Variant = region.call("world_to_cell", world_position)
		if not (cell_variant is Vector2i):
			continue
		var cell := cell_variant as Vector2i
		var has_resource := false
		if region.has_method("is_cow_cell") and bool(region.call("is_cow_cell", cell)):
			has_resource = true
		if region.has_method("is_tree_cell") and bool(region.call("is_tree_cell", cell)):
			has_resource = true
		if has_resource:
			return {
				"region": region,
				"cell": cell,
			}
	return {}


func _get_forest_regions() -> Array[Node]:
	var regions: Array[Node] = []
	for region_path: NodePath in forest_region_paths:
		if region_path.is_empty():
			continue
		var region := get_node_or_null(region_path)
		if region:
			regions.append(region)
	if not regions.is_empty():
		return regions

	var root := get_parent()
	if not root:
		root = get_tree().current_scene if get_tree() else null
	if root:
		_collect_forest_regions(root, regions)
	return regions


func _collect_forest_regions(node: Node, regions: Array[Node]) -> void:
	if node.has_method("harvest_wood_cell") and (node.has_method("world_to_cell") or node.has_method("get_tree_cells")):
		regions.append(node)
	for child: Node in node.get_children():
		_collect_forest_regions(child, regions)


func _is_pointer_over_ui() -> bool:
	var viewport := get_viewport()
	return viewport != null and viewport.gui_get_hovered_control() != null


func _ensure_context_menu() -> PopupMenu:
	if _context_menu and is_instance_valid(_context_menu):
		return _context_menu
	_context_menu = PopupMenu.new()
	_context_menu.name = "TroopContextMenu"
	_context_menu.hide_on_item_selection = true
	add_child(_context_menu)
	_context_menu.owner = null
	if not _context_menu.id_pressed.is_connected(_on_context_menu_id_pressed):
		_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	return _context_menu


func _get_troop_drawer() -> Node:
	return get_node_or_null(troop_drawer_path)


func _get_background_jobs_debug_panel() -> Node:
	return get_node_or_null(background_jobs_debug_panel_path)


func _update_background_jobs_debug_panel(troop: Node) -> void:
	var panel := _get_background_jobs_debug_panel()
	if panel and panel.has_method("set_selected_troop"):
		panel.call("set_selected_troop", troop)


func _bind_drawer_signals() -> void:
	var drawer := _get_troop_drawer()
	if not drawer:
		return
	var food_callable := Callable(self, "_on_collect_food_requested")
	if drawer.has_signal(&"collect_food_requested") and not drawer.is_connected(&"collect_food_requested", food_callable):
		drawer.connect(&"collect_food_requested", food_callable)
	var wood_callable := Callable(self, "_on_collect_wood_requested")
	if drawer.has_signal(&"collect_wood_requested") and not drawer.is_connected(&"collect_wood_requested", wood_callable):
		drawer.connect(&"collect_wood_requested", wood_callable)


func _on_collect_food_requested(troop: Node, amount_kg: float) -> void:
	if not _is_commandable_troop(troop):
		return
	_select_troop(troop)
	_clear_food_collection_targeting()
	_issue_nearest_food_collection(troop, amount_kg)
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _on_collect_wood_requested(troop: Node, soldier_count: int) -> void:
	if not _is_commandable_troop(troop):
		return
	_select_troop(troop)
	_issue_nearest_wood_collection(troop, soldier_count)
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _issue_nearest_food_collection(troop: Node, amount_kg: float) -> bool:
	if not is_instance_valid(troop) or not troop.has_method("begin_food_collection"):
		return false

	var village := _get_nearest_village_region(troop)
	if not village:
		return false
	return bool(troop.call("begin_food_collection", village, maxf(amount_kg, 0.0)))


func _issue_nearest_wood_collection(troop: Node, soldier_count: int) -> bool:
	if not is_instance_valid(troop) or not troop.has_method("begin_wood_collection"):
		return false

	var target := _get_nearest_tree_target(troop)
	if target.is_empty():
		return false

	var region := target.get("region") as Node
	var cell: Vector2i = target.get("cell", Vector2i.ZERO)
	if not region:
		return false
	return bool(troop.call("begin_wood_collection", region, cell, maxi(soldier_count, 1)))


func _get_nearest_village_region(troop: Node) -> Node:
	var origin := _get_node_world_position(troop)
	var best_village: Node
	var best_distance_squared := INF
	for village: Node in _get_village_regions():
		if not village.has_method("withdraw_food_kg"):
			continue
		if _get_village_food_available_kg(village) <= 0.0:
			continue
		var position := _get_village_storage_position(village)
		var distance_squared := origin.distance_squared_to(position)
		if distance_squared < best_distance_squared:
			best_village = village
			best_distance_squared = distance_squared
	return best_village


func _get_nearest_tree_target(troop: Node) -> Dictionary:
	var origin := _get_node_world_position(troop)
	var best_target := {}
	var best_distance_squared := INF
	for region: Node in _get_forest_regions():
		if not region.has_method("is_tree_cell"):
			continue
		for cell: Vector2i in _get_region_tree_cells(region):
			if not bool(region.call("is_tree_cell", cell)):
				continue
			var position := _get_forest_cell_world_position(region, cell)
			var distance_squared := origin.distance_squared_to(position)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_target = {
					"region": region,
					"cell": cell,
				}
	return best_target


func _get_region_tree_cells(region: Node) -> Array[Vector2i]:
	if region.has_method("get_tree_cells"):
		var cells_variant: Variant = region.call("get_tree_cells")
		if cells_variant is Array:
			return _variant_array_to_vector2i_array(cells_variant as Array)

	var raw_cells: Variant = region.get("forest_cells")
	if raw_cells is Array:
		var cells: Array[Vector2i] = []
		for cell_variant: Variant in raw_cells as Array:
			if cell_variant is Vector2i and bool(region.call("is_tree_cell", cell_variant)):
				cells.append(cell_variant as Vector2i)
		return cells
	return []


func _variant_array_to_vector2i_array(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value: Variant in values:
		if value is Vector2i:
			result.append(value as Vector2i)
	return result


func _get_village_regions() -> Array[Node]:
	var regions: Array[Node] = []
	for region_path: NodePath in village_region_paths:
		if region_path.is_empty():
			continue
		var region := get_node_or_null(region_path)
		if region and not regions.has(region):
			regions.append(region)
	if not regions.is_empty():
		return regions

	var root := get_parent()
	if not root:
		root = get_tree().current_scene if get_tree() else null
	if root:
		_collect_village_regions(root, regions)
	return regions


func _collect_village_regions(node: Node, regions: Array[Node]) -> void:
	if node.has_method("withdraw_food_kg") and not regions.has(node):
		regions.append(node)
	for child: Node in node.get_children():
		_collect_village_regions(child, regions)


func _get_village_food_available_kg(village: Node) -> float:
	if village.has_method("get_village_storage_summary"):
		var storage_summary: Dictionary = village.call("get_village_storage_summary") as Dictionary
		return maxf(float(storage_summary.get("storage_food_kg", 0.0)), 0.0)
	if village.has_method("get_village_food_summary"):
		var food_summary: Dictionary = village.call("get_village_food_summary") as Dictionary
		return maxf(float(food_summary.get("storage_food_kg", food_summary.get("total_reserve_kg", 0.0))), 0.0)
	return 0.0


func _get_village_storage_position(village: Node) -> Vector3:
	if village.has_method("get_village_storage_world_position"):
		var position_variant: Variant = village.call("get_village_storage_world_position")
		if position_variant is Vector3:
			return position_variant as Vector3
	return _get_node_world_position(village)


func _get_forest_cell_world_position(region: Node, cell: Vector2i) -> Vector3:
	if region.has_method("get_cell_world_position"):
		var position_variant: Variant = region.call("get_cell_world_position", cell)
		if position_variant is Vector3:
			return position_variant as Vector3
	if region.has_method("cell_to_local_center") and region is Node3D:
		var local_variant: Variant = region.call("cell_to_local_center", cell)
		if local_variant is Vector3:
			return (region as Node3D).to_global(local_variant as Vector3)
	return _get_node_world_position(region)


func _get_node_world_position(node: Node) -> Vector3:
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if not object:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false


func _clear_food_collection_targeting() -> void:
	_food_collection_troop = null
	_food_collection_amount_kg = 0.0


func _get_camera() -> Camera3D:
	if not camera_path.is_empty():
		var node := get_node_or_null(camera_path)
		if node is Camera3D:
			return node as Camera3D

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null
