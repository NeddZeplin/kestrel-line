extends Node3D
## Terrain mesh in 60 m chunks: 1 m detail near the camera, 4 m detail (with skirts) beyond NEAR_RANGE.

const CHUNK := 60.0
const NEAR_RANGE := 420.0

var world: WorldGen


func build(w: WorldGen) -> void:
	world = w
	var mat := _material()
	var count := int(w.SIZE / CHUNK)
	for cz in count:
		for cx in count:
			var o := Vector2(-w.HALF + cx * CHUNK, -w.HALF + cz * CHUNK)
			# Each chunk sits at its own centre so visibility ranges measure from the right place.
			var centre := Vector3(o.x + CHUNK / 2.0, 0.0, o.y + CHUNK / 2.0)
			var near := MeshInstance3D.new()
			near.mesh = _chunk(o, 1, false)
			near.position = centre
			near.material_override = mat
			near.visibility_range_end = NEAR_RANGE
			add_child(near)
			var far := MeshInstance3D.new()
			far.mesh = _chunk(o, 4, true)
			far.position = centre
			far.material_override = mat
			far.visibility_range_begin = NEAR_RANGE
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(far)
	_outer(mat)


## Countryside beyond the playable sector, out to 2 km, so the horizon is land rather than void.
## Inside the sector it sinks below the real terrain; at the boundary it samples the same heights.
func _outer(mat: Material) -> void:
	var ext := 2000.0
	var step := 25.0
	var n := int(ext * 2.0 / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n:
		var z := -ext + j * step
		var rx := world.river_x(z)
		for i in n:
			var x := -ext + i * step
			var inside := absf(x) < world.HALF and absf(z) < world.HALF
			var h := world.h_at(x, z) - 25.0 if inside else world._height(x, z, rx)
			verts.append(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := verts[j * n + maxi(i - 1, 0)].y - verts[j * n + mini(i + 1, n - 1)].y
			var b := verts[maxi(j - 1, 0) * n + i].y - verts[mini(j + 1, n - 1) * n + i].y
			norms.append(Vector3(a, 4.0 * step, b).normalized())
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for v in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:
				idx.append(v)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## step is in heightfield samples (1 m each). Skirts hide cracks where a far chunk meets a near one.
func _chunk(o: Vector2, step: int, skirt: bool) -> ArrayMesh:
	var n := int(CHUNK) / step + 1
	var i0 := int(o.x + world.HALF)
	var j0 := int(o.y + world.HALF)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var gi: int = mini(i0 + i * step, world.N - 1)
			var gj: int = mini(j0 + j * step, world.N - 1)
			var h: float = world.heights[gj * world.N + gi]
			verts[j * n + i] = Vector3(-world.HALF + gi - o.x - CHUNK / 2.0, h, -world.HALF + gj - o.y - CHUNK / 2.0)
			norms[j * n + i] = world.normals[gj * world.N + gi]
	idx.resize((n - 1) * (n - 1) * 6)
	var t := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx[t] = a
			idx[t + 1] = a + 1
			idx[t + 2] = a + n
			idx[t + 3] = a + 1
			idx[t + 4] = a + n + 1
			idx[t + 5] = a + n
			t += 6
	if skirt:
		var ring: Array[int] = []
		for i in n: ring.append(i)
		for j in range(1, n): ring.append(j * n + n - 1)
		for i in range(n - 2, -1, -1): ring.append((n - 1) * n + i)
		for j in range(n - 2, 0, -1): ring.append(j * n)
		ring.append(0)
		for r in ring.size() - 1:
			var a := ring[r]
			var b := ring[r + 1]
			var base := verts.size()
			verts.append(verts[a] - Vector3(0, 4, 0))
			verts.append(verts[b] - Vector3(0, 4, 0))
			norms.append(norms[a])
			norms.append(norms[b])
			for v in [a, b, base, b, base + 1, base]:
				idx.append(v)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("splat", world.build_splat())
	m.set_shader_parameter("half_size", world.HALF)
	m.set_shader_parameter("macro_noise", TexGen.noise(901, 0.012, 256))
	# Poly Haven CC0 photo textures (2K): colour, OpenGL normal, AO/roughness/metal.
	var layers := {
		"grass": "leafy_grass", "dry": "grass_ground", "forest": "forest_leaves_02",
		"road": "river_small_rocks", "rock": "aerial_rocks_02", "bed": "aerial_mud_1",
	}
	for key in layers:
		var base: String = "res://textures/ground/%s_" % layers[key]
		m.set_shader_parameter(key + "_c", load(base + "diff_2k.jpg"))
		m.set_shader_parameter(key + "_n", load(base + "nor_2k.jpg"))
		if key in ["grass", "road", "rock"]:
			m.set_shader_parameter(key + "_a", load(base + "arm_2k.jpg"))
	return m
