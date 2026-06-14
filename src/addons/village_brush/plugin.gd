@tool
extends EditorPlugin

const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")
const VillageTypeDataScript = preload("res://addons/village_brush/village_type_data.gd")
const WallTypeDataScript = preload("res://addons/village_brush/wall_type_data.gd")
const VillageRegionGizmo = preload("res://addons/village_brush/village_region_gizmo.gd")
const DockScene = preload("res://addons/village_brush/dock/village_brush_dock.tscn")
const VillageIcon = preload("res://addons/village_brush/icons/village_region.svg")

const RAY_LENGTH := 8192.0

var _selection: EditorSelection
var _dock
var _dock_added := false
var _gizmo_plugin
var _region: VillageRegionScript

var _brush_mode := VillageRegionScript.PaintMode.HOUSE
var _brush_radius := 0
var _has_hover_cell := false
var _hover_cell := Vector2i.ZERO
var _preview_active := false
var _preview_region_id := 0
var _preview_cell := Vector2i.ZERO
var _preview_mode := VillageRegionScript.PaintMode.HOUSE
var _preview_radius := -1
var _preview_cells: Array[Vector2i] = []

var _stroke_active := false
var _stroke_mode := VillageRegionScript.PaintMode.HOUSE
var _stroke_radius := 0
var _stroke_centers: Dictionary = {}
var _stroke_before_house: Array[Vector2i] = []
var _stroke_before_field: Array[Vector2i] = []
var _stroke_before_road: Array[Vector2i] = []


func _enter_tree() -> void:
	add_custom_type("VillageRegion", "Node3D", VillageRegionScript, VillageIcon)
	add_custom_type("VillageTypeData", "Resource", VillageTypeDataScript, VillageIcon)
	add_custom_type("WallTypeData", "Resource", WallTypeDataScript, VillageIcon)

	_gizmo_plugin = VillageRegionGizmo.new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_dock = DockScene.instantiate()
	_dock.name = "Village Brush"
	_dock.village_type_changed.connect(_on_dock_village_type_changed)
	_dock.wall_type_changed.connect(_on_dock_wall_type_changed)
	_dock.brush_mode_changed.connect(_on_dock_brush_mode_changed)
	_dock.brush_radius_changed.connect(_on_dock_brush_radius_changed)
	_dock.clear_requested.connect(_on_dock_clear_requested)
	_show_dock()

	_selection = get_editor_interface().get_selection()
	_selection.selection_changed.connect(_on_selection_changed)
	scene_changed.connect(_on_scene_changed)
	scene_closed.connect(_on_scene_closed)
	_on_selection_changed()


func _exit_tree() -> void:
	if _stroke_active:
		_finish_stroke()

	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if scene_closed.is_connected(_on_scene_closed):
		scene_closed.disconnect(_on_scene_closed)
	if is_instance_valid(_selection) and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)

	_hide_dock()
	if is_instance_valid(_dock):
		_dock.queue_free()
		_dock = null

	if is_instance_valid(_gizmo_plugin):
		_clear_brush_preview()
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null

	remove_custom_type("VillageRegion")
	remove_custom_type("VillageTypeData")
	remove_custom_type("WallTypeData")


func _handles(object: Object) -> bool:
	return object is VillageRegionScript


func _edit(object: Object) -> void:
	if object is VillageRegionScript:
		_set_region(object)
	else:
		_set_region(null)


func _make_visible(visible: bool) -> void:
	if visible or is_instance_valid(_dock):
		_show_dock()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> AfterGUIInput:
	if not is_instance_valid(_region):
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		if _is_camera_navigation_input():
			_clear_brush_preview()
			return AFTER_GUI_INPUT_PASS

		var motion_hit_position: Variant = _get_hit_position(camera, _get_event_mouse_position(camera, event.position))
		if motion_hit_position == null:
			_clear_brush_preview()
			return AFTER_GUI_INPUT_PASS

		_update_brush_preview_at_position(motion_hit_position)
		if _stroke_active:
			_paint_at_cell(_hover_cell)
			return AFTER_GUI_INPUT_STOP

		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_camera_navigation_input():
				return AFTER_GUI_INPUT_PASS

			var hit_position: Variant = _get_hit_position(camera, _get_event_mouse_position(camera, event.position))
			if hit_position == null:
				_clear_brush_preview()
				return AFTER_GUI_INPUT_PASS

			_update_brush_preview_at_position(hit_position)
			_start_stroke()
			_paint_at_cell(_hover_cell)
			return AFTER_GUI_INPUT_STOP

		if _stroke_active:
			_finish_stroke()
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _on_selection_changed() -> void:
	if not is_instance_valid(_selection):
		return

	var selected_nodes := _selection.get_selected_nodes()
	for node: Node in selected_nodes:
		if node is VillageRegionScript:
			_set_region(node)
			return

	_set_region(null)


func _on_scene_changed(_scene_root: Node) -> void:
	_set_region(null)


func _on_scene_closed(_filepath: String) -> void:
	_set_region(null)


func _set_region(region: VillageRegionScript) -> void:
	if _stroke_active:
		_finish_stroke()

	_clear_brush_preview()

	if _region == region:
		_sync_dock_region(_region)
		return

	_region = region
	if is_instance_valid(_region):
		_show_dock()
		_sync_dock_region(_region)
		if Engine.is_editor_hint() and _region.is_inside_tree():
			_region.update_gizmos()
	else:
		_sync_dock_region(null)
		_show_dock()


func _show_dock() -> void:
	if not is_instance_valid(_dock):
		_dock_added = false
		return
	if not _dock_added:
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
		_dock_added = true
	_dock.show()


func _hide_dock() -> void:
	if _dock_added and is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock_added = false
	elif not is_instance_valid(_dock):
		_dock_added = false


func _sync_dock_region(region: VillageRegionScript) -> void:
	if is_instance_valid(_dock):
		_dock.set_region(region)


func _on_dock_village_type_changed(resource: Resource) -> void:
	if not is_instance_valid(_region) or _region.village_type == resource:
		return

	var undo := get_undo_redo()
	undo.create_action("Set Village Type")
	undo.add_do_property(_region, "village_type", resource)
	undo.add_do_method(self, "_sync_dock_region", _region)
	undo.add_undo_property(_region, "village_type", _region.village_type)
	undo.add_undo_method(self, "_sync_dock_region", _region)
	undo.commit_action()


func _on_dock_wall_type_changed(resource: Resource) -> void:
	if not is_instance_valid(_region) or _region.wall_type == resource:
		return

	var undo := get_undo_redo()
	undo.create_action("Set Wall Type")
	undo.add_do_property(_region, "wall_type", resource)
	undo.add_do_method(self, "_sync_dock_region", _region)
	undo.add_undo_property(_region, "wall_type", _region.wall_type)
	undo.add_undo_method(self, "_sync_dock_region", _region)
	undo.commit_action()


func _on_dock_brush_mode_changed(mode: int) -> void:
	if _brush_mode == mode:
		return
	_brush_mode = mode
	_refresh_brush_preview()


func _on_dock_brush_radius_changed(radius: int) -> void:
	var clamped_radius := maxi(radius, 0)
	if _brush_radius == clamped_radius:
		return
	_brush_radius = clamped_radius
	_refresh_brush_preview()


func _on_dock_clear_requested(target: int) -> void:
	if not is_instance_valid(_region):
		return

	var before_house := _copy_cells(_region.house_cells)
	var before_field := _copy_cells(_region.field_cells)
	var before_road := _copy_cells(_region.road_cells)
	var after_house := _copy_cells(before_house)
	var after_field := _copy_cells(before_field)
	var after_road := _copy_cells(before_road)
	var action_name := "Clear Village Cells"

	match target:
		0:
			after_house.clear()
			action_name = "Clear Village House Cells"
		1:
			after_field.clear()
			action_name = "Clear Village Field Cells"
		2:
			after_road.clear()
			action_name = "Clear Village Road Cells"
		3:
			after_house.clear()
			after_field.clear()
			after_road.clear()

	if before_house == after_house and before_field == after_field and before_road == after_road:
		return

	_commit_cells_action(action_name, before_house, before_field, before_road, after_house, after_field, after_road)


func _start_stroke() -> void:
	_stroke_active = true
	_stroke_mode = _brush_mode
	_stroke_radius = _brush_radius
	_stroke_centers.clear()
	_stroke_before_house = _copy_cells(_region.house_cells)
	_stroke_before_field = _copy_cells(_region.field_cells)
	_stroke_before_road = _copy_cells(_region.road_cells)


func _finish_stroke() -> void:
	if not _stroke_active:
		return

	_stroke_active = false
	_stroke_centers.clear()

	if not is_instance_valid(_region):
		return

	var after_house := _copy_cells(_region.house_cells)
	var after_field := _copy_cells(_region.field_cells)
	var after_road := _copy_cells(_region.road_cells)
	if _stroke_before_house == after_house and _stroke_before_field == after_field and _stroke_before_road == after_road:
		return

	_commit_cells_action("Paint Village Cells", _stroke_before_house, _stroke_before_field, _stroke_before_road, after_house, after_field, after_road)


func _update_brush_preview_at_position(world_position: Vector3) -> void:
	if not is_instance_valid(_region):
		return

	var hover_cell := _region.world_to_cell(world_position)
	_hover_cell = hover_cell
	_has_hover_cell = true
	_refresh_brush_preview()


func _refresh_brush_preview() -> void:
	if not is_instance_valid(_region) or not _has_hover_cell:
		_clear_brush_preview()
		return

	var mode := _stroke_mode if _stroke_active else _brush_mode
	var radius := _stroke_radius if _stroke_active else _brush_radius
	var cells := _get_brush_cells(_hover_cell, radius)
	var region_id := _region.get_instance_id()
	if (
		_preview_active
		and _preview_region_id == region_id
		and _preview_cell == _hover_cell
		and _preview_mode == mode
		and _preview_radius == radius
		and _cells_equal(_preview_cells, cells)
	):
		return

	_preview_active = true
	_preview_region_id = region_id
	_preview_cell = _hover_cell
	_preview_mode = mode
	_preview_radius = radius
	_preview_cells = _copy_cells(cells)

	var preview_changed := true
	if is_instance_valid(_gizmo_plugin) and _gizmo_plugin.has_method("set_brush_preview"):
		preview_changed = bool(_gizmo_plugin.call("set_brush_preview", _region, cells, mode, true))
	if preview_changed and _region.is_inside_tree():
		_region.update_gizmos()


func _clear_brush_preview() -> void:
	var had_preview := _preview_active or _has_hover_cell
	_preview_active = false
	_preview_region_id = 0
	_preview_radius = -1
	_preview_cells.clear()

	var preview_changed := false
	if is_instance_valid(_gizmo_plugin) and _gizmo_plugin.has_method("clear_brush_preview"):
		preview_changed = bool(_gizmo_plugin.call("clear_brush_preview", _region))
	if (had_preview or preview_changed) and is_instance_valid(_region) and _region.is_inside_tree():
		_region.update_gizmos()
	_has_hover_cell = false


func _paint_at_cell(center_cell: Vector2i) -> void:
	if not is_instance_valid(_region):
		return

	if _stroke_centers.has(center_cell):
		return
	_stroke_centers[center_cell] = true

	var cells := _get_brush_cells(center_cell, _stroke_radius)
	_region.paint_cells(cells, _stroke_mode)


func _get_brush_cells(center_cell: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var clamped_radius := maxi(radius, 0)
	var radius_squared := clamped_radius * clamped_radius

	for x: int in range(center_cell.x - clamped_radius, center_cell.x + clamped_radius + 1):
		for y: int in range(center_cell.y - clamped_radius, center_cell.y + clamped_radius + 1):
			var offset := Vector2i(x - center_cell.x, y - center_cell.y)
			if offset.length_squared() <= radius_squared:
				cells.append(Vector2i(x, y))

	return cells


func _commit_cells_action(
	action_name: String,
	before_house: Array[Vector2i],
	before_field: Array[Vector2i],
	before_road: Array[Vector2i],
	after_house: Array[Vector2i],
	after_field: Array[Vector2i],
	after_road: Array[Vector2i]
) -> void:
	var undo := get_undo_redo()
	undo.create_action(action_name)
	undo.add_do_method(_region, "set_cell_arrays", after_house, after_field, after_road)
	undo.add_undo_method(_region, "set_cell_arrays", before_house, before_field, before_road)
	undo.commit_action()


func _get_hit_position(camera: Camera3D, mouse_position: Vector2) -> Variant:
	var ray_from := camera.project_ray_origin(mouse_position)
	var ray_dir := camera.project_ray_normal(mouse_position)
	var terrain := _get_terrain_node()
	if not is_instance_valid(terrain):
		return null

	if terrain.has_method("get_intersection"):
		if terrain.has_method("set_camera"):
			terrain.call("set_camera", camera)
		var terrain_hit: Variant = terrain.call("get_intersection", ray_from, ray_dir, true)
		if terrain_hit is Vector3 and _is_valid_intersection(terrain_hit):
			return terrain_hit

	var world := _region.get_world_3d() if is_instance_valid(_region) else camera.get_world_3d()
	if not world:
		return null

	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * RAY_LENGTH)
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	if not _ray_result_matches_terrain(result, terrain):
		return null

	return result.position


func _get_terrain_node() -> Node3D:
	if not is_instance_valid(_region) or _region.terrain_path.is_empty():
		return null

	var terrain := _region.get_node_or_null(_region.terrain_path)
	if terrain is Node3D:
		return terrain
	return null


func _ray_result_matches_terrain(result: Dictionary, terrain: Node3D) -> bool:
	var collider: Variant = result.get("collider")
	if collider == terrain:
		return true
	if collider is Node:
		var node := collider as Node
		return terrain.is_ancestor_of(node) or node.is_ancestor_of(terrain)
	return false


func _get_event_mouse_position(camera: Camera3D, fallback_position: Vector2) -> Vector2:
	var camera_parent := camera.get_parent()
	if not camera_parent:
		return fallback_position

	var viewport_container := camera_parent.get_parent()
	if viewport_container is SubViewportContainer:
		var mouse_position: Vector2 = viewport_container.get_local_mouse_position()
		return mouse_position / float(viewport_container.stretch_shrink) if viewport_container.stretch_shrink > 1 else mouse_position

	return fallback_position


func _is_valid_intersection(position: Vector3) -> bool:
	if is_nan(position.x) or is_nan(position.y) or is_nan(position.z):
		return false
	return absf(position.x) < 1.0e20 and absf(position.y) < 1.0e20 and absf(position.z) < 1.0e20


func _is_camera_navigation_input() -> bool:
	return (
		Input.is_key_pressed(KEY_ALT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)


func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copied: Array[Vector2i] = []
	for cell: Vector2i in cells:
		copied.append(cell)
	return copied


func _cells_equal(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false

	for index: int in range(a.size()):
		if a[index] != b[index]:
			return false
	return true
