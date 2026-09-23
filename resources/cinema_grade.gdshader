shader_type canvas_item;

// Full-frame cinematic grade for the intro cutscene.
//
// Sits on a ColorRect in a CanvasLayer between the world (0) and the letterbox
// (20), so it grades everything in shot but never tints the black bars. Godot
// applies WorldEnvironment glow after the canvas, which means this runs first
// and `flash` feeds the bloom instead of fighting it.
//
// The screen read is nearest-filtered and the grain is hashed on a fat-pixel
// grid: nothing here is allowed to soften the pixel art.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform vec2 viewport_size = vec2(1152.0, 648.0);

// Split tone. Mid grey stays put because the tints are multiplied by 2.0 and
// both average near 0.5 - only the ends of the range get pushed.
uniform vec3 shadow_tint : source_color = vec3(0.114, 0.231, 0.322);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.910, 0.784);
uniform float grade_amount : hint_range(0.0, 1.0) = 0.25;
uniform float contrast : hint_range(0.5, 2.0) = 1.03;
uniform float exposure : hint_range(0.5, 2.0) = 1.06;
// A true black lift: remaps the floor and leaves the ceiling alone, so the
// shadows open up without the highlights going milky.
uniform float lift : hint_range(0.0, 0.3) = 0.05;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.30;
uniform float vignette_softness : hint_range(0.05, 1.2) = 0.85;

uniform float grain : hint_range(0.0, 0.2) = 0.02;
uniform float grain_pixel : hint_range(1.0, 8.0) = 2.0;

// Driven from the AnimationPlayer: the frame floods warm on each blast and the
// flash is an additive spike on the ignition frame.
uniform float warmth : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

// Divides a tint by its own luma, so it shifts hue without changing how bright
// the frame is. Multiplying by a raw tint instead crushes shadows and clamps
// highlights to the tint's hue - which is the whole trap with split toning.
vec3 normalise(vec3 tint) {
	float l = dot(tint, vec3(0.2126, 0.7152, 0.0722));
	return tint / max(l, 0.001);
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	col *= exposure;
	col = mix(vec3(lift), vec3(1.0), col);
	col = (col - 0.5) * contrast + 0.5;

	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 tint = mix(shadow_tint, highlight_tint, smoothstep(0.30, 0.92, luma));
	col = mix(col, col * normalise(tint), grade_amount);

	col = mix(col, col * normalise(highlight_tint) + vec3(0.05, 0.02, 0.0), warmth);
	col += flash;

	// Aspect-corrected so the falloff is a circle on screen, not an ellipse.
	vec2 offset = SCREEN_UV - 0.5;
	offset.x *= viewport_size.x / max(viewport_size.y, 1.0);
	float dist = length(offset) / 0.5;
	float fade = smoothstep(1.0, 1.0 - vignette_softness, dist);
	col *= mix(1.0, fade, vignette_strength);

	if (grain > 0.0) {
		vec2 cell = floor(SCREEN_UV * viewport_size / grain_pixel);
		col += (hash12(cell) - 0.5) * grain;
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
