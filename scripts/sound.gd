extends Node
## Music, loops and sound effects. Every file in audio/ is synthesized by
## tools/make_audio.py (original, nothing licensed).
##
## Godot audio basics used here:
## - An AudioStreamPlayer plays one sound at a time, so a pool of them lets
##   effects overlap.
## - Loops (engine, tyres, siren, rain) each get a dedicated player whose
##   volume and pitch follow the game every frame.
## - Everything runs through buses (Music, SFX, Ambience), so each group's
##   volume is set in one place.
##
## Browsers only allow sound after the player clicks or taps once; Godot's web
## build unlocks it on the first input, which is the menu click.

const SFX := ["crash", "bump", "honk", "splash", "jump", "land", "kaching", "pickup", "review_good", "review_bad",
	"fine", "alert", "arrest", "incident", "near", "tick", "ui", "talk", "win", "lose", "scratch"]
const LOOPS := ["engine", "skid", "siren", "rain"]

## Passenger voices for the gibberish chatter: pitch, gap between syllables.
const VOICES := {"regular": [1.0, 0.09], "nana": [0.78, 0.13], "streamer": [1.45, 0.065], "hustler": [1.15, 0.075]}

var music_on := true
var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []   # two players, for crossfades
var _active := 0
var _music_now := ""
var _wanted := ""
var _loops := {}
var _loop_db := {}
var _talk_left := 0
var _talk_t := 0.0
var _talk_voice: Array = [1.0, 0.1]


func _ready() -> void:
	_bus("Music", -12.0)
	_bus("SFX", -4.0)
	_bus("Ambience", -10.0)
	for n in SFX:
		_sfx[n] = load("res://audio/sfx/%s.wav" % n)
	for i in 16:
		_pool.append(_player("SFX"))
	for i in 2:
		_music.append(_player("Music"))
	for n in LOOPS:
		_loops[n] = _player("Ambience" if n in ["engine", "rain"] else "SFX")
		_loops[n].stream = _looped(load("res://audio/loops/%s.wav" % n))
		_loop_db[n] = -80.0


func _bus(name: String, db: float) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(name), db)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


## WAV files don't loop by default: loop the whole file.
static func _looped(w: AudioStreamWAV) -> AudioStreamWAV:
	w = w.duplicate()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(round(w.get_length() * w.mix_rate))
	return w


func play(sound: String, volume_db := 0.0, pitch := 1.0, jitter := 0.05) -> void:
	var p := _pool[0]
	for c in _pool:
		if not c.playing:
			p = c
			break
	p.stream = _sfx[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.play()


## Set where a loop should be: volume in dB (-80 = off) and pitch. It glides there.
func loop(name: String, db: float, pitch := 1.0) -> void:
	_loop_db[name] = db
	var p: AudioStreamPlayer = _loops[name]
	p.pitch_scale = lerpf(p.pitch_scale, maxf(0.05, pitch), 0.15)


func silence_loops() -> void:
	for n in _loop_db:
		_loop_db[n] = -80.0
	_talk_left = 0


## A passenger talks: a burst of gibberish syllables in their voice.
func talk(kind: String, syllables: int) -> void:
	_talk_voice = VOICES.get(kind, [1.0, 0.09])
	_talk_left = clampi(syllables, 2, 7)
	_talk_t = 0.0


func _process(delta: float) -> void:
	for n in _loops:
		var p: AudioStreamPlayer = _loops[n]
		var target: float = _loop_db[n]
		if target <= -79.0 and not p.playing:
			continue
		if not p.playing:
			p.volume_db = -60.0
			p.play()
		p.volume_db = move_toward(p.volume_db, target, delta * 80.0)
		if target <= -79.0 and p.volume_db <= -59.0:
			p.stop()
	if _talk_left > 0:
		_talk_t -= delta
		if _talk_t <= 0.0:
			_talk_left -= 1
			_talk_t = float(_talk_voice[1]) * randf_range(0.8, 1.3)
			play("talk", -10.0, float(_talk_voice[0]) * randf_range(0.85, 1.25), 0.0)
	for i in 2:
		var m := _music[i]
		var want := 0.0 if i == _active and music_on else -60.0
		m.volume_db = move_toward(m.volume_db, want, delta * 30.0)
		if i != _active and m.playing and m.volume_db <= -59.0:
			m.stop()


## Crossfade to a music track ("" = fade out).
func music(track: String) -> void:
	_wanted = track
	if not music_on:
		track = ""
	if track == _music_now:
		return
	_music_now = track
	_active = 1 - _active
	var m := _music[_active]
	if track == "" or not ResourceLoader.exists("res://audio/music/%s.wav" % track):
		m.stop()
		return
	m.stream = _looped(load("res://audio/music/%s.wav" % track))
	m.volume_db = -40.0
	m.play()


func toggle_music() -> bool:
	music_on = not music_on
	var w := _wanted
	_music_now = "?"
	music(w)
	return music_on
