@tool
extends Node

const BONE_BINDINGS := [
	{ "target_path": ^"../Armature/Torso", "bone_name": &"Chest" },
	{ "target_path": ^"../Armature/Head", "bone_name": &"Head" },
	{ "target_path": ^"../Armature/LeftArm", "bone_name": &"UpperArm.L" },
	{ "target_path": ^"../Armature/RightArm", "bone_name": &"UpperArm.R" },
	{ "target_path": ^"../Armature/LeftLeg", "bone_name": &"UpperLeg.L" },
	{ "target_path": ^"../Armature/RightLeg", "bone_name": &"UpperLeg.R" },
	{ "target_path": ^"../Armature/RightArm/RightHandSocket", "bone_name": &"Hand.R" },
]

@export var enabled := true
@export_node_path("Skeleton3D") var skeleton_path: NodePath = ^"../ExternalModelSocket/AnimatedHumanoid/PersonAnimated/Armature/Skeleton3D"

var _skeleton: Skeleton3D
var _targets: Array[Node3D] = []
var _bone_indices: Array[int] = []
var _basis_offsets: Array[Basis] = []
var _bindings_configured := false


func _enter_tree() -> void:
	process_priority = 1000
	set_process(true)


func _ready() -> void:
	_configure_bindings()
	_sync_to_skeleton()


func _process(_delta: float) -> void:
	if not enabled:
		return
	if not _bindings_configured or not is_instance_valid(_skeleton):
		_configure_bindings()
	_sync_to_skeleton()


func _configure_bindings() -> void:
	_targets.clear()
	_bone_indices.clear()
	_basis_offsets.clear()
	_bindings_configured = false

	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _skeleton:
		return

	for binding in BONE_BINDINGS:
		var target := get_node_or_null(binding["target_path"]) as Node3D
		if not target:
			continue

		var bone_index := _skeleton.find_bone(String(binding["bone_name"]))
		if bone_index < 0:
			continue

		var bone_rest_transform := _skeleton.global_transform * _skeleton.get_bone_global_rest(bone_index)
		var bone_rest_basis := bone_rest_transform.basis.orthonormalized()
		var target_basis := target.global_transform.basis.orthonormalized()
		_targets.append(target)
		_bone_indices.append(bone_index)
		_basis_offsets.append(bone_rest_basis.inverse() * target_basis)

	_bindings_configured = true


func _sync_to_skeleton() -> void:
	if not enabled or not _bindings_configured or not _skeleton:
		return

	for index in range(_targets.size()):
		var target := _targets[index]
		if not is_instance_valid(target):
			_bindings_configured = false
			return

		var bone_index := _bone_indices[index]
		var bone_global_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_index)
		var corrected_basis := bone_global_transform.basis.orthonormalized()
		if index < _basis_offsets.size():
			corrected_basis *= _basis_offsets[index]

		target.global_transform = Transform3D(corrected_basis, bone_global_transform.origin)
