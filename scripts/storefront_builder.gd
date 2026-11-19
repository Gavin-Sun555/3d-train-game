class_name StorefrontBuilder
extends RefCounted

# Real ground-floor shopfronts placed from OpenStreetMap POIs (see tools/osm_storefronts.py):
# pilasters, granite bulkhead, framed display glazing with a lit parallax shop interior, entrance
# doors, a fascia sign carrying the real shop name, plus awnings / blade signs / planters by type.
# All frames are batched into one vertex-coloured mesh; all glazing into one shader mesh.

const WALK_Y := 0.192 # sidewalk top (kerb height)
const INTERIOR_CAFE := 0
const INTERIOR_RETAIL := 1
const INTERIOR_OFFICE := 2
const INTERIOR_GROCERY := 3
const INTERIOR_BAR := 4

# Brand sign treatments (approximate real colour schemes). Keys are lower-case brand / name.
#   bg: fascia board, fg: lettering, frame: shopfront framing, letters: raised letters on stone (no board)
const BRANDS := {
	"starbucks": {"bg": Color(0.0, 0.38, 0.25), "fg": Color(1, 1, 1), "frame": Color(0.16, 0.12, 0.09), "awning": Color(0.0, 0.32, 0.21)},
	"mcdonald's": {"bg": Color(0.80, 0.08, 0.08), "fg": Color(1.0, 0.78, 0.05), "frame": Color(0.2, 0.2, 0.2)},
	"walgreens": {"bg": Color(0.93, 0.93, 0.92), "fg": Color(0.86, 0.08, 0.14), "frame": Color(0.25, 0.25, 0.27)},
	"cvs pharmacy": {"bg": Color(0.93, 0.93, 0.92), "fg": Color(0.80, 0.0, 0.0), "frame": Color(0.25, 0.25, 0.27)},
	"7-eleven": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.0, 0.5, 0.3), "frame": Color(0.9, 0.4, 0.1)},
	"zara": {"letters": true, "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.08, 0.08, 0.08)},
	"uniqlo": {"bg": Color(0.86, 0.0, 0.07), "fg": Color(1, 1, 1), "frame": Color(0.9, 0.9, 0.9)},
	"sephora": {"bg": Color(0.04, 0.04, 0.04), "fg": Color(1, 1, 1), "frame": Color(0.06, 0.06, 0.06)},
	"old navy": {"bg": Color(0.06, 0.16, 0.36), "fg": Color(1, 1, 1), "frame": Color(0.85, 0.85, 0.85)},
	"nordstrom rack": {"bg": Color(0.97, 0.97, 0.97), "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.1, 0.1, 0.1)},
	"barnes & noble": {"bg": Color(0.08, 0.25, 0.17), "fg": Color(0.95, 0.91, 0.80), "frame": Color(0.10, 0.20, 0.14)},
	"urban outfitters": {"letters": true, "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.12, 0.12, 0.12)},
	"allsaints": {"bg": Color(0.06, 0.06, 0.06), "fg": Color(0.95, 0.95, 0.95), "frame": Color(0.08, 0.08, 0.08)},
	"dr. martens": {"bg": Color(0.05, 0.05, 0.05), "fg": Color(1.0, 0.85, 0.1), "frame": Color(0.05, 0.05, 0.05)},
	"patagonia": {"letters": true, "fg": Color(0.08, 0.08, 0.1), "frame": Color(0.30, 0.22, 0.15)},
	"carhartt": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.95, 0.66, 0.10), "frame": Color(0.12, 0.12, 0.12)},
	"pandora": {"bg": Color(0.97, 0.96, 0.95), "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.85, 0.80, 0.78)},
	"ben bridge": {"bg": Color(0.07, 0.12, 0.26), "fg": Color(0.95, 0.90, 0.75), "frame": Color(0.07, 0.12, 0.26)},
	"cartier": {"bg": Color(0.45, 0.06, 0.08), "fg": Color(0.95, 0.85, 0.55), "frame": Color(0.75, 0.68, 0.55)},
	"eileen fisher": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.75, 0.72, 0.68)},
	"men's wearhouse": {"bg": Color(0.10, 0.12, 0.18), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.12)},
	"t-mobile": {"bg": Color(0.89, 0.0, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"metro by t-mobile": {"bg": Color(0.36, 0.12, 0.62), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"verizon": {"bg": Color(0.03, 0.03, 0.03), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.1)},
	"at&t": {"bg": Color(0.0, 0.62, 0.86), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"chase": {"bg": Color(0.07, 0.36, 0.67), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"wells fargo": {"bg": Color(0.80, 0.05, 0.12), "fg": Color(1.0, 0.80, 0.15), "frame": Color(0.30, 0.25, 0.22)},
	"bank of america": {"bg": Color(0.0, 0.18, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"u.s. bank": {"bg": Color(0.05, 0.18, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"hsbc": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.86, 0.0, 0.07), "frame": Color(0.25, 0.25, 0.27)},
	"keybank": {"bg": Color(0.80, 0.08, 0.15), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"wafd bank": {"bg": Color(0.0, 0.25, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"umpqua bank": {"bg": Color(0.10, 0.30, 0.22), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"becu": {"bg": Color(0.0, 0.32, 0.60), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"chipotle": {"bg": Color(0.27, 0.10, 0.07), "fg": Color(0.95, 0.90, 0.82), "frame": Color(0.45, 0.36, 0.28)},
	"subway": {"bg": Color(0.0, 0.50, 0.25), "fg": Color(1.0, 0.80, 0.0), "frame": Color(0.2, 0.2, 0.2)},
	"jimmy john's": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.75, 0.05, 0.05), "frame": Color(0.1, 0.1, 0.1)},
	"mod pizza": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.95, 0.95, 0.95), "frame": Color(0.3, 0.3, 0.3)},
	"taco del mar": {"bg": Color(0.95, 0.45, 0.05), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"veggie grill": {"bg": Color(0.30, 0.55, 0.15), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"evergreens": {"bg": Color(0.20, 0.42, 0.20), "fg": Color(1, 1, 1), "frame": Color(0.35, 0.28, 0.20)},
	"sweetgreen": {"bg": Color(0.85, 0.92, 0.82), "fg": Color(0.10, 0.30, 0.15), "frame": Color(0.75, 0.75, 0.72)},
	"shake shack": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.55, 0.80, 0.30), "frame": Color(0.3, 0.3, 0.3)},
	"potbelly": {"bg": Color(0.45, 0.10, 0.10), "fg": Color(1.0, 0.85, 0.5), "frame": Color(0.35, 0.22, 0.12)},
	"einstein bros. bagels": {"bg": Color(0.10, 0.25, 0.55), "fg": Color(1, 1, 1), "frame": Color(0.3, 0.3, 0.3)},
	"yard house": {"bg": Color(0.15, 0.12, 0.10), "fg": Color(0.95, 0.80, 0.50), "frame": Color(0.25, 0.18, 0.12)},
	"regal cinemas": {"bg": Color(0.70, 0.05, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.15, 0.15, 0.15)},
	"ace hardware": {"bg": Color(0.82, 0.08, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"amazon fresh": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.55, 0.80, 0.20), "frame": Color(0.2, 0.2, 0.2)},
	"west elm": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.15, 0.15, 0.15)},
	"aveda": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.6, 0.55, 0.45)},
	"indochino": {"bg": Color(0.08, 0.08, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.1)},
	"tous les jours": {"bg": Color(0.95, 0.95, 0.93), "fg": Color(0.10, 0.30, 0.25), "frame": Color(0.2, 0.3, 0.25)},
}

# Fallback palettes by shop category: [bg, fg, frame, awning]
const CAT_STYLES := {
	"food": [[Color(0.12, 0.10, 0.09), Color(0.96, 0.90, 0.78), Color(0.20, 0.14, 0.10), Color(0.48, 0.12, 0.10)],
		[Color(0.08, 0.20, 0.16), Color(0.95, 0.92, 0.84), Color(0.10, 0.18, 0.14), Color(0.10, 0.28, 0.20)],
		[Color(0.55, 0.12, 0.10), Color(1.0, 0.95, 0.85), Color(0.18, 0.18, 0.18), Color(0.62, 0.14, 0.12)],
		[Color(0.90, 0.86, 0.78), Color(0.20, 0.14, 0.10), Color(0.32, 0.22, 0.14), Color(0.20, 0.30, 0.45)]],
	"retail": [[Color(0.06, 0.06, 0.06), Color(1, 1, 1), Color(0.08, 0.08, 0.08), Color(0.1, 0.1, 0.1)],
		[Color(0.95, 0.95, 0.94), Color(0.08, 0.08, 0.08), Color(0.70, 0.70, 0.70), Color(0.2, 0.2, 0.2)],
		[Color(0.14, 0.18, 0.26), Color(0.95, 0.92, 0.84), Color(0.16, 0.18, 0.22), Color(0.14, 0.18, 0.26)],
		[Color(0.40, 0.32, 0.24), Color(1, 1, 1), Color(0.30, 0.22, 0.15), Color(0.40, 0.32, 0.24)]],
	"service": [[Color(0.12, 0.14, 0.18), Color(1, 1, 1), Color(0.22, 0.24, 0.27), Color(0.12, 0.14, 0.18)],
		[Color(0.92, 0.90, 0.88), Color(0.30, 0.20, 0.25), Color(0.60, 0.58, 0.56), Color(0.70, 0.45, 0.50)]],
	"bar": [[Color(0.08, 0.06, 0.05), Color(0.95, 0.75, 0.40), Color(0.12, 0.08, 0.05), Color(0.25, 0.10, 0.08)],
		[Color(0.10, 0.12, 0.10), Color(0.92, 0.88, 0.70), Color(0.10, 0.12, 0.10), Color(0.12, 0.22, 0.14)]],
}

const FOOD := ["cafe", "restaurant", "fast_food", "bakery", "deli", "ice_cream", "food_court", "confectionery", "chocolate", "cheese", "butcher", "greengrocer", "beverages"]
const BARS := ["bar", "pub", "nightclub", "alcohol"]
const GROCERY := ["convenience", "supermarket", "pharmacy", "chemist", "grocery", "doityourself", "hardware"]
const OFFICE := ["bank", "hotel", "optician", "hairdresser", "beauty", "tattoo", "dry_cleaning", "storage_rental", "telecommunication", "mobile_phone", "ticket"]


static func build_storefronts(parent: Node3D, storefronts: Array, buildings: Array) -> ShaderMaterial:
	if storefronts.is_empty():
		return null
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var labels := Node3D.new()
	labels.name = "StorefrontSigns"
	parent.add_child(labels)

	for sf: Dictionary in storefronts:
		var bi := int(sf.get("b", -1))
		var bh := 12.0
		if bi >= 0 and bi < buildings.size():
			bh = float((buildings[bi] as Dictionary).get("h", 12.0))
		_build_one(fst, gst, labels, sf, bh)

	var f_mi := MeshInstance3D.new()
	f_mi.name = "StorefrontFrames"
	f_mi.mesh = fst.commit()
	var f_mat := StandardMaterial3D.new()
	f_mat.vertex_color_use_as_albedo = true
	f_mat.roughness = 0.55
	f_mat.metallic = 0.25
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mi.material_override = f_mat
	parent.add_child(f_mi)

	var g_mat := ShaderMaterial.new()
	g_mat.shader = load("res://shaders/shopfront_glass.gdshader") as Shader
	var g_mi := MeshInstance3D.new()
	g_mi.name = "StorefrontGlazing"
	g_mi.mesh = gst.commit()
	g_mi.material_override = g_mat
	g_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g_mi)
	return g_mat


static func _style_for(sf: Dictionary) -> Dictionary:
	var kind := str(sf.get("kind", ""))
	var name := str(sf.get("name", ""))
	var key := str(sf.get("brand", "")).to_lower()
	if not BRANDS.has(key):
		key = name.to_lower()
	var h := absi(hash(name))
	var interior := INTERIOR_RETAIL
	var cat := "retail"
	if kind in FOOD:
		interior = INTERIOR_CAFE
		cat = "food"
	elif kind in BARS:
		interior = INTERIOR_BAR
		cat = "bar"
	elif kind in GROCERY:
		interior = INTERIOR_GROCERY
		cat = "service"
	elif kind in OFFICE:
		interior = INTERIOR_OFFICE
		cat = "service"
	var pal: Array = CAT_STYLES[cat][h % (CAT_STYLES[cat] as Array).size()]
	var st := {
		"bg": pal[0], "fg": pal[1], "frame": pal[2], "awning": pal[3], "letters": false,
		"interior": interior, "accent": (pal[3] as Color).lerp(Color(0.8, 0.7, 0.5), 0.3),
		"has_awning": (cat == "food" and h % 3 != 0) or (cat == "bar" and h % 2 == 0) or kind == "florist",
		"has_blade": (cat == "food" or cat == "bar") and h % 4 < 2,
		"planters": kind == "restaurant" and h % 3 == 0,
		"cafe_tables": kind == "cafe" and h % 2 == 0,
		"striped": cat == "food" and h % 5 == 0,
	}
	if BRANDS.has(key):
		var b: Dictionary = BRANDS[key]
		for k in b.keys():
			st[k] = b[k]
		st["accent"] = (st["bg"] as Color) if not bool(st["letters"]) else (st["frame"] as Color).lightened(0.4)
		st["has_awning"] = b.has("awning")
		st["has_blade"] = false
		st["striped"] = false
	if (st["bg"] as Color).get_luminance() < 0.05 and not bool(st["letters"]):
		st["accent"] = Color(0.75, 0.70, 0.62)
	return st


static func _build_one(fst: SurfaceTool, gst: SurfaceTool, labels: Node3D, sf: Dictionary, bh: float) -> void:
	var p0a: Array = sf["p0"]
	var p1a: Array = sf["p1"]
	var na: Array = sf["n"]
	var o := Vector3(float(p0a[0]), 0.0, float(p0a[1]))
	var e := Vector3(float(p1a[0]), 0.0, float(p1a[1])) - o
	var w := e.length()
	if w < 2.5:
		return
	var U := e / w
	var N := Vector3(float(na[0]), 0.0, float(na[1])).normalized()
	var st := _style_for(sf)
	var gh := 4.4 if bh >= 7.0 else clampf(bh - 0.8, 3.2, 4.0)
	var frame_c: Color = st["frame"]
	var bulk_c: Color = Color(0.20, 0.20, 0.21) if (absi(hash(str(sf["name"]))) % 2 == 0) else frame_c.darkened(0.25)
	var sign_y0 := gh - 1.05
	var sign_y1 := gh - 0.18
	var glass_top := sign_y0 - 0.06
	var has_awning := bool(st["has_awning"])
	if has_awning:
		glass_top = sign_y0 - 0.1
	var pil := 0.32
	var ctx := {"o": o, "u": U, "n": N, "st": fst}

	# Pilasters + bulkhead + fascia board
	_box(ctx, 0.0, pil, 0.0, sign_y0, 0.0, 0.30, frame_c)
	_box(ctx, w - pil, w, 0.0, sign_y0, 0.0, 0.30, frame_c)
	if bool(st["letters"]):
		# Stone fascia band with raised individual letters
		_box(ctx, 0.0, w, sign_y0, sign_y1, 0.0, 0.22, Color(0.80, 0.77, 0.72))
	else:
		_box(ctx, 0.08, w - 0.08, sign_y0, sign_y1, 0.0, 0.34, st["bg"])
		_box(ctx, 0.05, w - 0.05, sign_y1, sign_y1 + 0.05, 0.0, 0.38, frame_c.darkened(0.3))
		_box(ctx, 0.05, w - 0.05, sign_y0 - 0.04, sign_y0, 0.0, 0.38, frame_c.darkened(0.3))

	# Entrance door position (recessed double door for wide shops, single otherwise)
	var door_w := 1.9 if w >= 8.0 else 1.05
	var door_c := w * 0.5 if w < 7.0 else (w * 0.3 if absi(hash(str(sf["name"]))) % 2 == 0 else w * 0.7)
	var d0 := door_c - door_w * 0.5
	var d1 := door_c + door_w * 0.5
	var sill := 0.48
	# Bulkhead (skip under the door)
	_box(ctx, pil, d0, 0.0, sill, 0.0, 0.20, bulk_c)
	_box(ctx, d1, w - pil, 0.0, sill, 0.0, 0.20, bulk_c)
	_box(ctx, pil, d0, sill, sill + 0.05, 0.0, 0.24, frame_c.lightened(0.1))
	_box(ctx, d1, w - pil, sill, sill + 0.05, 0.0, 0.24, frame_c.lightened(0.1))
	# Glazing (shop windows + door glass), interior shader
	var col := Color((st["accent"] as Color).r, (st["accent"] as Color).g, (st["accent"] as Color).b, float(int(st["interior"])) / 255.0)
	_glass(gst, o, U, N, pil, d0, sill, glass_top, 0.10, col)
	_glass(gst, o, U, N, d1, w - pil, sill, glass_top, 0.10, col)
	_glass(gst, o, U, N, d0, d1, 0.02, glass_top, -0.25, col) # door set back into a shallow vestibule
	# Door vestibule: reveals, threshold, door frames, push bars, transom
	_box(ctx, d0 - 0.06, d0, 0.0, glass_top, -0.30, 0.30, frame_c)
	_box(ctx, d1, d1 + 0.06, 0.0, glass_top, -0.30, 0.30, frame_c)
	_box(ctx, d0, d1, 0.0, 0.03, -0.3, 0.2, Color(0.55, 0.53, 0.50))
	_box(ctx, d0, d1, 2.3, 2.38, -0.28, -0.20, frame_c)
	if door_w > 1.5:
		_box(ctx, door_c - 0.04, door_c + 0.04, 0.02, 2.3, -0.28, -0.19, frame_c)
	for hx: float in ([door_c - 0.22, door_c + 0.22] if door_w > 1.5 else [d1 - 0.18]):
		_box(ctx, hx - 0.02, hx + 0.02, 0.85, 1.25, -0.20, -0.14, Color(0.78, 0.78, 0.76))
	# Window mullions and transom bar
	var spans: Array = [[pil, d0], [d1, w - pil]]
	for sp: Array in spans:
		var a := float(sp[0])
		var b := float(sp[1])
		if b - a < 0.4:
			continue
		var n_m := maxi(1, int(round((b - a) / 2.2)))
		for k in range(1, n_m):
			var mu := lerpf(a, b, float(k) / float(n_m))
			_box(ctx, mu - 0.035, mu + 0.035, sill, glass_top, 0.0, 0.16, frame_c)
		_box(ctx, a, b, glass_top - 0.75, glass_top - 0.70, 0.0, 0.15, frame_c)
	_box(ctx, pil, w - pil, glass_top - 0.02, sign_y0, 0.0, 0.18, frame_c.darkened(0.15))

	# Sign lettering
	var name_txt := str(sf.get("name", ""))
	var letters := bool(st["letters"])
	var txt := name_txt.to_upper() if (letters or name_txt.length() <= 12) else name_txt
	var depth := 0.235 if letters else 0.355
	_sign_label(labels, o + U * (w * 0.5) + N * depth + Vector3.UP * ((sign_y0 + sign_y1) * 0.5), N, txt, w * 0.84, (sign_y1 - sign_y0) * 0.62, st["fg"], letters)

	# Awning (sloped fabric with valance; striped for some cafes)
	if has_awning:
		var aw_c: Color = st["awning"]
		var y_top := sign_y0 - 0.02
		var proj := 1.35
		var drop := 0.55
		var n_str := int(ceil((w - 0.2) / 0.55)) if bool(st["striped"]) else 1
		for k in range(n_str):
			var a0 := lerpf(0.1, w - 0.1, float(k) / float(n_str))
			var a1 := lerpf(0.1, w - 0.1, float(k + 1) / float(n_str))
			var c := aw_c if k % 2 == 0 else Color(0.94, 0.92, 0.86)
			_quad(fst, o + U * a0 + N * 0.3 + Vector3.UP * y_top, o + U * a1 + N * 0.3 + Vector3.UP * y_top,
				o + U * a1 + N * proj + Vector3.UP * (y_top - drop), o + U * a0 + N * proj + Vector3.UP * (y_top - drop), c)
			_quad(fst, o + U * a0 + N * proj + Vector3.UP * (y_top - drop), o + U * a1 + N * proj + Vector3.UP * (y_top - drop),
				o + U * a1 + N * proj + Vector3.UP * (y_top - drop - 0.26), o + U * a0 + N * proj + Vector3.UP * (y_top - drop - 0.26), c.darkened(0.12))
		for end_u: float in [0.1, w - 0.1]:
			_tri(fst, o + U * end_u + N * 0.3 + Vector3.UP * y_top, o + U * end_u + N * proj + Vector3.UP * (y_top - drop),
				o + U * end_u + N * 0.3 + Vector3.UP * (y_top - drop), aw_c.darkened(0.1))

	# Projecting blade sign
	if bool(st["has_blade"]) and bh >= 6.0:
		var bu := 0.16
		var by0 := gh + 0.25
		var by1 := gh + 1.35
		_box(ctx, bu - 0.04, bu + 0.04, by0, by1, 0.25, 1.15, st["bg"])
		_box(ctx, bu - 0.025, bu + 0.025, by1, by1 + 0.05, 0.0, 1.2, Color(0.1, 0.1, 0.1))
		var short := name_txt.split(" ")[0] if name_txt.length() > 10 else name_txt
		for sd: float in [-1.0, 1.0]:
			var lp := o + U * (bu + sd * 0.045) + N * 0.70 + Vector3.UP * ((by0 + by1) * 0.5)
			var lbl := _make_label(short, st["fg"], false)
			lbl.transform = Transform3D(_face_basis(U * sd), lp)
			_fit_label(lbl, short, 0.80, 0.5)
			labels.add_child(lbl)

	# Street furniture: planters / cafe tables / A-frame menu board
	if bool(st["planters"]):
		for pu: float in [d0 - 0.55, d1 + 0.55]:
			_box(ctx, pu - 0.4, pu + 0.4, 0.0 + WALK_Y, 0.55 + WALK_Y, 0.35, 0.85, Color(0.22, 0.22, 0.23))
			_box(ctx, pu - 0.36, pu + 0.36, 0.55 + WALK_Y, 0.85 + WALK_Y, 0.39, 0.81, Color(0.18, 0.36, 0.16))
	if bool(st["cafe_tables"]):
		for tu: float in [w * 0.22, w * 0.78]:
			if absf(tu - door_c) < door_w:
				continue
			_box(ctx, tu - 0.03, tu + 0.03, 0.0 + WALK_Y, 0.72 + WALK_Y, 0.95, 1.01, Color(0.12, 0.12, 0.12))
			_box(ctx, tu - 0.32, tu + 0.32, 0.72 + WALK_Y, 0.75 + WALK_Y, 0.66, 1.30, Color(0.80, 0.78, 0.74))
			for cu: float in [-0.55, 0.55]:
				_box(ctx, tu + cu - 0.2, tu + cu + 0.2, 0.44 + WALK_Y, 0.47 + WALK_Y, 0.80, 1.18, Color(0.15, 0.15, 0.15))
				_box(ctx, tu + cu + (0.18 if cu > 0.0 else -0.2), tu + cu + (0.2 if cu > 0.0 else -0.18), 0.44 + WALK_Y, 0.85 + WALK_Y, 0.80, 1.18, Color(0.15, 0.15, 0.15))
	if str(sf.get("kind", "")) in ["cafe", "bakery", "restaurant"] and absi(hash(name_txt)) % 4 == 1:
		var au := clampf(door_c + door_w * 0.5 + 0.6, 0.4, w - 0.4)
		_box(ctx, au - 0.3, au + 0.3, 0.0 + WALK_Y, 1.0 + WALK_Y, 0.95, 1.0, Color(0.10, 0.10, 0.10))
		_box(ctx, au - 0.26, au + 0.26, 0.1 + WALK_Y, 0.92 + WALK_Y, 1.0, 1.005, Color(0.18, 0.20, 0.18))


static func _face_basis(f: Vector3) -> Basis:
	var right := (-f).cross(Vector3.UP).normalized()
	return Basis(right, Vector3.UP, f.normalized())


static func _make_label(txt: String, col: Color, letters: bool) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 64
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.shaded = letters
	l.visibility_range_end = 130.0
	l.render_priority = 1
	return l


static func _fit_label(l: Label3D, txt: String, max_w: float, max_h: float) -> void:
	var chars := maxf(3.0, float(txt.length()))
	var px_w := max_w / (chars * float(l.font_size) * 0.60)
	var px_h := max_h / (float(l.font_size) * 1.05)
	l.pixel_size = minf(px_w, px_h)


static func _sign_label(parent: Node3D, pos: Vector3, n: Vector3, txt: String, max_w: float, max_h: float, col: Color, letters: bool) -> void:
	var l := _make_label(txt, col, letters)
	l.transform = Transform3D(_face_basis(n), pos)
	_fit_label(l, txt, max_w, max_h)
	parent.add_child(l)


# Axis-aligned (facade-local) box: u along the facade, y up, d outward from the wall.
static func _box(ctx: Dictionary, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color) -> void:
	if u1 - u0 < 0.005 or y1 - y0 < 0.005:
		return
	var o: Vector3 = ctx["o"]
	var U: Vector3 = ctx["u"]
	var N: Vector3 = ctx["n"]
	var st: SurfaceTool = ctx["st"]
	var c := func(u: float, y: float, d: float) -> Vector3: return o + U * u + N * d + Vector3.UP * y
	# front, top, bottom, two ends
	_quad(st, c.call(u0, y0, d1), c.call(u1, y0, d1), c.call(u1, y1, d1), c.call(u0, y1, d1), col)
	_quad(st, c.call(u0, y1, d1), c.call(u1, y1, d1), c.call(u1, y1, d0), c.call(u0, y1, d0), col.lightened(0.05))
	_quad(st, c.call(u0, y0, d0), c.call(u1, y0, d0), c.call(u1, y0, d1), c.call(u0, y0, d1), col.darkened(0.2))
	_quad(st, c.call(u0, y0, d0), c.call(u0, y0, d1), c.call(u0, y1, d1), c.call(u0, y1, d0), col.darkened(0.08))
	_quad(st, c.call(u1, y0, d1), c.call(u1, y0, d0), c.call(u1, y1, d0), c.call(u1, y1, d1), col.darkened(0.08))
	if d0 < -0.01:
		_quad(st, c.call(u1, y0, d0), c.call(u0, y0, d0), c.call(u0, y1, d0), c.call(u1, y1, d0), col.darkened(0.1))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


static func _glass(st: SurfaceTool, o: Vector3, U: Vector3, N: Vector3, u0: float, u1: float, y0: float, y1: float, d: float, col: Color) -> void:
	if u1 - u0 < 0.1 or y1 - y0 < 0.1:
		return
	var vs := [
		[o + U * u0 + N * d + Vector3.UP * y0, Vector2(u0, y0 - 0.48)],
		[o + U * u1 + N * d + Vector3.UP * y0, Vector2(u1, y0 - 0.48)],
		[o + U * u1 + N * d + Vector3.UP * y1, Vector2(u1, y1 - 0.48)],
		[o + U * u0 + N * d + Vector3.UP * y1, Vector2(u0, y1 - 0.48)],
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(N)
		st.set_uv(vs[idx][1])
		st.add_vertex(vs[idx][0])
