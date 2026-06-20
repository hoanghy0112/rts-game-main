extends Node
class_name VillageSelectionController

const SELECTABLE_TYPE_META := &"village_selectable_type"
const SELECTABLE_REGION_PATH_META := &"village_region_path"
const SELECTABLE_FLAG_TYPE := &"flag"
const SELECTABLE_VILLAGE_TYPE := &"village"

@export var village_region_path: NodePath = NodePath("../VillageRegion")
@export var info_drawer_path: NodePath = NodePath("../VillageInfoDrawer")
@export var camera_path: NodePath = NodePath("")
@export_range(1.0, 20000.0, 1.0, "or_greater") var max_pick_distance: float = 5000.0
@export_flags_3d_physics var selection_collision_mask: int = 0xFFFFFFFF

var _pending_click_position := Vector2(INF, INF)
var _hovered_selectable: Node
var _hovered_region: Node


func _ready() -> void:
	var drawer := _get_info_drawer()
	var region := _get_village_region()
	if drawer and region and drawer.has_method("bind_to_village_region"):
		drawer.call("bind_to_village_region", region)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_pending_click_position = mouse_event.position


func _physics_process(_delta: float) -> void:
	_update_hovered_selectable()

	if not is_finite(_pending_click_position.x):
		return

	var click_position := _pending_click_position
	_pending_click_position = Vector2(INF, INF)
	_pick_selectable(click_position)


func _exit_tree() -> void:
	_set_hovered_selectable(null)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _pick_selectable(screen_position: Vector2) -> void:
	var selectable := _get_selectable_at(screen_position)
	if selectable:
		_open_selectable(selectable)


func _update_hovered_selectable() -> void:
	var viewport := get_viewport()
	if not viewport:
		_set_hovered_selectable(null)
		return
	if viewport.gui_get_hovered_control() != null:
		_set_hovered_selectable(null)
		return

	_set_hovered_selectable(_get_selectable_at(viewport.get_mouse_position()))


func _get_selectable_at(screen_position: Vector2) -> Node:
	var camera := _get_camera()
	if not camera:
		return null

	var world := camera.get_world_3d()
	if not world:
		return null

	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * max_pick_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = selection_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state := world.direct_space_state
	for _attempt: int in range(12):
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return

		var collider := result.get("collider") as Object
		var selectable := _find_selectable_node(collider)
		if selectable:
			return selectable

		var rid: RID = result.get("rid", RID())
		if rid.is_valid():
			query.exclude.append(rid)
		else:
			return null
	return null


func _set_hovered_selectable(selectable: Node) -> void:
	var next_region := _get_region_for_selectable(selectable)
	if _hovered_selectable == selectable and _hovered_region == next_region:
		return

	if _hovered_region != next_region:
		_set_region_hovered(_hovered_region, false)
		_set_region_hovered(next_region, true)
	_hovered_selectable = selectable
	_hovered_region = next_region
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if _hovered_selectable else Input.CURSOR_ARROW)


func _set_region_hovered(region: Node, hovered: bool) -> void:
	if region and region.has_method("set_village_hovered"):
		region.call("set_village_hovered", hovered)


func _get_region_for_selectable(selectable: Node) -> Node:
	if not selectable:
		return null

	var region_path: NodePath = selectable.get_meta(SELECTABLE_REGION_PATH_META, NodePath(""))
	if not region_path.is_empty():
		var region := get_node_or_null(region_path)
		if region:
			return region

	var current := selectable
	while current:
		if current is VillageRegion:
			return current
		current = current.get_parent()
	return null


func _find_selectable_node(object: Object) -> Node:
	if not (object is Node):
		return null

	var current := object as Node
	while current:
		if current.has_meta(SELECTABLE_TYPE_META):
			return current
		current = current.get_parent()
	return null


func _open_selectable(selectable: Node) -> void:
	var drawer := _get_info_drawer()
	if not drawer:
		return

	var selectable_type := StringName(selectable.get_meta(SELECTABLE_TYPE_META, &""))
	match selectable_type:
		SELECTABLE_FLAG_TYPE:
			if drawer.has_method("show_village_summary"):
				drawer.call("show_village_summary")
		SELECTABLE_VILLAGE_TYPE:
			if drawer.has_method("show_village_summary"):
				drawer.call("show_village_summary")


func _get_village_region() -> VillageRegion:
	var node := get_node_or_null(village_region_path)
	return node as VillageRegion if node is VillageRegion else null


func _get_info_drawer() -> Node:
	return get_node_or_null(info_drawer_path)


func _get_camera() -> Camera3D:
	if not camera_path.is_empty():
		var node := get_node_or_null(camera_path)
		if node is Camera3D:
			return node as Camera3D

	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null
