extends Node
class_name TroopSelectionController

const SELECTABLE_TYPE_META := &"troop_selectable_type"
const SELECTABLE_NODE_PATH_META := &"troop_node_path"
const SELECTABLE_TROOP_TYPE := &"troop"
const SELECTABLE_CAMP_TYPE := &"camp"
const VILLAGE_SELECTABLE_TYPE_META := &"village_selectable_type"
const VILLAGE_SELECTABLE_REGION_PATH_META := &"village_region_path"

@export var troop_drawer_path: NodePath = NodePath("../TroopManagementDrawer")
@export var camera_path: NodePath = NodePath("")
@export var forest_region_paths: Array[NodePath] = []
@export var village_region_paths: Array[NodePath] = []
@export_range(1.0, 20000.0, 1.0, "or_greater") var max_pick_distance: float = 5000.0
@export_range(1.0, 64.0, 0.5, "or_greater") var command_click_drag_threshold: float = 6.0
@export_flags_3d_physics var troop_collision_mask: int = 1 << 5
@export_flags_3d_physics var destination_collision_mask: int = 0xFFFFFFFF
@export_flags_3d_physics var village_selection_collision_mask: int = 1

var _selected_troop: Node
var _pending_select_position := Vector2(INF, INF)
var _pending_command_position := Vector2(INF, INF)
var _pending_food_select_position := Vector2(INF, INF)
var _right_press_position := Vector2(INF, INF)
var _food_collection_troop: Node
var _food_collection_amount_kg := 0.0


func _ready() -> void:
	_bind_drawer_signals()


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

	if is_finite(_pending_food_select_position.x):
		var food_position := _pending_food_select_position
		_pending_food_select_position = Vector2(INF, INF)
		_issue_food_collection(food_position)


func _exit_tree() -> void:
	_select_troop(null)


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
	if not is_instance_valid(troop):
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


func _try_issue_forest_logistics(world_position: Vector3) -> bool:
	if not _selected_troop:
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
	if troop and not _is_commandable_troop(troop):
		troop = null
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
		if _is_commandable_troop(troop):
			return troop

	var current := selectable
	while current:
		if _is_commandable_troop(current):
			return current
		current = current.get_parent()
	return null


func _is_commandable_troop(troop: Node) -> bool:
	if not troop or not troop.has_method("set_move_destination"):
		return false
	var controllable: Variant = troop.get("controllable")
	if controllable is bool:
		return bool(controllable)
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


func _get_troop_drawer() -> Node:
	return get_node_or_null(troop_drawer_path)


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
	if not is_instance_valid(troop):
		return
	_select_troop(troop)
	_clear_food_collection_targeting()
	_issue_nearest_food_collection(troop, amount_kg)
	var drawer := _get_troop_drawer()
	if drawer and drawer.has_method("refresh"):
		drawer.call("refresh")


func _on_collect_wood_requested(troop: Node, soldier_count: int) -> void:
	if not is_instance_valid(troop):
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
