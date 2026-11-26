"""
Fast city-wide Google Earth Satellite (lyrs=s, pure WGS-84) pixel sampler for Jiaxing.
Reads tools/osm_cache/google_earth_z16/jiaxing_ge_rgb.bin (built from 460 Google Earth z16 tiles,
~4.1 m/px covering the full Jiaxing urban + HSR corridor) and classifies real rooftop colors,
materials, and land-cover vegetation/water for every building footprint.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GE_DIR = os.path.join(HERE, "osm_cache", "google_earth_z16")
GE_BIN = os.path.join(GE_DIR, "jiaxing_ge_rgb.bin")
GE_META = os.path.join(GE_DIR, "jiaxing_ge_rgb.json")

# Same WGS-84 projection as tools/build_jiaxing_map.py
LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0


class GoogleEarthSampler:
    def __init__(self):
        self.available = False
        self.buf = None
        self.w = 0
        self.h = 0
        self.z = 16
        self.x0 = 0
        self.y0 = 0
        self.tile_px = 128
        self.n_tiles = 1 << 16
        if os.path.exists(GE_BIN) and os.path.exists(GE_META):
            with open(GE_META, encoding="utf-8") as f:
                m = json.load(f)
            self.z = int(m["z"])
            self.x0 = int(m["x0"])
            self.y0 = int(m["y0"])
            self.tile_px = int(m["tile_px"])
            self.w = int(m["w"])
            self.h = int(m["h"])
            self.n_tiles = 1 << self.z
            with open(GE_BIN, "rb") as f:
                self.buf = f.read()
            if len(self.buf) == self.w * self.h * 3:
                self.available = True

    def _xy_to_px(self, gx, gy):
        lat = LAT0 - gy / KY
        lon = LON0 + gx / KX
        xf = (lon + 180.0) / 360.0 * self.n_tiles
        lr = math.radians(lat)
        yf = (1.0 - math.asinh(math.tan(lr)) / math.pi) / 2.0 * self.n_tiles
        px = int((xf - self.x0) * self.tile_px)
        py = int((yf - self.y0) * self.tile_px)
        return px, py

    def rgb_at(self, gx, gy):
        if not self.available:
            return None
        px, py = self._xy_to_px(gx, gy)
        if px < 0 or py < 0 or px >= self.w or py >= self.h:
            return None
        off = (py * self.w + px) * 3
        b = self.buf
        return (b[off], b[off + 1], b[off + 2])

    def sample_footprint(self, pts):
        """Sample Google Earth satellite pixels across a building footprint (centroid + vertices + edge mids).
        Returns dict: {rgb, roof_class, roof_hex, veg_ratio, water_ratio, bright} or None if outside atlas."""
        if not self.available or not pts:
            return None
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        samples = [(cx, cy)]
        for p in pts:
            # pull 30% toward centroid so we sample the roof, not adjacent trees/shadows
            samples.append((cx + (p[0] - cx) * 0.65, cy + (p[1] - cy) * 0.65))
        rs = gs = bs = 0.0
        n = 0
        veg = 0
        water = 0
        red_votes = 0
        blue_votes = 0
        warm_votes = 0
        dark_votes = 0
        light_votes = 0
        for sx, sy in samples:
            c = self.rgb_at(sx, sy)
            if c is None:
                continue
            r, g, b = c
            rs += r
            gs += g
            bs += b
            n += 1
            # Vegetation: lush green trees / park lawn (G clearly > R and G > B, dark-medium value)
            if g > r + 7 and g > b + 6 and r < 115 and g < 150:
                veg += 1
            # Deep canal / lake water: dark blue-green with low R and low overall brightness
            if r < 52 and g < 68 and b < 78 and (b >= r - 2 or g >= r + 4):
                water += 1
            # Terracotta / rust-red pitched roof (平改坡 red steel/clay tiles in Jiaxing)
            if r > g + 14 and r > b + 20 and r >= 88:
                red_votes += 1
            # Bright industrial steel-blue roof (厂房 / 体育馆蓝彩钢瓦)
            elif b > r + 24 and b > g + 10 and b >= 105:
                blue_votes += 1
            # Warm ochre / beige / buff / tan roofs (modern/2000s compounds)
            elif r > b + 10 and g > b + 4 and r >= 92:
                warm_votes += 1
            # Light silver / white concrete or modern high-rise roof
            elif r >= 122 and g >= 120 and b >= 115:
                light_votes += 1
            # Dark charcoal / slate pitched roof
            elif r < 95 and g < 95 and b < 100:
                dark_votes += 1

        if n == 0:
            return None
        mr, mg, mb = rs / n, gs / n, bs / n
        bright = (mr * 0.299 + mg * 0.587 + mb * 0.114) / 255.0
        veg_ratio = veg / n
        water_ratio = water / n

        if blue_votes >= max(1, n * 0.28):
            rcls = "steel_blue"
            rhex = "#2d5f99"
        elif red_votes >= max(1, n * 0.28) or (mr > mg + 12 and mr > mb + 18 and mr > 86):
            rcls = "terracotta_red"
            # Modulate between deep rust-red and warm terracotta-orange based on satellite brightness
            if mr > 125:
                rhex = "#a64c38"
            elif mr > 105:
                rhex = "#8f4232"
            else:
                rhex = "#7a392c"
        elif warm_votes >= max(2, n * 0.45):
            rcls = "warm_tan"
            rhex = "#5d4c40" if bright < 0.42 else "#746252"
        elif light_votes >= max(2, n * 0.45):
            rcls = "light_concrete"
            rhex = "#6f7378"
        else:
            rcls = "dark_slate"
            rhex = "#363c44" if bright < 0.34 else "#464c54"

        return {
            "rgb": (round(mr, 1), round(mg, 1), round(mb, 1)),
            "roof_class": rcls,
            "roof_hex": rhex,
            "veg_ratio": veg_ratio,
            "water_ratio": water_ratio,
            "bright": bright,
        }

    def is_green_or_water_plot(self, cx, cy, half_l=12.0, half_w=7.0):
        """Check if Google Earth satellite shows dense vegetation/park/water across a candidate infill spot."""
        if not self.available:
            return False
        pts = [
            (cx, cy),
            (cx - half_l * 0.6, cy),
            (cx + half_l * 0.6, cy),
            (cx, cy - half_w * 0.6),
            (cx, cy + half_w * 0.6),
        ]
        bad = 0
        tot = 0
        for px, py in pts:
            c = self.rgb_at(px, py)
            if c is None:
                continue
            r, g, b = c
            tot += 1
            is_veg = (g > r + 9 and g > b + 8 and r < 98 and g < 135)
            is_wat = (r < 44 and g < 58 and b < 70 and b >= r - 2)
            if is_veg or is_wat:
                bad += 1
        return tot >= 4 and (bad / tot) >= 0.80

    def classify_open_plot(self, pts):
        """Classify an unbuilt open plot from Google Earth z16 RGB pixels into:
        'farmland' (agricultural paddy/vegetable greens), 'construction' (exposed ochre/tan bare soil
        & concrete foundation pits), or 'vacant' (general urban open space / scrub)."""
        if not self.available or len(pts) < 3:
            return "vacant"
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        cx = sum(xs) / len(xs)
        cy = sum(ys) / len(ys)
        # Sample a 3x3 interior grid pulled slightly inward from bbox edges
        samples = [(cx, cy)]
        for fx in (0.28, 0.50, 0.72):
            for fy in (0.28, 0.50, 0.72):
                samples.append((x0 + (x1 - x0) * fx, y0 + (y1 - y0) * fy))
        n = 0
        farm_v = 0
        soil_v = 0
        urb_grey_v = 0
        for sx, sy in samples:
            c = self.rgb_at(sx, sy)
            if c is None:
                continue
            r, g, b = c
            n += 1
            # Agricultural green/olive/autumn-khaki paddy & vegetable fields on Jiaxing Google Earth imagery
            is_green_crop = (g >= r + 3 and g >= b + 4 and r < 118 and g < 142 and b < 105)
            is_autumn_field = (50 <= r <= 128 and 48 <= g <= 132 and b < 92 and (r - b) >= 10 and (g - b) >= 7 and abs(r - g) <= 22)
            if is_green_crop or is_autumn_field:
                farm_v += 1
            # Bright exposed bare earth / sandy-ochre excavated construction pad & gravel/concrete foundation slabs
            elif r >= 120 and g >= 104 and r > b + 12 and g > b + 6 and r < 228:
                soil_v += 1
            elif abs(r - g) < 12 and abs(g - b) < 12 and 122 <= r <= 218:
                urb_grey_v += 1
        if n < 4:
            return "vacant"
        if (soil_v / n >= 0.36 or (soil_v >= 2 and (soil_v + urb_grey_v) / n >= 0.52)) and farm_v / n < 0.34:
            return "construction"
        if farm_v / n >= 0.45:
            return "farmland"
        return "vacant"

    def sample_wall_hue(self, pts):
        """Infer realistic facade/roof daylight color family directly from Google Earth z16 RGB pixels
        over and immediately around a building footprint."""
        if not self.available or len(pts) < 3:
            return None
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx = sum(xs) / len(xs)
        cy = sum(ys) / len(ys)
        samps = [(cx, cy)]
        for p in pts[::max(1, len(pts) // 4)][:4]:
            samps.append((cx + (p[0] - cx) * 0.7, cy + (p[1] - cy) * 0.7))
        rs = gs = bs = 0.0
        n = 0
        for sx, sy in samps:
            c = self.rgb_at(sx, sy)
            if c is None:
                continue
            rs += c[0]
            gs += c[1]
            bs += c[2]
            n += 1
        if n == 0:
            return None
        r, g, b = rs / n, gs / n, bs / n
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        if b >= r + 14 and b >= 115:
            return "blue_roof"
        if r >= b + 20 and r >= 120 and g < r - 6:
            return "terracotta"
        if lum >= 158 and abs(r - b) <= 16:
            return "bright_white"
        if r >= b + 12 and lum >= 118:
            return "warm_cream"
        if b >= r + 4 and lum >= 105:
            return "cool_silver"
        return "warm_stone"

    def has_roadside_trees(self, ax, ay, bx, by, hw, side):
        """Return True if Google Earth z16 satellite imagery shows roadside green tree canopies
        along the given side (-1 or +1) of road segment (a -> b)."""
        if not self.available:
            return True
        L = math.hypot(bx - ax, by - ay)
        if L < 4.0:
            return False
        dx, dy = (bx - ax) / L, (by - ay) / L
        nx, ny = -dy, dx
        n_steps = max(3, min(7, int(L / 18.0)))
        hits = 0
        tot = 0
        for i in range(n_steps):
            t = (i + 0.5) / n_steps
            px0 = ax + dx * (L * t)
            py0 = ay + dy * (L * t)
            for off in (hw + 2.6, hw + 5.4):
                c = self.rgb_at(px0 + nx * side * off, py0 + ny * side * off)
                if c is None:
                    continue
                r, g, b = c
                tot += 1
                # Jiangnan camphor / plane tree canopy on Google Earth: olive/emerald green OR dark-green canopy shade
                is_canopy = (
                    (g >= r + 2 and g >= b + 3 and r < 118 and g < 142 and b < 105)
                    or (r < 76 and g < 92 and b < 76 and g >= r - 2 and g >= b - 1)
                )
                if is_canopy:
                    hits += 1
        return tot >= 2 and (hits / tot) >= 0.24
