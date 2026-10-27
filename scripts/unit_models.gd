class_name UnitModels
extends RefCounted
## Unit visuals. Tanks, Humvees, the helicopter and the mortar come from the ithappy pack;
## soldiers, the IFV and the drone are built here, using the pack's camouflage textures.

const PACK := "res://ithappy/military_free/prefabs/assets/"
## Vehicle camouflage per biome (tools/make_camo.py). Enemy vehicles wear it darker and greyer.
const CAMO := {"temperate": "res://textures/camo/woodland.png", "desert": "res://textures/camo/desert.png", "winter": "res://textures/camo/winter.png"}
const ENEMY_TINT := Color(0.58, 0.62, 0.58)
const UNIFORM := {
	"temperate": [Color("#5b6338"), Color("#4d4f47")],
	"desert": [Color("#a8956a"), Color("#8a8068")],
	"winter": [Color("#c9cdc8"), Color("#8e918b")],
}

static var _mats := {}
static var _enemy_cache := {}
static var _paint_cache := {}


static func mat(key: String, color: Color, tex: String = "", rough: float = 0.85) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if tex != "":
		m.albedo_texture = load(tex)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mats[key] = m
	return m


static func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func cyl(r0: float, r1: float, h: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func prefab(path: String) -> Node3D:
	return (load(PACK + path) as PackedScene).instantiate()


## Returns {"root", "tur", "rotors", "tail", "men", "berm"}.
static func build(type: String, side: String, biome: String = "temperate") -> Dictionary:
	var d: Dictionary = GameData.DEFS[type]
	var out := {"root": Node3D.new(), "tur": null, "rotors": [], "tail": null, "men": [], "berm": null}
	var root: Node3D = out["root"]
	match d["model"]:
		"tank":
			var t := prefab("vehicles/tank_006.tscn")
			t.scale = Vector3.ONE * 1.15
			root.add_child(t)
			out["tur"] = t.find_child("tank_tower_006", true, false)
			out["berm"] = part(root, box(5.4, 1.5, 1.6), mat("earth", Color("#6e5b3e")), Vector3(0, 0.55, 5.6))
		"technical", "shorad":
			var h := prefab("vehicles/hummer_003.tscn")
			h.scale = Vector3.ONE * 1.3
			root.add_child(h)
			var tur := Node3D.new()
			tur.position = Vector3(0, 2.35, -0.6)
			root.add_child(tur)
			out["tur"] = tur
			if d["model"] == "technical":
				var mg := prefab("vehicles/machine_gun_004.tscn")
				mg.scale = Vector3.ONE * 1.3
				tur.add_child(mg)
			else:
				var metal := mat("metal", Color("#3d4038"), "", 0.6)
				part(tur, cyl(0.7, 0.75, 0.35, 10), metal, Vector3(0, 0.15, 0))
				part(tur, box(0.85, 0.7, 0.85), mat("shorad", Color("#6b6449")), Vector3(0, 0.65, 0))
				for x in [-0.9, 0.9]:
					part(tur, box(0.5, 0.6, 1.6), metal, Vector3(x, 0.8, 0.2), Vector3(-0.2, 0, 0))
				part(tur, box(1.1, 0.6, 0.08), mat("dark", Color("#22241f")), Vector3(0, 1.35, -0.45))
				out["berm"] = part(root, box(4.0, 1.3, 1.3), mat("earth", Color("#6e5b3e")), Vector3(0, 0.5, 4.2))
		"helo":
			var h := prefab("vehicles/helicopter_001.tscn")
			h.position.y = -1.8
			root.add_child(h)
			var r := h.find_child("blade_001", true, false)
			if r:
				out["rotors"] = [r]
			out["tail"] = h.find_child("blade_002", true, false)
		"ifv":
			out["tur"] = _ifv(root, side, biome)
		"drone":
			var grey := mat("drone", Color("#8a8f88"), "", 0.5)
			part(root, cyl(0.22, 0.14, 2.6, 8), grey, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
			part(root, box(3.4, 0.06, 0.55), grey, Vector3(0, 0, 0.1))
			part(root, box(1.2, 0.06, 0.35), grey, Vector3(0, 0, -1.1))
			part(root, box(0.06, 0.5, 0.35), grey, Vector3(0, 0.25, -1.15))
		"squad", "atgm_team", "mortar_team":
			_infantry(out, d, side, biome)
	if d["model"] in ["tank", "technical", "shorad", "helo"]:
		paint(root, biome, side)
	if out["berm"]:
		(out["berm"] as Node3D).visible = false
	return out


static func _ifv(root: Node3D, side: String, biome: String) -> Node3D:
	var camo := mat("camo_%s_%s" % [biome, side], Color(1, 1, 1) if side == "p" else ENEMY_TINT, CAMO.get(biome, CAMO["temperate"]))
	var dark := mat("dark", Color("#22241f"))
	var metal := mat("metal", Color("#3d4038"), "", 0.6)
	part(root, box(3.3, 1.6, 6.6), camo, Vector3(0, 1.55, -0.1))
	part(root, box(3.3, 0.9, 1.4), camo, Vector3(0, 1.5, 3.55), Vector3(0.55, 0, 0))
	for x in [-1.65, 1.65]:
		part(root, box(0.75, 1.05, 7.0), dark, Vector3(x, 0.55, 0))
		for z in [-2.6, -1.3, 0.0, 1.3, 2.6]:
			part(root, cyl(0.42, 0.42, 0.3, 10), dark, Vector3(x * 1.02, 0.45, z), Vector3(0, 0, PI / 2.0))
	var tur := Node3D.new()
	tur.position = Vector3(0, 2.35, 0.5)
	root.add_child(tur)
	part(tur, box(1.6, 0.65, 1.9), camo, Vector3(0, 0.32, 0))
	part(tur, cyl(0.07, 0.06, 2.8, 6), metal, Vector3(0, 0.38, 2.2), Vector3(PI / 2.0, 0, 0))
	part(tur, box(0.38, 0.38, 1.4), metal, Vector3(1.0, 0.5, 0))
	if side == "e":
		for x in [-1.67, 1.67]:
			part(root, box(0.04, 0.5, 1.3), mat("idstripe", Color("#eeeeea")), Vector3(x, 1.7, -1.0))
	return tur


static func _soldier(parent: Node3D, side: String, pos: Vector3, long_gun: bool, biome: String) -> Node3D:
	var s := Node3D.new()
	s.position = pos
	parent.add_child(s)
	var cols: Array = UNIFORM.get(biome, UNIFORM["temperate"])
	var uniform := mat("uniform_%s_%s" % [biome, side], cols[0] if side == "p" else cols[1])
	var dark := mat("dark", Color("#22241f"))
	part(s, box(0.36, 0.8, 0.26), uniform, Vector3(0, 0.4, 0))
	part(s, box(0.52, 0.62, 0.32), uniform, Vector3(0, 1.11, 0))
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	part(s, head, mat("skin", Color("#b8916e")), Vector3(0, 1.56, 0))
	var helm := SphereMesh.new()
	helm.radius = 0.2
	helm.height = 0.28
	part(s, helm, uniform, Vector3(0, 1.62, 0))
	part(s, box(0.07, 0.07, 1.15 if long_gun else 0.85), dark, Vector3(0.2, 1.12, 0.35))
	return s


static func _infantry(out: Dictionary, d: Dictionary, side: String, biome: String) -> void:
	var root: Node3D = out["root"]
	var g := Node3D.new()
	g.scale = Vector3.ONE * 1.35
	root.add_child(g)
	var men: Array = []
	match d["model"]:
		"squad":
			for e in [[0.0, 1.6, true], [-2.0, -0.4, false], [2.0, -0.4, false], [0.0, -2.4, false]]:
				men.append(_soldier(g, side, Vector3(e[0], 0, e[1]), e[2], biome))
		"atgm_team":
			men = [_soldier(g, side, Vector3(-1.0, 0, -0.6), false, biome), _soldier(g, side, Vector3(1.2, 0, -1.2), false, biome)]
			part(g, cyl(0.13, 0.13, 1.5, 8), mat("launcher", Color("#4f5640")), Vector3(0, 0.95, 1.4), Vector3(PI / 2.0 - 0.08, 0, 0))
			part(g, box(0.3, 0.25, 0.3), mat("dark", Color("#22241f")), Vector3(0.22, 0.95, 1.0))
		"mortar_team":
			men = [_soldier(g, side, Vector3(-1.4, 0, 0.2), false, biome), _soldier(g, side, Vector3(1.3, 0, -0.8), false, biome)]
			var m := prefab("decorations/mortar_001.tscn")
			m.position = Vector3(0, 0, 0.4)
			m.scale = Vector3.ONE * 1.2
			g.add_child(m)
	out["men"] = men
	# Sandbag ring, shown once the team has dug in.
	var ring := Node3D.new()
	g.add_child(ring)
	var bag := mat("sandbag", Color("#8f7f5b"))
	for i in range(1, 12):
		var a := i / 12.0 * TAU
		part(ring, box(1.1, 0.5, 0.55), bag, Vector3(sin(a) * 3.4, 0.25, cos(a) * 3.4), Vector3(0, a, 0))
	out["berm"] = ring


## Repaint the pack's vehicles in the biome's camouflage (see shaders/vehicle_paint.gdshader).
static func paint(root: Node, biome: String, side: String) -> void:
	var camo: Texture2D = load(CAMO.get(biome, CAMO["temperate"]))
	var shader: Shader = load("res://shaders/vehicle_paint.gdshader")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var key := "%d|%s|%s" % [src.get_instance_id(), biome, side]
			if not _paint_cache.has(key):
				var is_camo := "amouflage" in src.resource_name or "amouflage" in src.albedo_texture.resource_path
				var m := ShaderMaterial.new()
				m.shader = shader
				m.set_shader_parameter("base_tex", src.albedo_texture)
				m.set_shader_parameter("camo_tex", camo)
				m.set_shader_parameter("force", 1.0 if is_camo else 0.0)
				m.set_shader_parameter("tint", Color(1, 1, 1) if side == "p" else ENEMY_TINT)
				_paint_cache[key] = m
			mi.set_surface_override_material(s, _paint_cache[key])


## Darker, greyer copies of the pack's materials so enemy vehicles read differently from yours.
static func enemy_tint(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src == null or not (src is StandardMaterial3D):
				continue
			var key := src.get_instance_id()
			if not _enemy_cache.has(key):
				var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = dup.albedo_color * Color(0.55, 0.6, 0.55)
				_enemy_cache[key] = dup
			mi.set_surface_override_material(s, _enemy_cache[key])


static func char_out(root: Node) -> void:
	var burnt := mat("burnt", Color("#1d1b19"), "", 1.0)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = burnt
