extends SceneTree

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const MovementMapPathfinderScript = preload("res://modules/troops/movement_map_pathfinder.gd")
const TroopScene: PackedScene = preload("res://modules/troops/troop.tscn")
const TroopDrawerScene: PackedScene = preload("res://modules/troops/troop_management_drawer.tscn")
const RTSCameraScene: PackedScene = preload("res://modules/camera/rts_camera.tscn")


func _init() -> void:
	_run_deferred_checks.call_deferred()


func _run_deferred_checks() -> void:
	var failures: Array[String] = []
	await process_frame
	await _run_checks(failures)
	if failures.is_empty():
		print("Troop management headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_checks(failures: Array[String]) -> void:
	_check_pathfinder_avoids_blocked_cells(failures)
	_check_pathfinder_reports_unreachable(failures)
	await _check_troop_scene_and_exports(failures)
	await _check_troop_route_visuals(failures)
	await _check_camera_recovers_from_consumed_right_release(failures)
	_check_drawer_loads(failures)
	_check_scene_wiring("res://modules/draft/draft.tscn", failures)
	_check_scene_wiring("res://maps/midlands/midlands.tscn", failures)


func _check_pathfinder_avoids_blocked_cells(failures: Array[String]) -> void:
	var data := _make_map(6, 4)
	_set_blocked(data, Vector2i(2, 0))
	_set_blocked(data, Vector2i(2, 1))
	_set_blocked(data, Vector2i(2, 3))

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		data,
		Vector3(0.5, 0.0, 1.5),
		Vector3(5.5, 0.0, 1.5),
		1.0,
		4
	)
	_expect(bool(result.get("reachable", false)), "pathfinder should route through the wall gap", failures)
	var cells: Array = result.get("cells", [])
	_expect(cells.has(Vector2i(2, 2)), "pathfinder should use the only walkable wall gap", failures)
	for cell: Vector2i in cells:
		_expect(data.is_walkable_cell(cell), "pathfinder route should not include blocked cells", failures)


func _check_pathfinder_reports_unreachable(failures: Array[String]) -> void:
	var data := _make_map(5, 3)
	for y: int in range(3):
		_set_blocked(data, Vector2i(2, y))

	var result: Dictionary = MovementMapPathfinderScript.find_path(
		data,
		Vector3(0.5, 0.0, 1.5),
		Vector3(4.5, 0.0, 1.5),
		1.0,
		3
	)
	_expect(not bool(result.get("reachable", true)), "pathfinder should reject unreachable targets", failures)
	_expect(
		StringName(result.get("failure_reason", &"")) == MovementMapPathfinderScript.FAILURE_UNREACHABLE,
		"unreachable path should report the unreachable failure reason",
		failures
	)


func _check_troop_scene_and_exports(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("soldier_count", 8)
	troop.set("formation_columns", 4)
	troop.set("team_flag_color", Color.BLUE)
	troop.set("troop_flag_color", Color.RED)
	root.add_child(troop)
	await process_frame

	_expect(int(troop.call("get_soldier_count")) == 8, "troop should rebuild exported soldier count", failures)
	_expect(int(troop.call("get_flag_holder_count")) == 2, "troop should create two flag holders", failures)
	var proxy := troop.call("get_selection_proxy") as StaticBody3D
	_expect(proxy != null, "troop should create a selection proxy", failures)
	if proxy:
		_expect(proxy.has_meta(&"troop_selectable_type"), "selection proxy should carry troop metadata", failures)

	root.remove_child(troop)
	troop.free()


func _check_troop_route_visuals(failures: Array[String]) -> void:
	var troop := TroopScene.instantiate()
	troop.set("movement_map", _make_map(8, 8))
	troop.set("position", Vector3(0.5, 0.0, 0.5))
	root.add_child(troop)
	await process_frame

	var accepted: bool = bool(troop.call("set_move_destination", Vector3(6.5, 0.0, 6.5)))
	_expect(accepted, "troop should accept a reachable movement order", failures)
	_expect(bool(troop.call("has_destination")), "troop should store a destination after a move order", failures)
	_expect(int(troop.call("get_route_dash_count")) > 0, "troop should draw dashed route visuals", failures)
	_expect(bool(troop.call("has_destination_marker")), "troop should draw a destination flag", failures)
	troop.call("clear_destination")
	_expect(not bool(troop.call("has_destination")), "clear destination should remove active destination", failures)
	_expect(int(troop.call("get_route_dash_count")) == 0, "clear destination should clear route dashes", failures)

	root.remove_child(troop)
	troop.free()


func _check_camera_recovers_from_consumed_right_release(failures: Array[String]) -> void:
	var camera_rig := RTSCameraScene.instantiate()
	root.add_child(camera_rig)
	await process_frame

	camera_rig.set("_right_mouse_pressed", true)
	camera_rig.set("_is_rotating", true)
	camera_rig.call("_process", 0.016)
	_expect(
		not bool(camera_rig.get("_right_mouse_pressed")),
		"camera should clear stale right mouse state when release is consumed",
		failures
	)
	_expect(
		not bool(camera_rig.get("_is_rotating")),
		"camera should leave right-drag rotation when right mouse is no longer pressed",
		failures
	)

	root.remove_child(camera_rig)
	camera_rig.free()


func _check_drawer_loads(failures: Array[String]) -> void:
	var drawer := TroopDrawerScene.instantiate()
	_expect(drawer is CanvasLayer, "troop drawer scene should instantiate a CanvasLayer", failures)
	_expect(drawer.has_method("show_troop"), "troop drawer should expose show_troop", failures)
	drawer.free()


func _check_scene_wiring(scene_path: String, failures: Array[String]) -> void:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s should load as a PackedScene" % scene_path, failures)
	if not scene:
		return

	var instance := scene.instantiate()
	_expect(instance != null, "%s should instantiate" % scene_path, failures)
	if not instance:
		return

	_expect(
		instance.find_child("TroopSelectionController", true, false) != null,
		"%s should include a troop selection controller" % scene_path,
		failures
	)
	_expect(
		instance.find_child("TroopManagementDrawer", true, false) != null,
		"%s should include a troop management drawer" % scene_path,
		failures
	)
	var troop := instance.find_child("Troop_01", true, false)
	_expect(troop != null, "%s should include a default troop instance" % scene_path, failures)
	if troop:
		_expect(not String(troop.get("movement_map_path")).is_empty(), "%s troop should have a movement map path" % scene_path, failures)
		var terrain_path: NodePath = troop.get("terrain_path")
		_expect(not terrain_path.is_empty(), "%s troop should have a terrain path" % scene_path, failures)

	instance.free()


func _make_map(width: int, height: int) -> MovementMapData:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2.ZERO
	data.cell_size_meters = 1.0
	data.resize_map(width, height, 1.0, 0)
	return data


func _set_blocked(data: MovementMapData, cell: Vector2i) -> void:
	var index := data.get_cell_index(cell)
	if index >= 0:
		data.speed_multipliers[index] = 0.0


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
