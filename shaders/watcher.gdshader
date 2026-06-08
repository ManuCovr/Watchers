shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
// The Watcher's body = a shimmering hole in reality: it refracts the room behind it (wave +
// chromatic aberration) and a slow starfield drifts across it. Eerie, biblically-accurate-angel.

uniform sampler2D screen_texture: hint_screen_texture;

group_uniforms render;
uniform vec4 sphere_color: source_color = vec4(0.0, 0.0, 0.02, 0.35);

group_uniforms effects;
uniform float wave_amplitude: hint_range(0.0, 0.01) = 0.006;
uniform float wave_frequency: hint_range(0.0, 20.0) = 19.397;
uniform float wave_speed: hint_range(0.0, 10.0) = 3.618;
uniform float chroma_amount: hint_range(0.0, 1.0) = 1.0;

group_uniforms stars;
uniform bool stars_enabled = true;
uniform float star_field_scale: hint_range(1.0, 50.0) = 4.377;
uniform float star_size: hint_range(0.001, 0.05) = 0.008;
uniform float star_intensity: hint_range(0.0, 1.0) = 1.0;
uniform float star_axis_speed: hint_range(0.0, 0.5) = 0.051;
uniform int star_move_mode: hint_range(0, 3) = 1;

float random(vec2 st) {
	return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 wave_offset = vec2(
		sin(SCREEN_UV.y * wave_frequency + TIME * wave_speed),
		sin(SCREEN_UV.x * wave_frequency + TIME * wave_speed)
	) * wave_amplitude;

	vec2 distorted_uv = SCREEN_UV + wave_offset;
	vec2 red_uv   = distorted_uv + wave_offset * chroma_amount;
	vec2 blue_uv  = distorted_uv - wave_offset * chroma_amount;
	vec2 green_uv = distorted_uv;

	float r = texture(screen_texture, red_uv).r;
	float g = texture(screen_texture, green_uv).g;
	float b = texture(screen_texture, blue_uv).b;
	vec4 scene_color = vec4(r, g, b, 1.0);

	vec3 final_color = mix(scene_color.rgb, sphere_color.rgb, sphere_color.a);

	float star_accum = 0.0;
	if (stars_enabled) {
		vec2 moving_uv = UV;
		vec2 offset = vec2(0.0);
		if (star_move_mode == 0) { offset = vec2(0.0, TIME * star_axis_speed); }
		else if (star_move_mode == 1) { offset = vec2(TIME * star_axis_speed, 0.0); }
		else if (star_move_mode == 2) { offset = vec2(TIME * star_axis_speed, TIME * star_axis_speed); }
		else if (star_move_mode == 3) { offset = vec2(sin(TIME * star_axis_speed * 1.3), cos(TIME * star_axis_speed * 1.7)); }
		moving_uv += offset;
		moving_uv = fract(moving_uv);
		vec2 grid_uv = moving_uv * star_field_scale;
		vec2 id = floor(grid_uv);
		vec2 f = fract(grid_uv) - 0.5;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 neighbor = vec2(float(i), float(j));
				vec2 cell_id = id + neighbor;
				vec2 star_pos = vec2(random(cell_id), random(cell_id * 1.3)) - 0.5;
				float d = length(f - star_pos);
				float star = (1.0 - smoothstep(star_size * 0.5, star_size, d));
				star_accum += star;
			}
		}
		star_accum = clamp(star_accum, 0.0, 1.0);
	}

	final_color = mix(final_color, vec3(1.0), star_intensity * star_accum);
	ALBEDO = final_color;
	ALPHA = 1.0;
}
