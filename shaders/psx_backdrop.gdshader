shader_type canvas_item;
// PSX grade for the MAIN MENU's 3D lobby backdrop ONLY (applied to the SubViewportContainer, so it
// samples the lobby render via TEXTURE and never touches the UI text on top). Ordered-dither colour
// reduction + darken + a cold desaturated wash = the warm hotel, but something's gone wrong under it.

uniform int colors : hint_range(2, 16) = 8;
uniform int dither_size : hint_range(1, 8) = 2;
uniform float darken : hint_range(0.0, 1.0) = 0.6;        // overall brightness multiply (dimmer)
uniform float desaturate : hint_range(0.0, 1.0) = 0.35;   // drain the luxury warmth
uniform vec3 cold_tint : source_color = vec3(0.84, 0.9, 1.0);

float dpat(ivec2 fc) {
	const float pattern[16] = {
		0.00, 0.50, 0.10, 0.65,
		0.75, 0.25, 0.90, 0.35,
		0.20, 0.70, 0.05, 0.55,
		0.95, 0.40, 0.80, 0.30
	};
	return pattern[(fc.y % 4) * 4 + (fc.x % 4)];
}

float reduce(float raw, float dither, int depth) {
	float div = 1.0 / float(depth);
	int i = 0;
	while (i <= 16) {
		if (raw > div * float(i + 1)) { i += 1; continue; }
		return (raw * float(depth) - float(i) <= dither * 0.999) ? div * float(i) : div * float(i + 1);
	}
	return 1.0;
}

void fragment() {
	vec4 raw = texture(TEXTURE, UV);
	ivec2 dc = ivec2(FRAGCOORD.xy / float(dither_size));
	float d = (dpat(dc) - 0.5) * dpat(dc) + 0.5;
	vec3 c = vec3(
		reduce(raw.r, d, colors - 1),
		reduce(raw.g, d, colors - 1),
		reduce(raw.b, d, colors - 1));
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(lum), desaturate);          // drain colour
	c *= cold_tint;                              // cold cast
	c *= darken;                                 // dim it
	COLOR = vec4(c, raw.a);
}
