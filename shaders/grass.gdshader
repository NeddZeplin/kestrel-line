shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Grass clump cards (Foliage008 blades composed into a clump). UV.y = 0 at the tips.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.4;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = (1.0 - UV.y) * (1.0 - UV.y);
	float w = sin(TIME * 1.9 + wp.x * 0.25 + wp.z * 0.18) * 0.12 + sin(TIME * 3.4 + wp.x * 0.9) * 0.04;
	VERTEX.x += w * bend;
	VERTEX.z += w * 0.5 * bend;
}

void fragment() {
	// Light both sides of the card like the ground beneath it (Godot flips NORMAL on back faces).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec4 t = texture(albedo_tex, UV);
	// The blade photos are much darker than the graded meadow texture; lift them to match.
	ALBEDO = t.rgb * COLOR.rgb * vec3(2.3, 2.2, 1.5);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = t.rgb * 0.6;
	// Slightly darker toward the roots, where blades shade each other.
	AO = mix(1.0, 0.7, UV.y);
	AO_LIGHT_AFFECT = 0.4;
}
