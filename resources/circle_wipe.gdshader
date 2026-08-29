shader_type canvas_item;
uniform float radius : hint_range(0.0, 1.6) = 1.6;
uniform vec2 center = vec2(0.5, 0.5);
uniform float aspect = 1.0;

void fragment() {
	vec2 uv = UV - center;
	uv.x *= aspect;
	COLOR = vec4(0.0, 0.0, 0.0, step(radius, length(uv)));
}
