shader_type spatial;

render_mode skip_vertex_transform, cull_disabled;

uniform vec3 base_color = vec3(0.18, 0.25, 0.07);
uniform vec3 backlight_color = vec3(0.30, 0.36, 0.20);

varying vec4 data;


void vertex() {
	data[2] = VERTEX.y + 0.55;
	data[2] *= data[2];

	VERTEX.xz *= 1.0 - data[2];
	COLOR = mix(COLOR, vec4(1.0), smoothstep(0.9, 1.0, data[2]));
	COLOR *= INSTANCE_CUSTOM[3] < 0.35 ? 1.0 : mix(1.0, 0.75, smoothstep(0.35, 0.0, data[2]));
	data.rg = INSTANCE_CUSTOM.rg;

	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	data[3] = 0.0;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}


void fragment() {
	ALBEDO = base_color * (data[2] * 0.5 + 0.5);
	ALBEDO.rg *= data.rg * 0.3 + 0.9;
	ALBEDO *= pow(COLOR.rgb, vec3(2.2));
	float spec_rough = clamp(max(data[2], data[3]), 0.0, 1.0);
	ROUGHNESS = 1.0 - spec_rough;
	SPECULAR = clamp(spec_rough * 0.25, 0.0, 0.15);
	BACKLIGHT = backlight_color;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
