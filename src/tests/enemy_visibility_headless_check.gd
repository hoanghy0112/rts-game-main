extends SceneTree

const SCENE_PATHS: Array[String] = [
	"res://modules/draft/draft.tscn",
	"res://maps/midlands/midlands.tscn",
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	await process_frame
	for scene_path: String in SCENE_PATHS:
		await _check_scene(scene_path, failures)

	if failures.is_empty():
		print("Enemy visibility headless check passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _check_scene(scene_path: String, failures: Array[String]) -> void:
	var packed_scene := load(scene_path) as PackedScene
	_expect(packed_scene != null, "%s should load" % scene_path, failures)
	if not packed_scene:
		return

	var instance := packed_scene.instantiate() as Node3D
	_expect(instance != null, "%s should instantiate as Node3D" % scene_path, failures)
	if not instance:
		return

	root.add_child(instance)
	await process_frame
	await physics_frame
	await process_frame

	var spawner := instance.find_child("EnemyTroopSpawner", true, false)
	_expect(spawner != null, "%s should include EnemyTroopSpawner" % scene_path, failures)
	var player := instance.find_child("Troop_01", true, false) as Node3D
	_expect(player != null, "%s should include Troop_01" % scene_path, failures)
	var camera := instance.find_child("Camera3D", true, false) as Camera3D
	_expect(camera != null, "%s should include Camera3D" % scene_path, failures)

	var spawned: Array = []
	if spawner and spawner.has_method("get_spawned_troops"):
		spawned = spawner.call("get_spawned_troops") as Array
	_expect(spawned.size() > 0, "%s should spawn enemy troops when the scene enters the tree" % scene_path, failures)

	for enemy_variant: Variant in spawned:
		var enemy := enemy_variant as Node3D
		_expect(enemy != null and enemy.is_inside_tree(), "%s spawned enemy should be in the scene tree" % scene_path, failures)
		if not enemy:
			continue
		_expect(enemy.visible, "%s/%s enemy troop root should be visible" % [scene_path, enemy.name], failures)
		_expect(StringName(enemy.get("team_id")) == &"enemy", "%s/%s should use enemy team id" % [scene_path, enemy.name], failures)
		_expect(not bool(enemy.get("controllable")), "%s/%s should not be controllable" % [scene_path, enemy.name], failures)

		var soldiers := enemy.find_child("Soldiers", false, false) as Node3D
		_expect(soldiers != null, "%s/%s should have a Soldiers container" % [scene_path, enemy.name], failures)
		if soldiers:
			_expect(soldiers.get_child_count() > 0, "%s/%s should have visible soldier instances" % [scene_path, enemy.name], failures)

		if player:
			var distance_to_player := enemy.global_position.distance_to(player.global_position)
			_expect(
				distance_to_player <= 90.0,
				"%s/%s should spawn near the starting player troop, got %.2fm at %s vs player %s" % [
					scene_path,
					enemy.name,
					distance_to_player,
					str(enemy.global_position),
					str(player.global_position),
				],
				failures
			)
		if camera:
			var eye_level := enemy.global_position + Vector3(0.0, 1.6, 0.0)
			_expect(
				camera.is_position_in_frustum(eye_level),
				"%s/%s should start inside the camera view, enemy %s camera %s" % [
					scene_path,
					enemy.name,
					str(eye_level),
					str(camera.global_position),
				],
				failures
			)

	instance.queue_free()
	for _index: int in range(4):
		await process_frame
		await physics_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
