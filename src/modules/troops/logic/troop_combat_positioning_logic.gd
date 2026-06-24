extends Resource
class_name TroopCombatPositioningLogic


func get_soldier_engagement_position(troop, attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	var socket_direction: Vector3 = troop._get_combat_socket_direction(attacker, defender, index, total)
	var side := Vector3(-socket_direction.z, 0.0, socket_direction.x)
	var offset: Vector2 = troop._get_combat_offset_for_soldier(attacker, index, total)
	var spear_range: float = maxf(float(troop.combat_spear_range_m), 0.2)
	var clamp_margin := clampf(spear_range * 0.04, 0.06, 0.18)
	var max_socket_distance := maxf(spear_range - clamp_margin, 0.2)
	var min_socket_distance := minf(0.45, max_socket_distance)
	var base_radius: float = maxf(
		float(troop.combat_socket_radius),
		float(troop.soldier_personal_space_radius) + float(troop.enemy_personal_space_radius) + 0.16
	)
	var radius := clampf(base_radius + offset.y, min_socket_distance, max_socket_distance)
	var max_lateral := sqrt(maxf(max_socket_distance * max_socket_distance - radius * radius, 0.0))
	var lateral := clampf(offset.x, -max_lateral, max_lateral)
	var desired := defender.global_position + socket_direction * radius + side * lateral
	desired = troop._clamp_combat_socket_position(defender, desired, attacker.global_position.y)
	troop._combat_soldier_socket_positions[attacker.get_instance_id()] = desired
	return desired


func get_combat_socket_direction(troop, attacker: Node3D, defender: Node3D, index: int, total: int) -> Vector3:
	var key := attacker.get_instance_id()
	var stored: Variant = troop._combat_soldier_socket_directions.get(key)
	if stored is Vector3:
		var stored_direction: Vector3 = stored
		stored_direction.y = 0.0
		if stored_direction.length_squared() > 0.0001:
			return stored_direction.normalized()
	var socket_index := int(troop._combat_soldier_socket_indices.get(key, index))
	var direction := make_combat_socket_direction(troop, attacker, defender, socket_index, total)
	troop._combat_soldier_socket_directions[key] = direction
	return direction


func make_combat_socket_direction(troop, attacker: Node3D, defender: Node3D, socket_index: int, total: int) -> Vector3:
	var approach: Vector3 = troop.global_position - defender.global_position
	approach.y = 0.0
	if approach.length_squared() <= 0.0001:
		approach = attacker.global_position - defender.global_position
		approach.y = 0.0
	if approach.length_squared() <= 0.0001:
		var angle := TAU * float(socket_index) / float(maxi(total, 1))
		approach = Vector3(cos(angle), 0.0, sin(angle))
	approach = approach.normalized()
	var max_slots: int = maxi(int(troop.combat_max_attackers_per_target), 1)
	var ring := maxi(floori(float(socket_index) / float(max_slots)), 0)
	var slot := socket_index % max_slots
	var angle_offset := get_combat_surround_slot_angle(slot, max_slots)
	if ring > 0:
		angle_offset += float(ring) * (TAU / float(max_slots)) * 0.5
	var rotated := Basis(Vector3.UP, angle_offset) * approach
	rotated.y = 0.0
	if rotated.length_squared() <= 0.0001:
		return approach
	return rotated.normalized()


func get_combat_surround_slot_angle(slot: int, max_slots: int) -> float:
	var safe_slots := maxi(max_slots, 1)
	if safe_slots <= 1:
		return 0.0
	var safe_slot := posmod(slot, safe_slots)
	if safe_slot == 0:
		return 0.0
	var step := TAU / float(safe_slots)
	var pair_index := int(floori(float(safe_slot + 1) * 0.5))
	var sign := 1.0 if safe_slot % 2 == 1 else -1.0
	return sign * step * float(pair_index)


func get_combat_offset_for_soldier(troop, attacker: Node3D, index: int, total: int) -> Vector2:
	var key := attacker.get_instance_id()
	if troop._combat_soldier_offsets.has(key):
		return troop._combat_soldier_offsets[key] as Vector2
	var max_slots: int = maxi(int(troop.combat_max_attackers_per_target), 1)
	var socket_index := int(troop._combat_soldier_socket_indices.get(key, index))
	var local_slot_count := mini(max_slots, maxi(total, 1))
	var local_slot := socket_index % local_slot_count
	var centered := float(local_slot) - float(maxi(local_slot_count - 1, 0)) * 0.5
	var seed := float(absi(hash("%s:%s" % [String(troop.troop_id), String(attacker.name)])) % 10000) / 10000.0
	var width: float = maxf(float(troop.combat_frontline_width_per_soldier), 0.1)
	var lateral_jitter := (seed - 0.5) * width * 0.14
	var depth_jitter := (float(absi(hash("depth:%s" % String(attacker.name))) % 1000) / 1000.0 - 0.5) * 0.22
	var lateral := centered * width * 0.26 + lateral_jitter
	var max_lateral := width * 0.62
	var offset := Vector2(clampf(lateral, -max_lateral, max_lateral), depth_jitter)
	troop._combat_soldier_offsets[key] = offset
	return offset
