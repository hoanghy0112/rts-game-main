extends Node3D
class_name TroopSoldierBatchRenderer

var _enabled := true
var _soldiers: Array[Node3D] = []
var _mesh_paths: Array[NodePath] = []
var _batches: Dictionary = {}
var _source_meshes_by_path: Dictionary = {}
var _source_soldiers_by_path: Dictionary = {}
var _source_indices_by_path_and_soldier_id: Dictionary = {}
var _cached_source_meshes: Array[MeshInstance3D] = []
var _source_visibility: Dictionary = {}
var _last_source_transforms: Dictionary = {}
var _last_source_draw_indices: Dictionary = {}
var _transform_buffers_by_path: Dictionary = {}
var _dirty := true
var _source_cache_dirty := true
var _sources_hidden := false
var _local_space_enabled := false
var _hidden_source_mesh_count := 0
var _batched_instance_count := 0
var _last_sync_usec := 0
var _max_sync_usec := 0
var _last_sync_transform_writes := 0
var _max_sync_transform_writes := 0
var _last_sync_source_reads := 0
var _cached_source_mesh_count := 0
var _sync_count := 0

@export var multimesh_buffer_sync_enabled := false


func set_batching_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	visible = enabled
	_dirty = true
	_source_cache_dirty = true
	if enabled:
		_rebuild_batches_if_needed()
		_hide_source_meshes()
	else:
		_restore_source_meshes()


func set_soldiers(soldiers: Array[Node]) -> void:
	_restore_source_meshes()
	_soldiers.clear()
	for soldier: Node in soldiers:
		if soldier is Node3D and is_instance_valid(soldier):
			_soldiers.append(soldier as Node3D)
	_dirty = true
	_source_cache_dirty = true
	if _enabled:
		_rebuild_batches_if_needed()
		_hide_source_meshes()


func set_local_space_enabled(enabled: bool) -> void:
	if _local_space_enabled == enabled:
		return
	_local_space_enabled = enabled
	for batch_node: Node in get_children():
		var batch := batch_node as MultiMeshInstance3D
		if not batch:
			continue
		if enabled:
			batch.top_level = false
			batch.transform = Transform3D.IDENTITY
		else:
			batch.top_level = true
			batch.global_transform = Transform3D.IDENTITY
	_last_source_transforms.clear()
	_last_source_draw_indices.clear()


func sync(force_dirty_transforms: bool = false) -> void:
	if not _enabled:
		return
	var started := Time.get_ticks_usec()
	_sync_count += 1
	_rebuild_batches_if_needed()
	if not _sources_hidden:
		_hide_source_meshes()
	_batched_instance_count = 0
	_last_sync_transform_writes = 0
	_last_sync_source_reads = 0
	for path: NodePath in _mesh_paths:
		var batch := _batches.get(path) as MultiMeshInstance3D
		if not batch or not batch.multimesh:
			continue
		var multimesh := batch.multimesh
		var sources: Array = _source_meshes_by_path.get(path, [])
		var source_soldiers: Array = _source_soldiers_by_path.get(path, [])
		var batch_inverse := batch.global_transform.affine_inverse() if _local_space_enabled else Transform3D.IDENTITY
		if force_dirty_transforms and _can_use_buffer_sync():
			_batched_instance_count += _sync_path_buffer(path, multimesh, sources, source_soldiers, batch_inverse)
			continue
		var visible_count := 0
		for index: int in range(sources.size()):
			_last_sync_source_reads += 1
			var source := sources[index] as MeshInstance3D
			if not is_instance_valid(source):
				continue
			var soldier: Node3D = null
			if index < source_soldiers.size():
				soldier = source_soldiers[index] as Node3D
			if not is_instance_valid(soldier) or not soldier.visible:
				continue
			var source_id := source.get_instance_id()
			if not bool(_source_visibility.get(source_id, true)):
				continue
			var source_transform := batch_inverse * source.global_transform if _local_space_enabled else source.global_transform
			if force_dirty_transforms:
				multimesh.set_instance_transform(visible_count, source_transform)
				_last_source_transforms[source_id] = source_transform
				_last_source_draw_indices[source_id] = visible_count
				_last_sync_transform_writes += 1
			else:
				var previous_transform: Variant = _last_source_transforms.get(source_id)
				var previous_draw_index := int(_last_source_draw_indices.get(source_id, -1))
				if previous_draw_index != visible_count or previous_transform == null or previous_transform != source_transform:
					multimesh.set_instance_transform(visible_count, source_transform)
					_last_source_transforms[source_id] = source_transform
					_last_source_draw_indices[source_id] = visible_count
					_last_sync_transform_writes += 1
			visible_count += 1
		multimesh.visible_instance_count = visible_count
		_batched_instance_count += visible_count
	_last_sync_usec = Time.get_ticks_usec() - started
	_max_sync_usec = maxi(_max_sync_usec, _last_sync_usec)
	_max_sync_transform_writes = maxi(_max_sync_transform_writes, _last_sync_transform_writes)


func sync_dirty_soldiers(dirty_soldier_ids: Dictionary) -> void:
	if not _enabled or dirty_soldier_ids.is_empty():
		return
	var started := Time.get_ticks_usec()
	_sync_count += 1
	_rebuild_batches_if_needed()
	if not _sources_hidden:
		_hide_source_meshes()
	_last_sync_transform_writes = 0
	_last_sync_source_reads = 0
	for path: NodePath in _mesh_paths:
		var batch := _batches.get(path) as MultiMeshInstance3D
		if not batch or not batch.multimesh:
			continue
		var multimesh := batch.multimesh
		var sources: Array = _source_meshes_by_path.get(path, [])
		var source_soldiers: Array = _source_soldiers_by_path.get(path, [])
		var indices_by_soldier_id: Dictionary = _source_indices_by_path_and_soldier_id.get(path, {})
		var batch_inverse := batch.global_transform.affine_inverse() if _local_space_enabled else Transform3D.IDENTITY
		for soldier_id: Variant in dirty_soldier_ids.keys():
			var index := int(indices_by_soldier_id.get(soldier_id, -1))
			if index < 0 or index >= sources.size():
				continue
			_last_sync_source_reads += 1
			var source := sources[index] as MeshInstance3D
			if not is_instance_valid(source):
				continue
			var soldier: Node3D = null
			if index < source_soldiers.size():
				soldier = source_soldiers[index] as Node3D
			if not is_instance_valid(soldier):
				continue
			var source_id := source.get_instance_id()
			var draw_index := int(_last_source_draw_indices.get(source_id, -1))
			if draw_index < 0:
				continue
			var source_transform := batch_inverse * source.global_transform if _local_space_enabled else source.global_transform
			multimesh.set_instance_transform(draw_index, source_transform)
			_last_source_transforms[source_id] = source_transform
			_last_sync_transform_writes += 1
	_last_sync_usec = Time.get_ticks_usec() - started
	_max_sync_usec = maxi(_max_sync_usec, _last_sync_usec)
	_max_sync_transform_writes = maxi(_max_sync_transform_writes, _last_sync_transform_writes)


func _can_use_buffer_sync() -> bool:
	return multimesh_buffer_sync_enabled and DisplayServer.get_name() != "headless"


func _sync_path_buffer(
	path: NodePath,
	multimesh: MultiMesh,
	sources: Array,
	source_soldiers: Array,
	batch_inverse: Transform3D
) -> int:
	var instance_count := multimesh.instance_count
	var buffer := _get_transform_buffer(path, instance_count)
	var visible_count := 0
	for index: int in range(sources.size()):
		_last_sync_source_reads += 1
		var source := sources[index] as MeshInstance3D
		if not is_instance_valid(source):
			continue
		var soldier: Node3D = null
		if index < source_soldiers.size():
			soldier = source_soldiers[index] as Node3D
		if not is_instance_valid(soldier) or not soldier.visible:
			continue
		var source_id := source.get_instance_id()
		if not bool(_source_visibility.get(source_id, true)):
			continue
		var source_transform := batch_inverse * source.global_transform if _local_space_enabled else source.global_transform
		_write_transform_to_buffer(buffer, visible_count, source_transform)
		_last_source_transforms[source_id] = source_transform
		_last_source_draw_indices[source_id] = visible_count
		_last_sync_transform_writes += 1
		visible_count += 1
	multimesh.set_buffer(buffer)
	multimesh.visible_instance_count = visible_count
	return visible_count


func _get_transform_buffer(path: NodePath, instance_count: int) -> PackedFloat32Array:
	var required_size := maxi(instance_count, 0) * 12
	var buffer_variant: Variant = _transform_buffers_by_path.get(path)
	var buffer := buffer_variant as PackedFloat32Array if buffer_variant is PackedFloat32Array else PackedFloat32Array()
	if buffer.size() != required_size:
		buffer.resize(required_size)
		_transform_buffers_by_path[path] = buffer
	return buffer


func _write_transform_to_buffer(buffer: PackedFloat32Array, index: int, xform: Transform3D) -> void:
	var offset := index * 12
	var basis := xform.basis
	var origin := xform.origin
	buffer[offset] = basis.x.x
	buffer[offset + 1] = basis.x.y
	buffer[offset + 2] = basis.x.z
	buffer[offset + 3] = basis.y.x
	buffer[offset + 4] = basis.y.y
	buffer[offset + 5] = basis.y.z
	buffer[offset + 6] = basis.z.x
	buffer[offset + 7] = basis.z.y
	buffer[offset + 8] = basis.z.z
	buffer[offset + 9] = origin.x
	buffer[offset + 10] = origin.y
	buffer[offset + 11] = origin.z


func mark_dirty() -> void:
	_dirty = true
	_source_cache_dirty = true


func get_batch_count() -> int:
	return _mesh_paths.size()


func get_batched_instance_count() -> int:
	return _batched_instance_count


func get_hidden_source_mesh_count() -> int:
	return _hidden_source_mesh_count


func get_cached_source_mesh_count() -> int:
	return _cached_source_mesh_count


func get_last_sync_usec() -> int:
	return _last_sync_usec


func get_max_sync_usec() -> int:
	return _max_sync_usec


func get_last_sync_transform_writes() -> int:
	return _last_sync_transform_writes


func get_max_sync_transform_writes() -> int:
	return _max_sync_transform_writes


func get_last_sync_source_reads() -> int:
	return _last_sync_source_reads


func get_sync_count() -> int:
	return _sync_count


func reset_perf_counters() -> void:
	_last_sync_usec = 0
	_max_sync_usec = 0
	_last_sync_transform_writes = 0
	_max_sync_transform_writes = 0
	_last_sync_source_reads = 0
	_sync_count = 0


func _exit_tree() -> void:
	_restore_source_meshes()


func _rebuild_batches_if_needed() -> void:
	if not _dirty:
		_rebuild_source_cache_if_needed()
		return
	if _sources_hidden:
		_restore_source_meshes()
	_clear_batches()
	_dirty = false
	_source_cache_dirty = true
	var source_soldier := _get_first_valid_soldier()
	if not source_soldier:
		return
	var mesh_nodes := source_soldier.find_children("*", "MeshInstance3D", true, false)
	for node: Node in mesh_nodes:
		var source := node as MeshInstance3D
		if not source or not source.mesh:
			continue
		var path := source_soldier.get_path_to(source)
		var batch := MultiMeshInstance3D.new()
		batch.name = _make_batch_name(path)
		batch.top_level = not _local_space_enabled
		if _local_space_enabled:
			batch.transform = Transform3D.IDENTITY
		else:
			batch.global_transform = Transform3D.IDENTITY
		batch.visible = true
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
		multimesh.instance_count = maxi(_soldiers.size(), 1)
		multimesh.visible_instance_count = 0
		batch.multimesh = multimesh
		add_child(batch)
		batch.owner = null
		_mesh_paths.append(path)
		_batches[path] = batch
	_rebuild_source_cache_if_needed()


func _clear_batches() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_mesh_paths.clear()
	_batches.clear()
	_transform_buffers_by_path.clear()
	_clear_source_cache()
	_batched_instance_count = 0


func _rebuild_source_cache_if_needed() -> void:
	if not _source_cache_dirty:
		return
	_source_meshes_by_path.clear()
	_source_soldiers_by_path.clear()
	_source_indices_by_path_and_soldier_id.clear()
	_cached_source_meshes.clear()
	_source_visibility.clear()
	_last_source_transforms.clear()
	_last_source_draw_indices.clear()
	_hidden_source_mesh_count = 0
	_cached_source_mesh_count = 0
	_source_cache_dirty = false
	for path: NodePath in _mesh_paths:
		var sources: Array[MeshInstance3D] = []
		var source_soldiers: Array[Node3D] = []
		var indices_by_soldier_id := {}
		for soldier: Node3D in _soldiers:
			if not is_instance_valid(soldier):
				continue
			var source := soldier.get_node_or_null(path) as MeshInstance3D
			if not source:
				continue
			var id := source.get_instance_id()
			if not _source_visibility.has(id):
				_source_visibility[id] = source.visible
				_cached_source_meshes.append(source)
				_cached_source_mesh_count += 1
			if bool(_source_visibility.get(id, true)):
				indices_by_soldier_id[soldier.get_instance_id()] = sources.size()
				sources.append(source)
				source_soldiers.append(soldier)
		_source_meshes_by_path[path] = sources
		_source_soldiers_by_path[path] = source_soldiers
		_source_indices_by_path_and_soldier_id[path] = indices_by_soldier_id


func _clear_source_cache() -> void:
	_source_meshes_by_path.clear()
	_source_soldiers_by_path.clear()
	_source_indices_by_path_and_soldier_id.clear()
	_cached_source_meshes.clear()
	_source_visibility.clear()
	_last_source_transforms.clear()
	_last_source_draw_indices.clear()
	_source_cache_dirty = true
	_hidden_source_mesh_count = 0
	_cached_source_mesh_count = 0


func _hide_source_meshes() -> void:
	_hidden_source_mesh_count = 0
	_rebuild_source_cache_if_needed()
	for mesh_instance: MeshInstance3D in _cached_source_meshes:
		if not is_instance_valid(mesh_instance):
			continue
		var id := mesh_instance.get_instance_id()
		if bool(_source_visibility.get(id, true)):
			_hidden_source_mesh_count += 1
		mesh_instance.visible = false
	_sources_hidden = true


func _restore_source_meshes() -> void:
	for mesh_instance: MeshInstance3D in _cached_source_meshes:
		if not is_instance_valid(mesh_instance):
			continue
		var id := mesh_instance.get_instance_id()
		if _source_visibility.has(id):
			mesh_instance.visible = bool(_source_visibility[id])
	_clear_source_cache()
	_sources_hidden = false


func _get_first_valid_soldier() -> Node3D:
	for soldier: Node3D in _soldiers:
		if is_instance_valid(soldier):
			return soldier
	return null


func _make_batch_name(path: NodePath) -> String:
	var text := String(path)
	text = text.replace("/", "_")
	text = text.replace(":", "_")
	text = text.replace("@", "_")
	return "Batch_%s" % text
