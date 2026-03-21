extends Node


func _ready() -> void:
	Global.map_seed = Time.get_ticks_msec() + randi()
	_build_ui()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CITY BUILDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose a map size to begin"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	for info in [
		{"size": 25,  "slot": "town",       "label": "Town",       "desc": "25 × 25\nQuick game",      "cash": 1000},
		{"size": 75,  "slot": "city",        "label": "City",       "desc": "75 × 75\nBalanced game",   "cash": 3000},
		{"size": 150, "slot": "metropolis",  "label": "Metropolis", "desc": "150 × 150\nRoom to expand","cash": 8000},
	]:
		hbox.add_child(_make_card(info))

	vbox.add_child(HSeparator.new())

	var regen := Button.new()
	regen.text = "↺  Randomise Seed"
	regen.custom_minimum_size = Vector2(220, 0)
	regen.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	regen.pressed.connect(_regen_seed)
	vbox.add_child(regen)


func _make_card(info: Dictionary) -> PanelContainer:
	var slot: String  = info["slot"]
	var size: int     = info["size"]
	var cash: int     = info["cash"]
	var has_save: bool = FileAccess.file_exists("user://" + slot + ".res")

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(190, 0)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = info["label"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var detail := Label.new()
	detail.text = info["desc"] + "\nStart: $%s" % _fmt(cash)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(detail)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var start_btn := Button.new()
	start_btn.text = "New Game"
	start_btn.pressed.connect(_start.bind(size, slot, cash))
	vbox.add_child(start_btn)

	if has_save:
		var load_btn := Button.new()
		load_btn.text = "Continue ▶"
		load_btn.pressed.connect(_load_save.bind(size, slot, cash))
		vbox.add_child(load_btn)

	return card


func _fmt(n: int) -> String:
	# Simple comma formatter e.g. 1000 -> "1,000"
	var s := str(n)
	var result := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result


func _regen_seed() -> void:
	Global.map_seed = Time.get_ticks_msec() + randi()


func _start(size: int, slot: String, cash: int) -> void:
	Global.map_size     = size
	Global.map_seed     = Time.get_ticks_msec() + randi()
	Global.starting_cash = cash
	Global.save_slot    = slot
	Global.pending_load = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _load_save(size: int, slot: String, cash: int) -> void:
	Global.map_size     = size   # will be overridden from save
	Global.starting_cash = cash
	Global.save_slot    = slot
	Global.pending_load = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")
