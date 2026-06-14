extends Node

const LOG_PREFIX := "[startup_probe]"
const BYTES_PER_MIB := 1048576.0

var _boot_usec := 0
var _phase_counter := 0


func _ready() -> void:
	_boot_usec = Time.get_ticks_usec()
	mark_phase("boot")


func mark_phase(label: String, context: Dictionary = {}) -> void:
	if not OS.is_debug_build():
		return

	_phase_counter += 1
	var elapsed_ms := float(Time.get_ticks_usec() - _boot_usec) / 1000.0 if _boot_usec > 0 else 0.0
	var metrics := _collect_metrics()
	var context_text := _format_context(context)
	print(
		"%s phase=%02d label=%s elapsed_ms=%.1f fps=%d frame_ms=%.2f draw_calls=%d primitives=%d vram_mib=%.1f dense_emitters=%d dense_particles=%d nodes=%d%s"
		% [
			LOG_PREFIX,
			_phase_counter,
			label,
			elapsed_ms,
			int(metrics.get("fps", 0)),
			float(metrics.get("frame_ms", 0.0)),
			int(metrics.get("draw_calls", 0)),
			int(metrics.get("primitives", 0)),
			float(metrics.get("vram_mib", 0.0)),
			int(metrics.get("dense_emitters", 0)),
			int(metrics.get("dense_particles", 0)),
			int(metrics.get("nodes", 0)),
			context_text,
		]
	)


func mark_first_controllable_frame(context: Dictionary = {}) -> void:
	mark_phase("first_controllable_frame", context)


func _collect_metrics() -> Dictionary:
	var frame_time_sec := Performance.get_monitor(Performance.TIME_PROCESS)
	var root_node := get_tree().root if get_tree() else null
	var dense_totals := _collect_dense_particle_totals(root_node)
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": frame_time_sec * 1000.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"vram_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MIB,
		"dense_emitters": dense_totals.get("emitters", 0),
		"dense_particles": dense_totals.get("particles", 0),
		"nodes": _count_nodes(root_node),
	}


func _collect_dense_particle_totals(node: Node) -> Dictionary:
	var result := {
		"emitters": 0,
		"particles": 0,
	}
	if not node:
		return result

	if node is GPUParticles3D and _is_dense_particle_emitter(node):
		result["emitters"] = 1
		result["particles"] = int((node as GPUParticles3D).amount)

	for child: Node in node.get_children(true):
		var child_result := _collect_dense_particle_totals(child)
		result["emitters"] = int(result["emitters"]) + int(child_result["emitters"])
		result["particles"] = int(result["particles"]) + int(child_result["particles"])
	return result


func _is_dense_particle_emitter(node: Node) -> bool:
	var parent := node.get_parent()
	while parent:
		if bool(parent.get_meta(&"village_rice_dense_plants_layer", false)):
			return true
		if bool(parent.get_meta(&"forest_dense_grass_layer", false)):
			return true
		parent = parent.get_parent()
	return false


func _count_nodes(node: Node) -> int:
	if not node:
		return 0

	var count := 1
	for child: Node in node.get_children(true):
		count += _count_nodes(child)
	return count


func _format_context(context: Dictionary) -> String:
	if context.is_empty():
		return ""

	var keys: Array[String] = []
	for key: Variant in context.keys():
		keys.append(str(key))
	keys.sort()

	var parts: Array[String] = []
	for key: String in keys:
		parts.append("%s=%s" % [key, str(context[key])])
	return " " + " ".join(parts)
