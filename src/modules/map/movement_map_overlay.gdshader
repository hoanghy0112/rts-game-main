shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D movement_map_texture : repeat_disable, filter_nearest;
uniform float overlay_strength : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.01;
uniform float surface_offset : hint_range(0.0, 4.0, 0.01) = 0.12;
uniform float max_speed_multiplier : hint_range(1.0, 4.0, 0.01) = 2.0;
uniform vec4 blocked_color : source_color = vec4(0.82, 0.08, 0.04, 0.66);
uniform vec4 slow_color : source_color = vec4(1.0, 0.63, 0.12, 0.48);
uniform vec4 normal_color : source_color = vec4(0.12, 0.54, 0.20, 0.12);
uniform vec4 road_color : source_color = vec4(0.05, 0.72, 1.0, 0.56);
uniform bool terrain_height_enabled = false;
uniform uint _background_mode = 0u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;

varying vec2 world_xz;


ivec3 get_index_coord(const vec2 uv) {
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


float sample_terrain_height(vec2 world_position) {
	const vec3 offsets = vec3(0.0, 1.0, 2.0);
	vec2 index_id = floor(world_position * _vertex_density);
	vec2 weight = fract(world_position * _vertex_density);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y,
		weight.x * weight.y,
		weight.x * invert.y,
		invert.x * invert.y
	);

	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy);
	index[1] = get_index_coord(index_id + offsets.yy);
	index[2] = get_index_coord(index_id + offsets.yx);
	index[3] = get_index_coord(index_id + offsets.xx);

	highp float h0 = index[0].z >= 0 ? texelFetch(_height_maps, index[0], 0).r : 0.0;
	highp float h1 = index[1].z >= 0 ? texelFetch(_height_maps, index[1], 0).r : h0;
	highp float h2 = index[2].z >= 0 ? texelFetch(_height_maps, index[2], 0).r : h0;
	highp float h3 = index[3].z >= 0 ? texelFetch(_height_maps, index[3], 0).r : h0;
	return h0 * weights[0] + h1 * weights[1] + h2 * weights[2] + h3 * weights[3];
}


bool has_flag(float flags, float bit_value) {
	return mod(floor(flags / bit_value), 2.0) >= 1.0;
}


void vertex() {
	vec4 world_position = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = world_position.xz;
	if (terrain_height_enabled) {
		world_position.y = sample_terrain_height(world_xz) + surface_offset;
	} else {
		world_position.y += surface_offset;
	}
	VERTEX = (inverse(MODEL_MATRIX) * world_position).xyz;
}


void fragment() {
	vec4 encoded = texture(movement_map_texture, UV);
	float speed = encoded.r * max(max_speed_multiplier, 0.001);
	float flags = floor(encoded.g * 255.0 + 0.5);
	bool blocked = speed <= 0.001 || has_flag(flags, 1.0) || has_flag(flags, 2.0);
	bool road = has_flag(flags, 8.0);

	vec4 color = normal_color;
	if (blocked) {
		color = blocked_color;
	} else if (road) {
		color = road_color;
	} else if (speed < 0.98) {
		float slow_weight = clamp((0.98 - speed) / 0.53, 0.0, 1.0);
		color = mix(normal_color, slow_color, slow_weight);
	}

	ALBEDO = color.rgb;
	ALPHA = color.a * overlay_strength;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	ROUGHNESS = 1.0;
}
