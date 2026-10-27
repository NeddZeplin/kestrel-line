extends Node3D
## Trees, bushes, grass and rocks as chunked MultiMeshes, built from CC0 photo foliage cards
## (ambientCG leaves, needles, grass blades; composed by tools/compose_foliage.py) and bark textures.
## Each chunk is culled by distance; trees swap to a simple far version beyond TREE_NEAR.

const TREE_CHUNK := 120.0
const GRASS_CHUNK := 60.0
const TREE_NEAR := 650.0
const GRASS_RANGE := 130.0
const BUSH_RANGE := 600.0

var world: WorldGen
var rng := RandomNumberGenerator.new()


func build(w: WorldGen) -> void:
	world = w
	rng.seed = 99
	var needles := _card_mat("res://textures/foliage/pine_spray.png", 0.42)
	var leaves := _card_mat("res://textures/foliage/oak_spray.png", 0.45)
	var pine := _pine(needles, _bark_mat("fir"))
	var oak := _oak(leaves, _bark_mat("oak"))
	var pine_far := _far(true)
	var oak_far := _far(false)

	var pines := {}
	var oaks := {}
	var bushes := {}
	var rocks := {}
	var grass := {}
	for k in WorldGen.G * WorldGen.G:
		var c := w.cell_center(k)
		var dhq := c.distance_to(WorldGen.HQ)
		if w.forest[k] == 1:
			for n in 2:
				var p := _jitter(c)
				var s := rng.randf_range(0.8, 1.35)
				_add(pines if rng.randf() < 0.55 else oaks, p, TREE_CHUNK, _xf(p, s, rng.randf() * TAU, rng.randf_range(0.9, 1.15)), _tint(0.82, 1.1))
			if rng.randf() < 0.35:
				var p := _jitter(c)
				_add(bushes, p, TREE_CHUNK, _xf(p, rng.randf_range(0.7, 1.2), rng.randf() * TAU, 0.8, -0.15), _tint(0.75, 0.95))
			continue
		if w.slope[k] > 26.0 and rng.randf() < 0.6:
			var p := _jitter(c)
			var s := rng.randf_range(1.0, 3.0)
			_add(rocks, p, TREE_CHUNK, Transform3D(Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * TAU, rng.randf() * 3.0)).scaled(Vector3(s * 1.3, s * 0.7, s)), Vector3(p.x, w.h_at(p.x, p.y) + s * 0.1, p.y)), _tint(0.8, 1.05))
		var open := w.road[k] == 0 and w.water[k] == 0 and w.bridge[k] == 0 and w.slope[k] < 24.0 and dhq > 45.0
		if not open:
			continue
		var edge := w.forest[mini(k + 1, w.forest.size() - 1)] == 1 or w.forest[maxi(k - 1, 0)] == 1 or w.forest[mini(k + WorldGen.G, w.forest.size() - 1)] == 1 or w.forest[maxi(k - WorldGen.G, 0)] == 1
		if rng.randf() < (0.5 if edge else 0.04):
			var p := _jitter(c)
			_add(bushes, p, TREE_CHUNK, _xf(p, rng.randf_range(0.8, 1.5), rng.randf() * TAU, 0.8, -0.15), _tint(0.8, 1.05))
		if rng.randf() < 0.05:
			var p := _jitter(c)
			var s := rng.randf_range(0.4, 1.2)
			_add(rocks, p, TREE_CHUNK, Transform3D(Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * TAU, 0.0)).scaled(Vector3(s * 1.2, s * 0.6, s)), Vector3(p.x, w.h_at(p.x, p.y), p.y)), _tint(0.8, 1.05))
		for n in 70:
			var p := _jitter(c)
			_add(grass, p, GRASS_CHUNK, _xf(p, rng.randf_range(0.4, 0.85), rng.randf() * TAU), _tint(0.82, 1.12))

	_emit(pines, pine, 0.0, TREE_NEAR, true)
	_emit(pines, pine_far, TREE_NEAR, 0.0, true)
	_emit(oaks, oak, 0.0, TREE_NEAR, true)
	_emit(oaks, oak_far, TREE_NEAR, 0.0, true)
	_emit(bushes, _bush(leaves), 0.0, BUSH_RANGE, true)
	_emit(rocks, _rock(), 0.0, 0.0, true)
	_emit(grass, _grass(), 0.0, GRASS_RANGE, false)


func _tint(lo: float, hi: float) -> Color:
	var v := rng.randf_range(lo, hi)
	return Color(v, v * rng.randf_range(0.97, 1.03), v * rng.randf_range(0.9, 1.0))


func _jitter(c: Vector2) -> Vector2:
	return c + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))


func _xf(p: Vector2, s: float, rot: float, sy: float = 1.0, dy: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s * sy, s)), Vector3(p.x, world.h_at(p.x, p.y) + dy, p.y))


func _add(d: Dictionary, p: Vector2, chunk: float, xf: Transform3D, col: Color) -> void:
	var key := Vector2i(floori((p.x + WorldGen.HALF) / chunk), floori((p.y + WorldGen.HALF) / chunk))
	if not d.has(key):
		d[key] = []
	d[key].append([xf, col])


func _emit(d: Dictionary, mesh: Mesh, begin: float, end: float, shadows: bool) -> void:
	for key in d:
		var list: Array = d[key]
		var centre := Vector3.ZERO
		for e in list:
			centre += (e[0] as Transform3D).origin
		centre /= list.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[i][0]
			xf.origin -= centre
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = centre
		mmi.visibility_range_begin = begin
		mmi.visibility_range_end = end
		mmi.visibility_range_end_margin = 20.0 if end > 0.0 else 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if end > 0.0 and end < 200.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ---------- materials ----------

func _card_mat(tex: String, cut: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage_card.gdshader")
	m.set_shader_parameter("albedo_tex", load(tex))
	m.set_shader_parameter("alpha_cut", cut)
	return m


func _bark_mat(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/bark/%s_bark.jpg" % kind)
	m.normal_enabled = true
	m.normal_texture = load("res://textures/bark/%s_bark_nor.jpg" % kind)
	m.uv1_scale = Vector3(2.0, 3.0, 1.0)
	m.roughness = 0.95
	return m


# ---------- meshes ----------

## One textured quad. `along` runs from the card's base to its tip; normals bend toward `bend_from`
## being the crown centre, which gives soft, volumetric canopy lighting instead of flat cards.
func _card(st: SurfaceTool, base: Vector3, along: Vector3, across: Vector3, uv_base: Vector2, uv_tip: Vector2, uv_side: Vector2, bend_from: Vector3) -> void:
	var c := [base - across * 0.5, base + across * 0.5, base + along + across * 0.5, base + along - across * 0.5]
	var uv := [uv_base - uv_side * 0.5, uv_base + uv_side * 0.5, uv_tip + uv_side * 0.5, uv_tip - uv_side * 0.5]
	for i in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = c[i]
		st.set_normal(((v - bend_from).normalized() + Vector3.UP * 0.35).normalized())
		st.set_uv(uv[i])
		st.add_vertex(v)


func _trunk(st: SurfaceTool, h: float, r0: float, r1: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = h
	c.radial_segments = 9
	c.rings = 2
	c.cap_top = false
	c.cap_bottom = false
	st.append_from(c, 0, Transform3D(Basis(), Vector3(0, h / 2.0, 0)))


func _pine(needles: Material, bark: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var y := 2.2
	while y < 11.0:
		var t := (y - 2.2) / 8.8
		var length := lerpf(3.4, 0.9, t)
		var count := 6 if t < 0.7 else 5
		var phase := r.randf() * TAU
		for b in count:
			var a := phase + b * TAU / count + r.randf_range(-0.2, 0.2)
			var out := Vector3(cos(a), 0.0, sin(a))
			var droop := r.randf_range(0.15, 0.4) * (1.0 - t * 0.5)
			var along := (out - Vector3.UP * droop).normalized() * length
			var side := out.cross(Vector3.UP).normalized()
			var base := Vector3(0, y, 0) + out * 0.15
			# Two crossed cards per branch: one flat, one tilted, so it reads from any angle.
			_card(st, base, along, side * length * 0.75, Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 1.0), Vector3(0, y + 0.8, 0))
			_card(st, base, along, (side * 0.45 + Vector3.UP).normalized() * length * 0.55, Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 1.0), Vector3(0, y + 0.8, 0))
		y += lerpf(0.75, 0.55, t)
	# Leader at the top.
	for a in [0.0, PI / 2.0]:
		var side := Vector3(cos(a), 0.0, sin(a))
		_card(st, Vector3(0, 10.4, 0), Vector3(0, 1.8, 0), side * 1.0, Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 1.0), Vector3(0, 10.4, 0))
	var m := st.commit()
	m.surface_set_material(0, needles)
	var bt := SurfaceTool.new()
	bt.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(bt, 11.0, 0.32, 0.06)
	bt.commit(m)
	m.surface_set_material(1, bark)
	return m


func _oak(leaves: Material, bark: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var centre := Vector3(0, 7.0, 0)
	var radii := Vector3(3.6, 2.7, 3.6)
	for i in 95:
		# Even-ish spread over the crown surface, a few tucked inside for depth.
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.7, 1), r.randf_range(-1, 1)).normalized()
		var depth := r.randf_range(0.6, 1.05)
		var pos := centre + d * radii * depth
		var size := r.randf_range(1.6, 2.3)
		var along := (d + Vector3(r.randf_range(-0.4, 0.4), r.randf_range(-0.2, 0.5), r.randf_range(-0.4, 0.4))).normalized() * size
		var across := along.cross(d + Vector3(0.3, 0.1, -0.2)).normalized() * size
		# The spray's twig sits at the bottom middle of the texture.
		_card(st, pos - along * 0.35, along, across, Vector2(0.5, 1.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0), centre)
	var m := st.commit()
	m.surface_set_material(0, leaves)
	var bt := SurfaceTool.new()
	bt.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(bt, 6.2, 0.38, 0.22)
	for b in 5:
		var a := b * TAU / 5.0 + 0.4
		var dir := Vector3(cos(a) * 0.8, 1.0, sin(a) * 0.8).normalized()
		var c := CylinderMesh.new()
		c.top_radius = 0.05
		c.bottom_radius = 0.16
		c.height = 3.6
		c.radial_segments = 6
		c.rings = 1
		c.cap_top = false
		c.cap_bottom = false
		var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))
		bt.append_from(c, 0, Transform3D(basis, Vector3(0, 4.2, 0) + dir * 1.8))
	bt.commit(m)
	m.surface_set_material(1, bark)
	return m


func _bush(leaves: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var centre := Vector3(0, 0.6, 0)
	for i in 16:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 1), r.randf_range(-1, 1)).normalized()
		var size := r.randf_range(0.9, 1.3)
		var along := (d + Vector3.UP * 0.6).normalized() * size
		var across := along.cross(d + Vector3(0.2, 0.0, 0.3)).normalized() * size
		_card(st, centre + d * Vector3(0.9, 0.5, 0.9) - along * 0.4, along, across, Vector2(0.5, 1.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0), centre)
	var m := st.commit()
	m.surface_set_material(0, leaves)
	return m


func _grass() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := i * PI / 3.0
		var across := Vector3(cos(a), 0.0, sin(a)) * 0.9
		var c := [-across * 0.5, across * 0.5, across * 0.5 + Vector3(0, 0.8, 0), -across * 0.5 + Vector3(0, 0.8, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[k])
			st.add_vertex(c[k])
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://textures/foliage/grass_clump.png"))
	m.surface_set_material(0, mat)
	return m


## Far trees: one simple shape in the foliage's average colour.
func _far(pine: bool) -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#2b4423") if pine else Color("#3d5226")
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 3.2
		c.height = 9.5
		c.radial_segments = 7
		c.rings = 1
		c.cap_bottom = false
		st.append_from(c, 0, Transform3D(Basis(), Vector3(0, 6.6, 0)))
	else:
		var s := SphereMesh.new()
		s.radius = 3.6
		s.height = 5.6
		s.radial_segments = 8
		s.rings = 5
		st.append_from(s, 0, Transform3D(Basis(), Vector3(0, 7.0, 0)))
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


func _rock() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radial_segments = 18
	sm.rings = 11
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.9
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(v[i] * (1.0 + nz.get_noise_3dv(v[i]) * 0.5))
	st.index()
	st.generate_normals()
	var m := st.commit()
	# Same photographed rock as the terrain's steep slopes, projected in world space.
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://textures/ground/aerial_rocks_02_diff_2k.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://textures/ground/aerial_rocks_02_nor_2k.jpg")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	m.surface_set_material(0, mat)
	return m
