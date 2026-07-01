shader_type canvas_item;
// CRT warp for the HUD SubViewport. Applied to a full-screen TextureRect whose texture is the rendered
// HUD. The 3D world is NOT touched — only the HUD chrome bows. Center stays ~undistorted (so the
// crosshair + bottom-middle prompt read crisp); corners bow with scanlines + chromatic fringing.

uniform float curve_amount : hint_range(0.0, 0.5) = 0.10;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.16;
uniform float aberration : hint_range(0.0, 0.02) = 0.0035;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;
uniform float flicker_strength : hint_range(0.0, 0.2) = 0.03;
uniform bool enable_curve = true;
uniform bool enable_scanlines = true;
uniform bool enable_chromatic = true;
uniform bool reduced_motion = false;

vec2 barrel(vec2 uv) {
	vec2 cc = uv - 0.5;
	float d = dot(cc, cc);
	return uv + cc * d * curve_amount;
}

void fragment() {
	vec2 uv = enable_curve ? barrel(UV) : UV;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);          // beyond the bowed frame = transparent
	} else {
		float edge = clamp(length(uv - 0.5) * 1.4, 0.0, 1.0);
		vec4 col;
		if (enable_chromatic) {
			float a = aberration * (0.35 + edge);   // fringe grows toward the corners
			float r = texture(TEXTURE, uv + vec2(a, 0.0)).r;
			float b = texture(TEXTURE, uv - vec2(a, 0.0)).b;
			vec4 mid = texture(TEXTURE, uv);
			col = vec4(r, mid.g, b, mid.a);
		} else {
			col = texture(TEXTURE, uv);
		}
		if (enable_scanlines) {
			float line = 0.5 + 0.5 * sin(uv.y / max(TEXTURE_PIXEL_SIZE.y, 0.00001) * 3.14159);
			col.rgb *= 1.0 - scanline_strength * line;
		}
		col.rgb *= mix(1.0, smoothstep(1.25, 0.35, edge), vignette_strength);
		if (!reduced_motion) {
			col.rgb *= 1.0 - flicker_strength * (0.5 + 0.5 * sin(TIME * 8.0));
		}
		COLOR = col;
	}
}
