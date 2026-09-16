shader_type canvas_item;
uniform float radius : hint_range(0.0, 1.6) = 1.6;
uniform vec2 center = vec2(0.5, 0.5);
uniform float aspect = 1.0;
uniform vec2 viewport_size = vec2(1152.0, 648.0);
// Screen pixels per pixelation block -- same floor-to-a-grid trick SafeZone's
// overlay shader uses (there in world units, here in screen units), so the
// wipe's edge steps in chunky blocks instead of a smooth antialiased circle.
uniform float pixel_scale : hint_range(1.0, 16.0) = 6.0;

void fragment() {
	vec2 pixelated_screen = floor(UV * viewport_size / pixel_scale) * pixel_scale;
	vec2 uv = (pixelated_screen / viewport_size) - center;
	uv.x *= aspect;
	COLOR = vec4(0.0, 0.0, 0.0, step(radius, length(uv)));
}
