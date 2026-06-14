@tool
extends EditorPlugin

const DEFAULT_SCENE_PATH := "res://maps/midlands/midlands.tscn"


func _enter_tree() -> void:
	_run_save_probe.call_deferred()


func _run_save_probe() -> void:
	var scene_path := _get_scene_path_arg()
	var tree := EditorInterface.get_base_control().get_tree()
	print("[midlands-save-probe] waiting for scene: %s" % scene_path)

	var root := await _wait_for_edited_scene(scene_path, tree)
	if not is_instance_valid(root):
		push_error("[midlands-save-probe] edited scene root is not available")
		tree.quit(1)
		return
	if root.scene_file_path != scene_path:
		push_error("[midlands-save-probe] refusing to save unexpected scene root: %s (%s)" % [root.name, root.scene_file_path])
		tree.quit(1)
		return

	print("[midlands-save-probe] edited root: %s (%s)" % [root.name, root.scene_file_path])
	for _frame: int in range(10):
		await tree.process_frame
	var save_count := _get_save_count_arg()
	var edit_terrain := _get_bool_arg("--edit-terrain=", false)
	var terrain_edit_method := _get_string_arg("--terrain-edit-method=", "plugin")
	for save_index: int in range(save_count):
		root.set_meta("midlands_save_probe_cycle", save_index + 1)
		if edit_terrain:
			if not _edit_terrain(root, save_index, terrain_edit_method):
				push_error("[midlands-save-probe] terrain edit failed before save %d/%d" % [save_index + 1, save_count])
				tree.quit(1)
				return
			for _frame: int in range(4):
				await tree.process_frame
		print("[midlands-save-probe] saving scene %d/%d" % [save_index + 1, save_count])
		EditorInterface.save_scene()
		print("[midlands-save-probe] save complete %d/%d" % [save_index + 1, save_count])
		for _frame: int in range(4):
			await tree.process_frame

	for _frame: int in range(4):
		await tree.process_frame
	tree.quit(0)


func _wait_for_edited_scene(scene_path: String, tree: SceneTree) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not is_instance_valid(root) or root.scene_file_path != scene_path:
		print("[midlands-save-probe] opening scene: %s" % scene_path)
		EditorInterface.open_scene_from_path(scene_path)

	for _frame: int in range(180):
		root = EditorInterface.get_edited_scene_root()
		if is_instance_valid(root) and root.scene_file_path == scene_path:
			return root
		await tree.process_frame

	return EditorInterface.get_edited_scene_root()


func _get_scene_path_arg() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene-path="):
			return arg.trim_prefix("--scene-path=")
	return DEFAULT_SCENE_PATH


func _get_save_count_arg() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-count="):
			return maxi(arg.trim_prefix("--save-count=").to_int(), 1)
	return 1


func _get_bool_arg(prefix: String, default_value: bool) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			var value := arg.trim_prefix(prefix).to_lower()
			return value in ["1", "true", "yes", "on"]
	return default_value


func _get_string_arg(prefix: String, default_value: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return default_value


func _edit_terrain(root: Node, save_index: int, method: String) -> bool:
	var terrain := _find_terrain(root)
	if not is_instance_valid(terrain):
		push_error("[midlands-save-probe] Terrain3D node not found")
		return false

	var terrain_data: Variant = terrain.get("data")
	if not (terrain_data is Object) or not is_instance_valid(terrain_data):
		push_error("[midlands-save-probe] Terrain3D data is unavailable")
		return false

	var edit_position := _get_terrain_edit_position(terrain, terrain_data as Object, save_index)
	if edit_position == null:
		return false

	match method:
		"plugin":
			if _edit_terrain_with_active_plugin(terrain, edit_position):
				return true
			push_warning("[midlands-save-probe] active-plugin terrain edit failed; falling back to direct height edit")
			return _edit_terrain_direct(terrain_data as Object, edit_position, save_index)
		"direct":
			return _edit_terrain_direct(terrain_data as Object, edit_position, save_index)
		_:
			push_error("[midlands-save-probe] unknown terrain edit method: %s" % method)
			return false


func _find_terrain(root: Node) -> Node:
	var terrain := root.get_node_or_null("Terrain3D")
	if terrain != null:
		return terrain
	var matches := root.find_children("", "Terrain3D", true, false)
	if matches.is_empty():
		return null
	return matches[0]


func _get_terrain_edit_position(terrain: Node, terrain_data: Object, save_index: int) -> Variant:
	if not terrain_data.has_method("get_region_locations") or not terrain_data.has_method("get_height"):
		push_error("[midlands-save-probe] Terrain3D data lacks required query methods")
		return null

	var locations: Array = terrain_data.call("get_region_locations")
	if locations.is_empty():
		push_error("[midlands-save-probe] Terrain3D data has no active regions")
		return null

	var region_location := locations[abs(save_index) % locations.size()] as Vector2i
	var region_world_size := 1024.0
	if terrain.has_method("get_region_size") and terrain.has_method("get_vertex_spacing"):
		region_world_size = float(terrain.call("get_region_size")) * float(terrain.call("get_vertex_spacing"))
	var offset := fposmod(float(save_index), 7.0) * 0.5
	var position := Vector3(
		(float(region_location.x) + 0.5) * region_world_size + offset,
		0.0,
		(float(region_location.y) + 0.5) * region_world_size + offset
	)
	position.y = float(terrain_data.call("get_height", position))
	print("[midlands-save-probe] terrain edit point %s in region %s" % [position, region_location])
	return position


func _edit_terrain_with_active_plugin(terrain: Node, edit_position: Vector3) -> bool:
	var terrain_plugin := _find_terrain3d_editor_plugin()
	if not is_instance_valid(terrain_plugin):
		push_warning("[midlands-save-probe] active Terrain3D editor plugin not found")
		return false

	if terrain_plugin.has_method("_edit"):
		terrain_plugin.call("_edit", terrain)

	var editor: Variant = terrain_plugin.get("editor")
	if not (editor is Terrain3DEditor):
		push_warning("[midlands-save-probe] active Terrain3D editor helper not available")
		return false

	var terrain_editor := editor as Terrain3DEditor
	terrain_editor.set_brush_data(_make_terrain_brush_data())
	terrain_editor.set_tool(Terrain3DEditor.SCULPT)
	terrain_editor.set_operation(Terrain3DEditor.ADD)
	print("[midlands-save-probe] editing terrain via active Terrain3D plugin at %s" % edit_position)
	terrain_editor.start_operation(edit_position)
	terrain_editor.operate(edit_position, 0.0)
	terrain_editor.stop_operation()
	EditorInterface.mark_scene_as_unsaved()
	return true


func _find_terrain3d_editor_plugin() -> Node:
	var tree := EditorInterface.get_base_control().get_tree()
	return _find_node_with_script(tree.root, "res://addons/terrain_3d/src/editor_plugin.gd")


func _find_node_with_script(node: Node, script_path: String) -> Node:
	var script: Variant = node.get_script()
	if script is Script and (script as Script).resource_path == script_path:
		return node
	for child: Node in node.get_children():
		var found := _find_node_with_script(child, script_path)
		if found != null:
			return found
	return null


func _edit_terrain_direct(terrain_data: Object, edit_position: Vector3, save_index: int) -> bool:
	if not terrain_data.has_method("set_height") or not terrain_data.has_method("get_height"):
		return false
	var delta := 0.05 if save_index % 2 == 0 else -0.05
	var current_height := float(terrain_data.call("get_height", edit_position))
	var target_height := current_height + delta
	print("[midlands-save-probe] editing terrain directly at %s height %.3f -> %.3f" % [edit_position, current_height, target_height])
	terrain_data.call("set_height", edit_position, target_height)
	if terrain_data.has_method("get_region_location") and terrain_data.has_method("set_region_modified"):
		var region_location: Vector2i = terrain_data.call("get_region_location", edit_position)
		terrain_data.call("set_region_modified", region_location, true)
	if terrain_data.has_method("calc_height_range"):
		terrain_data.call("calc_height_range", true)
	if terrain_data.has_method("update_maps") and ClassDB.class_exists(&"Terrain3DRegion"):
		terrain_data.call("update_maps", Terrain3DRegion.TYPE_HEIGHT, false, true)
	EditorInterface.mark_scene_as_unsaved()
	return true


func _make_terrain_brush_data() -> Dictionary:
	var brush_image := Image.create_empty(1024, 1024, false, Image.FORMAT_R8)
	brush_image.fill(Color.WHITE)
	var brush_texture := ImageTexture.create_from_image(brush_image)
	return {
		"brush": [brush_image, brush_texture],
		"size": 2.0,
		"strength": 5.0,
		"height": 0.0,
		"auto_regions": false,
		"align_to_view": false,
		"show_cursor_while_painting": false,
		"gamma": 1.0,
		"jitter": 0.0,
		"crosshair_threshold": 16.0,
		"asset_id": 0,
		"mouse_pressure": 1.0,
		"modifier_shift": false,
		"modifier_ctrl": false,
		"modifier_alt": false,
		"invert": false,
	}
