extends Node
## Lecture de la musique (avec fondu) et des effets sonores (pool de lecteurs).

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const SFX_POOL_SIZE := 10

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_music := ""
var _sfx_players: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	for i in SFX_POOL_SIZE:
		_sfx_players.append(_make_player("SFX"))


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[path] = stream
	return stream


## Joue une piste musicale (fichier sans extension dans assets/audio/music).
func play_music(track: String, loop := true, fade := 0.8) -> void:
	if track == _current_music and _music_a.playing:
		return
	_current_music = track
	var stream := _load_stream(MUSIC_DIR + track + ".mp3")
	if stream == null:
		return
	stream = stream.duplicate()
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	# Fondu enchaîné : A (ancienne piste) s'éteint, B (nouvelle) monte puis devient A.
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	_music_a.stream = stream
	_music_a.volume_db = -40.0
	_music_a.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_a, "volume_db", 0.0, fade)
	if _music_b.playing:
		tw.tween_property(_music_b, "volume_db", -40.0, fade)
		tw.chain().tween_callback(_music_b.stop)


func stop_music(fade := 0.8) -> void:
	_current_music = ""
	var tw := create_tween()
	tw.tween_property(_music_a, "volume_db", -40.0, fade)
	tw.tween_callback(_music_a.stop)


func play_sfx(sfx_name: String, pitch_variation := 0.08, volume_db := 0.0) -> void:
	var stream := _load_stream(SFX_DIR + sfx_name + ".mp3")
	if stream == null:
		return
	var player: AudioStreamPlayer = null
	for p in _sfx_players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _sfx_players[0]
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()
