@tool
extends PanelContainer

signal palette_changed(resource: Resource)
signal selected_plant_ids_changed(plant_ids: Array[StringName])
signal paint_enabled_changed(enabled: bool)
signal brush_mode_changed(mode: int)
signal brush_radius_changed(radius: int)
signal density_multiplier_changed(multiplier: float)
signal macro_overlay_enabled_changed(enabled: bool)
signal tree_scale_multiplier_changed(multiplier: float)
signal rebuild_requested
signal clear_requested

const ForestRegionScript = preload("res://addons/forest_brush/forest_region.gd")

enum BrushMode {
	PAINT,
	ERASE,
}

var _region: ForestRegionScript
var _syncing := false
var _palette_picker: EditorResourcePicker
var _paint_checkbox: CheckBox
var _paint_enabled := false
var _plants_box: VBoxContainer
var _empty_plants_label: Label
var _mode_buttons: Dictionary = {}
var _selected_mode := BrushMode.PAINT
var _select_all_button: Button
var _deselect_all_button: Button
var _radius_spinbox: SpinBox
var _density_spinbox: SpinBox
var _macro_overlay_checkbox: CheckBox
var _tree_scale_spinbox: SpinBox
var _rebuild_button: Button
var _clear_button: Button
var _selected_plant_ids: Array[StringName] = []
var _has_explicit_plant_selection := false
var _plant_checkboxes: Dictionary = {}


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build_ui()
	set_region(null, [], false)


func set_region(region: ForestRegionScript, selected_plant_ids: Array[StringName], has_explicit_plant_selection := false) -> void:
	_region = region
	_selected_plant_ids = _copy_plant_ids(selected_plant_ids)
	_has_explicit_plant_selection = has_explicit_plant_selection
	_syncing = true

	if _palette_picker:
		_palette_picker.edited_resource = _region.palette if _region else null

	_rebuild_plant_checks()
	var has_region := is_instance_valid(_region)
	if _palette_picker:
		_palette_picker.editable = has_region
	if _paint_checkbox:
		_paint_checkbox.disabled = not has_region
	_set_mode_buttons_disabled(not has_region)
	if _radius_spinbox:
		_radius_spinbox.editable = has_region
	if _density_spinbox:
		_density_spinbox.value = _region.density_multiplier if has_region else 1.0
		_density_spinbox.editable = has_region
	if _macro_overlay_checkbox:
		_macro_overlay_checkbox.button_pressed = _region.macro_overlay_enabled if has_region else false
		_macro_overlay_checkbox.disabled = not has_region
	if _tree_scale_spinbox:
		_tree_scale_spinbox.value = _region.tree_scale_multiplier if has_region else 1.0
		_tree_scale_spinbox.editable = has_region
	if _rebuild_button:
		_rebuild_button.disabled = not has_region
	if _clear_button:
		_clear_button.disabled = not has_region
	for checkbox: CheckBox in _plant_checkboxes.values():
		checkbox.disabled = not has_region
	_update_plant_selection_buttons_disabled()

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


func get_tree_scale_multiplier() -> float:
	if not _tree_scale_spinbox:
		return 1.0
	return float(_tree_scale_spinbox.value)


func set_tree_scale_multiplier(multiplier: float) -> void:
	if not _tree_scale_spinbox:
		return
	_tree_scale_spinbox.value = maxf(multiplier, 0.05)


func get_selected_plant_ids() -> Array[StringName]:
	return _copy_plant_ids(_selected_plant_ids)


func set_selected_plant_ids(plant_ids: Array[StringName]) -> void:
	_selected_plant_ids = _copy_plant_ids(plant_ids)
	_has_explicit_plant_selection = true
	_rebuild_plant_checks()


func _build_ui() -> void:
	custom_minimum_size = Vector2(320.0 * EditorInterface.get_editor_scale(), 0.0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Forest Brush"
	title.add_theme_font_size_override("font_size", int(16.0 * EditorInterface.get_editor_scale()))
	root.add_child(title)

	_paint_checkbox = CheckBox.new()
	_paint_checkbox.text = "Paint Enabled"
	_paint_checkbox.button_pressed = _paint_enabled
	_paint_checkbox.toggled.connect(_on_paint_enabled_toggled)
	root.add_child(_paint_checkbox)

	_palette_picker = _add_resource_picker(root, "Palette", "ForestPaletteData")
	_palette_picker.resource_changed.connect(_on_palette_changed)

	var plants_label := Label.new()
	plants_label.text = "Plant Types"
	root.add_child(plants_label)

	var plant_selection_row := HBoxContainer.new()
	plant_selection_row.add_theme_constant_override("separation", 6)
	root.add_child(plant_selection_row)

	_select_all_button = Button.new()
	_select_all_button.text = "Select All"
	_select_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_all_button.pressed.connect(_on_select_all_pressed)
	plant_selection_row.add_child(_select_all_button)

	_deselect_all_button = Button.new()
	_deselect_all_button.text = "Deselect All"
	_deselect_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deselect_all_button.pressed.connect(_on_deselect_all_pressed)
	plant_selection_row.add_child(_deselect_all_button)

	_plants_box = VBoxContainer.new()
	_plants_box.add_theme_constant_override("separation", 2)
	root.add_child(_plants_box)

	_empty_plants_label = Label.new()
	_empty_plants_label.text = "No plants in palette"
	_empty_plants_label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	_plants_box.add_child(_empty_plants_label)

	var mode_label := Label.new()
	mode_label.text = "Brush Mode"
	root.add_child(mode_label)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 0)
	root.add_child(mode_row)

	var mode_group := ButtonGroup.new()
	_add_mode_button(mode_row, mode_group, "Paint", BrushMode.PAINT)
	_add_mode_button(mode_row, mode_group, "Erase", BrushMode.ERASE)
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
	_radius_spinbox.max_value = 48
	_radius_spinbox.step = 1
	_radius_spinbox.value = 1
	_radius_spinbox.allow_greater = true
	_radius_spinbox.value_changed.connect(_on_radius_changed)
	radius_row.add_child(_radius_spinbox)

	var density_row := HBoxContainer.new()
	density_row.add_theme_constant_override("separation", 8)
	root.add_child(density_row)

	var density_label := Label.new()
	density_label.text = "Density"
	density_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	density_row.add_child(density_label)

	_density_spinbox = SpinBox.new()
	_density_spinbox.min_value = 0.0
	_density_spinbox.max_value = 16.0
	_density_spinbox.step = 0.1
	_density_spinbox.value = 1.0
	_density_spinbox.allow_greater = true
	_density_spinbox.value_changed.connect(_on_density_changed)
	density_row.add_child(_density_spinbox)

	_macro_overlay_checkbox = CheckBox.new()
	_macro_overlay_checkbox.text = "Macro Overlay"
	_macro_overlay_checkbox.button_pressed = true
	_macro_overlay_checkbox.toggled.connect(_on_macro_overlay_enabled_toggled)
	root.add_child(_macro_overlay_checkbox)

	var tree_scale_row := HBoxContainer.new()
	tree_scale_row.add_theme_constant_override("separation", 8)
	root.add_child(tree_scale_row)

	var tree_scale_label := Label.new()
	tree_scale_label.text = "Tree Scale"
	tree_scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_scale_row.add_child(tree_scale_label)

	_tree_scale_spinbox = SpinBox.new()
	_tree_scale_spinbox.min_value = 0.05
	_tree_scale_spinbox.max_value = 8.0
	_tree_scale_spinbox.step = 0.05
	_tree_scale_spinbox.value = 1.0
	_tree_scale_spinbox.allow_greater = true
	_tree_scale_spinbox.value_changed.connect(_on_tree_scale_changed)
	tree_scale_row.add_child(_tree_scale_spinbox)

	var separator := HSeparator.new()
	root.add_child(separator)

	_rebuild_button = Button.new()
	_rebuild_button.text = "Rebuild Preview"
	_rebuild_button.pressed.connect(_on_rebuild_pressed)
	root.add_child(_rebuild_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear Forest Cells"
	_clear_button.pressed.connect(_on_clear_pressed)
	root.add_child(_clear_button)


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


func _rebuild_plant_checks() -> void:
	if not _plants_box:
		return

	for child: Node in _plants_box.get_children():
		child.queue_free()
	_plant_checkboxes.clear()

	var palette := _get_palette()
	if not palette or palette.plant_types.is_empty():
		_empty_plants_label = Label.new()
		_empty_plants_label.text = "No plants in palette"
		_empty_plants_label.modulate = Color(1.0, 1.0, 1.0, 0.65)
		_plants_box.add_child(_empty_plants_label)
		_update_plant_selection_buttons_disabled()
		return

	var filtered := palette.filter_plant_ids(_selected_plant_ids)
	if filtered.is_empty() and not _has_explicit_plant_selection:
		filtered = palette.get_default_selected_plant_ids()
	_selected_plant_ids = filtered

	for plant_type: ForestPlantTypeData in palette.plant_types:
		if not plant_type:
			continue
		var checkbox := CheckBox.new()
		checkbox.text = plant_type.display_name if not plant_type.display_name.is_empty() else str(plant_type.id)
		checkbox.button_pressed = _selected_plant_ids.has(plant_type.id)
		checkbox.disabled = not is_instance_valid(_region)
		checkbox.toggled.connect(_on_plant_toggled.bind(plant_type.id))
		_plants_box.add_child(checkbox)
		_plant_checkboxes[plant_type.id] = checkbox
	_update_plant_selection_buttons_disabled()


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


func _update_plant_selection_buttons_disabled() -> void:
	var palette := _get_palette()
	var disabled := not is_instance_valid(_region) or not palette or palette.plant_types.is_empty()
	if _select_all_button:
		_select_all_button.disabled = disabled
	if _deselect_all_button:
		_deselect_all_button.disabled = disabled


func _sync_plant_checkboxes() -> void:
	var was_syncing := _syncing
	_syncing = true
	for plant_id: Variant in _plant_checkboxes.keys():
		var checkbox := _plant_checkboxes[plant_id] as CheckBox
		if checkbox:
			checkbox.button_pressed = _selected_plant_ids.has(plant_id)
	_syncing = was_syncing


func _get_palette() -> ForestPaletteData:
	if is_instance_valid(_region):
		return _region.palette
	if _palette_picker and _palette_picker.edited_resource is ForestPaletteData:
		return _palette_picker.edited_resource as ForestPaletteData
	return null


func _on_palette_changed(resource: Resource) -> void:
	if _syncing:
		return
	palette_changed.emit(resource)
	_rebuild_plant_checks()
	selected_plant_ids_changed.emit(get_selected_plant_ids())


func _on_paint_enabled_toggled(pressed: bool) -> void:
	if _syncing:
		return
	_paint_enabled = pressed
	paint_enabled_changed.emit(pressed)


func _on_plant_toggled(pressed: bool, plant_id: StringName) -> void:
	if _syncing:
		return

	_has_explicit_plant_selection = true
	if pressed:
		if not _selected_plant_ids.has(plant_id):
			_selected_plant_ids.append(plant_id)
	else:
		_selected_plant_ids.erase(plant_id)

	selected_plant_ids_changed.emit(get_selected_plant_ids())


func _on_select_all_pressed() -> void:
	if _syncing:
		return

	var palette := _get_palette()
	if not palette:
		return

	_has_explicit_plant_selection = true
	_selected_plant_ids = palette.get_all_plant_ids()
	_sync_plant_checkboxes()
	selected_plant_ids_changed.emit(get_selected_plant_ids())


func _on_deselect_all_pressed() -> void:
	if _syncing:
		return

	_has_explicit_plant_selection = true
	_selected_plant_ids.clear()
	_sync_plant_checkboxes()
	selected_plant_ids_changed.emit(get_selected_plant_ids())


func _on_mode_button_toggled(pressed: bool, mode: int) -> void:
	if _syncing or not pressed:
		return
	_selected_mode = mode
	brush_mode_changed.emit(mode)


func _on_radius_changed(value: float) -> void:
	if _syncing:
		return
	brush_radius_changed.emit(int(value))


func _on_density_changed(value: float) -> void:
	if _syncing:
		return
	density_multiplier_changed.emit(maxf(value, 0.0))


func _on_macro_overlay_enabled_toggled(pressed: bool) -> void:
	if _syncing:
		return
	macro_overlay_enabled_changed.emit(pressed)


func _on_tree_scale_changed(value: float) -> void:
	if _syncing:
		return
	tree_scale_multiplier_changed.emit(maxf(value, 0.05))


func _on_rebuild_pressed() -> void:
	rebuild_requested.emit()


func _on_clear_pressed() -> void:
	clear_requested.emit()


func _copy_plant_ids(plant_ids: Array[StringName]) -> Array[StringName]:
	var copied: Array[StringName] = []
	for plant_id: StringName in plant_ids:
		if plant_id != &"" and not copied.has(plant_id):
			copied.append(plant_id)
	return copied
