shader_type spatial;

render_mode skip_vertex_transform, cull_disabled;

uniform vec3 base_shadow = vec3(0.11, 0.16, 0.05);
uniform vec3 tip_light = vec3(1.08, 1.05, 0.86);
uniform vec3 backlight_color = vec3(0.34, 0.38, 0.18);

varying vec4 data;
varying vec3 stage_tint;


void vertex() {
	stage_tint = COLOR.rgb;
	data[2] = clamp(VERTEX.y + 0.55, 0.0, 1.0);
	data[2] *= data[2];

	VERTEX.xz *= 1.0 - data[2] * 0.92;
	data.rg = INSTANCE_CUSTOM.rg;

	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}


void fragment() {
	vec3 leaf_gradient = mix(base_shadow, tip_light, data[2]);
	ALBEDO = leaf_gradient * stage_tint;
	ALBEDO *= 0.92 + data.r * 0.12;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	BACKLIGHT = backlight_color * stage_tint;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
