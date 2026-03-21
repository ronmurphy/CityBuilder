extends Control
class_name BuildingPicker

signal structure_selected(index: int)

var structures: Array = []
var current_category: String = "All"
var selected_index: int = 0

const HIDDEN_CATEGORIES: Array[String] = ["Nature", "Tiles"]

var _cat_hbox: HBoxContainer
var _structure_grid: VBoxContainer
var _cat_buttons: Dictionary = {}
var _struct_buttons: Dictionary = {}


func _ready() -> void:
	_setup_layout()
	# Guard: Builder._ready() fires before BuildingPicker._ready(), so
	# populate() may have already called _build_ui(). Don't call it twice.
	if not _cat_hbox:
		_build_ui()


func _setup_layout() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -320.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_ui() -> void:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "BUILD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	var cat_scroll := ScrollContainer.new()
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cat_scroll.custom_minimum_size = Vector2(0, 34)
	vbox.add_child(cat_scroll)

	_cat_hbox = HBoxContainer.new()
	_cat_hbox.add_theme_constant_override("separation", 4)
	cat_scroll.add_child(_cat_hbox)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_structure_grid = VBoxContainer.new()
	_structure_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_structure_grid.add_theme_constant_override("separation", 4)
	scroll.add_child(_structure_grid)


func populate(structs: Array) -> void:
	structures = structs
	_setup_layout()
	if not _cat_hbox:
		_build_ui()
	_rebuild_categories()
	_rebuild_structures()


func _rebuild_categories() -> void:
	for child in _cat_hbox.get_children():
		child.queue_free()
	_cat_buttons.clear()

	var cats: Array = ["All"]
	for s in structures:
		if s.category in HIDDEN_CATEGORIES:
			continue
		if s.category not in cats:
			cats.append(s.category)

	for cat in cats:
		var btn := Button.new()
		btn.text = cat
		btn.flat = (cat != current_category)
		btn.pressed.connect(_select_category.bind(cat))
		_cat_hbox.add_child(btn)
		_cat_buttons[cat] = btn


func _select_category(cat: String) -> void:
	current_category = cat
	for c in _cat_buttons:
		_cat_buttons[c].flat = (c != current_category)
	_rebuild_structures()


func _rebuild_structures() -> void:
	for child in _structure_grid.get_children():
		child.queue_free()
	_struct_buttons.clear()

	for i in structures.size():
		var s = structures[i]
		if s.category in HIDDEN_CATEGORIES:
			continue
		if current_category != "All" and s.category != current_category:
			continue

		var btn := Button.new()
		btn.text = s.display_name + "\n$" + str(s.price)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.flat = (i != selected_index)
		if s.thumbnail:
			btn.icon = s.thumbnail
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_constant_override("icon_max_width", 44)
		btn.pressed.connect(_select_structure.bind(i))
		_structure_grid.add_child(btn)
		_struct_buttons[i] = btn


func _select_structure(index: int) -> void:
	selected_index = index
	for i in _struct_buttons:
		_struct_buttons[i].flat = (i != selected_index)
	structure_selected.emit(index)


func set_selected_index(index: int) -> void:
	selected_index = index
	if index in _struct_buttons:
		for i in _struct_buttons:
			_struct_buttons[i].flat = (i != selected_index)
	else:
		_select_category("All")
