extends Control
class_name TaxReport

const CROSS_TEX     = preload("res://graphics/cross.png")
const INFO_TEX      = preload("res://graphics/information.png")
const TOKEN_IN_TEX  = preload("res://graphics/token_in.png")
const TOKEN_OUT_TEX = preload("res://graphics/token_out.png")

const PANEL_W: float = 740.0
const PANEL_H: float = 540.0

var _rows_container: VBoxContainer
var _summary_label:  Label
var _tax_help_panel: Control = null


func _ready() -> void:
	# Anchor the Control itself to the bottom-left corner, exactly panel-sized.
	# No full-screen overlay — the panel IS the entire control.
	anchor_left   = 0.0
	anchor_right  = 0.0
	anchor_top    = 1.0
	anchor_bottom = 1.0
	offset_left   = 0.0
	offset_right  = PANEL_W
	offset_top    = -PANEL_H
	offset_bottom = 0.0
	mouse_filter  = MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Panel fills the whole control
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	# ── Title row ─────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	title_row.add_child(_make_icon(TOKEN_IN_TEX, 20))

	var title := Label.new()
	title.text = "  Tax & Upkeep Report"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title_row.add_child(title)

	var info_btn := TextureButton.new()
	info_btn.texture_normal = INFO_TEX
	info_btn.custom_minimum_size = Vector2(20, 20)
	info_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_btn.ignore_texture_size = true
	info_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	info_btn.tooltip_text = "How taxes & upkeep work"
	info_btn.pressed.connect(_show_tax_help)
	title_row.add_child(info_btn)

	var close_btn := TextureButton.new()
	close_btn.texture_normal = CROSS_TEX
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.pressed.connect(_on_close)
	title_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Column headers ─────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	outer.add_child(header)
	_make_col(header, "Building",    0,  true)
	_make_col(header, "Price",       80)
	_make_col(header, "Income",      80)
	_make_col(header, "Age (wks)",   80)
	_make_col(header, "Upkeep %",    80)
	_make_col(header, "Upkeep $",    80)
	_make_col(header, "Net / cycle", 80)

	outer.add_child(HSeparator.new())

	# ── Scrollable building rows ───────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	outer.add_child(HSeparator.new())

	# ── Summary line ──────────────────────────────────────────────────────
	var summary_row := HBoxContainer.new()
	outer.add_child(summary_row)

	summary_row.add_child(_make_icon(TOKEN_OUT_TEX, 20))

	_summary_label = Label.new()
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary_label.add_theme_font_size_override("font_size", 16)
	summary_row.add_child(_summary_label)


# Helper — fixed-size icon that won't grow inside containers
func _make_icon(tex: Texture2D, size: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


# Helper — label cell in a row
func _make_col(parent: HBoxContainer, text: String, min_w: int, expand: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		lbl.custom_minimum_size = Vector2(min_w, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(lbl)
	return lbl


# Called by Builder — populate and show
func show_report(rows: Array, total_income: int, total_upkeep: int) -> void:
	for c in _rows_container.get_children():
		c.queue_free()

	for row: Dictionary in rows:
		var hbox := HBoxContainer.new()
		_rows_container.add_child(hbox)
		_make_col(hbox, row["name"],              0,  true)
		_make_col(hbox, "$%d"    % row["price"],  80)
		_make_col(hbox, "+$%d"   % row["income"], 80)
		_make_col(hbox, "%d"     % row["age"],    80)
		_make_col(hbox, "%.1f%%" % row["upkeep_pct"], 80)
		_make_col(hbox, "-$%d"   % row["upkeep"], 80)
		var net_lbl := _make_col(hbox,
			"%s$%d" % ["+" if row["net"] >= 0 else "", row["net"]], 80)
		if row["net"] < 0:
			net_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	var net := total_income - total_upkeep
	_summary_label.text = "Total  ·  Income +$%d  ·  Upkeep -$%d  ·  Net %s$%d  per cycle" % [
		total_income, total_upkeep, "+" if net >= 0 else "", net]

	visible = true


func _on_close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _tax_help_panel and _tax_help_panel.visible:
			_tax_help_panel.visible = false
			get_viewport().set_input_as_handled()
			return
		if visible:
			_on_close()
			get_viewport().set_input_as_handled()


func _show_tax_help() -> void:
	if _tax_help_panel == null:
		_build_tax_help()
	_tax_help_panel.visible = true


func _build_tax_help() -> void:
	_tax_help_panel = Control.new()
	_tax_help_panel.anchor_left   = 0.0
	_tax_help_panel.anchor_right  = 1.0
	_tax_help_panel.anchor_top    = 0.0
	_tax_help_panel.anchor_bottom = 1.0
	_tax_help_panel.mouse_filter  = MOUSE_FILTER_STOP
	_tax_help_panel.visible = false
	get_parent().add_child(_tax_help_panel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = MOUSE_FILTER_STOP
	_tax_help_panel.add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -260.0
	panel.offset_right  =  260.0
	panel.offset_top    = -230.0
	panel.offset_bottom =  230.0
	_tax_help_panel.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var title_lbl := Label.new()
	title_lbl.text = "How Taxes & Upkeep Work"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 18)
	top_row.add_child(title_lbl)

	var close_btn := TextureButton.new()
	close_btn.texture_normal = CROSS_TEX
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.pressed.connect(func(): _tax_help_panel.visible = false)
	top_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var sections := [
		["Income",
			"Each building earns 5% of its purchase price per payday cycle.\nPayday occurs every 14 in-game days."],
		["Upkeep",
			"Buildings age over time and require more maintenance.\nUpkeep starts at 0% and increases by 0.1% per week of age,\nup to a maximum of 3% of purchase price per cycle."],
		["Net / cycle",
			"Net = Income − Upkeep\nNewer buildings are more profitable.\nBuildings older than 30 weeks reach peak upkeep cost."],
	]

	for pair in sections:
		var heading := Label.new()
		heading.text = pair[0]
		heading.add_theme_font_size_override("font_size", 15)
		vbox.add_child(heading)

		var body := Label.new()
		body.text = pair[1]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(body)

		vbox.add_child(HSeparator.new())
