extends Node3D
class_name TeamController

signal team_changed(summary: Dictionary)
signal recruitment_failed(reason: StringName, details: Dictionary)

const DEFAULT_TROOP_SCENE: PackedScene = preload("res://modules/troops/troop.tscn")
const CampScript = preload("res://modules/troops/camp.gd")

@export_group("Identity")
@export var team_id: StringName = &"player"
@export var display_name := "Player Team"
@export var controllable := true
@export var team_flag_color: Color = Color(0.1, 0.28, 0.82, 1.0)
@export var troop_flag_color: Color = Color(0.82, 0.12, 0.08, 1.0)

@export_group("Starting Camp")
@export var create_default_camp := true
@export var default_camp_id: StringName = &"starting_camp"
@export var default_camp_name := "Starting Camp"
@export var default_camp_position := Vector3.ZERO
@export_range(0.0, 100000.0, 1.0, "or_greater") var starting_food_kg: float = 240.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var starting_wood_kg: float = 180.0
@export_range(1.0, 512.0, 0.5, "or_greater") var default_camp_range_m: float = 28.0

@export_group("Owned Assets")
@export_node_path("Node") var primary_village_path: NodePath
@export var primary_troop_paths: Array[NodePath] = []
@export var movement_map: Resource
@export_file("*.res", "*.tres") var movement_map_path := ""
@export_node_path("Node3D") var terrain_path: NodePath
@export_node_path("Node") var time_system_path: NodePath

@export_group("Recruitment")
@export_range(0.0, 1000.0, 0.1, "or_greater") var recruit_food_cost_kg: float = 2.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var recruit_wood_cost_kg: float = 1.0

@export_group("Initial Troops")
@export var spawn_initial_troops := false
@export var troop_scene: PackedScene = DEFAULT_TROOP_SCENE
@export var spawn_seed: int = 93017
@export_range(1, 12, 1, "or_greater") var min_initial_troops: int = 1
@export_range(1, 12, 1, "or_greater") var max_initial_troops: int = 1
@export_range(2, 256, 1, "or_greater") var min_soldiers_per_troop: int = 12
@export_range(2, 256, 1, "or_greater") var max_soldiers_per_troop: int = 12
@export_range(0.0, 512.0, 1.0, "or_greater") var spawn_radius_m: float = 14.0
@export var troop_display_prefix := "Troop"

@export_group("AI")
@export var ai_enabled := false
@export_range(0.2, 30.0, 0.1, "or_greater") var ai_tick_seconds: float = 3.0
@export_range(1.0, 2048.0, 1.0, "or_greater") var ai_attack_radius_m: float = 240.0
@export_range(1, 256, 1, "or_greater") var ai_retreat_active_soldiers: int = 8
@export_range(0.0, 1.0, 0.01) var ai_retreat_food_shortage_ratio: float = 0.45

var _rng := RandomNumberGenerator.new()
var _camp: Node
var _owned_troops: Array[Node] = []
var _spawned_troops: Array[Node] = []
var _initialized := false
var _ai_tick_remaining := 0.0


func _ready() -> void:
	add_to_group(&"team_controllers")
	_rng.seed = maxi(spawn_seed, 1)
	_initialize_team.call_deferred()


func _exit_tree() -> void:
	remove_from_group(&"team_controllers")


func _process(delta: float) -> void:
	if not _initialized or not ai_enabled:
		return
	_ai_tick_remaining -= delta
	if _ai_tick_remaining > 0.0:
		return
	_ai_tick_remaining = ai_tick_seconds
	_run_ai_tick()


func spawn_enemies() -> Array[Node]:
	if not _initialized:
		_initialize_team()
	return _spawn_initial_troops()


func get_spawned_troops() -> Array[Node]:
	return _spawned_troops.duplicate()


func get_team_summary() -> Dictionary:
	var troop_count := 0
	var active_soldiers := 0
	for troop: Node in _get_owned_troops():
		troop_count += 1
		if troop.has_method("get_active_soldier_count"):
			active_soldiers += maxi(int(troop.call("get_active_soldier_count")), 0)
		elif troop.has_method("get_soldier_count"):
			active_soldiers += maxi(int(troop.call("get_soldier_count")), 0)
	var camp_summary := _get_camp_summary()
	return {
		"entity_type": &"team",
		"team_id": team_id,
		"display_name": display_name,
		"controllable": controllable,
		"camp": camp_summary,
		"troop_count": troop_count,
		"active_soldier_count": active_soldiers,
		"food_kg": float(camp_summary.get("camp_food_kg", 0.0)),
		"wood_kg": float(camp_summary.get("camp_wood_kg", 0.0)),
	}


func recruit_soldiers_from_village(village: Node, count: int) -> Dictionary:
	var requested := maxi(count, 0)
	if requested <= 0:
		return _recruitment_failure(&"invalid_count", {"requested": requested})
	if not village or not village.has_method("get_available_recruit_count") or not village.has_method("recruit_villagers"):
		return _recruitment_failure(&"invalid_village", {"requested": requested})

	var troop := _get_primary_troop()
	if not troop or not troop.has_method("add_recruited_soldiers"):
		return _recruitment_failure(&"missing_primary_troop", {"requested": requested})

	var camp := _get_or_create_camp()
	if not camp:
		return _recruitment_failure(&"missing_camp", {"requested": requested})

	var available := maxi(int(village.call("get_available_recruit_count")), 0)
	var by_food := requested
	if recruit_food_cost_kg > 0.0:
		by_food = floori(_get_camp_food_kg(camp) / recruit_food_cost_kg)
	var by_wood := requested
	if recruit_wood_cost_kg > 0.0:
		by_wood = floori(_get_camp_wood_kg(camp) / recruit_wood_cost_kg)
	var recruit_count := mini(requested, mini(available, mini(by_food, by_wood)))
	if recruit_count <= 0:
		return _recruitment_failure(&"insufficient_population_or_resources", {
			"requested": requested,
			"available_villagers": available,
			"camp_food_kg": _get_camp_food_kg(camp),
			"camp_wood_kg": _get_camp_wood_kg(camp),
		})

	var food_cost := float(recruit_count) * recruit_food_cost_kg
	var wood_cost := float(recruit_count) * recruit_wood_cost_kg
	_withdraw_camp_food(camp, food_cost)
	_withdraw_camp_wood(camp, wood_cost)
	var recruited := maxi(int(village.call("recruit_villagers", recruit_count)), 0)
	if recruited <= 0:
		_deposit_camp_food(camp, food_cost)
		_deposit_camp_wood(camp, wood_cost)
		return _recruitment_failure(&"village_rejected_recruitment", {"requested": recruit_count})

	if recruited < recruit_count:
		_deposit_camp_food(camp, float(recruit_count - recruited) * recruit_food_cost_kg)
		_deposit_camp_wood(camp, float(recruit_count - recruited) * recruit_wood_cost_kg)

	var spawn_position := _get_village_spawn_position(village)
	var added := maxi(int(troop.call("add_recruited_soldiers", recruited, spawn_position)), 0)
	var result := {
		"accepted": added > 0,
		"reason": &"ok" if added > 0 else &"troop_rejected_recruits",
		"requested": requested,
		"recruited": recruited,
		"added_soldiers": added,
		"food_cost_kg": float(added) * recruit_food_cost_kg,
		"wood_cost_kg": float(added) * recruit_wood_cost_kg,
	}
	_emit_team_changed()
	return result


func _initialize_team() -> void:
	if _initialized:
		return
	_initialized = true
	_collect_existing_troops()
	if create_default_camp:
		_get_or_create_camp()
	if spawn_initial_troops:
		_spawn_initial_troops()
	_ai_tick_remaining = ai_tick_seconds
	_emit_team_changed()


func _collect_existing_troops() -> void:
	for path: NodePath in primary_troop_paths:
		var troop := get_node_or_null(path)
		if troop:
			_register_troop(troop)


func _register_troop(troop: Node) -> void:
	if not troop or _owned_troops.has(troop):
		return
	_owned_troops.append(troop)
	_set_if_present(troop, &"team_id", team_id)
	_set_if_present(troop, &"controllable", controllable)
	_set_if_present(troop, &"team_flag_color", team_flag_color)
	_set_if_present(troop, &"troop_flag_color", troop_flag_color)
	if movement_map:
		_set_if_present(troop, &"movement_map", movement_map)
	_set_if_present(troop, &"movement_map_path", movement_map_path)
	_set_if_present(troop, &"terrain_path", terrain_path)
	_set_if_present(troop, &"time_system_path", time_system_path)


func _get_or_create_camp() -> Node:
	if is_instance_valid(_camp):
		return _camp
	var camp := CampScript.new()
	camp.name = "DefaultCamp"
	camp.camp_id = default_camp_id
	camp.display_name = default_camp_name
	camp.team_id = team_id
	camp.controllable = controllable
	camp.food_kg = starting_food_kg
	camp.wood_kg = starting_wood_kg
	camp.camp_range_m = default_camp_range_m
	camp.team_flag_color = team_flag_color
	camp.camp_flag_color = troop_flag_color
	camp.top_level = true
	add_child(camp)
	camp.owner = null
	camp.global_position = default_camp_position if default_camp_position != Vector3.ZERO else global_position
	_camp = camp
	if camp.has_signal(&"logistics_changed"):
		var callable := Callable(self, "_on_camp_logistics_changed")
		if not camp.is_connected(&"logistics_changed", callable):
			camp.connect(&"logistics_changed", callable)
	return _camp


func _spawn_initial_troops() -> Array[Node]:
	if not _spawned_troops.is_empty():
		return _spawned_troops.duplicate()
	var scene := troop_scene if troop_scene else DEFAULT_TROOP_SCENE
	var count := _rng.randi_range(mini(min_initial_troops, max_initial_troops), maxi(min_initial_troops, max_initial_troops))
	var parent_node := get_parent() if get_parent() else self
	for index: int in range(count):
		var instance := scene.instantiate()
		if not (instance is Node3D):
			instance.free()
			continue
		var troop := instance as Node3D
		troop.name = "%sTroop_%02d" % [String(team_id).capitalize(), index + 1]
		_configure_spawned_troop(troop, index)
		var spawn_position := _make_spawn_position(index, count)
		if parent_node is Node3D:
			troop.position = (parent_node as Node3D).to_local(spawn_position)
		else:
			troop.position = spawn_position
		troop.rotation.y = _rng.randf_range(-PI, PI)
		parent_node.add_child(troop)
		troop.owner = null
		_register_troop(troop)
		_spawned_troops.append(troop)
	return _spawned_troops.duplicate()


func _configure_spawned_troop(troop: Node3D, index: int) -> void:
	_set_if_present(troop, &"troop_id", "%s_%02d" % [str(team_id), index + 1])
	_set_if_present(troop, &"display_name", "%s %02d" % [troop_display_prefix, index + 1])
	_set_if_present(troop, &"soldier_count", _rng.randi_range(min_soldiers_per_troop, max_soldiers_per_troop))
	_set_if_present(troop, &"troop_mode", "attack" if ai_enabled else "defensive")
	_set_if_present(troop, &"movement_mode", "walking")
	_set_if_present(troop, &"combat_seed", spawn_seed + index * 101)


func _make_spawn_position(index: int, count: int) -> Vector3:
	var center := default_camp_position if default_camp_position != Vector3.ZERO else global_position
	var angle := TAU * float(index) / float(maxi(count, 1)) + _rng.randf_range(-0.45, 0.45)
	var radius := _rng.randf_range(spawn_radius_m * 0.45, maxf(spawn_radius_m, 0.1))
	return center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _run_ai_tick() -> void:
	var camp := _get_or_create_camp()
	var camp_position := global_position
	if camp is Node3D:
		camp_position = (camp as Node3D).global_position
	for troop: Node in _get_owned_troops():
		if _should_retreat_to_camp(troop):
			_order_troop_to_camp(troop, camp_position)
			continue
		var target := _find_best_attack_target(troop)
		if target:
			if troop.has_method("command_attack_troop"):
				troop.call("command_attack_troop", target)
		elif troop.has_method("set_move_destination"):
			var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
			if not bool(summary.get("has_destination", false)):
				troop.call("set_move_destination", _make_patrol_position(camp_position), false)


func _should_retreat_to_camp(troop: Node) -> bool:
	if not troop or not troop.has_method("get_troop_summary"):
		return false
	var summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	var active := int(summary.get("active_soldier_count", summary.get("soldier_count", 0)))
	var shortage := float(summary.get("food_shortage_ratio", 0.0))
	return active <= ai_retreat_active_soldiers or shortage >= ai_retreat_food_shortage_ratio


func _order_troop_to_camp(troop: Node, camp_position: Vector3) -> void:
	if troop.has_method("set_troop_mode"):
		troop.call("set_troop_mode", &"rest")
	if troop.has_method("set_movement_mode"):
		troop.call("set_movement_mode", &"walking")
	if troop.has_method("set_move_destination"):
		troop.call("set_move_destination", camp_position, false)


func _find_best_attack_target(troop: Node) -> Node:
	if not (troop is Node3D):
		return null
	var troop_position := (troop as Node3D).global_position
	var troop_summary: Dictionary = troop.call("get_troop_summary") as Dictionary
	var own_active := maxf(float(troop_summary.get("active_soldier_count", troop_summary.get("soldier_count", 1))), 1.0)
	var best: Node
	var best_score := -INF
	var root := get_tree().current_scene if get_tree() else get_parent()
	if not root:
		root = get_tree().root if get_tree() else null
	for candidate: Node in _collect_nodes_with_method(root, "get_troop_summary"):
		if candidate == troop or not (candidate is Node3D):
			continue
		var summary: Dictionary = candidate.call("get_troop_summary") as Dictionary
		if str(summary.get("team_id", "")) == str(team_id):
			continue
		if bool(summary.get("defeated", false)):
			continue
		var distance := troop_position.distance_to((candidate as Node3D).global_position)
		if distance > ai_attack_radius_m:
			continue
		var enemy_active := maxf(float(summary.get("active_soldier_count", summary.get("soldier_count", 1))), 1.0)
		var weakness := clampf(own_active / enemy_active, 0.25, 4.0)
		var proximity := 1.0 - clampf(distance / maxf(ai_attack_radius_m, 1.0), 0.0, 1.0)
		var score := 0.55 * weakness + 0.45 * proximity
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _make_patrol_position(camp_position: Vector3) -> Vector3:
	var radius := maxf(default_camp_range_m * 0.75, 8.0)
	var angle := _rng.randf_range(0.0, TAU)
	return camp_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _get_owned_troops() -> Array[Node]:
	for index: int in range(_owned_troops.size() - 1, -1, -1):
		if not is_instance_valid(_owned_troops[index]):
			_owned_troops.remove_at(index)
	return _owned_troops.duplicate()


func _get_primary_troop() -> Node:
	var troops := _get_owned_troops()
	return troops[0] if not troops.is_empty() else null


func _get_camp_summary() -> Dictionary:
	var camp := _get_or_create_camp()
	if camp and camp.has_method("get_management_summary"):
		return camp.call("get_management_summary") as Dictionary
	return {}


func _get_village_spawn_position(village: Node) -> Vector3:
	if village and village.has_method("get_village_storage_world_position"):
		var value: Variant = village.call("get_village_storage_world_position")
		if value is Vector3:
			return value as Vector3
	if village is Node3D:
		return (village as Node3D).global_position
	return global_position


func _collect_nodes_with_method(root: Node, method_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if not root:
		return found
	if root.has_method(method_name):
		found.append(root)
	for child: Node in root.get_children():
		found.append_array(_collect_nodes_with_method(child, method_name))
	return found


func _get_camp_food_kg(camp: Node) -> float:
	if not camp:
		return 0.0
	return maxf(float(camp.get("food_kg")), 0.0)


func _get_camp_wood_kg(camp: Node) -> float:
	if not camp:
		return 0.0
	return maxf(float(camp.get("wood_kg")), 0.0)


func _withdraw_camp_food(camp: Node, amount: float) -> float:
	if camp and camp.has_method("withdraw_food_kg"):
		return maxf(float(camp.call("withdraw_food_kg", amount)), 0.0)
	return 0.0


func _withdraw_camp_wood(camp: Node, amount: float) -> float:
	if camp and camp.has_method("withdraw_wood_kg"):
		return maxf(float(camp.call("withdraw_wood_kg", amount)), 0.0)
	return 0.0


func _deposit_camp_food(camp: Node, amount: float) -> float:
	if camp and camp.has_method("deposit_food_kg"):
		return maxf(float(camp.call("deposit_food_kg", amount)), 0.0)
	return 0.0


func _deposit_camp_wood(camp: Node, amount: float) -> float:
	if camp and camp.has_method("deposit_wood_kg"):
		return maxf(float(camp.call("deposit_wood_kg", amount)), 0.0)
	return 0.0


func _recruitment_failure(reason: StringName, details: Dictionary) -> Dictionary:
	var result := details.duplicate(true)
	result["accepted"] = false
	result["reason"] = reason
	recruitment_failed.emit(reason, result.duplicate(true))
	return result


func _emit_team_changed() -> void:
	team_changed.emit(get_team_summary())


func _on_camp_logistics_changed(_summary: Dictionary) -> void:
	_emit_team_changed()


func _set_if_present(object: Object, property_name: StringName, value: Variant) -> void:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == str(property_name):
			object.set(str(property_name), value)
			return
