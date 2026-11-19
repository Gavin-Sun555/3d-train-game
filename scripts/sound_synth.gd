class_name SoundSynth
extends Node

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _mix_rate := 22050.0

var speed_mps := 0.0
var traction_effort := 0.0 # -1..+1
var overspeed_squeal := 0.0 # 0..1 continuous warning + flange squeal
var muted := false
var _menu_silenced := true

enum TtsLang {
	BILINGUAL = 0,
	ZH_ONLY = 1,
	EN_ONLY = 2,
}

var master_volume := 0.85
var sfx_enabled := true
var sfx_volume := 0.85
var tts_enabled := true
var tts_volume := 85
var tts_lang_mode: int = TtsLang.BILINGUAL
var _zh_voice_id := ""
var _en_voice_id := ""

var _motor_phase := 0.0
var _rumble_phase := 0.0
var _squeal_phase := 0.0
var _alarm_clock := 0.0
var _bell_timer := -1.0
var _chime_timer := -1.0
var _joint_timer := -1.0
var _crash_timer := -1.0
var _click_timer := -1.0
var _dist_since_joint := 0.0
var _noise_seed := 1337


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _mix_rate
	gen.buffer_length = 0.08
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -7.0
	add_child(_player)
	_player.play()
	_player.stream_paused = _menu_silenced
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

	var zh_v := DisplayServer.tts_get_voices_for_language("zh")
	if not zh_v.is_empty():
		_zh_voice_id = zh_v[0]
	var en_v := DisplayServer.tts_get_voices_for_language("en")
	if not en_v.is_empty():
		_en_voice_id = en_v[0]


func set_menu_silenced(silent: bool) -> void:
	_menu_silenced = silent
	if silent:
		speed_mps = 0.0
		traction_effort = 0.0
		overspeed_squeal = 0.0
		_bell_timer = -1.0
		_chime_timer = -1.0
		_joint_timer = -1.0
		_crash_timer = -1.0
		_click_timer = -1.0
		if DisplayServer.get_name() != "headless":
			DisplayServer.tts_stop()
	if _player != null:
		_player.stream_paused = silent


func play_notch_click() -> void:
	if not _menu_silenced and sfx_enabled:
		_click_timer = 0.0


func announce_station(zh_text: String, en_text: String = "") -> void:
	if _menu_silenced or muted or not tts_enabled or master_volume <= 0.01:
		return
	if DisplayServer.get_name() == "headless":
		return
	_chime_timer = 0.0
	var vol := clampi(int(round(master_volume * float(tts_volume))), 0, 100)
	if vol <= 0:
		return
	DisplayServer.tts_stop()
	var v_zh := _zh_voice_id if not _zh_voice_id.is_empty() else _en_voice_id
	var v_en := _en_voice_id if not _en_voice_id.is_empty() else v_zh
	if (tts_lang_mode == TtsLang.BILINGUAL or tts_lang_mode == TtsLang.ZH_ONLY) and not v_zh.is_empty() and not zh_text.is_empty():
		DisplayServer.tts_speak(zh_text, v_zh, vol, 1.0, 1.02, 0, false)
	if (tts_lang_mode == TtsLang.BILINGUAL or tts_lang_mode == TtsLang.EN_ONLY) and not v_en.is_empty() and not en_text.is_empty():
		DisplayServer.tts_speak(en_text, v_en, vol, 1.0, 1.0, 0, false)


func ring_bell() -> void:
	_bell_timer = 0.0


func play_door_chime() -> void:
	_chime_timer = 0.0


func play_crash_sound() -> void:
	_crash_timer = 0.0


func advance_distance(ds: float) -> void:
	_dist_since_joint += absf(ds)
	if _dist_since_joint >= 13.5:
		_dist_since_joint = fmod(_dist_since_joint, 13.5)
		_joint_timer = 0.0


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return

	var dt := 1.0 / _mix_rate
	var spd := absf(speed_mps)
	var spd_ratio := clampf(spd / 20.0, 0.0, 1.0)
	var motor_freq := 145.0 + spd * 21.0
	var motor_amp := clampf(absf(traction_effort) * 0.065 * clampf(spd * 0.45 + 0.15, 0.0, 1.0), 0.0, 0.08)
	var roll_amp := spd_ratio * 0.035
	var sq_amp := clampf(overspeed_squeal, 0.0, 1.0)

	var gain := master_volume * sfx_volume
	for _i in range(frames):
		if muted or _menu_silenced or not sfx_enabled or gain <= 0.005:
			_playback.push_frame(Vector2.ZERO)
			continue

		var sample := 0.0

		# 1. VVVF traction inverter + gear hum
		if motor_amp > 0.001:
			_motor_phase = fmod(_motor_phase + motor_freq * dt, 1.0)
			sample += (sin(_motor_phase * TAU) * 0.7 + sin(_motor_phase * TAU * 2.0) * 0.3) * motor_amp

		# 2. Wheel-rail rolling low-frequency hum
		if roll_amp > 0.001:
			_rumble_phase = fmod(_rumble_phase + (62.0 + spd * 3.2) * dt, 1.0)
			sample += sin(_rumble_phase * TAU) * roll_amp

		# 3. Rail joint "ka-chunk" double tap
		if _joint_timer >= 0.0:
			for tap: float in [0.0, 0.095]:
				var tj := _joint_timer - tap
				if tj >= 0.0 and tj < 0.055:
					var env := exp(-tj * 65.0)
					sample += sin(tj * TAU * 135.0) * env * 0.13 * clampf(spd / 8.0, 0.25, 1.0)
			_joint_timer += dt
			if _joint_timer > 0.22:
				_joint_timer = -1.0

		# 4. Classic brass "Ding-Ding!" streetcar bell
		if _bell_timer >= 0.0:
			for strike: float in [0.0, 0.18]:
				var tb := _bell_timer - strike
				if tb >= 0.0 and tb < 0.55:
					var env := exp(-tb * 7.8)
					var tone := (
						sin(tb * TAU * 1120.0) * 0.58
						+ sin(tb * TAU * 2275.0) * 0.28
						+ sin(tb * TAU * 3410.0) * 0.14
					)
					sample += tone * env * 0.22
			_bell_timer += dt
			if _bell_timer > 0.78:
				_bell_timer = -1.0

		# 5. Two-tone station door chime
		if _chime_timer >= 0.0:
			var freq := 659.25 if _chime_timer < 0.24 else 523.25
			var tc := _chime_timer if _chime_timer < 0.24 else (_chime_timer - 0.24)
			if _chime_timer < 0.56:
				var env := exp(-tc * 6.5)
				sample += sin(_chime_timer * TAU * freq) * env * 0.16
			_chime_timer += dt
			if _chime_timer > 0.60:
				_chime_timer = -1.0

		# 6. Curve/Turnout Overspeed Warning Beep + Wheel-Flange Metallic Squeal!
		if sq_amp > 0.02:
			_alarm_clock = fmod(_alarm_clock + dt, 0.36)
			_squeal_phase = fmod(_squeal_phase + 2680.0 * dt, 1.0)
			var flange := (sin(_squeal_phase * TAU) * 0.6 + sin(_squeal_phase * TAU * 1.41) * 0.4) * 0.065 * sq_amp
			var beep := sin(_alarm_clock * TAU * 980.0) * (0.12 if _alarm_clock < 0.16 else 0.0) * sq_amp
			sample += flange + beep

		# 7. Heavy Collision / Derailment Rollover Impact Sound!
		if _crash_timer >= 0.0:
			_noise_seed = (_noise_seed * 1103515245 + 12345) & 0x7fffffff
			var white := (float(_noise_seed % 2000) / 1000.0) - 1.0
			var thud_env := exp(-_crash_timer * 5.2)
			var scrape_env := exp(-_crash_timer * 2.1)
			var thud := sin(_crash_timer * TAU * (78.0 - _crash_timer * 28.0)) * thud_env * 0.52
			var crunch := white * scrape_env * 0.36
			sample += thud + crunch
			_crash_timer += dt
			if _crash_timer > 1.35:
				_crash_timer = -1.0

		if _click_timer >= 0.0:
			if _click_timer < 0.025:
				sample += sin(_click_timer * TAU * 860.0) * exp(-_click_timer * 140.0) * 0.22
			_click_timer += dt
			if _click_timer > 0.03:
				_click_timer = -1.0

		sample = clampf(sample * gain, -0.88, 0.88)
		_playback.push_frame(Vector2(sample, sample))
