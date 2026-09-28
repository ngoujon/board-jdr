class_name Fx3D
extends CanvasLayer
## Effets visuels 3D superposés au jeu 2D pixel art.
## Un SubViewport 3D transparent couvre l'écran ; une caméra en perspective est placée
## de sorte que le plan z = 0 corresponde exactement aux coordonnées écran (100 px = 1 unité).
## Les effets utilisent des particules cubiques (« voxels ») éclairées, des maillages émissifs,
## des anneaux d'onde de choc et des trajectoires qui plongent vers la caméra.

const PX_PER_UNIT := 100.0
const SCREEN := Vector2(1280, 720)
const FOV := 50.0

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _particle_mat: StandardMaterial3D
var _cube_mesh: BoxMesh


func _init() -> void:
	layer = 50


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = Vector2i(SCREEN)
	container.add_child(_vp)

	_world = Node3D.new()
	_vp.add_child(_world)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.position = Vector3(0, 0, (SCREEN.y / 2.0 / PX_PER_UNIT) / tan(deg_to_rad(FOV / 2.0)))
	_cam.far = 100.0
	_world.add_child(_cam)
	_cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	_world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.8)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	_particle_mat = StandardMaterial3D.new()
	_particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_particle_mat.vertex_color_use_as_albedo = true
	_particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE * 0.11
	_cube_mesh.material = _particle_mat


# ------------------------------------------------------------------ utilitaires

func to3d(p: Vector2, z := 0.0) -> Vector3:
	return Vector3((p.x - SCREEN.x / 2) / PX_PER_UNIT, -(p.y - SCREEN.y / 2) / PX_PER_UNIT, z)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


func _free_later(n: Node, t: float) -> void:
	get_tree().create_timer(t, false).timeout.connect(func():
		if is_instance_valid(n):
			n.queue_free())


func _emissive(color: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _glass(color: Color, alpha := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	m.rim_enabled = true
	m.rim = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _gradient(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / max(1, colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _fade_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(0.7, 0.8))
	c.add_point(Vector2(1, 0))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Crée un émetteur de particules cubiques.
func _particles(pos: Vector3, colors: Array, amount: int, lifetime: float, speed := Vector2(2, 5),
		size := 1.0, gravity := Vector3(0, -6, 0), one_shot := true, radius := 0.1,
		direction := Vector3.UP, spread := 180.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.direction = direction
	m.spread = spread
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = gravity
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = size * 0.5
	m.scale_max = size * 1.2
	m.scale_curve = _fade_curve()
	m.color_ramp = _gradient(colors)
	m.angular_velocity_min = -540
	m.angular_velocity_max = 540
	m.particle_flag_rotate_y = true
	m.angle_min = -180
	m.angle_max = 180
	p.process_material = m
	p.draw_pass_1 = _cube_mesh
	p.position = pos
	_world.add_child(p)
	p.emitting = true
	if one_shot:
		_free_later(p, lifetime + 0.3)
	return p


func _ring(pos: Vector3, color: Color, tilt_deg: float, from_scale: float, to_scale: float,
		duration: float, thickness := 0.08, energy := 4.0) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5 - thickness
	torus.outer_radius = 0.5
	torus.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	var mat := _emissive(color, energy, 0.95)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = tilt_deg
	mi.scale = Vector3.ONE * from_scale
	_world.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * to_scale, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, duration).set_ease(Tween.EASE_IN)
	_free_later(mi, duration + 0.1)
	return mi


func _flash_light(pos: Vector3, color: Color, energy := 6.0, duration := 0.4) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 4.0
	l.position = pos + Vector3(0, 0, 1)
	_world.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	_free_later(l, duration + 0.1)


func _bezier(a: Vector3, ctrl: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)


# ------------------------------------------------------------------ effets de base

func impact(at: Vector2, color := Color(1, 0.9, 0.6)) -> void:
	var p := to3d(at, 0.3)
	_particles(p, [Color.WHITE, color, Color(color, 0.0)], 26, 0.5, Vector2(2, 5), 0.8, Vector3(0, -8, 0))
	_ring(p, color, 70, 0.2, 1.6, 0.3, 0.06, 3.0)


func explosion(at: Vector2, colors: Array, scale_mult := 1.0) -> void:
	var p := to3d(at, 0.4)
	_particles(p, colors, int(70 * scale_mult), 0.9, Vector2(3, 8) * scale_mult, 1.3 * scale_mult, Vector3(0, -7, 0), true, 0.2)
	_particles(p, [Color(0.3, 0.3, 0.3, 0.8), Color(0.1, 0.1, 0.1, 0.0)], int(20 * scale_mult), 1.2, Vector2(0.5, 1.5), 2.0 * scale_mult, Vector3(0, 1.5, 0), true, 0.3)
	_ring(p, colors[1], 75, 0.3, 3.2 * scale_mult, 0.45, 0.07, 5.0)
	_ring(p, colors[0], 20, 0.2, 2.2 * scale_mult, 0.35, 0.05, 5.0)
	_flash_light(p, colors[1], 8.0, 0.5)


## Projectile générique (sphère lumineuse + traînée) sur une trajectoire qui plonge vers la caméra.
func _projectile(from: Vector2, to: Vector2, core_color: Color, trail_colors: Array, radius: float,
		duration: float, arc_z := 2.5) -> void:
	var a := to3d(from, 0.5)
	var b := to3d(to, 0.3)
	var ctrl := (a + b) / 2 + Vector3(0, 0.8, arc_z)
	var holder := Node3D.new()
	holder.position = a
	_world.add_child(holder)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	core.mesh = sphere
	core.material_override = _emissive(core_color, 6.0)
	holder.add_child(core)

	var shell := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = radius * 1.6
	s2.height = radius * 3.2
	s2.radial_segments = 8
	s2.rings = 4
	shell.mesh = s2
	shell.material_override = _emissive(trail_colors[1], 2.0, 0.35)
	holder.add_child(shell)

	var light := OmniLight3D.new()
	light.light_color = core_color
	light.light_energy = 3.0
	light.omni_range = 3.0
	holder.add_child(light)

	var trail := _particles(Vector3.ZERO, trail_colors, 90, 0.45, Vector2(0.2, 1.0), 1.1, Vector3(0, 1.5, 0), false, radius * 0.8)
	trail.reparent(holder, false)

	var tw := holder.create_tween()
	tw.tween_method(func(t: float):
		holder.position = _bezier(a, ctrl, b, t)
		shell.rotation += Vector3(0.3, 0.5, 0.2)
		shell.scale = Vector3.ONE * (1.0 + sin(t * 40.0) * 0.15), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	trail.emitting = false
	trail.reparent(_world)
	_free_later(trail, 0.6)
	holder.queue_free()


# ------------------------------------------------------------------ effets de cartes

func fireball(from: Vector2, to: Vector2) -> void:
	Audio.play_sfx("fire")
	await _projectile(from, to, Color(1.0, 0.7, 0.2), [Color(1, 0.8, 0.3), Color(1, 0.4, 0.05), Color(0.7, 0.08, 0.02, 0.6), Color(0.2, 0.05, 0.05, 0.0)], 0.28, 0.6)
	explosion(to, [Color(1, 0.85, 0.25), Color(1, 0.4, 0.05), Color(0.6, 0.05, 0.0, 0.0)], 1.2)


func lightning(from: Vector2, to: Vector2) -> void:
	Audio.play_sfx("lightning")
	var a := to3d(from, 0.5)
	var b := to3d(to, 0.2)
	var mat := _emissive(Color(0.7, 0.4, 1.0), 2.5)
	for flicker in 4:
		var bolt := Node3D.new()
		_world.add_child(bolt)
		var pts: Array[Vector3] = [a]
		var n := 9
		for i in range(1, n):
			var t := float(i) / n
			pts.append(a.lerp(b, t) + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(0, 1.2) * sin(t * PI)))
		pts.append(b)
		for i in range(pts.size() - 1):
			_segment(bolt, pts[i], pts[i + 1], 0.045 if flicker % 2 == 0 else 0.03, mat)
		_flash_light(b, Color(0.7, 0.5, 1.0), 5.0, 0.12)
		await _wait(0.07)
		bolt.queue_free()
	_particles(b, [Color.WHITE, Color(0.7, 0.5, 1.0), Color(0.3, 0.1, 0.6, 0.0)], 50, 0.6, Vector2(3, 7), 0.8, Vector3(0, -9, 0))
	_ring(b, Color(0.7, 0.5, 1.0), 70, 0.2, 2.4, 0.35)


func _segment(parent: Node3D, p1: Vector3, p2: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = p1.distance_to(p2)
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = (p1 + p2) / 2
	var dir := (p2 - p1).normalized()
	var up := Vector3.UP
	var axis := up.cross(dir)
	if axis.length() > 0.0001:
		mi.basis = Basis(axis.normalized(), up.angle_to(dir))


func heal(at: Vector2) -> void:
	Audio.play_sfx("heal")
	var p := to3d(at, 0.0)
	var em := _particles(p + Vector3(0, -0.5, 0), [Color(0.7, 1, 0.7), Color(0.3, 1, 0.4), Color(1, 1, 0.6, 0.0)], 70, 1.2, Vector2(1.0, 2.5), 0.9, Vector3(0, 2.5, 0), true, 0.7, Vector3.UP, 25)
	em.explosiveness = 0.4
	for i in 3:
		var r := _ring(p + Vector3(0, -0.6 + i * 0.1, 0), Color(0.4, 1, 0.5), 70, 1.4, 0.9, 1.1, 0.05, 4.0)
		var tw := r.create_tween()
		tw.tween_property(r, "position:y", p.y + 0.9, 1.1)
		await _wait(0.18)
	await _wait(0.3)


func buff(at: Vector2) -> void:
	Audio.play_sfx("buff")
	var p := to3d(at, 0.0)
	# Colonne de lumière dorée.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 6.0
	beam.mesh = cyl
	var mat := _emissive(Color(1, 0.85, 0.3), 3.0, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = mat
	beam.position = p + Vector3(0, 3, -0.3)
	beam.scale = Vector3(0.1, 1, 0.1)
	_world.add_child(beam)
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(1, 1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(beam, "scale", Vector3(0.01, 1, 0.01), 0.3)
	_free_later(beam, 1.0)
	# Anneau runique en rotation autour de la cible.
	var ring := _ring(p, Color(1, 0.8, 0.2), 65, 1.6, 1.2, 0.9, 0.06, 5.0)
	var rt := ring.create_tween()
	rt.tween_property(ring, "rotation_degrees:y", 360.0, 0.9)
	_particles(p, [Color(1, 1, 0.8), Color(1, 0.8, 0.2), Color(1, 0.6, 0.1, 0.0)], 50, 0.9, Vector2(1.5, 4), 0.7, Vector3(0, 3, 0), true, 0.5)
	await _wait(0.6)


func frost(targets: Array) -> void:
	Audio.play_sfx("frost")
	# Neige tourbillonnante sur tout le plateau adverse.
	var snow := _particles(to3d(Vector2(640, 150), 0.5), [Color(1, 1, 1, 0.9), Color(0.7, 0.9, 1, 0.0)], 120, 1.6, Vector2(0.5, 1.5), 0.6, Vector3(0.6, -3, 0), true, 3.0)
	snow.explosiveness = 0.2
	var shard_mat := _glass(Color(0.6, 0.9, 1.0), 0.75)
	var shards: Array[MeshInstance3D] = []
	for at in targets:
		var p := to3d(at, 0.2)
		var shard := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.22
		cone.height = 1.0
		cone.radial_segments = 5
		shard.mesh = cone
		shard.material_override = shard_mat
		shard.position = p + Vector3(randf_range(-0.8, 0.8), 4.5, 2.5)
		shard.rotation_degrees = Vector3(180, 0, 0)
		_world.add_child(shard)
		shards.append(shard)
		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "position", p, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(shard, "rotation_degrees:y", 540.0, 0.4)
		await _wait(0.06)
	await _wait(0.4)
	for i in shards.size():
		var p := shards[i].position
		shards[i].queue_free()
		_particles(p, [Color.WHITE, Color(0.6, 0.9, 1.0), Color(0.3, 0.6, 1.0, 0.0)], 40, 0.7, Vector2(2, 6), 1.0, Vector3(0, -8, 0))
		_ring(p, Color(0.6, 0.9, 1.0), 75, 0.2, 2.0, 0.4, 0.06, 4.0)
	await _wait(0.2)


func arrow(from: Vector2, to: Vector2) -> void:
	Audio.play_sfx("attack")
	var a := to3d(from, 0.5)
	var b := to3d(to, 0.2)
	var ctrl := (a + b) / 2 + Vector3(0, 1.2, 1.5)
	var arrow_node := Node3D.new()
	_world.add_child(arrow_node)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 0.8
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.35, 0.15)
	shaft.material_override = wood
	shaft.rotation_degrees.x = 90
	arrow_node.add_child(shaft)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.18
	tip.mesh = cone
	tip.material_override = _emissive(Color(0.85, 0.9, 1.0), 2.0)
	tip.rotation_degrees.x = -90
	tip.position = Vector3(0, 0, -0.48)
	arrow_node.add_child(tip)
	var trail := _particles(Vector3.ZERO, [Color(1, 1, 1, 0.8), Color(0.9, 0.95, 1, 0.0)], 40, 0.3, Vector2(0, 0.3), 0.5, Vector3.ZERO, false, 0.05)
	trail.reparent(arrow_node, false)
	var prev := [a]   # tableau : les lambdas ne peuvent pas réassigner une variable capturée
	var tw := arrow_node.create_tween()
	tw.tween_method(func(t: float):
		var pos := _bezier(a, ctrl, b, t)
		arrow_node.position = pos
		if pos.distance_to(prev[0]) > 0.001:
			arrow_node.look_at(pos + (pos - prev[0]), Vector3.UP)
		arrow_node.rotate_object_local(Vector3.FORWARD, t * 12.0)
		prev[0] = pos, 0.0, 1.0, 0.45)
	await tw.finished
	trail.emitting = false
	trail.reparent(_world)
	_free_later(trail, 0.4)
	arrow_node.queue_free()
	impact(to, Color(1, 0.85, 0.5))


func summon(at: Vector2) -> void:
	Audio.play_sfx("summon")
	var p := to3d(at, 0.0)
	var portal := _ring(p + Vector3(0, -0.4, 0), Color(0.5, 1.0, 0.4), 72, 0.1, 1.8, 1.0, 0.12, 5.0)
	var tw := portal.create_tween()
	tw.tween_property(portal, "rotation_degrees:y", 720.0, 1.0)
	_ring(p + Vector3(0, -0.4, 0), Color(0.6, 0.2, 0.9), 72, 1.8, 0.2, 0.8, 0.08, 5.0)
	var em := _particles(p + Vector3(0, -0.4, 0), [Color(0.8, 1, 0.6), Color(0.4, 0.9, 0.3), Color(0.5, 0.1, 0.7, 0.0)], 80, 1.0, Vector2(1, 3), 0.8, Vector3(0, 3, 0), true, 0.8, Vector3.UP, 30)
	em.explosiveness = 0.5
	_flash_light(p, Color(0.5, 1, 0.4), 5.0, 0.6)
	await _wait(0.5)


## Bris du bouclier divin : éclats dorés qui volent en tournoyant, onde de choc et flash.
func shield_pop(at: Vector2) -> void:
	Audio.play_sfx("shield")
	var p := to3d(at, 0.3)
	_flash_light(p, Color(1, 0.9, 0.5), 7.0, 0.35)
	_ring(p, Color(1, 0.88, 0.45), 0.0, 0.8, 2.6, 0.4, 0.06, 5.0)
	_ring(p, Color(1, 1, 0.9), 0.0, 0.6, 1.8, 0.25, 0.04, 6.0)
	var shard_mesh := PrismMesh.new()
	shard_mesh.size = Vector3(0.16, 0.26, 0.03)
	for i in 14:
		var shard := MeshInstance3D.new()
		shard.mesh = shard_mesh
		var mat := _emissive(Color(1, 0.85, 0.35) if i % 3 else Color(1, 0.98, 0.85), 3.5, 0.95)
		shard.material_override = mat
		var ang := TAU * i / 14.0 + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), sin(ang), randf_range(0.2, 0.8))
		# Les éclats partent du contour de la bulle.
		shard.position = p + Vector3(dir.x * 0.55, dir.y * 0.7, 0)
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, ang)
		shard.scale = Vector3.ONE * randf_range(0.7, 1.3)
		_world.add_child(shard)
		var dist := randf_range(1.0, 1.8)
		var dur := randf_range(0.45, 0.65)
		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "position", shard.position + dir * dist + Vector3(0, -0.5, 0), dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", shard.rotation + Vector3(randf_range(4, 9), randf_range(4, 9), 0), dur)
		tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, dur).set_ease(Tween.EASE_IN)
		_free_later(shard, dur + 0.1)
	_particles(p, [Color.WHITE, Color(1, 0.85, 0.3), Color(1, 0.6, 0.1, 0.0)], 50, 0.6, Vector2(3, 7), 1.0, Vector3(0, -9, 0), true, 0.5)
	await _wait(0.3)


func death(at: Vector2) -> void:
	var p := to3d(at, 0.2)
	_particles(p, [Color(0.6, 0.6, 0.65, 0.9), Color(0.25, 0.25, 0.3, 0.7), Color(0.1, 0.1, 0.1, 0.0)], 45, 1.1, Vector2(0.5, 2.5), 1.4, Vector3(0, 2.0, 0), true, 0.5)
	_particles(p, [Color(0.8, 0.5, 1.0), Color(0.4, 0.1, 0.6, 0.0)], 20, 0.8, Vector2(1, 3), 0.6, Vector3(0, 3.0, 0), true, 0.3)


func dragon_fire(from: Vector2, targets: Array) -> void:
	Audio.play_sfx("fire")
	var a := to3d(from, 0.3)
	_ring(a, Color(1, 0.5, 0.1), 80, 0.3, 9.0, 0.8, 0.1, 6.0)
	_ring(a, Color(1, 0.9, 0.4), 60, 0.3, 6.0, 0.6, 0.06, 6.0)
	_particles(a, [Color(1, 1, 0.7), Color(1, 0.5, 0.1), Color(0.6, 0.1, 0.0, 0.0)], 160, 1.0, Vector2(4, 10), 1.3, Vector3(0, -2, 0), true, 0.4)
	_flash_light(a, Color(1, 0.5, 0.1), 10.0, 0.8)
	for t in targets:
		_projectile(from, t, Color(1, 0.6, 0.2), [Color(1, 0.9, 0.5), Color(1, 0.45, 0.1), Color(0.5, 0.1, 0.0, 0.0)], 0.16, 0.35, 1.2)
	await _wait(0.38)
	for t in targets:
		explosion(t, [Color(1, 0.8, 0.2), Color(1, 0.35, 0.05), Color(0.6, 0.05, 0.0, 0.0)], 0.6)


## Cartes 3D qui volent du deck vers la main en tournoyant.
func draw_cards(from: Vector2, to: Vector2, count := 1, back: Texture2D = null) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = back if back else CardDB.texture("res://assets/ui/card_back.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.3, 0.6)
	mat.emission_energy_multiplier = 0.4
	for i in count:
		var card := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 1.12, 0.03)
		card.mesh = box
		card.material_override = mat
		var a := to3d(from, 0.5)
		var b := to3d(to + Vector2(i * 40 - (count - 1) * 20, 0), 0.5)
		var ctrl := (a + b) / 2 + Vector3(0, 1.0, 3.0)
		_world.add_child(card)
		var trail := _particles(Vector3.ZERO, [Color(0.7, 0.85, 1, 0.9), Color(0.3, 0.5, 1, 0.0)], 40, 0.4, Vector2(0, 0.4), 0.5, Vector3.ZERO, false, 0.2)
		trail.reparent(card, false)
		var tw := card.create_tween()
		tw.tween_method(func(t: float):
			card.position = _bezier(a, ctrl, b, t)
			card.rotation = Vector3(sin(t * PI) * 0.6, t * TAU * 1.5, sin(t * PI) * 0.3), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func():
			trail.emitting = false
			trail.reparent(_world)
			_free_later(trail, 0.5)
			card.queue_free())
		await _wait(0.15)
	await _wait(0.5)


## Braises flottantes (menu principal).
func ambient_embers() -> GPUParticles3D:
	var p := _particles(Vector3(0, -4.5, -1), [Color(1, 0.8, 0.3, 0.0), Color(1, 0.6, 0.2, 0.9), Color(1, 0.3, 0.1, 0.0)], 90, 6.0, Vector2(0.4, 1.2), 0.45, Vector3(0.15, 0.4, 0), false, 7.0, Vector3.UP, 20)
	(p.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(p.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(8, 0.3, 2)
	p.preprocess = 6.0
	return p


## Feu d'artifice doré (victoire).
func fireworks(count := 6) -> void:
	for i in count:
		var at := Vector2(randf_range(250, 1030), randf_range(120, 420))
		var hue := randf()
		var col := Color.from_hsv(hue, 0.6, 1.0)
		_particles(to3d(at, randf_range(-1, 1)), [Color.WHITE, col, Color(col, 0.0)], 90, 1.4, Vector2(3, 6), 0.9, Vector3(0, -2.5, 0), true, 0.1)
		_ring(to3d(at, 0), col, randf_range(40, 80), 0.2, 3.0, 0.6, 0.04, 5.0)
		await _wait(0.35)


## Joue l'effet associé à une carte. `source` / `targets` en coordonnées écran.
func play_card_fx(fx: String, source: Vector2, targets: Array) -> void:
	match fx:
		"fireball":
			for t in targets:
				await fireball(source, t)
		"lightning":
			for t in targets:
				await lightning(source, t)
		"heal":
			for t in targets:
				await heal(t)
		"buff":
			for t in targets:
				await buff(t)
		"frost":
			await frost(targets)
		"arrow":
			for t in targets:
				await arrow(source, t)
		"dragon_fire":
			await dragon_fire(source, targets)
		"summon":
			await summon(source)
		"draw":
			await draw_cards(source, Vector2(640, 660), 2)
