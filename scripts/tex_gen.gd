class_name TexGen
extends RefCounted
## Seamless procedural textures (albedo ramps and normal maps) built from Godot's noise.
## Stand-ins until photographic CC0 ground textures are added.


static func _noise(seed: int, freq: float, kind: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = kind
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 6
	n.fractal_gain = 0.55
	return n


static func albedo(seed: int, freq: float, hex: Array, size: int = 1024, grain: float = 0.06, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = _noise(seed, freq, kind)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25 - grain, 0.5, 0.75 + grain, 1.0])
	var c0 := Color(hex[0])
	var c1 := Color(hex[1])
	var c2 := Color(hex[2])
	g.colors = PackedColorArray([c0.darkened(0.15), c0, c1, c2, c2.lightened(0.1)])
	t.color_ramp = g
	return t


static func normal(seed: int, freq: float, size: int = 1024, bump: float = 8.0, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = bump
	t.noise = _noise(seed, freq, kind)
	return t


static func noise(seed: int, freq: float, size: int = 256) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = _noise(seed, freq, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	return t
