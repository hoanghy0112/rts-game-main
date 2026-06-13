# 05 - Logistics, kinh tế, hậu phương

## Vai trò trong gameplay

Logistics là trung tâm của game. Quân mạnh nhưng thiếu gạo, nước, tuyến vận chuyển, kho an toàn hoặc dân tâm sẽ yếu đi nhanh, không giữ được trại, không vây thành lâu, không truy kích hiệu quả.

Người chơi không chỉ "có tài nguyên" mà phải:

- thu đúng tài nguyên từ đúng vùng;
- vận chuyển về kho phù hợp;
- bảo quản vật phẩm có hạn sử dụng;
- chọn kho gần chiến trường nhưng không quá dễ bị tập kích;
- giữ đường vận chuyển bằng quân canh;
- sửa đường/cầu/cảng để giảm cost;
- quản lý thuế và dân tâm để output không sụp.

## Resource model

### Raw resources

| Resource | Nguồn | Vai trò |
|---|---|---|
| rice | ruộng, thuế lương, trade | ration chính |
| wood | rừng, khai thác, trade | cầu, thuyền, kho, công sự, cung/tên |
| iron | mỏ, trade | vũ khí, giáp, công cụ |
| salt | vùng muối, trade | bảo quản thịt/cá, ration tốt |
| meat | săn bắt, chăn nuôi, trade | ration giàu dinh dưỡng nhưng dễ hỏng |
| water | sông, suối, giếng, hồ | sống còn khi đóng quân |
| buffaloes | chăn nuôi, trade, captured herds | excellent field plowing, slow cart pulling, small meat yield |
| cattle | chăn nuôi, trade, captured herds | weak field plowing, excellent cart pulling, large meat yield |
| horses | chăn nuôi, trade, captured herds | excellent cart pulling, cavalry/scouts, small meat yield |
| pigs | chăn nuôi, trade, village herds | massive meat yield, fastest livestock growth |
| stone | mỏ đá, bãi đá sông, trade | nền kho, tường kho, công sự, đạn đá cho pháo |
| saltpeter | hang động, đất giàu nitrate, trade | nguyên liệu thuốc súng |
| sulfur | mỏ, trade | nguyên liệu thuốc súng |
| gold | thuế, trade, subsidy | mua vũ khí, thuê lao động, ngoại giao |

### Crafted supplies

| Supply | Recipe v0 | Dùng cho |
|---|---|---|
| basic rations | rice 1.0 | nuôi quân |
| preserved rations | rice 0.8 + salt 0.1 + meat 0.2 | hành quân dài |
| arrows | wood 0.02 + iron 0.005 | cung, thuyền cung |
| spears | wood 1.0 + iron 0.25 | spearmen |
| swords | iron 1.2 + wood 0.1 | swordsmen |
| armor light | iron 1.5 + leather/meat byproduct 0.5 | giảm casualty |
| armor heavy | iron 3.0 + gold 0.2 | elite units |
| tools | wood 0.4 + iron 0.2 | xây dựng/sửa đường |
| carts | wood 4 + iron 0.2 + tools 0.3 | land transport, pulled by cattle/horses/buffaloes |
| boats | wood 12 + iron 0.5 + tools 1 | small river/naval transport |
| ships | wood 80 + iron 6 + tools 8 + gold 2 | heavy river/coastal transport, navy |
| charcoal | wood 0.5 | thuốc súng, smithing |
| gunpowder | saltpeter 0.6 + sulfur 0.2 + charcoal 0.2 | cannon/firearm charge |
| firearm bullets | iron 0.03 | đạn firearm |
| cannon shot stone | stone 1.5 | đạn pháo rẻ, damage thấp hơn |
| cannon shot iron | iron 2.0 + charcoal 0.1 | đạn pháo mạnh, đắt |
| cannon | iron 18 + wood 6 + tools 2 + gold 8 | naval siege, rare |
| firearm | iron 1.2 + wood 0.5 + tools 0.3 + gold 1.5 | crafted workshop hoặc mua từ trader, limited |

Các recipe là gameplay v0. Với campaign lịch sử nghiêm ngặt, firearm/cannon phải được kiểm chứng theo scenario. Nếu không kiểm chứng, chỉ dùng ở random maps hoặc alternate-history options.

Firearm và cannon không hoạt động chỉ nhờ có vũ khí. Mỗi lần bắn phải tiêu thụ projectile và gunpowder:

```text
firearm_gunpowder_charge = gunpowder 0.025
cannon_gunpowder_charge = gunpowder 2.5
cannon_shot = cannon_shot_stone or cannon_shot_iron

firearm_volley_ammo =
    active_firearms * (1 firearm_bullet + 1 firearm_gunpowder_charge)

cannon_volley_ammo =
    active_cannon * (1 cannon_shot + 1 cannon_gunpowder_charge)
```

Nếu thiếu bullet/shot hoặc gunpowder:

```text
ranged_ECS_multiplier =
    0.15 if no_projectile_or_gunpowder
    0.50 if low_ammo_and_ordered_to_conserve
    1.00 otherwise
```

`gunpowder` phải được giữ khô. Kho ẩm, mưa, lũ hoặc depot chất lượng thấp làm tăng misfire và spoilage của gunpowder.

### Equipment weight and troop speed

Armor, tools, arrows, spears, swords, cannon, firearm và ammunition đều có `weight_kg`. Weight ảnh hưởng trực tiếp đến tốc độ hành quân, fatigue và route throughput.

Equipment data needs:

```text
EquipmentOrSupply {
    id;
    category;
    weight_kg;
    bulk_factor;
    stack_size;
    production_recipe;
    ammo_required;
}
```

Default carried/transport weights v0:

| Item | Weight v0 | Applies to | Notes |
|---|---:|---|---|
| arrows bundle x20 | 1.2 kg | archer carried load | consumed by ranged combat |
| spear | 2.5 kg | spearmen carried load | long weapon, higher bulk |
| sword | 1.4 kg | swordsmen carried load | lower bulk than spear |
| armor light | 8 kg | soldier carried load | moderate speed penalty |
| armor heavy | 18 kg | soldier carried load | large speed/fatigue penalty |
| tools | 3 kg | engineer/worker carried load | also convoy cargo |
| firearm | 4.5 kg | firearm infantry carried load | needs bullet + gunpowder |
| firearm bullets x20 | 0.6 kg | firearm infantry carried load | 0.03 kg each |
| firearm gunpowder charges x20 | 0.5 kg | firearm infantry carried load | must stay dry |
| cannon | 900 kg | convoy/boat load | not individual load; affects transport and setup |
| cannon stone shot | 3 kg | convoy/boat load | cheaper, lower damage |
| cannon iron shot | 6 kg | convoy/boat load | higher damage |
| cannon gunpowder charge | 2.5 kg | convoy/boat load | consumed per cannon shot |

Individual load:

```text
carried_weight_kg =
    base_clothing_pack_kg
  + weapon_weight_kg
  + armor_weight_kg
  + ammo_weight_kg
  + tool_weight_kg
  + ration_weight_kg
  + water_weight_kg

load_ratio = carried_weight_kg / max(carry_capacity_kg, 1)
```

Troop movement speed:

```text
troop_speed =
    base_speed
  * terrain_factor
  * weather_factor
  * formation_factor
  * load_speed_factor

load_speed_factor =
    clamp(1.05 - 0.35 * max(load_ratio - 0.50, 0), 0.55, 1.05)
```

If `load_ratio > 1.0`, fatigue gain increases. If `load_ratio > 1.25`, the unit cannot use `Fast` or forced-march orders until load is reduced or transport is assigned.

Heavy equipment carried by convoy:

```text
convoy_load_ratio =
    cargo_weight_kg / max(transport_capacity_kg, 1)

convoy_speed =
    base_transport_speed
  * road_factor
  * terrain_factor
  * weather_factor
  * clamp(1.10 - 0.45 * convoy_load_ratio, 0.35, 1.00)
```

Transport assets:

| Asset | Capacity v0 | Base speed | Constraint |
|---|---:|---|---|
| hand-carried load | 30 kg/person | soldier/worker speed | high fatigue |
| cart + buffalo | 350 kg | slow | good off-road, poor sprint/retreat |
| cart + cattle | 500 kg | medium | best regular cart hauler |
| cart + horse | 400 kg | fast | best urgent cart hauler, higher upkeep |
| boat | 1,500 kg | river speed | needs navigable water |
| ship | 12,000 kg | river/coastal speed | needs dock/deep water |

Draft animal speed:

```text
draft_speed =
    base_cart_speed[draft_animal]
  * road_factor
  * terrain_factor
  * weather_factor
  * health_factor
  * clamp(1.05 - 0.40 * cart_load_ratio, 0.40, 1.00)
```

Buffaloes can pull carts but slowly. Cattle and horses are preferred for carts; horses are fastest but compete with cavalry/scout needs.

## Region economy

Mỗi region có:

```text
Region {
    population;
    refugees_in;
    refugees_out;
    civilian_capacity;
    labor_available;
    resource_potentials;
    tax_rate;
    requisition_rate;
    happiness;
    local_support;
    infrastructure;
    safety;
    current_owner;
    contested_level;
    combat_zone_pressure;
    evacuation_policy;
}
```

Resource output:

```text
output[resource] =
    potential[resource]
  * labor_available
  * season_factor[resource]
  * infrastructure_factor
  * safety_factor
  * happiness_factor
  * occupation_efficiency
```

Tax allocation:

```text
collected[resource] = output[resource] * tax_rate_resource[resource] * compliance
local_retained = output[resource] - collected[resource]
```

Player có thể đặt tax mix:

- rice tax;
- gold tax;
- labor/corvée;
- wood/stone/iron requisition;
- saltpeter/sulfur requisition if firearms or cannon are enabled;
- salt/meat requisition;
- livestock requisition or slaughter order.

Tradeoff:

- tax cao tăng tài nguyên ngắn hạn;
- tax cao làm giảm happiness/compliance;
- requisition nhiều làm giảm sản xuất tương lai;
- dân tâm cao tăng recruit quality, intel, guard support.

## Civilian displacement and refugees

Khi một region trở thành vùng giao tranh, dân chúng có thể di tản sang khu vực khác. Vùng giao tranh gồm:

- có giao chiến đang diễn ra;
- có nhiều quân đội đối địch cùng chiếm đóng hoặc contest cùng khu vực;
- bị vây, bị raid, bị foraging nặng hoặc đường chính bị cắt;
- vừa chịu battle damage, loot hoặc đốt phá.

Di tản không phải teleport. Dân đi theo route khả dụng, ưu tiên vùng an toàn, cùng phe/đồng minh, có lương thực, còn sức chứa và không bị chặn. Nếu không có route an toàn, dân có thể kẹt lại, tăng mortality, disease và unrest risk.

Source region effects:

- `population`, `labor_available`, tax output và recruit pool giảm;
- ruộng, herd care, workshop và road repair thiếu lao động;
- happiness/local support giảm nếu chính quyền không bảo vệ hoặc không mở đường sơ tán;
- enemy/bandit có thể cướp đoàn dân nếu route không được guard.

Destination region effects:

- `refugees_in`, food/water need và shelter need tăng;
- có thêm lao động sau settlement delay nếu được bảo vệ và nuôi dưỡng;
- overcrowding làm tăng disease, unrest và bandit risk;
- relief rice, fair treatment và safe camp tăng local support;
- bỏ mặc refugees làm happiness và legitimacy giảm.

Refugee state:

```text
RefugeeGroup {
    origin_region;
    destination_region;
    population;
    route;
    days_displaced;
    food_need;
    health;
    security_risk;
    settlement_progress;
}
```

Home-front actions liên quan:

- open evacuation corridor;
- assign guard to refugee route;
- reserve depot for civilians;
- distribute relief rice;
- create temporary shelter camp;
- return civilians after region is safe;
- forced relocation, which reduces short-term risk but harms support if abusive.

## Rice cultivation and livestock farming

Rice and livestock are separate food systems. Rice is high-volume and seasonal. Livestock is slower to build, mobile, vulnerable to raids/disease and can be converted into meat by player order.

Rice field state:

```text
RiceField {
    area_ha;
    stage;              // fallow, prepared, planted, growing, harvest_ready
    water_access;
    irrigation_quality;
    labor_assigned;
    plow_power;
    flood_damage;
    safety;
}
```

Rice output:

```text
rice_output =
    base_rice_yield
  * area_ha
  * season_factor
  * irrigation_factor
  * labor_factor
  * plow_factor
  * safety_factor
  * happiness_factor
```

Plowing:

```text
plow_power =
    buffaloes_assigned * 1.25
  + cattle_assigned * 0.55
  + workers_with_tools * 0.20

plow_factor = clamp(0.70 + 0.30 * plow_power / required_plow_power, 0.70, 1.15)
```

Buffaloes are the best plow animals. Cattle can plow but poorly. Horses and pigs do not contribute to rice plowing in v0.

Livestock herd state:

```text
LivestockHerd {
    species;
    adults;
    young;
    health;
    feed_access;
    water_access;
    shelter_quality;
    assigned_herders;
    pasture_quality;
    owner;              // army, faction, region, civilian
    location;
}
```

Livestock roles:

| Species | Plowing | Cart pulling | Meat yield | Growth | Notes |
|---|---:|---:|---:|---:|---|
| buffaloes | excellent | slow | small | slow | best rice-field animal |
| cattle | weak | excellent | large | medium | best regular cart animal |
| horses | none | excellent/fast | small | slow | also cavalry/scout asset |
| pigs | none | none | massive | rapid | best meat farming animal |

Herd growth:

```text
births =
    breeding_adults
  * reproduction_rate[species]
  * feed_factor
  * water_factor
  * health_factor
  * shelter_factor

deaths =
    herd_size
  * (disease_risk + starvation_risk + raid_loss_risk)

herd_next =
    herd_current
  + births
  - deaths
  - slaughtered
  - requisitioned
  - captured
```

Default v0 livestock traits:

| Species | Reproduction | Feed need | Water need | Slaughter result |
|---|---:|---:|---:|---|
| buffaloes | low | high | high | small meat, loses strong plow power |
| cattle | medium | high | high | large meat, loses cart capacity |
| horses | low | high | high | small meat, loses fast transport/mount |
| pigs | very high | medium | medium | massive meat, fastest food recovery |

Livestock farming requires:

- pasture or feed stockpile;
- water access;
- herders/labor;
- security from raids and theft;
- shelter during storms/floods;
- time for young animals to become adults.

The player may order slaughter for livestock inside the army inventory or inside controlled territory:

```text
slaughter_meat_gain =
    animals_slaughtered
  * meat_yield[species]
  * butcher_efficiency
  * spoilage_immediate_factor
```

Slaughter tradeoffs:

- immediate meat supply increases;
- future herd growth decreases;
- buffalo slaughter reduces field plowing capacity;
- cattle/horse slaughter reduces cart transport capacity;
- horse slaughter can reduce cavalry/scout readiness;
- slaughtering civilian-owned livestock through requisition lowers local support unless compensated;
- preserved rations require salt and depot access before the meat spoils.

## Tax UI requirements

Region panel cần hiển thị:

- output dự kiến theo mùa;
- tax thu được;
- compliance;
- happiness change/day;
- risk of revolt/banditry;
- recruit quality forecast;
- supply route capacity from region;
- rice stage and expected harvest;
- herd count, growth and slaughter impact.

Không chỉ hiển thị con số. Map overlay phải tô/đánh dấu:

- ruộng đang hoạt động;
- grazing/pasture zones;
- livestock herd markers;
- vùng bị cháy;
- đường hỏng;
- kho quá tải;
- route bị đe dọa;
- region bất ổn.

## Storage system

Depot types:

| Depot | Cost v0 | Capacity | Preservation | Defense | Build time |
|---|---|---:|---:|---:|---:|
| field cache | wood 8 + stone 2 | 500 | poor | none | 1 day |
| thatched storehouse | wood 40 + stone 10 + tools 1 | 2,000 | low | low | 4 days |
| raised granary | wood 80 + stone 20 + tools 2 | 4,000 | medium | low | 7 days |
| covered warehouse | wood 110 + stone 40 + iron 8 + tools 3 | 6,000 | good | low | 10 days |
| reinforced depot | wood 150 + stone 100 + iron 20 + tools 5 + gold 4 | 10,000 | high | medium | 16 days |
| fortified depot | wood 220 + stone 220 + iron 45 + tools 8 + gold 10 | 15,000 | high | high | 28 days |

Stone is part of the economy in v0. Depot construction consumes stone for foundation, drainage, raised floors, retaining walls and reinforced storage rooms. Higher-tier depots cost more and take longer because they are durable logistics targets, not disposable containers.

Storage constraints:

- food, water, weapon, armor có category riêng;
- depot có max capacity theo weight/bulk;
- live livestock use pasture/corral capacity, not normal depot storage;
- carts use yard space; boats/ships use mooring or dock capacity;
- stone, wood, iron và tools can be stored as construction material;
- gunpowder requires dry storage; wet depot quality increases spoilage and misfire risk;
- lương thực quá hạn chuyển thành spoiled food;
- spoiled food có thể gây sickness nếu dùng trong khủng hoảng.

Capacity formula:

```text
used_capacity =
    rice_kg * 1.0
  + meat_kg * 1.2
  + water_l * 1.0
  + wood_unit * 2.5
  + stone_unit * 2.0
  + iron_unit * 0.8
  + equipment_weight_kg * equipment_bulk_factor
  + ammo_weight_kg * ammo_bulk_factor
  + gunpowder_kg * 1.4
```

Depot overload:

```text
overload_ratio = max(0, used_capacity / capacity - 1)
spoilage_multiplier += 1.5 * overload_ratio
collapse_hazard += 0.01 * overload_ratio
```

## Supply routes

Player manually maps supply lines.

Route:

```text
SupplyRoute {
    source_depot;
    target_camp_or_depot;
    path_segments;
    assigned_guards;
    assigned_transport;
    priority;
    allowed_resources;
    active;
}
```

Route cost:

```text
route_cost =
    Σ segment_cost

segment_cost =
    length_km
  / effective_speed_km_day
  * risk_multiplier
  * load_multiplier
```

Effective speed:

```text
effective_speed =
    base_transport_speed
  * road_factor
  * terrain_factor
  * weather_factor
  * security_factor
  * transport_load_speed_factor

transport_load_speed_factor =
    clamp(1.10 - 0.45 * convoy_load_ratio, 0.35, 1.00)
```

Load multiplier:

```text
load_multiplier =
    1
  + 0.25 * explosive_or_fragile_handling
```

Risk multiplier:

```text
risk_multiplier =
    1
  + 1.5 * enemy_presence
  + 1.0 * bandit_risk
  + 0.7 * flood_risk
  - 0.8 * guard_coverage
```

Guard coverage:

```text
guard_coverage =
    clamp(guard_ECS_along_route / required_guard_ECS, 0, 1)
```

Route throughput:

```text
daily_throughput =
    transport_capacity
  * trips_per_day
  * route_condition
```

Trips:

```text
trips_per_day = 1 / max(route_travel_days * 2 + loading_days, 0.25)
```

## Automatic resupply

Troops near depot are resupplied automatically if:

```text
distance_to_depot <= effective_resupply_radius
line_access_score >= 0.35
depot_has_allowed_supplies == true
```

Effective radius:

```text
effective_resupply_radius =
    base_radius[depot_type]
  * terrain_reach_factor
  * security_factor
  * weather_factor
```

Default base radius:

| Depot | Radius |
|---|---:|
| field cache | 1 km |
| storehouse/granary | 3 km |
| warehouse | 5 km |
| reinforced/fortified depot | 8 km |

Line access score:

```text
line_access_score =
    0.40 * path_quality
  + 0.30 * security
  + 0.20 * terrain_passability
  + 0.10 * weather_access
```

## Water as stationed resource

Water is vital when stationed. A camp needs local water or regular water transport.

Daily camp water need:

```text
camp_water_need_l =
    soldiers * 3
  + horses * 20
  + buffaloes * 35
  + cattle * 30
  + pigs * 8
  + workers * 3
  + crafting_water_need
```

Local water supply:

```text
local_water_capacity =
    river_access * river_capacity
  + stream_access * stream_capacity
  + wells * well_capacity
  + stored_water
```

If shortage:

```text
water_shortage_ratio = clamp(1 - local_water_capacity / camp_water_need_l, 0, 1)
```

Effects:

- morale falls quickly;
- disease rises;
- horses/draft animals lose readiness;
- livestock growth and meat yield fall;
- construction slows;
- surrender chance rises under siege.

## Home-front actions

Player actions:

- reduce taxes;
- repair roads;
- repair bridges;
- assign soldiers to help agriculture;
- assign engineers to irrigation/canals;
- assign labor to herd/pasture care;
- patrol against bandits;
- distribute rice during crisis;
- open evacuation corridor;
- escort refugee groups;
- build temporary shelter camp;
- slaughter army livestock for emergency meat;
- requisition/slaughter controlled-territory livestock;
- pay local leaders;
- punish unrest harshly.

Effects:

| Action | Short-term cost | Effect |
|---|---|---|
| reduce taxes | lower income | happiness/compliance up |
| road repair | labor + wood/tools | throughput/safety up |
| agriculture aid | soldier readiness down | output/happiness up |
| herd care | labor + water/feed | livestock growth/health up |
| patrol | garrison tied down | bandit risk down |
| relief rice | rice cost | support up, revolt risk down |
| evacuation corridor | guards + route capacity | civilian losses down, source labor temporarily down |
| refugee shelter | wood/rice/water/labor | disease/unrest down, later labor/support up |
| emergency slaughter | livestock cost | immediate meat up, future output/transport down |
| harsh punishment | morale fear up | support down, revolt risk delayed |

## Happiness and revolt

Revolt risk daily:

```text
p_revolt = sigmoid(
    -5.0
  + 3.0 * (1 - happiness)
  + 2.0 * tax_pressure
  + 1.5 * food_insecurity
  + 1.2 * enemy_agitation
  - 2.0 * local_support
  - 1.2 * security_presence
)
```

Bandit risk is related but separate:

```text
bandit_risk_next =
    clamp(
      bandit_risk
    + 0.05 * instability
    + 0.03 * food_shortage_region
    - 0.04 * patrol_coverage
    - 0.02 * local_support,
    0, 1
)
```

## Production zones

Không có base cố định. Production comes from:

- farms/rice fields;
- pasture/corrals/livestock farms;
- forests;
- iron sites;
- stone quarries/river stone sites;
- salt sites;
- saltpeter/sulfur sites if firearms or cannon are enabled;
- markets/trade nodes;
- workshops near labor + resources;
- docks/ports;
- mobile army workshops for limited repair/crafting.

Production requires:

```text
production_output =
    recipe_base_rate
  * labor_factor
  * tool_factor
  * resource_availability
  * infrastructure_factor
  * safety_factor
```

Workshops can be built anywhere suitable, but poor placement creates:

- long route to raw resources;
- higher raid risk;
- spoilage/warehouse overload;
- poor water/labor access.

## Logistics orders

Route orders:

- `Normal`: use shortest safe route.
- `Fast`: higher loss/fatigue, faster.
- `Avoid Enemy`: route longer but safer.
- `Night Movement`: lower detection, lower speed, higher fatigue.
- `Guarded Convoy`: consumes escort soldiers.
- `Emergency Ration`: prioritize food/water over weapons.
- `Stockpile Siege`: move supplies before siege starts.

Depot orders:

- reserve for army;
- reserve for civilians;
- burn before capture;
- evacuate to fallback depot;
- conceal;
- fortify;
- ration strictly.

## Acceptance criteria for v1 logistics

- Player can create depot and route manually.
- Depot construction requires stone and longer build time for durable storage.
- Route has visible path, risk, throughput and ETA.
- Camp consumes rice/water per day.
- Rice cultivation uses field stage, irrigation, labor and plow power.
- Livestock herds grow, consume water/feed and can be raided or diseased.
- Player can slaughter army or controlled-territory livestock for meat.
- Slaughter affects future farming, transport or cavalry readiness depending on species.
- Depot food spoils according to weather/depot quality.
- Gunpowder spoilage/misfire risk changes with depot quality and rain/wetness.
- Firearms/cannon consume bullet/shot and gunpowder when firing.
- Armor, weapons, tools and ammunition weight slows troops or convoys.
- Bandit risk can loot unstable route/depot.
- Guards reduce route risk.
- High taxes increase short-term income but lower happiness/support.
- Region support affects recruit quality and report accuracy.
- Combat zones can displace civilians to safer regions.
- Refugees consume food/water, affect disease/unrest, and can later become local labor if settled safely.
- Road/bridge damage visibly changes route cost.
