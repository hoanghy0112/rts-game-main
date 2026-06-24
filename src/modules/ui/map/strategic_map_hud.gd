extends CanvasLayer
class_name StrategicMapHud

const MODE_MOVEMENT := &"movement"
const MODE_MILITARY := &"military"
const FLAG_RIVER := 1
const FLAG_STEEP_SLOPE := 2
const FLAG_FOREST := 4
const FLAG_ROAD := 8

class MapCanvas:
	extends Control

	var hud: Node
	var full_map := false

	func _draw() -> void:
		if hud and hud.has_method("_draw_map_canvas"):
			hud.call("_draw_map_canvas", self, full_map)

	func _gui_input(event: InputEvent) -> void:
		if hud and hud.has_method("_handle_map_input"):
			hud.call("_handle_map_input", self, full_map, event)

@export var movement_map: Resource:
	set(value):
		movement_map = value
		_request_redraw()
@export_file("*.res", "*.tres") var movement_map_path := "":
	set(value):
		movement_map_path = value
		if is_inside_tree():
			reload_movement_map()
@export_node_path("Camera3D") var camera_path: NodePath
@export_node_path("Node") var camera_rig_path: NodePath
@export var full_map_mode: StringName = MODE_MOVEMENT:
	set(value):
		full_map_mode = MODE_MILITARY if str(value) == str(MODE_MILITARY) else MODE_MOVEMENT
		_update_mode_buttons()
		_request_redraw()
@export_range(0.05, 2.0, 0.05, "or_greater") var refresh_interval_seconds: float = 0.35
@export_range(96.0, 420.0, 1.0, "or_greater") var minimap_size_px: float = 184.0

var _root: Control
var _minimap_panel: PanelContainer
var _minimap_canvas: MapCanvas
var _full_map_root: Control
var _full_map_canvas: MapCanvas
var _hover_label: Label
var _movement_button: Button
var _military_button: Button
var _open_button: Button
var _close_button: Button
var _refresh_remaining := 0.0
var _markers: Array[Dictionary] = []
var _hover_marker: Dictionary = {}


func _ready() -> void:
	layer = 20
	if not movement_map and not movement_map_path.is_empty():
		reload_movement_map(false)
	_build_ui()
	_refresh_markers()
	_request_redraw()


func _process(delta: float) -> void:
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = refresh_interval_seconds
	_refresh_markers()
	_request_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and is_full_map_open():
			set_full_map_open(false)
			get_viewport().set_input_as_handled()


func reload_movement_map(redraw: bool = true) -> void:
	if movement_map_path.is_empty() or not ResourceLoader.exists(movement_map_path):
		movement_map = null
		return
	movement_map = ResourceLoader.load(movement_map_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if redraw:
		_request_redraw()


func is_full_map_open() -> bool:
	return _full_map_root != null and _full_map_root.visible


func set_full_map_open(open: bool) -> void:
	if not _full_map_root:
		return
	_full_map_root.visible = open
	_hover_marker.clear()
	_update_hover_label()
	_request_redraw()


func toggle_full_map() -> void:
	set_full_map_open(not is_full_map_open())


func set_map_mode(mode: StringName) -> void:
	full_map_mode = mode


func get_marker_count() -> int:
	return _markers.size()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_minimap_panel = PanelContainer.new()
	_minimap_panel.name = "MinimapPanel"
	_minimap_panel.custom_minimum_size = Vector2(minimap_size_px, minimap_size_px + 34.0)
	_minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap_panel.offset_left = -minimap_size_px - 18.0
	_minimap_panel.offset_top = -minimap_size_px - 56.0
	_minimap_panel.offset_right = -18.0
	_minimap_panel.offset_bottom = -18.0
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.052, 0.058, 0.88)))
	_root.add_child(_minimap_panel)

	var minimap_margin := MarginContainer.new()
	minimap_margin.add_theme_constant_override("margin_left", 8)
	minimap_margin.add_theme_constant_override("margin_top", 8)
	minimap_margin.add_theme_constant_override("margin_right", 8)
	minimap_margin.add_theme_constant_override("margin_bottom", 8)
	_minimap_panel.add_child(minimap_margin)

	var minimap_rows := VBoxContainer.new()
	minimap_rows.add_theme_constant_override("separation", 6)
	minimap_margin.add_child(minimap_rows)

	_minimap_canvas = MapCanvas.new()
	_minimap_canvas.name = "MinimapCanvas"
	_minimap_canvas.hud = self
	_minimap_canvas.full_map = false
	_minimap_canvas.custom_minimum_size = Vector2(minimap_size_px - 16.0, minimap_size_px - 16.0)
	_minimap_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_rows.add_child(_minimap_canvas)

	_open_button = Button.new()
	_open_button.name = "OpenFullMapButton"
	_open_button.text = "Full Map"
	_open_button.pressed.connect(toggle_full_map)
	minimap_rows.add_child(_open_button)

	_build_full_map_ui()


func _build_full_map_ui() -> void:
	_full_map_root = Control.new()
	_full_map_root.name = "FullMapRoot"
	_full_map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_map_root.visible = false
	_full_map_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_full_map_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.012, 0.014, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_root.add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "FullMapPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 42.0
	panel.offset_top = 34.0
	panel.offset_right = -42.0
	panel.offset_bottom = -34.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.045, 0.048, 0.94)))
	_full_map_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 9)
	margin.add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)

	var title := Label.new()
	title.text = "Strategic Map"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.94, 0.98, 0.95, 1.0))
	top.add_child(title)

	_movement_button = Button.new()
	_movement_button.text = "Movement"
	_movement_button.toggle_mode = true
	_movement_button.pressed.connect(func(): set_map_mode(MODE_MOVEMENT))
	top.add_child(_movement_button)

	_military_button = Button.new()
	_military_button.text = "Military"
	_military_button.toggle_mode = true
	_military_button.pressed.connect(func(): set_map_mode(MODE_MILITARY))
	top.add_child(_military_button)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): set_full_map_open(false))
	top.add_child(_close_button)

	_full_map_canvas = MapCanvas.new()
	_full_map_canvas.name = "FullMapCanvas"
	_full_map_canvas.hud = self
	_full_map_canvas.full_map = true
	_full_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_full_map_canvas.custom_minimum_size = Vector2(640, 420)
	_full_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	rows.add_child(_full_map_canvas)

	_hover_label = Label.new()
	_hover_label.name = "HoverStatsLabel"
	_hover_label.text = ""
	_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_label.add_theme_color_override("font_color", Color(0.84, 0.91, 0.88, 1.0))
	rows.add_child(_hover_label)
	_update_mode_buttons()


func _draw_map_canvas(canvas: Control, full_map: bool) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	canvas.draw_rect(rect, Color(0.025, 0.034, 0.034, 1.0), true)
	var world_rect := _get_world_rect()
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		canvas.draw_rect(rect.grow(-8.0), Color(0.18, 0.2, 0.18, 0.35), false, 1.0)
		return
	if not full_map or full_map_mode == MODE_MOVEMENT:
		_draw_movement_cells(canvas, rect, world_rect, full_map)
	else:
		_draw_military_background(canvas, rect)
	_draw_markers(canvas, rect, world_rect, full_map)
	_draw_camera_rect(canvas, rect, world_rect)
	canvas.draw_rect(rect, Color(0.78, 0.84, 0.82, 0.28), false, 1.0)


func _handle_map_input(canvas: Control, full_map: bool, event: InputEvent) -> void:
	var world_rect := _get_world_rect()
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return
	if full_map and event is InputEventMouseMotion:
		var mouse := (event as InputEventMouseMotion).position
		_hover_marker = _find_hover_marker(canvas, mouse, world_rect)
		_update_hover_label()
		canvas.queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var world := _canvas_to_world(button.position, Rect2(Vector2.ZERO, canvas.size), world_rect)
			_jump_camera_to(world)
			get_viewport().set_input_as_handled()


func _draw_movement_cells(canvas: Control, rect: Rect2, world_rect: Rect2, full_map: bool) -> void:
	var width := _get_map_width()
	var height := _get_map_height()
	if width <= 0 or height <= 0:
		return
	var max_samples := 190 if full_map else 95
	var step := maxi(ceili(float(maxi(width, height)) / float(max_samples)), 1)
	var cell_world_size := _get_map_cell_size()
	var speed_array: PackedFloat32Array = movement_map.get("speed_multipliers") as PackedFloat32Array
	var flag_array: PackedByteArray = movement_map.get("flags") as PackedByteArray
	for y: int in range(0, height, step):
		for x: int in range(0, width, step):
			var index := y * width + x
			var speed := speed_array[index] if index < speed_array.size() else 0.0
			var flags := int(flag_array[index]) if index < flag_array.size() else 0
			var top_left := _world_to_canvas(_cell_world_top_left(x, y), rect, world_rect)
			var bottom_right := _world_to_canvas(_cell_world_top_left(x + step, y + step), rect, world_rect)
			var cell_rect := Rect2(top_left, bottom_right - top_left).abs()
			canvas.draw_rect(cell_rect.grow(0.3), _movement_color(speed, flags), true)


func _draw_military_background(canvas: Control, rect: Rect2) -> void:
	canvas.draw_rect(rect, Color(0.045, 0.055, 0.052, 1.0), true)
	var spacing := 36.0
	var line_color := Color(0.32, 0.38, 0.34, 0.12)
	var x := 0.0
	while x < rect.size.x:
		canvas.draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), line_color, 1.0)
		x += spacing
	var y := 0.0
	while y < rect.size.y:
		canvas.draw_line(Vector2(0.0, y), Vector2(rect.size.x, y), line_color, 1.0)
		y += spacing


func _draw_markers(canvas: Control, rect: Rect2, world_rect: Rect2, full_map: bool) -> void:
	for marker: Dictionary in _markers:
		var world_position: Vector3 = marker.get("position", Vector3.ZERO)
		var point := _world_to_canvas(Vector2(world_position.x, world_position.z), rect, world_rect)
		var marker_type := str(marker.get("type", ""))
		var color: Color = marker.get("color", Color.WHITE)
		var radius := 3.5 if not full_map else 5.5
		match marker_type:
			"village":
				canvas.draw_circle(point, radius + 2.0, Color(0.12, 0.18, 0.11, 0.95))
				canvas.draw_circle(point, radius, Color(0.62, 0.88, 0.44, 1.0))
			"camp":
				canvas.draw_rect(Rect2(point - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color, true)
			"troop":
				var triangle := PackedVector2Array([
					point + Vector2(0.0, -radius - 2.0),
					point + Vector2(radius + 2.0, radius + 2.0),
					point + Vector2(-radius - 2.0, radius + 2.0),
				])
				canvas.draw_colored_polygon(triangle, color)
			_:
				canvas.draw_circle(point, radius, color)
		if full_map and marker == _hover_marker:
			canvas.draw_arc(point, radius + 7.0, 0.0, TAU, 36, Color(1.0, 0.92, 0.38, 0.55), 2.0)


func _draw_camera_rect(canvas: Control, rect: Rect2, world_rect: Rect2) -> void:
	var camera := _get_camera()
	if not camera:
		return
	var center := Vector2(camera.global_position.x, camera.global_position.z)
	var size_world := maxf(camera.global_position.y, 24.0) * 1.8
	var a := _world_to_canvas(center - Vector2(size_world, size_world), rect, world_rect)
	var b := _world_to_canvas(center + Vector2(size_world, size_world), rect, world_rect)
	canvas.draw_rect(Rect2(a, b - a).abs(), Color(1.0, 0.95, 0.58, 0.72), false, 1.5)


func _refresh_markers() -> void:
	_markers.clear()
	var root := get_tree().current_scene if get_tree() else get_parent()
	if not root:
		root = get_tree().root if get_tree() else null
	_collect_village_markers(root)
	_collect_camp_markers()
	_collect_troop_markers()


func _collect_village_markers(root: Node) -> void:
	if not root:
		return
	if root.has_method("get_village_food_summary") and root is Node3D:
		var summary: Dictionary = root.call("get_village_food_summary") as Dictionary
		var position: Vector3 = summary.get("storage_world_position", (root as Node3D).global_position)
		_markers.append({
			"type": &"village",
			"name": root.name,
			"position": position,
			"summary": summary,
			"color": Color(0.62, 0.88, 0.44, 1.0),
		})
	for child: Node in root.get_children():
		_collect_village_markers(child)


func _collect_camp_markers() -> void:
	if not get_tree():
		return
	for camp: Node in get_tree().get_nodes_in_group(&"camps"):
		if not (camp is Node3D):
			continue
		var summary := {}
		if camp.has_method("get_management_summary"):
			summary = camp.call("get_management_summary") as Dictionary
		_markers.append({
			"type": &"camp",
			"name": String(summary.get("display_name", camp.name)),
			"position": (camp as Node3D).global_position,
			"summary": summary,
			"color": _team_color(summary.get("team_id", "")),
		})


func _collect_troop_markers() -> void:
	if not get_tree():
		return
	for troop: Node in get_tree().get_nodes_in_group(&"troops"):
		if not (troop is Node3D) or not troop.has_method("get_troop_summary"):
			continue
		var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
		if bool(summary.get("defeated", false)):
			continue
		_markers.append({
			"type": &"troop",
			"name": String(summary.get("display_name", troop.name)),
			"position": (troop as Node3D).global_position,
			"summary": summary,
			"color": _team_color(summary.get("team_id", "")),
		})


func _find_hover_marker(canvas: Control, mouse: Vector2, world_rect: Rect2) -> Dictionary:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	var best: Dictionary = {}
	var best_distance := 16.0
	for marker: Dictionary in _markers:
		var world_position: Vector3 = marker.get("position", Vector3.ZERO)
		var point := _world_to_canvas(Vector2(world_position.x, world_position.z), rect, world_rect)
		var distance := point.distance_to(mouse)
		if distance < best_distance:
			best_distance = distance
			best = marker
	return best


func _update_hover_label() -> void:
	if not _hover_label:
		return
	if _hover_marker.is_empty():
		_hover_label.text = "Hover a village, camp, or troop for stats. Click the map to move the camera."
		return
	_hover_label.text = _format_marker_summary(_hover_marker)


func _format_marker_summary(marker: Dictionary) -> String:
	var summary: Dictionary = marker.get("summary", {})
	match str(marker.get("type", "")):
		"village":
			return "Village  population %d   food %s   rice %.1f/day" % [
				int(summary.get("resident_count", summary.get("available_villagers", 0))),
				_format_kg(float(summary.get("storage_food_kg", 0.0))),
				float(summary.get("daily_production_kg", 0.0)),
			]
		"camp":
			var camp_position: Vector3 = summary.get("camp_position", marker.get("position", Vector3.ZERO))
			return "Camp  troops nearby %d   food %s   wood %s" % [
				_count_troops_in_range(camp_position, float(summary.get("camp_range_m", 0.0)), summary.get("team_id", "")),
				_format_kg(float(summary.get("camp_food_kg", 0.0))),
				_format_kg(float(summary.get("camp_wood_kg", 0.0))),
			]
		"troop":
			return "%s  units %d   HP %.0f   DMG %.1f   MOR %.0f" % [
				String(summary.get("display_name", "Troop")),
				int(summary.get("active_soldier_count", summary.get("soldier_count", 0))),
				float(summary.get("average_strength", 0.0)),
				float(summary.get("average_damage", 0.0)),
				float(summary.get("average_morale", 0.0)),
			]
	return String(marker.get("name", "Marker"))


func _count_troops_in_range(camp_position: Vector3, range_m: float, team: Variant) -> int:
	if not get_tree():
		return 0
	var count := 0
	for troop: Node in get_tree().get_nodes_in_group(&"troops"):
		if not (troop is Node3D) or not troop.has_method("get_troop_summary"):
			continue
		var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
		if str(summary.get("team_id", "")) != str(team):
			continue
		if camp_position.distance_to((troop as Node3D).global_position) <= maxf(range_m, 0.1):
			count += int(summary.get("active_soldier_count", summary.get("soldier_count", 0)))
	return count


func _jump_camera_to(world_xz: Vector2) -> void:
	var rig := _get_camera_rig()
	if rig and rig.has_method("set_target_world_position"):
		var current_y := (rig as Node3D).global_position.y if rig is Node3D else 0.0
		rig.call("set_target_world_position", Vector3(world_xz.x, current_y, world_xz.y), false)


func _get_camera() -> Camera3D:
	if not camera_path.is_empty():
		var node := get_node_or_null(camera_path)
		if node is Camera3D:
			return node as Camera3D
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport else null


func _get_camera_rig() -> Node:
	if not camera_rig_path.is_empty():
		var node := get_node_or_null(camera_rig_path)
		if node:
			return node
	var camera := _get_camera()
	return camera.get_parent() if camera else null


func _get_world_rect() -> Rect2:
	if not movement_map:
		return Rect2()
	return Rect2(
		_get_map_origin(),
		Vector2(float(_get_map_width()) * _get_map_cell_size(), float(_get_map_height()) * _get_map_cell_size())
	)


func _get_map_origin() -> Vector2:
	var value: Variant = movement_map.get("origin") if movement_map else Vector2.ZERO
	return value as Vector2 if value is Vector2 else Vector2.ZERO


func _get_map_width() -> int:
	return int(movement_map.get("width")) if movement_map else 0


func _get_map_height() -> int:
	return int(movement_map.get("height")) if movement_map else 0


func _get_map_cell_size() -> float:
	return maxf(float(movement_map.get("cell_size_meters")), 0.001) if movement_map else 1.0


func _cell_world_top_left(x: int, y: int) -> Vector2:
	return _get_map_origin() + Vector2(float(x), float(y)) * _get_map_cell_size()


func _world_to_canvas(world: Vector2, rect: Rect2, world_rect: Rect2) -> Vector2:
	var ratio := Vector2(
		(world.x - world_rect.position.x) / maxf(world_rect.size.x, 0.001),
		(world.y - world_rect.position.y) / maxf(world_rect.size.y, 0.001)
	)
	return rect.position + Vector2(ratio.x * rect.size.x, ratio.y * rect.size.y)


func _canvas_to_world(point: Vector2, rect: Rect2, world_rect: Rect2) -> Vector2:
	var ratio := Vector2(
		clampf((point.x - rect.position.x) / maxf(rect.size.x, 0.001), 0.0, 1.0),
		clampf((point.y - rect.position.y) / maxf(rect.size.y, 0.001), 0.0, 1.0)
	)
	return world_rect.position + ratio * world_rect.size


func _movement_color(speed: float, flags: int) -> Color:
	if speed <= 0.0:
		return Color(0.16, 0.12, 0.11, 0.92)
	if (flags & FLAG_STEEP_SLOPE) != 0:
		return Color(0.36, 0.2, 0.18, 0.9)
	if (flags & FLAG_RIVER) != 0:
		return Color(0.14, 0.28, 0.38, 0.9)
	if (flags & FLAG_ROAD) != 0:
		return Color(0.52, 0.48, 0.32, 0.9)
	if (flags & FLAG_FOREST) != 0:
		return Color(0.16, 0.32, 0.18, 0.9)
	var intensity := clampf(speed / 2.0, 0.0, 1.0)
	return Color(0.12 + 0.24 * intensity, 0.18 + 0.36 * intensity, 0.14 + 0.16 * intensity, 0.9)


func _team_color(team: Variant) -> Color:
	match str(team):
		"enemy":
			return Color(0.86, 0.18, 0.12, 1.0)
		"deserter":
			return Color(0.62, 0.55, 0.44, 1.0)
		_:
			return Color(0.22, 0.48, 0.92, 1.0)


func _update_mode_buttons() -> void:
	if _movement_button:
		_movement_button.button_pressed = full_map_mode == MODE_MOVEMENT
	if _military_button:
		_military_button.button_pressed = full_map_mode == MODE_MILITARY


func _request_redraw() -> void:
	if _minimap_canvas:
		_minimap_canvas.queue_redraw()
	if _full_map_canvas:
		_full_map_canvas.queue_redraw()


func _make_panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.78, 0.84, 0.78, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _format_kg(value: float) -> String:
	return "%.1f kg" % [value]
