extends Node3D
## Hollow Valley visual slice: terrain, vegetation, water, sky, lighting, the HQ and a few vehicles.
## Run with `-- --shot=PATH [--view=overview|road|hq]` to save a screenshot and quit.

const PACK := "res://ithappy/military_free/prefabs/assets/"

var world: WorldGen
var camera_rig
var game
var shot_path := ""
var view := "overview"
var frames := 0
var test_secs := 0.0
var test_t := 0.0
var test_report := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		elif a.begins_with("--view="): view = a.substr(7)
		elif a.begins_with("--test="): test_secs = float(a.substr(7))
	if shot_path != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var t := Time.get_ticks_msec()
	world = WorldGen.new()
	world.generate()
	print("[kestrel] heightfield + layers: %d ms" % (Time.get_ticks_msec() - t))

	_environment()
	t = Time.get_ticks_msec()
	var terrain = load("res://scripts/terrain.gd").new()
	add_child(terrain)
	terrain.build(world)
	print("[kestrel] terrain meshes: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var veg = load("res://scripts/vegetation.gd").new()
	add_child(veg)
	veg.build(world)
	print("[kestrel] vegetation: %d ms" % (Time.get_ticks_msec() - t))
	_river()
	_hq()

	camera_rig = load("res://scripts/rts_camera.gd").new()
	camera_rig.world = world
	add_child(camera_rig)
	_set_view(view)

	t = Time.get_ticks_msec()
	game = load("res://scripts/game.gd").new()
	add_child(game)
	game.setup(world, camera_rig)
	print("[kestrel] game + enemy routing: %d ms" % (Time.get_ticks_msec() - t))


func _set_view(v: String) -> void:
	var rp := world.road_pts[int(world.road_pts.size() * 0.72)]
	match v:
		"road": camera_rig.set_view(Vector3(rp.x, 0.0, rp.y), 70.0, 2.4)
		"hq": camera_rig.set_view(Vector3(WorldGen.HQ.x - 10.0, 0.0, 10.0), 95.0, 2.1)
		"river": camera_rig.set_view(Vector3(world.river_x(world.bridge_z[1]) + 20.0, 0.0, world.bridge_z[1] + 5.0), 110.0, 1.9)
		_: camera_rig.set_view(Vector3(120.0, 0.0, -20.0), 520.0, PI / 2.0 + 0.35)


func _process(delta: float) -> void:
	if test_secs > 0.0:
		_test_step(delta)
		return
	if shot_path == "":
		return
	frames += 1
	if frames == 360:
		print("[kestrel] fps %d, primitives %d, draw calls %d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		print("[kestrel] GPU: %s" % RenderingServer.get_video_adapter_name())
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("[kestrel] saved %s" % shot_path)
		get_tree().quit()


## Automated battle (`-- --test=SECONDS [--shot=PATH]`): deploys a defence, plays waves at 4×,
## prints a status line every 10 s of real time, then saves a screenshot and quits.
func _test_step(delta: float) -> void:
	test_t += delta
	frames += 1
	if frames == 30:
		var hq := WorldGen.HQ
		for e in [["mbt", Vector2(-170, -20)], ["mbt", Vector2(-170, 40)], ["atgm", Vector2(-120, -60)], ["atgm", Vector2(-120, 70)],
				["rifle", Vector2(-200, 0)], ["rifle", Vector2(-150, 110)], ["mortar", Vector2(-60, 0)], ["shorad", Vector2(-80, 30)]]:
			var p: Vector2 = hq + e[1]
			var k: int = game.nav.nearest_passable(GameData.DEFS[e[0]]["move"], Nav.k_of(p.x, p.y))
			var u = game.make_unit(e[0], "p", game.world.cell_center(k))
			game.players.append(u)
		game.supply = 400
		game.threat_dirty = true
		game.speed = 1.0 if OS.get_cmdline_user_args().has("--realtime") else 4.0
		camera_rig.set_view(Vector3(hq.x - 200.0, 0.0, 0.0), 260.0, PI / 2.0 + 0.5)
		if OS.get_cmdline_user_args().has("--realtime"):
			camera_rig.set_view(Vector3(-60.0, 0.0, -40.0), 560.0, PI / 2.0 + 0.3)
		if OS.get_cmdline_user_args().has("--ui"):
			# Show the unit card and a closer view of the line for UI screenshots.
			game.selection = [game.players[0]]
			camera_rig.set_view(Vector3(hq.x - 170.0, 0.0, 10.0), 230.0, PI / 2.0 + 0.4)
		if view == "close":
			# Friendly and enemy armour side by side, paused, to compare paint schemes.
			var base := hq + Vector2(-80.0, -5.0)
			var i := 0
			for t in ["mbt", "shorad"]:
				game.players.append(game.make_unit(t, "p", base + Vector2(i * 14.0, -12.0)))
				i += 1
			i = 0
			for t in ["embt", "ifv", "tech"]:
				game.enemies.append(game.make_unit(t, "e", base + Vector2(i * 14.0 - 6.0, 14.0)))
				i += 1
			game.paused = true
			camera_rig.set_view(Vector3(base.x + 8.0, 0.0, base.y + 2.0), 55.0, PI / 2.0 + 0.25)
	if view == "close":
		if test_t >= test_secs:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
		return
	if frames > 30 and not game.wave_active and game.over == "" and game.nav_task == -1:
		game.send_wave()
	test_report -= delta
	if test_report <= 0.0 and frames > 30:
		test_report = 10.0
		print("[test] t=%.0fs wave %d active=%s enemies=%d players=%d kills=%d lost=%d hq=%d supply=%d fps=%d" % [
			test_t, game.wave, game.wave_active, game.enemies.size(), game.players.size(), game.kills, game.lost,
			game.integrity, game.supply, Engine.get_frames_per_second()])
		if OS.get_cmdline_user_args().has("--trace"):
			for e in game.enemies:
				var k := Nav.k_of(e.p.x, e.p.y)
				print("[trace]   %s#%d (%.0f, %.0f) to-HQ %.0f m  forest=%d  speed=%.1f  halt=%s  variant=%d" % [e.type, e.uid, e.p.x, e.p.y,
					e.p.distance_to(WorldGen.HQ), game.world.forest[k], e.vel.length(), e.halt, e.variant])
		if game.enemies.size() <= 2:
			for e in game.enemies:
				var tg := []
				for w in e.weapons:
					tg.append(w["target"].type if game.alive(w["target"]) else "-")
				print("[test]   %s at (%.0f, %.0f) hp %.0f halt=%s stuck=%.1f spotted=%s targets=%s" % [e.type, e.p.x, e.p.y, e.hp, e.halt, e.stuck_t, e.spotted, tg])
	if test_t >= test_secs or game.over != "":
		print("[test] END over='%s' wave %d kills=%d lost=%d hq=%d" % [game.over, game.wave, game.kills, game.lost, game.integrity])
		if shot_path != "":
			get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.24, 0.42, 0.7)
	sm.sky_horizon_color = Color(0.68, 0.75, 0.82)
	sm.ground_horizon_color = Color(0.6, 0.63, 0.62)
	sm.ground_bottom_color = Color(0.2, 0.22, 0.2)
	sm.sky_curve = 0.12
	sm.sun_angle_max = 18.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 1.0
	env.sdfgi_cascades = 6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.8)
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.00025
	env.volumetric_fog_albedo = Color(0.92, 0.94, 0.97)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 500.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36.0, -128.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 650.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _river() -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var z := -WorldGen.HALF - 10.0
	var n := 0
	while z <= WorldGen.HALF + 10.0:
		var x := world.river_x(z)
		verts.append(Vector3(x - 22.0, WorldGen.WATER_Y, z))
		verts.append(Vector3(x + 22.0, WorldGen.WATER_Y, z))
		if n > 0:
			var a := (n - 1) * 2
			for v in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
				idx.append(v)
		z += 5.0
		n += 1
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_a", TexGen.normal(61, 0.01, 512, 3.0))
	mat.set_shader_parameter("wave_b", TexGen.normal(62, 0.025, 512, 2.0))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = TexGen.albedo(71, 0.05, ["#7d7a72", "#96938a", "#aaa79e"], 512, 0.05)
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	concrete.uv1_scale = Vector3(0.2, 0.2, 0.2)
	concrete.roughness = 0.85
	for bz0 in world.bridge_z:
		var bz: float = bz0 + WorldGen.CELL / 2.0
		var bx := world.river_x(bz)
		var y := WorldGen.WATER_Y + 3.4
		_box(Vector3(62, 0.8, 19), Vector3(bx, y, bz), concrete)
		_box(Vector3(62, 0.9, 0.35), Vector3(bx, y + 0.85, bz + 9.3), concrete)
		_box(Vector3(62, 0.9, 0.35), Vector3(bx, y + 0.85, bz - 9.3), concrete)
		for px in [-18.0, 0.0, 18.0]:
			_box(Vector3(1.8, 7.0, 14.0), Vector3(bx + px, y - 3.8, bz), concrete)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = mat
	b.position = pos
	add_child(b)


func _place(path: String, pos: Vector2, rot: float = 0.0, s: float = 1.0, dy: float = 0.0) -> Node3D:
	var n: Node3D = (load(PACK + path) as PackedScene).instantiate()
	n.position = Vector3(pos.x, world.h_at(pos.x, pos.y) + dy, pos.y)
	n.rotation.y = rot
	n.scale = Vector3.ONE * s
	add_child(n)
	return n


func _hq() -> void:
	var c := WorldGen.HQ
	for i in 26:
		if i == 6 or i == 19:
			continue
		var a := i / 26.0 * TAU
		_place("decorations/barrier_007.tscn", c + Vector2(cos(a), sin(a)) * 29.0, -a - PI / 2.0, 1.2)
	_place("buildings/tent_002.tscn", c + Vector2(-11, -8), 0.2, 1.2)
	_place("buildings/tent_010.tscn", c + Vector2(-11, 8), -0.1, 1.2)
	_place("buildings/tent_002.tscn", c + Vector2(5, 14), PI / 2.0, 1.2)
	_place("buildings/radiostation_001.tscn", c + Vector2(8, -8), PI / 2.0, 1.2)
	_place("buildings/tower_003.tscn", c + Vector2(-20, -14), 0.0, 1.2)
	_place("buildings/tower_003.tscn", c + Vector2(18, 17), 0.0, 1.2)
	_place("vehicles/generator_004.tscn", c + Vector2(11, 2), 0.4, 1.2)
	_place("decorations/box_003.tscn", c + Vector2(-2, -3), 0.0, 1.2)
	_place("decorations/box_005.tscn", c + Vector2(0, -4), 0.7, 1.2)
	_place("decorations/barrel_005.tscn", c + Vector2(-3.5, 3.5), 0.0, 1.2)
	_place("decorations/barrel_005.tscn", c + Vector2(-2.6, 4.2), 0.0, 1.2)
	_place("decorations/tires_001.tscn", c + Vector2(3.5, 3.5), 0.0, 1.2)
	for i in 9:
		var a := PI * 0.72 + i / 8.0 * PI * 0.56
		_place("decorations/hedgehog_001.tscn", c + Vector2(cos(a), sin(a)) * 41.0, i * 0.9, 1.5)


func _units() -> void:
	var rp := world.road_pts[int(world.road_pts.size() * 0.72)]
	var rq := world.road_pts[int(world.road_pts.size() * 0.72) + 3]
	var dir := atan2(rq.x - rp.x, rq.y - rp.y)
	_place("vehicles/tank_006.tscn", rp, dir, 1.0)
	_place("vehicles/hummer_003.tscn", rp + Vector2(9, -14).rotated(-dir), dir, 1.0)
	_place("vehicles/helicopter_001.tscn", rp + Vector2(-30, 25), dir + 0.6, 1.0, 28.0)
