extends Node3D
## Gameplay: units, enemy AI, combat, waves and player commands. A port of the browser prototype.
## The enemy's threat map and flow fields are rebuilt on a worker thread whenever the player's
## settled positions change, so the AI re-routes around new defences without stalling the frame.

const HQ := WorldGen.HQ
const SPAWNS := WorldGen.SPAWNS

var world: WorldGen
var nav: Nav
var rig
var fx
var hud

var players: Array = []
var enemies: Array = []
var wrecks: Array = []
var shots: Array = []
var queue: Array = []
var wave := 0
var wave_active := false
var wave_t := 0.0
var supply := GameData.START_SUPPLY
var integrity := GameData.HQ_INTEGRITY
var kills := 0
var lost := 0
var over := ""
var speed := 1.0
var paused := false
var show_avenues := true

var threat: Array = []
var fields := {}
var threat_dirty := false
var nav_task := -1
var nav_result: Array = []
var nav_cooldown := 0.0
var spot_t := 0.0
var _uid := 0
var avenues: Array = []

var selection: Array = []
var inspect: Unit
var build_type := ""
var ghost: Node3D
var ghost_ok := false
var ghost_err := ""
var hover := Vector2.ZERO
var order_mark := {}
var drag := {}

var _avenue_im := ImmediateMesh.new()
var _ring_im := ImmediateMesh.new()
var _range_im := ImmediateMesh.new()
var _line_mat := StandardMaterial3D.new()
var _ghost_ok_mat := StandardMaterial3D.new()
var _ghost_bad_mat := StandardMaterial3D.new()


# ================= setup =================

func setup(w: WorldGen, camera_rig) -> void:
	world = w
	rig = camera_rig
	nav = Nav.new(w)
	fx = load("res://scripts/fx.gd").new()
	add_child(fx)
	var zero := PackedFloat32Array()
	zero.resize(WorldGen.G * WorldGen.G)
	threat = [zero, zero.duplicate()]
	fields = Nav.compute_fields(nav.cost, threat, nav.goal_cells)

	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.no_depth_test = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat.render_priority = 10
	for m in [_ghost_ok_mat, _ghost_bad_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_ok_mat.albedo_color = Color(0.45, 0.73, 0.93, 0.5)
	_ghost_bad_mat.albedo_color = Color(0.9, 0.35, 0.3, 0.5)
	for im in [_avenue_im, _ring_im, _range_im]:
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_draw_deploy_ring()
	update_avenues()

	hud = load("res://scripts/hud.gd").new()
	hud.game = self
	add_child(hud)
	log_msg("Deploy inside the blue ring (keys 1–5), then send wave 1 (Space).", "good")
	log_msg("Red lines show where the enemy plans to attack. Build, and watch them change.", "warn")


static func alive(u) -> bool:
	return u != null and is_instance_valid(u) and not (u as Unit).dead


static func alive_or_dead(u) -> bool:
	return u != null and is_instance_valid(u)


func ground_y(x: float, z: float) -> float:
	var h := world.h_at(x, z)
	if world.bridge[Nav.k_of(x, z)] == 1:
		return maxf(h, WorldGen.WATER_Y + 3.8)
	return h


func normal_at(x: float, z: float) -> Vector3:
	if world.bridge[Nav.k_of(x, z)] == 1:
		return Vector3.UP
	var e := 3.0
	return Vector3(world.h_at(x - e, z) - world.h_at(x + e, z), 2.0 * e, world.h_at(x, z - e) - world.h_at(x, z + e)).normalized()


func log_msg(text: String, kind: String = "") -> void:
	if hud:
		hud.add_log(text, kind)
	print("[game] ", text)


# ================= units =================

func make_unit(t: String, s: String, pos: Vector2) -> Unit:
	_uid += 1
	var u := Unit.new()
	u.setup(t, s, _uid)
	var m := UnitModels.build(t, s, world.biome)
	u.add_child(m["root"])
	u.tur = m["tur"]
	u.rotors = m["rotors"]
	u.tail_rotor = m["tail"]
	u.men = m["men"]
	u.berm = m["berm"]
	u.p = pos
	u.y = world.h_at(pos.x, pos.y) + u.alt if u.air else ground_y(pos.x, pos.y)
	add_child(u)
	sync_unit(u, 0.0)
	return u


func sync_unit(u: Unit, dt: float) -> void:
	u.position = Vector3(u.p.x, u.y, u.p.y)
	if not u.dead:
		var yaw := Basis(Vector3.UP, u.heading)
		if not u.air and not u.small:
			u.basis = Basis(Quaternion(Vector3.UP, normal_at(u.p.x, u.p.y))) * yaw
		elif u.type == "helo":
			u.basis = yaw * Basis(Vector3.RIGHT, u.vel.length() / u.def["speed"] * 0.25)
		else:
			u.basis = yaw
	if u.tur:
		u.tur.rotation.y = u.tur_yaw
	for r in u.rotors:
		(r as Node3D).rotation.y += dt * 28.0
	if u.tail_rotor:
		u.tail_rotor.rotation.x += dt * 45.0
	if u.men.size() > 0:
		var n := ceili(u.hp / u.max_hp * u.men.size() - 0.001)
		var t := Time.get_ticks_msec() / 160.0
		for i in u.men.size():
			var s: Node3D = u.men[i]
			s.visible = i < n
			s.position.y = absf(sin(t + i)) * 0.12 if u.moving else 0.0
	if u.berm:
		u.berm.visible = u.dug_in


# ================= combat =================

func est_eff(w: Dictionary, t: Unit) -> float:
	var air_f: float = w.get("air", 0.0)
	var air_only: bool = w.get("air_only", false)
	if t.air:
		if not air_only and air_f <= 0.0:
			return 0.0
	elif air_only:
		return 0.0
	var armor: Array = t.def["armor"]
	var e: float
	if armor[0] == 0.0:
		e = w.get("soft", 1.0)
	else:
		var a: float = armor[1] if w.get("top", false) else (armor[0] + armor[1]) / 2.0
		var pen: float = w["pen"]
		e = 1.0 if pen >= a else (0.3 if pen >= a * 0.6 else 0.04)
	if t.air and not air_only:
		e *= air_f
	return e


## Woods conceal: a unit under canopy can only be seen from close in. Applies to both sides.
const CONCEAL_SMALL := 150.0
const CONCEAL_VEHICLE := 250.0


func can_see(from: Vector3, t: Unit) -> bool:
	if not t.air and world.forest[Nav.k_of(t.p.x, t.p.y)] == 1:
		if Vector2(from.x, from.z).distance_to(t.p) > (CONCEAL_SMALL if t.small else CONCEAL_VEHICLE):
			return false
	return Nav.los(world, from, Vector3(t.p.x, t.y + (0.0 if t.air else 1.8), t.p.y))


func acquire(u: Unit) -> void:
	var foes: Array = enemies if u.side == "p" else players
	var eye := Vector3(u.p.x, u.y + (0.0 if u.air else 2.5), u.p.y)
	var seen := {}
	u.halt = false
	for e in u.weapons:
		var w: Dictionary = e["w"]
		var best: Unit = null
		var bs := 0.0
		for t in foes:
			var tu: Unit = t
			if tu.dead:
				continue
			var d := u.p.distance_to(tu.p)
			if d > w["range"] or d < w.get("min", 0.0):
				continue
			var eff := est_eff(w, tu)
			if eff < 0.25:
				continue
			if w.get("indirect", false):
				if not tu.spotted or tu.air:
					continue
			else:
				if not seen.has(tu.uid):
					seen[tu.uid] = can_see(eye, tu)
				if not seen[tu.uid]:
					continue
			var sc: float = eff * GameData.VALUE.get(tu.type, 1.0) * (1.0 - 0.4 * d / w["range"])
			if sc > bs:
				bs = sc
				best = tu
		e["target"] = best
		if best != null and not w.get("indirect", false):
			u.halt = true


func apply_damage(t: Unit, w: Dictionary, src, from: Vector2) -> void:
	if t.dead:
		return
	var armor: Array = t.def["armor"]
	var a := 0.0
	if armor[0] > 0.0:
		if w.get("top", false) or t.air:
			a = armor[1]
		else:
			var to := from - t.p
			var l := to.length()
			var c := 0.0 if l < 0.01 else (sin(t.heading) * to.x + cos(t.heading) * to.y) / l
			a = armor[0] if c > 0.5 else armor[1]
	var pen: float = w["pen"]
	var eff: float
	if armor[0] == 0.0:
		eff = w.get("soft", 1.0)
	else:
		eff = 1.0 if pen >= a else (0.3 if pen >= a * 0.6 else 0.04)
	t.hp -= w["dmg"] * eff
	if t.hp <= 0.0:
		kill(t, src)


func kill(t: Unit, src) -> void:
	if t.dead:
		return
	t.dead = true
	fx.explosion(Vector3(t.p.x, t.y if t.air else ground_y(t.p.x, t.p.y), t.p.y), not t.small)
	if t.side == "e":
		supply += int(t.def.get("reward", 0))
		kills += 1
		if alive_or_dead(src) and (src as Unit).side == "p":
			(src as Unit).kills += 1
		if t.type in ["embt", "helo"]:
			log_msg("%s destroyed." % t.def["name"], "good")
	else:
		lost += 1
		log_msg("Lost: %s." % t.def["name"], "bad")
		threat_dirty = true
		selection.erase(t)
	if not t.small and t.type != "drone":
		UnitModels.char_out(t)
		if t.air:
			t.y = ground_y(t.p.x, t.p.y) + 0.8
			t.position.y = t.y
			t.rotation.z = 0.5
		t.wreck_t = 45.0
		wrecks.append(t)
	else:
		t.visible = false
		t.queue_free()


func fire(u: Unit, e: Dictionary) -> void:
	var w: Dictionary = e["w"]
	var t: Unit = e["target"]
	var d := u.p.distance_to(t.p)
	var dir := (t.p - u.p).normalized()
	var fwd := 1.0 if u.small else 4.5
	var mz := Vector3(u.p.x + dir.x * fwd, u.y + (-1.0 if u.air else (2.2 if u.small else 3.4)), u.p.y + dir.y * fwd)
	var kind: String = w["fx"]
	fx.flash(mz, 0.9 if kind == "tracer" else (1.4 if kind == "heavy" else 2.4))
	if w.get("indirect", false):
		var flight := 2.5 + d / 350.0
		var land: Vector2 = t.p + t.vel * flight + Vector2(randfn(0.0, 1.0), randfn(0.0, 1.0)) * w["disp"] * 0.6
		var n: Node3D = fx.projectile(Color(0.15, 0.15, 0.13), 0.7)
		n.position = mz
		shots.append({"kind": "shell", "n": n, "a": mz, "b": land, "t": 0.0, "T": flight, "w": w, "src": u})
		fx.puff(mz + Vector3.UP, 2.5, 1.5, Color("#9a958b"), 1.5)
		return
	var pr: float = lerpf(w["acc"][0], w["acc"][1], d / w["range"])
	if u.moving:
		pr *= 0.3 if u.small else 0.55
	if t.dug_in:
		pr *= 0.6
	if t.small and world.forest[Nav.k_of(t.p.x, t.p.y)] == 1:
		pr *= 0.55
	if t.air and not w.get("air_only", false):
		pr *= 0.5
	var hit := randf() < pr
	var miss := t.p + Vector2(randfn(0.0, 1.0), randfn(0.0, 1.0)) * 8.0
	var aim := Vector3(t.p.x, t.y + (0.0 if t.air else 1.6), t.p.y) if hit else Vector3(miss.x, ground_y(miss.x, miss.y) + 0.5, miss.y)
	if kind == "tracer" or kind == "heavy":
		fx.tracer(mz, aim, Color(1.0, 0.82, 0.48) if kind == "tracer" else Color(1.0, 0.6, 0.3))
		if hit:
			apply_damage(t, w, u, u.p)
		elif randf() < 0.3:
			fx.puff(aim, 1.0, 0.6, Color("#8a8070"), 1.0)
		return
	var col := Color(0.85, 0.85, 0.8) if kind == "sam" else (Color(1.0, 0.95, 0.7) if kind == "sabot" else Color(0.17, 0.17, 0.15))
	var pn: Node3D = fx.projectile(col, 0.5 if kind == "sabot" else 1.0)
	pn.position = mz
	shots.append({"kind": kind, "n": pn, "pos": mz, "target": t, "hit": hit, "aim": aim, "speed": w["speed"], "w": w, "src": u, "from": u.p, "trail": 0.0})
	if kind != "sabot":
		fx.puff(mz, 1.6, 1.0, Color("#b7b2a8"), 0.5)


func update_shots(dt: float) -> void:
	var keep: Array = []
	for s in shots:
		var n: Node3D = s["n"]
		var src = s["src"] if alive_or_dead(s["src"]) else null
		if s["kind"] == "shell":
			s["t"] += dt
			var f := minf(1.0, s["t"] / s["T"])
			var a: Vector3 = s["a"]
			var b: Vector2 = s["b"]
			var by := ground_y(b.x, b.y)
			n.position = Vector3(lerpf(a.x, b.x, f), lerpf(a.y, by, f) + sin(f * PI) * (40.0 + s["T"] * 18.0), lerpf(a.z, b.y, f))
			if f >= 1.0:
				var w: Dictionary = s["w"]
				fx.explosion(Vector3(b.x, by, b.y), false)
				fx.puff(Vector3(b.x, by + 1.0, b.y), 5.0, 2.4, Color("#5a5348"), 3.0)
				for e in enemies:
					var eu: Unit = e
					if eu.dead or eu.air:
						continue
					var d := eu.p.distance_to(b)
					if d < w["splash"]:
						var w2 := w.duplicate()
						w2["dmg"] = w["dmg"] * (1.0 if d < w["splash"] * 0.4 else 0.5)
						apply_damage(eu, w2, src, b)
				fx.release_projectile(n)
				continue
			keep.append(s)
			continue
		var t = s["target"]
		if s["hit"] and alive(t) and s["kind"] != "sabot":
			var tu: Unit = t
			s["aim"] = Vector3(tu.p.x, tu.y + (0.0 if tu.air else 1.6), tu.p.y)
		var pos: Vector3 = s["pos"]
		var aim: Vector3 = s["aim"]
		var step: float = s["speed"] * dt
		var dv := aim - pos
		var dist := dv.length()
		if s["kind"] in ["missile", "sam", "rocket"]:
			s["trail"] -= dt
			if s["trail"] <= 0.0:
				s["trail"] = 0.04
				fx.puff(pos, 1.3 if s["kind"] == "sam" else 1.0, 0.9, Color("#d9d5cc"), 0.3, 0.5)
		if dist <= step + 1.0:
			if s["hit"] and alive(t):
				apply_damage(t, s["w"], src, s["from"])
				fx.flash(aim, 3.0)
				fx.puff(aim, 2.5, 1.2, Color("#4a4540"), 1.5)
			else:
				fx.explosion(aim, false)
			fx.release_projectile(n)
			continue
		var np := pos + dv / dist * step
		s["pos"] = np
		n.position = np
		if dist > 0.5:
			n.look_at(aim, Vector3.UP if absf(dv.normalized().y) < 0.99 else Vector3.RIGHT)
			n.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		keep.append(s)
	shots = keep


# ================= movement =================

func terrain_factor(u: Unit) -> float:
	var k := Nav.k_of(u.p.x, u.p.y)
	var m: String = u.def["move"]
	var f := 1.0 - world.slope[k] / 70.0
	if world.forest[k] == 1:
		f *= 0.85 if m == "foot" else 0.5
	if world.road[k] == 1 and m != "foot":
		f *= 1.25
	return clampf(f, 0.25, 1.3)


func steer(u: Unit, target: Vector2, dt: float) -> float:
	var to := target - u.p
	var dist := to.length()
	var desired := atan2(to.x, to.y)
	var diff := angle_difference(u.heading, desired)
	var turn := 6.0 if u.small else 1.6
	u.heading += clampf(diff, -turn * dt, turn * dt)
	var sp: float = u.def["speed"] * terrain_factor(u)
	if not u.small and absf(diff) > 1.0:
		sp *= 0.2
	var step := minf(dist, sp * dt)
	var dir := to / dist if (u.small and dist > 0.001) else Vector2(sin(u.heading), cos(u.heading))
	var o := u.p
	var np := u.p + dir * step
	var m: String = u.def["move"]
	if not nav.passable(m, np.x, np.y) and nav.passable(m, o.x, o.y):
		# Slide along water or cliffs instead of stopping dead.
		if nav.passable(m, np.x, o.y):
			np.y = o.y
		elif nav.passable(m, o.x, np.y):
			np.x = o.x
		else:
			np = o
	np.x = clampf(np.x, -WorldGen.HALF + 2.0, WorldGen.HALF - 2.0)
	np.y = clampf(np.y, -WorldGen.HALF + 2.0, WorldGen.HALF - 2.0)
	u.p = np
	u.vel = (u.p - o) / dt if dt > 0.0 else Vector2.ZERO
	return dist


func aim_turret(u: Unit, dt: float) -> void:
	var t: Unit = null
	for e in u.weapons:
		if alive(e["target"]):
			t = e["target"]
			break
	if t == null:
		return
	var desired := atan2(t.p.x - u.p.x, t.p.y - u.p.y)
	if u.tur:
		var rel := angle_difference(0.0, desired - u.heading)
		u.tur_yaw += clampf(angle_difference(u.tur_yaw, rel), -2.0 * dt, 2.0 * dt)
	elif not u.moving and (u.small or u.air):
		u.heading += clampf(angle_difference(u.heading, desired), -3.0 * dt, 3.0 * dt)


func update_weapons(u: Unit, dt: float) -> void:
	u.retarget -= dt
	if u.retarget <= 0.0:
		u.retarget = 0.45 + randf() * 0.2
		acquire(u)
	for e in u.weapons:
		e["cd"] -= dt
		if e["cd"] > 0.0 or not alive(e["target"]):
			continue
		var t: Unit = e["target"]
		var w: Dictionary = e["w"]
		var d := u.p.distance_to(t.p)
		if d > w["range"] * 1.05 or d < w.get("min", 0.0):
			e["target"] = null
			continue
		if u.moving and u.small:
			continue
		if u.tur and not w.get("indirect", false) and w["fx"] != "tracer":
			var rel := angle_difference(0.0, atan2(t.p.x - u.p.x, t.p.y - u.p.y) - u.heading)
			if absf(angle_difference(u.tur_yaw, rel)) > 0.25:
				continue
		fire(u, e)
		e["cd"] = w["rof"] * randf_range(0.9, 1.1)
		if u.dead:
			return


func update_player(u: Unit, dt: float) -> void:
	if u.path.size() > 0:
		var tp: Vector2 = u.path[0]
		var d := steer(u, tp, dt)
		u.moving = true
		u.still_t = 0.0
		u.dug_in = false
		if d < (8.0 if u.path.size() > 1 else 2.0):
			u.path.pop_front()
	else:
		if u.moving:
			u.moving = false
			u.vel = Vector2.ZERO
			threat_dirty = true
		u.still_t += dt
		if not u.dug_in and u.still_t > 6.0:
			u.dug_in = true
			threat_dirty = true
	u.y = ground_y(u.p.x, u.p.y)
	aim_turret(u, dt)
	update_weapons(u, dt)


func update_enemy(u: Unit, dt: float) -> void:
	update_weapons(u, dt)
	if u.dead:
		return
	if u.halt and u.type != "tech":
		u.vel = Vector2.ZERO
		u.moving = false
		u.stuck_t = 0.0
		aim_turret(u, dt)
		u.y = ground_y(u.p.x, u.p.y)
		return
	# Close to the objective, cautious groups stop skirting the defences and press the assault.
	if u.variant == 0 and u.p.distance_to(HQ) < 450.0:
		u.variant = 1
	var key: String = u.def["move"] + str(u.variant)
	var k := Nav.k_of(u.p.x, u.p.y)
	var target := HQ
	var n1 := -1
	if fields.has(key):
		var f: PackedFloat64Array = fields[key]
		if f[k] != INF:
			n1 = Nav.best_neighbor(f, k)
			if n1 >= 0:
				var a := world.cell_center(n1)
				var n2 := Nav.best_neighbor(f, n1)
				var b := world.cell_center(n2) if n2 >= 0 else a
				target = (a + b) * 0.5
	var sep := Vector2.ZERO
	if world.bridge[k] == 0:
		for o in enemies:
			var ou: Unit = o
			if ou == u or ou.air or ou.dead:
				continue
			var dv := u.p - ou.p
			var d2 := dv.length_squared()
			if d2 < 196.0 and d2 > 0.01:
				var d := sqrt(d2)
				sep += dv / d * (14.0 - d)
	var old := u.p
	steer(u, target + sep * 1.5, dt)
	# Wedged against a bank or another vehicle: shuffle straight toward the next cell.
	u.stuck_t = u.stuck_t + dt if old.distance_to(u.p) < u.def["speed"] * dt * 0.15 else 0.0
	if u.stuck_t > 3.0 and n1 >= 0:
		var c := world.cell_center(n1)
		var dv := c - u.p
		var dl := dv.length()
		if dl > 0.01:
			u.p += dv / dl * minf(dl, u.def["speed"] * 0.5 * dt)
			u.heading += clampf(angle_difference(u.heading, atan2(dv.x, dv.y)), -3.0 * dt, 3.0 * dt)
	u.moving = true
	u.y = ground_y(u.p.x, u.p.y)
	aim_turret(u, dt)
	if u.p.distance_to(HQ) < 55.0:
		leak(u)


func update_air(u: Unit, dt: float) -> void:
	if u.type == "drone":
		u.retarget -= dt
		if not alive(u.dtarget) or u.retarget <= 0.0:
			u.retarget = 1.5
			var best: Unit = null
			var bd := 1e9
			for pu in players:
				var pp: Unit = pu
				if pp.dead:
					continue
				var d := u.p.distance_to(pp.p) * (1.8 if pp.small else 1.0)
				if d < bd:
					bd = d
					best = pp
			u.dtarget = best
		var t: Unit = u.dtarget if alive(u.dtarget) else null
		var tp := t.p if t else HQ
		var ty := t.y + 1.5 if t else ground_y(HQ.x, HQ.y) + 2.0
		var hd := u.p.distance_to(tp)
		u.heading = atan2(tp.x - u.p.x, tp.y - u.p.y)
		var o := u.p
		if hd > 1.0:
			u.p += (tp - u.p) / hd * minf(u.def["speed"] * dt, hd)
		var cruise := world.h_at(u.p.x, u.p.y) + u.alt
		u.y = lerpf(ty, cruise, hd / 60.0) if hd < 60.0 else lerpf(u.y, cruise, minf(1.0, dt * 2.0))
		u.vel = (u.p - o) / dt
		if hd < 4.0:
			if t:
				for pu in players:
					var pp: Unit = pu
					if not pp.dead and pp.p.distance_to(u.p) < (99.0 if pp == t else 8.0):
						apply_damage(pp, GameData.DRONE_HIT, u, u.p)
				kill(u, null)
				supply -= int(u.def["reward"])
				kills -= 1
			else:
				leak(u)
		return
	# Helicopter: fly toward the HQ; hover and engage from standoff when it has a shot.
	update_weapons(u, dt)
	if u.dead:
		return
	var o2 := u.p
	if not u.halt:
		var to := HQ - u.p
		u.heading += clampf(angle_difference(u.heading, atan2(to.x, to.y)), -dt, dt)
		u.p += Vector2(sin(u.heading), cos(u.heading)) * u.def["speed"] * dt
		if to.length() < 60.0:
			leak(u)
			return
	else:
		aim_turret(u, dt)
	var hover_y := maxf(world.h_at(u.p.x, u.p.y), WorldGen.WATER_Y) + u.alt + sin(Time.get_ticks_msec() / 700.0 + u.uid) * 1.5
	u.y = lerpf(u.y, hover_y, minf(1.0, dt * 1.5))
	u.vel = (u.p - o2) / dt


func leak(u: Unit) -> void:
	if u.dead:
		return
	u.dead = true
	integrity = maxi(0, integrity - int(u.def["leak"]))
	fx.explosion(Vector3(HQ.x + randf_range(-15, 15), ground_y(HQ.x, HQ.y), HQ.y + randf_range(-15, 15)), true)
	log_msg("%s broke through to the HQ. −%d integrity." % [u.def["name"], u.def["leak"]], "bad")
	u.visible = false
	u.queue_free()


func update_spotting() -> void:
	var hq_eye := Vector3(HQ.x, ground_y(HQ.x, HQ.y) + 18.0, HQ.y)
	for e in enemies:
		var eu: Unit = e
		if eu.dead:
			continue
		eu.spotted = false
		for pu in players:
			var pp: Unit = pu
			if not pp.dead and pp.p.distance_to(eu.p) < 750.0 and can_see(Vector3(pp.p.x, pp.y + 2.5, pp.p.y), eu):
				eu.spotted = true
				break
		if not eu.spotted and HQ.distance_to(eu.p) < 650.0 and can_see(hq_eye, eu):
			eu.spotted = true


# ================= waves =================

func send_wave() -> void:
	# Waves can be called early: a new wave's groups are queued behind whatever is still arriving.
	if over != "" or wave >= GameData.WAVES.size():
		return
	var groups: Array = GameData.WAVES[wave]
	wave += 1
	if not wave_active:
		wave_t = 0.0
	wave_active = true
	var t := wave_t
	var names: Array = []
	for g in groups:
		var s := randi() % 3
		var v := 0 if randf() < 0.6 else 1
		for i in int(g[1]):
			queue.append({"t": t + i * 2.5, "type": g[0], "s": s, "v": v})
		t += 8.0
		names.append("%d× %s" % [g[1], GameData.DEFS[g[0]]["name"]])
	queue.sort_custom(func(a, b): return a["t"] < b["t"])
	log_msg("Wave %d: %s." % [wave, ", ".join(names)], "warn")


func spawn_enemy(q: Dictionary) -> void:
	var d: Dictionary = GameData.DEFS[q["type"]]
	var pos: Vector2 = SPAWNS[q["s"]] + Vector2(randf_range(-15, 15), randf_range(-25, 25))
	if d.get("air", false):
		pos = Vector2(-WorldGen.HALF + 5.0, pos.y + randf_range(-80, 80))
	else:
		var k := nav.nearest_passable(d["move"], Nav.k_of(pos.x, pos.y))
		if k >= 0:
			pos = world.cell_center(k)
	var u := make_unit(q["type"], "e", pos)
	u.variant = q["v"]
	enemies.append(u)


func wave_cleared() -> void:
	wave_active = false
	if wave >= GameData.WAVES.size():
		end_level(true)
		return
	var bonus := 120 + 30 * wave
	supply += bonus
	log_msg("Wave %d defeated. +%d supply." % [wave, bonus], "good")


func end_level(won: bool) -> void:
	if over != "":
		return
	over = "won" if won else "lost"
	if won:
		hud.show_end("Hollow Valley held", "All %d waves defeated with %d HQ integrity left. %d enemy destroyed, %d units lost." % [GameData.WAVES.size(), integrity, kills, lost])
	else:
		hud.show_end("Hollow Valley lost", "The command post fell during wave %d. Cover the avenues of approach before sending the next wave." % wave)


# ================= main loop =================

func step(dt: float) -> void:
	if wave_active:
		wave_t += dt
		while queue.size() > 0 and queue[0]["t"] <= wave_t:
			spawn_enemy(queue.pop_front())
	spot_t -= dt
	if spot_t <= 0.0:
		spot_t = 0.8
		update_spotting()
	for u in players:
		if not (u as Unit).dead:
			update_player(u, dt)
	for u in enemies:
		var eu: Unit = u
		if eu.dead:
			continue
		if eu.air:
			update_air(eu, dt)
		else:
			update_enemy(eu, dt)
	update_shots(dt)
	for w in wrecks:
		var wu: Unit = w
		wu.wreck_t -= dt
		wu.smoke_t -= dt
		if wu.smoke_t <= 0.0 and wu.wreck_t > 20.0:
			wu.smoke_t = 0.45
			fx.puff(Vector3(wu.p.x + randf_range(-1, 1), wu.y + 3.0, wu.p.y), 2.5, 4.0, Color("#2f2c29"), 3.5, 0.45)
		if wu.wreck_t <= 0.0:
			wu.queue_free()
	wrecks = wrecks.filter(func(x): return (x as Unit).wreck_t > 0.0)
	players = players.filter(func(x): return not (x as Unit).dead)
	enemies = enemies.filter(func(x): return not (x as Unit).dead)
	if wave_active and queue.is_empty() and enemies.is_empty():
		wave_cleared()
	if integrity <= 0:
		end_level(false)


func _process(delta: float) -> void:
	if world == null:
		return
	if not paused and over == "":
		var sim := delta * speed
		while sim > 0.0001:
			var s := minf(0.05, sim)
			step(s)
			sim -= s
	fx.update(0.0 if paused else delta * speed)
	nav_cooldown -= delta
	if nav_task != -1 and WorkerThreadPool.is_task_completed(nav_task):
		WorkerThreadPool.wait_for_task_completion(nav_task)
		nav_task = -1
		threat = nav_result[0]
		fields = nav_result[1]
		update_avenues()
	if threat_dirty and nav_task == -1 and nav_cooldown <= 0.0:
		threat_dirty = false
		nav_cooldown = 1.0
		_start_nav()
	for u in players + enemies:
		sync_unit(u, 0.0 if paused else delta * speed)
	if not order_mark.is_empty():
		order_mark["t"] += delta


func _start_nav() -> void:
	var snap: Array = []
	for u in players:
		var pu: Unit = u
		if pu.dead or pu.moving:
			continue
		var ws: Array = []
		for e in pu.weapons:
			ws.append(e["w"])
		snap.append({"pos": Vector3(pu.p.x, pu.y + 2.5, pu.p.y), "dug": pu.dug_in, "weapons": ws})
	nav_task = WorkerThreadPool.add_task(_nav_job.bind(snap), false, "kestrel nav")


func _nav_job(snap: Array) -> void:
	var th := Nav.compute_threat(world, snap)
	nav_result = [th, Nav.compute_fields(nav.cost, th, nav.goal_cells)]


# ================= avenues and rings (terrain-following ribbons) =================

func _ribbon(im: ImmediateMesh, pts: PackedVector2Array, width: float, col: Color, dashed: bool, lift: float) -> void:
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	var run := 0.0
	var any := false
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		run += a.distance_to(b)
		if dashed and int(run / 7.0) % 2 == 1:
			continue
		var n := (b - a).orthogonal().normalized() * width * 0.5
		var al := Vector3(a.x + n.x, world.h_at(a.x, a.y) + lift, a.y + n.y)
		var ar := Vector3(a.x - n.x, world.h_at(a.x, a.y) + lift, a.y - n.y)
		var bl := Vector3(b.x + n.x, world.h_at(b.x, b.y) + lift, b.y + n.y)
		var br := Vector3(b.x - n.x, world.h_at(b.x, b.y) + lift, b.y - n.y)
		for v in [al, ar, bl, ar, br, bl]:
			im.surface_set_color(col)
			im.surface_add_vertex(v)
		any = true
	if not any:
		for v in [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]:
			im.surface_set_color(Color(0, 0, 0, 0))
			im.surface_add_vertex(v)
	im.surface_end()


func update_avenues() -> void:
	avenues.clear()
	_avenue_im.clear_surfaces()
	for s in SPAWNS:
		for m in ["foot", "track"]:
			var f: PackedFloat64Array = fields[m + "0"]
			var k := nav.nearest_passable(m, Nav.k_of(s.x, s.y))
			var pts := PackedVector2Array()
			for i in 400:
				if k < 0:
					break
				pts.append(world.cell_center(k))
				var nk := Nav.best_neighbor(f, k)
				if nk < 0:
					break
				k = nk
			if pts.size() < 3:
				continue
			pts = WorldGen.chaikin(pts, 3)
			avenues.append({"move": m, "pts": pts})
			if show_avenues:
				_ribbon(_avenue_im, pts, 2.2 if m == "track" else 1.4, Color(0.75, 0.15, 0.1, 0.85) if m == "track" else Color(0.95, 0.35, 0.28, 0.85), m == "foot", 2.5)


func _circle(c: Vector2, r: float, step: float = 0.02) -> Array:
	var out: Array = []
	var seg := PackedVector2Array()
	var a := 0.0
	while a <= TAU + 0.01:
		var p := c + Vector2(cos(a), sin(a)) * r
		if absf(p.x) < WorldGen.HALF - 2.0 and absf(p.y) < WorldGen.HALF - 2.0:
			seg.append(p)
		else:
			if seg.size() > 1:
				out.append(seg)
			seg = PackedVector2Array()
		a += step
	if seg.size() > 1:
		out.append(seg)
	return out


func _draw_deploy_ring() -> void:
	_ring_im.clear_surfaces()
	for seg in _circle(HQ, GameData.DEPLOY_R):
		_ribbon(_ring_im, seg, 1.6, Color(0.45, 0.73, 0.93, 0.7), true, 2.0)


# ================= player commands =================

func place_check(t: String, p: Vector2) -> String:
	var d: Dictionary = GameData.DEFS[t]
	if absf(p.x) > WorldGen.HALF - 10.0 or absf(p.y) > WorldGen.HALF - 10.0:
		return "Outside the sector."
	if p.distance_to(HQ) > GameData.DEPLOY_R:
		return "Deploy inside the blue ring."
	if p.distance_to(HQ) < 50.0:
		return "Too close to the HQ."
	if not nav.passable(d["move"], p.x, p.y):
		return "Ground is impassable for this unit."
	for u in players:
		if not (u as Unit).dead and (u as Unit).p.distance_to(p) < 12.0:
			return "Too close to another unit."
	if supply < d["cost"]:
		return "Need %d supply." % d["cost"]
	return ""


func set_build(t: String) -> void:
	if over != "":
		return
	build_type = "" if build_type == t else t
	if ghost:
		ghost.queue_free()
		ghost = null
	_range_im.clear_surfaces()
	if build_type != "":
		var m := UnitModels.build(build_type, "p", world.biome)
		ghost = m["root"]
		add_child(ghost)
		ghost.visible = false


func update_ghost(g) -> void:
	if ghost == null:
		return
	_range_im.clear_surfaces()
	if g == null:
		ghost.visible = false
		return
	var p: Vector2 = g
	ghost_err = place_check(build_type, p)
	ghost_ok = ghost_err == ""
	ghost.visible = true
	ghost.position = Vector3(p.x, ground_y(p.x, p.y), p.y)
	ghost.rotation.y = -PI / 2.0
	for n in ghost.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = _ghost_ok_mat if ghost_ok else _ghost_bad_mat
	var r := 0.0
	for k in GameData.DEFS[build_type]["weapons"]:
		r = maxf(r, GameData.WEAP[k]["range"])
	for seg in _circle(p, r, 0.04):
		_ribbon(_range_im, seg, 1.2, Color(0.45, 0.73, 0.93, 0.9) if ghost_ok else Color(0.9, 0.35, 0.3, 0.9), false, 2.5)


func place_unit(p: Vector2, keep_building: bool) -> void:
	var err := place_check(build_type, p)
	if err != "":
		log_msg(err, "warn")
		return
	var u := make_unit(build_type, "p", p)
	supply -= int(GameData.DEFS[build_type]["cost"])
	players.append(u)
	threat_dirty = true
	selection = [u]
	if not keep_building or supply < GameData.DEFS[build_type]["cost"]:
		set_build("")


func order_move(target: Vector2) -> void:
	var units: Array = selection.filter(func(x): return alive(x) and (x as Unit).side == "p")
	if units.is_empty():
		return
	var n := units.size()
	var cols := ceili(sqrt(n))
	var centre := Vector2.ZERO
	for u in units:
		centre += (u as Unit).p
	centre /= n
	var fwd := (target - centre).normalized()
	if fwd == Vector2.ZERO:
		fwd = Vector2.LEFT
	var right := fwd.orthogonal()
	for i in n:
		var u: Unit = units[i]
		var c := i % cols - (cols - 1) / 2.0
		var r := i / cols
		var dest := target + right * c * 16.0 - fwd * r * 16.0
		var path := nav.route(u.def["move"], u.p, dest)
		if path.is_empty():
			log_msg("%s can't find a route there." % u.def["name"], "warn")
			continue
		u.path = path
		u.still_t = 0.0
	order_mark = {"p": target, "t": 0.0}


func withdraw() -> void:
	var units: Array = selection.filter(func(x): return alive(x) and (x as Unit).side == "p")
	if units.is_empty():
		return
	for u in units:
		var pu: Unit = u
		supply += int(pu.invested * 0.5)
		pu.dead = true
		pu.queue_free()
	log_msg("Withdrew %d unit%s. Half the supply came back." % [units.size(), "" if units.size() == 1 else "s"], "warn")
	selection.clear()
	threat_dirty = true


# ================= input =================

func pick_ground(screen: Vector2):
	var cam: Camera3D = rig.cam
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var prev := 0.0
	var t := 2.0
	while t < 4000.0:
		var p := o + d * t
		if p.y < world.h_at(p.x, p.z) and absf(p.x) < 700.0 and absf(p.z) < 700.0:
			var a := prev
			var b := t
			for i in 10:
				var m := (a + b) * 0.5
				var q := o + d * m
				if q.y < world.h_at(q.x, q.z):
					b = m
				else:
					a = m
			var r := o + d * b
			if absf(r.x) > WorldGen.HALF or absf(r.z) > WorldGen.HALF:
				return null
			return Vector2(r.x, r.z)
		prev = t
		t += 3.0
	return null


func screen_of(u: Unit, lift: float = 2.0):
	var cam: Camera3D = rig.cam
	var w := Vector3(u.p.x, u.y + lift, u.p.y)
	if cam.is_position_behind(w):
		return null
	return cam.unproject_position(w)


func pick_unit(screen: Vector2) -> Unit:
	var best: Unit = null
	var bd := 26.0
	for u in players + enemies:
		var uu: Unit = u
		if uu.dead:
			continue
		var s = screen_of(uu)
		if s == null:
			continue
		var d: float = (s as Vector2).distance_to(screen) - (4.0 if uu.side == "p" else 0.0)
		if d < bd:
			bd = d
			best = uu
	return best


func _unhandled_input(ev: InputEvent) -> void:
	if world == null:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				drag = {"button": mb.button_index, "start": mb.position, "cur": mb.position, "moved": false, "shift": mb.shift_pressed}
				if mb.button_index == MOUSE_BUTTON_LEFT and not mb.shift_pressed:
					rig.grab_start(mb.position, pick_ground(mb.position))
			elif not drag.is_empty() and drag["button"] == mb.button_index:
				_release(mb.position, mb.shift_pressed)
				drag = {}
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		hover = mm.position
		if build_type != "":
			update_ghost(pick_ground(mm.position))
		if not drag.is_empty():
			var delta: Vector2 = mm.position - drag["cur"]
			drag["cur"] = mm.position
			if mm.position.distance_to(drag["start"]) > 6.0:
				drag["moved"] = true
			# Left-drag pans, right-drag rotates; Shift + left-drag draws a selection box instead.
			if drag["moved"] and drag["button"] == MOUSE_BUTTON_RIGHT:
				rig.rotate_by(delta.x)
			elif drag["moved"] and drag["button"] == MOUSE_BUTTON_LEFT and not drag["shift"]:
				rig.grab_move(mm.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_5:
			set_build(GameData.PLAYER_KEYS[k - KEY_1])
		elif k == KEY_ESCAPE:
			set_build("")
			selection.clear()
			inspect = null
		elif k == KEY_SPACE:
			send_wave()
		elif k == KEY_T:
			toggle_avenues()
		elif k == KEY_P:
			paused = not paused
		elif k == KEY_X or k == KEY_DELETE:
			withdraw()
		elif k == KEY_H:
			rig.target = Vector3(HQ.x - 120.0, 0.0, HQ.y)


func _release(pos: Vector2, shift: bool) -> void:
	if drag["button"] == MOUSE_BUTTON_LEFT and drag["moved"] and drag["shift"] and build_type == "":
		var r := Rect2(drag["start"], Vector2.ZERO).expand(pos)
		selection.clear()
		for u in players:
			var s = screen_of(u)
			if s != null and r.has_point(s):
				selection.append(u)
		inspect = null
		return
	if drag["moved"]:
		return
	var g = pick_ground(pos)
	if drag["button"] == MOUSE_BUTTON_RIGHT:
		if build_type != "":
			set_build("")
		elif g != null and not selection.is_empty():
			order_move(g)
		return
	if build_type != "":
		if g != null:
			place_unit(g, shift)
		return
	var u := pick_unit(pos)
	if u != null and u.side == "p":
		if not shift:
			selection.clear()
		if u in selection:
			selection.erase(u)
		else:
			selection.append(u)
		inspect = null
	elif u != null:
		inspect = u
		selection.clear()
	else:
		selection.clear()
		inspect = null


func toggle_avenues() -> void:
	show_avenues = not show_avenues
	update_avenues()


func cycle_speed() -> void:
	speed = 2.0 if speed == 1.0 else (4.0 if speed == 2.0 else 1.0)
