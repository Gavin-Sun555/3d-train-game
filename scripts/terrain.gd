class_name Terrain
extends RefCounted
# Real ground elevation (Seattle: USGS 3DEP via Terrarium tiles, built by tools/osm_cache/fetch_terrain.py).
# Everything is still authored flat (y = 0 street level); the world is then put on the ground:
#   * surfaces (streets, kerbs, sidewalks, lawns, track beds ...) are draped vertex by vertex,
#   * rigid things (buildings, landmark towers, signal masts, trees ...) move up as one piece,
#   * water stays flat at its lake / sea level, and whatever stands on water sits on its surface.
# Maps without terrain data stay flat (height 0 everywhere).

static var active := false
static var _x0 := 0.0
static var _z0 := 0.0
static var _cell := 8.0
static var _w := 0
static var _h := 0
static var _hs := PackedFloat32Array() # ground (bare earth), m
static var _wl := PackedFloat32Array() # water surface where there is water, else -1e6
static var _dk := PackedFloat32Array() # street bridge decks (overpasses, canal bridges), else -1e6
static var _rigid_max := 60.0


static func load_for(map_key: String, areas: Array, edges: Array = []) -> void:
	active = false
	_hs = PackedFloat32Array()
	_wl = PackedFloat32Array()
	_dk = PackedFloat32Array()
	var base := "res://data/%s_terrain" % map_key
	if not FileAccess.file_exists(base + ".bin") or not FileAccess.file_exists(base + ".json"):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var buf := FileAccess.get_file_as_bytes(base + ".bin")
	_x0 = float(meta["x0"])
	_z0 = float(meta["z0"])
	_cell = float(meta["cell"])
	_w = int(meta["w"])
	_h = int(meta["h"])
	var sc := float(meta.get("scale", 0.1))
	if buf.size() < _w * _h * 2:
		return
	_hs.resize(_w * _h)
	for i in range(_w * _h):
		_hs[i] = float(buf.decode_s16(i * 2)) * sc
	_build_water(areas)
	_build_decks(edges)
	active = true


# Water surface raster: each water polygon is flat at its own level (lake surface from the elevation data;
# the sea at 0). Cells inside a polygon get that level; the ground under the water is pushed below it.
static func _build_water(areas: Array) -> void:
	_wl.resize(_w * _h)
	_wl.fill(-1e6)
	for a: Dictionary in areas:
		if str(a.get("kind", "")) != "water":
			continue
		var poly := PackedVector2Array()
		for p in a.get("pts", []):
			poly.append(Vector2(float(p[0]), float(p[1])))
		if poly.size() < 3:
			continue
		var lvl := water_level_of(poly)
		a["_level"] = lvl
		var mn := poly[0]
		var mx := poly[0]
		for p2 in poly:
			mn = mn.min(p2)
			mx = mx.max(p2)
		var i0 := clampi(int(floor((mn.x - _x0) / _cell)), 0, _w - 1)
		var i1 := clampi(int(ceil((mx.x - _x0) / _cell)), 0, _w - 1)
		var j0 := clampi(int(floor((mn.y - _z0) / _cell)), 0, _h - 1)
		var j1 := clampi(int(ceil((mx.y - _z0) / _cell)), 0, _h - 1)
		for j in range(j0, j1 + 1):
			var z := _z0 + float(j) * _cell
			# scanline: crossings of this row with the polygon edges
			var xs: Array[float] = []
			for k in range(poly.size()):
				var pa := poly[k]
				var pb := poly[(k + 1) % poly.size()]
				if (pa.y > z) != (pb.y > z):
					xs.append(pa.x + (z - pa.y) / (pb.y - pa.y) * (pb.x - pa.x))
			xs.sort()
			for q in range(0, xs.size() - 1, 2):
				var ia := maxi(i0, int(ceil((xs[q] - _x0) / _cell)))
				var ib := mini(i1, int(floor((xs[q + 1] - _x0) / _cell)))
				for i in range(ia, ib + 1):
					var k2 := j * _w + i
					_wl[k2] = maxf(_wl[k2], lvl)
					_hs[k2] = minf(_hs[k2], lvl - 1.2)


# Street bridges (graph edges with "bridge"): the elevation data is bare earth (an overpass would sink into
# the freeway cut under it), so the deck spans straight from one end's ground to the other's. The ground mesh
# keeps the real ground; streets, kerbs, cars and trams stand on the deck (surface()).
static func _build_decks(edges: Array) -> void:
	_dk.resize(_w * _h)
	_dk.fill(-1e6)
	for e: Dictionary in edges:
		if not bool(e.get("bridge", false)):
			continue
		var pts: Array = e.get("pts", [])
		if pts.size() < 2:
			continue
		var poly: Array[Vector2] = []
		for p in pts:
			poly.append(Vector2(float(p[0]), float(p[1])))
		var cum: Array[float] = [0.0]
		for i in range(1, poly.size()):
			cum.append(cum[i - 1] + poly[i].distance_to(poly[i - 1]))
		var L := maxf(cum[cum.size() - 1], 0.01)
		var ha := maxf(_ground(poly[0].x, poly[0].y), _water_at(poly[0].x, poly[0].y))
		var hb := maxf(_ground(poly[poly.size() - 1].x, poly[poly.size() - 1].y), _water_at(poly[poly.size() - 1].x, poly[poly.size() - 1].y))
		var reach := float(e.get("width", 10.0)) * 0.5 + 4.0 + _cell * 0.5
		for i in range(poly.size() - 1):
			var a := poly[i]
			var b := poly[i + 1]
			var mn := a.min(b) - Vector2(reach, reach)
			var mx := a.max(b) + Vector2(reach, reach)
			for j in range(clampi(int(floor((mn.y - _z0) / _cell)), 0, _h - 1), clampi(int(ceil((mx.y - _z0) / _cell)), 0, _h - 1) + 1):
				for ii in range(clampi(int(floor((mn.x - _x0) / _cell)), 0, _w - 1), clampi(int(ceil((mx.x - _x0) / _cell)), 0, _w - 1) + 1):
					var c := Vector2(_x0 + float(ii) * _cell, _z0 + float(j) * _cell)
					var q := Geometry2D.get_closest_point_to_segment(c, a, b)
					if c.distance_to(q) > reach:
						continue
					var t := cum[i] + a.distance_to(q)
					var k := j * _w + ii
					_dk[k] = maxf(_dk[k], lerpf(ha, hb, t / L))


static func _water_at(x: float, z: float) -> float:
	if _wl.is_empty():
		return -1e6
	var fx := clampf((x - _x0) / _cell, 0.0, float(_w) - 1.0)
	var fz := clampf((z - _z0) / _cell, 0.0, float(_h) - 1.0)
	return _wl[int(round(fz)) * _w + int(round(fx))]


# Level of a water polygon: the elevation data holds lakes as flat surfaces (their lowest value); the sea
# (bathymetry, clamped) is at 0.
static func water_level_of(poly: PackedVector2Array) -> float:
	var lo := 1e9
	var c := Vector2.ZERO
	for p in poly:
		lo = minf(lo, _ground(p.x, p.y))
		c += p
	c /= float(poly.size())
	lo = minf(lo, _ground(c.x, c.y))
	return 0.0 if lo < 0.8 else lo


static func _ground(x: float, z: float) -> float:
	var fx := clampf((x - _x0) / _cell, 0.0, float(_w) - 1.001)
	var fz := clampf((z - _z0) / _cell, 0.0, float(_h) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ux := fx - float(ix)
	var uz := fz - float(iz)
	var k := iz * _w + ix
	return lerpf(lerpf(_hs[k], _hs[k + 1], ux), lerpf(_hs[k + _w], _hs[k + _w + 1], ux), uz)


# Bare ground height (0 on maps without terrain)
static func ground(x: float, z: float) -> float:
	return _ground(x, z) if active else 0.0


# Height things stand on: the ground, or the water surface where there is water
static func surface(x: float, z: float) -> float:
	if not active:
		return 0.0
	var g := _ground(x, z)
	var fx := clampf((x - _x0) / _cell, 0.0, float(_w) - 1.0)
	var fz := clampf((z - _z0) / _cell, 0.0, float(_h) - 1.0)
	var k := int(round(fz)) * _w + int(round(fx))
	return maxf(g, maxf(_wl[k], _dk[k]))


static func surface_v(p: Vector3) -> float:
	return surface(p.x, p.z)


# Base for something rigid with this footprint: its lowest corner (walls then reach down into the slope)
static func base_under(poly: PackedVector2Array) -> float:
	if not active or poly.is_empty():
		return 0.0
	var lo := 1e9
	var c := Vector2.ZERO
	for p in poly:
		lo = minf(lo, maxf(_ground(p.x, p.y), _water_at(p.x, p.y)))
		c += p
	c /= float(poly.size())
	return minf(lo, maxf(_ground(c.x, c.y), _water_at(c.x, c.y))) - 0.25


# ---------------------------------------------------------------------------------------------
# Draping a built subtree onto the terrain
# ---------------------------------------------------------------------------------------------

# Put a whole built subtree on the ground. Nodes with meta "on_terrain" are already placed (and skipped
# with their children); nodes with meta "drape_vertices" (e.g. a long station platform) bend with the ground
# instead of moving as one piece.
static func drape_subtree(n: Node) -> void:
	if not active:
		return
	var xf := Transform3D.IDENTITY
	if n is Node3D:
		xf = (n as Node3D).global_transform if (n as Node3D).is_inside_tree() else (n as Node3D).transform
		if not (n as Node3D).is_inside_tree():
			xf = Transform3D.IDENTITY # an off-tree subtree root (map tile) is at the origin
	for ch in n.get_children():
		_drape_node(ch, xf)


static func _lift_local(n3: Node3D, parent_xf: Transform3D, dy: float) -> void:
	n3.position += parent_xf.basis.inverse() * Vector3(0.0, dy, 0.0)


static func _drape_node(n: Node, parent_xf: Transform3D) -> void:
	if n.has_meta("on_terrain"):
		return
	if n.get_class() == "Node3D" and n.get_child_count() == 0:
		return # an empty holder: nothing to place (and children it gets later are placed on their own)
	n.set_meta("on_terrain", true)
	if n.has_method("terrain_drape"):
		n.call("terrain_drape") # e.g. monorail switches: animated from their own frames
		return
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm != null and mm.transform_format == MultiMesh.TRANSFORM_3D:
			var full := parent_xf * mmi.transform
			var inv_b := full.basis.inverse()
			for i in range(mm.instance_count):
				var tf := mm.get_instance_transform(i)
				var wp := full * tf.origin
				tf.origin += inv_b * Vector3(0.0, surface(wp.x, wp.z), 0.0)
				mm.set_instance_transform(i, tf)
		return
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var full2 := parent_xf * mi.transform
		if mi.mesh != null:
			var ab := mi.mesh.get_aabb()
			if (maxf(ab.size.x, ab.size.z) <= _rigid_max or mi.has_meta("rigid")) and not n.get_parent().has_meta("drape_vertices"):
				# small piece (mast, kiosk, tower, statue): moves as a whole onto its lowest ground
				var lo := 1e9
				for cx in [0.0, 1.0]:
					for cz in [0.0, 1.0]:
						var wc := full2 * (ab.position + Vector3(ab.size.x * cx, 0.0, ab.size.z * cz))
						lo = minf(lo, surface(wc.x, wc.z))
				var wc2 := full2 * (ab.position + ab.size * 0.5)
				_lift_local(mi, parent_xf, minf(lo, surface(wc2.x, wc2.z)))
				full2 = parent_xf * mi.transform
				for ch in n.get_children():
					_mark_moved(ch)
				return
			mi.mesh = drape_mesh(mi.mesh, full2)
		for ch in n.get_children():
			_drape_node(ch, full2)
		return
	if n is Node3D:
		var n3 := n as Node3D
		var full3 := parent_xf * n3.transform
		var is_group := n3.has_meta("drape_vertices") or (n3.get_child_count() > 0 and n3.transform.origin.length_squared() < 0.01)
		if is_group:
			for ch in n.get_children():
				_drape_node(ch, full3)
		else:
			# a placed object (light, label, sign, small assembly): moves as a whole
			var wp3 := full3.origin
			_lift_local(n3, parent_xf, surface(wp3.x, wp3.z))
			for ch in n.get_children():
				_mark_moved(ch)
		return
	for ch in n.get_children():
		_drape_node(ch, parent_xf)


# Children of something moved as a whole are already on the ground with it
static func _mark_moved(n: Node) -> void:
	n.set_meta("on_terrain", true)
	for ch in n.get_children():
		_mark_moved(ch)


# Station passenger points (platform spots, stair tops, street ramps) onto the draped platform / ground
static func lift_station_view(sv: Dictionary) -> void:
	if not active or bool(sv.get("_lifted", false)):
		return
	sv["_lifted"] = true
	for k: String in ["pos", "ramp_entry", "platform_entry", "board_edge"]:
		if sv.get(k) is Vector3:
			var v: Vector3 = sv[k]
			v.y += surface(v.x, v.z)
			sv[k] = v
	var slots = sv.get("waiting_slots")
	if slots is Array:
		for i in range((slots as Array).size()):
			var w: Vector3 = slots[i]
			w.y += surface(w.x, w.z)
			slots[i] = w
	var tw = sv.get("twins")
	if tw is Array:
		for t in tw:
			if t is Dictionary:
				lift_station_view(t)


# Every vertex follows the ground under it (mesh in its node's local frame `xf`)
static func drape_mesh(mesh: Mesh, xf: Transform3D = Transform3D.IDENTITY) -> Mesh:
	var out := ArrayMesh.new()
	var ident := xf.is_equal_approx(Transform3D.IDENTITY)
	var inv := xf.affine_inverse()
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if ident:
			arr[Mesh.ARRAY_VERTEX] = _lift_verts(verts)
		else:
			for i in range(verts.size()):
				verts[i] = xf * verts[i]
			verts = _lift_verts(verts)
			for i in range(verts.size()):
				verts[i] = inv * verts[i]
			arr[Mesh.ARRAY_VERTEX] = verts
		var prim := (mesh as ArrayMesh).surface_get_primitive_type(s) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		out.add_surface_from_arrays(prim, arr)
		var mat := mesh.surface_get_material(s)
		if mat != null:
			out.surface_set_material(s, mat)
	return out


# Raise world-space vertices onto surface() (inlined bilinear lookup: this runs over millions of vertices)
static func _lift_verts(verts: PackedVector3Array) -> PackedVector3Array:
	var hs := _hs
	var wl := _wl
	var dk := _dk
	var w := _w
	var x0 := _x0
	var z0 := _z0
	var inv_cell := 1.0 / _cell
	var max_x := float(_w) - 1.001
	var max_z := float(_h) - 1.001
	for i in range(verts.size()):
		var v := verts[i]
		var fx := clampf((v.x - x0) * inv_cell, 0.0, max_x)
		var fz := clampf((v.z - z0) * inv_cell, 0.0, max_z)
		var ix := int(fx)
		var iz := int(fz)
		var ux := fx - float(ix)
		var uz := fz - float(iz)
		var k := iz * w + ix
		var g := (hs[k] * (1.0 - ux) + hs[k + 1] * ux) * (1.0 - uz) + (hs[k + w] * (1.0 - ux) + hs[k + w + 1] * ux) * uz
		var kw := (iz + (1 if uz > 0.5 else 0)) * w + ix + (1 if ux > 0.5 else 0)
		v.y += maxf(g, maxf(wl[kw], dk[kw]))
		verts[i] = v
	return verts


# Densify a 2D polyline (Array of [x, z]) so draped strips bend with the ground
static func densify(pts: Array, step: float) -> Array:
	if not active or pts.size() < 2:
		return pts
	var out: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var n := int(ceil(a.distance_to(b) / step))
		for k in range(1, n):
			var p := a.lerp(b, float(k) / float(n))
			out.append([p.x, p.y])
		out.append(pts[i + 1])
	return out


# Ground mesh: the terrain itself, in 512 m chunks (one node each, for culling), full 8 m detail up close and a
# 32 m version far away
static func build_ground(parent: Node3D, bounds: Array, mat: Material, step_cells: int = 1) -> void:
	if not active:
		return
	var holder := Node3D.new()
	holder.name = "TerrainGround"
	holder.set_meta("on_terrain", true)
	parent.add_child(holder)
	var x_lo := maxf(float(bounds[0]) - 300.0, _x0)
	var z_lo := maxf(float(bounds[1]) - 300.0, _z0)
	var x_hi := minf(float(bounds[2]) + 300.0, _x0 + float(_w - 1) * _cell)
	var z_hi := minf(float(bounds[3]) + 300.0, _z0 + float(_h - 1) * _cell)
	var chunk_m := 512.0
	var cx0 := x_lo
	while cx0 < x_hi:
		var cz0 := z_lo
		while cz0 < z_hi:
			var cx1 := minf(cx0 + chunk_m, x_hi)
			var cz1 := minf(cz0 + chunk_m, z_hi)
			var centre := Vector3((cx0 + cx1) * 0.5, 0.0, (cz0 + cz1) * 0.5)
			for lod in range(2):
				var step := _cell * float(step_cells) * (1.0 if lod == 0 else 4.0)
				var mi := MeshInstance3D.new()
				mi.name = "Ground_%d_%d_%d" % [int(cx0), int(cz0), lod]
				mi.position = centre # vertices are local to the chunk centre: distance culling measures from here
				mi.mesh = _ground_chunk(cx0, cz0, cx1, cz1, step, centre)
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if lod == 0:
					mi.visibility_range_end = 1500.0
				else:
					mi.visibility_range_begin = 1500.0
				holder.add_child(mi)
			cz0 += chunk_m
		cx0 += chunk_m


static func _ground_chunk(x0: float, z0: float, x1: float, z1: float, step: float, centre: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := maxi(1, int(ceil((x1 - x0) / step)))
	var nz := maxi(1, int(ceil((z1 - z0) / step)))
	for j in range(nz):
		for i in range(nx):
			var xa := minf(x0 + float(i) * step, x1)
			var za := minf(z0 + float(j) * step, z1)
			var xb := minf(xa + step, x1)
			var zb := minf(za + step, z1)
			var p00 := Vector3(xa, _ground(xa, za) - 0.02, za)
			var p10 := Vector3(xb, _ground(xb, za) - 0.02, za)
			var p01 := Vector3(xa, _ground(xa, zb) - 0.02, zb)
			var p11 := Vector3(xb, _ground(xb, zb) - 0.02, zb)
			var nrm := (p01 - p00).cross(p10 - p00).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for v: Vector3 in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(nrm)
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v - centre)
	return st.commit()


# Ray / terrain intersection (for picking): march along the ray and refine. Returns null on a miss.
static func raycast(origin: Vector3, dir: Vector3, max_dist: float = 6000.0) -> Variant:
	var d := dir.normalized()
	if not active:
		if absf(d.y) < 1e-5:
			return null
		var t0 := -origin.y / d.y
		return origin + d * t0 if t0 > 0.0 else null
	var t := 0.0
	var step := 4.0
	var prev_t := 0.0
	var prev_above := origin.y - surface(origin.x, origin.z)
	while t < max_dist:
		t += step
		var p := origin + d * t
		var above := p.y - surface(p.x, p.z)
		if above <= 0.0:
			var lo := prev_t
			var hi := t
			for _i in range(18):
				var mid := (lo + hi) * 0.5
				var pm := origin + d * mid
				if pm.y - surface(pm.x, pm.z) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit := origin + d * hi
			hit.y = surface(hit.x, hit.z)
			return hit
		prev_t = t
		prev_above = above
		step = clampf(above * 0.5, 1.0, 40.0)
	return null


# Per-building rigid offsets for builders that batch many buildings into one SurfaceTool: build each building
# into its own temporary tool, then append its arrays shifted by dy.
static func acc_new() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "has_c": false, "has_uv": false, "has_n": false}


static func acc_add(acc: Dictionary, st: SurfaceTool, dy: float) -> void:
	var arr := st.commit_to_arrays()
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		# indexed output: expand to a plain triangle list like the rest of the batch
		var order: PackedInt32Array = idx
		var nv := PackedVector3Array()
		nv.resize(order.size())
		for k in range(order.size()):
			nv[k] = verts[order[k]]
		verts = nv
		for slot: int in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
			if arr[slot] == null:
				continue
			if slot == Mesh.ARRAY_COLOR:
				var src_c: PackedColorArray = arr[slot]
				var dst_c := PackedColorArray()
				dst_c.resize(order.size())
				for k in range(order.size()):
					dst_c[k] = src_c[order[k]]
				arr[slot] = dst_c
			elif slot == Mesh.ARRAY_TEX_UV:
				var src_u: PackedVector2Array = arr[slot]
				var dst_u := PackedVector2Array()
				dst_u.resize(order.size())
				for k in range(order.size()):
					dst_u[k] = src_u[order[k]]
				arr[slot] = dst_u
			else:
				var src_n: PackedVector3Array = arr[slot]
				var dst_n := PackedVector3Array()
				dst_n.resize(order.size())
				for k in range(order.size()):
					dst_n[k] = src_n[order[k]]
				arr[slot] = dst_n
	if dy != 0.0:
		for k in range(verts.size()):
			verts[k].y += dy
	# packed arrays are values: append to locals, then store them back
	var av: PackedVector3Array = acc["v"]
	av.append_array(verts)
	acc["v"] = av
	if arr[Mesh.ARRAY_NORMAL] != null:
		var an: PackedVector3Array = acc["n"]
		an.append_array(arr[Mesh.ARRAY_NORMAL])
		acc["n"] = an
		acc["has_n"] = true
	if arr[Mesh.ARRAY_COLOR] != null:
		var ac: PackedColorArray = acc["c"]
		ac.append_array(arr[Mesh.ARRAY_COLOR])
		acc["c"] = ac
		acc["has_c"] = true
	if arr[Mesh.ARRAY_TEX_UV] != null:
		var au: PackedVector2Array = acc["uv"]
		au.append_array(arr[Mesh.ARRAY_TEX_UV])
		acc["uv"] = au
		acc["has_uv"] = true


static func acc_empty(acc: Dictionary) -> bool:
	return (acc["v"] as PackedVector3Array).is_empty()


static func acc_mesh(acc: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = acc["v"]
	if bool(acc["has_n"]) and (acc["n"] as PackedVector3Array).size() == (acc["v"] as PackedVector3Array).size():
		arr[Mesh.ARRAY_NORMAL] = acc["n"]
	if bool(acc["has_c"]) and (acc["c"] as PackedColorArray).size() == (acc["v"] as PackedVector3Array).size():
		arr[Mesh.ARRAY_COLOR] = acc["c"]
	if bool(acc["has_uv"]) and (acc["uv"] as PackedVector2Array).size() == (acc["v"] as PackedVector3Array).size():
		arr[Mesh.ARRAY_TEX_UV] = acc["uv"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
