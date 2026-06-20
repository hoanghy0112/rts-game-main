extends Node
class_name TroopSelectionController

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"

@export var troop_drawer_path: NodePath = NodePath("../TroopManagementDrawer")
@export var camera_path: NodePath = NodePath("")
@export_range(1.0, 20000.0, 1.0, "or_greater") var max_pick_distance: float = 5000.0
@export_range(1.0, 64.0, 0.5, "or_greater") var command_click_drag_threshold: float = 6.0
@export_flags_3d_physics var troop_collision_mask: int = 1 << 5
@export_flags_3d_physics var destination_collision_mask: int = 0xFFFFFFFF

var _selected_troop: Node
var _pending_select_position := Vector2(INF, INF)
var _pending_command_position := Vector2(INF, INF)
var _right_press_position := Vector2(INF, INF)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)


func _physics_process(_delta: float) -> void:
	if is_finite(_pending_select_position.x):
		var select_position := _pending_select_position
		_pending_select_position = Vector2(INF, INF)
		_pick_troop(select_position)

	if is_finite(_pending_command_position.x):
		var command_position := _pending_command_position
		_pending_command_position = Vector2(INF, INF)
		_issue_move_command(command_position)


func _exit_tree() -> void:
	_select_troop(null)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if _is_pointer_over_ui():
		return

	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pending_select_position = event.position
		return

	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if event.pressed:
		_right_press_position = event.position
		return

	if not is_finite(_right_press_position.x):
		return
	var drag_distance := event.position.distance_to(_right_press_position)
	_right_press_position = Vector2(INF, INF)
	if drag_distance > command_click_drag_threshold:
		return
	if not _selected_troop:
		return

	_pending_command_position = event.position
	get_viewport().set_input_as_handled()


func _pick_troop(screen_position: Vector2) -> void:
	var troop := _get_troop_at(screen_position)
	_select_troop(troop)
	if troop:
		get_viewport().set_input_as_handled()


func _issue_move_command(screen_position: Vector2) -> void:
	if not _selected_troop:
		return
	var destination: Variant = _get_world_destination(screen_position)
	if destination == null:
		return
	if _selected_troop.has_method("set_move_destination"):
		_selected_troop.call("set_move_destination", destination as Vector3)
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _select_troop(troop: Node) -> void:
	if _selected_troop == troop:
		if troop:
			_show_drawer(troop)
		return

	if is_instance_valid(_selected_troop):
		if _selected_troop.has_method("set_selected"):
			_selected_troop.call("set_selected", false)

	_selected_troop = troop
	if is_instance_valid(_selected_troop):
		if _selected_troop.has_method("set_selected"):
			_selected_troop.call("set_selected", true)
		_show_drawer(_selected_troop)
	else:
		var drawer := _get_troop_drawer()
		if drawer and drawer.has_method("hide_drawer"):
			drawer.call("hide_drawer")


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
			return null

		var collider := result.get("collider") as Object
		var selectable := _find_selectable_node(collider)
		if selectable:
			return _get_troop_for_selectable(selectable)

		var rid: RID = result.get("rid", RID())
		if rid.is_valid():
			query.exclude.append(rid)
		else:
			return null
	return null


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
	if StringName(selectable.get_meta(SELECTABLE_TYPE_META, &"")) != SELECTABLE_TROOP_TYPE:
		return null

	var troop_path: NodePath = selectable.get_meta(SELECTABLE_NODE_PATH_META, NodePath(""))
	if not troop_path.is_empty():
		var troop := get_node_or_null(troop_path)
		if troop and troop.has_method("set_move_destination"):
			return troop

	var current := selectable
	while current:
		if current.has_method("set_move_destination"):
			return current
		current = current.get_parent()
	return null


func _is_pointer_over_ui() -> bool:
	var viewport := get_viewport()
	return viewport != null and viewport.gui_get_hovered_control() != null


func _get_troop_drawer() -> Node:
	return get_node_or_null(troop_drawer_path)


func _get_camera() -> Camera3D:
	if not camera_path.is_empty():
		var node := get_node_or_null(camera_path)
		if node is Camera3D:
			return node as Camera3D

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null
