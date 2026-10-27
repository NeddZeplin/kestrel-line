extends Node3D
## Pooled combat effects: tracers, projectiles, muzzle flashes, explosions (with a brief light) and smoke.

var _free := {"puff": [], "fire": [], "tracer": [], "proj": [], "light": []}
var _live: Array = []
var _sphere := SphereMesh.new()
var _tracer_mesh := BoxMesh.new()
var _proj_mesh := CylinderMesh.new()


func _ready() -> void:
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 10
	_sphere.rings = 6
	_tracer_mesh.size = Vector3(0.09, 0.09, 1.0)
	_proj_mesh.top_radius = 0.12
	_proj_mesh.bottom_radius = 0.12
	_proj_mesh.height = 1.4
	_proj_mesh.radial_segments = 6


func _take(kind: String) -> Node3D:
	var pool: Array = _free[kind]
	if pool.size() > 0:
		var n: Node3D = pool.pop_back()
		n.visible = true
		return n
	var n: Node3D
	match kind:
		"light":
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.7, 0.35)
			l.omni_range = 30.0
			l.shadow_enabled = false
			n = l
		_:
			var mi := MeshInstance3D.new()
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			match kind:
				"puff":
					mi.mesh = _sphere
					m.roughness = 1.0
				"fire":
					mi.mesh = _sphere
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.albedo_color = Color(1.0, 0.68, 0.3)
				"tracer":
					mi.mesh = _tracer_mesh
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				"proj":
					mi.mesh = _proj_mesh
					m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
			n = mi
	add_child(n)
	return n


func _release(kind: String, n: Node3D) -> void:
	n.visible = false
	(_free[kind] as Array).append(n)


func _mat(n: Node3D) -> StandardMaterial3D:
	return (n as MeshInstance3D).material_override as StandardMaterial3D


func puff(pos: Vector3, size: float, life: float, color: Color, rise: float = 2.0, opacity: float = 0.55) -> void:
	var n := _take("puff")
	n.position = pos
	n.scale = Vector3.ONE * size * 0.5
	var m := _mat(n)
	m.albedo_color = Color(color, opacity)
	var drift := Vector3(randf_range(-0.8, 0.8), rise, randf_range(-0.8, 0.8))
	_live.append({"kind": "puff", "n": n, "t": 0.0, "T": life, "size": size, "v": drift, "op": opacity})


func flash(pos: Vector3, size: float) -> void:
	var n := _take("fire")
	n.position = pos
	n.scale = Vector3.ONE * size * 0.3
	_mat(n).albedo_color = Color(1.0, 0.7, 0.3, 1.0)
	_live.append({"kind": "fire", "n": n, "t": 0.0, "T": 0.08 + size * 0.03, "size": size})


func explosion(pos: Vector3, big: bool) -> void:
	var n := _take("fire")
	n.position = pos + Vector3.UP
	n.scale = Vector3.ONE * 0.5
	_mat(n).albedo_color = Color(1.0, 0.62, 0.25, 1.0)
	_live.append({"kind": "fire", "n": n, "t": 0.0, "T": 0.55 if big else 0.3, "size": 10.0 if big else 4.5})
	var l := _take("light") as OmniLight3D
	l.position = pos + Vector3.UP * 3.0
	l.light_energy = 6.0 if big else 2.5
	_live.append({"kind": "light", "n": l, "t": 0.0, "T": 0.35, "e": l.light_energy})
	for i in (7 if big else 3):
		var c := Color("#2e2b28") if big else Color("#6d665c")
		puff(pos + Vector3(randf_range(-2, 2), 1.0 + randf() * 2.0, randf_range(-2, 2)), randf_range(5.0, 9.0) if big else randf_range(2.5, 4.5), randf_range(3.0, 5.0) if big else 1.6, c, 4.0 if big else 2.0)


func tracer(a: Vector3, b: Vector3, color: Color) -> void:
	var n := _take("tracer")
	var d := a.distance_to(b)
	if d < 0.5:
		_release("tracer", n)
		return
	n.position = (a + b) * 0.5
	n.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	n.scale = Vector3(1, 1, d)
	_mat(n).albedo_color = Color(color, 1.0)
	_live.append({"kind": "tracer", "n": n, "t": 0.0, "T": 0.09})


func projectile(color: Color, scale: float) -> Node3D:
	var n := _take("proj")
	n.scale = Vector3.ONE * scale
	_mat(n).albedo_color = color
	return n


func release_projectile(n: Node3D) -> void:
	_release("proj", n)


func clear() -> void:
	for e in _live:
		_release(e["kind"], e["n"])
	_live.clear()


func update(dt: float) -> void:
	var keep: Array = []
	for e in _live:
		e["t"] += dt
		var k: float = e["t"] / e["T"]
		var n: Node3D = e["n"]
		match e["kind"]:
			"puff":
				n.position += (e["v"] as Vector3) * dt
				n.scale = Vector3.ONE * e["size"] * (0.5 + k * 0.8)
				var m := _mat(n)
				m.albedo_color.a = e["op"] * (1.0 - k)
			"fire":
				n.scale = Vector3.ONE * e["size"] * (0.3 + k * 0.7)
				_mat(n).albedo_color.a = 1.0 - k
			"tracer":
				_mat(n).albedo_color.a = 1.0 - k
			"light":
				(n as OmniLight3D).light_energy = e["e"] * (1.0 - k)
		if k >= 1.0:
			_release(e["kind"], n)
		else:
			keep.append(e)
	_live = keep
