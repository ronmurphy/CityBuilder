extends Resource
class_name DataMap

@export var cash: int = 10000
@export var structures: Array[DataStructure]
@export var map_size: int = 0   # stored so a save is self-contained
@export var map_seed: int = 0
@export var current_day: int = 0
