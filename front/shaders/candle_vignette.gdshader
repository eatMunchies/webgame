shader_type canvas_item;
render_mode unshaded;

// Candlelight over the town at night: a warm pool of light where the town
// shows through the HUD, falling off to a deep blue dark at the edges.
// Blended over the town, not multiplied (blend_mul doesn't draw in the
// Compatibility renderer the web build uses). `night` fades it in; at 0
// it draws nothing.

// The light's tint and how much of it lies over the middle of the pool, and
// the dark at the edges: Tokens.NIGHT_CANDLE and NIGHT_DARK, set by the town.
uniform vec4 glow;
uniform vec4 dark;
// The middle of the light (xy) and how far it reaches (zw), as shares of
// the screen. One vec4, and `night` as a vec4's x: separate floats and
// vec2s mixed with the colors came through wrong in the Compatibility
// renderer.
uniform vec4 pool = vec4(0.5, 0.5, 0.5, 0.5);
// x: 0 by day, 1 at night.
uniform vec4 night = vec4(0.0);

void fragment() {
	vec2 d = (UV - pool.xy) / max(pool.zw, vec2(0.001));
	float fall = smoothstep(0.1, 1.0, length(d));
	vec4 c = mix(glow, dark, fall);
	COLOR = vec4(c.rgb, c.a * night.x);
}
