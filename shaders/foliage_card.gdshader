shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Photo foliage cards (leaf sprays, pine branches). Instance colour gives per-tree variation.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float wind = 0.3;

varying vec3 crown_normal;

void vertex() {
	crown_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float reach = length(VERTEX.xz) * 0.25 + max(VERTEX.y - 3.0, 0.0) * 0.04;
	float gust = sin(TIME * 1.1 + wp.x * 0.04 + wp.z * 0.05) * 0.6 + sin(TIME * 2.7 + wp.x * 0.3) * 0.25;
	float flutter = sin(TIME * 6.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.03;
	VERTEX.x += (gust * wind * reach) * 0.15 + flutter;
	VERTEX.z += (gust * wind * reach) * 0.1;
	VERTEX.y += flutter * 0.5;
}

void fragment() {
	// Both sides of a card use the crown-shaped normal; Godot would otherwise flip it on back faces.
	NORMAL = normalize((VIEW_MATRIX * vec4(crown_normal, 0.0)).xyz);
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	// Light passing through thin leaves and needles.
	BACKLIGHT = t.rgb * 0.55;
}
