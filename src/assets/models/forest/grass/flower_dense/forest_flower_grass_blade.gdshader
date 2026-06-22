shader_type spatial;

render_mode skip_vertex_transform, cull_disabled;

uniform vec3 base_color = vec3(0.18, 0.25, 0.07);
uniform vec3 backlight_color = vec3(0.30, 0.36, 0.20);
uniform vec3 stem_color = vec3(0.14, 0.19, 0.06);
uniform vec3 flower_white = vec3(0.96, 0.94, 0.84);
uniform vec3 flower_yellow = vec3(0.95, 0.72, 0.24);
uniform vec3 flower_red = vec3(0.82, 0.16, 0.12);
uniform vec2 wind_direction = vec2(1.0, 1.0);

varying vec4 data;
varying vec2 part_data;


void vertex() {
	float leaf_mask = 1.0 - step(0.25, UV2.x);
	float stem_mask = step(0.25, UV2.x) * (1.0 - step(0.75, UV2.x));
	float flower_mask = step(0.75, UV2.x);
	float leaf_count = 3.0 + floor(clamp(INSTANCE_CUSTOM.g * 3.0, 0.0, 2.99));
	float leaf_visible = 1.0 - step(leaf_count - 0.5, UV.x);
	float second_flower_visible = step(0.52, INSTANCE_CUSTOM.g);
	float flower_visible = mix(1.0, second_flower_visible, step(0.5, UV.x));
	float visible_part = max(max(leaf_mask * leaf_visible, stem_mask), flower_mask * flower_visible);

	vec3 root_vertex = vec3(0.0, -0.45, 0.0);
	VERTEX = mix(root_vertex, VERTEX, visible_part);

	data[2] = clamp(UV.y, 0.0, 1.0);
	data[2] *= data[2];

	VERTEX.xz *= mix(1.0 - data[2] * 0.2, 1.0 - data[2], leaf_mask);
	COLOR = mix(COLOR, vec4(1.0), smoothstep(0.88, 1.0, data[2]) * leaf_mask);
	COLOR *= INSTANCE_CUSTOM[3] < 0.35 ? 1.0 : mix(1.0, 0.75, smoothstep(0.35, 0.0, data[2]));
	data.rg = INSTANCE_CUSTOM.rg;
	part_data = vec2(UV2.x, UV.x);

	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scale = pow(max(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.0), 0.707);
	float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	force -= fract(force * 256.0) * force * 0.05;
	force = pow(max(force, 0.0), 0.707);

	float lateral_wobble = sin(TIME * 2.0 * (1.0 + data.r + data.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 direction = wind_direction / max(length(wind_direction), 0.0001);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral_wobble + direction) * force;
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2];
	data[3] = force;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}


void fragment() {
	float leaf_mask = 1.0 - step(0.25, part_data.x);
	float stem_mask = step(0.25, part_data.x) * (1.0 - step(0.75, part_data.x));
	float flower_mask = step(0.75, part_data.x);

	vec3 grass_albedo = base_color * (data[2] * 0.5 + 0.5);
	grass_albedo.rg *= data.rg * 0.3 + 0.9;
	grass_albedo *= pow(COLOR.rgb, vec3(2.2));

	float flower_palette = floor(fract(data.g * 7.37 + part_data.y * 0.43) * 3.0);
	vec3 flower_color = mix(flower_white, flower_yellow, step(0.5, flower_palette));
	flower_color = mix(flower_color, flower_red, step(1.5, flower_palette));

	ALBEDO = grass_albedo * leaf_mask;
	ALBEDO += stem_color * (data[2] * 0.35 + 0.75) * stem_mask;
	ALBEDO += flower_color * flower_mask;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	BACKLIGHT = backlight_color;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
