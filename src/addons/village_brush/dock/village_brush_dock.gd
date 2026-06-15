@tool
extends PanelContainer

signal village_type_changed(resource: Resource)
signal wall_type_changed(resource: Resource)
signal paint_enabled_changed(enabled: bool)
signal brush_mode_changed(mode: int)
signal brush_radius_changed(radius: int)
signal house_density_changed(density: float)
signal clear_requested(target: int)

const VillageRegionScript = preload("res://addons/village_brush/village_region.gd")

enum BrushMode {
	HOUSE,
	FIELD,
	ROAD,
	ERASE,
}

enum ClearTarget {
	HOUSE,
	FIELD,
	ROAD,
	ALL,
}

var _region: VillageRegionScript
var _syncing := false
var _village_picker: EditorResourcePicker
var _wall_picker: EditorResourcePicker
var _paint_checkbox: CheckBox
var _paint_enabled := false
var _selected_mode := BrushMode.HOUSE
var _mode_buttons: Dictionary = {}
var _radius_spinbox: SpinBox
var _house_density_spinbox: SpinBox
var _clear_house_button: Button
var _clear_field_button: Button
var _clear_road_button: Button
var _clear_all_button: Button


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build_ui()
	set_region(null)


func set_region(region: VillageRegionScript) -> void:
	_region = region
	_syncing = true

	if _village_picker:
		_village_picker.edited_resource = _region.village_type if _region else null
	if _wall_picker:
		_wall_picker.edited_resource = _region.wall_type if _region else null

	var has_region := is_instance_valid(_region)
	if _village_picker:
		_village_picker.editable = has_region
	if _wall_picker:
		_wall_picker.editable = has_region
	if _paint_checkbox:
		_paint_checkbox.disabled = not has_region
	_set_mode_buttons_disabled(not has_region)
	if _radius_spinbox:
		_radius_spinbox.editable = has_region
	if _house_density_spinbox:
		_house_density_spinbox.editable = has_region
		_house_density_spinbox.value = _region.house_density if has_region else 1.0
	if _clear_house_button:
		_clear_house_button.disabled = not has_region
	if _clear_field_button:
		_clear_field_button.disabled = not has_region
	if _clear_road_button:
		_clear_road_button.disabled = not has_region
	if _clear_all_button:
		_clear_all_button.disabled = not has_region

	_syncing = false


func get_brush_mode() -> int:
	return _selected_mode


func set_paint_enabled(enabled: bool) -> void:
	_paint_enabled = enabled
	if not _paint_checkbox:
		return

	var was_syncing := _syncing
	_syncing = true
	_paint_checkbox.button_pressed = enabled
	_syncing = was_syncing


func set_brush_mode(mode: int) -> void:
	_selected_mode = mode
	_sync_mode_buttons()


func get_brush_radius() -> int:
	if not _radius_spinbox:
		return 0
	return int(_radius_spinbox.value)


func set_brush_radius(radius: int) -> void:
	if not _radius_spinbox:
		return
	_radius_spinbox.value = maxi(radius, 0)


func _build_ui() -> void:
	custom_minimum_size = Vector2(300.0 * EditorInterface.get_editor_scale(), 0.0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Village Brush"
	title.add_theme_font_size_override("font_size", int(16.0 * EditorInterface.get_editor_scale()))
	root.add_child(title)

	_paint_checkbox = CheckBox.new()
	_paint_checkbox.text = "Paint Enabled"
	_paint_checkbox.button_pressed = _paint_enabled
	_paint_checkbox.toggled.connect(_on_paint_enabled_toggled)
	root.add_child(_paint_checkbox)

	_village_picker = _add_resource_picker(root, "Village Type", "VillageTypeData")
	_village_picker.resource_changed.connect(_on_village_type_changed)

	_wall_picker = _add_resource_picker(root, "Wall Type", "WallTypeData")
	_wall_picker.resource_changed.connect(_on_wall_type_changed)

	var mode_label := Label.new()
	mode_label.text = "Brush Mode"
	root.add_child(mode_label)

	var mode_grid := GridContainer.new()
	mode_grid.columns = 2
	mode_grid.add_theme_constant_override("h_separation", 0)
	mode_grid.add_theme_constant_override("v_separation", 0)
	root.add_child(mode_grid)

	var mode_group := ButtonGroup.new()
	_add_mode_button(mode_grid, mode_group, "House", BrushMode.HOUSE)
	_add_mode_button(mode_grid, mode_group, "Field", BrushMode.FIELD)
	_add_mode_button(mode_grid, mode_group, "Road", BrushMode.ROAD)
	_add_mode_button(mode_grid, mode_group, "Erase", BrushMode.ERASE)
	_sync_mode_buttons()

	var radius_row := HBoxContainer.new()
	radius_row.add_theme_constant_override("separation", 8)
	root.add_child(radius_row)

	var radius_label := Label.new()
	radius_label.text = "Brush Radius"
	radius_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_row.add_child(radius_label)

	_radius_spinbox = SpinBox.new()
	_radius_spinbox.min_value = 0
	_radius_spinbox.max_value = 32
	_radius_spinbox.step = 1
	_radius_spinbox.value = 0
	_radius_spinbox.allow_greater = true
	_radius_spinbox.value_changed.connect(_on_radius_changed)
	radius_row.add_child(_radius_spinbox)

	var density_row := HBoxContainer.new()
	density_row.add_theme_constant_override("separation", 8)
	root.add_child(density_row)

	var density_label := Label.new()
	density_label.text = "House Density"
	density_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	density_row.add_child(density_label)

	_house_density_spinbox = SpinBox.new()
	_house_density_spinbox.min_value = 0.25
	_house_density_spinbox.max_value = 4.0
	_house_density_spinbox.step = 0.05
	_house_density_spinbox.value = 1.0
	_house_density_spinbox.allow_greater = true
	_house_density_spinbox.value_changed.connect(_on_house_density_changed)
	density_row.add_child(_house_density_spinbox)

	var separator := HSeparator.new()
	root.add_child(separator)

	_clear_house_button = Button.new()
	_clear_house_button.text = "Clear Houses"
	_clear_house_button.pressed.connect(_on_clear_house_pressed)
	root.add_child(_clear_house_button)

	_clear_field_button = Button.new()
	_clear_field_button.text = "Clear Fields"
	_clear_field_button.pressed.connect(_on_clear_field_pressed)
	root.add_child(_clear_field_button)

	_clear_road_button = Button.new()
	_clear_road_button.text = "Clear Roads"
	_clear_road_button.pressed.connect(_on_clear_road_pressed)
	root.add_child(_clear_road_button)

	_clear_all_button = Button.new()
	_clear_all_button.text = "Clear All Cells"
	_clear_all_button.pressed.connect(_on_clear_all_pressed)
	root.add_child(_clear_all_button)


func _add_resource_picker(parent: Control, label_text: String, base_type: String) -> EditorResourcePicker:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var picker := EditorResourcePicker.new()
	picker.base_type = base_type
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(picker)
	return picker


func _add_mode_button(parent: Control, group: ButtonGroup, label_text: String, mode: int) -> void:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggled.connect(_on_mode_button_toggled.bind(mode))
	parent.add_child(button)
	_mode_buttons[mode] = button


func _sync_mode_buttons() -> void:
	var was_syncing := _syncing
	_syncing = true
	for key: Variant in _mode_buttons.keys():
		var button := _mode_buttons[key] as Button
		if button:
			button.button_pressed = int(key) == _selected_mode
	_syncing = was_syncing


func _set_mode_buttons_disabled(disabled: bool) -> void:
	for button: Button in _mode_buttons.values():
		button.disabled = disabled


func _on_village_type_changed(resource: Resource) -> void:
	if _syncing:
		return
	village_type_changed.emit(resource)


func _on_wall_type_changed(resource: Resource) -> void:
	if _syncing:
		return
	wall_type_changed.emit(resource)


func _on_paint_enabled_toggled(pressed: bool) -> void:
	if _syncing:
		return
	_paint_enabled = pressed
	paint_enabled_changed.emit(pressed)


func _on_mode_button_toggled(pressed: bool, mode: int) -> void:
	if _syncing:
		return
	if not pressed:
		return

	_selected_mode = mode
	brush_mode_changed.emit(mode)


func _on_radius_changed(value: float) -> void:
	if _syncing:
		return
	brush_radius_changed.emit(int(value))


func _on_house_density_changed(value: float) -> void:
	if _syncing:
		return
	house_density_changed.emit(value)


func _on_clear_house_pressed() -> void:
	clear_requested.emit(ClearTarget.HOUSE)


func _on_clear_field_pressed() -> void:
	clear_requested.emit(ClearTarget.FIELD)


func _on_clear_road_pressed() -> void:
	clear_requested.emit(ClearTarget.ROAD)


func _on_clear_all_pressed() -> void:
	clear_requested.emit(ClearTarget.ALL)
