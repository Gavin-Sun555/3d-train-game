class_name TrackBuilder
extends RefCounted

const RAIL_HALF_GAUGE := 0.7175
const CATENARY_HEIGHT := 4.95

const EMBED_RAIL_TOP := 0.098
const VIGNOLE_RAIL_TOP := 0.218

enum BedStyle {
	GRASS_VIGNOLE = 0, # 独立路权 · 工字轨草皮道床
	ASPHALT = 1,       # 柏油马路 · 槽型轨嵌轨
	GRASS_EMBED = 2,   # 绿茵草皮 · 齐平槽型嵌轨
	STONE_SLAB = 3,    # 花岗岩步行街板
	BALLAST = 4,       # 传统碎石道砟 · 工字轨枕木
	MONORAIL = 5,      # 高架单轨梁 · 跨座式单轨 (separate track system)
}

const MONORAIL_BEAM_TOP := 7.2 # rail-top reference for straddle-beam monorail (beam top ~7.1m above street)
const MONORAIL_HALF_SEP := 2.4 # twin guideway beams 4.8m apart (cars 2.9m wide)


static func is_monorail_style(style: int) -> bool:
	return style == BedStyle.MONORAIL


# 0 = tram (street-running rails), 1 = monorail (elevated beam). Systems never connect to each other.
static func edge_system(graph: NetworkGraph, eid: int) -> int:
	return 1 if is_monorail_style(int(graph.built_tracks.get(eid, -1))) else 0


static func create_smooth_curve(raw_pts: Array, closed_loop: bool) -> Curve3D:
	var pts: Array[Vector3] = []
	for p in raw_pts:
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))

	var curve := Curve3D.new()
	curve.bake_interval = 0.35
	var n := pts.size()
	if n < 2:
		return curve

	for i in range(n):
		var prev_idx := (i - 1 + n) % n if closed_loop else maxi(0, i - 1)
		var next_idx := (i + 1) % n if closed_loop else mini(n - 1, i + 1)
		var p_prev := pts[prev_idx]
		var p_curr := pts[i]
		var p_next := pts[next_idx]

		var chord := p_next - p_prev
		var dir := chord.normalized() if chord.length() > 0.001 else Vector3.FORWARD
		var d_in := p_curr.distance_to(p_prev) * 0.24
		var d_out := p_curr.distance_to(p_next) * 0.24

		var in_vec := -dir * d_in
		var out_vec := dir * d_out
		if absf(p_curr.y - p_prev.y) < 0.02 and absf(p_next.y - p_curr.y) < 0.02:
			in_vec.y = 0.0
			out_vec.y = 0.0

		if not closed_loop and i == 0:
			in_vec = Vector3.ZERO
		if not closed_loop and i == n - 1:
			out_vec = Vector3.ZERO
		# Reversal cusp (terminal turnback): the path doubles back on itself, so keep zero handles
		# to make the return leg retrace the arrival leg exactly instead of looping sideways.
		if _is_cusp_point(p_prev, p_curr, p_next):
			in_vec = Vector3.ZERO
			out_vec = Vector3.ZERO

		curve.add_point(p_curr, in_vec, out_vec)

	if closed_loop:
		var p_prev := pts[n - 1]
		var p_curr := pts[0]
		var p_next := pts[1]
		var dir := (p_next - p_prev).normalized()
		var in_vec := -dir * (p_curr.distance_to(p_prev) * 0.24)
		var out_vec := dir * (p_curr.distance_to(p_next) * 0.24)
		if absf(p_curr.y - p_prev.y) < 0.02 and absf(p_next.y - p_curr.y) < 0.02:
			in_vec.y = 0.0
			out_vec.y = 0.0
		if _is_cusp_point(p_prev, p_curr, p_next):
			in_vec = Vector3.ZERO
			out_vec = Vector3.ZERO
		curve.add_point(p_curr, in_vec, out_vec)

	return curve


static func _is_cusp_point(p_prev: Vector3, p_curr: Vector3, p_next: Vector3) -> bool:
	var v_in := p_curr - p_prev
	var v_out := p_next - p_curr
	if v_in.length_squared() < 1e-6 or v_out.length_squared() < 1e-6:
		return false
	return v_in.normalized().dot(v_out.normalized()) < -0.3


# ---------------------------------------------------------------------------------------------
# Shared rail geometry: used by BOTH the track renderer and the tram route compiler, so trams
# always ride exactly on the rails that are drawn (edge curves, junction connector arcs, crossovers).
# ---------------------------------------------------------------------------------------------

static func built_edges_at_node(graph: NetworkGraph, nid: int, sys: int = -1) -> Array:
	var out: Array = []
	for nb: Dictionary in graph.adj.get(nid, []):
		var eid := int(nb["edge_id"])
		if graph.built_tracks.has(eid) and not out.has(eid) and (sys < 0 or edge_system(graph, eid) == sys):
			out.append(eid)
	return out


# {bare: bool (trimmed + connector arcs), trim: float, edges: Array}
static func node_track_info(graph: NetworkGraph, nid: int, sys: int = 0) -> Dictionary:
	var elist := built_edges_at_node(graph, nid, sys)
	var is_bare := _is_bare_junction_node(graph, nid, elist)
	var has_sep_change := false
	if elist.size() == 2:
		var sa := graph.get_edge_track_half_sep(int(elist[0]))
		var sb := graph.get_edge_track_half_sep(int(elist[1]))
		if absf(sa - sb) > 0.1:
			has_sep_change = true
	var trim := 2.2
	if is_bare:
		trim = _node_intersection_trim(graph, nid)
	elif has_sep_change:
		trim = 5.5
	return {"bare": is_bare or has_sep_change, "trim": trim, "edges": elist}


# Smoothed centerline curve of a built edge plus the trimmed [s_start, s_end] range where its rails are laid.
static func edge_track_geom(graph: NetworkGraph, eid: int) -> Dictionary:
	if not graph.edges.has(eid):
		return {}
	var ed: Dictionary = graph.edges[eid]
	var curve := _edge_smooth_curve(graph, eid)
	if curve == null:
		return {}
	var clen := curve.get_baked_length()
	if clen < 2.0:
		return {}
	var na_id := int(ed["a"])
	var nb_id := int(ed["b"])
	var e_sys := edge_system(graph, eid)
	var info_a := node_track_info(graph, na_id, e_sys)
	var info_b := node_track_info(graph, nb_id, e_sys)
	var is_bare_a := bool(info_a["bare"]) or ((graph.adj.get(na_id, []) as Array).size() >= 3)
	var is_bare_b := bool(info_b["bare"]) or ((graph.adj.get(nb_id, []) as Array).size() >= 3)
	var s_start := minf(float(info_a["trim"]), clen * 0.44) if is_bare_a else 0.0
	var s_end := maxf(clen - minf(float(info_b["trim"]), clen * 0.44), s_start + 1.0) if is_bare_b else clen
	var is_double := graph.is_multi_track(eid)
	var sep := graph.get_edge_track_half_sep(eid)
	var g := {
		"curve": curve,
		"clen": clen,
		"s_start": s_start,
		"s_end": s_end,
		"sep": sep if is_double else 0.0,
		"is_double": is_double,
	}
	if is_double:
		var prof := _curve_clearance_sep_profile(curve, clen, sep)
		var n_prof := prof.size()
		# Rails flow straight through plain 2-edge nodes (no connector arc), so the spacing must match on both
		# sides of the joint: meet at the larger of the two widenings and ease back over SEP_JOIN_RAMP_M.
		# Keep ramp strictly under half the edge length so opposite ends never perturb each other's endpoint sep.
		var ramp_len := minf(SEP_JOIN_RAMP_M, maxf(clen * 0.48, 1.0))
		for end_i in range(2):
			var nid := na_id if end_i == 0 else nb_id
			var bare := is_bare_a if end_i == 0 else is_bare_b
			if bare:
				continue
			var el: Array = (info_a if end_i == 0 else info_b)["edges"]
			if el.size() != 2:
				continue
			var other := int(el[0]) if int(el[1]) == eid else int(el[1])
			if not graph.is_multi_track(other):
				continue
			var o_curve := _edge_smooth_curve(graph, other)
			if o_curve == null:
				continue
			var o_len := o_curve.get_baked_length()
			var o_prof := _curve_clearance_sep_profile(o_curve, o_len, graph.get_edge_track_half_sep(other))
			var o_end := o_prof[0] if int(graph.edges[other]["a"]) == nid else o_prof[o_prof.size() - 1]
			var own_end := prof[0] if end_i == 0 else prof[n_prof - 1]
			var target := maxf(own_end, o_end)
			for i in range(n_prof):
				var s_i := clen * float(i) / float(maxi(n_prof - 1, 1))
				var d := s_i if end_i == 0 else (clen - s_i)
				if d > ramp_len:
					continue
				var w := 1.0 - smoothstep(0.0, ramp_len, d)
				prof[i] = maxf(prof[i], lerpf(sep, target, w))
		g["sep_prof"] = prof
		if graph.is_quad(eid):
			g["quad"] = true
			g["lsep_prof"] = _quad_local_sep_profile(graph, eid, curve, clen, prof, s_start, s_end, na_id, nb_id, e_sys)
	return g


# Four-track edge: half separation of the outer local tracks along the edge (same sampling as sep_prof).
# One track spacing outside the express pair, flared out to QUAD_ISLAND_LOCAL_SEP around twin-island stops,
# and merged back into the express tracks at every end that does not continue as four-track.
static func _quad_local_sep_profile(graph: NetworkGraph, eid: int, curve: Curve3D, clen: float, xprof: PackedFloat32Array,
		s_start: float, s_end: float, na_id: int, nb_id: int, e_sys: int) -> PackedFloat32Array:
	var n := xprof.size()
	var spacing := NetworkGraph.QUAD_LOCAL_HALF_SEP - NetworkGraph.DOUBLE_TRACK_HALF_SEP
	var out := PackedFloat32Array()
	out.resize(n)
	var islands: Array = [] # [s_station, half_platform]
	for sid: int in graph.stations.keys():
		var st: Dictionary = graph.stations[sid]
		if int(st["edge_id"]) == eid and int(st.get("side", 1)) == 0:
			islands.append([curve.get_closest_offset(st["pos"] as Vector3), float(st.get("platform_len", 27.0)) * 0.5 + 1.0])
	# Distance from each end of this edge to the end of the whole four-track section (0 where it ends right here)
	var ext_a := _quad_run_beyond(graph, eid, na_id, e_sys)
	var ext_b := _quad_run_beyond(graph, eid, nb_id, e_sys)
	var section := ext_a + ext_b + (s_end - s_start)
	var ramp := minf(NetworkGraph.QUAD_MERGE_RAMP, maxf(section * 0.45, 4.0))
	for i in range(n):
		var s_i := clen * float(i) / float(maxi(n - 1, 1))
		var base := xprof[i] + spacing
		var fl := 0.0
		for isl: Array in islands:
			var d := absf(s_i - float(isl[0])) - float(isl[1])
			fl = maxf(fl, 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, NetworkGraph.QUAD_ISLAND_TAPER, d))
		var v := lerpf(base, maxf(base, NetworkGraph.QUAD_ISLAND_LOCAL_SEP), fl)
		var w_a := 1.0 if ext_a >= NetworkGraph.QUAD_MERGE_RAMP - 0.01 else smoothstep(0.0, ramp, s_i - s_start + ext_a)
		var w_b := 1.0 if ext_b >= NetworkGraph.QUAD_MERGE_RAMP - 0.01 else smoothstep(0.0, ramp, s_end - s_i + ext_b)
		var w := minf(w_a, w_b)
		out[i] = lerpf(xprof[i], v, w)
	return out


# Length of four-track running on beyond node `nid` (away from `eid`), up to QUAD_MERGE_RAMP; 0 if it ends here
static func _quad_run_beyond(graph: NetworkGraph, eid: int, nid: int, e_sys: int) -> float:
	var acc := 0.0
	var cur_e := eid
	var cur_n := nid
	var guard := 0
	while acc < NetworkGraph.QUAD_MERGE_RAMP and guard < 12:
		guard += 1
		if not _quad_continues(graph, cur_e, cur_n, e_sys):
			break
		var el := built_edges_at_node(graph, cur_n, e_sys)
		var nxt := int(el[0]) if int(el[1]) == cur_e else int(el[1])
		var c := _edge_smooth_curve(graph, nxt)
		acc += c.get_baked_length() if c != null else float(graph.edges[nxt]["length"])
		cur_n = int(graph.edges[nxt]["b"]) if int(graph.edges[nxt]["a"]) == cur_n else int(graph.edges[nxt]["a"])
		cur_e = nxt
		if cur_e == eid:
			break
	return minf(acc, NetworkGraph.QUAD_MERGE_RAMP)


# The four tracks run on through node `nid`: exactly one other built edge of the same system meets here and it is
# four-track too (road crossings in between are fine: the junction connectors carry all four tracks across).
static func _quad_continues(graph: NetworkGraph, eid: int, nid: int, e_sys: int) -> bool:
	var el := built_edges_at_node(graph, nid, e_sys)
	if el.size() != 2:
		return false
	var other := int(el[0]) if int(el[1]) == eid else int(el[1])
	return graph.is_quad(other)


static func geom_lsep_at(geom: Dictionary, s: float) -> float:
	if not geom.has("lsep_prof"):
		return geom_sep_at(geom, s)
	var prof: PackedFloat32Array = geom["lsep_prof"]
	var clen := maxf(float(geom.get("clen", 1.0)), 0.001)
	var f := clampf(s / clen, 0.0, 1.0) * float(prof.size() - 1)
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, prof.size() - 1)
	return lerpf(prof[i0], prof[i1], f - float(i0))


# Lateral offsets of every track laid on an edge at arc length s (single: [0]; double: [-x, x]; four-track:
# [-local, -express, express, local]).
static func geom_track_offsets(geom: Dictionary, s: float) -> Array[float]:
	if geom.is_empty() or not bool(geom.get("is_double", false)):
		return [0.0]
	var x := geom_sep_at(geom, s)
	if not geom.has("lsep_prof"):
		return [-x, x]
	var l := geom_lsep_at(geom, s)
	return [-l, -x, x, l]


# Outermost track offset (trackbed edges, kerbs, masts)
static func geom_outer_sep_at(geom: Dictionary, s: float) -> float:
	if geom.has("lsep_prof"):
		return geom_lsep_at(geom, s)
	return geom_sep_at(geom, s)


const SEP_JOIN_RAMP_M := 22.0


# ---------------------------------------------------------------------------------------------
# Track clearance index: every laid lane centerline (edges, crossovers, junction connector arcs)
# sampled every 0.5m into a 4m spatial hash. Poles, lamps and trees use it to stay clear of trams.
# ---------------------------------------------------------------------------------------------
const CLEAR_CELL := 4.0
const MAST_CLEARANCE_M := 2.0 # own lane sits 2.18m from a mast
const LAMP_CLEARANCE_M := 2.6
const TREE_CLEARANCE_M := 3.9 # crowns spread ~2.4m from the trunk at car-roof height


static func build_track_clearance_index(graph: NetworkGraph) -> Dictionary:
	var grid := {}
	var geoms := {}
	for eid: int in graph.built_tracks.keys():
		var g := edge_track_geom(graph, eid)
		if g.is_empty():
			continue
		geoms[eid] = g
		var c: Curve3D = g["curve"]
		var clen := float(g["clen"])
		var ss := float(g["s_start"])
		while ss <= float(g["s_end"]) + 0.001:
			var tf := sample_track_frame(c, minf(ss, float(g["s_end"])), clen, false)
			if bool(g["is_double"]):
				var sp_v := geom_sep_at(g, ss)
				_clear_add(grid, tf.origin + tf.basis.x * sp_v)
				_clear_add(grid, tf.origin - tf.basis.x * sp_v)
			else:
				_clear_add(grid, tf.origin)
			ss += 0.5
		var xo := edge_crossover_span(graph, eid, g)
		if not xo.is_empty():
			for xk in range(41):
				var u := float(xk) / 40.0
				var sx := lerpf(float(xo["s_mid"]) - float(xo["x_half"]), float(xo["s_mid"]) + float(xo["x_half"]), u)
				var tf2 := sample_track_frame(c, sx, clen, false)
				var herm := 3.0 * u * u - 2.0 * u * u * u
				var sep := geom_sep_at(g, sx)
				for xd: float in [-1.0, 1.0]:
					_clear_add(grid, tf2.origin + tf2.basis.x * (xd * lerpf(-sep, sep, herm)))
	# Player-built streets: hide trees / lamps / furniture standing on the new carriageway
	for eid_p: int in graph.edges.keys():
		var edp: Dictionary = graph.edges[eid_p]
		if not bool(edp.get("player", false)) or bool(edp.get("no_cars", false)):
			continue
		var pp: Array = edp["pts"]
		var hw_p := float(edp.get("width", 9.8)) * 0.5
		for pi in range(pp.size() - 1):
			var pa2: Vector2 = pp[pi]
			var pb2: Vector2 = pp[pi + 1]
			var sl := pa2.distance_to(pb2)
			var dv := (pb2 - pa2) / maxf(sl, 0.001)
			var nv := Vector2(-dv.y, dv.x)
			var u := 0.0
			while u <= sl:
				var lat := -hw_p
				while lat <= hw_p:
					var q := pa2 + dv * u + nv * lat
					_clear_add(grid, Vector3(q.x, 0.0, q.y))
					lat += 2.0
				u += 2.0
	for nid_sys: Vector2i in _node_sys_pairs(graph):
		var nid := nid_sys.x
		var info := node_track_info(graph, nid, nid_sys.y)
		var el: Array = info["edges"]
		if el.size() < 2 or (not bool(info["bare"]) and el.size() == 2):
			continue
		for ia in range(el.size()):
			for ib in range(ia + 1, el.size()):
				var ea := int(el[ia]); var eb := int(el[ib])
				if not geoms.has(ea) or not geoms.has(eb):
					continue
				var ga: Dictionary = geoms[ea]; var gb: Dictionary = geoms[eb]
				var ea_is_a := int(graph.edges[ea]["a"]) == nid
				var eb_is_a := int(graph.edges[eb]["a"]) == nid
				var s_a := float(ga["s_start"]) if ea_is_a else float(ga["s_end"])
				var s_b := float(gb["s_start"]) if eb_is_a else float(gb["s_end"])
				var tf_a := sample_track_frame(ga["curve"], s_a, float(ga["clen"]), false)
				var tf_b := sample_track_frame(gb["curve"], s_b, float(gb["clen"]), false)
				var out_a := (-tf_a.basis.z if ea_is_a else tf_a.basis.z).normalized()
				var out_b := (-tf_b.basis.z if eb_is_a else tf_b.basis.z).normalized()
				var right_a := (tf_a.basis.x if ea_is_a else -tf_a.basis.x).normalized()
				var right_b := (tf_b.basis.x if eb_is_a else -tf_b.basis.x).normalized()
				var dbl_a := bool(ga["is_double"]); var dbl_b := bool(gb["is_double"])
				var lanes: Array[float] = [0.0]
				if dbl_a or dbl_b:
					lanes = [-1.0, 1.0]
				for lane: float in lanes:
					var pa := tf_a.origin - right_a * (lane * geom_sep_at(ga, s_a) if dbl_a else 0.0)
					var pb := tf_b.origin + right_b * (lane * geom_sep_at(gb, s_b) if dbl_b else 0.0)
					var jc := junction_connector_curve(pa, -out_a, pb, out_b)
					if jc == null:
						continue
					var jl := jc.get_baked_length()
					var js := 0.0
					while js <= jl:
						_clear_add(grid, jc.sample_baked(js, true))
						js += 0.5
	return {"grid": grid}


static func _node_sys_pairs(graph: NetworkGraph) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for nid: int in graph.nodes.keys():
		for sys in range(2):
			out.append(Vector2i(nid, sys))
	return out


static func _clear_add(grid: Dictionary, p: Vector3) -> void:
	var k := Vector2i(int(floor(p.x / CLEAR_CELL)), int(floor(p.z / CLEAR_CELL)))
	if not grid.has(k):
		grid[k] = PackedVector2Array()
	var arr: PackedVector2Array = grid[k]
	arr.append(Vector2(p.x, p.z))
	grid[k] = arr


# Distance from p to the nearest laid lane centerline (999 if none within ~8m).
static func track_clearance_dist(idx: Dictionary, p: Vector2) -> float:
	if idx.is_empty():
		return 999.0
	var grid: Dictionary = idx["grid"]
	var cx := int(floor(p.x / CLEAR_CELL))
	var cz := int(floor(p.y / CLEAR_CELL))
	var best_sq := 999.0 * 999.0
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := Vector2i(cx + dx, cz + dz)
			if not grid.has(k):
				continue
			for q: Vector2 in (grid[k] as PackedVector2Array):
				best_sq = minf(best_sq, p.distance_squared_to(q))
	return sqrt(best_sq)


# ---------------------------------------------------------------------------------------------
# Monorail alignment: an elevated guideway does not have to follow the kerb line. Street polylines jog 30-80 deg
# around offset intersections although the street runs straight on; following them gives needless sharp
# S-bends (20 km/h). Each chain of guideway edges (between dead ends / guideway junctions) is therefore
# re-aligned as a whole: the street polyline is simplified (Douglas-Peucker, MONO_ALIGN_TOL) so jogs vanish and
# only real corners remain, each real corner is rounded with the widest curve that fits, and the result is cut
# back into per-edge polylines at the nodes. Station platforms (+ approach) keep the exact street line, since
# platforms are placed on it.
# ---------------------------------------------------------------------------------------------
const MONO_ALIGN_TOL := 6.0
const MONO_STATION_GUARD := 10.0
const MONO_MAX_CORNER_CUT := 5.0
# Street-level tram track gets the same treatment within a much tighter lateral budget: it shares the road with
# cars (motor lanes keep >= ~1.9 m clear of a tram body), so it may only drift a little off the street centre.
const TRAM_ALIGN_TOL := 2.0
const TRAM_STATION_GUARD := 8.0
const TRAM_MAX_CORNER_CUT := 2.0
const TRAM_MAX_SHIFT := 2.0
static var _align_cache := {} # system -> per-edge polylines
static var _align_key := {} # system -> signature


static func _polyline_len(pts2: Array) -> float:
	var l := 0.0
	for k in range(pts2.size() - 1):
		l += (pts2[k] as Vector2).distance_to(pts2[k + 1])
	return l


static func _dp_simplify(pts: Array, i0: int, i1: int, tol: float, keep: Dictionary) -> void:
	if i1 <= i0 + 1:
		return
	var a: Vector2 = pts[i0]
	var b: Vector2 = pts[i1]
	var best := -1.0
	var bi := -1
	var ab := b - a
	var l2 := ab.length_squared()
	for i in range(i0 + 1, i1):
		var p: Vector2 = pts[i]
		var dist := p.distance_to(a) if l2 < 0.0001 else p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))
		if dist > best:
			best = dist
			bi = i
	if best > tol:
		keep[bi] = true
		_dp_simplify(pts, i0, bi, tol, keep)
		_dp_simplify(pts, bi, i1, tol, keep)


static func _align_signature(graph: NetworkGraph, sys: int) -> String:
	var parts: PackedStringArray = []
	var ks: Array = graph.built_tracks.keys()
	ks.sort()
	for eid: int in ks:
		if (1 if is_monorail_style(int(graph.built_tracks[eid])) else 0) == sys:
			parts.append(str(eid))
	parts.append("|")
	for sid: int in graph.stations.keys():
		var st: Dictionary = graph.stations[sid]
		if graph.built_tracks.has(int(st["edge_id"])) and (1 if is_monorail_style(int(graph.built_tracks[int(st["edge_id"])])) else 0) == sys:
			parts.append("%d:%.3f:%.1f" % [int(st["edge_id"]), float(st["t"]), float(st.get("platform_len", 27.0))])
	return ",".join(parts) + "#%d" % graph.get_instance_id()


static func _mono_alignments(graph: NetworkGraph) -> Dictionary:
	return _track_alignments(graph, 1)


# Per-edge track polylines (oriented a -> b) for every built edge of system `sys` (0 tram, 1 monorail);
# cached until that system's track or stations change
static func _track_alignments(graph: NetworkGraph, sys: int) -> Dictionary:
	var key := _align_signature(graph, sys)
	if str(_align_key.get(sys, "")) == key:
		return _align_cache[sys]
	var res := {}
	var mono: Dictionary = {}
	for eid: int in graph.built_tracks.keys():
		if (1 if is_monorail_style(int(graph.built_tracks[eid])) else 0) == sys and graph.edges.has(eid) and (graph.edges[eid]["pts"] as Array).size() >= 2:
			mono[eid] = true
	var used := {}
	var deg := func(nid: int) -> int:
		var c := 0
		for nb: Dictionary in graph.adj.get(nid, []):
			if mono.has(int(nb["edge_id"])):
				c += 1
		return c
	var starts: Array = []
	for eid: int in mono.keys():
		for nid: int in [int(graph.edges[eid]["a"]), int(graph.edges[eid]["b"])]:
			if deg.call(nid) != 2:
				starts.append([eid, nid])
	for st_pair: Array in starts:
		var e0 := int(st_pair[0])
		if used.has(e0):
			continue
		# Walk the chain
		var chain_e: Array = []
		var chain_fwd: Array = [] # true when the edge runs a -> b along the chain
		var cur_e := e0
		var cur_n := int(st_pair[1])
		while true:
			used[cur_e] = true
			chain_e.append(cur_e)
			var fwd := int(graph.edges[cur_e]["a"]) == cur_n
			chain_fwd.append(fwd)
			var far_n := int(graph.edges[cur_e]["b"]) if fwd else int(graph.edges[cur_e]["a"])
			if deg.call(far_n) != 2 or far_n == int(st_pair[1]):
				break
			var nxt := -1
			for nb: Dictionary in graph.adj.get(far_n, []):
				var ne := int(nb["edge_id"])
				if mono.has(ne) and ne != cur_e and not used.has(ne):
					nxt = ne
			if nxt < 0:
				break
			cur_e = nxt
			cur_n = far_n
		_mono_align_chain(graph, chain_e, chain_fwd, res, sys)
	_align_cache[sys] = res
	_align_key[sys] = key
	return res


static func _mono_align_chain(graph: NetworkGraph, chain_e: Array, chain_fwd: Array, res: Dictionary, sys: int = 1) -> void:
	var tol := MONO_ALIGN_TOL if sys == 1 else TRAM_ALIGN_TOL
	var guard := MONO_STATION_GUARD if sys == 1 else TRAM_STATION_GUARD
	var max_cut := MONO_MAX_CORNER_CUT if sys == 1 else TRAM_MAX_CORNER_CUT
	var max_shift := 15.0 if sys == 1 else TRAM_MAX_SHIFT
	# 1. Raw chain polyline, node positions (arc length) and fixed (station) ranges
	var pts: Array = []
	var node_d: Array[float] = [0.0]
	var fixed: Array = [] # [d0, d1]
	var open_ground: Array = [] # [d0, d1] of tram-only track across open ground (no street to stay inside)
	var acc := 0.0
	for ci in range(chain_e.size()):
		var eid := int(chain_e[ci])
		var ep: Array = (graph.edges[eid]["pts"] as Array).duplicate()
		if not bool(chain_fwd[ci]):
			ep.reverse()
		var e_len := _polyline_len(ep)
		if bool(graph.edges[eid].get("no_cars", false)):
			open_ground.append([acc, acc + e_len])
		for sid: int in graph.stations.keys():
			var st: Dictionary = graph.stations[sid]
			if int(st["edge_id"]) != eid:
				continue
			var st_d := float(st["t"]) * e_len if bool(chain_fwd[ci]) else (1.0 - float(st["t"])) * e_len
			var hw := float(st.get("platform_len", 27.0)) * 0.5 + guard
			fixed.append([acc + st_d - hw, acc + st_d + hw])
		for k in range(ep.size()):
			if k == 0 and not pts.is_empty():
				continue
			pts.append(ep[k])
		acc += e_len
		node_d.append(acc)
	# Resample every 2 m (fine enough to cut fixed ranges and nodes exactly), remember fixed samples
	var samples: Array = []
	var s_d: Array[float] = []
	var total := acc
	var n_s := maxi(2, int(ceil(total / 2.0)) + 1)
	var seg_i := 0
	var seg_acc := 0.0
	for k in range(n_s):
		var d := total * float(k) / float(n_s - 1)
		while seg_i < pts.size() - 2 and seg_acc + (pts[seg_i] as Vector2).distance_to(pts[seg_i + 1]) < d:
			seg_acc += (pts[seg_i] as Vector2).distance_to(pts[seg_i + 1])
			seg_i += 1
		var pa: Vector2 = pts[seg_i]
		var pb: Vector2 = pts[seg_i + 1]
		var sl := maxf(pa.distance_to(pb), 0.0001)
		samples.append(pa.lerp(pb, clampf((d - seg_acc) / sl, 0.0, 1.0)))
		s_d.append(d)
	var keep := {0: true, n_s - 1: true}
	var is_fixed := func(d: float) -> bool:
		for fr: Array in fixed:
			if d >= float(fr[0]) - 0.01 and d <= float(fr[1]) + 0.01:
				return true
		return false
	for k in range(n_s):
		if is_fixed.call(s_d[k]):
			keep[k] = true
	# 2. Douglas-Peucker between consecutive kept samples
	var kept_sorted: Array = keep.keys()
	kept_sorted.sort()
	for i in range(kept_sorted.size() - 1):
		_dp_simplify(samples, int(kept_sorted[i]), int(kept_sorted[i + 1]), tol, keep)
	kept_sorted = keep.keys()
	kept_sorted.sort()
	var verts: Array = []
	var v_fixed: Array[bool] = []
	for k: int in kept_sorted:
		verts.append(samples[k])
		v_fixed.append(bool(is_fixed.call(s_d[k])) or k == 0 or k == n_s - 1)
	# 2b. DP vertices sit on jog points (offset intersection nodes are usually all offset to the same side), so
	#     fit each straight run to the street samples it spans (least squares) and put free corners where the
	#     neighbouring fitted lines meet -> the guideway follows the street centre, not its kerb-side jogs.
	var fits: Array = [] # per run: [point, dir] or []
	for i in range(kept_sorted.size() - 1):
		var k0 := int(kept_sorted[i])
		var k1 := int(kept_sorted[i + 1])
		if k1 - k0 < 6:
			fits.append([])
			continue
		var c := Vector2.ZERO
		for k in range(k0, k1 + 1):
			c += samples[k]
		c /= float(k1 - k0 + 1)
		var sxx := 0.0
		var syy := 0.0
		var sxy := 0.0
		for k in range(k0, k1 + 1):
			var q: Vector2 = samples[k] - c
			sxx += q.x * q.x
			syy += q.y * q.y
			sxy += q.x * q.y
		var th := 0.5 * atan2(2.0 * sxy, sxx - syy)
		fits.append([c, Vector2(cos(th), sin(th))])
	for i in range(1, verts.size() - 1):
		if v_fixed[i]:
			continue
		var fa: Array = fits[i - 1]
		var fb: Array = fits[i]
		var v0: Vector2 = verts[i]
		var cands: Array = []
		if not fa.is_empty():
			var pa0: Vector2 = fa[0]
			var da0: Vector2 = fa[1]
			cands.append(pa0 + da0 * (v0 - pa0).dot(da0))
		if not fb.is_empty():
			var pb0: Vector2 = fb[0]
			var db0: Vector2 = fb[1]
			cands.append(pb0 + db0 * (v0 - pb0).dot(db0))
		if cands.is_empty():
			continue
		var nv := Vector2.ZERO
		for cq: Vector2 in cands:
			nv += cq
		nv /= float(cands.size())
		if not fa.is_empty() and not fb.is_empty():
			var da: Vector2 = fa[1]
			var db: Vector2 = fb[1]
			var den := da.cross(db)
			if absf(den) > sin(deg_to_rad(4.0)):
				var pa: Vector2 = fa[0]
				var pb: Vector2 = fb[0]
				var x := pa + da * ((pb - pa).cross(db) / den)
				if x.distance_to(v0) < max_shift:
					nv = x
		verts[i] = nv
	# 3. Round every free corner as widely as the neighbouring straights allow
	var line: Array = [verts[0]]
	for i in range(1, verts.size() - 1):
		var v: Vector2 = verts[i]
		if v_fixed[i]:
			line.append(v)
			continue
		var pv: Vector2 = verts[i - 1]
		var nv: Vector2 = verts[i + 1]
		var lp := v.distance_to(pv) * (0.95 if v_fixed[i - 1] else 0.5)
		var ln := v.distance_to(nv) * (0.95 if v_fixed[i + 1] else 0.5)
		var t := minf(lp, ln)
		var ang := absf((v - pv).angle_to(nv - v))
		# The arc's middle cuts the corner by t*sin(ang/2)/2: stay within the street (no slicing building corners)
		t = minf(t, 2.0 * max_cut / maxf(sin(ang * 0.5), 0.01))
		if t < 0.5 or ang < deg_to_rad(1.0):
			line.append(v)
			continue
		var t0 := v + (pv - v).normalized() * t
		var t1 := v + (nv - v).normalized() * t
		var n_arc := clampi(int(ceil(t / 3.0)), 3, 14)
		for j in range(n_arc + 1):
			var u := float(j) / float(n_arc)
			line.append(t0 * (1.0 - u) * (1.0 - u) + v * 2.0 * u * (1.0 - u) + t1 * u * u)
	line.append(verts[verts.size() - 1])
	if sys == 0:
		line = _tram_relax(graph, line, samples, s_d, fixed, open_ground)
	# 4. Cut back into edges: a node lands where the new line passes closest to it (in order, near its old position)
	var l_cum: Array[float] = [0.0]
	for i in range(1, line.size()):
		l_cum.append(l_cum[i - 1] + (line[i - 1] as Vector2).distance_to(line[i]))
	var l_tot: float = l_cum[l_cum.size() - 1]
	var cuts: Array[float] = [0.0]
	for ni in range(1, chain_e.size()):
		var nid := int(graph.edges[int(chain_e[ni])]["a"]) if bool(chain_fwd[ni]) else int(graph.edges[int(chain_e[ni])]["b"])
		var np: Vector2 = graph.nodes[nid]["pos"]
		var guess := l_tot * node_d[ni] / maxf(total, 0.001)
		var best_d := 1e18
		var best_s := guess
		for i in range(line.size() - 1):
			if absf(l_cum[i] - guess) > 60.0 and absf(l_cum[i + 1] - guess) > 60.0:
				continue
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var ab := b - a
			var f := clampf((np - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var dd := np.distance_squared_to(a + ab * f)
			if dd < best_d:
				best_d = dd
				best_s = l_cum[i] + f * ab.length()
		cuts.append(clampf(best_s, cuts[cuts.size() - 1] + 4.0, l_tot - 4.0 * float(chain_e.size() - ni)))
	cuts.append(l_tot)
	var point_at := func(s: float) -> Vector2:
		for i in range(line.size() - 1):
			if l_cum[i + 1] >= s:
				var seg := maxf(l_cum[i + 1] - l_cum[i], 0.0001)
				return (line[i] as Vector2).lerp(line[i + 1], clampf((s - l_cum[i]) / seg, 0.0, 1.0))
		return line[line.size() - 1]
	for ci in range(chain_e.size()):
		var s0 := cuts[ci]
		var s1 := cuts[ci + 1]
		var ep2: Array = [point_at.call(s0)]
		for i in range(line.size()):
			if l_cum[i] > s0 + 0.3 and l_cum[i] < s1 - 0.3:
				ep2.append(line[i])
		ep2.append(point_at.call(s1))
		if not bool(chain_fwd[ci]):
			ep2.reverse()
		res[int(chain_e[ci])] = ep2


# Street-level tram: turn what is left of the street's jogs (offset intersections, kinks in the kerb data) into
# gentle S-curves. The line is resampled every TRAM_RELAX_STEP m and relaxed by curvature-minimising (bi-Laplacian)
# steps while being held inside a corridor of TRAM_MAX_SHIFT m around the street centre (wider inside
# intersections, where the whole junction is paved), so straights stay straight and bends get the widest
# radius the street allows. Platforms (+ approach) and the chain ends stay exactly where they are.
const TRAM_RELAX_STEP := 3.0
const TRAM_RELAX_ITERS := 700
const TRAM_JUNCTION_SHIFT := 3.5

const OPEN_GROUND_SHIFT := 8.0

static func _tram_relax(graph: NetworkGraph, line: Array, street: Array, street_d: Array[float], fixed: Array, open_ground: Array = []) -> Array:
	var l_tot := _polyline_len(line)
	var n := int(ceil(l_tot / TRAM_RELAX_STEP)) + 1
	if n < 7:
		return line
	var pts := PackedVector2Array()
	var acc := 0.0
	var seg := 0
	for k in range(n):
		var d := l_tot * float(k) / float(n - 1)
		while seg < line.size() - 2 and acc + (line[seg] as Vector2).distance_to(line[seg + 1]) < d:
			acc += (line[seg] as Vector2).distance_to(line[seg + 1])
			seg += 1
		var a: Vector2 = line[seg]
		var b: Vector2 = line[seg + 1]
		pts.append(a.lerp(b, clampf((d - acc) / maxf(a.distance_to(b), 0.0001), 0.0, 1.0)))
	# Nearest street sample of each point (monotone along the chain), its corridor width and whether it is fixed
	var near := PackedInt32Array()
	near.resize(n)
	var budget := PackedFloat32Array()
	budget.resize(n)
	var locked := PackedByteArray()
	locked.resize(n)
	var junctions: Array = [] # [pos, radius] of every road intersection along the way
	var j_seen := {}
	var m := street.size()
	var j := 0
	for k in range(n):
		var best := 1e18
		var bj := j
		for jj in range(maxi(0, j - 4), mini(m, j + 12)):
			var dd := pts[k].distance_squared_to(street[jj])
			if dd < best:
				best = dd
				bj = jj
		j = bj
		near[k] = bj
		var dk: float = street_d[bj]
		var fx := k < 3 or k > n - 4
		for fr: Array in fixed:
			if dk >= float(fr[0]) - 0.01 and dk <= float(fr[1]) + 0.01:
				fx = true
		locked[k] = 1 if fx else 0
	for nid: int in graph.nodes.keys():
		var adj: Array = graph.adj.get(nid, [])
		if adj.size() < 3:
			continue
		var np: Vector2 = graph.nodes[nid]["pos"]
		var w_min := 1e9
		for nb: Dictionary in adj:
			w_min = minf(w_min, float(graph.edges[int(nb["edge_id"])].get("width", 12.0)))
		j_seen[nid] = [np, w_min * 0.5]
	# Only junctions near this chain matter
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		bb = bb.expand(p)
	bb = bb.grow(12.0)
	for nid: int in j_seen.keys():
		if bb.has_point(j_seen[nid][0]):
			junctions.append(j_seen[nid])
	for k in range(n):
		var bud := TRAM_MAX_SHIFT
		var dkb: float = street_d[int(near[k])]
		for og: Array in open_ground:
			if dkb >= float(og[0]) + 4.0 and dkb <= float(og[1]) - 4.0:
				bud = OPEN_GROUND_SHIFT
		for jn: Array in junctions:
			if pts[k].distance_to(jn[0]) < float(jn[1]):
				bud = maxf(bud, minf(TRAM_JUNCTION_SHIFT, float(jn[1]) - 2.6))
		budget[k] = bud
	var clamp_pt := func(k: int, p: Vector2) -> Vector2:
		var c := int(near[k])
		var best_p: Vector2 = street[c]
		var best := 1e18
		for jj in range(maxi(0, c - 3), mini(m - 1, c + 3)):
			var a: Vector2 = street[jj]
			var ab: Vector2 = (street[jj + 1] as Vector2) - a
			var q := a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var dd := p.distance_squared_to(q)
			if dd < best:
				best = dd
				best_p = q
		var off := p - best_p
		var lim := budget[k]
		if off.length_squared() > lim * lim:
			return best_p + off.normalized() * lim
		return p
	# Work only where the line bends (plus a margin); long straights are already optimal
	var active := PackedInt32Array()
	var mark := PackedByteArray()
	mark.resize(n)
	for k in range(1, n - 1):
		var t_ang := absf((pts[k] - pts[k - 1]).angle_to(pts[k + 1] - pts[k]))
		if t_ang > deg_to_rad(0.3):
			for q in range(maxi(0, k - 14), mini(n, k + 15)):
				mark[q] = 1
	for k in range(2, n - 2):
		if mark[k] == 1 and locked[k] == 0:
			active.append(k)
	if active.is_empty():
		return line
	var lam := 0.06
	var nxt := pts.duplicate()
	for _it in range(TRAM_RELAX_ITERS):
		for k: int in active:
			var bl := pts[k - 2] - 4.0 * pts[k - 1] + 6.0 * pts[k] - 4.0 * pts[k + 1] + pts[k + 2]
			nxt[k] = clamp_pt.call(k, pts[k] - bl * lam)
		for k: int in active:
			pts[k] = nxt[k]
	var out: Array = []
	for p: Vector2 in pts:
		out.append(p)
	return out


# Polyline the guideway of monorail edge `eid` actually follows (oriented a -> b)
static func mono_alignment_pts(graph: NetworkGraph, eid: int) -> Array:
	var al := _mono_alignments(graph)
	if al.has(eid):
		return al[eid]
	return graph.edges[eid]["pts"]


static func _edge_pts(graph: NetworkGraph, eid: int) -> Array:
	if not graph.built_tracks.has(eid):
		return graph.edges[eid]["pts"]
	var al := _track_alignments(graph, edge_system(graph, eid))
	if al.has(eid):
		return al[eid]
	return graph.edges[eid]["pts"]


static func _edge_neighbor_dir(graph: NetworkGraph, eid: int, nid: int) -> Vector3:
	if not graph.edges.has(eid):
		return Vector3.ZERO
	var ed: Dictionary = graph.edges[eid]
	var pts2: Array = _edge_pts(graph, eid)
	var n := pts2.size()
	if n < 2:
		return Vector3.ZERO
	var is_a := (int(ed["a"]) == nid)
	var p0_2: Vector2 = pts2[0] if is_a else pts2[n - 1]
	var p0 := Vector3(p0_2.x, 0.0, p0_2.y)
	var step := 1 if is_a else -1
	var idx := 1 if is_a else (n - 2)
	while idx >= 0 and idx < n:
		var pk_2: Vector2 = pts2[idx]
		var pk := Vector3(pk_2.x, 0.0, pk_2.y)
		var dv := pk - p0
		if dv.length_squared() > 0.01:
			return dv.normalized()
		idx += step
	return Vector3.ZERO


# Builds the edge's smoothed centerline curve, enforcing exact G1 tangent continuity across every plain
# non-bare 2-edge node so double-track rails and trackbeds meet with 0.000m lateral gap/overlap on curves.
static func _edge_smooth_curve(graph: NetworkGraph, eid: int) -> Curve3D:
	if not graph.edges.has(eid):
		return null
	var ed: Dictionary = graph.edges[eid]
	var pts2: Array = _edge_pts(graph, eid)
	if pts2.size() < 2:
		return null
	var raw3: Array = []
	for p2: Vector2 in pts2:
		raw3.append([p2.x, 0.0, p2.y])
	var c := create_smooth_curve(raw3, false)
	var n := c.point_count
	if n < 2:
		return null
	var e_sys := edge_system(graph, eid)
	for end_i in range(2):
		var nid := int(ed["a"]) if end_i == 0 else int(ed["b"])
		if (graph.adj.get(nid, []) as Array).size() >= 3:
			continue
		var info := node_track_info(graph, nid, e_sys)
		if bool(info["bare"]):
			continue
		var el: Array = info["edges"]
		if el.size() != 2:
			continue
		var other := int(el[0]) if int(el[1]) == eid else int(el[1])
		var u_self := _edge_neighbor_dir(graph, eid, nid)
		var u_other := _edge_neighbor_dir(graph, other, nid)
		var diff := u_other - u_self
		if diff.length_squared() < 0.04:
			continue
		var t_to_other := diff.normalized()
		if end_i == 0:
			var seg_len := c.get_point_position(0).distance_to(c.get_point_position(1))
			c.set_point_in(0, Vector3.ZERO)
			c.set_point_out(0, -t_to_other * (seg_len * 0.24))
		else:
			var seg_len := c.get_point_position(n - 1).distance_to(c.get_point_position(n - 2))
			c.set_point_in(n - 1, -t_to_other * (seg_len * 0.24))
			c.set_point_out(n - 1, Vector3.ZERO)
	return c if c.get_baked_length() >= 2.0 else null


# Half track separation needed so two trams passing on a curve never touch: car bodies cut inside the curve
# at mid-length and swing outside at the ends, together ~L^2/(8R). Sized for the longest car (14.2m sections).
const CLEARANCE_DESIGN_CAR_LEN := 14.5
const CLEARANCE_BASE_HALF := 1.48 # half car width (1.33) + 0.15m safety
const CLEARANCE_MAX_EXTRA := 2.4


static func _curve_clearance_sep_profile(curve: Curve3D, clen: float, base_sep: float) -> PackedFloat32Array:
	var n := maxi(2, int(ceil(clen)) + 1)
	var need := PackedFloat32Array()
	need.resize(n)
	var l2 := CLEARANCE_DESIGN_CAR_LEN * CLEARANCE_DESIGN_CAR_LEN
	for i in range(n):
		var s := clen * float(i) / float(n - 1)
		var fb := -sample_track_frame(curve, maxf(0.0, s - 2.0), clen, false).basis.z
		var ff := -sample_track_frame(curve, minf(clen, s + 2.0), clen, false).basis.z
		var chord := minf(clen, s + 2.0) - maxf(0.0, s - 2.0)
		var ang := acos(clampf(fb.dot(ff), -1.0, 1.0))
		var radius := chord / maxf(ang, 0.0005)
		need[i] = clampf(CLEARANCE_BASE_HALF + l2 / (16.0 * radius), base_sep, base_sep + CLEARANCE_MAX_EXTRA)
	# Hold the widening over a car length around the tightest point, then ease it in/out smoothly
	var win := int(ceil(CLEARANCE_DESIGN_CAR_LEN * 0.55))
	var held := PackedFloat32Array()
	held.resize(n)
	for i in range(n):
		var m := need[i]
		for k in range(maxi(0, i - win), mini(n - 1, i + win) + 1):
			m = maxf(m, need[k])
		held[i] = m
	var out := held
	for _pass in range(4):
		var sm := PackedFloat32Array()
		sm.resize(n)
		for i in range(n):
			var acc := 0.0
			var cnt := 0
			for k in range(maxi(0, i - 7), mini(n - 1, i + 7) + 1):
				acc += out[k]
				cnt += 1
			sm[i] = maxf(base_sep, acc / float(cnt))
		out = sm
	return out


static func geom_sep_at(geom: Dictionary, s: float) -> float:
	if geom.is_empty():
		return 0.0
	if not geom.has("sep_prof"):
		return float(geom.get("sep", 0.0))
	var prof: PackedFloat32Array = geom["sep_prof"]
	var clen := maxf(float(geom.get("clen", 1.0)), 0.001)
	var f := clampf(s / clen, 0.0, 1.0) * float(prof.size() - 1)
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, prof.size() - 1)
	return lerpf(prof[i0], prof[i1], f - float(i0))


# Crossover footprint along an edge curve: {s_mid, x_half}; empty if the edge has no drawable crossover.
static func edge_crossover_span(graph: NetworkGraph, eid: int, geom: Dictionary) -> Dictionary:
	if geom.is_empty() or not bool(geom["is_double"]) or geom.has("lsep_prof"):
		return {}
	if int(graph.crossovers.get(eid, NetworkGraph.CrossoverType.NONE)) <= NetworkGraph.CrossoverType.NONE:
		return {}
	var s0 := float(geom["s_start"])
	var s1 := float(geom["s_end"])
	var span := s1 - s0
	if span < 10.0:
		return {}
	var x_half := crossover_x_half(edge_system(graph, eid) == 1, int(graph.crossovers[eid]), span)
	var t_xo := clampf(float(graph.crossover_t.get(eid, 0.5)), 0.0, 1.0)
	var clen := float(geom["clen"])
	var s_min := s0 + x_half + 0.8
	var s_max := s1 - x_half - 0.8
	var s_mid := (s0 + s1) * 0.5 if s_min >= s_max else clampf(t_xo * clen, s_min, s_max)
	return {
		"s_mid": s_mid,
		"x_half": x_half,
	}


# Half-length of a crossover footprint. Monorail beams sit 4.8m apart, so a beam switch is long (gentle S-bend);
# a two-way monorail crossover is two such switches in series, hence twice as long.
static func crossover_x_half(is_mono: bool, xtype: int, span: float) -> float:
	if not is_mono:
		return minf(9.5, span * 0.44)
	if xtype == NetworkGraph.CrossoverType.DOUBLE:
		return minf(40.0, span * 0.44)
	return minf(20.0, span * 0.44)


# Monorail beam switches inside a crossover footprint: SINGLE = one switch, DOUBLE (two-way) = two opposite-handed
# switches in series. hand +1: lane -1 at the low-s end -> lane +1 at the high-s end (the turnback departure
# move); hand -1 is its mirror (arrival straight onto the other platform track).
static func mono_switch_parts(graph: NetworkGraph, eid: int, xo: Dictionary) -> Array:
	if xo.is_empty():
		return []
	var s_mid := float(xo["s_mid"])
	var xh := float(xo["x_half"])
	if int(graph.crossovers.get(eid, NetworkGraph.CrossoverType.NONE)) != NetworkGraph.CrossoverType.DOUBLE:
		return [{"s_mid": s_mid, "x_half": xh, "hand": 1.0}]
	var h := xh * 0.5
	return [{"s_mid": s_mid - h, "x_half": h, "hand": 1.0}, {"s_mid": s_mid + h, "x_half": h, "hand": -1.0}]


# Validates and computes exact placement for a crossover near cursor `t_val` along double-track `eid`.
# Automatically snaps cleanly right outside an island-station track merge taper while strictly forbidding
# any overlap with station platforms!
static func compute_crossover_placement(graph: NetworkGraph, eid: int, t_val: float, xtype: int = NetworkGraph.CrossoverType.SINGLE) -> Dictionary:
	if not graph.built_tracks.has(eid) or not graph.edges.has(eid):
		return {"valid": false, "reason": "no_track"}
	if int(graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) != NetworkGraph.TrackMode.DOUBLE:
		return {"valid": false, "reason": "single_track"}
	var geom := edge_track_geom(graph, eid)
	if geom.is_empty():
		return {"valid": false, "reason": "too_short"}
	var s0 := float(geom["s_start"])
	var s1 := float(geom["s_end"])
	var clen := float(geom["clen"])
	var span := s1 - s0
	var is_mono := (edge_system(graph, eid) == 1)
	var min_span := (56.0 if xtype == NetworkGraph.CrossoverType.DOUBLE else 26.0) if is_mono else 18.0
	if span < min_span or float(graph.edges[eid]["length"]) < 22.0:
		return {"valid": false, "reason": "too_short"}

	var x_half := crossover_x_half(is_mono, xtype, span)
	var s_min := s0 + x_half + 0.8
	var s_max := s1 - x_half - 0.8
	if s_min > s_max:
		return {"valid": false, "reason": "too_short"}

	var curve: Curve3D = geom["curve"]
	var std_sep := MONORAIL_HALF_SEP if is_mono else NetworkGraph.DOUBLE_TRACK_HALF_SEP
	var s_cand := clampf(t_val * clen, s_min, s_max)

	# If tracks near this edge end are still tapering down from an adjacent island station,
	# gently snap s_cand to the nearest point right where the twin tracks finish merging back together!
	var check_clear := func(sc: float) -> String:
		var tf_c := sample_track_frame(curve, sc, clen, false)
		var pos_c := tf_c.origin
		for sid: int in graph.stations.keys():
			var st: Dictionary = graph.stations[sid]
			var st_half := float(st.get("platform_len", 27.0)) * 0.5
			if int(st["edge_id"]) == eid:
				var st_s := clampf(float(st["t"]), 0.0, 1.0) * clen
				var need_d := st_half + x_half + 2.0
				if absf(sc - st_s) < need_d:
					return "on_station"
			else:
				var st_pos: Vector3 = st["pos"]
				if pos_c.distance_to(st_pos) < st_half + x_half + 1.5:
					return "on_station"
		return ""

	var err: String = check_clear.call(s_cand)
	# Also ensure the crossover doesn't sit in the widened splay zone right next to an island station;
	# if the user hovered inside the taper, snap cleanly to the start of the merged straight throat!
	if err == "" and (geom_sep_at(geom, s_cand - x_half) > std_sep + 0.22 or geom_sep_at(geom, s_cand + x_half) > std_sep + 0.22):
		var best_s := -1.0
		var best_d := 1e9
		var probe := s_min
		while probe <= s_max + 0.01:
			var sp_p := minf(probe, s_max)
			if geom_sep_at(geom, sp_p - x_half) <= std_sep + 0.22 and geom_sep_at(geom, sp_p + x_half) <= std_sep + 0.22:
				if str(check_clear.call(sp_p)) == "":
					var dd := absf(sp_p - s_cand)
					if dd < best_d:
						best_d = dd
						best_s = sp_p
			probe += 2.0
		if best_s >= 0.0:
			s_cand = best_s

	err = check_clear.call(s_cand)
	var tf_mid := sample_track_frame(curve, s_cand, clen, false)
	if err != "":
		return {
			"valid": false,
			"reason": err,
			"s_mid": s_cand,
			"t_clamped": s_cand / maxf(clen, 1.0),
			"x_half": x_half,
			"pos": tf_mid.origin,
			"fwd": -tf_mid.basis.z,
		}

	return {
		"valid": true,
		"reason": "",
		"s_mid": s_cand,
		"t_clamped": s_cand / maxf(clen, 1.0),
		"x_half": x_half,
		"pos": tf_mid.origin,
		"fwd": -tf_mid.basis.z,
	}


static func station_overlaps_crossover(
	graph: NetworkGraph,
	eid: int,
	t_val: float,
	_req_kind: int = NetworkGraph.StationKind.SIDE_SINGLE,
	plat_len: float = 27.0,
	margin: float = 2.0
) -> bool:
	if not graph.crossovers.has(eid):
		return false
	var geom := edge_track_geom(graph, eid)
	var xo := edge_crossover_span(graph, eid, geom)
	if xo.is_empty():
		return false
	var st_s := clampf(t_val, 0.15, 0.85) * float(geom["clen"])
	return absf(st_s - float(xo["s_mid"])) < (plat_len * 0.5) + float(xo["x_half"]) + margin


# Cubic junction connector arc from rail end point `pa` (travelling along `ta`) to rail start `pb` (travelling along `tb`).
static func junction_connector_curve(pa: Vector3, ta: Vector3, pb: Vector3, tb: Vector3) -> Curve3D:
	var chord_d := pa.distance_to(pb)
	if chord_d < 0.02:
		return null
	var h_len := minf(chord_d * 0.42, 9.5)
	var j_curve := Curve3D.new()
	j_curve.bake_interval = 0.35
	j_curve.add_point(pa, Vector3.ZERO, ta.normalized() * h_len)
	j_curve.add_point(pb, -tb.normalized() * h_len, Vector3.ZERO)
	if j_curve.get_baked_length() < 0.02:
		return null
	return j_curve


static func is_vignole_style(style: int) -> bool:
	return style == BedStyle.GRASS_VIGNOLE or style == BedStyle.BALLAST


static func rail_top_for_style(style: int) -> float:
	if is_monorail_style(style):
		return MONORAIL_BEAM_TOP
	return VIGNOLE_RAIL_TOP if is_vignole_style(style) else EMBED_RAIL_TOP


static func sample_track_frame(curve: Curve3D, s: float, total_len: float, closed_loop: bool) -> Transform3D:
	var s0 := fposmod(s, total_len) if closed_loop else clampf(s, 0.0, total_len)
	var ds := 0.35
	var s_ahead := fposmod(s0 + ds, total_len) if closed_loop else minf(s0 + ds, total_len)
	var s_behind := fposmod(s0 - ds, total_len) if closed_loop else maxf(s0 - ds, 0.0)

	var pos := curve.sample_baked(s0, true)
	var fwd := Vector3.ZERO
	# Use exact analytical Bezier endpoint tangents at non-loop curve ends so meeting curves align to 0.000deg
	if not closed_loop and curve.point_count >= 2:
		if s0 <= 0.001:
			var out0 := curve.get_point_out(0)
			if out0.length_squared() > 1e-6:
				fwd = out0.normalized()
		elif s0 >= total_len - 0.001:
			var in_last := curve.get_point_in(curve.point_count - 1)
			if in_last.length_squared() > 1e-6:
				fwd = (-in_last).normalized()
	if fwd.length_squared() < 1e-6:
		var p_ahead := curve.sample_baked(s_ahead, true)
		var p_behind := curve.sample_baked(s_behind, true)
		fwd = (p_ahead - p_behind)
		if fwd.length_squared() < 1e-6:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()

	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	return Transform3D(Basis(right, up, -fwd), pos)


static func build_network_tracks_and_stations(
	parent: Node3D,
	graph: NetworkGraph,
	cjk_font: Font,
	grass_mat: ShaderMaterial
) -> Dictionary:
	var station_lights: Array[OmniLight3D] = []
	var station_views: Dictionary = {}

	var clear_idx := build_track_clearance_index(graph)
	graph.set_meta("track_clear_idx", clear_idx)
	graph.set_meta("station_bays", [])
	if graph.built_tracks.is_empty():
		return {"stations": station_views, "lights": station_lights}

	var grass_st := SurfaceTool.new(); grass_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_grass := false
	var curb_st := SurfaceTool.new(); curb_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_curb := false
	var collar_st := SurfaceTool.new(); collar_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_collar := false
	var stone_st := SurfaceTool.new(); stone_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_stone := false
	var bal_st := SurfaceTool.new(); bal_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_ballast := false
	var lane_mark_st := SurfaceTool.new(); lane_mark_st.begin(Mesh.PRIMITIVE_TRIANGLES); var has_lane_mark := false
	var dark_rail_st := SurfaceTool.new(); dark_rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bright_rail_st := SurfaceTool.new(); bright_rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wire_st := SurfaceTool.new(); wire_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sleeper_tfs: Array[Transform3D] = []
	var clip_tfs: Array[Transform3D] = []
	var bollard_tfs: Array[Transform3D] = []
	var mast_tfs: Array[Transform3D] = []
	var arm_tfs: Array[Transform3D] = []

	var stone_prof: Array[Vector2] = [
		Vector2(-1.38, 0.044), Vector2(-1.34, 0.068), Vector2(1.34, 0.068), Vector2(1.38, 0.044),
	]
	var bal_prof: Array[Vector2] = [
		Vector2(-1.68, 0.040), Vector2(-1.32, 0.102), Vector2(1.32, 0.102), Vector2(1.68, 0.040),
	]
	var low_curb_l: Array[Vector2] = [
		Vector2(-1.50, 0.042), Vector2(-1.47, 0.115), Vector2(-1.32, 0.115), Vector2(-1.32, 0.065),
	]
	var low_curb_r: Array[Vector2] = [
		Vector2(1.32, 0.065), Vector2(1.32, 0.115), Vector2(1.47, 0.115), Vector2(1.50, 0.042),
	]
	var row_curb_l: Array[Vector2] = [
		Vector2(-1.62, 0.042), Vector2(-1.56, 0.225), Vector2(-1.36, 0.225), Vector2(-1.36, 0.075),
	]
	var row_curb_r: Array[Vector2] = [
		Vector2(1.36, 0.075), Vector2(1.36, 0.225), Vector2(1.56, 0.225), Vector2(1.62, 0.042),
	]

	# Precollect station world positions to avoid placing bollards/catenary masts inside platforms
	var st_positions: Array[Dictionary] = []
	for sid: int in graph.stations.keys():
		st_positions.append(graph.stations[sid])

	# Build smooth curved junction connector arcs wherever >= 2 built track edges meet!
	var node_built_edges: Dictionary = {}
	for eid: int in graph.built_tracks.keys():
		if is_monorail_style(int(graph.built_tracks[eid])):
			continue # monorail guideways are built separately (_build_monorail_guideways)
		var ed: Dictionary = graph.edges[eid]
		var na := int(ed["a"])
		var nb := int(ed["b"])
		if not node_built_edges.has(na):
			node_built_edges[na] = []
		if not node_built_edges.has(nb):
			node_built_edges[nb] = []
		node_built_edges[na].append(eid)
		node_built_edges[nb].append(eid)

	# Precompute which junction nodes need curved connectors (intersections, turnouts, sharp bends, or track-width transitions)
	var node_bare_junction: Dictionary = {}
	var node_trim_dist: Dictionary = {}
	for nid: int in node_built_edges.keys():
		var n_info := node_track_info(graph, nid)
		node_bare_junction[nid] = bool(n_info["bare"])
		node_trim_dist[nid] = float(n_info["trim"])

	# Exact saved endpoint Transform3D frames for every built edge (guarantees 0.000m rail gaps at corners!)
	var edge_end_frames: Dictionary = {}
	var edge_geoms: Dictionary = {}
	var edge_eff_vignole: Dictionary = {}

	# Extrude every built street edge with its own permanently saved bed_style & track_mode (single / double)
	for eid: int in graph.built_tracks.keys():
		var seg_st := int(graph.built_tracks[eid])
		var is_double := graph.is_multi_track(eid)
		var sep_base := graph.get_edge_track_half_sep(eid)
		if graph.is_quad(eid):
			sep_base = NetworkGraph.QUAD_LOCAL_HALF_SEP

		# Trim slightly at junctions with >=2 built edges so curved switch arcs connect cleanly (shared with route compiler)
		var geom := edge_track_geom(graph, eid)
		if geom.is_empty():
			continue
		edge_geoms[eid] = geom
		var curve: Curve3D = geom["curve"]
		var clen := float(geom["clen"])
		var s_start := float(geom["s_start"])
		var s_end := float(geom["s_end"])
		var span := s_end - s_start
		var steps := maxi(2, int(ceil(span / 1.4)))

		var frames: Array[Transform3D] = []
		var s_vals: Array[float] = []
		for k in range(steps + 1):
			var s_here := lerpf(s_start, s_end, float(k) / float(steps))
			frames.append(sample_track_frame(curve, s_here, clen, false))
			s_vals.append(s_here)
		edge_end_frames[eid] = {"a_tf": frames[0], "b_tf": frames[frames.size() - 1]}
		if is_monorail_style(seg_st):
			continue

		# Grass bed rule: only lay grass if usable span >= 2x grass bed width (prevents tiny grass patches in boulevard medians/short stubs!)
		var eff_seg_st := seg_st
		if seg_st == BedStyle.GRASS_VIGNOLE or seg_st == BedStyle.GRASS_EMBED:
			var grass_w := (1.38 + sep_base) * 2.0
			var min_grass_span := maxf(grass_w * 2.0, 12.0)
			if span < min_grass_span:
				eff_seg_st = BedStyle.ASPHALT

		var vignole := is_vignole_style(eff_seg_st)
		edge_eff_vignole[eid] = vignole
		for i in range(frames.size() - 1):
			var f0 := frames[i]
			var f1 := frames[i + 1]
			var s0 := s_vals[i]
			var s1 := s_vals[i + 1]
			# Double track spreads apart on tight curves (car-body overhang clearance), see edge_track_geom().
			# sep_* is the OUTERMOST track (bed edges, kerbs); offs* lists every track (four-track: 4 of them).
			var sep := geom_outer_sep_at(geom, (s0 + s1) * 0.5)
			var sep_f0 := geom_outer_sep_at(geom, s0)
			var sep_f1 := geom_outer_sep_at(geom, s1)
			var offs0 := geom_track_offsets(geom, s0)
			var offs1 := geom_track_offsets(geom, s1)

			if eff_seg_st == BedStyle.GRASS_VIGNOLE:
				for li in range(offs0.size()):
					var gf0 := f0; gf0.origin += f0.basis.x * offs0[li]
					var gf1 := f1; gf1.origin += f1.basis.x * offs1[li]
					_emit_turf_quad(grass_st, gf0, gf1, s0, s1, 1.38, 0.076)
				_emit_between_track_turf(grass_st, f0, f1, s0, s1, offs0, offs1, 1.30, 0.075)
				has_grass = true
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(row_curb_l, -sep_f0), _shift_prof(row_curb_l, -sep_f1))
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(row_curb_r, sep_f0), _shift_prof(row_curb_r, sep_f1))
				has_curb = true
			elif eff_seg_st == BedStyle.GRASS_EMBED:
				for li in range(offs0.size()):
					var gf0 := f0; gf0.origin += f0.basis.x * offs0[li]
					var gf1 := f1; gf1.origin += f1.basis.x * offs1[li]
					_emit_turf_quad(grass_st, gf0, gf1, s0, s1, 1.36, 0.068)
				_emit_between_track_turf(grass_st, f0, f1, s0, s1, offs0, offs1, 1.28, 0.067)
				has_grass = true
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(low_curb_l, -sep_f0), _shift_prof(low_curb_l, -sep_f1))
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(low_curb_r, sep_f0), _shift_prof(low_curb_r, sep_f1))
				has_curb = true
			elif eff_seg_st == BedStyle.STONE_SLAB:
				var w_stone_p0: Array[Vector2] = [
					Vector2(-1.38 - sep_f0, 0.044), Vector2(-1.34 - sep_f0, 0.068),
					Vector2(1.34 + sep_f0, 0.068), Vector2(1.38 + sep_f0, 0.044),
				]
				var w_stone_p1: Array[Vector2] = [
					Vector2(-1.38 - sep_f1, 0.044), Vector2(-1.34 - sep_f1, 0.068),
					Vector2(1.34 + sep_f1, 0.068), Vector2(1.38 + sep_f1, 0.044),
				]
				_extrude_open_profile_2(stone_st, f0, f1, w_stone_p0, w_stone_p1)
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(low_curb_l, -sep_f0), _shift_prof(low_curb_l, -sep_f1))
				_extrude_open_profile_2(curb_st, f0, f1, _shift_prof(low_curb_r, sep_f0), _shift_prof(low_curb_r, sep_f1))
				has_stone = true
				has_curb = true
			elif eff_seg_st == BedStyle.BALLAST:
				var w_bal_p0: Array[Vector2] = [
					Vector2(-1.68 - sep_f0, 0.040), Vector2(-1.32 - sep_f0, 0.102),
					Vector2(1.32 + sep_f0, 0.102), Vector2(1.68 + sep_f0, 0.040),
				]
				var w_bal_p1: Array[Vector2] = [
					Vector2(-1.68 - sep_f1, 0.040), Vector2(-1.32 - sep_f1, 0.102),
					Vector2(1.32 + sep_f1, 0.102), Vector2(1.68 + sep_f1, 0.040),
				]
				_extrude_open_profile_2(bal_st, f0, f1, w_bal_p0, w_bal_p1)
				has_ballast = true
			else:
				for li in range(offs0.size()):
					for side: float in [-1.0, 1.0]:
						var rx0 := offs0[li] + side * RAIL_HALF_GAUGE
						var rx1 := offs1[li] + side * RAIL_HALF_GAUGE
						var col_p0: Array[Vector2] = [
							Vector2(rx0 - 0.24, 0.045), Vector2(rx0 - 0.22, 0.062),
							Vector2(rx0 + 0.22, 0.062), Vector2(rx0 + 0.24, 0.045),
						]
						var col_p1: Array[Vector2] = [
							Vector2(rx1 - 0.24, 0.045), Vector2(rx1 - 0.22, 0.062),
							Vector2(rx1 + 0.22, 0.062), Vector2(rx1 + 0.24, 0.045),
						]
						_extrude_open_profile_2(collar_st, f0, f1, col_p0, col_p1)
				has_collar = true
				if int(floor(s0 / 2.4)) % 2 == 0:
					for side: float in [-1.0, 1.0]:
						var lx0 := side * (1.40 + sep_f0)
						var lx1 := side * (1.40 + sep_f1)
						var m_p0: Array[Vector2] = [Vector2(lx0 - 0.065, 0.055), Vector2(lx0 + 0.065, 0.055)]
						var m_p1: Array[Vector2] = [Vector2(lx1 - 0.065, 0.055), Vector2(lx1 + 0.065, 0.055)]
						_extrude_open_profile_2(lane_mark_st, f0, f1, m_p0, m_p1)
					has_lane_mark = true

			for li in range(offs0.size()):
				var sf0 := f0; sf0.origin += f0.basis.x * offs0[li]
				var sf1 := f1; sf1.origin += f1.basis.x * offs1[li]
				_emit_rail_pair_and_wire(dark_rail_st, bright_rail_st, wire_st, sf0, sf1, vignole)

		# Build Single or Double (Scissors) Crossover rails in the middle of double-track edge!
		var xover_type := int(graph.crossovers.get(eid, NetworkGraph.CrossoverType.NONE))
		var xo_span := edge_crossover_span(graph, eid, geom)
		if not xo_span.is_empty():
			var s_mid := float(xo_span["s_mid"])
			var x_half := float(xo_span["x_half"])
			var x_dirs: Array[float] = [1.0]
			if xover_type != NetworkGraph.CrossoverType.SINGLE:
				x_dirs = [-1.0, 1.0]
			for xd: float in x_dirs:
				var x_steps := 14
				var prev_xf := Transform3D.IDENTITY
				for xk in range(x_steps + 1):
					var u := float(xk) / float(x_steps)
					var sx := lerpf(s_mid - x_half, s_mid + x_half, u)
					var tf_base := sample_track_frame(curve, sx, clen, false)
					var herm := 3.0 * u * u - 2.0 * u * u * u
					var sep := geom_sep_at(geom, sx)
					var lat := xd * lerpf(-sep, sep, herm)
					var dlat_ds := xd * (2.0 * sep) * (6.0 * u * (1.0 - u)) / maxf(2.0 * x_half, 1.0)
					var fwd_x := (-tf_base.basis.z + tf_base.basis.x * dlat_ds).normalized()
					var right_x := fwd_x.cross(Vector3.UP).normalized()
					var xf := Transform3D(Basis(right_x, Vector3.UP, -fwd_x), tf_base.origin + tf_base.basis.x * lat + Vector3.UP * (0.005 if xd < 0.0 else 0.0068))
					if xk > 0:
						_emit_rail_pair_and_wire(dark_rail_st, bright_rail_st, wire_st, prev_xf, xf, vignole)
						var xo_bed_y := 0.088 if vignole else 0.062
						var xo_bed_prof: Array[Vector2] = [
							Vector2(-1.12, xo_bed_y - 0.02), Vector2(-1.05, xo_bed_y),
							Vector2(1.05, xo_bed_y), Vector2(1.12, xo_bed_y - 0.02),
						]
						_extrude_open_profile(stone_st, prev_xf, xf, xo_bed_prof)
						has_stone = true
					prev_xf = xf
			# Add amber switch indicator box beside the crossover midpoint (strictly clear of tracks)
			var tf_xo_mid := sample_track_frame(curve, s_mid, clen, false)
			var xo_sep := geom_sep_at(geom, s_mid)
			var xo_pos := tf_xo_mid.origin + tf_xo_mid.basis.x * (xo_sep + 2.05) + Vector3(0.0, 0.28, 0.0)
			if track_clearance_dist(clear_idx, Vector2(xo_pos.x, xo_pos.z)) < 1.95:
				var alt_xo := tf_xo_mid.origin - tf_xo_mid.basis.x * (xo_sep + 2.05) + Vector3(0.0, 0.28, 0.0)
				if track_clearance_dist(clear_idx, Vector2(alt_xo.x, alt_xo.z)) >= 1.95:
					xo_pos = alt_xo
			if track_clearance_dist(clear_idx, Vector2(xo_pos.x, xo_pos.z)) >= 1.95:
				var xo_box := MeshInstance3D.new()
				var xo_bm := BoxMesh.new()
				xo_bm.size = Vector3(0.46, 0.52, 0.46)
				var xo_mat := StandardMaterial3D.new()
				xo_mat.albedo_color = Color(0.96, 0.72, 0.12)
				xo_mat.emission_enabled = true
				xo_mat.emission = Color(0.96, 0.68, 0.10)
				xo_mat.emission_energy_multiplier = 1.1
				xo_bm.material = xo_mat
				xo_box.mesh = xo_bm
				xo_box.position = xo_pos
				xo_box.visibility_range_end = 240.0
				parent.add_child(xo_box)

		# Sleepers, Pandrol clips & ROW bollards on Vignole edges
		if vignole:
			var slp_s := s_start + 0.35
			var slp_idx := 0
			while slp_s < s_end - 0.2:
				var tf_s := sample_track_frame(curve, slp_s, clen, false)
				var sep := geom_outer_sep_at(geom, slp_s)
				var track_offsets := geom_track_offsets(geom, slp_s)
				for t_off: float in track_offsets:
					var slp_tf := tf_s
					slp_tf.origin += tf_s.basis.x * t_off + tf_s.basis.y * (0.080 if seg_st == BedStyle.GRASS_VIGNOLE else 0.092)
					sleeper_tfs.append(slp_tf)
					for side: float in [-1.0, 1.0]:
						var rx := side * RAIL_HALF_GAUGE
						for c_side: float in [-0.105, 0.105]:
							var clip_tf := tf_s
							clip_tf.origin += tf_s.basis.x * (t_off + rx + c_side) + tf_s.basis.y * 0.114
							clip_tfs.append(clip_tf)
				if seg_st == BedStyle.GRASS_VIGNOLE and (slp_idx % 18 == 0):
					var near_stn := false
					for st_d: Dictionary in st_positions:
						if tf_s.origin.distance_to(st_d["pos"] as Vector3) < 17.5:
							near_stn = true
							break
					if not near_stn:
						for b_side: float in [-1.46 - sep, 1.46 + sep]:
							var bol_tf := tf_s
							bol_tf.origin += tf_s.basis.x * b_side + tf_s.basis.y * 0.42
							bollard_tfs.append(bol_tf)
				slp_s += 0.68
				slp_idx += 1

		# Catenary poles every 28m along each built edge
		var pole_s := s_start + 6.0
		while pole_s < s_end - 4.0:
			var tf_p := sample_track_frame(curve, pole_s, clen, false)
			var sep := geom_outer_sep_at(geom, pole_s)
			var side := -1.0
			var near_stn_pole := false
			for st_d: Dictionary in st_positions:
				if tf_p.origin.distance_to(st_d["pos"] as Vector3) < 16.5:
					side = -float(st_d.get("side", 1))
					near_stn_pole = true
					break
			if is_double and near_stn_pole:
				pole_s += 28.0
				continue
			var m_tf := tf_p
			m_tf.origin += tf_p.basis.x * (side * (2.18 + sep)) + tf_p.basis.y * 2.65
			var m_ok := track_clearance_dist(clear_idx, Vector2(m_tf.origin.x, m_tf.origin.z)) >= MAST_CLEARANCE_M
			if m_ok:
				mast_tfs.append(m_tf)
			if is_double:
				# Opposite side mast + twin cantilever arms on double track!
				var m_tf2 := tf_p
				m_tf2.origin += tf_p.basis.x * (-side * (2.18 + sep)) + tf_p.basis.y * 2.65
				if track_clearance_dist(clear_idx, Vector2(m_tf2.origin.x, m_tf2.origin.z)) >= MAST_CLEARANCE_M:
					mast_tfs.append(m_tf2)
				elif not m_ok:
					pole_s += 28.0
					continue
				for t_off: float in geom_track_offsets(geom, pole_s):
					var a_tf_d := tf_p
					var arm_s := signf(t_off)
					a_tf_d.origin += tf_p.basis.x * (t_off + arm_s * 0.95) + tf_p.basis.y * (CATENARY_HEIGHT + 0.14)
					arm_tfs.append(a_tf_d)
			elif m_ok:
				var a_tf := tf_p
				a_tf.origin += tf_p.basis.x * (side * 1.02) + tf_p.basis.y * (CATENARY_HEIGHT + 0.14)
				arm_tfs.append(a_tf)
			pole_s += 28.0

	# Build curved switch/junction rail connectors at every junction with >= 2 built edges!
	for nid: int in node_built_edges.keys():
		var e_list: Array = node_built_edges[nid]
		if e_list.size() < 2:
			continue
		var j_pos2: Vector2 = graph.nodes[nid]["pos"]
		var j_pos3 := Vector3(j_pos2.x, 0.0, j_pos2.y)
		var is_bare_junc := bool(node_bare_junction.get(nid, true))
		if not is_bare_junc and e_list.size() == 2:
			continue
		var trim_d := float(node_trim_dist.get(nid, 7.2))
		var conn_k := 0
		for idx_a in range(e_list.size()):
			for idx_b in range(idx_a + 1, e_list.size()):
				var ea := int(e_list[idx_a])
				var eb := int(e_list[idx_b])
				if not edge_end_frames.has(ea) or not edge_end_frames.has(eb):
					continue
				var ea_is_a := (int(graph.edges[ea]["a"]) == nid)
				var eb_is_a := (int(graph.edges[eb]["a"]) == nid)
				var tf_a: Transform3D = edge_end_frames[ea]["a_tf"] if ea_is_a else edge_end_frames[ea]["b_tf"]
				var tf_b: Transform3D = edge_end_frames[eb]["a_tf"] if eb_is_a else edge_end_frames[eb]["b_tf"]
				# Outward unit vectors pointing AWAY from node `nid` along ea and eb, and their right-hand vectors
				var out_a := (-tf_a.basis.z if ea_is_a else tf_a.basis.z).normalized()
				var out_b := (-tf_b.basis.z if eb_is_a else tf_b.basis.z).normalized()
				var right_a := (tf_a.basis.x if ea_is_a else -tf_a.basis.x).normalized()
				var right_b := (tf_b.basis.x if eb_is_a else -tf_b.basis.x).normalized()
				# Skip only extreme acute U-turn switchbacks (< 43 deg) on multi-way junctions
				if out_a.dot(out_b) > 0.72 and e_list.size() > 2:
					continue
				var dbl_a := graph.is_multi_track(ea)
				var dbl_b := graph.is_multi_track(eb)
				var bst_a := int(graph.built_tracks[ea])
				var bst_b := int(graph.built_tracks[eb])
				var vig_j := bool(edge_eff_vignole.get(ea, is_vignole_style(bst_a))) and bool(edge_eff_vignole.get(eb, is_vignole_style(bst_b)))
				var is_real_road_int := ((graph.adj.get(nid, []) as Array).size() >= 3)
				var keep_grass := (not is_real_road_int) and (not _is_bare_junction_node(graph, nid, e_list)) and (bst_a == BedStyle.GRASS_VIGNOLE or bst_a == BedStyle.GRASS_EMBED) and (bst_b == BedStyle.GRASS_VIGNOLE or bst_b == BedStyle.GRASS_EMBED)

				var g_ea: Dictionary = edge_geoms[ea]
				var g_eb: Dictionary = edge_geoms[eb]
				var se_a := float(g_ea["s_start"]) if ea_is_a else float(g_ea["s_end"])
				var se_b := float(g_eb["s_start"]) if eb_is_a else float(g_eb["s_end"])
				var sep_a := geom_sep_at(g_ea, se_a)
				var sep_b := geom_sep_at(g_eb, se_b)
				# [offset on ea, offset on eb, lane sign]; four-track running on across a road crossing adds the local pair
				var j_pairs: Array = []
				if dbl_a or dbl_b:
					for lane_j: float in [-1.0, 1.0]:
						j_pairs.append([lane_j * sep_a if dbl_a else 0.0, lane_j * sep_b if dbl_b else 0.0, lane_j])
				else:
					j_pairs.append([0.0, 0.0, 0.0])
				if g_ea.has("lsep_prof") and g_eb.has("lsep_prof"):
					var ls_a := geom_lsep_at(g_ea, se_a)
					var ls_b := geom_lsep_at(g_eb, se_b)
					if ls_a - sep_a > 0.3 and ls_b - sep_b > 0.3:
						for lane_j: float in [-1.0, 1.0]:
							j_pairs.append([lane_j * ls_a, lane_j * ls_b, lane_j * 2.0])
				for jp: Array in j_pairs:
					var lane := float(jp[2])
					var off_a := float(jp[0])
					var off_b := float(jp[1])
					var pa_l := tf_a.origin - right_a * off_a
					var pb_l := tf_b.origin + right_b * off_b
					var j_curve := junction_connector_curve(pa_l, -out_a, pb_l, out_b)
					if j_curve == null:
						continue
					var jlen := j_curve.get_baked_length()
					var jsteps := maxi(4, int(ceil(jlen / 0.85)))
					# Connectors at one junction cross each other: lift each by a distinct ~1mm step so their
					# coplanar stone beds / groove strips resolve consistently instead of z-fighting in motion
					conn_k += 1
					var j_lift := Vector3.UP * (float(conn_k % 12) * 0.0009)
					for jk in range(jsteps):
						var s_jk0 := (float(jk) / float(jsteps)) * jlen
						var s_jk1 := (float(jk + 1) / float(jsteps)) * jlen
						var jf0 := sample_track_frame(j_curve, s_jk0, jlen, false)
						var jf1 := sample_track_frame(j_curve, s_jk1, jlen, false)
						jf0.origin += j_lift
						jf1.origin += j_lift
						if keep_grass:
							var turf_y := 0.076 if vig_j else 0.068
							_emit_turf_quad(grass_st, jf0, jf1, s_jk0, s_jk1, 1.38, turf_y)
							has_grass = true
							if not (dbl_a or dbl_b) or (lane < 0.0 and (j_pairs.size() <= 2 or lane < -1.5)):
								_extrude_open_profile(curb_st, jf0, jf1, row_curb_l if vig_j else low_curb_l)
								has_curb = true
							if not (dbl_a or dbl_b) or (lane > 0.0 and (j_pairs.size() <= 2 or lane > 1.5)):
								_extrude_open_profile(curb_st, jf0, jf1, row_curb_r if vig_j else low_curb_r)
								has_curb = true
						elif is_bare_junc:
							_extrude_open_profile(stone_st, jf0, jf1, stone_prof)
							has_stone = true
						_emit_rail_pair_and_wire(dark_rail_st, bright_rail_st, wire_st, jf0, jf1, vig_j)
					if keep_grass and vig_j:
						var js_slp := 0.34
						while js_slp < jlen - 0.15:
							var tf_js := sample_track_frame(j_curve, js_slp, jlen, false)
							var slp_tf := tf_js
							slp_tf.origin += tf_js.basis.y * 0.080 + j_lift
							sleeper_tfs.append(slp_tf)
							for s_rail: float in [-1.0, 1.0]:
								var rx_j := s_rail * RAIL_HALF_GAUGE
								for c_side: float in [-0.105, 0.105]:
									var clip_tf := tf_js
									clip_tf.origin += tf_js.basis.x * (rx_j + c_side) + tf_js.basis.y * 0.114
									clip_tfs.append(clip_tf)
							js_slp += 0.68

	# Commit batched trackbed & rail meshes
	if has_grass:
		var g_mi := MeshInstance3D.new()
		g_mi.name = "GrassTrackBed"
		g_mi.mesh = grass_st.commit()
		g_mi.material_override = grass_mat
		parent.add_child(g_mi)

	if has_collar:
		_commit_mesh(parent, "RailConcreteCollars", collar_st, Color(0.58, 0.56, 0.53), 0.84, 0.0)
	if has_lane_mark:
		_commit_mesh(parent, "TramLaneEdgeDashes", lane_mark_st, Color(0.86, 0.76, 0.34), 0.78, 0.0)
	if has_stone:
		_commit_mesh(parent, "StoneSlabTrackBed", stone_st, Color(0.56, 0.55, 0.52), 0.84, 0.0)
	if has_curb:
		_commit_mesh(parent, "TrackEdgeCurbs", curb_st, Color(0.70, 0.69, 0.66), 0.80, 0.0)
	if has_ballast:
		_commit_mesh(parent, "BallastTrackBed", bal_st, Color(0.40, 0.39, 0.37), 0.94, 0.0)

	_commit_mesh(parent, "RailWebFootAndGrooves", dark_rail_st, Color(0.09, 0.085, 0.08), 0.90, 0.05)

	var bright_mi := MeshInstance3D.new()
	bright_mi.name = "PolishedSteelRailHeads"
	bright_mi.mesh = bright_rail_st.commit()
	var bright_mat := StandardMaterial3D.new()
	bright_mat.albedo_color = Color(0.95, 0.96, 0.98)
	bright_mat.metallic = 0.22
	bright_mat.roughness = 0.18
	bright_mat.metallic_specular = 0.95
	bright_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bright_mi.material_override = bright_mat
	parent.add_child(bright_mi)

	_commit_mesh(parent, "ContactWire", wire_st, Color(0.16, 0.16, 0.16), 0.55, 0.20)

	_emit_multimesh_boxes(parent, "ConcreteSleepers", sleeper_tfs, Vector3(2.26, 0.056, 0.24), Color(0.68, 0.67, 0.64), 0.84, 0.0)
	_emit_multimesh_boxes(parent, "PandrolRailClips", clip_tfs, Vector3(0.065, 0.032, 0.14), Color(0.16, 0.15, 0.15), 0.72, 0.0)

	if not bollard_tfs.is_empty():
		var bmm := MultiMesh.new()
		bmm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045; cyl.bottom_radius = 0.052; cyl.height = 0.44; cyl.radial_segments = 8
		var bol_mat := StandardMaterial3D.new()
		bol_mat.albedo_color = Color(0.16, 0.22, 0.18); bol_mat.metallic = 0.45; bol_mat.roughness = 0.45
		cyl.material = bol_mat
		bmm.mesh = cyl; bmm.instance_count = bollard_tfs.size()
		for idx in range(bollard_tfs.size()):
			bmm.set_instance_transform(idx, bollard_tfs[idx])
		var b_inst := MultiMeshInstance3D.new()
		b_inst.name = "ROWBollards"; b_inst.multimesh = bmm
		parent.add_child(b_inst)

	if not mast_tfs.is_empty():
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.20, 0.22, 0.23); pole_mat.metallic = 0.55; pole_mat.roughness = 0.42

		var mmm := MultiMesh.new()
		mmm.transform_format = MultiMesh.TRANSFORM_3D
		var mcyl := CylinderMesh.new()
		mcyl.top_radius = 0.08; mcyl.bottom_radius = 0.115; mcyl.height = 5.35; mcyl.radial_segments = 8
		mcyl.material = pole_mat
		mmm.mesh = mcyl; mmm.instance_count = mast_tfs.size()
		for idx in range(mast_tfs.size()):
			mmm.set_instance_transform(idx, mast_tfs[idx])
		var m_inst := MultiMeshInstance3D.new()
		m_inst.name = "CatenaryMasts"; m_inst.multimesh = mmm
		parent.add_child(m_inst)

		var amm := MultiMesh.new()
		amm.transform_format = MultiMesh.TRANSFORM_3D
		var abox := BoxMesh.new()
		abox.size = Vector3(2.45, 0.065, 0.065); abox.material = pole_mat
		amm.mesh = abox; amm.instance_count = arm_tfs.size()
		for idx in range(arm_tfs.size()):
			amm.set_instance_transform(idx, arm_tfs[idx])
		var a_inst := MultiMeshInstance3D.new()
		a_inst.name = "CatenaryArms"; a_inst.multimesh = amm
		parent.add_child(a_inst)

	# Build 3D Wayside Speed Limit Signs & Turnout Switch Indicators ahead of curves & turnouts!
	_build_wayside_speed_signs(parent, graph, node_built_edges, edge_geoms, clear_idx, st_positions, cjk_font)

	# Build detailed 3D stations for every station in graph.stations!
	var bays: Array = []
	for sid: int in graph.stations.keys():
		var st_d: Dictionary = graph.stations[sid].duplicate()
		var eid := int(st_d["edge_id"])
		var bst := int(graph.built_tracks.get(eid, BedStyle.ASPHALT))
		var sep_st := graph.get_edge_track_half_sep(eid)
		var quad_e := graph.is_quad(eid)
		if quad_e:
			sep_st = NetworkGraph.QUAD_LOCAL_HALF_SEP # side platforms stand outside the local tracks
		var st_fwd := (st_d["fwd"] as Vector3).normalized()
		var st_right := st_fwd.cross(Vector3.UP).normalized()
		if sep_st > 0.01 and int(st_d["side"]) != 0:
			st_d["pos"] = (st_d["pos"] as Vector3) + st_right * (float(st_d["side"]) * sep_st)
		var rtop := rail_top_for_style(bst)
		if quad_e and int(st_d["side"]) == 0:
			# Four-track twin islands: one between the express and local track of each direction
			var centre: Vector3 = st_d["pos"]
			var twins: Array = []
			for isl_s: float in [-1.0, 1.0]:
				var isl_d := st_d.duplicate()
				isl_d["pos"] = centre + st_right * (isl_s * NetworkGraph.QUAD_ISLAND_CENTER)
				twins.append(StationBuilder.build_detailed_station(parent, isl_d, rtop, cjk_font, station_lights))
			var sv_main: Dictionary = (twins[1] as Dictionary).duplicate()
			sv_main["twins"] = twins
			sv_main["waiting_slots"] = _interleave_slots(twins)
			station_views[sid] = sv_main
			continue
		var sview := StationBuilder.build_detailed_station(parent, st_d, rtop, cjk_font, station_lights)
		station_views[sid] = sview
		# Side platforms take the motor lane: cut the kerb back into a tapered bay so traffic shifts outward
		if int(st_d["side"]) != 0 and not is_monorail_style(bst) and not quad_e:
			bays.append(station_bay(graph, st_d, sep_st))
	graph.set_meta("station_bays", bays)
	_build_buffer_stops(parent, graph, station_lights)
	_build_monorail_guideways(parent, graph)
	_build_tram_switches(parent, graph)

	return {
		"stations": station_views,
		"lights": station_lights,
	}


# Waiting spots alternating between the two islands of a four-track stop (the queue fills both)
static func _interleave_slots(twins: Array) -> Array:
	var out: Array = []
	var a: Array = (twins[0] as Dictionary).get("waiting_slots", [])
	var b: Array = (twins[1] as Dictionary).get("waiting_slots", [])
	for i in range(maxi(a.size(), b.size())):
		if i < b.size():
			out.append(b[i])
		if i < a.size():
			out.append(a[i])
	return out


# Kerb bay around a side platform, in the station frame (pos = outer track centreline, out = away from road centre).
#   platform occupies q = 1.46 .. 4.41 from the track line; the shifted motor lane is centred on LANE_Q;
#   the kerb moves out to BAY_Q over a TAPER on each end (real "lane shift" / kerb build-out geometry).
const BAY_PLATFORM_OUT := 4.41
const BAY_LANE_Q := 6.55
const BAY_KERB_Q := 8.25
const BAY_HALF := 18.0
const BAY_TAPER := 14.0


static func station_bay(graph: NetworkGraph, st_d: Dictionary, sep_st: float) -> Dictionary:
	var fwd := (st_d["fwd"] as Vector3).normalized()
	var side := float(st_d["side"])
	var out := fwd.cross(Vector3.UP).normalized() * side
	var w := float(graph.edges[int(st_d["edge_id"])]["width"])
	var hw := clampf(w * 0.5, 3.2, 10.5)
	var kerb_rel := hw - sep_st
	var bay_half := maxf(BAY_HALF, float(st_d.get("platform_len", 27.0)) * 0.5 + 3.5)
	return {
		"pos": st_d["pos"],
		"fwd": fwd,
		"out": out,
		"half": bay_half,
		"taper": BAY_TAPER,
		"kerb_q": kerb_rel,
		"bay_q": maxf(kerb_rel, BAY_KERB_Q),
		"lane_q": BAY_LANE_Q,
	}


# 0..1 weight of a bay at `along` metres from its centre (1 along the platform, eased to 0 over the taper)
static func bay_blend(bay: Dictionary, along: float) -> float:
	var a := absf(along)
	var half := float(bay["half"])
	if a <= half:
		return 1.0
	var t := clampf((a - half) / float(bay["taper"]), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


static func _shift_prof(prof: Array[Vector2], dx: float) -> Array[Vector2]:
	if absf(dx) < 0.001:
		return prof
	var out: Array[Vector2] = []
	for p: Vector2 in prof:
		out.append(Vector2(p.x + dx, p.y))
	return out


static func _node_intersection_trim(graph: NetworkGraph, nid: int) -> float:
	var max_w := 10.0
	for nb: Dictionary in graph.adj.get(nid, []):
		var w := float(graph.edges[int(nb["edge_id"])]["width"])
		if w > max_w:
			max_w = w
	return clampf(max_w * 0.5 + 1.8, 7.2, 11.5)


static func _is_bare_junction_node(graph: NetworkGraph, nid: int, e_list: Array) -> bool:
	# Bare rails/stone crossing ONLY at real street intersections (adj >= 3), turnouts (built >= 3), or sharp curves!
	if (graph.adj.get(nid, []) as Array).size() >= 3:
		return true
	if e_list.size() != 2:
		return e_list.size() >= 3
	var j_pos2: Vector2 = graph.nodes[nid]["pos"]
	var j_pos3 := Vector3(j_pos2.x, 0.0, j_pos2.y)
	var p_a := _edge_trim_point_near_node(graph, int(e_list[0]), nid, 6.0)
	var p_b := _edge_trim_point_near_node(graph, int(e_list[1]), nid, 6.0)
	var va := (p_a - j_pos3).normalized()
	var vb := (p_b - j_pos3).normalized()
	return va.dot(vb) > -0.78


static func _edge_trim_point_near_node(graph: NetworkGraph, edge_id: int, node_id: int, trim_m: float) -> Vector3:
	var ed: Dictionary = graph.edges[edge_id]
	var elen := maxf(float(ed["length"]), 1.0)
	var dt := minf(trim_m / elen, 0.44)
	var t_use := dt if int(ed["a"]) == node_id else (1.0 - dt)
	return graph.sample_edge(edge_id, t_use)["pos"] as Vector3


static func _emit_rail_pair_and_wire(
	dark_st: SurfaceTool,
	bright_st: SurfaceTool,
	wire_st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	vignole: bool
) -> void:
	for side: float in [-1.0, 1.0]:
		var cx := side * RAIL_HALF_GAUGE
		var inward := -side
		if vignole:
			var foot_prof: Array[Vector2] = [
				Vector2(cx - 0.086, 0.102), Vector2(cx - 0.076, 0.124),
				Vector2(cx - 0.022, 0.130), Vector2(cx - 0.022, 0.184),
				Vector2(cx + 0.022, 0.184), Vector2(cx + 0.022, 0.130),
				Vector2(cx + 0.076, 0.124), Vector2(cx + 0.086, 0.102),
			]
			_extrude_open_profile(dark_st, f0, f1, foot_prof)
			var head_prof: Array[Vector2] = [
				Vector2(cx - 0.046, 0.182), Vector2(cx - 0.044, VIGNOLE_RAIL_TOP),
				Vector2(cx + 0.044, VIGNOLE_RAIL_TOP), Vector2(cx + 0.046, 0.182),
			]
			_extrude_open_profile(bright_st, f0, f1, head_prof)
		else:
			var groove_prof: Array[Vector2] = [
				Vector2(cx - 0.150, 0.062), Vector2(cx - 0.142, 0.080),
				Vector2(cx + 0.142, 0.080), Vector2(cx + 0.150, 0.062),
			]
			_extrude_open_profile(dark_st, f0, f1, groove_prof)
			var r_center := cx - inward * 0.028
			var run_prof: Array[Vector2] = [
				Vector2(r_center - 0.050, 0.080), Vector2(r_center - 0.046, EMBED_RAIL_TOP + 0.012),
				Vector2(r_center + 0.046, EMBED_RAIL_TOP + 0.012), Vector2(r_center + 0.050, 0.080),
			]
			_extrude_open_profile(bright_st, f0, f1, run_prof)
			var g_center := cx + inward * 0.082
			var lip_prof: Array[Vector2] = [
				Vector2(g_center - 0.022, 0.080), Vector2(g_center - 0.020, EMBED_RAIL_TOP + 0.006),
				Vector2(g_center + 0.020, EMBED_RAIL_TOP + 0.006), Vector2(g_center + 0.022, 0.080),
			]
			_extrude_open_profile(bright_st, f0, f1, lip_prof)

	var wire_prof: Array[Vector2] = [
		Vector2(-0.020, CATENARY_HEIGHT - 0.020), Vector2(-0.020, CATENARY_HEIGHT + 0.022),
		Vector2(0.020, CATENARY_HEIGHT + 0.022), Vector2(0.020, CATENARY_HEIGHT - 0.020),
	]
	_extrude_closed_profile(wire_st, f0, f1, wire_prof)


static func _commit_mesh(
	parent: Node3D,
	m_name: String,
	st: SurfaceTool,
	col: Color,
	rough: float,
	metal: float
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = m_name
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)


static func _emit_multimesh_boxes(
	parent: Node3D,
	m_name: String,
	tfs: Array[Transform3D],
	sz: Vector3,
	col: Color,
	rough: float,
	vis_end: float = 0.0
) -> void:
	if tfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	box.material = mat
	mm.mesh = box
	mm.instance_count = tfs.size()
	for idx in range(tfs.size()):
		mm.set_instance_transform(idx, tfs[idx])
	var inst := MultiMeshInstance3D.new()
	inst.name = m_name
	inst.multimesh = mm
	if vis_end > 0.0:
		inst.visibility_range_end = vis_end
	parent.add_child(inst)


static func _build_wayside_speed_signs(
	parent: Node3D,
	graph: NetworkGraph,
	node_built_edges: Dictionary,
	edge_geoms: Dictionary,
	clear_idx: Dictionary,
	st_positions: Array[Dictionary],
	cjk_font: Font
) -> void:
	var holder := Node3D.new()
	holder.name = "WaysideSpeedSigns"
	parent.add_child(holder)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.24, 0.26, 0.28); post_mat.metallic = 0.6; post_mat.roughness = 0.4
	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.88, 0.16, 0.14); red_mat.roughness = 0.45
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.96, 0.96, 0.95); white_mat.roughness = 0.45
	var amber_mat := StandardMaterial3D.new()
	amber_mat.albedo_color = Color(0.95, 0.72, 0.12)
	amber_mat.emission_enabled = true
	amber_mat.emission = Color(0.95, 0.68, 0.10)
	amber_mat.emission_energy_multiplier = 0.8

	for nid: int in node_built_edges.keys():
		var e_list: Array = node_built_edges[nid]
		if e_list.size() < 2:
			continue
		var is_turnout := (e_list.size() >= 3)
		var j_pos2: Vector2 = graph.nodes[nid]["pos"]
		var j_pos3 := Vector3(j_pos2.x, 0.0, j_pos2.y)

		# Check if a 2-edge node is a sharp corner (dot > -0.68 means turn >= ~47 deg)
		var is_sharp_corner := false
		if e_list.size() == 2:
			var p0 := _edge_trim_point_near_node(graph, int(e_list[0]), nid, 8.0)
			var p1 := _edge_trim_point_near_node(graph, int(e_list[1]), nid, 8.0)
			var v0 := (p0 - j_pos3).normalized()
			var v1 := (p1 - j_pos3).normalized()
			if v0.dot(v1) > -0.68:
				is_sharp_corner = true

		if not is_turnout and not is_sharp_corner:
			continue

		# Place illuminated ground switch-box indicator beside every 3-way/4-way turnout, strictly clear of all rails!
		if is_turnout:
			var sw_pos := Vector3.ZERO
			var sw_ok := false
			for r_sw: float in [4.2, 5.6, 7.0]:
				for ai in range(8):
					var ang := (float(ai) + 0.5) * (TAU / 8.0)
					var cand := j_pos3 + Vector3(cos(ang) * r_sw, 0.28, sin(ang) * r_sw)
					if track_clearance_dist(clear_idx, Vector2(cand.x, cand.z)) >= 1.95:
						sw_pos = cand
						sw_ok = true
						break
				if sw_ok:
					break
			if sw_ok:
				var sw_box := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.42, 0.46, 0.42)
				bm.material = amber_mat
				sw_box.mesh = bm
				sw_box.position = sw_pos
				sw_box.visibility_range_end = 180.0
				holder.add_child(sw_box)

		# Place approach speed limit sign strictly BESIDE the outer rail on each approaching built edge!
		for raw_eid in e_list:
			var eid := int(raw_eid)
			var geom: Dictionary = edge_geoms.get(eid, {})
			if geom.is_empty():
				continue
			var curve: Curve3D = geom["curve"]
			var clen := float(geom["clen"])
			var s_lo := float(geom["s_start"])
			var s_hi := float(geom["s_end"])
			if s_hi - s_lo < 6.0 or clen < 20.0:
				continue
			var ed: Dictionary = graph.edges[eid]
			var from_a := (int(ed["a"]) == nid)
			var s_sign := clampf(maxf(s_lo + 2.5, 11.5), s_lo + 1.0, s_hi - 1.0) if from_a else clampf(minf(s_hi - 2.5, clen - 11.5), s_lo + 1.0, s_hi - 1.0)
			var tf_s := sample_track_frame(curve, s_sign, clen, false)
			var pos_s := tf_s.origin
			# Direction of a tram approaching junction `nid` along `eid`
			var fwd_toward_j := (tf_s.basis.z if from_a else -tf_s.basis.z).normalized()
			var right_v := fwd_toward_j.cross(Vector3.UP).normalized()
			var sep_here := geom_sep_at(geom, s_sign) if bool(geom["is_double"]) else 0.0

			# Place outside the outer rail curb (sep + 2.05m), stepping further outward if a curve/cross-track is near
			var sign_pos := Vector3.ZERO
			var sign_ok := false
			var lat_candidates: Array[float] = [
				sep_here + 2.05,
				sep_here + 2.45,
				sep_here + 2.95,
				sep_here + 3.45,
				-(sep_here + 2.05),
				-(sep_here + 2.55),
			]
			for lat: float in lat_candidates:
				var cand := pos_s + right_v * lat
				if track_clearance_dist(clear_idx, Vector2(cand.x, cand.z)) < 1.95:
					continue
				# Also avoid planting a post inside a station platform
				var hits_stn := false
				for st_d: Dictionary in st_positions:
					var st_p: Vector3 = st_d["pos"]
					var st_half := float(st_d.get("platform_len", 27.0)) * 0.5 + 1.5
					if cand.distance_to(st_p) < st_half:
						var st_fw := (st_d["fwd"] as Vector3).normalized()
						var rel := cand - st_p
						var along := absf(rel.dot(st_fw))
						var across := absf(rel.dot(st_fw.cross(Vector3.UP).normalized()))
						if along < st_half and across < 5.2:
							hits_stn = true
							break
				if hits_stn:
					continue
				sign_pos = cand
				sign_ok = true
				break
			if not sign_ok:
				continue

			var sign_root := Node3D.new()
			sign_root.transform = Transform3D(
				Basis(right_v, Vector3.UP, -fwd_toward_j),
				sign_pos
			)
			holder.add_child(sign_root)

			var post_mi := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 0.032; pcyl.bottom_radius = 0.038; pcyl.height = 2.45; pcyl.radial_segments = 6
			pcyl.material = post_mat
			post_mi.mesh = pcyl
			post_mi.position = Vector3(0.0, 1.22, 0.0)
			post_mi.visibility_range_end = 160.0
			sign_root.add_child(post_mi)

			var ring_mi := MeshInstance3D.new()
			var rcyl := CylinderMesh.new()
			rcyl.top_radius = 0.34; rcyl.bottom_radius = 0.34; rcyl.height = 0.04; rcyl.radial_segments = 14
			rcyl.material = red_mat
			ring_mi.mesh = rcyl
			ring_mi.position = Vector3(0.0, 2.38, 0.0)
			ring_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			ring_mi.visibility_range_end = 160.0
			sign_root.add_child(ring_mi)

			var disc_mi := MeshInstance3D.new()
			var dcyl := CylinderMesh.new()
			dcyl.top_radius = 0.26; dcyl.bottom_radius = 0.26; dcyl.height = 0.05; dcyl.radial_segments = 14
			dcyl.material = white_mat
			disc_mi.mesh = dcyl
			disc_mi.position = Vector3(0.0, 2.38, 0.0)
			disc_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			disc_mi.visibility_range_end = 160.0
			sign_root.add_child(disc_mi)

			var spd_lbl := Label3D.new()
			spd_lbl.text = "18/30" if is_turnout else "20"
			if cjk_font != null:
				spd_lbl.font = cjk_font
			spd_lbl.font_size = 44 if is_turnout else 62
			spd_lbl.pixel_size = 0.0038
			spd_lbl.modulate = Color(0.08, 0.09, 0.11)
			spd_lbl.outline_size = 4
			spd_lbl.outline_modulate = Color(0.95, 0.95, 0.95)
			spd_lbl.position = Vector3(0.0, 2.38, 0.032)
			spd_lbl.visibility_range_end = 145.0
			sign_root.add_child(spd_lbl)


# Turf strip in every gap between neighbouring tracks that is narrow enough to be one grassed bed
static func _emit_between_track_turf(st: SurfaceTool, f0: Transform3D, f1: Transform3D, s0: float, s1: float,
		offs0: Array[float], offs1: Array[float], trk_hw: float, y: float) -> void:
	for k in range(offs0.size() - 1):
		var g0 := offs0[k + 1] - offs0[k]
		var g1 := offs1[k + 1] - offs1[k]
		if g0 <= trk_hw * 2.0 or g0 >= 4.4 or g1 <= trk_hw * 2.0 or g1 >= 4.4:
			continue
		var c0 := f0; c0.origin += f0.basis.x * ((offs0[k] + offs0[k + 1]) * 0.5)
		var c1 := f1; c1.origin += f1.basis.x * ((offs1[k] + offs1[k + 1]) * 0.5)
		_emit_turf_quad_uv_var(st, c0, c1, s0, s1, maxf(0.05, g0 * 0.5 - trk_hw), maxf(0.05, g1 * 0.5 - trk_hw), y, 0.35)


static func _emit_turf_quad_uv(
	grass_st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	s0: float,
	s1: float,
	half_w: float,
	y_h: float,
	uv_hw: float
) -> void:
	var v00 := f0 * Vector3(-half_w, y_h, 0.0)
	var v01 := f0 * Vector3(half_w, y_h, 0.0)
	var v11 := f1 * Vector3(half_w, y_h, 0.0)
	var v10 := f1 * Vector3(-half_w, y_h, 0.0)
	var up_n := f0.basis.y
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s1)); grass_st.add_vertex(v11)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s0)); grass_st.add_vertex(v01)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s1)); grass_st.add_vertex(v10)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s1)); grass_st.add_vertex(v11)


static func _emit_turf_quad_uv_var(
	grass_st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	s0: float,
	s1: float,
	hw0: float,
	hw1: float,
	y_h: float,
	uv_hw: float
) -> void:
	var v00 := f0 * Vector3(-hw0, y_h, 0.0)
	var v01 := f0 * Vector3(hw0, y_h, 0.0)
	var v11 := f1 * Vector3(hw1, y_h, 0.0)
	var v10 := f1 * Vector3(-hw1, y_h, 0.0)
	var up_n := f0.basis.y
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s1)); grass_st.add_vertex(v11)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s0)); grass_st.add_vertex(v01)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-uv_hw, s1)); grass_st.add_vertex(v10)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(uv_hw, s1)); grass_st.add_vertex(v11)


static func _emit_turf_quad(
	grass_st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	s0: float,
	s1: float,
	half_w: float,
	y_h: float
) -> void:
	var v00 := f0 * Vector3(-half_w, y_h, 0.0)
	var v01 := f0 * Vector3(half_w, y_h, 0.0)
	var v11 := f1 * Vector3(half_w, y_h, 0.0)
	var v10 := f1 * Vector3(-half_w, y_h, 0.0)
	var up_n := f0.basis.y
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-half_w, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(half_w, s1)); grass_st.add_vertex(v11)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(half_w, s0)); grass_st.add_vertex(v01)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-half_w, s0)); grass_st.add_vertex(v00)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(-half_w, s1)); grass_st.add_vertex(v10)
	grass_st.set_normal(up_n); grass_st.set_uv(Vector2(half_w, s1)); grass_st.add_vertex(v11)


static func _extrude_open_profile(
	st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	prof: Array[Vector2]
) -> void:
	_extrude_open_profile_2(st, f0, f1, prof, prof)


static func _extrude_open_profile_2(
	st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	prof0: Array[Vector2],
	prof1: Array[Vector2]
) -> void:
	for j in range(prof0.size() - 1):
		var a0 := prof0[j]
		var b0 := prof0[j + 1]
		var a1 := prof1[j]
		var b1 := prof1[j + 1]
		var v00 := f0 * Vector3(a0.x, a0.y, 0.0)
		var v01 := f0 * Vector3(b0.x, b0.y, 0.0)
		var v11 := f1 * Vector3(b1.x, b1.y, 0.0)
		var v10 := f1 * Vector3(a1.x, a1.y, 0.0)
		var edge2 := b0 - a0
		var local_nrm := Vector3(-edge2.y, edge2.x, 0.0).normalized()
		if local_nrm.y < 0.0 and absf(a0.y - b0.y) < 0.02:
			local_nrm = -local_nrm
		var nrm := (f0.basis * local_nrm).normalized()
		for v: Vector3 in [v00, v11, v01, v00, v10, v11]:
			st.set_normal(nrm)
			st.add_vertex(v)


static func _extrude_closed_profile(
	st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	prof: Array[Vector2]
) -> void:
	var m := prof.size()
	for j in range(m):
		var a := prof[j]
		var b := prof[(j + 1) % m]
		var v00 := f0 * Vector3(a.x, a.y, 0.0)
		var v01 := f0 * Vector3(b.x, b.y, 0.0)
		var v11 := f1 * Vector3(b.x, b.y, 0.0)
		var v10 := f1 * Vector3(a.x, a.y, 0.0)
		var edge2 := b - a
		var local_nrm := Vector3(-edge2.y, edge2.x, 0.0).normalized()
		var nrm := (f0.basis * local_nrm).normalized()
		for v: Vector3 in [v00, v11, v01, v00, v10, v11]:
			st.set_normal(nrm)
			st.add_vertex(v)



# ---------------------------------------------------------------------------------------------
# Buffer stops (车挡) at every rail dead end: hydraulic buffer beam with red/white chevrons on a braced
# steel frame, red tail lamp and a round red "no entry" board. Hitting one above walking pace derails.
# ---------------------------------------------------------------------------------------------
static func _build_buffer_stops(parent: Node3D, graph: NetworkGraph, lights: Array[OmniLight3D]) -> void:
	var holder := Node3D.new()
	holder.name = "BufferStops"
	parent.add_child(holder)
	var mats := _buffer_mats()
	for eid: int in graph.built_tracks.keys():
		for at_b: bool in [false, true]:
			var info := graph.buffer_stop_at_edge_end(eid, at_b)
			if info.is_empty():
				continue
			var g := edge_track_geom(graph, eid)
			var s_rail := float(info["s_rail_end"])
			var inward := -1.0 if at_b else 1.0
			var tf := sample_track_frame(g["curve"], s_rail + inward * 0.75, float(g["clen"]), false)
			var face := (-tf.basis.z * inward).normalized() # direction an approaching tram travels
			var lanes: Array[float] = [0.0]
			if bool(g["is_double"]):
				var sp := geom_sep_at(g, s_rail)
				lanes = [-sp, sp]
			var y0 := rail_top_for_style(int(graph.built_tracks[eid]))
			var mono := is_monorail_style(int(graph.built_tracks[eid]))
			if mono:
				y0 = MONORAIL_BEAM_TOP - EMBED_RAIL_TOP
			for lat: float in lanes:
				var pos := tf.origin + tf.basis.x * lat + Vector3.UP * y0
				var root := Node3D.new()
				root.name = "BufferStop_%d_%s" % [eid, "b" if at_b else "a"]
				# Local -Z points back toward the approaching tram
				root.transform = Transform3D(Basis.looking_at(-face, Vector3.UP), pos)
				holder.add_child(root)
				if mono:
					_build_monorail_bumper(root, mats, lights)
				else:
					_build_one_buffer(root, mats, lights)


static var _buffer_mat_cache: Dictionary = {}


static func _buffer_mats() -> Dictionary:
	if not _buffer_mat_cache.is_empty():
		return _buffer_mat_cache
	var m := {}
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.20, 0.21, 0.22)
	steel.metallic = 0.7
	steel.roughness = 0.45
	m["steel"] = steel
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.78, 0.79, 0.80)
	chrome.metallic = 0.9
	chrome.roughness = 0.2
	m["chrome"] = chrome
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.92, 0.72, 0.08)
	yellow.roughness = 0.5
	m["yellow"] = yellow
	# Red/white chevron stripes for the buffer beam
	var img := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(128):
			var band := int(floor(float(x + y) / 16.0)) % 2
			img.set_pixel(x, y, Color(0.86, 0.08, 0.08) if band == 0 else Color(0.96, 0.96, 0.94))
	var stripe := StandardMaterial3D.new()
	stripe.albedo_texture = ImageTexture.create_from_image(img)
	stripe.roughness = 0.45
	m["stripe"] = stripe
	# Round red "no entry / stop" board with a white bar
	var simg := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var d := Vector2(x - 63.5, y - 63.5).length()
			var c := Color(0, 0, 0, 0)
			if d < 63.0:
				c = Color(0.95, 0.95, 0.95)
			if d < 58.0:
				c = Color(0.82, 0.06, 0.06)
			if d < 58.0 and absf(y - 63.5) < 11.0 and absf(x - 63.5) < 40.0:
				c = Color(0.98, 0.98, 0.98)
			simg.set_pixel(x, y, c)
	var sign := StandardMaterial3D.new()
	sign.albedo_texture = ImageTexture.create_from_image(simg)
	sign.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sign.alpha_scissor_threshold = 0.5
	sign.roughness = 0.4
	sign.cull_mode = BaseMaterial3D.CULL_DISABLED
	sign.emission_enabled = true
	sign.emission_texture = sign.albedo_texture
	sign.emission_energy_multiplier = 0.25
	m["sign"] = sign
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.9, 0.05, 0.05)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.1, 0.08)
	lamp.emission_energy_multiplier = 2.2
	m["lamp"] = lamp
	_buffer_mat_cache = m
	return m


static func _bbox(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


static func _bcyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


# Local frame: origin on the track centreline at rail-top height, -Z faces the approaching tram.
static func _build_one_buffer(root: Node3D, mats: Dictionary, lights: Array[OmniLight3D]) -> void:
	var g := RAIL_HALF_GAUGE
	# Rail-clamped base runners on each rail + cross ties
	for sx: float in [-g, g]:
		_bbox(root, Vector3(0.16, 0.12, 2.2), Vector3(sx, 0.06, 0.55), mats["steel"])
	_bbox(root, Vector3(2.0, 0.10, 0.18), Vector3(0.0, 0.08, 1.55), mats["steel"])
	# Vertical posts + diagonal struts back to the runners
	for sx: float in [-g, g]:
		_bbox(root, Vector3(0.18, 1.0, 0.18), Vector3(sx, 0.55, -0.15), mats["steel"])
		_bbox(root, Vector3(0.14, 1.35, 0.14), Vector3(sx, 0.55, 0.55), mats["steel"], Vector3(-42.0, 0.0, 0.0))
	# Buffer beam with red/white chevrons at coupler height + two hydraulic buffer heads
	_bbox(root, Vector3(2.2, 0.42, 0.26), Vector3(0.0, 0.88, -0.28), mats["stripe"])
	for sx: float in [-0.62, 0.62]:
		_bcyl(root, 0.10, 0.34, Vector3(sx, 0.88, -0.56), mats["chrome"], Vector3(90.0, 0.0, 0.0))
		_bcyl(root, 0.17, 0.06, Vector3(sx, 0.88, -0.75), mats["yellow"], Vector3(90.0, 0.0, 0.0))
	# Red tail lamp on top and the round red stop board above it
	_bbox(root, Vector3(0.08, 1.2, 0.08), Vector3(0.0, 1.66, -0.2), mats["steel"])
	_bcyl(root, 0.09, 0.08, Vector3(0.0, 1.18, -0.44), mats["lamp"], Vector3(90.0, 0.0, 0.0))
	var sign := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	sign.mesh = q
	sign.material_override = mats["sign"]
	sign.position = Vector3(0.0, 2.25, -0.26)
	sign.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	root.add_child(sign)
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.15, 0.1)
	ol.light_energy = 0.0
	ol.visible = false
	ol.omni_range = 4.0
	ol.position = Vector3(0.0, 1.2, -0.7)
	root.add_child(ol)
	lights.append(ol)



# Monorail end-of-guideway bumper: concrete end block on the beam with a hydraulic buffer, chevron board,
# red lamp and the round "no entry" board (local -Z faces the approaching train; origin at beam top).
static func _build_monorail_bumper(root: Node3D, mats: Dictionary, lights: Array[OmniLight3D]) -> void:
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.70, 0.69, 0.66)
	conc.roughness = 0.85
	_bbox(root, Vector3(1.3, 2.4, 1.6), Vector3(0, -0.2, 0.8), conc)
	_bbox(root, Vector3(1.6, 0.9, 0.24), Vector3(0, 0.75, -0.1), mats["stripe"])
	_bcyl(root, 0.12, 0.4, Vector3(0, 0.75, -0.42), mats["chrome"], Vector3(90, 0, 0))
	_bcyl(root, 0.2, 0.06, Vector3(0, 0.75, -0.64), mats["yellow"], Vector3(90, 0, 0))
	_bcyl(root, 0.09, 0.08, Vector3(0, 1.35, -0.14), mats["lamp"], Vector3(90, 0, 0))
	_bbox(root, Vector3(0.08, 1.4, 0.08), Vector3(0, 1.9, 0.2), mats["steel"])
	var sign := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	sign.mesh = q
	sign.material_override = mats["sign"]
	sign.position = Vector3(0, 2.6, 0.12)
	sign.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(sign)
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.15, 0.1)
	ol.light_energy = 0.0
	ol.visible = false
	ol.omni_range = 4.0
	ol.position = Vector3(0, 1.3, -0.7)
	root.add_child(ol)
	lights.append(ol)


# ---------------------------------------------------------------------------------------------
# Monorail guideways: straddle beams (0.9m wide, 1.5m deep, top 7.1m) on T-piers in the street median,
# curved beam connectors at junctions and beam switches for crossovers. Shares geometry with the route
# compiler (edge_track_geom / junction_connector_curve), so trains always ride exactly on the beams.
# ---------------------------------------------------------------------------------------------
const MONO_BEAM_W := 0.9
const MONO_BEAM_D := 1.5


const MonorailSwitchScript := preload("res://scripts/monorail_switch.gd")


# Street-tram crossovers get the same interlocking as monorail switches: a points state plus four ground-mast
# signals (each track, each end) 10 m before the crossover. The rails themselves are built with the track.
static func _build_tram_switches(parent: Node3D, graph: NetworkGraph) -> void:
	var lst: Array = graph.get_meta("monorail_switches", [])
	for eid: int in graph.crossovers.keys():
		if int(graph.crossovers[eid]) <= NetworkGraph.CrossoverType.NONE or not graph.built_tracks.has(eid):
			continue
		if is_monorail_style(int(graph.built_tracks[eid])):
			continue
		var g := edge_track_geom(graph, eid)
		var xo := edge_crossover_span(graph, eid, g)
		if xo.is_empty():
			continue
		var c: Curve3D = g["curve"]
		var clen := float(g["clen"])
		var q0 := float(xo["s_mid"]) - float(xo["x_half"])
		var q1 := float(xo["s_mid"]) + float(xo["x_half"])
		var frames_sw: Array[Transform3D] = []
		var seps_sw := PackedFloat32Array()
		for i in range(MonorailSwitchScript.SEGMENTS + 1):
			var su := lerpf(q0, q1, float(i) / float(MonorailSwitchScript.SEGMENTS))
			frames_sw.append(sample_track_frame(c, su, clen, false))
			seps_sw.append(geom_sep_at(g, su))
		var sig_frames: Array[Transform3D] = []
		var sig_seps := PackedFloat32Array()
		for ss: float in [maxf(float(g["s_start"]) + 0.5, q0 - 10.0), minf(float(g["s_end"]) - 0.5, q1 + 10.0)]:
			sig_frames.append(sample_track_frame(c, ss, clen, false))
			sig_seps.append(geom_sep_at(g, ss))
		var sw: Node3D = MonorailSwitchScript.new()
		sw.name = "TramSwitch_%d" % eid
		sw.set("signals_only", true)
		sw.set("system", 0)
		sw.set("throw_speed", 0.5) # tram points throw in ~2 s
		sw.set("top", rail_top_for_style(int(graph.built_tracks[eid])))
		sw.set("half_w", 1.6) # masts stand clear of the tram body
		sw.set("group", [sw])
		parent.add_child(sw)
		sw.call("setup", frames_sw, seps_sw, sig_frames, sig_seps, null, null)
		lst.append(sw)
	graph.set_meta("monorail_switches", lst)


static func _build_monorail_guideways(parent: Node3D, graph: NetworkGraph) -> void:
	graph.set_meta("monorail_switches", [])
	var beam_st := SurfaceTool.new()
	beam_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_st := SurfaceTool.new()
	rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pier_st := SurfaceTool.new()
	pier_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var switch_nodes: Array = []
	var switch_setup: Array = []
	var top := MONORAIL_BEAM_TOP - EMBED_RAIL_TOP
	var bot := top - MONO_BEAM_D
	var hw := MONO_BEAM_W * 0.5
	var any := false
	var geoms := {}
	var placed_piers: Array[Vector2] = []
	for eid: int in graph.built_tracks.keys():
		if not is_monorail_style(int(graph.built_tracks[eid])):
			continue
		var g := edge_track_geom(graph, eid)
		if g.is_empty():
			continue
		geoms[eid] = g
		any = true
		var c: Curve3D = g["curve"]
		var clen := float(g["clen"])
		var s0 := float(g["s_start"])
		var s1 := float(g["s_end"])
		var n := maxi(2, int(ceil((s1 - s0) / 1.5)))
		var lanes: Array[float] = [0.0]
		if bool(g["is_double"]):
			lanes = [-1.0, 1.0]
		var xo := edge_crossover_span(graph, eid, g)
		var parts := mono_switch_parts(graph, eid, xo)
		var gap0 := 1e9
		var gap1 := -1e9
		if not xo.is_empty():
			gap0 = float(xo["s_mid"]) - float(xo["x_half"])
			gap1 = float(xo["s_mid"]) + float(xo["x_half"])
		# Break the beam exactly at the switch span ends so the moving beams fit the gaps
		var cuts: Array[float] = []
		for k in range(n + 1):
			cuts.append(lerpf(s0, s1, float(k) / float(n)))
		for pt: Dictionary in parts:
			for sc: float in [float(pt["s_mid"]) - float(pt["x_half"]), float(pt["s_mid"]), float(pt["s_mid"]) + float(pt["x_half"])]:
				cuts.append(sc)
		cuts.sort()
		for k in range(cuts.size() - 1):
			var sa := cuts[k]
			var sb := cuts[k + 1]
			if sb - sa < 0.01:
				continue
			var fa := sample_track_frame(c, sa, clen, false)
			var fb := sample_track_frame(c, sb, clen, false)
			for ln: float in lanes:
				var movable := false
				for pt: Dictionary in parts:
					var p0 := float(pt["s_mid"]) - float(pt["x_half"])
					var pm := float(pt["s_mid"])
					var p1 := float(pt["s_mid"]) + float(pt["x_half"])
					var hand := float(pt["hand"])
					if ln * hand < 0.0 and sa >= p0 - 0.01 and sb <= pm + 0.01:
						movable = true # movable half-beam A of this switch
					if ln * hand > 0.0 and sa >= pm - 0.01 and sb <= p1 + 0.01:
						movable = true # movable half-beam B of this switch
				if movable:
					continue
				var la := ln * geom_sep_at(g, sa)
				var lb := ln * geom_sep_at(g, sb)
				_mono_beam_segment(beam_st, rail_st, fa, fb, la, lb, top, bot, hw)
		# T-piers every ~28m in the median — strictly under the actual beam(s) and CLEAR of intersections & crosswalks!
		var ps := s0 + 9.0
		while ps < s1 - 5.5:
			if xo.is_empty() or ps < gap0 - 4.5 or ps > gap1 + 4.5:
				for shift_s: float in [0.0, 4.5, -4.5, 9.0, -9.0]:
					var cand_s := ps + shift_s
					if cand_s < s0 + 4.5 or cand_s > s1 - 4.5:
						continue
					if not xo.is_empty() and cand_s >= gap0 - 4.5 and cand_s <= gap1 + 4.5:
						continue
					var pf := sample_track_frame(c, cand_s, clen, false)
					var p2 := Vector2(pf.origin.x, pf.origin.z)
					var fw2 := Vector2(-pf.basis.z.x, -pf.basis.z.z).normalized()
					if _is_mono_pier_clear(graph, p2, eid, fw2, placed_piers, 13.0):
						var sep := geom_sep_at(g, cand_s) if bool(g["is_double"]) else 0.0
						_mono_pier(pier_st, pf, sep, bot)
						placed_piers.append(p2)
						break
			ps += 28.0
		# Monorail crossover = an articulated moving-beam switch: the anchored guideway's beam over this span
		# flexes across to the other guideway when a train needs to cross (driven by TransitSim).
		var group: Array = []
		var cap_s: Array[float] = []
		for pi in range(parts.size()):
			var pt: Dictionary = parts[pi]
			var q0 := float(pt["s_mid"]) - float(pt["x_half"])
			var q1 := float(pt["s_mid"]) + float(pt["x_half"])
			var frames_sw: Array[Transform3D] = []
			var seps_sw := PackedFloat32Array()
			for i in range(MonorailSwitchScript.SEGMENTS + 1):
				var su := lerpf(q0, q1, float(i) / float(MonorailSwitchScript.SEGMENTS))
				frames_sw.append(sample_track_frame(c, su, clen, false))
				seps_sw.append(geom_sep_at(g, su))
			var sw: Node3D = MonorailSwitchScript.new()
			sw.name = "MonorailSwitch_%d_%d" % [eid, pi]
			sw.set("top", top)
			sw.set("bot", bot)
			sw.set("half_w", hw)
			sw.set("hand", float(pt["hand"]))
			switch_nodes.append(sw)
			group.append(sw)
			var sig_frames: Array[Transform3D] = []
			var sig_seps := PackedFloat32Array()
			for ss: float in [maxf(s0 + 0.5, q0 - 10.0), minf(s1 - 0.5, q1 + 10.0)]:
				sig_frames.append(sample_track_frame(c, ss, clen, false))
				sig_seps.append(geom_sep_at(g, ss))
			switch_setup.append([sw, frames_sw, seps_sw, sig_frames, sig_seps])
			for se: float in [q0, float(pt["s_mid"]), q1]:
				var dup := false
				for cs: float in cap_s:
					if absf(cs - se) < 1.0:
						dup = true
				if not dup:
					cap_s.append(se)
		# The switches of one crossover are interlocked as a unit (a train takes them all or none)
		for sw_g: Node3D in group:
			sw_g.set("group", group)
		if not parts.is_empty():
			for se: float in cap_s:
				var pf := sample_track_frame(c, se, clen, false)
				var p2 := Vector2(pf.origin.x, pf.origin.z)
				var fw2 := Vector2(-pf.basis.z.x, -pf.basis.z.z).normalized()
				if _is_mono_pier_clear(graph, p2, eid, fw2, placed_piers, 6.0):
					var sep_sw := geom_sep_at(g, se) if bool(g["is_double"]) else 0.0
					_mono_pier(pier_st, pf, sep_sw, bot)
					var mb := pf
					mb.origin += Vector3.UP * (bot - 0.75)
					_mono_box(pier_st, mb, Vector3(2.0 * sep_sw + 1.2, 0.5, 2.2))
					placed_piers.append(p2)
	if not any:
		return
	# Junction connectors between monorail edges (same rule as the route compiler)
	for nid: int in graph.nodes.keys():
		var info := node_track_info(graph, nid, 1)
		var el: Array = info["edges"]
		if el.size() < 2 or (not bool(info["bare"]) and el.size() == 2):
			continue
		for ia in range(el.size()):
			for ib in range(ia + 1, el.size()):
				var ea := int(el[ia])
				var eb := int(el[ib])
				if not geoms.has(ea) or not geoms.has(eb):
					continue
				var ga: Dictionary = geoms[ea]
				var gb: Dictionary = geoms[eb]
				var ea_is_a := int(graph.edges[ea]["a"]) == nid
				var eb_is_a := int(graph.edges[eb]["a"]) == nid
				var s_a := float(ga["s_start"]) if ea_is_a else float(ga["s_end"])
				var s_b := float(gb["s_start"]) if eb_is_a else float(gb["s_end"])
				var tf_a := sample_track_frame(ga["curve"], s_a, float(ga["clen"]), false)
				var tf_b := sample_track_frame(gb["curve"], s_b, float(gb["clen"]), false)
				var out_a := (-tf_a.basis.z if ea_is_a else tf_a.basis.z).normalized()
				var out_b := (-tf_b.basis.z if eb_is_a else tf_b.basis.z).normalized()
				if out_a.dot(out_b) > 0.72 and el.size() > 2:
					continue
				var right_a := (tf_a.basis.x if ea_is_a else -tf_a.basis.x).normalized()
				var right_b := (tf_b.basis.x if eb_is_a else -tf_b.basis.x).normalized()
				var dbl_a := bool(ga["is_double"])
				var dbl_b := bool(gb["is_double"])
				var lanes: Array[float] = [0.0]
				if dbl_a or dbl_b:
					lanes = [-1.0, 1.0]
				for lane: float in lanes:
					var pa := tf_a.origin - right_a * (lane * geom_sep_at(ga, s_a) if dbl_a else 0.0)
					var pb := tf_b.origin + right_b * (lane * geom_sep_at(gb, s_b) if dbl_b else 0.0)
					var jc := junction_connector_curve(pa, -out_a, pb, out_b)
					if jc == null:
						continue
					var jl := jc.get_baked_length()
					var jn := maxi(2, int(ceil(jl / 1.2)))
					var prev_f := sample_track_frame(jc, 0.0, jl, false)
					for k in range(1, jn + 1):
						var f := sample_track_frame(jc, jl * float(k) / float(jn), jl, false)
						_mono_beam_segment(beam_st, rail_st, prev_f, f, 0.0, 0.0, top, bot, hw)
						prev_f = f
				# Do NOT drop a junction pier at s_a (it sits on the crosswalk/intersection with sep=0 between beams!)
				# Adjacent mid-block piers cleanly support the beam span across intersections.
	beam_st.generate_normals()
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.80, 0.79, 0.76)
	bm.roughness = 0.75
	var beam_mi := MeshInstance3D.new()
	beam_mi.name = "MonorailGuidewayBeams"
	beam_mi.mesh = beam_st.commit()
	beam_mi.material_override = bm
	parent.add_child(beam_mi)
	rail_st.generate_normals()
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.22, 0.23, 0.24)
	rm.metallic = 0.6
	rm.roughness = 0.4
	var rail_mi := MeshInstance3D.new()
	rail_mi.name = "MonorailPowerRails"
	rail_mi.mesh = rail_st.commit()
	rail_mi.material_override = rm
	parent.add_child(rail_mi)
	for item: Array in switch_setup:
		var sw_node: Node3D = item[0]
		parent.add_child(sw_node)
		sw_node.call("setup", item[1], item[2], item[3], item[4], bm, rm)
	graph.set_meta("monorail_switches", switch_nodes)
	pier_st.generate_normals()
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.74, 0.73, 0.70)
	pm.roughness = 0.85
	var pier_mi := MeshInstance3D.new()
	pier_mi.name = "MonorailPiers"
	pier_mi.mesh = pier_st.commit()
	pier_mi.material_override = pm
	parent.add_child(pier_mi)


static func _mono_beam_segment(beam_st: SurfaceTool, rail_st: SurfaceTool, fa: Transform3D, fb: Transform3D, la: float, lb: float, top: float, bot: float, hw: float) -> void:
	var ra := fa.basis.x.normalized()
	var rb := fb.basis.x.normalized()
	var ca := fa.origin + ra * la
	var cb := fb.origin + rb * lb
	var c := func(cc: Vector3, r: Vector3, x: float, y: float) -> Vector3: return cc + r * x + Vector3.UP * y
	var quads := [
		[c.call(ca, ra, -hw, top), c.call(cb, rb, -hw, top), c.call(cb, rb, hw, top), c.call(ca, ra, hw, top)],
		[c.call(ca, ra, hw, top), c.call(cb, rb, hw, top), c.call(cb, rb, hw, bot), c.call(ca, ra, hw, bot)],
		[c.call(ca, ra, -hw, bot), c.call(cb, rb, -hw, bot), c.call(cb, rb, -hw, top), c.call(ca, ra, -hw, top)],
		[c.call(ca, ra, hw, bot), c.call(cb, rb, hw, bot), c.call(cb, rb, -hw, bot), c.call(ca, ra, -hw, bot)],
	]
	for q: Array in quads:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			beam_st.add_vertex(q[idx])
	# Power / guide rails along both beam flanks
	for sd: float in [-1.0, 1.0]:
		var x := sd * (hw + 0.03)
		var q2 := [c.call(ca, ra, x, top - 0.25), c.call(cb, rb, x, top - 0.25), c.call(cb, rb, x, top - 0.45), c.call(ca, ra, x, top - 0.45)]
		for idx: int in ([0, 1, 2, 0, 2, 3] if sd > 0.0 else [0, 2, 1, 0, 3, 2]):
			rail_st.add_vertex(q2[idx])


static func _is_mono_pier_clear(
	graph: NetworkGraph,
	p2: Vector2,
	own_eid: int,
	beam_fwd_xz: Vector2,
	placed_piers: Array[Vector2],
	min_pier_gap: float
) -> bool:
	# 1. Never clump duplicate piers too close together
	for ep: Vector2 in placed_piers:
		if p2.distance_squared_to(ep) < min_pier_gap * min_pier_gap:
			return false

	# 2. Never place a pier inside ANY street intersection or on its crosswalk zebra stripes!
	for nid: int in graph.nodes.keys():
		var np: Vector2 = graph.nodes[nid]["pos"]
		var deg := (graph.adj.get(nid, []) as Array).size()
		if deg >= 3:
			var clr := _node_intersection_trim(graph, nid) + 6.0
			if p2.distance_squared_to(np) < clr * clr:
				return false
		elif deg == 2:
			var nbs: Array = graph.adj[nid]
			if _is_bare_junction_node(graph, nid, [int(nbs[0]["edge_id"]), int(nbs[1]["edge_id"])]):
				if p2.distance_squared_to(np) < 9.5 * 9.5:
					return false

	# 3. Never drop a pier onto a crossing / side street roadway or crosswalk!
	for other_eid: int in graph.edges.keys():
		if other_eid == own_eid:
			continue
		var oe: Dictionary = graph.edges[other_eid]
		var pts: Array = oe["pts"]
		var hw := float(oe.get("width", 12.0)) * 0.5
		var clr_d := hw + 4.8
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := b - a
			var slen := d.length()
			if slen < 0.2:
				continue
			var sdir := d / slen
			# Skip collinear continuation segments of the same street; strictly avoid cross streets!
			if absf(sdir.dot(beam_fwd_xz)) > 0.85:
				continue
			var q := Geometry2D.get_closest_point_to_segment(p2, a, b)
			if p2.distance_squared_to(q) < clr_d * clr_d:
				return false

	return true


static func _mono_pier(st: SurfaceTool, f: Transform3D, sep: float, bot: float) -> void:
	var r := f.basis.x.normalized()
	var fw := -f.basis.z.normalized()
	var o := f.origin
	var box := func(cx: float, cy: float, sx: float, sy: float, sz: float) -> void:
		var cc := o + r * cx + Vector3.UP * cy
		var hx := r * (sx * 0.5)
		var hy := Vector3.UP * (sy * 0.5)
		var hz := fw * (sz * 0.5)
		var v := [cc - hx - hy - hz, cc + hx - hy - hz, cc + hx + hy - hz, cc - hx + hy - hz, cc - hx - hy + hz, cc + hx - hy + hz, cc + hx + hy + hz, cc - hx + hy + hz]
		for fc: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7]]:
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(v[fc[idx]])
	box.call(0.0, bot * 0.5, 1.3, bot, 1.3)
	box.call(0.0, 0.25, 1.9, 0.5, 1.9)
	if sep > 0.1:
		box.call(0.0, bot - 0.35, sep * 2.0 + 1.6, 0.7, 1.4)
	else:
		box.call(0.0, bot - 0.3, 1.8, 0.6, 1.4)



static func _mono_box(st: SurfaceTool, f: Transform3D, sz: Vector3) -> void:
	var r := f.basis.x.normalized() * (sz.x * 0.5)
	var u := Vector3.UP * (sz.y * 0.5)
	var w := -f.basis.z.normalized() * (sz.z * 0.5)
	var o := f.origin
	var v := [o - r - u - w, o + r - u - w, o + r + u - w, o - r + u - w, o - r - u + w, o + r - u + w, o + r + u + w, o - r + u + w]
	for fc: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(v[fc[idx]])
