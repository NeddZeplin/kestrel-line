shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Tree crowns and bushes. Colour comes from the MultiMesh instance colour.
uniform float lumps = 0.0;
uniform float wind = 0.35;

varying float height;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bulge = sin(VERTEX.x * 2.7 + VERTEX.y * 1.9 + wp.x * 0.1) * sin(VERTEX.z * 3.1 - VERTEX.y * 2.3 + wp.z * 0.1);
	VERTEX += NORMAL * bulge * lumps;
	float sway = sin(TIME * 1.3 + wp.x * 0.05 + wp.z * 0.07) * wind * max(VERTEX.y - 2.0, 0.0) * 0.03;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	height = VERTEX.y;
}

void fragment() {
	// Lighter, warmer toward the crown top; a little self-shadowing near the trunk.
	float k = clamp(height / 10.0, 0.0, 1.0);
	ALBEDO = COLOR.rgb * mix(0.62, 1.05, k);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = COLOR.rgb * 0.15;
}
