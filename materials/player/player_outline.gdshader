// Inverted-hull outline for the blob player models. Used as a `next_pass` on each body/face
// material by PlayerModelView (NOT baked into the GLB). It re-draws the mesh expanded outward,
// showing only back faces (cull_front), in a flat dark color -> a thin readable silhouette that
// fits the PSX / friendslop look.
//
// IMPORTANT: the blob is FLAT-SHADED (hard normals), so expanding along NORMAL splits the outline
// shell at every hard edge -> gaps / "outline doesn't wrap". Instead we expand each vertex along
// the direction from the model CENTRE (model_center). For a convex-ish blob that gives ONE
// continuous gap-free shell. Falls back to NORMAL if a vertex sits exactly on the centre.
//
// thickness is in MODEL space, so ~0.02-0.03 reads as a couple of cm on a ~1.5 m blob.
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, specular_disabled;

uniform float thickness : hint_range(0.0, 0.08) = 0.02;
uniform vec4 outline_color : source_color = vec4(0.04, 0.04, 0.05, 1.0);
uniform vec3 model_center = vec3(0.0);

void vertex() {
	vec3 dir = VERTEX - model_center;
	float len = length(dir);
	vec3 grow = (len > 0.0001) ? dir / len : normalize(NORMAL);
	VERTEX += grow * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
