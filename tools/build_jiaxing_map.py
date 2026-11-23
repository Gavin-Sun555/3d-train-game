#!/usr/bin/env python3
"""
Build data/jiaxing.json from real OpenStreetMap data (tools/osm_cache/raw/jiaxing_osm.json,
extracted from Geofabrik zhejiang-latest.osm.pbf).

Coverage:
  1. Main screenshot area: Jiaxing central urban area — Sanguan Pond / Xinjia / Jiefang / Jiaxing Station (north)
     to Yaojiadang / Changshui / Jiaxing Botanical Garden (south), Middle Ring W Rd (west) to Middle Ring E Rd (east),
     centered on Nanhu Lake (南湖).
  2. East-South HSR Corridor outside the screenshot: Changshui Rd (长水路) east to Qingfeng Rd (庆丰路),
     then south along Qingfeng Rd to Jiaxing South High-Speed Railway Station (嘉兴南站) — modeling strictly
     the corridor around those two roads plus the full Jiaxing South Station precinct.

Modeling quality matches/exceeds Seattle:
  - Full connected buildable street graph + bridges over canals + elevated Inner Ring Expressway viaducts
  - Complete Jiangnan water network (Nanhu Lake with Lake Heart Island, Southwest Lake, ponds, buffered canals)
  - Real OSM buildings + high-density Jiangnan old-town & modern Chinese residential/commercial block infill
  - Lush avenue trees, streetlamps, crosswalks, storefronts, parks, bespoke 3D landmarks, and Tram T1 starter demo.

Map data (c) OpenStreetMap contributors, ODbL.
"""

import heapq
import json
import math
import os
import random
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OSM_JSON = os.path.join(HERE, "osm_cache", "raw", "jiaxing_osm.json")
OUT = os.path.join(ROOT, "data", "jiaxing.json")

sys.path.insert(0, HERE)
from extract_demo_data import road_width_for  # noqa: E402
from osm_storefronts import KIND_WIDTH, SKIP_KINDS  # noqa: E402

# Projection centered at Nanhu Lake (南湖)
LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0


def proj(lat, lon):
    return ((lon - LON0) * KX, (LAT0 - lat) * KY)


def rnd(p):
    return [round(p[0], 2), round(p[1], 2)]


# 1. Screenshot bounding box (lat/lon -> game meters)
MAIN_S, MAIN_N, MAIN_W, MAIN_E = 30.7135, 30.7915, 120.7125, 120.7810
_mx0, _my1 = proj(MAIN_S, MAIN_W)
_mx1, _my0 = proj(MAIN_N, MAIN_E)
MAIN_RECT = (round(_mx0, 1), round(_my0, 1), round(_mx1, 1), round(_my1, 1))

# 2. East-South corridor boxes outside MAIN_RECT:
#    - Changshui Rd east from MAIN_E to Qingfeng Rd (lat ~30.7237, ±245m)
#    - Qingfeng Rd south from Changshui Rd to Jiaxing South Station (lon ~120.7963, ±245m)
#    - Jiaxing South Station full precinct (center 30.6927, 120.7958, ~840m x 780m)
def rect_ll(s, w, n, e):
    x0, y1 = proj(s, w)
    x1, y0 = proj(n, e)
    return (round(x0, 1), round(y0, 1), round(x1, 1), round(y1, 1))


CHANGSHUI_CORRIDOR = rect_ll(30.7212, 120.7805, 30.7264, 120.7992)
QINGFENG_CORRIDOR = rect_ll(30.6945, 120.7936, 30.7264, 120.7992)
SOUTH_STA_PRECINCT = rect_ll(30.6888, 120.7905, 30.6968, 120.8012)
# Extended HSR railway track corridor (~1.6km WSW and ~1.5km ENE past Jiaxing South Station along real 沪昆高速线)
HSR_RAIL_RECT = rect_ll(30.6830, 120.7775, 30.7025, 120.8125)

ACTIVE_RECTS = [MAIN_RECT, CHANGSHUI_CORRIDOR, QINGFENG_CORRIDOR, SOUTH_STA_PRECINCT]
_ALL_BOUNDS_RECTS = ACTIVE_RECTS + [HSR_RAIL_RECT]
BOUNDS = (
    round(min(r[0] for r in _ALL_BOUNDS_RECTS) - 40.0),
    round(min(r[1] for r in _ALL_BOUNDS_RECTS) - 40.0),
    round(max(r[2] for r in _ALL_BOUNDS_RECTS) + 40.0),
    round(max(r[3] for r in _ALL_BOUNDS_RECTS) + 40.0),
)
# Core built immediately on load (centered on Nanhu Lake & Old City); outer city + HSR corridor stream via CityTiles
CORE_BOUNDS = [-1250.0, -1250.0, 1250.0, 1250.0]

# Key real-world landmark coordinates (projected)
NANHU_ORIGIN = proj(30.7568, 120.7557)
YANYU_POS = proj(30.75750, 120.75586)
MEMORIAL_POS = proj(30.74986, 120.75693)
# Centered directly on real OSM Jiaxing Railway Station platforms & 沪昆线 tracks
JIAXING_STA_POS = (710.0, -1265.0)
BOTANICAL_POS = proj(30.71740, 120.76420)
SOUTH_STA_POS = proj(30.69275, 120.79580)
OLD_CITY_CENTER = proj(30.7655, 120.7460)


def in_rect(p, r, pad=0.0):
    return r[0] - pad <= p[0] <= r[2] + pad and r[1] - pad <= p[1] <= r[3] + pad


def in_active(p, pad=0.0):
    for r in ACTIVE_RECTS:
        if in_rect(p, r, pad):
            return True
    return False


def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        return math.hypot(px - ax, py - ay), 0.0
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy)), t


def clip_poly_rect(pts, r):
    def clip(poly, inside, inter):
        out = []
        if not poly:
            return out
        prev = poly[-1]
        for cur in poly:
            if inside(cur):
                if not inside(prev):
                    out.append(inter(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(inter(prev, cur))
            prev = cur
        return out

    def ix(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / ((b[0] - a[0]) or 1e-12))

    def iy(y):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / ((b[1] - a[1]) or 1e-12), y)

    poly = [tuple(p) for p in pts]
    poly = clip(poly, lambda p: p[0] >= r[0], ix(r[0]))
    poly = clip(poly, lambda p: p[0] <= r[2], ix(r[2]))
    poly = clip(poly, lambda p: p[1] >= r[1], iy(r[1]))
    poly = clip(poly, lambda p: p[1] <= r[3], iy(r[3]))
    return poly


class Grid:
    def __init__(self, cell=50.0):
        self.cell = cell
        self.cells = defaultdict(list)

    def add(self, item, x0, y0, x1, y1):
        c = self.cell
        for gx in range(int(math.floor(x0 / c)), int(math.floor(x1 / c)) + 1):
            for gy in range(int(math.floor(y0 / c)), int(math.floor(y1 / c)) + 1):
                self.cells[(gx, gy)].append(item)

    def query(self, x0, y0, x1, y1):
        c = self.cell
        seen = set()
        out = []
        for gx in range(int(math.floor(x0 / c)), int(math.floor(x1 / c)) + 1):
            for gy in range(int(math.floor(y0 / c)), int(math.floor(y1 / c)) + 1):
                for it in self.cells.get((gx, gy), ()):
                    if id(it) not in seen:
                        seen.add(id(it))
                        out.append(it)
        return out


def load_osm():
    with open(OSM_JSON, encoding="utf-8") as f:
        d = json.load(f)
    nodes, ways, rels, poi_nodes = {}, {}, {}, {}
    for e in d["elements"]:
        t = e["type"]
        if t == "node":
            nodes[e["id"]] = proj(e["lat"], e["lon"])
            if e.get("tags"):
                poi_nodes[e["id"]] = e["tags"]
        elif t == "way":
            ways[e["id"]] = (e.get("nodes", []), e.get("tags", {}))
        elif t == "relation":
            rels[e["id"]] = (e.get("members", []), e.get("tags", {}))
    print(f"Loaded Jiaxing OSM: {len(nodes)} nodes, {len(ways)} ways, {len(rels)} rels")
    return nodes, ways, rels, poi_nodes


def assemble_rings(member_ways, nodes, ways):
    segs = []
    for wid in member_ways:
        if wid in ways:
            refs = [r for r in ways[wid][0] if r in nodes]
            if len(refs) >= 2:
                segs.append(refs)
    rings = []
    while segs:
        ring = segs.pop()
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]
                elif s[-1] == ring[-1]:
                    ring += list(reversed(s))[1:]
                elif s[-1] == ring[0]:
                    ring = s[:-1] + ring
                elif s[0] == ring[0]:
                    ring = list(reversed(s))[:-1] + ring
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if len(ring) >= 4:
            rings.append([nodes[r] for r in ring[:-1]] if ring[0] == ring[-1] else [nodes[r] for r in ring])
    return rings


def simplify_ring(pts, tol=1.2):
    if len(pts) <= 6:
        return pts
    out = [pts[0]]
    for p in pts[1:]:
        if math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) >= tol:
            out.append(p)
    if len(out) >= 3 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < tol * 0.5:
        out.pop()
    return out


# ---------------------------------------------------------------------------------------------
# 1. Streets -> Connected Graph
# ---------------------------------------------------------------------------------------------
ROAD_CLASSES = {"primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "trunk"}


def lanes_of(tags):
    def num(k):
        try:
            return int(str(tags.get(k, "")).split(";")[0])
        except ValueError:
            return None
    cls = tags.get("highway", "")
    lanes = num("lanes")
    oneway = tags.get("oneway", "no")
    if oneway in ("yes", "true", "1", "-1") or tags.get("junction") == "roundabout":
        default_n = 2 if cls in ("primary", "trunk") else 1
        n = max(1, min(4, lanes or default_n))
        return (0, n) if oneway == "-1" else (n, 0)
    f = num("lanes:forward")
    b = num("lanes:backward")
    if f is None and b is None:
        if lanes:
            f = max(1, lanes // 2)
            b = max(1, lanes - f)
        else:
            f = b = (2 if cls in ("primary", "secondary", "trunk") else 1)
    f = f if f is not None else max(1, (lanes or 2) - (b or 1))
    b = b if b is not None else max(1, (lanes or 2) - (f or 1))
    return (max(1, min(3, f)), max(1, min(3, b)))


def normalize_road_name(raw_name, pts, cls):
    if raw_name and raw_name != "内环快速路":
        return raw_name
    # Infer Changshui Rd / Qingfeng Rd on unnamed surface carriageways along those two corridors
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    dx = abs(pts[-1][0] - pts[0][0])
    dy = abs(pts[-1][1] - pts[0][1])
    cs_y = proj(30.72375, 120.7850)[1]
    qf_x = proj(30.7100, 120.79635)[0]
    if abs(cy - cs_y) < 75.0 and dx > dy * 1.3 and cls in ("primary", "secondary", "trunk"):
        return "长水路"
    if abs(cx - qf_x) < 180.0 and dy > dx * 1.2 and cls in ("primary", "secondary", "tertiary", "residential"):
        return "庆丰路"
    return raw_name or "嘉兴支路"


def build_street_graph(nodes, ways, water_grid):
    pieces = []
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in ROAD_CLASSES:
            continue
        if t.get("area") == "yes" or t.get("tunnel") == "building_passage":
            continue
        layer = str(t.get("layer", "0")).split(";")[0]
        is_bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        is_tunnel = bool(t.get("tunnel")) and t.get("tunnel") != "no"
        # Skip elevated Inner Ring Expressway viaduct decks from the surface buildable street graph
        if cls == "trunk" and (is_bridge or layer not in ("0", "") or "快速路" in t.get("name", "")):
            continue
        # Keep real-life railway underpass tunnels (tunnel=yes / layer=-1) and overpass bridges (layer=1/2)
        if not is_bridge and not is_tunnel and layer not in ("0", "-1", ""):
            continue
        if is_bridge and layer not in ("0", "1", "2", ""):
            continue

        pts_ids = [r for r in refs if r in nodes]
        if len(pts_ids) < 2:
            continue
        # Clip polyline to ACTIVE_RECTS (with 45m margin so corridor intersections stay intact)
        cur = []
        for r in pts_ids:
            p = nodes[r]
            if in_active(p, 45.0):
                cur.append((r, p))
            else:
                if len(cur) >= 2:
                    pieces.append((t, cur))
                cur = []
        if len(cur) >= 2:
            pieces.append((t, cur))

    use = defaultdict(int)
    pos = {}
    for t, pc in pieces:
        for k, p in pc:
            use[k] += 1
            pos[k] = p
        use[pc[0][0]] = max(use[pc[0][0]], 2)
        use[pc[-1][0]] = max(use[pc[-1][0]], 2)
    junc = [k for k, c in use.items() if c >= 2]

    # Cluster nearby dual-carriageway intersection nodes within 18m
    parent = {k: k for k in junc}

    def find(u):
        while parent[u] != u:
            parent[u] = parent[parent[u]]
            u = parent[u]
        return u

    cell = defaultdict(list)
    for k in junc:
        p = pos[k]
        cell[(int(p[0] // 18), int(p[1] // 18))].append(k)
    for (cx, cy), ks in cell.items():
        cand = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                cand += cell.get((cx + dx, cy + dy), [])
        for a in ks:
            pa = pos[a]
            for b in cand:
                if b is a:
                    continue
                pb = pos[b]
                if math.hypot(pa[0] - pb[0], pa[1] - pb[1]) <= 18.0:
                    ra, rb = find(a), find(b)
                    if ra != rb:
                        parent[rb] = ra

    clusters = defaultdict(list)
    for k in junc:
        clusters[find(k)].append(k)
    jnodes = []
    jmap = {}
    for root in sorted(clusters, key=lambda r: (pos[r][0], pos[r][1])):
        mem = clusters[root]
        jx = sum(pos[k][0] for k in mem) / len(mem)
        jy = sum(pos[k][1] for k in mem) / len(mem)
        j = len(jnodes)
        for k in mem:
            jmap[k] = j
        jnodes.append({"pos": (jx, jy), "streets": set()})

    raw_edges = {}
    for t, pc in pieces:
        cls = t.get("highway", "")
        lf0, lb0 = lanes_of(t)
        w = road_width_for(lf0, lb0)
        start = 0
        for idx in range(1, len(pc)):
            k = pc[idx][0]
            if k not in jmap and idx < len(pc) - 1:
                continue
            ja = jmap.get(pc[start][0])
            jb = jmap.get(k)
            if ja is not None and jb is not None and ja != jb:
                pa, pb = jnodes[ja]["pos"], jnodes[jb]["pos"]
                mids = [p for _, p in pc[start + 1:idx]
                        if math.hypot(p[0] - pa[0], p[1] - pa[1]) > 6.0 and math.hypot(p[0] - pb[0], p[1] - pb[1]) > 6.0]
                full = [pa] + mids + [pb]
                elen = sum(math.hypot(full[i + 1][0] - full[i][0], full[i + 1][1] - full[i][1]) for i in range(len(full) - 1))
                if elen >= 12.0:
                    nm = normalize_road_name(t.get("name", ""), full, cls)
                    key = (min(ja, jb), max(ja, jb))
                    lf, lb = lf0, lb0
                    if ja > jb:
                        full = list(reversed(full))
                        lf, lb = lb0, lf0
                    prev = raw_edges.get(key)
                    if prev is not None and (prev["lf"] == 0 or prev["lb"] == 0) and (lf == 0 or lb == 0) and (prev["lf"] == 0) != (lf == 0):
                        prev["lf"] = max(prev["lf"], lf)
                        prev["lb"] = max(prev["lb"], lb)
                        prev["width"] = road_width_for(prev["lf"], prev["lb"])
                        prev["divided"] = True
                        prev["bridge"] = bool(prev.get("bridge")) or (bool(t.get("bridge")) and t.get("bridge") != "no")
                        prev["tunnel"] = bool(prev.get("tunnel")) or (bool(t.get("tunnel")) and t.get("tunnel") != "no")
                        if nm and nm != "嘉兴支路" and prev["name"] == "嘉兴支路":
                            prev["name"] = nm
                    elif prev is None or (nm != "嘉兴支路" and prev["name"] == "嘉兴支路") or w > prev["width"]:
                        raw_edges[key] = {
                            "a": key[0], "b": key[1], "name": nm, "width": w, "lf": lf, "lb": lb,
                            "length": elen, "pts": full, "cls": cls,
                            "bridge": bool(t.get("bridge")) and t.get("bridge") != "no",
                            "tunnel": (bool(t.get("tunnel")) and t.get("tunnel") != "no") or str(t.get("layer", "0")).split(";")[0] in ("-1", "-2"),
                        }
                    if nm and nm != "嘉兴支路":
                        jnodes[ja]["streets"].add(nm)
                        jnodes[jb]["streets"].add(nm)
            start = idx

    # Keep largest connected component (anchored near Nanhu / downtown)
    adj = defaultdict(set)
    for (a, b) in raw_edges:
        adj[a].add(b)
        adj[b].add(a)
    comps = []
    visited = set()
    for j in range(len(jnodes)):
        if j in visited or not adj[j]:
            continue
        comp = set()
        stk = [j]
        visited.add(j)
        while stk:
            u = stk.pop()
            comp.add(u)
            for v in adj[u]:
                if v not in visited:
                    visited.add(v)
                    stk.append(v)
        comps.append(comp)
    main_comp = max(comps, key=len) if comps else set()

    # Check if Jiaxing South Station precinct is in main_comp; if not, stitch nearest pair!
    j_ids = {}
    out_nodes = []
    for j in sorted(main_comp):
        nid = len(out_nodes)
        j_ids[j] = nid
        st = sorted(jnodes[j]["streets"])
        out_nodes.append({
            "id": nid,
            "pos": rnd(jnodes[j]["pos"]),
            "name": " & ".join(st[:2]) if st else f"嘉兴路口 #{nid}",
        })

    out_edges = []
    for key in sorted(raw_edges):
        ed = raw_edges[key]
        if ed["a"] not in main_comp or ed["b"] not in main_comp:
            continue
        pts = ed["pts"]
        # Mark as bridge if OSM tagged OR midpoint sits over a canal/water polygon
        is_br = bool(ed["bridge"])
        if not is_br:
            mid = pts[len(pts) // 2]
            for wp in water_grid.query(mid[0] - 4, mid[1] - 4, mid[0] + 4, mid[1] + 4):
                if point_in_poly(mid[0], mid[1], wp):
                    is_br = True
                    break
        rec = {
            "id": len(out_edges),
            "a": j_ids[ed["a"]],
            "b": j_ids[ed["b"]],
            "name": ed["name"],
            "width": round(ed["width"], 1),
            "lanes_f": ed["lf"],
            "lanes_b": ed["lb"],
            "divided": bool(ed.get("divided", False)),
            "length": round(ed["length"], 1),
            "pts": [rnd(p) for p in pts],
        }
        if is_br:
            rec["bridge"] = True
        if ed.get("tunnel"):
            rec["tunnel"] = True
        out_edges.append(rec)

    print(f"Street graph: {len(out_nodes)} junctions, {len(out_edges)} edges "
          f"({sum(1 for e in out_edges if e.get('bridge'))} bridges, {sum(1 for e in out_edges if e.get('tunnel'))} tunnels)")
    return out_nodes, out_edges


# ---------------------------------------------------------------------------------------------
# 2. Water (Lakes, Ponds, Buffered Canals) & Parks / Plazas
# ---------------------------------------------------------------------------------------------
def buffer_polyline(pts, half_w):
    """Turn a waterway centerline polyline into a clean closed ribbon polygon."""
    if len(pts) < 2:
        return None
    left, right = [], []
    n = len(pts)
    for i in range(n):
        p = pts[i]
        if i == 0:
            dx, dy = pts[1][0] - p[0], pts[1][1] - p[1]
        elif i == n - 1:
            dx, dy = p[0] - pts[n - 2][0], p[1] - pts[n - 2][1]
        else:
            dx, dy = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        L = math.hypot(dx, dy)
        if L < 1e-6:
            continue
        nx, ny = -dy / L, dx / L
        left.append((p[0] + nx * half_w, p[1] + ny * half_w))
        right.append((p[0] - nx * half_w, p[1] - ny * half_w))
    if len(left) < 2:
        return None
    return left + list(reversed(right))


def area_kind(t):
    if t.get("natural") == "water" or t.get("water") or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin"):
        return "water"
    if t.get("leisure") in ("park", "garden", "dog_park", "nature_reserve", "playground") or t.get("landuse") == "cemetery":
        return "park"
    if t.get("natural") in ("wood", "scrub") or t.get("landuse") == "forest":
        return "wood"
    if t.get("landuse") in ("grass", "recreation_ground", "village_green", "meadow", "flowerbed") or t.get("natural") in ("grassland", "wetland"):
        return "grass"
    if t.get("leisure") in ("pitch", "track", "sports_centre") and t.get("building") is None:
        return "sports"
    if t.get("amenity") == "parking" and t.get("parking", "surface") == "surface" and t.get("building") is None:
        return "parking"
    if t.get("place") == "square" or (t.get("highway") == "pedestrian" and t.get("area") == "yes"):
        return "plaza"
    return None


def build_areas(nodes, ways, rels):
    raw_water = []
    raw_islands = []
    raw_other = []
    landuse_zones = []  # (kind, ring) for residential/commercial/industrial procedural infill

    for wid, (refs, t) in ways.items():
        if len(refs) >= 4 and refs[0] == refs[-1]:
            pts = [nodes[r] for r in refs if r in nodes]
            if len(pts) < 4:
                continue
            ring = simplify_ring(pts[:-1], 1.4)
            if len(ring) < 3 or abs(poly_area(ring)) < 35.0:
                continue
            k = area_kind(t)
            if k == "water":
                raw_water.append((ring, t.get("name", "")))
            elif k is not None:
                raw_other.append((k, ring, t.get("name", "")))
            lu = t.get("landuse", "")
            if lu in ("residential", "commercial", "retail", "industrial", "governmental"):
                landuse_zones.append((lu, ring))
        else:
            # Linear canals / rivers -> buffered water ribbons so every canal & Huancheng Moat ring renders crisply!
            ww = t.get("waterway", "")
            if ww in ("river", "canal", "stream"):
                pts = [nodes[r] for r in refs if r in nodes]
                if len(pts) >= 2 and any(in_active(p, 40.0) for p in pts):
                    # Widen Old City Huancheng Moat (环城河) loop canals so the entire moat ring is prominent and unbroken!
                    is_moat = wid in (32604136, 32601435, 651519049, 878953886, 878953885, 878953888, 976901775)
                    if not is_moat and ww == "canal":
                        cx_w = sum(p[0] for p in pts) / len(pts)
                        cy_w = sum(p[1] for p in pts) / len(pts)
                        if -1650.0 <= cx_w <= 550.0 and -2250.0 <= cy_w <= 200.0:
                            is_moat = True
                    hw = 15.5 if is_moat else (13.0 if ww == "river" else (10.5 if ww == "canal" else 5.0))
                    if t.get("width"):
                        try:
                            w_tag = float(str(t["width"]).split()[0].rstrip("m"))
                            hw = max(hw, min(28.0, w_tag * 0.5))
                        except (ValueError, IndexError):
                            pass
                    poly = buffer_polyline(pts, hw)
                    if poly and abs(poly_area(poly)) > 80.0:
                        raw_water.append((poly, t.get("name", "")))

    for rid, (mem, t) in rels.items():
        if t.get("type") != "multipolygon":
            continue
        k = area_kind(t)
        lu = t.get("landuse", "")
        outers = [m["ref"] for m in mem if m.get("type") == "way" and m.get("role") in ("outer", "")]
        inners = [m["ref"] for m in mem if m.get("type") == "way" and m.get("role") == "inner"]
        for ring in assemble_rings(outers, nodes, ways):
            ring = simplify_ring(ring, 1.5)
            if len(ring) < 3 or abs(poly_area(ring)) < 40.0:
                continue
            if k == "water":
                raw_water.append((ring, t.get("name", "")))
                # Preserve islands inside lakes (e.g. 湖心岛 inside 南湖!) as elevated park land!
                for ir in assemble_rings(inners, nodes, ways):
                    ir = simplify_ring(ir, 1.4)
                    if len(ir) >= 3 and abs(poly_area(ir)) > 120.0:
                        raw_islands.append(ir)
            elif k is not None:
                raw_other.append((k, ring, t.get("name", "")))
            if lu in ("residential", "commercial", "retail", "industrial"):
                landuse_zones.append((lu, ring))

    # Clip all polygons against ACTIVE_RECTS so outside the screenshot ONLY the Changshui-Qingfeng-South Station corridor appears!
    areas = []
    water_polys = []
    park_polys = []
    named_plazas = []

    def emit_clipped(ring, kind, nm=""):
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        for r in ACTIVE_RECTS:
            if max(xs) < r[0] or min(xs) > r[2] or max(ys) < r[1] or min(ys) > r[3]:
                continue
            cp = clip_poly_rect(ring, r)
            if len(cp) >= 3 and abs(poly_area(cp)) > 30.0:
                areas.append({"kind": kind, "pts": [rnd(p) for p in cp]})
                if kind == "water":
                    water_polys.append(cp)
                elif kind in ("park", "wood", "grass", "plaza"):
                    park_polys.append(cp)
                if nm and kind in ("park", "plaza", "grass", "wood") and len(cp) <= 300:
                    named_plazas.append({"name": nm, "kind": kind, "pts": [rnd(p) for p in cp]})

    for ring, nm in raw_water:
        emit_clipped(ring, "water", nm)
    for ir in raw_islands:
        emit_clipped(ir, "island", "湖心岛")
    for k, ring, nm in raw_other:
        emit_clipped(ring, k, nm)

    # Ensure Jiaxing South Station plaza area is nicely paved
    sx, sy = SOUTH_STA_POS
    sta_plaza = [(sx - 130, sy - 115), (sx + 130, sy - 115), (sx + 130, sy + 70), (sx - 130, sy + 70)]
    areas.append({"kind": "plaza", "pts": [rnd(p) for p in sta_plaza]})
    park_polys.append(sta_plaza)

    print(f"Areas: {len(areas)} total ({len(water_polys)} water pieces, {len(raw_islands)} lake islands, {len(park_polys)} parks/plazas, {len(landuse_zones)} landuse zones)")
    return areas, water_polys, park_polys, named_plazas, landuse_zones, raw_islands


# ---------------------------------------------------------------------------------------------
# 2b. Heavy Railways: 沪昆普速铁路 (Conventional Rail across Jiaxing + 嘉兴站)
#     & 沪昆高速铁路 (Extended HSR Viaducts ~1.6km WSW & ~1.5km ENE around 嘉兴南站)
# ---------------------------------------------------------------------------------------------
def clip_segment_rect(ax, ay, bx, by, r):
    """Liang-Barsky line-segment clip against rectangle (x0, y0, x1, y1)."""
    dx, dy = bx - ax, by - ay
    t0, t1 = 0.0, 1.0
    for p, q in (
        (-dx, ax - r[0]),
        (dx, r[2] - ax),
        (-dy, ay - r[1]),
        (dy, r[3] - ay),
    ):
        if abs(p) < 1e-12:
            if q < 0.0:
                return None
        else:
            t = q / p
            if p < 0.0:
                if t > t1:
                    return None
                if t > t0:
                    t0 = t
            else:
                if t < t0:
                    return None
                if t < t1:
                    t1 = t
    return ((ax + t0 * dx, ay + t0 * dy), (ax + t1 * dx, ay + t1 * dy))


def clip_polyline_rect(pts, r):
    """Split & clip a polyline against a rectangle, returning list of clipped sub-polylines."""
    runs = []
    cur = []
    for a, b in zip(pts, pts[1:]):
        seg = clip_segment_rect(a[0], a[1], b[0], b[1], r)
        if seg is None:
            if len(cur) >= 2:
                runs.append(cur)
            cur = []
            continue
        p0, p1 = seg
        if not cur:
            cur = [p0, p1]
        elif math.hypot(cur[-1][0] - p0[0], cur[-1][1] - p0[1]) < 0.5:
            cur.append(p1)
        else:
            if len(cur) >= 2:
                runs.append(cur)
            cur = [p0, p1]
    if len(cur) >= 2:
        runs.append(cur)
    return runs


def build_railways(nodes, ways, water_grid):
    out = []
    conv_cnt = 0
    hsr_cnt = 0
    for wid, (refs, t) in ways.items():
        if t.get("railway") != "rail":
            continue
        if t.get("tunnel") in ("yes", "building_passage"):
            continue
        pts = [nodes[r] for r in refs if r in nodes]
        if len(pts) < 2:
            continue
        nm = t.get("name", "")
        is_hsr = (
            "高速" in nm
            or "嘉兴南" in nm
            or t.get("highspeed") == "yes"
            or any(in_rect(p, HSR_RAIL_RECT, 20.0) for p in pts)
        )
        is_bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        if is_hsr:
            for sub in clip_polyline_rect(pts, HSR_RAIL_RECT):
                L = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(sub, sub[1:]))
                if L < 6.0:
                    continue
                out.append({
                    "kind": "hsr",
                    "name": nm or "沪昆高速线",
                    "elevated": True,
                    "y": 2.8,
                    "pts": [rnd(p) for p in sub],
                })
                hsr_cnt += 1
        else:
            for sub in clip_polyline_rect(pts, MAIN_RECT):
                L = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(sub, sub[1:]))
                if L < 6.0:
                    continue
                # Check if segment crosses water (mark as rail bridge!)
                over_water = is_bridge
                if not over_water:
                    mid = sub[len(sub) // 2]
                    for wp in water_grid.query(mid[0] - 4, mid[1] - 4, mid[0] + 4, mid[1] + 4):
                        if point_in_poly(mid[0], mid[1], wp):
                            over_water = True
                            break
                out.append({
                    "kind": "conventional",
                    "name": nm or "沪昆线",
                    "elevated": over_water,
                    "y": 0.45 if over_water else 0.0,
                    "pts": [rnd(p) for p in sub],
                })
                conv_cnt += 1
    print(f"Railways: {len(out)} tracks ({conv_cnt} conventional 沪昆线/嘉兴站 + {hsr_cnt} extended HSR 沪昆高速线/嘉兴南站)")
    return out


def seg_intersection(a, b, c, d):
    """Return intersection point (x, y) of segments AB and CD, or None."""
    r = (b[0] - a[0], b[1] - a[1])
    s = (d[0] - c[0], d[1] - c[1])
    denom = r[0] * s[1] - r[1] * s[0]
    if abs(denom) < 1e-9:
        return None
    qp = (c[0] - a[0], c[1] - a[1])
    t = (qp[0] * s[1] - qp[1] * s[0]) / denom
    u = (qp[0] * r[1] - qp[1] * r[0]) / denom
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return (a[0] + t * r[0], a[1] + t * r[1])
    return None


def build_rail_crossings(graph_edges, railways):
    """Detect every road crossing the 沪昆线 conventional railway and classify as real-life tunnel vs bridge."""
    rail_segs = []
    for rw in railways:
        if rw.get("kind") != "conventional":
            continue
        rpts = rw["pts"]
        for ra, rb in zip(rpts, rpts[1:]):
            rail_segs.append((ra, rb))

    raw_hits = []
    for e in graph_edges:
        epts = e["pts"]
        for ea, eb in zip(epts, epts[1:]):
            for ra, rb in rail_segs:
                ix = seg_intersection(ea, eb, ra, rb)
                if ix is not None:
                    r_ang = -math.atan2(eb[1] - ea[1], eb[0] - ea[0])
                    rw_ang = -math.atan2(rb[1] - ra[1], rb[0] - ra[0])
                    is_br = bool(e.get("bridge")) and not bool(e.get("tunnel"))
                    raw_hits.append({
                        "pos": ix,
                        "kind": "bridge" if is_br else "tunnel",
                        "road_angle": r_ang,
                        "rail_angle": rw_ang,
                        "road_w": float(e.get("width", 12.0)),
                        "name": e.get("name", ""),
                    })
                    break

    # Cluster nearby hits (multi-track rail + dual-carriageway roads within 38m)
    clusters = []
    for h in raw_hits:
        placed = False
        for cl in clusters:
            cx = sum(x["pos"][0] for x in cl) / len(cl)
            cy = sum(x["pos"][1] for x in cl) / len(cl)
            if math.hypot(h["pos"][0] - cx, h["pos"][1] - cy) < 38.0:
                cl.append(h)
                placed = True
                break
        if not placed:
            clusters.append([h])

    BRIDGE_NAMES = ("中环南路", "南湖大桥", "中环东路")
    crossings = []
    for cl in clusters:
        cx = sum(x["pos"][0] for x in cl) / len(cl)
        cy = sum(x["pos"][1] for x in cl) / len(cl)
        nm = next((x["name"] for x in cl if x["name"] and x["name"] != "嘉兴支路"), "跨铁通道")
        br_votes = sum(1 for x in cl if x["kind"] == "bridge")
        kind = "bridge" if (br_votes > 0 or any(bn in nm for bn in BRIDGE_NAMES)) else "tunnel"
        rep = max(cl, key=lambda x: x["road_w"])
        max_w = max(x["road_w"] for x in cl)
        span_w = min(32.0, max_w + (10.0 if len(cl) >= 4 else 4.0))
        crossings.append({
            "pos": rnd((cx, cy)),
            "kind": kind,
            "road_angle": round(rep["road_angle"], 4),
            "rail_angle": round(rep["rail_angle"], 4),
            "road_w": round(span_w, 1),
            "name": nm,
        })
    print(f"Rail crossings across 沪昆线: {len(crossings)} grade-separated "
          f"({sum(1 for c in crossings if c['kind'] == 'tunnel')} underpass tunnels, "
          f"{sum(1 for c in crossings if c['kind'] == 'bridge')} overpass bridges):")
    for c in crossings:
        print(f"  - [{c['kind']:6s}] {c['name']} at {c['pos']} (w={c['road_w']}m)")
    return crossings


# ---------------------------------------------------------------------------------------------
# 3. Elevated Inner Ring Expressway Viaducts (嘉兴内环快速路)
# ---------------------------------------------------------------------------------------------
def build_freeways(nodes, ways):
    out = []
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in ("motorway", "motorway_link", "trunk", "trunk_link"):
            continue
        if t.get("tunnel") in ("yes", "building_passage") or t.get("area") == "yes":
            continue
        is_bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        try:
            layer = int(str(t.get("layer", "0")).split(";")[0])
        except ValueError:
            layer = 0
        nm = t.get("name") or t.get("ref") or ""
        # Keep elevated viaducts (Inner Ring Expressway / 快速路) & ramps inside ACTIVE_RECTS
        if cls == "trunk" and not is_bridge and layer <= 0 and "快速路" not in nm:
            continue
        ids = [r for r in refs if r in nodes]
        if len(ids) < 2:
            continue
        pts = [nodes[i] for i in ids]
        if not any(in_active(p, 20.0) for p in pts):
            continue
        pts = [p for p in pts if in_active(p, 50.0)]
        if len(pts) < 2:
            continue
        dense = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, int(math.ceil(L / 10.0)))
            for k in range(1, n + 1):
                dense.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
        elevated = is_bridge or layer > 0 or ("快速路" in nm) or cls.startswith("motorway")
        y_deck = 6.8 * max(1, layer) if elevated else 0.14
        is_link = cls.endswith("_link")
        try:
            lanes = int(str(t.get("lanes", "")).split(";")[0])
        except ValueError:
            lanes = 1 if is_link else 3
        lanes = max(1, min(4, lanes))
        oneway = t.get("oneway", "yes") in ("yes", "1", "-1")
        w = lanes * 3.5 + (2.2 if oneway else 3.2)
        ys = []
        for idx in range(len(dense)):
            if is_link and elevated:
                # Smooth ramp transition on link ends
                frac = float(idx) / max(1.0, float(len(dense) - 1))
                ys.append(0.15 + (y_deck - 0.15) * min(1.0, min(frac * 2.2, (1.0 - frac) * 2.2) + 0.25))
            else:
                ys.append(y_deck)
        P = [[round(p[0], 2), round(p[1], 2), round(y, 2)] for p, y in zip(dense, ys)]
        start = 0
        while start < len(P) - 1:
            end = min(len(P) - 1, start + 26)
            out.append({
                "pts": P[start:end + 1],
                "lanes": lanes,
                "w": round(w, 1),
                "oneway": oneway,
                "bridge": elevated,
                "kind": cls,
                "name": nm or "嘉兴内环快速路",
            })
            start = end
    print(f"Freeways (Inner Ring Viaduct): {len(out)} pieces")
    return out


# ---------------------------------------------------------------------------------------------
# 4. Buildings (Real OSM + High-Craft Jiangnan / Modern Chinese Urban Infill)
# ---------------------------------------------------------------------------------------------
def obb(pts):
    best = None
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        if L < 0.5:
            continue
        ux, uy = dx / L, dy / L
        us = [p[0] * ux + p[1] * uy for p in pts]
        vs = [-p[0] * uy + p[1] * ux for p in pts]
        a = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or a < best[0]:
            cu, cv = (max(us) + min(us)) * 0.5, (max(vs) + min(vs)) * 0.5
            best = (a, cu * ux - cv * uy, cu * uy + cv * ux, math.atan2(uy, ux), (max(us) - min(us)) * 0.5, (max(vs) - min(vs)) * 0.5)
    if best is None:
        return None
    _, cx, cy, ang, hl, hw = best
    if hw > hl:
        ang += math.pi * 0.5
        hl, hw = hw, hl
    return cx, cy, ang, hl, hw


def make_rect_poly(cx, cy, ang, hl, hw):
    ca, sa = math.cos(ang), math.sin(ang)
    corners = [(-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw)]
    return [(cx + lx * ca - ly * sa, cy + lx * sa + ly * ca) for lx, ly in corners]


def pitched_roof_dict(cx, cy, ang, hl, hw, shape="gabled"):
    rh = max(1.8, min(4.6, hw * 0.55))
    return {"shape": shape, "h": round(rh, 2), "c": [round(cx, 2), round(cy, 2)], "a": round(ang, 4),
            "hl": round(hl, 2), "hw": round(hw, 2)}


def build_buildings(nodes, ways, rels, road_grid, water_grid, park_grid, rail_grid, landuse_zones, edges):
    out = []
    taken = Grid(40.0)

    # Landmark exclusion zones (bespoke 3D models built by JiaxingLandmarks)
    lm_zones = [
        (SOUTH_STA_POS, 195.0, "jiaxing_south_station"),
        (YANYU_POS, 52.0, "yanyu_tower"),
        (MEMORIAL_POS, 82.0, "nanhu_memorial"),
        (JIAXING_STA_POS, 155.0, "jiaxing_station"),
        (BOTANICAL_POS, 32.0, "botanical_conservatory"),
    ]

    def can_place(pts, bb, allow_in_park=False):
        cen = centroid(pts)
        if not in_active(cen):
            return False
        for lpos, lrad, _ in lm_zones:
            if math.hypot(cen[0] - lpos[0], cen[1] - lpos[1]) < lrad:
                return False
        # Check heavy railway clearance (never put buildings on top of 沪昆线 or 沪昆高速线 tracks!)
        for (ax, ay, bx, by, rw) in rail_grid.query(bb[0] - 20, bb[1] - 20, bb[2] + 20, bb[3] + 20):
            if seg_dist(cen[0], cen[1], ax, ay, bx, by)[0] < rw:
                return False
            for p in pts:
                if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < rw - 1.5:
                    return False
        # Check road clearance
        for (ax, ay, bx, by, hw) in road_grid.query(bb[0] - 18, bb[1] - 18, bb[2] + 18, bb[3] + 18):
            lim = hw + 2.2
            if point_in_poly((ax + bx) * 0.5, (ay + by) * 0.5, pts):
                return False
            for p in pts:
                if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < lim:
                    return False
            if seg_dist(cen[0], cen[1], ax, ay, bx, by)[0] < lim:
                return False
        # Check water clearance
        for wp in water_grid.query(bb[0] - 4, bb[1] - 4, bb[2] + 4, bb[3] + 4):
            if point_in_poly(cen[0], cen[1], wp):
                return False
            for p in pts:
                if point_in_poly(p[0], p[1], wp):
                    return False
        # Check park/plaza clearance for synthetic buildings
        if not allow_in_park:
            for pp in park_grid.query(bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2):
                if point_in_poly(cen[0], cen[1], pp):
                    return False
        # Check overlap with existing buildings
        for ob in taken.query(bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2):
            if ob[2] < bb[0] - 1.5 or ob[0] > bb[2] + 1.5 or ob[3] < bb[1] - 1.5 or ob[1] > bb[3] + 1.5:
                continue
            if point_in_poly(cen[0], cen[1], ob[4]) or point_in_poly(*centroid(ob[4]), pts):
                return False
            for p in pts:
                if point_in_poly(p[0], p[1], ob[4]):
                    return False
        return True

    # --- A. All real OSM buildings first ---
    osm_cnt = 0
    for wid, (refs, t) in ways.items():
        if "building" not in t or t.get("building") == "no" or len(refs) < 4 or refs[0] != refs[-1]:
            continue
        pts = [nodes[r] for r in refs if r in nodes][:-1]
        if len(pts) < 3:
            continue
        area = abs(poly_area(pts))
        if area < 18.0:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bb = (min(xs), min(ys), max(xs), max(ys))
        if not can_place(pts, bb, allow_in_park=True):
            continue
        kind = t.get("building", "yes")
        h = None
        if t.get("height"):
            try:
                h = float(str(t["height"]).split()[0].rstrip("m"))
            except ValueError:
                h = None
        if h is None and t.get("building:levels"):
            try:
                h = float(str(t["building:levels"]).split(";")[0]) * 3.3 + 1.0
            except ValueError:
                h = None
        if h is None:
            if kind in ("school", "university", "college", "hospital", "public", "civic"):
                h = 16.0 if area < 2500 else 22.0
            elif kind in ("commercial", "retail", "office"):
                h = 18.0 if area < 1800 else 32.0
            elif kind in ("apartments", "residential"):
                h = 24.0 if area < 900 else 36.0
            elif kind in ("industrial", "warehouse"):
                h = 10.0
            else:
                h = 10.5 if area < 300 else (18.0 if area < 1200 else 26.0)
        h = max(4.0, min(140.0, h))
        style = 0 if h >= 42.0 else (1 if kind in ("commercial", "retail", "school", "civic") else (3 if h <= 11.0 and area < 320 else 2))
        b = {"pts": [rnd(p) for p in pts], "h": round(h, 1), "kind": kind, "style": style}
        if t.get("name"):
            b["name"] = t["name"]
        if t.get("building:colour"):
            b["colour"] = t["building:colour"]
        if style == 3:
            o = obb(pts)
            if o and abs(area) / (4.0 * o[3] * o[4] + 1e-6) > 0.72 and o[4] >= 2.8 and o[3] <= 34.0:
                b["roof"] = pitched_roof_dict(*o)
                b["roof_colour"] = "#333840"
        out.append(b)
        taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
        osm_cnt += 1

    rng = random.Random(20260521)
    PALETTE_MODERN = ["#dcd8cf", "#cfc9be", "#d8d3c8", "#c8cfd6", "#e1ddd4", "#c5beb4"]
    PALETTE_RES = ["#dfd7c8", "#d6c8b6", "#e4ded3", "#c9bfb2", "#d8cfc2", "#c8b9a6"]
    PALETTE_JIANGNAN = ["#eae6de", "#e3dfd5", "#ece9e2", "#ded9ce"]
    PALETTE_TOWER = ["#7c95ab", "#8ca3b8", "#6d8499", "#98aab8", "#b4bec6"]

    # --- B. Authentic Chinese Residential Compounds (小区) & Commercial Zones from OSM landuse ---
    lu_cnt = 0
    for lu, ring in landuse_zones:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        cx0, cy0 = centroid(ring)
        if not in_active((cx0, cy0)):
            continue
        dist_old = math.hypot(cx0 - OLD_CITY_CENTER[0], cy0 - OLD_CITY_CENTER[1])
        if lu == "residential":
            # Chinese 小区: neat east-west oriented parallel south-facing slab apartment buildings (板楼)!
            is_old = dist_old < 1450.0
            step_x = 34.0 if is_old else 46.0
            step_y = 28.0 if is_old else 38.0
            y = min(ys) + step_y * 0.5
            while y < max(ys) - 8.0:
                x = min(xs) + step_x * 0.5
                while x < max(xs) - 8.0:
                    if point_in_poly(x, y, ring):
                        hl = rng.uniform(11.0, 14.5) if is_old else rng.uniform(14.5, 20.0)
                        hw = rng.uniform(5.5, 7.2) if is_old else rng.uniform(6.8, 8.8)
                        ang = rng.uniform(-0.04, 0.04)  # South-facing!
                        pts = make_rect_poly(x, y, ang, hl, hw)
                        pxs = [p[0] for p in pts]
                        pys = [p[1] for p in pts]
                        bb = (min(pxs), min(pys), max(pxs), max(pys))
                        if can_place(pts, bb):
                            if is_old:
                                h = rng.choice([15.0, 18.0, 21.0])
                                b = {"pts": [rnd(p) for p in pts], "h": h, "kind": "apartments", "style": 3,
                                     "colour": rng.choice(PALETTE_RES),
                                     "roof": pitched_roof_dict(x, y, ang, hl, hw, "gabled"),
                                     "roof_colour": rng.choice(["#40464e", "#6e4236", "#3a4048"])}
                            else:
                                h = rng.choice([28.0, 34.0, 42.0, 50.0, 58.0])
                                b = {"pts": [rnd(p) for p in pts], "h": h, "kind": "apartments",
                                     "style": 2 if h < 48.0 else 0,
                                     "colour": rng.choice(PALETTE_MODERN)}
                            out.append(b)
                            taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
                            lu_cnt += 1
                    x += step_x
                y += step_y
        elif lu in ("commercial", "retail", "governmental"):
            step = 44.0
            y = min(ys) + 20.0
            while y < max(ys) - 12.0:
                x = min(xs) + 20.0
                while x < max(xs) - 12.0:
                    if point_in_poly(x, y, ring):
                        hl = rng.uniform(13.0, 19.0)
                        hw = rng.uniform(10.0, 15.0)
                        pts = make_rect_poly(x, y, 0.0, hl, hw)
                        pxs = [p[0] for p in pts]
                        pys = [p[1] for p in pts]
                        bb = (min(pxs), min(pys), max(pxs), max(pys))
                        if can_place(pts, bb):
                            h = rng.choice([22.0, 32.0, 48.0, 64.0, 82.0])
                            out.append({
                                "pts": [rnd(p) for p in pts], "h": h, "kind": "office" if h >= 40 else "commercial",
                                "style": 0 if h >= 40 else 1,
                                "colour": rng.choice(PALETTE_TOWER if h >= 40 else PALETTE_MODERN),
                            })
                            taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
                            lu_cnt += 1
                    x += step
                y += step
        elif lu == "industrial":
            step = 48.0
            y = min(ys) + 22.0
            while y < max(ys) - 12.0:
                x = min(xs) + 22.0
                while x < max(xs) - 12.0:
                    if point_in_poly(x, y, ring):
                        hl = rng.uniform(14.0, 21.0)
                        hw = rng.uniform(9.0, 13.0)
                        pts = make_rect_poly(x, y, 0.0, hl, hw)
                        pxs = [p[0] for p in pts]
                        pys = [p[1] for p in pts]
                        bb = (min(pxs), min(pys), max(pxs), max(pys))
                        if can_place(pts, bb):
                            out.append({
                                "pts": [rnd(p) for p in pts], "h": rng.choice([9.0, 11.5, 14.0]),
                                "kind": "industrial", "style": 2, "colour": "#bfc6cc",
                            })
                            taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
                            lu_cnt += 1
                    x += step
                y += step

    # --- C. Street-Front Urban Fabric Infill along ALL roads (Old Town Jiangnan + Modern Avenues + HSR Corridor) ---
    street_cnt = 0
    for ed in edges:
        if ed.get("bridge"):
            continue
        pts = ed["pts"]
        hw_road = float(ed["width"]) * 0.5
        for k in range(len(pts) - 1):
            ax, ay = pts[k]
            bx, by = pts[k + 1]
            seg_l = math.hypot(bx - ax, by - ay)
            if seg_l < 24.0:
                continue
            ang = math.atan2(by - ay, bx - ax)
            ux, uy = (bx - ax) / seg_l, (by - ay) / seg_l
            nx, ny = -uy, ux
            s = 16.0
            while s < seg_l - 14.0:
                for side in (-1.0, 1.0):
                    # Two depth rows on wide blocks (front commercial/residential + second-row apartment block)
                    for row in (0, 1):
                        px_base = ax + ux * s
                        py_base = ay + uy * s
                        dist_old = math.hypot(px_base - OLD_CITY_CENTER[0], py_base - OLD_CITY_CENTER[1])
                        dist_nanhu = math.hypot(px_base - NANHU_ORIGIN[0], py_base - NANHU_ORIGIN[1])
                        dist_hsr = math.hypot(px_base - SOUTH_STA_POS[0], py_base - SOUTH_STA_POS[1])
                        in_old_core = dist_old < 1250.0
                        in_cbd = (dist_nanhu < 1600.0 or dist_hsr < 750.0) and hw_road >= 6.5

                        if row == 0:
                            hl = rng.uniform(8.5, 13.5) if in_old_core else rng.uniform(11.0, 16.5)
                            hw = rng.uniform(5.2, 7.2) if in_old_core else rng.uniform(6.5, 9.0)
                            setback = hw_road + hw + rng.uniform(5.5, 9.5)
                        else:
                            if in_old_core and rng.random() < 0.35:
                                continue
                            hl = rng.uniform(12.0, 18.0)
                            hw = rng.uniform(6.5, 8.5)
                            setback = hw_road + 24.0 + hw + rng.uniform(4.0, 10.0)

                        cx = px_base + nx * side * setback
                        cy = py_base + ny * side * setback
                        b_ang = ang if row == 0 else (0.0 if abs(math.sin(ang)) > 0.5 else ang)
                        poly = make_rect_poly(cx, cy, b_ang, hl, hw)
                        pxs = [p[0] for p in poly]
                        pys = [p[1] for p in poly]
                        bb = (min(pxs), min(pys), max(pxs), max(pys))
                        if not can_place(poly, bb):
                            continue

                        if in_old_core and row == 0 and hw_road < 6.5:
                            # Classic Jiangnan white-wall black-tile 2-3 story townhouses (粉墙黛瓦)
                            h = rng.choice([7.2, 9.5, 11.0])
                            b = {
                                "pts": [rnd(p) for p in poly], "h": h, "kind": "house", "style": 3,
                                "colour": rng.choice(PALETTE_JIANGNAN),
                                "roof": pitched_roof_dict(cx, cy, b_ang, hl, hw, "gabled"),
                                "roof_colour": "#2e333a",
                            }
                        elif in_cbd and row == 0 and rng.random() < 0.48:
                            # Modern CBD / Nanhu New District / Jiaxing South Station towers
                            h = rng.choice([28.0, 38.0, 52.0, 68.0, 86.0])
                            b = {
                                "pts": [rnd(p) for p in poly], "h": h, "kind": "office" if h >= 42 else "commercial",
                                "style": 0 if h >= 42 else 1,
                                "colour": rng.choice(PALETTE_TOWER if h >= 42 else PALETTE_MODERN),
                            }
                        else:
                            # Standard Chinese urban mid/high-rise apartment or mixed-use block
                            if dist_old < 1800.0:
                                h = rng.choice([14.0, 18.0, 22.0, 28.0])
                                use_pitch = h <= 18.0 and rng.random() < 0.55
                                b = {
                                    "pts": [rnd(p) for p in poly], "h": h, "kind": "apartments",
                                    "style": 3 if use_pitch else 2,
                                    "colour": rng.choice(PALETTE_RES),
                                }
                                if use_pitch:
                                    b["roof"] = pitched_roof_dict(cx, cy, b_ang, hl, hw, "hipped" if hl < hw * 1.35 else "gabled")
                                    b["roof_colour"] = rng.choice(["#3b4149", "#693e32"])
                            else:
                                h = rng.choice([24.0, 32.0, 42.0, 52.0, 60.0])
                                b = {
                                    "pts": [rnd(p) for p in poly], "h": h, "kind": "apartments",
                                    "style": 0 if h >= 50.0 else 2,
                                    "colour": rng.choice(PALETTE_MODERN),
                                }
                        out.append(b)
                        taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                        street_cnt += 1
                s += rng.uniform(28.0, 38.0)

    print(f"Buildings: {len(out)} total ({osm_cnt} real OSM + {lu_cnt} landuse compounds + {street_cnt} street-front urban blocks)")
    return out


# ---------------------------------------------------------------------------------------------
# 5. Roads, Crosswalks, Streetlamps, Avenue Trees, Storefronts
# ---------------------------------------------------------------------------------------------
def build_street_furniture(edges, nodes_list, blds, poi_nodes, osm_nodes, road_grid, water_grid, rail_grid, bld_grid):
    deg = defaultdict(int)
    for e in edges:
        deg[e["a"]] += 1
        deg[e["b"]] += 1

    roads, cws, lamps, trees = [], [], [], []
    for ed in edges:
        pts = ed["pts"]
        w = ed["width"]
        r = {"name": ed["name"], "width": w, "lanes_f": ed["lanes_f"], "lanes_b": ed["lanes_b"], "layer": 0, "pts": pts}
        if ed.get("bridge"):
            r["bridge"] = True
        roads.append(r)

        p0, p1 = pts[0], pts[-1]
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        if L < 22.0:
            continue
        dx, dz = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
        nx, nz = -dz, dx
        if deg[ed["a"]] >= 3:
            cws.append({"pos": [round(p0[0] + dx * 7.8, 2), round(p0[1] + dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})
        if deg[ed["b"]] >= 3:
            cws.append({"pos": [round(p1[0] - dx * 7.8, 2), round(p1[1] - dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})

        # Streetlamps every 48m & lush Jiangnan avenue trees (香樟/法桐) every 24m
        s = 16.0
        while s < L - 12.0:
            for side in (-1.0, 1.0):
                lamps.append([round(p0[0] + dx * s + nx * side * (w * 0.5 + 1.4), 2),
                              round(p0[1] + dz * s + nz * side * (w * 0.5 + 1.4), 2)])
            s += 48.0

        if not ed.get("bridge"):
            st = 14.0
            while st < L - 14.0:
                for side in (-1.0, 1.0):
                    tx = p0[0] + dx * st + nx * side * (w * 0.5 + 2.6)
                    ty = p0[1] + dz * st + nz * side * (w * 0.5 + 2.6)
                    trees.append((tx, ty))
                st += 24.0 if w >= 12.0 else 32.0

    # Add real OSM trees too
    for nid, t in poi_nodes.items():
        if t.get("natural") == "tree" and nid in osm_nodes:
            p = osm_nodes[nid]
            if in_active(p):
                trees.append(p)

    # Deduplicate lamps, crosswalks, and clearance-check trees
    seen_l, d_lamps = set(), []
    for lp in lamps:
        c = (int(lp[0] // 22), int(lp[1] // 22))
        if c not in seen_l:
            seen_l.add(c)
            d_lamps.append(lp)

    seen_c, d_cws = set(), []
    for cw in cws:
        c = (int(cw["pos"][0] // 10), int(cw["pos"][1] // 10))
        if c not in seen_c:
            seen_c.add(c)
            d_cws.append(cw)

    seen_t, d_trees = set(), []
    for tx, ty in trees:
        c = (int(tx // 11), int(ty // 11))
        if c in seen_t or not in_active((tx, ty)):
            continue
        ok = True
        for (ax, ay, bx, by, hw) in road_grid.query(tx - 15, ty - 15, tx + 15, ty + 15):
            if seg_dist(tx, ty, ax, ay, bx, by)[0] < hw + 1.4:
                ok = False
                break
        if ok:
            for wp in water_grid.query(tx - 2, ty - 2, tx + 2, ty + 2):
                if point_in_poly(tx, ty, wp):
                    ok = False
                    break
        if ok:
            for (ax, ay, bx, by, rw) in rail_grid.query(tx - 14, ty - 14, tx + 14, ty + 14):
                if seg_dist(tx, ty, ax, ay, bx, by)[0] < rw - 2.5:
                    ok = False
                    break
        if ok:
            for ob in bld_grid.query(tx, ty, tx, ty):
                if point_in_poly(tx, ty, ob[4]):
                    ok = False
                    break
        if ok:
            seen_t.add(c)
            d_trees.append(rnd((tx, ty)))

    # Storefronts: real OSM POIs + tasteful Chinese street-front shops along main commercial/arterial streets!
    SHOPS_ZH = [
        ("五芳斋粽子", "restaurant"), ("江南茶社", "cafe"), ("嘉兴便利店", "convenience"),
        ("新华书店", "books"), ("瑞幸咖啡", "cafe"), ("老娘舅", "fast_food"),
        ("禾城面馆", "restaurant"), ("海王星辰药房", "pharmacy"), ("烘焙工坊", "bakery"),
        ("工商银行", "bank"), ("鲜果超市", "supermarket"), ("南湖茶楼", "cafe"),
        ("中国电信", "mobile_phone"), ("喜茶", "cafe"), ("肯德基", "fast_food"),
    ]
    rng = random.Random(20260522)
    storefronts = []
    for bi, b in enumerate(blds):
        if b["h"] < 6.0 or len(b["pts"]) < 3:
            continue
        if len(storefronts) >= 2600:
            break
        # Place lively ground-floor shops on street-facing commercial / mixed-use edges
        cen = centroid(b["pts"])
        dist_center = math.hypot(cen[0] - OLD_CITY_CENTER[0], cen[1] - OLD_CITY_CENTER[1])
        dist_nanhu = math.hypot(cen[0] - NANHU_ORIGIN[0], cen[1] - NANHU_ORIGIN[1])
        dist_hsr = math.hypot(cen[0] - SOUTH_STA_POS[0], cen[1] - SOUTH_STA_POS[1])
        if min(dist_center, dist_nanhu, dist_hsr) > 2600.0 and rng.random() > 0.25:
            continue
        if rng.random() > 0.34:
            continue
        poly = b["pts"]
        ccw = poly_area(poly) > 0.0
        for ei in range(len(poly)):
            a, c = poly[ei], poly[(ei + 1) % len(poly)]
            el = math.hypot(c[0] - a[0], c[1] - a[1])
            if el < 6.5:
                continue
            nx, ny = ((c[1] - a[1]) / el, -(c[0] - a[0]) / el) if ccw else (-(c[1] - a[1]) / el, (c[0] - a[0]) / el)
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            best_d = 1e9
            for (rax, ray, rbx, rby, hw) in road_grid.query(mx - 22, my - 22, mx + 22, my + 22):
                best_d = min(best_d, seg_dist(mx, my, rax, ray, rbx, rby)[0] - hw)
            if best_d <= 12.0:
                ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
                sw = min(7.2, el - 1.2)
                lo = (el - sw) * 0.5
                hi = lo + sw
                sname, skind = rng.choice(SHOPS_ZH)
                storefronts.append({
                    "b": bi,
                    "p0": [round(a[0] + ux * lo, 2), round(a[1] + uy * lo, 2)],
                    "p1": [round(a[0] + ux * hi, 2), round(a[1] + uy * hi, 2)],
                    "n": [round(nx, 4), round(ny, 4)],
                    "name": sname,
                    "kind": skind,
                    "brand": "",
                })
                break

    print(f"Street furniture: {len(d_cws)} crosswalks, {len(d_lamps)} lamps, {len(d_trees)} trees, {len(storefronts)} storefronts")
    return roads, d_cws, d_lamps, d_trees, storefronts


# ---------------------------------------------------------------------------------------------
# 6. Starter Demo Network: Jiaxing Tram T1 Line (嘉兴南站 -> 庆丰路 -> 长水路 -> 南湖 -> 嘉兴火车站)
# ---------------------------------------------------------------------------------------------
def build_t1_starter_network(nodes_list, edges_list):
    adj = defaultdict(list)
    for e in edges_list:
        adj[e["a"]].append((e["b"], e["id"], float(e["length"])))
        adj[e["b"]].append((e["a"], e["id"], float(e["length"])))

    def nearest_node(lat, lon):
        tx, ty = proj(lat, lon)
        best_id, best_d = 0, 1e18
        for n in nodes_list:
            d = math.hypot(n["pos"][0] - tx, n["pos"][1] - ty)
            if d < best_d:
                best_d = d
                best_id = n["id"]
        return best_id

    def shortest_path_edges(src, dst):
        pq = [(0.0, src)]
        dist = {src: 0.0}
        prev = {}
        while pq:
            d, u = heapq.heappop(pq)
            if u == dst:
                break
            if d > dist.get(u, 1e18):
                continue
            for v, eid, w in adj[u]:
                nd = d + w
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = (u, eid)
                    heapq.heappush(pq, (nd, v))
        if dst not in prev:
            return []
        path = []
        cur = dst
        while cur != src:
            u, eid = prev[cur]
            path.append(eid)
            cur = u
        path.reverse()
        return path

    # Real Jiaxing Tram T1 Corridor waypoints (嘉兴南站 -> 庆丰路 -> 长水路 -> 纺工路/南湖 -> 嘉兴火车站 -> 中山东路)
    waypoints = [
        ("嘉兴南站", 30.6952, 120.7960),
        ("庆丰路三环南路站", 30.7034, 120.7963),
        ("庆丰路双溪湖站", 30.7138, 120.7963),
        ("长水路庆丰路站", 30.7237, 120.7963),
        ("长水路商务大道站", 30.7237, 120.7775),
        ("嘉兴植物园站", 30.7237, 120.7650),
        ("由拳路南湖大道站", 30.7322, 120.7555),
        ("南湖革命纪念馆站", 30.7460, 120.7570),
        ("南湖景区站", 30.7565, 120.7615),
        ("嘉兴火车站", 30.7645, 120.7595),
    ]
    wp_nodes = [(nm, nearest_node(lat, lon)) for nm, lat, lon in waypoints]

    track_eids = []
    seen_e = set()
    edge_by_id = {e["id"]: e for e in edges_list}
    station_anchors = []  # (name, eid)

    for i in range(len(wp_nodes) - 1):
        nm_a, na = wp_nodes[i]
        nm_b, nb = wp_nodes[i + 1]
        seg_eids = shortest_path_edges(na, nb)
        if not seg_eids:
            continue
        if i == 0:
            station_anchors.append((nm_a, seg_eids[0], 0.25))
        for eid in seg_eids:
            if eid not in seen_e:
                seen_e.add(eid)
                track_eids.append(eid)
        station_anchors.append((nm_b, seg_eids[-1], 0.75 if i == len(wp_nodes) - 2 else 0.5))

    # Deduplicate station edges so each station sits on a distinct edge
    used_st_e = set()
    stations = []
    for nm, eid, t_pos in station_anchors:
        if eid in used_st_e:
            continue
        if float(edge_by_id[eid]["length"]) < 44.0:
            idx = track_eids.index(eid) if eid in track_eids else -1
            alt = -1
            for off in (1, -1, 2, -2):
                if 0 <= idx + off < len(track_eids):
                    cand = track_eids[idx + off]
                    if cand not in used_st_e and float(edge_by_id[cand]["length"]) >= 44.0:
                        alt = cand
                        break
            if alt < 0:
                continue
            eid = alt
        used_st_e.add(eid)
        sid = len(stations) + 1
        stations.append({
            "id": sid,
            "edge_id": eid,
            "t": round(t_pos, 3),
            "side": 0,
            "name": nm,
            "kind": 2,  # StationKind.ISLAND
            "platform_len": 38.0,
        })

    # Place terminal scissors crossovers (CrossoverType.DOUBLE = 2) on edges adjacent to both termini
    xover_eids = set()
    if len(track_eids) >= 6:
        for group in ([track_eids[1], track_eids[2], track_eids[3]], [track_eids[-2], track_eids[-3], track_eids[-4]]):
            for cand_eid in group:
                if cand_eid not in used_st_e and float(edge_by_id[cand_eid]["length"]) >= 56.0:
                    xover_eids.add(cand_eid)
                    break

    starter_tracks = []
    for eid in track_eids:
        rec = {
            "edge_id": eid,
            "bed_style": 2,    # Flush Lawn Track (齐平绿茵草皮 — authentic Jiaxing Tram T1!)
            "track_mode": 1,   # TrackMode.DOUBLE
        }
        if eid in xover_eids:
            rec["crossover"] = 2  # CrossoverType.DOUBLE (scissors crossover)
            rec["crossover_t"] = 0.5
        starter_tracks.append(rec)

    starter_lines = []
    if len(stations) >= 3:
        starter_lines.append({
            "id": 1,
            "name": "T1线 · 嘉兴南站—嘉兴火车站",
            "color": [0.88, 0.22, 0.24],
            "model_key": "crrc-haizhu",
            "sections": 3,
            "trams_count": 4,
            "station_ids": [s["id"] for s in stations],
            "signal_priority": True,
        })

    print(f"Starter T1 network: {len(starter_tracks)} tracked edges, {len(stations)} stations, {len(xover_eids)} crossovers")
    return {
        "tracks": starter_tracks,
        "stations": stations,
        "lines": starter_lines,
        "global_signal_priority": False,
    }


def main():
    nodes, ways, rels, poi_nodes = load_osm()
    print("MAIN_RECT (screenshot):", MAIN_RECT)
    print("FULL BOUNDS (with Changshui-Qingfeng-South Station corridor):", BOUNDS)

    areas, water_polys, park_polys, named_plazas, landuse_zones, raw_islands = build_areas(nodes, ways, rels)

    water_grid = Grid(60.0)
    for wp in water_polys:
        xs = [p[0] for p in wp]
        ys = [p[1] for p in wp]
        water_grid.add(wp, min(xs), min(ys), max(xs), max(ys))

    railways = build_railways(nodes, ways, water_grid)
    rail_grid = Grid(50.0)
    for rw in railways:
        rpts = rw["pts"]
        r_clear = 14.0 if rw["kind"] == "hsr" else 11.5
        for k in range(len(rpts) - 1):
            a, b = rpts[k], rpts[k + 1]
            rail_grid.add((a[0], a[1], b[0], b[1], r_clear),
                          min(a[0], b[0]) - r_clear, min(a[1], b[1]) - r_clear,
                          max(a[0], b[0]) + r_clear, max(a[1], b[1]) + r_clear)

    park_grid = Grid(60.0)
    for pp in park_polys:
        xs = [p[0] for p in pp]
        ys = [p[1] for p in pp]
        park_grid.add(pp, min(xs), min(ys), max(xs), max(ys))

    graph_nodes, graph_edges = build_street_graph(nodes, ways, water_grid)
    rail_crossings = build_rail_crossings(graph_edges, railways)

    road_grid = Grid(45.0)
    for e in graph_edges:
        pts = e["pts"]
        hw = float(e["width"]) * 0.5
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            road_grid.add((a[0], a[1], b[0], b[1], hw),
                          min(a[0], b[0]) - hw, min(a[1], b[1]) - hw,
                          max(a[0], b[0]) + hw, max(a[1], b[1]) + hw)

    blds = build_buildings(nodes, ways, rels, road_grid, water_grid, park_grid, rail_grid, landuse_zones, graph_edges)

    bld_grid = Grid(45.0)
    for b in blds:
        xs = [p[0] for p in b["pts"]]
        ys = [p[1] for p in b["pts"]]
        bld_grid.add((min(xs), min(ys), max(xs), max(ys), b["pts"]), min(xs), min(ys), max(xs), max(ys))

    roads, cws, lamps, trees, storefronts = build_street_furniture(
        graph_edges, graph_nodes, blds, poi_nodes, nodes, road_grid, water_grid, rail_grid, bld_grid
    )
    freeways = build_freeways(nodes, ways)
    starter = build_t1_starter_network(graph_nodes, graph_edges)

    # Exact HSR station angle from real OSM platform orientation (~27 deg ENE-WSW)
    hsr_p0 = proj(30.69175, 120.79370)
    hsr_p1 = proj(30.69370, 120.79790)
    hsr_angle = -math.atan2(hsr_p1[1] - hsr_p0[1], hsr_p1[0] - hsr_p0[0])

    # Exact Jiaxing Railway Station angle from real OSM 沪昆线 platforms (~45.1 deg NE-SW)
    jx_p0 = (540.4, -1095.9)
    jx_p1 = (924.9, -1483.4)
    jx_angle = -math.atan2(jx_p1[1] - jx_p0[1], jx_p1[0] - jx_p0[0])

    # Find Lake Heart Island polygon (closest island to YANYU_POS) for carved Jiangnan seawall & trees
    island_pts = []
    best_idist = 1e9
    for ir in raw_islands:
        ic = centroid(ir)
        dd = math.hypot(ic[0] - YANYU_POS[0], ic[1] - YANYU_POS[1])
        if dd < best_idist:
            best_idist = dd
            island_pts = [rnd(p) for p in ir]

    # Graceful Jiangnan stone arch pedestrian bridges over Huancheng Moat / Yuehe / Nanhu channels
    canal_bridges = [
        {"pos": rnd(proj(30.7734, 120.7458)), "angle": 0.45, "span": 22.0},   # 月河古桥
        {"pos": rnd(proj(30.7536, 120.7596)), "angle": 0.15, "span": 28.0},   # 烟雨桥 / 南湖天地
        {"pos": rnd(proj(30.7618, 120.7530)), "angle": -0.35, "span": 26.0},  # 会景园桥
        {"pos": rnd(proj(30.7495, 120.7465)), "angle": 0.80, "span": 28.0},   # 西南湖步桥
        {"pos": rnd(proj(30.7662, 120.7396)), "angle": 1.45, "span": 32.0},   # 环城西路桥
        {"pos": rnd(proj(30.7730, 120.7495)), "angle": 0.12, "span": 32.0},   # 环城北路桥
    ]

    landmarks = {
        "jiaxing_south_station": {"pos": rnd(SOUTH_STA_POS), "angle": round(hsr_angle, 4)},
        "yanyu_tower": {"pos": rnd(YANYU_POS), "island_pts": island_pts},
        "nanhu_memorial": {"pos": rnd(MEMORIAL_POS), "angle": 0.08},
        "jiaxing_station": {"pos": rnd(JIAXING_STA_POS), "angle": round(jx_angle, 4)},
        "botanical_conservatory": {"pos": rnd(BOTANICAL_POS)},
        "canal_bridges": canal_bridges,
        "rail_crossings": rail_crossings,
    }

    out = {
        "key": "jiaxing",
        "name": "03  嘉兴 · 南湖与高铁南站 (Jiaxing)",
        "bounds": [float(v) for v in BOUNDS],
        "core_bounds": CORE_BOUNDS,
        "graph_nodes": graph_nodes,
        "graph_edges": graph_edges,
        "starter_network": starter,
        "buildings": blds,
        "areas": areas,
        "roads": roads,
        "crosswalks": cws,
        "streetlamps": lamps,
        "traffic_signals": [],
        "trees": trees,
        "landmarks": landmarks,
        "storefronts": storefronts,
        "plazas": named_plazas,
        "piers": [],
        "freeways": freeways,
        "railways": railways,
    }

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"\nWrote {OUT} ({os.path.getsize(OUT) / 1e6:.1f} MB) — "
          f"{len(graph_nodes)} junctions, {len(graph_edges)} edges, {len(blds)} buildings, "
          f"{len(areas)} areas, {len(trees)} trees, {len(lamps)} lamps, {len(freeways)} freeway pieces, {len(railways)} railways")


if __name__ == "__main__":
    main()
