// The machine's glass, laid over a SystemPanel's contents: faint horizontal
// scanlines every few screen pixels (so they stay crisp at any scale), a
// slight darkening toward the edges, and, while `glitch` is above 0 (only
// for a moment, when a panel opens), torn horizontal slices of light.
// WebGL2-safe.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.08;
// Screen pixels from one scanline to the next.
uniform float spacing = 3.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(0.275, 0.878, 0.878, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float line = step(0.5, fract(FRAGCOORD.y / spacing));
	vec2 c = UV - 0.5;
	float vignette = smoothstep(0.15, 0.5, dot(c, c));
	float a = line * strength + vignette * strength * 0.8;
	vec3 col = vec3(0.0);
	if (glitch > 0.0) {
		float band = floor(UV.y * 24.0);
		float on = step(1.0 - glitch * 0.35, hash(band + floor(TIME * 30.0)));
		col = mix(col, accent.rgb, on);
		a = max(a, on * 0.25 * glitch);
	}
	COLOR = vec4(col, a);
}
