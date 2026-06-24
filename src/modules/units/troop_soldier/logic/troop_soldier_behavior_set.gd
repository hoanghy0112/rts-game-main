extends Resource
class_name TroopSoldierBehaviorSet

const DefaultWalkLogicScript = preload("res://modules/units/troop_soldier/logic/troop_soldier_walk_logic.gd")
const DefaultRunLogicScript = preload("res://modules/units/troop_soldier/logic/troop_soldier_run_logic.gd")
const DefaultFightLogicScript = preload("res://modules/units/troop_soldier/logic/troop_soldier_fight_logic.gd")

@export var walk_logic: Resource
@export var run_logic: Resource
@export var fight_logic: Resource


func ensure_defaults() -> void:
	if not walk_logic:
		walk_logic = DefaultWalkLogicScript.new()
	if not run_logic:
		run_logic = DefaultRunLogicScript.new()
	if not fight_logic:
		fight_logic = DefaultFightLogicScript.new()


func duplicate_for_runtime() -> Resource:
	var copy := duplicate(true)
	if not copy:
		copy = load("res://modules/units/troop_soldier/logic/troop_soldier_behavior_set.gd").new()
	copy.ensure_defaults()
	return copy
