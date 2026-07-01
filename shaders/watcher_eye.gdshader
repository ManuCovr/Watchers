shader_type spatial;
render_mode unshaded, cull_disabled;
// The watcher's single EYEBALL. The iris texture, given a subtle radial CHROMATIC ABERRATION fringe,
// and washed gently by the gameplay TELL colour (muted blue = watched, muted red = creeping). The
// wash is deliberately soft (tint < 0.5, low emission) so states read without a garish red/blue ball.

uniform sampler2D tex : source_color;
uniform vec3 tell_color : source_color = vec3(0.8, 0.8, 0.85);
uniform float tell_energy = 0.6;                  // bloom strength of the tell
uniform float tint : hint_range(0.0, 1.0) = 0.42; // how strongly the tell washes the eye
uniform float aberration = 0.006;                 // radial RGB split amount

void fragment() {
	vec2 d = UV - vec2(0.5);                       // radial from the pupil centre
	float r = texture(tex, UV + d * aberration).r;
	float g = texture(tex, UV).g;
	float b = texture(tex, UV - d * aberration).b;
	vec3 base = vec3(r, g, b);
	ALBEDO = mix(base, base * tell_color, tint);
	EMISSION = tell_color * tell_energy * 0.25;
}
