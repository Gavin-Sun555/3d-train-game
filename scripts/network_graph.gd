class_name NetworkGraph
extends RefCounted

const GRID_CELL_M := 75.0
const PROFILE_STEP_M := 2.0
const DOUBLE_TRACK_HALF_SEP := 1.65
const ISLAND_TRACK_HALF_SEP := 3.05
const TURNBACK_EXTEND_M := 12.0 # Terminal turnback point beyond the platform center (27m platforms)
const BUFFER_CLEAR_M := 2.4 # Dead-end tail tracks: usable track ends this far before the rail end (buffer stop)
const MAX_TAIL_TRACK_M := 90.0
const ROUTE_SAMPLE_STEP_M := 1.0
const TERMINAL_HOLD_MARGIN_M := 6.0 # Waiting trams stop this far before the terminal crossover
const ZONE_LABELS := ["正线", "缓弯", "弯道", "急弯", "直向道岔", "侧向道岔"]

enum TrackMode {
	SINGLE = 0,
	DOUBLE = 1,
	QUAD = 2, # 四轨：内侧两条快车线 + 外侧两条慢车线（独立路权）
}

# Four-track (express / local) corridor geometry, after the 2D game's design: the inner express pair runs
# like an ordinary double track (DOUBLE_TRACK_HALF_SEP) and stays straight through stations; the outer local
# pair sits one track spacing further out, flares outward around twin island platforms and merges into the
# express pair wherever the four-track section ends.
const QUAD_LOCAL_HALF_SEP := 4.95
const QUAD_ISLAND_LOCAL_SEP := 7.75 # local track at a twin-island stop: 1.65 + 2 x 3.05 (an island each side)
const QUAD_ISLAND_CENTER := 4.70 # island centre line between express (1.65) and flared local (7.75)
const QUAD_ISLAND_TAPER := 18.0 # local tracks ease out / back over this length beyond the platform
const QUAD_MERGE_RAMP := 36.0 # local tracks join the express tracks over this length at a section end

enum CrossoverType {
	NONE = 0,
	SINGLE = 1, # 单渡线
	DOUBLE = 2, # 交叉渡线 (剪刀渡线)
}

enum StationKind {
	SIDE_SINGLE = 0, # 单侧站台
	SIDE_DUAL = 1,   # 对称双侧站台
	ISLAND = 2,      # 中央岛式站台
}

# Graph geometry loaded from map json
var nodes: Dictionary = {} # node_id (int) -> {id, pos: Vector2, name: String}
var edges: Dictionary = {} # edge_id (int) -> {id, a: int, b: int, name: String, width: float, length: float, pts: Array[Vector2]}
var adj: Dictionary = {}   # node_id (int) -> Array[Dictionary] ({to: int, edge_id: int, length: float})
var _edge_grid: Dictionary = {} # Vector2i(cx, cz) -> Array[int] (edge_ids)

# Player-built permanent infrastructure & transit lines
var built_tracks: Dictionary = {}      # edge_id (int) -> bed_style (int)
var built_track_modes: Dictionary = {} # edge_id (int) -> TrackMode (int)
var crossovers: Dictionary = {}        # edge_id (int) -> CrossoverType (int)
var crossover_t: Dictionary = {}       # edge_id (int) -> float (normalized position 0..1 along edge)
var stations: Dictionary = {}          # station_id (int) -> {id, name, edge_id, t, side, pos: Vector3, fwd: Vector3}
var lines: Dictionary = {}             # line_id (int) -> {id, name, color: Color, model_key, trams_count, sections, station_ids: Array[int]}

func is_multi_track(eid: int) -> bool:
	return int(built_track_modes.get(eid, TrackMode.SINGLE)) >= TrackMode.DOUBLE


func is_quad(eid: int) -> bool:
	return int(built_track_modes.get(eid, TrackMode.SINGLE)) == TrackMode.QUAD


# Twin-island stop on a four-track edge (express and local trains of one direction share an island)
func is_quad_island(sid: int) -> bool:
	if not stations.has(sid):
		return false
	var st: Dictionary = stations[sid]
	return is_quad(int(st["edge_id"])) and int(st.get("side", 1)) == 0


var next_station_id := 1
var next_line_id := 1
var monorail_seeded := false
# Player road / land edits on top of the map, replayed in order on load (ids are stored so they never drift):
#   {op: "node", id, pos} | {op: "edge", id, a, b, pts, width, lf, lb, name, no_cars}
#   {op: "split", eid, t, nid, eid2} | {op: "remove", eid} | {op: "lanes", eid, lf, lb, width}
var road_edits: Array = []
var demolished_buildings: Dictionary = {} # map building index -> true
var _base_geo: Dictionary = {} # untouched map graph (nodes / edges / adj) the edits are applied to # the Seattle Center Monorail line has been offered once for this save

const LINE_PALETTE: Array[Color] = [
	Color(0.12, 0.54, 0.88),
	Color(0.16, 0.72, 0.46),
	Color(0.88, 0.28, 0.24),
	Color(0.92, 0.64, 0.14),
	Color(0.62, 0.34, 0.84),
	Color(0.14, 0.72, 0.76),
]


func load_from_map_data(map_data: Dictionary, use_starter: bool = true) -> void:
	nodes.clear()
	edges.clear()
	adj.clear()
	_edge_grid.clear()
	built_tracks.clear()
	built_track_modes.clear()
	crossovers.clear()
	crossover_t.clear()
	stations.clear()
	lines.clear()
	next_station_id = 1
	next_line_id = 1
	monorail_seeded = false

	for n_raw in map_data.get("graph_nodes", []):
		var nid := int(n_raw["id"])
		var p: Array = n_raw["pos"]
		nodes[nid] = {
			"id": nid,
			"pos": Vector2(float(p[0]), float(p[1])),
			"name": str(n_raw.get("name", "路口")),
		}
		adj[nid] = []

	for e_raw in map_data.get("graph_edges", []):
		var eid := int(e_raw["id"])
		var a := int(e_raw["a"])
		var b := int(e_raw["b"])
		var pts2: Array[Vector2] = []
		for rp in e_raw.get("pts", []):
			pts2.append(Vector2(float(rp[0]), float(rp[1])))
		var elen := float(e_raw.get("length", 20.0))
		edges[eid] = {
			"id": eid,
			"a": a,
			"b": b,
			"name": str(e_raw.get("name", "Street")),
			"width": float(e_raw.get("width", 12.0)),
			"lanes_f": int(e_raw.get("lanes_f", 1)), # motor lanes along a -> b
			"lanes_b": int(e_raw.get("lanes_b", 1)), # motor lanes along b -> a (0 / 0: one-way street)
			"length": elen,
			"pts": pts2,
		}
		if adj.has(a):
			adj[a].append({"to": b, "edge_id": eid, "length": elen})
		if adj.has(b):
			adj[b].append({"to": a, "edge_id": eid, "length": elen})
		_insert_edge_into_grid(eid, pts2)

	_base_geo = {"nodes": nodes.duplicate(true), "edges": edges.duplicate(true), "adj": adj.duplicate(true)}
	road_edits.clear()
	demolished_buildings.clear()

	if use_starter:
		var starter: Dictionary = map_data.get("starter_network", {})
		if not starter.is_empty():
			import_state(starter)


func clear_player_network() -> void:
	if not road_edits.is_empty():
		_restore_base_geometry()
	road_edits.clear()
	demolished_buildings.clear()
	built_tracks.clear()
	built_track_modes.clear()
	crossovers.clear()
	crossover_t.clear()
	stations.clear()
	lines.clear()
	next_station_id = 1
	next_line_id = 1


func export_state() -> Dictionary:
	var tr_arr: Array = []
	for eid: int in built_tracks.keys():
		var item := {
			"edge_id": eid,
			"bed_style": int(built_tracks[eid]),
			"track_mode": int(built_track_modes.get(eid, TrackMode.SINGLE)),
		}
		if crossovers.has(eid):
			item["crossover"] = int(crossovers[eid])
			item["crossover_t"] = float(crossover_t.get(eid, 0.5))
		tr_arr.append(item)

	var st_arr: Array = []
	for sid: int in stations.keys():
		var st: Dictionary = stations[sid]
		st_arr.append({
			"id": sid,
			"name": st["name"],
			"edge_id": st["edge_id"],
			"t": st["t"],
			"side": st["side"],
			"kind": int(st.get("kind", StationKind.SIDE_SINGLE)),
			"platform_len": float(st.get("platform_len", 27.0)),
		})

	var ln_arr: Array = []
	for lid: int in lines.keys():
		var ln: Dictionary = lines[lid]
		var col: Color = ln["color"]
		ln_arr.append({
			"id": lid,
			"name": ln["name"],
			"color": [col.r, col.g, col.b],
			"model_key": ln["model_key"],
			"trams_count": ln["trams_count"],
			"sections": ln["sections"],
			"station_ids": ln["station_ids"],
			"express": bool(ln.get("express", false)),
		})

	return {
		"tracks": tr_arr,
		"stations": st_arr,
		"lines": ln_arr,
		"monorail_seeded": monorail_seeded,
		"mono_two_way": true,
		"road_edits": road_edits.duplicate(true),
		"demolished_buildings": demolished_buildings.keys(),
	}


func import_state(state: Dictionary) -> void:
	clear_player_network()
	monorail_seeded = bool(state.get("monorail_seeded", false))
	# Roads / open-ground track first: tracks and stations refer to their edge ids
	for op in state.get("road_edits", []):
		if typeof(op) == TYPE_DICTIONARY:
			_record((op as Dictionary).duplicate(true))
	for bi in state.get("demolished_buildings", []):
		demolished_buildings[int(bi)] = true

	for t_item in state.get("tracks", []):
		var eid := int(t_item["edge_id"])
		var bst := int(t_item["bed_style"])
		var tmode := int(t_item.get("track_mode", TrackMode.SINGLE))
		var xover := int(t_item.get("crossover", CrossoverType.NONE))
		if edges.has(eid):
			built_tracks[eid] = bst
			built_track_modes[eid] = tmode
			if tmode == TrackMode.DOUBLE and xover > CrossoverType.NONE: # four-track sections take no crossovers
				crossovers[eid] = xover
				crossover_t[eid] = clampf(float(t_item.get("crossover_t", 0.5)), 0.05, 0.95)

	for s_item in state.get("stations", []):
		var eid := int(s_item["edge_id"])
		if not edges.has(eid) or not built_tracks.has(eid):
			continue
		var sid := int(s_item["id"])
		var t_val := clampf(float(s_item.get("t", 0.5)), 0.15, 0.85)
		var side := int(s_item.get("side", 1))
		var plat_len := clampf(float(s_item.get("platform_len", 27.0)), 20.0, 56.0)
		var skind_chk := StationKind.ISLAND if side == 0 else StationKind.SIDE_SINGLE
		# Loading: only drop a crossover that really runs into the platform (track alignment may shift lengths a little)
		if TrackBuilder.station_overlaps_crossover(self, eid, t_val, skind_chk, plat_len, 0.0):
			crossovers.erase(eid)
			crossover_t.erase(eid)
		var skind := int(s_item.get("kind", StationKind.ISLAND if side == 0 else StationKind.SIDE_SINGLE))
		var sample := sample_edge(eid, t_val)
		stations[sid] = {
			"id": sid,
			"name": _strip_auto_station_suffix(str(s_item.get("name", "电车站 %d" % sid))),
			"edge_id": eid,
			"t": t_val,
			"side": side,
			"kind": skind,
			"platform_len": plat_len,
			"pos": sample["pos"],
			"fwd": sample["fwd"],
		}
		next_station_id = maxi(next_station_id, sid + 1)

	for l_item in state.get("lines", []):
		var lid := int(l_item["id"])
		var sids: Array[int] = []
		for raw_sid in l_item.get("station_ids", []):
			var sid := int(raw_sid)
			if stations.has(sid):
				sids.append(sid)
		if sids.size() < 2:
			continue
		var c_arr: Array = l_item.get("color", [0.12, 0.54, 0.88])
		lines[lid] = {
			"id": lid,
			"name": str(l_item.get("name", "%d号线" % lid)),
			"color": Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2])),
			"model_key": str(l_item.get("model_key", "siemens-s700")),
			"trams_count": clampi(int(l_item.get("trams_count", 2)), 1, 8),
			"sections": clampi(int(l_item.get("sections", 3)), 1, 4),
			"station_ids": sids,
			"express": bool(l_item.get("express", false)),
		}
		next_line_id = maxi(next_line_id, lid + 1)

	# Older saves only had one-way monorail beam switches: upgrade them to two-way crossovers where they fit,
	# so a terminal can be entered on either platform track.
	if not bool(state.get("mono_two_way", false)):
		for eid: int in crossovers.keys():
			if int(crossovers[eid]) == CrossoverType.SINGLE and TrackBuilder.is_monorail_style(int(built_tracks.get(eid, -1))):
				set_crossover_on_edge(eid, CrossoverType.DOUBLE, float(crossover_t.get(eid, 0.5)))


func set_track_on_edge(edge_id: int, bed_style: int, track_mode: int = TrackMode.SINGLE) -> bool:
	if not edges.has(edge_id):
		return false
	built_tracks[edge_id] = bed_style
	built_track_modes[edge_id] = track_mode
	if track_mode != TrackMode.DOUBLE:
		crossovers.erase(edge_id) # single track has none; four-track turns back on its double-track ends
	return true


func has_station_on_edge(edge_id: int) -> bool:
	for sid: int in stations.keys():
		if int(stations[sid]["edge_id"]) == edge_id:
			return true
	return false


func set_crossover_on_edge(edge_id: int, xover_type: int, t_val: float = 0.5) -> bool:
	if not built_tracks.has(edge_id) or not edges.has(edge_id):
		return false
	if xover_type <= CrossoverType.NONE:
		crossovers.erase(edge_id)
		crossover_t.erase(edge_id)
		return true
	# Monorail DOUBLE = two-way crossover: two opposite-handed beam switches in series (no scissors on a guideway)
	var place := TrackBuilder.compute_crossover_placement(self, edge_id, t_val, xover_type)
	if not bool(place.get("valid", false)):
		return false
	crossovers[edge_id] = xover_type
	crossover_t[edge_id] = float(place["t_clamped"])
	return true


func remove_track_on_edge(edge_id: int) -> void:
	built_tracks.erase(edge_id)
	built_track_modes.erase(edge_id)
	crossovers.erase(edge_id)
	crossover_t.erase(edge_id)
	# Also remove any station sitting on this demolished edge
	var to_remove: Array[int] = []
	for sid: int in stations.keys():
		if int(stations[sid]["edge_id"]) == edge_id:
			to_remove.append(sid)
	for sid: int in to_remove:
		remove_station(sid)


func get_edge_track_half_sep(edge_id: int) -> float:
	var mode := int(built_track_modes.get(edge_id, TrackMode.SINGLE))
	if mode == TrackMode.SINGLE:
		return 0.0
	if mode == TrackMode.QUAD:
		return DOUBLE_TRACK_HALF_SEP # express pair; the local pair is laid outside it (TrackBuilder lsep)
	if TrackBuilder.is_monorail_style(int(built_tracks.get(edge_id, -1))):
		for sid_m: int in stations.keys():
			if int(stations[sid_m]["edge_id"]) == edge_id and int(stations[sid_m].get("side", 1)) == 0:
				return ISLAND_TRACK_HALF_SEP
		return TrackBuilder.MONORAIL_HALF_SEP
	for sid: int in stations.keys():
		var st: Dictionary = stations[sid]
		if int(st["edge_id"]) == edge_id and (int(st.get("kind", StationKind.SIDE_SINGLE)) == StationKind.ISLAND or int(st.get("side", 1)) == 0):
			return ISLAND_TRACK_HALF_SEP
	return DOUBLE_TRACK_HALF_SEP


# Rail dead end at one end of a built edge (that end's node has no other built track): returns
# {nid, s_rail_end, s_track_end} in edge-curve arc length, or {} if the track continues there.
func buffer_stop_at_edge_end(eid: int, at_b_end: bool) -> Dictionary:
	if not built_tracks.has(eid) or not edges.has(eid):
		return {}
	var nid := int(edges[eid]["b"]) if at_b_end else int(edges[eid]["a"])
	var sys := TrackBuilder.edge_system(self, eid)
	for nb: Dictionary in adj.get(nid, []):
		var oe := int(nb["edge_id"])
		if oe != eid and built_tracks.has(oe) and TrackBuilder.edge_system(self, oe) == sys:
			return {}
	var g := TrackBuilder.edge_track_geom(self, eid)
	if g.is_empty():
		return {}
	var s_rail := float(g["s_end"]) if at_b_end else float(g["s_start"])
	var inward := -1.0 if at_b_end else 1.0
	return {"nid": nid, "s_rail_end": s_rail, "s_track_end": s_rail + inward * BUFFER_CLEAR_M}


func rename_station(sid: int, new_name: String) -> bool:
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty() or not stations.has(sid):
		return false
	stations[sid]["name"] = trimmed
	return true


static func _strip_auto_station_suffix(raw_name: String) -> String:
	var out := raw_name.strip_edges()
	for suf: String in [
		"（中央岛式）", "(中央岛式)",
		"（马路东侧）", "(马路东侧)",
		"（马路西侧）", "(马路西侧)",
		"（马路南侧）", "(马路南侧)",
		"（马路北侧）", "(马路北侧)",
	]:
		if out.ends_with(suf):
			out = out.substr(0, out.length() - suf.length()).strip_edges()
	return out


func add_station_on_edge(
	edge_id: int,
	t_val: float,
	side: int = 1,
	custom_name: String = "",
	kind: int = StationKind.SIDE_SINGLE,
	platform_len: float = 27.0
) -> int:
	if not built_tracks.has(edge_id) or not edges.has(edge_id):
		return -1
	var plat_len := clampf(platform_len, 20.0, 56.0)
	var t_clamped := clampf(t_val, 0.15, 0.85)
	var is_dbl := is_multi_track(edge_id)
	var eff_kind := kind if is_dbl else StationKind.SIDE_SINGLE
	# Never allow building a station overlapping an existing crossover/switch!
	if TrackBuilder.station_overlaps_crossover(self, edge_id, t_clamped, eff_kind, plat_len):
		return -1
	var sample := sample_edge(edge_id, t_clamped)
	var eff_side := 0 if eff_kind == StationKind.ISLAND else (1 if side >= 0 else -1)

	# Prevent overlapping stations (on Double Track side platforms, allow building on BOTH sides!)
	for sid: int in stations.keys():
		var st: Dictionary = stations[sid]
		if eff_kind != StationKind.ISLAND and is_dbl and int(st["edge_id"]) == edge_id and int(st["side"]) != 0 and int(st["side"]) != eff_side:
			continue
		var min_sep := (plat_len + float(st.get("platform_len", 27.0))) * 0.5 - 1.0
		if (st["pos"] as Vector3).distance_to(sample["pos"]) < min_sep:
			return sid

	var sid := next_station_id
	next_station_id += 1

	var ed: Dictionary = edges[edge_id]
	var st_name := custom_name
	if st_name.is_empty():
		var near_nid: int = int(ed["a"]) if t_clamped < 0.5 else int(ed["b"])
		var j_name: String = str(nodes[near_nid]["name"])
		if j_name != "" and not j_name.begins_with("路口"):
			st_name = j_name + " 站"
		else:
			st_name = "%s #%d站" % [str(ed["name"]), sid]

	stations[sid] = {
		"id": sid,
		"name": st_name,
		"edge_id": edge_id,
		"t": t_clamped,
		"side": eff_side,
		"kind": eff_kind,
		"platform_len": plat_len,
		"pos": sample["pos"],
		"fwd": sample["fwd"],
	}
	return sid


func remove_station(station_id: int) -> void:
	stations.erase(station_id)
	var dead_lines: Array[int] = []
	for lid: int in lines.keys():
		var sids: Array = lines[lid]["station_ids"]
		sids.erase(station_id)
		if sids.size() < 2:
			dead_lines.append(lid)
	for lid: int in dead_lines:
		lines.erase(lid)


func create_line(
	station_ids: Array[int],
	model_key: String,
	trams_count: int,
	sections: int,
	custom_name: String = "",
	express: bool = false
) -> int:
	if station_ids.size() < 2:
		return -1
	# Validate connectivity along built tracks between every consecutive station pair!
	for i in range(station_ids.size() - 1):
		var seg := find_track_path_between_stations(station_ids[i], station_ids[i + 1])
		if seg.is_empty():
			return -1

	var lid := next_line_id
	next_line_id += 1
	var col: Color = LINE_PALETTE[(lid - 1) % LINE_PALETTE.size()]
	var lname := custom_name if not custom_name.is_empty() else ("%d号线" % lid)

	lines[lid] = {
		"id": lid,
		"name": lname,
		"color": col,
		"model_key": model_key,
		"trams_count": clampi(trams_count, 1, 8),
		"sections": clampi(sections, 1, 4),
		"station_ids": station_ids.duplicate(),
		"express": express,
	}
	return lid


# Edit an existing line in place (keeps its id, name and colour). False if a station pair has no connecting track.
func update_line(lid: int, station_ids: Array[int], model_key: String, trams_count: int, sections: int, express: bool = false) -> bool:
	if not lines.has(lid) or station_ids.size() < 2:
		return false
	for i in range(station_ids.size() - 1):
		if find_track_path_between_stations(station_ids[i], station_ids[i + 1]).is_empty():
			return false
	var ln: Dictionary = lines[lid]
	ln["station_ids"] = station_ids.duplicate()
	ln["model_key"] = model_key
	ln["trams_count"] = clampi(trams_count, 1, 8)
	ln["sections"] = clampi(sections, 1, 4)
	ln["express"] = express
	return true


func sample_edge(edge_id: int, t: float) -> Dictionary:
	var ed: Dictionary = edges[edge_id]
	var pts: Array = ed["pts"]
	if pts.size() < 2:
		return {"pos": Vector3.ZERO, "fwd": Vector3.FORWARD}

	var seg_lens: Array[float] = []
	var total := 0.0
	for i in range(pts.size() - 1):
		var d := (pts[i] as Vector2).distance_to(pts[i + 1] as Vector2)
		seg_lens.append(d)
		total += d
	if total < 0.01:
		var p0: Vector2 = pts[0]
		return {"pos": Vector3(p0.x, 0.0, p0.y), "fwd": Vector3.FORWARD}

	var target := clampf(t, 0.0, 1.0) * total
	var acc := 0.0
	for i in range(seg_lens.size()):
		var sl := seg_lens[i]
		if acc + sl >= target or i == seg_lens.size() - 1:
			var local_t := clampf((target - acc) / maxf(sl, 0.001), 0.0, 1.0)
			var a2: Vector2 = pts[i]
			var b2: Vector2 = pts[i + 1]
			var p2 := a2.lerp(b2, local_t)
			var d2 := (b2 - a2).normalized()
			return {
				"pos": Vector3(p2.x, 0.0, p2.y),
				"fwd": Vector3(d2.x, 0.0, d2.y),
			}
		acc += sl
	var plast: Vector2 = pts[pts.size() - 1]
	return {"pos": Vector3(plast.x, 0.0, plast.y), "fwd": Vector3.FORWARD}


func _insert_edge_into_grid(eid: int, pts: Array[Vector2]) -> void:
	if pts.is_empty():
		return
	var min_v := pts[0]
	var max_v := pts[0]
	for p: Vector2 in pts:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var cx0 := int(floor(min_v.x / GRID_CELL_M))
	var cz0 := int(floor(min_v.y / GRID_CELL_M))
	var cx1 := int(floor(max_v.x / GRID_CELL_M))
	var cz1 := int(floor(max_v.y / GRID_CELL_M))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var key := Vector2i(cx, cz)
			if not _edge_grid.has(key):
				_edge_grid[key] = []
			(_edge_grid[key] as Array).append(eid)


func get_built_track_degree(node_id: int) -> int:
	if not adj.has(node_id):
		return 0
	var deg := [0, 0]
	for nb: Dictionary in adj[node_id]:
		var e := int(nb["edge_id"])
		if built_tracks.has(e):
			deg[TrackBuilder.edge_system(self, e)] += 1
	return maxi(int(deg[0]), int(deg[1]))


func get_turnout_world_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for nid: int in nodes.keys():
		if get_built_track_degree(nid) >= 3:
			var p2: Vector2 = nodes[nid]["pos"]
			out.append(Vector3(p2.x, 0.0, p2.y))
	for eid: int in crossovers.keys():
		if int(crossovers[eid]) > CrossoverType.NONE and edges.has(eid):
			if int(crossovers[eid]) == CrossoverType.DOUBLE and TrackBuilder.is_monorail_style(int(built_tracks.get(eid, -1))):
				# Two-way monorail crossover: one switch centre per beam switch
				var g := TrackBuilder.edge_track_geom(self, eid)
				var xo := TrackBuilder.edge_crossover_span(self, eid, g)
				if not xo.is_empty():
					for pt: Dictionary in TrackBuilder.mono_switch_parts(self, eid, xo):
						var tf := TrackBuilder.sample_track_frame(g["curve"] as Curve3D, float(pt["s_mid"]), float(g["clen"]), false)
						out.append(Vector3(tf.origin.x, 0.0, tf.origin.z))
					continue
			# Centre of the crossover as built on the (aligned) track centreline
			var gx := TrackBuilder.edge_track_geom(self, eid)
			var xs := TrackBuilder.edge_crossover_span(self, eid, gx)
			if not xs.is_empty():
				var tfx := TrackBuilder.sample_track_frame(gx["curve"] as Curve3D, float(xs["s_mid"]), float(gx["clen"]), false)
				out.append(Vector3(tfx.origin.x, 0.0, tfx.origin.z))
				continue
			out.append(sample_edge(eid, float(crossover_t.get(eid, 0.5)))["pos"] as Vector3)
	return out


func find_closest_edge(xz: Vector2, max_dist: float, only_built: bool = false) -> Dictionary:
	var best_eid := -1
	var best_d := max_dist
	var best_t := 0.5

	var cx0 := int(floor((xz.x - max_dist) / GRID_CELL_M))
	var cz0 := int(floor((xz.y - max_dist) / GRID_CELL_M))
	var cx1 := int(floor((xz.x + max_dist) / GRID_CELL_M))
	var cz1 := int(floor((xz.y + max_dist) / GRID_CELL_M))

	var checked := {}
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var cell_list: Array = _edge_grid.get(Vector2i(cx, cz), [])
			for raw_eid in cell_list:
				var eid := int(raw_eid)
				if checked.has(eid) or not edges.has(eid):
					continue
				checked[eid] = true
				if only_built and not built_tracks.has(eid):
					continue
				var pts: Array = edges[eid]["pts"]
				var total := 0.0
				var seg_lens: Array[float] = []
				for i in range(pts.size() - 1):
					var l := (pts[i] as Vector2).distance_to(pts[i + 1] as Vector2)
					seg_lens.append(l)
					total += l
				if total < 0.1:
					continue

				var acc := 0.0
				for i in range(pts.size() - 1):
					var a: Vector2 = pts[i]
					var b: Vector2 = pts[i + 1]
					var ab := b - a
					var l2 := ab.length_squared()
					var lt := 0.0 if l2 < 1e-5 else clampf((xz - a).dot(ab) / l2, 0.0, 1.0)
					var proj := a + ab * lt
					var d := xz.distance_to(proj)
					if d < best_d:
						best_d = d
						best_eid = eid
						best_t = (acc + seg_lens[i] * lt) / total
					acc += seg_lens[i]

	if best_eid < 0:
		return {}
	var smp := sample_edge(best_eid, best_t)
	return {
		"edge_id": best_eid,
		"t": best_t,
		"dist": best_d,
		"pos": smp["pos"],
		"fwd": smp["fwd"],
	}


func find_closest_node(xz: Vector2, max_dist: float) -> int:
	var best_id := -1
	var best_d := max_dist
	for nid: int in nodes.keys():
		var d := xz.distance_to(nodes[nid]["pos"] as Vector2)
		if d < best_d:
			best_d = d
			best_id = nid
	return best_id


func get_station_platform_world_pos(sid: int) -> Vector3:
	if not stations.has(sid):
		return Vector3.ZERO
	var st: Dictionary = stations[sid]
	var pos: Vector3 = st["pos"]
	var side := float(st.get("side", 1))
	if int(side) == 0:
		return pos
	var fwd := (st["fwd"] as Vector3).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var eid := int(st.get("edge_id", -1))
	var sep := get_edge_track_half_sep(eid) if eid >= 0 else 0.0
	if eid >= 0 and is_quad(eid):
		sep = QUAD_LOCAL_HALF_SEP # side platforms stand outside the local tracks
	return pos + right * (side * (sep + 2.8))


func find_closest_station(xz: Vector2, max_dist: float) -> int:
	var best_id := -1
	var best_d := max_dist
	for sid: int in stations.keys():
		var sp := get_station_platform_world_pos(sid)
		var d := xz.distance_to(Vector2(sp.x, sp.z))
		if d < best_d:
			best_d = d
			best_id = sid
	return best_id


func shortest_street_path(node_a: int, node_b: int, only_built: bool, sys: int = -1) -> Array[int]:
	if node_a == node_b or not nodes.has(node_a) or not nodes.has(node_b):
		return []
	var dist := {node_a: 0.0}
	var prev_node := {}
	var prev_edge := {}
	var open: Array[int] = [node_a]

	while not open.is_empty():
		var best_i := 0
		var best_u := open[0]
		var best_c: float = float(dist[best_u])
		for i in range(1, open.size()):
			var u_cand := open[i]
			var c_cand: float = float(dist[u_cand])
			if c_cand < best_c:
				best_c = c_cand
				best_u = u_cand
				best_i = i
		open.remove_at(best_i)

		if best_u == node_b:
			break

		for nb: Dictionary in adj[best_u]:
			var eid := int(nb["edge_id"])
			if only_built and not built_tracks.has(eid):
				continue
			if sys >= 0 and TrackBuilder.edge_system(self, eid) != sys:
				continue
			var v := int(nb["to"])
			var nc := best_c + float(nb["length"])
			if not dist.has(v) or nc < float(dist[v]):
				dist[v] = nc
				prev_node[v] = best_u
				prev_edge[v] = eid
				if not open.has(v):
					open.append(v)

	if not prev_edge.has(node_b):
		return []

	var res: Array[int] = []
	var cur := node_b
	while cur != node_a:
		res.append(int(prev_edge[cur]))
		cur = int(prev_node[cur])
	res.reverse()
	return res


func find_track_path_between_stations(sid_a: int, sid_b: int) -> Array[Vector3]:
	var spans := _station_path_spans(sid_a, sid_b)
	var pts_out: Array[Vector3] = []
	for sp: Dictionary in spans:
		_append_unique_pts(pts_out, _slice_edge_points_3d(int(sp["eid"]), float(sp["t0"]), float(sp["t1"])))
	return pts_out


# Edge traversal list between two stations: [{eid, t0, t1}] (t = normalized position along edge polyline).
func _station_path_spans(sid_a: int, sid_b: int) -> Array:
	if not stations.has(sid_a) or not stations.has(sid_b):
		return []
	var st_a: Dictionary = stations[sid_a]
	var st_b: Dictionary = stations[sid_b]
	var eid_a := int(st_a["edge_id"])
	var eid_b := int(st_b["edge_id"])
	if not built_tracks.has(eid_a) or not built_tracks.has(eid_b):
		return []
	# Trams and monorails are separate systems: a path never changes between them
	var sys := TrackBuilder.edge_system(self, eid_a)
	if TrackBuilder.edge_system(self, eid_b) != sys:
		return []

	if eid_a == eid_b:
		return [{"eid": eid_a, "t0": float(st_a["t"]), "t1": float(st_b["t"])}]

	var ed_a: Dictionary = edges[eid_a]
	var ed_b: Dictionary = edges[eid_b]
	var candidates_a: Array[int] = [int(ed_a["a"]), int(ed_a["b"])]
	var candidates_b: Array[int] = [int(ed_b["a"]), int(ed_b["b"])]

	var best_eids: Array[int] = []
	var best_cost := 1e18
	var best_na := -1
	var best_nb := -1

	for na: int in candidates_a:
		var cost_a := (float(st_a["t"]) if na == int(ed_a["a"]) else (1.0 - float(st_a["t"]))) * float(ed_a["length"])
		for nb: int in candidates_b:
			var cost_b := (float(st_b["t"]) if nb == int(ed_b["a"]) else (1.0 - float(st_b["t"]))) * float(ed_b["length"])
			var mid_eids: Array[int] = []
			var mid_cost := 0.0
			if na != nb:
				mid_eids = shortest_street_path(na, nb, true, sys)
				if mid_eids.is_empty():
					continue
				for me: int in mid_eids:
					mid_cost += float(edges[me]["length"])
			var total_c := cost_a + mid_cost + cost_b
			if total_c < best_cost:
				best_cost = total_c
				best_eids = mid_eids
				best_na = na
				best_nb = nb

	if best_na < 0:
		return []

	var spans: Array = []
	var end_ta := 0.0 if best_na == int(ed_a["a"]) else 1.0
	spans.append({"eid": eid_a, "t0": float(st_a["t"]), "t1": end_ta})

	var cur_node := best_na
	for me: int in best_eids:
		var med: Dictionary = edges[me]
		var forward := (int(med["a"]) == cur_node)
		spans.append({"eid": me, "t0": 0.0 if forward else 1.0, "t1": 1.0 if forward else 0.0})
		cur_node = int(med["b"]) if forward else int(med["a"])

	var start_tb := 0.0 if best_nb == int(ed_b["a"]) else 1.0
	spans.append({"eid": eid_b, "t0": start_tb, "t1": float(st_b["t"])})
	return spans


# Express trains run on the inner tracks of a four-track section, which have no side platforms
func express_can_call_at(sid: int) -> bool:
	if not stations.has(sid):
		return true
	return not (is_quad(int(stations[sid]["edge_id"])) and int(stations[sid].get("side", 1)) != 0)


func _find_opposite_side_station(sid: int) -> int:
	if not stations.has(sid):
		return sid
	var st: Dictionary = stations[sid]
	var s_side := int(st.get("side", 1))
	if s_side == 0:
		return sid # Island platform serves both directions directly!
	var eid := int(st["edge_id"])
	var t_val := float(st["t"])
	for cand_sid: int in stations.keys():
		if cand_sid == sid:
			continue
		var cst: Dictionary = stations[cand_sid]
		if int(cst["edge_id"]) == eid and int(cst.get("side", 1)) == -s_side and absf(float(cst["t"]) - t_val) < 0.28:
			return cand_sid
	return sid


# b_platform_sids: terminal station ids whose turnback should use platform track B (cross over BEFORE arriving,
# depart straight out). All other terminals use track A (arrive straight in, cross over after departing).
# wrong_sids: terminals the train leaves on the wrong track (the driver set the departure switch for it): the
# route stays on that track (or crosses onto it, from platform B) until the next terminal, which it enters
# straight onto platform B, or over the crossover onto platform A.
func compile_line_route(line_dict: Dictionary, b_platform_sids: Dictionary = {}, wrong_sids: Dictionary = {}) -> Dictionary:
	var raw_sids: Array = line_dict.get("station_ids", [])
	if raw_sids.size() < 2:
		return {}

	var is_loop := (raw_sids.size() >= 3 and int(raw_sids[0]) == int(raw_sids[raw_sids.size() - 1]))
	var sids: Array[int] = []
	for r_sid in raw_sids:
		sids.append(int(r_sid))

	# On Double Track corridors, convert open bidirectional lines (S0..Sk) into a right-hand bidirectional loop
	# with terminal crossover turnback so trams ALWAYS keep right after departing the terminal!
	if not is_loop:
		var double_stn_cnt := 0
		for sid_c: int in sids:
			if stations.has(sid_c):
				var e_c := int(stations[sid_c]["edge_id"])
				if is_multi_track(e_c):
					double_stn_cnt += 1
		if double_stn_cnt > 0:
			var ret_idx := sids.size() - 2
			while ret_idx >= 0:
				sids.append(_find_opposite_side_station(sids[ret_idx]))
				ret_idx -= 1
			if sids[sids.size() - 1] != sids[0]:
				sids.append(sids[0])
			is_loop = true

	# 1. Edge traversal spans for every inter-station segment, in edge-curve arc length (s) with lateral lane sign
	#    (lat = +1 -> right of the edge's a->b direction, -1 -> left; normal running keeps to the right of travel).
	var geo_cache: Dictionary = {}
	var seg_spans: Array = []
	# Four-track sections: express lines run on the inner (express) tracks, all others on the outer local tracks
	var express := bool(line_dict.get("express", false))
	for i in range(sids.size() - 1):
		var raw_spans := _station_path_spans(sids[i], sids[i + 1])
		if raw_spans.is_empty():
			return {}
		var conv: Array = []
		for rs: Dictionary in raw_spans:
			var eid := int(rs["eid"])
			var s0 := _route_t_to_s(geo_cache, eid, float(rs["t0"]))
			var s1 := _route_t_to_s(geo_cache, eid, float(rs["t1"]))
			var lat := 1.0 if s1 >= s0 else -1.0
			var span_d := {"eid": eid, "s0": s0, "s1": s1, "lat0": lat, "lat1": lat}
			if not express and is_quad(eid):
				span_d["loc"] = true
			conv.append(span_d)
		seg_spans.append(conv)
	var n_seg := seg_spans.size()

	# 2. Terminal turnbacks: the tram pulls up to the far end of the platform, changes cab, departs back on the
	#    SAME track (wrong-track running) and switches to the right-hand track over the next crossover.
	var is_turnback: Array[bool] = []
	is_turnback.resize(sids.size())
	is_turnback.fill(false)
	var turnback_meta: Array = []
	# Wrong-track running: flip every span from the departure out of a wrong_sids terminal to the next terminal
	var dep_wrong := {}
	var arr_flip := {}
	if not wrong_sids.is_empty():
		var tb_js: Array[int] = []
		var tb_io := {}
		for j in range(sids.size()):
			var in_k0 := j - 1
			if is_loop:
				if j == sids.size() - 1:
					continue
				if j == 0:
					in_k0 = n_seg - 1
			if in_k0 < 0 or j >= n_seg:
				continue
			var isp: Dictionary = (seg_spans[in_k0] as Array).back()
			var osp: Dictionary = (seg_spans[j] as Array).front()
			if int(isp["eid"]) != int(osp["eid"]):
				continue
			var di := signf(float(isp["s1"]) - float(isp["s0"]))
			if di == 0.0 or signf(float(osp["s1"]) - float(osp["s0"])) != -di:
				continue
			tb_js.append(j)
			tb_io[j] = in_k0
		for ti in range(tb_js.size()):
			var j0 := tb_js[ti]
			if not wrong_sids.has(sids[j0]):
				continue
			if ti + 1 >= tb_js.size() and not is_loop:
				continue
			var j1 := tb_js[(ti + 1) % tb_js.size()]
			dep_wrong[j0] = true
			arr_flip[j1] = true
			var k := j0
			var k_end := int(tb_io[j1])
			for _guard in range(n_seg):
				for sp_f: Dictionary in seg_spans[k]:
					sp_f["lat0"] = -float(sp_f["lat0"])
					sp_f["lat1"] = -float(sp_f["lat1"])
				if k == k_end:
					break
				k = (k + 1) % n_seg
	for j in range(sids.size()):
		var in_k := j - 1
		var out_k := j
		if is_loop:
			if j == sids.size() - 1:
				continue
			if j == 0:
				in_k = n_seg - 1
		if in_k < 0 or out_k >= n_seg:
			continue
		var in_sp: Dictionary = (seg_spans[in_k] as Array).back()
		var out_sp: Dictionary = (seg_spans[out_k] as Array).front()
		if int(in_sp["eid"]) != int(out_sp["eid"]):
			continue
		var d_in := signf(float(in_sp["s1"]) - float(in_sp["s0"]))
		var d_out := signf(float(out_sp["s1"]) - float(out_sp["s0"]))
		if d_in == 0.0 or d_out != -d_in:
			continue
		var t_eid := int(in_sp["eid"])
		var s_st := float(in_sp["s1"])
		var s_cusp := _route_clamp_s(geo_cache, t_eid, s_st + d_in * TURNBACK_EXTEND_M)
		if (s_cusp - s_st) * d_in < 0.0:
			s_cusp = s_st
		# Dead-end tail track: the usable track runs on to the buffer stop at the rail end. Trams still stop at
		# the platform (stop_back), but an overrunning tram can now travel the tail track and hit the buffer.
		var stop_back := 0.0
		var end_info := buffer_stop_at_edge_end(t_eid, d_in > 0.0)
		if not end_info.is_empty():
			var s_buf := float(end_info["s_track_end"])
			var tail := (s_buf - s_cusp) * d_in
			if tail > 0.5:
				tail = minf(tail, MAX_TAIL_TRACK_M)
				s_cusp += d_in * tail
				stop_back = tail
			elif tail < 0.0 and (s_buf - s_st) * d_in > 0.0:
				s_cusp = s_buf # turnback point would be inside the buffer stop: pull it back to the clearance
		in_sp["s1"] = s_cusp
		out_sp["s0"] = s_cusp
		is_turnback[j] = true
		var tb_sid := sids[j]
		out_sp["mark"] = "cusp:%d" % tb_sid
		var in_spans: Array = seg_spans[in_k]
		var out_spans: Array = seg_spans[out_k]
		var xo_in := _route_find_crossover(in_spans, geo_cache, true)
		var xo_out := _route_find_crossover(out_spans, geo_cache, false)
		var b_ok := (not xo_in.is_empty()) and (not xo_out.is_empty()) and int(xo_in["eid"]) == int(xo_out["eid"]) \
			and int(crossovers.get(int(xo_in["eid"]), CrossoverType.NONE)) == CrossoverType.DOUBLE
		var use_b := b_ok and b_platform_sids.has(tb_sid)
		# Crossings made from the "other" track take the other half of a two-way crossover
		if arr_flip.has(j) and not use_b and not xo_in.is_empty():
			xo_in = _route_find_crossover(in_spans, geo_cache, true, true)
		if dep_wrong.has(j) and use_b and not xo_out.is_empty():
			xo_out = _route_find_crossover(out_spans, geo_cache, false, true)
		# Arriving on the wrong track, platform B lies straight ahead and platform A over the crossover
		if not xo_in.is_empty():
			_route_apply_arrival_crossover(in_spans, xo_in, (not use_b) if arr_flip.has(j) else use_b, tb_sid)
		# Leaving on the wrong track (spans already flipped): straight out from A, over the crossover from B
		if not xo_out.is_empty():
			_route_apply_departure_crossover(out_spans, xo_out, use_b if dep_wrong.has(j) else not use_b, tb_sid)
		turnback_meta.append({"j": j, "station_id": tb_sid, "b_available": b_ok, "platform": 1 if use_b else 0, "has_crossover": not xo_out.is_empty(), "stop_back": stop_back, "buffer": not end_info.is_empty()})

	# Open (single-track) lines: run the track on a little past both terminals so the whole tram fits the platform
	if not is_loop:
		var first_sp: Dictionary = (seg_spans[0] as Array).front()
		var d_f := signf(float(first_sp["s1"]) - float(first_sp["s0"]))
		first_sp["s0"] = _route_clamp_s(geo_cache, int(first_sp["eid"]), float(first_sp["s0"]) - d_f * TURNBACK_EXTEND_M)
		var last_sp: Dictionary = (seg_spans[n_seg - 1] as Array).back()
		var d_l := signf(float(last_sp["s1"]) - float(last_sp["s0"]))
		last_sp["s1"] = _route_clamp_s(geo_cache, int(last_sp["eid"]), float(last_sp["s1"]) + d_l * TURNBACK_EXTEND_M)

	# 3. Sample the exact rendered rail geometry (edge curves + junction connector arcs + crossover diagonals)
	var all_pts: Array[Vector3] = []
	var stop_pts: Array[Vector3] = []
	var mark_idx: Dictionary = {} # "hold:<sid>" / "cusp:<sid>" / "exit:<sid>" -> index into all_pts
	var prev_sp: Dictionary = {}
	for k in range(n_seg):
		var spans_k: Array = seg_spans[k]
		stop_pts.append(_route_stop_point(sids[k], spans_k.front() as Dictionary, is_turnback[k], true, geo_cache))
		for sp: Dictionary in spans_k:
			if not prev_sp.is_empty() and int(prev_sp["eid"]) != int(sp["eid"]):
				_append_unique_pts(all_pts, _route_junction_points(prev_sp, sp, geo_cache))
			if sp.has("mark"):
				mark_idx[str(sp["mark"])] = maxi(0, all_pts.size() - 1) if is_loop or not all_pts.is_empty() else 0
			_append_unique_pts(all_pts, _route_span_points(sp, geo_cache))
			prev_sp = sp
	if is_loop:
		var first_sp_l: Dictionary = (seg_spans[0] as Array).front()
		if int(prev_sp["eid"]) != int(first_sp_l["eid"]):
			_append_unique_pts(all_pts, _route_junction_points(prev_sp, first_sp_l, geo_cache))
		while all_pts.size() > 2 and all_pts[all_pts.size() - 1].distance_to(all_pts[0]) < 0.35:
			all_pts.remove_at(all_pts.size() - 1)
	else:
		stop_pts.append(_route_stop_point(sids[sids.size() - 1], (seg_spans[n_seg - 1] as Array).back() as Dictionary, false, false, geo_cache))

	if all_pts.size() < 2:
		return {}

	var raw_arr: Array = []
	for p: Vector3 in all_pts:
		raw_arr.append([p.x, p.y + Terrain.surface(p.x, p.z), p.z]) # trains run over the real ground

	var curve := TrackBuilder.create_smooth_curve(raw_arr, is_loop)
	var total_len := curve.get_baked_length()
	if total_len < 10.0:
		return {}

	var stop_count := sids.size() - 1 if is_loop else sids.size()
	var route_stops: Array[Dictionary] = []
	var turnbacks: Array[float] = []
	for idx in range(stop_count):
		var sid := sids[idx]
		var st: Dictionary = stations[sid]
		var sp_l: Vector3 = stop_pts[idx]
		var s_off := curve.get_closest_offset(sp_l + Vector3(0.0, Terrain.surface(sp_l.x, sp_l.z), 0.0)) # curve is on the ground
		var cusp_off := s_off
		var stop_back := 0.0
		if is_turnback[idx]:
			s_off = _refine_cusp_offset(curve, total_len, is_loop, s_off)
			cusp_off = s_off
			turnbacks.append(s_off)
			for tm0: Dictionary in turnback_meta:
				if int(tm0["station_id"]) == sid:
					stop_back = float(tm0.get("stop_back", 0.0))
			# Platform stop point lies stop_back before the turnback point (arrival leg runs toward +s)
			if stop_back > 0.0:
				s_off = fposmod(s_off - stop_back, total_len) if is_loop else maxf(0.0, s_off - stop_back)
		route_stops.append({
			"station_id": sid,
			"name": st["name"],
			"offset": s_off,
			"cusp": cusp_off,
			"pos": st["pos"],
			"side": st["side"],
			"turnback": is_turnback[idx],
		})

	# Terminal interlocking zones (route arc length): hold point before the crossover, turnback point, and
	# the point the departing tram must clear (crossover outer end) before the zone is released.
	var cum := PackedFloat32Array()
	cum.resize(all_pts.size())
	var acc_len := 0.0
	for pi in range(all_pts.size()):
		if pi > 0:
			acc_len += all_pts[pi].distance_to(all_pts[pi - 1])
		cum[pi] = acc_len
	var poly_total := acc_len + (all_pts[all_pts.size() - 1].distance_to(all_pts[0]) if is_loop else 0.0)
	var terminal_zones: Array = []
	for tm: Dictionary in turnback_meta:
		var tsid := int(tm["station_id"])
		var cusp_s := 0.0
		for rs: Dictionary in route_stops:
			if int(rs["station_id"]) == tsid and bool(rs["turnback"]):
				cusp_s = float(rs["cusp"])
		var fallback_d := TURNBACK_EXTEND_M + 13.5 + 6.0
		var arr_d := fallback_d
		var dep_d := fallback_d
		var ci: int = mark_idx.get("cusp:%d" % tsid, -1)
		var hi: int = mark_idx.get("hold:%d" % tsid, -1)
		var ei: int = mark_idx.get("exit:%d" % tsid, -1)
		if ci >= 0 and hi >= 0:
			arr_d = fposmod(cum[ci] - cum[hi], poly_total) if is_loop else cum[ci] - cum[hi]
		if ci >= 0 and ei >= 0:
			dep_d = fposmod(cum[ei] - cum[ci], poly_total) if is_loop else cum[ei] - cum[ci]
		var hold_s := cusp_s - arr_d - TERMINAL_HOLD_MARGIN_M
		var exit_s := cusp_s + dep_d
		terminal_zones.append({
			"station_id": tsid,
			"cusp_s": cusp_s,
			"hold_s": fposmod(hold_s, total_len) if is_loop else maxf(0.0, hold_s),
			"exit_s": fposmod(exit_s, total_len) if is_loop else minf(total_len, exit_s),
			"platform": int(tm["platform"]),
			"b_available": bool(tm["b_available"]),
			"stop_back": float(tm.get("stop_back", 0.0)),
			"buffer": bool(tm.get("buffer", false)),
		})

	# Pre-bake O(1) rail height + curve & turnout speed-limit profile every 2.0m along the route!
	var n_samples := maxi(2, int(ceil(total_len / PROFILE_STEP_M)) + 1)
	var rail_heights := PackedFloat32Array()
	var raw_limits := PackedFloat32Array()
	var raw_derail := PackedFloat32Array()
	var curve_signs := PackedFloat32Array()
	var raw_zones := PackedByteArray()
	rail_heights.resize(n_samples)
	raw_limits.resize(n_samples)
	raw_derail.resize(n_samples)
	curve_signs.resize(n_samples)
	raw_zones.resize(n_samples)

	var turnout_pts := get_turnout_world_positions()

	for si in range(n_samples):
		var s_val := minf(float(si) * PROFILE_STEP_M, total_len)
		var pos_here := curve.sample_baked(s_val, true)
		var bst := get_bed_style_at_world_pos(pos_here)
		rail_heights[si] = TrackBuilder.rail_top_for_style(bst) - TrackBuilder.EMBED_RAIL_TOP

		# Measure local curvature over a 7.0m chord
		var s_back := fposmod(s_val - 3.5, total_len) if is_loop else maxf(0.0, s_val - 3.5)
		var s_fore := fposmod(s_val + 3.5, total_len) if is_loop else minf(total_len, s_val + 3.5)
		var tf_b := TrackBuilder.sample_track_frame(curve, s_back, total_len, is_loop)
		var tf_f := TrackBuilder.sample_track_frame(curve, s_fore, total_len, is_loop)
		var fwd_b := -tf_b.basis.z
		var fwd_f := -tf_f.basis.z
		var chord := maxf(2.0, s_fore - s_back if not is_loop else 7.0)
		var d_ang := acos(clampf(fwd_b.dot(fwd_f), -1.0, 1.0))
		var radius := chord / maxf(d_ang, 0.0004)
		if d_ang > deg_to_rad(150.0):
			radius = 999.0 # Terminal turnback cusp (direction reversal), not a curve
		var turn_s := signf(fwd_b.cross(fwd_f).y)
		curve_signs[si] = turn_s

		var near_turnout := false
		for tp: Vector3 in turnout_pts:
			if pos_here.distance_squared_to(tp) <= 95.0: # within ~9.7m of turnout switch center
				near_turnout = true
				break

		if near_turnout and bst == TrackBuilder.BedStyle.MONORAIL:
			# Monorail moving-beam switch: running straight through is plain guideway (no restriction);
			# only the crossing S-beam (gentle, R ~55 m) is a diverging-switch zone.
			# The S-beam has an inflection at mid-switch (locally straight but ~10 deg skewed), so also test the
			# heading against 22 m back/forward: an S turns one way then back, a plain curve keeps turning.
			var crossing := radius < 150.0
			if not crossing:
				var s_b2 := fposmod(s_val - 22.0, total_len) if is_loop else maxf(0.0, s_val - 22.0)
				var s_f2 := fposmod(s_val + 22.0, total_len) if is_loop else minf(total_len, s_val + 22.0)
				var fwd_here := -TrackBuilder.sample_track_frame(curve, s_val, total_len, is_loop).basis.z
				var fb2 := -TrackBuilder.sample_track_frame(curve, s_b2, total_len, is_loop).basis.z
				var ff2 := -TrackBuilder.sample_track_frame(curve, s_f2, total_len, is_loop).basis.z
				var a_in := signf(fb2.cross(fwd_here).y) * acos(clampf(fb2.dot(fwd_here), -1.0, 1.0))
				var a_out := signf(fwd_here.cross(ff2).y) * acos(clampf(fwd_here.dot(ff2), -1.0, 1.0))
				crossing = a_in * a_out < 0.0 and absf(a_in) > deg_to_rad(3.0) and absf(a_out) > deg_to_rad(3.0)
			if crossing:
				raw_limits[si] = 30.0
				raw_derail[si] = 42.0
				raw_zones[si] = 5 # 侧向道岔
				continue
			near_turnout = false
		if near_turnout and radius < 48.0:
			raw_limits[si] = 18.0
			raw_derail[si] = 27.0
			raw_zones[si] = 5 # 侧向道岔
		elif near_turnout:
			raw_limits[si] = 30.0
			raw_derail[si] = 42.0
			raw_zones[si] = 4 # 直向道岔
		elif radius < 18.5:
			raw_limits[si] = 20.0
			raw_derail[si] = 30.0
			raw_zones[si] = 3 # 急弯
		elif radius < 36.0:
			raw_limits[si] = 28.0
			raw_derail[si] = 40.0
			raw_zones[si] = 2 # 弯道
		elif radius < 68.0:
			raw_limits[si] = 40.0
			raw_derail[si] = 54.0
			raw_zones[si] = 1 # 缓弯
		else:
			raw_limits[si] = 60.0 if bst == TrackBuilder.BedStyle.ASPHALT else 70.0
			raw_derail[si] = 999.0 # Straight track does not centrifugally overturn
			raw_zones[si] = 0 # 正线

	# Dilate restrictive speed zones by +/- 3 samples (+/- 6m) so curves/turnouts feel smooth and consistent
	var speed_limits := PackedFloat32Array()
	var derail_limits := PackedFloat32Array()
	var zone_kinds := PackedByteArray()
	speed_limits.resize(n_samples)
	derail_limits.resize(n_samples)
	zone_kinds.resize(n_samples)

	for si in range(n_samples):
		var best_lim := raw_limits[si]
		var best_der := raw_derail[si]
		var best_zk := raw_zones[si]
		var best_sign := curve_signs[si]
		for off in range(-3, 4):
			var ni := posmod(si + off, n_samples) if is_loop else clampi(si + off, 0, n_samples - 1)
			if raw_limits[ni] < best_lim:
				best_lim = raw_limits[ni]
				best_der = raw_derail[ni]
				best_zk = raw_zones[ni]
				if absf(curve_signs[ni]) > 0.1:
					best_sign = curve_signs[ni]
		speed_limits[si] = best_lim
		derail_limits[si] = best_der
		zone_kinds[si] = best_zk
		if absf(curve_signs[si]) < 0.1 and absf(best_sign) > 0.1:
			curve_signs[si] = best_sign

	return {
		"curve": curve,
		"length": total_len,
		"is_loop": is_loop,
		"stops": route_stops,
		"turnbacks": turnbacks,
		"terminal_zones": terminal_zones,
		"rail_heights": rail_heights,
		"speed_limits_kmh": speed_limits,
		"derail_kmh": derail_limits,
		"curve_signs": curve_signs,
		"zone_kinds": zone_kinds,
	}


func get_bed_style_at_world_pos(pos: Vector3) -> int:
	var hit := find_closest_edge(Vector2(pos.x, pos.z), 16.0, true)
	if hit.is_empty():
		return TrackBuilder.BedStyle.ASPHALT
	var eid := int(hit["edge_id"])
	return int(built_tracks.get(eid, TrackBuilder.BedStyle.ASPHALT))


func _slice_edge_points_3d(edge_id: int, t0: float, t1: float) -> Array[Vector3]:
	var steps := maxi(2, int(ceil(absf(t1 - t0) * float(edges[edge_id]["length"]) / 8.0)))
	var sep := get_edge_track_half_sep(edge_id)
	var lat_sign := (1.0 if t1 >= t0 else -1.0)
	var out: Array[Vector3] = []
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var smp := sample_edge(edge_id, lerpf(t0, t1, f))
		var p: Vector3 = smp["pos"] as Vector3
		if sep > 0.01:
			var fwd := (smp["fwd"] as Vector3).normalized()
			var right_v := fwd.cross(Vector3.UP).normalized()
			p += right_v * (sep * lat_sign)
		out.append(p)
	return out


static func _append_unique_pts(dst: Array[Vector3], src: Array[Vector3]) -> void:
	for p: Vector3 in src:
		if dst.is_empty() or dst[dst.size() - 1].distance_to(p) > 0.35:
			dst.append(p)


# ---------------------------------------------------------------------------------------------
# Route geometry helpers: sample the SAME rail geometry TrackBuilder renders.
# ---------------------------------------------------------------------------------------------

func _route_geom(cache: Dictionary, eid: int) -> Dictionary:
	if not cache.has(eid):
		cache[eid] = TrackBuilder.edge_track_geom(self, eid)
	return cache[eid]


func _route_edge_len(cache: Dictionary, eid: int) -> float:
	var g := _route_geom(cache, eid)
	return float(g["clen"]) if not g.is_empty() else float(edges[eid]["length"])


# Polyline parameter t (station / node position) -> arc length on the edge's smoothed rail curve.
func _route_t_to_s(cache: Dictionary, eid: int, t: float) -> float:
	var clen := _route_edge_len(cache, eid)
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return clen
	var g := _route_geom(cache, eid)
	if g.is_empty():
		return t * clen
	return (g["curve"] as Curve3D).get_closest_offset(sample_edge(eid, t)["pos"] as Vector3)


func _route_clamp_s(cache: Dictionary, eid: int, s: float) -> float:
	var g := _route_geom(cache, eid)
	if g.is_empty():
		return clampf(s, 0.5, maxf(0.5, float(edges[eid]["length"]) - 0.5))
	return clampf(s, float(g["s_start"]) + 0.5, maxf(float(g["s_start"]) + 0.5, float(g["s_end"]) - 0.5))


# Lateral lane sign at arc length s inside a span (crossover diagonals blend lat0 -> lat1 with the renderer's hermite).
static func _route_span_lat(sp: Dictionary, s: float) -> float:
	var lat0 := float(sp["lat0"])
	var lat1 := float(sp["lat1"])
	if is_equal_approx(lat0, lat1):
		return lat0
	var s0 := float(sp["s0"])
	var s1 := float(sp["s1"])
	var u := clampf((s - s0) / (s1 - s0), 0.0, 1.0) if absf(s1 - s0) > 0.01 else 0.0
	var herm := 3.0 * u * u - 2.0 * u * u * u
	return lerpf(lat0, lat1, herm)


func _route_point_at(sp: Dictionary, s: float, cache: Dictionary) -> Vector3:
	var eid := int(sp["eid"])
	var g := _route_geom(cache, eid)
	if g.is_empty():
		var len_e := maxf(0.01, float(edges[eid]["length"]))
		var smp := sample_edge(eid, s / len_e)
		var fwd := (smp["fwd"] as Vector3).normalized()
		var sep_f := QUAD_LOCAL_HALF_SEP if sp.has("loc") else get_edge_track_half_sep(eid)
		return (smp["pos"] as Vector3) + fwd.cross(Vector3.UP).normalized() * (sep_f * _route_span_lat(sp, s))
	var s_c := clampf(s, float(g["s_start"]), float(g["s_end"]))
	var tf := TrackBuilder.sample_track_frame(g["curve"] as Curve3D, s_c, float(g["clen"]), false)
	var sep_c := TrackBuilder.geom_lsep_at(g, s_c) if sp.has("loc") else TrackBuilder.geom_sep_at(g, s_c)
	return tf.origin + tf.basis.x * (sep_c * _route_span_lat(sp, s_c))


func _route_span_points(sp: Dictionary, cache: Dictionary) -> Array[Vector3]:
	var eid := int(sp["eid"])
	var g := _route_geom(cache, eid)
	var a := float(sp["s0"])
	var b := float(sp["s1"])
	if not g.is_empty():
		a = clampf(a, float(g["s_start"]), float(g["s_end"]))
		b = clampf(b, float(g["s_start"]), float(g["s_end"]))
	# Fixed per-edge sampling grid so a turnback's return leg reuses exactly the arrival leg's points
	var lo := minf(a, b)
	var hi := maxf(a, b)
	var s_list: Array[float] = [a]
	var k0 := int(floor(lo / ROUTE_SAMPLE_STEP_M)) + 1
	var k1 := int(ceil(hi / ROUTE_SAMPLE_STEP_M)) - 1
	var grid: Array[float] = []
	for k in range(k0, k1 + 1):
		var gs := float(k) * ROUTE_SAMPLE_STEP_M
		if gs > lo + 0.05 and gs < hi - 0.05:
			grid.append(gs)
	if b < a:
		grid.reverse()
	s_list.append_array(grid)
	s_list.append(b)
	var out: Array[Vector3] = []
	for s: float in s_list:
		out.append(_route_point_at(sp, s, cache))
	return out


# Junction connector arc between two consecutive spans on different edges (same cubic the renderer draws).
func _route_junction_points(sp_a: Dictionary, sp_b: Dictionary, cache: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ed_a: Dictionary = edges[int(sp_a["eid"])]
	var ed_b: Dictionary = edges[int(sp_b["eid"])]
	var nid := -1
	for n_a: int in [int(ed_a["a"]), int(ed_a["b"])]:
		if n_a == int(ed_b["a"]) or n_a == int(ed_b["b"]):
			nid = n_a
	if nid < 0:
		return out
	var info := TrackBuilder.node_track_info(self, nid, TrackBuilder.edge_system(self, int(sp_a["eid"])))
	if not bool(info["bare"]) and (info["edges"] as Array).size() <= 2:
		return out # Plain bend: the two edges' rails meet directly at the node
	var g_a := _route_geom(cache, int(sp_a["eid"]))
	var g_b := _route_geom(cache, int(sp_b["eid"]))
	if g_a.is_empty() or g_b.is_empty():
		return out
	var s_a := clampf(float(sp_a["s1"]), float(g_a["s_start"]), float(g_a["s_end"]))
	var s_b := clampf(float(sp_b["s0"]), float(g_b["s_start"]), float(g_b["s_end"]))
	var pa := _route_point_at(sp_a, s_a, cache)
	var pb := _route_point_at(sp_b, s_b, cache)
	var da := 1.0 if float(sp_a["s1"]) >= float(sp_a["s0"]) else -1.0
	var db := 1.0 if float(sp_b["s1"]) >= float(sp_b["s0"]) else -1.0
	var tf_a := TrackBuilder.sample_track_frame(g_a["curve"] as Curve3D, s_a, float(g_a["clen"]), false)
	var tf_b := TrackBuilder.sample_track_frame(g_b["curve"] as Curve3D, s_b, float(g_b["clen"]), false)
	var j_curve := TrackBuilder.junction_connector_curve(pa, -tf_a.basis.z * da, pb, -tf_b.basis.z * db)
	if j_curve == null:
		return out
	var jlen := j_curve.get_baked_length()
	var jsteps := maxi(2, int(ceil(jlen / ROUTE_SAMPLE_STEP_M)))
	for jk in range(1, jsteps):
		out.append(j_curve.sample_baked(jlen * float(jk) / float(jsteps), true))
	return out


# First crossover lying fully inside the spans, searched forward (departure) or backward from the station (arrival).
# Returns {k, eid, s_inner, s_outer}: inner = crossover end nearer the terminal station.
# Two-way monorail crossovers hold two beam switches: the arrival move onto platform B uses the hand -1 one, the
# departure move uses the hand +1 one; s_zone is the outer end of the whole footprint (terminal interlocking).
# flip_hand: the train runs on the other track than usual here (wrong-track arrival / departure onto the wrong
# track), so the crossing it can take is the other half of a two-way crossover.
func _route_find_crossover(spans: Array, cache: Dictionary, backward: bool, flip_hand: bool = false) -> Dictionary:
	var order: Array = range(spans.size())
	if backward:
		order.reverse()
	for k: int in order:
		var sp: Dictionary = spans[k]
		var eid := int(sp["eid"])
		var s0 := float(sp["s0"])
		var s1 := float(sp["s1"])
		var d := signf(s1 - s0)
		if d == 0.0:
			continue
		var xo := TrackBuilder.edge_crossover_span(self, eid, _route_geom(cache, eid))
		if xo.is_empty():
			continue
		var s_a := float(xo["s_mid"]) - d * float(xo["x_half"]) # first end met in travel direction
		var s_b := float(xo["s_mid"]) + d * float(xo["x_half"])
		if (s_a - s0) * d >= -0.05 and (s1 - s_b) * d >= -0.05:
			var s_zone := s_a if backward else s_b
			if TrackBuilder.edge_system(self, eid) == 1 and int(crossovers.get(eid, CrossoverType.NONE)) == CrossoverType.DOUBLE:
				for pt: Dictionary in TrackBuilder.mono_switch_parts(self, eid, xo):
					if float(pt["hand"]) == (-1.0 if backward else 1.0) * (-1.0 if flip_hand else 1.0):
						s_a = float(pt["s_mid"]) - d * float(pt["x_half"])
						s_b = float(pt["s_mid"]) + d * float(pt["x_half"])
			if backward:
				return {"k": k, "eid": eid, "s_outer": s_a, "s_inner": s_b, "s_zone": s_zone}
			return {"k": k, "eid": eid, "s_inner": s_a, "s_outer": s_b, "s_zone": s_zone}
	return {}


static func _span_copy(sp: Dictionary, s0: float, s1: float, lat0: float, lat1: float) -> Dictionary:
	var c := {"eid": int(sp["eid"]), "s0": s0, "s1": s1, "lat0": lat0, "lat1": lat1}
	if sp.has("loc"):
		c["loc"] = true
	return c


# Arrival leg into a terminal. Track A: straight in on the right-hand track. Track B: cross over the
# scissors onto the other platform track (wrong-track relative to arrival) right before the terminal.
func _route_apply_arrival_crossover(spans: Array, xo: Dictionary, use_b: bool, sid: int) -> void:
	var k := int(xo["k"])
	var sp: Dictionary = spans[k]
	var lat_ok := float(sp["lat0"])
	var out: Array = []
	for i in range(k):
		out.append(spans[i])
	var s_zone := float(xo.get("s_zone", xo["s_outer"]))
	var first := _span_copy(sp, float(sp["s0"]), s_zone, lat_ok, lat_ok)
	if sp.has("mark"):
		first["mark"] = sp["mark"]
	out.append(first)
	var held := false
	if absf(s_zone - float(xo["s_outer"])) > 0.05:
		# Two-way crossover: run straight through the first switch to the one this move uses
		var app := _span_copy(sp, s_zone, float(xo["s_outer"]), lat_ok, lat_ok)
		app["mark"] = "hold:%d" % sid
		out.append(app)
		held = true
	if use_b:
		var diag := _span_copy(sp, float(xo["s_outer"]), float(xo["s_inner"]), lat_ok, -lat_ok)
		if not held:
			diag["mark"] = "hold:%d" % sid
		out.append(diag)
		out.append(_span_copy(sp, float(xo["s_inner"]), float(sp["s1"]), -lat_ok, -lat_ok))
		for i in range(k + 1, spans.size()):
			var rest: Dictionary = spans[i]
			rest["lat0"] = -float(rest["lat0"])
			rest["lat1"] = -float(rest["lat1"])
			out.append(rest)
	else:
		var tail := _span_copy(sp, float(xo["s_outer"]), float(sp["s1"]), lat_ok, lat_ok)
		if not held:
			tail["mark"] = "hold:%d" % sid
		out.append(tail)
		for i in range(k + 1, spans.size()):
			out.append(spans[i])
	spans.clear()
	spans.append_array(out)


# Departure leg out of a terminal. From track A: run back on the arrival track (wrong-track) and cross over.
# From track B: the platform track already is the right-hand track, so depart straight out.
func _route_apply_departure_crossover(spans: Array, xo: Dictionary, from_a: bool, sid: int) -> void:
	var k := int(xo["k"])
	var sp: Dictionary = spans[k]
	var lat_ok := float(sp["lat0"])
	var out: Array = []
	for i in range(k):
		var pre: Dictionary = spans[i]
		if from_a:
			pre["lat0"] = -float(pre["lat0"])
			pre["lat1"] = -float(pre["lat1"])
		out.append(pre)
	var lat_first := -lat_ok if from_a else lat_ok
	var first := _span_copy(sp, float(sp["s0"]), float(xo["s_inner"]), lat_first, lat_first)
	if sp.has("mark"):
		first["mark"] = sp["mark"]
	out.append(first)
	out.append(_span_copy(sp, float(xo["s_inner"]), float(xo["s_outer"]), lat_first, lat_ok))
	var s_zone := float(xo.get("s_zone", xo["s_outer"]))
	if absf(s_zone - float(xo["s_outer"])) > 0.05:
		out.append(_span_copy(sp, float(xo["s_outer"]), s_zone, lat_ok, lat_ok)) # through the other switch
	var tail := _span_copy(sp, s_zone, float(sp["s1"]), lat_ok, lat_ok)
	tail["mark"] = "exit:%d" % sid
	out.append(tail)
	for i in range(k + 1, spans.size()):
		out.append(spans[i])
	spans.clear()
	spans.append_array(out)


# Track point a route stop is measured from: the turnback point for terminals, else the station center on the served track.
func _route_stop_point(sid: int, sp: Dictionary, turnback: bool, at_span_start: bool, cache: Dictionary) -> Vector3:
	if turnback:
		return _route_point_at(sp, float(sp["s0"]), cache)
	var st: Dictionary = stations[sid]
	var eid := int(st["edge_id"])
	if eid == int(sp["eid"]):
		return _route_point_at(sp, _route_t_to_s(cache, eid, float(st["t"])), cache)
	return _route_point_at(sp, float(sp["s0"]) if at_span_start else float(sp["s1"]), cache)


# Exact arc-length of a reversal cusp: the point where the arrival and departure legs mirror each other.
# (Trams change cab by mirroring s about this point, so it must be precise to avoid any visible hop.)
static func _refine_cusp_offset(curve: Curve3D, total_len: float, is_loop: bool, s_guess: float) -> float:
	var best_s := s_guess
	var best_err := 1e9
	var probe := 6.0
	var k := -150
	while k <= 150:
		var s_c := s_guess + float(k) * 0.02
		var s_b := fposmod(s_c - probe, total_len) if is_loop else clampf(s_c - probe, 0.0, total_len)
		var s_f := fposmod(s_c + probe, total_len) if is_loop else clampf(s_c + probe, 0.0, total_len)
		var err := curve.sample_baked(s_b, true).distance_squared_to(curve.sample_baked(s_f, true))
		if err < best_err:
			best_err = err
			best_s = s_c
		k += 1
	return fposmod(best_s, total_len) if is_loop else clampf(best_s, 0.0, total_len)



# ---------------------------------------------------------------------------------------------
# Seattle Center Monorail: lay the real 5th Avenue / 5th Ave N route as a double straddle-beam guideway
# with island terminals (beam-switch crossovers for the turnback) and a two-train line. Only edges nobody
# has built on are used; returns the new line id or -1.
# ---------------------------------------------------------------------------------------------
func seed_seattle_monorail(start_xz: Vector2, end_xz: Vector2, model_key: String) -> int:
	var na := find_closest_node(start_xz, 40.0)
	var nb := find_closest_node(end_xz, 40.0)
	if na < 0 or nb < 0:
		return -1
	var path := shortest_street_path(na, nb, false)
	if path.size() < 3:
		return -1
	for e: int in path:
		if built_tracks.has(e):
			return -1
	# Terminal edges must hold a 27m platform plus its tail track
	while path.size() > 2 and float(edges[path[0]]["length"]) < 45.0:
		na = int(edges[path[0]]["b"]) if int(edges[path[0]]["a"]) == na else int(edges[path[0]]["a"])
		path.remove_at(0)
	while path.size() > 2 and float(edges[path[path.size() - 1]]["length"]) < 45.0:
		path.remove_at(path.size() - 1)
	if path.size() < 3:
		return -1
	for e: int in path:
		set_track_on_edge(e, TrackBuilder.BedStyle.MONORAIL, TrackMode.DOUBLE)
	# Stations: ~24m in from the dead end of each terminal edge
	var e0 := int(path[0])
	var e1 := int(path[path.size() - 1])
	var t0 := 24.0 / float(edges[e0]["length"])
	if int(edges[e0]["a"]) != na:
		t0 = 1.0 - t0
	var end_node := na
	for e: int in path:
		end_node = int(edges[e]["b"]) if int(edges[e]["a"]) == end_node else int(edges[e]["a"])
	var t1 := 24.0 / float(edges[e1]["length"])
	if int(edges[e1]["a"]) != end_node:
		t1 = 1.0 - t1
	var sa := add_station_on_edge(e0, t0, 0, "西湖中心站（单轨）", StationKind.ISLAND)
	var sb := add_station_on_edge(e1, t1, 0, "西雅图中心站（单轨）", StationKind.ISLAND)
	if sa < 0 or sb < 0:
		return -1
	# Two-way beam-switch crossover inward of each terminal for the turnback onto the other guideway
	for idx: Array in [range(1, path.size() - 1), range(path.size() - 2, 0, -1)]:
		for k: int in idx:
			if set_crossover_on_edge(int(path[k]), CrossoverType.DOUBLE) or set_crossover_on_edge(int(path[k]), CrossoverType.SINGLE):
				break
	var ids: Array[int] = [sa, sb, sa]
	return create_line(ids, model_key, 2, 2, "西雅图中心单轨")


# ---------------------------------------------------------------------------------------------
# Player road editing: new streets, removed streets, lane changes, and tram-only track across open ground.
# Every change is one op in road_edits, applied to the map graph in order (see import_state).
# ---------------------------------------------------------------------------------------------
const LANE_W := 3.3

static func road_width_for(lf: int, lb: int) -> float:
	var total := lf + lb
	var median := 1.6 if (lf > 0 and lb > 0 and total >= 4) else 0.0
	return float(total) * LANE_W + median + 2.2


# Right-of-way width of tram-only track laid across open ground
static func row_width_for(track_mode: int) -> float:
	if track_mode == TrackMode.QUAD:
		return 14.6
	return 7.6 if track_mode == TrackMode.DOUBLE else 4.4


func _restore_base_geometry() -> void:
	if _base_geo.is_empty():
		return
	nodes = (_base_geo["nodes"] as Dictionary).duplicate(true)
	edges = (_base_geo["edges"] as Dictionary).duplicate(true)
	adj = (_base_geo["adj"] as Dictionary).duplicate(true)
	_rebuild_edge_grid()


func _rebuild_edge_grid() -> void:
	_edge_grid.clear()
	for eid: int in edges.keys():
		var pts2: Array[Vector2] = []
		pts2.assign(edges[eid]["pts"])
		_insert_edge_into_grid(eid, pts2)


func _new_node_id() -> int:
	var m := -1
	for k: int in nodes.keys():
		m = maxi(m, k)
	return m + 1


func _new_edge_id() -> int:
	var m := -1
	for k: int in edges.keys():
		m = maxi(m, k)
	return m + 1


static func _polyline_length(pts: Array) -> float:
	var l := 0.0
	for i in range(pts.size() - 1):
		l += (pts[i] as Vector2).distance_to(pts[i + 1])
	return l


func _apply_road_op(op: Dictionary) -> bool:
	match str(op.get("op", "")):
		"node":
			var nid := int(op["id"])
			var pa: Array = op["pos"]
			nodes[nid] = {"id": nid, "pos": Vector2(float(pa[0]), float(pa[1])), "name": str(op.get("name", "新路口"))}
			if not adj.has(nid):
				adj[nid] = []
			return true
		"edge":
			var eid := int(op["id"])
			var a := int(op["a"])
			var b := int(op["b"])
			if not nodes.has(a) or not nodes.has(b):
				return false
			var pts2: Array[Vector2] = []
			for rp in op["pts"]:
				pts2.append(Vector2(float(rp[0]), float(rp[1])))
			var elen := _polyline_length(pts2)
			edges[eid] = {
				"id": eid, "a": a, "b": b,
				"name": str(op.get("name", "新建道路")),
				"width": float(op.get("width", 9.8)),
				"lanes_f": int(op.get("lf", 1)),
				"lanes_b": int(op.get("lb", 1)),
				"length": elen,
				"pts": pts2,
				"player": true,
			}
			if bool(op.get("no_cars", false)):
				edges[eid]["no_cars"] = true
				edges[eid]["lanes_f"] = 0
				edges[eid]["lanes_b"] = 0
			adj[a].append({"to": b, "edge_id": eid, "length": elen})
			adj[b].append({"to": a, "edge_id": eid, "length": elen})
			_insert_edge_into_grid(eid, pts2)
			return true
		"split":
			return _split_edge_now(int(op["eid"]), float(op["t"]), int(op["nid"]), int(op["eid2"]))
		"remove":
			var reid := int(op["eid"])
			if not edges.has(reid):
				return false
			var red: Dictionary = edges[reid]
			for end_n: int in [int(red["a"]), int(red["b"])]:
				var keep: Array = []
				for nb: Dictionary in adj.get(end_n, []):
					if int(nb["edge_id"]) != reid:
						keep.append(nb)
				adj[end_n] = keep
			edges.erase(reid)
			for end_n2: int in [int(red["a"]), int(red["b"])]:
				if (adj.get(end_n2, []) as Array).is_empty():
					adj.erase(end_n2)
					nodes.erase(end_n2)
			return true
		"lanes":
			var leid := int(op["eid"])
			if not edges.has(leid):
				return false
			edges[leid]["lanes_f"] = int(op["lf"])
			edges[leid]["lanes_b"] = int(op["lb"])
			edges[leid]["width"] = float(op["width"])
			return true
	return false


func _record(op: Dictionary) -> bool:
	if _apply_road_op(op):
		road_edits.append(op)
		return true
	return false


# Cut edge `eid` at polyline fraction t: it keeps a -> new node, a new edge `eid2` runs new node -> b.
# Track, stations and crossover move with the half they lie on.
func _split_edge_now(eid: int, t: float, nid: int, eid2: int) -> bool:
	if not edges.has(eid):
		return false
	var ed: Dictionary = edges[eid]
	var pts: Array = ed["pts"]
	var total := _polyline_length(pts)
	var target := clampf(t, 0.02, 0.98) * total
	var first: Array[Vector2] = [pts[0]]
	var second: Array[Vector2] = []
	var acc := 0.0
	var cut := Vector2.ZERO
	var done := false
	for i in range(pts.size() - 1):
		var pa: Vector2 = pts[i]
		var pb: Vector2 = pts[i + 1]
		var sl := pa.distance_to(pb)
		if not done and acc + sl >= target:
			cut = pa.lerp(pb, clampf((target - acc) / maxf(sl, 0.0001), 0.0, 1.0))
			first.append(cut)
			second.append(cut)
			done = true
		elif not done:
			first.append(pb)
		if done and second.back() != pb:
			second.append(pb)
		acc += sl
	if not done or second.size() < 2:
		return false
	var b := int(ed["b"])
	nodes[nid] = {"id": nid, "pos": cut, "name": str(ed["name"])}
	adj[nid] = []
	var l1 := _polyline_length(first)
	var l2 := _polyline_length(second)
	ed["pts"] = first
	ed["b"] = nid
	ed["length"] = l1
	var ed2 := ed.duplicate(true)
	ed2["id"] = eid2
	ed2["a"] = nid
	ed2["b"] = b
	ed2["pts"] = second
	ed2["length"] = l2
	edges[eid2] = ed2
	for nb: Dictionary in adj[int(ed["a"])]:
		if int(nb["edge_id"]) == eid:
			nb["to"] = nid
			nb["length"] = l1
	var keep_b: Array = []
	for nb2: Dictionary in adj[b]:
		if int(nb2["edge_id"]) == eid:
			keep_b.append({"to": nid, "edge_id": eid2, "length": l2})
		else:
			keep_b.append(nb2)
	adj[b] = keep_b
	adj[nid] = [{"to": int(ed["a"]), "edge_id": eid, "length": l1}, {"to": b, "edge_id": eid2, "length": l2}]
	_rebuild_edge_grid()
	var tf := target / maxf(total, 0.001)
	if built_tracks.has(eid):
		built_tracks[eid2] = built_tracks[eid]
		built_track_modes[eid2] = built_track_modes.get(eid, TrackMode.SINGLE)
	for sid: int in stations.keys():
		var st: Dictionary = stations[sid]
		if int(st["edge_id"]) != eid:
			continue
		var st_t := float(st["t"])
		if st_t < tf:
			st["t"] = st_t / tf
		else:
			st["edge_id"] = eid2
			st["t"] = (st_t - tf) / maxf(1.0 - tf, 0.001)
		var smp := sample_edge(int(st["edge_id"]), float(st["t"]))
		st["pos"] = smp["pos"]
		st["fwd"] = smp["fwd"]
	if crossovers.has(eid):
		var xt := float(crossover_t.get(eid, 0.5))
		var xtype := int(crossovers[eid])
		crossovers.erase(eid)
		crossover_t.erase(eid)
		if xt < tf:
			set_crossover_on_edge(eid, xtype, xt / tf)
		else:
			set_crossover_on_edge(eid2, xtype, (xt - tf) / maxf(1.0 - tf, 0.001))
	return true


# Node for a clicked point: an existing junction within snap_r, else a cut in the nearest street within snap_r
# (refused inside a platform), else a new free node. Returns {nid} or {error}.
func node_for_point(xz: Vector2, snap_r: float = 9.0) -> Dictionary:
	var nid := find_closest_node(xz, snap_r)
	if nid >= 0:
		return {"nid": nid}
	var hit := find_closest_edge(xz, snap_r * 0.8, false)
	if not hit.is_empty():
		var eid := int(hit["edge_id"])
		var t := float(hit["t"])
		var len_e := float(edges[eid]["length"])
		if t * len_e < 6.0 or (1.0 - t) * len_e < 6.0:
			return {"nid": int(edges[eid]["a"]) if t < 0.5 else int(edges[eid]["b"])}
		for sid: int in stations.keys():
			var st: Dictionary = stations[sid]
			if int(st["edge_id"]) == eid and absf(float(st["t"]) - t) * len_e < float(st.get("platform_len", 27.0)) * 0.5 + 6.0:
				return {"error": "on_station"}
		if crossovers.has(eid) and absf(float(crossover_t.get(eid, 0.5)) - t) * len_e < 26.0:
			return {"error": "on_crossover"}
		var new_n := _new_node_id()
		var new_e := _new_edge_id()
		if _record({"op": "split", "eid": eid, "t": t, "nid": new_n, "eid2": new_e}):
			return {"nid": new_n}
		return {"error": "split_failed"}
	var free_n := _new_node_id()
	_record({"op": "node", "id": free_n, "pos": [xz.x, xz.y]})
	return {"nid": free_n}


# New street (or tram-only right of way when no_cars) from node a to node b. Returns the edge id or -1.
func add_road(a: int, b: int, lf: int, lb: int, no_cars: bool = false, track_mode: int = TrackMode.DOUBLE, name: String = "") -> int:
	if a == b or not nodes.has(a) or not nodes.has(b):
		return -1
	for nb: Dictionary in adj.get(a, []):
		if int(nb["to"]) == b:
			return -1 # already connected
	var pa: Vector2 = nodes[a]["pos"]
	var pb: Vector2 = nodes[b]["pos"]
	if pa.distance_to(pb) < 8.0:
		return -1
	var eid := _new_edge_id()
	var w := row_width_for(track_mode) if no_cars else road_width_for(lf, lb)
	var nm := name
	if nm.is_empty():
		nm = "专用轨道" if no_cars else "新建道路"
	if not _record({"op": "edge", "id": eid, "a": a, "b": b, "pts": [[pa.x, pa.y], [pb.x, pb.y]], "width": w,
			"lf": lf, "lb": lb, "name": nm, "no_cars": no_cars}):
		return -1
	return eid


# Remove a street: refused while it carries track ("has_track")
func remove_road(eid: int) -> String:
	if not edges.has(eid):
		return "no_edge"
	if built_tracks.has(eid):
		return "has_track"
	_record({"op": "remove", "eid": eid})
	return "ok"


# Tram-only track across open ground is removed together with its right of way
func remove_offroad_track(eid: int) -> void:
	if not edges.has(eid) or not bool(edges[eid].get("no_cars", false)):
		return
	remove_track_on_edge(eid)
	_record({"op": "remove", "eid": eid})


func set_road_lanes(eid: int, lf: int, lb: int) -> bool:
	if not edges.has(eid) or bool(edges[eid].get("no_cars", false)) or lf + lb < 1:
		return false
	var w := maxf(road_width_for(lf, lb), 6.0)
	return _record({"op": "lanes", "eid": eid, "lf": lf, "lb": lb, "width": w})


func demolish_building(bi: int) -> void:
	demolished_buildings[bi] = true


# Signature of everything that changes the road surface / building layer (for rebuilding the city only when needed)
func land_edit_signature() -> String:
	return "%d:%d:%s" % [road_edits.size(), demolished_buildings.size(), str(road_edits.back() if not road_edits.is_empty() else "")]
