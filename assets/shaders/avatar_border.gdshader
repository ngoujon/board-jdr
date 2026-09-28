shader_type canvas_item;
// Contour d'avatar en « gros pixels » : anneau carré arrondi, dégradé qui tourne,
// étincelles qui parcourent le contour. Le centre est transparent (l'avatar est dessous).

uniform vec2 rect_size = vec2(128.0, 128.0);
uniform float thickness = 8.0;
uniform float corner = 10.0;
uniform float pixel = 2.0;
uniform vec4 color_a : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform vec4 color_b : source_color = vec4(0.7, 0.45, 0.1, 1.0);
uniform float speed = 0.0;       // vitesse de rotation du dégradé (0 = fixe)
uniform float sparkle = 0.0;     // quantité d'étincelles (0 à 1)
uniform float rainbow = 0.0;     // reflets irisés (Champion)

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = (floor(UV * rect_size / pixel) + 0.5) * pixel;
	vec2 p = px - rect_size * 0.5;
	vec2 half_size = rect_size * 0.5 - 1.0;
	float d_out = sd_round_box(p, half_size, corner);
	float d_in = sd_round_box(p, half_size - thickness, max(corner - thickness, 1.0));
	float ring = step(d_out, 0.0) * step(0.0, d_in);
	if (ring < 0.5) {
		discard;
	}
	float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
	float w = 0.5 + 0.5 * sin((ang - TIME * speed * 0.25) * 6.2831853 * 2.0);
	// Biseau : bord extérieur clair, bord intérieur sombre.
	float bevel = clamp(-d_out / thickness, 0.0, 1.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, w * 0.7 + bevel * 0.3);
	col *= 1.15 - bevel * 0.35;
	if (rainbow > 0.0) {
		vec3 iris = 0.5 + 0.5 * cos(6.2831853 * (ang * 2.0 - TIME * 0.2 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, iris, rainbow * 0.35 * w);
	}
	// Étincelles : points lumineux qui défilent le long de l'anneau.
	if (sparkle > 0.0) {
		float cell = floor(ang * 48.0);
		float h = hash(vec2(cell, floor(TIME * 3.0 + cell)));
		float s = step(1.0 - sparkle * 0.18, h) * (0.6 + 0.4 * sin(TIME * 9.0 + cell));
		col = mix(col, vec3(1.0), clamp(s, 0.0, 1.0));
	}
	// Paliers de couleur (8-bit).
	col = floor(col * 8.0 + 0.5) / 8.0;
	COLOR = vec4(col, 1.0);
}
