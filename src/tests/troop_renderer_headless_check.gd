extends SceneTree

const TroopSoldierBatchRendererScript = preload("res://modules/troops/troop_soldier_batch_renderer.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	await process_frame
	_check_buffer_sync_preserves_global_transforms(failures)
	_check_buffer_sync_preserves_local_transforms(failures)
	if failures.is_empty():
		print("Troop renderer headless check passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _check_buffer_sync_preserves_global_transforms(failures: Array[String]) -> void:
	var group := Node3D.new()
	root.add_child(group)
	var renderer := TroopSoldierBatchRendererScript.new()
	renderer.name = "RendererGlobal"
	renderer.multimesh_buffer_sync_enabled = true
	group.add_child(renderer)
	var soldiers := _make_soldiers(group)
	renderer.set_soldiers(soldiers)
	renderer.sync(true)
	_expect_batch_transforms_match_sources(renderer, soldiers, false, "global", failures)
	group.queue_free()


func _check_buffer_sync_preserves_local_transforms(failures: Array[String]) -> void:
	var group := Node3D.new()
	group.transform = Transform3D(Basis().rotated(Vector3.UP, 0.37), Vector3(21.0, 0.5, -13.0))
	root.add_child(group)
	var renderer := TroopSoldierBatchRendererScript.new()
	renderer.name = "RendererLocal"
	renderer.multimesh_buffer_sync_enabled = true
	group.add_child(renderer)
	var soldiers := _make_soldiers(group)
	renderer.set_soldiers(soldiers)
	renderer.set_local_space_enabled(true)
	renderer.sync(true)
	_expect_batch_transforms_match_sources(renderer, soldiers, true, "local", failures)
	group.queue_free()


func _make_soldiers(parent: Node3D) -> Array[Node]:
	var soldiers: Array[Node] = []
	var mesh := BoxMesh.new()
	for index: int in range(3):
		var soldier := Node3D.new()
		soldier.name = "Soldier_%03d" % index
		var basis := Basis().rotated(Vector3.UP, 0.25 + float(index) * 0.41)
		soldier.transform = Transform3D(basis, Vector3(float(index) * 3.5, 0.0, float(index) * -1.75))
		parent.add_child(soldier)
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = mesh
		body.transform = Transform3D(
			Basis().rotated(Vector3.RIGHT, 0.1 + float(index) * 0.07).scaled(Vector3(0.7, 1.8, 0.45)),
			Vector3(0.15 * float(index), 0.9, -0.2)
		)
		soldier.add_child(body)
		soldiers.append(soldier)
	return soldiers


func _expect_batch_transforms_match_sources(
	renderer: Node3D,
	soldiers: Array[Node],
	local_space: bool,
	label: String,
	failures: Array[String]
) -> void:
	_expect(renderer.get_child_count() == 1, "%s renderer should create one test mesh batch" % label, failures)
	if renderer.get_child_count() == 0:
		return
	var batch := renderer.get_child(0) as MultiMeshInstance3D
	_expect(batch != null and batch.multimesh != null, "%s renderer should create a multimesh batch" % label, failures)
	if not batch or not batch.multimesh:
		return
	var batch_inverse := batch.global_transform.affine_inverse() if local_space else Transform3D.IDENTITY
	var buffer: PackedFloat32Array = batch.multimesh.buffer
	_expect(buffer.size() >= soldiers.size() * 12, "%s packed buffer should contain one 3D transform per source" % label, failures)
	for index: int in range(soldiers.size()):
		var soldier := soldiers[index] as Node3D
		var source := soldier.get_node_or_null("Body") as MeshInstance3D
		var expected := batch_inverse * source.global_transform if local_space else source.global_transform
		var actual := _read_transform_from_multimesh_buffer(buffer, index)
		_expect_transform_close(
			actual,
			expected,
			"%s batched transform %d should match source transform after packed buffer sync" % [label, index],
			failures
		)
		_expect(not source.visible, "%s source mesh %d should be hidden after batching" % [label, index], failures)
	_expect(batch.multimesh.visible_instance_count == soldiers.size(), "%s visible instance count should match visible soldiers" % label, failures)


func _read_transform_from_multimesh_buffer(buffer: PackedFloat32Array, index: int) -> Transform3D:
	var offset := index * 12
	return Transform3D(
		Basis(
			Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])
		),
		Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
	)


func _expect_transform_close(actual: Transform3D, expected: Transform3D, label: String, failures: Array[String]) -> void:
	_expect(actual.origin.distance_to(expected.origin) <= 0.01, "%s origin mismatch: got %s expected %s" % [label, actual.origin, expected.origin], failures)
	_expect(actual.basis.x.distance_to(expected.basis.x) <= 0.01, "%s basis x mismatch: got %s expected %s" % [label, actual.basis.x, expected.basis.x], failures)
	_expect(actual.basis.y.distance_to(expected.basis.y) <= 0.01, "%s basis y mismatch: got %s expected %s" % [label, actual.basis.y, expected.basis.y], failures)
	_expect(actual.basis.z.distance_to(expected.basis.z) <= 0.01, "%s basis z mismatch: got %s expected %s" % [label, actual.basis.z, expected.basis.z], failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
