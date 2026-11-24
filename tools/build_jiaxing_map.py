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


# 1. Expanded urban bounding box (west of Middle Ring W -> east past 3rd Ring E / Hilton / Wanda!)
MAIN_S, MAIN_N, MAIN_W, MAIN_E = 30.7135, 30.7915, 120.7125, 120.8125
_mx0, _my1 = proj(MAIN_S, MAIN_W)
_mx1, _my0 = proj(MAIN_N, MAIN_E)
MAIN_RECT = (round(_mx0, 1), round(_my0, 1), round(_mx1, 1), round(_my1, 1))

# 2. Additional city & scenic precincts seamlessly joined to MAIN_RECT:
#    - Sam's Club / Shuangxi Lake precinct (south of MAIN_RECT, linking smoothly to Qingfeng Rd -> HSR South Sta.)
#    - Xiangjiadang Wetland Park & Lake (northeast of MAIN_RECT, full lake & wetland parkways)
#    - Qingfeng Rd south to Jiaxing South High-Speed Railway Station
def rect_ll(s, w, n, e):
    x0, y1 = proj(s, w)
    x1, y0 = proj(n, e)
    return (round(x0, 1), round(y0, 1), round(x1, 1), round(y1, 1))


CHANGSHUI_CORRIDOR = rect_ll(30.7212, 120.7805, 30.7264, 120.8125)
SAMS_SHUANGXI_RECT = rect_ll(30.7035, 120.7785, 30.7150, 120.8020)
XIANGJIADANG_RECT = rect_ll(30.7905, 120.7850, 30.8180, 120.8240)
QINGFENG_CORRIDOR = rect_ll(30.6945, 120.7936, 30.7264, 120.7992)
SOUTH_STA_PRECINCT = rect_ll(30.6888, 120.7905, 30.6968, 120.8012)
# Extended HSR railway track corridor (~1.6km WSW and ~1.5km ENE past Jiaxing South Station along real 沪昆高速线)
HSR_RAIL_RECT = rect_ll(30.6830, 120.7775, 30.7025, 120.8125)
# Airport Expressway (机场快速路) focused diagonal corridor from MAIN_W to Jiaxing Nanhu Airport Terminal
AIRPORT_CORRIDOR_PTS = [
    (-3750.0, 1266.0),
    (-5250.0, 1510.0),
    (-6870.0, 2520.0),
    (-9450.0, 4120.0),
    (-9442.0, 5316.0),
]
AIRPORT_CORRIDOR_HALF_W = 240.0
# Jiaxing Nanhu Airport precinct (terminal, ATC tower, cargo hangars, taxiways & 3400m Runway 12/30)
AIRPORT_PRECINCT = (-10250.0, 4800.0, -6800.0, 7020.0)

ACTIVE_RECTS = [MAIN_RECT, CHANGSHUI_CORRIDOR, SAMS_SHUANGXI_RECT, XIANGJIADANG_RECT, QINGFENG_CORRIDOR, SOUTH_STA_PRECINCT]
_ALL_BOUNDS_RECTS = ACTIVE_RECTS + [HSR_RAIL_RECT, AIRPORT_PRECINCT]
BOUNDS = (
    round(min(r[0] for r in _ALL_BOUNDS_RECTS) - 80.0),
    round(min(r[1] for r in _ALL_BOUNDS_RECTS) - 80.0),
    round(max(r[2] for r in _ALL_BOUNDS_RECTS) + 80.0),
    round(max(r[3] for r in _ALL_BOUNDS_RECTS) + 80.0),
)
# Core built immediately on load (centered on Nanhu Lake & Old City); outer city + HSR/Airport/Xiangjiadang stream via CityTiles
CORE_BOUNDS = [-1250.0, -1250.0, 1250.0, 1250.0]

# Key real-world landmark coordinates (projected from verified OSM & GPS elements)
NANHU_ORIGIN = proj(30.7568, 120.7557)
YANYU_POS = proj(30.75750, 120.75586)
HAOGU_PAGODA_POS = (-158.0, -162.0)       # 壕股塔 (verified dry green park land on Nanhu NW peninsula beside 伍相祠!)
HUIJINGYUAN_POS = (830.0, 56.0)           # 会景园码头 (Nanhu east shore)
NANHU_GATE_POS = (786.0, 486.0)           # 南湖景区主大门广场 (cleanly west of 海盐塘路 & Tram T1, facing east!)
NANHU_TIANDI_POS = (798.0, -347.0)        # 南湖天地 (Nanhu NE lakeside commercial heritage)
MEMORIAL_POS = proj(30.74986, 120.75693)  # 南湖革命纪念馆
GOV_POS = (-95.0, 610.0)                  # 嘉兴市人民政府
JIAXING_NO1_POS = (1756.0, 1430.0)        # 嘉兴市第一中学
YUEHE_POS = (-620.0, -1930.0)             # 月河历史街区南入口牌坊 (verified dry land!)
ZICHENG_POS = (-306.0, -816.0)            # 子城遗址公园 · 谯楼
CATHOLIC_CHURCH_POS = (-522.0, -894.0)    # 嘉兴天主教堂 (圣母显灵堂)
FIRST_HOSPITAL_POS = (-1362.0, 1765.0)    # 嘉兴市第一医院
SECOND_HOSPITAL_POS = (-198.0, -1781.0)   # 嘉兴市第二医院
TCM_HOSPITAL_POS = (-2518.0, -835.0)      # 嘉兴市中医医院
YAOHAN_POS = (-2339.0, -651.0)            # 八佰伴购物中心 (中山路店)
YAOHAN_BRIDGE_POS = (-2210.0, -758.0)     # 八佰伴标志性环形人行天桥
CENTRAL_PARK_POS = (1075.0, 3045.0)       # 嘉兴中央公园
JIAXING_STA_POS = (710.0, -1265.0)        # 嘉兴火车站 (森林中的地下火车站 & 南广场)
BOTANICAL_POS = proj(30.71740, 120.76420) # 嘉兴植物园温室
SOUTH_STA_POS = proj(30.69275, 120.79580) # 嘉兴南站 (高铁枢纽)
HILTON_POS = (3636.0, 1610.0)             # 嘉兴希尔顿酒店 (广益路)
WANDA_NANHU_POS = (4428.0, 1858.0)        # 南湖万达广场 (广益路/庆丰路)
SAMS_CLUB_POS = proj(30.709753, 120.785248)  # 嘉兴山姆会员商店 (槜李路/商务大道)
XIANGJIADANG_PARK_POS = (4770.0, -5180.0) # 湘家荡湿地公园 (dry west shore archway/birding tower + boardwalk east into lake!)
AIRPORT_TERM_POS = (-9442.0, 5316.0)      # 嘉兴南湖机场航站楼 (IATA: JNH / ICAO: ZSJX)
OLD_CITY_CENTER = proj(30.7655, 120.7460)


def in_rect(p, r, pad=0.0):
    return r[0] - pad <= p[0] <= r[2] + pad and r[1] - pad <= p[1] <= r[3] + pad


def in_airport_corridor(p, pad=0.0):
    lim = AIRPORT_CORRIDOR_HALF_W + pad
    px, py = p[0], p[1]
    for a, b in zip(AIRPORT_CORRIDOR_PTS, AIRPORT_CORRIDOR_PTS[1:]):
        if seg_dist(px, py, a[0], a[1], b[0], b[1])[0] <= lim:
            return True
    return False


def in_airport_precinct(p, pad=0.0):
    return in_rect(p, AIRPORT_PRECINCT, pad)


def in_active(p, pad=0.0):
    for r in ACTIVE_RECTS:
        if in_rect(p, r, pad):
            return True
    if in_airport_corridor(p, pad):
        return True
    if in_airport_precinct(p, pad):
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
ROAD_CLASSES = {
    "primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "trunk",
    "primary_link", "secondary_link", "tertiary_link", "service",
}
SKIP_SERVICE_SUBTYPES = {"parking_aisle", "driveway", "drive-through", "emergency_access", "alley"}


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
    if cx < -3750.0 and cy > 1100.0 and in_airport_corridor((cx, cy), 40.0):
        return "机场快速路辅道"
    return raw_name or "嘉兴支路"


def build_street_graph(nodes, ways, water_grid, park_grid=None, rail_grid=None):
    pieces = []
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in ROAD_CLASSES:
            continue
        if cls == "service" and t.get("service", "") in SKIP_SERVICE_SUBTYPES:
            continue
        if t.get("area") == "yes" or t.get("tunnel") == "building_passage":
            continue
        layer = str(t.get("layer", "0")).split(";")[0]
        is_bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        is_tunnel = bool(t.get("tunnel")) and t.get("tunnel") != "no"
        pts_ids = [r for r in refs if r in nodes]
        if len(pts_ids) < 2:
            continue
        # Keep service roads ONLY when long enough (> 38m) or in sparse eastern expansion so parking stubs don't clutter
        if cls == "service":
            p_first, p_last = nodes[pts_ids[0]], nodes[pts_ids[-1]]
            if math.hypot(p_last[0] - p_first[0], p_last[1] - p_first[1]) < 36.0:
                continue
        # Keep surface roads inside Airport Corridor (even trunk surface carriageways) while skipping high viaducts
        in_ap_corr = any(in_airport_corridor(nodes[r], 40.0) for r in pts_ids)
        # Skip elevated Inner Ring Expressway & Airport Expressway viaduct decks from the surface buildable street graph
        if cls == "trunk" and (is_bridge or layer not in ("0", "") or "快速路" in t.get("name", "")):
            continue
        # Keep real-life railway underpass tunnels (tunnel=yes / layer=-1/-2/-3) and overpass bridges (layer=1/2)
        if not is_bridge and not is_tunnel and layer not in ("0", "-1", "-2", "-3", ""):
            continue
        if is_bridge and layer not in ("0", "1", "2", ""):
            continue
        # Inside Airport Precinct, keep ONLY roads near the terminal approach (not airside perimeter service roads)
        if any(in_airport_precinct(nodes[r]) for r in pts_ids) and not in_ap_corr:
            if not any(math.hypot(nodes[r][0] - AIRPORT_TERM_POS[0], nodes[r][1] - AIRPORT_TERM_POS[1]) < 480.0 for r in pts_ids):
                continue

        # Clip polyline to ACTIVE_RECTS + Airport Corridor (with 45m margin so corridor intersections stay intact)
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
                        lay_s = str(t.get("layer", "0")).split(";")[0]
                        is_tun = (bool(t.get("tunnel")) and t.get("tunnel") != "no") or lay_s in ("-1", "-2", "-3")
                        mid_e = full[len(full) // 2]
                        # Subterranean drop-off loops / deep car tunnels (e.g. Jiaxing Station North Plaza 出租车/网约车/城东路隧道)
                        # are hidden from the surface green park and shown in B1 Underground View instead!
                        is_ug = is_tun and (
                            lay_s in ("-2", "-3")
                            or any(k in nm for k in ("出租车", "网约车", "城东路隧道"))
                            or (math.hypot(mid_e[0] - JIAXING_STA_POS[0], mid_e[1] - JIAXING_STA_POS[1]) < 340.0 and cls in ("unclassified", "service", "tertiary", "primary"))
                        )
                        raw_edges[key] = {
                            "a": key[0], "b": key[1], "name": nm, "width": w, "lf": lf, "lb": lb,
                            "length": elen, "pts": full, "cls": cls,
                            "bridge": bool(t.get("bridge")) and t.get("bridge") != "no",
                            "tunnel": is_tun,
                            "underground": is_ug,
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

    # Ensure a continuous buildable surface boulevard (机场大道 / 机场快速路辅道) connects MAIN_W -> Airport Terminal!
    ap_nodes = []
    if main_comp:
        # Find closest existing main_comp node near the Airport Expressway entrance (-3750, 1266)
        start_j = min(main_comp, key=lambda j: math.hypot(jnodes[j]["pos"][0] - (-3750.0), jnodes[j]["pos"][1] - 1266.0))
        ap_waypoints = [
            (-4550.0, 1390.0), (-5350.0, 1550.0), (-6150.0, 2060.0), (-6950.0, 2570.0),
            (-7800.0, 3100.0), (-8650.0, 3620.0), (-9450.0, 4130.0), (-9448.0, 4700.0), (-9450.0, 5205.0),
        ]
        prev_j = start_j
        for wi, wp in enumerate(ap_waypoints):
            nj = len(jnodes)
            jnodes.append({"pos": wp, "streets": {"机场快速路辅道" if wi < 7 else "嘉兴机场大道"}})
            main_comp.add(nj)
            pa, pb = jnodes[prev_j]["pos"], wp
            elen = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
            key = (min(prev_j, nj), max(prev_j, nj))
            pts_e = [pa, pb] if prev_j < nj else [pb, pa]
            raw_edges[key] = {
                "a": key[0], "b": key[1], "name": "机场快速路辅道" if wi < 7 else "嘉兴机场大道",
                "width": 16.0, "lf": 2, "lb": 2, "divided": True, "length": elen, "pts": pts_e,
                "cls": "primary", "bridge": False, "tunnel": False,
            }
            prev_j = nj
        # Stitch any nearby Airport Terminal OSM road component into the terminal node
        for comp in comps:
            if comp is main_comp:
                continue
            if any(math.hypot(jnodes[j]["pos"][0] - AIRPORT_TERM_POS[0], jnodes[j]["pos"][1] - AIRPORT_TERM_POS[1]) < 420.0 for j in comp):
                cj = min(comp, key=lambda j: math.hypot(jnodes[j]["pos"][0] - jnodes[prev_j]["pos"][0], jnodes[j]["pos"][1] - jnodes[prev_j]["pos"][1]))
                pa, pb = jnodes[prev_j]["pos"], jnodes[cj]["pos"]
                elen = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
                if elen >= 6.0:
                    key = (min(prev_j, cj), max(prev_j, cj))
                    pts_e = [pa, pb] if prev_j < cj else [pb, pa]
                    raw_edges[key] = {
                        "a": key[0], "b": key[1], "name": "嘉兴机场航站楼引道",
                        "width": 14.0, "lf": 2, "lb": 2, "divided": False, "length": elen, "pts": pts_e,
                        "cls": "secondary", "bridge": False, "tunnel": False,
                    }
                main_comp.update(comp)

    # Complete sparse Eastern & Northeastern Jiaxing urban road grid (fixes huge barren blocks with missing streets!)
    # Synthesizes realistic connected municipal branch streets (支路) strictly on dry non-park urban land,
    # snapped cleanly into existing arterial junctions!
    if main_comp:
        existing_seg_grid = Grid(80.0)
        for ed in raw_edges.values():
            if ed["a"] not in main_comp or ed["b"] not in main_comp:
                continue
            pts_e = ed["pts"]
            for pa, pb in zip(pts_e, pts_e[1:]):
                existing_seg_grid.add((pa[0], pa[1], pb[0], pb[1]),
                                      min(pa[0], pb[0]) - 10, min(pa[1], pb[1]) - 10,
                                      max(pa[0], pb[0]) + 10, max(pa[1], pb[1]) + 10)

        def pt_in_water(x, y):
            for wp in water_grid.query(x - 6, y - 6, x + 6, y + 6):
                if point_in_poly(x, y, wp):
                    return True
            return False

        def pt_in_park(x, y):
            if park_grid is None:
                return False
            for pp in park_grid.query(x - 4, y - 4, x + 4, y + 4):
                if point_in_poly(x, y, pp):
                    return True
            return False

        def seg_hits_rail(pa, pb):
            if rail_grid is None:
                return False
            for (ax, ay, bx, by, rw) in rail_grid.query(min(pa[0], pb[0]) - 20, min(pa[1], pb[1]) - 20,
                                                        max(pa[0], pb[0]) + 20, max(pa[1], pb[1]) + 20):
                if seg_intersection(pa, pb, (ax, ay), (bx, by)) is not None:
                    return True
                if seg_dist(pa[0], pa[1], ax, ay, bx, by)[0] < rw + 6.0 or seg_dist(pb[0], pb[1], ax, ay, bx, by)[0] < rw + 6.0:
                    return True
            return False

        def seg_mostly_water(pa, pb):
            hits = 0
            for k_s in range(1, 6):
                t_s = k_s / 6.0
                if pt_in_water(pa[0] + (pb[0] - pa[0]) * t_s, pa[1] + (pb[1] - pa[1]) * t_s):
                    hits += 1
            return hits >= 2

        def nearest_road_dist(x, y):
            best = 1e9
            for (ax, ay, bx, by) in existing_seg_grid.query(x - 210, y - 210, x + 210, y + 210):
                d = seg_dist(x, y, ax, ay, bx, by)[0]
                if d < best:
                    best = d
            return best

        lm_keepout = [
            (HILTON_POS, 110.0), (WANDA_NANHU_POS, 155.0), (SAMS_CLUB_POS, 130.0),
            (JIAXING_NO1_POS, 165.0), (CENTRAL_PARK_POS, 150.0), (JIAXING_STA_POS, 190.0),
        ]
        # Candidate grid across sparse eastern/NE MAIN_RECT & Sam's/Shuangxi urban blocks
        grid_step = 240.0
        new_grid_nodes = {}  # (gx, gy) -> jnode_id
        for zone in (
            (1800.0, -3720.0, MAIN_RECT[2] - 90.0, MAIN_RECT[3] - 90.0),
            (SAMS_SHUANGXI_RECT[0] + 90.0, SAMS_SHUANGXI_RECT[1] + 90.0, SAMS_SHUANGXI_RECT[2] - 90.0, SAMS_SHUANGXI_RECT[3] - 90.0),
        ):
            gx_i = 0
            x = zone[0]
            while x <= zone[2]:
                gy_i = 0
                y = zone[1]
                while y <= zone[3]:
                    if (not pt_in_water(x, y) and not pt_in_park(x, y)
                            and all(math.hypot(x - lp[0], y - lp[1]) > lr for lp, lr in lm_keepout)
                            and nearest_road_dist(x, y) > 135.0):
                        # Only spawn if within 620m of existing main road network so it stays urban & connected
                        nj = len(jnodes)
                        jnodes.append({"pos": (round(x, 1), round(y, 1)), "streets": {"东区支路"}})
                        new_grid_nodes[(gx_i, gy_i, zone[0])] = nj
                    y += grid_step
                    gy_i += 1
                x += grid_step
                gx_i += 1

        # Build spatial index of existing main_comp surface nodes for fast snapping
        surf_nodes = Grid(160.0)
        for j in main_comp:
            p = jnodes[j]["pos"]
            surf_nodes.add(j, p[0], p[1], p[0], p[1])

        syn_edges = 0
        syn_adj = defaultdict(set)
        # 1) Connect adjacent new grid nodes (orthogonal E-W / N-S neighborhood streets)
        for (gx_i, gy_i, z0), ja in list(new_grid_nodes.items()):
            pa = jnodes[ja]["pos"]
            for dgx, dgy, st_nm in ((1, 0, "东城横街"), (0, 1, "东城纵街")):
                jb = new_grid_nodes.get((gx_i + dgx, gy_i + dgy, z0))
                if jb is None:
                    continue
                pb = jnodes[jb]["pos"]
                if seg_hits_rail(pa, pb) or seg_mostly_water(pa, pb):
                    continue
                key = (min(ja, jb), max(ja, jb))
                if key not in raw_edges:
                    elen = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
                    pts_e = [pa, pb] if ja < jb else [pb, pa]
                    raw_edges[key] = {
                        "a": key[0], "b": key[1], "name": st_nm,
                        "width": 10.5, "lf": 1, "lb": 1, "divided": False,
                        "length": elen, "pts": pts_e, "cls": "residential",
                        "bridge": pt_in_water((pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5),
                        "tunnel": False, "underground": False,
                    }
                    syn_adj[ja].add(jb)
                    syn_adj[jb].add(ja)
                    syn_edges += 1

        # 2) Snap boundary grid nodes into nearest existing arterial/branch junctions within 330m
        for key_g, ja in list(new_grid_nodes.items()):
            pa = jnodes[ja]["pos"]
            cands = []
            for jb in surf_nodes.query(pa[0] - 330, pa[1] - 330, pa[0] + 330, pa[1] + 330):
                pb = jnodes[jb]["pos"]
                d = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
                if 28.0 <= d <= 330.0:
                    cands.append((d, jb))
            cands.sort()
            linked = 0
            for d, jb in cands:
                if linked >= 2:
                    break
                pb = jnodes[jb]["pos"]
                if seg_hits_rail(pa, pb) or seg_mostly_water(pa, pb):
                    continue
                key = (min(ja, jb), max(ja, jb))
                if key not in raw_edges:
                    pts_e = [pa, pb] if ja < jb else [pb, pa]
                    raw_edges[key] = {
                        "a": key[0], "b": key[1], "name": "东区联络路",
                        "width": 10.5, "lf": 1, "lb": 1, "divided": False,
                        "length": d, "pts": pts_e, "cls": "residential",
                        "bridge": pt_in_water((pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5),
                        "tunnel": False, "underground": False,
                    }
                    syn_adj[ja].add(jb)
                    syn_adj[jb].add(ja)
                    syn_edges += 1
                    linked += 1

        # Add ONLY new grid nodes that reached main_comp via BFS!
        q_bfs = [j for j in main_comp if j in syn_adj]
        seen_syn = set(main_comp)
        while q_bfs:
            u = q_bfs.pop()
            for v in syn_adj[u]:
                if v not in seen_syn:
                    seen_syn.add(v)
                    main_comp.add(v)
                    q_bfs.append(v)
        print(f"Eastern sparse-grid completion: +{syn_edges} connected branch streets ({len(main_comp)} total junctions)")

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
        if not is_br and not ed.get("underground"):
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
        if ed.get("underground"):
            rec["underground"] = True
        out_edges.append(rec)

    print(f"Street graph: {len(out_nodes)} junctions, {len(out_edges)} edges "
          f"({sum(1 for e in out_edges if e.get('bridge'))} bridges, {sum(1 for e in out_edges if e.get('tunnel'))} tunnels, "
          f"{sum(1 for e in out_edges if e.get('underground'))} underground-only B1 tunnels)")
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

    # Ensure Jiaxing South Station plaza area is nicely paved, Xiangjiadang Wetland Park surrounding land is
    # lush green wetland lawn (water renders cleanly on top via shader depth-push!), and Jiaxing Airport infield is grass.
    sx, sy = SOUTH_STA_POS
    sta_plaza = [(sx - 130, sy - 115), (sx + 130, sy - 115), (sx + 130, sy + 70), (sx - 130, sy + 70)]
    areas.append({"kind": "plaza", "pts": [rnd(p) for p in sta_plaza]})
    park_polys.append(sta_plaza)
    # Full lush wetland meadow lawn covering Xiangjiadang Wetland Park (ZERO bare grey concrete around Xiangjiadang Lake!)
    xr = XIANGJIADANG_RECT
    xj_meadow = [(xr[0] + 10, xr[1] + 10), (xr[2] - 10, xr[1] + 10), (xr[2] - 10, xr[3] - 10), (xr[0] + 10, xr[3] - 10)]
    areas.append({"kind": "park", "pts": [rnd(p) for p in xj_meadow]})
    park_polys.append(xj_meadow)
    named_plazas.append({"name": "湘家荡湿地公园", "kind": "park", "pts": [rnd(p) for p in xj_meadow]})
    # Yuehe historic lotus-pond garden pocket lawn (荷花池公园) & Nanhu Scenic lakeside lawn aprons
    yuehe_garden = [(-865, -2250), (-755, -2250), (-755, -2140), (-865, -2140)]
    areas.append({"kind": "park", "pts": [rnd(p) for p in yuehe_garden]})
    park_polys.append(yuehe_garden)
    nanhu_se_park = [(520, 260), (880, 260), (880, 560), (520, 560)]
    areas.append({"kind": "park", "pts": [rnd(p) for p in nanhu_se_park]})
    park_polys.append(nanhu_se_park)
    ap_grass = [
        (AIRPORT_PRECINCT[0], AIRPORT_PRECINCT[1]),
        (AIRPORT_PRECINCT[2], AIRPORT_PRECINCT[1]),
        (AIRPORT_PRECINCT[2], AIRPORT_PRECINCT[3]),
        (AIRPORT_PRECINCT[0], AIRPORT_PRECINCT[3]),
    ]
    areas.append({"kind": "grass", "pts": [rnd(p) for p in ap_grass]})

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
# 3. Elevated Inner Ring Expressway Viaducts (嘉兴内环快速路全环闭合: 中环北/三环东/三环南/中环西) + Airport Expressway
# ---------------------------------------------------------------------------------------------
INNER_RING_NAMES = ("中环北路", "中环西路", "三环东路", "三环南路", "内环快速路", "长水路")
INNER_RING_BOX = (-3250.0, -4020.0, 5600.0, 3680.0)


def build_freeways(nodes, ways, road_grid=None):
    out = []
    existing_viaduct_grid = Grid(60.0)
    elev_nodes = {}  # osm_node_id -> deck elevation y

    def emit_viaduct(pts, lanes, oneway, y_start, y_end, cls, nm):
        if len(pts) < 2:
            return
        dense = [pts[0]]
        cum = [0.0]
        for a, b in zip(pts, pts[1:]):
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, int(math.ceil(L / 12.0)))
            for k in range(1, n + 1):
                np = (a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n)
                cum.append(cum[-1] + math.hypot(np[0] - dense[-1][0], np[1] - dense[-1][1]))
                dense.append(np)
        total_l = max(cum[-1], 1.0)
        w = lanes * 3.5 + (2.2 if oneway else 3.2)
        ys = []
        for s_cur in cum:
            u = max(0.0, min(1.0, s_cur / total_l))
            su = u * u * (3.0 - 2.0 * u)
            ys.append(y_start + (y_end - y_start) * su)
        P = [[round(p[0], 2), round(p[1], 2), round(y, 2)] for p, y in zip(dense, ys)]
        start = 0
        while start < len(P) - 1:
            end = min(len(P) - 1, start + 26)
            out.append({
                "pts": P[start:end + 1],
                "lanes": lanes,
                "w": round(w, 1),
                "oneway": oneway,
                "bridge": True,
                "kind": cls,
                "name": nm,
            })
            start = end

    # Collect surface street OSM nodes so ramp touchdown ends snap cleanly to ground level (y = 0.05m)!
    surface_nodes = set()
    for wid, (refs, t) in ways.items():
        h_s = t.get("highway", "")
        if h_s in ("primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "service"):
            lay_s = str(t.get("layer", "0")).split(";")[0]
            if lay_s in ("0", "") and not (bool(t.get("bridge")) and t.get("bridge") != "no"):
                surface_nodes.update(refs)

    # Pass A1: Real OSM elevated MAINLINE expressways (内环快速路, 机场快速路 — motorway / trunk)
    raw_links = []
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in ("motorway", "motorway_link", "trunk", "trunk_link"):
            continue
        nm = t.get("name") or t.get("ref") or ""
        if t.get("area") == "yes":
            continue
        if t.get("tunnel") in ("yes", "building_passage") and "内环快速路" not in nm:
            continue
        is_bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        try:
            layer = int(str(t.get("layer", "0")).split(";")[0])
        except ValueError:
            layer = 0
        if cls == "trunk" and not is_bridge and layer <= 0 and "快速路" not in nm:
            continue
        ids = [r for r in refs if r in nodes]
        if len(ids) < 2:
            continue
        pts = [nodes[i] for i in ids]
        if not any(in_active(p, 25.0) for p in pts):
            continue
        is_link = cls.endswith("_link")
        try:
            lanes = int(str(t.get("lanes", "")).split(";")[0])
        except ValueError:
            lanes = 1 if is_link else 3
        lanes = max(1, min(4, lanes))
        oneway = t.get("oneway", "yes") in ("yes", "1", "-1")
        y_deck = 7.4 + 2.4 * max(0, min(2, layer - 1))
        if is_link:
            raw_links.append((ids, lanes, oneway, y_deck, cls, nm or "嘉兴内环快速路匝道"))
            continue
        # Mainline elevated deck: keep active runs & record elevated node heights
        runs = []
        cur = []
        cur_ids = []
        for nid_r, p in zip(ids, pts):
            if in_active(p, 60.0):
                cur.append(p)
                cur_ids.append(nid_r)
            else:
                if len(cur) >= 2:
                    runs.append((cur_ids, cur))
                cur = []
                cur_ids = []
        if len(cur) >= 2:
            runs.append((cur_ids, cur))
        for r_ids, run in runs:
            emit_viaduct(run, lanes, oneway, y_deck, y_deck, cls, nm or "嘉兴内环快速路")
            for nid_r in r_ids:
                elev_nodes[nid_r] = max(elev_nodes.get(nid_r, 0.0), y_deck)
            for a, b in zip(run, run[1:]):
                existing_viaduct_grid.add((a[0], a[1], b[0], b[1], y_deck),
                                          min(a[0], b[0]) - 28, min(a[1], b[1]) - 28,
                                          max(a[0], b[0]) + 28, max(a[1], b[1]) + 28)

    # Pass B: Complete all 4 sides of 嘉兴内环快速路 elevated viaduct cleanly forming a 360-deg closed loop!
    # Real Jiaxing Inner Ring Expressway runs along: 中环北路 (N) -> 三环东路 (E) -> 三环南路 (S) -> 中环西路 (W)
    ring_added = 0
    for wid, (refs, t) in ways.items():
        if t.get("highway") not in ("primary", "trunk"):
            continue
        nm = t.get("name", "")
        if not any(rn in nm for rn in INNER_RING_NAMES):
            continue
        if t.get("tunnel") in ("yes", "building_passage"):
            continue
        ids = [r for r in refs if r in nodes]
        if len(ids) < 2:
            continue
        pts = [nodes[i] for i in ids if in_rect(nodes[i], INNER_RING_BOX, 40.0)]
        r_ids = [i for i in ids if in_rect(nodes[i], INNER_RING_BOX, 40.0)]
        if len(pts) < 2:
            continue
        mid = pts[len(pts) // 2]
        if "三环南路" in nm and (mid[1] > 3620.0 or mid[0] < -2900.0 or mid[0] > 5480.0):
            continue
        if "长水路" in nm and (mid[1] < 3360.0 or mid[1] > 3560.0 or mid[0] < -2800.0 or mid[0] > 5400.0):
            continue
        if "三环东路" in nm and (mid[1] > 3580.0 or mid[1] < -3750.0 or mid[0] < 2400.0):
            continue
        if "中环西路" in nm and (mid[1] > 3560.0 or mid[1] < -3750.0):
            continue
        already = False
        for (ax, ay, bx, by, _yd) in existing_viaduct_grid.query(mid[0] - 26, mid[1] - 26, mid[0] + 26, mid[1] + 26):
            if seg_dist(mid[0], mid[1], ax, ay, bx, by)[0] < 24.0:
                already = True
                break
        if already:
            continue
        oneway = t.get("oneway", "no") in ("yes", "1", "-1")
        emit_viaduct(pts, 3 if oneway else 4, oneway, 7.4, 7.4, "trunk", f"嘉兴内环快速路（{nm}）")
        for nid_r in r_ids:
            elev_nodes[nid_r] = max(elev_nodes.get(nid_r, 0.0), 7.4)
        for a, b in zip(pts, pts[1:]):
            existing_viaduct_grid.add((a[0], a[1], b[0], b[1], 7.4),
                                      min(a[0], b[0]) - 28, min(a[1], b[1]) - 28,
                                      max(a[0], b[0]) + 28, max(a[1], b[1]) + 28)
        ring_added += 1

    # Pass A2: Stitch connected *_link ramp chains & solve exact ground (0.06m) <-> elevated (7.4m+) elevations!
    # Guarantees EVERY on/off ramp seamlessly touches the ground road at y=0.06m AND joins the elevated deck at y=7.4m!
    def endpoint_elev(nid, pt, default_deck):
        if nid in elev_nodes:
            return elev_nodes[nid], True
        if nid in surface_nodes:
            return 0.06, False
        best_d = 1e9
        best_y = default_deck
        for (ax, ay, bx, by, yd) in existing_viaduct_grid.query(pt[0] - 18, pt[1] - 18, pt[0] + 18, pt[1] + 18):
            dd = seg_dist(pt[0], pt[1], ax, ay, bx, by)[0]
            if dd < best_d:
                best_d = dd
                best_y = yd
        if best_d < 13.5:
            return best_y, True
        return 0.06, False

    def snap_ground_to_road(pts_list, at_end):
        """Extend a ramp's ground touchdown smoothly flush onto the adjacent surface road carriageway edge."""
        if road_grid is None or len(pts_list) < 2:
            return pts_list
        p_end = pts_list[-1] if at_end else pts_list[0]
        p_prev = pts_list[-2] if at_end else pts_list[1]
        best_d = 1e9
        best_proj = None
        best_hw = 6.0
        best_nrm = (0.0, 1.0)
        for (ax, ay, bx, by, hw) in road_grid.query(p_end[0] - 32, p_end[1] - 32, p_end[0] + 32, p_end[1] + 32):
            dx, dy = bx - ax, by - ay
            l2 = dx * dx + dy * dy
            if l2 < 1e-6:
                continue
            t_p = max(0.0, min(1.0, ((p_end[0] - ax) * dx + (p_end[1] - ay) * dy) / l2))
            proj_p = (ax + dx * t_p, ay + dy * t_p)
            dd = math.hypot(p_end[0] - proj_p[0], p_end[1] - proj_p[1])
            if dd < best_d:
                best_d = dd
                best_proj = proj_p
                best_hw = hw
                sl = math.sqrt(l2)
                best_nrm = (-dy / sl, dx / sl)
        if best_proj is None or best_d > 30.0:
            return pts_list
        # If the ramp touchdown sits right on the center of a surface road (where a center tramway runs!),
        # shift the ground touchdown cleanly PERPENDICULAR onto the outer motor lane (~7.0m from centerline)!
        if best_d < 6.4:
            # Find which side of the surface road the ramp body lies on
            ref_idx = min(len(pts_list) - 1, max(1, len(pts_list) // 3)) if not at_end else max(0, len(pts_list) - 1 - max(1, len(pts_list) // 3))
            p_ref = pts_list[ref_idx]
            nx, ny = best_nrm
            if (p_ref[0] - best_proj[0]) * nx + (p_ref[1] - best_proj[1]) * ny < 0.0:
                nx, ny = -nx, -ny
            lat_off = max(best_hw - 0.5, 7.2)
            new_pts = list(pts_list)
            # Shift any vertices near the touchdown that sit within lat_off of the road centerline onto the outer lane!
            idxs = range(min(4, len(new_pts))) if not at_end else range(len(new_pts) - 1, max(-1, len(new_pts) - 5), -1)
            for k_i in idxs:
                pk = new_pts[k_i]
                # Lateral signed distance from road line through best_proj
                s_lat = (pk[0] - best_proj[0]) * nx + (pk[1] - best_proj[1]) * ny
                if s_lat < lat_off:
                    delta = lat_off - s_lat
                    new_pts[k_i] = (pk[0] + nx * delta, pk[1] + ny * delta)
            return new_pts
        # Touch down cleanly on the outer lane edge of the surface road (staying clear of center tramway!)
        if best_d > best_hw + 0.5:
            vx, vy = p_end[0] - best_proj[0], p_end[1] - best_proj[1]
            vl = max(math.hypot(vx, vy), 1e-6)
            target = (best_proj[0] + vx / vl * max(best_hw - 1.4, 5.8), best_proj[1] + vy / vl * max(best_hw - 1.4, 5.8))
            if math.hypot(target[0] - p_end[0], target[1] - p_end[1]) >= 2.0:
                tdx, tdy = p_end[0] - p_prev[0], p_end[1] - p_prev[1]
                tl = max(math.hypot(tdx, tdy), 1e-6)
                target = (target[0] + tdx / tl * 6.0, target[1] + tdy / tl * 6.0)
                return (pts_list + [target]) if at_end else ([target] + pts_list)
        return pts_list

    # Stitch simple degree-2 intermediate link nodes (e.g. bridge=yes ramp + ground approach ramp) into full chains!
    link_end_map = defaultdict(list)
    for li, item in enumerate(raw_links):
        ids_l = item[0]
        link_end_map[ids_l[0]].append((li, 0))
        link_end_map[ids_l[-1]].append((li, 1))
    used_link = [False] * len(raw_links)
    stitched_links = []
    for li in range(len(raw_links)):
        if used_link[li]:
            continue
        used_link[li] = True
        ids_c, lanes_c, ow_c, yd_c, cls_c, nm_c = raw_links[li]
        chain = list(ids_c)
        # Extend forward and backward through purely intermediate link nodes (not elev_nodes and not surface_nodes)
        for extend_end in (True, False):
            while True:
                cur_n = chain[-1] if extend_end else chain[0]
                if cur_n in elev_nodes or cur_n in surface_nodes:
                    break
                cands = [(oi, side_o) for (oi, side_o) in link_end_map[cur_n] if not used_link[oi]]
                if len(cands) != 1:
                    break
                oi, side_o = cands[0]
                used_link[oi] = True
                oids = list(raw_links[oi][0])
                yd_c = max(yd_c, raw_links[oi][3])
                if extend_end:
                    if side_o == 1:
                        oids.reverse()
                    chain.extend(oids[1:])
                else:
                    if side_o == 0:
                        oids.reverse()
                    chain = oids[:-1] + chain
        stitched_links.append((chain, lanes_c, ow_c, yd_c, cls_c, nm_c))

    ramp_cnt = 0
    for chain, lanes_c, ow_c, yd_c, cls_c, nm_c in stitched_links:
        pts_c = [nodes[nid] for nid in chain if nid in nodes]
        ids_c = [nid for nid in chain if nid in nodes]
        if len(pts_c) < 2 or not any(in_active(p, 40.0) for p in pts_c):
            continue
        # Keep active span
        if not all(in_active(p, 80.0) for p in pts_c):
            pts_c = [p for p in pts_c if in_active(p, 80.0)]
            ids_c = [nid for nid in ids_c if in_active(nodes[nid], 80.0)]
            if len(pts_c) < 2:
                continue
        y0, e0 = endpoint_elev(ids_c[0], pts_c[0], yd_c)
        y1, e1 = endpoint_elev(ids_c[-1], pts_c[-1], yd_c)
        if not e0 and e1:
            pts_c = snap_ground_to_road(pts_c, at_end=False)
        elif e0 and not e1:
            pts_c = snap_ground_to_road(pts_c, at_end=True)
        elif not e0 and not e1:
            # Ground-level surface slip road (both ends on ground) — keep low flush with road or skip if tiny
            y0, y1 = 0.06, 0.06
        emit_viaduct(pts_c, lanes_c, ow_c, y0, y1, cls_c, nm_c)
        ramp_cnt += 1

    # Verify 360-degree ring continuity around ring center (1100, -100) across 36 angular sectors
    ring_sectors = [0] * 36
    for fw in out:
        for pt in fw["pts"]:
            if in_rect((pt[0], pt[1]), INNER_RING_BOX, 80.0):
                if math.hypot(pt[0] - 1100.0, pt[1] + 100.0) > 2800.0:
                    ang = math.degrees(math.atan2(pt[1] + 100.0, pt[0] - 1100.0)) % 360.0
                    ring_sectors[int(ang // 10)] += 1
    covered = sum(1 for c in ring_sectors if c > 0)
    print(f"Freeways (Closed Inner Ring + Airport Expressway): {len(out)} pieces (+{ring_added} Inner Ring completions, {ramp_cnt} stitched ramps, {covered}/36 ring sectors covered)")
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

    # Landmark exclusion zones (bespoke 3D models built by JiaxingLandmarks & JiaxingCivicLandmarks)
    lm_zones = [
        (SOUTH_STA_POS, 195.0, "jiaxing_south_station"),
        (YANYU_POS, 52.0, "yanyu_tower"),
        (HAOGU_PAGODA_POS, 42.0, "haogu_pagoda"),
        (HUIJINGYUAN_POS, 64.0, "huijingyuan"),
        (NANHU_GATE_POS, 58.0, "nanhu_gate"),
        (NANHU_TIANDI_POS, 115.0, "nanhu_tiandi"),
        (MEMORIAL_POS, 105.0, "nanhu_memorial"),
        (GOV_POS, 125.0, "jiaxing_gov"),
        (JIAXING_NO1_POS, 155.0, "jiaxing_no1_school"),
        (YUEHE_POS, 18.0, "yuehe_quarter"),
        (ZICHENG_POS, 92.0, "zicheng_park"),
        (CATHOLIC_CHURCH_POS, 58.0, "catholic_church"),
        (FIRST_HOSPITAL_POS, 128.0, "first_hospital"),
        (SECOND_HOSPITAL_POS, 95.0, "second_hospital"),
        (TCM_HOSPITAL_POS, 102.0, "tcm_hospital"),
        (YAOHAN_POS, 88.0, "yaohan_mall"),
        (CENTRAL_PARK_POS, 92.0, "central_park"),
        (JIAXING_STA_POS, 130.0, "jiaxing_station"),
        (BOTANICAL_POS, 36.0, "botanical_conservatory"),
        (HILTON_POS, 96.0, "hilton_hotel"),
        (WANDA_NANHU_POS, 138.0, "wanda_nanhu"),
        (SAMS_CLUB_POS, 115.0, "sams_club"),
        (XIANGJIADANG_PARK_POS, 95.0, "xiangjiadang_park"),
        (AIRPORT_TERM_POS, 260.0, "jiaxing_airport"),
    ]

    def can_place(pts, bb, allow_in_park=False, water_margin=0.0):
        cen = centroid(pts)
        if not in_active(cen):
            return False
        # Never place synthetic residential/commercial blocks inside the Airport airside precinct
        if not allow_in_park and in_airport_precinct(cen):
            return False
        for lpos, lrad, _ in lm_zones:
            if math.hypot(cen[0] - lpos[0], cen[1] - lpos[1]) < lrad:
                return False
        # Keep the full Jiaxing South HSR Station + North Forecourt Plaza + Bus Transit Hub precinct clear of random blocks!
        dx_s = cen[0] - SOUTH_STA_POS[0]
        dy_s = cen[1] - SOUTH_STA_POS[1]
        ca_s, sa_s = math.cos(0.4925), math.sin(0.4925)
        lx_s = dx_s * ca_s - dy_s * sa_s
        lz_s = dx_s * sa_s + dy_s * ca_s
        if -160.0 <= lx_s <= 260.0 and -265.0 <= lz_s <= 80.0:
            return False
        # Keep Jiaxing T1 open-cut U-trough tunnel ramps 100% free of surface buildings!
        for (rax, ray, rbx, rby) in (
            (997.81, -1170.11, 885.0, -1178.5),
            (618.0, -1425.0, 596.91, -1523.54),
        ):
            if seg_dist(cen[0], cen[1], rax, ray, rbx, rby)[0] < 24.0:
                return False
            for p in pts:
                if seg_dist(p[0], p[1], rax, ray, rbx, rby)[0] < 16.0:
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
        # Check water clearance (including corners, edge midpoints & optional shoreline buffer margin!)
        w_pad = 4.0 + water_margin
        check_w_pts = [cen] + list(pts)
        for pi in range(len(pts)):
            pa, pb = pts[pi], pts[(pi + 1) % len(pts)]
            check_w_pts.append(((pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5))
        if water_margin > 0.1:
            for p in pts:
                dxw, dyw = p[0] - cen[0], p[1] - cen[1]
                lw = math.hypot(dxw, dyw)
                if lw > 0.1:
                    check_w_pts.append((p[0] + dxw / lw * water_margin, p[1] + dyw / lw * water_margin))
        for wp in water_grid.query(bb[0] - w_pad, bb[1] - w_pad, bb[2] + w_pad, bb[3] + w_pad):
            for cp in check_w_pts:
                if point_in_poly(cp[0], cp[1], wp):
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

    # --- B2. Authentic Dry-Land-Conforming Yuehe Historic Quarter (月河历史街区 粉墙黛瓦水乡民居) ---
    # Places dense Jiangnan 2-story white-wall/dark-gable courtyard townhouses strictly on DRY land
    # (>= 3.5m clear of ALL real OSM canals!) framing the 14 real OSM stone bridges & pedestrian alleys!
    yuehe_cnt = 0
    yh_foot_segs = []
    for wid, (refs, t) in ways.items():
        if t.get("highway") in ("footway", "pedestrian", "path") and not t.get("bridge"):
            fpts = [nodes[r] for r in refs if r in nodes]
            for fa, fb in zip(fpts, fpts[1:]):
                mcx, mcy = (fa[0] + fb[0]) * 0.5, (fa[1] + fb[1]) * 0.5
                if -890.0 <= mcx <= -390.0 and -2260.0 <= mcy <= -1860.0:
                    yh_foot_segs.append((fa[0], fa[1], fb[0], fb[1]))
    # First align traditional shop-houses directly along real Yuehe pedestrian alleys (中基路/小猪廊下/花鸟街)
    for (ax, ay, bx, by) in yh_foot_segs:
        sl = math.hypot(bx - ax, by - ay)
        if sl < 8.0:
            continue
        ang = math.atan2(by - ay, bx - ax)
        ux, uy = (bx - ax) / sl, (by - ay) / sl
        nx, ny = -uy, ux
        s = 5.0
        while s < sl - 4.0:
            for side in (-1.0, 1.0):
                hl = rng.uniform(5.2, 8.2)
                hw = rng.uniform(3.6, 5.2)
                setb = 3.2 + hw
                cx = ax + ux * s + nx * side * setb
                cy = ay + uy * s + ny * side * setb
                poly = make_rect_poly(cx, cy, ang, hl, hw)
                pxs = [p[0] for p in poly]
                pys = [p[1] for p in poly]
                bb = (min(pxs), min(pys), max(pxs), max(pys))
                if can_place(poly, bb, allow_in_park=False, water_margin=3.5):
                    h = rng.choice([6.2, 7.2, 8.0, 8.8])
                    out.append({
                        "pts": [rnd(p) for p in poly], "h": h, "kind": "house", "style": 3,
                        "colour": rng.choice(PALETTE_JIANGNAN),
                        "roof": pitched_roof_dict(cx, cy, ang, hl, hw, "gabled"),
                        "roof_colour": "#242830",
                    })
                    taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                    yuehe_cnt += 1
            s += rng.uniform(13.0, 17.5)
    # Second, fill remaining dry Yuehe peninsulas & canal banks with tight Jiangnan courtyard rows (strictly off water!)
    yh_y = -2238.0
    while yh_y <= -1874.0:
        yh_x = -868.0
        while yh_x <= -412.0:
            # Leave clean stone pedestrian alleys clear
            near_alley = any(seg_dist(yh_x, yh_y, fa, fb, fc, fd)[0] < 6.5 for (fa, fb, fc, fd) in yh_foot_segs)
            if not near_alley:
                hl = rng.uniform(5.6, 8.6)
                hw = rng.uniform(3.8, 5.2)
                ang = rng.choice([0.10, 0.14, 0.18, math.pi * 0.5 + 0.14])
                poly = make_rect_poly(yh_x, yh_y, ang, hl, hw)
                pxs = [p[0] for p in poly]
                pys = [p[1] for p in poly]
                bb = (min(pxs), min(pys), max(pxs), max(pys))
                if can_place(poly, bb, allow_in_park=False, water_margin=3.6):
                    h = rng.choice([6.0, 7.0, 7.8, 8.6])
                    out.append({
                        "pts": [rnd(p) for p in poly], "h": h, "kind": "house", "style": 3,
                        "colour": rng.choice(PALETTE_JIANGNAN),
                        "roof": pitched_roof_dict(yh_x, yh_y, ang, hl, hw, "gabled"),
                        "roof_colour": "#252932",
                    })
                    taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                    yuehe_cnt += 1
            yh_x += 17.5
        yh_y += 15.5

    # --- C. Street-Front Urban Fabric Infill along ALL roads (Old Town Jiangnan + Modern Avenues + HSR Corridor) ---
    street_cnt = 0
    for ed in edges:
        if ed.get("bridge") or ed.get("underground"):
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

    # --- D. Sparse Eastern & Northeastern Urban Block Compound Infill (fills interior blocks like SW Jiaxing!) ---
    east_cnt = 0
    for ezone in (
        (1650.0, -3720.0, MAIN_RECT[2] - 70.0, MAIN_RECT[3] - 70.0),
        (SAMS_SHUANGXI_RECT[0] + 70.0, SAMS_SHUANGXI_RECT[1] + 70.0, SAMS_SHUANGXI_RECT[2] - 70.0, SAMS_SHUANGXI_RECT[3] - 70.0),
    ):
        ey = ezone[1] + 24.0
        while ey < ezone[3] - 24.0:
            ex = ezone[0] + 24.0
            while ex < ezone[2] - 24.0:
                # Only fill blocks that sit within 210m of a real/completed street (keeps urban fabric grounded)
                near_rd = False
                for (rax, ray, rbx, rby, rhw) in road_grid.query(ex - 210, ey - 210, ex + 210, ey + 210):
                    if seg_dist(ex, ey, rax, ray, rbx, rby)[0] < 210.0:
                        near_rd = True
                        break
                if near_rd:
                    # Leave realistic landscaped compound courtyards (~16% open space)
                    if rng.random() > 0.16:
                        hl = rng.uniform(14.5, 20.5)
                        hw = rng.uniform(6.6, 8.8)
                        ang = rng.uniform(-0.03, 0.03)  # Authentic south-facing Chinese 小区板楼
                        poly = make_rect_poly(ex, ey, ang, hl, hw)
                        pxs = [p[0] for p in poly]
                        pys = [p[1] for p in poly]
                        bb = (min(pxs), min(pys), max(pxs), max(pys))
                        if can_place(poly, bb, allow_in_park=False, water_margin=3.0):
                            h = rng.choice([24.0, 30.0, 38.0, 46.0, 54.0])
                            out.append({
                                "pts": [rnd(p) for p in poly], "h": h, "kind": "apartments",
                                "style": 0 if h >= 48.0 else 2,
                                "colour": rng.choice(PALETTE_MODERN if h >= 36.0 else PALETTE_RES),
                            })
                            taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                            east_cnt += 1
                ex += 48.0
            ey += 40.0

    print(f"Buildings: {len(out)} total ({osm_cnt} real OSM + {lu_cnt} landuse compounds + {yuehe_cnt} Yuehe dry-land houses + {street_cnt} street-front + {east_cnt} eastern block compounds)")
    return out


# ---------------------------------------------------------------------------------------------
# 5. Roads, Crosswalks, Streetlamps, Avenue Trees, Storefronts
# ---------------------------------------------------------------------------------------------
def build_street_furniture(edges, nodes_list, blds, poi_nodes, osm_nodes, road_grid, water_grid, rail_grid, bld_grid, freeway_grid=None):
    deg = defaultdict(int)
    for e in edges:
        deg[e["a"]] += 1
        deg[e["b"]] += 1

    roads, cws, lamps, trees = [], [], [], []
    for ed in edges:
        if ed.get("hide_road"):
            continue
        pts = ed["pts"]
        w = ed["width"]
        r = {"name": ed["name"], "width": w, "lanes_f": ed["lanes_f"], "lanes_b": ed["lanes_b"], "layer": 0, "pts": pts}
        if ed.get("bridge"):
            r["bridge"] = True
        if ed.get("tram_median"):
            r["tram_median"] = True
        if ed.get("underground"):
            r["underground"] = True
            roads.append(r)
            continue
        # Mark almost ALL Jiaxing urban streets (width >= 8.0m, ~86% of roads!) with Chinese Non-Motorized Bike Lanes (非机动车道)
        if w >= 8.0:
            r["bike_lane"] = True
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

    # Add real OSM trees + lush scenic groves in Nanhu Scenic Area & Xiangjiadang Wetland Park!
    for nid, t in poi_nodes.items():
        if t.get("natural") == "tree" and nid in osm_nodes:
            p = osm_nodes[nid]
            if in_active(p):
                trees.append(p)
    rng_tr = random.Random(20260529)
    # Nanhu Scenic Area (Lanxiu Garden, Haogu Peninsula, South/East lakeside groves)
    for gx in range(-440, 920, 28):
        for gy in range(-480, 620, 28):
            tx = gx + rng_tr.uniform(-8.0, 8.0)
            ty = gy + rng_tr.uniform(-8.0, 8.0)
            if math.hypot(tx - HAOGU_PAGODA_POS[0], ty - HAOGU_PAGODA_POS[1]) < 36.0:
                continue
            if math.hypot(tx - NANHU_GATE_POS[0], ty - NANHU_GATE_POS[1]) < 44.0:
                continue
            if math.hypot(tx - HUIJINGYUAN_POS[0], ty - HUIJINGYUAN_POS[1]) < 48.0:
                continue
            if rng_tr.random() < 0.62:
                trees.append((tx, ty))
    # Xiangjiadang Wetland Park lush dry-shore woodland & lakeside willow groves
    xr = XIANGJIADANG_RECT
    for gx in range(int(xr[0]) + 40, int(xr[2]) - 40, 42):
        for gy in range(int(xr[1]) + 40, int(xr[3]) - 40, 42):
            tx = gx + rng_tr.uniform(-14.0, 14.0)
            ty = gy + rng_tr.uniform(-14.0, 14.0)
            if math.hypot(tx - XIANGJIADANG_PARK_POS[0], ty - XIANGJIADANG_PARK_POS[1]) < 85.0:
                continue
            if rng_tr.random() < 0.68:
                trees.append((tx, ty))

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
        if ok and freeway_grid is not None:
            for (ax, ay, bx, by, fhw) in freeway_grid.query(tx - 16, ty - 16, tx + 16, ty + 16):
                if seg_dist(tx, ty, ax, ay, bx, by)[0] < fhw + 4.4:
                    ok = False
                    break
        if ok:
            if in_airport_precinct((tx, ty)) and math.hypot(tx - AIRPORT_TERM_POS[0], ty - AIRPORT_TERM_POS[1]) > 240.0:
                ok = False
        if ok:
            for ob in bld_grid.query(tx, ty, tx, ty):
                if point_in_poly(tx, ty, ob[4]):
                    ok = False
                    break
        if ok:
            seen_t.add(c)
            d_trees.append(rnd((tx, ty)))

    # Storefronts: real OSM POIs first + dense authentic Chinese street-front retail!
    # Realistic two-tier mix:
    #   1) National / Regional Chain Brands (standardized sleek corporate fascia signboards)
    #   2) Everyday Local Chinese Street Shops (earthy vibrant red/blue/green/yellow PVC lightboxes, awnings & blade signs!)
    CHAIN_SHOPS = [
        ("五芳斋粽子", "restaurant"), ("文虎酱鸭", "restaurant"), ("真真老老", "restaurant"),
        ("瑞幸咖啡", "cafe"), ("星巴克咖啡", "cafe"), ("霸王茶姬", "cafe"), ("喜茶", "cafe"),
        ("奈雪的茶", "cafe"), ("古茗奶茶", "cafe"), ("沪上阿姨", "cafe"), ("蜜雪冰城", "cafe"),
        ("CoCo都可", "cafe"), ("一点点", "cafe"), ("肯德基", "fast_food"), ("麦当劳", "fast_food"),
        ("塔斯汀汉堡", "fast_food"), ("老娘舅", "fast_food"), ("杨国福麻辣烫", "fast_food"),
        ("绝味鸭脖", "fast_food"), ("紫燕百味鸡", "fast_food"), ("外婆家", "restaurant"),
        ("海底捞火锅", "restaurant"), ("小菜园", "restaurant"), ("全家便利店", "convenience"),
        ("罗森便利店", "convenience"), ("十足便利店", "convenience"), ("盒马鲜生", "supermarket"),
        ("良品铺子", "convenience"), ("新华书店", "books"), ("名创优品", "retail"),
        ("屈臣氏", "pharmacy"), ("工商银行", "bank"), ("建设银行", "bank"), ("中国银行", "bank"),
        ("农业银行", "bank"), ("招商银行", "bank"), ("嘉兴银行", "bank"), ("邮政储蓄", "bank"),
        ("华为授权体验店", "mobile_phone"), ("小米之家", "mobile_phone"),
        ("中国移动", "mobile_phone"), ("中国电信", "mobile_phone"), ("中国联通", "mobile_phone"),
        ("老百姓大药房", "pharmacy"), ("海王星辰药房", "pharmacy"), ("益丰大药房", "pharmacy"),
        ("顺丰速运", "service"), ("菜鸟驿站", "service"), ("链家房产", "office"),
        ("汉庭酒店", "hotel"), ("全季酒店", "hotel"), ("亚朵酒店", "hotel"),
    ]
    LOCAL_SHOPS = [
        # Authentic earthy non-chain Chinese street shops (红底白/黄字、蓝底白字、绿底白字、黄底红字等接地气招牌!)
        ("沙县小吃", "fast_food"), ("兰州正宗牛肉拉面", "restaurant"), ("黄焖鸡米饭", "fast_food"),
        ("重庆小面", "fast_food"), ("东北手工水饺", "restaurant"), ("老字号肉夹馍", "fast_food"),
        ("正新鸡排", "fast_food"), ("嘉兴阿婆粽子", "restaurant"), ("禾城早点·豆浆油条", "fast_food"),
        ("好再来面馆", "restaurant"), ("川湘小炒家常菜", "restaurant"), ("阿强烧烤大排档", "restaurant"),
        ("老北京炸酱面", "restaurant"), ("千里香馄饨王", "fast_food"), ("三元路臭豆腐", "fast_food"),
        ("老王五金水电", "hardware"), ("鑫源电动车维修", "hardware"), ("雅迪电动车专卖", "hardware"),
        ("爱玛电动车行", "hardware"), ("顺心干洗改衣", "dry_cleaning"), ("便民打印复印", "office"),
        ("手机快修贴膜", "mobile_phone"), ("专业配钥匙开锁", "hardware"), ("兴旺烟酒副食", "convenience"),
        ("天天鲜果超市", "greengrocer"), ("社区生鲜菜店", "greengrocer"), ("惠民粮油副食", "convenience"),
        ("康乐大药房", "pharmacy"), ("红太阳美发造型", "hairdresser"), ("时尚剪艺理发", "hairdresser"),
        ("光明眼镜店", "optician"), ("快捷商务宾馆", "hotel"), ("足浴养生会馆", "beauty"),
        ("便宜实惠百货", "convenience"), ("禾兴房产中介", "office"), ("晨光文具百货", "books"),
        ("宠物美容洗护", "service"), ("江南茶叶茶庄", "cafe"), ("老字号糕点铺", "bakery"),
    ]
    YUEHE_SHOPS = [
        ("五芳斋粽子", "restaurant", "chain"), ("月河茶馆", "cafe", "local"),
        ("文虎酱鸭", "restaurant", "chain"), ("真真老老", "restaurant", "chain"),
        ("南湖茶楼", "cafe", "local"), ("禾城老面馆", "restaurant", "local"),
        ("嘉兴阿婆粽子", "restaurant", "local"), ("三元路臭豆腐", "fast_food", "local"),
        ("江南丝绸老铺", "clothes", "local"), ("江南茶叶茶庄", "cafe", "local"),
    ]
    rng = random.Random(20260522)
    storefronts = []
    used_b_edges = set()

    # Pass 1: Real OSM commercial POI nodes snapped to nearest street-facing building facade
    for nid, t in poi_nodes.items():
        if nid not in osm_nodes:
            continue
        nm = t.get("name", "").strip()
        if not nm or len(nm) > 16:
            continue
        skind = t.get("shop") or t.get("amenity") or ""
        if skind not in ("restaurant", "cafe", "fast_food", "bakery", "convenience", "supermarket", "bank", "pharmacy", "books", "clothes", "mall", "mobile_phone", "hairdresser", "hardware", "yes"):
            continue
        px, py = osm_nodes[nid]
        if not in_active((px, py)):
            continue
        best_bi = -1
        best_d = 42.0
        for bi_cand in range(len(blds)):
            b = blds[bi_cand]
            if b["h"] < 5.5 or len(b["pts"]) < 3:
                continue
            bc = centroid(b["pts"])
            dd = math.hypot(bc[0] - px, bc[1] - py)
            if dd < best_d:
                best_d = dd
                best_bi = bi_cand
        if best_bi < 0:
            continue
        poly = blds[best_bi]["pts"]
        ccw = poly_area(poly) > 0.0
        for ei in range(len(poly)):
            if (best_bi, ei) in used_b_edges:
                continue
            a, c = poly[ei], poly[(ei + 1) % len(poly)]
            el = math.hypot(c[0] - a[0], c[1] - a[1])
            if el < 5.2:
                continue
            nx, ny = ((c[1] - a[1]) / el, -(c[0] - a[0]) / el) if ccw else (-(c[1] - a[1]) / el, (c[0] - a[0]) / el)
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            rd_min = 1e9
            for (rax, ray, rbx, rby, hw) in road_grid.query(mx - 24, my - 24, mx + 24, my + 24):
                rd_min = min(rd_min, seg_dist(mx, my, rax, ray, rbx, rby)[0] - hw)
            if rd_min <= 16.5:
                ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
                sw = min(7.8, el - 0.8)
                lo = (el - sw) * 0.5
                hi = lo + sw
                storefronts.append({
                    "b": best_bi,
                    "p0": [round(a[0] + ux * lo, 2), round(a[1] + uy * lo, 2)],
                    "p1": [round(a[0] + ux * hi, 2), round(a[1] + uy * hi, 2)],
                    "n": [round(nx, 4), round(ny, 4)],
                    "name": nm,
                    "kind": skind if skind != "yes" else "restaurant",
                    "brand": nm,
                    "tier": "chain" if any(nm in cs[0] or cs[0] in nm for cs in CHAIN_SHOPS) else "local",
                })
                used_b_edges.add((best_bi, ei))
                break

    # Pass 2: High-density flush wall-to-wall continuous street-front retail rows (连排底商) across ALL Jiaxing streets!
    # Collect up to 2 street-facing facades per building (handles corner buildings!) sorted closest & widest avenues first!
    b_candidates = []
    for bi, b in enumerate(blds):
        if b["h"] < 5.5 or len(b["pts"]) < 3:
            continue
        if b.get("kind") == "industrial":
            continue
        poly = b["pts"]
        ccw = poly_area(poly) > 0.0
        face_hits = []
        for ei in range(len(poly)):
            if (bi, ei) in used_b_edges:
                continue
            a, c = poly[ei], poly[(ei + 1) % len(poly)]
            el = math.hypot(c[0] - a[0], c[1] - a[1])
            if el < 4.6:
                continue
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            best_d = 1e9
            best_hw = 4.0
            for (rax, ray, rbx, rby, hw) in road_grid.query(mx - 28, my - 28, mx + 28, my + 28):
                dd = seg_dist(mx, my, rax, ray, rbx, rby)[0] - hw
                if dd < best_d:
                    best_d = dd
                    best_hw = hw
            if best_d <= 18.0:
                face_hits.append((best_d, best_hw, ei, a, c, el, ccw))
        face_hits.sort(key=lambda it: it[0])
        for fh in face_hits[:2]:
            b_candidates.append((fh[0] - fh[1] * 0.70, bi, fh))
    b_candidates.sort(key=lambda it: it[0])

    for _prio, bi, (best_d, best_hw, ei, a, c, el, ccw) in b_candidates:
        if len(storefronts) >= 22000:
            break
        if (bi, ei) in used_b_edges:
            continue
        cen = centroid(blds[bi]["pts"])
        dist_center = math.hypot(cen[0] - OLD_CITY_CENTER[0], cen[1] - OLD_CITY_CENTER[1])
        dist_nanhu = math.hypot(cen[0] - NANHU_ORIGIN[0], cen[1] - NANHU_ORIGIN[1])
        dist_hsr = math.hypot(cen[0] - SOUTH_STA_POS[0], cen[1] - SOUTH_STA_POS[1])
        dist_yuehe = math.hypot(cen[0] - YUEHE_POS[0], cen[1] - YUEHE_POS[1])
        in_core_comm = min(dist_center, dist_nanhu) < 2600.0 or dist_hsr < 1100.0 or best_hw >= 5.2
        prob = 0.96 if (best_hw >= 5.2 or in_core_comm) else 0.85
        if rng.random() > prob:
            continue
        nx, ny = ((c[1] - a[1]) / el, -(c[0] - a[0]) / el) if ccw else (-(c[1] - a[1]) / el, (c[0] - a[0]) / el)
        ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
        # Flush wall-to-wall continuous Chinese ground-floor shop rows (连排底商 — 1 to 5 seamless bays filling the entire facade!)
        pad_end = 0.20 if el >= 9.0 else 0.12
        usable = el - pad_end * 2.0
        n_shops = max(1, min(5, int(round(usable / 5.8))))
        bay_w = usable / n_shops
        if bay_w < 3.5:
            n_shops = max(1, int(usable // 3.8))
            bay_w = usable / n_shops
        for si in range(n_shops):
            lo = pad_end + bay_w * si
            hi = pad_end + bay_w * (si + 1)
            if hi - lo < 3.4:
                continue
            if dist_yuehe < 400.0:
                sname, skind, stier = rng.choice(YUEHE_SHOPS)
            else:
                chain_p = 0.42 if (best_hw >= 5.8 or in_core_comm) else 0.26
                if rng.random() < chain_p:
                    sname, skind = rng.choice(CHAIN_SHOPS)
                    stier = "chain"
                else:
                    sname, skind = rng.choice(LOCAL_SHOPS)
                    stier = "local"
            storefronts.append({
                "b": bi,
                "p0": [round(a[0] + ux * lo, 2), round(a[1] + uy * lo, 2)],
                "p1": [round(a[0] + ux * hi, 2), round(a[1] + uy * hi, 2)],
                "n": [round(nx, 4), round(ny, 4)],
                "name": sname,
                "kind": skind,
                "brand": sname,
                "tier": stier,
            })
        used_b_edges.add((bi, ei))

    print(f"Street furniture: {len(d_cws)} crosswalks, {len(d_lamps)} lamps, {len(d_trees)} trees, {len(storefronts)} storefronts "
          f"({sum(1 for s in storefronts if s.get('tier') == 'chain')} chain + {sum(1 for s in storefronts if s.get('tier') == 'local')} local)")
    return roads, d_cws, d_lamps, d_trees, storefronts


# ---------------------------------------------------------------------------------------------
# 6. Starter Demo Network: Authentic Real-Life Jiaxing Tram T1 Phase 1 (21 Stations!)
#    嘉兴南站 -> 庆丰路 -> 由拳路 -> 纺工路 -> 嘉兴火车站 -> 中山东路 -> 安乐路（旭辉广场）
#    Rolling Stock: 中车长客 · 嘉兴“南湖号” 5-Module Supercapacitor 100% Low-Floor Tram
# ---------------------------------------------------------------------------------------------
def build_t1_starter_network(nodes_list, edges_list):
    adj = defaultdict(list)
    for e in edges_list:
        if e.get("underground"):
            continue
        adj[e["a"]].append((e["b"], e["id"], float(e["length"]), e.get("name", "")))
        adj[e["b"]].append((e["a"], e["id"], float(e["length"]), e.get("name", "")))

    T1_AVENUE_KWS = ("庆丰路", "由拳路", "纺工路", "中山东路", "勤俭路")

    def nearest_node_xy(tx, ty, prefer_kw=""):
        best_id, best_sc = 0, 1e18
        for n in nodes_list:
            nid = n["id"]
            if not adj[nid]:
                continue
            d = math.hypot(n["pos"][0] - tx, n["pos"][1] - ty)
            bonus = -35.0 if (prefer_kw and any(prefer_kw in nm for _, _, _, nm in adj[nid])) else 0.0
            if d + bonus < best_sc:
                best_sc = d + bonus
                best_id = nid
        return best_id

    def shortest_path_edges(src, dst, avoid_eids):
        pq = [(0.0, src)]
        dist = {src: 0.0}
        prev = {}
        while pq:
            d, u = heapq.heappop(pq)
            if u == dst:
                break
            if d > dist.get(u, 1e18):
                continue
            for v, eid, w, nm in adj[u]:
                if eid in avoid_eids:
                    continue
                mult = 0.80 if any(kw in nm for kw in T1_AVENUE_KWS) else 1.0
                nd = d + w * mult
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

    # All 15 authentic operational stations of Jiaxing Tram Line T1 in exact real-world Amap (高德地图) sequence:
    # Part A (Surface South -> North): 嘉兴南站(站前东行平滑北转) -> 庆丰路(庆丰路基地/长水路) -> 由拳路(商务大道) -> 纺工路(由拳路/一中/烟雨路/南溪西路/景湖路/滨河路) -> 跨平湖塘桥 -> 干地入口
    # Part B (B1 Underground Tunnel): 东隧道坡道 -> 嘉兴火车站(B1中央无遮挡廊道) -> 下穿沪昆铁路 -> 勤俭路出口坡道
    # Part C (Surface West): 勤俭路西行 -> 环城东路南行(人民公园) -> 中山东路(瓶山 -> 禾兴南路 -> 中山东路安乐路)
    waypoints_south = [
        ("嘉兴南站", 4080.68, 6817.27, ""),
        ("__south_plaza_m__", 4221.50, 6742.88, ""),
        ("__south_plaza_e__", 4392.0, 6644.0, ""),
        ("__qingfeng_s__", 4317.21, 6448.94, "庆丰路"),
        ("有轨电车庆丰路基地站", 4252.0, 4297.0, "庆丰路"),
        ("庆丰路长水路站", 4242.0, 3527.0, "庆丰路"),
        ("__qf_yq_corner__", 4216.26, 2577.23, "由拳路"),
        ("由拳路商务大道站", 2408.0, 2529.0, "由拳路"),
        ("纺工路由拳路站", 1435.0, 2436.0, "纺工路"),
        ("嘉兴一中站", 1433.0, 1540.0, "纺工路"),
        ("纺工路烟雨路站", 1294.0, 724.0, "纺工路"),
        ("纺工路南溪西路站", 1185.54, 117.30, ""),
        ("纺工路景湖路站", 1139.92, -351.19, ""),
        ("纺工路滨河路站", 985.44, -970.49, ""),
    ]
    waypoints_west = [
        ("__qinjian_corner__", 152.51, -1528.44, "勤俭路"),
        ("人民公园", 198.17, -1343.18, "环城东路"),
        ("__hcd_zsd_corner__", 238.97, -1172.32, "环城东路"),
        ("__zsd_east__", 226.44, -1130.44, "中山东路"),
        ("中山东路建国南路(瓶山)", -214.02, -1088.86, "中山东路"),
        ("中山东路禾兴南路", -689.30, -1027.66, "中山东路"),
        ("中山东路安乐路", -1119.63, -943.17, "中山东路"),
    ]
    wp_south_nodes = [(nm, nearest_node_xy(x, y, kw), x, y) for nm, x, y, kw in waypoints_south]
    # Surface continuation across 平湖塘 bridge (1320 -> 1321) onto dry land north of the canal (1328)!
    nid_pinghu_n = nearest_node_xy(985.58, -1040.28, "")
    nid_portal_e = nearest_node_xy(997.81, -1170.11, "")
    nid_portal_w = nearest_node_xy(596.91, -1523.54, "勤俭路")
    node_pos_by_id = {n["id"]: n["pos"] for n in nodes_list}
    p_portal_e = node_pos_by_id[nid_portal_e]
    p_portal_w = node_pos_by_id[nid_portal_w]

    # Smooth the South Station SE plaza corner (node 2265): OSM's raw service ramp had a 175-deg hairpin hook
    # at [4409.11, 6627.79]. Reshaping it to [4392.0, 6644.0] yields a clean 71-deg sweeping turn from the
    # HSR station front plaza (eid=3141->3198->3223) straight north along the east plaza edge onto 庆丰路 (eid=3245)!
    nid_se_turn = nearest_node_xy(4409.11, 6627.79, "")
    nid_s_mid = nearest_node_xy(4264.97, 6721.03, "")
    nid_qf_ne = nearest_node_xy(4317.21, 6448.94, "庆丰路")
    p_se_clean = [4392.0, 6644.0]
    for nd_c in nodes_list:
        if nd_c["id"] == nid_se_turn:
            nd_c["pos"] = p_se_clean
            node_pos_by_id[nid_se_turn] = p_se_clean
            break
    for ed_chk in edges_list:
        a_id, b_id = ed_chk["a"], ed_chk["b"]
        if (a_id == nid_s_mid and b_id == nid_se_turn) or (b_id == nid_s_mid and a_id == nid_se_turn):
            p_f = node_pos_by_id[nid_s_mid]
            pts_new = [p_f, [4355.0, 6674.0], p_se_clean] if a_id == nid_s_mid else [p_se_clean, [4355.0, 6674.0], p_f]
            ed_chk["pts"] = pts_new
            ed_chk["length"] = round(sum(math.hypot(pts_new[k + 1][0] - pts_new[k][0], pts_new[k + 1][1] - pts_new[k][1]) for k in range(len(pts_new) - 1)), 2)
            ed_chk["name"] = "嘉兴南站站前路"
        elif (a_id == nid_qf_ne and b_id == nid_se_turn) or (b_id == nid_qf_ne and a_id == nid_se_turn):
            p_n = node_pos_by_id[nid_qf_ne]
            pts_new = [p_n, [4356.0, 6548.0], p_se_clean] if a_id == nid_qf_ne else [p_se_clean, [4356.0, 6548.0], p_n]
            ed_chk["pts"] = pts_new
            ed_chk["length"] = round(sum(math.hypot(pts_new[k + 1][0] - pts_new[k][0], pts_new[k + 1][1] - pts_new[k][1]) for k in range(len(pts_new) - 1)), 2)
            ed_chk["name"] = "庆丰路"
        elif a_id == nid_se_turn:
            ed_chk["pts"][0] = p_se_clean
        elif b_id == nid_se_turn:
            ed_chk["pts"][-1] = p_se_clean
        if (a_id == nid_pinghu_n and b_id == nid_portal_e) or (b_id == nid_pinghu_n and a_id == nid_portal_e):
            ed_chk["width"] = max(float(ed_chk.get("width", 5.5)), 9.2)
            ed_chk["name"] = "纺工路"

    # Add a clean direct junction connector edge from 环城东路 (1112 [238.97, -1172.32]) -> 中山东路 (1099 [226.44, -1130.44])
    # so T1 turns cleanly from People's Park (环城东路) west onto 中山东路 without an OSM dual-carriageway hairpin!
    next_nid = max(n["id"] for n in nodes_list) + 1
    next_eid = max(e["id"] for e in edges_list) + 1
    nid_hcd_s = nearest_node_xy(238.97, -1172.32, "环城东路")
    nid_zsd_e = nearest_node_xy(226.44, -1130.44, "中山东路")
    if nid_hcd_s != nid_zsd_e:
        pa_hz, pb_hz = node_pos_by_id[nid_hcd_s], node_pos_by_id[nid_zsd_e]
        L_hz = round(math.hypot(pb_hz[0] - pa_hz[0], pb_hz[1] - pa_hz[1]), 2)
        e_hz = {
            "id": next_eid, "a": nid_hcd_s, "b": nid_zsd_e, "name": "环城东路",
            "width": 9.2, "lanes_f": 1, "lanes_b": 1, "length": L_hz,
            "pts": [pa_hz, pb_hz],
        }
        edges_list.append(e_hz)
        adj[nid_hcd_s].append((nid_zsd_e, next_eid, L_hz, "环城东路"))
        adj[nid_zsd_e].append((nid_hcd_s, next_eid, L_hz, "环城东路"))
        next_eid += 1

    # Create 2 dedicated B1 underground nodes & 3 subterranean tunnel edges running DEAD CENTER along
    # JiaxingStationB1Hall's unobstructed central corridor (lx = 0, y = -10.0m) straight under 沪昆铁路 -> 勤俭路!
    nid_b1_e = next_nid
    nid_b1_w = next_nid + 1
    p_b1_e = [795.0, -1185.0]
    p_b1_w = [632.0, -1342.0]
    nodes_list.append({"id": nid_b1_e, "pos": p_b1_e, "name": "嘉兴站地下南端"})
    nodes_list.append({"id": nid_b1_w, "pos": p_b1_w, "name": "嘉兴站地下北端"})

    def _add_ug_edge(eid_new, na, nb, pa, pb, ename):
        L = round(math.hypot(pb[0] - pa[0], pb[1] - pa[1]), 2)
        ed = {
            "id": eid_new, "a": na, "b": nb, "name": ename,
            "width": 9.2, "lanes_f": 0, "lanes_b": 0, "length": L,
            "pts": [pa, pb], "underground": True,
        }
        edges_list.append(ed)
        return ed

    e_ramp_in = _add_ug_edge(next_eid, nid_portal_e, nid_b1_e, p_portal_e, p_b1_e, "嘉兴站东地下隧道坡道")
    e_b1_sta = _add_ug_edge(next_eid + 1, nid_b1_e, nid_b1_w, p_b1_e, p_b1_w, "嘉兴火车站地下隧道")
    e_ramp_out = _add_ug_edge(next_eid + 2, nid_b1_w, nid_portal_w, p_b1_w, p_portal_w, "嘉兴站北地下隧道坡道")
    ug_elev_map = {
        e_ramp_in["id"]: (0.0, -10.0),
        e_b1_sta["id"]: (-10.0, -10.0),
        e_ramp_out["id"]: (-10.0, 0.0),
    }

    # Extend south surface chain across 平湖塘 bridge to dry-land dive-in node (1328)
    wp_south_chain = wp_south_nodes + [
        ("__pinghu_n__", nid_pinghu_n, node_pos_by_id[nid_pinghu_n][0], node_pos_by_id[nid_pinghu_n][1]),
        ("__portal_e__", nid_portal_e, p_portal_e[0], p_portal_e[1]),
    ]
    wp_west_nodes = [(nm, nearest_node_xy(x, y, kw), x, y) for nm, x, y, kw in waypoints_west]
    wp_west_chain = [("__portal_w__", nid_portal_w, p_portal_w[0], p_portal_w[1])] + wp_west_nodes

    track_eids = []
    seen_e = set()
    edge_by_id = {e["id"]: e for e in edges_list}
    station_targets = []  # (name, ideal_x, ideal_y, hint_idx_in_track_eids, is_term, forced_eid_or_None)

    # Trace Part A (South Surface: 嘉兴南站 -> 纺工路滨河路 -> 跨平湖塘桥 -> 干地入口)
    for i in range(len(wp_south_chain) - 1):
        nm_a, na, xa, ya = wp_south_chain[i]
        nm_b, nb, xb, yb = wp_south_chain[i + 1]
        if na == nb:
            continue
        seg_eids = shortest_path_edges(na, nb, seen_e)
        if not seg_eids:
            seg_eids = shortest_path_edges(na, nb, set())
        if not seg_eids:
            continue
        if i == 0:
            station_targets.append((nm_a, xa, ya, 0, True, None))
        for eid in seg_eids:
            if eid not in seen_e:
                seen_e.add(eid)
                track_eids.append(eid)
        if not nm_b.startswith("__"):
            station_targets.append((nm_b, xb, yb, len(track_eids) - 1, False, None))

    # Trace Part B (Underground B1 Tunnel straight through 嘉兴火车站 & underneath 沪昆铁路 -> 勤俭路!)
    for ug_ed in (e_ramp_in, e_b1_sta, e_ramp_out):
        seen_e.add(ug_ed["id"])
        track_eids.append(ug_ed["id"])
    b1_hint_idx = len(track_eids) - 2
    station_targets.append(("嘉兴火车站", 749.0, -1229.0, b1_hint_idx, False, e_b1_sta["id"]))

    # Trace Part C (West Surface: 勤俭路 -> 环城东路(人民公园) -> 中山东路 -> 安乐路旭辉广场)
    for i in range(len(wp_west_chain) - 1):
        nm_a, na, xa, ya = wp_west_chain[i]
        nm_b, nb, xb, yb = wp_west_chain[i + 1]
        if na == nb:
            continue
        seg_eids = shortest_path_edges(na, nb, seen_e)
        if not seg_eids:
            seg_eids = shortest_path_edges(na, nb, set())
        if not seg_eids:
            continue
        for eid in seg_eids:
            if eid not in seen_e:
                seen_e.add(eid)
                track_eids.append(eid)
        if not nm_b.startswith("__"):
            # Place 人民公园 station centered along 环城东路 (1066 -> 1086, y ~ -1435) matching Amap!
            sx_use, sy_use = (175.3, -1435.8) if nm_b == "人民公园" else (xb, yb)
            station_targets.append((nm_b, sx_use, sy_use, len(track_eids) - 1, i == len(wp_west_chain) - 2, None))

    # Place terminal scissors crossovers (CrossoverType.DOUBLE = 2) on clean long surface edges near both termini FIRST
    # so NO station ever overlaps a crossover!
    xover_eids = set()
    if len(track_eids) >= 8:
        for group in (track_eids[1:6], list(reversed(track_eids[-6:-1]))):
            for cand_eid in group:
                if cand_eid not in ug_elev_map and float(edge_by_id[cand_eid]["length"]) >= 62.0:
                    xover_eids.add(cand_eid)
                    break

    # Assign each of the 21 real stations cleanly to an ordered distinct edge (or well-spaced slot on a long avenue edge!)
    stations = []
    used_slots = defaultdict(list)  # eid -> list of t positions already placed
    min_track_idx = 0
    for st_i, (nm, sx, sy, hint_idx, is_term, forced_eid) in enumerate(station_targets):
        chosen_eid = -1
        chosen_t = 0.5
        if forced_eid is not None:
            chosen_eid = forced_eid
            chosen_t = 0.28  # Right inside Jiaxing Station B1 South Tram Interchange Hall (lx=0, y=-10.0m)!
            min_track_idx = max(min_track_idx, hint_idx)
        else:
            if st_i == 0:
                cand_order = list(range(0, min(4, len(track_eids))))
            elif st_i == len(station_targets) - 1:
                cand_order = list(range(len(track_eids) - 1, max(-1, len(track_eids) - 5), -1))
            else:
                lo_i = max(min_track_idx, hint_idx - 2)
                hi_i = min(len(track_eids) - 1, hint_idx + 2)
                cand_order = sorted(range(lo_i, hi_i + 1), key=lambda k: abs(k - hint_idx))

            for ti in cand_order:
                eid = track_eids[ti]
                if eid in xover_eids or eid in ug_elev_map:
                    continue
                elen = float(edge_by_id[eid]["length"])
                if elen < 48.0:
                    continue
                pts_e = edge_by_id[eid]["pts"]
                pa, pb = pts_e[0], pts_e[-1]
                dx, dy = pb[0] - pa[0], pb[1] - pa[1]
                l2 = dx * dx + dy * dy
                t_raw = 0.5 if l2 < 1e-6 else ((sx - pa[0]) * dx + (sy - pa[1]) * dy) / l2
                margin_t = min(0.36, 40.0 / elen)
                t_clamped = max(margin_t, min(1.0 - margin_t, t_raw))
                if st_i == 0:
                    # Center 嘉兴南站 tram stop right in front of the HSR Station North Entrance (local x ~ 0)!
                    t_clamped = max(margin_t, min(0.45, 0.42))
                elif st_i == len(station_targets) - 1:
                    t_clamped = min(1.0 - margin_t, max(0.65, t_clamped))
                if all(abs(t_clamped - prev_t) * elen >= 95.0 for prev_t in used_slots[eid]):
                    chosen_eid = eid
                    chosen_t = t_clamped
                    min_track_idx = max(min_track_idx, ti)
                    break
        if chosen_eid < 0:
            continue
        used_slots[chosen_eid].append(chosen_t)
        sid = len(stations) + 1
        stations.append({
            "id": sid,
            "edge_id": chosen_eid,
            "t": round(chosen_t, 3),
            "side": 0,
            "name": nm,
            "kind": 2,  # StationKind.ISLAND
            "platform_len": 42.0,  # Fits the real 34.8m 5-module "南湖号" with generous 5/5 door alignment margin!
        })

    # Center-of-Road Boulevard Upgrade (Real Jiaxing T1 cross-section: green lawn double-track tramway IN THE CENTER,
    # flanked by bidirectional motorized car lanes + outer bike lanes on BOTH sides!)
    track_eid_set = set(track_eids)
    t1_surface_segs = []
    for eid in track_eids:
        if eid in ug_elev_map:
            continue
        ed = edge_by_id[eid]
        ename = ed.get("name", "")
        is_inner_narrow = any(k in ename for k in ("勤俭", "环城东")) or (ed["pts"][0][1] > 6620.0 and ed["pts"][-1][1] > 6620.0)
        if is_inner_narrow:
            ed["width"] = max(float(ed.get("width", 8.8)), 18.0)
            ed["lanes_f"] = max(int(ed.get("lanes_f", 1)), 1)
            ed["lanes_b"] = max(int(ed.get("lanes_b", 1)), 1)
        else:
            ed["width"] = max(float(ed.get("width", 8.8)), 24.0)
            ed["lanes_f"] = max(int(ed.get("lanes_f", 2)), 2)
            ed["lanes_b"] = max(int(ed.get("lanes_b", 2)), 2)
        ed["tram_median"] = True
        pts_t = ed["pts"]
        hw_t = float(ed["width"]) * 0.5
        for k in range(len(pts_t) - 1):
            ax, ay = pts_t[k]
            bx, by = pts_t[k + 1]
            L_seg = math.hypot(bx - ax, by - ay)
            if L_seg > 1.0:
                t1_surface_segs.append((ax, ay, bx, by, (bx - ax) / L_seg, (by - ay) / L_seg, hw_t))

    # Suppress duplicate parallel OSM twin-carriageway strips running right next to the unified 24m/18m T1 boulevards
    # so there is no overlapping double asphalt or ghost parallel car lane!
    hidden_twin_cnt = 0
    for ed in edges_list:
        if ed["id"] in track_eid_set or ed.get("underground"):
            continue
        pts_o = ed["pts"]
        if len(pts_o) < 2:
            continue
        ax, ay = pts_o[0]
        bx, by = pts_o[-1]
        L_o = math.hypot(bx - ax, by - ay)
        if L_o < 12.0:
            continue
        mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
        dx_o, dy_o = (bx - ax) / L_o, (by - ay) / L_o
        for (tax, tay, tbx, tby, tdx, tdy, thw) in t1_surface_segs:
            if abs(dx_o * tdx + dy_o * tdy) < 0.88:
                continue
            d_mid = seg_dist(mx, my, tax, tay, tbx, tby)[0]
            if d_mid < thw + 11.5:
                d_a = seg_dist(ax, ay, tax, tay, tbx, tby)[0]
                d_b = seg_dist(bx, by, tax, tay, tbx, tby)[0]
                if min(d_a, d_b) < thw + 11.5 and max(d_a, d_b) < thw + 17.0:
                    ed["hide_road"] = True
                    ed["lanes_f"] = 0
                    ed["lanes_b"] = 0
                    hidden_twin_cnt += 1
                    break

    starter_tracks = []
    for eid in track_eids:
        is_ug = eid in ug_elev_map
        rec = {
            "edge_id": eid,
            "bed_style": 3 if is_ug else 2,  # Concrete slab bed inside B1 tunnel; Flush Lawn Track on avenues!
            "track_mode": 1,                 # TrackMode.DOUBLE
        }
        if is_ug:
            rec["ya"] = ug_elev_map[eid][0]
            rec["yb"] = ug_elev_map[eid][1]
        if eid in xover_eids:
            rec["crossover"] = 2  # CrossoverType.DOUBLE (scissors crossover)
            rec["crossover_t"] = 0.5
        starter_tracks.append(rec)

    starter_lines = []
    if len(stations) >= 3:
        starter_lines.append({
            "id": 1,
            "name": "T1线 · 嘉兴南站—中山东路安乐路",
            "color": [0.82, 0.12, 0.15],
            "model_key": "crrc-jiaxing-nanhu",
            "sections": 5,
            "trams_count": 6,
            "station_ids": [s["id"] for s in stations],
            "signal_priority": True,
        })

    print(f"Starter T1 network (Real Operational Amap): {len(starter_tracks)} tracked edges, {len(stations)} stations, {len(xover_eids)} crossovers, {hidden_twin_cnt} twin strips merged")
    return {
        "tracks": starter_tracks,
        "stations": stations,
        "lines": starter_lines,
        "global_signal_priority": False,
        "_surface_segs": t1_surface_segs,
    }


# ---------------------------------------------------------------------------------------------
# 6b. Chinese Gated Residential Compounds (封闭式小区围墙、小区大门牌楼、保安亭与道闸)
# ---------------------------------------------------------------------------------------------
COMPOUND_NAMES_ZH = [
    "南湖名苑", "凌公塘花园", "巴黎都市", "格林小镇", "万科金色梦想", "佳源都市",
    "御溪半岛", "翰林府第", "景宜社区", "东栅新村", "烟雨小区", "紫阳花苑",
    "中南樾府", "绿城留香园", "尚东名邸", "秀洲花园", "月河雅苑", "双溪华庭",
    "庆丰新苑", "长水嘉园", "翠柳庄园", "金都景苑", "禾兴新村", "江南摩尔苑",
    "融创望海潮", "龙湖春江天玺", "荣安府", "保利西塘越", "云海湾花园", "晴湾名苑",
    "望湖公馆", "文贤社区", "新嘉花苑", "松鹤里小区", "梅湾花园", "中港城名邸",
    "三水湾社区", "纺工新村", "勤俭新村", "桂苑小区", "竹桥新村", "金都九月洋房",
    "中梁壹号院", "荣盛百合花园", "香缇世家", "盛世豪庭", "凯旋门花园", "南湖国际社区",
    "禾兴公寓", "凌公塘壹号", "翠湖花园", "锦绣花园", "金色年华", "春晓源",
    "东方都市", "云栖里", "翡翠公馆", "熙悦府", "星河湾", "水岸嘉苑",
    "碧桂园天麓", "融创江南悦", "华润中央公园", "新城海上风华", "万达华府", "城南花园",
    "长水新村", "双溪花园", "湘家荡逸景苑", "亚太花园", "光明新村", "荷花堤小区",
]


def build_gated_compounds(landuse_zones, ways, nodes, road_grid, water_grid, rail_grid, bld_grid):
    """Build authentic Chinese gated residential compound walls & street-facing gatehouses city-wide."""
    compounds = []
    rng = random.Random(20260530)

    # Collect ALL named & unnamed OSM residential polygons first!
    res_polys = []
    for wid, (refs, t) in ways.items():
        if t.get("landuse") == "residential" and len(refs) >= 4 and refs[0] == refs[-1]:
            pts = [nodes[r] for r in refs if r in nodes][:-1]
            ring = simplify_ring(pts, 4.0)
            if len(ring) >= 4 and abs(poly_area(ring)) >= 2200.0:
                res_polys.append((ring, t.get("name", "")))

    seen_c = set()
    for ring, nm in res_polys:
        c = centroid(ring)
        seen_c.add((int(c[0] // 110), int(c[1] // 110)))
    for lu, ring in landuse_zones:
        if lu != "residential":
            continue
        c = centroid(ring)
        ck = (int(c[0] // 110), int(c[1] // 110))
        if ck in seen_c or abs(poly_area(ring)) < 2200.0:
            continue
        seen_c.add(ck)
        res_polys.append((simplify_ring(ring, 4.0), ""))

    # Synthesize block-hugging Chinese gated compounds across the ENTIRE Jiaxing urban fabric
    # (old town + Nanhu New District + Xiuzhou + East Expansion + South Station/Qingfeng corridor)!
    # Each block encloses the actual tight bounding box of residential buildings in that block so fences stay clear of roads!
    synth_zones = [
        (-3500, -3700, 5500, 4300, 175),
        (1300, 2600, 4600, 6600, 185),
    ]
    for x0, y0, x1, y1, step in synth_zones:
        for ex in range(x0, x1, step):
            for ey in range(y0, y1, step):
                cx, cy = ex + step * 0.5, ey + step * 0.5
                ck = (int(cx // 110), int(cy // 110))
                if ck in seen_c or not in_active((cx, cy), -50.0):
                    continue
                # Never enclose Yuehe Historic Quarter, Nanhu Lake Island, or Airport
                if math.hypot(cx - YUEHE_POS[0], cy - YUEHE_POS[1]) < 340.0:
                    continue
                if math.hypot(cx - NANHU_ORIGIN[0], cy - NANHU_ORIGIN[1]) < 460.0:
                    continue
                if in_airport_precinct((cx, cy)):
                    continue
                half_s = step * 0.44
                blk_blds = []
                for ob in bld_grid.query(cx - half_s, cy - half_s, cx + half_s, cy + half_s):
                    bc = centroid(ob[4])
                    if abs(bc[0] - cx) <= half_s and abs(bc[1] - cy) <= half_s:
                        blk_blds.append(ob)
                if len(blk_blds) < 3:
                    continue
                bx0 = min(ob[0] for ob in blk_blds) - 4.0
                by0 = min(ob[1] for ob in blk_blds) - 4.0
                bx1 = max(ob[2] for ob in blk_blds) + 4.0
                by1 = max(ob[3] for ob in blk_blds) + 4.0
                if (bx1 - bx0) < 38.0 or (by1 - by0) < 38.0:
                    continue
                if (bx1 - bx0) > 210.0 or (by1 - by0) > 210.0:
                    continue
                rect_r = [(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)]
                seen_c.add(ck)
                res_polys.append((rect_r, ""))

    name_idx = 0
    for ring, raw_nm in res_polys:
        if len(compounds) >= 520:
            break
        if len(ring) < 4 or len(ring) > 36:
            continue
        c = centroid(ring)
        if not in_active(c, -20.0):
            continue
        if any(point_in_poly(c[0], c[1], wp) for wp in water_grid.query(c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4)):
            continue
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        b_cnt = sum(1 for ob in bld_grid.query(min(xs), min(ys), max(xs), max(ys))
                    if point_in_poly(*centroid(ob[4]), ring))
        if b_cnt < 2:
            continue

        # Shrink polygon vertices slightly inward toward centroid (~5%) so fence stays cleanly behind sidewalks!
        shrunk = []
        for p in ring:
            vx, vy = p[0] - c[0], p[1] - c[1]
            L = math.hypot(vx, vy)
            if L > 8.0:
                sh = min(4.2, L * 0.07)
                shrunk.append((p[0] - vx / L * sh, p[1] - vy / L * sh))
            else:
                shrunk.append(p)

        # Keep only perimeter segments completely clear of roadways, water & railways!
        clean_segs = []
        gate_cand = None  # (dist_to_road, mx, my, ux, uy, nx, ny, seg_idx)
        ccw = poly_area(shrunk) > 0.0
        for i in range(len(shrunk)):
            a = shrunk[i]
            b = shrunk[(i + 1) % len(shrunk)]
            sl = math.hypot(b[0] - a[0], b[1] - a[1])
            if sl < 8.0:
                continue
            mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            hits_bad = False
            for (rax, ray, rbx, rby, hw) in road_grid.query(min(a[0], b[0]) - 14, min(a[1], b[1]) - 14, max(a[0], b[0]) + 14, max(a[1], b[1]) + 14):
                if seg_intersection(a, b, (rax, ray), (rbx, rby)) is not None:
                    hits_bad = True
                    break
                if seg_dist(mx, my, rax, ray, rbx, rby)[0] < hw + 1.6:
                    hits_bad = True
                    break
            if hits_bad:
                continue
            for (rax, ray, rbx, rby, rw) in rail_grid.query(min(a[0], b[0]) - 14, min(a[1], b[1]) - 14, max(a[0], b[0]) + 14, max(a[1], b[1]) + 14):
                if seg_dist(mx, my, rax, ray, rbx, rby)[0] < rw:
                    hits_bad = True
                    break
            if hits_bad:
                continue
            if any(point_in_poly(mx, my, wp) for wp in water_grid.query(mx - 4, my - 4, mx + 4, my + 4)):
                continue
            clean_segs.append((a, b))
            if sl >= 15.0:
                rd_d = 1e9
                for (rax, ray, rbx, rby, hw) in road_grid.query(mx - 32, my - 32, mx + 32, my + 32):
                    rd_d = min(rd_d, seg_dist(mx, my, rax, ray, rbx, rby)[0] - hw)
                if rd_d <= 26.0 and (gate_cand is None or rd_d < gate_cand[0]):
                    ux, uy = (b[0] - a[0]) / sl, (b[1] - a[1]) / sl
                    nx, ny = (uy, -ux) if ccw else (-uy, ux)
                    gate_cand = (rd_d, mx, my, ux, uy, nx, ny, len(clean_segs) - 1)

        if len(clean_segs) < 2 or gate_cand is None:
            continue
        _gd, gx, gy, gux, guy, gnx, gny, g_seg_idx = gate_cand
        # Split the gate segment to leave an 11m clean entrance driveway opening for the gatehouse & boom barrier!
        ga, gb = clean_segs[g_seg_idx]
        final_segs = []
        for si, (sa, sb) in enumerate(clean_segs):
            if si != g_seg_idx:
                final_segs.append([rnd(sa), rnd(sb)])
            else:
                g_left = (gx - gux * 5.6, gy - guy * 5.6)
                g_right = (gx + gux * 5.6, gy + guy * 5.6)
                if math.hypot(g_left[0] - sa[0], g_left[1] - sa[1]) >= 2.5:
                    final_segs.append([rnd(sa), rnd(g_left)])
                if math.hypot(sb[0] - g_right[0], sb[1] - g_right[1]) >= 2.5:
                    final_segs.append([rnd(g_right), rnd(sb)])
        nm = raw_nm if raw_nm else COMPOUND_NAMES_ZH[name_idx % len(COMPOUND_NAMES_ZH)]
        name_idx += 1
        compounds.append({
            "name": nm,
            "segs": final_segs,
            "gate_pos": rnd((gx, gy)),
            "gate_angle": round(-math.atan2(gny, gnx) + math.pi * 0.5, 4),
            "style": rng.randint(0, 2),
        })

    print(f"Chinese gated compounds: {len(compounds)} enclosed 小区 with perimeter walls, gatehouses & boom barriers")
    return compounds


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

    graph_nodes, graph_edges = build_street_graph(nodes, ways, water_grid, park_grid, rail_grid)
    rail_crossings = build_rail_crossings(graph_edges, railways)

    road_grid = Grid(45.0)
    for e in graph_edges:
        if e.get("underground"):
            continue
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

    freeways = build_freeways(nodes, ways, road_grid)
    freeway_grid = Grid(60.0)
    for fw in freeways:
        fpts = fw["pts"]
        fhw = float(fw.get("w", 12.0)) * 0.5
        for k in range(len(fpts) - 1):
            a, b = fpts[k], fpts[k + 1]
            freeway_grid.add((a[0], a[1], b[0], b[1], fhw),
                             min(a[0], b[0]) - fhw - 5.0, min(a[1], b[1]) - fhw - 5.0,
                             max(a[0], b[0]) + fhw + 5.0, max(a[1], b[1]) + fhw + 5.0)

    # Build T1 starter network & widen its center-of-road boulevards BEFORE street furniture & storefronts!
    starter = build_t1_starter_network(graph_nodes, graph_edges)
    t1_surf_segs = starter.pop("_surface_segs", [])

    # Update road_grid with widened T1 boulevard widths AND clear ANY building whose footprint encroaches on
    # the widened T1 corridor (guarantees ZERO tram tracks ever drive through a building or storefront!)
    t1_corridor_grid = Grid(80.0)
    for (ax, ay, bx, by, _dx, _dy, thw) in t1_surf_segs:
        road_grid.add((ax, ay, bx, by, thw + 1.5),
                      min(ax, bx) - thw - 4.0, min(ay, by) - thw - 4.0,
                      max(ax, bx) + thw + 4.0, max(ay, by) + thw + 4.0)
        t1_corridor_grid.add((ax, ay, bx, by, thw + 3.2),
                             min(ax, bx) - thw - 6.0, min(ay, by) - thw - 6.0,
                             max(ax, bx) + thw + 6.0, max(ay, by) + thw + 6.0)

    cleaned_blds = []
    removed_t1_blds = 0
    for b in blds:
        bpts = b.get("pts", [])
        if not bpts:
            continue
        xs = [p[0] for p in bpts]
        ys = [p[1] for p in bpts]
        cands = t1_corridor_grid.query(min(xs) - 20.0, min(ys) - 20.0, max(xs) + 20.0, max(ys) + 20.0)
        blocked = False
        if cands:
            cx = sum(xs) / len(xs)
            cy = sum(ys) / len(ys)
            chk_pts = [(cx, cy)] + [(p[0], p[1]) for p in bpts] + [
                ((bpts[k][0] + bpts[(k + 1) % len(bpts)][0]) * 0.5, (bpts[k][1] + bpts[(k + 1) % len(bpts)][1]) * 0.5)
                for k in range(len(bpts))
            ]
            for (ax, ay, bx, by, clr_r) in cands:
                for (px, py) in chk_pts:
                    if seg_dist(px, py, ax, ay, bx, by)[0] < clr_r:
                        blocked = True
                        break
                if blocked:
                    break
        if blocked:
            removed_t1_blds += 1
            continue
        cleaned_blds.append(b)
    blds = cleaned_blds
    if removed_t1_blds > 0:
        print(f"T1 corridor building clearance: removed {removed_t1_blds} buildings encroaching on widened T1 boulevards")
        bld_grid = Grid(45.0)
        for b in blds:
            bpts = b["pts"]
            xs = [p[0] for p in bpts]
            ys = [p[1] for p in bpts]
            bld_grid.add((min(xs), min(ys), max(xs), max(ys), bpts), min(xs), min(ys), max(xs), max(ys))

    roads, cws, lamps, trees, storefronts = build_street_furniture(
        graph_edges, graph_nodes, blds, poi_nodes, nodes, road_grid, water_grid, rail_grid, bld_grid, freeway_grid
    )
    gated_compounds = build_gated_compounds(landuse_zones, ways, nodes, road_grid, water_grid, rail_grid, bld_grid)

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

    # Extract ALL real OSM pedestrian stone bridges inside Yuehe Historic Quarter (月河古街步行桥)
    yuehe_bridges = []
    for wid, (refs, t) in ways.items():
        if t.get("highway") in ("footway", "pedestrian", "path") and t.get("bridge") in ("yes", "viaduct", "arch"):
            bpts = [nodes[r] for r in refs if r in nodes]
            if len(bpts) < 2:
                continue
            bc = centroid(bpts)
            if -860.0 <= bc[0] <= -420.0 and -2280.0 <= bc[1] <= -1880.0:
                span = max(11.0, min(32.0, math.hypot(bpts[-1][0] - bpts[0][0], bpts[-1][1] - bpts[0][1]) + 4.0))
                ang = -math.atan2(bpts[-1][1] - bpts[0][1], bpts[-1][0] - bpts[0][0])
                yuehe_bridges.append({
                    "pos": rnd(bc),
                    "angle": round(ang, 4),
                    "span": round(span, 1),
                    "name": t.get("name", "月河石桥"),
                })

    # Graceful Jiangnan stone arch pedestrian bridges over Huancheng Moat / Yuehe / Nanhu channels
    canal_bridges = [
        {"pos": rnd(proj(30.7734, 120.7458)), "angle": 0.45, "span": 22.0},   # 月河古桥
        {"pos": rnd(proj(30.7536, 120.7596)), "angle": 0.15, "span": 28.0},   # 烟雨桥 / 南湖天地
        {"pos": rnd(proj(30.7618, 120.7530)), "angle": -0.35, "span": 26.0},  # 会景园桥
        {"pos": rnd(proj(30.7495, 120.7465)), "angle": 0.80, "span": 28.0},   # 西南湖步桥
        {"pos": rnd(proj(30.7662, 120.7396)), "angle": 1.45, "span": 32.0},   # 环城西路桥
        {"pos": rnd(proj(30.7730, 120.7495)), "angle": 0.12, "span": 32.0},   # 环城北路桥
    ] + yuehe_bridges

    # Extract real OSM Jiaxing Nanhu Airport (嘉兴南湖机场) runway 12/30 & main taxiways
    ap_runway = [[-10101.0, 5712.0], [-6909.0, 6893.0]]
    ap_taxiways = []
    for wid, (refs, t) in ways.items():
        aw = t.get("aeroway", "")
        if aw == "runway" and t.get("ref") == "12/30":
            rpts = [nodes[r] for r in refs if r in nodes]
            if len(rpts) >= 2:
                ap_runway = [rnd(rpts[0]), rnd(rpts[-1])]
        elif aw == "taxiway" and t.get("ref") in ("B", "C", "D", "F", "G", "H", "K", "B1", "B2", "B3", "C1", "C2", "D1", "D2"):
            tpts = [nodes[r] for r in refs if r in nodes]
            if len(tpts) >= 2 and all(in_airport_precinct(p, 120.0) for p in tpts):
                ap_taxiways.append([rnd(p) for p in tpts])
    rwy_angle = -math.atan2(ap_runway[1][1] - ap_runway[0][1], ap_runway[1][0] - ap_runway[0][0])

    # Iconic Jiaxing commercial district & landmark mall rooftop / plaza signboards at real OSM coordinates
    commercial_signs = [
        {"name": "五芳斋 · 嘉兴总店", "sub": "百年老字号", "pos": rnd((-250.1, -1168.3)), "angle": 0.0, "color": [0.76, 0.12, 0.12]},
        {"name": "戴梦得购物中心", "sub": "DAIMOND PLAZA", "pos": rnd((-722.1, -879.4)), "angle": 0.0, "color": [0.16, 0.20, 0.34]},
        {"name": "旭 辉 广 场", "sub": "CIFI MALL", "pos": rnd((-947.0, -896.5)), "angle": 0.0, "color": [0.80, 0.26, 0.14]},
        {"name": "经开万达广场", "sub": "WANDA PLAZA", "pos": rnd((-3645.8, -16.9)), "angle": 1.57, "color": [0.08, 0.32, 0.64]},
        {"name": "华府八佰伴", "sub": "YAOHAN PLAZA", "pos": rnd((-2018.0, 2288.0)), "angle": 0.0, "color": [0.14, 0.22, 0.38]},
    ]

    # Extract real OSM scenic park walkways & historic old-town alleys (南湖景区步道 / 月河青石板老街 / 湘家荡生态绿道)
    def pt_in_water_m(x, y, margin=0.0):
        pts_chk = [(x, y)]
        if margin > 0.1:
            for ka in range(8):
                a_rad = ka * math.pi / 4.0
                pts_chk.append((x + math.cos(a_rad) * margin, y + math.sin(a_rad) * margin))
        for px, py in pts_chk:
            for wp in water_grid.query(px - 2, py - 2, px + 2, py + 2):
                if point_in_poly(px, py, wp):
                    return True
        return False

    scenic_paths = []
    for wid, (refs, t) in ways.items():
        hw = t.get("highway", "")
        if hw not in ("footway", "path", "pedestrian", "cycleway", "steps"):
            continue
        if t.get("tunnel") in ("yes", "building_passage") or str(t.get("layer", "0")).startswith("-"):
            continue
        fpts = [nodes[r] for r in refs if r in nodes]
        if len(fpts) < 2:
            continue
        fc = centroid(fpts)
        in_nanhu = (-540.0 <= fc[0] <= 1020.0 and -560.0 <= fc[1] <= 980.0)
        in_yuehe = (-900.0 <= fc[0] <= -380.0 and -2270.0 <= fc[1] <= -1850.0)
        in_xj = in_rect(fc, XIANGJIADANG_RECT)
        in_zicheng = math.hypot(fc[0] - ZICHENG_POS[0], fc[1] - ZICHENG_POS[1]) < 160.0
        in_cp = math.hypot(fc[0] - CENTRAL_PARK_POS[0], fc[1] - CENTRAL_PARK_POS[1]) < 320.0
        if not (in_nanhu or in_yuehe or in_xj or in_zicheng or in_cp):
            continue
        is_br = bool(t.get("bridge")) and t.get("bridge") != "no"
        kind_p = "timber" if (is_br or in_xj) else ("greenway" if hw == "cycleway" else "stone")
        w_p = 4.2 if (in_yuehe and hw == "pedestrian") else (3.4 if hw == "cycleway" else 2.8)
        scenic_paths.append({"kind": kind_p, "w": w_p, "pts": [rnd(p) for p in fpts]})

    # Add curated Nanhu Scenic Area west-peninsula (揽秀园/壕股塔院) walkways & Xiangjiadang Wetland Park lakeside loops!
    curated_paths = [
        # Haogu Pagoda & Lanxiu Garden waterfront promenade & cross trails (strictly on dry west peninsula!)
        ("stone", 3.4, [(-280, -320), (-210, -230), (-158, -162), (-105, -108)]),
        ("stone", 3.0, [(-340, -180), (-240, -175), (-158, -162), (-75, -180), (-40, -280)]),
        ("timber", 3.2, [(-290, -110), (-210, -90), (-135, -95), (-65, -115), (-35, -205), (-25, -310)]),
        ("greenway", 3.6, [(-420, -260), (-330, -120), (-260, -10), (-220, 120), (-180, 240)]),
        # Nanhu South & East Scenic Park promenade linking Main Gate -> Huijingyuan -> Nanhu Tiandi
        ("greenway", 3.8, [(786, 486), (824, 320), (830, 160), (830, 56), (822, -140), (798, -347)]),
        ("stone", 3.4, [(842, 498), (786, 486), (680, 460), (540, 440), (410, 470)]),
        # Xiangjiadang Wetland Park lush dry-shore circular walking trails & lakefront greenway!
        ("greenway", 4.0, [(4520, -5620), (4640, -5420), (4710, -5180), (4700, -4920), (4640, -4680), (4820, -4480)]),
        ("stone", 3.2, [(4710, -5180), (4560, -5180), (4560, -4960), (4700, -4920)]),
        ("timber", 3.4, [(4820, -4480), (5180, -4380), (5620, -4380), (6100, -4420), (6420, -4720), (6440, -5280), (6360, -5920)]),
        ("greenway", 3.8, [(4640, -5420), (4760, -5920), (5060, -6340), (5580, -6380), (6120, -6320), (6360, -5920)]),
    ]
    for kind_c, w_c, cpts in curated_paths:
        scenic_paths.append({"kind": kind_c, "w": w_c, "pts": [rnd(p) for p in cpts]})

    # Curated Jiangnan Lakeside Scenic Gazebos (verified strictly on dry land!)
    gazebo_cands = [
        (-215.0, -120.0),  # 揽秀园望塔亭
        (-85.0, -250.0),   # 壕股北岸亭
        (-265.0, -245.0),  # 伍相祠园亭
        (680.0, 430.0),    # 南湖东南观湖亭
        (780.0, 260.0),    # 会景园南亭
        (4660.0, -5440.0), # 湘家荡西岸亭
        (4680.0, -4820.0), # 湘家荡北林亭
        (5320.0, -4360.0), # 湘家荡望湖亭
        (6410.0, -5120.0), # 湘家荡东湿地亭
        (5560.0, -6370.0), # 湘家荡南荷风亭
    ]
    scenic_pavilions = [{"pos": rnd(p)} for p in gazebo_cands if not pt_in_water_m(p[0], p[1], 5.5)]

    # Programmatically verify Yuehe Entrance Archway (dry), Opera Stage (dry), and Wupeng Boats (strictly ON canal water!)
    yh_arch_pos = YUEHE_POS
    if pt_in_water_m(yh_arch_pos[0], yh_arch_pos[1], 6.0):
        for dx_a in range(-60, 65, 10):
            for dy_a in range(-40, 45, 10):
                cand = (YUEHE_POS[0] + dx_a, YUEHE_POS[1] + dy_a)
                if not pt_in_water_m(cand[0], cand[1], 7.0):
                    yh_arch_pos = cand
                    break
            else:
                continue
            break
    yh_opera_pos = (-680.0, -2060.0)
    for op_cand in [(-700.0, -2060.0), (-560.0, -2000.0), (-740.0, -2140.0), (-640.0, -2180.0)]:
        if not pt_in_water_m(op_cand[0], op_cand[1], 7.0):
            yh_opera_pos = op_cand
            break
    yh_boats = []
    for bx, by, bang in [
        (-610.0, -2060.0, 0.25),
        (-520.0, -2135.0, -0.30),
        (-660.0, -2000.0, 0.65),
        (-540.0, -1975.0, -0.55),
        (-730.0, -1955.0, 0.40),
        (-580.0, -2125.0, 0.12),
    ]:
        if pt_in_water_m(bx, by, 1.5):
            yh_boats.append({"pos": rnd((bx, by)), "angle": bang})

    print(f"Scenic features: {len(scenic_paths)} park walkways, {len(scenic_pavilions)} lakeside pavilions, "
          f"{len(yh_boats)} Yuehe canal boats, arch={rnd(yh_arch_pos)}, opera={rnd(yh_opera_pos)}")

    landmarks = {
        "jiaxing_south_station": {"pos": rnd(SOUTH_STA_POS), "angle": round(hsr_angle, 4)},
        "yanyu_tower": {"pos": rnd(YANYU_POS), "island_pts": island_pts},
        "haogu_pagoda": {"pos": rnd(HAOGU_PAGODA_POS)},
        "huijingyuan": {"pos": rnd(HUIJINGYUAN_POS)},
        "nanhu_gate": {"pos": rnd(NANHU_GATE_POS), "angle": -1.32},
        "nanhu_tiandi": {"pos": rnd(NANHU_TIANDI_POS)},
        "nanhu_memorial": {"pos": rnd(MEMORIAL_POS), "angle": 0.08},
        "jiaxing_gov": {"pos": rnd(GOV_POS), "angle": 0.04},
        "jiaxing_no1_school": {"pos": rnd(JIAXING_NO1_POS), "angle": 0.02},
        "yuehe_quarter": {
            "pos": rnd(yh_arch_pos),
            "arch_pos": rnd(yh_arch_pos),
            "opera_pos": rnd(yh_opera_pos),
            "angle": 0.14,
            "bridges": yuehe_bridges,
            "boats": yh_boats,
        },
        "scenic_paths": scenic_paths,
        "scenic_pavilions": scenic_pavilions,
        "gated_compounds": gated_compounds,
        "zicheng_park": {"pos": rnd(ZICHENG_POS), "angle": 0.05},
        "catholic_church": {"pos": rnd(CATHOLIC_CHURCH_POS), "angle": 0.06},
        "first_hospital": {"pos": rnd(FIRST_HOSPITAL_POS), "angle": 0.03},
        "second_hospital": {"pos": rnd(SECOND_HOSPITAL_POS), "angle": 0.08},
        "tcm_hospital": {"pos": rnd(TCM_HOSPITAL_POS), "angle": -0.10},
        "yaohan_mall": {"pos": rnd(YAOHAN_POS), "bridge_pos": rnd(YAOHAN_BRIDGE_POS), "angle": 0.28},
        "central_park": {"pos": rnd(CENTRAL_PARK_POS), "angle": 0.0},
        "jiaxing_station": {"pos": rnd(JIAXING_STA_POS), "angle": round(jx_angle, 4)},
        "botanical_conservatory": {"pos": rnd(BOTANICAL_POS)},
        "hilton_hotel": {"pos": rnd(HILTON_POS), "angle": 0.08},
        "wanda_nanhu": {"pos": rnd(WANDA_NANHU_POS), "angle": 0.06},
        "sams_club": {"pos": rnd(SAMS_CLUB_POS), "angle": 0.05},
        "xiangjiadang_park": {"pos": rnd(XIANGJIADANG_PARK_POS), "angle": 0.0},
        "jiaxing_airport": {
            "pos": rnd(AIRPORT_TERM_POS),
            "angle": round(rwy_angle, 4),
            "runway": ap_runway,
            "taxiways": ap_taxiways,
        },
        "commercial_signs": commercial_signs,
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
