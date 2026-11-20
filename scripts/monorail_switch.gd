extends Node3D
# Monorail crossover made of two moving half-beams (the way straddle-monorail crossovers work):
#   * half A belongs to guideway -1, pivots at the low-s end of the span;
#   * half B belongs to guideway +1, pivots at the high-s end.
# Straight (throw 0): both halves lie in their own guideway, which then runs through unbroken.
# Diverging (throw 1): both swing towards the middle and their free ends meet on the centreline,
# forming one continuous S-beam from guideway -1 to guideway +1 (both through routes are then broken).
# Four signals (each guideway, each end) protect the span; TransitSim does the interlocking.

const SEGMENTS := 10 # 5 rigid segments per half
const THROW_SPEED := 0.25 # full throw in ~4s
const SIG_RED := 0
const SIG_GREEN := 1

var base_frames: Array[Transform3D] = [] # SEGMENTS+1 frames along the edge centreline over the span
var seps: PackedFloat32Array = PackedFloat32Array()
var top := 7.1
var bot := 5.6
var half_w := 0.45
var throw := 0.0
var target := 0.0

# Route probes (world space)
var straight_a := Vector3.ZERO # guideway -1 at mid-span (free end of half A)
var straight_b := Vector3.ZERO # guideway +1 at mid-span (free end of half B)
var diverge_mid := Vector3.ZERO # where the two halves meet when thrown
var entries: Array[Vector3] = [] # 0: low end -1, 1: low end +1, 2: high end -1, 3: high end +1

# Interlocking state (owned by TransitSim)
var owner_idx := -1
var owner_need := 0.0
var owner_entry := -1
var manual_override := false # driver threw it by hand (G): automatic route setting leaves it alone

var _segs: Array[MeshInstance3D] = []
var _rails: Array[MeshInstance3D] = []
var _sig_red: Array[StandardMaterial3D] = []
var _sig_green: Array[StandardMaterial3D] = []
var _sig_state: Array[int] = []


func setup(frames: Array[Transform3D], sep_values: PackedFloat32Array, sig_frames: Array[Transform3D], sig_seps: PackedFloat32Array, beam_mat: Material, rail_mat: Material) -> void:
	base_frames = frames
	seps = sep_values
	for i in range(SEGMENTS):
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(half_w * 2.0, top - bot, 1.0)
		mi.mesh = b
		mi.material_override = beam_mat
		add_child(mi)
		_segs.append(mi)
		var rm := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(half_w * 2.0 + 0.08, 0.2, 1.0)
		rm.mesh = rb
		rm.material_override = rail_mat
		add_child(rm)
		_rails.append(rm)
	# Probes at mid-span, where the straight lanes and the crossing path are a full track spacing apart
	var mid := SEGMENTS / 2
	straight_a = _frame_pt(mid, -seps[mid])
	straight_b = _frame_pt(mid, seps[mid])
	diverge_mid = _frame_pt(mid, _diverge_lat(mid))
	entries = [_frame_pt(0, -seps[0]), _frame_pt(0, seps[0]), _frame_pt(SEGMENTS, -seps[SEGMENTS]), _frame_pt(SEGMENTS, seps[SEGMENTS])]
	# Signals: index matches `entries`; low-end heads face trains travelling +s, high-end heads face -s
	for k in range(4):
		var f: Transform3D = sig_frames[0 if k < 2 else 1]
		var lane := -1.0 if k % 2 == 0 else 1.0
		var facing := 1.0 if k < 2 else -1.0 # lens faces the trains approaching this end (frame -Z points along +s)
		_build_signal(f, lane, float(sig_seps[0 if k < 2 else 1]), facing)
	_apply()


func _frame_pt(i: int, lat: float) -> Vector3:
	var f: Transform3D = base_frames[i]
	return f.origin + f.basis.x * lat + Vector3.UP * top


func _diverge_lat(i: int) -> float:
	var u := float(i) / float(SEGMENTS)
	var herm := 3.0 * u * u - 2.0 * u * u * u
	return -seps[i] + 2.0 * seps[i] * herm


# Lateral offset of point i of the half-beam `half` (0 = A on -1, 1 = B on +1) at throw k
func _lat(i: int, half: int, k: float) -> float:
	var base := -seps[i] if half == 0 else seps[i]
	return base + k * (_diverge_lat(i) - base)


func _apply() -> void:
	for i in range(SEGMENTS):
		var half := 0 if i < SEGMENTS / 2 else 1
		var fa: Transform3D = base_frames[i]
		var fb: Transform3D = base_frames[i + 1]
		var a := fa.origin + fa.basis.x * _lat(i, half, throw)
		var b := fb.origin + fb.basis.x * _lat(i + 1, half, throw)
		var d := b - a
		d.y = 0.0
		var length := d.length()
		if length < 0.01:
			continue
		var basis := Basis.looking_at(d / length, Vector3.UP)
		var m := (a + b) * 0.5
		var sc := Basis.from_scale(Vector3(1.0, 1.0, length + 0.04))
		_segs[i].transform = Transform3D(basis * sc, m + Vector3.UP * ((top + bot) * 0.5))
		_rails[i].transform = Transform3D(basis * sc, m + Vector3.UP * (top - 0.35))


func _build_signal(f: Transform3D, lane: float, sep: float, facing: float) -> void:
	var side := f.basis.x * lane # outward side of this guideway
	var fwd := f.basis.z * facing # direction the lenses face
	var base := f.origin + f.basis.x * (lane * sep) + side * (half_w + 0.35)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.roughness = 0.6
	var bracket := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.12, 1.9, 0.12)
	bracket.mesh = bb
	bracket.material_override = dark
	bracket.position = base + Vector3.UP * (top - 0.2)
	add_child(bracket)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.42, 0.9, 0.3)
	head.mesh = hb
	head.material_override = dark
	var head_pos := base + Vector3.UP * (top + 1.05)
	head.transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), head_pos)
	add_child(head)
	var red := StandardMaterial3D.new()
	var green := StandardMaterial3D.new()
	for li in range(2):
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.13
		lm.bottom_radius = 0.13
		lm.height = 0.05
		lens.mesh = lm
		lens.material_override = red if li == 0 else green
		var lp := head_pos + Vector3.UP * (0.2 if li == 0 else -0.2) + fwd * 0.16
		lens.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), lp)
		add_child(lens)
		var hood := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.34, 0.04, 0.2)
		hood.mesh = hm
		hood.material_override = dark
		hood.transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), lp + Vector3.UP * 0.17 + fwd * 0.08)
		add_child(hood)
	_sig_red.append(red)
	_sig_green.append(green)
	_sig_state.append(-1)
	_set_lens(_sig_state.size() - 1, SIG_RED)


func _set_lens(k: int, state: int) -> void:
	if _sig_state[k] == state:
		return
	_sig_state[k] = state
	var on_r := state == SIG_RED
	var r := _sig_red[k]
	var g := _sig_green[k]
	r.albedo_color = Color(1.0, 0.12, 0.08) if on_r else Color(0.22, 0.05, 0.04)
	r.emission_enabled = on_r
	r.emission = Color(1.0, 0.1, 0.05)
	r.emission_energy_multiplier = 3.0
	g.albedo_color = Color(0.15, 1.0, 0.45) if not on_r else Color(0.03, 0.16, 0.08)
	g.emission_enabled = not on_r
	g.emission = Color(0.1, 1.0, 0.4)
	g.emission_energy_multiplier = 3.0


func is_set_for(need: float) -> bool:
	return absf(target - need) < 0.001 and absf(throw - need) < 0.001


func signal_green(entry: int) -> bool:
	return entry >= 0 and entry < _sig_state.size() and _sig_state[entry] == SIG_GREEN


func update_signals() -> void:
	for k in range(_sig_state.size()):
		var green := owner_idx >= 0 and owner_entry == k and is_set_for(owner_need)
		_set_lens(k, SIG_GREEN if green else SIG_RED)


# Advanced by TransitSim on simulation time (so it keeps pace with fast-forward and headless runs)
func advance(delta: float) -> void:
	if absf(throw - target) > 0.0005:
		throw = move_toward(throw, target, THROW_SPEED * delta)
		_apply()
	update_signals()
