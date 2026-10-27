class_name Nav
extends RefCounted
## Movement costs per class, A* for player orders, threat maps and the enemy's flow fields.
## Threat and flow fields are pure functions of their inputs so they can run on a worker thread.

const G := WorldGen.G
const CELL := WorldGen.CELL
const MOVES := ["foot", "track", "wheel"]
const DI := [1, -1, 0, 0, 1, 1, -1, -1]
const DJ := [0, 0, 1, -1, 1, -1, 1, -1]
const DC := [1.0, 1.0, 1.0, 1.0, 1.4142, 1.4142, 1.4142, 1.4142]
const THREAT_CELL := 20.0

var world: WorldGen
var cost := {}
var astar := {}
var goal_cells := PackedInt32Array()


func _init(w: WorldGen) -> void:
	world = w
	for m in MOVES:
		var c := PackedFloat32Array()
		c.resize(G * G)
		cost[m] = c
	var foot: PackedFloat32Array = cost["foot"]
	var track: PackedFloat32Array = cost["track"]
	var wheel: PackedFloat32Array = cost["wheel"]
	for k in G * G:
		var s := w.slope[k]
		var wet := w.water[k] == 1 and w.bridge[k] == 0
		var f := w.forest[k] == 1
		var r := w.road[k] == 1
		foot[k] = INF if wet or s > 40.0 else 1.0 + s / 25.0 - (0.15 if f else 0.0) - (0.1 if r else 0.0)
		track[k] = INF if wet or s > 28.0 else 1.0 + s / 14.0 + (1.8 if f else 0.0) - (0.35 if r else 0.0)
		wheel[k] = INF if wet or s > 20.0 else 1.0 + s / 9.0 + (3.5 if f else 0.0) - (0.6 if r else 0.0)
	cost["foot"] = foot
	cost["track"] = track
	cost["wheel"] = wheel
	for m in MOVES:
		var a := AStarGrid2D.new()
		a.region = Rect2i(0, 0, G, G)
		a.cell_size = Vector2(1, 1)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
		var c: PackedFloat32Array = cost[m]
		for k in G * G:
			var id := Vector2i(k % G, k / G)
			if c[k] == INF:
				a.set_point_solid(id, true)
			else:
				a.set_point_weight_scale(id, maxf(c[k], 0.3))
		astar[m] = a
	for k in G * G:
		if w.cell_center(k).distance_to(WorldGen.HQ) < 40.0:
			goal_cells.append(k)


static func k_of(x: float, z: float) -> int:
	return clampi(floori((z + WorldGen.HALF) / CELL), 0, G - 1) * G + clampi(floori((x + WorldGen.HALF) / CELL), 0, G - 1)


func passable(move: String, x: float, z: float) -> bool:
	return (cost[move] as PackedFloat32Array)[k_of(x, z)] != INF


func nearest_passable(move: String, k: int) -> int:
	var c: PackedFloat32Array = cost[move]
	if c[k] != INF:
		return k
	var i0 := k % G
	var j0 := k / G
	for r in range(1, 12):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var i := i0 + di
				var j := j0 + dj
				if i >= 0 and j >= 0 and i < G and j < G and c[j * G + i] != INF:
					return j * G + i
	return -1


## Waypoints (x, z) for a player move order, or an empty array if there is no route.
func route(move: String, from: Vector2, to: Vector2) -> Array:
	var a: AStarGrid2D = astar[move]
	var s := nearest_passable(move, k_of(from.x, from.y))
	var g := nearest_passable(move, k_of(to.x, to.y))
	if s < 0 or g < 0:
		return []
	var ids := a.get_id_path(Vector2i(s % G, s / G), Vector2i(g % G, g / G))
	var out: Array = []
	for n in ids.size():
		if n % 2 == 1 or n == ids.size() - 1:
			out.append(world.cell_center(ids[n].y * G + ids[n].x))
	if out.size() > 0 and to.distance_to(out[out.size() - 1]) < CELL:
		out.append(to)
	return out


## Line of sight over the heightfield; woods block it except within 16 m of either end.
static func los(w: WorldGen, a: Vector3, b: Vector3, step: float = 12.0) -> bool:
	var dx := b.x - a.x
	var dz := b.z - a.z
	var d := sqrt(dx * dx + dz * dz)
	var n := maxi(1, ceili(d / step))
	for s in range(1, n):
		var t := s / float(n)
		var x := a.x + dx * t
		var z := a.z + dz * t
		var g := w.h_at(x, z)
		var dd := d * t
		if dd > 16.0 and d - dd > 16.0 and w.forest[k_of(x, z)] == 1:
			g += 9.0
		if a.y + (b.y - a.y) * t < g:
			return false
	return true


## Danger map from the player's settled units. `units` is a snapshot:
## [{"pos": Vector3 (eye), "dug": bool, "weapons": [weapon dicts]}].
## Returns [anti_armour, anti_personnel] on the 10 m nav grid.
static func compute_threat(w: WorldGen, units: Array) -> Array:
	var cg := int(WorldGen.SIZE / THREAT_CELL)
	var cat := PackedFloat32Array()
	var cap := PackedFloat32Array()
	cat.resize(cg * cg)
	cap.resize(cg * cg)
	for u in units:
		var eye: Vector3 = u["pos"]
		var max_r := 0.0
		for wp in u["weapons"]:
			if not wp.get("air_only", false):
				max_r = maxf(max_r, wp["range"])
		max_r = minf(max_r, 650.0)
		var ci := floori((eye.x + WorldGen.HALF) / THREAT_CELL)
		var cj := floori((eye.z + WorldGen.HALF) / THREAT_CELL)
		var rc := ceili(max_r / THREAT_CELL)
		for j in range(maxi(0, cj - rc), mini(cg, cj + rc + 1)):
			for i in range(maxi(0, ci - rc), mini(cg, ci + rc + 1)):
				var x := -WorldGen.HALF + (i + 0.5) * THREAT_CELL
				var z := -WorldGen.HALF + (j + 0.5) * THREAT_CELL
				var d := Vector2(x - eye.x, z - eye.z).length()
				if d > max_r:
					continue
				var vis := -1
				for wp in u["weapons"]:
					if wp.get("air_only", false) or d > wp["range"] or d < wp.get("min", 0.0):
						continue
					if not wp.get("indirect", false):
						if vis == -1:
							vis = 1 if los(w, eye, Vector3(x, w.h_at(x, z) + 2.0, z), 15.0) else 0
						if vis == 0:
							continue
					var f: float = wp.get("threat", 1.0) * (1.0 - 0.5 * d / wp["range"]) * (1.2 if u["dug"] else 1.0)
					if wp["pen"] >= 40.0:
						cat[j * cg + i] = minf(4.0, cat[j * cg + i] + f)
					else:
						cap[j * cg + i] = minf(4.0, cap[j * cg + i] + f)
	var tat := PackedFloat32Array()
	var tap := PackedFloat32Array()
	tat.resize(G * G)
	tap.resize(G * G)
	var ratio := int(THREAT_CELL / CELL)
	for k in G * G:
		var c := ((k / G) / ratio) * cg + (k % G) / ratio
		tat[k] = cat[c]
		tap[k] = cap[c]
	return [tat, tap]


## Distance-to-HQ field (Dijkstra from the goal) with threat folded into the step cost.
## Float64 throughout: rounding in 32-bit floats can make live nodes look stale.
static func flow_field(base: PackedFloat32Array, tat: PackedFloat32Array, tap: PackedFloat32Array, wat: float, wap: float, goals: PackedInt32Array) -> PackedFloat64Array:
	var n := G * G
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var hk := PackedInt32Array()
	var hp := PackedFloat64Array()
	for g in goals:
		if base[g] == INF:
			continue
		dist[g] = 0.0
		hk.append(g)
		hp.append(0.0)
	# hk/hp form a binary min-heap (the seeded goals all have priority 0, so it starts valid).
	while hk.size() > 0:
		var k := hk[0]
		var d := hp[0]
		var last := hk.size() - 1
		hk[0] = hk[last]
		hp[0] = hp[last]
		hk.resize(last)
		hp.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and hp[l] < hp[m]:
				m = l
			if r < last and hp[r] < hp[m]:
				m = r
			if m == i:
				break
			var tk := hk[i]
			hk[i] = hk[m]
			hk[m] = tk
			var tp := hp[i]
			hp[i] = hp[m]
			hp[m] = tp
			i = m
		if d > dist[k]:
			continue
		var ci := k % G
		var cj := k / G
		for nb in 8:
			var ni: int = ci + DI[nb]
			var nj: int = cj + DJ[nb]
			if ni < 0 or nj < 0 or ni >= G or nj >= G:
				continue
			var nk := nj * G + ni
			var c := base[nk]
			if c == INF:
				continue
			if nb >= 4 and (base[cj * G + ni] == INF or base[nj * G + ci] == INF):
				continue
			var nd: float = d + (c + wat * tat[nk] + wap * tap[nk]) * DC[nb]
			if nd < dist[nk]:
				dist[nk] = nd
				hk.append(nk)
				hp.append(nd)
				var q := hk.size() - 1
				while q > 0:
					var pq := (q - 1) / 2
					if hp[pq] <= hp[q]:
						break
					var tk2 := hk[q]
					hk[q] = hk[pq]
					hk[pq] = tk2
					var tp2 := hp[q]
					hp[q] = hp[pq]
					hp[pq] = tp2
					q = pq
	return dist


## All six enemy fields: cautious (0) and bold (1) for each movement class.
static func compute_fields(costs: Dictionary, threat: Array, goals: PackedInt32Array) -> Dictionary:
	var out := {}
	for m in MOVES:
		var mw: Dictionary = GameData.MOVE_W[m]
		for v in [0, 1]:
			var f := 1.0 if v == 0 else 0.3
			out[m + str(v)] = flow_field(costs[m], threat[0], threat[1], mw["at"] * f, mw["ap"] * f, goals)
	return out


static func best_neighbor(field: PackedFloat64Array, k: int) -> int:
	var ci := k % G
	var cj := k / G
	var best := -1
	var bd := field[k]
	for nb in 8:
		var ni: int = ci + DI[nb]
		var nj: int = cj + DJ[nb]
		if ni < 0 or nj < 0 or ni >= G or nj >= G:
			continue
		var nk := nj * G + ni
		if field[nk] < bd:
			bd = field[nk]
			best = nk
	return best
