class_name WorldGen
extends RefCounted
## Hollow Valley: 1 m heightfield plus terrain classes (water, bridges, forest, road) on a 10 m nav grid.
## Ported from the browser prototype; the same layout drives the enemy AI once it is ported.

const HALF := 600.0
const SIZE := 1200.0
const RES := 1.0
const N := 1201
const CELL := 10.0
const G := 120
const WATER_Y := 2.0
const HQ := Vector2(430.0, 0.0)
const SPAWNS: Array[Vector2] = [Vector2(-575.0, -380.0), Vector2(-575.0, 0.0), Vector2(-575.0, 380.0)]

## Drives terrain-matched vehicle camouflage and uniforms ("temperate", "desert", "winter").
var biome := "temperate"
var seed_i := 4127
var relief := 24.0
var rough := 5.0
var hq_hill := 26.0
var forest_t := 0.12
var bridge_z: Array[float] = []

var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var slope := PackedFloat32Array()
var water := PackedByteArray()
var bridge := PackedByteArray()
var forest := PackedByteArray()
var road := PackedByteArray()
var road_pts := PackedVector2Array()
var hq_top := 0.0

var _big := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _micro := FastNoiseLite.new()
var _river := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init() -> void:
	_setup(_big, 1.0 / 420.0, 5, 0)
	_setup(_mid, 1.0 / 110.0, 3, 11)
	_setup(_fine, 1.0 / 26.0, 3, 23)
	_setup(_micro, 1.0 / 5.0, 2, 37)
	_setup(_river, 1.0 / 90.0, 1, 41)
	_setup(_forest, 1.0 / 160.0, 3, 53)


func _setup(n: FastNoiseLite, freq: float, octaves: int, s: int) -> void:
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = seed_i + s
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves


func generate() -> void:
	hq_top = _raw(HQ.x, HQ.y)
	heights.resize(N * N)
	for j in N:
		var z := -HALF + j * RES
		var rx := river_x(z)
		for i in N:
			heights[j * N + i] = _height(-HALF + i * RES, z, rx)
	_build_normals()
	_build_cells()
	_build_road()


func river_x(z: float) -> float:
	return -60.0 + 90.0 * sin(z / 170.0 + float(seed_i % 7)) + 30.0 * _river.get_noise_1d(z)


func _raw(x: float, z: float) -> float:
	var h := 24.0 + _big.get_noise_2d(x, z) * relief * 1.7 + _mid.get_noise_2d(x, z) * rough * 1.7 + _fine.get_noise_2d(x, z)
	var dh := Vector2(x, z).distance_to(HQ)
	h += hq_hill * exp(-dh * dh / (2.0 * 150.0 * 150.0))
	h -= maxf(0.0, (-x - 200.0) / 400.0) * 8.0
	return h


func _height(x: float, z: float, rx: float) -> float:
	var h := _raw(x, z)
	h = lerpf(h, hq_top, smoothstep(70.0, 35.0, Vector2(x, z).distance_to(HQ)))
	var d := absf(x - rx)
	h = lerpf(h, minf(h, WATER_Y + 3.5), smoothstep(130.0, 26.0, d))
	h += _micro.get_noise_2d(x, z) * 0.22 * smoothstep(14.0, 24.0, d)
	h = lerpf(h, WATER_Y - 3.0, smoothstep(22.0, 12.0, d))
	if d > 22.0:
		h = maxf(h, WATER_Y + 1.2)
	return h


func _build_normals() -> void:
	normals.resize(N * N)
	for j in N:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, N - 1)
		for i in N:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, N - 1)
			var dx := heights[j * N + i0] - heights[j * N + i1]
			var dz := heights[j0 * N + i] - heights[j1 * N + i]
			normals[j * N + i] = Vector3(dx, 2.0 * RES, dz).normalized()


func h_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / RES, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / RES, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func cell_center(k: int) -> Vector2:
	return Vector2(-HALF + (k % G + 0.5) * CELL, -HALF + (floori(k / float(G)) + 0.5) * CELL)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + HALF) / CELL), 0, G - 1), clampi(floori((p.y + HALF) / CELL), 0, G - 1))


func cell_k(x: float, z: float) -> int:
	var c := cell_of(Vector2(x, z))
	return c.y * G + c.x


func _build_cells() -> void:
	var nn := G * G
	# Packed arrays are values in GDScript, so each one is sized directly.
	water.resize(nn)
	water.fill(0)
	bridge.resize(nn)
	bridge.fill(0)
	forest.resize(nn)
	forest.fill(0)
	road.resize(nn)
	road.fill(0)
	slope.resize(nn)
	for k in nn:
		var c := cell_center(k)
		var gx := (h_at(c.x + 5.0, c.y) - h_at(c.x - 5.0, c.y)) / 10.0
		var gz := (h_at(c.x, c.y + 5.0) - h_at(c.x, c.y - 5.0)) / 10.0
		slope[k] = rad_to_deg(atan(Vector2(gx, gz).length()))
		var dr := absf(c.x - river_x(c.y))
		if dr < 14.0:
			water[k] = 1
		var near_spawn := false
		for s in SPAWNS:
			if c.distance_to(s) < 60.0:
				near_spawn = true
		if dr > 30.0 and slope[k] < 32.0 and c.distance_to(HQ) > 110.0 and not near_spawn and _forest.get_noise_2d(c.x, c.y) * 1.6 > forest_t:
			forest[k] = 1
	for bz0 in [-260.0, 230.0]:
		var bz: float = floorf((bz0 + HALF) / CELL) * CELL - HALF + CELL / 2.0
		bridge_z.append(bz)
		var bx := river_x(bz + CELL / 2.0)
		for k in nn:
			var c := cell_center(k)
			if (absf(c.y - bz) < 1.0 or absf(c.y - bz - CELL) < 1.0) and absf(c.x - bx) < 30.0:
				water[k] = 0
				bridge[k] = 1
				slope[k] = 2.0
				forest[k] = 0


func _build_road() -> void:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, G, G)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for k in G * G:
		var id := Vector2i(k % G, floori(k / float(G)))
		if (water[k] == 1 and bridge[k] == 0) or slope[k] > 20.0:
			astar.set_point_solid(id, true)
		else:
			astar.set_point_weight_scale(id, 1.0 + slope[k] / 6.0 + (2.0 if forest[k] == 1 else 0.0))
	var path := astar.get_id_path(cell_of(SPAWNS[1]), cell_of(HQ - Vector2(40.0, 0.0)))
	var pts := PackedVector2Array([SPAWNS[1]])
	for id in path:
		var k := id.y * G + id.x
		road[k] = 1
		forest[k] = 0
		pts.append(cell_center(k))
	pts.append(HQ)
	road_pts = chaikin(pts, 3)


static func chaikin(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	for _n in iterations:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			out.append(pts[i].lerp(pts[i + 1], 0.25))
			out.append(pts[i].lerp(pts[i + 1], 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts


## Blend map for the terrain shader. R = road and hardstand, G = forest floor, B = riverbed and banks.
func build_splat(size: int = 512) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var k := size / SIZE
	_stroke(img, road_pts, 9.0, 0, k)
	_disc(img, HQ, 32.0, 0, k)
	for s in SPAWNS:
		_disc(img, s, 22.0, 0, k)
	for kk in G * G:
		if forest[kk] == 1:
			_disc(img, cell_center(kk), 8.5, 1, k)
	var river := PackedVector2Array()
	var z := -HALF - 10.0
	while z <= HALF + 10.0:
		river.append(Vector2(river_x(z), z))
		z += 6.0
	_stroke(img, river, 46.0, 2, k)
	return ImageTexture.create_from_image(img)


func _stroke(img: Image, pts: PackedVector2Array, width: float, ch: int, k: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
		for s in steps:
			_disc(img, a.lerp(b, s / float(steps)), width / 2.0, ch, k)


func _disc(img: Image, p: Vector2, r: float, ch: int, k: float) -> void:
	var cx := (p.x + HALF) * k
	var cy := (p.y + HALF) * k
	var rp := r * k
	var feather := maxf(rp * 0.6, 1.5)
	var size := img.get_width()
	for y in range(maxi(0, floori(cy - rp - feather)), mini(size, ceili(cy + rp + feather) + 1)):
		for x in range(maxi(0, floori(cx - rp - feather)), mini(size, ceili(cx + rp + feather) + 1)):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			var v := clampf(1.0 - (d - rp) / feather, 0.0, 1.0)
			if v <= 0.0:
				continue
			var c := img.get_pixel(x, y)
			c[ch] = maxf(c[ch], v)
			img.set_pixel(x, y, c)
