// Shared see-through cutaway (included by the city and landmark shaders).
// Any part of a building that hides ROAD near the car, or near the route
// ahead, becomes a faint dithered ghost. The values are global shader
// parameters, set once per frame by view3d.gd, so every material agrees.
//
// How: follow the line from the camera through this pixel down to the ground.
// If it lands on a drivable tile (cut_road_mask, one texel per tile) close to
// one of the two focus points, drop most of this pixel's neighbours in a
// fixed 4x4 pattern: no transparency sorting, just fewer pixels.

global uniform vec3 cut_focus;        // the car
global uniform vec3 cut_focus2;       // a point a few tiles along the route
global uniform float cut_on;          // 1 while driving
global uniform sampler2D cut_road_mask : filter_nearest;

const float CUT_RADIUS = 16.0;        // world units (a tile is 4)
const float CUT_TILE = 4.0;

float cut_bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

// True if this pixel should be dropped.
bool cut_away(vec3 world_pos, vec3 cam, vec2 frag) {
	if (cut_on < 0.5 || world_pos.y < 0.45) {
		return false;
	}
	vec3 dir = world_pos - cam;
	if (dir.y >= 0.0) {
		return false;
	}
	vec3 ground = cam + dir * (-cam.y / dir.y);   // the ground this pixel hides
	float d = min(length(ground.xz - cut_focus.xz), length(ground.xz - cut_focus2.xz));
	if (d > CUT_RADIUS) {
		return false;
	}
	ivec2 cell = ivec2(floor(ground.xz / CUT_TILE));
	ivec2 size = textureSize(cut_road_mask, 0);
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y
			|| texelFetch(cut_road_mask, cell, 0).r < 0.5) {
		return false;
	}
	float amount = 0.92 * smoothstep(CUT_RADIUS, CUT_RADIUS - 5.0, d);
	return amount > cut_bayer4(frag);
}
