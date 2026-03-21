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

	title_row.add_child(_make_icon(INFO_TEX, 20))

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
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
