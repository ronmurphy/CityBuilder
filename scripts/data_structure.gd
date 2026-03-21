extends Resource
class_name DataStructure

@export var position: Vector2i
@export var orientation: int
@export var structure: int
@export var layer: int = 0        # 0 = base GridMap, 1 = decoration GridMap
@export var placed_week: int = 0  # week number when this structure was placed
