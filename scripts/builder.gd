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
@export var underlay_gridmap: GridMap   # Permanent grass underlay — never cleared
@export var cash_display: Label
@export var date_display: Label
@export var week_clock: TextureRect
@export var report_panel: Control
@export var building_picker: BuildingPicker
@export var help_panel: Control
@export var population_display: Label

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
var _struct_variation_ids: Array = []  # Array of Array[int]: base + variation IDs per structure
var _struct_layer:   Array[int] = []

# Pre-picked variation for the next placement (shown in preview)
var _pending_mid: int = -1
var _pending_variation_tex: Texture2D = null
var _pending_variation_idx: int = 0  # current index into _struct_variation_ids[index]

# Categories that keep a single fixed color (no random variation)
const _NO_VARIATION_CATEGORIES: Array = ["Roads", "Fences", "Nature"]

# Reverse-lookup: mesh library id -> structure index (for refund on demolish)
var _base_id_to_struct: Dictionary = {}
var _deco_id_to_struct: Dictionary = {}

# Economy / time
var _cell_placed_week: Dictionary = {}   # Vector3i -> int (week placed)
var _cell_job_slots: Dictionary  = {}   # Vector3i -> int (workers, locked at placement)
var _cell_patience: Dictionary   = {}   # Vector3i -> int (0–10, residential only)
var _multi_cell_anchor: Dictionary = {} # Vector3i -> Vector3i (child cell -> anchor cell for multi-tile structures)
var _payday_count: int = 0              # total paydays elapsed (tracks grace period)
var _day_timer: float = 0.0
const DAY_DURATION: float = 30.0         # real seconds per in-game day
const PAYDAY_INTERVAL_DAYS: int = 14     # payday every 2 in-game weeks
const GRACE_PERIOD_PAYDAYS: int = 4      # first N paydays immune from patience loss

# Wage constants (abstract units multiplied by tax_rate each payday)
const RESIDENT_WAGE:    int = 20   # per adult in a residential building
const COMMERCIAL_WAGE:  int = 40   # per job slot in a commercial building
const INDUSTRIAL_WAGE:  int = 25   # per job slot in an industrial building

# Cached city stats — updated every payday and when the report is opened
var _last_income:  int = 0
var _last_upkeep:  int = 0
var _payday_history: Array = []   # newest first, max 10 entries
const MAX_PAYDAY_HISTORY: int = 10

# Terrain
var _terrain_noise: FastNoiseLite = null
var _terrain_mesh_ids: Dictionary = {}     # glb basename  -> mesh library id
var _terrain_rewards: Dictionary  = {}     # mesh library id -> cash reward

const PICKER_WIDTH:int = 320 # Must match building_picker.gd offset_left
const _SAVE_ICON = preload("res://graphics/icon_save.png")
const _WARN_ICON = preload("res://graphics/information.png")

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
		_payday_count = 0   # fresh game always starts in the grace period
		generate_terrain()

	# Permanent grass underlay — fills road-edge gaps so the grey background
	# never shows through. Sits at y = -0.05 (just below terrain tiles) and
	# is never modified by build / demolish / load.
	_spawn_ground_underlay()

	# Keep background music looping: reconnect finished → play each time the
	# clip ends so it restarts automatically.
	var asp := get_parent().get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer
	if asp and not asp.finished.is_connected(asp.play):
		asp.finished.connect(asp.play)

	if building_picker:
		building_picker.populate(structures)
		building_picker.structure_selected.connect(select_structure)
		building_picker.report_requested.connect(_open_report)
		building_picker.help_requested.connect(_open_help)
		building_picker.save_requested.connect(_do_save)

	if report_panel:
		report_panel.tax_rate_changed.connect(func(rate: float) -> void:
			map.tax_rate = rate)

	# Start in browse mode — selector hidden until a building is picked
	selector.visible = false

	update_structure()
	update_cash()
	_update_date_display()
	_update_population_display((_compute_city_stats().get("population", 0)) as int)

func _process(delta):

	# Time / economy tick
	_advance_time(delta)

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
	_struct_variation_ids.clear()
	_struct_layer.clear()
	_base_id_to_struct.clear()
	_deco_id_to_struct.clear()
	for i in structures.size():
		var s := structures[i]
		var mesh = get_mesh(s.model)
		_struct_layer.append(s.layer)
		if mesh == null:
			_struct_mesh_id.append(-1)
			_struct_variation_ids.append([-1])
			continue
		var lib: MeshLibrary = deco_lib if s.layer == 1 else base_lib

		# Register base mesh (embedded colormap)
		var base_id := lib.get_last_unused_item_id()
		lib.create_item(base_id)
		lib.set_item_mesh(base_id, mesh)
		lib.set_item_mesh_transform(base_id, Transform3D())
		_struct_mesh_id.append(base_id)
		if s.layer == 1:
			_deco_id_to_struct[base_id] = i
		else:
			_base_id_to_struct[base_id] = i

		var all_ids: Array = [base_id]

		# Register variation meshes for eligible categories
		if s.category not in _NO_VARIATION_CATEGORIES:
			for tex in _get_variation_textures(s.model.resource_path):
				var var_mesh := _apply_texture_to_mesh(mesh, tex)
				if var_mesh == null:
					continue
				var var_id := lib.get_last_unused_item_id()
				lib.create_item(var_id)
				lib.set_item_mesh(var_id, var_mesh)
				lib.set_item_mesh_transform(var_id, Transform3D())
				if s.layer == 1:
					_deco_id_to_struct[var_id] = i
				else:
					_base_id_to_struct[var_id] = i
				all_ids.append(var_id)

		_struct_variation_ids.append(all_ids)

	gridmap.mesh_library = base_lib
	if decoration_gridmap:
		decoration_gridmap.mesh_library = deco_lib


# Returns variation textures found alongside the model's colormap (variation-a, -b, -c...)
func _get_variation_textures(model_path: String) -> Array:
	var textures: Array = []
	var tex_dir := model_path.get_base_dir().get_base_dir() + "/Textures/"
	for letter in ["a", "b", "c", "d"]:
		var path: String = tex_dir + "variation-" + letter + ".png"
		if ResourceLoader.exists(path):
			textures.append(load(path))
		else:
			break
	return textures


# Duplicates a mesh and overrides all surface materials to use the given texture
func _apply_texture_to_mesh(base_mesh: Mesh, tex: Texture2D) -> Mesh:
	var new_mesh := base_mesh.duplicate() as Mesh
	for surf_idx in new_mesh.get_surface_count():
		var mat := new_mesh.surface_get_material(surf_idx)
		if mat == null:
			continue
		var new_mat := mat.duplicate()
		if new_mat is StandardMaterial3D:
			(new_mat as StandardMaterial3D).albedo_texture = tex
		new_mesh.surface_set_material(surf_idx, new_mat)
	return new_mesh

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


func _spawn_ground_underlay() -> void:
	# Fill the underlay GridMap with plain grass tiles across the entire map.
	# This layer is NEVER cleared by build / demolish / load, so it always
	# shows through any gaps in road-corner geometry or missing terrain tiles.
	if not underlay_gridmap:
		return
	# Share the same mesh library as the terrain — we only need the plain grass tile
	underlay_gridmap.mesh_library = terrain_gridmap.mesh_library
	underlay_gridmap.clear()
	var grass_id: int = _terrain_mesh_ids.get("grass", -1)
	if grass_id == -1:
		push_warning("[Builder] No grass tile found — underlay skipped")
		return
	var half := Global.map_size / 2
	for x in range(-half, half):
		for z in range(-half, half):
			underlay_gridmap.set_cell_item(Vector3i(x, 0, z), grass_id)
	print("[Builder] Ground underlay filled %dx%d with grass" % [Global.map_size, Global.map_size])


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
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if help_panel and help_panel.visible:
			return  # let help_overlay.gd handle it
		if report_panel and report_panel.visible:
			return  # let tax_report.gd handle it
		if _placing:
			_set_placing(false)
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_C and _placing:
		if index < _struct_variation_ids.size():
			var ids: Array = _struct_variation_ids[index]
			if ids.size() > 1:
				_pending_variation_idx = (_pending_variation_idx + 1) % ids.size()
				_apply_variation_idx()
				_update_preview_variation()
		get_viewport().set_input_as_handled()

func _set_placing(value: bool) -> void:
	_placing = value
	selector.visible = value

# Returns true when the mouse is inside the right-side picker panel, or a modal is open
func _is_over_picker() -> bool:
	if help_panel and help_panel.visible:
		return true
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

func _get_footprint_cells(anchor: Vector3i, s: Structure) -> Array:
	# Returns all Vector3i cells occupied by a structure placed at anchor.
	# For a 1×1 structure, returns just [anchor].
	# For larger structures, centers the footprint around the anchor
	# (the mesh origin is at the center of the model, not the corner).
	var cells: Array = []
	var off_x: int = (s.footprint.x - 1) / 2
	var off_z: int = (s.footprint.y - 1) / 2
	for dx in range(s.footprint.x):
		for dz in range(s.footprint.y):
			cells.append(Vector3i(anchor.x - off_x + dx, anchor.y, anchor.z - off_z + dz))
	return cells


func action_build(gridmap_position):
	if not _placing:
		return
	if _is_over_picker():
		return
	if Input.is_action_just_pressed("build"):
		var mid: int = _pending_mid
		if mid == -1:
			return
		var is_deco := _struct_layer[index] == 1
		var target_map: GridMap = decoration_gridmap if is_deco else gridmap
		var rotation_idx = target_map.get_orthogonal_index_from_basis(selector.basis)
		var s: Structure = structures[index]
		var anchor := Vector3i(gridmap_position)
		var fp_cells: Array = _get_footprint_cells(anchor, s)

		# Check ALL footprint cells are clear before placing
		if not is_deco:
			for cell in fp_cells:
				var vcell := Vector3i(cell)
				if gridmap.get_cell_item(vcell) != -1 or _multi_cell_anchor.has(vcell):
					Toast.notify("Not enough room!", _WARN_ICON)
					return

		var previous_tile = target_map.get_cell_item(gridmap_position)
		# Place the mesh at the anchor cell
		target_map.set_cell_item(gridmap_position, mid, rotation_idx)

		# Record placement week for aging upkeep (base layer only)
		if not is_deco:
			_cell_placed_week[anchor] = Global.current_week
			# Lock in randomised job slots for commercial / industrial buildings
			var s_idx: int = _base_id_to_struct.get(mid, -1)
			if s_idx != -1:
				_cell_job_slots[anchor] = \
					_gen_job_slots(s.category, s.price)
				# New residential buildings start with slightly varied patience
				if s.category == "Buildings":
					_cell_patience[anchor] = randi_range(8, 10)
			# Register multi-cell footprint so child cells block future placement
			if s.footprint.x > 1 or s.footprint.y > 1:
				for cell in fp_cells:
					_multi_cell_anchor[Vector3i(cell)] = anchor

		# Clear terrain tiles under ALL footprint cells; reward player for resources
		if not is_deco and terrain_gridmap:
			for cell in fp_cells:
				var vcell := Vector3i(cell)
				var terrain_tile := terrain_gridmap.get_cell_item(vcell)
				if terrain_tile != -1:
					var reward: int = _terrain_rewards.get(terrain_tile, 0)
					if reward > 0:
						map.cash += reward
					terrain_gridmap.set_cell_item(vcell, -1)
			update_cash()

		if previous_tile != mid:
			map.cash -= s.price
			update_cash()
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)
			_update_population_display((_compute_city_stats().get("population", 0)) as int)
		_pick_next_variation()
		_update_preview_variation()

# Demolish (remove) a structure — decoration layer first, then base

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		var removed := false
		var pos := Vector3i(gridmap_position)
		if decoration_gridmap and decoration_gridmap.get_cell_item(pos) != -1:
			var mid := decoration_gridmap.get_cell_item(pos)
			decoration_gridmap.set_cell_item(pos, -1)
			if mid in _deco_id_to_struct:
				var refund := ceili(structures[_deco_id_to_struct[mid]].price / 2.0)
				map.cash += refund
				update_cash()
			removed = true
		elif gridmap.get_cell_item(pos) != -1 or _multi_cell_anchor.has(pos):
			# If user clicked a child cell of a multi-tile structure, find the anchor
			var anchor: Vector3i = _multi_cell_anchor.get(pos, pos) as Vector3i
			var mid := gridmap.get_cell_item(anchor)
			if mid == -1:
				return
			# Determine the footprint so we can clean up all cells
			var s_idx: int = _base_id_to_struct.get(mid, -1)
			var fp := Vector2i(1, 1)
			if s_idx != -1:
				fp = structures[s_idx].footprint
				var refund := ceili(structures[s_idx].price / 2.0)
				map.cash += refund
				update_cash()
			# Remove the mesh from the anchor cell
			gridmap.set_cell_item(anchor, -1)
			_cell_placed_week.erase(anchor)
			_cell_job_slots.erase(anchor)
			_cell_patience.erase(anchor)
			# Clean up all footprint cells — restore terrain and clear multi-cell tracking
			var off_x: int = (fp.x - 1) / 2
			var off_z: int = (fp.y - 1) / 2
			for dx in range(fp.x):
				for dz in range(fp.y):
					var cell := Vector3i(anchor.x - off_x + dx, anchor.y, anchor.z - off_z + dz)
					_multi_cell_anchor.erase(cell)
					if terrain_gridmap:
						var tile := _get_terrain_tile(cell.x, cell.z)
						if tile != -1:
							terrain_gridmap.set_cell_item(cell, tile)
			removed = true
		if removed:
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			_update_population_display((_compute_city_stats().get("population", 0)) as int)

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
	_pick_next_variation()
	_update_preview_variation()


# Pick a random variation for the current structure and store it for next placement
func _pick_next_variation() -> void:
	if index >= _struct_variation_ids.size():
		_pending_mid = -1
		_pending_variation_tex = null
		_pending_variation_idx = 0
		return
	var ids: Array = _struct_variation_ids[index]
	if ids.is_empty():
		_pending_mid = -1
		_pending_variation_tex = null
		_pending_variation_idx = 0
		return
	_pending_variation_idx = randi() % ids.size()
	_apply_variation_idx()


# Apply _pending_variation_idx to set _pending_mid and _pending_variation_tex
func _apply_variation_idx() -> void:
	var ids: Array = _struct_variation_ids[index]
	_pending_mid = ids[_pending_variation_idx]
	# Index 0 = base colormap (no override), 1+ = variation-a, -b, etc.
	if _pending_variation_idx == 0:
		_pending_variation_tex = null
	else:
		var textures: Array = _get_variation_textures(structures[index].model.resource_path)
		var tex_idx: int = _pending_variation_idx - 1
		_pending_variation_tex = textures[tex_idx] if tex_idx < textures.size() else null


# Apply the pending variation texture to the current selector preview mesh
func _update_preview_variation() -> void:
	if selector_container.get_child_count() == 0:
		return
	var model_node := selector_container.get_child(0)
	for child in model_node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if _pending_variation_tex == null:
				for surf_idx in mi.get_surface_override_material_count():
					mi.set_surface_override_material(surf_idx, null)
			else:
				for surf_idx in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(surf_idx)
					if mat == null:
						continue
					var new_mat := mat.duplicate()
					if new_mat is StandardMaterial3D:
						(new_mat as StandardMaterial3D).albedo_texture = _pending_variation_tex
					mi.set_surface_override_material(surf_idx, new_mat)
			break

func update_cash():
	cash_display.text = "$" + str(map.cash)
	var threshold_red:    int = int(Global.starting_cash * 0.10)
	var threshold_yellow: int = int(Global.starting_cash * 0.20)
	if map.cash <= threshold_red:
		cash_display.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	elif map.cash <= threshold_yellow:
		cash_display.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
	else:
		cash_display.remove_theme_color_override("font_color")

func _update_population_display(population: int) -> void:
	if population_display:
		population_display.text = "Pop: %d" % population

# Colour the population label based on average city mood
func _update_mood_display(avg_patience: float) -> void:
	if not population_display:
		return
	if avg_patience < 0.0:            # no residential buildings → no colour
		population_display.remove_theme_color_override("font_color")
	elif avg_patience <= 2.5:
		population_display.add_theme_color_override("font_color", Color(1.0, 0.30, 0.30))
	elif avg_patience <= 5.0:
		population_display.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
	else:
		population_display.remove_theme_color_override("font_color")

# ── Happiness / patience tick ─────────────────────────────────────────────────
# Called once per payday after the grace period ends.
# Reads current tax rate + unemployment, adjusts patience for every house,
# and evicts any that hit 0.
func _tick_patience(stats: Dictionary) -> void:
	var tax_pct: int      = int(map.tax_rate * 100.0)
	var total_adults: int = stats.get("adults", 0) as int
	var unemp_rate: float = 0.0
	if total_adults > 0:
		unemp_rate = float(stats.get("unemployed", 0) as int) / float(total_adults)

	# Patience change this payday from tax rate
	var patience_delta: int
	if tax_pct <= 8:
		patience_delta = 1          # low taxes → slow recovery
	elif tax_pct <= 12:
		patience_delta = -1         # mild pressure
	elif tax_pct <= 16:
		patience_delta = -2         # moderate drain
	else:
		patience_delta = -3 - (1 if randf() < 0.5 else 0)   # heavy drain, some randomness

	# Extra drain when unemployment is high (> 20 % of adults)
	var unemp_drain: int = -1 if unemp_rate > 0.20 else 0
	var total_delta: int = patience_delta + unemp_drain

	var cells_to_evict: Array[Vector3i] = []
	var patience_min: int = 10
	var any_near_leaving: bool = false

	for cell in gridmap.get_used_cells():
		var mid: int = gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var s: Structure = structures[_base_id_to_struct[mid]]
		if s.category != "Buildings":
			continue

		var vcell: Vector3i = Vector3i(cell)
		# Per-building random variation so houses don't all leave on the same tick
		var jitter: int = randi_range(-1, 1)
		var p: int = clampi(_cell_patience.get(vcell, 10) + total_delta + jitter, 0, 10)
		_cell_patience[vcell] = p
		patience_min = mini(patience_min, p)
		if p == 0:
			cells_to_evict.append(vcell)
		elif p <= 2:
			any_near_leaving = true

	# Evict houses at patience 0 — no refund, terrain restored
	var evicted: int = cells_to_evict.size()
	for vcell in cells_to_evict:
		gridmap.set_cell_item(vcell, -1)
		_cell_placed_week.erase(vcell)
		_cell_job_slots.erase(vcell)
		_cell_patience.erase(vcell)
		if terrain_gridmap:
			var tile: int = _get_terrain_tile(vcell.x, vcell.z)
			if tile != -1:
				terrain_gridmap.set_cell_item(vcell, tile)

	# Toasts — only one per payday so we don't spam
	if evicted > 0:
		var msg: String = "A family has packed up and moved out!" if evicted == 1 \
			else "%d families have packed up and moved out!" % evicted
		Toast.notify(msg, _WARN_ICON, 6.0)
	elif any_near_leaving:
		Toast.notify("Warning: some families are seriously considering leaving!", _WARN_ICON, 5.0)
	elif patience_min <= 4 and patience_min > 2:
		Toast.notify("Citizens are grumbling about taxes and unemployment.", _WARN_ICON, 4.0)

# ── Time & Economy ────────────────────────────────────────────────────────────

func _advance_time(delta: float) -> void:
	_day_timer += delta
	Global.day_progress = _day_timer / DAY_DURATION   # 0.0 – 1.0 within the current day
	if _day_timer >= DAY_DURATION:
		_day_timer -= DAY_DURATION
		Global.current_day += 1
		Global.current_week = Global.current_day / 7
		_update_date_display()
		if Global.current_day % PAYDAY_INTERVAL_DAYS == 0:
			_do_payday()
		# Patience ticks weekly (every 7 days) for faster feedback than payday
		if Global.current_day % 7 == 0 and _payday_count > GRACE_PERIOD_PAYDAYS:
			var stats: Dictionary = _compute_city_stats()
			_tick_patience(stats)
			var fresh: Dictionary = _compute_city_stats()
			_update_population_display(fresh.get("population", 0) as int)
			_update_mood_display(fresh.get("avg_patience", 10.0) as float)

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

# ── Population / workforce helpers ────────────────────────────────────────────

# How many residents live in a building of this price (residential only).
func _residents_for(price: int) -> int:
	return max(3, int(round(float(price) / 25.0)))

# Randomise job slots when a commercial/industrial building is first placed.
# The value is locked for the lifetime of the building.
func _gen_job_slots(category: String, price: int) -> int:
	match category:
		"Commercial":
			return randi_range(max(2, price / 100), max(4, price / 60))
		"Industrial":
			return randi_range(max(3, price / 80),  max(6, price / 50))
		_:
			return 0

# Deterministic fallback for saves made before job_slots existed.
func _default_job_slots(category: String, price: int) -> int:
	match category:
		"Commercial": return max(2, price / 80)
		"Industrial":  return max(3, price / 65)
		_:             return 0

# Returns true if any of the four cardinal neighbours is a road tile.
func _is_road_adjacent(cell: Vector3i, road_cells: Dictionary) -> bool:
	return (Vector3i(cell.x + 1, cell.y, cell.z) in road_cells or
			Vector3i(cell.x - 1, cell.y, cell.z) in road_cells or
			Vector3i(cell.x, cell.y, cell.z + 1) in road_cells or
			Vector3i(cell.x, cell.y, cell.z - 1) in road_cells)

# Compute population / workforce / road-connectivity stats.
func _compute_city_stats() -> Dictionary:
	# ── 1. Build a fast road-cell lookup ──────────────────────────────────
	var road_cells: Dictionary = {}
	for cell in gridmap.get_used_cells():
		var mid: int = gridmap.get_cell_item(cell)
		if mid != -1 and mid in _base_id_to_struct:
			if structures[_base_id_to_struct[mid]].category == "Roads":
				road_cells[Vector3i(cell)] = true

	# ── 2. Count residents split by road access ────────────────────────────
	var total_residents:  int = 0
	var commuter_adults:  int = 0   # road-adjacent → can fill any job
	var remote_adults:    int = 0   # no road → commercial only, 70% rate
	var commercial_slots: int = 0
	var industrial_slots: int = 0
	var res_count: int = 0
	var com_count: int = 0
	var ind_count: int = 0
	var patience_sum: int = 0
	var patience_count: int = 0
	var min_patience: int = 10

	for cell in gridmap.get_used_cells():
		var mid: int = gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var s: Structure  = structures[_base_id_to_struct[mid]]
		var road_adj: bool = _is_road_adjacent(Vector3i(cell), road_cells)
		match s.category:
			"Buildings":
				var res: int    = _residents_for(s.price)
				var adults: int = int(floor(res * 0.67))
				total_residents += res
				if road_adj:
					commuter_adults += adults
				else:
					remote_adults += adults
				res_count += 1
				var p: int = _cell_patience.get(Vector3i(cell), 10)
				patience_sum   += p
				patience_count += 1
				min_patience    = mini(min_patience, p)
			"Commercial":
				commercial_slots += _cell_job_slots.get(Vector3i(cell), 0)
				com_count        += 1
			"Industrial":
				industrial_slots += _cell_job_slots.get(Vector3i(cell), 0)
				ind_count        += 1

	# ── 3. Staffing ratios ────────────────────────────────────────────────
	# Industrial: only commuters (you can't telecommute to a factory)
	# Commercial: commuters + remote workers at 70%
	var ind_workforce: int = commuter_adults
	var com_workforce: int = commuter_adults + int(remote_adults * 0.7)

	var commercial_staffing: float = 0.0
	if commercial_slots > 0:
		commercial_staffing = minf(1.0, float(com_workforce) / float(commercial_slots))

	var industrial_staffing: float = 0.0
	if industrial_slots > 0:
		industrial_staffing = minf(1.0, float(ind_workforce) / float(industrial_slots))

	# Weighted average for summary display
	var total_slots: int = commercial_slots + industrial_slots
	var staffing_ratio: float = 0.0
	if total_slots > 0:
		staffing_ratio = (commercial_staffing * commercial_slots +
				industrial_staffing * industrial_slots) / float(total_slots)

	var total_adults: int = commuter_adults + remote_adults
	var total_jobs:   int = commercial_slots + industrial_slots

	return {
		"population":           total_residents,
		"adults":               total_adults,
		"commuter_adults":      commuter_adults,
		"remote_adults":        remote_adults,
		"commercial_slots":     commercial_slots,
		"industrial_slots":     industrial_slots,
		"job_slots":            total_jobs,
		"employed":             mini(total_adults, total_jobs),
		"unemployed":           max(0, total_adults - total_jobs),
		"unfilled_jobs":        max(0, total_jobs - total_adults),
		"commercial_staffing":  commercial_staffing,
		"industrial_staffing":  industrial_staffing,
		"staffing_ratio":       staffing_ratio,
		"res_count":            res_count,
		"com_count":            com_count,
		"ind_count":            ind_count,
		"road_cells":           road_cells,
		"avg_patience":         float(patience_sum) / float(patience_count) if patience_count > 0 else -1.0,
		"min_patience":         min_patience if patience_count > 0 else 10,
		"payday_grace_remaining": max(0, GRACE_PERIOD_PAYDAYS - _payday_count),
	}

func _do_payday() -> void:
	var stats: Dictionary        = _compute_city_stats()
	var com_staffing: float      = stats["commercial_staffing"]
	var ind_staffing: float      = stats["industrial_staffing"]
	var road_cells: Dictionary   = stats["road_cells"]
	var tax_rate: float          = map.tax_rate
	var total_income: int        = 0
	var total_upkeep: int        = 0

	for cell in gridmap.get_used_cells():
		var mid: int = gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var s: Structure   = structures[_base_id_to_struct[mid]]
		var income: int    = 0
		var road_adj: bool = _is_road_adjacent(Vector3i(cell), road_cells)

		match s.category:
			"Buildings":
				var adults: int = int(floor(_residents_for(s.price) * 0.67))
				income = int(floor(adults * RESIDENT_WAGE * tax_rate))
			"Commercial":
				var slots: int = _cell_job_slots.get(Vector3i(cell), 0)
				var road_bonus: float = 1.15 if road_adj else 1.0
				income = int(floor(slots * com_staffing * COMMERCIAL_WAGE * (tax_rate * 1.5) * road_bonus))
			"Industrial":
				var slots: int = _cell_job_slots.get(Vector3i(cell), 0)
				# No road access = hard cap at 60% — trucks can't get in/out
				var eff_staffing: float = minf(ind_staffing, 0.6) if not road_adj else ind_staffing
				income = int(floor(slots * eff_staffing * INDUSTRIAL_WAGE * (tax_rate * 1.2)))
			"Roads", "Nature":
				pass   # zero upkeep, zero income — skip upkeep calc below

		# Upkeep: roads and nature tiles are free to maintain
		var upkeep: int = 0
		if s.category not in ["Roads", "Nature"]:
			var placed_week: int  = _cell_placed_week.get(cell, Global.current_week)
			var age_weeks:   int  = Global.current_week - placed_week
			var upkeep_pct: float = minf(0.03, age_weeks * 0.001)
			upkeep = floori(s.price * upkeep_pct)

		total_income += income
		total_upkeep += upkeep

	var net: int = total_income - total_upkeep
	map.cash    += net
	_last_income = total_income
	_last_upkeep = total_upkeep
	update_cash()

	# Record payday in history (newest first, before evictions so pop is pre-eviction)
	_payday_count += 1
	var ind_pct: int = int(ind_staffing * 100.0)
	var com_pct: int = int(com_staffing * 100.0)
	_payday_history.push_front({
		"week":         Global.current_week,
		"income":       total_income,
		"upkeep":       total_upkeep,
		"net":          net,
		"ind_pct":      ind_pct,
		"com_pct":      com_pct,
		"population":   stats["population"] as int,
	})
	if _payday_history.size() > MAX_PAYDAY_HISTORY:
		_payday_history.pop_back()

	# Toast — show staffing warnings if either sector is below 100%
	var sign_str: String    = "+" if net >= 0 else ""
	var staffing_str: String = ""
	if ind_pct < 100 and stats["industrial_slots"] as int > 0:
		staffing_str += "   ·   Industry %d%%  → build road-side houses" % ind_pct
	if com_pct < 100 and stats["commercial_slots"] as int > 0:
		staffing_str += "   ·   Commercial %d%%  → build more houses" % com_pct
	Toast.notify("Payday!   +$%d taxes   -$%d upkeep   %s$%d net%s" % [
		total_income, total_upkeep, sign_str, net, staffing_str],
		preload("res://graphics/token_in.png"), 5.0)

	_update_population_display(stats.get("population", 0) as int)

# ── Tax Report ────────────────────────────────────────────────────────────────

func _open_report() -> void:
	if not report_panel:
		return

	var stats: Dictionary      = _compute_city_stats()
	var com_staffing: float    = stats["commercial_staffing"]
	var ind_staffing: float    = stats["industrial_staffing"]
	var road_cells: Dictionary = stats["road_cells"]
	var tax_rate: float        = map.tax_rate
	var rows: Array            = []
	var total_income: int      = 0
	var total_upkeep: int      = 0

	for cell in gridmap.get_used_cells():
		var mid: int = gridmap.get_cell_item(cell)
		if mid == -1 or mid not in _base_id_to_struct:
			continue
		var s: Structure   = structures[_base_id_to_struct[mid]]
		var road_adj: bool = _is_road_adjacent(Vector3i(cell), road_cells)

		var income: int = 0
		var people: int = 0

		match s.category:
			"Buildings":
				var adults: int = int(floor(_residents_for(s.price) * 0.67))
				income = int(floor(adults * RESIDENT_WAGE * tax_rate))
				people = _residents_for(s.price)
			"Commercial":
				var slots: int = _cell_job_slots.get(Vector3i(cell), 0)
				var road_bonus: float = 1.15 if road_adj else 1.0
				income = int(floor(slots * com_staffing * COMMERCIAL_WAGE * (tax_rate * 1.5) * road_bonus))
				people = slots
			"Industrial":
				var slots: int = _cell_job_slots.get(Vector3i(cell), 0)
				var eff_staffing: float = minf(ind_staffing, 0.6) if not road_adj else ind_staffing
				income = int(floor(slots * eff_staffing * INDUSTRIAL_WAGE * (tax_rate * 1.2)))
				people = slots
			_:
				continue   # skip roads, nature, decorations

		# Roads have zero upkeep
		var age: int       = 0
		var upk_pct: float = 0.0
		var upkeep: int    = 0
		if s.category not in ["Roads", "Nature"]:
			var placed_w: int = _cell_placed_week.get(cell, Global.current_week)
			age     = Global.current_week - placed_w
			upk_pct = minf(0.03, age * 0.001)
			upkeep  = floori(s.price * upk_pct)

		rows.append({
			"name":       s.display_name,
			"zone":       s.category,
			"road_adj":   road_adj,
			"people":     people,
			"income":     income,
			"age":        age,
			"upkeep_pct": upk_pct * 100.0,
			"upkeep":     upkeep,
			"net":        income - upkeep,
		})
		total_income += income
		total_upkeep += upkeep

	report_panel.show_report(rows, total_income, total_upkeep, stats, map.tax_rate, _payday_history)


func _open_help() -> void:
	if help_panel:
		help_panel.show_overlay()


# Load a saved map from a path, restoring terrain and placed structures
func _do_load(path: String) -> void:
	var loaded
	if OS.has_feature("web"):
		loaded = Global.web_load()
	else:
		loaded = ResourceLoader.load(path)
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
	# Derive payday count from the calendar so loaded saves always reflect the
	# correct grace period — Month 3, Year 1 onward (day 56+) means it's expired.
	_payday_count = Global.current_day / PAYDAY_INTERVAL_DAYS
	Global.day_cycle_enabled = map.day_cycle_enabled
	_cell_placed_week.clear()
	_cell_job_slots.clear()
	_cell_patience.clear()
	_multi_cell_anchor.clear()
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
			# Restore job slots; fall back to deterministic default for old saves
			var slots := cell.job_slots
			if slots == 0 and cell.structure in _base_id_to_struct:
				var s_idx: int = _base_id_to_struct[cell.structure]
				slots = _default_job_slots(structures[s_idx].category, structures[s_idx].price)
			if slots > 0:
				_cell_job_slots[gpos] = slots
			# Restore patience (defaults to 10 for old saves via DataStructure @export default)
			_cell_patience[gpos] = cell.patience
			# Rebuild multi-cell footprint tracking for large structures
			if cell.structure in _base_id_to_struct:
				var s_idx: int = _base_id_to_struct[cell.structure]
				var fp: Vector2i = structures[s_idx].footprint
				if fp.x > 1 or fp.y > 1:
					var off_x: int = (fp.x - 1) / 2
					var off_z: int = (fp.y - 1) / 2
					for dx in range(fp.x):
						for dz in range(fp.y):
							var child := Vector3i(gpos.x - off_x + dx, gpos.y, gpos.z - off_z + dz)
							_multi_cell_anchor[child] = gpos
							if terrain_gridmap:
								terrain_gridmap.set_cell_item(child, -1)
	_update_date_display()


# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		_do_save()


func _do_save() -> void:
	print("Saving map to slot: ", Global.save_slot)
	map.map_size    = Global.map_size
	map.map_seed    = Global.map_seed
	map.current_day = Global.current_day
	map.payday_count      = _payday_count
	map.day_cycle_enabled = Global.day_cycle_enabled
	map.structures.clear()
	for cell in gridmap.get_used_cells():
		var ds := DataStructure.new()
		ds.position     = Vector2i(cell.x, cell.z)
		ds.orientation  = gridmap.get_cell_item_orientation(cell)
		ds.structure    = gridmap.get_cell_item(cell)
		ds.layer        = 0
		ds.placed_week  = _cell_placed_week.get(cell, 0)
		ds.job_slots    = _cell_job_slots.get(cell, 0)
		ds.patience     = _cell_patience.get(cell, 10)
		map.structures.append(ds)
	if decoration_gridmap:
		for cell in decoration_gridmap.get_used_cells():
			var ds := DataStructure.new()
			ds.position    = Vector2i(cell.x, cell.z)
			ds.orientation = decoration_gridmap.get_cell_item_orientation(cell)
			ds.structure   = decoration_gridmap.get_cell_item(cell)
			ds.layer       = 1
			map.structures.append(ds)
	if OS.has_feature("web"):
		var ok: bool = Global.web_save(map)
		if ok:
			Toast.notify("Game saved!", _SAVE_ICON)
		else:
			Toast.notify("Save FAILED — localStorage unavailable!", _SAVE_ICON)
	else:
		ResourceSaver.save(map, Global.save_path())
		Toast.notify("Game saved!", _SAVE_ICON)

func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map from slot: ", Global.save_slot)
		_do_load(Global.save_path())
		update_cash()
		_update_population_display((_compute_city_stats().get("population", 0)) as int)

func action_load_resources():
	if Input.is_action_just_pressed("load_resources"):
		print("Loading sample map...")
		_do_load("res://sample map/map.res")
		update_cash()
