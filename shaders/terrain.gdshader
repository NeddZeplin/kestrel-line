shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Photographic CC0 ground layers (Poly Haven): colour, OpenGL normal, and ARM (R = AO, G = roughness).
// Blend map: R road/hardstand, G forest floor, B riverbed.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bed_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bed_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// Metres per texture tile for each layer.
uniform float grass_tile = 2.6;
uniform float dry_tile = 3.0;
uniform float forest_tile = 2.2;
uniform float road_tile = 2.4;
uniform float rock_tile = 9.0;
uniform float bed_tile = 5.0;
// Colour grading per layer: the photographed grass is mostly brown/olive seen from above.
uniform vec3 grass_grade = vec3(0.66, 0.95, 0.42);
uniform vec3 dry_grade = vec3(0.92, 1.0, 0.62);
uniform vec3 forest_grade = vec3(0.66, 0.7, 0.55);
uniform vec3 road_grade = vec3(1.05, 1.0, 0.92);
uniform float half_size = 600.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

vec2 rot(vec2 p, float a) {
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

// Colour from two scales and rotations so the repeat is hard to spot.
vec3 color2(sampler2D t, vec2 p, float tile, float m) {
	vec3 a = texture(t, p / tile).rgb;
	vec3 b = texture(t, rot(p, 1.1) / (tile * 3.7) + 0.31).rgb;
	return mix(a, b, 0.25 + 0.3 * m);
}

vec2 nrm2(sampler2D t, vec2 p, float tile) {
	vec2 a = texture(t, p / tile).rg * 2.0 - 1.0;
	return a;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec2 p = wpos.xz;
	float m1 = texture(macro_noise, p * 0.0035).r;
	float m2 = texture(macro_noise, p * 0.017).r;
	float m3 = texture(macro_noise, p * 0.09).r;

	float w_dry = smoothstep(0.45, 0.72, m1 * 0.65 + m2 * 0.35);
	vec4 sp = texture(splat, (p + half_size) / (2.0 * half_size));
	sp *= 1.0 - smoothstep(half_size - 15.0, half_size, max(abs(p.x), abs(p.y)));
	float w_forest = smoothstep(0.25, 0.7, sp.g + (m3 - 0.5) * 0.5);
	float w_bed = smoothstep(0.2, 0.65, sp.b + (m3 - 0.5) * 0.35);
	float w_road = smoothstep(0.3, 0.65, sp.r + (m3 - 0.5) * 0.3);
	float w_rock = smoothstep(0.17, 0.3, (1.0 - n.y) + (m3 - 0.5) * 0.1);

	vec3 col = color2(grass_c, p, grass_tile, m2) * grass_grade;
	vec2 nt = nrm2(grass_n, p, grass_tile);
	vec3 arm = texture(grass_a, p / grass_tile).rgb;

	col = mix(col, color2(dry_c, p, dry_tile, m2) * dry_grade, w_dry * 0.75);
	nt = mix(nt, nrm2(dry_n, p, dry_tile), w_dry);

	col = mix(col, color2(forest_c, p, forest_tile, m2) * forest_grade, w_forest);
	nt = mix(nt, nrm2(forest_n, p, forest_tile), w_forest);
	arm = mix(arm, vec3(0.8, 0.9, 0.0), w_forest);

	col = mix(col, color2(bed_c, p, bed_tile, m2), w_bed);
	nt = mix(nt, nrm2(bed_n, p, bed_tile), w_bed);
	arm = mix(arm, vec3(0.85, 0.55, 0.0), w_bed);

	col = mix(col, color2(road_c, p, road_tile, m2) * road_grade, w_road);
	nt = mix(nt, nrm2(road_n, p, road_tile), w_road);
	arm = mix(arm, texture(road_a, p / road_tile).rgb, w_road);

	// Rock: side projections on steep ground so it doesn't stretch.
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 rk = texture(rock_c, wpos.zy / rock_tile).rgb * bw.x + color2(rock_c, p, rock_tile, m2) * bw.y + texture(rock_c, wpos.xy / rock_tile).rgb * bw.z;
	vec2 rn = (texture(rock_n, wpos.zy / rock_tile).rg * bw.x + texture(rock_n, p / rock_tile).rg * bw.y + texture(rock_n, wpos.xy / rock_tile).rg * bw.z) * 2.0 - 1.0;
	col = mix(col, rk, w_rock);
	nt = mix(nt, rn, w_rock);
	arm = mix(arm, texture(rock_a, p / rock_tile).rgb, w_rock);

	// Large-scale brightness variation reads as soil moisture and lighting from far away.
	col *= 0.88 + 0.24 * m2;

	// Tangent-space detail to world space: U runs along +X, image-up (OpenGL +Y) along -Z.
	vec3 nw = normalize(n + vec3(nt.x, 0.0, -nt.y) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = clamp(arm.g, 0.3, 1.0);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.35;
}
