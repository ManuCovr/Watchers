shader_type spatial;
render_mode cull_back, diffuse_burley;
// The blob's FACE PLATE. Replaces the imported StandardMaterial on the face surface so we can
// transform the painted texture's UVs (the plate's authored UV island is slightly rotated, which made
// drawn faces look crooked): flip X (un-mirror) + a tunable rotation about the plate centre. Keeps the
// "talking = face glows" tell via emission_amt, and stays scene-lit like the original matte plate.

uniform sampler2D face_tex : source_color, filter_nearest;
uniform vec3 plate_color : source_color = vec3(0.91, 0.89, 0.85);
uniform bool has_tex = false;
uniform bool flip_x = true;
uniform float uv_rot = 0.0;        // radians, about UV centre
uniform float emission_amt = 0.0;  // 0 at rest, ramps up while speaking

void fragment() {
	vec2 uv = UV - vec2(0.5);
	if (flip_x) {
		uv.x = -uv.x;
	}
	float c = cos(uv_rot);
	float s = sin(uv_rot);
	uv = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + vec2(0.5);
	vec3 base = has_tex ? texture(face_tex, uv).rgb : plate_color;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = base * emission_amt;
}
