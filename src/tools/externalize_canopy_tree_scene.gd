@tool
extends SceneTree

const SCENE_PATH := "res://assets/models/forest/plants/forest_canopy_tree_01.tscn"
const MESH_PATH := "res://assets/models/forest/plants/forest_canopy_tree_01_mesh.res"
const MATERIAL_PATH := "res://assets/models/forest/plants/forest_canopy_tree_01_material.res"


func _init() -> void:
	var errors: Array[String] = []
	var scene := ResourceLoader.load(SCENE_PATH) as PackedScene
	if not scene:
		_fail("Could not load %s." % SCENE_PATH)
		return

	var root := scene.instantiate()
	if not root:
		_fail("Could not instantiate %s." % SCENE_PATH)
		return

	var mesh_instance := _find_first_mesh_instance(root)
	if not mesh_instance or not mesh_instance.mesh:
		root.free()
		_fail("%s has no MeshInstance3D with a mesh." % SCENE_PATH)
		return

	var mesh_error := ResourceSaver.save(mesh_instance.mesh, MESH_PATH)
	if mesh_error != OK:
		errors.append("Could not save %s: %s" % [MESH_PATH, error_string(mesh_error)])

	var material := mesh_instance.material_override
	var saved_material: Material = null
	if material:
		var material_error := ResourceSaver.save(material, MATERIAL_PATH)
		if material_error != OK:
			errors.append("Could not save %s: %s" % [MATERIAL_PATH, error_string(material_error)])
		else:
			saved_material = ResourceLoader.load(MATERIAL_PATH) as Material

	var saved_mesh := ResourceLoader.load(MESH_PATH) as Mesh
	if not saved_mesh:
		errors.append("Could not reload %s." % MESH_PATH)

	if errors.is_empty():
		var packed := PackedScene.new()
		var wrapper := Node3D.new()
		wrapper.name = root.name
		var new_mesh_instance := MeshInstance3D.new()
		new_mesh_instance.name = mesh_instance.name
		new_mesh_instance.transform = mesh_instance.transform
		new_mesh_instance.mesh = saved_mesh
		new_mesh_instance.cast_shadow = mesh_instance.cast_shadow
		new_mesh_instance.material_override = saved_material
		wrapper.add_child(new_mesh_instance)
		new_mesh_instance.owner = wrapper

		var pack_error := packed.pack(wrapper)
		if pack_error != OK:
			errors.append("Could not pack wrapper scene: %s" % error_string(pack_error))
		else:
			var scene_error := ResourceSaver.save(packed, SCENE_PATH)
			if scene_error != OK:
				errors.append("Could not save %s: %s" % [SCENE_PATH, error_string(scene_error)])

		wrapper.free()

	root.free()

	if errors.is_empty():
		print("Externalized canopy tree scene.")
		quit(0)
	else:
		for error: String in errors:
			push_error(error)
		quit(1)


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var result := _find_first_mesh_instance(child)
		if result:
			return result
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
