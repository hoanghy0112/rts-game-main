shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.23, 0.48, 0.14, 1.0);
uniform vec4 dark_color : source_color = vec4(0.13, 0.33, 0.09, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.68, 0.21, 1.0);
uniform float overlay_alpha : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float patch_size_meters : hint_range(0.25, 32.0, 0.25) = 3.5;
uniform float edge_fade_uv : hint_range(0.0, 0.3, 0.005) = 0.035;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.04;

varying vec2 local_xz;


float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}


void vertex() {
	local_xz = VERTEX.xz;
}


void fragment() {
	float safe_patch_size = max(patch_size_meters, 0.01);
	vec2 coarse_cell = floor(local_xz / safe_patch_size);
	vec2 fine_cell = floor(local_xz / max(safe_patch_size * 0.42, 0.01));
	float coarse_noise = hash21(coarse_cell);
	float fine_noise = hash21(fine_cell + vec2(19.7, 5.3));
	float field_stripe = 0.5 + 0.5 * sin((local_xz.x + local_xz.y * 0.37) * 1.65);
	vec3 varied_color = mix(dark_color.rgb, light_color.rgb, smoothstep(0.12, 0.92, coarse_noise));
	vec3 rice_color = mix(varied_color, base_color.rgb, 0.55);
	rice_color *= 0.86 + fine_noise * 0.18 + field_stripe * 0.08;

	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge_alpha = smoothstep(0.0, max(edge_fade_uv, 0.001), edge_distance);
	float alpha_noise = 0.82 + coarse_noise * 0.18;

	ALBEDO = rice_color;
	ALPHA = overlay_alpha * edge_alpha * alpha_noise;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	ROUGHNESS = 1.0;
}
