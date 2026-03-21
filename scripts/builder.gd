extends Node3D

var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector: Node3D           # The 'cursor'
@export var selector_container: Node3D # Node that holds a preview of the structure
@export var view_camera: Camera3D      # Used for raycasting mouse
@export var gridmap: GridMap            # Layer 1 — player-placed base tiles
@export var decoration_gridmap: GridMap # Layer 2 — lights, signs, construction
@export var terrain_gridmap: GridMap    # Layer 0 — auto-generated terrain
@export var cash_display: Label
@export var date_display: Label
@export var payday_label: Label
@export var week_clock: TextureRect
@export var report_panel: Control
@export var building_picker: BuildingPicker

# Week progress clock textures (timer_0 → timer_100)
const _CLOCK_TEXTURES: Array = [
	preload("res://graphics/timer_0.png"),
	preload("res://graphics/timer_CCW_25.png"),
	preload("res://graphics/timer_CCW_50.png"),
	preload("res://graphics/timer_CCW_75.png"),
	preload("res://graphics/timer_100.png"),
]

var plane: Plane # Used for raycasting mouse
var last_gridmap_position: Vector3 = Vector3.ZERO
var _placing: bool = false  # true when a structure is selected and ready to place

# Per-structure mesh library IDs and layer assignments (built in _ready)
var _struct_mesh_id: Array[int] = []
var _struct_layer:   Array[int] = []

# Reverse-lookup: mesh library id -> structure index (for refund on demolish)
var _base_id_to_struct: Dictionary = {}
var _deco_id_to_struct: Dictionary = {}

# Economy / time
var _cell_placed_week: Dictionary = {}   # Vector3i -> int (week placed)
var _day_timer: float = 0.0
var _payday_label_timer: float = 0.0
const DAY_DURATION: float = 30.0         # real seconds per in-game day
const PAYDAY_INTERVAL_DAYS: int = 14     # payday every 2 in-game weeks

# Terrain
var _terrain_noise: FastNoiseLite = null
var _terrain_mesh_ids: Dictionary = {}     # glb basename  -> mesh library id
var _terrain_rewards: Dictionary  = {}     # mesh library id -> cash reward

const PICKER_WIDTH:int = 320 # Must match building_picker.gd offset_left

func _ready():

	_load_structures()

	plane = Plane(Vector3.UP, Vector3.ZERO)

	# Build separate MeshLibraries for base, decoration, and terrain layers
	_build_mesh_libraries()
	_build_terrain_mesh_library()

	if Global.pending_load:
		_do_load(Global.save_path())
	else:
		map = DataMap.new()
		map.cash = Global.starting_cash
		generate_terrain()

	if building_picker:
		building_picker.populate(structures)
		building_picker.structure_selected.connect(select_structure)
		building_picker.report_requested.connect(_open_report)

	# Start in browse mode — selector hidden until a building is picked
	selector.visible = false

	update_structure()
	update_cash()
	_update_date_display()

func _process(delta):

	# Time / economy tick
	_advance_time(delta)
	if _payday_label_timer > 0.0:
		_payday_label_timer -= delta
		if _payday_label_timer <= 0.0 and payday_label:
			payday_label.visible = false

	# Keyboard / non-mouse controls always fire
	action_cycle_structure()
	action_rotate()
	action_save()
	action_load()
	action_load_resources()

	# Skip all mouse-position work when cursor is over the picker sidebar
	if not _is_over_picker():
		var world_position = plane.intersects_ray(
			view_camera.project_ray_origin(get_viewport().get_mouse_position()),
			view_camera.project_ray_normal(get_viewport().get_mouse_position()))
		if world_position:
			last_gridmap_position = Vector3(round(world_position.x), 0, round(world_position.z))

	selector.position = lerp(selector.position, last_gridmap_position, min(delta * 40, 1.0))

	action_build(last_gridmap_position)
	action_demolish(last_gridmap_position)

# Build two MeshLibraries — one per layer — and record per-structure IDs
func _build_mesh_libraries() -> void:
	var base_lib := MeshLibrary.new()
	var deco_lib := MeshLibrary.new()
	_struct_mesh_id.clear()
	_struct_layer.clear()
	_base_id_to_struct.clear()
	_deco_id_to_struct.clear()
	for i in structures.size():
		var s := structures[i]
		var mesh = get_mesh(s.model)
		_struct_layer.append(s.layer)
		if mesh == null:
			_struct_mesh_id.append(-1)
			continue
		var lib: MeshLibrary = deco_lib if s.layer == 1 else base_lib
		var id := lib.get_last_unused_item_id()
		lib.create_item(id)
		lib.set_item_mesh(id, mesh)
		lib.set_item_mesh_transform(id, Transform3D())
		_struct_mesh_id.append(id)
		if s.layer == 1:
			_deco_id_to_struct[id] = i
		else:
			_base_id_to_struct[id] = i
	gridmap.mesh_library = base_lib
	if decoration_gridmap:
		decoration_gridmap.mesh_library = deco_lib

# Build terrain MeshLibrary from Nature-category structures
const TERRAIN_REWARDS: Dictionary = {
	"grass":            5,
	"grass-trees":     50,
	"grass-trees-tall": 100,
}

func _build_terrain_mesh_library() -> void:
	if not terrain_gridmap:
		return
	var lib := MeshLibrary.new()
	_terrain_mesh_ids.clear()
	_terrain_rewards.clear()
	var id := 0
	for s in structures:
		if s.category != "Nature":
			continue
		var mesh = get_mesh(s.model)
		if mesh == null:
			continue
		var key: String = s.model.resource_path.get_file().get_basename()
		lib.create_item(id)
		lib.set_item_mesh(id, mesh)
		lib.set_item_mesh_transform(id, Transform3D())
		_terrain_mesh_ids[key] = id
		_terrain_rewards[id] = TERRAIN_REWARDS.get(key, 0)
		id += 1
	terrain_gridmap.mesh_library = lib
	print("[Builder] Terrain mesh IDs: ", _terrain_mesh_ids)
	print("[Builder] Terrain rewards: ", _terrain_rewards)


func generate_terrain() -> void:
	if not terrain_gridmap or _terrain_mesh_ids.is_empty():
		return
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = Global.map_seed
	_terrain_noise.frequency = 0.07
	terrain_gridmap.clear()
	var half := Global.map_size / 2
	for x in range(-half, half):
		for z in range(-half, half):
			var tile := _get_terrain_tile(x, z)
			if tile != -1:
				terrain_gridmap.set_cell_item(Vector3i(x, 0, z), tile)
	print("[Builder] Terrain generated %dx%d seed=%d" % [Global.map_size, Global.map_size, Global.map_seed])


func _get_terrain_tile(x: int, z: int) -> int:
	if _terrain_noise == null or _terrain_mesh_ids.is_empty():
		return -1
	var n := _terrain_noise.get_noise_2d(float(x), float(z))
	if n < 0.1:
		return _terrain_mesh_ids.get("grass", -1)
	elif n < 0.4:
		return _terrain_mesh_ids.get("grass-trees", -1)
	else:
		return _terrain_mesh_ids.get("grass-trees-tall", -1)


# Load structures from the pre-generated static list (works in exported builds)
const _STRUCTURE_LIST = preload("res://scripts/structure_list.gd")

func _load_structures() -> void:
	structures.clear()
	for res in _STRUCTURE_LIST.ALL:
		if res is Structure:
			structures.append(res)
	structures.sort_custom(func(a, b):
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name)
	print("[Builder] Loaded %d structures" % structures.size())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if report_panel and report_panel.visible:
			return  # let tax_report.gd handle it
		if _placing:
			_set_placing(false)
			get_viewport().set_input_as_handled()

func _set_placing(value: bool) -> void:
	_placing = value
	selector.visible = value

# Returns true when the mouse is inside the right-side picker panel, or a modal is open
func _is_over_picker() -> bool:
	if report_panel and report_panel.visible:
		return true
	return get_viewport().get_mouse_position().x >= get_viewport().get_visible_rect().size.x - PICKER_WIDTH

# Retrieve the mesh from a PackedScene, used for dynamically creating a MeshLibrary

func get_mesh(packed_scene):
	var scene_state:SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if(scene_state.get_node_type(i) == "MeshInstance3D"):
			for j in scene_state.get_node_property_count(i):
				var prop_name = scene_state.get_node_property_name(i, j)
				if prop_name == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)

					return prop_value.duplicate()

# Cycle structure with Q / E keys

func action_cycle_structure() -> void:
	var changed := false
	if Input.is_action_just_pressed("structure_next"):
		index = (index + 1) % structures.size()
		changed = true
	elif Input.is_action_just_pressed("structure_previous"):
		index = (index - 1 + structures.size()) % structures.size()
		changed = true
	if changed:
		print("[Builder] cycle_structure -> index: ", index)
		if building_picker:
			building_picker.set_selected_index(index)
		Audio.play("sounds/toggle.ogg", -30)
		update_structure()

# Build (place) a structure

func action_build(gridmap_position):
	if not _placing:
		return
	if _is_over_picker():
		return
	if Input.is_action_just_pressed("build"):
		var mid = _struct_mesh_id[index] if index < _struct_mesh_id.size() else -1
		if mid == -1:
			return
		var is_deco := _struct_layer[index] == 1
		var target_map: GridMap = decoration_gridmap if is_deco else gridmap
		var rotation_idx = target_map.get_orthogonal_index_from_basis(selector.basis)
		var previous_tile = target_map.get_cell_item(gridmap_position)
		target_map.set_cell_item(gridmap_position, mid, rotation_idx)
		# Record placement week for aging upkeep (base layer only)
		if not is_deco:
			_cell_placed_week[Vector3i(gridmap_position)] = Global.current_week
		# Clear terrain tile under base-layer placement; reward player for resources
		if not is_deco and terrain_gridmap:
			var terrain_tile := terrain_gridmap.get_cell_item(gridmap_position)
			if terrain_tile != -1:
				var reward: int = _terrain_rewards.get(terrain_tile, 0)
				if reward > 0:
					map.cash += reward
					update_cash()
				terrain_gridmap.set_cell_item(gridmap_position, -1)
		if previous_tile != mid:
			map.cash -= structures[index].price
			update_cash()
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

# Demolish (remove) a structure — decoration layer first, then base

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		var removed := false
		if decoration_gridmap and decoration_gridmap.get_cell_item(gridmap_position) != -1:
			var mid := decoration_gridmap.get_cell_item(gridmap_position)
			decoration_gridmap.set_cell_item(gridmap_position, -1)
			if mid in _deco_id_to_struct:
				var refund := ceili(structures[_deco_id_to_struct[mid]].price / 2.0)
				map.cash += refund
				update_cash()
			removed = true
		elif gridmap.get_cell_item(gridmap_position) != -1:
			var mid := gridmap.get_cell_item(gridmap_position)
			gridmap.set_cell_item(gridmap_position, -1)
			_cell_placed_week.erase(Vector3i(gridmap_position))
			if mid in _base_id_to_struct:
				var refund := ceili(structures[_base_id_to_struct[mid]].price / 2.0)
				map.cash += refund
				update_cash()
			# Restore terrain tile underneath
			if terrain_gridmap:
				var tile := _get_terrain_tile(gridmap_position.x, gridmap_position.z)
				if tile != -1:
					terrain_gridmap.set_cell_item(gridmap_position, tile)
			removed = true
		if removed:
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)

# Rotates the 'cursor' 90 degrees

func action_rotate():
	if _is_over_picker():
		return
	if Input.is_action_just_pressed("rotate"):
		selector.rotate_y(deg_to_rad(90))

		Audio.play("sounds/rotate.ogg", -30)

# Select a structure by index (called from BuildingPicker signal)

func select_structure(new_index: int) -> void:
	index = new_index
	_set_placing(true)
	Audio.play("sounds/toggle.ogg", -30)
	update_structure()

# Update the structure visual in the 'cursor'

func update_structure():
	if structures.is_empty():
		return
	# Clear previous structure preview in selector
	for n in selector_container.get_children():
		selector_container.remove_child(n)

	# Create new structure preview in selector
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.position.y += 0.25

func update_cash():
	cash_display.text = "$" + str(map.cash)

# ── Time & Economy ────────────────────────────────────────────────────────────

func _advance_time(delta: float) -> void:
	_day_timer += delta
	if _day_timer >= DAY_DURATION:
		_day_timer -= DAY_DURATION
		Global.current_day += 1
		Global.current_week = Global.current_day / 7
		_update_date_display()
		if Global.current_day % PAYDAY_INTERVAL_DAYS == 0:
			_do_payday()

func _update_date_display() -> void:
	var d      := Global.current_day
	var year   := d / 336 + 1
	var month  := (d % 336) / 28 + 1
	var week   := (d % 28)  / 7  + 1
	var day    := d % 7 + 1
	if date_display:
		date_display.text = "Year %d  ·  Month %d  ·  Week %d  ·  Day %d" % [year, month, week, day]
	# Update week-progress clock (5 frames over 7 days)
	if week_clock:
		var frame := int(float(d % 7) / 7.0 * 5.0)
		week_clock.texture = _CLOCK_TEXTURES[clampi(frame, 0, 4)]

func _do_payday() -> void:
	var total_income := 0
	var total_upkeep := 0
	for cell in gridmap.get_used_cells():
		var mid := gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var price: int = structures[_base_id_to_struct[mid]].price
		var income: int = floori(price * 0.05)
		var placed_week: int = _cell_placed_week.get(cell, Global.current_week)
		var age_weeks: int   = Global.current_week - placed_week
		var upkeep_pct: float = minf(0.03, age_weeks * 0.001)
		var upkeep: int = floori(price * upkeep_pct)
		total_income += income
		total_upkeep += upkeep
	var net := total_income - total_upkeep
	map.cash += net
	update_cash()
	if payday_label:
		var sign_str := "+" if net >= 0 else ""
		payday_label.text = "📅 Payday!   +$%d taxes   -$%d upkeep   %s$%d net" % [
			total_income, total_upkeep, sign_str, net]
		payday_label.visible = true
		_payday_label_timer = 8.0

# ── Tax Report ────────────────────────────────────────────────────────────────

func _open_report() -> void:
	if not report_panel:
		return
	var rows: Array = []
	var total_income := 0
	var total_upkeep := 0
	for cell in gridmap.get_used_cells():
		var mid := gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var s := structures[_base_id_to_struct[mid]]
		var income    := floori(s.price * 0.05)
		var placed_w: int = _cell_placed_week.get(cell, Global.current_week)
		var age: int      = Global.current_week - placed_w
		var upk_pct   := minf(0.03, age * 0.001)
		var upkeep    := floori(s.price * upk_pct)
		rows.append({
			"name":       s.display_name,
			"price":      s.price,
			"income":     income,
			"age":        age,
			"upkeep_pct": upk_pct * 100.0,
			"upkeep":     upkeep,
			"net":        income - upkeep,
		})
		total_income += income
		total_upkeep += upkeep
	report_panel.show_report(rows, total_income, total_upkeep)


# Load a saved map from a path, restoring terrain and placed structures
func _do_load(path: String) -> void:
	var loaded = ResourceLoader.load(path)
	if loaded:
		map = loaded
		if map.map_size > 0:
			Global.map_size = map.map_size
		if map.map_seed != 0:
			Global.map_seed = map.map_seed
	else:
		map = DataMap.new()
		map.cash = Global.starting_cash
	Global.pending_load = false
	Global.current_day  = map.current_day
	Global.current_week = Global.current_day / 7
	_cell_placed_week.clear()
	generate_terrain()
	gridmap.clear()
	if decoration_gridmap:
		decoration_gridmap.clear()
	for cell in map.structures:
		var gpos := Vector3i(cell.position.x, 0, cell.position.y)
		var target: GridMap = decoration_gridmap if (cell.layer == 1 and decoration_gridmap) else gridmap
		target.set_cell_item(gpos, cell.structure, cell.orientation)
		if cell.layer == 0:
			_cell_placed_week[gpos] = cell.placed_week
			if terrain_gridmap:
				terrain_gridmap.set_cell_item(gpos, -1)
	_update_date_display()


# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		print("Saving map to slot: ", Global.save_slot)
		map.map_size    = Global.map_size
		map.map_seed    = Global.map_seed
		map.current_day = Global.current_day
		map.structures.clear()
		for cell in gridmap.get_used_cells():
			var ds := DataStructure.new()
			ds.position     = Vector2i(cell.x, cell.z)
			ds.orientation  = gridmap.get_cell_item_orientation(cell)
			ds.structure    = gridmap.get_cell_item(cell)
			ds.layer        = 0
			ds.placed_week  = _cell_placed_week.get(cell, 0)
			map.structures.append(ds)
		if decoration_gridmap:
			for cell in decoration_gridmap.get_used_cells():
				var ds := DataStructure.new()
				ds.position    = Vector2i(cell.x, cell.z)
				ds.orientation = decoration_gridmap.get_cell_item_orientation(cell)
				ds.structure   = decoration_gridmap.get_cell_item(cell)
				ds.layer       = 1
				map.structures.append(ds)
		ResourceSaver.save(map, Global.save_path())

func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map from slot: ", Global.save_slot)
		_do_load(Global.save_path())
		update_cash()

func action_load_resources():
	if Input.is_action_just_pressed("load_resources"):
		print("Loading sample map...")
		_do_load("res://sample map/map.res")
		update_cash()
