shader_type particles;
render_mode disable_velocity, disable_force;

group_uniforms options;
uniform sampler2D main_noise;
uniform float main_noise_scale = 0.015;
uniform vec3 position_offset = vec3(0.0, 0.75, 0.0);
uniform bool align_to_normal = true;
uniform float normal_strength : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform bool random_rotation = true;
uniform float random_spacing : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform vec3 min_scale = vec3(0.0675, 1.5, 0.0675);
uniform vec3 max_scale = vec3(0.1275, 1.5, 0.1275);
uniform float far_width_boost : hint_range(1.0, 4.0, 0.05) = 1.65;

group_uniforms filtering;
uniform float condition_dither_range : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float surface_slope_min : hint_range(0.0, 1.0, 0.01) = 0.58;

group_uniforms rice_mask;
uniform bool rice_mask_enabled = false;
uniform sampler2D rice_plot_mask : repeat_disable, filter_nearest;
uniform mat4 rice_world_to_region = mat4(1.0);
uniform vec2 rice_mask_origin = vec2(0.0);
uniform float rice_mask_sample_size = 0.5;
uniform vec2 rice_mask_texture_size = vec2(1.0);
uniform vec3 seedling_color = vec3(0.52, 0.82, 0.24);
uniform vec3 flooded_green_color = vec3(0.34, 0.68, 0.20);
uniform vec3 tillering_color = vec3(0.22, 0.58, 0.16);
uniform vec3 mature_color = vec3(0.83, 0.69, 0.28);
uniform vec3 stubble_color = vec3(0.62, 0.48, 0.24);

group_uniforms private;
uniform float max_dist = 360.0;
uniform vec3 camera_position = vec3(0.0);
uniform uint instance_rows = 1u;
uniform float instance_spacing = 0.9375;
uniform uint _background_mode = 0u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;

#define VERTEX_PASS 1


ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv, _region_size);
	ivec2 pos;
	int bounds;
	int layer_index = -1;
	for (int i = -1; i < 0; i++) {
		if ((layer_index == -1 && _background_mode == 0u) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[pos.y * _region_map_size + pos.x] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}


#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
#endif


float random(vec2 v) {
	return fract(1e4 * sin(fma(17.0, v.x, v.y * 0.1)) * (0.1 + abs(sin(fma(v.y, 13.0, v.x)))));
}


mat3 rotation_matrix(vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	float t = 1.0 - c;
	vec3 n = normalize(axis);
	float x = n.x;
	float y = n.y;
	float z = n.z;

	return mat3(
		vec3(t * x * x + c, t * x * y - z * s, t * x * z + y * s),
		vec3(t * x * y + z * s, t * y * y + c, t * y * z - x * s),
		vec3(t * x * z - y * s, t * y * z + x * s, t * z * z + c)
	);
}


mat3 align_to_vector(vec3 normal) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	if (abs(dot(normal, up)) > 0.9999) {
		up = vec3(1.0, 0.0, 0.0);
	}
	vec3 tangent = normalize(cross(up, normal));
	vec3 bitangent = normalize(cross(tangent, normal));
	return mat3(tangent, normal, bitangent);
}


int rice_stage_code_at(vec3 world_pos) {
	if (!rice_mask_enabled) {
		return 0;
	}

	vec3 region_pos = (rice_world_to_region * vec4(world_pos, 1.0)).xyz;
	vec2 texel = floor((region_pos.xz - rice_mask_origin) / max(rice_mask_sample_size, 0.001));
	if (
		texel.x < 0.0 || texel.y < 0.0 ||
		texel.x >= rice_mask_texture_size.x || texel.y >= rice_mask_texture_size.y
	) {
		return 0;
	}

	vec2 uv = (texel + vec2(0.5)) / rice_mask_texture_size;
	return int(floor(textureLod(rice_plot_mask, uv, 0.0).r * 255.0 + 0.5));
}


vec3 rice_stage_tint(int code) {
	if (code == 1) {
		return seedling_color;
	}
	if (code == 2) {
		return flooded_green_color;
	}
	if (code == 3) {
		return tillering_color;
	}
	if (code == 4) {
		return mature_color;
	}
	if (code == 5) {
		return stubble_color;
	}
	return tillering_color;
}


float rice_stage_height(int code) {
	if (code == 1) {
		return 0.42;
	}
	if (code == 2) {
		return 0.72;
	}
	if (code == 3) {
		return 1.0;
	}
	if (code == 4) {
		return 1.08;
	}
	if (code == 5) {
		return 0.32;
	}
	return 1.0;
}


void hide_particle(inout vec3 pos) {
	pos.y = 0.0 / 0.0;
	pos.xz = vec2(100000.0);
}


void start() {
	vec3 pos = vec3(float(INDEX % instance_rows), 0.0, float(INDEX / instance_rows)) - float(instance_rows >> 1u);
	pos *= instance_spacing;
	pos.xz += EMISSION_TRANSFORM[3].xz;

	float seed = fract(uintBitsToFloat(RANDOM_SEED & 0x7EFFFFFFu));
	vec3 r = fract(vec3(random(pos.xz), random(pos.xz + vec2(0.5)), random(pos.xz - vec2(0.5))) + seed);
	pos.x += ((r.x * 2.0) - 1.0) * random_spacing * instance_spacing;
	pos.z += ((r.z * 2.0) - 1.0) * random_spacing * instance_spacing;

	const vec3 offsets = vec3(0.0, 1.0, 2.0);
	vec2 index_id = floor(pos.xz * _vertex_density);
	vec2 weight = fract(pos.xz * _vertex_density);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y,
		weight.x * weight.y,
		weight.x * invert.y,
		invert.x * invert.y
	);

	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy, VERTEX_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, VERTEX_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, VERTEX_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, VERTEX_PASS);

	highp float h[8];
	h[0] = texelFetch(_height_maps, index[0], 0).r;
	h[1] = texelFetch(_height_maps, index[1], 0).r;
	h[2] = texelFetch(_height_maps, index[2], 0).r;
	h[3] = texelFetch(_height_maps, index[3], 0).r;
	h[4] = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, VERTEX_PASS), 0).r;
	h[5] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, VERTEX_PASS), 0).r;
	h[6] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, VERTEX_PASS), 0).r;
	h[7] = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, VERTEX_PASS), 0).r;

	vec3 index_normal[4];
	index_normal[0] = vec3(h[0] - h[1], _vertex_spacing, h[0] - h[7]);
	index_normal[1] = vec3(h[1] - h[5], _vertex_spacing, h[1] - h[4]);
	index_normal[2] = vec3(h[2] - h[6], _vertex_spacing, h[2] - h[1]);
	index_normal[3] = vec3(h[3] - h[2], _vertex_spacing, h[3] - h[0]);
	vec3 w_normal = normalize(
		index_normal[0] * weights[0] +
		index_normal[1] * weights[1] +
		index_normal[2] * weights[2] +
		index_normal[3] * weights[3]
	);

	pos.y = h[0] * weights[0] + h[1] * weights[1] + h[2] * weights[2] + h[3] * weights[3];

	TRANSFORM = mat4(1.0);
	vec3 orientation = vec3(0.0, 1.0, 0.0);

	int stage_code = rice_stage_code_at(pos);
	if (stage_code <= 0) {
		hide_particle(pos);
	}

	if (surface_slope_min > w_normal.y + (r.y - 0.5) * condition_dither_range) {
		hide_particle(pos);
	}

	float dist = length(camera_position - pos);
	if (dist > max_dist) {
		hide_particle(pos);
	}

	float width_modifier = mix(1.0, far_width_boost, smoothstep(max_dist * 0.35, max_dist, dist));
	vec3 scale = vec3(
		mix(min_scale.x, max_scale.x, r.x) * width_modifier,
		mix(min_scale.y, max_scale.y, r.y) * rice_stage_height(stage_code),
		mix(min_scale.z, max_scale.z, r.z) * width_modifier
	);
	vec3 offset = position_offset;

	if (align_to_normal) {
		orientation = normalize(mix(orientation, w_normal, normal_strength));
		mat3 alignment = align_to_vector(orientation);
		offset = alignment * offset;
		TRANSFORM = mat4(alignment);
	}

	if (random_rotation) {
		mat3 rotation = rotation_matrix(orientation, r.x * TAU);
		TRANSFORM = mat4(rotation) * TRANSFORM;
	}

	TRANSFORM[0] *= scale.x;
	TRANSFORM[1] *= scale.y;
	TRANSFORM[2] *= scale.z;
	TRANSFORM[3].xyz = pos.xyz + offset;

	vec2 noise_uv = pos.xz * main_noise_scale;
	float noise = textureLod(main_noise, noise_uv, 0.0).r;
	vec3 tint = rice_stage_tint(stage_code) * mix(0.88, 1.12, noise);
	COLOR = vec4(tint, 1.0);
	CUSTOM.rg = r.rg;
	CUSTOM[3] = 1.0;
}
