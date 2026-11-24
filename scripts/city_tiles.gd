class_name CityTiles
extends Node3D
# The big Seattle map: the v3 core (downtown / SLU / Seattle Center) is built in full at load by CityBuilder;
# everything around it (Fremont, Wallingford, UW, Queen Anne, Capitol Hill, Central District, SoDo ...) is cut
# into TILE x TILE m tiles that are built on a worker thread, nearest to the camera first, and swapped in
# when ready. Each tile is a Node3D with the same child names CityBuilder uses (Buildings, Roads,
# StreetlampPosts, ParksAndLandscape ...), so track clearance and station kerb bays work on it unchanged.
# Player land edits re-cut the data; only tiles whose content changed are rebuilt.

const TILE := 480.0
const CORE_PAD := 40.0
const CONTEXT_PAD := 30.0

var core_rect := Rect2()
var focus := Vector3.ZERO # camera position: nearest tiles are built first
var on_tile_built: Callable # main: (tile_root: Node3D) -> void (clearance, kerb bays, lights, night materials)

var _mats := {}
var _tiles := {} # Vector2i -> {"data": Dictionary, "sig": int, "built_sig": int, "node": Node3D}
var _clear_idx := {}
var _station_bays: Array = []
var track_ctx_ver := 0
var _task_id := -1
var _task_key := Vector2i.ZERO
var _task_sig := 0
var _task_result: Node3D = null
# Real terrain: a finished tile is draped on the main thread (reading meshes back from the RenderingServer is
# instant there, but waits a frame per call on a worker), a few milliseconds per frame, then swapped in
var _drape := {} # {"key", "node", "sig", "queue": Array[Node]} while one is in progress
const DRAPE_BUDGET_MS := 2.0
var _swap_cooldown := 0
const SWAP_COOLDOWN_FRAMES := 4


static func has_tiles(map_data: Dictionary) -> bool:
	return map_data.has("core_bounds")


static func core_rect_of(map_data: Dictionary) -> Rect2:
	var cb: Array = map_data.get("core_bounds", [0, 0, 0, 0])
	var r := Rect2(float(cb[0]), float(cb[1]), float(cb[2]) - float(cb[0]), float(cb[3]) - float(cb[1]))
	return r.grow(CORE_PAD)


static func _pt(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


static func _poly_centre(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += _pt(p)
	return c / float(maxi(1, pts.size()))


static func _road_mid(r: Dictionary) -> Vector2:
	var pts: Array = r.get("pts", [])
	if pts.is_empty():
		return Vector2.ZERO
	return (_pt(pts[0]) + _pt(pts[pts.size() - 1])) * 0.5


static func _fw_mid(f: Dictionary) -> Vector2:
	var pts: Array = f.get("pts", [])
	if pts.is_empty():
		return Vector2.ZERO
	var m = pts[pts.size() / 2]
	return Vector2(float(m[0]), float(m[1]))


static func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


# The part of the map the core build covers: generic layers restricted to the core rectangle. Buildings keep
# their indices (others become empty placeholders) so storefront building indices stay valid.
static func core_subset(map_data: Dictionary) -> Dictionary:
	if not has_tiles(map_data):
		return map_data
	var cr := core_rect_of(map_data)
	var d := map_data.duplicate(false)
	var blds: Array = []
	for b: Dictionary in map_data.get("buildings", []):
		var pts: Array = b.get("pts", [])
		blds.append(b if (pts.size() >= 3 and cr.has_point(_poly_centre(pts))) else {"pts": [], "h": 0.0})
	d["buildings"] = blds
	var roads: Array = []
	for r: Dictionary in map_data.get("roads", []):
		if cr.has_point(_road_mid(r)):
			roads.append(r)
	d["roads"] = roads
	for key: String in ["crosswalks"]:
		var lst: Array = []
		for it: Dictionary in map_data.get(key, []):
			if cr.has_point(_pt(it["pos"])):
				lst.append(it)
		d[key] = lst
	for key: String in ["streetlamps", "trees"]:
		var lst2: Array = []
		for p in map_data.get(key, []):
			if cr.has_point(_pt(p)):
				lst2.append(p)
		d[key] = lst2
	var sfs: Array = []
	for sf: Dictionary in map_data.get("storefronts", []):
		var bi := int(sf.get("b", -1))
		if bi >= 0 and bi < blds.size() and ((blds[bi] as Dictionary).get("pts", []) as Array).size() >= 3:
			sfs.append(sf)
	d["storefronts"] = sfs
	# Parks / woods of the outer map are detailed (paths, groves, benches) by their tiles
	var park_areas: Array = []
	for a: Dictionary in map_data.get("areas", []):
		if cr.has_point(_poly_centre(a.get("pts", []))):
			park_areas.append(a)
	d["park_areas"] = park_areas
	var fills: Array = []
	for a2: Dictionary in map_data.get("areas", []):
		if str(a2.get("kind", "")) == "water" or cr.has_point(_poly_centre(a2.get("pts", []))):
			fills.append(a2)
	d["fill_areas"] = fills
	var piers: Array = []
	for pr: Dictionary in map_data.get("piers", []):
		if cr.has_point(_poly_centre(pr.get("pts", []))):
			piers.append(pr)
	d["piers"] = piers
	var fws: Array = []
	for f: Dictionary in map_data.get("freeways", []):
		if cr.has_point(_fw_mid(f)):
			fws.append(f)
	d["freeways"] = fws
	return d


func setup(map_data: Dictionary, mats: Dictionary) -> void:
	_mats = mats
	core_rect = core_rect_of(map_data)
	update_data(map_data)


# Snapshot track clearance & station bays so worker threads bake kerb bays + track clearance off the main thread!
func set_track_context(clear_idx: Dictionary, bays: Array) -> void:
	_clear_idx = clear_idx
	_station_bays = bays.duplicate(false)
	track_ctx_ver += 1
	if not clear_idx.is_empty():
		CityBuilder._touched_tiles(clear_idx, _station_bays) # pre-populate _touched_tiles cache on main thread


static func _bays_near_key(key: Vector2i, bays: Array) -> Array:
	if bays.is_empty():
		return []
	var out: Array = []
	var r := Rect2(Vector2(float(key.x), float(key.y)) * TILE, Vector2(TILE, TILE)).grow(60.0)
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		if r.has_point(Vector2(bp.x, bp.z)):
			out.append(bay)
	return out


# Re-cut the (possibly edited) map into tiles; tiles whose content changed are queued for a rebuild
func update_data(map_data: Dictionary) -> void:
	var cuts := _cut_tiles(map_data)
	for key: Vector2i in _tiles.keys():
		if not cuts.has(key):
			var t: Dictionary = _tiles[key]
			if is_instance_valid(t.get("node")):
				(t["node"] as Node).queue_free()
			_tiles.erase(key)
	for key: Vector2i in cuts.keys():
		var td: Dictionary = cuts[key]
		var sig := _data_sig(td)
		if _tiles.has(key):
			var t: Dictionary = _tiles[key]
			t["data"] = td
			t["sig"] = sig
		else:
			_tiles[key] = {"data": td, "sig": sig, "built_sig": -1, "node": null}


func _cut_tiles(map_data: Dictionary) -> Dictionary:
	var cr := core_rect
	var cuts := {}
	var get_t := func(key: Vector2i) -> Dictionary:
		if not cuts.has(key):
			cuts[key] = {"key": key, "buildings": [], "storefronts": [], "roads": [], "context": [], "crosswalks": [],
				"streetlamps": [], "trees": [], "areas": [], "piers": [], "fills": [], "freeways": []}
		return cuts[key]
	# Buildings (local indices; storefronts follow their building)
	var blds: Array = map_data.get("buildings", [])
	var b_local := {} # global index -> [tile key, local index]
	for bi in range(blds.size()):
		var b: Dictionary = blds[bi]
		var pts: Array = b.get("pts", [])
		if pts.size() < 3:
			continue
		var c := _poly_centre(pts)
		if cr.has_point(c):
			continue
		var t: Dictionary = get_t.call(_tile_of(c))
		b_local[bi] = [t["key"], (t["buildings"] as Array).size()]
		(t["buildings"] as Array).append(b)
	for sf: Dictionary in map_data.get("storefronts", []):
		var bi := int(sf.get("b", -1))
		if not b_local.has(bi):
			continue
		var t2: Dictionary = cuts[b_local[bi][0]]
		var sf2 := sf.duplicate()
		sf2["b"] = int(b_local[bi][1])
		(t2["storefronts"] as Array).append(sf2)
	# Streets: one map-wide height level per street (core streets first, as the core build orders them)
	var roads: Array = map_data.get("roads", [])
	var core_roads: Array = []
	var ext_roads: Array = []
	for r: Dictionary in roads:
		if cr.has_point(_road_mid(r)):
			core_roads.append(r)
		else:
			ext_roads.append(r)
	# Outer streets in a stable spatial order (map order and edited-graph order differ), so a street edit
	# only re-levels the streets around it
	ext_roads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := _road_mid(a)
		var mb := _road_mid(b)
		return ma.x < mb.x if absf(ma.x - mb.x) > 0.05 else ma.y < mb.y)
	# Height levels for the outer streets only, offset above the core's own (0..2 in practice): independent of
	# how the core streets are ordered, and never coplanar with a core street at the seam
	var all_r: Array = core_roads + ext_roads
	var levels := CityBuilder._road_height_levels(ext_roads)
	var lv_roads: Array = []
	for i in range(all_r.size()):
		var r2: Dictionary = (all_r[i] as Dictionary).duplicate()
		if i >= core_roads.size():
			r2["lv"] = mini(3 + levels[i - core_roads.size()], 7)
		lv_roads.append(r2)
	var road_grid := {} # 120 m cells -> road indices into lv_roads (for context lookups)
	for i in range(lv_roads.size()):
		var rr: Dictionary = lv_roads[i]
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in rr.get("pts", []):
			mn = mn.min(_pt(p))
			mx = mx.max(_pt(p))
		rr["_bb"] = Rect2(mn, mx - mn)
		for gx in range(int(floor(mn.x / 120.0)), int(floor(mx.x / 120.0)) + 1):
			for gz in range(int(floor(mn.y / 120.0)), int(floor(mx.y / 120.0)) + 1):
				var gk := Vector2i(gx, gz)
				if not road_grid.has(gk):
					road_grid[gk] = []
				(road_grid[gk] as Array).append(i)
	var own_tile := {} # road index -> tile key
	for i in range(core_roads.size(), lv_roads.size()):
		var tk := _tile_of(_road_mid(lv_roads[i]))
		var t3: Dictionary = get_t.call(tk)
		(t3["roads"] as Array).append(lv_roads[i])
		own_tile[i] = tk
	for key: Vector2i in cuts.keys():
		var t4: Dictionary = cuts[key]
		if (t4["roads"] as Array).is_empty():
			continue
		var trect := Rect2(Vector2(key) * TILE, Vector2(TILE, TILE)).grow(CONTEXT_PAD)
		var seen := {}
		for gx in range(int(floor(trect.position.x / 120.0)), int(floor(trect.end.x / 120.0)) + 1):
			for gz in range(int(floor(trect.position.y / 120.0)), int(floor(trect.end.y / 120.0)) + 1):
				for ri: int in road_grid.get(Vector2i(gx, gz), []):
					if seen.has(ri):
						continue
					seen[ri] = true
					var r4: Dictionary = lv_roads[ri]
					if own_tile.get(ri, Vector2i(2147483647, 0)) != key and (r4["_bb"] as Rect2).intersects(trect):
						(t4["context"] as Array).append(r4)
	for key2: String in ["crosswalks"]:
		for it: Dictionary in map_data.get(key2, []):
			var p2 := _pt(it["pos"])
			if not cr.has_point(p2):
				(get_t.call(_tile_of(p2))[key2] as Array).append(it)
	for key3: String in ["streetlamps", "trees"]:
		for p3 in map_data.get(key3, []):
			var v := _pt(p3)
			if not cr.has_point(v):
				(get_t.call(_tile_of(v))[key3] as Array).append(p3)
	# Parks / woods are detailed by the tile holding their centre; water near a tile is clearance only
	for a: Dictionary in map_data.get("areas", []):
		var apts: Array = a.get("pts", [])
		if apts.size() < 3:
			continue
		var ac := _poly_centre(apts)
		if cr.has_point(ac):
			continue
		var kind := str(a.get("kind", ""))
		if kind != "water":
			(get_t.call(_tile_of(ac))["fills"] as Array).append(a)
		if kind in ["park", "grass", "wood", "meadow", "garden"]:
			(get_t.call(_tile_of(ac))["areas"] as Array).append(a)
	for pr: Dictionary in map_data.get("piers", []):
		var pc := _poly_centre(pr.get("pts", []))
		if not cr.has_point(pc):
			(get_t.call(_tile_of(pc))["piers"] as Array).append(pr)
	for f: Dictionary in map_data.get("freeways", []):
		var fm := _fw_mid(f)
		if not cr.has_point(fm):
			(get_t.call(_tile_of(fm))["freeways"] as Array).append(f)
	# Water touching a tile: clearance only (no trees / benches / flower beds on lakes and reservoirs)
	for a2: Dictionary in map_data.get("areas", []):
		if str(a2.get("kind", "")) != "water":
			continue
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p4 in a2.get("pts", []):
			mn = mn.min(_pt(p4))
			mx = mx.max(_pt(p4))
		var t0 := _tile_of(mn)
		var t1 := _tile_of(mx)
		for tx in range(t0.x, t1.x + 1):
			for tz in range(t0.y, t1.y + 1):
				var kk := Vector2i(tx, tz)
				if cuts.has(kk):
					((cuts[kk] as Dictionary)["areas"] as Array).append(a2)
	return cuts


# Content fingerprint on values rounded to 5 cm (edited streets come back from the graph as float32)
static func _data_sig(td: Dictionary) -> int:
	var h := 17
	for b: Dictionary in td["buildings"]:
		var pts: Array = b.get("pts", [])
		var p0 := _pt(pts[0]) if not pts.is_empty() else Vector2.ZERO
		h = hash([h, pts.size(), roundi(p0.x * 20.0), roundi(p0.y * 20.0), roundi(float(b.get("h", 0)) * 10.0)])
	for r: Dictionary in td["roads"]:
		h = hash([h, _road_key(r), int(r.get("lanes_f", 1)), int(r.get("lanes_b", 1)), int(r.get("lv", 0))])
	for r2: Dictionary in td["context"]:
		h = hash([h, _road_key(r2)])
	h = hash([h, Terrain._graded_sig, (td["crosswalks"] as Array).size(), (td["storefronts"] as Array).size(), (td["streetlamps"] as Array).size(), (td["piers"] as Array).size(), (td["fills"] as Array).size(), (td["freeways"] as Array).size()])
	return h


static func _road_key(r: Dictionary) -> Array:
	var pts: Array = r.get("pts", [])
	var k: Array = [pts.size(), roundi(float(r.get("width", 0)) * 10.0)]
	for p in pts:
		k.append(roundi(float(p[0]) * 20.0))
		k.append(roundi(float(p[1]) * 20.0))
	return k


# Builds one tile's subtree off the scene tree (runs on a worker thread)
static func build_tile_node(
	td: Dictionary,
	mats: Dictionary,
	bays: Array = [],
	clear_idx: Dictionary = {},
	ctx_ver: int = -1
) -> Node3D:
	var key: Vector2i = td["key"]
	var root := Node3D.new()
	root.name = "Tile_%d_%d" % [key.x, key.y]
	if not (td["fills"] as Array).is_empty():
		CityBuilder._build_areas(root, td["fills"]) # lawns, plazas, parking, playing fields of this tile
	var blds: Array = td["buildings"]
	if not blds.is_empty():
		CityBuilder._build_buildings(root, blds, mats["building"])
		var shop_mat := StorefrontBuilder.build_storefronts(root, td["storefronts"], blds)
		if shop_mat != null:
			root.set_meta("shop_mat", shop_mat)
	var roads: Array = td["roads"]
	if not roads.is_empty():
		CityBuilder._build_roads_and_curbs(root, roads + (td["context"] as Array), td["crosswalks"], mats["road"], roads.size(), bays, clear_idx)
		FreewayBuilder.build_street_bridges(root, roads)
	if not (td["freeways"] as Array).is_empty():
		FreewayBuilder.build(root, td["freeways"], mats["road"], roads + (td["context"] as Array), clear_idx)
	var lights: Array = []
	if not (td["streetlamps"] as Array).is_empty():
		for l in CityBuilder._build_streetlamps(root, td["streetlamps"], mats["globe"]):
			lights.append(l)
	if not (td["trees"] as Array).is_empty() or not (td["areas"] as Array).is_empty():
		ParkLandscapeBuilder.build_all_parks_and_trees(root, {
			"key": "tile",
			"areas": td["areas"],
			"roads": roads + (td["context"] as Array),
			"buildings": blds,
			"trees": td["trees"],
		}, lights, mats["globe"])
	if not (td["piers"] as Array).is_empty():
		SeattleV2Landmarks._piers(root, td["piers"])
	if ctx_ver >= 0 and not clear_idx.is_empty():
		CityBuilder.apply_track_clearance(root, clear_idx, bays)
		root.set_meta("clear_ctx_ver", ctx_ver)
	root.set_meta("lights", lights)
	_apply_visibility_ranges(root)
	return root


# Distance culling for everything in a tile (detail fades out first, building masses last)
static func _apply_visibility_ranges(n: Node) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			var gi := ch as GeometryInstance3D
			if gi.visibility_range_end <= 0.0:
				var nm := str(gi.name)
				var far := 1500.0
				if nm in ["Buildings", "HouseRoofs"]:
					far = 2700.0
				elif nm == "BuildingFrames3D":
					far = 650.0
				elif nm == "Roads":
					far = 2200.0
				elif nm == "Sidewalks":
					far = 550.0
				elif nm in ["GraniteCurbs", "RoadMarkings", "RoadCentreLines", "StationKerbBays", "ParkGraniteCurbs"]:
					far = 450.0
				elif nm.begins_with("Storefront") or nm.begins_with("Streetlamp"):
					far = 300.0
				elif nm in ["PierPiles", "PierEdgeBeams"]:
					far = 260.0
				elif nm in ["FreewayDecks", "FreewayConcrete", "FreewaySteel"]:
					far = 2700.0
				elif nm == "FreewayLines":
					far = 600.0
				elif nm == "StreetBridgeStructure":
					far = 1500.0
				gi.visibility_range_end = far
				gi.visibility_range_end_margin = far * 0.06
				gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if ch.get_child_count() > 0:
			_apply_visibility_ranges(ch)


func _thread_build(td: Dictionary, near_bays: Array, clear_idx: Dictionary, ctx_ver: int) -> void:
	_task_result = build_tile_node(td, _mats, near_bays, clear_idx, ctx_ver)


# Called every frame by main: finish the tile in flight, then start the nearest tile that needs building
func step() -> void:
	if not _drape.is_empty():
		_drape_step()
		return
	if _swap_cooldown > 0:
		_swap_cooldown -= 1
		return
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_install(_task_key, _task_result, _task_sig)
		_task_result = null
		_swap_cooldown = SWAP_COOLDOWN_FRAMES
		return
	var key := _next_tile()
	if key == Vector2i(2147483647, 0):
		return
	var t: Dictionary = _tiles[key]
	_task_key = key
	_task_sig = int(t["sig"])
	var near_bays := _bays_near_key(key, _station_bays)
	_task_id = WorkerThreadPool.add_task(_thread_build.bind(t["data"], near_bays, _clear_idx, track_ctx_ver), false, "city tile")


func _next_tile() -> Vector2i:
	var best := Vector2i(2147483647, 0)
	var best_d := 1e18
	var f := Vector2(focus.x, focus.z)
	for key: Vector2i in _tiles.keys():
		var t: Dictionary = _tiles[key]
		if int(t["built_sig"]) == int(t["sig"]):
			continue
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * TILE
		var d := c.distance_squared_to(f)
		if d < best_d:
			best_d = d
			best = key
	return best


func _install(key: Vector2i, node: Node3D, sig: int) -> void:
	if node == null:
		return
	if not _tiles.has(key):
		node.queue_free()
		return
	if Terrain.active and not node.has_meta("on_terrain"):
		var q: Array = []
		_collect_drape_queue(node, q)
		if q.is_empty():
			node.set_meta("on_terrain", true)
			_swap_in(key, node, sig)
			return
		# put remaining nodes on the ground first (hidden, over the next frames), then swap it in
		node.visible = false
		add_child(node)
		_drape = {"key": key, "node": node, "sig": sig, "queue": q}
		return
	_swap_in(key, node, sig)


static func _collect_drape_queue(parent: Node, q: Array) -> void:
	for ch in parent.get_children():
		if ch.has_meta("on_terrain"):
			continue
		if ch.get_class() == "Node3D":
			var n3 := ch as Node3D
			if n3.get_child_count() == 0:
				continue
			if n3.has_meta("drape_vertices") or n3.transform.origin.length_squared() < 0.01:
				n3.set_meta("on_terrain", true)
				_collect_drape_queue(n3, q)
				continue
		q.append(ch)


func _drape_step(budget_ms: float = DRAPE_BUDGET_MS) -> void:
	var t0 := Time.get_ticks_usec()
	var q: Array = _drape["queue"]
	while not q.is_empty() and float(Time.get_ticks_usec() - t0) < budget_ms * 1000.0:
		var ch: Node = q.pop_front()
		if is_instance_valid(ch):
			Terrain._drape_node(ch, Transform3D.IDENTITY)
	if q.is_empty():
		var node: Node3D = _drape["node"]
		var key: Vector2i = _drape["key"]
		var sig: int = _drape["sig"]
		_drape = {}
		node.set_meta("on_terrain", true)
		if is_instance_valid(node):
			_swap_in(key, node, sig)


func _swap_in(key: Vector2i, node: Node3D, sig: int) -> void:
	if not _tiles.has(key):
		node.queue_free()
		return
	node.visible = true
	var t: Dictionary = _tiles[key]
	if is_instance_valid(t.get("node")):
		(t["node"] as Node).queue_free()
	if node.get_parent() != self:
		add_child(node)
	t["node"] = node
	t["built_sig"] = sig
	if on_tile_built.is_valid():
		on_tile_built.call(node)


# Waits for the tile in flight (before the main thread touches shared builder caches, or for tests)
func finish_pending() -> void:
	if not _drape.is_empty():
		_drape_step(1e9)
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_install(_task_key, _task_result, _task_sig)
		_task_result = null
	if not _drape.is_empty():
		_drape_step(1e9)


# Builds every remaining tile right now on the calling thread (headless tests / screenshots)
func build_all_now() -> void:
	finish_pending()
	while true:
		var key := _next_tile()
		if key == Vector2i(2147483647, 0):
			break
		var t: Dictionary = _tiles[key]
		var near_bays := _bays_near_key(key, _station_bays)
		_install(key, build_tile_node(t["data"], _mats, near_bays, _clear_idx, track_ctx_ver), int(t["sig"]))
		if not _drape.is_empty():
			_drape_step(1e9)


func tile_count() -> int:
	return _tiles.size()


func built_count() -> int:
	var n := 0
	for t: Dictionary in _tiles.values():
		if int(t["built_sig"]) == int(t["sig"]):
			n += 1
	return n


func near_unbuilt_count(center: Vector3, radius_m: float = 1450.0) -> int:
	var f := Vector2(center.x, center.z)
	var r2 := radius_m * radius_m
	var n := 0
	for key: Vector2i in _tiles.keys():
		var t: Dictionary = _tiles[key]
		if int(t["built_sig"]) == int(t["sig"]):
			continue
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * TILE
		if c.distance_squared_to(f) <= r2:
			n += 1
	return n


# Advance one non-blocking prewarm tick during the loading overlay (no swap cooldown, builds nearest tiles within radius_m).
# Returns true while prewarming is still in progress, false once all tiles within radius_m are installed.
func prewarm_step(center: Vector3, radius_m: float = 1450.0) -> bool:
	focus = center
	_swap_cooldown = 0
	if not _drape.is_empty():
		_drape_step(10.0)
		return true
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return true
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_install(_task_key, _task_result, _task_sig)
		_task_result = null
		if not _drape.is_empty():
			return true
	var key := _next_tile()
	if key == Vector2i(2147483647, 0):
		return false
	var f := Vector2(center.x, center.z)
	var c := (Vector2(key) + Vector2(0.5, 0.5)) * TILE
	if c.distance_squared_to(f) > radius_m * radius_m:
		return false
	var t: Dictionary = _tiles[key]
	_task_key = key
	_task_sig = int(t["sig"])
	var near_bays := _bays_near_key(key, _station_bays)
	_task_id = WorkerThreadPool.add_task(_thread_build.bind(t["data"], near_bays, _clear_idx, track_ctx_ver), false, "city tile")
	return true


func _exit_tree() -> void:
	_drape = {}
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	if _task_result != null:
		_task_result.free() # built but never installed (map changed / game quit mid-build)
		_task_result = null
