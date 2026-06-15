@tool
extends Resource
class_name ForestPlantTypeData

enum PlantCategory {
	TREE,
	PALM,
	BAMBOO,
	SHRUB,
	FERN,
	GRASS,
}

enum RenderStrategy {
	MULTIMESH,
	DENSE_GRASS_PARTICLES,
}

@export var id: StringName = &"plant"
@export var display_name: String = "Plant"
@export_multiline var description: String = ""
@export var category: PlantCategory = PlantCategory.TREE
@export var default_selected := true
@export var render_strategy: RenderStrategy = RenderStrategy.MULTIMESH

@export_group("Scenes")
@export var scene: PackedScene
@export var lod1_scene: PackedScene
@export var lod2_scene: PackedScene
@export var billboard_scene: PackedScene

@export_group("Placement")
@export_range(0.0, 256.0, 0.1, "or_greater") var density_per_cell: float = 1.0
@export_range(0.0, 1.0, 0.01) var density_jitter: float = 0.25
@export_range(0.01, 16.0, 0.01, "or_greater") var min_scale: float = 0.9
@export_range(0.01, 16.0, 0.01, "or_greater") var max_scale: float = 1.15
@export_range(0.0, 8.0, 0.01, "or_greater") var surface_offset: float = 0.0
@export_range(0.0, 1.0, 0.01) var cell_edge_margin: float = 0.08
@export var random_yaw := true
@export var align_to_surface := false
@export var disable_shadows := false

@export_group("LOD Thinning")
@export_range(1.0, 10000.0, 1.0, "or_greater") var near_visible_distance: float = 64.0
@export_range(1.0, 10000.0, 1.0, "or_greater") var mid_visible_distance: float = 144.0
@export_range(1.0, 10000.0, 1.0, "or_greater") var far_visible_distance: float = 320.0
@export_range(1.0, 20000.0, 1.0, "or_greater") var billboard_visible_distance: float = 1600.0
@export_range(0.0, 1.0, 0.01) var mid_keep_ratio: float = 0.45
@export_range(0.0, 1.0, 0.01) var far_keep_ratio: float = 0.12
@export_range(0.0, 1.0, 0.01) var billboard_keep_ratio: float = 0.22
@export_range(0.1, 8.0, 0.01, "or_greater") var mid_scale_multiplier: float = 1.0
@export_range(0.1, 8.0, 0.01, "or_greater") var far_scale_multiplier: float = 1.0
@export_range(0.1, 8.0, 0.01, "or_greater") var billboard_scale_multiplier: float = 1.0
@export_range(-1, 8, 1, "or_greater") var max_shadow_lod_tier: int = 0

@export_group("Terrain3D")
@export var terrain3d_mesh_id: int = -1

@export_group("Dense Grass Particles")
@export var dense_particle_scene: PackedScene


func get_scene_for_lod(lod_tier: int) -> PackedScene:
	if lod_tier >= 3 and billboard_scene:
		return billboard_scene
	if lod_tier >= 2 and lod2_scene:
		return lod2_scene
	if lod_tier >= 1 and lod1_scene:
		return lod1_scene
	return scene


func get_visible_distance_for_lod(lod_tier: int) -> float:
	match lod_tier:
		0:
			return near_visible_distance
		1:
			return mid_visible_distance
		2:
			return far_visible_distance
		_:
			return billboard_visible_distance


func get_keep_ratio_for_lod(lod_tier: int) -> float:
	match lod_tier:
		0:
			return 1.0
		1:
			return mid_keep_ratio
		2:
			return far_keep_ratio
		_:
			return billboard_keep_ratio


func get_scale_multiplier_for_lod(lod_tier: int) -> float:
	match lod_tier:
		0:
			return 1.0
		1:
			return mid_scale_multiplier
		2:
			return far_scale_multiplier
		_:
			return billboard_scale_multiplier
