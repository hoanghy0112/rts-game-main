@tool
extends Resource
class_name VillageBalanceConfig

@export_group("Food")
@export_range(0.0, 1000.0, 0.001, "or_greater") var rice_kg_per_square_meter_per_year: float = 0.1
@export_range(0.0, 100.0, 0.01, "or_greater") var daily_rice_kg_per_farmer: float = 1.0
@export_range(0, 128, 1, "or_greater") var house_min_villagers: int = 3
@export_range(0, 128, 1, "or_greater") var house_max_villagers: int = 4
@export_range(0.0, 10000.0, 0.1, "or_greater") var default_food_reserve_kg_per_house: float = 30.0
@export_range(1, 9999, 1, "or_greater") var food_days_per_year: int = 360

@export_group("Residential Defaults")
@export_range(0, 512, 1, "or_greater") var residential_house_max_count: int = 32
@export_range(0.25, 4.0, 0.05, "or_greater") var residential_house_density: float = 2.0
@export_range(0.0, 64.0, 0.1, "or_greater") var house_min_spacing: float = 3.0
@export_range(1.0, 4.0, 0.05, "or_greater") var house_size_spacing_multiplier: float = 1.05
@export_range(0.0, 32.0, 0.1, "or_greater") var house_footprint_padding: float = 0.2
@export_range(0.0, 32.0, 0.1, "or_greater") var house_region_margin: float = 0.75
@export_range(0.0, 32.0, 0.1, "or_greater") var house_road_clearance: float = 2.0
@export_range(0.0, 32.0, 0.1, "or_greater") var field_road_clearance: float = 1.0
@export_range(0.0, 16.0, 0.1, "or_greater") var field_region_road_margin: float = 0.6
