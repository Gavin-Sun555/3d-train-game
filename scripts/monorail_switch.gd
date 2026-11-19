extends Node3D
# Articulated monorail switch: one guideway beam made of rigid segments that flexes sideways between
# "straight" (throw 0, continues its own guideway) and "diverging" (throw 1, its free end docks onto the
# other guideway) - the moving-beam switch used on straddle monorails. No fixed extra beam.

const SEGMENTS := 10
const THROW_SPEED := 0.25 # full throw in ~4s

var base_frames: Array[Transform3D] = [] # SEGMENTS+1 frames along the edge centreline
var seps: PackedFloat32Array = PackedFloat32Array()
var lane_sign := -1.0 # guideway the switch beam belongs to (its anchored end)
var top := 7.1
var bot := 5.6
var half_w := 0.45
var throw := 0.0
var target := 0.0
var straight_mid := Vector3.ZERO # point a through train passes (anchored guideway, mid span)
var diverge_mid := Vector3.ZERO  # point a crossing train passes (mid of the diverging path)
var _segs: Array[MeshInstance3D] = []
var _rails: Array[MeshInstance3D] = []


func setup(frames: Array[Transform3D], sep_values: PackedFloat32Array, beam_mat: Material, rail_mat: Material) -> void:
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
	var mid := SEGMENTS / 2
	var fm: Transform3D = base_frames[mid]
	straight_mid = fm.origin + fm.basis.x * (lane_sign * seps[mid])
	diverge_mid = fm.origin + fm.basis.x * _lat(mid, 1.0)
	_apply()


func _lat(i: int, k: float) -> float:
	var u := float(i) / float(SEGMENTS)
	var herm := 3.0 * u * u - 2.0 * u * u * u
	var s := seps[i]
	# anchored on lane_sign at u=0; at full throw the free end reaches the other guideway
	return lane_sign * s + k * (-2.0 * lane_sign * s * herm)


func _point(i: int, k: float) -> Vector3:
	var f: Transform3D = base_frames[i]
	return f.origin + f.basis.x * _lat(i, k)


func _apply() -> void:
	for i in range(SEGMENTS):
		var a := _point(i, throw)
		var b := _point(i + 1, throw)
		var d := b - a
		d.y = 0.0
		var length := d.length()
		if length < 0.01:
			continue
		var basis := Basis.looking_at(d / length, Vector3.UP)
		var mid := (a + b) * 0.5
		_segs[i].transform = Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, length + 0.06)), mid + Vector3.UP * ((top + bot) * 0.5))
		_rails[i].transform = Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, length + 0.06)), mid + Vector3.UP * (top - 0.35))


# Advanced by TransitSim on simulation time (so it keeps pace with fast-forward and headless runs)
func advance(delta: float) -> void:
	if absf(throw - target) > 0.0005:
		throw = move_toward(throw, target, THROW_SPEED * delta)
		_apply()
