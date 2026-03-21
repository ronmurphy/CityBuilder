extends Control
class_name TaxReport

signal tax_rate_changed(new_rate: float)

const CROSS_TEX     = preload("res://graphics/cross.png")
const INFO_TEX      = preload("res://graphics/information.png")
const TOKEN_IN_TEX  = preload("res://graphics/token_in.png")
const TOKEN_OUT_TEX = preload("res://graphics/token_out.png")

const PANEL_W: float = 760.0
const PANEL_H: float = 560.0

# Economy tab
var _rows_container: VBoxContainer
var _summary_label:  Label

# City Hall tab
var _tax_slider:        HSlider
var _tax_pct_label:     Label
var _pay_history_rows:  VBoxContainer

# Population tab
var _pop_labels: Dictionary = {}   # stat key -> Label (value column)

# Tax help sub-panel
var _tax_help_panel: Control = null


func _ready() -> void:
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

	# ── Title row (always visible) ────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	title_row.add_child(_make_icon(TOKEN_IN_TEX, 20))

	var title := Label.new()
	title.text = "  City Reports"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title_row.add_child(title)

	var close_btn := TextureButton.new()
	close_btn.texture_normal = CROSS_TEX
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.pressed.connect(_on_close)
	title_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Tab container ─────────────────────────────────────────────────────
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	_build_economy_tab(tabs)
	_build_city_hall_tab(tabs)
	_build_population_tab(tabs)


# ── Tab: Economy ──────────────────────────────────────────────────────────────

func _build_economy_tab(tabs: TabContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Economy"
	vbox.add_theme_constant_override("separation", 6)
	tabs.add_child(vbox)

	# Column headers
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_make_col(header, "Building",   0,   true)
	_make_col(header, "Zone",       90)
	_make_col(header, "People",     65)
	_make_col(header, "Income",     70)
	_make_col(header, "Age (wks)",  75)
	_make_col(header, "Upkeep %",   70)
	_make_col(header, "Upkeep $",   70)
	_make_col(header, "Net/cycle",  75)

	vbox.add_child(HSeparator.new())

	# Scrollable rows
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	vbox.add_child(HSeparator.new())

	# Summary + info button row
	var summary_row := HBoxContainer.new()
	vbox.add_child(summary_row)

	summary_row.add_child(_make_icon(TOKEN_OUT_TEX, 20))

	var info_btn := TextureButton.new()
	info_btn.texture_normal = INFO_TEX
	info_btn.custom_minimum_size = Vector2(20, 20)
	info_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_btn.ignore_texture_size = true
	info_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	info_btn.tooltip_text = "How taxes & upkeep work"
	info_btn.pressed.connect(_show_tax_help)
	summary_row.add_child(info_btn)

	_summary_label = Label.new()
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary_label.add_theme_font_size_override("font_size", 16)
	summary_row.add_child(_summary_label)


# ── Tab: City Hall ────────────────────────────────────────────────────────────

func _build_city_hall_tab(tabs: TabContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "City Hall"
	vbox.add_theme_constant_override("separation", 10)
	tabs.add_child(vbox)

	# Spacer
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sp)

	# Tax Rate heading
	var heading := Label.new()
	heading.text = "Tax Rate"
	heading.add_theme_font_size_override("font_size", 17)
	vbox.add_child(heading)

	# Slider row
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 10)
	vbox.add_child(slider_row)

	_tax_slider = HSlider.new()
	_tax_slider.min_value = 0
	_tax_slider.max_value = 20
	_tax_slider.step = 1
	_tax_slider.value = 8
	_tax_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tax_slider.value_changed.connect(_on_tax_slider_changed)
	slider_row.add_child(_tax_slider)

	_tax_pct_label = Label.new()
	_tax_pct_label.text = "8%"
	_tax_pct_label.custom_minimum_size = Vector2(40, 0)
	_tax_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tax_pct_label.add_theme_font_size_override("font_size", 16)
	slider_row.add_child(_tax_pct_label)

	# Rate breakdown
	var note := Label.new()
	note.text = "Residential ×1.0  ·  Commercial ×1.5  ·  Industrial ×1.2"
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(note)

	vbox.add_child(HSeparator.new())

	# Payday history
	var pay_heading := Label.new()
	pay_heading.text = "Payday History  (last 10)"
	pay_heading.add_theme_font_size_override("font_size", 17)
	vbox.add_child(pay_heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_pay_history_rows = VBoxContainer.new()
	_pay_history_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pay_history_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_pay_history_rows)


func _on_tax_slider_changed(value: float) -> void:
	_tax_pct_label.text = "%d%%" % int(value)
	tax_rate_changed.emit(value / 100.0)


# ── Tab: Population ───────────────────────────────────────────────────────────

func _build_population_tab(tabs: TabContainer) -> void:
	# Wrap everything in a scroll container so tall content isn't clipped
	var scroll := ScrollContainer.new()
	scroll.name = "Population"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(sp)

	# Residents section
	_section_label(vbox, "Residents")
	_pop_labels["population"]      = _stat_row(vbox, "Total residents")
	_pop_labels["adults"]          = _stat_row(vbox, "Working-age adults")
	_pop_labels["commuter_adults"] = _stat_row(vbox, "  Commuters  (road-side housing)")
	_pop_labels["remote_adults"]   = _stat_row(vbox, "  Remote workers  (no road nearby)")

	vbox.add_child(HSeparator.new())

	# Industrial section
	_section_label(vbox, "Industrial  (commuters only — trucks need roads)")
	_pop_labels["industrial_slots"]    = _stat_row(vbox, "Job slots")
	_pop_labels["industrial_staffing"] = _stat_row(vbox, "Staffing rate")

	vbox.add_child(HSeparator.new())

	# Commercial section
	_section_label(vbox, "Commercial  (commuters + remote workers at 70%)")
	_pop_labels["commercial_slots"]    = _stat_row(vbox, "Job slots")
	_pop_labels["commercial_staffing"] = _stat_row(vbox, "Staffing rate")

	vbox.add_child(HSeparator.new())

	# Overall
	_section_label(vbox, "Overall")
	_pop_labels["employed"]      = _stat_row(vbox, "Employed adults")
	_pop_labels["unemployed"]    = _stat_row(vbox, "Unemployed adults")
	_pop_labels["unfilled_jobs"] = _stat_row(vbox, "Unfilled job slots")

	vbox.add_child(HSeparator.new())

	# Buildings section
	_section_label(vbox, "City Breakdown")
	_pop_labels["res_count"] = _stat_row(vbox, "Residential buildings")
	_pop_labels["com_count"] = _stat_row(vbox, "Commercial buildings")
	_pop_labels["ind_count"] = _stat_row(vbox, "Industrial buildings")

	vbox.add_child(HSeparator.new())

	# City Mood section
	_section_label(vbox, "City Mood")
	_pop_labels["avg_patience"]   = _stat_row(vbox, "Happiness  (0 – 10)")
	_pop_labels["mood_desc"]      = _stat_row(vbox, "Mood")
	_pop_labels["grace_period"]   = _stat_row(vbox, "Grace period")

	# Hint
	vbox.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Roads cost nothing to maintain. Build roads beside factories.\n\nHappiness: taxes ≤8% slowly recover patience (+1/payday). High taxes and unemployment drain it. At 0 patience, families leave — no refund. First 4 paydays are a grace period."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(hint)


func _section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	parent.add_child(lbl)


func _stat_row(parent: VBoxContainer, label_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "—"
	val_lbl.custom_minimum_size = Vector2(80, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return val_lbl


# ── Public API ────────────────────────────────────────────────────────────────

func show_report(rows: Array, total_income: int, total_upkeep: int,
		pop_data: Dictionary, tax_rate: float, payday_history: Array) -> void:

	# --- Economy tab ---
	for c in _rows_container.get_children():
		c.queue_free()

	for row: Dictionary in rows:
		var hbox := HBoxContainer.new()
		_rows_container.add_child(hbox)
		_make_col(hbox, row["name"],              0,   true)
		_make_col(hbox, row["zone"],              90)
		_make_col(hbox, "%d"     % row["people"], 65)
		_make_col(hbox, "+$%d"   % row["income"], 70)
		_make_col(hbox, "%d"     % row["age"],    75)
		_make_col(hbox, "%.1f%%" % row["upkeep_pct"], 70)
		_make_col(hbox, "-$%d"   % row["upkeep"], 70)
		var net_lbl := _make_col(hbox,
			"%s$%d" % ["+" if row["net"] >= 0 else "", row["net"]], 75)
		if row["net"] < 0:
			net_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	var net := total_income - total_upkeep
	_summary_label.text = "Income +$%d  ·  Upkeep -$%d  ·  Net %s$%d  per cycle" % [
		total_income, total_upkeep, "+" if net >= 0 else "", net]

	# --- City Hall tab ---
	_tax_slider.set_value_no_signal(int(tax_rate * 100.0))
	_tax_pct_label.text = "%d%%" % int(tax_rate * 100.0)

	# Payday history list
	for c in _pay_history_rows.get_children():
		c.queue_free()

	if payday_history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No paydays yet — check back after the first cycle."
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_pay_history_rows.add_child(empty_lbl)
	else:
		for entry: Dictionary in payday_history:
			var row_net: int  = entry["net"]
			var ind_pct: int  = entry.get("ind_pct", 100)
			var com_pct: int  = entry.get("com_pct", 100)
			var sign: String  = "+" if row_net >= 0 else ""
			var stf_tag: String = ""
			if ind_pct < 100:
				stf_tag += "  Ind %d%%" % ind_pct
			if com_pct < 100:
				stf_tag += "  Com %d%%" % com_pct

			var lbl := Label.new()
			lbl.text = "Wk %-3d  +$%d  -$%d  %s$%d net  ·  Pop %d%s" % [
				entry["week"], entry["income"], entry["upkeep"],
				sign, row_net, entry["population"], stf_tag]
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if row_net < 0:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			elif ind_pct < 100 or com_pct < 100:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			else:
				lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			_pay_history_rows.add_child(lbl)
			_pay_history_rows.add_child(HSeparator.new())

	# --- Population tab ---
	var unemployed: int = pop_data.get("unemployed",    0)
	var unfilled:   int = pop_data.get("unfilled_jobs", 0)
	var ind_stf:    int = int((pop_data.get("industrial_staffing",  0.0) as float) * 100.0)
	var com_stf:    int = int((pop_data.get("commercial_staffing",  0.0) as float) * 100.0)
	var commuters:  int = pop_data.get("commuter_adults", 0)
	var remotes:    int = pop_data.get("remote_adults",   0)

	_pop_labels["population"].text      = "%d" % pop_data.get("population", 0)
	_pop_labels["adults"].text          = "%d" % pop_data.get("adults", 0)
	_pop_labels["res_count"].text       = "%d" % pop_data.get("res_count", 0)
	_pop_labels["com_count"].text       = "%d" % pop_data.get("com_count", 0)
	_pop_labels["ind_count"].text       = "%d" % pop_data.get("ind_count", 0)
	_pop_labels["industrial_slots"].text = "%d" % pop_data.get("industrial_slots", 0)
	_pop_labels["commercial_slots"].text = "%d" % pop_data.get("commercial_slots", 0)
	_pop_labels["employed"].text        = "%d" % pop_data.get("employed", 0)

	# Commuters vs remote workers
	var com_lbl: Label = _pop_labels["commuter_adults"]
	com_lbl.text = "%d" % commuters
	com_lbl.add_theme_color_override("font_color",
		Color(0.6, 1.0, 0.6) if commuters > 0 else Color(0.6, 0.6, 0.6))

	var rem_lbl: Label = _pop_labels["remote_adults"]
	rem_lbl.text = "%d" % remotes
	rem_lbl.add_theme_color_override("font_color",
		Color(0.8, 0.8, 0.8) if remotes > 0 else Color(0.5, 0.5, 0.5))

	# Industrial staffing
	var ind_lbl: Label = _pop_labels["industrial_staffing"]
	ind_lbl.text = "%d%%" % ind_stf
	ind_lbl.add_theme_color_override("font_color",
		Color(0.6, 1.0, 0.6) if ind_stf >= 100 else
		Color(1.0, 0.85, 0.4) if ind_stf >= 60 else Color(1.0, 0.5, 0.5))

	# Commercial staffing
	var com_s_lbl: Label = _pop_labels["commercial_staffing"]
	com_s_lbl.text = "%d%%" % com_stf
	com_s_lbl.add_theme_color_override("font_color",
		Color(0.6, 1.0, 0.6) if com_stf >= 100 else Color(1.0, 0.85, 0.4))

	# Unemployed / unfilled hints
	var unemp_lbl: Label = _pop_labels["unemployed"]
	unemp_lbl.text = "%d%s" % [unemployed,
		"  → build more businesses" if unemployed > 0 else ""]
	unemp_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.7, 0.3) if unemployed > 0 else Color(0.6, 1.0, 0.6))

	var unfill_lbl: Label = _pop_labels["unfilled_jobs"]
	unfill_lbl.text = "%d%s" % [unfilled,
		"  → build road-side houses" if unfilled > 0 else ""]
	unfill_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.7, 0.3) if unfilled > 0 else Color(0.6, 1.0, 0.6))

	# ── City Mood ──────────────────────────────────────────────────────────
	var avg_pat: float = pop_data.get("avg_patience",          -1.0) as float
	var grace:   int   = pop_data.get("payday_grace_remaining",  0)  as int

	if avg_pat < 0.0:
		# No residential buildings yet
		_pop_labels["avg_patience"].text = "—"
		_pop_labels["mood_desc"].text    = "—"
		_pop_labels["avg_patience"].remove_theme_color_override("font_color")
		_pop_labels["mood_desc"].remove_theme_color_override("font_color")
	else:
		var mood_desc: String
		var mood_color: Color
		if avg_pat >= 8.5:
			mood_desc  = "Content"
			mood_color = Color(0.60, 1.00, 0.60)
		elif avg_pat >= 6.5:
			mood_desc  = "Comfortable"
			mood_color = Color(0.70, 0.90, 0.70)
		elif avg_pat >= 4.5:
			mood_desc  = "Neutral"
			mood_color = Color(0.85, 0.85, 0.85)
		elif avg_pat >= 2.5:
			mood_desc  = "Grumbling"
			mood_color = Color(1.00, 0.85, 0.40)
		else:
			mood_desc  = "Angry"
			mood_color = Color(1.00, 0.40, 0.40)

		var ap_lbl: Label = _pop_labels["avg_patience"]
		ap_lbl.text = "%.1f / 10" % avg_pat
		ap_lbl.add_theme_color_override("font_color", mood_color)

		var md_lbl: Label = _pop_labels["mood_desc"]
		md_lbl.text = mood_desc
		md_lbl.add_theme_color_override("font_color", mood_color)

	var gr_lbl: Label = _pop_labels["grace_period"]
	if grace > 0:
		gr_lbl.text = "%d paydays remaining" % grace
		gr_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 1.00))
	else:
		gr_lbl.text = "Expired — happiness is active"
		gr_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))

	visible = true


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_icon(tex: Texture2D, size: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


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


# ── Tax help sub-panel (unchanged) ────────────────────────────────────────────

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
	panel.offset_left   = -280.0
	panel.offset_right  =  280.0
	panel.offset_top    = -260.0
	panel.offset_bottom =  260.0
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
		["Residential Income",
			"Each adult (2/3 of residents) earns a wage taxed at your chosen rate.\nBase: 3 residents per house, scaling with building price."],
		["Commercial Income",
			"Job slots × staffing ratio × commercial wage × (tax rate × 1.5).\nBusinesses pay a higher rate than households."],
		["Industrial Income",
			"Job slots × staffing ratio × industrial wage × (tax rate × 1.2).\nFactory workers earn less but factories tend to be larger."],
		["Staffing Ratio",
			"Adults from residential buildings fill job slots city-wide.\nIf adults < job slots, businesses run at partial capacity.\nBuild more houses to raise the staffing ratio to 100%."],
		["Upkeep",
			"All buildings age and require more maintenance over time.\nUpkeep starts at 0% and rises by 0.1% per week, capped at 3%."],
		["Happiness & Patience",
			"Every house has a patience score (0–10). The first 4 paydays are a grace period.\n\n≤ 8% tax: +1 recovery each payday.\n9–12%: -1 per payday.\n13–16%: -2 per payday.\n17–20%: -3 or -4 per payday.\n\nHigh unemployment (> 20% of adults) adds an extra -1 drain.\n\nAt patience 0 the family moves out — no refund, terrain is restored."],
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
