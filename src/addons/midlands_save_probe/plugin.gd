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
	var save_count := _get_save_count_arg()
	for save_index: int in range(save_count):
		root.set_meta("midlands_save_probe_cycle", save_index + 1)
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
