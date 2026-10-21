// A plain coloured surface (landmarks) with the shared see-through cutaway.
shader_type spatial;

#include "res://shaders/cutaway.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool glow = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cut_away(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.75;
	if (glow) {
		EMISSION = albedo.rgb * 1.4;
	}
}
