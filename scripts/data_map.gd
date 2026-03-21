extends Resource
class_name DataMap

@export var cash: int = 10000
@export var structures: Array[DataStructure]
@export var map_size: int = 0   # stored so a save is self-contained
@export var map_seed: int = 0
@export var current_day: int = 0
@export var tax_rate: float = 0.08  # 0.0–0.20, player-controlled via City Hall
@export var payday_count: int = 0       # total paydays elapsed (tracks grace period)
@export var day_cycle_enabled: bool = true  # day/night colour cycle on or off
