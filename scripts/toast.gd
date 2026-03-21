extends Node

# Toast notification singleton.
# Call Toast.notify("message") or Toast.notify("message", icon_texture) from anywhere.

const FADE_IN  : float = 0.15
const FADE_OUT : float = 0.4

var _panel     : PanelContainer
var _icon_rect : TextureRect
var _label     : Label
var _tween     : Tween


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 128
	add_child(canvas)

	_panel = PanelContainer.new()
	_panel.anchor_left     = 0.5
	_panel.anchor_right    = 0.5
	_panel.anchor_top      = 0.0
	_panel.anchor_bottom   = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_left     = -200.0
	_panel.offset_right    =  200.0
	_panel.offset_top      = 16.0
	_panel.offset_bottom   = 64.0
	_panel.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a      = 0.0
	_panel.visible         = false
	canvas.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(24, 24)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.visible = false
	hbox.add_child(_icon_rect)

	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	hbox.add_child(_label)


func notify(message: String, icon: Texture2D = null, duration: float = 3.0) -> void:
	_label.text = message

	if icon:
		_icon_rect.texture = icon
		_icon_rect.visible = true
	else:
		_icon_rect.visible = false

	if _tween:
		_tween.kill()

	_panel.modulate.a = 0.0
	_panel.visible    = true

	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(duration)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func(): _panel.visible = false)
