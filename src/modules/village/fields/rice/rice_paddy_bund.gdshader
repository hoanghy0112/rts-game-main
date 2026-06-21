shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 mud_color : source_color = vec3(0.20, 0.12, 0.065);
uniform vec3 wet_mud_color : source_color = vec3(0.11, 0.075, 0.045);
uniform vec3 grass_color : source_color = vec3(0.20, 0.36, 0.11);
uniform float grass_blend : hint_range(0.0, 1.0, 0.01) = 0.44;
uniform float noise_scale : hint_range(0.01, 1.0, 0.01) = 0.09;

varying vec3 world_pos;
varying vec3 world_normal;


float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	float coarse = hash21(floor(world_pos.xz * noise_scale));
	float fine = hash21(floor(world_pos.xz * noise_scale * 3.7 + vec2(17.0, 3.0)));
	float top = smoothstep(0.42, 0.92, world_normal.y);
	float grass = clamp(grass_blend * top + coarse * 0.22 - fine * 0.10, 0.0, 1.0);
	vec3 mud = mix(wet_mud_color, mud_color, 0.35 + coarse * 0.45);
	ALBEDO = mix(mud, grass_color, grass);
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
	METALLIC = 0.0;
}
