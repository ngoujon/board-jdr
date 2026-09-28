shader_type canvas_item;
render_mode blend_add;
// Bouclier divin : bulle sacrée dorée autour d'un serviteur, rendue en « gros pixels ».
// Bord lumineux, halo extérieur, alvéoles hexagonales discrètes près du bord,
// reflet qui balaie la bulle. Le centre reste transparent pour garder l'illustration lisible.

uniform vec2 rect_size = vec2(128.0, 152.0);
uniform float margin = 12.0;          // distance entre le bord du ColorRect et la bulle
uniform float corner = 16.0;
uniform float pixel = 3.0;            // taille d'un « pixel » à l'écran
uniform float intensity = 1.0;        // > 1 pendant le bris (flash)
uniform vec4 gold : source_color = vec4(1.0, 0.82, 0.32, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.98, 0.85, 1.0);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hex_lines(vec2 uv) {
	vec2 r = vec2(1.0, 1.732);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 ag = abs(g);
	float d = max(dot(ag, normalize(vec2(1.0, 1.732))), ag.x);
	return step(0.42, d);
}

void fragment() {
	// Aligne chaque fragment sur une grille de gros pixels (style 8-bit).
	vec2 px = (floor(UV * rect_size / pixel) + 0.5) * pixel;
	vec2 p = px - rect_size * 0.5;
	vec2 half_size = rect_size * 0.5 - margin;
	float d = sd_round_box(p, half_size, corner);

	float t = TIME;
	float breathe = 0.8 + 0.2 * sin(t * 2.4);

	// Bord : trait clair + liseré doré.
	float edge = 1.0 - smoothstep(0.0, 3.5, abs(d));
	float edge_gold = 1.0 - smoothstep(3.0, 7.0, abs(d));
	// Halo extérieur.
	float halo = d > 0.0 ? exp(-d / 6.0) * 0.8 : 0.0;
	// Voile intérieur, uniquement près du bord.
	float inner = d < 0.0 ? exp(d / 14.0) * 0.5 : 0.0;
	// Alvéoles près du bord, qui ondulent doucement.
	float cells = d < 0.0 ? hex_lines(px / 8.0 + vec2(0.0, t * 0.15)) * exp(d / 16.0) * 0.6 : 0.0;
	// Reflet diagonal qui parcourt la bulle.
	float s = fract((p.x * 0.6 + p.y) / (rect_size.x + rect_size.y) - t * 0.33);
	float sweep = (1.0 - smoothstep(0.0, 0.07, abs(s - 0.5))) * (d < 1.0 ? 1.0 : 0.0);
	sweep *= 0.35 + 0.65 * edge_gold;

	float a = max(max(edge, edge_gold * 0.8), max(halo, inner + cells)) * breathe + sweep * 0.55;
	vec3 col = mix(gold.rgb, core.rgb, clamp(edge + sweep, 0.0, 1.0));
	a *= intensity;
	col *= max(1.0, intensity);
	// Paliers d'opacité : pas de dégradé lisse.
	a = floor(clamp(a, 0.0, 1.0) * 6.0) / 6.0;
	// Mélange additif : la bulle éclaire le serviteur au lieu de le voiler.
	COLOR = vec4(col * a, 1.0);
}
