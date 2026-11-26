#!/usr/bin/env python3
"""
Extract 100% real-world building footprints and real 3D heights (in meters) for Jiaxing, China
from TUM GlobalBuildingAtlas (GBA.LoD1 + GBA.ODbLPolygon, ESSD 2025, satellite-derived + OSM),
streaming directly via parallel HTTP Range requests so only Jiaxing's bounding box is saved locally.

Output: tools/osm_cache/jiaxing_real_buildings.json
  Each record: {"k": key, "s": source, "h": height_m, "pts": [[x, y], ...]}
  where [x, y] are in Jiaxing game meters (LAT0=30.7550, LON0=120.7520, WGS-84).
"""

import concurrent.futures
import json
import math
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(HERE, "osm_cache", "jiaxing_real_buildings.json")

# Jiaxing game projection (exact match with tools/build_jiaxing_map.py)
LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0

# Exact EPSG:3857 bounding box covering FULL_BOUNDS of Jiaxing (with small margin)
X_MIN, X_MAX = 13429500.0, 13450800.0
Y_MIN, Y_MAX = 3591000.0, 3609800.0

URLS = {
    "odbl": "https://huggingface.co/datasets/zhu-xlab/GBA.ODbLPolygon/resolve/main/asiaeast/e120_n35_e125_n30.geojson",
    "poly": "https://huggingface.co/datasets/zhu-xlab/GBA.LoD1/resolve/main/Polygon/asiaeast/e120_n35_e125_n30.geojson",
    "lod1": "https://huggingface.co/datasets/zhu-xlab/GBA.LoD1/resolve/main/LoD1/asiaeast/e120_n35_e125_n30.json",
}

COORD_RE = re.compile(r"\[\s*(134[2345]\d+\.\d+)\s*,\s*(3[56]\d+\.\d+)\s*\]")


def epsg3857_to_game(mx, my):
    lon = mx * 180.0 / 20037508.34
    lat = (2.0 * math.atan(math.exp(my * math.pi / 20037508.34)) - math.pi * 0.5) * 180.0 / math.pi
    return round((lon - LON0) * KX, 2), round((LAT0 - lat) * KY, 2)


def get_content_length(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return int(r.headers.get("Content-Length", "0"))


def fetch_range(url, start, end, retries=4):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "Mozilla/5.0", "Range": f"bytes={start}-{end}"},
            )
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.read()
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(0.8 * (attempt + 1))


def scan_geojson_url(label, url, chunk_mb=12, workers=20):
    total = get_content_length(url)
    print(f"[{label}] size={total / 1e6:.1f} MB, scanning with {workers} parallel range workers...", flush=True)
    chunk_sz = chunk_mb * 1024 * 1024
    overlap = 65536  # 64KB overlap so no GeoJSON line is ever split across chunk boundaries
    ranges = []
    pos = 0
    while pos < total:
        end = min(total - 1, pos + chunk_sz - 1)
        r_start = max(0, pos - overlap) if pos > 0 else 0
        ranges.append((pos == 0, r_start, end))
        pos = end + 1

    # Fast byte-level prefilter prefixes for Jiaxing's X (13429500..13450800 -> "1343", "1344", "13450", "13429")
    # and Y (3591000..3609800 -> "359", "360")
    x_prefixes = (b"1343", b"1344", b"13450", b"13429")
    y_prefixes = (b", 359", b", 360", b",359", b",360")

    def process_chunk(args):
        is_first, s, e = args
        raw = fetch_range(url, s, e)
        lines = raw.split(b"\n")
        # Drop partial first/last lines (covered by adjacent chunk overlap)
        if not is_first and len(lines) > 1:
            lines = lines[1:]
        if e < total - 1 and len(lines) > 1:
            lines = lines[:-1]
        found = []
        for ln in lines:
            if b"Feature" not in ln:
                continue
            if not any(xp in ln for xp in x_prefixes):
                continue
            if not any(yp in ln for yp in y_prefixes):
                continue
            text = ln.decode("utf-8", errors="ignore").strip().rstrip(",")
            if not text.startswith("{"):
                continue
            try:
                feat = json.loads(text)
            except Exception:
                continue
            geom = feat.get("geometry")
            if not geom:
                continue
            gtype = geom.get("type")
            rings = []
            if gtype == "Polygon":
                coords = geom.get("coordinates")
                if coords and coords[0]:
                    rings.append(coords[0])
            elif gtype == "MultiPolygon":
                for poly in geom.get("coordinates", []):
                    if poly and poly[0]:
                        rings.append(poly[0])
            if not rings:
                continue
            ring = rings[0]
            # Check bbox against Jiaxing EPSG:3857 bounds
            mx0 = min(p[0] for p in ring)
            mx1 = max(p[0] for p in ring)
            my0 = min(p[1] for p in ring)
            my1 = max(p[1] for p in ring)
            if mx1 < X_MIN or mx0 > X_MAX or my1 < Y_MIN or my0 > Y_MAX:
                continue
            props = feat.get("properties") or {}
            src = str(props.get("source", ""))
            bid = str(props.get("id", ""))
            reg = str(props.get("region", "CHN"))
            key = f"{src}{bid}{reg}"
            # Convert ring to Jiaxing game meters (drop closing duplicate vertex)
            pts = [list(epsg3857_to_game(p[0], p[1])) for p in ring]
            if len(pts) >= 4 and pts[0] == pts[-1]:
                pts = pts[:-1]
            if len(pts) >= 3:
                found.append((key, src, pts))
        return found

    t0 = time.time()
    buildings = {}
    done_cnt = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(process_chunk, ranges):
            done_cnt += 1
            for key, src, pts in res:
                if key not in buildings:
                    buildings[key] = {"k": key, "s": src, "pts": pts}
            if done_cnt % 20 == 0 or done_cnt == len(ranges):
                dt = time.time() - t0
                mb_done = min(total, done_cnt * chunk_sz) / 1e6
                print(
                    f"  [{label}] {done_cnt}/{len(ranges)} chunks ({mb_done:.0f}/{total/1e6:.0f} MB) "
                    f"in {dt:.1f}s -> {len(buildings)} Jiaxing buildings",
                    flush=True,
                )
    return buildings


def attach_heights(url, buildings, chunk_mb=12, workers=16):
    if not buildings:
        return
    total = get_content_length(url)
    print(f"[lod1] size={total / 1e6:.1f} MB, matching heights for {len(buildings)} Jiaxing buildings...", flush=True)
    needed = set(buildings.keys())
    chunk_sz = chunk_mb * 1024 * 1024
    overlap = 4096
    ranges = []
    pos = 0
    while pos < total:
        end = min(total - 1, pos + chunk_sz - 1)
        r_start = max(0, pos - overlap) if pos > 0 else 0
        ranges.append((r_start, end))
        pos = end + 1

    # Entry format: "ours22h78MCHN": {"height": 8.2407, "var": 1.0641}
    entry_re = re.compile(rb'"([^"]+)":\s*\{\s*"height":\s*([0-9eE.+-]+)')

    def process_chunk(args):
        s, e = args
        raw = fetch_range(url, s, e)
        hits = []
        for m in entry_re.finditer(raw):
            k = m.group(1).decode("ascii", errors="ignore")
            if k in needed:
                try:
                    hits.append((k, round(float(m.group(2)), 2)))
                except ValueError:
                    pass
        return hits

    t0 = time.time()
    matched = 0
    done_cnt = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(process_chunk, ranges):
            done_cnt += 1
            for k, h in res:
                if "h" not in buildings[k]:
                    buildings[k]["h"] = h
                    matched += 1
            if done_cnt % 10 == 0 or done_cnt == len(ranges):
                print(f"  [lod1] {done_cnt}/{len(ranges)} chunks in {time.time()-t0:.1f}s -> matched {matched}/{len(buildings)}", flush=True)


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    t_all = time.time()
    b_odbl = scan_geojson_url("odbl", URLS["odbl"], chunk_mb=12, workers=16)
    b_poly = scan_geojson_url("poly", URLS["poly"], chunk_mb=16, workers=24)

    merged = {}
    # Prefer ODbL (OSM) first where keys overlap, then add all satellite-derived GBA polygons
    merged.update(b_odbl)
    for k, v in b_poly.items():
        if k not in merged:
            merged[k] = v
    print(f"Merged Jiaxing real buildings: {len(merged)} (ODbL={len(b_odbl)}, GBA.Polygon={len(b_poly)})", flush=True)

    attach_heights(URLS["lod1"], merged, chunk_mb=12, workers=16)

    out_list = list(merged.values())
    with_h = sum(1 for b in out_list if "h" in b and b["h"] > 0.5)
    print(f"Writing {len(out_list)} buildings ({with_h} with real LoD1 heights) -> {OUT_PATH}", flush=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out_list, f, ensure_ascii=False, separators=(",", ":"))
    sz = os.path.getsize(OUT_PATH) / 1e6
    print(f"Done in {time.time() - t_all:.1f}s ({sz:.1f} MB)", flush=True)


if __name__ == "__main__":
    main()
