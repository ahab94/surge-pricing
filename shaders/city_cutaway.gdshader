// The city's buildings: coloured by their vertex colours, with the shared
// see-through cutaway (cutaway.gdshaderinc).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/cutaway.gdshaderinc"

uniform bool lit_windows = false;  // the glowing-windows mesh: no lighting

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cut_away(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) {
		discard;
	}
	// Vertex colours are ordinary sRGB hex colours; light in linear space.
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.9;
	if (lit_windows) {
		EMISSION = ALBEDO;
		ALBEDO = vec3(0.0);
	}
}
