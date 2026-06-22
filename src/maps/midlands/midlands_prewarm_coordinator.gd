extends Node
class_name MidlandsPrewarmCoordinator

signal prewarm_completed

@export var auto_start := true
@export_node_path("Node") var player_troop_path: NodePath = NodePath("../Troop_01")
@export_node_path("Node") var enemy_spawner_path: NodePath = NodePath("../EnemyTroopSpawner")
@export_node_path("Node") var village_region_path: NodePath = NodePath("../VillageRegion")
@export_node_path("Node") var forest_region_path: NodePath = NodePath("../ForestRegion")
@export_node_path("Node") var macro_atlas_path: NodePath = NodePath("../MacroDetailAtlas")
@export_node_path("Node") var macro_overlay_path: NodePath = NodePath("../MacroDetailOverlay")

var _prewarm_started := false
var _prewarm_complete := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_start:
		prewarm_async.call_deferred()


func is_prewarm_complete() -> bool:
	return _prewarm_complete


func prewarm_async() -> void:
	if _prewarm_complete:
		return
	if _prewarm_started:
		while not _prewarm_complete and is_inside_tree():
			await get_tree().process_frame
		return

	_prewarm_started = true
	_mark_startup_phase("midlands_prewarm_start")
	await get_tree().process_frame
	if not is_inside_tree():
		return

	await _prewarm_troop(get_node_or_null(player_troop_path), "player_troop")
	await _spawn_and_prewarm_enemies()
	await _prewarm_runtime_region(get_node_or_null(village_region_path), "village")
	await _prewarm_runtime_region(get_node_or_null(forest_region_path), "forest")
	_rebuild_macro_detail()
	await get_tree().process_frame
	await get_tree().process_frame

	_prewarm_complete = true
	_mark_startup_phase("midlands_prewarm_ready")
	prewarm_completed.emit()


func _spawn_and_prewarm_enemies() -> void:
	var spawner := get_node_or_null(enemy_spawner_path)
	if not spawner or not spawner.has_method("spawn_enemies"):
		return

	_mark_startup_phase("midlands_enemy_spawn_start")
	var spawned_variant: Variant = spawner.call("spawn_enemies")
	var spawned: Array = spawned_variant if spawned_variant is Array else []
	_mark_startup_phase("midlands_enemy_spawned", {"troops": spawned.size()})
	for troop: Node in spawned:
		await _prewarm_troop(troop, "enemy_troop")


func _prewarm_troop(troop: Node, label: String) -> void:
	if not troop:
		return
	_mark_startup_phase("midlands_%s_prewarm_start" % label, {
		"soldiers": _get_int_property(troop, &"soldier_count"),
	})
	if troop.has_method("prewarm_async"):
		await troop.call("prewarm_async")
	elif troop.has_method("rebuild_formation"):
		troop.call("rebuild_formation")
		await get_tree().process_frame
	_mark_startup_phase("midlands_%s_prewarm_ready" % label)


func _prewarm_runtime_region(region: Node, label: String) -> void:
	if not region or not region.has_method("rebuild_runtime_preview_async"):
		return
	_mark_startup_phase("midlands_%s_prewarm_start" % label)
	await region.call("rebuild_runtime_preview_async")
	_mark_startup_phase("midlands_%s_prewarm_ready" % label)


func _rebuild_macro_detail() -> void:
	var atlas := get_node_or_null(macro_atlas_path)
	if atlas and atlas.has_method("rebuild"):
		_mark_startup_phase("midlands_macro_atlas_start")
		atlas.call("rebuild")
		_mark_startup_phase("midlands_macro_atlas_ready")

	var overlay := get_node_or_null(macro_overlay_path)
	if overlay and overlay.has_method("rebuild_overlay"):
		_mark_startup_phase("midlands_macro_overlay_start")
		overlay.call("rebuild_overlay")
		_mark_startup_phase("midlands_macro_overlay_ready")


func _get_int_property(object: Object, property_name: StringName) -> int:
	if not object:
		return 0
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return int(object.get(String(property_name)))
	return 0


func _mark_startup_phase(label: String, context: Dictionary = {}) -> void:
	var probe := get_node_or_null("/root/StartupPerformanceProbe")
	if probe and probe.has_method("mark_phase"):
		probe.call("mark_phase", label, context)
