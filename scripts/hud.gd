extends CanvasLayer
## HUD: command bar, deploy palette, next-wave intel, unit card, message log, minimap, end panel, and an
## overlay that draws NATO-style symbols (APP-6, simplified), health bars and selection rings over units.
## Styled as a field command console: Bahnschrift (Windows' DIN face) with monospace figures.

var game
var stats := {}
var btn := {}
var pal := {}
var pal_cost := {}
var info: RichTextLabel
var info_panel: PanelContainer
var info_icon: Control
var info_name: Label
var info_sub: Label
var info_bar: Control
var pal_panel: PanelContainer
var mini_panel: PanelContainer
var intel_panel: PanelContainer
var intel_box: VBoxContainer
var log_box: VBoxContainer
var overlay: Control
var minimap: Control
var end_panel: PanelContainer
var end_title: Label
var end_text: Label
var _info_sig := ""
var _info_unit: Unit
var _info_icon := {"affil": "friend", "glyph": "inf"}
var _intel_wave := -1
var _mini_tex: ImageTexture
var _font: Font
var _bold: Font
var _title: Font
var _mono: Font

const FRIEND := Color("#80e0ff")
const HOSTILE := Color("#ff8080")
const INK := Color("#ebe9de")
const MUTED := Color("#98a395")
const LINE := Color("#323c35")
const BLUE := Color("#72b9ec")
const RED := Color("#e65a4c")
const AMBER := Color("#e9b44c")
const GLASS := Color(0.055, 0.07, 0.06, 0.88)


# ---------- theme ----------

func _sys_font(names: Array, weight: int = 400, stretch: int = 100) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.font_stretch = stretch
	return f


func _box(bg: Color, border: Color, width: int = 1, radius: int = 3, margin: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _make_theme() -> Theme:
	_font = _sys_font(["Bahnschrift", "Segoe UI", "Arial"])
	_bold = _sys_font(["Bahnschrift", "Segoe UI", "Arial"], 700)
	_title = _sys_font(["Bahnschrift", "Arial Narrow", "Segoe UI"], 700, 75)
	_mono = _sys_font(["Cascadia Mono", "Consolas", "Courier New"])
	var t := Theme.new()
	t.default_font = _font
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", _box(GLASS, LINE, 1, 4, 10))
	for k in ["normal_font", "bold_font", "mono_font"]:
		t.set_font(k, "RichTextLabel", _bold if k == "bold_font" else (_mono if k == "mono_font" else _font))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", INK)
	# Buttons: quiet outline by default, blue when toggled on, amber for the primary action.
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.04), LINE, 1, 3, 7))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.09), MUTED, 1, 3, 7))
	t.set_stylebox("pressed", "Button", _box(Color(BLUE, 0.2), BLUE, 1, 3, 7))
	t.set_stylebox("hover_pressed", "Button", _box(Color(BLUE, 0.28), BLUE, 1, 3, 7))
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.015), Color(LINE, 0.6), 1, 3, 7))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(AMBER, AMBER, 1, 3, 9))
	t.set_stylebox("hover", "PrimaryButton", _box(AMBER.lightened(0.15), AMBER.lightened(0.15), 1, 3, 9))
	t.set_stylebox("pressed", "PrimaryButton", _box(AMBER.darkened(0.15), AMBER.darkened(0.15), 1, 3, 9))
	t.set_stylebox("disabled", "PrimaryButton", _box(Color(AMBER, 0.2), Color(AMBER, 0.3), 1, 3, 9))
	t.set_font("font", "PrimaryButton", _bold)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(k, "PrimaryButton", Color("#1a1408"))
	t.set_color("font_disabled_color", "PrimaryButton", Color(AMBER, 0.6))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.04, 0.05, 0.045, 0.95), LINE, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 15)
	return t


# ---------- small builders ----------

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, size: int = 14, col: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _caption(parent: Control, text: String) -> Label:
	return _label(parent, text.to_upper(), 12, MUTED, _bold)


func _button(parent: Control, text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A small control that draws one unit symbol, used in the palette, intel panel and unit card.
func _icon(parent: Control, size: Vector2, affil: String, glyph: String, scale: float = 13.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("affil", affil)
	c.set_meta("glyph", glyph)
	c.draw.connect(func(): symbol(c, c.size / 2.0, scale, c.get_meta("affil"), c.get_meta("glyph"), 1.0))
	parent.add_child(c)
	return c


## Hover text for a build-bar button: what the unit is for and what it carries.
func _unit_tooltip(d: Dictionary, hotkey: int) -> String:
	var armor: Array = d["armor"]
	var lines := ["%s  —  %d supply" % [d["name"], d["cost"]], d["role"], ""]
	for wk in d["weapons"]:
		var w: Dictionary = GameData.WEAP[wk]
		lines.append("%s: %d m, pen %d" % [w["name"], w["range"], w["pen"]])
	lines.append("Armour: %s" % ("%d front / %d side" % [armor[0], armor[1]] if armor[0] > 0.0 else "none"))
	lines.append("Speed: %d m/s  ·  Hotkey %d" % [d["speed"], hotkey])
	return "\n".join(lines)


func _stat(parent: Control, key: String, caption: String) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	parent.add_child(v)
	_caption(v, caption)
	stats[key] = _label(v, "", 20, INK, _mono)


# ---------- layout ----------

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(func(): _draw_overlay(overlay))
	root.add_child(overlay)

	# Command bar
	var bar := _panel(root)
	bar.position = Vector2(12, 10)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	bar.add_child(hb)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -4)
	hb.add_child(brand)
	_label(brand, "KESTREL LINE", 26, AMBER, _title)
	_label(brand, "SECTOR 1 · HOLLOW VALLEY", 11, MUTED, _mono)
	hb.add_child(VSeparator.new())
	_stat(hb, "wave", "Wave")
	_stat(hb, "supply", "Supply")
	_stat(hb, "hq", "HQ integrity")
	_stat(hb, "kills", "Destroyed")
	_stat(hb, "lost", "Lost")
	hb.add_child(VSeparator.new())
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(acts)
	btn["avenues"] = _button(acts, "Avenues  T", func(): game.toggle_avenues())
	btn["avenues"].toggle_mode = true
	btn["speed"] = _button(acts, "1×", func(): game.cycle_speed())
	btn["speed"].custom_minimum_size = Vector2(44, 0)
	btn["pause"] = _button(acts, "Pause  P", func(): game.paused = not game.paused)
	btn["pause"].toggle_mode = true
	btn["wave"] = _button(acts, "Send wave 1", func(): game.send_wave(), true)
	btn["wave"].custom_minimum_size = Vector2(196, 40)
	for b in btn.values():
		(b as Button).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Message log
	log_box = VBoxContainer.new()
	log_box.position = Vector2(12, 92)
	log_box.add_theme_constant_override("separation", 4)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	# Next-wave intel
	intel_panel = _panel(root)
	intel_box = VBoxContainer.new()
	intel_box.add_theme_constant_override("separation", 4)
	intel_box.custom_minimum_size = Vector2(230, 0)
	intel_panel.add_child(intel_box)

	# Deploy palette
	# A compact build bar: one square icon per unit (symbol, cost, hotkey); hover for the full description.
	pal_panel = _panel(root)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 5)
	pal_panel.add_child(pv)
	_caption(pv, "Deploy")
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 5)
	pv.add_child(ph)
	for i in GameData.PLAYER_KEYS.size():
		var k: String = GameData.PLAYER_KEYS[i]
		var d: Dictionary = GameData.DEFS[k]
		var b := _button(ph, "", func(): game.set_build(k))
		b.toggle_mode = true
		b.tooltip_text = _unit_tooltip(d, i + 1)
		b.custom_minimum_size = Vector2(64, 70)
		var key := _label(b, str(i + 1), 11, MUTED, _mono)
		key.position = Vector2(6, 3)
		var icon := _icon(b, Vector2(64, 40), "friend", d["glyph"], 15.0)
		icon.position = Vector2(0, 8)
		var cost := _label(b, str(d["cost"]), 14, AMBER, _mono)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.position = Vector2(0, 46)
		cost.size = Vector2(64, 18)
		pal_cost[k] = cost
		pal[k] = b

	# Unit card
	info_panel = _panel(root)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	iv.custom_minimum_size = Vector2(320, 0)
	info_panel.add_child(iv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	iv.add_child(head)
	info_icon = Control.new()
	info_icon.custom_minimum_size = Vector2(48, 36)
	info_icon.draw.connect(func(): symbol(info_icon, info_icon.size / 2.0, 15.0, _info_icon["affil"], _info_icon["glyph"], 1.0))
	head.add_child(info_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	head.add_child(hv)
	info_name = _label(hv, "", 18, INK, _bold)
	info_sub = _label(hv, "", 12, MUTED)
	info_bar = Control.new()
	info_bar.custom_minimum_size = Vector2(0, 6)
	info_bar.draw.connect(_draw_info_bar)
	iv.add_child(info_bar)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.add_theme_font_size_override("normal_font_size", 13)
	info.add_theme_font_size_override("mono_font_size", 13)
	iv.add_child(info)
	info_panel.visible = false

	# Minimap
	mini_panel = _panel(root)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mini_panel.add_child(mv)
	_caption(mv, "Sector map")
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(216, 216)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	minimap.clip_contents = true
	minimap.draw.connect(func(): _draw_minimap(minimap))
	minimap.gui_input.connect(_minimap_input)
	mv.add_child(minimap)
	_label(mv, "LMB drag pan · RMB drag rotate\nMMB drag tilt · wheel zoom\nclick select · Shift+drag box\nRMB click move · X withdraw · H HQ", 13, MUTED)

	# End panel
	end_panel = _panel(root)
	end_panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.065, 0.055, 0.96), AMBER, 1, 6, 26))
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 14)
	end_panel.add_child(ev)
	_caption(ev, "Sitrep")
	end_title = _label(ev, "", 40, AMBER, _title)
	end_text = _label(ev, "", 16)
	end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_text.custom_minimum_size = Vector2(460, 0)
	var eb := HBoxContainer.new()
	eb.add_theme_constant_override("separation", 8)
	ev.add_child(eb)
	_button(eb, "Play again", func(): get_tree().reload_current_scene(), true).custom_minimum_size = Vector2(160, 40)
	_button(eb, "Quit", func(): get_tree().quit()).custom_minimum_size = Vector2(100, 40)
	end_panel.visible = false


func show_end(title: String, text: String) -> void:
	end_title.text = title.to_upper()
	end_text.text = text
	end_panel.visible = true


func add_log(text: String, kind: String) -> void:
	if log_box == null:
		return
	var col := {"bad": RED, "good": BLUE, "warn": AMBER}.get(kind, MUTED) as Color
	var p := PanelContainer.new()
	var sb := _box(GLASS, col, 0, 3, 8)
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_child(p)
	var l := _label(p, text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(390, 0)
	log_box.move_child(p, 0)
	while log_box.get_child_count() > 5:
		var old := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


func _process(_delta: float) -> void:
	if game == null or game.world == null:
		return
	var g = game
	# Panels are placed from the window size each frame so they stay put when it's resized.
	var vp := get_viewport().get_visible_rect().size
	for p in [pal_panel, info_panel, mini_panel, intel_panel, end_panel]:
		(p as Control).size = (p as Control).get_combined_minimum_size()
	pal_panel.position = Vector2(12, vp.y - pal_panel.size.y - 12)
	info_panel.position = Vector2(pal_panel.size.x + 24, vp.y - info_panel.size.y - 12)
	mini_panel.position = vp - mini_panel.size - Vector2(12, 12)
	intel_panel.position = Vector2(vp.x - intel_panel.size.x - 12, 10)
	end_panel.position = (vp - end_panel.size) / 2.0
	stats["wave"].text = "%d/%d" % [g.wave, GameData.WAVES.size()]
	stats["supply"].text = str(g.supply)
	stats["hq"].text = "%d/%d" % [g.integrity, GameData.HQ_INTEGRITY]
	stats["hq"].add_theme_color_override("font_color", RED if g.integrity <= 6 else (AMBER if g.integrity <= 12 else INK))
	stats["kills"].text = str(g.kills)
	stats["lost"].text = str(g.lost)
	stats["lost"].add_theme_color_override("font_color", RED if g.lost > 0 else INK)
	btn["speed"].text = "%d×" % int(g.speed)
	btn["pause"].set_pressed_no_signal(g.paused)
	btn["pause"].text = "Resume  P" if g.paused else "Pause  P"
	btn["avenues"].set_pressed_no_signal(g.show_avenues)
	var wb: Button = btn["wave"]
	wb.disabled = g.over != "" or g.wave >= GameData.WAVES.size()
	if g.wave >= GameData.WAVES.size():
		wb.text = "All waves sent"
	elif g.wave_active:
		wb.text = "Send wave %d early" % (g.wave + 1)
	else:
		wb.text = "Send wave %d  ▸" % (g.wave + 1)
	for k in pal:
		var b: Button = pal[k]
		var poor: bool = g.supply < GameData.DEFS[k]["cost"]
		b.set_pressed_no_signal(g.build_type == k)
		b.disabled = poor and g.build_type != k
		(pal_cost[k] as Label).add_theme_color_override("font_color", RED if poor else AMBER)
	_update_intel()
	_update_info()
	overlay.queue_redraw()
	minimap.queue_redraw()


func _update_intel() -> void:
	var g = game
	if _intel_wave == g.wave:
		return
	_intel_wave = g.wave
	for c in intel_box.get_children():
		c.queue_free()
	if g.wave >= GameData.WAVES.size():
		_caption(intel_box, "Intel")
		_label(intel_box, "No further enemy forces\nreported in this sector.", 13, MUTED)
		return
	_caption(intel_box, "Intel · wave %d" % (g.wave + 1))
	var counts := {}
	for grp in GameData.WAVES[g.wave]:
		counts[grp[0]] = counts.get(grp[0], 0) + int(grp[1])
	for t in counts:
		var d: Dictionary = GameData.DEFS[t]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		intel_box.add_child(row)
		_icon(row, Vector2(30, 26), "air" if d.get("air", false) else "hostile", d["glyph"], 10.0)
		_label(row, "%d×" % counts[t], 15, RED, _mono)
		_label(row, d["name"], 14)


func _draw_info_bar() -> void:
	var u := _info_unit
	if not game.alive(u):
		return
	var w := info_bar.size.x
	var f := clampf(u.hp / u.max_hp, 0.0, 1.0)
	info_bar.draw_rect(Rect2(0, 0, w, 6), Color(1, 1, 1, 0.08))
	info_bar.draw_rect(Rect2(0, 0, w * f, 6), BLUE if u.side == "p" else (AMBER if f > 0.4 else RED))


func _update_info() -> void:
	var g = game
	var sel: Array = g.selection.filter(func(x): return game.alive(x))
	var u: Unit = null
	if sel.size() == 1:
		u = sel[0]
	elif sel.is_empty() and game.alive(g.inspect):
		u = g.inspect
	if u == null and sel.is_empty():
		info_panel.visible = false
		_info_sig = ""
		return
	info_panel.visible = true
	_info_unit = u
	info_bar.visible = u != null
	info_bar.queue_redraw()
	var head_txt := ""
	var sub := ""
	var txt := ""
	if u == null:
		var counts := {}
		var refund := 0
		for s in sel:
			counts[(s as Unit).def["name"]] = counts.get((s as Unit).def["name"], 0) + 1
			refund += int((s as Unit).invested * 0.5)
		head_txt = "%d units selected" % sel.size()
		sub = "Right-click to move · X withdraws (+%d)" % refund
		_info_icon = {"affil": "friend", "glyph": (sel[0] as Unit).def["glyph"]}
		txt = "[table=2]"
		for k in counts:
			txt += "[cell]%s[/cell][cell][right][code]× %d[/code][/right][/cell]" % [k, counts[k]]
		txt += "[/table]"
	else:
		var friend := u.side == "p"
		var armor: Array = u.def["armor"]
		head_txt = u.def["name"]
		sub = "%s · %s · strength %d%%" % ["Friendly" if friend else "Hostile", u.status(), int(maxf(0.0, u.hp / u.max_hp * 100.0))]
		_info_icon = {"affil": "friend" if friend else ("air" if u.air else "hostile"), "glyph": u.def["glyph"]}
		txt = "[table=2][cell][color=#98a395]Armour[/color][/cell][cell][right][code]%s[/code][/right][/cell]" % ("%d front / %d side" % [armor[0], armor[1]] if armor[0] > 0.0 else "none")
		for e in u.weapons:
			var w: Dictionary = e["w"]
			txt += "[cell][color=#98a395]%s[/color][/cell][cell][right][code]%d m · pen %d[/code][/right][/cell]" % [w["name"], w["range"], w["pen"]]
		if friend:
			txt += "[cell][color=#98a395]Destroyed[/color][/cell][cell][right][code]%d[/code][/right][/cell]" % u.kills
		else:
			txt += "[cell][color=#98a395]Route[/color][/cell][cell][right][code]%s[/code][/right][/cell]" % ("direct" if u.air else ("bold" if u.variant == 1 else "cautious"))
		txt += "[/table]"
		if friend:
			txt += "\n[color=#98a395]X withdraws this unit (+%d supply)[/color]" % int(u.invested * 0.5)
	var sig := head_txt + sub + txt
	if sig != _info_sig:
		_info_sig = sig
		info_name.text = head_txt
		info_sub.text = sub
		info.text = txt
		info_icon.queue_redraw()


# ---------- overlay ----------

func _ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := i / float(n) * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## NATO-style unit symbol. affil: "friend" (rectangle), "hostile" (diamond), "air" (open-bottom frame).
func symbol(c: Control, at: Vector2, s: float, affil: String, glyph: String, alpha: float) -> void:
	var out := Color(0.07, 0.07, 0.07, alpha)
	var fill := (FRIEND if affil == "friend" else HOSTILE)
	fill.a = alpha
	var lw := maxf(1.0, s * 0.11)
	var hw: float
	var hh: float
	var cy := 0.0
	if affil == "friend":
		hw = s * 0.75
		hh = s * 0.5
		var r := Rect2(at - Vector2(hw, hh), Vector2(hw * 2.0, hh * 2.0))
		c.draw_rect(r, fill)
		c.draw_rect(r, out, false, lw)
	elif affil == "air":
		hw = s * 0.72
		hh = s * 0.62
		var pts := PackedVector2Array([at + Vector2(-hw, hh * 0.55), at + Vector2(-hw, 0), at + Vector2(0, -hh * 1.15), at + Vector2(hw, 0), at + Vector2(hw, hh * 0.55)])
		c.draw_colored_polygon(pts, fill)
		c.draw_polyline(pts, out, lw)
		cy = -hh * 0.05
	else:
		hw = s * 0.78
		hh = s * 0.78
		var pts := PackedVector2Array([at + Vector2(0, -hh), at + Vector2(hw, 0), at + Vector2(0, hh), at + Vector2(-hw, 0)])
		c.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		c.draw_polyline(pts, out, lw)
	var gw := hw * 0.5 if affil == "hostile" else (hw * 0.62 if affil == "air" else hw)
	var gh := hh * 0.5 if affil == "hostile" else (hh * 0.5 if affil == "air" else hh)
	var o := at + Vector2(0, cy)
	match glyph:
		"inf", "mech":
			c.draw_line(o + Vector2(-gw, -gh), o + Vector2(gw, gh), out, lw)
			c.draw_line(o + Vector2(gw, -gh), o + Vector2(-gw, gh), out, lw)
			if glyph == "mech":
				var e := _ellipse(o, gw * 0.62, gh * 0.48)
				c.draw_colored_polygon(e, fill)
				c.draw_polyline(e, out, lw)
		"armor":
			c.draw_polyline(_ellipse(o, gw * 0.62, gh * 0.48), out, lw)
		"recon":
			c.draw_line(o + Vector2(-gw, gh), o + Vector2(gw, -gh), out, lw)
		"at":
			c.draw_polyline(PackedVector2Array([o + Vector2(-gw, gh), o + Vector2(0, -gh), o + Vector2(gw, gh)]), out, lw)
		"mortar":
			c.draw_circle(o + Vector2(0, -gh * 0.15), gh * 0.3, out)
			c.draw_line(o + Vector2(0, gh * 0.15), o + Vector2(0, gh * 0.75), out, lw)
		"ada":
			c.draw_arc(o + Vector2(0, gh), gw * 0.62, PI, TAU, 14, out, lw)
		"rotary":
			var r := gw * 0.8
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(-r, -r * 0.55), o, o + Vector2(-r, r * 0.55)]), out)
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(r, -r * 0.55), o, o + Vector2(r, r * 0.55)]), out)
		"uav":
			var r := gw * 0.9
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(-r, -r * 0.3), o + Vector2(0, r * 0.08), o + Vector2(r, -r * 0.3), o + Vector2(r, 0), o + Vector2(0, r * 0.4), o + Vector2(-r, 0)]), out)


func _draw_overlay(c: Control) -> void:
	var g = game
	if g == null or g.world == null:
		return
	var cam: Camera3D = g.rig.cam
	var sym_a := clampf((g.rig.dist - 160.0) / 200.0, 0.0, 1.0)
	for u in g.players + g.enemies:
		var uu: Unit = u
		if uu.dead:
			continue
		var top = g.screen_of(uu, 3.0 if uu.air else (4.0 if uu.small else 6.0))
		if top == null:
			continue
		var tp: Vector2 = top
		var sel: bool = uu in g.selection or g.inspect == uu
		if sel:
			var base = g.screen_of(uu, 0.0)
			var edge := Vector3(uu.p.x + 9.0, uu.y, uu.p.y)
			if base != null and not cam.is_position_behind(edge):
				var r := maxf(8.0, (cam.unproject_position(edge) - (base as Vector2)).length())
				c.draw_polyline(_ellipse(base, r, r * 0.55, 28), BLUE if uu.side == "p" else RED, 2.0)
		# Friendly symbols fade in as you zoom out; enemy symbols are always shown so the threat can't
		# disappear under the trees: bright when spotted, dimmed when only their last position is known.
		var a := sym_a * 0.95
		if uu.side == "e":
			a = 1.0 if uu.spotted else 0.45
		if a > 0.0:
			symbol(c, tp + Vector2(0, -12), 15.0 if sym_a > 0.0 else 12.0, "friend" if uu.side == "p" else ("air" if uu.air else "hostile"), uu.def["glyph"], a)
			if uu.side == "e" and uu.spotted and sym_a < 1.0:
				c.draw_arc(tp + Vector2(0, -12), 13.0, 0.0, TAU, 20, Color(RED, 0.8), 1.5)
		if uu.hp < uu.max_hp or sel:
			var w := 26.0
			var f := clampf(uu.hp / uu.max_hp, 0.0, 1.0)
			var y := tp.y - (28.0 if a > 0.0 else 8.0)
			c.draw_rect(Rect2(tp.x - w / 2.0 - 1.0, y - 1.0, w + 2.0, 5.0), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(tp.x - w / 2.0, y, w * f, 3.0), BLUE if uu.side == "p" else (AMBER if f > 0.4 else RED))
		if uu.dug_in and uu.side == "p" and g.rig.dist < 320.0:
			c.draw_string(_bold, tp + Vector2(-20, 14), "DUG IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AMBER)
	for i in WorldGen.SPAWNS.size():
		var s: Vector2 = WorldGen.SPAWNS[i]
		var w3 := Vector3(s.x, g.world.h_at(s.x, s.y) + 14.0, s.y)
		if not cam.is_position_behind(w3):
			c.draw_string(_bold, cam.unproject_position(w3) - Vector2(55, 0), "ASSEMBLY AREA %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RED)
	var hq3 := Vector3(WorldGen.HQ.x, g.world.h_at(WorldGen.HQ.x, WorldGen.HQ.y) + 30.0, WorldGen.HQ.y)
	if not cam.is_position_behind(hq3):
		c.draw_string(_bold, cam.unproject_position(hq3) - Vector2(30, 0), "HQ · %d/%d" % [g.integrity, GameData.HQ_INTEGRITY], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BLUE)
	if not g.order_mark.is_empty() and g.order_mark["t"] < 0.8:
		var op: Vector2 = g.order_mark["p"]
		var w4 := Vector3(op.x, g.ground_y(op.x, op.y), op.y)
		if not cam.is_position_behind(w4):
			var k: float = 1.0 - g.order_mark["t"] / 0.8
			c.draw_polyline(_ellipse(cam.unproject_position(w4), 22.0 * k, 12.0 * k), Color(BLUE, k), 2.0)
	if not g.drag.is_empty() and g.drag["button"] == MOUSE_BUTTON_LEFT and g.drag["moved"] and g.drag["shift"] and g.build_type == "":
		var r := Rect2(g.drag["start"], Vector2.ZERO).expand(g.drag["cur"])
		c.draw_rect(r, Color(BLUE, 0.12))
		c.draw_rect(r, BLUE, false, 1.0)
	if g.build_type != "" and g.ghost and g.ghost.visible:
		var d: Dictionary = GameData.DEFS[g.build_type]
		var txt: String = ("%s · %d" % [d["name"], d["cost"]]) if g.ghost_ok else g.ghost_err
		var pos: Vector2 = g.hover + Vector2(18, 26)
		c.draw_rect(Rect2(pos - Vector2(6, 16), Vector2(_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12, 22)), Color(0.04, 0.05, 0.04, 0.85))
		c.draw_string(_bold, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK if g.ghost_ok else RED)
	var vp := c.get_viewport_rect().size
	if g.wave_active and g.queue.size() > 0:
		c.draw_string(_bold, Vector2(vp.x / 2.0 - 70, vp.y - 24), "%d MORE INBOUND" % g.queue.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, RED)
	if g.paused:
		c.draw_string(_title, Vector2(vp.x / 2.0 - 70, vp.y / 2.0), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, INK)


# ---------- minimap ----------

func _build_minimap() -> void:
	var w: WorldGen = game.world
	var img := Image.create(WorldGen.G, WorldGen.G, false, Image.FORMAT_RGB8)
	for k in WorldGen.G * WorldGen.G:
		var c := w.cell_center(k)
		var col := Color("#6f8a45")
		if w.water[k] == 1:
			col = Color("#4c7f96")
		elif w.bridge[k] == 1:
			col = Color("#8d8b82")
		elif w.road[k] == 1:
			col = Color("#a8936c")
		elif w.forest[k] == 1:
			col = Color("#2f4a26")
		col = col * (0.75 + clampf(w.h_at(c.x, c.y) / 90.0, 0.0, 0.5))
		img.set_pixel(k % WorldGen.G, k / WorldGen.G, col)
	_mini_tex = ImageTexture.create_from_image(img)


func _mini(p: Vector2, s: float) -> Vector2:
	return (p + Vector2(WorldGen.HALF, WorldGen.HALF)) / WorldGen.SIZE * s


func _draw_minimap(c: Control) -> void:
	var g = game
	if g == null or g.world == null:
		return
	if _mini_tex == null:
		_build_minimap()
	var s := minf(c.size.x, c.size.y)
	c.draw_texture_rect(_mini_tex, Rect2(Vector2.ZERO, Vector2(s, s)), false)
	c.draw_arc(_mini(WorldGen.HQ, s), GameData.DEPLOY_R / WorldGen.SIZE * s, 0, TAU, 64, Color(BLUE, 0.7), 1.5)
	if g.show_avenues:
		for a in g.avenues:
			var pts := PackedVector2Array()
			for p in a["pts"]:
				pts.append(_mini(p, s))
			c.draw_polyline(pts, Color(0.75, 0.15, 0.1) if a["move"] == "track" else Color(0.95, 0.4, 0.3), 1.5)
	var hq := _mini(WorldGen.HQ, s)
	c.draw_rect(Rect2(hq - Vector2(5, 5), Vector2(10, 10)), BLUE)
	for u in g.players:
		var uu: Unit = u
		c.draw_rect(Rect2(_mini(uu.p, s) - Vector2(3, 3), Vector2(6, 6)), Color.WHITE if uu in g.selection else BLUE)
	for u in g.enemies:
		var uu: Unit = u
		c.draw_circle(_mini(uu.p, s), 2.0 if uu.air else 3.0, RED)
	var t: Vector3 = g.rig.target
	var cp := _mini(Vector2(t.x, t.z), s)
	var r: float = g.rig.dist * 0.7 / WorldGen.SIZE * s
	c.draw_set_transform(cp, -g.rig.yaw, Vector2.ONE)
	c.draw_rect(Rect2(Vector2(-r, -r * 0.6), Vector2(r * 2.0, r * 1.2)), Color.WHITE, false, 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _minimap_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		var w := mb.position / minimap.size.x * WorldGen.SIZE - Vector2(WorldGen.HALF, WorldGen.HALF)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			game.rig.target = Vector3(w.x, 0.0, w.y)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			game.order_move(w)
		minimap.accept_event()
