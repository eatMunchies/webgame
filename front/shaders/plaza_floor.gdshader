shader_type canvas_item;

// The start screen's floor: a checkerboard of pale tiles that fades into a
// soft void with distance from `focus`, so the floor seems to go on forever
// around the player. Tiles are laid out in world pixels, so the pattern
// stays put however the rect drawing it moves (see PlazaFloor).
//
// `reveal` dissolves the floor tile by tile, from `reveal_origin` outward,
// as it goes from 0 (all there) to 1 (all gone). The town uses that to phase
// in around the player's house.

uniform float tile_size = 16.0;
uniform vec4 tile_light : source_color = vec4(0.94, 0.95, 0.96, 1.0);
uniform vec4 tile_dark : source_color = vec4(0.83, 0.86, 0.9, 1.0);
uniform vec4 void_color : source_color = vec4(0.69, 0.74, 0.83, 1.0);
// Where the floor is clearest, in world pixels.
uniform vec2 focus;
// The floor is solid within fade_start world pixels of focus and all void
// past fade_end.
uniform float fade_start = 48.0;
uniform float fade_end = 150.0;
uniform vec2 reveal_origin;
// Tiles this far from reveal_origin are the last to go.
uniform float reveal_span = 320.0;
uniform float reveal = 0.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 tile = floor(world / tile_size);
	// 0 on light tiles, 1 on dark ones.
	vec4 floor_color = mix(tile_light, tile_dark, mod(tile.x + tile.y, 2.0));
	float fade = smoothstep(fade_start, fade_end, distance(world, focus));
	// When this tile goes, from 0 to 1: mostly by distance, with a little
	// noise so the edge is ragged. It's gone once reveal passes it.
	vec2 middle = (tile + 0.5) * tile_size;
	float goes_at = clamp(distance(middle, reveal_origin) / reveal_span, 0.0, 1.0) * 0.8 + hash(tile) * 0.2;
	COLOR = vec4(mix(floor_color, void_color, fade).rgb, step(reveal, goes_at));
}
