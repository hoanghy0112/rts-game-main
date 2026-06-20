extends SceneTree

const MovementMapDataScript = preload("res://modules/map/movement_map_data.gd")
const OUTPUT_PATH := "res://modules/draft/draft_movement_map.res"


func _init() -> void:
	var data: MovementMapData = MovementMapDataScript.new()
	data.origin = Vector2(-512.0, -512.0)
	data.cell_size_meters = 16.0
	data.resize_map(64, 64, 1.0, 0)
	var error := ResourceSaver.save(data, OUTPUT_PATH, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not save %s: %d" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("Saved %s." % OUTPUT_PATH)
	quit(0)
