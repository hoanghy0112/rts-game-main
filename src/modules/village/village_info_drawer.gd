@tool
extends CanvasLayer
class_name VillageInfoDrawer

@export var village_region_path: NodePath = NodePath("../VillageRegion")

@onready var _root_control: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _reserve_label: Label = %ReserveLabel
@onready var _farmers_label: Label = %FarmersLabel
@onready var _production_label: Label = %ProductionLabel
@onready var _consumption_label: Label = %ConsumptionLabel
@onready var _net_label: Label = %NetLabel
@onready var _field_area_label: Label = %FieldAreaLabel
@onready var _house_count_label: Label = %HouseCountLabel

var _village_region: VillageRegion
var _selected_house_id: StringName = &""
var _mode: StringName = &"village"
var _pending_summary: Dictionary = {}


func _ready() -> void:
	_cache_control_nodes()
	if Engine.is_editor_hint():
		_apply_village_summary(_make_preview_summary())
		return

	var region_node := get_node_or_null(village_region_path)
	if region_node is VillageRegion:
		bind_to_village_region(region_node as VillageRegion)

	hide_drawer()


func _exit_tree() -> void:
	if _village_region and _village_region.food_state_changed.is_connected(_on_food_state_changed):
		_village_region.food_state_changed.disconnect(_on_food_state_changed)


func bind_to_village_region(region: VillageRegion) -> void:
	if _village_region == region:
		return
	if _village_region and _village_region.food_state_changed.is_connected(_on_food_state_changed):
		_village_region.food_state_changed.disconnect(_on_food_state_changed)

	_village_region = region
	if _village_region and not _village_region.food_state_changed.is_connected(_on_food_state_changed):
		_village_region.food_state_changed.connect(_on_food_state_changed)


func show_village_summary() -> void:
	_mode = &"village"
	_selected_house_id = &""
	_show_root()
	_refresh()


func show_house_detail(house_id: Variant) -> void:
	_mode = &"house"
	_selected_house_id = StringName(str(house_id))
	_show_root()
	_refresh()


func hide_drawer() -> void:
	if _cache_control_nodes():
		_root_control.visible = false


func _show_root() -> void:
	if _cache_control_nodes():
		_root_control.visible = true


func _refresh() -> void:
	if not _village_region:
		return

	var summary := _village_region.get_village_food_summary()
	if _mode == &"house" and _selected_house_id != &"":
		var record := _village_region.get_house_food_record(_selected_house_id)
		if not record.is_empty():
			_apply_house_detail(record, summary)
			return
	_apply_village_summary(summary)


func _on_food_state_changed(summary: Dictionary) -> void:
	_pending_summary = summary.duplicate(true)
	if _root_control and _root_control.visible:
		if _mode == &"house":
			_refresh()
		else:
			_apply_village_summary(summary)


func _apply_village_summary(summary: Dictionary) -> void:
	if not _cache_control_nodes():
		_pending_summary = summary.duplicate(true)
		return

	_title_label.text = "Village Food"
	_subtitle_label.text = "%d houses, %d residents" % [
		int(summary.get("house_count", 0)),
		int(summary.get("resident_count", 0)),
	]
	_reserve_label.text = "Storage  %s" % [_format_kg(float(summary.get("storage_food_kg", summary.get("total_reserve_kg", 0.0))))]
	_farmers_label.text = "Farmers  %d" % [int(summary.get("farmer_count", 0))]
	_production_label.text = "Production/day  %s" % [_format_kg(float(summary.get("daily_production_kg", 0.0)))]
	_consumption_label.text = "Consumption/day  %s" % [_format_kg(float(summary.get("daily_consumption_kg", 0.0)))]
	_net_label.text = "Net/day  %s" % [_format_signed_kg(float(summary.get("daily_net_kg", 0.0)))]
	_field_area_label.text = "Field area  %s" % [_format_area(float(summary.get("field_area_m2", 0.0)))]
	_house_count_label.text = "Food days  %s" % [_format_days(float(summary.get("food_days_remaining", 0.0)))]


func _apply_house_detail(record: Dictionary, summary: Dictionary) -> void:
	if not _cache_control_nodes():
		return

	_title_label.text = String(record.get("display_name", "House"))
	_subtitle_label.text = String(record.get("house_id", record.get("id", "")))
	_reserve_label.text = "Reserve  %s" % [_format_kg(float(record.get("food_reserve_kg", 0.0)))]
	_farmers_label.text = "Residents  %d" % [int(record.get("resident_count", 0))]
	_production_label.text = "Production/day  %s" % [_format_kg(float(record.get("daily_production_share_kg", 0.0)))]
	_consumption_label.text = "Consumption/day  %s" % [_format_kg(float(record.get("daily_consumption_share_kg", 0.0)))]
	_net_label.text = "Net/day  %s" % [_format_signed_kg(float(record.get("daily_net_kg", 0.0)))]
	_field_area_label.text = "Village fields  %s" % [_format_area(float(summary.get("field_area_m2", 0.0)))]
	_house_count_label.text = "Food days  %s" % [_format_days(float(record.get("food_days_remaining", 0.0)))]


func _cache_control_nodes() -> bool:
	if not _root_control:
		_root_control = get_node_or_null("Root") as Control
	if not _title_label:
		_title_label = get_node_or_null("Root/Panel/Margin/Rows/TitleLabel") as Label
	if not _subtitle_label:
		_subtitle_label = get_node_or_null("Root/Panel/Margin/Rows/SubtitleLabel") as Label
	if not _reserve_label:
		_reserve_label = get_node_or_null("Root/Panel/Margin/Rows/ReserveLabel") as Label
	if not _farmers_label:
		_farmers_label = get_node_or_null("Root/Panel/Margin/Rows/FarmersLabel") as Label
	if not _production_label:
		_production_label = get_node_or_null("Root/Panel/Margin/Rows/ProductionLabel") as Label
	if not _consumption_label:
		_consumption_label = get_node_or_null("Root/Panel/Margin/Rows/ConsumptionLabel") as Label
	if not _net_label:
		_net_label = get_node_or_null("Root/Panel/Margin/Rows/NetLabel") as Label
	if not _field_area_label:
		_field_area_label = get_node_or_null("Root/Panel/Margin/Rows/FieldAreaLabel") as Label
	if not _house_count_label:
		_house_count_label = get_node_or_null("Root/Panel/Margin/Rows/HouseCountLabel") as Label
	return (
		_root_control != null
		and _title_label != null
		and _subtitle_label != null
		and _reserve_label != null
		and _farmers_label != null
		and _production_label != null
		and _consumption_label != null
		and _net_label != null
		and _field_area_label != null
		and _house_count_label != null
	)


func _format_kg(value: float) -> String:
	return "%.1f kg" % [value]


func _format_signed_kg(value: float) -> String:
	var prefix := "+" if value >= 0.0 else ""
	return "%s%.1f kg" % [prefix, value]


func _format_area(value: float) -> String:
	return "%.0f m2" % [value]


func _format_days(value: float) -> String:
	if value <= 0.0:
		return "0.0"
	return "%.1f" % [value]


func _make_preview_summary() -> Dictionary:
	return {
		"house_count": 12,
		"resident_count": 42,
		"farmer_count": 18,
		"total_reserve_kg": 360.0,
		"daily_production_kg": 8.4,
		"daily_consumption_kg": 18.0,
		"daily_net_kg": -9.6,
		"field_area_m2": 30240.0,
		"food_days_remaining": 20.0,
	}
