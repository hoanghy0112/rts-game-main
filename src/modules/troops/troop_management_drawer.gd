extends CanvasLayer
class_name TroopManagementDrawer

signal collect_food_requested(troop: Node, amount_kg: float)
signal collect_wood_requested(troop: Node, soldier_count: int)

const TROOP_MODE_OPTIONS := [
	{"label": "Rest", "value": &"rest"},
	{"label": "Training", "value": &"training"},
	{"label": "Defensive", "value": &"defensive"},
	{"label": "Attack", "value": &"attack"},
]
const MOVEMENT_MODE_OPTIONS := [
	{"label": "Walking", "value": &"walking"},
	{"label": "Running", "value": &"running"},
]
const TEAM_PLAYER := &"player"

@onready var _root_control: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _state_label: Label = %StateLabel
@onready var _troop_mode_option: OptionButton = %TroopModeOption
@onready var _movement_mode_option: OptionButton = %MovementModeOption
@onready var _combat_label: Label = %CombatLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _mission_label: Label = %MissionLabel
@onready var _continue_mission_button: Button = %ContinueMissionButton
@onready var _failure_label: Label = %FailureLabel
@onready var _stop_button: Button = %StopButton
@onready var _clear_button: Button = %ClearButton
@onready var _load_label: Label = %LoadLabel
@onready var _assets_label: Label = %AssetsLabel
@onready var _carrier_label: Label = %CarrierLabel
@onready var _camp_label: Label = %CampLabel
@onready var _food_amount_spin_box: SpinBox = %FoodAmountSpinBox
@onready var _collect_food_button: Button = %CollectFoodButton
@onready var _wood_soldiers_spin_box: SpinBox = %WoodSoldiersSpinBox
@onready var _collect_wood_button: Button = %CollectWoodButton
@onready var _craft_trolley_button: Button = %CraftTrolleyButton
@onready var _establish_camp_button: Button = %EstablishCampButton
@onready var _pack_camp_button: Button = %PackCampButton
@onready var _camp_transfer_label: Label = %CampTransferLabel
@onready var _camp_transfer_spin_box: SpinBox = %CampTransferSpinBox
@onready var _take_food_button: Button = %TakeFoodButton
@onready var _give_food_button: Button = %GiveFoodButton
@onready var _take_wood_button: Button = %TakeWoodButton
@onready var _give_wood_button: Button = %GiveWoodButton
@onready var _persuade_deserters_button: Button = %PersuadeDesertersButton

var _troop: Node


func _ready() -> void:
	_cache_control_nodes()
	_setup_mode_options()
	if _troop_mode_option and not _troop_mode_option.item_selected.is_connected(_on_troop_mode_selected):
		_troop_mode_option.item_selected.connect(_on_troop_mode_selected)
	if _movement_mode_option and not _movement_mode_option.item_selected.is_connected(_on_movement_mode_selected):
		_movement_mode_option.item_selected.connect(_on_movement_mode_selected)
	if _stop_button and not _stop_button.pressed.is_connected(_on_stop_pressed):
		_stop_button.pressed.connect(_on_stop_pressed)
	if _clear_button and not _clear_button.pressed.is_connected(_on_clear_pressed):
		_clear_button.pressed.connect(_on_clear_pressed)
	if _continue_mission_button and not _continue_mission_button.pressed.is_connected(_on_continue_mission_pressed):
		_continue_mission_button.pressed.connect(_on_continue_mission_pressed)
	if _collect_food_button and not _collect_food_button.pressed.is_connected(_on_collect_food_pressed):
		_collect_food_button.pressed.connect(_on_collect_food_pressed)
	if _collect_wood_button and not _collect_wood_button.pressed.is_connected(_on_collect_wood_pressed):
		_collect_wood_button.pressed.connect(_on_collect_wood_pressed)
	if _craft_trolley_button and not _craft_trolley_button.pressed.is_connected(_on_craft_trolley_pressed):
		_craft_trolley_button.pressed.connect(_on_craft_trolley_pressed)
	if _establish_camp_button and not _establish_camp_button.pressed.is_connected(_on_establish_camp_pressed):
		_establish_camp_button.pressed.connect(_on_establish_camp_pressed)
	if _pack_camp_button and not _pack_camp_button.pressed.is_connected(_on_pack_camp_pressed):
		_pack_camp_button.pressed.connect(_on_pack_camp_pressed)
	if _take_food_button and not _take_food_button.pressed.is_connected(_on_take_food_pressed):
		_take_food_button.pressed.connect(_on_take_food_pressed)
	if _give_food_button and not _give_food_button.pressed.is_connected(_on_give_food_pressed):
		_give_food_button.pressed.connect(_on_give_food_pressed)
	if _take_wood_button and not _take_wood_button.pressed.is_connected(_on_take_wood_pressed):
		_take_wood_button.pressed.connect(_on_take_wood_pressed)
	if _give_wood_button and not _give_wood_button.pressed.is_connected(_on_give_wood_pressed):
		_give_wood_button.pressed.connect(_on_give_wood_pressed)
	if _persuade_deserters_button and not _persuade_deserters_button.pressed.is_connected(_on_persuade_deserters_pressed):
		_persuade_deserters_button.pressed.connect(_on_persuade_deserters_pressed)
	hide_drawer()


func _exit_tree() -> void:
	_unbind_troop()


func show_troop(troop: Node) -> void:
	_bind_troop(troop)
	if _cache_control_nodes():
		_root_control.visible = true
	refresh()


func hide_drawer() -> void:
	if _cache_control_nodes():
		_root_control.visible = false


func refresh() -> void:
	if not _cache_control_nodes() or not _troop or not _troop.has_method("get_troop_summary"):
		return

	var summary: Dictionary = _troop.call("get_troop_summary") as Dictionary
	var entity_type := StringName(summary.get("entity_type", &"troop"))
	var display_name := String(summary.get("display_name", "Troop"))
	var troop_id := String(summary.get("troop_id", ""))
	var soldier_count := int(summary.get("soldier_count", 0))
	var current_soldiers := int(summary.get("active_soldier_count", soldier_count))
	var state := String(summary.get("state", &"idle")).capitalize()
	var team_id := StringName(summary.get("team_id", TEAM_PLAYER))
	var troop_mode := StringName(summary.get("troop_mode", &"defensive"))
	var movement_mode := StringName(summary.get("movement_mode", &"walking"))
	var controllable := bool(summary.get("controllable", true))
	var read_only := _is_summary_read_only(summary)
	var in_combat := bool(summary.get("in_combat", false))
	var food_shortage := float(summary.get("food_shortage_ratio", 0.0))
	var avg_strength := float(summary.get("average_strength", 0.0))
	var avg_max_strength := float(summary.get("average_max_strength", 0.0))
	var avg_damage := float(summary.get("average_damage", 0.0))
	var avg_morale := float(summary.get("average_morale", 0.0))
	var avg_endurance := float(summary.get("average_endurance", 0.0))
	var avg_max_endurance := float(summary.get("average_max_endurance", 0.0))
	var avg_run_speed := float(summary.get("average_run_speed", 0.0))
	var min_run_speed := float(summary.get("minimum_run_speed", 0.0))
	var max_run_speed := float(summary.get("maximum_run_speed", 0.0))
	var has_destination := bool(summary.get("has_destination", false))
	var failure_reason := String(summary.get("failure_reason", &""))
	var carried_food := float(summary.get("carried_food_kg", 0.0))
	var carried_wood := float(summary.get("carried_wood_kg", 0.0))
	var current_load := float(summary.get("current_load_kg", 0.0))
	var capacity := float(summary.get("carry_capacity_kg", 0.0))
	var free_capacity := float(summary.get("free_capacity_kg", 0.0))
	var trolleys := int(summary.get("cargo_trolley_count", 0))
	var cows := int(summary.get("cow_count", 0))
	var available_carriers := int(summary.get("available_carrier_soldiers", 0))
	var busy_carriers := int(summary.get("busy_carrier_soldiers", 0))
	var camp_established := bool(summary.get("camp_established", false))
	var camp_food := float(summary.get("camp_food_kg", 0.0))
	var camp_wood := float(summary.get("camp_wood_kg", 0.0))
	var camp_cost := float(summary.get("camp_total_wood_cost_kg", 0.0))
	var camp_living_huts := int(summary.get("camp_living_hut_count", 1))
	var camp_soldiers_per_hut := int(summary.get("camp_soldiers_per_living_hut", 20))
	var camp_pack_range := float(summary.get("camp_pack_range_m", 0.0))
	var camp_pack_in_range := bool(summary.get("camp_pack_in_range", false))
	var mission_active := bool(summary.get("mission_active", false))
	var mission_label := String(summary.get("mission_label", ""))
	var can_continue_mission := bool(summary.get("can_continue_mission", false))
	var nearby_camp_in_range := bool(summary.get("nearby_camp_in_range", false))
	var nearby_camp_food := float(summary.get("nearby_camp_food_kg", 0.0))
	var nearby_camp_wood := float(summary.get("nearby_camp_wood_kg", 0.0))
	var trolley_cost := float(summary.get("cargo_trolley_wood_cost_kg", 0.0))
	var trolley_crafting := bool(summary.get("cargo_trolley_crafting", false))
	var trolley_craft_remaining := float(summary.get("cargo_trolley_craft_remaining_seconds", 0.0))
	var trolley_craft_seconds := float(summary.get("cargo_trolley_craft_seconds", 5.0))

	_title_label.text = display_name
	_state_label.text = "State  %s" % state
	if entity_type == &"camp":
		_apply_camp_visibility()
		_subtitle_label.text = "%s  Team %s" % [troop_id, String(team_id).capitalize()]
		_camp_label.text = "Camp  %s food   %s wood   range %.0fm" % [
			_format_kg(camp_food),
			_format_kg(camp_wood),
			float(summary.get("camp_range_m", camp_pack_range)),
		]
		_assets_label.text = "Stored  %s food   %s wood" % [_format_kg(camp_food), _format_kg(camp_wood)]
		return
	if read_only:
		_apply_read_only_visibility(true)
		_subtitle_label.text = "%s  Team %s" % [troop_id, String(team_id).capitalize()]
		_combat_label.text = "Combat  %s   Troops %d" % [
			"engaged" if in_combat else "ready",
			current_soldiers,
		]
		_stats_label.text = "Troops  %d soldiers" % current_soldiers
		_troop_mode_option.disabled = true
		_movement_mode_option.disabled = true
		return

	_apply_read_only_visibility(false)
	_subtitle_label.text = "%s  %d soldiers" % [troop_id, current_soldiers]
	_select_option_value(_troop_mode_option, troop_mode)
	_select_option_value(_movement_mode_option, movement_mode)
	_troop_mode_option.disabled = not controllable
	_movement_mode_option.disabled = not controllable
	_combat_label.text = "Combat  %s   Food shortage %.0f%%" % [
		"engaged" if in_combat else "ready",
		food_shortage * 100.0,
	]
	_stats_label.text = "Avg  HP %.0f/%.0f   DMG %.1f   MOR %.0f   END %.0f/%.0f   RUN %.1f (%.1f-%.1f)" % [
		avg_strength,
		avg_max_strength,
		avg_damage,
		avg_morale,
		avg_endurance,
		avg_max_endurance,
		avg_run_speed,
		min_run_speed,
		max_run_speed,
	]
	_mission_label.visible = mission_active
	_mission_label.text = mission_label
	_continue_mission_button.visible = mission_active
	_continue_mission_button.disabled = not can_continue_mission

	_failure_label.visible = not failure_reason.is_empty()
	_failure_label.text = "Last order  %s" % failure_reason.replace("_", " ")
	_stop_button.disabled = not has_destination
	_clear_button.disabled = not has_destination and failure_reason.is_empty()

	_load_label.text = "Load  %s / %s" % [_format_kg(current_load), _format_kg(capacity)]
	_assets_label.text = "Food  %s   Wood  %s   Trolleys  %d   Cows  %d" % [
		_format_kg(carried_food),
		_format_kg(carried_wood),
		trolleys,
		cows,
	]
	_carrier_label.text = "Carriers  %d ready   %d away" % [available_carriers, busy_carriers]
	if camp_established:
		var range_text := "near" if camp_pack_in_range else "out of range"
		_camp_label.text = "Camp  %s food   %s wood   pack %s (%.0fm)" % [
			_format_kg(camp_food),
			_format_kg(camp_wood),
			range_text,
			camp_pack_range,
		]
	else:
		_camp_label.text = "Camp  Packed"

	_camp_transfer_label.visible = false
	_camp_transfer_label.text = "Nearby camp  %s food   %s wood" % [_format_kg(nearby_camp_food), _format_kg(nearby_camp_wood)]
	var camp_transfer_row: Control = null
	if _camp_transfer_spin_box:
		camp_transfer_row = _camp_transfer_spin_box.get_parent() as Control
	_set_control_visible(camp_transfer_row, false)
	if nearby_camp_in_range and _camp_transfer_spin_box:
		var max_transfer := maxf(maxf(nearby_camp_food, nearby_camp_wood), maxf(carried_food, carried_wood))
		max_transfer = maxf(max_transfer, 20.0)
		_camp_transfer_spin_box.max_value = max_transfer
		_camp_transfer_spin_box.value = clampf(float(_camp_transfer_spin_box.value), 1.0, max_transfer)
	if _take_food_button:
		_take_food_button.disabled = not nearby_camp_in_range or free_capacity <= 0.0 or nearby_camp_food <= 0.0
	if _give_food_button:
		_give_food_button.disabled = not nearby_camp_in_range or carried_food <= 0.0
	if _take_wood_button:
		_take_wood_button.disabled = not nearby_camp_in_range or free_capacity <= 0.0 or nearby_camp_wood <= 0.0
	if _give_wood_button:
		_give_wood_button.disabled = not nearby_camp_in_range or carried_wood <= 0.0

	_persuade_deserters_button.visible = false
	_persuade_deserters_button.disabled = true

	var max_food_amount := maxf(free_capacity, 20.0)
	_food_amount_spin_box.max_value = max_food_amount
	if _food_amount_spin_box.value <= 0.0:
		_food_amount_spin_box.value = minf(20.0, max_food_amount)
	else:
		_food_amount_spin_box.value = clampf(float(_food_amount_spin_box.value), 1.0, max_food_amount)
	_collect_food_button.disabled = free_capacity <= 0.0 or available_carriers <= 0

	_wood_soldiers_spin_box.max_value = maxf(float(maxi(available_carriers, 1)), 1.0)
	if _wood_soldiers_spin_box.value <= 0.0:
		_wood_soldiers_spin_box.value = 1.0
	else:
		_wood_soldiers_spin_box.value = clampf(float(_wood_soldiers_spin_box.value), 1.0, _wood_soldiers_spin_box.max_value)
	_collect_wood_button.disabled = free_capacity <= 0.0 or available_carriers <= 0

	var craft_wood := camp_wood if camp_established else carried_wood
	if trolley_crafting:
		_craft_trolley_button.text = "Crafting Trolley (%s)" % _format_seconds(trolley_craft_remaining)
		_craft_trolley_button.disabled = true
	else:
		_craft_trolley_button.text = "Craft Trolley (%s wood, %s)" % [
			_format_kg(trolley_cost),
			_format_seconds(trolley_craft_seconds),
		]
		_craft_trolley_button.disabled = craft_wood + 0.001 < trolley_cost
	_establish_camp_button.text = "Establish Camp (%d hut/%d, %s wood)" % [
		camp_living_huts,
		camp_soldiers_per_hut,
		_format_kg(camp_cost),
	]
	_establish_camp_button.disabled = camp_established or carried_wood + 0.001 < camp_cost
	_pack_camp_button.disabled = not camp_established or not camp_pack_in_range


func get_wood_collection_soldiers() -> int:
	if not _cache_control_nodes():
		return 1
	return maxi(roundi(float(_wood_soldiers_spin_box.value)), 1)


func get_food_collection_amount_kg() -> float:
	if not _cache_control_nodes():
		return 20.0
	return maxf(float(_food_amount_spin_box.value), 1.0)


func get_camp_transfer_amount_kg() -> float:
	if not _camp_transfer_spin_box:
		return 20.0
	return maxf(float(_camp_transfer_spin_box.value), 1.0)


func _bind_troop(troop: Node) -> void:
	if _troop == troop:
		return
	_unbind_troop()
	_troop = troop
	_connect_troop_signal(&"selected_changed")
	_connect_troop_signal(&"state_changed")
	_connect_troop_signal(&"destination_changed")
	_connect_troop_signal(&"logistics_changed")
	_connect_troop_signal(&"mode_changed")
	_connect_troop_signal(&"combat_changed")


func _unbind_troop() -> void:
	if not _troop:
		return
	_disconnect_troop_signal(&"selected_changed")
	_disconnect_troop_signal(&"state_changed")
	_disconnect_troop_signal(&"destination_changed")
	_disconnect_troop_signal(&"logistics_changed")
	_disconnect_troop_signal(&"mode_changed")
	_disconnect_troop_signal(&"combat_changed")
	_troop = null


func _connect_troop_signal(signal_name: StringName) -> void:
	var callable := Callable(self, "_on_troop_changed")
	if _troop and _troop.has_signal(signal_name) and not _troop.is_connected(signal_name, callable):
		_troop.connect(signal_name, callable)


func _disconnect_troop_signal(signal_name: StringName) -> void:
	var callable := Callable(self, "_on_troop_changed")
	if _troop and _troop.has_signal(signal_name) and _troop.is_connected(signal_name, callable):
		_troop.disconnect(signal_name, callable)


func _on_troop_changed(_value: Variant = null) -> void:
	refresh()


func _is_summary_read_only(summary: Dictionary) -> bool:
	var team := StringName(summary.get("team_id", TEAM_PLAYER))
	return team != TEAM_PLAYER or not bool(summary.get("controllable", true))


func _is_current_troop_commandable() -> bool:
	if not _troop or not _troop.has_method("get_troop_summary"):
		return false
	var summary: Dictionary = _troop.call("get_troop_summary") as Dictionary
	return not _is_summary_read_only(summary)


func _apply_read_only_visibility(read_only: bool) -> void:
	var show_controls := not read_only
	var mode_rows: Control = null
	if _troop_mode_option:
		mode_rows = _troop_mode_option.get_parent() as Control
	var buttons_row: Control = null
	if _stop_button:
		buttons_row = _stop_button.get_parent() as Control
	var food_row: Control = null
	if _food_amount_spin_box:
		food_row = _food_amount_spin_box.get_parent() as Control
	var wood_row: Control = null
	if _wood_soldiers_spin_box:
		wood_row = _wood_soldiers_spin_box.get_parent() as Control
	var camp_buttons: Control = null
	if _establish_camp_button:
		camp_buttons = _establish_camp_button.get_parent() as Control
	var camp_transfer_row: Control = null
	if _camp_transfer_spin_box:
		camp_transfer_row = _camp_transfer_spin_box.get_parent() as Control
	_set_control_visible(mode_rows, show_controls)
	_set_control_visible(_combat_label, true)
	_set_control_visible(_stats_label, true)
	_set_control_visible(_mission_label, show_controls)
	_set_control_visible(_continue_mission_button, show_controls)
	_set_control_visible(_failure_label, show_controls)
	_set_control_visible(buttons_row, show_controls)
	_set_control_visible(_load_label, show_controls)
	_set_control_visible(_assets_label, show_controls)
	_set_control_visible(_carrier_label, show_controls)
	_set_control_visible(_camp_label, show_controls)
	_set_control_visible(food_row, false)
	_set_control_visible(wood_row, show_controls)
	_set_control_visible(_craft_trolley_button, show_controls)
	_set_control_visible(camp_buttons, show_controls)
	_set_control_visible(_camp_transfer_label, false)
	_set_control_visible(camp_transfer_row, false)
	_set_control_visible(_persuade_deserters_button, show_controls)


func _apply_camp_visibility() -> void:
	var mode_rows: Control = null
	if _troop_mode_option:
		mode_rows = _troop_mode_option.get_parent() as Control
	var buttons_row: Control = null
	if _stop_button:
		buttons_row = _stop_button.get_parent() as Control
	var food_row: Control = null
	if _food_amount_spin_box:
		food_row = _food_amount_spin_box.get_parent() as Control
	var wood_row: Control = null
	if _wood_soldiers_spin_box:
		wood_row = _wood_soldiers_spin_box.get_parent() as Control
	var camp_buttons: Control = null
	if _establish_camp_button:
		camp_buttons = _establish_camp_button.get_parent() as Control
	var camp_transfer_row: Control = null
	if _camp_transfer_spin_box:
		camp_transfer_row = _camp_transfer_spin_box.get_parent() as Control
	_set_control_visible(mode_rows, false)
	_set_control_visible(_combat_label, false)
	_set_control_visible(_stats_label, false)
	_set_control_visible(_mission_label, false)
	_set_control_visible(_continue_mission_button, false)
	_set_control_visible(_failure_label, false)
	_set_control_visible(buttons_row, false)
	_set_control_visible(_load_label, false)
	_set_control_visible(_assets_label, true)
	_set_control_visible(_carrier_label, false)
	_set_control_visible(_camp_label, true)
	_set_control_visible(food_row, false)
	_set_control_visible(wood_row, false)
	_set_control_visible(_craft_trolley_button, false)
	_set_control_visible(camp_buttons, false)
	_set_control_visible(_camp_transfer_label, false)
	_set_control_visible(camp_transfer_row, false)
	_set_control_visible(_persuade_deserters_button, false)


func _set_control_visible(control: Control, visible: bool) -> void:
	if control:
		control.visible = visible


func _on_stop_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("stop_movement"):
		_troop.call("stop_movement")
	refresh()


func _on_clear_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("clear_destination"):
		_troop.call("clear_destination")
	refresh()


func _on_continue_mission_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("continue_mission"):
		_troop.call("continue_mission")
	refresh()


func _on_collect_food_pressed() -> void:
	if not _is_current_troop_commandable():
		return
	collect_food_requested.emit(_troop, get_food_collection_amount_kg())
	refresh()


func _on_collect_wood_pressed() -> void:
	if not _is_current_troop_commandable():
		return
	collect_wood_requested.emit(_troop, get_wood_collection_soldiers())
	refresh()


func _on_craft_trolley_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("craft_cargo_trolley"):
		_troop.call("craft_cargo_trolley")
	refresh()


func _on_establish_camp_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("establish_camp"):
		_troop.call("establish_camp")
	refresh()


func _on_pack_camp_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("pack_camp"):
		_troop.call("pack_camp")
	refresh()


func _get_camp_transfer_amount_kg() -> float:
	if not _camp_transfer_spin_box:
		return 20.0
	return maxf(float(_camp_transfer_spin_box.value), 1.0)


func _on_take_food_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("take_food_from_nearby_camp"):
		_troop.call("take_food_from_nearby_camp", _get_camp_transfer_amount_kg())
	refresh()


func _on_give_food_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("deposit_food_to_nearby_camp"):
		_troop.call("deposit_food_to_nearby_camp", _get_camp_transfer_amount_kg())
	refresh()


func _on_take_wood_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("take_wood_from_nearby_camp"):
		_troop.call("take_wood_from_nearby_camp", _get_camp_transfer_amount_kg())
	refresh()


func _on_give_wood_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("deposit_wood_to_nearby_camp"):
		_troop.call("deposit_wood_to_nearby_camp", _get_camp_transfer_amount_kg())
	refresh()


func _on_persuade_deserters_pressed() -> void:
	if _is_current_troop_commandable() and _troop.has_method("persuade_nearby_deserters"):
		_troop.call("persuade_nearby_deserters")
	refresh()


func _on_troop_mode_selected(index: int) -> void:
	if not _is_current_troop_commandable() or not _troop.has_method("set_troop_mode"):
		return
	var mode := _get_option_value(_troop_mode_option, index)
	_troop.call("set_troop_mode", mode)
	refresh()


func _on_movement_mode_selected(index: int) -> void:
	if not _is_current_troop_commandable() or not _troop.has_method("set_movement_mode"):
		return
	var mode := _get_option_value(_movement_mode_option, index)
	_troop.call("set_movement_mode", mode)
	refresh()


func _cache_control_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _title_label:
		_title_label = get_node_or_null("Root/Panel/Margin/Rows/TitleLabel") as Label
	if not _subtitle_label:
		_subtitle_label = get_node_or_null("Root/Panel/Margin/Rows/SubtitleLabel") as Label
	if not _state_label:
		_state_label = get_node_or_null("Root/Panel/Margin/Rows/StateLabel") as Label
	if not _troop_mode_option:
		_troop_mode_option = get_node_or_null("Root/Panel/Margin/Rows/ModeRows/TroopModeOption") as OptionButton
	if not _movement_mode_option:
		_movement_mode_option = get_node_or_null("Root/Panel/Margin/Rows/ModeRows/MovementModeOption") as OptionButton
	if not _combat_label:
		_combat_label = get_node_or_null("Root/Panel/Margin/Rows/CombatLabel") as Label
	if not _stats_label:
		_stats_label = get_node_or_null("Root/Panel/Margin/Rows/StatsLabel") as Label
	if not _mission_label:
		_mission_label = get_node_or_null("Root/Panel/Margin/Rows/MissionLabel") as Label
	if not _continue_mission_button:
		_continue_mission_button = get_node_or_null("Root/Panel/Margin/Rows/ContinueMissionButton") as Button
	if not _failure_label:
		_failure_label = get_node_or_null("Root/Panel/Margin/Rows/FailureLabel") as Label
	if not _stop_button:
		_stop_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/StopButton") as Button
	if not _clear_button:
		_clear_button = get_node_or_null("Root/Panel/Margin/Rows/Buttons/ClearButton") as Button
	if not _load_label:
		_load_label = get_node_or_null("Root/Panel/Margin/Rows/LoadLabel") as Label
	if not _assets_label:
		_assets_label = get_node_or_null("Root/Panel/Margin/Rows/AssetsLabel") as Label
	if not _carrier_label:
		_carrier_label = get_node_or_null("Root/Panel/Margin/Rows/CarrierLabel") as Label
	if not _camp_label:
		_camp_label = get_node_or_null("Root/Panel/Margin/Rows/CampLabel") as Label
	if not _food_amount_spin_box:
		_food_amount_spin_box = get_node_or_null("Root/Panel/Margin/Rows/FoodAmountRow/FoodAmountSpinBox") as SpinBox
	if not _collect_food_button:
		_collect_food_button = get_node_or_null("Root/Panel/Margin/Rows/FoodAmountRow/CollectFoodButton") as Button
	if not _wood_soldiers_spin_box:
		_wood_soldiers_spin_box = get_node_or_null("Root/Panel/Margin/Rows/WoodCarrierRow/WoodSoldiersSpinBox") as SpinBox
	if not _collect_wood_button:
		_collect_wood_button = get_node_or_null("Root/Panel/Margin/Rows/WoodCarrierRow/CollectWoodButton") as Button
	if not _craft_trolley_button:
		_craft_trolley_button = get_node_or_null("Root/Panel/Margin/Rows/CraftTrolleyButton") as Button
	if not _establish_camp_button:
		_establish_camp_button = get_node_or_null("Root/Panel/Margin/Rows/CampButtons/EstablishCampButton") as Button
	if not _pack_camp_button:
		_pack_camp_button = get_node_or_null("Root/Panel/Margin/Rows/CampButtons/PackCampButton") as Button
	if not _camp_transfer_label:
		_camp_transfer_label = get_node_or_null("Root/Panel/Margin/Rows/CampTransferLabel") as Label
	if not _camp_transfer_spin_box:
		_camp_transfer_spin_box = get_node_or_null("Root/Panel/Margin/Rows/CampTransferRow/CampTransferSpinBox") as SpinBox
	if not _take_food_button:
		_take_food_button = get_node_or_null("Root/Panel/Margin/Rows/CampTransferRow/TakeFoodButton") as Button
	if not _give_food_button:
		_give_food_button = get_node_or_null("Root/Panel/Margin/Rows/CampTransferRow/GiveFoodButton") as Button
	if not _take_wood_button:
		_take_wood_button = get_node_or_null("Root/Panel/Margin/Rows/CampTransferRow/TakeWoodButton") as Button
	if not _give_wood_button:
		_give_wood_button = get_node_or_null("Root/Panel/Margin/Rows/CampTransferRow/GiveWoodButton") as Button
	if not _persuade_deserters_button:
		_persuade_deserters_button = get_node_or_null("Root/Panel/Margin/Rows/PersuadeDesertersButton") as Button
	return (
		_root_control != null
		and _title_label != null
		and _subtitle_label != null
		and _state_label != null
		and _troop_mode_option != null
		and _movement_mode_option != null
		and _combat_label != null
		and _stats_label != null
		and _mission_label != null
		and _continue_mission_button != null
		and _failure_label != null
		and _stop_button != null
		and _clear_button != null
		and _load_label != null
		and _assets_label != null
		and _carrier_label != null
		and _camp_label != null
		and _food_amount_spin_box != null
		and _collect_food_button != null
		and _wood_soldiers_spin_box != null
		and _collect_wood_button != null
		and _craft_trolley_button != null
		and _establish_camp_button != null
		and _pack_camp_button != null
		and _camp_transfer_label != null
		and _camp_transfer_spin_box != null
		and _take_food_button != null
		and _give_food_button != null
		and _take_wood_button != null
		and _give_wood_button != null
		and _persuade_deserters_button != null
	)


func _setup_mode_options() -> void:
	_populate_option(_troop_mode_option, TROOP_MODE_OPTIONS)
	_populate_option(_movement_mode_option, MOVEMENT_MODE_OPTIONS)


func _populate_option(option: OptionButton, items: Array) -> void:
	if not option or option.item_count > 0:
		return
	for item: Dictionary in items:
		var index := option.item_count
		option.add_item(String(item.get("label", "")))
		option.set_item_metadata(index, item.get("value", &""))


func _select_option_value(option: OptionButton, value: StringName) -> void:
	if not option:
		return
	for index: int in range(option.item_count):
		if StringName(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _get_option_value(option: OptionButton, index: int) -> StringName:
	if not option or index < 0 or index >= option.item_count:
		return &""
	return StringName(option.get_item_metadata(index))


func _format_meters(value: float) -> String:
	if value >= 1000.0:
		return "%.1f km" % (value / 1000.0)
	return "%.0f m" % value


func _format_kg(value: float) -> String:
	if value >= 1000.0:
		return "%.1ft" % (value / 1000.0)
	return "%.0fkg" % value


func _format_seconds(value: float) -> String:
	if value >= 60.0:
		return "%.1f min" % (value / 60.0)
	return "%.0f sec" % value
