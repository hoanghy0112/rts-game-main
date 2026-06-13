# 07 - Thời tiết, mùa, thời gian

## Design goal

Weather must change decisions, not just visuals.

Weather affects:

- marching speed;
- road mud and road damage;
- depot spoilage/collapse;
- construction speed;
- disease/health;
- visibility/report accuracy;
- naval movement;
- defensive advantages;
- northern troop heat stress.

## Time compression

Default:

```text
1 day = 8 real seconds
1 month = 4 real minutes
1 season = 12 real minutes
1 year = 48 real minutes
```

This matches "traditional RTS fast time" while still letting seasons matter.

Season mapping:

| Season | Months | Gameplay focus |
|---|---|---|
| Spring | 1-3 | planting, road recovery, moderate rain |
| Summer | 4-6 | heat, rain, disease risk |
| Autumn | 7-9 | harvest, storms/flood risk |
| Winter | 10-12 | cooler, lower heat stress, campaign windows |

This is a gameplay simplification; exact climate/month profiles must come from climate dataset or scenario tuning.

## Weather cell

Map is divided into weather cells larger than tactical chunks.

Default:

```text
weather_cell_size = 16 km
```

Weather state:

```text
WeatherCell {
    temperature_c;
    humidity;
    rain_intensity;  // 0..1
    wind_intensity;  // 0..1
    storm_severity;  // 0..1
    flood_level;     // 0..1
    visibility;      // 0..1
    mud;             // 0..1
}
```

## Weather generation

Use seasonal climate normals as baseline, then seeded stochastic variation.

Rain probability per day:

```text
p_rain =
    clamp(
      monthly_rainfall_mm / 300
    + terrain_orographic_bonus
    + monsoon_modifier
    - drought_modifier,
    0.05, 0.85
)
```

Rain intensity:

```text
rain_intensity =
    clamp(
      random_beta(alpha_season, beta_season)
    * rain_event_multiplier,
    0, 1
)
```

Storm severity:

```text
storm_severity =
    clamp(
      0.60 * rain_intensity
    + 0.40 * wind_intensity
    + storm_event_bonus,
    0, 1
)
```

Storm event:

```text
p_storm_event =
    clamp(0.02 + 0.10 * monsoon_peak + 0.08 * coastal_exposure, 0, 0.25)
```

## Movement effects

Rain:

```text
movement_weather_factor =
    clamp(1 - 0.35 * rain_intensity - 0.55 * mud - 0.25 * wind_intensity, 0.05, 1)
```

Severe storm:

```text
if storm_severity >= 0.90:
    marching_allowed = false
```

Exception:

- units can move within camp/fort;
- emergency retreat may move at `0.10 * base_speed` with heavy casualty/fatigue risk;
- naval units seek shelter instead of continuing route.

## Logistics effects

Route throughput:

```text
throughput_weather_factor =
    clamp(1 - 0.40 * rain_intensity - 0.50 * mud - 0.60 * flood_level, 0, 1)
```

Depot spoilage:

```text
spoilage_weather_factor =
    1
  + 1.2 * rain_intensity
  + 1.5 * flood_level
  + 0.8 * heat_excess
```

Heat excess:

```text
heat_excess = max(0, temperature_c - 30) / 10
```

## Defense effects

Weather can help defenders.

```text
defense_weather_bonus =
    0.10 * rain_intensity
  + 0.15 * mud
  + 0.10 * low_visibility
```

But storms damage weak defenses:

```text
fortification_damage_risk =
    base_risk
  * (1 + 2.0 * storm_severity + 1.2 * flood_level)
  * (1 - maintenance)
```

## Visibility and reports

Visibility:

```text
visibility =
    clamp(
      1
    - 0.45 * rain_intensity
    - 0.35 * storm_severity
    - 0.20 * forest_density
    - 0.15 * night_factor,
    0.05, 1
)
```

Report delay:

```text
report_delay_hours =
    base_distance_hours
  / messenger_speed_factor
  * (1 + 1.5 * mud + 1.0 * storm_severity)
```

Report accuracy uses `visibility` as weather penalty.

## Heat and acclimatization

Each formation has acclimatization:

```text
acclimatization ∈ 0..1
```

Initial values:

```text
faction_a = 0.80
faction_b = 0.20
faction_c = 0.45
```

Acclimatization gain:

```text
acclimatization_next =
    clamp(acclimatization + 0.01 * days_in_region - 0.02 * severe_heat_days, 0, 1)
```

Heat sensitivity effective:

```text
effective_heat_sensitivity =
    base_heat_sensitivity * (1 - 0.50 * acclimatization)
```

Heat stress:

```text
heat_stress_gain =
    effective_heat_sensitivity
  * max(0, temperature_c - comfort_temp_c)
  * (0.5 + 0.5 * humidity)
  * exertion
  / 12
```

## Disease risk

Daily disease risk:

```text
disease_risk =
    clamp(
      0.02
    + 0.08 * humidity
    + 0.08 * flood_level
    + 0.06 * camp_overcrowding
    + 0.05 * spoiled_food_usage
    - 0.05 * sanitation
    - 0.04 * clean_water_access,
    0, 0.40
)
```

Health loss:

```text
health_loss_disease = disease_risk * random_range(0.5, 2.0)
```

## Seasonal economy

Rice output by season:

```text
rice_season_factor =
    0.60 spring
    0.80 summer
    1.40 autumn harvest
    0.50 winter
```

Wood:

```text
wood_season_factor =
    1.00 spring
    0.85 summer rain
    0.95 autumn
    1.10 winter dry
```

Salt:

```text
salt_season_factor =
    1.10 dry months
    0.60 heavy rain months
```

## Visual requirements

Weather must be visible:

- rain streaks at zoom close;
- map tint/texture change for wet ground, but no decorative gradients;
- muddy roads drawn darker/rougher;
- flooded riverbanks visible;
- storm warning flags/markers;
- depot damage shown physically;
- burned/scorched areas remain on terrain.

## Acceptance criteria

- Rain slows routes and increases mud.
- Severe storms halt marches.
- Hot humid weather affects heat fatigue profiles differently depending on acclimatization.
- Weather affects depot spoilage.
- Weather affects report accuracy.
- Road condition degrades under rain/heavy use and improves with repair.
- UI shows next 1-3 day forecast with uncertainty.
