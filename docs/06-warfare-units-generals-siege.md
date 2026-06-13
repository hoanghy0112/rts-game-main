# 06 - Chiến tranh, đơn vị, tướng, công thành

## Warfare pillars

Warfare phải xoay quanh vị trí:

- chọn nơi đóng quân;
- chọn hướng chặn đường;
- chọn bờ sông/cao điểm/rừng để phòng thủ;
- xây camp quanh thành để vây;
- cắt route tiếp tế;
- cân nhắc direct assault khi morale/supply/intel thuận lợi;
- quyết định truy kích hay giữ vòng vây.

Người chơi không click thành rồi bấm "Siege". Người chơi đặt camp, assign army, set orders; AI cấp dưới thực thi chi tiết.

## Military hierarchy

```text
Faction
└── Theater Command
    └── Army
        └── Wing/Column
            └── Formation
                └── Squad
                    └── UnitIndividual
```

Generals can command:

- theater;
- army;
- column;
- garrison;
- siege camp;
- convoy guard.

Command capacity:

```text
command_capacity =
    200
  + 15 * intelligence
  + 10 * courage
  + 8 * loyalty
```

Overcapacity penalty:

```text
command_penalty = clamp(1 - 0.30 * max(0, assigned_units / command_capacity - 1), 0.50, 1.0)
```

## Unit stats

Each individual:

```text
UnitIndividual {
    courage: 0..100;
    loyalty: 0..100;
    intelligence: 0..100;
    strength: 0..100;
    health: 0..100;
    fatigue: 0..100;
    unit_type;
    equipment_id;
    formation_id;
}
```

Stats persist when transferred.

General:

```text
General {
    loyalty: 0..100;
    intelligence: 0..100;
    strength: 0..100;
    courage: 0..100;
    reputation;
    recent_victories;
    recent_defeats;
}
```

## Unit types

### Spearmen

Role:

- anti-cavalry;
- good defensive line;
- long attack reach;
- formation-locked for max value.

Weakness:

- slow turning;
- lower flexibility in forest/mud;
- poor if disrupted.

Key modifiers:

```text
formation_locked_bonus = +0.25 defense
anti_cavalry_bonus = +0.55 ECS vs cavalry
disrupted_penalty = -0.35 ECS
```

### Swordsmen

Role:

- flexible infantry;
- good in broken terrain;
- assault and pursuit.

Weakness:

- countered by cavalry in open terrain;
- shorter reach.

Modifiers:

```text
forest_flex_bonus = +0.15
open_vs_cavalry_penalty = -0.25
assault_bonus = +0.10
```

### Archers

Role:

- ranged pressure;
- defensive camp support;
- naval cheap ranged option.

Weakness:

- ammunition dependency;
- lower melee defense.

Modifiers:

```text
high_ground_range_bonus = +0.20
rain_accuracy_penalty = -0.35 * rain_intensity
ammo_empty_ECS_multiplier = 0.25
```

### Firearm infantry

Use only if scenario allows.

Role:

- high shock;
- armor penetration;
- expensive and limited.

Constraints:

- firearm supply from foreign traders or scenario source;
- ammunition production/purchase;
- weather reliability penalty.

Modifiers:

```text
armor_penetration_bonus = +0.30
rain_misfire_chance = 0.10 + 0.35 * rain_intensity
reload_penalty_in_mud = -0.20 * mud
```

### Cavalry

Role:

- fast movement;
- pursuit;
- flanking;
- convoy raiding.

Weakness:

- paddy/mud/forest/slope;
- spearmen.

Modifiers:

```text
open_terrain_charge_bonus = +0.40
paddy_penalty = -0.30
forest_penalty = -0.45
mud_penalty = -0.40 * mud
spearmen_contact_penalty = -0.45
```

### Engineers

Role:

- bridges;
- roads;
- trenches;
- ramparts;
- siege works;
- depot construction;
- canal/irrigation.

Combat:

- weak in direct combat;
- valuable strategic target.

### Navy

Navy is route/control focused.

Loadouts:

- arrows: cheap, medium range;
- cannon: expensive, long production, long range;
- fire weapons: short range, high risk/high damage.

Naval route factors:

```text
boat_speed =
    base_boat_speed
  * navigability
  * flow_factor
  * weather_factor
  * load_factor
```

Storm:

```text
if storm_severity >= 0.85:
    naval_movement = halted_or_seek_shelter
```

## Equipment

Equipment has:

```text
Equipment {
    type;
    attack;
    defense;
    range_m;
    durability;
    maintenance_cost;
    production_recipe;
}
```

Durability decay:

```text
durability_next =
    durability
  - combat_use * combat_decay
  - weather_exposure * weather_decay
  - storage_decay
```

Broken equipment:

```text
equipment_factor = 0.50 + 0.50 * durability
```

## Orders

Army/camp orders:

- hold;
- patrol;
- guard route;
- guard depot;
- raid route;
- construct;
- forage;
- forced march;
- avoid battle;
- seek battle;
- pursue fleeing enemy;
- do not pursue;
- encircle;
- assault;
- withdraw;
- surrender allowed/forbidden policy if command structure permits.

Order compliance:

```text
compliance =
    clamp(
      0.40
    + 0.25 * N(general_loyalty)
    + 0.20 * N(general_intelligence)
    + 0.15 * morale / 100
    - 0.20 * chaos
    - 0.15 * distance_from_command,
    0, 1
)
```

## AI điều khiển lính và tướng lĩnh

Người chơi đặt intent ở cấp chỉ huy. AI cấp dưới triển khai chi tiết cho formation/squad: giữ đội hình, chọn vị trí, tiếp cận, giao chiến, rút lui, truy kích, phá vây hoặc bỏ chạy. AI không được đọc state ẩn hoàn hảo; mọi quyết định dùng `TacticalSituation` đã qua fog of war, report noise và giới hạn command range.

### TacticalSituation

Mỗi tick chiến thuật, AI tạo snapshot đánh giá:

```text
TacticalSituation {
    perceived_enemy_ECS;
    own_ECS;
    terrain_advantage;
    formation_cohesion;
    morale;
    average_loyalty;
    fatigue;
    supply_state;
    encirclement;
    casualty_ratio_recent;
    objective_value;
    retreat_route_safety;
    nearby_friendly_support;
    intel_confidence;
    command_delay;
}
```

Snapshot này là input bất biến cho scoring. System quyết định không mutate world trực tiếp; nó phát `Command` đã validate vào command queue.

### Formation AI states

Formation/squad dùng State Pattern. State tối thiểu:

| State | Hành vi chính | Transition quan trọng |
|---|---|---|
| `idle` | giữ vị trí, nghỉ, resupply, chờ lệnh | có order mới, enemy detected |
| `marching` | đi theo route, giữ cohesion, tránh địa hình xấu | tới điểm, bị phục kích, supply thấp |
| `deploying` | chọn đội hình, chiếm cao điểm/choke, đặt cung thủ/kỵ binh | enemy vào range, vị trí xấu, order đổi |
| `skirmishing` | bắn/quấy rối, giữ khoảng cách, không lao vào melee nếu yếu | ammo thấp, bị áp sát, morale giảm |
| `fighting` | giữ line, xoay hướng, exploit flank, gọi hỗ trợ | morale thấp, casualty cao, phá vỡ đội hình |
| `withdrawing` | rút có tổ chức về route an toàn | route bị chặn, cohesion mất, tới fallback |
| `routing` | bỏ chạy mất tổ chức, dễ bị truy kích | regroup được, bị bao vây, desertion tăng |
| `deserting` | cá nhân/nhóm nhỏ rời quân ngũ | bắt được, thoát khỏi vùng kiểm soát, được ân xá |

State phản ứng với tình huống:

- **giao tranh mạnh:** ưu tiên giữ cohesion, bảo vệ cánh, không truy kích nếu route/security xấu;
- **bị bao vây:** đánh giá phá vòng vây ở cung yếu nhất, co cụm về địa hình phòng thủ hoặc xin rút;
- **supply thấp:** giảm pursuit/assault, tìm depot/forage hoặc rút về route an toàn;
- **morale thấp:** giảm aggression, tăng khả năng withdraw/rout/desert;
- **loyalty thấp:** tăng khả năng không tuân lệnh, tự ý lùi hoặc đào ngũ khi áp lực cao;
- **intel thấp:** chọn hành động bằng perception nhiễu, dễ đánh nhầm mục tiêu yếu/khó hoặc truy kích quá xa.

### Utility AI cho hành động

Mỗi state sinh danh sách `AiActionCandidate`, ví dụ:

- hold formation;
- advance to terrain advantage;
- attack exposed flank;
- guard route/depot;
- retreat to fallback;
- break encirclement;
- refuse combat;
- pursue fleeing enemy;
- call reinforcement;
- surrender request if allowed;
- rout/desert under collapse conditions.

Scoring dùng Utility AI, không dùng chuỗi `if/elif` dài:

```text
action_score =
    0.30 * objective_value
  + 0.25 * tactical_advantage
  + 0.15 * survival_gain
  + 0.10 * supply_gain
  + 0.10 * command_alignment
  + 0.10 * formation_cohesion_gain
  - 0.30 * risk
  - 0.20 * fatigue_cost
```

`AiActionScoringStrategy` có thể thay theo faction/scenario/profile qua config đã validate. Các hệ số là balance data, không hard-code trong state.

### Tướng lĩnh thông minh và quyết định sai

Tướng lĩnh không chọn action tốt nhất một cách tuyệt đối. AI tạo hai phân phối xác suất:

- `p_smart(action)`: ưu tiên action có utility cao theo tình huống đã nhận thức;
- `p_mistake(action)`: ưu tiên action rủi ro, quá tự tin, chậm rút lui hoặc đánh sai mục tiêu.

Xác suất cuối cùng trộn theo intelligence:

```text
smartness = clamp(N(general_intelligence), 0.05, 1.0)

weighted_action_probability =
    smartness * p_smart(action)
  + (1 - smartness) * p_mistake(action)
```

Chuẩn hóa `weighted_action_probability` trên toàn bộ candidate trước khi sampling.

Tướng thông minh thấp vì vậy vẫn có thể nhìn thấy vài lựa chọn tốt, nhưng xác suất chọn sai cao hơn. Tướng thông minh cao vẫn có thể sai nếu intel confidence thấp, command delay lớn hoặc tình huống biến động nhanh.

Quyết định phải deterministic để replay: mọi random sampling dùng `RngStream` seed theo match seed, tick, commander ID và decision sequence.

### Đào ngũ, rout và rút lui

Rút lui có tổ chức, rout và đào ngũ là ba trạng thái khác nhau:

- `withdrawing`: vẫn thuộc quân, còn cohesion và tuân lệnh;
- `routing`: mất tổ chức, chạy khỏi nguy hiểm, có thể regroup;
- `deserting`: rời quân ngũ, mất khỏi formation hoặc chuyển thành fugitive/refugee-like group theo rule scenario.

Đào ngũ có thể xảy ra khi sĩ khí hoặc trung thành thấp, nhất là lúc đang giao tranh, bị bao vây, thiếu lương/nước, thua liên tiếp, casualty cao hoặc đường rút bị chặn. General loyalty/courage, kỷ luật, thắng lợi gần đây, route rút an toàn và quân bạn gần đó giảm rủi ro.

Domain events bắt buộc:

- `ArmyStateChanged`;
- `FormationRouted`;
- `UnitDeserted`;
- `CommandDisobeyed`;
- `AiDecisionMade` for debug/replay with visible inputs and chosen action.

## Combat encounter lifecycle

1. Detection.
2. Intent evaluation.
3. Formation deployment.
4. Terrain advantage calculation.
5. Ranged/skirmish phase.
6. Melee/contact phase.
7. Morale checks.
8. Withdrawal/pursuit/surrender.
9. Aftermath: casualty, loot, route damage, report generation.

## Terrain combat modifiers

| Terrain | Infantry | Cavalry | Archer | Defense | Logistics |
|---|---:|---:|---:|---:|---:|
| road | +speed | +speed | neutral | low | high |
| paddy dry | -small | -medium | neutral | medium | food |
| paddy wet | -medium | -large | -small | medium | slow |
| forest | +ambush | -large | -small | high | wood |
| mountain | -speed | -very large | +high ground | high | poor |
| riverbank | choke | poor charge | line of sight | high | water |
| port/dock | neutral | poor | neutral | medium | high |

Terrain advantage:

```text
terrain_advantage =
    0.35 * elevation_advantage
  + 0.25 * cover
  + 0.20 * choke_control
  + 0.10 * water_barrier
  + 0.10 * prepared_position
```

## Siege system

### Siege setup

A fortress/stronghold has:

```text
Stronghold {
    wall_integrity;
    gate_integrity;
    garrison;
    stored_food;
    stored_water;
    internal_morale;
    supply_entries;
    sortie_paths;
}
```

Player creates siege camps around it.

Siege camp has:

```text
SiegeCamp {
    position;
    assigned_army;
    order;
    arc_covered_degrees;
    blockade_strength;
    pursuit_policy;
    fortification_level;
}
```

### Encirclement coverage

For each camp:

```text
arc_covered =
    2 * atan(camp_control_radius / distance_to_stronghold)
```

Total blocked arc merges overlapping arcs.

```text
encirclement = blocked_arc_degrees / 360
```

### Supply blockade

Each enemy supply entry has route pressure:

```text
route_block_score =
    clamp(
      siege_ECS_near_route / required_blockade_ECS
    * terrain_choke_bonus
    * patrol_order_factor,
    0, 1
)
```

Stronghold supply received:

```text
supply_received =
    normal_supply * (1 - average_route_block_score)
```

### Siege attrition

Daily defender attrition:

```text
defender_health_loss =
    1.0 * food_shortage_ratio
  + 2.0 * water_shortage_ratio
  + 0.5 * disease_risk
  + 0.3 * morale_collapse
```

Attacker attrition:

```text
attacker_health_loss =
    0.4 * camp_supply_shortage
  + 0.5 * weather_exposure
  + 0.4 * sortie_pressure
  + 0.2 * disease_risk
```

### Direct assault decision score

UI should show an estimated score, not guaranteed result.

```text
assault_score =
    attacker_ECS / max(defender_defense_ECS, 1)
  * morale_ratio
  * intel_confidence
  * wall_breach_factor
  * weather_factor
```

Recommendation:

```text
assault_score < 0.75: very risky
0.75..1.10: risky
1.10..1.50: plausible
> 1.50: favorable
```

### Pursuit policy

If enemy flees:

```text
pursuit_trigger =
    enemy_detected
  && pursuit_policy != "do_not_pursue"
  && own_morale >= min_pursuit_morale
  && route_security_after_pursuit >= threshold
```

Risk:

```text
pursuit_overextension =
    pursuit_distance / safe_pursuit_distance
  * enemy_ambush_risk
  * fatigue_factor
```

## Intelligence and fog of war

The map does not show perfect truth unless near friendly unit/report.

Intel sources:

- scouts;
- general reports;
- local support;
- captured prisoners;
- trade rumors;
- watch posts;
- naval patrols.

Intel confidence:

```text
intel_confidence =
    0.35 * scout_quality
  + 0.25 * general_intelligence
  + 0.20 * local_support
  + 0.10 * report_recency
  + 0.10 * source_count
```

Display:

- exact marker if confidence high;
- blurred area if confidence medium;
- rumor marker if confidence low;
- stale marker fades by time.

## AI behavior v1

Enemy AI should not be full grand strategy at first. V1 operational AI uses the tactical AI rules above and should:

- maintain garrisons;
- attack weak route/depot;
- retreat when supply/morale low;
- try to break encirclement;
- reinforce threatened strongholds;
- patrol important roads;
- exploit storms to halt or avoid risky moves.

AI scoring for target:

```text
target_score =
    0.30 * strategic_value
  + 0.25 * weakness
  + 0.20 * supply_gain
  + 0.15 * proximity
  + 0.10 * terrain_advantage
  - 0.30 * risk
```

## Acceptance criteria for v1 warfare

- Player can place siege camps around a stronghold.
- Encirclement score changes with camp position.
- Supply routes into stronghold can be blocked.
- Defender morale/supply declines under blockade.
- General loyalty/courage affects surrender chance.
- Troops can be ordered to pursue or hold.
- Terrain changes combat result.
- Spearmen counter cavalry only when formation is coherent.
- Cavalry is weak in forest/paddy/mud.
- Reports can be wrong if general intelligence is low.
- Formation AI reacts differently when idle, marching, fighting, withdrawing, routing or encircled.
- Low-intelligence generals have a measurable chance to choose bad actions through the smartness/mistake probability mix.
- Low morale or low loyalty can cause rout/desertion, especially during combat or encirclement.
