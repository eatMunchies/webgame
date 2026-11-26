// A sheet of parchment, drawn by ParchmentPanel under its contents (text is
// never shaded). All in the panel's own units, so it looks the same at any
// screen scale:
// - a mottled grain of two noises and faint fibers;
// - edges that darken toward the border, more so on a Document;
// - on a Document (deckle 1), a torn, uneven edge;
// - at night (candle 1), the sheet leans toward candlelight: warmer, darker
//   at the edges, brighter in the middle.
// WebGL2-safe: no derivatives, no texture lookups.
shader_type canvas_item;

uniform vec4 paper_day : source_color = vec4(0.914, 0.863, 0.753, 1.0);
uniform vec4 paper_night : source_color = vec4(0.804, 0.69, 0.514, 1.0);
uniform vec4 edge_day : source_color = vec4(0.722, 0.608, 0.416, 1.0);
uniform vec4 edge_night : source_color = vec4(0.431, 0.31, 0.173, 1.0);
uniform vec4 candle_light : source_color = vec4(1.0, 0.702, 0.278, 1.0);
// The panel's size in units, set by ParchmentPanel.
uniform vec2 size = vec2(100.0, 60.0);
uniform float candle : hint_range(0.0, 1.0) = 0.0;
uniform float deckle : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 0.3) = 0.07;
// Changes the pattern, so neighbouring panels don't match.
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), s.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), s.x), s.y);
}

void fragment() {
	vec2 p = UV * size;
	vec3 paper = mix(paper_day.rgb, paper_night.rgb, candle);
	vec3 edge = mix(edge_day.rgb, edge_night.rgb, candle);

	float mottle = noise(p * 0.12) * 0.6 + noise(p * 0.45) * 0.3 + noise(p * 1.6) * 0.1;
	float fibers = smoothstep(0.82, 1.0, noise(vec2(p.x * 0.08, p.y * 1.9)));
	vec3 col = paper * (1.0 + grain * (0.5 - mottle) * 2.0) - fibers * grain * 0.6;

	// Distance to the nearest edge, roughened on a Document.
	float d = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float along = (p.x + p.y) * 0.9;
	float tear = (noise(vec2(along, seed)) - 0.5) * 2.2 + (noise(vec2(along * 3.1, seed)) - 0.5) * 0.8;
	float dd = d + tear * deckle;

	float burn = 1.0 - smoothstep(0.0, 2.5 + 4.0 * deckle, dd);
	col = mix(col, edge, burn * (0.45 + 0.25 * deckle));

	// Candlelight: warm in the middle, falling off to the edges.
	vec2 c = UV - 0.5;
	float r = dot(c, c) * 2.0;
	col = mix(col, col * (1.0 - r * 0.55) + candle_light.rgb * 0.08 * (1.0 - r), candle);

	float alpha = mix(1.0, smoothstep(0.0, 0.8, dd), deckle);
	COLOR = vec4(col, alpha);
}
