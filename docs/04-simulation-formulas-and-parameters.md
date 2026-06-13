# 04 - Công thức mô phỏng và tham số v0

## Quy ước

Tất cả stat cá nhân nằm trong `0..100`.

```text
N(x) = clamp(x / 100, 0, 1)
clamp(x, a, b) = min(max(x, a), b)
sigmoid(x) = 1 / (1 + exp(-x))
softmax(x_i) = exp(x_i) / Σ exp(x_j)
binomial(n, p) = seeded random sample of successes from n trials
```

Các công thức dưới đây là v0 để implement. Chúng cần balance bằng playtest.

## Nguồn tham số

Các số trong tài liệu này là default v0 để đưa vào config, không phải magic number trong code. Khi implement:

- mỗi công thức có file config riêng trong `content/common/formulas/`;
- bảng unit, terrain, weather, resource và building nằm trong `content/common/balance/`;
- global setting như tick rate, speed multiplier, camera/LOD threshold nằm trong `content/common/globals/`;
- code đọc tham số qua registry đã validate schema, không đọc string/path rải rác;
- thiếu tham số bắt buộc phải fail fast trong dev/test;
- mod/scenario chỉ được override qua data manifest có version.

## Thời gian

Default 1x:

```text
1 real second = 3 in-game hours
1 in-game day = 8 real seconds
1 in-game month = 240 real seconds = 4 minutes
1 in-game season = 720 real seconds = 12 minutes
1 in-game year = 2880 real seconds = 48 minutes
```

Game speed:

```text
game_hours_advanced = real_seconds * 3 * speed_multiplier
```

Allowed speed:

```text
speed_multiplier ∈ {0.25, 0.5, 1, 2, 4}
```

## Movement

Base speed by formation:

| Formation | Base km/day |
|---|---:|
| Infantry column | 24 |
| Spearmen formation | 18 |
| Swordsmen light | 26 |
| Archer column | 22 |
| Cavalry | 42 |
| Engineers | 18 |
| Supply convoy | 16 |
| Siege equipment | 8 |
| Boat upstream | 25 |
| Boat downstream | 45 |

Movement per tick:

```text
distance_m = base_speed_km_day * 1000 / 24 * game_hours_dt
           * terrain_factor
           * weather_factor
           * supply_factor
           * fatigue_factor
           * order_factor
```

Terrain factor:

```text
terrain_factor =
    road_factor
  * slope_factor
  * vegetation_factor
  * water_crossing_factor
```

Road factor:

```text
road_factor = 0.45 + 0.75 * road_condition
```

No road:

```text
road_condition = 0
road_factor = 0.45
```

Slope factor:

```text
slope_factor = clamp(1 - 0.025 * slope_deg, 0.25, 1.05)
```

Vegetation factor:

```text
vegetation_factor =
    1.00 plain
    0.80 paddy/dry field
    0.65 forest
    0.50 dense forest
    0.35 swamp
```

Water crossing:

```text
water_crossing_factor =
    1.00 bridge
    0.75 ford
    0.45 ferry
    0.15 improvised crossing
    0.00 impossible
```

Supply factor:

```text
supply_factor = clamp(0.45 + 0.55 * ration_days_remaining / ration_days_target, 0.45, 1.0)
```

Fatigue factor:

```text
fatigue_factor = clamp(1 - fatigue / 140, 0.35, 1.0)
```

Forced march:

```text
order_factor = 1.25
fatigue_gain_multiplier = 1.75
morale_loss_per_day += 2
```

Severe storm halt:

```text
if storm_severity >= 0.90:
    movement_factor = 0
```

## Mud and road damage

Mud update per in-game hour:

```text
mud_next = clamp(
    mud
  + 0.08 * rain_intensity
  + 0.04 * flood_level
  - 0.03 * heat_index
  - 0.02 * drainage_quality,
  0, 1
)
```

Weather factor:

```text
weather_factor = clamp(1 - 0.55 * mud - 0.35 * rain_intensity - 0.25 * wind_intensity, 0.05, 1.0)
```

Road condition decay:

```text
road_condition_next = clamp(
    road_condition
  - 0.015 * heavy_use
  - 0.020 * rain_intensity
  - 0.050 * flood_level
  - 0.100 * battle_damage
  + repair_rate,
  0, 1
)
```

## Heat penalty by faction climate profile

Faction parameter:

```text
heat_sensitivity:
    faction_a = 0.35
    faction_b = 1.00
    faction_c = 0.65
```

Heat stress per in-game hour:

```text
heat_stress_gain =
    heat_sensitivity
  * max(0, temperature_c - comfort_temp_c)
  * (0.5 + 0.5 * humidity)
  * exertion
  / 12
```

Default:

```text
comfort_temp_c = 28
exertion = 1.0 marching, 1.4 forced_march, 0.5 camped
```

Effect:

```text
fatigue += heat_stress_gain
health_loss_per_day += 0.15 * heat_stress
morale_delta_per_day -= 0.08 * heat_stress
```

## Supply consumption

Per individual per in-game day:

| Resource | Normal | Forced march/combat |
|---|---:|---:|
| rice/ration kg | 0.75 | 1.00 |
| meat kg | 0.10 | 0.15 |
| water liter | 3.00 | 5.00 |
| arrows | 0.00 | by combat |
| firearm shot | 0.00 | by combat |

Supply need:

```text
daily_food_kg = soldiers * food_rate * activity_multiplier
daily_water_l = soldiers * water_rate * heat_multiplier
```

Heat multiplier:

```text
heat_multiplier = 1 + max(0, temperature_c - 28) / 20
```

Shortage:

```text
food_shortage_ratio = clamp(1 - available_food / needed_food, 0, 1)
water_shortage_ratio = clamp(1 - available_water / needed_water, 0, 1)
```

Effects per day:

```text
morale_delta -= 18 * food_shortage_ratio + 28 * water_shortage_ratio
health_delta -= 6 * food_shortage_ratio + 14 * water_shortage_ratio
fatigue_delta += 12 * food_shortage_ratio + 20 * water_shortage_ratio
```

## Depot spoilage

Use exponential decay.

```text
quantity_next = quantity * exp(-decay_rate_per_day * days_dt)
```

Decay rate:

```text
decay_rate_per_day =
    base_decay[item]
  * weather_spoilage_multiplier
  * depot_quality_multiplier
  * handling_multiplier
```

Base decay:

| Item | Base decay/day |
|---|---:|
| dried rice | 0.003 |
| fresh rice | 0.012 |
| salted meat | 0.010 |
| fresh meat | 0.080 |
| water stored | 0.005 |
| arrows | 0.0005 |
| weapons | 0.0002 |
| armor | 0.0002 |

Depot quality multiplier:

| Depot | Multiplier |
|---|---:|
| field cache | 1.50 |
| thatched storehouse | 1.10 |
| raised granary | 0.70 |
| covered warehouse | 0.55 |
| reinforced depot | 0.35 |
| fortified depot | 0.30 |

Weather spoilage:

```text
weather_spoilage_multiplier =
    1
  + 1.2 * rain_intensity
  + 1.5 * flood_level
  + 0.8 * max(0, temperature_c - 30) / 10
```

## Depot collapse/damage

Daily collapse probability:

```text
p_collapse =
    1 - exp(-hazard_per_day)
```

Hazard:

```text
hazard_per_day =
    base_structural_risk[depot_type]
  * (1 + 2.0 * storm_severity + 1.2 * flood_level + 0.8 * wind_intensity)
  * (1 - maintenance_level)
```

Default base structural risk:

| Depot | Risk/day |
|---|---:|
| field cache | 0.020 |
| thatched storehouse | 0.010 |
| raised granary | 0.006 |
| covered warehouse | 0.004 |
| reinforced depot | 0.002 |
| fortified depot | 0.001 |

Loss if collapse:

```text
lost_food = stored_food * random_range(0.25, 0.80)
lost_weapons = stored_weapons * random_range(0.05, 0.35)
lost_armor = stored_armor * random_range(0.05, 0.30)
```

Use seeded RNG.

## Banditry risk

Daily looting probability:

```text
p_loot = sigmoid(
    -4.0
  + 2.5 * instability
  + 1.5 * depot_value_norm
  - 2.0 * guard_strength_norm
  - 1.0 * local_support
)
```

If looted:

```text
loot_loss_ratio = clamp(0.10 + 0.40 * instability - 0.25 * guard_strength_norm, 0.02, 0.60)
```

## Tax and resource extraction

Region output:

```text
resource_output =
    base_potential
  * labor_available
  * season_factor
  * infrastructure_factor
  * safety_factor
  * happiness_factor
```

Tax collected:

```text
tax_collected = resource_output * tax_rate * compliance
```

Compliance:

```text
compliance = clamp(
    0.35
  + 0.50 * local_support
  + 0.15 * garrison_legitimacy
  - 0.25 * tax_rate
  - 0.20 * enemy_pressure,
  0, 1
)
```

Happiness update per day:

```text
happiness_next = clamp(
    happiness
  - 0.20 * max(0, tax_rate - 0.25)
  - 0.15 * requisition_rate
  - 0.30 * foraging_damage
  - 0.25 * battle_damage_nearby
  + 0.10 * road_repair_effort
  + 0.12 * agricultural_aid
  + 0.08 * fair_trade
  + 0.05 * security_presence,
  0, 1
)
```

Support:

```text
local_support = clamp(0.65 * happiness + 0.20 * faction_legitimacy + 0.15 * recent_victory_effect, 0, 1)
```

Recruit quality:

```text
recruit_quality =
    35
  + 25 * local_support
  + 15 * food_security
  + 10 * local_training_infrastructure
  + random_normal(0, 8)
```

Clamp to `1..100`.

## Training

Stat gain per in-game day:

```text
stat_gain =
    learning_rate[stat]
  * trainer_quality
  * drill_hours / 8
  * supply_factor
  * morale_factor
  * (1 - current_stat / 100)
```

Trainer quality:

```text
trainer_quality =
    0.40 * N(general_intelligence)
  + 0.30 * N(general_strength)
  + 0.20 * N(general_courage)
  + 0.10 * unit_discipline
```

Default learning rate/day:

| Stat | Rate |
|---|---:|
| courage | 1.2 |
| loyalty | 0.5 |
| intelligence | 0.4 |
| strength | 1.0 |
| health | 0.8 |

## Morale

Individual morale component:

```text
individual_morale =
    0.25 * N(courage)
  + 0.20 * N(loyalty)
  + 0.15 * N(intelligence)
  + 0.20 * N(health)
  + 0.20 * situation_score
```

Formation morale:

```text
morale =
    100 * clamp(
      0.55 * average_individual_morale
    + 0.15 * N(general_courage)
    + 0.10 * N(general_loyalty)
    + 0.10 * recent_outcome_score
    + 0.10 * supply_state,
    0, 1
)
```

Situation score:

```text
situation_score =
    clamp(
      0.50
    + 0.15 * terrain_advantage
    + 0.15 * friendly_nearby_ratio
    + 0.10 * fortified
    - 0.20 * encirclement
    - 0.15 * casualty_ratio_recent
    - 0.10 * fatigue_norm,
    0, 1
)
```

Recent outcome:

```text
recent_outcome_score =
    clamp(
      0.50
    + 0.25 * recent_victory_count
    - 0.25 * recent_defeat_count
    - 0.15 * commander_wounded
    - 0.20 * route_cut,
    0, 1
)
```

## Desertion and routing

Checked every in-game hour for formations with low morale, low loyalty, active combat, encirclement or recent severe losses.

```text
desertion_pressure =
    clamp(
      0.30 * (1 - morale / 100)
    + 0.25 * (1 - average_loyalty / 100)
    + 0.15 * casualty_ratio_recent
    + 0.15 * encirclement
    + 0.10 * supply_shortage_ratio
    + 0.05 * unpaid_or_unrewarded_days_norm
    + state_pressure_bonus
    - 0.20 * discipline
    - 0.15 * N(general_courage)
    - 0.10 * N(general_loyalty)
    - 0.10 * retreat_route_safety,
    0, 1
)
```

State pressure bonus:

| Formation state | Bonus |
|---|---:|
| camped/idle | 0.00 |
| marching | 0.04 |
| skirmishing | 0.08 |
| fighting | 0.14 |
| withdrawing | 0.10 |
| encircled | 0.18 |
| routing | 0.24 |

Hourly probability:

```text
p_desertion = sigmoid(
    -6.0
  + 7.5 * desertion_pressure
)
```

Deserter count:

```text
deserter_count =
    binomial(
      formation_count,
      p_desertion * desertion_scale_by_policy
    )
```

Default:

```text
desertion_scale_by_policy =
    0.50 strict_discipline
    1.00 normal
    1.25 unpaid_or_poorly_supplied
```

Routing trigger is separate from desertion:

```text
p_rout = sigmoid(
    -5.5
  + 5.0 * (1 - morale / 100)
  + 2.0 * casualty_ratio_recent
  + 1.5 * encirclement
  - 1.5 * discipline
  - 1.0 * nearby_friendly_support
)
```

If rout happens, formation enters `routing`. Desertion may then remove individuals from the formation if pressure remains high. Use seeded RNG and emit `FormationRouted` or `UnitDeserted` events.

## Combat power

Formation effective combat strength:

```text
ECS =
    unit_count
  * base_unit_power[unit_type]
  * equipment_factor
  * training_factor
  * health_factor
  * morale_factor
  * supply_factor
  * formation_factor
  * terrain_factor_combat
  * commander_factor
```

Factors:

```text
training_factor = 0.60 + 0.40 * average_strength / 100
health_factor = 0.30 + 0.70 * average_health / 100
morale_factor = 0.35 + 0.65 * morale / 100
commander_factor = 0.85 + 0.30 * N(general_intelligence) + 0.15 * N(general_courage)
```

Base unit power:

| Unit | Base power |
|---|---:|
| spearmen | 1.10 |
| swordsmen | 1.00 |
| archers | 0.85 |
| firearm infantry | 1.25 |
| cavalry | 1.45 |
| engineers in combat | 0.55 |
| naval arrows | 1.00 |
| naval cannon | 2.10 |
| naval fire weapon | 1.60 |

Counter modifiers:

```text
spearmen_vs_cavalry = 1.55 if formation_locked else 1.15
cavalry_vs_swordsmen = 1.35 on open terrain
archer_vs_unshielded = 1.25
firearm_vs_armor = 1.30
forest_penalty_cavalry = 0.55
paddy_penalty_cavalry = 0.70
```

Damage per combat tick:

```text
damage_A_to_B =
    lethality
  * ECS_A
  / (ECS_A + defense_ECS_B + 1)
  * exposure_B
  * dt_combat
```

Casualties:

```text
casualties = floor(damage_A_to_B * casualty_scale * seeded_random_variation)
```

Default:

```text
lethality = 0.08
casualty_scale = 10
seeded_random_variation ∈ [0.85, 1.15]
```

## Defense

Defense ECS:

```text
defense_ECS =
    ECS_B
  * (1 + 0.50 * terrain_defense_score)
  * (1 + fortification_bonus)
  * (1 - supply_shortage_penalty)
```

Fortification bonus:

| Fortification | Bonus |
|---|---:|
| none | 0.00 |
| trench | 0.20 |
| rampart | 0.35 |
| wooden fort | 0.50 |
| fortress | 0.80 |

## Encirclement

Encirclement score is based on blocked arcs around target.

```text
encirclement =
    blocked_arc_degrees / 360
  * supply_route_cut_factor
  * enemy_pressure_factor
```

Supply route cut factor:

```text
supply_route_cut_factor = 0.50 + 0.50 * cut_supply_routes / max(1, total_supply_routes)
```

Enemy pressure:

```text
enemy_pressure_factor = clamp(enemy_ECS_nearby / max(own_ECS, 1), 0.25, 1.50)
```

## Surrender probability

Checked every in-game hour when encircled or after severe defeat.

```text
p_surrender = sigmoid(
    -5.0
  + 4.0 * encirclement
  + 2.0 * food_shortage_ratio
  + 2.5 * water_shortage_ratio
  + 2.0 * casualty_ratio_recent
  - 2.5 * N(general_loyalty)
  - 1.8 * N(general_courage)
  - 1.2 * morale / 100
)
```

High-loyalty generals surrender less often because their loyalty and courage reduce the logit.

## Report accuracy

A general report has true state plus noise.

Detection probability:

```text
p_detect = sigmoid(
    -2.0
  + 0.05 * general_intelligence
  + 0.03 * scout_quality
  + 0.02 * local_support * 100
  - 0.04 * enemy_concealment
  - 0.03 * terrain_complexity
  - 0.02 * distance_km
)
```

Position error:

```text
error_radius_m =
    base_error_m
  * (1 - 0.007 * general_intelligence)
  * (1 + terrain_complexity)
  * (1 + weather_visibility_penalty)
```

Default:

```text
base_error_m = 5000 strategic, 1000 operational, 200 tactical
```

Status classification:

```text
threat_score =
    0.35 * enemy_ECS_ratio
  + 0.25 * supply_shortage_ratio
  + 0.20 * depot_risk
  + 0.10 * local_unrest
  + 0.10 * weather_risk
```

```text
Stable: threat_score < 0.30
Threatened: 0.30 <= threat_score < 0.55
Critical: 0.55 <= threat_score < 0.75
At War: active_combat == true
Collapse Risk: threat_score >= 0.75 and not active_combat
```

Intelligence noise:

```text
reported_threat_score =
    clamp(threat_score + random_normal(0, sigma), 0, 1)

sigma = 0.25 * (1 - N(general_intelligence)) + 0.05 * weather_visibility_penalty
```

## AI action probability

AI decisions use perceived state, not perfect truth. `p_smart` is the softmax distribution over utility scores. `p_mistake` is a separate distribution over poor or risky candidates from an `AiMistakeBiasStrategy`.

```text
p_smart(action) =
    softmax(action_score[action] / decision_temperature)

p_mistake(action) =
    softmax(mistake_bias_score[action] / mistake_temperature)
```

General intelligence mixes both distributions:

```text
smartness = clamp(N(general_intelligence), 0.05, 1.0)

p_action_raw(action) =
    smartness * p_smart(action)
  + (1 - smartness) * p_mistake(action)

p_action(action) =
    p_action_raw(action) / Σ p_action_raw(all_candidates)
```

Default:

```text
decision_temperature = 0.20
mistake_temperature = 0.35
```

Mistake bias examples:

```text
mistake_bias_score =
    0.30 * overconfidence_attack_bias
  + 0.25 * bad_intel_target_bias
  + 0.20 * delayed_retreat_bias
  + 0.15 * pursuit_overextension_bias
  + 0.10 * terrain_misread_bias
```

Low intelligence should increase wrong decisions through probability, not through hard-coded forced failure. High intelligence still suffers from bad intel because `action_score` uses perceived inputs.

## Combat-zone civilian displacement

Regions with active combat or multiple opposing armies occupying/contesting the area create civilian displacement pressure.

```text
combat_zone_pressure =
    clamp(
      0.35 * active_combat
    + 0.25 * opposing_army_presence
    + 0.15 * army_density_norm
    + 0.10 * siege_or_encirclement_nearby
    + 0.10 * looting_or_foraging_damage
    + 0.05 * recent_battle_damage,
    0, 1
)
```

Daily displacement probability:

```text
p_displacement =
    sigmoid(
      -4.5
    + 5.0 * combat_zone_pressure
    + 1.5 * (1 - safety)
    + 1.0 * food_insecurity
    - 1.2 * evacuation_support
    - 0.8 * trusted_garrison_presence
)
```

People leaving source region per day:

```text
displaced_population =
    floor(population * p_displacement * displacement_scale)
```

Default:

```text
displacement_scale = 0.08
```

Destination score:

```text
destination_score =
    0.30 * safety
  + 0.20 * food_security
  + 0.15 * same_faction_or_allied_control
  + 0.15 * route_access
  + 0.10 * capacity_remaining
  + 0.10 * local_support
  - 0.25 * distance_cost
  - 0.20 * known_enemy_threat
```

Effects:

```text
source_population_next -= displaced_population
source_labor_available_next -= displaced_population * labor_ratio
source_happiness_next -= 0.05 * combat_zone_pressure

destination_refugees_next += displaced_population
destination_food_need_next += displaced_population * civilian_food_rate
destination_overcrowding_next =
    max(0, destination_population / civilian_capacity - 1)
```

Refugees become normal population only after `settlement_days_required`, if safety, food and housing are sufficient. Otherwise they continue consuming food, increasing disease/unrest risk and lowering local support if neglected.

## Construction

Progress per day:

```text
progress +=
    labor_points
  * tool_factor
  * material_availability
  * weather_construction_factor
  * terrain_build_factor
  / required_work_points
```

Labor points:

```text
labor_points =
    civilians * 1.0
  + engineers * 2.0
  + regular_soldiers * 0.8
```

Combat readiness penalty for soldiers on labor:

```text
readiness = readiness_base * (1 - 0.60 * labor_assignment_ratio)
health_delta_per_day -= 1.5 * labor_assignment_ratio * harsh_weather_factor
```

Weather construction factor:

```text
weather_construction_factor =
    clamp(1 - 0.50 * rain_intensity - 0.80 * storm_severity - 0.30 * mud, 0, 1)
```

Terrain build factor:

```text
terrain_build_factor = clamp(1 - 0.02 * slope_deg - 0.30 * flood_level, 0.2, 1.0)
```

## Diplomacy

Agreement acceptance score:

```text
acceptance =
    base_relation
  + 0.30 * mutual_enemy_pressure
  + 0.25 * trade_value
  + 0.20 * offered_gold_norm
  - 0.30 * betrayal_memory
  - 0.25 * ideological_conflict
  - 0.20 * current_strength_advantage
```

Accept if:

```text
acceptance + random_normal(0, 0.05) >= 0.50
```

Subsidy amount:

```text
subsidy_gold =
    requested_gold
  * clamp(acceptance, 0, 1)
  * donor_treasury_factor
```

## Balancing rule

Every formula must have:

- unit test for boundary values;
- debug UI display;
- config parameter with id, default, min/max and version;
- replay-safe random source;
- telemetry counter during playtest.

No gameplay formula may keep tunable values hard-coded in simulation code. Only mathematical constants and unit conversions are acceptable as code constants.
