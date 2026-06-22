extends Node3D
class_name TroopCorpseManager

var _batches: Dictionary = {}
var _transforms_by_key: Dictionary = {}
var _corpse_count := 0
var _mesh_part_count := 0


func register_soldier_corpse(soldier: Node3D) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("_enter_corpse_state"):
		soldier.call("_enter_corpse_state")

	var captured := 0
	var mesh_nodes := soldier.find_children("*", "MeshInstance3D", true, false)
	for node: Node in mesh_nodes:
		var source := node as MeshInstance3D
		if not source or not source.mesh or not source.visible:
			continue
		_append_source_mesh(source)
		captured += 1
	if captured <= 0:
		return false
	_corpse_count += 1
	_mesh_part_count += captured
	return true


func get_corpse_count() -> int:
	return _corpse_count


func get_batch_count() -> int:
	return _batches.size()


func get_mesh_part_count() -> int:
	return _mesh_part_count


func clear_all_corpses() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_batches.clear()
	_transforms_by_key.clear()
	_corpse_count = 0
	_mesh_part_count = 0


func get_debug_summary() -> Dictionary:
	return {
		"corpse_count": _corpse_count,
		"corpse_batch_count": _batches.size(),
		"corpse_mesh_part_count": _mesh_part_count,
	}


func _append_source_mesh(source: MeshInstance3D) -> void:
	var key := _get_batch_key(source)
	var batch := _get_or_create_batch(key, source)
	var transforms: Array = _transforms_by_key.get(key, [])
	transforms.append(source.global_transform)
	_transforms_by_key[key] = transforms

	var multimesh := batch.multimesh
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])


func _get_or_create_batch(key: String, source: MeshInstance3D) -> MultiMeshInstance3D:
	var existing := _batches.get(key) as MultiMeshInstance3D
	if existing:
		return existing
	var batch := MultiMeshInstance3D.new()
	batch.name = "CorpseBatch_%03d" % _batches.size()
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	batch.cast_shadow = source.cast_shadow
	batch.gi_mode = source.gi_mode
	batch.layers = source.layers
	if source.material_override:
		batch.material_override = source.material_override
	else:
		var surface_material := source.get_surface_override_material(0)
		if surface_material:
			batch.material_override = surface_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source.mesh
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0
	batch.multimesh = multimesh
	add_child(batch)
	batch.owner = null
	_batches[key] = batch
	_transforms_by_key[key] = []
	return batch


func _get_batch_key(source: MeshInstance3D) -> String:
	var material: Material = source.material_override
	if not material:
		material = source.get_surface_override_material(0)
	var material_id := material.get_instance_id() if material else 0
	return "%d:%d:%d:%d" % [
		source.mesh.get_instance_id(),
		material_id,
		int(source.cast_shadow),
		int(source.layers),
	]
