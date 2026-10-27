shader_type spatial;
render_mode cull_disabled, depth_draw_always, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.24, 0.33, 0.26);
uniform vec3 deep : source_color = vec3(0.04, 0.11, 0.12);
uniform float flow = 0.025;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 na = texture(wave_a, wp.xz * 0.035 + TIME * vec2(0.004, flow)).rgb * 2.0 - 1.0;
	vec3 nb = texture(wave_b, wp.xz * 0.11 - TIME * vec2(0.012, flow * 0.6)).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3(na.x + nb.x * 0.6, 5.0, na.y + nb.y * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// How much water lies between the surface and the riverbed behind it.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float wd = clamp(VERTEX.z - behind.z, 0.0, 30.0);

	ALBEDO = mix(shallow, deep, smoothstep(0.0, 3.5, wd));
	ALPHA = clamp(0.3 + wd * 0.3, 0.0, 0.94);
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
}
