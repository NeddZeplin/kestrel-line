shader_type spatial;

// Repaints ithappy vehicles in the sector's camouflage.
// force = 1: the surface is the pack's camo material, so it is all paint.
// force = 0: the surface uses the pack's colour palette; only the tan body colour is repainted,
//            so tyres, glass, metal and lights keep their palette colours.
uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D camo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float force = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float camo_scale = 0.3;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec3 base = texture(base_tex, UV).rgb;
	// Judge the palette colour in display (sRGB-like) space, where the thresholds are intuitive.
	vec3 hsv = rgb2hsv(pow(base, vec3(1.0 / 2.2)));
	float tan_hue = smoothstep(0.03, 0.06, hsv.x) * (1.0 - smoothstep(0.15, 0.19, hsv.x));
	float paint = max(force, tan_hue * smoothstep(0.12, 0.22, hsv.y) * smoothstep(0.35, 0.5, hsv.z));

	// Camo projected in the model's own space so it sticks to the vehicle as it moves.
	vec3 w = pow(abs(normalize(onrm)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = opos * camo_scale;
	vec3 camo = texture(camo_tex, p.zy).rgb * w.x + texture(camo_tex, p.xz).rgb * w.y + texture(camo_tex, p.xy).rgb * w.z;

	ALBEDO = mix(base, camo * tint, paint);
	ROUGHNESS = mix(0.6, 0.78, paint);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
