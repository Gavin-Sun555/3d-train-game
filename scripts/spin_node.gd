extends Node3D
# Slowly rotates around local Z (e.g. the Seattle Great Wheel); children in `upright` stay level.

var speed_rad := 0.035
var upright: Array[Node3D] = []


func _process(delta: float) -> void:
	rotation.z += speed_rad * delta
	for n in upright:
		if is_instance_valid(n):
			n.rotation.z = -rotation.z
