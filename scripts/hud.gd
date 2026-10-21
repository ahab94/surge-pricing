extends Control
## Everything drawn over the world:
## - the shift clock;
## - the "Yoink" app card (earnings, rating, current rider);
## - review toasts;
## - the results card and the shift-select menu;
## - touch controls: a floating stick on the left, BRAKE and DRIFT on the right.
##
## The app card and toasts are plain Controls with a custom draw callback:
## they redraw only when queue_redraw() is called after the numbers change.

signal retry_pressed
signal next_pressed
signal menu_pressed
signal level_chosen(index: int)

const Riders := preload("res://scripts/riders.gd")

const INK := Color("2a2d36")
const CREAM := Color("fff8e7")
const SUN := Color("ffd23f")
const GOOD := Color("57e36b")
const BAD := Color("ff4d6d")
const PINK := Color("ff4fa3")
const BLUE := Color("37b7ff")
const STICK_R := 80.0
const BUTTON_R := 62.0

var show_touch := false
var stick := Vector2.ZERO        # touch stick, length 0..1

var _money := 0.0
var _goal := 0.0
var _rating := 5.0
var _floor := 4.0
var _clock := 0.0
var _ride: Dictionary = {}
var _rain := false
var _toasts: Array = []          # {name, stars, quote, pay, t}

var _driving_ui: Control
var _card: Control
var _clock_label: Label
var _tip_label: Label
var _toast_box: Control
var _rain_layer: Control
var _result_panel: PanelContainer
var _result_title: Label
var _result_info: Label
var _result_stars: Control
var _result_star_count := 0
var _next_button: Button
var _menu_panel: PanelContainer
var _level_list: GridContainer
var _touch: Node2D
var _brake: TouchScreenButton
var _drift: TouchScreenButton
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _tip_time := 0.0
var _alert: Label
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_tail: Polygon2D
var _alert_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()

	_rain_layer = Control.new()
	_rain_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_layer.draw.connect(_draw_rain)
	add_child(_rain_layer)

	_driving_ui = Control.new()
	_driving_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_driving_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_driving_ui)
	_card = Control.new()
	_card.size = Vector2(350, 220)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.draw.connect(_draw_card)
	_driving_ui.add_child(_card)
	_clock_label = _label(64, CREAM)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.size = Vector2(240, 80)
	_driving_ui.add_child(_clock_label)
	_tip_label = _label(28, CREAM)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_driving_ui.add_child(_tip_label)
	_toast_box = Control.new()
	_toast_box.size = Vector2(380, 400)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.draw.connect(_draw_toasts)
	_driving_ui.add_child(_toast_box)
	var pause := Button.new()
	pause.text = "Menu"
	pause.name = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(func() -> void: menu_pressed.emit())
	_driving_ui.add_child(pause)

	_alert = _label(26, Color("ffffff"), false)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color("ff4fa3")
	pill.set_corner_radius_all(22)
	pill.set_border_width_all(3)
	pill.border_color = INK
	pill.content_margin_left = 22
	pill.content_margin_right = 22
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	_alert.add_theme_stylebox_override("normal", pill)
	_driving_ui.add_child(_alert)
	_alert.visible = false

	_build_bubble()
	_build_touch()
	_build_result_panel()
	_build_menu()
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if _alert_time > 0.0:
		_alert_time -= delta
		_alert.visible = _alert_time > 0.0
		_alert.modulate.a = clampf(_alert_time, 0.0, 1.0) * (0.75 + 0.25 * sin(_alert_time * 12.0))
	if _tip_time > 0.0:
		_tip_time -= delta
		_tip_label.modulate.a = clampf(_tip_time, 0.0, 1.0)
	if not _toasts.is_empty():
		for t in _toasts:
			t.t -= delta
		_toasts = _toasts.filter(func(t) -> bool: return t.t > 0.0)
		_toast_box.queue_redraw()
	if _rain and _driving_ui.visible:
		_rain_layer.queue_redraw()
	if _touch.visible:
		_touch.queue_redraw()


# ---------------------------------------------------------------- driving HUD

func show_level(index: int, level: Dictionary) -> void:
	_menu_panel.visible = false
	_result_panel.visible = false
	_driving_ui.visible = true
	_touch.visible = show_touch
	_rain = level.rain
	_rain_layer.visible = _rain
	_toasts.clear()
	_alert_time = 0.0
	_alert.visible = false
	_tip_label.text = "Shift %d: %s\n%s" % [index + 1, level.name, level.tip]
	_tip_label.modulate.a = 1.0
	_tip_time = 6.0
	stick = Vector2.ZERO
	_stick_index = -1


# ---------------------------------------------------------------- speech bubble

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label = _label(30, INK, false)
	_bubble.add_child(_bubble_label)
	# The tail: a little triangle pointing down at the car.
	_bubble_tail = Polygon2D.new()
	_bubble_tail.polygon = PackedVector2Array([Vector2(-14, -4), Vector2(14, -4), Vector2(0, 22)])
	_bubble_tail.color = Color.WHITE
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2(-14, 0), Vector2(0, 22), Vector2(14, 0)])
	edge.width = 4
	edge.default_color = INK
	_bubble_tail.add_child(edge)
	_bubble.add_child(_bubble_tail)
	_bubble.visible = false
	_driving_ui.add_child(_bubble)


## Shows `text` in a bubble whose tail points at `anchor` (screen px). Empty hides it.
func set_bubble(text: String, anchor: Vector2, alpha: float) -> void:
	if text == "" or alpha <= 0.0:
		_bubble.visible = false
		return
	if _bubble_label.text != text:
		_bubble_label.text = text
		_bubble.reset_size()
	_bubble.visible = true
	_bubble.modulate.a = alpha
	var sz := _bubble.size
	var pos := anchor - Vector2(sz.x * 0.5, sz.y + 34.0)
	pos.x = clampf(pos.x, 8.0, size.x - sz.x - 8.0)
	pos.y = clampf(pos.y, 8.0, size.y - sz.y - 8.0)
	_bubble.position = pos
	_bubble_tail.position = Vector2(clampf(anchor.x - pos.x, 24.0, sz.x - 24.0), sz.y - 2.0)


## A flashing app alert under the clock, for special traffic events.
func alert(text: String) -> void:
	_alert.text = "YOINK ALERT: " + text
	_alert_time = 4.0
	_alert.visible = true
	_layout()


func hide_tip() -> void:
	_tip_time = 0.0
	_tip_label.modulate.a = 0.0


func update_stats(money: float, goal: float, rating: float, floor_rating: float, clock: float,
		ride: Dictionary, _waiting: int) -> void:
	_money = money
	_goal = goal
	_rating = rating
	_floor = floor_rating
	_ride = ride
	_clock = clock
	_clock_label.text = "%d" % ceili(maxf(clock, 0.0))
	_clock_label.label_settings.font_color = BAD if clock < 10.0 else CREAM
	_card.queue_redraw()


func toast(rider: String, stars: int, quote: String, pay: String) -> void:
	_toasts.push_front({"name": rider, "stars": stars, "quote": quote, "pay": pay, "t": 4.5})
	if _toasts.size() > 3:
		_toasts.pop_back()
	_toast_box.queue_redraw()


## The phone-app card: earnings toward the goal, rating with its floor, and
## the current rider with their fare timer and mood.
func _draw_card() -> void:
	var font := get_theme_default_font()
	var c := _card
	var r := Rect2(Vector2.ZERO, c.size)
	var h := 112.0 if _ride.is_empty() else c.size.y
	r.size.y = h
	_round_rect(c, Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.3))
	_round_rect(c, r, Color(INK, 0.92))
	c.draw_string(font, Vector2(16, 30), "YOINK", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PINK)
	c.draw_string(font, Vector2(100, 30), "driver app", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(CREAM, 0.6))
	# Earnings bar.
	c.draw_string(font, Vector2(16, 64), "$%.2f" % _money, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, GOOD)
	c.draw_string(font, Vector2(150, 64), "/ $%d" % int(_goal), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CREAM)
	var bar := Rect2(16, 74, c.size.x - 32, 8)
	c.draw_rect(bar, Color(1, 1, 1, 0.15))
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_money / maxf(_goal, 1.0), 0, 1), 8)), GOOD)
	# Rating: five stars, partly filled, and the floor.
	for i in 5:
		var fill := clampf(_rating - i, 0.0, 1.0)
		_star(c, Vector2(26 + i * 26, 98), 11.0, fill)
	var rc := BAD if _rating < _floor + 0.25 else CREAM
	c.draw_string(font, Vector2(160, 106), "%.2f" % _rating, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, rc)
	c.draw_string(font, Vector2(232, 106), "min %.1f" % _floor, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(CREAM, 0.6))
	if _ride.is_empty():
		return
	var kind: Dictionary = Riders.KINDS[_ride.kind]
	c.draw_line(Vector2(12, 120), Vector2(c.size.x - 12, 120), Color(1, 1, 1, 0.15), 2)
	c.draw_circle(Vector2(30, 146), 14, kind.color)
	_face(c, Vector2(30, 146), _ride.mood)
	c.draw_string(font, Vector2(54, 142), String(_ride.name), HORIZONTAL_ALIGNMENT_LEFT, 200, 20, CREAM)
	c.draw_string(font, Vector2(54, 160), String(_ride.get("label", kind.label)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, kind.color)
	c.draw_string(font, Vector2(230, 150), "tip $%.2f" % _ride.tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOOD)
	var city_name: String = _ride.get("dest_name", "")
	c.draw_string(font, Vector2(16, 188), "to " + city_name, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 32, 20, BLUE)
	var left: float = clampf(_ride.time_left / _ride.limit, 0.0, 1.0)
	var bar2 := Rect2(16, 200, c.size.x - 32, 10)
	c.draw_rect(bar2, Color(1, 1, 1, 0.15))
	c.draw_rect(Rect2(bar2.position, Vector2(bar2.size.x * left, 10)),
			GOOD if left > 0.5 else (SUN if left > 0.2 else BAD))


## A smiley that follows the rider's mood.
func _face(c: CanvasItem, p: Vector2, mood: float) -> void:
	c.draw_circle(p + Vector2(-5, -3), 2.2, INK)
	c.draw_circle(p + Vector2(5, -3), 2.2, INK)
	var curve := (mood - 50.0) / 50.0     # -1 frown .. 1 grin
	var pts := PackedVector2Array()
	for i in 7:
		var x := -6.0 + i * 2.0
		pts.append(p + Vector2(x, 5.0 + curve * (3.0 - x * x / 12.0)))
	c.draw_polyline(pts, INK, 2.0, true)


func _draw_toasts() -> void:
	var font := get_theme_default_font()
	var y := 0.0
	for t in _toasts:
		var a: float = clampf(t.t / 0.5, 0.0, 1.0)
		var r := Rect2(0, y, _toast_box.size.x, 96)
		_round_rect(_toast_box, r, Color(CREAM, 0.95 * a))
		for i in 5:
			_star(_toast_box, Vector2(20 + i * 24, y + 22), 10.0, 1.0 if i < t.stars else 0.0)
		_toast_box.draw_string(font, Vector2(138, y + 29), t.name, HORIZONTAL_ALIGNMENT_LEFT, 150, 18, Color(INK, a))
		_toast_box.draw_string(font, Vector2(r.size.x - 90, y + 29), t.pay, HORIZONTAL_ALIGNMENT_RIGHT, 78, 20,
				Color(Color("2e9e46") if t.pay != "$0" else BAD, a))
		_toast_box.draw_multiline_string(font, Vector2(12, y + 58), "\"%s\"" % t.quote, HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x - 24, 17, 2, Color(INK, a))
		y += 104.0


func _draw_rain() -> void:
	var s := _rain_layer.size
	var t := Time.get_ticks_msec() / 1000.0
	_rain_layer.draw_rect(Rect2(Vector2.ZERO, s), Color(0.15, 0.2, 0.35, 0.18))
	for i in 140:
		var x := fposmod(i * 97.3 + t * 260.0, s.x + 100.0) - 50.0
		var y := fposmod(i * 53.7 + t * 1300.0, s.y + 60.0) - 30.0
		_rain_layer.draw_line(Vector2(x, y), Vector2(x - 6, y + 22), Color(0.8, 0.9, 1.0, 0.35), 2.0)


# ---------------------------------------------------------------- results

func show_result(won: bool, title: String, info: String, stars: int, has_next: bool) -> void:
	_result_panel.visible = true
	_touch.visible = false
	_result_title.text = title
	_result_title.label_settings.font_color = Color("2e9e46") if won else BAD
	_result_info.text = info
	_result_star_count = stars
	_result_stars.visible = won
	_result_stars.queue_redraw()
	_next_button.visible = won and has_next
	(_next_button if _next_button.visible else _result_panel.find_child("Retry", true, false)).grab_focus()


func _build_result_panel() -> void:
	_result_panel = _panel()
	add_child(_result_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_panel.add_child(box)
	_result_title = _label(48, GOOD, false)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_stars = Control.new()
	_result_stars.custom_minimum_size = Vector2(300, 80)
	_result_stars.draw.connect(func() -> void:
		var c := _result_stars.size * 0.5
		for i in 3:
			_star(_result_stars, c + Vector2((i - 1) * 90.0, 0), 34.0, 1.0 if i < _result_star_count else 0.0))
	box.add_child(_result_stars)
	_result_info = _label(24, INK, false)
	_result_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_info.custom_minimum_size = Vector2(560, 0)
	box.add_child(_result_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var retry := _button("Retry (R)", func() -> void: retry_pressed.emit())
	retry.name = "Retry"
	row.add_child(retry)
	_next_button = _button("Next (Enter)", func() -> void: next_pressed.emit())
	row.add_child(_next_button)
	row.add_child(_button("Menu", func() -> void: menu_pressed.emit()))
	_result_panel.visible = false


# ---------------------------------------------------------------- menu

func show_menu(stars: Dictionary, levels: Array) -> void:
	_driving_ui.visible = false
	_result_panel.visible = false
	_rain_layer.visible = false
	_touch.visible = false
	_menu_panel.visible = true
	for child in _level_list.get_children():
		child.queue_free()
	var first_unbeaten := -1
	for i in levels.size():
		var earned: int = stars.get(i, 0)
		var b := _button("%d.  %s" % [i + 1, levels[i].name], func() -> void: level_chosen.emit(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 50)
		b.draw.connect(func() -> void:
			for s in 3:
				_star(b, Vector2(b.size.x - 96 + s * 34, b.size.y * 0.5), 13.0, 1.0 if s < earned else 0.0))
		_level_list.add_child(b)
		if earned == 0 and first_unbeaten < 0:
			first_unbeaten = i
	(_level_list.get_child(maxi(first_unbeaten, 0)) as Button).call_deferred("grab_focus")


func _build_menu() -> void:
	_menu_panel = _panel()
	add_child(_menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_menu_panel.add_child(box)
	var title := _label(64, PINK, true)
	title.text = "SURGE PRICING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label(22, INK, false)
	sub.text = "World Tour: 10 cities. Drive fast, get tipped, stay above 4 stars."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var keys := _label(17, Color(INK, 0.7), false)
	keys.text = "Arrows / WASD drive   Space drift   R retry   M music   Esc menu"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
	_level_list = GridContainer.new()   # one column on phones, two on wide screens (see _layout)
	_level_list.add_theme_constant_override("h_separation", 10)
	_level_list.add_theme_constant_override("v_separation", 6)
	box.add_child(_level_list)
	_menu_panel.visible = false


# ---------------------------------------------------------------- touch controls

func _build_touch() -> void:
	_touch = Node2D.new()
	_touch.draw.connect(_draw_touch)
	add_child(_touch)
	_brake = _touch_button("brake")
	_drift = _touch_button("drift")
	_touch.visible = false


func _touch_button(action: String) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	var circle := CircleShape2D.new()
	circle.radius = BUTTON_R * 1.2
	b.shape = circle
	b.shape_centered = true
	b.action = action
	b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	_touch.add_child(b)
	return b


## The stick floats: wherever your left thumb lands becomes its centre.
func _input(event: InputEvent) -> void:
	if not show_touch or not _driving_ui.visible or _result_panel.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _stick_index < 0 and event.position.x < size.x * 0.5 and event.position.y > 140:
			_stick_index = event.index
			_stick_origin = event.position
			stick = Vector2.ZERO
		elif not event.pressed and event.index == _stick_index:
			_stick_index = -1
			stick = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _stick_index:
		stick = ((event.position - _stick_origin) / STICK_R).limit_length(1.0)


func _draw_touch() -> void:
	var font := get_theme_default_font()
	for b in [_brake, _drift]:
		var col := BAD if b == _brake else BLUE
		col.a = 0.85 if b.is_pressed() else 0.45
		_touch.draw_circle(b.position, BUTTON_R, col)
		_touch.draw_arc(b.position, BUTTON_R, 0, TAU, 40, INK, 4.0, true)
		_touch.draw_string(font, b.position + Vector2(-BUTTON_R, 9), "BRAKE" if b == _brake else "DRIFT",
				HORIZONTAL_ALIGNMENT_CENTER, BUTTON_R * 2.0, 24, CREAM)
	var base := _stick_origin if _stick_index >= 0 else Vector2(STICK_R + 50.0, size.y - STICK_R - 50.0)
	_touch.draw_circle(base, STICK_R, Color(1, 1, 1, 0.15))
	_touch.draw_arc(base, STICK_R, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
	_touch.draw_circle(base + stick * STICK_R, 34, Color(1, 1, 1, 0.55))


# ---------------------------------------------------------------- layout and helpers

func _layout() -> void:
	if _menu_panel == null:
		return
	var s := size
	var narrow := s.x < 900.0
	if _level_list != null:
		_level_list.columns = 1 if narrow else 2
	_clock_label.position = Vector2(s.x * 0.5 - _clock_label.size.x * 0.5, 6)
	_alert.reset_size()
	_alert.position = Vector2((s.x - _alert.size.x) * 0.5, 250.0 if s.x >= 900.0 else 330.0)
	_card.position = Vector2(16, 96 if narrow else 16)
	_tip_label.size = Vector2(minf(s.x - 60.0, 860.0), 0)
	_tip_label.position = Vector2((s.x - _tip_label.size.x) * 0.5, s.y * (0.62 if narrow else 0.68))
	_toast_box.position = Vector2(s.x - _toast_box.size.x - 16, 80) if not narrow \
			else Vector2((s.x - _toast_box.size.x) * 0.5, s.y * 0.40)
	var pause := _driving_ui.get_node("Pause") as Button
	pause.position = Vector2(s.x - 110, 14)
	_drift.position = Vector2(s.x - BUTTON_R - 36.0, s.y - BUTTON_R - 40.0)
	_brake.position = Vector2(s.x - BUTTON_R * 3.0 - 56.0, s.y - BUTTON_R - 40.0)
	for p in [_result_panel, _menu_panel]:
		p.reset_size()
		p.position = (s - p.size) * 0.5


func _round_rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(16)
	c.draw_style_box(sb, r)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := StyleBoxFlat.new()
	normal.bg_color = SUN
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(3)
	normal.border_color = INK
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color("ffe27a")
	var focus := normal.duplicate()
	focus.bg_color = Color("ffe27a")
	focus.set_border_width_all(5)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", INK)
	return t


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	p.resized.connect(_layout)
	return p


func _label(font_size: int, color: Color, outlined := true) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	if outlined:
		ls.outline_size = 10
		ls.outline_color = INK
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


## A five-point star, filled `fill` of the way from the left (for 4.6 stars).
func _star(ci: CanvasItem, c: Vector2, r: float, fill: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2.0 + i * TAU / 10.0) * rad)
	ci.draw_colored_polygon(pts, Color(0.5, 0.5, 0.5, 0.35))
	if fill >= 0.999:
		ci.draw_colored_polygon(pts, SUN)
	elif fill > 0.01:
		# Clip the star to its left `fill` portion.
		var cut := c.x - r + 2.0 * r * fill
		var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([
			Vector2(c.x - r - 1, c.y - r - 1), Vector2(cut, c.y - r - 1),
			Vector2(cut, c.y + r + 1), Vector2(c.x - r - 1, c.y + r + 1)]))
		for poly in clipped:
			ci.draw_colored_polygon(poly, SUN)
	pts.append(pts[0])
	ci.draw_polyline(pts, INK, 2.0, true)
