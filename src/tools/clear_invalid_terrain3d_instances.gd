extends SceneTree

const SCENE_PATH := "res://modules/draft/draft.tscn"
const TERRAIN_NODE_PATH := "Terrain3D"
const MAX_MESH_ID_TO_CHECK := 64


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := ResourceLoader.load(SCENE_PATH) as PackedScene
	if not scene:
		push_error("Could not load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var root_node := scene.instantiate()
	if not root_node:
		push_error("Could not instantiate scene: %s" % SCENE_PATH)
		quit(1)
		return

	root.add_child(root_node)
	await process_frame

	var terrain := root_node.get_node_or_null(TERRAIN_NODE_PATH)
	if not terrain:
		push_error("Could not find Terrain3D node at %s." % TERRAIN_NODE_PATH)
		root_node.free()
		quit(1)
		return

	var valid_mesh_ids := _get_valid_mesh_ids(terrain)
	var instancer: Variant = terrain.call("get_instancer")
	if not (instancer is Object):
		push_error("Terrain3D instancer is not available.")
		root_node.free()
		quit(1)
		return

	var cleared_ids: Array[int] = []
	for mesh_id: int in range(MAX_MESH_ID_TO_CHECK + 1):
		if valid_mesh_ids.has(mesh_id):
			continue
		(instancer as Object).call("clear_by_mesh", mesh_id)
		cleared_ids.append(mesh_id)

	var data: Variant = terrain.get("data")
	var data_directory := str(terrain.get("data_directory"))
	if data is Object and not data_directory.is_empty() and (data as Object).has_method("save_directory"):
		(data as Object).call("save_directory", data_directory)
	else:
		push_error("Terrain3D data could not be saved.")
		root_node.free()
		quit(1)
		return

	print("Cleared invalid Terrain3D mesh instance IDs outside %s." % str(valid_mesh_ids.keys()))
	root_node.free()
	quit(0)


func _get_valid_mesh_ids(terrain: Object) -> Dictionary:
	var valid_mesh_ids: Dictionary = {}
	var assets: Variant = terrain.get("assets")
	if not (assets is Object):
		return valid_mesh_ids

	var mesh_list: Variant = (assets as Object).get("mesh_list")
	if not (mesh_list is Array):
		return valid_mesh_ids

	for mesh_asset: Variant in mesh_list:
		if not (mesh_asset is Object):
			continue
		var mesh_id := int((mesh_asset as Object).get("id"))
		valid_mesh_ids[mesh_id] = true

	return valid_mesh_ids
