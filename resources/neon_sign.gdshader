shader_type canvas_item;
render_mode unshaded;

// Repaints a pale tileset glyph in any neon colour.
// The source art is near-white, so its brightness is used as the mask and the
// colour is supplied here — that way one PNG can be any colour of neon.
uniform vec4 neon_color : source_color = vec4(1.0, 0.35, 0.85, 1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.6;
uniform float core_whiteness : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = max(max(tex.r, tex.g), tex.b);
	// Real neon tubes read white in the middle and coloured at the edges.
	vec3 tinted = mix(neon_color.rgb, vec3(1.0), core_whiteness * lum);
	COLOR = vec4(tinted * lum * brightness, tex.a * neon_color.a);
}
