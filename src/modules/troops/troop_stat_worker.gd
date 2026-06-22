extends RefCounted
class_name TroopStatWorker

var result: Dictionary = {}


func run(request: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	result = calculate(request)
	result["worker_usec"] = Time.get_ticks_usec() - started


static func calculate(request: Dictionary) -> Dictionary:
	var effects: Dictionary = request.get("effects", {})
	var results: Array[Dictionary] = []
	for soldier_variant: Variant in request.get("soldiers", []):
		if not (soldier_variant is Dictionary):
			continue
		var soldier := soldier_variant as Dictionary
		var next := _calculate_soldier_result(soldier, effects)
		if not next.is_empty():
			results.append(next)
	return {
		"job_id": int(request.get("job_id", 0)),
		"results": results,
		"soldier_count": int(request.get("soldier_count", 0)),
		"effect_label": String(request.get("effect_label", "")),
	}


static func _calculate_soldier_result(soldier: Dictionary, effects: Dictionary) -> Dictionary:
	var soldier_id := int(soldier.get("id", 0))
	if soldier_id == 0:
		return {}

	var original_health := float(soldier.get("health", 0.0))
	var original_max_strength := float(soldier.get("max_strength", 1.0))
	var original_damage := float(soldier.get("damage", 0.1))
	var original_morale := float(soldier.get("morale", 0.0))
	var original_endurance := float(soldier.get("endurance", 0.0))
	var original_max_endurance := float(soldier.get("max_endurance", 1.0))
	var original_starving_days := float(soldier.get("starving_days", 0.0))

	var health := original_health
	var max_strength := maxf(original_max_strength, 1.0)
	var damage := maxf(original_damage, 0.1)
	var morale := clampf(original_morale, 0.0, 100.0)
	var endurance := clampf(original_endurance, 0.0, maxf(original_max_endurance, 1.0))
	var max_endurance := maxf(original_max_endurance, 1.0)
	var starving_days := maxf(original_starving_days, 0.0)
	var kill := false
	var death_reason := &"starvation"

	var starvation_days := maxf(float(effects.get("starvation_days", 0.0)), 0.0)
	if starvation_days > 0.0:
		var starvation_ratio := clampf(float(effects.get("starvation_ratio", 0.0)), 0.0, 1.0)
		if starvation_ratio <= 0.0:
			starving_days = maxf(starving_days - starvation_days, 0.0)
		else:
			starving_days += starvation_ratio * starvation_days
			endurance = clampf(
				endurance - maxf(float(effects.get("starvation_endurance_loss_per_day", 0.0)), 0.0) * starvation_ratio * starvation_days,
				0.0,
				max_endurance
			)
			health = maxf(
				health - maxf(float(effects.get("starvation_health_loss_per_day", 0.0)), 0.0) * starvation_ratio * starvation_days,
				0.0
			)
			if health <= 0.0:
				kill = true
			else:
				var death_start := maxf(float(effects.get("starvation_death_start_days", 0.0)), 0.0)
				if starving_days >= death_start:
					var daily_chance := clampf(
						maxf(float(effects.get("starvation_death_base_chance_per_day", 0.0)), 0.0)
						+ maxf(starving_days - death_start, 0.0) * maxf(float(effects.get("starvation_death_extra_chance_per_day", 0.0)), 0.0),
						0.0,
						clampf(float(effects.get("starvation_death_max_chance_per_day", 0.0)), 0.0, 1.0)
					)
					var probability := clampf(daily_chance * starvation_days * starvation_ratio, 0.0, 1.0)
					if clampf(float(soldier.get("death_roll", 1.0)), 0.0, 1.0) < probability:
						kill = true

	max_strength = maxf(
		max_strength + _get_soft_capped_gain(max_strength, float(effects.get("training_strength", 0.0)), float(effects.get("training_strength_soft_cap", max_strength))),
		1.0
	)
	damage = maxf(
		damage
		+ _get_soft_capped_gain(damage, float(effects.get("training_damage", 0.0)), float(effects.get("training_damage_soft_cap", damage)))
		+ _get_soft_capped_gain(damage, float(effects.get("fight_damage", 0.0)), float(effects.get("fight_damage_soft_cap", damage))),
		0.1
	)
	morale = clampf(
		morale
		+ _get_soft_capped_gain(morale, float(effects.get("training_morale", 0.0)), float(effects.get("training_morale_soft_cap", morale)))
		+ float(effects.get("morale_delta", 0.0)),
		0.0,
		100.0
	)
	max_endurance = maxf(
		max_endurance
		+ _get_soft_capped_gain(max_endurance, float(effects.get("training_max_endurance", 0.0)), float(effects.get("training_endurance_soft_cap", max_endurance)))
		+ _get_soft_capped_gain(max_endurance, float(effects.get("fight_max_endurance", 0.0)), float(effects.get("fight_endurance_soft_cap", max_endurance))),
		1.0
	)
	endurance = clampf(endurance + float(effects.get("endurance_delta", 0.0)), 0.0, max_endurance)
	health = clampf(health, 0.0, max_strength)

	if (
		not kill
		and is_equal_approx(health, original_health)
		and is_equal_approx(max_strength, original_max_strength)
		and is_equal_approx(damage, original_damage)
		and is_equal_approx(morale, original_morale)
		and is_equal_approx(endurance, original_endurance)
		and is_equal_approx(max_endurance, original_max_endurance)
		and is_equal_approx(starving_days, original_starving_days)
	):
		return {}

	return {
		"id": soldier_id,
		"health": health,
		"max_strength": max_strength,
		"damage": damage,
		"morale": morale,
		"endurance": endurance,
		"max_endurance": max_endurance,
		"starving_days": starving_days,
		"kill": kill,
		"death_reason": death_reason,
	}


static func _get_soft_capped_gain(current_value: float, amount: float, soft_cap: float) -> float:
	if amount <= 0.0 or soft_cap <= current_value:
		return 0.0
	var remaining_ratio := clampf((soft_cap - current_value) / maxf(soft_cap, 0.001), 0.0, 1.0)
	return amount * remaining_ratio
