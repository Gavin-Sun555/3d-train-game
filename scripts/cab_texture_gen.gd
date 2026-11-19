class_name CabTextureGen
extends RefCounted

# Procedural High-Definition Texture Generator for 3D Tram Cab, Cabin Interior & Passengers.
# Uses crisp 1024x512 / 512x512 procedural instruments with a built-in 5x7 bitmap font renderer.

static var _cache: Dictionary = {}

const FONT_5X7 := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["01110", "10000", "11110", "10001", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
	":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


static func get_modern_mfd_tex() -> ImageTexture:
	if _cache.has("mfd"):
		return _cache["mfd"]
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.025, 0.042, 0.068, 1.0))

	_draw_rect_outline(img, 4, 4, w - 8, h - 8, Color(0.18, 0.28, 0.40), 3)
	# Top Status Header Bar
	_fill_rect(img, 8, 8, w - 16, 52, Color(0.05, 0.09, 0.15))
	_fill_rect(img, 8, 60, w - 16, 3, Color(0.20, 0.56, 0.84))

	# Header status pills with crisp legible labels
	_fill_rect(img, 20, 16, 128, 34, Color(0.09, 0.52, 0.34))
	_draw_text(img, "ATP OK", 38, 25, 2, Color(0.95, 1.0, 0.98))

	_fill_rect(img, 162, 16, 146, 34, Color(0.12, 0.32, 0.54))
	_draw_text(img, "750V DC", 182, 25, 2, Color(0.92, 0.98, 1.0))

	_fill_rect(img, 322, 16, 152, 34, Color(0.14, 0.38, 0.28))
	_draw_text(img, "PANTO UP", 338, 25, 2, Color(0.92, 1.0, 0.94))

	_fill_rect(img, 488, 16, 168, 34, Color(0.10, 0.22, 0.34))
	_draw_text(img, "DOOR LOCK", 506, 25, 2, Color(0.84, 0.96, 1.0))

	_fill_rect(img, 836, 16, 166, 34, Color(0.09, 0.16, 0.26))
	_draw_text(img, "TRAM HMI", 856, 25, 2, Color(0.70, 0.88, 0.98))

	# Left Panel: High-Res Circular Speedometer Dial Arc (center 224, 290, radius 164)
	var cx := 224.0
	var cy := 292.0
	var r_outer := 162.0
	var r_inner := 130.0
	_draw_circle_outline(img, cx, cy, r_outer + 6.0, Color(0.16, 0.26, 0.38), 3.0)
	_draw_arc_ticks(img, cx, cy, r_inner, r_outer, deg_to_rad(135.0), deg_to_rad(405.0), 40, Color(0.36, 0.58, 0.78), Color(0.90, 0.97, 1.0), Color(0.98, 0.28, 0.22), 0.75)
	_draw_arc_band(img, cx, cy, r_inner - 14.0, r_inner - 5.0, deg_to_rad(135.0), deg_to_rad(250.0), Color(0.14, 0.78, 0.95))

	# Speedometer dial numbers: 0, 20, 40, 60, 80
	var labels_spd: Array[String] = ["0", "20", "40", "60", "80"]
	for i in range(5):
		var ang := lerpf(deg_to_rad(135.0), deg_to_rad(405.0), float(i) / 4.0)
		var lx: int = int(cx + cos(ang) * 102.0) - (labels_spd[i].length() * 6)
		var ly := int(cy + sin(ang) * 102.0) - 7
		_draw_text(img, labels_spd[i], lx, ly, 2, Color(0.95, 0.35, 0.28) if i == 4 else Color(0.86, 0.94, 1.0))

	_draw_text(img, "KM/H", int(cx - 26), int(cy - 44), 2, Color(0.56, 0.74, 0.88))
	_fill_rect(img, int(cx - 66), int(cy + 36), 132, 52, Color(0.04, 0.08, 0.13))
	_draw_rect_outline(img, int(cx - 66), int(cy + 36), 132, 52, Color(0.24, 0.50, 0.74), 2)
	_fill_circle(img, cx, cy, 14.0, Color(0.22, 0.30, 0.40))
	_fill_circle(img, cx, cy, 7.0, Color(0.82, 0.90, 0.98))

	# Vertical Divider 1
	_fill_rect(img, 424, 74, 3, h - 88, Color(0.15, 0.24, 0.36))

	# Center Panel: Traction / Brake Effort Bar Graph
	_draw_rect_outline(img, 444, 82, 174, 402, Color(0.16, 0.26, 0.38), 2)
	_fill_rect(img, 446, 84, 170, 34, Color(0.07, 0.13, 0.21))
	_draw_text(img, "TRACTION", 472, 94, 2, Color(0.32, 0.92, 0.58))
	_fill_rect(img, 458, 290, 146, 3, Color(0.76, 0.84, 0.92))
	for i in range(6):
		var by := 262 - i * 26
		var col := Color(0.12, 0.80, 0.48) if i < 4 else Color(0.18, 0.66, 0.96)
		_fill_rect(img, 478, by, 106, 18, col if i < 3 else col.darkened(0.65))
	for j in range(5):
		var by := 306 + j * 26
		var col := Color(0.95, 0.65, 0.14) if j < 4 else Color(0.96, 0.22, 0.20)
		_fill_rect(img, 478, by, 106, 18, col.darkened(0.60))
	_draw_text(img, "BRAKE / EB", 464, 450, 2, Color(0.96, 0.56, 0.26))

	# Vertical Divider 2
	_fill_rect(img, 636, 74, 3, h - 88, Color(0.15, 0.24, 0.36))

	# Right Panel: Train Consist Schematic + Diagnostic Tiles
	_fill_rect(img, 654, 82, 348, 114, Color(0.05, 0.09, 0.15))
	_draw_rect_outline(img, 654, 82, 348, 114, Color(0.20, 0.34, 0.48), 2)
	_draw_text(img, "CONSIST DOORS", 672, 92, 2, Color(0.68, 0.82, 0.94))
	for c_i in range(3):
		var rx := 676 + c_i * 104
		_fill_rect(img, rx, 126, 88, 44, Color(0.14, 0.24, 0.36))
		_draw_rect_outline(img, rx, 126, 88, 44, Color(0.40, 0.72, 0.96), 2)
		for dx_off: int in [16, 56]:
			_fill_rect(img, rx + dx_off, 118, 16, 7, Color(0.18, 0.90, 0.48))
			_fill_rect(img, rx + dx_off, 171, 16, 7, Color(0.18, 0.90, 0.48))

	var diag_items := [
		["AIR 8.2B", Color(0.12, 0.58, 0.38)],
		["VOLT 750", Color(0.14, 0.46, 0.68)],
		["HVAC ON", Color(0.12, 0.54, 0.42)],
		["SAND RDY", Color(0.62, 0.44, 0.12)],
		["CCTV OK", Color(0.14, 0.36, 0.56)],
		["RADIO OK", Color(0.14, 0.50, 0.38)],
	]
	for t_i in range(diag_items.size()):
		var tx := 654 + (t_i % 2) * 178
		var ty := 214 + (t_i / 2) * 74
		_fill_rect(img, tx, ty, 170, 62, Color(0.06, 0.11, 0.17))
		_draw_rect_outline(img, tx, ty, 170, 62, Color(0.20, 0.32, 0.44), 2)
		_fill_rect(img, tx + 8, ty + 10, 18, 42, diag_items[t_i][1])
		_draw_text(img, diag_items[t_i][0], tx + 34, ty + 24, 2, Color(0.88, 0.95, 1.0))

	# Bottom route progress bar
	_fill_rect(img, 654, 446, 348, 38, Color(0.06, 0.10, 0.16))
	_draw_rect_outline(img, 654, 446, 348, 38, Color(0.18, 0.30, 0.44), 1)
	_fill_rect(img, 676, 463, 304, 4, Color(0.24, 0.72, 0.94))
	for s_i in range(5):
		_fill_circle(img, 684.0 + s_i * 72.0, 465.0, 8.0, Color(0.24, 0.94, 0.62) if s_i <= 2 else Color(0.45, 0.56, 0.68))

	var tex := ImageTexture.create_from_image(img)
	_cache["mfd"] = tex
	return tex


static func get_cctv_tex() -> ImageTexture:
	if _cache.has("cctv"):
		return _cache["cctv"]
	var w := 512
	var h := 320
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.06, 0.08))

	for half in range(2):
		var ox := 8 + half * 252
		var pw := 244
		var ph := 296
		_fill_rect(img, ox, 12, pw, 104, Color(0.10, 0.15, 0.21))
		_fill_rect(img, ox, 116, pw, 192, Color(0.18, 0.20, 0.22))
		for y in range(116, 308):
			var t := float(y - 116) / 192.0
			var edge_x := ox + int(lerpf(pw * 0.45, pw * 0.14, t)) if half == 0 else ox + int(lerpf(pw * 0.55, pw * 0.86, t))
			var y_line := edge_x + (18 if half == 0 else -22)
			if half == 0:
				_fill_rect(img, ox, y, maxi(1, edge_x - ox), 1, Color(0.14, 0.22, 0.32))
			else:
				_fill_rect(img, edge_x, y, maxi(1, ox + pw - edge_x), 1, Color(0.14, 0.22, 0.32))
			_fill_rect(img, clampi(y_line, ox, ox + pw - 5), y, 5, 1, Color(0.80, 0.68, 0.16))
		for sy in range(12, 308, 6):
			for sx in range(ox, ox + pw):
				img.set_pixel(sx, sy, img.get_pixel(sx, sy).darkened(0.12))
		_draw_rect_outline(img, ox, 12, pw, ph, Color(0.28, 0.48, 0.64), 2)
		_fill_circle(img, float(ox + 22), 30.0, 6.0, Color(0.18, 0.88, 0.46))
		_draw_text(img, "CAM L" if half == 0 else "CAM R", ox + 36, 23, 2, Color(0.84, 0.94, 1.0))

	var tex := ImageTexture.create_from_image(img)
	_cache["cctv"] = tex
	return tex


static func get_switch_panel_tex() -> ImageTexture:
	if _cache.has("switch_panel"):
		return _cache["switch_panel"]
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var streak := sin(float(y) * 1.1) * 0.010 + cos(float(y) * 0.31) * 0.007
		_fill_rect(img, 0, y, w, 1, Color(0.095 + streak, 0.105 + streak, 0.125 + streak))

	_draw_rect_outline(img, 10, 10, w - 20, h - 20, Color(0.28, 0.32, 0.38), 3)
	for sp: Vector2 in [Vector2(30, 30), Vector2(w - 30, 30), Vector2(30, h - 30), Vector2(w - 30, h - 30)]:
		_fill_circle(img, sp.x, sp.y, 10.0, Color(0.36, 0.40, 0.44))
		_fill_circle(img, sp.x, sp.y, 5.0, Color(0.14, 0.16, 0.18))

	_draw_rect_outline(img, 42, 42, 456, 200, Color(0.32, 0.38, 0.46), 2)
	_draw_rect_outline(img, 526, 42, 456, 200, Color(0.32, 0.38, 0.46), 2)
	_draw_rect_outline(img, 42, 266, 940, 204, Color(0.32, 0.38, 0.46), 2)

	var btn_specs := [
		["DOORS", Color(0.16, 0.86, 0.42)],
		["BELL", Color(0.95, 0.72, 0.14)],
		["LIGHT", Color(0.22, 0.68, 0.98)],
		["WIPER", Color(0.22, 0.68, 0.98)],
		["PANTO", Color(0.16, 0.86, 0.42)],
		["SAND", Color(0.95, 0.72, 0.14)],
		["HVAC", Color(0.16, 0.86, 0.42)],
		["STOP", Color(0.94, 0.22, 0.18)],
	]
	for i in range(8):
		var bx := (66 + i * 106) if i < 4 else (550 + (i - 4) * 106)
		var by := 82
		_fill_rect(img, bx, by, 84, 68, Color(0.05, 0.06, 0.08))
		_draw_rect_outline(img, bx, by, 84, 68, Color(0.46, 0.52, 0.58), 2)
		_fill_rect(img, bx + 8, by + 8, 68, 52, btn_specs[i][1])
		_draw_text(img, btn_specs[i][0], bx + 8, by + 84, 2, Color(0.86, 0.90, 0.95))

	var rot_labels := ["KEY", "F/N/R", "LAMP", "CAB"]
	for r_i in range(4):
		var rcx := 140.0 + r_i * 140.0
		var rcy := 356.0
		_draw_circle_outline(img, rcx, rcy, 44.0, Color(0.58, 0.64, 0.70), 2.5)
		_fill_circle(img, rcx, rcy, 30.0, Color(0.06, 0.07, 0.09))
		_fill_rect(img, int(rcx - 6), int(rcy - 26), 12, 52, Color(0.34, 0.38, 0.44))
		_fill_rect(img, int(rcx - 2), int(rcy - 24), 4, 20, Color(0.94, 0.96, 0.98))
		_draw_text(img, rot_labels[r_i], int(rcx - 24), int(rcy + 58), 2, Color(0.84, 0.88, 0.94))

	_fill_rect(img, 672, 304, 276, 128, Color(0.06, 0.07, 0.09))
	_draw_rect_outline(img, 672, 304, 276, 128, Color(0.88, 0.68, 0.14), 3)
	for stripe in range(0, 260, 28):
		_fill_rect(img, 680 + stripe, 312, 14, 16, Color(0.92, 0.72, 0.14))
	_draw_text(img, "EMERGENCY EB", 714, 352, 2, Color(1.0, 0.38, 0.32))
	_draw_text(img, "PULL OR PRESS", 706, 390, 2, Color(0.88, 0.90, 0.94))

	var tex := ImageTexture.create_from_image(img)
	_cache["switch_panel"] = tex
	return tex


static func get_vintage_dial_tex(is_pressure: bool = false) -> ImageTexture:
	var key := "vintage_pres" if is_pressure else "vintage_spd"
	if _cache.has(key):
		return _cache[key]
	var sz := 512
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.12, 0.08, 1.0))
	var c := float(sz) * 0.5
	_fill_circle(img, c, c, 244.0, Color(0.70, 0.56, 0.24))
	_fill_circle(img, c, c, 224.0, Color(0.95, 0.92, 0.84))
	_draw_circle_outline(img, c, c, 208.0, Color(0.18, 0.16, 0.14), 4.0)
	_draw_circle_outline(img, c, c, 148.0, Color(0.55, 0.50, 0.42), 2.0)
	_draw_arc_ticks(img, c, c, 164.0, 204.0, deg_to_rad(135.0), deg_to_rad(405.0), 32, Color(0.24, 0.22, 0.18), Color(0.10, 0.09, 0.08), Color(0.78, 0.16, 0.14), 0.75)
	var nums: Array[String] = []
	nums.assign(["0", "2", "4", "6", "8"] if is_pressure else ["0", "20", "40", "60", "80"])
	for i in range(5):
		var ang := lerpf(deg_to_rad(135.0), deg_to_rad(405.0), float(i) / 4.0)
		var lx: int = int(c + cos(ang) * 124.0) - nums[i].length() * 8
		var ly := int(c + sin(ang) * 124.0) - 10
		_draw_text(img, nums[i], lx, ly, 3, Color(0.12, 0.11, 0.10))
	_draw_text(img, "BAR" if is_pressure else "KM/H", int(c - 32), int(c + 72), 3, Color(0.28, 0.24, 0.18))
	if is_pressure:
		var ang := deg_to_rad(285.0)
		_draw_line_thick(img, c - cos(ang) * 32.0, c - sin(ang) * 32.0, c + cos(ang) * 168.0, c + sin(ang) * 168.0, Color(0.78, 0.14, 0.12), 7.0)
	_fill_circle(img, c, c, 20.0, Color(0.68, 0.54, 0.22))
	_fill_circle(img, c, c, 9.0, Color(0.26, 0.20, 0.10))

	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func get_cabin_floor_tex() -> ImageTexture:
	if _cache.has("cabin_floor"):
		return _cache["cabin_floor"]
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4091
	img.fill(Color(0.20, 0.22, 0.25))
	for _i in range(4200):
		var px := rng.randi_range(0, sz - 1)
		var py := rng.randi_range(0, sz - 1)
		var r := rng.randf()
		var col := Color(0.32, 0.35, 0.39)
		if r < 0.28:
			col = Color(0.13, 0.14, 0.16)
		elif r < 0.42:
			col = Color(0.56, 0.60, 0.66)
		elif r < 0.48:
			col = Color(0.22, 0.44, 0.62)
		img.set_pixel(px, py, col)
		if px + 1 < sz and r > 0.72:
			img.set_pixel(px + 1, py, col)
	_fill_rect(img, 0, 127, sz, 2, Color(0.13, 0.14, 0.16))
	_fill_rect(img, 127, 0, 2, sz, Color(0.14, 0.15, 0.17))

	var tex := ImageTexture.create_from_image(img)
	_cache["cabin_floor"] = tex
	return tex


static func get_moquette_seat_tex(base_col: Color) -> ImageTexture:
	var key := "moq_%02x%02x%02x" % [int(base_col.r * 255), int(base_col.g * 255), int(base_col.b * 255)]
	if _cache.has(key):
		return _cache[key]
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var dark := base_col.darkened(0.28)
	var hi := base_col.lightened(0.24)
	var accent := Color(0.90, 0.72, 0.22) if base_col.b > 0.35 else Color(0.24, 0.64, 0.82)
	for y in range(sz):
		for x in range(sz):
			var weave := (((x + y) % 4) == 0)
			var c := base_col.darkened(0.06) if weave else base_col
			var diag := (x + y * 2) % 32
			if diag >= 0 and diag <= 3:
				c = dark
			elif diag >= 14 and diag <= 16 and ((x / 8 + y / 8) % 2 == 0):
				c = hi
			elif ((x % 24) >= 10 and (x % 24) <= 13) and ((y % 24) >= 10 and (y % 24) <= 13):
				c = accent.lerp(base_col, 0.45)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func get_cabin_lcd_tex() -> ImageTexture:
	if _cache.has("cabin_lcd"):
		return _cache["cabin_lcd"]
	var w := 512
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.08, 0.14))
	_draw_rect_outline(img, 3, 3, w - 6, h - 6, Color(0.20, 0.32, 0.48), 2)
	_fill_rect(img, 6, 6, w - 12, 32, Color(0.08, 0.26, 0.48))
	_fill_rect(img, 14, 11, 56, 22, Color(0.14, 0.76, 0.44))
	_draw_text(img, "L1", 30, 15, 2, Color(1.0, 1.0, 1.0))
	_draw_text(img, "NEXT STOP: DOWNTOWN", 84, 15, 2, Color(0.92, 0.96, 1.0))
	_fill_rect(img, 36, 76, 440, 6, Color(0.18, 0.68, 0.92))
	for i in range(7):
		var sx := 44.0 + i * 70.0
		var active := (i == 3)
		var passed := (i < 3)
		var r := 11.0 if active else 7.5
		var col := Color(0.98, 0.78, 0.16) if active else (Color(0.32, 0.42, 0.52) if passed else Color(0.92, 0.96, 1.0))
		_fill_circle(img, sx, 79.0, r, col)
		if not active:
			_fill_circle(img, sx, 79.0, 3.5, Color(0.08, 0.14, 0.24))
		_fill_rect(img, int(sx - 20), 96, 40, 7, Color(0.96, 0.84, 0.30) if active else Color(0.56, 0.66, 0.78))
		_fill_rect(img, int(sx - 14), 107, 28, 5, Color(0.38, 0.48, 0.58))

	var tex := ImageTexture.create_from_image(img)
	_cache["cabin_lcd"] = tex
	return tex


static func get_person_face_tex(skin: Color, hair: Color) -> ImageTexture:
	var key := "face_%02x%02x_%02x%02x" % [int(skin.r * 255), int(skin.g * 255), int(hair.r * 255), int(hair.b * 255)]
	if _cache.has(key):
		return _cache[key]
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := float(y) / float(h - 1)
		for x in range(w):
			var u := float(x) / float(w - 1)
			var du := absf(u - 0.5)
			var hair_mask := 0.0
			if v < 0.25:
				hair_mask = 1.0
			elif du > 0.22 and v < 0.70:
				hair_mask = smoothstep(0.20, 0.25, du) * smoothstep(0.74, 0.64, v)
			elif du > 0.15 and v < 0.36:
				hair_mask = smoothstep(0.14, 0.19, du) * smoothstep(0.38, 0.28, v)

			var shade := 1.0 - maxf(0.0, (v - 0.72) * 0.48) - maxf(0.0, (0.28 - v) * 0.25)
			var col := Color(skin.r * shade, skin.g * shade, skin.b * shade)
			var cheek_d := Vector2((du - 0.085) * 2.2, (v - 0.58) * 2.6).length()
			if cheek_d < 0.18:
				col = col.lerp(Color(0.86, 0.48, 0.44), (1.0 - cheek_d / 0.18) * 0.14)

			if hair_mask > 0.01:
				var strand := sin(u * 160.0 + v * 18.0) * 0.038
				var hc := Color(clampf(hair.r + strand, 0.0, 1.0), clampf(hair.g + strand, 0.0, 1.0), clampf(hair.b + strand, 0.0, 1.0))
				col = col.lerp(hc, hair_mask)
			img.set_pixel(x, y, col)

	var brow_c := hair.lerp(skin.darkened(0.42), 0.35)
	_fill_rect(img, 108, 49, 14, 3, brow_c)
	_fill_rect(img, 134, 49, 14, 3, brow_c)
	# Soft eyes with subtle eyelid shadow
	_fill_rect(img, 110, 56, 11, 2, skin.darkened(0.22))
	_fill_rect(img, 135, 56, 11, 2, skin.darkened(0.22))
	_fill_rect(img, 110, 58, 10, 5, Color(0.88, 0.86, 0.84))
	_fill_rect(img, 136, 58, 10, 5, Color(0.88, 0.86, 0.84))
	_fill_circle(img, 115.0, 60.5, 2.5, Color(0.14, 0.12, 0.11))
	_fill_circle(img, 141.0, 60.5, 2.5, Color(0.14, 0.12, 0.11))
	# Soft nose shading & natural lips
	_fill_rect(img, 127, 65, 2, 11, skin.darkened(0.10))
	_fill_rect(img, 124, 76, 8, 3, skin.darkened(0.16))
	_fill_rect(img, 120, 88, 16, 3, skin.lerp(Color(0.64, 0.36, 0.36), 0.44))

	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _draw_text(img: Image, txt: String, x0: int, y0: int, scale: int, col: Color) -> void:
	var cx := x0
	var upper := txt.to_upper()
	for i in range(upper.length()):
		var ch := upper.substr(i, 1)
		var glyph: Array = FONT_5X7.get(ch, FONT_5X7[" "])
		for gy in range(7):
			var row_s: String = glyph[gy]
			for gx in range(5):
				if row_s.substr(gx, 1) == "1":
					_fill_rect(img, cx + gx * scale, y0 + gy * scale, scale, scale, col)
		cx += 6 * scale


static func _fill_rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	var x1 := mini(iw, x0 + rw)
	var y1 := mini(ih, y0 + rh)
	for y in range(maxi(0, y0), y1):
		for x in range(maxi(0, x0), x1):
			img.set_pixel(x, y, col)


static func _draw_rect_outline(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color, t: int = 1) -> void:
	_fill_rect(img, x0, y0, rw, t, col)
	_fill_rect(img, x0, y0 + rh - t, rw, t, col)
	_fill_rect(img, x0, y0, t, rh, col)
	_fill_rect(img, x0 + rw - t, y0, t, rh, col)


static func _fill_circle(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	var r2 := r * r
	for y in range(maxi(0, int(floor(cy - r))), mini(ih, int(ceil(cy + r)) + 1)):
		var dy := float(y) - cy
		for x in range(maxi(0, int(floor(cx - r))), mini(iw, int(ceil(cx + r)) + 1)):
			var dx := float(x) - cx
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, col)


static func _draw_circle_outline(img: Image, cx: float, cy: float, r: float, col: Color, thick: float = 1.5) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	var r_out := (r + thick * 0.5) * (r + thick * 0.5)
	var r_in := maxf(0.0, r - thick * 0.5)
	r_in *= r_in
	for y in range(maxi(0, int(floor(cy - r - thick))), mini(ih, int(ceil(cy + r + thick)) + 1)):
		var dy := float(y) - cy
		for x in range(maxi(0, int(floor(cx - r - thick))), mini(iw, int(ceil(cx + r + thick)) + 1)):
			var d2 := (float(x) - cx) * (float(x) - cx) + dy * dy
			if d2 <= r_out and d2 >= r_in:
				img.set_pixel(x, y, col)


static func _draw_line_thick(img: Image, x0: float, y0: float, x1: float, y1: float, col: Color, thick: float = 2.0) -> void:
	var steps := maxi(2, int(ceil(Vector2(x1 - x0, y1 - y0).length() * 1.5)))
	var rad := thick * 0.5
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		_fill_circle(img, lerpf(x0, x1, t), lerpf(y0, y1, t), rad, col)


static func _draw_arc_ticks(
	img: Image, cx: float, cy: float, r_in: float, r_out: float,
	a0: float, a1: float, count: int,
	minor_col: Color, major_col: Color, red_col: Color, red_start: float
) -> void:
	for i in range(count + 1):
		var f := float(i) / float(count)
		var ang := lerpf(a0, a1, f)
		var is_major := (i % 5 == 0)
		var r0 := r_in if is_major else lerpf(r_in, r_out, 0.42)
		var col := red_col if f >= red_start else (major_col if is_major else minor_col)
		_draw_line_thick(
			img,
			cx + cos(ang) * r0, cy + sin(ang) * r0,
			cx + cos(ang) * r_out, cy + sin(ang) * r_out,
			col, 4.2 if is_major else 2.2
		)


static func _draw_arc_band(img: Image, cx: float, cy: float, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var steps := 72
	var rm := (r0 + r1) * 0.5
	var rad := (r1 - r0) * 0.5
	for i in range(steps + 1):
		var ang := lerpf(a0, a1, float(i) / float(steps))
		_fill_circle(img, cx + cos(ang) * rm, cy + sin(ang) * rm, rad, col)
