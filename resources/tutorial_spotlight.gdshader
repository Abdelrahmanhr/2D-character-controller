shader_type canvas_item;


const int MAX_HOLES = 4;

uniform vec4 holes[MAX_HOLES];
uniform float radii[MAX_HOLES];
uniform float feathers[MAX_HOLES];
uniform int hole_count : hint_range(0, 4) = 0;
uniform float dim_alpha : hint_range(0.0, 1.0) = 0.72;
uniform vec3 dim_color : source_color = vec3(0.02, 0.02, 0.04);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

float rounded_box(vec2 point, vec2 half_extents, float radius) {
	vec2 inner = max(half_extents - vec2(radius), vec2(0.0));
	vec2 d = abs(point) - inner;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 pixel = SCREEN_UV * viewport_size;

	float cover = 1.0;
	for (int i = 0; i < MAX_HOLES; i++) {
		if (i >= hole_count) {
			break;
		}
		float distance = rounded_box(pixel - holes[i].xy, holes[i].zw, radii[i]);
		float feather = max(feathers[i], 0.001);
		cover = min(cover, smoothstep(-feather, feather, distance));
	}

	COLOR = vec4(dim_color, dim_alpha * cover);
}
