@tool
extends Node3D

const WaterfallConfiguration = preload("./waterfall_configuration.gd")
const WaterHelperMethods = preload("./water_helper_methods.gd")
const line_sample_resolution := 100

@export var configuration: WaterfallConfiguration:
	set(value):
		if configuration != null and configuration.changed.is_connected(_configuration_changed):
			configuration.changed.disconnect(_configuration_changed)
		configuration = value
		if configuration != null and not configuration.changed.is_connected(_configuration_changed):
			configuration.changed.connect(_configuration_changed)
#@export var width := 3.0:
#	set(value):
#		width = value
#		_generate_waterfall()
#@export var step_length_divs := 1:
#	set(value):
#		step_length_divs = value
#		_generate_waterfall()
#@export var step_width_divs := 1:
#	set(value):
#		step_width_divs = value
#		_generate_waterfall()

var points := PackedVector3Array([Vector3(0.0, 4.0, 0.0), Vector3(0.0, 0.0, 1.0)]):
	set(value):
		points = value
		_request_generate_waterfall()
		emit_signal("waterfall_changed")
var mesh_instance : MeshInstance3D

var _st : SurfaceTool
var _mdt : MeshDataTool
var _steps := 2
var _first_enter_tree = true
var _exiting_tree := false
var _waterfall_generation_pending := false
var _editor_gizmo_update_pending := false

# TODO - connect this
signal waterfall_changed


func get_points() -> PackedVector3Array:
	return points


func set_point(id: int, position: Vector3) -> void:
	points[id] = position
	_request_generate_waterfall()
	emit_signal("waterfall_changed")


func _configuration_changed() -> void:
	# TODO - I assume we can pass a parameter about whether a re-gen is needed
	_request_generate_waterfall()
	emit_signal("waterfall_changed")


func _enter_tree() -> void:
	_exiting_tree = false
	if Engine.is_editor_hint() and _first_enter_tree:
		_first_enter_tree = false

	if Engine.is_editor_hint():
		var gizmo_update_callable := Callable(self, "request_editor_gizmo_update")
		if not is_connected("waterfall_changed", gizmo_update_callable):
			connect("waterfall_changed", gizmo_update_callable)

	if get_child_count() <= 0:
		var new_mesh_instance := MeshInstance3D.new()
		new_mesh_instance.name = "WaterfallMeshInstance"
		add_child(new_mesh_instance)
		mesh_instance = get_child(0) as MeshInstance3D
		_request_generate_waterfall()
	else:
		mesh_instance = get_child(0) as MeshInstance3D
		# TODO set material?
	

func _exit_tree() -> void:
	_exiting_tree = true
	_waterfall_generation_pending = false
	_editor_gizmo_update_pending = false
	var gizmo_update_callable := Callable(self, "request_editor_gizmo_update")
	if is_connected("waterfall_changed", gizmo_update_callable):
		disconnect("waterfall_changed", gizmo_update_callable)
	if configuration != null and configuration.changed.is_connected(_configuration_changed):
		configuration.changed.disconnect(_configuration_changed)
	mesh_instance = null


func _generate_waterfall() -> void:
	if not _can_update_editor_visuals() or not _is_mesh_instance_ready() or configuration == null:
		return
	
	# TODO - This spams "the target vector can't be zero", not sure which part, maybe cross product
	
	var to_from: Vector3 = points[1] - points[0]
	var to_from_2d = Vector3(to_from.x, 0.0, to_from.z)
	var dist = to_from_2d.length()
	
	var line_points := PackedVector3Array()
	
	var curve := Curve3D.new()
	
	for i in line_sample_resolution + 1:
		var val = float(i) / float(line_sample_resolution)
		var position = points[0] + to_from_2d * val + Vector3(0.0, ease_back_in(val) * to_from.y, 0.0)
		curve.add_point(position)
		line_points.append(position)
	
	var curve_length := curve.get_baked_length()
		
	_steps = int( max(1.0, round(curve_length / configuration.width)))
	
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st.set_smooth_group(0)
	
	# Generating the verts
	for step in _steps * configuration.step_length_divs + 1:
		var position := curve.sample_baked(float(step) / float(_steps * configuration.step_length_divs) * curve_length, false)
		var backward_pos := curve.sample_baked((float(step) - 0.05) / float(_steps * configuration.step_length_divs) * curve_length, false)
		var forward_pos := curve.sample_baked((float(step) + 0.05) / float(_steps *configuration. step_length_divs) * curve_length, false)
		var forward_vector := forward_pos - backward_pos
		var right_vector := forward_vector.cross(Vector3.UP).normalized()
		
				
		for w_sub in configuration.step_width_divs + 1:
			_st.set_uv(Vector2(float(w_sub) / (float(configuration.step_width_divs)), float(step) / float(configuration.step_length_divs) ))
			_st.add_vertex(position + right_vector * configuration.width - 2.0 * right_vector * configuration.width * float(w_sub) / (float(configuration.step_width_divs)))
	
	# Defining the tris
	for step in _steps * configuration.step_length_divs:
		for w_sub in configuration.step_width_divs:
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub)
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub + 1)
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub + 2 + configuration.step_width_divs - 1)
			
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub + 1)
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub + 3 + configuration.step_width_divs - 1)
			_st.add_index( (step * (configuration.step_width_divs + 1)) + w_sub + 2 + configuration.step_width_divs - 1)
		
	_st.generate_normals()
	_st.generate_tangents()
	_st.deindex()
	
	var mesh := ArrayMesh.new()
	mesh = _st.commit()
	mesh_instance.mesh = mesh


func ease_back_in(x: float) -> float:
	var c1 = 1.70158
	var c3 = c1 + 1
	return c3 * x * x * x - c1 * x * x


# Signal Methods
func properties_changed() -> void:
	emit_signal("waterfall_changed")


func request_editor_gizmo_update() -> void:
	if not Engine.is_editor_hint() or _exiting_tree or is_queued_for_deletion():
		return
	if not is_inside_tree() or not _is_in_active_edited_scene():
		return
	if _editor_gizmo_update_pending:
		return

	_editor_gizmo_update_pending = true
	_flush_editor_gizmo_update.call_deferred()


func _flush_editor_gizmo_update() -> void:
	_editor_gizmo_update_pending = false
	if not Engine.is_editor_hint() or _exiting_tree or is_queued_for_deletion():
		return
	if not is_inside_tree() or not _is_in_active_edited_scene():
		return

	update_gizmos()


func _request_generate_waterfall() -> void:
	if Engine.is_editor_hint():
		if _waterfall_generation_pending:
			return
		_waterfall_generation_pending = true
		_flush_generate_waterfall.call_deferred()
		return

	_generate_waterfall()


func _flush_generate_waterfall() -> void:
	_waterfall_generation_pending = false
	_generate_waterfall()


func _can_update_editor_visuals() -> bool:
	if _exiting_tree or is_queued_for_deletion():
		return false
	if Engine.is_editor_hint():
		return is_inside_tree() and _is_in_active_edited_scene()
	return true


func _is_mesh_instance_ready() -> bool:
	if not is_instance_valid(mesh_instance) or mesh_instance.is_queued_for_deletion():
		return false
	if Engine.is_editor_hint():
		return mesh_instance.is_inside_tree() and _can_update_editor_visuals()
	return true


func _is_in_active_edited_scene() -> bool:
	if not Engine.is_editor_hint():
		return true
	if not is_inside_tree():
		return false
	if not Engine.has_singleton(&"EditorInterface"):
		return true

	var editor_interface := Engine.get_singleton(&"EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_edited_scene_root"):
		return true

	var edited_root := editor_interface.call("get_edited_scene_root") as Node
	if not is_instance_valid(edited_root):
		return false

	return self == edited_root or edited_root.is_ancestor_of(self)
