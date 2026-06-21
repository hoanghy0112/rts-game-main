shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha;

uniform vec4 water_color : source_color = vec4(0.24, 0.42, 0.39, 0.52);
uniform vec3 shallow_mud_tint : source_color = vec3(0.18, 0.12, 0.06);
uniform float ripple_scale : hint_range(0.01, 1.0, 0.01) = 0.08;
uniform float ripple_strength : hint_range(0.0, 0.2, 0.005) = 0.035;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float ripple = sin(world_pos.x * 8.0 * ripple_scale + TIME * 0.55) * sin(world_pos.z * 11.0 * ripple_scale - TIME * 0.35);
	vec3 color = mix(shallow_mud_tint, water_color.rgb, 0.72 + ripple * ripple_strength);
	ALBEDO = color;
	ALPHA = water_color.a;
	ROUGHNESS = 0.24;
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
