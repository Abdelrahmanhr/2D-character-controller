shader_type canvas_item;

uniform vec4 screen_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float screen_boost : hint_range(0.5, 4.0) = 1.4;
uniform float red_max_ratio : hint_range(0.0, 1.5) = 0.45;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float peak = max(c.g, c.b);
	if (c.a > 0.01 && peak > 0.02 && c.r < peak * red_max_ratio) {
		c.rgb = screen_color.rgb * max(c.r, peak) * screen_boost;
	}
	COLOR = c;
}
