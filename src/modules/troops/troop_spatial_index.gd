extends RefCounted
class_name TroopSpatialIndex

var _grid: Dictionary = {}
var _bucket_pool: Array[Array] = []
var _cell_size := 1.0
var _rebuild_count := 0
var max_query_ring := 8


func rebuild(nodes: Array, cell_size: float) -> void:
	_cell_size = maxf(cell_size, 0.1)
	_recycle_buckets()
	for node: Variant in nodes:
		if not (node is Node3D):
			continue
		var spatial := node as Node3D
		var cell := _get_cell(spatial.global_position)
		var bucket: Array
		if _grid.has(cell):
			bucket = _grid[cell] as Array
		else:
			bucket = _take_bucket()
			_grid[cell] = bucket
		bucket.append(spatial)
	_rebuild_count += 1


func query(position: Vector3, max_count: int, out_array: Array[Node3D]) -> void:
	out_array.clear()
	if _grid.is_empty():
		return
	var center := _get_cell(position)
	var limit := maxi(max_count, 1)
	var ring_limit := maxi(max_query_ring, 1)
	for ring: int in range(0, ring_limit + 1):
		for x: int in range(center.x - ring, center.x + ring + 1):
			for y: int in range(center.y - ring, center.y + ring + 1):
				if ring > 0 and x > center.x - ring and x < center.x + ring and y > center.y - ring and y < center.y + ring:
					continue
				var bucket_variant: Variant = _grid.get(Vector2i(x, y))
				if not (bucket_variant is Array):
					continue
				var bucket := bucket_variant as Array
				for node: Variant in bucket:
					if not (node is Node3D):
						continue
					out_array.append(node as Node3D)
					if out_array.size() >= limit:
						return


func clear() -> void:
	_recycle_buckets()


func get_rebuild_count() -> int:
	return _rebuild_count


func reset_rebuild_count() -> void:
	_rebuild_count = 0


func _recycle_buckets() -> void:
	for bucket_variant: Variant in _grid.values():
		if bucket_variant is Array:
			var bucket := bucket_variant as Array
			bucket.clear()
			_bucket_pool.append(bucket)
	_grid.clear()


func _take_bucket() -> Array:
	if _bucket_pool.is_empty():
		return []
	var bucket := _bucket_pool.pop_back() as Array
	bucket.clear()
	return bucket


func _get_cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / _cell_size), floori(position.z / _cell_size))
