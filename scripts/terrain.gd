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
# How far water / a deck lifts the surface above the ground at each node (>= 0). Interpolated bilinearly like
# the ground, so surface() is continuous: streets and tracks draped with different vertex spacings then agree
# at deck ends and shores (a nearest-cell step there put one above the other by up to metres)
static var _lf := PackedFloat32Array()
static var _hs_raw := PackedFloat32Array()
static var _lf_raw := PackedFloat32Array()
static var _graded_sig := 0
static var _rigid_max := 60.0


static func load_for(map_key: String, areas: Array, edges: Array = []) -> void:
	active = false
	_hs = PackedFloat32Array()
	_wl = PackedFloat32Array()
	_dk = PackedFloat32Array()
	_lf = PackedFloat32Array()
	_hs_raw = PackedFloat32Array()
	_lf_raw = PackedFloat32Array()
	_graded_sig = 0
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
	_lf.resize(_w * _h)
	for i in range(_w * _h):
		_lf[i] = maxf(0.0, maxf(_wl[i], _dk[i]) - _hs[i])
	_hs_raw = _hs.duplicate()
	_lf_raw = _lf.duplicate()
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


static func _raw_surface(x: float, z: float) -> float:
	if not active or _hs_raw.is_empty():
		return 0.0
	var fx := clampf((x - _x0) / _cell, 0.0, float(_w) - 1.001)
	var fz := clampf((z - _z0) / _cell, 0.0, float(_h) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ux := fx - float(ix)
	var uz := fz - float(iz)
	var k := iz * _w + ix
	var g := lerpf(lerpf(_hs_raw[k], _hs_raw[k + 1], ux), lerpf(_hs_raw[k + _w], _hs_raw[k + _w + 1], ux), uz)
	return g + lerpf(lerpf(_lf_raw[k], _lf_raw[k + 1], ux), lerpf(_lf_raw[k + _w], _lf_raw[k + _w + 1], ux), uz)


# Grade terrain under built tracks: levels out small local undulations into flat stretches or uniform-gradient
# ramps across the full track + platform corridor width, blending smoothly into the surrounding ground.
# Returns true if the graded terrain changed.
static func grade_for_tracks(graph) -> bool:
	if not active or graph == null or _hs_raw.is_empty():
		return false
	var eids: Array = graph.built_tracks.keys()
	eids.sort()
	var sig := 23
	for eid_raw in eids:
		var eid0 := int(eid_raw)
		if graph.edges.has(eid0):
			var ed0: Dictionary = graph.edges[eid0]
			sig = hash([sig, eid0, int(ed0["a"]), int(ed0["b"]), roundi(float(ed0["length"]) * 10.0), int(graph.built_tracks[eid0])])
	if sig == _graded_sig:
		return false
	_graded_sig = sig
	_hs = _hs_raw.duplicate()
	_lf = _lf_raw.duplicate()
	if eids.is_empty():
		return true

	# 1. Build track subgraph and sample raw elevations at track nodes
	var t_adj := {} # nid -> Array of {to, eid, len, dir}
	var node_h := {} # nid -> float
	var valid_eids: Array[int] = []
	for eid_raw in eids:
		var eid := int(eid_raw)
		if not graph.edges.has(eid):
			continue
		var ed: Dictionary = graph.edges[eid]
		var pts: Array = ed.get("pts", [])
		if pts.size() < 2:
			continue
		valid_eids.append(eid)
		var a := int(ed["a"])
		var b := int(ed["b"])
		var elen := maxf(1.0, float(ed.get("length", 20.0)))
		var p_a: Vector2 = pts[0]
		var p_b: Vector2 = pts[pts.size() - 1]
		var dir_ab := (p_b - p_a).normalized() if p_a.distance_to(p_b) > 0.01 else Vector2(1.0, 0.0)
		if not node_h.has(a):
			var pa2: Vector2 = graph.nodes[a]["pos"] if graph.nodes.has(a) else p_a
			node_h[a] = _raw_surface(pa2.x, pa2.y)
			t_adj[a] = []
		if not node_h.has(b):
			var pb2: Vector2 = graph.nodes[b]["pos"] if graph.nodes.has(b) else p_b
			node_h[b] = _raw_surface(pb2.x, pb2.y)
			t_adj[b] = []
		(t_adj[a] as Array).append({"to": b, "eid": eid, "len": elen, "dir": dir_ab})
		(t_adj[b] as Array).append({"to": a, "eid": eid, "len": elen, "dir": -dir_ab})

	if valid_eids.is_empty():
		return true

	var nids: Array = node_h.keys()
	# 2. Long-wavelength graph Laplacian diffusion (removes <500m bumps and dips)
	for _it in range(80):
		var next_h := {}
		for nid: int in nids:
			var nbs: Array = t_adj[nid]
			if nbs.is_empty():
				next_h[nid] = float(node_h[nid])
				continue
			var sum_w := 0.25 / 40.0
			var sum_wh := sum_w * float(node_h[nid])
			for i in range(nbs.size()):
				var nb: Dictionary = nbs[i]
				var d_i: Vector2 = nb["dir"]
				var col_boost := 1.0
				for j in range(nbs.size()):
					if i != j and d_i.dot(nbs[j]["dir"] as Vector2) < -0.55:
						col_boost = 2.6
						break
				var w := col_boost / maxf(18.0, float(nb["len"]))
				sum_w += w
				sum_wh += w * float(node_h[int(nb["to"])])
			var nh := sum_wh / sum_w
			if graph.nodes.has(nid):
				var np: Vector2 = graph.nodes[nid]["pos"]
				nh = maxf(nh, _water_at(np.x, np.y))
			next_h[nid] = nh
		node_h = next_h

	# 3. Extract maximal collinear track chains and apply 1D RDP piecewise-linear uniform-slope grading
	var used_eids := {}
	var chains: Array = []
	# Start chains from terminals/junctions (degree != 2) first, then remaining loop cycles
	for pass_i in range(2):
		for start_nid: int in nids:
			var nbs0: Array = t_adj[start_nid]
			if pass_i == 0 and nbs0.size() == 2:
				continue
			for nb0: Dictionary in nbs0:
				var eid0 := int(nb0["eid"])
				if used_eids.has(eid0):
					continue
				used_eids[eid0] = true
				var chain_nids: Array[int] = [start_nid, int(nb0["to"])]
				var chain_s: Array[float] = [0.0, float(nb0["len"])]
				var prev_dir: Vector2 = nb0["dir"]
				var cur_nid := int(nb0["to"])
				while true:
					var c_nbs: Array = t_adj[cur_nid]
					var best_nb: Dictionary = {}
					var best_dot := 0.35 # only continue along collinear corridor (dot > 0.35)
					for cnb: Dictionary in c_nbs:
						var ceid := int(cnb["eid"])
						if used_eids.has(ceid):
							continue
						var d_dot := prev_dir.dot(cnb["dir"] as Vector2)
						if d_dot > best_dot:
							best_dot = d_dot
							best_nb = cnb
					if best_nb.is_empty():
						break
					used_eids[int(best_nb["eid"])] = true
					cur_nid = int(best_nb["to"])
					chain_nids.append(cur_nid)
					chain_s.append(chain_s[chain_s.size() - 1] + float(best_nb["len"]))
					prev_dir = best_nb["dir"]
				chains.append({"nids": chain_nids, "s": chain_s})

	var locked_nids := {}
	for ch: Dictionary in chains:
		var cn: Array[int] = ch["nids"]
		var cs: Array[float] = ch["s"]
		if cn.size() < 2:
			continue
		var ch_h: Array[float] = []
		for nid_c: int in cn:
			ch_h.append(float(node_h[nid_c]))
		var keep := _rdp_profile_indices(cs, ch_h, 2.1)
		# Flatten spans with negligible elevation change (<1.1m or <0.3% slope)
		for ki in range(keep.size() - 1):
			var i0: int = keep[ki]
			var i1: int = keep[ki + 1]
			var ds := maxf(1.0, cs[i1] - cs[i0])
			var dh := ch_h[i1] - ch_h[i0]
			if absf(dh) < 1.1 or absf(dh) / ds < 0.003:
				if locked_nids.has(cn[i0]) and not locked_nids.has(cn[i1]):
					ch_h[i1] = ch_h[i0]
				elif locked_nids.has(cn[i1]) and not locked_nids.has(cn[i0]):
					ch_h[i0] = ch_h[i1]
				elif not locked_nids.has(cn[i0]) and not locked_nids.has(cn[i1]):
					var avg_h := (ch_h[i0] + ch_h[i1]) * 0.5
					ch_h[i0] = avg_h
					ch_h[i1] = avg_h
		# Strict uniform-slope linear interpolation between kept control points
		for ki in range(keep.size() - 1):
			var i0: int = keep[ki]
			var i1: int = keep[ki + 1]
			var s0 := cs[i0]
			var ds := maxf(0.01, cs[i1] - s0)
			var h0 := ch_h[i0]
			var h1 := ch_h[i1]
			for idx in range(i0, i1 + 1):
				var u := clampf((cs[idx] - s0) / ds, 0.0, 1.0)
				node_h[cn[idx]] = lerpf(h0, h1, u)
				locked_nids[cn[idx]] = true

	# Gentle 4-pass vertical curve rounding at grade break junctions
	for _it2 in range(4):
		var next_h2 := node_h.duplicate()
		for nid: int in nids:
			var nbs: Array = t_adj[nid]
			if nbs.size() < 2:
				continue
			var sw := 0.0
			var swh := 0.0
			for nb: Dictionary in nbs:
				var w := 1.0 / maxf(15.0, float(nb["len"]))
				sw += w
				swh += w * float(node_h[int(nb["to"])])
			next_h2[nid] = lerpf(float(node_h[nid]), swh / sw, 0.35)
		node_h = next_h2

	# 4. Stamp graded track corridors onto the terrain grid (_hs and _lf)
	var touched := {} # cell index k -> [sum_w, sum_wh, min_u]
	for eid: int in valid_eids:
		var ed: Dictionary = graph.edges[eid]
		var pts: Array = ed["pts"]
		var cum: Array[float] = [0.0]
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + (pts[i] as Vector2).distance_to(pts[i - 1] as Vector2))
		var L := maxf(cum[cum.size() - 1], 0.01)
		var ha := float(node_h[int(ed["a"])])
		var hb := float(node_h[int(ed["b"])])
		var road_hw := float(ed.get("width", 12.0)) * 0.5
		if graph.is_quad(eid):
			road_hw = maxf(road_hw, 11.5)
		var flat_r := road_hw + 14.0
		var blend_r := flat_r + 28.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg_v := b - a
			var seg_l := seg_v.length()
			var seg_dir := seg_v / seg_l if seg_l > 0.001 else Vector2(1.0, 0.0)
			var mn := a.min(b) - Vector2(blend_r, blend_r)
			var mx := a.max(b) + Vector2(blend_r, blend_r)
			var j0 := clampi(int(floor((mn.y - _z0) / _cell)), 0, _h - 1)
			var j1 := clampi(int(ceil((mx.y - _z0) / _cell)), 0, _h - 1)
			var i0 := clampi(int(floor((mn.x - _x0) / _cell)), 0, _w - 1)
			var i1 := clampi(int(ceil((mx.x - _x0) / _cell)), 0, _w - 1)
			for j in range(j0, j1 + 1):
				var cz := _z0 + float(j) * _cell
				for ii in range(i0, i1 + 1):
					var c := Vector2(_x0 + float(ii) * _cell, cz)
					var q := Geometry2D.get_closest_point_to_segment(c, a, b)
					var d := c.distance_to(q)
					if d > blend_r:
						continue
					var proj := clampf((c - a).dot(seg_dir), 0.0, seg_l)
					var t := clampf(cum[i] + proj, 0.0, L)
					var h_t := lerpf(ha, hb, t / L)
					var eff_d := maxf(0.0, d - road_hw * 0.6)
					var w := 1.0 / (eff_d * eff_d * eff_d + 0.04)
					var u := clampf((d - flat_r) / (blend_r - flat_r), 0.0, 1.0)
					var k := j * _w + ii
					if touched.has(k):
						var cur_t: Array = touched[k]
						cur_t[0] = float(cur_t[0]) + w
						cur_t[1] = float(cur_t[1]) + w * h_t
						cur_t[2] = minf(float(cur_t[2]), u)
					else:
						touched[k] = [w, w * h_t, u]

	for k: int in touched.keys():
		var info: Array = touched[k]
		var h_trk := float(info[1]) / maxf(1e-6, float(info[0]))
		var u := float(info[2])
		var s_u := u * u * (3.0 - 2.0 * u)
		var h_raw := _hs_raw[k] + _lf_raw[k]
		var h_final := lerpf(h_trk, h_raw, s_u)
		if _wl[k] > -1e5:
			_hs[k] = minf(_hs_raw[k], _wl[k] - 1.2)
			_lf[k] = maxf(0.0, h_final - _hs[k])
		else:
			_hs[k] = h_final
			_lf[k] = 0.0
	return true


static func _rdp_profile_indices(s_arr: Array[float], h_arr: Array[float], tol: float) -> Array[int]:
	var n := s_arr.size()
	if n <= 2:
		var out_s: Array[int] = []
		for i in range(n):
			out_s.append(i)
		return out_s
	var keep_flags := PackedByteArray()
	keep_flags.resize(n)
	keep_flags.fill(0)
	keep_flags[0] = 1
	keep_flags[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var ia := seg.x
		var ib := seg.y
		if ib - ia <= 1:
			continue
		var sa := s_arr[ia]
		var sb := s_arr[ib]
		var ds := maxf(0.01, sb - sa)
		var ha := h_arr[ia]
		var hb := h_arr[ib]
		var best_err := -1.0
		var best_idx := -1
		for i in range(ia + 1, ib):
			var u := clampf((s_arr[i] - sa) / ds, 0.0, 1.0)
			var h_line := lerpf(ha, hb, u)
			var err := absf(h_arr[i] - h_line)
			if err > best_err:
				best_err = err
				best_idx = i
		if best_err > tol and best_idx > ia and best_idx < ib:
			keep_flags[best_idx] = 1
			stack.append(Vector2i(ia, best_idx))
			stack.append(Vector2i(best_idx, ib))
	var out: Array[int] = []
	for i in range(n):
		if keep_flags[i] != 0:
			out.append(i)
	return out


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
	var fx := clampf((x - _x0) / _cell, 0.0, float(_w) - 1.001)
	var fz := clampf((z - _z0) / _cell, 0.0, float(_h) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ux := fx - float(ix)
	var uz := fz - float(iz)
	var k := iz * _w + ix
	var g := lerpf(lerpf(_hs[k], _hs[k + 1], ux), lerpf(_hs[k + _w], _hs[k + _w + 1], ux), uz)
	return g + lerpf(lerpf(_lf[k], _lf[k + 1], ux), lerpf(_lf[k + _w], _lf[k + _w + 1], ux), uz)


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


# Drape a world-space SurfaceTool in CPU RAM before uploading to RenderingServer (safe & instant on worker threads)
static func commit_draped(st: SurfaceTool, mi: MeshInstance3D = null) -> ArrayMesh:
	if not active:
		return st.commit()
	var arr := st.commit_to_arrays()
	var out := ArrayMesh.new()
	if not arr.is_empty() and arr[Mesh.ARRAY_VERTEX] != null:
		arr[Mesh.ARRAY_VERTEX] = _lift_verts(arr[Mesh.ARRAY_VERTEX])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mi != null:
		mi.set_meta("on_terrain", true)
	return out


# Every vertex follows the ground under it (mesh in its node's local frame `xf`)
static func drape_mesh(mesh: Mesh, xf: Transform3D = Transform3D.IDENTITY) -> Mesh:
	var out := ArrayMesh.new()
	var ident := xf.is_equal_approx(Transform3D.IDENTITY)
	var inv := xf.affine_inverse()
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue # empty surface (e.g. a mesh freed / not yet filled): nothing to drape
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
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


# Raise world-space vertices onto surface() (inlined bilinear lookup: this runs over millions of vertices)
static func _lift_verts(verts: PackedVector3Array) -> PackedVector3Array:
	var hs := _hs
	var lf := _lf
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
		v.y += g + (lf[k] * (1.0 - ux) + lf[k + 1] * ux) * (1.0 - uz) + (lf[k + w] * (1.0 - ux) + lf[k + w + 1] * ux) * uz
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


# Densify where the ground needs it: spans of at most max_step, halved (down to min_step) wherever the surface
# under their middle strays more than tol from the straight line between their ends (draped strips then stay
# within a few cm of the ground on curved slopes, without adding vertices on flat streets)
static func densify_adaptive(pts: Array, max_step: float, min_step: float, tol: float) -> Array:
	if not active or pts.size() < 2:
		return pts
	var out: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var n := int(ceil(a.distance_to(b) / max_step))
		var prev := a
		for k in range(1, n + 1):
			var q := a.lerp(b, float(k) / float(n))
			_split_span(prev, q, surface(prev.x, prev.y), surface(q.x, q.y), min_step, tol, out)
			if k < n:
				out.append([q.x, q.y])
			prev = q
		out.append(pts[i + 1])
	return out


static func _split_span(a: Vector2, b: Vector2, ha: float, hb: float, min_step: float, tol: float, out: Array) -> void:
	if a.distance_to(b) < min_step * 2.0:
		return
	var mid := (a + b) * 0.5
	var hm := surface(mid.x, mid.y)
	var q1 := a.lerp(b, 0.25)
	var q3 := a.lerp(b, 0.75)
	# the ground is bilinear on its cells: a kink can sit anywhere along the span, not just in the middle
	var dev := maxf(absf(hm - (ha + hb) * 0.5), maxf(absf(surface(q1.x, q1.y) - lerpf(ha, hb, 0.25)), absf(surface(q3.x, q3.y) - lerpf(ha, hb, 0.75))))
	if dev <= tol:
		return
	_split_span(a, mid, ha, hm, min_step, tol, out)
	out.append([mid.x, mid.y])
	_split_span(mid, b, hm, hb, min_step, tol, out)


# Ground mesh: the terrain itself, in 512 m chunks (one node each, for culling), full 8 m detail up close and a
# 32 m version far away
static func build_ground(parent: Node3D, bounds: Array, mat: Material, step_cells: int = 1) -> void:
	if not active:
		return
	var old := parent.get_node_or_null("TerrainGround")
	if old != null:
		parent.remove_child(old)
		old.queue_free()
	var holder := Node3D.new()
	holder.name = "TerrainGround"
	holder.set_meta("on_terrain", true)
	holder.set_meta("bounds", bounds)
	holder.set_meta("mat", mat)
	holder.set_meta("step_cells", step_cells)
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
					mi.visibility_range_end = 600.0
				else:
					mi.visibility_range_begin = 600.0
				holder.add_child(mi)
			cz0 += chunk_m
		cx0 += chunk_m


static func rebuild_ground(parent: Node3D) -> void:
	if not active or parent == null:
		return
	var holder := parent.get_node_or_null("TerrainGround")
	if holder == null or not holder.has_meta("bounds"):
		return
	build_ground(parent, holder.get_meta("bounds"), holder.get_meta("mat"), int(holder.get_meta("step_cells", 1)))


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
