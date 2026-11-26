#!/usr/bin/env python3
"""Scan ALL z=17 Amap tiles across Jiaxing ACTIVE_RECTS (ltype=11 vs ltype=3 diff)
to recover EVERY real 2021-2026 building missing from GlobalBuildingAtlas (2020) & OSM!

Outputs: tools/osm_cache/jiaxing_amap_2025_buildings.json (pure WGS-84 Jiaxing game meters).
"""
import concurrent.futures
import json
import math
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0

CACHE_DIR = os.path.join(HERE, "osm_cache", "amap_z17")
OUT_PATH = os.path.join(HERE, "osm_cache", "jiaxing_amap_2025_buildings.json")
REAL_PATH = os.path.join(HERE, "osm_cache", "jiaxing_real_buildings.json")
os.makedirs(CACHE_DIR, exist_ok=True)


def _tlat(x, y):
    r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
    r += (160.0 * math.sin(y / 12.0 * math.pi) + 320.0 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
    return r


def _tlon(x, y):
    r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
    r += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
    return r


def wgs2gcj(lat, lon):
    a, ee = 6378245.0, 0.00669342162296594323
    rad = lat / 180.0 * math.pi
    m = 1.0 - ee * math.sin(rad) ** 2
    sm = math.sqrt(m)
    dlat = (_tlat(lon - 105.0, lat - 35.0) * 180.0) / ((a * (1.0 - ee)) / (m * sm) * math.pi)
    dlon = (_tlon(lon - 105.0, lat - 35.0) * 180.0) / (a / sm * math.cos(rad) * math.pi)
    return lat + dlat, lon + dlon


def gcj2wgs(lat, lon):
    glat, glon = lat, lon
    for _ in range(4):
        tlat, tlon = wgs2gcj(glat, glon)
        glat += lat - tlat
        glon += lon - tlon
    return glat, glon


def proj(lat, lon):
    return ((lon - LON0) * KX, -(lat - LAT0) * KY)


def rect_ll(s, w, n, e):
    x0, y1 = proj(s, w)
    x1, y0 = proj(n, e)
    return (round(x0, 1), round(y0, 1), round(x1, 1), round(y1, 1))


def game_to_tile_gcj(gx, gy, z=17):
    lat = LAT0 - gy / KY
    lon = LON0 + gx / KX
    glat, glon = wgs2gcj(lat, lon)
    n = 2 ** z
    tx = int((glon + 180.0) / 360.0 * n)
    ty = int((1.0 - math.asinh(math.tan(math.radians(glat))) / math.pi) / 2.0 * n)
    return tx, ty


def tile_px_to_game(fx, fy, z=17):
    n = 2 ** z
    glon = fx / n * 360.0 - 180.0
    glat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * fy / n))))
    wlat, wlon = gcj2wgs(glat, glon)
    return (round((wlon - LON0) * KX, 2), round((LAT0 - wlat) * KY, 2))


def fetch_tile_pair(tx, ty):
    p11 = os.path.join(CACHE_DIR, f"t11_{tx}_{ty}.png")
    p3 = os.path.join(CACHE_DIR, f"t3_{tx}_{ty}.png")
    srv = ((tx + ty) % 4) + 1
    for lt, path in ((11, p11), (3, p3)):
        if os.path.exists(path) and os.path.getsize(path) > 120:
            continue
        url = f"https://webrd0{srv}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={tx}&y={ty}&z=17&ltype={lt}"
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                data = urllib.request.urlopen(req, timeout=12).read()
                if len(data) > 100:
                    with open(path, "wb") as f:
                        f.write(data)
                    break
            except Exception:
                time.sleep(0.25 * (attempt + 1))
    if not (os.path.exists(p11) and os.path.exists(p3)):
        return False
    return open(p11, "rb").read() != open(p3, "rb").read()


SWIFT_SRC = r"""
import Foundation
import CoreGraphics
import ImageIO

func loadRGB(_ path: String) -> [UInt8]? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    if w != 256 || h != 256 { return nil }
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

// Args: cacheDir tx0 ty0 cols rows outFile
let args = CommandLine.arguments
if args.count < 7 { exit(1) }
let cacheDir = args[1]
let tx0 = Int(args[2])!
let ty0 = Int(args[3])!
let cols = Int(args[4])!
let rows = Int(args[5])!
let outFile = args[6]

let W = cols * 256
let H = rows * 256
var mask = [UInt8](repeating: 0, count: W * H)

for dy in 0..<rows {
    for dx in 0..<cols {
        let tx = tx0 + dx
        let ty = ty0 + dy
        let p11 = "\(cacheDir)/t11_\(tx)_\(ty).png"
        let p3 = "\(cacheDir)/t3_\(tx)_\(ty).png"
        guard let a = loadRGB(p11), let b = loadRGB(p3) else { continue }
        for py in 0..<256 {
            let rowOff = (dy * 256 + py) * W + dx * 256
            let srcRow = py * 256 * 4
            for px in 0..<256 {
                let si = srcRow + px * 4
                let diff = abs(Int(a[si]) - Int(b[si])) + abs(Int(a[si+1]) - Int(b[si+1])) + abs(Int(a[si+2]) - Int(b[si+2]))
                // Amap building fill in style=8 is warm light beige/grey; diff >= 5 cleanly isolates every building polygon
                if diff >= 5 {
                    mask[rowOff + px] = 1
                }
            }
        }
    }
}

// Erode 1px lightly? No — keep exact footprint, just split tiny 1px corner bridges via 4-connected flood fill!
var visited = [UInt8](repeating: 0, count: W * H)
var queue = [Int]()
queue.reserveCapacity(16384)

var lines = [String]()
lines.reserveCapacity(1024)

for y in 0..<H {
    let yw = y * W
    for x in 0..<W {
        let idx = yw + x
        if mask[idx] == 0 || visited[idx] != 0 { continue }
        visited[idx] = 1
        queue.removeAll(keepingCapacity: true)
        queue.append(idx)
        var head = 0
        var sumX: Double = 0, sumY: Double = 0
        var minX = x, maxX = x, minY = y, maxY = y
        var ptsX = [Int]()
        var ptsY = [Int]()
        var touchesBorder = false

        while head < queue.count {
            let cur = queue[head]
            head += 1
            let cy = cur / W
            let cx = cur - cy * W
            sumX += Double(cx)
            sumY += Double(cy)
            if cx < minX { minX = cx }
            if cx > maxX { maxX = cx }
            if cy < minY { minY = cy }
            if cy > maxY { maxY = cy }
            if cx == 0 || cx == W - 1 || cy == 0 || cy == H - 1 {
                touchesBorder = true
            }
            // Track boundary pixels only for super-fast OBB angle computation
            var isBoundary = false
            if cx > 0 {
                let n = cur - 1
                if mask[n] == 1 { if visited[n] == 0 { visited[n] = 1; queue.append(n) } } else { isBoundary = true }
            } else { isBoundary = true }
            if cx + 1 < W {
                let n = cur + 1
                if mask[n] == 1 { if visited[n] == 0 { visited[n] = 1; queue.append(n) } } else { isBoundary = true }
            } else { isBoundary = true }
            if cy > 0 {
                let n = cur - W
                if mask[n] == 1 { if visited[n] == 0 { visited[n] = 1; queue.append(n) } } else { isBoundary = true }
            } else { isBoundary = true }
            if cy + 1 < H {
                let n = cur + W
                if mask[n] == 1 { if visited[n] == 0 { visited[n] = 1; queue.append(n) } } else { isBoundary = true }
            } else { isBoundary = true }
            if isBoundary {
                ptsX.append(cx)
                ptsY.append(cy)
            }
        }

        let area = queue.count
        if area < 42 || area > 65000 || touchesBorder { continue }
        let bw = maxX - minX + 1
        let bh = maxY - minY + 1
        if bw < 4 || bh < 4 { continue }

        // Compute principal axis via covariance of all pixels (or boundary pixels) for accurate oriented rectangle!
        let meanX = sumX / Double(area)
        let meanY = sumY / Double(area)
        var sxx: Double = 0, syy: Double = 0, sxy: Double = 0
        for p in queue {
            let py = Double(p / W) - meanY
            let px = Double(p % W) - meanX
            sxx += px * px
            syy += py * py
            sxy += px * py
        }
        let ang = 0.5 * atan2(2.0 * sxy, sxx - syy)
        let ca = cos(ang), sa = sin(ang)
        var uMin = 1e9, uMax = -1e9, vMin = 1e9, vMax = -1e9
        for i in 0..<ptsX.count {
            let px = Double(ptsX[i]) - meanX
            let py = Double(ptsY[i]) - meanY
            let u = px * ca + py * sa
            let v = -px * sa + py * ca
            if u < uMin { uMin = u }
            if u > uMax { uMax = u }
            if v < vMin { vMin = v }
            if v > vMax { vMax = v }
        }
        let rectW = max(1.0, uMax - uMin)
        let rectH = max(1.0, vMax - vMin)
        let fill = Double(area) / (rectW * rectH)
        let aspect = max(rectW, rectH) / min(rectW, rectH)
        // Reject skinny road-stroke noise or sprawling hollow artifacts
        if fill < 0.34 || aspect > 16.0 || min(rectW, rectH) < 3.5 { continue }

        // If near-rectangular (fill >= 0.72), emit crisp 4-corner OBB; otherwise emit 8-pt convex hull approximation!
        if fill >= 0.70 {
            let c0x = meanX + uMin * ca - vMin * sa
            let c0y = meanY + uMin * sa + vMin * ca
            let c1x = meanX + uMax * ca - vMin * sa
            let c1y = meanY + uMax * sa + vMin * ca
            let c2x = meanX + uMax * ca - vMax * sa
            let c2y = meanY + uMax * sa + vMax * ca
            let c3x = meanX + uMin * ca - vMax * sa
            let c3y = meanY + uMin * sa + vMax * ca
            lines.append(String(format: "%d %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f",
                                area, c0x, c0y, c1x, c1y, c2x, c2y, c3x, c3y))
        } else {
            // Andrew's monotone chain convex hull on boundary points for L-shaped/courtyard complexes
            var bpts = [(Int, Int)]()
            bpts.reserveCapacity(ptsX.count)
            for i in 0..<ptsX.count { bpts.append((ptsX[i], ptsY[i])) }
            bpts.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            func cross(_ o: (Int, Int), _ a: (Int, Int), _ b: (Int, Int)) -> Int {
                return (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
            }
            var lower = [(Int, Int)]()
            for p in bpts {
                while lower.count >= 2 && cross(lower[lower.count-2], lower[lower.count-1], p) <= 0 { lower.removeLast() }
                lower.append(p)
            }
            var upper = [(Int, Int)]()
            for p in bpts.reversed() {
                while upper.count >= 2 && cross(upper[upper.count-2], upper[upper.count-1], p) <= 0 { upper.removeLast() }
                upper.append(p)
            }
            lower.removeLast()
            upper.removeLast()
            let hull = lower + upper
            if hull.count >= 3 && hull.count <= 24 {
                var s = "\(area)"
                for p in hull { s += " \(p.0) \(p.1)" }
                lines.append(s)
            }
        }
    }
}

try lines.joined(separator: "\n").write(toFile: outFile, atomically: true, encoding: .utf8)
"""


def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def main():
    t0 = time.time()
    # Active rects (matching build_jiaxing_map.py with widened QINGFENG_CORRIDOR!)
    MAIN_RECT = (-3778.7, -4036.0, 5787.7, 4588.8)
    CHANGSHUI_CORRIDOR = rect_ll(30.7212, 120.7805, 30.7264, 120.8125)
    SAMS_SHUANGXI_RECT = rect_ll(30.7035, 120.7785, 30.7150, 120.8020)
    XIANGJIADANG_RECT = rect_ll(30.7905, 120.7850, 30.8180, 120.8240)
    QINGFENG_CORRIDOR = rect_ll(30.6945, 120.7895, 30.7264, 120.8035)
    SOUTH_STA_PRECINCT = rect_ll(30.6888, 120.7905, 30.6968, 120.8012)
    ACTIVE_RECTS = [MAIN_RECT, CHANGSHUI_CORRIDOR, SAMS_SHUANGXI_RECT, XIANGJIADANG_RECT, QINGFENG_CORRIDOR, SOUTH_STA_PRECINCT]

    def in_active(x, y):
        return any(r[0] <= x <= r[2] and r[1] <= y <= r[3] for r in ACTIVE_RECTS)

    tiles = set()
    for (x0, y0, x1, y1) in ACTIVE_RECTS:
        tx0, ty0 = game_to_tile_gcj(x0, y0, 17)
        tx1, ty1 = game_to_tile_gcj(x1, y1, 17)
        for tx in range(min(tx0, tx1), max(tx0, tx1) + 1):
            for ty in range(min(ty0, ty1), max(ty0, ty1) + 1):
                tiles.add((tx, ty))
    tiles = sorted(tiles)
    print(f"Scanning {len(tiles)} Amap z=17 tiles across ALL Jiaxing ACTIVE_RECTS...")

    diff_tiles = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=28) as ex:
        futs = {ex.submit(fetch_tile_pair, tx, ty): (tx, ty) for (tx, ty) in tiles}
        done = 0
        for fut in concurrent.futures.as_completed(futs):
            done += 1
            if fut.result():
                diff_tiles.add(futs[fut])
            if done % 300 == 0 or done == len(tiles):
                print(f"  Fetched {done}/{len(tiles)} tiles ({len(diff_tiles)} with buildings) in {time.time() - t0:.1f}s", flush=True)

    # Compile Swift fast block extractor once
    swift_file = os.path.join(CACHE_DIR, "amap_extract.swift")
    swift_bin = os.path.join(CACHE_DIR, "amap_extract")
    with open(swift_file, "w") as f:
        f.write(SWIFT_SRC)
    if not os.path.exists(swift_bin) or os.path.getmtime(swift_file) > os.path.getmtime(swift_bin):
        subprocess.check_call(["swiftc", "-O", swift_file, "-o", swift_bin])
    print(f"Compiled Swift extractor in {time.time() - t0:.1f}s")

    # Partition diff_tiles into overlapping 8x8 blocks (step=7 -> 1-tile overlap so zero buildings are ever clipped!)
    all_tx = [t[0] for t in diff_tiles]
    all_ty = [t[1] for t in diff_tiles]
    min_tx, max_tx = min(all_tx), max(all_tx)
    min_ty, max_ty = min(all_ty), max(all_ty)

    blocks = []
    for bx in range(min_tx, max_tx + 1, 7):
        for by in range(min_ty, max_ty + 1, 7):
            if any((bx + dx, by + dy) in diff_tiles for dx in range(8) for dy in range(8)):
                blocks.append((bx, by, 8, 8))
    print(f"Extracting building polygons from {len(blocks)} overlapping 8x8 tile blocks...")

    raw_polys = []

    def run_block(b):
        bx, by, cols, rows = b
        out_f = os.path.join(CACHE_DIR, f"blk_{bx}_{by}.txt")
        subprocess.check_call([swift_bin, CACHE_DIR, str(bx), str(by), str(cols), str(rows), out_f])
        res = []
        with open(out_f, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) < 7:
                    continue
                coords = [float(v) for v in parts[1:]]
                pts = []
                for i in range(0, len(coords), 2):
                    fx = bx + coords[i] / 256.0
                    fy = by + coords[i + 1] / 256.0
                    pts.append(tile_px_to_game(fx, fy, 17))
                if len(pts) >= 3:
                    res.append(pts)
        try:
            os.remove(out_f)
        except OSError:
            pass
        return res

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for res in ex.map(run_block, blocks):
            raw_polys.extend(res)
    print(f"Extracted {len(raw_polys)} raw Amap 2025 building footprints in {time.time() - t0:.1f}s")

    # Build spatial grid of existing real buildings (GBA + OSM + earlier holes) to keep ONLY missing ones!
    existing = json.load(open(REAL_PATH, "r"))
    cell = 60.0
    ex_grid = {}
    for b in existing:
        pts = [(float(p[0]), float(p[1])) for p in b.get("pts", [])]
        if len(pts) < 3:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx = sum(xs) / len(xs)
        cy = sum(ys) / len(ys)
        item = (min(xs), min(ys), max(xs), max(ys), cx, cy, float(b.get("h", 8.0)), abs(poly_area(pts)), pts)
        for gx in range(int(math.floor(item[0] / cell)), int(math.floor(item[2] / cell)) + 1):
            for gy in range(int(math.floor(item[1] / cell)), int(math.floor(item[3] / cell)) + 1):
                ex_grid.setdefault((gx, gy), []).append(item)

    # Deduplicate overlapping block results AND filter against existing real buildings
    kept_grid = {}
    new_buildings = []
    for pts in raw_polys:
        area = abs(poly_area(pts))
        if area < 38.0 or area > 42000.0:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx = sum(xs) / len(xs)
        cy = sum(ys) / len(ys)
        if not in_active(cx, cy):
            continue
        x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)

        # Skip if already represented in jiaxing_real_buildings.json (centroid or >=1 vertex inside, or center within 7m)
        dup = False
        near_hs = []
        for gx in range(int(math.floor((x0 - 15) / cell)), int(math.floor((x1 + 15) / cell)) + 1):
            for gy in range(int(math.floor((y0 - 15) / cell)), int(math.floor((y1 + 15) / cell)) + 1):
                for eb in ex_grid.get((gx, gy), ()):
                    d_c = math.hypot(cx - eb[4], cy - eb[5])
                    if d_c < 140.0 and eb[6] >= 3.0:
                        near_hs.append((d_c, eb[6], eb[7]))
                    if eb[2] < x0 - 4 or eb[0] > x1 + 4 or eb[3] < y0 - 4 or eb[1] > y1 + 4:
                        continue
                    if d_c < 8.0 or point_in_poly(cx, cy, eb[8]) or point_in_poly(eb[4], eb[5], pts):
                        dup = True
                        break
                    if any(point_in_poly(p[0], p[1], eb[8]) for p in pts):
                        dup = True
                        break
                if dup:
                    break
            if dup:
                break
        if dup:
            continue

        # Deduplicate against other newly extracted polygons from overlapping 8x8 blocks
        dup_new = False
        for gx in range(int(math.floor((x0 - 4) / cell)), int(math.floor((x1 + 4) / cell)) + 1):
            for gy in range(int(math.floor((y0 - 4) / cell)), int(math.floor((y1 + 4) / cell)) + 1):
                for nb in kept_grid.get((gx, gy), ()):
                    if math.hypot(cx - nb[0], cy - nb[1]) < 6.0 or point_in_poly(cx, cy, nb[2]) or point_in_poly(nb[0], nb[1], pts):
                        dup_new = True
                        break
                if dup_new:
                    break
            if dup_new:
                break
        if dup_new:
            continue

        # Estimate realistic raw GBA-scale height for this brand-new 2021-2025 building!
        in_zh = (-2350.0 <= cx <= 2450.0 and -2800.0 <= cy <= 1650.0)
        in_hsr_newtown = (3300.0 <= cx <= 5200.0 and 4400.0 <= cy <= 7300.0)  # 高铁新城 / 庆丰路北
        # Filter nearby GBA neighbors of comparable footprint size
        same_sz = [nh[1] for nh in sorted(near_hs)[:8] if 0.35 <= (nh[2] / max(1.0, area)) <= 2.8]
        if area < 220.0 and not in_zh and not in_hsr_newtown:
            est_h = 5.4  # Rural self-built house or small gatehouse
        elif area < 160.0:
            est_h = 4.6  # Gatehouse / kiosk / 1-2F street shop
        elif area >= 2400.0:
            est_h = 11.5  # Large industrial hall / school / mall podium
        elif in_hsr_newtown and 240.0 <= area <= 1450.0:
            # Brand-new 2022-2025 高铁新城 / 庆丰路 residential high-rise towers (12-18F!)
            est_h = 18.5 if area >= 420.0 else 15.5
        elif same_sz:
            same_sz.sort()
            est_h = max(5.2, min(26.0, same_sz[len(same_sz) // 2]))
        elif not in_zh and 280.0 <= area <= 1350.0:
            # Modern suburban residential slab / high-rise compound built 2021-2025
            est_h = 15.5
        else:
            est_h = 10.5

        if poly_area(pts) < 0:
            pts = list(reversed(pts))
        rec = {"pts": pts, "h": round(est_h, 2), "s": "amap_2025"}
        new_buildings.append(rec)
        for gx in range(int(math.floor(x0 / cell)), int(math.floor(x1 / cell)) + 1):
            for gy in range(int(math.floor(y0 / cell)), int(math.floor(y1 / cell)) + 1):
                kept_grid.setdefault((gx, gy), []).append((cx, cy, pts))

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(new_buildings, f, separators=(",", ":"))
    shot2_cnt = sum(1 for b in new_buildings if 3700 <= b["pts"][0][0] <= 4850 and 5450 <= b["pts"][0][1] <= 6350)
    print(f"Wrote {len(new_buildings)} NEW real 2021-2025 Jiaxing buildings to {OUT_PATH} "
          f"(including {shot2_cnt} in Screenshot 2 庆丰路北!) in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
