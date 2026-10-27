extends CanvasLayer
## HUD: command bar, deploy palette, unit card, message log, minimap, end panel, and an overlay
## that draws NATO-style symbols (APP-6, simplified), health bars and selection rings over units.

var game
var stats := {}
var btn := {}
var pal := {}
var info: RichTextLabel
var info_panel: PanelContainer
var pal_panel: PanelContainer
var mini_panel: PanelContainer
var log_box: VBoxContainer
var overlay: Control
var minimap: Control
var end_panel: PanelContainer
var end_title: Label
var end_text: Label
var _info_sig := ""
var _mini_tex: ImageTexture
var _font: Font

const FRIEND := Color("#80e0ff")
const HOSTILE := Color("#ff8080")
const INK := Color("#ebe9de")
const MUTED := Color("#98a395")
const BLUE := Color("#72b9ec")
const RED := Color("#e65a4c")
const AMBER := Color("#e9b44c")


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.075, 0.065, 0.86)
	s.border_color = Color(0.19, 0.23, 0.2)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	return s


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, size: int = 14, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	hb.add_theme_constant_override("separation", 20)
	bar.add_child(hb)
	_label(hb, "KESTREL LINE · HOLLOW VALLEY", 16, AMBER)
	for k in ["wave", "supply", "hq", "kills", "lost"]:
		stats[k] = _label(hb, "", 15)
	btn["avenues"] = _button(hb, "Avenues (T)", func(): game.toggle_avenues())
	btn["speed"] = _button(hb, "1×", func(): game.cycle_speed())
	btn["pause"] = _button(hb, "Pause (P)", func(): game.paused = not game.paused)
	btn["wave"] = _button(hb, "Send wave 1", func(): game.send_wave())

	# Message log
	log_box = VBoxContainer.new()
	log_box.position = Vector2(14, 62)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	# Deploy palette
	var pp := _panel(root)
	pal_panel = pp
	var pv := VBoxContainer.new()
	pp.add_child(pv)
	_label(pv, "DEPLOY", 12, MUTED)
	for i in GameData.PLAYER_KEYS.size():
		var k: String = GameData.PLAYER_KEYS[i]
		var d: Dictionary = GameData.DEFS[k]
		var b := _button(pv, "%d  %s  —  %d" % [i + 1, d["name"], d["cost"]], func(): game.set_build(k))
		b.tooltip_text = d["role"]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 0)
		pal[k] = b

	# Unit card
	info_panel = _panel(root)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(330, 0)
	info.add_theme_font_size_override("normal_font_size", 14)
	info.add_theme_font_size_override("bold_font_size", 16)
	info_panel.add_child(info)
	info_panel.visible = false

	# Minimap
	var mp := _panel(root)
	mini_panel = mp
	var mv := VBoxContainer.new()
	mp.add_child(mv)
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(210, 210)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	minimap.clip_contents = true
	minimap.draw.connect(func(): _draw_minimap(minimap))
	minimap.gui_input.connect(_minimap_input)
	mv.add_child(minimap)
	_label(mv, "Left-drag pan · right-drag rotate\nmiddle-drag tilt · wheel zoom\nclick select · Shift+drag box select\nright-click move · X withdraw · H HQ", 11, MUTED)

	# End panel
	end_panel = _panel(root)
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 12)
	end_panel.add_child(ev)
	end_title = _label(ev, "", 30, AMBER)
	end_text = _label(ev, "", 15)
	end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_text.custom_minimum_size = Vector2(420, 0)
	_button(ev, "Play again", func(): get_tree().reload_current_scene())
	end_panel.visible = false


func show_end(title: String, text: String) -> void:
	end_title.text = title
	end_text.text = text
	end_panel.visible = true


func add_log(text: String, kind: String) -> void:
	if log_box == null:
		return
	var p := _panel(log_box)
	var col := {"bad": RED, "good": BLUE, "warn": AMBER}.get(kind, INK) as Color
	var l := _label(p, text, 14, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.move_child(p, 0)
	while log_box.get_child_count() > 5:
		log_box.get_child(log_box.get_child_count() - 1).queue_free()
		log_box.remove_child(log_box.get_child(log_box.get_child_count() - 1))
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


func _process(_delta: float) -> void:
	if game == null or game.world == null:
		return
	var g = game
	# Bottom panels are placed from the window size each frame so they stay put when it's resized.
	var vp := get_viewport().get_visible_rect().size
	for p in [pal_panel, info_panel, mini_panel]:
		(p as Control).size = (p as Control).get_combined_minimum_size()
	pal_panel.position = Vector2(12, vp.y - pal_panel.size.y - 12)
	info_panel.position = Vector2(pal_panel.size.x + 24, vp.y - info_panel.size.y - 12)
	mini_panel.position = vp - mini_panel.size - Vector2(12, 12)
	stats["wave"].text = "Wave %d/%d" % [g.wave, GameData.WAVES.size()]
	stats["supply"].text = "Supply %d" % g.supply
	stats["hq"].text = "HQ %d/%d" % [g.integrity, GameData.HQ_INTEGRITY]
	stats["hq"].add_theme_color_override("font_color", RED if g.integrity <= 6 else INK)
	stats["kills"].text = "Destroyed %d" % g.kills
	stats["lost"].text = "Lost %d" % g.lost
	btn["speed"].text = "%d×" % int(g.speed)
	btn["pause"].text = "Resume (P)" if g.paused else "Pause (P)"
	btn["avenues"].modulate = Color(1, 0.6, 0.55) if g.show_avenues else Color(1, 1, 1)
	var wb: Button = btn["wave"]
	wb.disabled = g.wave_active or g.over != "" or g.wave >= GameData.WAVES.size()
	wb.text = ("Wave %d in contact" % g.wave) if g.wave_active else ("All waves sent" if g.wave >= GameData.WAVES.size() else "Send wave %d (Space)" % (g.wave + 1))
	for k in pal:
		var b: Button = pal[k]
		b.set_pressed_no_signal(g.build_type == k)
		b.modulate = Color(1, 0.6, 0.55) if g.supply < GameData.DEFS[k]["cost"] else Color(1, 1, 1)
	_update_info()
	overlay.queue_redraw()
	minimap.queue_redraw()


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
	var sig := ""
	var txt := ""
	if u == null:
		var counts := {}
		var refund := 0
		for s in sel:
			counts[(s as Unit).def["name"]] = counts.get((s as Unit).def["name"], 0) + 1
			refund += int((s as Unit).invested * 0.5)
		txt = "[b]%d units selected[/b]\n" % sel.size()
		for k in counts:
			txt += "%s × %d\n" % [k, counts[k]]
		txt += "[color=#98a395]Right-click to move. X to withdraw (+%d).[/color]" % refund
	else:
		var friend := u.side == "p"
		var armor: Array = u.def["armor"]
		txt = "[b]%s[/b]  [color=#98a395]%s · %s[/color]\n" % [u.def["name"], "Friendly" if friend else "Hostile", u.status()]
		txt += "Strength %d%%\n" % int(maxf(0.0, u.hp / u.max_hp * 100.0))
		txt += "Armor: %s\n" % ("%d front / %d side" % [armor[0], armor[1]] if armor[0] > 0.0 else "none")
		for e in u.weapons:
			var w: Dictionary = e["w"]
			txt += "%s · %d m · pen %d\n" % [w["name"], w["range"], w["pen"]]
		if friend:
			txt += "Destroyed %d · X to withdraw (+%d)" % [u.kills, int(u.invested * 0.5)]
		else:
			txt += "Route: %s" % ("direct" if u.air else ("bold" if u.variant == 1 else "cautious"))
	sig = txt
	if sig != _info_sig:
		_info_sig = sig
		info.text = txt


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
		if sym_a > 0.0:
			symbol(c, tp + Vector2(0, -12), 15.0, "friend" if uu.side == "p" else ("air" if uu.air else "hostile"), uu.def["glyph"], sym_a * 0.95)
		if uu.hp < uu.max_hp or sel:
			var w := 26.0
			var f := clampf(uu.hp / uu.max_hp, 0.0, 1.0)
			var y := tp.y - (28.0 if sym_a > 0.0 else 8.0)
			c.draw_rect(Rect2(tp.x - w / 2.0 - 1.0, y - 1.0, w + 2.0, 5.0), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(tp.x - w / 2.0, y, w * f, 3.0), BLUE if uu.side == "p" else (AMBER if f > 0.4 else RED))
		if uu.dug_in and uu.side == "p" and g.rig.dist < 320.0:
			c.draw_string(_font, tp + Vector2(-20, 14), "DUG IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AMBER)
	for i in WorldGen.SPAWNS.size():
		var s: Vector2 = WorldGen.SPAWNS[i]
		var w3 := Vector3(s.x, g.world.h_at(s.x, s.y) + 14.0, s.y)
		if not cam.is_position_behind(w3):
			c.draw_string(_font, cam.unproject_position(w3) - Vector2(55, 0), "ASSEMBLY AREA %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RED)
	var hq3 := Vector3(WorldGen.HQ.x, g.world.h_at(WorldGen.HQ.x, WorldGen.HQ.y) + 30.0, WorldGen.HQ.y)
	if not cam.is_position_behind(hq3):
		c.draw_string(_font, cam.unproject_position(hq3) - Vector2(30, 0), "HQ · %d/%d" % [g.integrity, GameData.HQ_INTEGRITY], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BLUE)
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
		c.draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK if g.ghost_ok else RED)
	var vp := c.get_viewport_rect().size
	if g.wave_active and g.queue.size() > 0:
		c.draw_string(_font, Vector2(vp.x / 2.0 - 70, vp.y - 24), "%d MORE INBOUND" % g.queue.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, RED)
	if g.paused:
		c.draw_string(_font, Vector2(vp.x / 2.0 - 70, vp.y / 2.0), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, INK)


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
