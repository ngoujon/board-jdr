shader_type canvas_item;
// Niveaux de gris assombris : récompenses déjà récupérées du passe de combat.

void fragment() {
	vec4 c = COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * 0.7, c.a);
}
