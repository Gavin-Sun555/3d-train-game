"""
Attach real-world OpenStreetMap detail to the Seattle map buildings:
  * named buildings -> "name", "levels", "colour", "material", "lm" (landmark facade key)
  * shops / cafes / restaurants / banks -> street-facing ground-floor "storefronts"
    placed on the facade edge nearest to the real POI location
  * named plazas & parks -> "plazas"

Input is tools/osm_cache/seattle_downtown_extra.json (built by osm_cache/parse_osm_tiles.py
from api.openstreetmap.org map tiles, already projected into game coordinates).
Map data (c) OpenStreetMap contributors, ODbL.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "osm_cache", "seattle_downtown_extra.json")

# Landmark facade keys matched by OSM building name (handled by scripts/landmark_facades.gd)
LANDMARK_NAMES = {
    "Westlake Center": "westlake_mall",
    "Nordstrom": "nordstrom",
    "Pacific Place": "pacific_place",
    "Times Square Building": "times_square",
    "Mayflower Park Hotel": "mayflower",
    "Medical Dental Building": "medical_dental",
    "Sixth and Pine Building": "sixth_pine",
    "Securities Building": "securities",
    "Joshua Green Building": "joshua_green",
    "Coliseum Theater Building": "coliseum",
    "Washington Athletic Club Building": "wac",
    "Fourth and Pike Building": "fourth_pike",
    "Great Northern Building": "great_northern",
    "Terminal Sales Building": "terminal_sales",
    "Century Square": "century_square",
    "Amazon.com Day 1": "amazon_day1",
    "Amazon.com Doppler": "amazon_doppler",
    "Amazon.com re:Invent": "amazon_reinvent",
    "Amazon.com Blackfoot": "amazon_blackfoot",
    "Amazon.com Meeting Center": "amazon_meeting",
    "Denny Park Lutheran Church": "church",
    "Immanuel Lutheran Church": "church",
    "Center for Wooden Boats": "wooden_boats",
    # v2 extension: Seattle Center & waterfront
    "Space Needle": "space_needle",
    "Climate Pledge Arena": "climate_pledge",
    "MoPOP: Museum of Pop Culture": "mopop",
    "Pacific Science Center": "pacific_science",
    "Seattle Center Armory": "armory",
    "McCaw Hall": "mccaw",
    "Benaroya Hall": "benaroya",
    "Pier 57 - Miner's Landing": "pier_shed",
    "Pier 56": "pier_shed",
    "Pier 55": "pier_shed",
    "Pier 70": "pier_shed",
    "Corner Market": "pike_market",
    "Sanitary Public Market": "pike_market",
    "Market Heritage Center": "pike_market",
}

# Ground-floor bay width (m) by OSM shop / amenity kind
KIND_WIDTH = {
    "cafe": 6.0, "fast_food": 6.5, "bakery": 6.0, "deli": 6.0, "ice_cream": 5.0,
    "restaurant": 8.5, "bar": 7.5, "pub": 8.0, "nightclub": 8.0,
    "clothes": 10.0, "shoes": 8.0, "cosmetics": 8.0, "jewelry": 7.0, "books": 12.0,
    "bank": 9.0, "supermarket": 16.0, "department_store": 18.0, "convenience": 7.0,
    "pharmacy": 10.0, "cinema": 12.0, "theatre": 10.0, "hotel": 7.0, "mobile_phone": 7.0,
    "furniture": 12.0, "doityourself": 12.0, "hairdresser": 5.5, "beauty": 5.5,
}
SKIP_KINDS = {"vacant", "dentist", "clinic", "copyshop", "post_office", "library", "marketplace"}


def _seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        return math.hypot(px - ax, py - ay), 0.0
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy)), t


def _point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _ccw(poly):
    a = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        a += x0 * y1 - x1 * y0
    return a > 0.0


def _road_dist(px, py, road_segs):
    best = 1e9
    for ax, ay, bx, by, hw in road_segs:
        if max(ax, bx) < px - 40 or min(ax, bx) > px + 40 or max(ay, by) < py - 40 or min(ay, by) > py + 40:
            continue
        d, _ = _seg_dist(px, py, ax, ay, bx, by)
        best = min(best, d - hw)
    return best


def augment(buildings, roads):
    if not os.path.exists(CACHE):
        return [], [], []
    with open(CACHE, encoding="utf-8") as f:
        extra = json.load(f)

    road_segs = []
    for r in roads:
        pts = r["pts"]
        hw = float(r.get("width", 12.0)) * 0.5
        for i in range(len(pts) - 1):
            road_segs.append((pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], hw))

    # 1. Named building detail + landmark keys
    for ob in extra["buildings"]:
        cx, cy = ob["center"]
        hit = -1
        for bi, b in enumerate(buildings):
            if _point_in_poly(cx, cy, b["pts"]):
                hit = bi
                break
        if hit < 0:
            continue
        b = buildings[hit]
        if ob.get("name") and not b.get("name"):
            b["name"] = ob["name"]
            if ob["name"] in LANDMARK_NAMES:
                b["lm"] = LANDMARK_NAMES[ob["name"]]
        for k_src, k_dst in (("levels", "levels"), ("colour", "colour"), ("material", "material"), ("start", "year")):
            if ob.get(k_src) and k_dst not in b:
                b[k_dst] = ob[k_src]
        if ob.get("shop") in ("mall", "department_store") and "mall" not in b:
            b["mall"] = ob["shop"]

    # 2. Street-facing facade edges per building (outward normal, sidewalk room)
    facade_edges = []  # (bi, ei, p0, p1, n, length)
    for bi, b in enumerate(buildings):
        poly = b["pts"]
        if len(poly) < 3:
            continue
        ccw = _ccw(poly)
        for ei in range(len(poly)):
            a = poly[ei]
            c = poly[(ei + 1) % len(poly)]
            ex, ey = c[0] - a[0], c[1] - a[1]
            el = math.hypot(ex, ey)
            if el < 4.0:
                continue
            # outward normal (Godot renderer uses CCW-in-XZ polygons; normal = (-dy, dx) after making CCW)
            nx, ny = (ey / el, -ex / el) if ccw else (-ey / el, ex / el)
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            d_out = _road_dist(mx + nx * 3.0, my + ny * 3.0, road_segs)
            d_mid = _road_dist(mx, my, road_segs)
            if d_mid > 14.0 or d_out >= d_mid:
                continue
            facade_edges.append((bi, ei, a, c, (nx, ny), el))

    # 3. Place POIs on their nearest street-facing facade edge
    per_edge = {}
    for p in extra["pois"]:
        kind = p.get("kind") or ""
        if kind in SKIP_KINDS:
            continue
        lvl = str(p.get("level", "")).split(";")[0].strip()
        if lvl not in ("", "0", "1"):
            continue
        px, py = p["pos"]
        best = None
        for fe in facade_edges:
            bi, ei, a, c, n, el = fe
            if max(a[0], c[0]) < px - 26 or min(a[0], c[0]) > px + 26 or max(a[1], c[1]) < py - 26 or min(a[1], c[1]) > py + 26:
                continue
            d, t = _seg_dist(px, py, a[0], a[1], c[0], c[1])
            inside = _point_in_poly(px, py, buildings[bi]["pts"])
            lim = 24.0 if inside else 14.0
            if d > lim:
                continue
            score = d - (6.0 if inside else 0.0)
            if best is None or score < best[0]:
                best = (score, fe, t)
        if best is None:
            continue
        _, fe, t = best
        bi, ei, a, c, n, el = fe
        w = min(KIND_WIDTH.get(kind, 6.5), el - 0.8)
        if w < 3.2:
            continue
        per_edge.setdefault((bi, ei), []).append({"t": t, "w": w, "poi": p, "fe": fe})

    storefronts = []
    for key, lst in per_edge.items():
        lst.sort(key=lambda s: s["t"])
        bi, ei, a, c, n, el = lst[0]["fe"]
        # 1D packing along the edge: centre on the POI, then push apart, then clip to the edge
        centers = [min(max(s["t"] * el, s["w"] * 0.5 + 0.4), el - s["w"] * 0.5 - 0.4) for s in lst]
        for _ in range(6):
            for i in range(1, len(lst)):
                need = (lst[i - 1]["w"] + lst[i]["w"]) * 0.5 + 0.35
                gap = centers[i] - centers[i - 1]
                if gap < need:
                    push = (need - gap) * 0.5
                    centers[i - 1] -= push
                    centers[i] += push
            for i in range(len(lst)):
                centers[i] = min(max(centers[i], lst[i]["w"] * 0.5 + 0.4), el - lst[i]["w"] * 0.5 - 0.4)
        used = []
        for i, s in enumerate(lst):
            lo, hi = centers[i] - s["w"] * 0.5, centers[i] + s["w"] * 0.5
            if any(lo < u1 - 0.2 and hi > u0 + 0.2 for u0, u1 in used):
                # shrink to the free space on the right of the last used bay
                lo = max(lo, max(u1 for u0, u1 in used) + 0.35)
                if hi - lo < 3.2:
                    continue
            used.append((lo, hi))
            ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
            p = s["poi"]
            storefronts.append({
                "b": bi,
                "p0": [round(a[0] + ux * lo, 2), round(a[1] + uy * lo, 2)],
                "p1": [round(a[0] + ux * hi, 2), round(a[1] + uy * hi, 2)],
                "n": [round(n[0], 4), round(n[1], 4)],
                "name": p["name"],
                "kind": p.get("kind", ""),
                "brand": p.get("brand", ""),
            })

    plazas = []
    for pk in extra.get("parks", []):
        if pk.get("name"):
            plazas.append({"name": pk["name"], "kind": pk["kind"], "pts": pk["poly"]})
    piers = []
    for pr in extra.get("piers", []):
        if pr.get("closed") and len(pr["poly"]) >= 4:
            piers.append({"name": pr.get("name", ""), "pts": pr["poly"]})
    return storefronts, plazas, piers
