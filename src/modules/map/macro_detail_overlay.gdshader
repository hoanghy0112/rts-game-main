shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D macro_detail_texture : source_color, repeat_disable, filter_linear_mipmap;
uniform float overlay_strength : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.04;
uniform float surface_offset : hint_range(0.0, 4.0, 0.01) = 0.08;
uniform sampler2D near_hide_mask_texture : repeat_disable, filter_linear_mipmap;
uniform bool near_hide_mask_enabled = false;
uniform float near_hide_distance : hint_range(0.0, 10000.0, 1.0) = 920.0;
uniform float near_fade_distance : hint_range(0.0, 2048.0, 1.0) = 240.0;
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
	vec4 macro = texture(macro_detail_texture, UV);
	float camera_distance = length(world_xz - CAMERA_POSITION_WORLD.xz);
	float near_alpha = 1.0;
	if (near_hide_distance > 0.0 || near_fade_distance > 0.0) {
		near_alpha = smoothstep(
			near_hide_distance,
			near_hide_distance + max(near_fade_distance, 0.001),
			camera_distance
		);
	}
	float near_hide_mask = near_hide_mask_enabled ? texture(near_hide_mask_texture, UV).r : 1.0;
	near_alpha = mix(1.0, near_alpha, near_hide_mask);
	ALBEDO = macro.rgb;
	ALPHA = macro.a * overlay_strength * near_alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	ROUGHNESS = 1.0;
}
