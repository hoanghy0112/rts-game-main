extends Node3D
class_name TroopCorpseManager

const CUSTOM_AABB_MARGIN_M := 8.0

@export_range(0, 4096, 1, "or_greater") var max_visible_corpse_count: int = 0
@export_range(0, 32768, 1, "or_greater") var max_visible_mesh_part_count: int = 0
@export_range(0, 8192, 1, "or_greater") var max_visible_batch_count: int = 0
@export_enum("Off", "On", "Double-sided", "Shadows Only") var corpse_shadow_mode: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
@export_range(0.0, 10000.0, 1.0, "or_greater") var corpse_visibility_range_end_m: float = 900.0
@export_range(0.0, 2048.0, 1.0, "or_greater") var corpse_visibility_fade_margin_m: float = 120.0

var _batches: Dictionary = {}
var _transforms_by_key: Dictionary = {}
var _capacities_by_key: Dictionary = {}
var _corpse_count := 0
var _mesh_part_count := 0
var _skipped_corpse_count := 0
var _skipped_mesh_part_count := 0


func has_corpse_capacity() -> bool:
	if max_visible_corpse_count > 0 and _corpse_count >= max_visible_corpse_count:
		return false
	if max_visible_mesh_part_count > 0 and _mesh_part_count >= max_visible_mesh_part_count:
		return false
	return true


func register_soldier_corpse(soldier: Node3D) -> bool:
	if not is_instance_valid(soldier):
		return false
	if max_visible_corpse_count > 0 and _corpse_count >= max_visible_corpse_count:
		_skipped_corpse_count += 1
		return false
	if max_visible_mesh_part_count > 0 and _mesh_part_count >= max_visible_mesh_part_count:
		_skipped_corpse_count += 1
		return false
	if soldier.has_method("_enter_corpse_state"):
		soldier.call("_enter_corpse_state")

	var captured := 0
	var mesh_nodes := soldier.find_children("*", "MeshInstance3D", true, false)
	for node: Node in mesh_nodes:
		if max_visible_mesh_part_count > 0 and _mesh_part_count + captured >= max_visible_mesh_part_count:
			_skipped_mesh_part_count += 1
			continue
		var source := node as MeshInstance3D
		if not source or not source.mesh or not source.visible:
			continue
		if max_visible_batch_count > 0 and not _batches.has(_get_batch_key(source)) and _batches.size() >= max_visible_batch_count:
			_skipped_mesh_part_count += 1
			continue
		_append_source_mesh(source)
		captured += 1
	if captured <= 0:
		_skipped_corpse_count += 1
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
	_capacities_by_key.clear()
	_corpse_count = 0
	_mesh_part_count = 0
	_skipped_corpse_count = 0
	_skipped_mesh_part_count = 0


func get_debug_summary() -> Dictionary:
	return {
		"corpse_count": _corpse_count,
		"corpse_batch_count": _batches.size(),
		"corpse_mesh_part_count": _mesh_part_count,
		"corpse_skipped_count": _skipped_corpse_count,
		"corpse_skipped_mesh_part_count": _skipped_mesh_part_count,
		"corpse_max_visible_count": max_visible_corpse_count,
		"corpse_max_visible_mesh_part_count": max_visible_mesh_part_count,
		"corpse_max_visible_batch_count": max_visible_batch_count,
	}


func _append_source_mesh(source: MeshInstance3D) -> void:
	var key := _get_batch_key(source)
	var batch := _get_or_create_batch(key, source)
	var transforms: Array = _transforms_by_key.get(key, [])
	transforms.append(source.global_transform)
	_transforms_by_key[key] = transforms

	var multimesh := batch.multimesh
	var transform_count := transforms.size()
	var capacity := int(_capacities_by_key.get(key, 0))
	if transform_count > capacity:
		capacity = _grow_capacity(capacity, transform_count)
		multimesh.instance_count = capacity
		_capacities_by_key[key] = capacity
		for index: int in range(transform_count):
			multimesh.set_instance_transform(index, transforms[index])
	else:
		multimesh.set_instance_transform(transform_count - 1, transforms[transform_count - 1])
	multimesh.visible_instance_count = transform_count
	_update_batch_custom_aabb(batch, multimesh, transforms)


func _get_or_create_batch(key: String, source: MeshInstance3D) -> MultiMeshInstance3D:
	var existing := _batches.get(key) as MultiMeshInstance3D
	if existing:
		return existing
	var batch := MultiMeshInstance3D.new()
	batch.name = "CorpseBatch_%03d" % _batches.size()
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	batch.cast_shadow = corpse_shadow_mode
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	batch.layers = source.layers
	batch.visibility_range_end = maxf(corpse_visibility_range_end_m, 0.0)
	batch.visibility_range_end_margin = maxf(corpse_visibility_fade_margin_m, 0.0)
	batch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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
	_capacities_by_key[key] = 0
	return batch


func _grow_capacity(current_capacity: int, required_count: int) -> int:
	var capacity := maxi(current_capacity, 8)
	while capacity < required_count:
		capacity *= 2
	return capacity


func _update_batch_custom_aabb(batch: MultiMeshInstance3D, multimesh: MultiMesh, transforms: Array) -> void:
	if not is_instance_valid(batch) or not multimesh or not multimesh.mesh:
		return
	if transforms.is_empty():
		return
	var bounds := AABB()
	var has_bounds := false
	for transform_variant: Variant in transforms:
		if not (transform_variant is Transform3D):
			continue
		var origin := (transform_variant as Transform3D).origin
		if has_bounds:
			bounds = bounds.expand(origin)
		else:
			bounds = AABB(origin, Vector3.ZERO)
			has_bounds = true
	if not has_bounds:
		return
	var grown := bounds.grow(CUSTOM_AABB_MARGIN_M)
	multimesh.custom_aabb = grown
	batch.custom_aabb = grown


func _get_batch_key(source: MeshInstance3D) -> String:
	var material: Material = source.material_override
	if not material:
		material = source.get_surface_override_material(0)
	return "%s:%s:%d:%d" % [
		_get_resource_batch_key(source.mesh),
		_get_resource_batch_key(material),
		int(corpse_shadow_mode),
		int(source.layers),
	]


func _get_resource_batch_key(resource: Resource) -> String:
	if not resource:
		return "0"
	if not resource.resource_path.is_empty():
		return resource.resource_path
	return str(resource.get_instance_id())
