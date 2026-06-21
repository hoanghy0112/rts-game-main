extends Node3D
class_name TroopEnemySpawner

const DEFAULT_TROOP_SCENE: PackedScene = preload("res://modules/troops/troop.tscn")

@export var enabled := true
@export var troop_scene: PackedScene = DEFAULT_TROOP_SCENE
@export var spawn_seed: int = 93017
@export_range(1, 12, 1, "or_greater") var min_enemy_troops: int = 2
@export_range(1, 12, 1, "or_greater") var max_enemy_troops: int = 3
@export_range(2, 256, 1, "or_greater") var min_soldiers_per_troop: int = 8
@export_range(2, 256, 1, "or_greater") var max_soldiers_per_troop: int = 18
@export_range(0.0, 512.0, 1.0, "or_greater") var spawn_radius_m: float = 28.0
@export var enemy_team_id: StringName = &"enemy"
@export var enemy_display_prefix := "Enemy"
@export var enemy_team_flag_color: Color = Color(0.55, 0.06, 0.05, 1.0)
@export var enemy_troop_flag_color: Color = Color(0.12, 0.1, 0.1, 1.0)
@export var enemy_ring_color: Color = Color(0.95, 0.12, 0.08, 0.64)
@export var enemy_selected_ring_color: Color = Color(1.0, 0.36, 0.22, 0.86)
@export var enemy_robe_color: Color = Color(0.42, 0.05, 0.04, 1.0)
@export var enemy_robe_shadow_color: Color = Color(0.16, 0.02, 0.02, 1.0)
@export var enemy_trim_color: Color = Color(0.94, 0.52, 0.24, 1.0)
@export var enemy_pants_color: Color = Color(0.16, 0.12, 0.11, 1.0)
@export var enemy_wrap_color: Color = Color(0.56, 0.47, 0.39, 1.0)
@export var enemy_hat_color: Color = Color(0.05, 0.04, 0.035, 1.0)
@export var enemy_accent_color: Color = Color(0.98, 0.18, 0.08, 1.0)
@export var movement_map: Resource
@export_file("*.res", "*.tres") var movement_map_path := ""
@export_node_path("Node3D") var terrain_path: NodePath = NodePath("../Terrain3D")
@export_node_path("Node") var time_system_path: NodePath = NodePath("../GameTimeSystem")

var _spawned := false
var _spawned_troops: Array[Node] = []


func _ready() -> void:
	if enabled:
		spawn_enemies.call_deferred()


func spawn_enemies() -> Array[Node]:
	if _spawned:
		return _spawned_troops.duplicate()
	_spawned = true

	var scene := troop_scene if troop_scene else DEFAULT_TROOP_SCENE
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(spawn_seed, 1)
	var count := rng.randi_range(mini(min_enemy_troops, max_enemy_troops), maxi(min_enemy_troops, max_enemy_troops))
	var parent_node := get_parent() if get_parent() else self

	for index: int in range(count):
		var instance := scene.instantiate()
		if not (instance is Node3D):
			instance.free()
			continue
		var troop := instance as Node3D
		troop.name = "EnemyTroop_%02d" % (index + 1)
		_configure_enemy_troop(troop, index, rng)
		var spawn_position := _make_spawn_position(rng, index, count)
		if parent_node is Node3D:
			troop.position = (parent_node as Node3D).to_local(spawn_position)
		else:
			troop.position = spawn_position
		troop.rotation.y = rng.randf_range(-PI, PI)
		parent_node.add_child(troop)
		troop.owner = null
		_spawned_troops.append(troop)
	return _spawned_troops.duplicate()


func get_spawned_troops() -> Array[Node]:
	return _spawned_troops.duplicate()


func _make_spawn_position(rng: RandomNumberGenerator, index: int, count: int) -> Vector3:
	var angle := TAU * float(index) / float(maxi(count, 1)) + rng.randf_range(-0.45, 0.45)
	var radius := rng.randf_range(spawn_radius_m * 0.45, spawn_radius_m)
	return global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _configure_enemy_troop(troop: Node3D, index: int, rng: RandomNumberGenerator) -> void:
	_set_if_present(troop, &"troop_id", StringName("enemy_%02d" % (index + 1)))
	_set_if_present(troop, &"display_name", "%s %02d" % [enemy_display_prefix, index + 1])
	_set_if_present(troop, &"team_id", enemy_team_id)
	_set_if_present(troop, &"controllable", false)
	_set_if_present(troop, &"troop_mode", "attack")
	_set_if_present(troop, &"movement_mode", "walking")
	_set_if_present(troop, &"combat_seed", spawn_seed + index * 101)
	_set_if_present(troop, &"soldier_count", rng.randi_range(min_soldiers_per_troop, max_soldiers_per_troop))
	_set_if_present(troop, &"team_flag_color", enemy_team_flag_color)
	_set_if_present(troop, &"troop_flag_color", enemy_troop_flag_color)
	_set_if_present(troop, &"ring_color", enemy_ring_color)
	_set_if_present(troop, &"selected_ring_color", enemy_selected_ring_color)
	_set_if_present(troop, &"soldier_robe_color", enemy_robe_color)
	_set_if_present(troop, &"soldier_robe_shadow_color", enemy_robe_shadow_color)
	_set_if_present(troop, &"soldier_trim_color", enemy_trim_color)
	_set_if_present(troop, &"soldier_pants_color", enemy_pants_color)
	_set_if_present(troop, &"soldier_wrap_color", enemy_wrap_color)
	_set_if_present(troop, &"soldier_hat_color", enemy_hat_color)
	_set_if_present(troop, &"soldier_accent_color", enemy_accent_color)
	if movement_map:
		_set_if_present(troop, &"movement_map", movement_map)
	_set_if_present(troop, &"movement_map_path", movement_map_path)
	_set_if_present(troop, &"terrain_path", terrain_path)
	_set_if_present(troop, &"time_system_path", time_system_path)


func _set_if_present(object: Object, property_name: StringName, value: Variant) -> void:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			object.set(String(property_name), value)
			return
