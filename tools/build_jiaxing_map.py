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

from jiaxing_t1_survey import NO_SHOP_BOXES  # noqa: E402
from jiaxing_google_survey import (  # noqa: E402
    ARCHETYPES,
    REAL_CAMPUSES,
    REAL_COMPOUNDS,
    REAL_SHOPS_GOOGLE,
    T1_ROAD_WIDTHS,
    find_compound,
    nearest_real_compound_name,
    road_spec_for_name,
)
from google_earth_sampler import GoogleEarthSampler  # noqa: E402

GE_SAMPLER = GoogleEarthSampler()

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
QINGFENG_CORRIDOR = rect_ll(30.6945, 120.7895, 30.7264, 120.8035)
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
JIAXING_NO1_POS = (1680.0, 1385.0)        # 嘉兴市第一中学 (full authentic campus east of 纺工路, north of 中环南路)
HANLIN_POS = (1268.0, 1412.0)             # 瀚林府邸 (嘉兴一中纺工路西侧高端封闭小区)
NO1_BRIDGE_POS = (1427.6, 1506.5)         # 嘉兴一中站人行过街天桥 (位于站台北端，实景1:1对齐)
YUEHE_POS = (-620.0, -1930.0)             # 月河历史街区南入口牌坊 (verified dry land!)
ZICHENG_POS = (-306.0, -816.0)            # 子城遗址公园 · 谯楼
PINGSHAN_PARK_POS = (-325.0, -1210.0)     # 瓶山公园 (real OSM park hillock north of 中山东路建国南路)
SHAONIAN_POS = (-485.5, -1342.0)          # 少年路步行街 (中山东路至环城北路历史商业步行街)
JIANGNAN_MALL_POS = (-625.0, -1105.0)     # 江南大厦 (中山东路/禾兴南路东北角老牌百货地标)
DIAMOND_PLAZA_POS = (-740.0, -900.0)      # 戴梦得大厦 · 戴梦得购物中心 (禾兴南路520号商圈地标)
CIFI_PLAZA_POS = (-955.0, -885.0)         # 旭辉广场 (中山东路666号核心商业综合体)
CATHOLIC_CHURCH_POS = (-522.0, -894.0)    # 嘉兴天主教堂 (圣母显灵堂)
# 中山东路 × 禾兴南路 block, laid out from the satellite view (built by ZhongshanBlockBuilder): sites kept free of
# generated blocks and vacant-plot greening -- 中山影城 + corner plaza, 戴梦得, 旭辉广场, 江南大厦, the 天主堂 lawn
ZS_RECTS = [
    (-806.0, -998.0, -694.0, -936.0),    # 中山影城 and its round corner plaza
    (-796.0, -938.0, -688.0, -800.0),    # 戴梦得 podium, rotunda, tower, triangular wing
    (-964.0, -995.0, -800.0, -832.0),    # 旭辉广场 forecourt, U podium and towers
    (-680.0, -1140.0, -585.0, -1047.0),  # 江南大厦
    (-668.0, -1034.0, -452.0, -792.0),   # 天主堂 and its open lawn
]


def in_zs_rect(x, y):
    return any(x0 <= x <= x1 and y0 <= y <= y1 for (x0, y0, x1, y1) in ZS_RECTS)


# 南湖天地 (east shore between the lake and 纺工路/T1), laid out from the satellite view, and the two Hyatt hotels
# (built by NanhuBuilder): sites kept free of generated blocks
NH_RECTS = [
    (690.0, -485.0, 912.0, -345.0),     # 嘉绢 sawtooth hall and the glass shop pavilions east of it
    (690.0, -345.0, 935.0, -262.0),     # central axis plaza and the pavilions on its south side
    (836.0, -272.0, 920.0, -170.0),     # 南湖书院
    (935.0, -322.0, 1136.0, 100.0),     # new 南湖天地 glass mall along 纺工路 (construction ground up to T1)
    (895.0, -322.0, 946.0, 60.0),       # west side of 南湖路: low-rise only
    (838.0, -172.0, 946.0, 60.0),       # 南堰新景 shore promenade
    (878.0, -640.0, 1080.0, -360.0),    # 南湖凯悦酒店 and 凯悦嘉轩酒店
    (1040.0, -420.0, 1110.0, -340.0),   # 凯悦嘉轩酒店 corner at 景湖路 × 纺工路
    (520.0, -665.0, 785.0, -476.0),     # 鸳湖里弄 lane houses
]
NH_LANES_RECT = (522.0, -660.0, 780.0, -480.0)


def in_nh_rect(x, y):
    return any(x0 <= x <= x1 and y0 <= y <= y1 for (x0, y0, x1, y1) in NH_RECTS)
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


def in_zhonghuan(x, y):
    """Inside the 中环 ring (中环西/北/东/南路): Jiaxing's 1980s-2000s city, built mostly as 5-7 storey walk-up
    小区 (烟雨社区, 南溪花园, 湖滨花园 ... as on the Amap satellite layer), not the 18-33 storey towers of the
    new districts outside it."""
    return -2900.0 < x < 2250.0 and -3250.0 < y < 1450.0



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
            (JIAXING_NO1_POS, 245.0), (CENTRAL_PARK_POS, 150.0), (JIAXING_STA_POS, 190.0),
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
        if ed.get("cls"):
            rec["cls"] = ed["cls"]
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
    if t.get("landuse") in ("farmland", "orchard", "allotments", "plant_nursery", "greenhouse_horticulture"):
        return "farmland"
    if t.get("leisure") in ("park", "garden", "dog_park", "nature_reserve", "playground") or t.get("landuse") == "cemetery":
        return "park"
    if t.get("natural") in ("wood", "scrub") or t.get("landuse") == "forest":
        return "wood"
    if t.get("landuse") in ("grass", "recreation_ground", "village_green", "meadow", "flowerbed") or t.get("natural") in ("grassland", "wetland"):
        return "grass"
    if t.get("leisure") in ("pitch", "track", "sports_centre", "stadium") and t.get("building") is None:
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
    # Full lush wetland meadow lawn covering Xiangjiadang Wetland Park (visual green ground backdrop only —
    # do NOT append into park_polys so the 900+ real lakeside villages & resorts around Xiangjiadang are preserved!)
    xr = XIANGJIADANG_RECT
    xj_meadow = [(xr[0] + 10, xr[1] + 10), (xr[2] - 10, xr[1] + 10), (xr[2] - 10, xr[3] - 10), (xr[0] + 10, xr[3] - 10)]
    areas.append({"kind": "park", "pts": [rnd(p) for p in xj_meadow]})
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


def make_shaped_poly(cx, cy, ang, hl, hw, shape_kind="rect"):
    """Generate authentic Chinese residential / commercial building footprints (stepped 凸 slab,
    winged lightwell slab, point-tower cross, L-block, or stairwell-projected walk-up) in local
    building coordinates rotated by `ang`. Always simple & CCW-consistent."""
    if shape_kind == "rect" or hl < 8.0 or hw < 4.5:
        return make_rect_poly(cx, cy, ang, hl, hw)
    ca, sa = math.cos(ang), math.sin(ang)
    if shape_kind == "stepped_slab":
        # Modern Chinese 高层板楼 (凸字退台板楼: central bay projects slightly south & north)
        w0 = hw * 0.86
        w1 = hw * 1.12
        x1 = hl * 0.42
        local = [
            (-hl, -w0), (-x1, -w0), (-x1, -w1), (x1, -w1), (x1, -w0), (hl, -w0),
            (hl, w0), (x1, w0), (x1, w1), (-x1, w1), (-x1, w0), (-hl, w0),
        ]
    elif shape_kind == "wing_slab":
        # Twin-wing Chinese slab with recessed central north lightwell & proud end wings (工字/凹槽板楼)
        w_in = hw * 0.72
        w_out = hw * 1.08
        x1 = hl * 0.36
        local = [
            (-hl, -w_out), (-x1, -w_out), (-x1, -w_in), (x1, -w_in), (x1, -w_out), (hl, -w_out),
            (hl, w_out), (x1 * 0.85, w_out), (x1 * 0.85, w_in * 1.18), (-x1 * 0.85, w_in * 1.18),
            (-x1 * 0.85, w_out), (-hl, w_out),
        ]
    elif shape_kind == "point_cross":
        # Chinese 点式高层 / 蝶形点楼 (stepped-corner cross/pinwheel massing)
        c_x = hl * 0.62
        c_y = hw * 0.62
        hx = min(hl, hw * 1.45)
        hy = max(hw, hx * 0.78)
        cx_ = hx * 0.56
        cy_ = hy * 0.56
        local = [
            (-cx_, -hy), (cx_, -hy), (cx_, -cy_), (hx, -cy_),
            (hx, cy_), (cx_, cy_), (cx_, hy), (-cx_, hy),
            (-cx_, cy_), (-hx, cy_), (-hx, -cy_), (-cx_, -cy_),
        ]
    elif shape_kind == "L_wing":
        # Authentic corner L-shaped apartment / street-front mixed-use block
        wx = hl * 0.32
        wy = hw * 0.45
        local = [
            (-hl, -hw), (hl, -hw), (hl, wy), (wx, wy), (wx, hw * 1.35), (-hl, hw * 1.35),
        ]
    elif shape_kind == "walkup_stair":
        # Classic 1990s-2000s 单元多层板楼 with 2 crisp projecting north stairwell bays (flush under pitched roof eaves)
        st_d = min(0.55, hw * 0.10)
        s0, s1 = -hl * 0.48, -hl * 0.24
        s2, s3 = hl * 0.24, hl * 0.48
        local = [
            (-hl, -hw), (s0, -hw), (s0, -hw - st_d), (s1, -hw - st_d), (s1, -hw),
            (s2, -hw), (s2, -hw - st_d), (s3, -hw - st_d), (s3, -hw), (hl, -hw),
            (hl, hw), (-hl, hw),
        ]
    else:
        return make_rect_poly(cx, cy, ang, hl, hw)
    return [(cx + lx * ca - ly * sa, cy + lx * sa + ly * ca) for lx, ly in local]


def poly_fits_rect_roof(poly, hl, hw):
    """Return True only when a rectangular OBB pitched roof cleanly covers the footprint (never over L-wings!)."""
    if len(poly) == 6:
        return False
    area = abs(poly_area(poly))
    box_area = max(1e-6, 4.0 * hl * hw)
    return (area / box_area) >= 0.86


def pitched_roof_dict(cx, cy, ang, hl, hw, shape="gabled"):
    rh = max(1.8, min(4.6, hw * 0.55))
    return {"shape": shape, "h": round(rh, 2), "c": [round(cx, 2), round(cy, 2)], "a": round(ang, 4),
            "hl": round(hl, 2), "hw": round(hw, 2)}


# 月河 watertown houses / alleys are handed to the dedicated Jiangnan builder (not the generic city buildings)
YH_HOUSES = []
YH_ALLEYS = []
YH_SIGNS = ["五味堂江浙土菜", "小小月河楼", "嘉兴粽子博物馆", "月河茶馆", "南湖茶楼", "禾城老面馆", "江南丝绸老铺",
            "江南茶叶茶庄", "五芳斋粽子", "文虎酱鸭", "真真老老", "三元路臭豆腐", "江南小酒馆", "清河人家", "米酒坊",
            "月河客栈", "老街糕团", "嘉禾书局", "梅花糕", "古玩字画", "青团铺", "黄酒馆", "蓝印花布", "手工竹编"]


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
        (MEMORIAL_POS, 105.0, "nanhu_memorial"),
        (GOV_POS, 125.0, "jiaxing_gov"),
        (JIAXING_NO1_POS, 175.0, "jiaxing_no1_school"),
        (YUEHE_POS, 18.0, "yuehe_quarter"),
        (ZICHENG_POS, 92.0, "zicheng_park"),
        ((-315.0, -935.0), 72.0, "zicheng_park_north"),
        (PINGSHAN_PARK_POS, 74.0, "pingshan_park"),
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

    def can_place(pts, bb, allow_in_park=False, water_margin=0.0, tight=False, allow_yuehe=False, real_bldg=False):
        cen = centroid(pts)
        if not in_active(cen):
            return False
        # Preserve Yuehe Historic Quarter (月河历史街区) strictly for authentic 1-2 story Jiangnan heritage houses (zero modern towers!)
        if not allow_yuehe and -898.0 <= cen[0] <= -382.0 and -2272.0 <= cen[1] <= -1848.0:
            return False
        # Never place residential/commercial blocks inside the Airport airside precinct
        if not allow_in_park and in_airport_precinct(cen):
            return False
        for lpos, lrad, _ in lm_zones:
            if math.hypot(cen[0] - lpos[0], cen[1] - lpos[1]) < lrad:
                return False
        # landmark sites: no generated block may even touch one (centroid tests let wide blocks clip in)
        bx0 = min(q[0] for q in pts)
        bx1 = max(q[0] for q in pts)
        by0 = min(q[1] for q in pts)
        by1 = max(q[1] for q in pts)
        if any(bx1 > x0 and bx0 < x1 and by1 > y0 and by0 < y1 for (x0, y0, x1, y1) in ZS_RECTS + NH_RECTS):
            return False
        # Keep MAD Architects' 1:1 Jiaxing Station South Plaza circular green-roof pavilions & forest park
        # (triangular plaza between SE tracks, 东方路 x=948, and 环城河 south canal y=-1040) clear of generic boxes!
        if 650.0 <= cen[0] <= 948.0 and -1398.0 <= cen[1] <= -1040.0 and cen[1] > (-cen[0] - 485.0):
            return False
        # Keep the full Jiaxing South HSR Station + 1:1 Google Earth North Plaza precinct (Bus/Taxi Hubs,
        # P2 Parking Garage, NE Grid-Frame Hotel, SW Atrium Building & W High-Rise Complex) 100% clear of
        # overlapping generic satellite footprints!
        dx_s = cen[0] - SOUTH_STA_POS[0]
        dy_s = cen[1] - SOUTH_STA_POS[1]
        ca_s, sa_s = math.cos(0.4925), math.sin(0.4925)
        lx_s = dx_s * ca_s - dy_s * sa_s
        lz_s = dx_s * sa_s + dy_s * ca_s
        if -240.0 <= lx_s <= 272.0 and -362.0 <= lz_s <= 80.0:
            return False
        # Keep the bespoke Jiaxing No.1 High School (嘉兴一中) campus and Hanlin Residence (瀚林府邸) inner courtyard
        # clear of duplicate towers, while PRESERVING real 沿街商铺 strips lining both sides of 纺工路 & 赞成·学仕苑!
        def _in_no1_or_hanlin(qx, qy):
            x_fg = 1376.2 + (qy - 1260.2) * 0.2058
            if 1262.0 <= qy <= 1595.0 and x_fg + 14.0 <= qx <= 1898.0:
                return True
            if 1285.0 <= qy <= 1545.0 and 1158.0 <= qx <= x_fg - 48.0:
                return True
            return False

        if _in_no1_or_hanlin(cen[0], cen[1]):
            return False
        # Keep 少年路步行街 (Shaonian Pedestrian Street: 中山东路 -> 环城北路) corridor clear for bespoke arcades!
        if seg_dist(cen[0], cen[1], -445.0, -1065.0, -526.0, -1622.0)[0] < 22.0:
            return False
        if any(seg_dist(p[0], p[1], -445.0, -1065.0, -526.0, -1622.0)[0] < 18.0 for p in pts):
            return False
        # Keep Jiaxing T1 open-cut U-trough tunnel ramps 100% free of surface buildings!
        # East portal runs STRAIGHT NORTH down 纺工路/东方路 center median (993.3,-1075.3 -> 998.5,-1195.0)
        for (rax, ray, rbx, rby) in (
            (993.3, -1075.3, 998.5, -1195.0),
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
        # Check road clearance (real satellite footprints sit right behind sidewalks; keep asphalt strictly clear)
        rd_pad = 0.5 if real_bldg else 2.2
        for (ax, ay, bx, by, hw) in road_grid.query(bb[0] - 18, bb[1] - 18, bb[2] + 18, bb[3] + 18):
            lim = hw + rd_pad
            if (not real_bldg or hw >= 5.2) and point_in_poly((ax + bx) * 0.5, (ay + by) * 0.5, pts):
                return False
            if seg_dist(cen[0], cen[1], ax, ay, bx, by)[0] < (hw * 0.65 if real_bldg else lim):
                return False
            if not real_bldg:
                for p in pts:
                    if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < lim:
                        return False
            else:
                # For real buildings (already nudged off kerbs), reject only if a vertex still deeply intrudes into asphalt
                for p in pts:
                    if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < max(0.0, hw - 1.8):
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
        # Check overlap with existing buildings (tight=True allows authentic shoulder-to-shoulder Yuehe rowhouses!)
        pad_ov = 0.15 if tight else 1.5
        for ob in taken.query(bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2):
            if ob[2] < bb[0] - pad_ov or ob[0] > bb[2] + pad_ov or ob[3] < bb[1] - pad_ov or ob[1] > bb[3] + pad_ov:
                continue
            if point_in_poly(cen[0], cen[1], ob[4]) or point_in_poly(*centroid(ob[4]), pts):
                return False
            if not tight:
                for p in pts:
                    if point_in_poly(p[0], p[1], ob[4]):
                        return False
            else:
                # For tight rowhouses, only reject deep overlaps (> 45% overlap with existing footprint)
                in_cnt = sum(1 for p in pts if point_in_poly(p[0], p[1], ob[4]))
                if in_cnt >= 2:
                    return False
        return True

    # Load 100% real-world satellite-extracted + OSM 3D building dataset (TUM GlobalBuildingAtlas LoD1, WGS-84)
    # PLUS up-to-date 2021-2025 Amap real building footprints recovered across all of Jiaxing!
    real_bldg_path = os.path.join(HERE, "osm_cache", "jiaxing_real_buildings.json")
    amap_2025_path = os.path.join(HERE, "osm_cache", "jiaxing_amap_2025_buildings.json")
    gba_real_buildings = []
    osm_lod1_h = {}
    if os.path.exists(real_bldg_path):
        with open(real_bldg_path, "r", encoding="utf-8") as f_rb:
            gba_real_buildings = json.load(f_rb)
        for rb in gba_real_buildings:
            if rb.get("s") == "osm" and rb.get("h", 0.0) > 1.0:
                k_id = str(rb.get("k", ""))[3:-3]
                if k_id.isdigit():
                    osm_lod1_h[int(k_id)] = float(rb["h"])
        print(f"Loaded {len(gba_real_buildings)} real Jiaxing buildings from {os.path.basename(real_bldg_path)}")
    else:
        print(f"WARNING: {real_bldg_path} not found — run tools/fetch_jiaxing_real_buildings.py first!")
    if os.path.exists(amap_2025_path):
        with open(amap_2025_path, "r", encoding="utf-8") as f_a25:
            amap_2025 = json.load(f_a25)
        gba_real_buildings.extend(amap_2025)
        print(f"Loaded +{len(amap_2025)} brand-new 2021-2025 real buildings from {os.path.basename(amap_2025_path)}")

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
        if not can_place(pts, bb, allow_in_park=True, real_bldg=True):
            continue
        kind = t.get("building", "yes")
        is_sports_bldg = (t.get("leisure") in ("sports_hall", "stadium", "sports_centre") or
                          kind in ("stadium", "grandstand") or
                          (kind == "roof" and area > 2000.0))
        if is_sports_bldg:
            kind = "civic"
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
        if h is None and wid in osm_lod1_h:
            raw_h = osm_lod1_h[wid]
            h = raw_h if is_sports_bldg else (raw_h * 1.45 if raw_h < 12.0 else raw_h * 1.25)
        if h is None:
            if is_sports_bldg:
                h = 22.0
            elif kind in ("school", "university", "college", "hospital", "public", "civic"):
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
        style = 1 if is_sports_bldg else (0 if h >= 42.0 else (1 if kind in ("commercial", "retail", "school", "civic") else (3 if h <= 11.0 and area < 320 else 2)))
        b = {"pts": [rnd(p) for p in pts], "h": round(h, 1), "kind": kind, "style": style}
        if is_sports_bldg:
            b["colour"] = "#e2e6eb"
            b["trim"] = "#4a525c"
        if t.get("name"):
            b["name"] = t["name"]
        if t.get("building:colour"):
            b["colour"] = t["building:colour"]
        if style == 3:
            o = obb(pts)
            if o and abs(area) / (4.0 * o[3] * o[4] + 1e-6) > 0.84 and o[4] >= 2.8 and o[3] <= 34.0:
                b["roof"] = pitched_roof_dict(*o)
                b["roof_colour"] = "#333840"
        if GE_SAMPLER.available:
            ge = GE_SAMPLER.sample_footprint(pts)
            if ge is not None:
                if ge["roof_class"] == "steel_blue" and h <= 20.0:
                    b["roof_colour"] = ge["roof_hex"]
                    if "roof" not in b:
                        o = obb(pts)
                        if o and abs(area) / (4.0 * o[3] * o[4] + 1e-6) > 0.82:
                            b["roof"] = pitched_roof_dict(*o)
                            b["roof"]["h"] = round(max(1.2, min(2.4, o[4] * 0.28)), 2)
                elif ge["roof_class"] == "terracotta_red" and h <= 24.0:
                    b["roof_colour"] = ge["roof_hex"]
                    if "roof" not in b:
                        o = obb(pts)
                        if o and abs(area) / (4.0 * o[3] * o[4] + 1e-6) > 0.84:
                            b["roof"] = pitched_roof_dict(*o)
                elif "roof" in b and ge["roof_class"] in ("dark_slate", "warm_tan"):
                    b["roof_colour"] = ge["roof_hex"]
        comp_osm = find_compound(*centroid(pts))
        if comp_osm is not None and not b.get("name") and kind in ("apartments", "residential", "yes"):
            b["name"] = comp_osm["name"]
            if not b.get("colour") and comp_osm["wall"]:
                b["colour"] = comp_osm["wall"]
            if comp_osm["trim"]:
                b["trim"] = comp_osm["trim"]
            b["arch"] = comp_osm["arch_key"]
        elif not b.get("colour"):
            cx_o, cy_o = centroid(pts)
            oh = (int(cx_o * 0.23) * 73856093 ^ int(cy_o * 0.23) * 19349663) & 0x7FFFFFFF
            b["colour"] = ["#f0e4d0", "#eccfa8", "#f3efe6", "#e4eaf0", "#edd5b4", "#e4b292", "#e2e9e4", "#f4f1ea"][oh % 8]
        out.append(b)
        taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
        osm_cnt += 1

    rng = random.Random(20260521)

    def _lift_daylight_hex(hx, target_max=242):
        """Scale wall hex proportionally up to bright daylight reflectance WITHOUT washing out hue saturation!"""
        if not hx or not hx.startswith("#") or len(hx) != 7:
            return hx
        r = int(hx[1:3], 16)
        g = int(hx[3:5], 16)
        b_c = int(hx[5:7], 16)
        mx = max(r, g, b_c, 1)
        if mx < target_max:
            sc = min(1.32, target_max / float(mx))
            r = min(248, int(round(r * sc)))
            g = min(248, int(round(g * sc)))
            b_c = min(248, int(round(b_c * sc)))
        return f"#{r:02x}{g:02x}{b_c:02x}"

    # Bright, richly diverse Jiaxing daylight architectural palettes calibrated to Google Earth satellite imagery:
    # distinct warm champagne-gold, sunlit apricot, terracotta-peach, crisp pure white, sky-blue Low-E glass,
    # emerald-teal glass, pale butter-yellow, soft sage-cream, pearl-blue-silver & warm brick-red!
    PALETTE_MODERN = [
        "#f7f7f5", "#f5dfb8", "#d4e6f5", "#f0c294", "#f6edd6",
        "#cde4df", "#e6ab86", "#dce8d8", "#f3d8a4", "#eaeef2",
    ]
    PALETTE_RES = [
        "#f5dfba", "#efbe8e", "#f7f3ea", "#d8e7f4", "#f4d29a",
        "#e6a682", "#f4ead4", "#d6e6da", "#edb992", "#f1e3c4",
    ]
    PALETTE_JIANGNAN = ["#f7f4ed", "#f2ece0", "#f9f6f0", "#ede7da"]
    PALETTE_TOWER = [
        "#6eb0de", "#86c0e6", "#5fa2d2", "#d8e6f4", "#68b8b0",
        "#e6eff7", "#c4dcf0", "#ebd8b0", "#7ebad8", "#f0f4f8",
    ]
    # Facade schemes of Jiaxing compounds (wall, trim): luminous AND unmistakably varied across blocks!
    PALETTE_ZH2026 = [
        ("#f6ead4", "#6b5a46"), ("#f5dba8", "#806242"), ("#f4f6f8", "#485260"), ("#f0be8e", "#7a523a"),
        ("#d6e6f4", "#3c4c60"), ("#f7f4ec", "#565a62"), ("#e6a882", "#744a36"), ("#f4d69c", "#7c5e3e"),
        ("#cde2dc", "#425852"), ("#f2e2c2", "#6e5a44"), ("#e8b48e", "#704c38"), ("#e2ebf4", "#465466"),
    ]
    GE_HUE_PALETTES = {
        "bright_white": [("#f7f8fa", "#4a5360"), ("#f8f5ee", "#5c564e"), ("#eef3f8", "#445060"), ("#f4f2eb", "#58544c")],
        "warm_cream":   [("#f6e2b8", "#785e42"), ("#f5d89e", "#806240"), ("#f7ebd0", "#6c5a46"), ("#f2cf94", "#7e5c3e")],
        "terracotta":   [("#efb88e", "#7c4e38"), ("#e6a27c", "#764632"), ("#f2c49c", "#80543a"), ("#df9670", "#704230")],
        "cool_silver":  [("#d6e6f4", "#3e4e62"), ("#cce0f2", "#3a4a5e"), ("#e4edf6", "#485666"), ("#c8dce8", "#3d5060")],
        "blue_roof":    [("#d4e6f6", "#385270"), ("#c8dff4", "#344e6c"), ("#e2eef8", "#405874"), ("#c0daf0", "#364f6e")],
        "warm_stone":   [("#f4e2c2", "#705c46"), ("#eed8b0", "#6c5640"), ("#d8e8dc", "#485e52"), ("#f2e8d4", "#64584a")],
    }

    def zone_profile(px, py):
        """Development profile of a point: uses real Google Maps/Earth surveyed Jiaxing compound
        when available, otherwise deterministic ~220 m block developer profile."""
        comp = find_compound(px, py)
        if comp is not None:
            arch = comp["arch"]
            ak = comp["arch_key"]
            hsh = abs(hash(comp["name"])) & 0x7FFFFFFF
            f_lo, f_hi = arch["floors"]
            tfl = f_lo + (hsh % max(1, f_hi - f_lo + 1))
            y_lo, y_hi = arch.get("y_floors", arch["floors"])
            yfl = y_lo + ((hsh // 13) % max(1, y_hi - y_lo + 1))
            wall_c = _lift_daylight_hex(comp["wall"], 244) if comp["wall"] else arch["walls"][hsh % len(arch["walls"])]
            trim_c = _lift_daylight_hex(comp["trim"], 130) if comp["trim"] else arch["trims"][(hsh // 7) % len(arch["trims"])]
            roof_c = comp["roof"] or arch["roofs"][(hsh // 19) % len(arch["roofs"])]
            if ak in ("old_walkup_red", "old_walkup_slate", "old_jiangnan"):
                ctype = "walkup"
            elif ak == "garden_yangfang":
                ctype = "yangfang"
            elif ak == "mixed_modern":
                ctype = "mixed"
            else:
                ctype = "tower"
            return ctype, tfl, yfl, (wall_c, trim_c), 800000 + (hsh % 199999), comp, roof_c

        cx_i, cy_i = int(math.floor(px / 220.0)), int(math.floor(py / 220.0))
        hsh = (cx_i * 73856093) ^ (cy_i * 19349663) ^ 0x5bd1e995
        hsh &= 0x7FFFFFFF
        r_t = (hsh % 1000) / 1000.0
        if in_zhonghuan(px, py):
            ctype = "walkup" if r_t < 0.68 else ("yangfang" if r_t < 0.85 else "tower")
        else:
            ctype = "tower" if r_t < 0.56 else ("yangfang" if r_t < 0.80 else "mixed")
        tfl = [16, 18, 20, 22, 24, 26, 28, 30][(hsh // 1000) % 8]
        yfl = [6, 7, 8, 9, 11][(hsh // 8000) % 5]
        sch = PALETTE_ZH2026[(hsh // 40000) % len(PALETTE_ZH2026)]
        rc = ["#3c424b", "#924232", "#474d56", "#863b2d"][(hsh // 13000) % 4]
        return ctype, tfl, yfl, sch, 900000 + (hsh % 899999), None, rc

    def choose_shape(px, py, ctype, row_hint, is_tower):
        """Pick an authentic Chinese building footprint shape for this building."""
        comp = find_compound(px, py)
        hsh = (int(px * 0.37) * 2654435761 ^ int(py * 0.41) * 2246822519) & 0x7FFFFFFF
        if comp is not None:
            shapes = comp["arch"]["shapes"]
            sh = shapes[hsh % len(shapes)]
            if not is_tower and sh in ("point_cross", "wing_slab"):
                return "walkup_stair" if (hsh % 3 != 0) else "rect"
            return sh
        if is_tower:
            return ["stepped_slab", "wing_slab", "point_cross", "stepped_slab", "rect"][hsh % 5]
        if ctype == "walkup":
            return ["walkup_stair", "walkup_stair", "rect", "L_wing"][hsh % 4]
        return ["walkup_stair", "rect", "stepped_slab"][hsh % 3]

    def apply_google_earth_roof(b, poly, px, py, b_ang, hl, hw, is_tower):
        """Refine roof color & industrial/pitched roof type using real Google Earth z16 satellite pixels."""
        if not GE_SAMPLER.available:
            return b
        ge = GE_SAMPLER.sample_footprint(poly)
        if ge is None:
            return b
        rcls = ge["roof_class"]
        if rcls == "steel_blue" and not is_tower and b["h"] <= 20.0:
            # Real blue steel-roofed workshop / gym / warehouse visible on Google Earth
            b["kind"] = "industrial"
            b["style"] = 1
            b["h"] = min(float(b["h"]), 12.5)
            b["colour"] = "#c2c7cc"
            if poly_fits_rect_roof(poly, hl, hw):
                b["roof"] = pitched_roof_dict(px, py, b_ang, hl, hw, "gabled")
                b["roof"]["h"] = round(max(1.2, min(2.4, hw * 0.28)), 2)
                b["roof_colour"] = ge["roof_hex"]
            b.pop("yangfang", None)
            return b
        if "roof" in b and rcls in ("terracotta_red", "dark_slate", "warm_tan"):
            # Let real Google Earth roof color override generic default when not explicitly pinned by compound survey
            if not b.get("_roof_pinned"):
                b["roof_colour"] = ge["roof_hex"]
        elif (not is_tower) and b["h"] <= 24.0 and rcls == "terracotta_red" and "roof" not in b and poly_fits_rect_roof(poly, hl, hw):
            # Google Earth clearly shows a terracotta-red pitched roof here (平改坡!)
            b["roof"] = pitched_roof_dict(px, py, b_ang, hl, hw, "gabled")
            b["roof_colour"] = ge["roof_hex"]
        return b

    def profile_building(poly, px, py, row_hint, b_ang, hl, hw):
        ctype, tfl, yfl, sch, cid, comp, rc_default = zone_profile(px, py)
        # mixed compounds: towers on the north half of the cell (+y is south), 洋房 on the south half
        if comp is not None and ctype == "mixed":
            bx0, by0, bx1, by1 = comp["box"]
            frac_y = (py - by0) / max(1.0, by1 - by0)
            tower = frac_y < 0.52
        else:
            tower = ctype == "tower" or (ctype == "mixed" and (py / 220.0 - math.floor(py / 220.0)) < 0.5)
        roof_ok = poly_fits_rect_roof(poly, hl, hw)

        if ctype == "walkup":
            if comp is not None:
                f_lo, f_hi = comp["arch"]["floors"]
                fl = f_lo + ((cid + int(abs(px) * 0.1)) % max(1, f_hi - f_lo + 1))
                ak = comp["arch_key"]
                wall_c, trim_c = sch
                b = {
                    "pts": [rnd(p) for p in poly],
                    "h": round(fl * 3.0 + 1.0, 1),
                    "kind": "apartments",
                    "style": 3 if ak == "old_jiangnan" else 2,
                    "colour": wall_c,
                    "trim": trim_c,
                    "cpd": cid,
                    "arch": ak,
                    "name": comp["name"],
                }
                if roof_ok and (ak == "old_jiangnan" or (cid + int(abs(py) * 0.05)) % 4 != 3):
                    b["roof"] = pitched_roof_dict(px, py, b_ang, hl, hw + (0.28 if len(poly) == 12 else 0.0), comp["arch"]["roof_shape"] or "gabled")
                    b["roof_colour"] = rc_default
                    b["_roof_pinned"] = True
                return apply_google_earth_roof(b, poly, px, py, b_ang, hl, hw, False)
            fl = [5, 6, 6, 6, 7][cid % 5]
            b = {
                "pts": [rnd(p) for p in poly],
                "h": fl * 3.0 + 1.0,
                "kind": "apartments",
                "style": 2,
                "colour": PALETTE_RES[cid % len(PALETTE_RES)],
                "trim": "#554c44",
                "cpd": cid,
                "arch": "old_walkup_slate",
            }
            if roof_ok and cid % 3 != 2:  # 平改坡: most old compounds in Jiaxing have pitched roofs
                b["roof"] = pitched_roof_dict(px, py, b_ang, hl, hw + (0.28 if len(poly) == 12 else 0.0), "gabled")
                b["roof_colour"] = rc_default
            return apply_google_earth_roof(b, poly, px, py, b_ang, hl, hw, False)

        if tower:
            fl = max(11, tfl + rng.choice([0, 0, 0, -1, 1, -2, 2]))
            ak = comp["arch_key"] if comp is not None else "modern_warm_slab"
            b = {
                "pts": [rnd(p) for p in poly],
                "h": round(fl * 3.0 + 1.5, 1),
                "kind": "apartments",
                "style": 2,
                "colour": sch[0],
                "trim": sch[1],
                "cpd": cid,
                "arch": ak,
            }
            if comp is not None:
                b["name"] = comp["name"]
            return b

        # 洋房 (6-11F hipped-roof mid-rise)
        ak = comp["arch_key"] if comp is not None else "garden_yangfang"
        b = {
            "pts": [rnd(p) for p in poly],
            "h": round(yfl * 3.0 + 1.2, 1),
            "kind": "apartments",
            "style": 2,
            "colour": sch[0],
            "trim": sch[1],
            "cpd": cid,
            "arch": ak,
        }
        if roof_ok:
            b["yangfang"] = True
            b["roof"] = pitched_roof_dict(px, py, b_ang, hl, hw + (0.28 if len(poly) == 12 else 0.0), "hipped")
            b["roof_colour"] = rc_default if comp is not None else ["#3a3f46", "#46403b", "#333840"][cid % 3]
        if comp is not None:
            b["name"] = comp["name"]
            b["_roof_pinned"] = True
        return apply_google_earth_roof(b, poly, px, py, b_ang, hl, hw, False)

    # --- B. 100% REAL Satellite-Extracted Jiaxing Buildings (TUM GlobalBuildingAtlas LoD1, ZERO random infill!) ---
    # Every building footprint below is an actual real-world structure observed in satellite imagery of Jiaxing,
    # enriched with its real LoD1 height, real Google Maps compound identity & palette, and Google Earth roof color!
    def calibrate_real_height(gba_h, area_m2, comp, cx, cy):
        """Convert PlanetScope 3m LoD1 building height (which compresses mid/high-rise heights) into realistic
        Jiaxing building heights while strictly preserving real height differences between low podiums,
        walk-ups, 洋房, and high-rise towers."""
        if comp is not None:
            arch = comp["arch"]
            ak = comp["arch_key"]
            # Real 1-2F gatehouses, substations, or commercial podiums inside a compound stay low
            if gba_h < 4.6 or (area_m2 < 125.0 and gba_h < 6.0):
                return round(max(4.5, min(8.2, gba_h * 1.45)), 1), "podium"
            f_lo, f_hi = arch["floors"]
            if ak == "mixed_modern":
                # Separate real towers vs real 洋房 inside mixed compounds by their real satellite LoD1 height!
                if gba_h >= 12.2:
                    t = max(0.0, min(1.0, (gba_h - 12.2) / 14.0))
                    fl = round(f_lo + t * (f_hi - f_lo))
                    return round(fl * 3.0 + 1.5, 1), "tower"
                y_lo, y_hi = arch.get("y_floors", (6, 11))
                t = max(0.0, min(1.0, (gba_h - 5.5) / 6.7))
                fl = round(y_lo + t * (y_hi - y_lo))
                return round(fl * 3.0 + 1.2, 1), "yangfang"
            if ak in ("old_walkup_red", "old_walkup_slate", "old_jiangnan"):
                t = max(0.0, min(1.0, (gba_h - 5.0) / 8.5))
                fl = round(f_lo + t * (f_hi - f_lo))
                return round(fl * 3.0 + 1.0, 1), "walkup"
            if ak == "garden_yangfang":
                t = max(0.0, min(1.0, (gba_h - 6.0) / 9.5))
                fl = round(f_lo + t * (f_hi - f_lo))
                return round(fl * 3.0 + 1.2, 1), "yangfang"
            # Modern high-rise / Art-Deco tower compounds
            t = max(0.0, min(1.0, (gba_h - 6.5) / 17.0))
            fl = round(f_lo + t * (f_hi - f_lo))
            return round(fl * 3.0 + 1.5, 1), "tower"

        # Outside surveyed named compounds: calibrate directly from real GBA LoD1 height + footprint area
        if area_m2 >= 2800.0 and gba_h < 14.5:
            return round(max(7.5, min(16.0, gba_h * 1.15)), 1), "industrial"
        if gba_h < 4.5:
            return round(max(4.4, gba_h * 1.45), 1), "low"
        if gba_h < 11.5:
            return round(gba_h * 1.85, 1), "walkup"
        if gba_h < 22.0:
            return round(gba_h * 2.05, 1), "midrise"
        return round(min(115.0, gba_h * 2.25), 1), "tower"

    # Build quick landuse lookup for classifying non-compound industrial / commercial zones & rural farmland
    lu_ind_grid = Grid(160.0)
    lu_com_grid = Grid(160.0)
    for lu_k, lu_ring in landuse_zones:
        lxs = [p[0] for p in lu_ring]
        lys = [p[1] for p in lu_ring]
        if lu_k == "industrial":
            lu_ind_grid.add(lu_ring, min(lxs), min(lys), max(lxs), max(lys))
        elif lu_k in ("commercial", "retail", "governmental"):
            lu_com_grid.add(lu_ring, min(lxs), min(lys), max(lxs), max(lys))

    # Authentic sunlit 1980s-early-1990s "老破小" weathered concrete / faded-tile palettes & bright rural Jiangnan villa palettes
    LAOPOXIAO_PALETTES = [
        ("#e0dace", "#5c5852"),
        ("#e8dec6", "#665e52"),
        ("#d8ddd8", "#555a56"),
        ("#e8d0ba", "#6a5a4d"),
        ("#d5dbe2", "#525862"),
        ("#e5d7be", "#625a4e"),
    ]
    LAOPOXIAO_NAMED_KEYS = (
        "勤俭", "三水湾", "吉水", "新嘉", "春波", "禾兴", "瓶山", "府南", "建国",
        "东升", "百花", "文昌", "栅堰", "菜花泾", "杉青闸", "烟雨", "南杨", "紫阳",
        "翠柳", "桂苑", "梅湾", "纺工", "城南", "竹桥", "松鹤", "光明", "荷花堤",
    )
    RURAL_PALETTES = [
        ("#f6f2e8", "#e2dfd8"),
        ("#f8f4ec", "#e6e3dc"),
        ("#f2e8d2", "#dfd9ce"),
        ("#eef1ed", "#dce0dc"),
        ("#f5e9d0", "#e2dcd0"),
        ("#f0e1ce", "#ded7cc"),
    ]
    RURAL_ROOFS = ["#3a3f48", "#8a4232", "#395574", "#45423e"]

    real_sat_cnt = 0
    rural_sb_cnt = 0
    laopoxiao_cnt = 0
    for rb in gba_real_buildings:
        src = rb.get("s", "")
        # Skip stale OSM entries that already exist in our fresher jiaxing_osm.json (or were fixed to landuse=residential!)
        if src == "osm":
            k_id = str(rb.get("k", ""))[3:-3]
            if k_id.isdigit() and int(k_id) in ways:
                continue
        gba_h = float(rb.get("h", 0.0))
        raw_pts = rb.get("pts", [])
        if len(raw_pts) < 3:
            continue
        pts = simplify_ring([(float(p[0]), float(p[1])) for p in raw_pts], 0.65)
        if len(pts) < 3:
            pts = [(float(p[0]), float(p[1])) for p in raw_pts]
        area = abs(poly_area(pts))
        if area < 24.0:
            continue
        # Restore real low-rise rural village self-built houses (1.4m..2.8m GBA LoD1 heights, 36..280 m2)
        if gba_h < 2.8 and not (1.4 <= gba_h and 36.0 <= area <= 280.0):
            continue
        cx, cy = centroid(pts)
        if not in_active((cx, cy)):
            continue
        # Guard against rare erroneous mega-compound polygons (>25,000 m2 inside residential zones)
        comp = find_compound(cx, cy)
        if area > 25000.0 and (comp is not None or in_zhonghuan(cx, cy)):
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bb = (min(xs), min(ys), max(xs), max(ys))
        # Gently pull back any real street-front 沿街商铺 vertices that slightly touch a widened road carriageway
        # (up to 6.5m behind kerb) so we NEVER delete real 100-220m street-front commercial strips!
        near_rds = road_grid.query(bb[0] - 18, bb[1] - 18, bb[2] + 18, bb[3] + 18)
        if near_rds:
            nudged_pts = []
            moved = False
            for (px, py) in pts:
                nx_p, ny_p = px, py
                for (rax, ray, rbx, rby, rhw) in near_rds:
                    dd, tt = seg_dist(nx_p, ny_p, rax, ray, rbx, rby)
                    if dd < rhw + 0.65:
                        qx = rax + (rbx - rax) * tt
                        qy = ray + (rby - ray) * tt
                        vx, vy = nx_p - qx, ny_p - qy
                        vl = math.hypot(vx, vy)
                        if vl < 1e-4:
                            vx, vy = cx - qx, cy - qy
                            vl = math.hypot(vx, vy) or 1.0
                        push = min(10.5, (rhw + 0.95) - dd)
                        if push > 0.0:
                            nx_p += (vx / vl) * push
                            ny_p += (vy / vl) * push
                            moved = True
                nudged_pts.append((nx_p, ny_p))
            if moved and abs(poly_area(nudged_pts)) >= 24.0:
                pts = nudged_pts
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                bb = (min(xs), min(ys), max(xs), max(ys))
                cx, cy = centroid(pts)
        if not can_place(pts, bb, allow_in_park=False, water_margin=1.5, real_bldg=True):
            continue

        zt, _tfl, _yfl, sch, cid, comp_z, rc_default = zone_profile(cx, cy)
        cal_h, role = calibrate_real_height(gba_h, area, comp_z, cx, cy)
        in_ind = any(point_in_poly(cx, cy, lr) for lr in lu_ind_grid.query(cx - 5, cy - 5, cx + 5, cy + 5))
        in_com = any(point_in_poly(cx, cy, lr) for lr in lu_com_grid.query(cx - 5, cy - 5, cx + 5, cy + 5))
        o = obb(pts)
        b_ang = o[2] if o else 0.0
        hl = o[3] if o else math.sqrt(area) * 0.5
        hw = o[4] if o else math.sqrt(area) * 0.5
        fill_ratio = area / max(1e-6, 4.0 * hl * hw)
        roof_fit = (o is not None) and (fill_ratio >= 0.87) and (hw >= 2.6) and (hl <= 48.0)

        # Detect real Jiangnan Rural Self-Built Villa Houses (农村自建房: compact 2-3F footprints outside old-city core!)
        is_rural_house = (
            comp_z is None
            and not in_ind
            and not in_com
            and not in_zhonghuan(cx, cy)
            and 36.0 <= area <= 290.0
            and gba_h <= 7.8
            and hl <= 14.5
            and hw <= 10.5
        )

        # Sample Google Earth satellite hue so non-named buildings match real satellite colors!
        ge_hue = GE_SAMPLER.sample_wall_hue(pts) if (comp_z is None and GE_SAMPLER.available) else None
        if ge_hue is not None and ge_hue in GE_HUE_PALETTES:
            hue_list = GE_HUE_PALETTES[ge_hue]
            sch = hue_list[(cid + int(abs(cx) * 0.05)) % len(hue_list)]

        # Classify authentic architectural kind, style, wall/trim colors, and roof
        if is_rural_house:
            r_h = round(max(6.4, min(10.5, gba_h * 1.25 + 3.2)), 1)
            r_wall, r_trim = RURAL_PALETTES[(cid + int(abs(cx) * 0.13 + abs(cy) * 0.17)) % len(RURAL_PALETTES)]
            b = {
                "pts": [rnd(p) for p in pts],
                "h": r_h,
                "kind": "house",
                "style": 3,
                "colour": r_wall,
                "trim": r_trim,
                "arch": "rural_selfbuilt",
            }
            if roof_fit:
                rshape = "gabled" if ((int(abs(cx)) + int(abs(cy))) % 3 != 0) else "hipped"
                b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], rshape)
                b["roof_colour"] = RURAL_ROOFS[(cid + int(abs(cx) * 0.1)) % len(RURAL_ROOFS)]
            is_tw = False
            rural_sb_cnt += 1
        elif role == "industrial" or (in_ind and comp_z is None and cal_h <= 18.0):
            # Bright concrete/steel factory halls matching Google Earth (blue corrugated steel roofs / bright silver / brick!)
            ind_wall = "#e8ecf0" if ge_hue != "terracotta" else "#e2cab8"
            b = {
                "pts": [rnd(p) for p in pts],
                "h": min(cal_h, 15.0),
                "kind": "industrial",
                "style": 1,
                "colour": ind_wall,
                "trim": "#5a6470",
            }
            if roof_fit and ge_hue == "blue_roof":
                b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], "gabled")
                b["roof_colour"] = "#4f86cc"
            is_tw = False
        elif in_com and comp_z is None and (cal_h >= 24.0 or area >= 1100.0):
            b = {
                "pts": [rnd(p) for p in pts],
                "h": cal_h,
                "kind": "office" if cal_h >= 40.0 else "commercial",
                "style": 0 if cal_h >= 42.0 else 1,
                "colour": PALETTE_TOWER[cid % len(PALETTE_TOWER)] if cal_h >= 42.0 else (sch[0] if ge_hue else PALETTE_MODERN[cid % len(PALETTE_MODERN)]),
            }
            is_tw = cal_h >= 30.0
        elif role == "podium" or (role == "low" and area < 260.0 and cal_h <= 9.5):
            # Real 1-2F Jiangnan house / compound gatehouse / low street commercial shop
            is_jn = (comp_z is not None and comp_z["arch_key"] == "old_jiangnan") or (in_zhonghuan(cx, cy) and area < 220.0)
            b = {
                "pts": [rnd(p) for p in pts],
                "h": cal_h,
                "kind": "house" if is_jn else "commercial",
                "style": 3 if is_jn else 1,
                "colour": PALETTE_JIANGNAN[cid % len(PALETTE_JIANGNAN)] if is_jn else sch[0],
                "trim": sch[1],
            }
            if is_jn and roof_fit:
                b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], "gabled")
                b["roof_colour"] = "#2f343b"
            is_tw = False
        elif role == "tower" or cal_h >= 34.0:
            ak = comp_z["arch_key"] if comp_z is not None else "modern_warm_slab"
            b = {
                "pts": [rnd(p) for p in pts],
                "h": cal_h,
                "kind": "apartments",
                "style": 2,
                "colour": sch[0],
                "trim": sch[1],
                "cpd": cid,
                "arch": ak,
            }
            is_tw = True
        elif role == "yangfang" or (role == "midrise" and not in_zhonghuan(cx, cy)):
            ak = comp_z["arch_key"] if comp_z is not None else "garden_yangfang"
            b = {
                "pts": [rnd(p) for p in pts],
                "h": cal_h,
                "kind": "apartments",
                "style": 2,
                "colour": sch[0],
                "trim": sch[1],
                "cpd": cid,
                "arch": ak,
            }
            if roof_fit and cal_h <= 34.0:
                b["yangfang"] = True
                b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], "hipped")
                b["roof_colour"] = rc_default if comp_z is not None else ["#3a3f46", "#46403b", "#333840"][cid % 3]
                if comp_z is not None:
                    b["_roof_pinned"] = True
            is_tw = False
        else:
            # Real 3-7F Jiaxing walk-up / 1980s-90s "老破小" old-town residential building
            in_old_core = in_zhonghuan(cx, cy) or (-2600.0 <= cx <= 2600.0 and -3000.0 <= cy <= 2200.0)
            is_lpx_named = (comp_z is not None and any(k in comp_z["name"] for k in LAOPOXIAO_NAMED_KEYS) and comp_z["arch_key"] in ("old_walkup_red", "old_walkup_slate"))
            is_lpx = (
                11.0 <= cal_h <= 22.0
                and area <= 1250.0
                and (is_lpx_named or (comp_z is None and in_old_core and (cid % 5 in (0, 2, 4))))
            )
            if is_lpx:
                lw_c, lt_c = LAOPOXIAO_PALETTES[cid % len(LAOPOXIAO_PALETTES)]
                b = {
                    "pts": [rnd(p) for p in pts],
                    "h": cal_h,
                    "kind": "apartments",
                    "style": 2,
                    "colour": lw_c,
                    "trim": lt_c,
                    "cpd": cid,
                    "arch": "laopoxiao",
                }
                # ~65% 平改坡 weathered pitched roof, ~35% authentic 1980s flat concrete roof + solar heaters!
                if roof_fit and cal_h <= 21.5 and (cid % 3 != 2):
                    b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], "gabled")
                    b["roof_colour"] = "#45484c" if (cid % 2 == 0) else "#744438"
                laopoxiao_cnt += 1
            else:
                ak = comp_z["arch_key"] if comp_z is not None else ("old_walkup_red" if (cid % 3 == 0) else "old_walkup_slate")
                b = {
                    "pts": [rnd(p) for p in pts],
                    "h": cal_h,
                    "kind": "apartments",
                    "style": 3 if (ak == "old_jiangnan" and cal_h <= 11.0) else 2,
                    "colour": sch[0] if comp_z is not None else PALETTE_RES[cid % len(PALETTE_RES)],
                    "trim": sch[1] if comp_z is not None else "#554c44",
                    "cpd": cid,
                    "arch": ak,
                }
                if roof_fit and cal_h <= 25.0 and (comp_z is not None or cid % 4 != 3):
                    rshape = (comp_z["arch"]["roof_shape"] or "gabled") if comp_z is not None else "gabled"
                    b["roof"] = pitched_roof_dict(o[0], o[1], o[2], o[3], o[4], rshape)
                    b["roof_colour"] = rc_default
                    if comp_z is not None:
                        b["_roof_pinned"] = True
            is_tw = False

        if comp_z is not None:
            b["name"] = comp_z["name"]
        # Refine roof material/color directly from Google Earth z16 satellite pixels over this real footprint!
        if o is not None:
            b = apply_google_earth_roof(b, pts, o[0], o[1], o[2], o[3], o[4], is_tw)
        out.append(b)
        taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
        real_sat_cnt += 1

    # --- B2. Authentic Dense Continuous 1-2 Story Yuehe Historic Quarter (月河历史街区 专属水乡地标区) ---
    yuehe_cnt = 0
    yh_foot_segs = []
    for wid, (refs, t) in ways.items():
        if t.get("highway") in ("footway", "pedestrian", "path") and not t.get("bridge"):
            fpts = [nodes[r] for r in refs if r in nodes]
            for fa, fb in zip(fpts, fpts[1:]):
                mcx, mcy = (fa[0] + fb[0]) * 0.5, (fa[1] + fb[1]) * 0.5
                if -905.0 <= mcx <= -375.0 and -2275.0 <= mcy <= -1845.0:
                    yh_foot_segs.append((fa[0], fa[1], fb[0], fb[1]))
    YH_ALLEYS[:] = [[rnd((a0, a1)), rnd((b0, b1))] for (a0, a1, b0, b1) in yh_foot_segs]
    # Pass 1: Continuous wall-to-wall 1-2 story Jiangnan shop-houses directly lining every Yuehe pedestrian alley!
    for (ax, ay, bx, by) in yh_foot_segs:
        sl = math.hypot(bx - ax, by - ay)
        if sl < 6.0:
            continue
        ang = math.atan2(by - ay, bx - ax)
        ux, uy = (bx - ax) / sl, (by - ay) / sl
        nx, ny = -uy, ux
        s = 3.5
        while s < sl - 2.5:
            hl = rng.uniform(3.8, 5.8)
            for side in (-1.0, 1.0):
                hw = rng.uniform(3.0, 4.2)
                setb = 2.3 + hw
                cx = ax + ux * s + nx * side * setb
                cy = ay + uy * s + ny * side * setb
                poly = make_rect_poly(cx, cy, ang, hl, hw)
                pxs = [p[0] for p in poly]
                pys = [p[1] for p in poly]
                bb = (min(pxs), min(pys), max(pxs), max(pys))
                if can_place(poly, bb, allow_in_park=False, water_margin=1.4, tight=True, allow_yuehe=True):
                    h = rng.choice([4.4, 5.2, 6.0, 6.6, 7.2])
                    shop = rng.choice(YH_SIGNS) if rng.random() < 0.55 else ""
                    YH_HOUSES.append({"c": rnd((cx, cy)), "a": round(ang, 4), "l": round(hl, 2), "w": round(hw, 2), "h": h,
                                      "f": [round(-nx * side, 3), round(-ny * side, 3)], "s": shop, "g": 1 if rng.random() < 0.45 else 0})
                    taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                    yuehe_cnt += 1
            s += hl * 1.92
    # Pass 2: Dense continuous multi-row Jiangnan courtyard houses packing every dry Yuehe peninsula & canal bank!
    yh_y = -2256.0
    row_i = 0
    while yh_y <= -1856.0:
        yh_x = -892.0 + (3.5 if (row_i % 2 == 1) else 0.0)
        while yh_x <= -388.0:
            near_alley = any(seg_dist(yh_x, yh_y, fa, fb, fc, fd)[0] < 4.5 for (fa, fb, fc, fd) in yh_foot_segs)
            if not near_alley:
                hl = rng.uniform(4.2, 6.0)
                hw = rng.uniform(3.1, 4.1)
                ang = rng.choice([0.12, 0.14, 0.16]) if (row_i % 4 != 3) else (math.pi * 0.5 + 0.14)
                poly = make_rect_poly(yh_x, yh_y, ang, hl, hw)
                pxs = [p[0] for p in poly]
                pys = [p[1] for p in poly]
                bb = (min(pxs), min(pys), max(pxs), max(pys))
                if can_place(poly, bb, allow_in_park=False, water_margin=1.5, tight=True, allow_yuehe=True):
                    h = rng.choice([4.2, 5.0, 5.8, 6.4, 7.0])
                    fx, fy = -math.sin(ang), math.cos(ang)
                    if fy < 0.0:
                        fx, fy = -fx, -fy
                    YH_HOUSES.append({"c": rnd((yh_x, yh_y)), "a": round(ang, 4), "l": round(hl, 2), "w": round(hw, 2), "h": h,
                                      "f": [round(fx, 3), round(fy, 3)], "s": "", "g": 1 if rng.random() < 0.5 else 0})
                    taken.add((bb[0], bb[1], bb[2], bb[3], poly), *bb)
                    yuehe_cnt += 1
            yh_x += 9.8
        yh_y += 9.0
        row_i += 1

    # --- B3. Auto-cluster Unnamed Visible Real Residential Compounds (地图上可见的无名真实小区) ---
    # Group nearby real unnamed residential buildings into cohesive real compounds with unified developer
    # facade palettes, trim & roof colors, and pass their convex hulls to build_gated_compounds()!
    UNNAMED_COMPOUND_HULLS.clear()
    unnamed_idxs = [
        i for i, b in enumerate(out)
        if b.get("kind") == "apartments" and not b.get("name") and b.get("arch") != "rural_selfbuilt" and not b.get("lm")
    ]
    if unnamed_idxs:
        u_cen = {i: centroid(out[i]["pts"]) for i in unnamed_idxs}
        u_grid = Grid(68.0)
        for i in unnamed_idxs:
            cx_u, cy_u = u_cen[i]
            u_grid.add(i, cx_u - 4, cy_u - 4, cx_u + 4, cy_u + 4)
        parent_uf = {i: i for i in unnamed_idxs}
        def uf_find(x):
            while parent_uf[x] != x:
                parent_uf[x] = parent_uf[parent_uf[x]]
                x = parent_uf[x]
            return x
        def uf_union(a, b_id):
            ra, rb = uf_find(a), uf_find(b_id)
            if ra != rb:
                parent_uf[ra] = rb
        for i in unnamed_idxs:
            cx_i, cy_i = u_cen[i]
            hi = float(out[i]["h"])
            for j in u_grid.query(cx_i - 62, cy_i - 62, cx_i + 62, cy_i + 62):
                if j <= i:
                    continue
                cx_j, cy_j = u_cen[j]
                if math.hypot(cx_i - cx_j, cy_i - cy_j) > 60.0:
                    continue
                if abs(hi - float(out[j]["h"])) > 20.0:
                    continue
                # Do not merge compounds across a wide arterial road!
                crossed_arterial = False
                for (rax, ray, rbx, rby, rhw) in road_grid.query(min(cx_i, cx_j) - 6, min(cy_i, cy_j) - 6, max(cx_i, cx_j) + 6, max(cy_i, cy_j) + 6):
                    if rhw >= 7.5 and seg_intersection((cx_i, cy_i), (cx_j, cy_j), (rax, ray), (rbx, rby)) is not None:
                        crossed_arterial = True
                        break
                if not crossed_arterial:
                    uf_union(i, j)
        clusters = defaultdict(list)
        for i in unnamed_idxs:
            clusters[uf_find(i)].append(i)
        # Pre-index named road midpoints so unnamed compounds get real street-anchored names (e.g. 昌盛南路·住宅小区)
        named_roads = []
        for e in edges:
            rnm = e.get("name", "")
            if rnm and not any(sk in rnm for sk in ("支路", "隧道", "坡道", "引道", "辅道", "辅路")) and e.get("pts"):
                mid_p = e["pts"][len(e["pts"]) // 2]
                named_roads.append((mid_p[0], mid_p[1], rnm))
        DEV_PALETTES_MODERN = [
            ("#f7f7f5", "#4a525e"), ("#f5dfb4", "#785e42"), ("#d2e5f5", "#3d4e62"),
            ("#f0be8e", "#7a523c"), ("#f6eed8", "#665848"), ("#c8e2dc", "#3e5852"),
            ("#e8a882", "#744a36"), ("#f4d498", "#7a5c3e"), ("#e0ebf6", "#425264"),
            ("#f2e4c4", "#6e5a44"),
        ]
        DEV_PALETTES_WALKUP = [
            ("#f5dfb6", "#7a5e44"), ("#f4efe4", "#5c5954"), ("#efbc8c", "#7c523c"),
            ("#d4e6da", "#4c5f54"), ("#f6ecd4", "#6a5a48"), ("#e5a47e", "#744834"),
            ("#d6e6f4", "#445466"), ("#f2d69c", "#765a40"),
        ]
        uc_idx = 0
        for _root, idxs in clusters.items():
            if len(idxs) < 3:
                continue
            hs = sorted(float(out[i]["h"]) for i in idxs)
            med_h = hs[len(hs) // 2]
            all_pts = [p for i in idxs for p in out[i]["pts"]]
            ux0 = min(p[0] for p in all_pts) - 5.0
            uy0 = min(p[1] for p in all_pts) - 5.0
            ux1 = max(p[0] for p in all_pts) + 5.0
            uy1 = max(p[1] for p in all_pts) + 5.0
            if (ux1 - ux0) > 340.0 or (uy1 - uy0) > 340.0:
                continue
            ccx, ccy = (ux0 + ux1) * 0.5, (uy0 + uy1) * 0.5
            is_lpx_cl = (med_h <= 21.5 and in_zhonghuan(ccx, ccy) and (uc_idx % 2 == 0))
            cl_hue = GE_SAMPLER.sample_wall_hue([(ux0, uy0), (ux1, uy0), (ux1, uy1), (ux0, uy1)]) if GE_SAMPLER.available else None
            if is_lpx_cl:
                w_c, t_c = LAOPOXIAO_PALETTES[uc_idx % len(LAOPOXIAO_PALETTES)]
                cl_arch = "laopoxiao"
            elif cl_hue is not None and cl_hue in GE_HUE_PALETTES and (uc_idx % 2 == 0):
                hp = GE_HUE_PALETTES[cl_hue]
                w_c, t_c = hp[uc_idx % len(hp)]
                cl_arch = "modern_warm_slab" if med_h >= 24.0 else "old_walkup_slate"
            elif med_h >= 24.0:
                w_c, t_c = DEV_PALETTES_MODERN[uc_idx % len(DEV_PALETTES_MODERN)]
                cl_arch = "modern_warm_slab"
            else:
                w_c, t_c = DEV_PALETTES_WALKUP[uc_idx % len(DEV_PALETTES_WALKUP)]
                cl_arch = "old_walkup_slate"
            # Apply unified developer palette across the entire unnamed compound!
            for i in idxs:
                out[i]["cpd"] = 7000 + uc_idx
                out[i]["colour"] = w_c
                out[i]["trim"] = t_c
                if is_lpx_cl and float(out[i]["h"]) <= 22.0:
                    out[i]["arch"] = "laopoxiao"
            # Find nearest real street name for authentic local compound signage
            best_rd = ""
            best_dd = 1e9
            for rx, ry, rnm in named_roads:
                dd = (rx - ccx) * (rx - ccx) + (ry - ccy) * (ry - ccy)
                if dd < best_dd:
                    best_dd = dd
                    best_rd = rnm
            sfx = ("新村", "小区", "雅苑", "嘉苑", "花苑", "名苑")[uc_idx % 6]
            cl_nm = f"{best_rd}·{sfx}" if (best_rd and best_dd < 420.0 * 420.0) else ""
            # Build clean convex hull padded slightly outward for compound fence & lawn
            hull_pts = [(ux0, uy0), (ux1, uy0), (ux1, uy1), (ux0, uy1)]
            UNNAMED_COMPOUND_HULLS.append((hull_pts, cl_nm))
            uc_idx += 1

    print(f"Buildings: {len(out)} total ({osm_cnt} real OSM + {real_sat_cnt} real satellite LoD1; "
          f"{rural_sb_cnt} 农村自建房, {laopoxiao_cnt} 老破小, {len(UNNAMED_COMPOUND_HULLS)} 无名真实小区; +{yuehe_cnt} Yuehe heritage houses)")
    return out


# ---------------------------------------------------------------------------------------------
# 5. Roads, Crosswalks, Streetlamps, Avenue Trees, Storefronts
# ---------------------------------------------------------------------------------------------
# Hanyu Pinyin of every character used in Jiaxing street names (road name plates carry it under the hanzi)
PINYIN = dict(zip(
    "一万丈三下业东中丰乐九云仁会俭元光公兴军农凌凯出创前力务勤北区升华南博历原友双吉同周和商嘉园国園地场坡城塔塘墅声大安宜宝宾小少展山川州工带常平年广庆府建引御德心快怡拥拳振支放文斜新方旋昌明春景曲望机杨松林柳树格桐桥梧楼横橋正殷民气水永汇江沭河波泾洪洲浜海清渡港湖湾溪火烟玉环甪由百益盐盛禾秀租站章紫红纵纺络绣羊翔翠联舟航船花茶莲蚕街西谊象贸越路车辅迎速道里锦长门阳隧雨顺高鸣鹤龙",
    ("yi wan zhang san xia ye dong zhong feng le jiu yun ren hui jian yuan guang gong xing jun nong ling kai chu chuang "
     "qian li wu qin bei qu sheng hua nan bo li yuan you shuang ji tong zhou he shang jia yuan guo yuan di chang po cheng "
     "ta tang shu sheng da an yi bao bin xiao shao zhan shan chuan zhou gong dai chang ping nian guang qing fu jian yin yu "
     "de xin kuai yi yong quan zhen zhi fang wen xie xin fang xuan chang ming chun jing qu wang ji yang song lin liu shu "
     "ge tong qiao wu lou heng qiao zheng yin min qi shui yong hui jiang shu he bo jing hong zhou bang hai qing du gang hu "
     "wan xi huo yan yu huan lu you bai yi yan sheng he xiu zu zhan zhang zi hong zong fang luo xiu yang xiang cui lian "
     "zhou hang chuan hua cha lian can jie xi yi xiang mao yue lu che fu ying su dao li jin chang men yang sui yu shun gao "
     "ming he long").split()))
SIGN_SKIP = ("支路", "隧道", "坡道", "引道", "出租车", "辅道", "辅路")


def road_pinyin(name):
    """'中山西路' -> 'ZHONGSHAN XILU', '南湖大道' -> 'NANHU DADAO' (GB 17733 style street-plate romanisation)."""
    gen_len = 1
    if name.endswith("大道"):
        gen_len = 2
    elif len(name) >= 3 and name[-1] in "路街" and name[-2] in "东西南北":
        gen_len = 2
    proper, generic = name[:-gen_len], name[-gen_len:]
    py = lambda t: "".join(PINYIN.get(ch, "") for ch in t)
    return (py(proper) + " " + py(generic)).upper().strip()


def build_road_signs(edges, nodes_list):
    """Chinese street signage: 路名牌 (blue street-name plates with pinyin) at junction corners, and 指路标志
    (blue overhead lane-guidance signs naming the roads left / ahead / right) on main-road approaches."""
    npos = {n["id"]: n["pos"] for n in nodes_list}
    deg = defaultdict(int)
    for e in edges:
        deg[e["a"]] += 1
        deg[e["b"]] += 1

    def along(pts, dist):
        acc = 0.0
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            L = math.hypot(bx - ax, by - ay)
            if acc + L >= dist and L > 1e-6:
                t = (dist - acc) / L
                return (ax + (bx - ax) * t, ay + (by - ay) * t), ((bx - ax) / L, (by - ay) / L)
            acc += L
        ax, ay = pts[-2]
        bx, by = pts[-1]
        L = max(1e-6, math.hypot(bx - ax, by - ay))
        return (bx, by), ((bx - ax) / L, (by - ay) / L)

    def plen(pts):
        return sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))

    # leaving directions of every edge at each junction (sampled 15 m out so short kinks do not mislead)
    legs = defaultdict(list)  # node -> [(edge, out_dir, pts_from_node)]
    for e in edges:
        if e.get("underground") or e.get("hide_road"):
            continue
        pts = e["pts"]
        if len(pts) < 2:
            continue
        L = plen(pts)
        if L < 4.0:
            continue
        rev = list(reversed(pts))
        for node, seq in ((e["a"], pts), (e["b"], rev)):
            p, _ = along(seq, min(15.0, L * 0.5))
            o = seq[0]
            dx, dy = p[0] - o[0], p[1] - o[1]
            d = math.hypot(dx, dy)
            if d > 1e-6:
                legs[node].append((e, (dx / d, dy / d), seq, L))

    def nice(nm):
        return nm and not any(k in nm for k in SIGN_SKIP)

    # every sign post must stand off the asphalt of EVERY road, not just its own (twin carriageways, a wide cross
    # street at a short leg and a sharp bend all used to drop plates in the traffic lanes)
    CELL = 40.0
    surf = defaultdict(list)
    for e in edges:
        if e.get("underground") or e.get("hide_road"):
            continue
        pts = e["pts"]
        hw = float(e["width"]) * 0.5
        for k in range(len(pts) - 1):
            ax, ay = pts[k]
            bx, by = pts[k + 1]
            seg = (ax, ay, bx, by, hw)
            for gx in range(int(math.floor((min(ax, bx) - hw) / CELL)), int(math.floor((max(ax, bx) + hw) / CELL)) + 1):
                for gy in range(int(math.floor((min(ay, by) - hw) / CELL)), int(math.floor((max(ay, by) + hw) / CELL)) + 1):
                    surf[(gx, gy)].append(seg)

    def clear_of_roads(px, py, pad):
        for (ax, ay, bx, by, hw) in surf.get((int(math.floor(px / CELL)), int(math.floor(py / CELL))), ()):
            if seg_dist(px, py, ax, ay, bx, by)[0] < hw + pad:
                return False
        return True

    signs = []
    plate_seen = set()
    for node, lg in legs.items():
        if deg[node] < 3 or node not in npos:
            continue
        nx0, ny0 = npos[node]
        if not in_active((nx0, ny0)):
            continue
        for (e, od, seq, L) in lg:
            w = e["width"]
            nm = e["name"]
            # --- street-name plate on the corner, parallel to its road, one per road per junction ---
            if nice(nm) and (node, nm) not in plate_seen and L >= 20.0:
                plate_seen.add((node, nm))
                side0 = 1.0 if (node % 2 == 0) else -1.0
                spot = None
                # stand past the crossing street's kerb and its crosswalk (7.8 m out, kerb ramps cut back there),
                # on the pavement proper, not in the junction mouth
                cross_hw = max([float(e2["width"]) * 0.5 for (e2, *_r) in lg if e2 is not e] or [4.0])
                d0 = max(11.0, cross_hw + 7.5)
                for dist_p in (d0, d0 + 5.0, d0 + 11.0, d0 + 18.0, d0 + 26.0):
                    if dist_p > L - 4.0:
                        break
                    p, d = along(seq, dist_p)
                    rx, ry = -d[1], d[0]
                    for side in (side0, -side0):
                        for off in (1.8, 2.8):
                            qx = p[0] + rx * side * (w * 0.5 + off)
                            qy = p[1] + ry * side * (w * 0.5 + off)
                            if clear_of_roads(qx, qy, 0.7):
                                spot = (qx, qy, d)
                                break
                        if spot:
                            break
                    if spot:
                        break
                if spot:
                    signs.append({"k": "name", "p": [round(spot[0], 2), round(spot[1], 2)],
                                  "d": [round(spot[2][0], 4), round(spot[2][1], 4)], "t": nm, "py": road_pinyin(nm)})
            # --- overhead guide sign on a main-road approach (traffic drives toward this node) ---
            if w < 15.0 or L < 110.0 or not nice(nm):
                continue
            din = (-od[0], -od[1])  # travel direction arriving at the junction
            names = {"L": "", "S": "", "R": ""}
            best = {"L": 1e9, "S": 1e9, "R": 1e9}
            for (e2, od2, _seq2, _L2) in lg:
                if e2 is e:
                    continue
                cr = din[0] * od2[1] - din[1] * od2[0]
                dt = din[0] * od2[0] + din[1] * od2[1]
                ang = math.degrees(math.atan2(cr, dt))
                if abs(ang) > 150.0:
                    continue
                key = "S" if abs(ang) < 35.0 else ("R" if ang > 0 else "L")
                score = abs(ang) if key == "S" else abs(abs(ang) - 90.0)
                if nice(e2["name"]) and score < best[key]:
                    best[key] = score
                    names[key] = e2["name"]
            if not names["S"] and any(nice(e2["name"]) and e2["name"] == nm for (e2, *_r) in lg if e2 is not e):
                names["S"] = nm
            if sum(1 for v in names.values() if v) < 2:
                continue
            dist0 = min(75.0, L * 0.45)
            spot = None
            for dist in (dist0, dist0 - 15.0, dist0 + 15.0, dist0 - 28.0):
                if dist < 30.0 or dist > L - 20.0:
                    continue
                p, d = along(seq, dist)
                # traffic on this side drives toward the node, i.e. along -d; its right-hand kerb is right of -d
                tdx, tdy = -d[0], -d[1]
                rx, ry = -tdy, tdx
                for off in (0.9, 2.0):
                    qx, qy = p[0] + rx * (w * 0.5 + off), p[1] + ry * (w * 0.5 + off)
                    if clear_of_roads(qx, qy, 0.5):
                        spot = (qx, qy, tdx, tdy)
                        break
                if spot:
                    break
            if spot is None:
                continue
            signs.append({"k": "guide", "p": [round(spot[0], 2), round(spot[1], 2)],
                          "d": [round(spot[2], 4), round(spot[3], 4)], "w": round(w, 1), "tram": bool(e.get("tram_median")),
                          "L": names["L"], "S": names["S"], "R": names["R"]})
    return signs


def build_street_furniture(edges, nodes_list, blds, poi_nodes, osm_nodes, road_grid, water_grid, rail_grid, bld_grid, freeway_grid=None, island_rings=None):
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
        if ed.get("bike_buffer"):
            r["bike_buffer"] = ed["bike_buffer"]
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
        if L >= 22.0:
            dx, dz = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
            nx, nz = -dz, dx
            if deg[ed["a"]] >= 3:
                cws.append({"pos": [round(p0[0] + dx * 7.8, 2), round(p0[1] + dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})
            if deg[ed["b"]] >= 3:
                cws.append({"pos": [round(p1[0] - dx * 7.8, 2), round(p1[1] - dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})

            # Streetlamps every 48m
            s = 16.0
            while s < L - 12.0:
                for side in (-1.0, 1.0):
                    lamps.append([round(p0[0] + dx * s + nx * side * (w * 0.5 + 1.4), 2),
                                  round(p0[1] + dz * s + nz * side * (w * 0.5 + 1.4), 2),
                                  round(-nx * side, 3), round(-nz * side, 3)])
                s += 48.0

        # Satellite-guided dense Jiangnan street trees (行道树: 香樟/法桐/银杏) along EVERY polyline segment!
        # Samples Google Earth z16 canopy along BOTH sidewalks AND computes true widened carriageway half-width
        # from road_grid so T1 boulevards (纺工路/庆丰路/由拳路/中山东路) get lush outer-sidewalk trees too!
        if not ed.get("bridge"):
            is_major_rd = (w >= 11.0 or bool(ed.get("tram_median")) or bool(ed.get("name")))
            for pa, pb in zip(pts, pts[1:]):
                sl = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
                if sl < 8.0:
                    continue
                sdx, sdz = (pb[0] - pa[0]) / sl, (pb[1] - pa[1]) / sl
                snx, snz = -sdz, sdx
                mid_x, mid_y = (pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5
                # Determine true widened half-width at this segment (handles T1 40m avenues & widened trunks!)
                eff_hw = w * 0.5
                for (rax, ray, rbx, rby, rhw) in road_grid.query(mid_x - 24, mid_y - 24, mid_x + 24, mid_y + 24):
                    if seg_dist(mid_x, mid_y, rax, ray, rbx, rby)[0] < 4.5:
                        eff_hw = max(eff_hw, rhw)
                for side in (-1.0, 1.0):
                    has_sat_trees = GE_SAMPLER.has_roadside_trees(pa[0], pa[1], pb[0], pb[1], eff_hw, side)
                    if not (has_sat_trees or is_major_rd):
                        continue
                    step_t = 11.5 if (has_sat_trees or eff_hw >= 7.0) else 15.0
                    # Start cleanly past intersection corners
                    st = 6.5 if sl >= 16.0 else sl * 0.5
                    end_s = sl - 5.5 if sl >= 16.0 else sl * 0.5 + 0.1
                    while st < end_s:
                        tx = pa[0] + sdx * st + snx * side * (eff_hw + 2.35)
                        ty = pa[1] + sdz * st + snz * side * (eff_hw + 2.35)
                        trees.append((tx, ty))
                        st += step_t

    # Add real OSM trees + lush scenic groves in Nanhu Scenic Area & Xiangjiadang Wetland Park!
    for nid, t in poi_nodes.items():
        if t.get("natural") == "tree" and nid in osm_nodes:
            p = osm_nodes[nid]
            if in_active(p):
                trees.append(p)
    rng_tr = random.Random(20260529)
    # Lush dense park & scenic woodland groves across Nanhu Scenic Area (Lanxiu Garden, Haogu Peninsula, South/East shores)
    for gx in range(-480, 960, 12):
        for gy in range(-520, 660, 12):
            tx = gx + rng_tr.uniform(-4.5, 4.5)
            ty = gy + rng_tr.uniform(-4.5, 4.5)
            if math.hypot(tx - HAOGU_PAGODA_POS[0], ty - HAOGU_PAGODA_POS[1]) < 34.0:
                continue
            if math.hypot(tx - NANHU_GATE_POS[0], ty - NANHU_GATE_POS[1]) < 42.0:
                continue
            if math.hypot(tx - HUIJINGYUAN_POS[0], ty - HUIJINGYUAN_POS[1]) < 46.0:
                continue
            if math.hypot(tx - NANHU_TIANDI_POS[0], ty - NANHU_TIANDI_POS[1]) < 142.0:
                continue
            if rng_tr.random() < 0.78:
                trees.append((tx, ty))
    # Xiangjiadang Wetland Park lush dry-shore woodland & lakeside willow groves (denser canopy!)
    xr = XIANGJIADANG_RECT
    for gx in range(int(xr[0]) + 40, int(xr[2]) - 40, 18):
        for gy in range(int(xr[1]) + 40, int(xr[3]) - 40, 18):
            tx = gx + rng_tr.uniform(-6.5, 6.5)
            ty = gy + rng_tr.uniform(-6.5, 6.5)
            if math.hypot(tx - XIANGJIADANG_PARK_POS[0], ty - XIANGJIADANG_PARK_POS[1]) < 78.0:
                continue
            if rng_tr.random() < 0.76:
                trees.append((tx, ty))

    # Populate lush scenic trees directly on lake islands (especially North Lake Island #353 around 399,-634!)
    if island_rings:
        for ir in island_rings:
            ic = centroid(ir)
            if math.hypot(ic[0] - YANYU_POS[0], ic[1] - YANYU_POS[1]) < 95.0:
                continue  # Yanyu Tower Lake Heart Island has its own bespoke landscaping
            ixs = [p[0] for p in ir]
            iys = [p[1] for p in ir]
            ix0, ix1, iy0, iy1 = int(min(ixs)) + 3, int(max(ixs)) - 3, int(min(iys)) + 3, int(max(iys)) - 3
            for gx in range(ix0, ix1 + 1, 9):
                for gy in range(iy0, iy1 + 1, 9):
                    tx = gx + rng_tr.uniform(-3.0, 3.0)
                    ty = gy + rng_tr.uniform(-3.0, 3.0)
                    # Keep island pavilions clear
                    if math.hypot(tx - 386.0, ty + 672.0) < 8.5 or math.hypot(tx - 414.0, ty + 592.0) < 8.5:
                        continue
                    if point_in_poly(tx, ty, ir) and rng_tr.random() < 0.85:
                        trees.append((tx, ty))

    # Deduplicate lamps, crosswalks, and clearance-check trees (a lamp set out from one street must not stand on
    # the asphalt of another: a wide crossing street, a widened boulevard beside a side road)
    def lamp_clear(lp):
        for (ax, ay, bx, by, hw) in road_grid.query(lp[0] - 30, lp[1] - 30, lp[0] + 30, lp[1] + 30):
            if seg_dist(lp[0], lp[1], ax, ay, bx, by)[0] < hw + 0.6:
                return False
        return True
    lamps = [lp for lp in lamps if lamp_clear(lp)]
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
        c = (int(tx // 6.5), int(ty // 6.5))
        if c in seen_t or not in_active((tx, ty)):
            continue
        ok = True
        for (ax, ay, bx, by, hw) in road_grid.query(tx - 15, ty - 15, tx + 15, ty + 15):
            if seg_dist(tx, ty, ax, ay, bx, by)[0] < hw + 1.2:
                ok = False
                break
        if ok:
            # Lake islands are dry land; everywhere else require a 2.2m dry shoreline buffer from water!
            on_island = False
            if island_rings:
                for ir in island_rings:
                    if point_in_poly(tx, ty, ir):
                        # Must be at least 2.6m inside island edge so canopy never overhangs water
                        if all(seg_dist(tx, ty, ir[k][0], ir[k][1], ir[(k + 1) % len(ir)][0], ir[(k + 1) % len(ir)][1])[0] >= 2.6 for k in range(len(ir))):
                            on_island = True
                            break
            if not on_island:
                for wp in water_grid.query(tx - 3.5, ty - 3.5, tx + 3.5, ty + 3.5):
                    if point_in_poly(tx, ty, wp):
                        ok = False
                        break
                    for k in range(len(wp)):
                        if seg_dist(tx, ty, wp[k][0], wp[k][1], wp[(k + 1) % len(wp)][0], wp[(k + 1) % len(wp)][1])[0] < 2.2:
                            ok = False
                            break
                    if not ok:
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
            # Keep MAD Jiaxing Station South Plaza bespoke circular pavilions clear of stray street trees
            if 655.0 <= tx <= 944.0 and -1392.0 <= ty <= -1046.0 and ty > (-tx - 485.0):
                ok = False
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
        ("库迪咖啡", "cafe"), ("茶百道", "cafe"), ("书亦烧仙草", "cafe"),
        ("美宜佳", "convenience"), ("赵一鸣零食", "convenience"), ("好特卖", "supermarket"),
        ("百果园", "greengrocer"), ("鲜丰水果", "greengrocer"), ("钱大妈", "greengrocer"),
        ("来伊份", "convenience"), ("周黑鸭", "fast_food"), ("巴比馒头", "fast_food"),
        ("张亮麻辣烫", "fast_food"), ("袁记云饺", "restaurant"), ("老盛昌", "restaurant"),
        ("好利来", "bakery"), ("必胜客", "restaurant"), ("德克士", "fast_food"),
        ("一心堂药房", "pharmacy"), ("博士眼镜", "optician"), ("中通快递", "service"),
        ("圆通快递", "service"), ("雅迪电动车", "hardware"), ("爱玛电动车", "hardware"),
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
        ("嘉兴烧卖老店", "fast_food"), ("南湖卤味熟食", "fast_food"), ("桐乡煲仔饭", "restaurant"),
        ("衢州鸭头夜宵", "restaurant"), ("小龙虾烧烤城", "restaurant"), ("手工烘焙蛋糕房", "bakery"),
        ("鲜花绿植花艺", "florist"), ("图文广告快印", "office"), ("汽车美容洗车行", "hardware"),
        ("盲人推拿正骨", "beauty"), ("美甲美睫工作室", "beauty"), ("棋牌品茗茶室", "cafe"),
        ("萌宠动物医院", "service"), ("建材卫浴定制", "hardware"), ("家电空调维修", "hardware"),
        ("名烟名酒茶行", "convenience"), ("母婴童装生活馆", "clothes"), ("品牌尾货折扣店", "clothes"),
        ("体育用品专卖", "retail"), ("社区便民菜站", "greengrocer"), ("老城裁缝改衣", "dry_cleaning"),
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

    # Pass 2: High-density flush wall-to-wall continuous street-front retail rows (沿街商铺 / 连排底商) across ALL Jiaxing streets!
    # Collect up to 4 street-facing facades per building (handles corner & L-shaped 沿街商铺 strips!) sorted closest & widest avenues first!
    b_candidates = []
    for bi, b in enumerate(blds):
        if b["h"] < 3.6 or len(b["pts"]) < 3:
            continue
        if b.get("kind") == "industrial" or b.get("arch") == "rural_selfbuilt":
            continue
        poly = b["pts"]
        ccw = poly_area(poly) > 0.0
        face_hits = []
        for ei in range(len(poly)):
            if (bi, ei) in used_b_edges:
                continue
            a, c = poly[ei], poly[(ei + 1) % len(poly)]
            el = math.hypot(c[0] - a[0], c[1] - a[1])
            if el < 4.4:
                continue
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            best_d = 1e9
            best_hw = 4.0
            for (rax, ray, rbx, rby, hw) in road_grid.query(mx - 44, my - 44, mx + 44, my + 44):
                dd = seg_dist(mx, my, rax, ray, rbx, rby)[0] - hw
                if dd < best_d:
                    best_d = dd
                    best_hw = hw
            if best_d <= 29.0:
                face_hits.append((best_d, best_hw, ei, a, c, el, ccw))
        face_hits.sort(key=lambda it: it[0])
        # Keep EVERY street-facing edge (not capped at 4!) so long multi-segment / L-shaped 沿街商铺 strips
        # receive continuous wall-to-wall storefronts along BOTH intersecting avenues!
        for fh in face_hits:
            b_candidates.append((fh[0] - fh[1] * 0.70, bi, fh))
    b_candidates.sort(key=lambda it: it[0])

    for _prio, bi, (best_d, best_hw, ei, a, c, el, ccw) in b_candidates:
        if len(storefronts) >= 96000:
            break
        if (bi, ei) in used_b_edges:
            continue
        cen = centroid(blds[bi]["pts"])
        dist_center = math.hypot(cen[0] - OLD_CITY_CENTER[0], cen[1] - OLD_CITY_CENTER[1])
        dist_nanhu = math.hypot(cen[0] - NANHU_ORIGIN[0], cen[1] - NANHU_ORIGIN[1])
        dist_hsr = math.hypot(cen[0] - SOUTH_STA_POS[0], cen[1] - SOUTH_STA_POS[1])
        dist_yuehe = math.hypot(cen[0] - YUEHE_POS[0], cen[1] - YUEHE_POS[1])
        in_core_comm = min(dist_center, dist_nanhu) < 3500.0 or dist_hsr < 1600.0 or best_hw >= 4.8
        bk = blds[bi]
        kind_b = bk.get("kind", "yes")
        if kind_b in ("school", "university", "college", "hospital", "civic", "public", "office",
                      "government", "church", "train_station", "warehouse"):
            continue
        if bk.get("yangfang") and float(bk["h"]) > 13.5:
            continue
        # Recognize authentic Chinese 沿街商铺 strips:
        #   - 1-3F standalone street-hugging commercial strips (h <= 13.5m)
        #   - commercial/retail/mall frontages
        #   - long street-parallel podium/arcade strips (el >= 14m facing an avenue/secondary road)
        is_strip_shop = (
            kind_b in ("commercial", "retail", "mall")
            or (float(bk["h"]) <= 14.5 and best_d <= 30.0 and best_hw >= 3.8)
            or (el >= 12.0 and best_d <= 29.0 and best_hw >= 4.5)
        )
        max_setback = 30.0 if is_strip_shop else 26.0
        if best_d > max_setback:
            continue
        if is_strip_shop:
            prob = 1.0
        elif kind_b in ("apartments", "residential") and bk["h"] >= 26.0:
            prob = 0.96 if best_hw >= 5.2 else 0.72
        elif kind_b == "apartments" or bk.get("style") == 3:
            prob = 0.98 if best_hw >= 4.5 else 0.78
        else:
            prob = 0.94 if best_hw >= 4.5 else 0.72
        if dist_yuehe < 400.0:
            prob = 0.99
        if rng.random() > prob:
            continue
        nx, ny = ((c[1] - a[1]) / el, -(c[0] - a[0]) / el) if ccw else (-(c[1] - a[1]) / el, (c[0] - a[0]) / el)
        # the shop face must actually look at the street (allow slight angle on curved/angled avenues!)
        mx_f, my_f = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
        look_ok = False
        for (rax, ray, rbx, rby, hw) in road_grid.query(mx_f - 44, my_f - 44, mx_f + 44, my_f + 44):
            dd, tt = seg_dist(mx_f, my_f, rax, ray, rbx, rby)
            if dd - hw <= best_d + 5.5:
                qx, qy = rax + (rbx - rax) * tt, ray + (rby - ray) * tt
                ql = math.hypot(qx - mx_f, qy - my_f)
                if ql > 1e-6 and ((qx - mx_f) * nx + (qy - my_f) * ny) / ql > 0.25:
                    look_ok = True
                    break
        if not look_ok:
            continue
        ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
        # Flush wall-to-wall continuous Chinese ground-floor shop rows (连排底商 — up to 40 seamless ~4.8m bays!)
        pad_end = 0.18 if el >= 8.0 else 0.10
        usable = el - pad_end * 2.0
        n_shops = max(1, min(40, int(round(usable / 4.8))))
        bay_w = usable / n_shops
        if bay_w < 3.4:
            n_shops = max(1, int(usable // 3.6))
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
# Real Jiaxing cross-sections by road class, kerb to kerb (Amap satellite survey of the T1 corridor, Nov 2026):
# 主干道 ~32-45 m (3+3 lanes, bike lanes, 机非隔离带), 次干道 ~24-28 m (2+2), 支路 ~16-18 m (1+1 + bike lanes).
# OSM rarely tags lanes in Jiaxing, so most of these came through as 8.8 m two-lane streets.
# (two-way width, lanes per direction, one-way carriageway width, one-way lanes)
ROAD_RANK = {"trunk": 5, "primary": 4, "secondary": 3, "tertiary": 2, "unclassified": 1, "residential": 1}

CLASS_SECTION = {
    "trunk": (36.0, 3, 14.5, 3),
    "primary": (34.0, 3, 14.5, 3),
    "secondary": (26.0, 2, 11.5, 2),
    "tertiary": (17.0, 1, 8.8, 2),
}


FANGGONG_X = 1440.0   # 纺工路 crosses 中环南路 here (game x)
SIDE_ROADS = []        # (kept empty: the 辅路 are real graph edges now)


def zhonghuan_side_roads(graph_edges):
    """East of 纺工路, 中环南路 has a one-lane 辅路 outside each main carriageway, behind a ~3 m planted strip
    (Amap satellite at 嘉兴一中). OSM has no separate ways for them, so they are laid parallel to each main
    half, stopping short of the junction mouths."""
    SIDE_ROADS.clear()
    new_edges = []
    next_id = max(e["id"] for e in graph_edges) + 1
    halves = [e for e in graph_edges if e.get("name") == "中环南路" and not e.get("hide_road")
              and not e.get("underground") and not (int(e.get("lanes_f", 1)) and int(e.get("lanes_b", 1)))]
    for e in halves:
        p = e["pts"]
        mx = sum(q[0] for q in p) / len(p)
        if mx < FANGGONG_X + 20.0:
            continue
        L = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for k in range(len(p) - 1))
        if L < 90.0:
            continue
        # outward = away from the other direction's carriageway
        my = sum(q[1] for q in p) / len(p)
        others = [o for o in halves if o is not e and int(o.get("lanes_f", 0)) != int(e.get("lanes_f", 0))]
        if not others:
            continue
        oy = min(others, key=lambda o: abs(sum(q[0] for q in o["pts"]) / len(o["pts"]) - mx))
        oy_m = sum(q[1] for q in oy["pts"]) / len(oy["pts"])
        out_sign = -1.0 if my < oy_m else 1.0   # north half -> further north (-y), south half -> further south
        off = float(e["width"]) * 0.5 + 3.0 + 2.75
        # resample, trim 30 m at both ends, offset along the local normal (pointing to out_sign in y)
        pts = []
        acc = 0.0
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            sl = math.hypot(bx - ax, by - ay)
            if sl < 1e-6:
                continue
            ux, uy = (bx - ax) / sl, (by - ay) / sl
            nx, ny = -uy, ux
            if ny * out_sign < 0.0:
                nx, ny = -nx, -ny
            t = 0.0
            while t <= sl:
                s_ = acc + t
                if 30.0 <= s_ <= L - 30.0:
                    pts.append([round(ax + ux * t + nx * off, 2), round(ay + uy * t + ny * off, 2)])
                t += 20.0
            acc += sl
        if len(pts) < 2:
            continue
        lf = 1 if int(e.get("lanes_f", 0)) else 0
        # a real street in the traffic graph: it leaves the main road's junction, swings out behind the planted
        # strip, runs alongside and rejoins at the next junction (same nodes, same direction as its main half)
        full = [list(p[0])] + pts + [list(p[-1])]
        new_edges.append({
            "id": next_id, "a": e["a"], "b": e["b"], "name": "中环南路辅路", "width": 5.5,
            "lanes_f": lf, "lanes_b": 1 - lf, "divided": False, "cls": "service",
            "length": round(sum(math.hypot(full[k + 1][0] - full[k][0], full[k + 1][1] - full[k][1]) for k in range(len(full) - 1)), 1),
            "pts": full, "side_road": True,
        })
        next_id += 1
    graph_edges.extend(new_edges)
    print(f"中环南路: {len(new_edges)} one-lane 辅路 laid east of 纺工路 as streets of the traffic graph")


def unwedge_twin_carriageways(graph_edges, graph_nodes):
    """The two one-way halves of a divided road snapped to one junction node leave it as a long thin wedge (each
    half heads straight for the other half's far end). Give each half a bend 30-35 m out so it runs parallel at its
    own side of the road for the rest of the way; the convergence then sits inside the junction."""
    npos = {n["id"]: n["pos"] for n in graph_nodes}
    at = defaultdict(list)
    for e in graph_edges:
        if e.get("hide_road") or e.get("underground") or len(e["pts"]) < 2:
            continue
        if int(e.get("lanes_f", 1)) and int(e.get("lanes_b", 1)):
            continue
        at[e["a"]].append(e)
        at[e["b"]].append(e)
    n_fix = 0
    done = set()
    for nid, es in at.items():
        for i in range(len(es)):
            for j in range(i + 1, len(es)):
                e1, e2 = es[i], es[j]
                if e1["name"] != e2["name"] or (e1["id"], nid) in done or (e2["id"], nid) in done:
                    continue
                seqs = []
                for e in (e1, e2):
                    seqs.append(e["pts"] if e["a"] == nid else list(reversed(e["pts"])))
                o = seqs[0][0]
                f1, f2 = seqs[0][-1], seqs[1][-1]
                L1 = math.hypot(f1[0] - o[0], f1[1] - o[1])
                L2 = math.hypot(f2[0] - o[0], f2[1] - o[1])
                if L1 < 90.0 or L2 < 90.0:
                    continue
                d1 = ((f1[0] - o[0]) / L1, (f1[1] - o[1]) / L1)
                d2 = ((f2[0] - o[0]) / L2, (f2[1] - o[1]) / L2)
                if d1[0] * d2[0] + d1[1] * d2[1] < math.cos(math.radians(22.0)):
                    continue
                ax_, ay_ = d1[0] + d2[0], d1[1] + d2[1]
                al = math.hypot(ax_, ay_)
                ax_, ay_ = ax_ / al, ay_ / al
                nx_, ny_ = -ay_, ax_
                # lateral offset of each half, read 60 % of the way out
                lats = []
                for sq, Lf in ((seqs[0], L1), (seqs[1], L2)):
                    tgt = 0.6 * Lf
                    acc = 0.0
                    q = sq[-1]
                    for k in range(len(sq) - 1):
                        sl = math.hypot(sq[k + 1][0] - sq[k][0], sq[k + 1][1] - sq[k][1])
                        if acc + sl >= tgt and sl > 1e-6:
                            t = (tgt - acc) / sl
                            q = (sq[k][0] + (sq[k + 1][0] - sq[k][0]) * t, sq[k][1] + (sq[k + 1][1] - sq[k][1]) * t)
                            break
                        acc += sl
                    lats.append((q[0] - o[0]) * nx_ + (q[1] - o[1]) * ny_)
                if abs(lats[0] - lats[1]) < 9.0:
                    continue
                for e, sq, lat in ((e1, seqs[0], lats[0]), (e2, seqs[1], lats[1])):
                    s_b = 32.0
                    bend = [round(o[0] + ax_ * s_b + nx_ * lat, 2), round(o[1] + ay_ * s_b + ny_ * lat, 2)]
                    # drop interior points that the bend overtakes (within 40 m of the node)
                    rest = [q for q in sq[1:] if math.hypot(q[0] - o[0], q[1] - o[1]) > 40.0]
                    if not rest:
                        rest = [sq[-1]]
                    new = [list(o), bend] + [list(q) for q in rest]
                    e["pts"] = new if e["a"] == nid else list(reversed(new))
                    e["length"] = round(sum(math.hypot(new[k + 1][0] - new[k][0], new[k + 1][1] - new[k][1]) for k in range(len(new) - 1)), 1)
                    done.add((e["id"], nid))
                n_fix += 1
    print(f"Twin carriageways: {n_fix} junction wedges opened so both halves run side by side")


def widen_roads_by_class(graph_edges, nodes, ways):
    """Widen streets to their class's real cross-section, but never so far that the kerb comes within 3 m of a
    mapped (OSM) building: real buildings stay, the street takes what room there is."""
    bgrid = Grid(40.0)
    for wid, (refs, t) in ways.items():
        if "building" not in t or t.get("building") == "no" or len(refs) < 4:
            continue
        pts = [nodes[r] for r in refs if r in nodes]
        if len(pts) < 3:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bgrid.add(pts, min(xs), min(ys), max(xs), max(ys))
    # parallel neighbours (the other carriageway of a divided road, a frontage road): both may widen, so each keeps
    # to its half of the gap
    sgrid = Grid(40.0)
    for e in graph_edges:
        if e.get("underground"):
            continue
        p = e["pts"]
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            sgrid.add((e["id"], ax, ay, bx, by), min(ax, bx), min(ay, by), max(ax, bx), max(ay, by))

    def parallel_gap(e):
        p = e["pts"]
        Ltot = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for k in range(len(p) - 1))
        gap = 99.0
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            L = math.hypot(bx - ax, by - ay)
            if L < 1.0:
                continue
            ux, uy = (bx - ax) / L, (by - ay) / L
            t = 5.0
            while t < L - 5.0:
                qx, qy = ax + ux * t, ay + uy * t
                dend = min(math.hypot(qx - p[0][0], qy - p[0][1]), math.hypot(qx - p[-1][0], qy - p[-1][1]))
                # twin carriageways snapped to a shared junction converge into a wedge there: judge their gap on
                # the middle of the street, the wedge lies inside the junction
                if dend > max(18.0, 0.28 * Ltot):
                    for (oid, ox0, oy0, ox1, oy1) in sgrid.query(qx - 25, qy - 25, qx + 25, qy + 25):
                        if oid == e["id"]:
                            continue
                        oe = by_id.get(oid)
                        # a lesser street alongside (its own 辅路 / a lane) gives way later, it does not cap this one
                        if oe is None or oe.get("hide_road") or \
                                ROAD_RANK.get(oe.get("cls", ""), 0) < ROAD_RANK.get(e.get("cls", ""), 0):
                            continue
                        oL = math.hypot(ox1 - ox0, oy1 - oy0)
                        if oL < 1.0 or abs(ux * (ox1 - ox0) / oL + uy * (oy1 - oy0) / oL) < 0.9:
                            continue
                        gap = min(gap, seg_dist(qx, qy, ox0, oy0, ox1, oy1)[0])
                t += 10.0
        return gap

    # Twin one-way carriageways the junction clustering laid (almost) on top of each other are one street: the
    # straighter twin becomes the two-way street and takes the class's two-way section; the other stays in the
    # graph for connectivity (its junction may carry a side street) but is not drawn
    n_merge = 0
    by_id = {e["id"]: e for e in graph_edges}
    one_way0 = {e["id"] for e in graph_edges if not (int(e.get("lanes_f", 1)) and int(e.get("lanes_b", 1)))}
    ow_lanes = {e["id"]: int(e.get("lanes_f", 0)) + int(e.get("lanes_b", 0)) for e in graph_edges if e["id"] in one_way0}
    for e in graph_edges:
        if e.get("hide_road") or e.get("underground") or e.get("cls") not in CLASS_SECTION:
            continue
        if e["id"] not in one_way0:
            continue
        p = e["pts"]
        Le = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for k in range(len(p) - 1))
        if Le < 30.0:
            continue
        sm = []
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            L = math.hypot(bx - ax, by - ay)
            t = 4.0
            while t < L:
                sm.append((ax + (bx - ax) * t / L, ay + (by - ay) * t / L))
                t += 8.0
        cnt = defaultdict(int)
        for (qx, qy) in sm:
            for (oid, ox0, oy0, ox1, oy1) in sgrid.query(qx - 9, qy - 9, qx + 9, qy + 9):
                o = by_id.get(oid)
                if o is None or oid == e["id"] or o.get("hide_road") or o.get("name") != e.get("name"):
                    continue
                if oid not in one_way0:
                    continue
                if seg_dist(qx, qy, ox0, oy0, ox1, oy1)[0] < 8.0:
                    cnt[oid] += 1
        twins = [oid for oid, c in cnt.items() if c >= 0.7 * len(sm)]
        if not twins:
            continue
        # e lies along its twin(s) for most of its length: e is the one drawn only if it is the straighter / longer
        tw = max(twins, key=lambda oid: by_id[oid]["length"])
        o = by_id[tw]
        keep, drop = (e, o) if len(e["pts"]) <= len(o["pts"]) and e["length"] >= 0.8 * o["length"] else (o, e)
        if keep.get("hide_road") or drop.get("hide_road"):
            continue
        n_dir = max(ow_lanes.get(e["id"], 1), ow_lanes.get(o["id"], 1), 2)
        keep["lanes_f"] = max(int(keep.get("lanes_f", 0)), n_dir)
        keep["lanes_b"] = max(int(keep.get("lanes_b", 0)), n_dir)
        keep["divided"] = True
        drop["hide_road"] = True
        n_merge += 1

    n_w = 0
    n_ge_rd = 0
    for e in graph_edges:
        if e.get("hide_road") or e.get("underground") or e.get("tunnel"):
            continue
        ename = e.get("name", "")
        rspec = road_spec_for_name(ename)
        sec = CLASS_SECTION.get(e.get("cls", ""))
        ge_buf = 0.0
        if rspec is not None:
            sec = (rspec[0], rspec[1], rspec[2], rspec[3])
            ge_buf = float(rspec[4])
            n_ge_rd += 1
        elif ename.startswith("中环"):
            # 中环路 is a 主辅路 ring: per direction two main lanes plus two side-road lanes (~17 m)
            sec = (44.0, 4, 17.0, 4)
        if sec is None:
            continue
        lf, lb = int(e.get("lanes_f", 1)), int(e.get("lanes_b", 1))
        one_way = lf == 0 or lb == 0
        want = sec[2] if one_way else sec[0]
        w0 = float(e["width"])
        # For explicitly Google-Earth-measured narrow old-town lanes/streets, allow narrowing down to real width too!
        if rspec is not None and want < w0 - 0.5 and not e.get("tram_median"):
            e["width"] = round(want, 1)
            n_new = sec[3] if one_way else sec[1]
            if one_way:
                e["lanes_f"] = n_new if lf else 0
                e["lanes_b"] = n_new if lb else 0
            else:
                e["lanes_f"] = n_new
                e["lanes_b"] = n_new
            continue
        if want <= w0 + 0.5:
            if ge_buf > 0.0 and not e.get("bridge") and not one_way and w0 >= 25.0:
                e["bike_buffer"] = ge_buf
            continue
        pts = e["pts"]
        L = sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(pts) - 1))
        clear = 99.0
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for bp in bgrid.query(min(xs) - 30, min(ys) - 30, max(xs) + 30, max(ys) + 30):
            for q in bp:
                # corners beyond the street's ends stand across the junction, not beside it
                d, tt = min((seg_dist(q[0], q[1], pts[k][0], pts[k][1], pts[k + 1][0], pts[k + 1][1]) for k in range(len(pts) - 1)),
                            key=lambda r: r[0])
                if d < clear:
                    along_ok = True
                    if L > 30.0:
                        da = math.hypot(q[0] - pts[0][0], q[1] - pts[0][1])
                        db = math.hypot(q[0] - pts[-1][0], q[1] - pts[-1][1])
                        along_ok = min(da, db) > 14.0
                    if along_ok:
                        clear = d
        w1 = min(want, max(w0, 2.0 * (clear - 3.0)))
        if ename.startswith("中环"):
            w1 = want  # the ring road has priority: whatever stands in its real section yields
        if w1 > w0 + 0.5:
            gap = parallel_gap(e)
            if gap < 60.0:
                w1 = min(w1, max(w0, gap - 1.2))
        if w1 <= w0 + 0.5:
            continue
        e["width"] = round(w1, 1)
        if one_way:
            n = sec[3] if w1 >= sec[2] - 0.5 else max(1, int((w1 - 4.2) / 3.3))
            if lf:
                e["lanes_f"] = max(lf, n)
            else:
                e["lanes_b"] = max(lb, n)
        else:
            n = sec[1] if w1 >= sec[0] - 1.0 else max(1, min(sec[1], int((w1 - 6.5) / 6.6)))
            e["lanes_f"] = max(lf, n)
            e["lanes_b"] = max(lb, n)
            if ge_buf > 0.0 and not e.get("bridge") and w1 >= 26.0:
                e["bike_buffer"] = ge_buf
        n_w += 1
    # 中环南路 as surveyed (Amap satellite + the user's notes): two-way 6 lanes; west of 纺工路 it is the bridge
    # (3 + 3), east of it each direction is a 3-lane main road plus a one-lane 辅路 outside a planted strip
    # (the 辅路 are laid by zhonghuan_side_roads)
    for e in graph_edges:
        if e.get("name") != "中环南路" or e.get("underground"):
            continue
        lf, lb = int(e.get("lanes_f", 1)), int(e.get("lanes_b", 1))
        if lf and lb:
            e["width"], e["lanes_f"], e["lanes_b"] = 24.8, 3, 3
        else:
            e["width"] = 12.1
            e["lanes_f"], e["lanes_b"] = (3, 0) if lf else (0, 3)
        e.pop("bike_buffer", None)

    for e in graph_edges:
        lf, lb = int(e.get("lanes_f", 1)), int(e.get("lanes_b", 1))
        w = float(e["width"])
        if lf and lb:
            cap = max(1, int((w * 0.5 - 1.5) / 3.3 + 0.05))
        else:
            cap = max(1, int((w - 2.2) / 3.3 + 0.05))
        e["lanes_f"] = min(lf, cap) if lf else 0
        e["lanes_b"] = min(lb, cap) if lb else 0
    print(f"Road class cross-sections: {n_merge} stacked twin carriageways drawn as one street, widened {n_w} street edges ({n_ge_rd} matched Google Earth road specs, kerbs kept 3 m off mapped buildings)")


def resolve_parallel_overlaps(graph_edges, t1_ids):
    """Last pass before the street meshes: two parallel carriageways may not share asphalt (coplanar surfaces
    flicker). A strip lying mostly inside a T1 boulevard is the old twin carriageway and is hidden; any other pair
    is narrowed (the wider one first) until their kerbs no longer cross."""
    vis = [e for e in graph_edges if not e.get("hide_road") and not e.get("underground") and not e.get("bridge")]
    sgrid = Grid(40.0)
    for e in vis:
        p = e["pts"]
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            sgrid.add((e["id"], ax, ay, bx, by), min(ax, bx), min(ay, by), max(ax, bx), max(ay, by))
    by_id = {e["id"]: e for e in vis}

    def samples(e):
        p = e["pts"]
        Ltot = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for k in range(len(p) - 1))
        out = []
        for k in range(len(p) - 1):
            ax, ay = p[k]
            bx, by = p[k + 1]
            L = math.hypot(bx - ax, by - ay)
            if L < 1.0:
                continue
            ux, uy = (bx - ax) / L, (by - ay) / L
            t = 4.0
            while t < L - 4.0:
                qx, qy = ax + ux * t, ay + uy * t
                if min(math.hypot(qx - p[0][0], qy - p[0][1]), math.hypot(qx - p[-1][0], qy - p[-1][1])) > max(22.0, 0.28 * Ltot):
                    out.append((qx, qy, ux, uy))
                t += 8.0
        return out

    n_hide = n_narrow = 0
    for _it in range(3):
        changed = False
        for e in vis:
            if e.get("hide_road") or e["id"] in t1_ids:
                continue
            sm = samples(e)
            if not sm:
                continue
            hw = float(e["width"]) * 0.5
            in_t1 = 0
            worst = {}
            inside_n = defaultdict(int)
            for (qx, qy, ux, uy) in sm:
                for (oid, ox0, oy0, ox1, oy1) in sgrid.query(qx - 30, qy - 30, qx + 30, qy + 30):
                    o = by_id.get(oid)
                    if o is None or oid == e["id"] or o.get("hide_road"):
                        continue
                    oL = math.hypot(ox1 - ox0, oy1 - oy0)
                    if oL < 1.0 or abs(ux * (ox1 - ox0) / oL + uy * (oy1 - oy0) / oL) < 0.9:
                        continue
                    d = seg_dist(qx, qy, ox0, oy0, ox1, oy1)[0]
                    ohw = float(o["width"]) * 0.5
                    if d < hw + ohw - 0.3:
                        if oid in t1_ids and d < ohw + hw * 0.5:
                            in_t1 += 1
                            break
                        worst[oid] = min(worst.get(oid, 99.0), d)
                        if d < ohw:
                            inside_n[oid] += 1
            if in_t1 >= max(2, int(0.5 * len(sm))):
                e["hide_road"] = True
                e["lanes_f"] = 0
                e["lanes_b"] = 0
                n_hide += 1
                changed = True
                continue
            for oid, d in worst.items():
                if e.get("hide_road"):
                    break
                o = by_id[oid]
                if o.get("hide_road"):
                    continue
                ohw = float(o["width"]) * 0.5
                hw = float(e["width"]) * 0.5
                excess = hw + ohw - (d - 0.4)
                if excess <= 0.0:
                    continue
                # the more important street keeps its section (a main road over its own 辅路 / a lane beside
                # it); between equals the wider one gives way; T1 boulevards stay as they are; never below 5.5 m
                re_, ro_ = ROAD_RANK.get(e.get("cls", ""), 0), ROAD_RANK.get(o.get("cls", ""), 0)
                if oid in t1_ids or ro_ > re_:
                    tgt, other_hw = e, ohw
                elif re_ > ro_:
                    tgt, other_hw = o, hw
                elif ohw > hw:
                    tgt, other_hw = o, hw
                else:
                    tgt, other_hw = e, ohw
                # a lesser strip whose centreline mostly runs inside the bigger street is that street's side lane:
                # stop drawing it (it stays in the graph, so its junctions and traffic keep working)
                if tgt is e and inside_n[oid] >= max(2, int(0.6 * len(sm))) and (re_ < ro_ or oid in t1_ids):
                    e["hide_road"] = True
                    n_hide += 1
                    changed = True
                    break
                new_w = max(5.5, 2.0 * (d - 0.4 - other_hw))
                if new_w < float(tgt["width"]) - 0.05:
                    tgt["width"] = round(new_w, 1)
                    lanes_room = max(1, int((new_w - 2.2) / 3.3 + 0.05))
                    if int(tgt.get("lanes_f", 0)) and int(tgt.get("lanes_b", 0)):
                        per = max(1, lanes_room // 2)
                        tgt["lanes_f"] = min(int(tgt["lanes_f"]), per)
                        tgt["lanes_b"] = min(int(tgt["lanes_b"]), per)
                    elif int(tgt.get("lanes_f", 0)):
                        tgt["lanes_f"] = min(int(tgt["lanes_f"]), lanes_room)
                    elif int(tgt.get("lanes_b", 0)):
                        tgt["lanes_b"] = min(int(tgt["lanes_b"]), lanes_room)
                    tgt.pop("bike_buffer", None)
                    n_narrow += 1
                    changed = True
        if not changed:
            break
    print(f"Parallel carriageways: {n_hide} twin strips inside T1 boulevards hidden, {n_narrow} narrowed to stop sharing asphalt")


# 瀚林府邸's eight 新中式 slab towers (local centre, size x/height/z in the landmark's frame, rotated by its angle):
# kept in step with JiaxingCivicLandmarks._hanlin_residence_and_skybridge, which draws only their podium and cap
HANLIN_TOWERS = [
    ((-56.0, -96.0), (52.0, 38.0, 16.0)), ((38.0, -96.0), (54.0, 42.0, 16.0)),
    ((-56.0, -48.0), (52.0, 34.0, 16.0)), ((46.0, -48.0), (48.0, 36.0, 16.0)),
    ((-58.0, 56.0), (54.0, 44.0, 16.0)), ((40.0, 58.0), (52.0, 38.0, 16.0)),
    ((-54.0, 106.0), (56.0, 46.0, 16.0)), ((42.0, 106.0), (54.0, 40.0, 16.0)),
]
HANLIN_ANGLE = 0.203


def hanlin_tower_buildings():
    out = []
    ca, sa = math.cos(HANLIN_ANGLE), math.sin(HANLIN_ANGLE)
    for (lx, lz), (sx, sh, sz) in HANLIN_TOWERS:
        corners = []
        for (cx, cz) in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
            x, z = lx + cx, lz + cz
            # Godot rotation.y: x' = x cos + z sin, z' = -x sin + z cos
            corners.append(rnd((HANLIN_POS[0] + x * ca + z * sa, HANLIN_POS[1] - x * sa + z * ca)))
        out.append({"pts": corners, "h": sh, "kind": "apartments", "style": 2, "colour": "#e6ddcf", "trim": "#5a4c3c",
                    "name": "瀚林府邸"})
    # Authentic 2-3 storey street-front commercial complex SOUTH of Hanlin Residence East Gate extending ALL THE WAY
    # down to 中环南路 (1:1 Google Earth match to user's screenshot: 沿街商铺 strip + large square 瀚林商业广场 +
    # south 中环南路 commercial wing; residential fence stops cleanly at the west wall of 瀚林商业广场!)
    def _world_rect(cx_w, cy_w, wx_s, wy_s, yaw_w):
        cw, sw = math.cos(yaw_w), math.sin(yaw_w)
        pts_w = []
        for (ox, oy) in ((-wx_s * 0.5, -wy_s * 0.5), (wx_s * 0.5, -wy_s * 0.5),
                         (wx_s * 0.5, wy_s * 0.5), (-wx_s * 0.5, wy_s * 0.5)):
            pts_w.append(rnd((cx_w + ox * cw + oy * sw, cy_w - ox * sw + oy * cw)))
        return pts_w

    # 1. North 2-storey 沿街商铺 strip hugging 纺工路 west side directly south of Hanlin East Gate
    out.append({
        "pts": _world_rect(1386.0, 1476.0, 18.0, 56.0, 0.195),
        "h": 8.8, "kind": "commercial", "style": 1, "colour": "#e6ddd0", "trim": "#4a525c",
        "name": "瀚林府邸沿街商铺",
    })
    # 2. Prominent 3-storey square commercial plaza building (瀚林商业广场) with central roof garden/skylight
    out.append({
        "pts": _world_rect(1374.0, 1536.0, 42.0, 48.0, 0.08),
        "h": 12.2, "kind": "commercial", "style": 1, "colour": "#d8dee4", "trim": "#3d4650",
        "name": "瀚林商业广场",
    })
    # 3. South 2-storey retail wing extending all the way down to 中环南路 north sidewalk!
    out.append({
        "pts": _world_rect(1375.0, 1568.5, 42.0, 14.0, -0.092),
        "h": 7.8, "kind": "commercial", "style": 1, "colour": "#e4dcd0", "trim": "#4a525c",
        "name": "瀚林南街商铺",
    })
    return out


def apply_t1_survey(blds, storefronts, road_grid, bld_grid):
    """Street-level corrections along T1 from the map survey (tools/jiaxing_t1_survey.py): campuses that the
    generator filled with towers come back down to office / hospital height, frontages that are really walls get
    no shops, and the merchants actually trading at each stop take over the nearest matching shop slot (or a
    small two-storey podium is added on that kerb when the generator left the frontage empty)."""
    def cen(pts):
        return sum(q[0] for q in pts) / len(pts), sum(q[1] for q in pts) / len(pts)

    # Style 3 is the small-house facade (one or two storeys, no window grid): a 5-7 storey walk-up given it renders
    # as a blank box, so anything taller than a house uses the residential facade (pitched roofs are kept)
    # (hanlin_tower_buildings() are now appended BEFORE build_street_furniture() so their south 沿街商铺 get real storefronts!)
    n_house = 0
    for b in blds:
        if int(b.get("style", 2)) == 3 and float(b["h"]) > 11.5:
            b["style"] = 2
            n_house += 1
    print(f"Walk-up facades: {n_house} multi-storey blocks moved off the small-house facade")

    n_campus = 0
    all_no_shop = list(NO_SHOP_BOXES)
    for (cnm, x0, y0, x1, y1, hmax, kind, col, no_sh) in REAL_CAMPUSES:
        if no_sh:
            all_no_shop.append((x0, y0, x1, y1))
    for b in blds:
        b.pop("_roof_pinned", None)
        cx, cy = cen(b["pts"])
        for (cnm, x0, y0, x1, y1, hmax, kind, col, _nsh) in REAL_CAMPUSES:
            if not kind:
                continue
            if x0 < cx < x1 and y0 < cy < y1 and b.get("kind") in ("apartments", "residential", "yes", "commercial", "office"):
                if float(b["h"]) > hmax:
                    b["h"] = round(hmax * (0.58 + 0.42 * ((int(abs(cx) * 7 + abs(cy) * 13) % 100) / 100.0)), 1)
                b["kind"] = kind
                b["style"] = 1
                b["colour"] = col
                b["name"] = cnm
                for k in ("cpd", "yangfang", "roof", "roof_colour", "trim", "arch"):
                    b.pop(k, None)
                n_campus += 1
                break

    def mid(sf):
        return (sf["p0"][0] + sf["p1"][0]) * 0.5, (sf["p0"][1] + sf["p1"][1]) * 0.5

    n0 = len(storefronts)
    storefronts[:] = [sf for sf in storefronts
                      if not any(x0 < mid(sf)[0] < x1 and y0 < mid(sf)[1] < y1 for (x0, y0, x1, y1) in all_no_shop)]
    n_cut = n0 - len(storefronts)

    sf_grid = Grid(40.0)
    for i, sf in enumerate(storefronts):
        mx, my = mid(sf)
        sf_grid.add(i, mx, my, mx, my)

    def nearest_road(px, py):
        best = None
        for (ax, ay, bx, by, hw) in road_grid.query(px - 95, py - 95, px + 95, py + 95):
            d, _t = seg_dist(px, py, ax, ay, bx, by)
            if best is None or d - hw < best[0]:
                best = (d - hw, ax, ay, bx, by, hw)
        return best

    def side_of(r, px, py):
        _d, ax, ay, bx, by, _hw = r
        return 1.0 if (bx - ax) * (py - ay) - (by - ay) * (px - ax) >= 0.0 else -1.0

    taken = set()
    n_named = n_podium = n_miss = 0
    for (nm, kind, brand, (tx, ty)) in REAL_SHOPS_GOOGLE:
        r = nearest_road(tx, ty)
        if r is None:
            n_miss += 1
            continue
        s_t = side_of(r, tx, ty)
        best = None
        for i in sf_grid.query(tx - 65, ty - 65, tx + 65, ty + 65):
            if i in taken:
                continue
            sf = storefronts[i]
            mx, my = mid(sf)
            d = math.hypot(mx - tx, my - ty)
            if d > 65.0 or side_of(r, mx, my) != s_t:
                continue
            if best is None or d < best[0]:
                best = (d, i)
        rec = {"name": nm, "kind": kind, "brand": brand or nm, "tier": "chain" if brand else "local", "verified": True}
        if best is not None:
            taken.add(best[1])
            storefronts[best[1]].update(rec)
            n_named += 1
            continue
        # No existing storefront slot on that kerb: attach directly onto the nearest REAL building's street-facing
        # wall (NEVER synthesize fake podium buildings!)
        _d, ax, ay, bx, by, hw = r
        best_edge = None
        for bi_cand, bc in enumerate(blds):
            bpts = bc["pts"]
            if len(bpts) < 3:
                continue
            bx0, by0 = cen(bpts)
            if abs(bx0 - tx) > 85.0 or abs(by0 - ty) > 85.0:
                continue
            if side_of(r, bx0, by0) != s_t:
                continue
            # Check each wall edge of this real building facing the target road
            n_v = len(bpts)
            for ei in range(n_v):
                p0 = bpts[ei]
                p1 = bpts[(ei + 1) % n_v]
                elen = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
                if elen < 5.0:
                    continue
                emx, emy = (p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5
                d_t = math.hypot(emx - tx, emy - ty)
                if d_t > 75.0:
                    continue
                # Outward normal (ensure it points away from building centroid and toward the street)
                dux, duy = (p1[0] - p0[0]) / elen, (p1[1] - p0[1]) / elen
                onx, ony = duy, -dux
                if onx * (emx - bx0) + ony * (emy - by0) < 0.0:
                    onx, ony = -onx, -ony
                    dux, duy = -dux, -duy
                d_rd, _ = seg_dist(emx, emy, ax, ay, bx, by)
                if d_rd > hw + 38.0:
                    continue
                score = d_t + d_rd * 0.4
                if best_edge is None or score < best_edge[0]:
                    best_edge = (score, bi_cand, emx, emy, dux, duy, onx, ony, min(3.4, elen * 0.42))
        if best_edge is not None:
            _, bi_cand, emx, emy, dux, duy, onx, ony, half_s = best_edge
            sf = {
                "b": bi_cand,
                "p0": rnd((emx - dux * half_s, emy - duy * half_s)),
                "p1": rnd((emx + dux * half_s, emy + duy * half_s)),
                "n": [round(onx, 4), round(ony, 4)],
            }
            sf.update(rec)
            storefronts.append(sf)
            n_podium += 1
        else:
            n_miss += 1
    # Pass 2: Snap THOUSANDS of real Jiaxing street-front merchant names harvested from Amap tiles (Vision OCR)
    # onto matching real storefront slots city-wide (falling back to generated local names ONLY where no real
    # merchant exists nearby)!
    ocr_path = os.path.join(HERE, "osm_cache", "jiaxing_real_shops_ocr.json")
    n_ocr_matched = 0
    if os.path.exists(ocr_path):
        ocr_shops = json.load(open(ocr_path, "r", encoding="utf-8"))
        # Rebuild sf_grid including any podium-attached shops from Pass 1
        sf_grid2 = Grid(45.0)
        for i, sf in enumerate(storefronts):
            if i in taken or sf.get("verified"):
                continue
            mx, my = mid(sf)
            sf_grid2.add(i, mx, my, mx, my)
        for it in ocr_shops:
            tx, ty = float(it["x"]), float(it["y"])
            nm = str(it["name"]).strip()
            sk = str(it.get("kind", "convenience"))
            if not nm or any(x0 < tx < x1 and y0 < ty < y1 for (x0, y0, x1, y1) in all_no_shop):
                continue
            best = None
            for i in sf_grid2.query(tx - 65, ty - 65, tx + 65, ty + 65):
                if i in taken:
                    continue
                mx, my = mid(storefronts[i])
                d = math.hypot(mx - tx, my - ty)
                if d <= 65.0 and (best is None or d < best[0]):
                    best = (d, i)
            if best is not None:
                idx_sf = best[1]
                taken.add(idx_sf)
                storefronts[idx_sf].update({
                    "name": nm,
                    "kind": sk,
                    "brand": nm,
                    "tier": "chain" if any(ck in nm for ck in ("银行", "十足", "罗森", "全家", "瑞幸", "星巴克", "蜜雪冰城", "古茗", "霸王茶姬", "肯德基", "麦当劳", "老百姓", "益丰", "海王星辰", "五芳斋", "真真老老", "中国移动", "中国电信", "中国联通", "华为", "小米")) else "local",
                    "verified": True,
                })
                n_ocr_matched += 1
    print(f"Google Maps/Earth survey: {n_campus} campus buildings re-kinded, {n_cut} made-up shops off campus/compound walls, "
          f"{n_named} T1 survey merchants + {n_ocr_matched} real map-wide OCR merchants placed, "
          f"{n_podium} attached to real street buildings (0 synthetic podiums), {n_miss} not placed")


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

    # All 16 authentic operational stations of Jiaxing Tram Line T1 in exact real-world Amap (高德地图) sequence:
    # Part A (Surface South -> North): 嘉兴南站(站前东行平滑北转) -> 庆丰路(庆丰路基地/长水路) -> 由拳路(双溪路/商务大道) -> 纺工路(由拳路/一中/烟雨路/南溪西路/景湖路/滨河路) -> 跨平湖塘桥 -> 干地入口
    # Part B (B1 Underground Tunnel): 东隧道坡道 -> 嘉兴火车站(B1中央无遮挡廊道) -> 下穿沪昆铁路 -> 勤俭路出口坡道
    # Part C (Surface West): 勤俭路西行 -> 环城东路南行(人民公园) -> 中山东路(瓶山 -> 禾兴南路 -> 中山东路安乐路)
    waypoints_south = [
        ("嘉兴南站", 4080.68, 6817.27, ""),
        ("__south_plaza_m__", 4221.50, 6742.88, ""),
        ("__south_plaza_e__", 4392.0, 6644.0, ""),
        ("__qingfeng_s__", 4317.21, 6448.94, "庆丰路"),
        ("有轨电车庆丰路基地站", 4246.0, 4275.0, "庆丰路"),
        ("庆丰路长水路站", 4242.0, 3527.0, "庆丰路"),
        ("__qf_yq_corner__", 4216.26, 2577.23, "由拳路"),
        ("由拳路双溪路站", 3255.4, 2531.6, "由拳路"),
        ("由拳路商务大道站", 2408.0, 2529.0, "由拳路"),
        ("纺工路由拳路站", 1410.6, 2519.6, "纺工路"),
        ("嘉兴一中站", 1446.6, 1602.3, "纺工路"),
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

    # Create dedicated B1 underground nodes & subterranean tunnel edges:
    #   1. T1 continues DEAD STRAIGHT NORTH down the center median of 纺工路/东方路 into an open-cut concrete U-trough
    #      portal ([993.3, -1075.3] -> [998.5, -1195.0], y: 0 -> -10m — 1:1 match to Google Earth!)
    #   2. Once completely underground at B1 (y = -10.0m), T1 curves smoothly westward under South Plaza
    #      ([998.5, -1195.0] -> [950.0, -1238.0] -> [795.0, -1185.0]) into JiaxingStationB1Hall's unobstructed
    #      central corridor (lx = 0, y = -10.0m) straight under 沪昆铁路 -> 勤俭路!
    # Reshape surface 纺工路 (nid_pinghu_n -> nid_portal_e) so nid_portal_e sits at [993.3, -1075.3] (just north of
    # People's Park East Gate / 甪里街), and keep surface 东方路 continuing straight north around the portal median!
    p_portal_e_straight = [993.3, -1075.3]
    for nd_p in nodes_list:
        if nd_p["id"] == nid_portal_e:
            nd_p["pos"] = p_portal_e_straight
            node_pos_by_id[nid_portal_e] = p_portal_e_straight
            break
    p_portal_e = p_portal_e_straight
    for ed_p in edges_list:
        a_id, b_id = ed_p["a"], ed_p["b"]
        if (a_id == nid_pinghu_n and b_id == nid_portal_e) or (b_id == nid_pinghu_n and a_id == nid_portal_e):
            pa_s = node_pos_by_id[nid_pinghu_n]
            ed_p["pts"] = [pa_s, p_portal_e] if a_id == nid_pinghu_n else [p_portal_e, pa_s]
            ed_p["length"] = round(math.hypot(p_portal_e[0] - pa_s[0], p_portal_e[1] - pa_s[1]), 2)
            ed_p["width"] = 36.0
            ed_p["name"] = "纺工路"
        elif a_id == nid_portal_e and not ed_p.get("underground"):
            ed_p["pts"][0] = p_portal_e
        elif b_id == nid_portal_e and not ed_p.get("underground"):
            ed_p["pts"][-1] = p_portal_e
    # Add wide surface 东方路 continuation flanking the straight center-median concrete U-trough portal north to [1006.2, -1332.0]
    nid_df_north = nearest_node_xy(1006.2, -1332.0, "东方路")
    if nid_df_north != nid_portal_e:
        p_dfn = node_pos_by_id[nid_df_north]
        pts_df = [p_portal_e, [998.5, -1195.0], [1002.4, -1270.0], p_dfn]
        L_df = round(sum(math.hypot(pts_df[k + 1][0] - pts_df[k][0], pts_df[k + 1][1] - pts_df[k][1]) for k in range(len(pts_df) - 1)), 2)
        edges_list.append({
            "id": next_eid, "a": nid_portal_e, "b": nid_df_north, "name": "东方路",
            "width": 36.0, "lanes_f": 3, "lanes_b": 3, "tram_median": True, "bike_lane": True,
            "length": L_df, "pts": pts_df, "cls": "primary",
        })
        next_eid += 1
        # Hide the old overlapping narrow twin carriageway beside this wide unified 东方路 boulevard
        for ed_h in edges_list:
            if ed_h.get("name") == "东方路" and not ed_h.get("underground") and float(ed_h.get("width", 0)) < 16.0:
                ep = ed_h.get("pts", [])
                if ep and any(-1325.0 <= q[1] <= -1045.0 and 955.0 <= q[0] <= 1015.0 for q in ep):
                    ed_h["hide_road"] = True

    nid_b1_df = next_nid
    nid_b1_mid = next_nid + 1
    nid_b1_e = next_nid + 2
    nid_b1_w = next_nid + 3
    p_b1_df = [998.5, -1195.0]
    p_b1_mid = [950.0, -1238.0]
    p_b1_e = [795.0, -1185.0]
    p_b1_w = [632.0, -1342.0]
    nodes_list.append({"id": nid_b1_df, "pos": p_b1_df, "name": "纺工路地下隧道入口底"})
    nodes_list.append({"id": nid_b1_mid, "pos": p_b1_mid, "name": "南广场地下弯道"})
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

    e_ramp_in = _add_ug_edge(next_eid, nid_portal_e, nid_b1_df, p_portal_e, p_b1_df, "纺工路直行下穿隧道坡道")
    e_b1_c1 = _add_ug_edge(next_eid + 1, nid_b1_df, nid_b1_mid, p_b1_df, p_b1_mid, "南广场地下联络隧道")
    e_b1_c2 = _add_ug_edge(next_eid + 2, nid_b1_mid, nid_b1_e, p_b1_mid, p_b1_e, "嘉兴站南地下联络隧道")
    e_b1_sta = _add_ug_edge(next_eid + 3, nid_b1_e, nid_b1_w, p_b1_e, p_b1_w, "嘉兴火车站地下隧道")
    e_ramp_out = _add_ug_edge(next_eid + 4, nid_b1_w, nid_portal_w, p_b1_w, p_portal_w, "嘉兴站北地下隧道坡道")
    ug_elev_map = {
        e_ramp_in["id"]: (0.0, -10.0),
        e_b1_c1["id"]: (-10.0, -10.0),
        e_b1_c2["id"]: (-10.0, -10.0),
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

    # Trace Part B (Underground B1 Tunnel straight north down 东方路 -> smooth underground curve -> 嘉兴火车站 -> 勤俭路!)
    for ug_ed in (e_ramp_in, e_b1_c1, e_b1_c2, e_b1_sta, e_ramp_out):
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

    # Exact real-world side-of-intersection coordinates for stations pinned just past their cross street:
    # - 由拳路双溪路站: on 由拳路 immediately WEST of 双溪路 (x < 3255.4)
    # - 纺工路由拳路站: on 纺工路 immediately NORTH of 由拳路 (y < 2519.6), NOT on 由拳路!
    # - 嘉兴一中站: on 纺工路 immediately NORTH of 中环南路 (y < 1602.3), NOT south!
    # - 中山东路建国南路(瓶山): on 中山东路 immediately WEST of 建国南路 (x < -217.7), NOT east!
    # - 中山东路禾兴南路: on 中山东路 immediately WEST of 禾兴南路 (x < -689.3), NOT east!
    exact_station_pos = {
        "有轨电车庆丰路基地站": (4246.0, 4275.0),
        "由拳路双溪路站": (3193.0, 2531.3),
        "纺工路由拳路站": (1413.0, 2448.0),
        "嘉兴一中站": (1432.0, 1532.0),
        "中山东路建国南路(瓶山)": (-288.0, -1097.5),
        "中山东路禾兴南路": (-754.0, -1015.5),
    }

    # Assign each of the 16 real operational stations cleanly to its exact ordered edge & side of intersection!
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
        elif nm in exact_station_pos:
            tx_p, ty_p = exact_station_pos[nm]
            best_ti = -1
            best_dist = 1e18
            best_t = 0.5
            for ti in range(min_track_idx, len(track_eids)):
                eid = track_eids[ti]
                if eid in xover_eids or eid in ug_elev_map:
                    continue
                elen = float(edge_by_id[eid]["length"])
                if elen < 48.0:
                    continue
                pts_e = edge_by_id[eid]["pts"]
                pa, pb = pts_e[0], pts_e[-1]
                d_seg, _ = seg_dist(tx_p, ty_p, pa[0], pa[1], pb[0], pb[1])
                if d_seg < best_dist:
                    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
                    l2 = dx * dx + dy * dy
                    t_raw = 0.5 if l2 < 1e-6 else ((tx_p - pa[0]) * dx + (ty_p - pa[1]) * dy) / l2
                    margin_t = min(0.36, 42.0 / elen)
                    t_clamped = max(margin_t, min(1.0 - margin_t, t_raw))
                    if all(abs(t_clamped - prev_t) * elen >= 95.0 for prev_t in used_slots[eid]):
                        best_dist = d_seg
                        best_ti = ti
                        best_t = t_clamped
            if best_ti >= 0:
                chosen_eid = track_eids[best_ti]
                chosen_t = best_t
                min_track_idx = max(min_track_idx, best_ti)
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
            # real cross-sections measured along the line (tools/jiaxing_t1_survey.py)
            for rn, (rw, rl, rbuf) in T1_ROAD_WIDTHS.items():
                if rn in ename:
                    ed["width"] = rw
                    ed["lanes_f"] = rl
                    ed["lanes_b"] = rl
                    if rbuf > 0.0:
                        ed["bike_buffer"] = rbuf
                    break
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


UNNAMED_COMPOUND_HULLS = []


def build_gated_compounds(landuse_zones, ways, nodes, road_grid, water_grid, rail_grid, bld_grid, park_grid=None):
    """Build authentic Chinese gated residential compound walls & street-facing gatehouses city-wide."""
    compounds = []
    rng = random.Random(20260530)

    def in_park_or_campus(qx, qy):
        if park_grid is not None:
            for pp in park_grid.query(qx - 6, qy - 6, qx + 6, qy + 6):
                if point_in_poly(qx, qy, pp):
                    return True
        for (_cnm, x0, y0, x1, y1, _hm, _kd, _col, _ns) in REAL_CAMPUSES:
            if x0 < qx < x1 and y0 < qy < y1:
                return True
        return False

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
        seen_c.add((int(c[0] // 72), int(c[1] // 72)))
    for lu, ring in landuse_zones:
        if lu != "residential":
            continue
        c = centroid(ring)
        ck = (int(c[0] // 72), int(c[1] // 72))
        if ck in seen_c or abs(poly_area(ring)) < 1600.0:
            continue
        seen_c.add(ck)
        res_polys.append((simplify_ring(ring, 4.0), ""))

    # Add auto-clustered real unnamed visible residential compounds (地图上可见的无名真实小区)
    for hull_pts, cl_nm in UNNAMED_COMPOUND_HULLS:
        c = centroid(hull_pts)
        ck = (int(c[0] // 72), int(c[1] // 72))
        if ck in seen_c or in_park_or_campus(c[0], c[1]) or in_airport_precinct(c):
            continue
        seen_c.add(ck)
        res_polys.append((hull_pts, cl_nm))

    # Synthesize block-hugging Chinese gated compounds across the ENTIRE active Jiaxing residential fabric
    # (including outer districts, suburban/newly built 2021-2025 blocks & unnamed visible compounds!)
    synth_zones = [
        (-6200, -5000, 6500, 7200, 112),
    ]
    for x0, y0, x1, y1, step in synth_zones:
        for ex in range(x0, x1, step):
            for ey in range(y0, y1, step):
                cx, cy = ex + step * 0.5, ey + step * 0.5
                ck = (int(cx // 72), int(cy // 72))
                if ck in seen_c or not in_active((cx, cy), -40.0):
                    continue
                # Never enclose Yuehe Historic Quarter, Nanhu Lake Island, Shaonian St., Hanlin bespoke compound, or Airport
                if math.hypot(cx - YUEHE_POS[0], cy - YUEHE_POS[1]) < 340.0:
                    continue
                if math.hypot(cx - NANHU_ORIGIN[0], cy - NANHU_ORIGIN[1]) < 460.0:
                    continue
                if math.hypot(cx - HANLIN_POS[0], cy - HANLIN_POS[1]) < 150.0:
                    continue
                if math.hypot(cx - JIAXING_NO1_POS[0], cy - JIAXING_NO1_POS[1]) < 245.0:
                    continue
                if seg_dist(cx, cy, -445.0, -1065.0, -526.0, -1622.0)[0] < 48.0:
                    continue
                if in_airport_precinct((cx, cy)) or in_park_or_campus(cx, cy):
                    continue
                half_s = step * 0.48
                blk_blds = []
                for ob in bld_grid.query(cx - half_s, cy - half_s, cx + half_s, cy + half_s):
                    bc = centroid(ob[4])
                    if abs(bc[0] - cx) <= half_s and abs(bc[1] - cy) <= half_s:
                        blk_blds.append(ob)
                if len(blk_blds) < 2:
                    continue
                bx0 = min(ob[0] for ob in blk_blds) - 4.0
                by0 = min(ob[1] for ob in blk_blds) - 4.0
                bx1 = max(ob[2] for ob in blk_blds) + 4.0
                by1 = max(ob[3] for ob in blk_blds) + 4.0
                if (bx1 - bx0) < 26.0 or (by1 - by0) < 26.0:
                    continue
                if (bx1 - bx0) > 260.0 or (by1 - by0) > 260.0:
                    continue
                rect_r = [(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)]
                seen_c.add(ck)
                res_polys.append((rect_r, ""))

    # Connected-component convex-hull clustering for ALL remaining un-enclosed residential/apartment buildings
    # (captures 2021-2025 newly built blocks & irregular road-bounded 无名小区 that square grids miss!)
    existing_comp_grid = Grid(90.0)
    for r_poly, _rnm in res_polys:
        rc = centroid(r_poly)
        existing_comp_grid.add(r_poly, rc[0] - 85, rc[1] - 85, rc[0] + 85, rc[1] + 85)

    unenc_res = []
    for ob in bld_grid.items if hasattr(bld_grid, "items") else []:
        pass
    # Gather all unique building items from bld_grid cells
    seen_ob_ids = set()
    for cell_list in bld_grid.cells.values():
        for ob in cell_list:
            oid = id(ob)
            if oid in seen_ob_ids:
                continue
            seen_ob_ids.add(oid)
            bc = centroid(ob[4])
            if not in_active(bc, -35.0) or in_airport_precinct(bc) or in_park_or_campus(bc[0], bc[1]):
                continue
            if math.hypot(bc[0] - YUEHE_POS[0], bc[1] - YUEHE_POS[1]) < 340.0:
                continue
            if math.hypot(bc[0] - NANHU_ORIGIN[0], bc[1] - NANHU_ORIGIN[1]) < 460.0:
                continue
            if math.hypot(bc[0] - HANLIN_POS[0], bc[1] - HANLIN_POS[1]) < 150.0:
                continue
            if math.hypot(bc[0] - JIAXING_NO1_POS[0], bc[1] - JIAXING_NO1_POS[1]) < 245.0:
                continue
            # Skip if already inside any existing residential compound polygon
            already = False
            for ep in existing_comp_grid.query(bc[0], bc[1], bc[0], bc[1]):
                if point_in_poly(bc[0], bc[1], ep):
                    already = True
                    break
            if not already:
                unenc_res.append((bc[0], bc[1], ob))

    if len(unenc_res) >= 2:
        u_parent = list(range(len(unenc_res)))
        def uf_find(i):
            while u_parent[i] != i:
                u_parent[i] = u_parent[u_parent[i]]
                i = u_parent[i]
            return i
        u_bins = defaultdict(list)
        for i, (ux, uy, _) in enumerate(unenc_res):
            u_bins[(int(ux // 60), int(uy // 60))].append(i)
        for i, (ux, uy, _) in enumerate(unenc_res):
            bx, by = int(ux // 60), int(uy // 60)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for j in u_bins.get((bx + dx, by + dy), ()):
                        if j <= i:
                            continue
                        vx, vy, _ = unenc_res[j]
                        if math.hypot(ux - vx, uy - vy) <= 56.0:
                            # Do not merge across a major road!
                            mx_u, my_u = (ux + vx) * 0.5, (uy + vy) * 0.5
                            cross_rd = False
                            for (rax, ray, rbx, rby, rhw) in road_grid.query(mx_u - 12, my_u - 12, mx_u + 12, my_u + 12):
                                if rhw >= 4.5 and seg_intersection((ux, uy), (vx, vy), (rax, ray), (rbx, rby)) is not None:
                                    cross_rd = True
                                    break
                            if not cross_rd:
                                ri, rj = uf_find(i), uf_find(j)
                                if ri != rj:
                                    u_parent[ri] = rj
        u_groups = defaultdict(list)
        for i in range(len(unenc_res)):
            u_groups[uf_find(i)].append(unenc_res[i])
        n_cc_added = 0
        for grp in u_groups.values():
            if len(grp) < 2 or len(grp) > 28:
                continue
            all_pts = []
            for _ux, _uy, ob in grp:
                all_pts.extend(ob[4])
            # Simple padded convex hull around this un-enclosed residential cluster
            pts_s = sorted(set((round(p[0], 1), round(p[1], 1)) for p in all_pts))
            if len(pts_s) < 3:
                continue
            def _cross(o, a, b):
                return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
            lo_h, hi_h = [], []
            for p in pts_s:
                while len(lo_h) >= 2 and _cross(lo_h[-2], lo_h[-1], p) <= 0:
                    lo_h.pop()
                lo_h.append(p)
            for p in reversed(pts_s):
                while len(hi_h) >= 2 and _cross(hi_h[-2], hi_h[-1], p) <= 0:
                    hi_h.pop()
                hi_h.append(p)
            hull = lo_h[:-1] + hi_h[:-1]
            if len(hull) < 4:
                continue
            hc = centroid(hull)
            padded = []
            for p in hull:
                vx, vy = p[0] - hc[0], p[1] - hc[1]
                L = math.hypot(vx, vy)
                if L > 1.0:
                    padded.append((p[0] + vx / L * 4.5, p[1] + vy / L * 4.5))
                else:
                    padded.append(p)
            hs = simplify_ring(padded, 4.0)
            if len(hs) >= 4 and 1200.0 <= abs(poly_area(hs)) <= 120000.0:
                res_polys.append((hs, ""))
                n_cc_added += 1
        print(f"Auto-clustered unnamed residential compounds (无名小区): +{n_cc_added} new clusters")

    name_idx = 0
    used_compound_names = defaultdict(int)
    for ring, raw_nm in res_polys:
        if len(compounds) >= 2800:
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
        # Assign authentic real Jiaxing residential compound name from OSM -> Google Maps survey
        # (with natural Chinese sub-zone suffixes when a large compound spans multiple gated blocks)
        real_nm, real_style = (raw_nm, None) if raw_nm else nearest_real_compound_name(c[0], c[1])
        if real_nm:
            used_cnt = used_compound_names[real_nm]
            used_compound_names[real_nm] = used_cnt + 1
            if used_cnt == 0:
                nm = real_nm
            else:
                suffixes = ("东区", "西区", "南区", "北区", "二期", "三期", "锦苑", "雅苑", "丽苑", "华庭", "新苑", "景苑")
                nm = f"{real_nm}·{suffixes[(used_cnt - 1) % len(suffixes)]}"
            g_style = real_style if real_style is not None else rng.randint(0, 2)
        else:
            nm = COMPOUND_NAMES_ZH[name_idx % len(COMPOUND_NAMES_ZH)]
            name_idx += 1
            g_style = rng.randint(0, 2)
        compounds.append({
            "_ring": shrunk,
            "name": nm,
            "segs": final_segs,
            "gate_pos": rnd((gx, gy)),
            "gate_angle": round(-math.atan2(gny, gnx) + math.pi * 0.5, 4),
            "style": g_style,
        })

    print(f"Chinese gated compounds: {len(compounds)} enclosed 小区 with perimeter walls, gatehouses & boom barriers")
    return compounds



def square_junction(graph_nodes, graph_edges, near, centre, drop_names_widths=()):
    """Turn a skewed junction into a square crossroads: move the node to `centre`, make every leg leave it along
    the nearest compass axis for 30 m before rejoining its own line beyond 40 m, and drop redundant parallel
    carriageways converging into it (given as (name, width))."""
    node = None
    for n in graph_nodes:
        if math.hypot(n["pos"][0] - near[0], n["pos"][1] - near[1]) < 4.0:
            node = n
            break
    if node is None:
        print("square_junction: no node near", near)
        return
    nid = node["id"]
    node["pos"] = [round(centre[0], 2), round(centre[1], 2)]
    keep = []
    for e in graph_edges:
        if nid not in (e["a"], e["b"]):
            keep.append(e)
            continue
        if any(e["name"] == nm and abs(float(e["width"]) - w) < 0.2 for nm, w in drop_names_widths):
            continue
        seq = list(e["pts"]) if e["a"] == nid else list(reversed(e["pts"]))
        far = None
        for q in seq[1:]:
            if math.hypot(q[0] - centre[0], q[1] - centre[1]) >= 40.0:
                far = q
                break
        if far is None:
            far = seq[-1]
        ang = math.atan2(far[1] - centre[1], far[0] - centre[0])
        ax = round(ang / (math.pi * 0.5)) * (math.pi * 0.5)
        ux, uy = math.cos(ax), math.sin(ax)
        rest = [q for q in seq[1:] if math.hypot(q[0] - centre[0], q[1] - centre[1]) >= 40.0]
        if not rest:
            rest = [seq[-1]]
        new_seq = [[round(centre[0], 2), round(centre[1], 2)], [round(centre[0] + ux * 30.0, 2), round(centre[1] + uy * 30.0, 2)]] + [list(q) for q in rest]
        e["pts"] = new_seq if e["a"] == nid else list(reversed(new_seq))
        e["length"] = round(sum(math.hypot(e["pts"][k + 1][0] - e["pts"][k][0], e["pts"][k + 1][1] - e["pts"][k][1]) for k in range(len(e["pts"]) - 1)), 1)
        keep.append(e)
    graph_edges[:] = keep
    print(f"square_junction: node {nid} squared at {centre}, {sum(1 for e in keep if nid in (e['a'], e['b']))} legs")


def merge_staggered_junctions(graph_nodes, graph_edges, max_gap=28.0, only_nodes=None):
    """Split OSM crossings (a divided road's two carriageway nodes, or a cross street meeting a road at two offset
    nodes) joined by a short crosswise stub make anything routed along the road -- T1 or a player's line -- hop
    sideways inside the junction. Where a named road leaves the two nodes in opposite directions and the stub runs
    across it, fold the nodes into one crossroads on that road's line, so a road reads straight through."""
    pos = {n["id"]: n["pos"] for n in graph_nodes}
    inc = defaultdict(list)
    for e in graph_edges:
        if not e.get("underground"):
            inc[e["a"]].append(e)
            inc[e["b"]].append(e)

    def far_pt(e, nid):
        seq = e["pts"] if e["a"] == nid else list(reversed(e["pts"]))
        o = seq[0]
        for q in seq[1:]:
            if math.hypot(q[0] - o[0], q[1] - o[1]) >= 40.0:
                return q
        return seq[-1]

    def unit(o, q):
        dx, dy = q[0] - o[0], q[1] - o[1]
        L = math.hypot(dx, dy)
        return (dx / L, dy / L) if L > 1e-6 else (0.0, 0.0)

    parent = {}

    def root(n):
        while parent.get(n, n) != n:
            n = parent[n]
        return n

    lines = defaultdict(list)  # merged group -> through-road far points (to put the node on that road's line)
    for c in graph_edges:
        if c.get("underground") or c.get("bridge"):
            continue
        a, b = c["a"], c["b"]
        if a == b or (only_nodes is not None and a not in only_nodes and b not in only_nodes):
            continue
        L = math.hypot(pos[b][0] - pos[a][0], pos[b][1] - pos[a][1])
        if L >= max_gap:
            continue
        u = ((pos[b][0] - pos[a][0]) / L, (pos[b][1] - pos[a][1]) / L)
        hit = None
        for ea in inc[a]:
            if ea is c or not ea.get("name"):
                continue
            fa = far_pt(ea, a)
            da = unit(pos[a], fa)
            if abs(da[0] * u[0] + da[1] * u[1]) > 0.5:
                continue
            for eb in inc[b]:
                if eb is c or eb is ea or eb.get("name") != ea.get("name"):
                    continue
                fb = far_pt(eb, b)
                db = unit(pos[b], fb)
                if da[0] * db[0] + da[1] * db[1] < -0.92:
                    hit = (fa, fb)
                    break
            if hit:
                break
        if not hit:
            continue
        ra, rb = root(a), root(b)
        if ra != rb:
            parent[rb] = ra
            lines[ra].extend(lines.pop(rb, []))
        lines[ra].append(hit)
    if not parent:
        return
    groups = defaultdict(list)
    for n in list(parent.keys()) + list({root(k) for k in parent}):
        groups[root(n)].append(n)
    new_pos = {}
    for r, mem in groups.items():
        mem = sorted(set(mem))
        groups[r] = mem
        mx = sum(pos[m][0] for m in mem) / len(mem)
        my = sum(pos[m][1] for m in mem) / len(mem)
        # snap onto the first through road's line (the straight run between its far points)
        fa, fb = lines[r][0]
        dx, dy = fb[0] - fa[0], fb[1] - fa[1]
        l2 = dx * dx + dy * dy
        if l2 > 1e-6:
            t = ((mx - fa[0]) * dx + (my - fa[1]) * dy) / l2
            mx, my = fa[0] + dx * t, fa[1] + dy * t
        new_pos[r] = [round(mx, 2), round(my, 2)]
    for n in graph_nodes:
        if n["id"] in new_pos:
            n["pos"] = new_pos[n["id"]]
    drop_nodes = {m for r, mem in groups.items() for m in mem if m != r}
    graph_nodes[:] = [n for n in graph_nodes if n["id"] not in drop_nodes]

    keep = []
    seen_pairs = {}
    for e in graph_edges:
        a2, b2 = root(e["a"]), root(e["b"])
        if a2 == b2 and (e["a"] != e["b"]):
            continue  # the stub inside the folded junction
        if a2 != e["a"] or b2 != e["b"] or a2 in new_pos or b2 in new_pos:
            pts = [list(q) for q in e["pts"]]
            if a2 in new_pos:
                c0 = new_pos[a2]
                while len(pts) > 2 and math.hypot(pts[1][0] - c0[0], pts[1][1] - c0[1]) < 15.0:
                    pts.pop(1)
                pts[0] = list(c0)
            if b2 in new_pos:
                c1 = new_pos[b2]
                while len(pts) > 2 and math.hypot(pts[-2][0] - c1[0], pts[-2][1] - c1[1]) < 15.0:
                    pts.pop(-2)
                pts[-1] = list(c1)
            e["pts"] = pts
            e["a"], e["b"] = a2, b2
            e["length"] = round(sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(pts) - 1)), 2)
        key = (min(a2, b2), max(a2, b2), e.get("name"))
        if key in seen_pairs and len(e["pts"]) == 2:
            prev = seen_pairs[key]
            if float(e["width"]) > float(prev["width"]):
                prev["width"] = e["width"]
            continue
        seen_pairs[key] = e
        keep.append(e)
    graph_edges[:] = keep
    print(f"staggered junctions: {len(groups)} folded into straight crossroads ({len(drop_nodes)} nodes merged)")


def straighten_through_nodes(graph_nodes, graph_edges, track_ids, max_dev=12.0, min_angle=165.0):
    """Where T1 carries straight on through a junction but the OSM node sits a few metres off the road's line
    (so the track snakes left-right inside the junction), move the node onto the straight line between the
    track's points ~30 m either side and drop the track edges' kinking shape points in between; the cross
    streets follow the node."""
    pos = {n["id"]: n for n in graph_nodes}
    inc = defaultdict(list)
    for e in graph_edges:
        inc[e["a"]].append(e)
        inc[e["b"]].append(e)
    moved = 0
    for nid, es in inc.items():
        tes = [e for e in es if e["id"] in track_ids and not e.get("underground")]
        if len(tes) != 2 or nid not in pos:
            continue
        P = pos[nid]["pos"]

        def far(e):
            seq = e["pts"] if e["a"] == nid else list(reversed(e["pts"]))
            for q in seq[1:]:
                if math.hypot(q[0] - P[0], q[1] - P[1]) >= 30.0:
                    return q
            return seq[-1]
        A, B = far(tes[0]), far(tes[1])
        ux, uy = A[0] - P[0], A[1] - P[1]
        vx, vy = B[0] - P[0], B[1] - P[1]
        la, lb = math.hypot(ux, uy), math.hypot(vx, vy)
        if la < 1e-6 or lb < 1e-6:
            continue
        ang = math.degrees(math.acos(max(-1.0, min(1.0, (ux * vx + uy * vy) / (la * lb)))))
        dx, dy = B[0] - A[0], B[1] - A[1]
        L2 = dx * dx + dy * dy
        t = ((P[0] - A[0]) * dx + (P[1] - A[1]) * dy) / L2
        Q = [A[0] + dx * t, A[1] + dy * t]
        dev = math.hypot(Q[0] - P[0], Q[1] - P[1])
        if ang < min_angle or dev < 0.8 or dev > max_dev:
            continue
        Q = [round(Q[0], 2), round(Q[1], 2)]
        pos[nid]["pos"] = Q
        for e in es:
            pts = [list(q) for q in e["pts"]]
            at_a = e["a"] == nid
            if not at_a:
                pts.reverse()
            keep_r = 30.0 if e in tes else 12.0
            stop = far(e) if e in tes else None
            out = [Q]
            dropping = True
            for q in pts[1:]:
                if dropping and len(pts) > 2 and q is not pts[-1] and (
                        (stop is not None and q != stop and math.hypot(q[0] - P[0], q[1] - P[1]) < keep_r) or
                        (stop is None and math.hypot(q[0] - P[0], q[1] - P[1]) < keep_r)):
                    continue
                dropping = False
                out.append(q)
            if not at_a:
                out.reverse()
            e["pts"] = out
            e["length"] = round(sum(math.hypot(out[k + 1][0] - out[k][0], out[k + 1][1] - out[k][1]) for k in range(len(out) - 1)), 2)
        moved += 1
    print(f"T1 through-junction kinks straightened: {moved}")


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
    unwedge_twin_carriageways(graph_edges, graph_nodes)
    widen_roads_by_class(graph_edges, nodes, ways)
    zhonghuan_side_roads(graph_edges)
    # 由拳路 × 庆丰路: the divided 由拳路 carriageways and the kinked 庆丰路 leg met in a skewed five-way Y where T1
    # turns south; rebuilt as a square crossroads (the parallel one-way carriageway is folded into the main road)
    square_junction(graph_nodes, graph_edges, (4216.26, 2577.23), (4208.5, 2564.0), drop_names_widths=[("由拳路", 8.8)])
    # Fold the split junctions T1 runs through (elsewhere a divided road keeps its carriageway box; player lines
    # are kept straight by the game's turn-aware track routing). A dry run of the route finds them.
    import copy
    _probe_edges = copy.deepcopy(graph_edges)
    _probe = build_t1_starter_network(copy.deepcopy(graph_nodes), _probe_edges)
    _pe = {e["id"]: e for e in _probe_edges}
    t1_nodes = set()
    for t in _probe.get("tracks", []):
        e = _pe.get(t["edge_id"])
        if e:
            t1_nodes.update((e["a"], e["b"]))
    merge_staggered_junctions(graph_nodes, graph_edges, only_nodes=t1_nodes)
    straighten_through_nodes(graph_nodes, graph_edges, {t["edge_id"] for t in _probe.get("tracks", [])})
    rail_crossings = build_rail_crossings(graph_edges, railways)

    road_grid = Grid(45.0)
    for e in graph_edges + SIDE_ROADS:
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

    # A divided road's bridge that starts inside the T1 corridor (中山东路 over the canal at 环城东路) ramps up
    # across the tracks; when its twin carriageway bridge runs alongside, fold the road onto the twin (wider,
    # both directions) and drop the one that crosses the corridor
    def _in_t1(px, py, pad):
        return any(seg_dist(px, py, ax, ay, bx, by)[0] < thw + pad for (ax, ay, bx, by, _dx, _dy, thw) in t1_surf_segs)
    n_fold = 0
    _vis_deg = defaultdict(int)
    for e in graph_edges:
        if not e.get("hide_road") and not e.get("underground"):
            _vis_deg[e["a"]] += 1
            _vis_deg[e["b"]] += 1
    for e in graph_edges:
        if not e.get("bridge") or e.get("hide_road") or e.get("underground"):
            continue
        a0, b0 = e["pts"][0], e["pts"][-1]
        # only the stray twin: its corridor end leads nowhere but hidden links (the kept bridge stays reachable)
        stray = (_in_t1(a0[0], a0[1], 4.0) and _vis_deg[e["a"]] <= 1) or (_in_t1(b0[0], b0[1], 4.0) and _vis_deg[e["b"]] <= 1)
        if not stray:
            continue
        L0 = math.hypot(b0[0] - a0[0], b0[1] - a0[1]) or 1.0
        for t in graph_edges:
            if t is e or not t.get("bridge") or t.get("hide_road") or t.get("name") != e.get("name"):
                continue
            a1, b1 = t["pts"][0], t["pts"][-1]
            L1 = math.hypot(b1[0] - a1[0], b1[1] - a1[1]) or 1.0
            cosang = abs(((b0[0] - a0[0]) * (b1[0] - a1[0]) + (b0[1] - a0[1]) * (b1[1] - a1[1])) / (L0 * L1))
            mx, my = (a0[0] + b0[0]) * 0.5, (a0[1] + b0[1]) * 0.5
            if cosang > 0.95 and seg_dist(mx, my, a1[0], a1[1], b1[0], b1[1])[0] < 32.0:
                e["hide_road"] = True
                e["lanes_f"] = 0
                e["lanes_b"] = 0
                t["width"] = max(float(t["width"]), 17.0)
                t["lanes_f"] = max(int(t.get("lanes_f", 1)), 2)
                t["lanes_b"] = max(int(t.get("lanes_b", 1)), 2)
                n_fold += 1
                break
    print(f"bridges folded off the T1 corridor: {n_fold}")
    # bridge ends in the T1 corridor get no extended approach ramp (the terrain would otherwise hump the road
    # back across the tram's junction)
    n_flat = 0
    t1_edge_ids = {t["edge_id"] for t in starter.get("tracks", [])}
    for e in graph_edges:
        if not e.get("bridge") or e.get("hide_road") or e.get("underground") or e["id"] in t1_edge_ids:
            continue
        for key, q in (("ramp_a", e["pts"][0]), ("ramp_b", e["pts"][-1])):
            if _in_t1(q[0], q[1], 8.0):
                e[key] = False
                n_flat += 1
    print(f"bridge ends kept flat at the T1 corridor: {n_flat}")

    # 机非隔离带: major non-tram roads get a 1.5 m planted buffer between the motor lanes and each non-motorised
    # lane. The OSM-derived 24 m section has no room for it (3 lanes + 2.05 m bike lane per side), so those roads
    # widen by the two buffers; a road gets one only where every motor lane still fits at >= 3.0 m (sims clamp the
    # half-width at 13.5 m)
    BUF = 1.5
    n_buf = 0
    for e in graph_edges:
        w0 = float(e["width"])
        if e.get("tram_median") or e.get("underground") or e.get("bridge") or w0 < 23.5:
            continue
        w1 = min(27.0, w0 + 2.0 * BUF) if w0 < 27.0 else w0
        hw = min(13.5, w1 * 0.5)
        lf, lb = int(e.get("lanes_f", 1)), int(e.get("lanes_b", 1))
        med = 0.8 if lf + lb >= 4 else 0.0
        room = hw - 2.05 - BUF - 1.15 - med
        if room < (max(lf, lb) - 0.5) * 3.0:
            continue
        e["width"] = round(w1, 1)
        e["bike_buffer"] = BUF
        n_buf += 1
    print(f"机非隔离带: {n_buf} major road edges with planted buffers")

    # Where T1 turns off a boulevard, the road carrying straight on across the junction keeps the boulevard's
    # width (in Jiaxing the cross-section does not halve at the turn); the widening runs along the straight chain to
    # the next real junction, and any OSM twin strip it swallows is hidden so the asphalt does not double up
    n_wide = n_wide_twin = 0
    vis_deg = defaultdict(int)
    for e in graph_edges:
        if not e.get("hide_road") and not e.get("underground"):
            vis_deg[e["a"]] += 1
            vis_deg[e["b"]] += 1
    at_node = defaultdict(list)
    for e in graph_edges:
        if e.get("hide_road") or e.get("underground") or len(e["pts"]) < 2:
            continue
        at_node[e["a"]].append(e)
        at_node[e["b"]].append(e)

    def _leave(e, n, reach=15.0):
        seq = e["pts"] if e["a"] == n else list(reversed(e["pts"]))
        ox, oy = seq[0]
        acc = 0.0
        for k in range(len(seq) - 1):
            ax, ay = seq[k]
            bx, by = seq[k + 1]
            acc += math.hypot(bx - ax, by - ay)
            if acc >= reach:
                break
        dx, dy = bx - ox, by - oy
        d = math.hypot(dx, dy)
        return (dx / d, dy / d) if d > 1e-6 else (0.0, 0.0)

    widened = set()
    wide_segs = []
    for te in graph_edges:
        if te["id"] not in t1_edge_ids or te.get("underground") or te.get("bridge"):
            continue
        tw = float(te["width"])
        for n in (te["a"], te["b"]):
            th = _leave(te, n)
            # only where the tram turns (or ends): along a straight T1 run a road leaving "straight on" is a twin
            others = [c for c in at_node[n] if c["id"] in t1_edge_ids and c is not te]
            if any(th[0] * _leave(c, n)[0] + th[1] * _leave(c, n)[1] < -0.87 for c in others):
                continue
            best, best_dot = None, -0.92
            for c in at_node[n]:
                if c["id"] in t1_edge_ids or c.get("bridge") or c["id"] in widened or "支路" in c["name"] \
                        or c["name"] != te["name"]:
                    continue
                ch = _leave(c, n)
                dot = th[0] * ch[0] + th[1] * ch[1]
                if dot < best_dot and float(c["width"]) < tw - 1.0:
                    best, best_dot = c, dot
            if best is None:
                continue
            # follow the straight chain through plain (degree-2) nodes, up to 650 m
            cur, node, run = best, n, 0.0
            while cur is not None and run < 650.0:
                widened.add(cur["id"])
                cur["width"] = tw
                cur["lanes_f"] = max(int(cur.get("lanes_f", 1)), 2 if tw >= 23.5 else 1)
                cur["lanes_b"] = max(int(cur.get("lanes_b", 1)), 2 if tw >= 23.5 else 1)
                cur["divided"] = False
                cur.pop("bike_buffer", None)
                run += float(cur.get("length", 0.0))
                p = cur["pts"]
                for k in range(len(p) - 1):
                    ax, ay = p[k]
                    bx, by = p[k + 1]
                    L = math.hypot(bx - ax, by - ay)
                    if L > 1.0:
                        wide_segs.append((ax, ay, bx, by, (bx - ax) / L, (by - ay) / L, tw * 0.5))
                n_wide += 1
                node = cur["b"] if cur["a"] == node else cur["a"]
                if vis_deg[node] != 2:
                    break
                nxt = [c for c in at_node[node] if c is not cur]
                cur = nxt[0] if nxt and nxt[0]["id"] not in t1_edge_ids and nxt[0]["id"] not in widened \
                    and not nxt[0].get("bridge") else None
    # twin strips now lying inside a widened road
    for e in graph_edges:
        if e["id"] in widened or e["id"] in t1_edge_ids or e.get("hide_road") or e.get("underground") or e.get("bridge"):
            continue
        p = e["pts"]
        L_e = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for k in range(len(p) - 1))
        if L_e < 12.0:
            continue
        inside = True
        for q in p:
            if not any(seg_dist(q[0], q[1], ax, ay, bx, by)[0] < hw - 0.5 for (ax, ay, bx, by, _dx, _dy, hw) in wide_segs):
                inside = False
                break
        if inside:
            e["hide_road"] = True
            e["lanes_f"] = 0
            e["lanes_b"] = 0
            n_wide_twin += 1
    t1_surf_segs = t1_surf_segs + wide_segs
    print(f"T1 turn continuations widened: {n_wide} edges, {n_wide_twin} twin strips hidden")

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
    nudged_t1_blds = 0
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
            # Only delete if the building's centroid itself sits inside the widened T1 boulevard!
            if any(seg_dist(cx, cy, ax, ay, bx, by)[0] < clr_r - 2.0 for (ax, ay, bx, by, clr_r) in cands):
                blocked = True
            else:
                # Otherwise gently pull any front-facing vertices behind the T1 sidewalk kerb (preserves all 沿街商铺 strips!)
                new_pts = []
                did_nudge = False
                for (px, py) in bpts:
                    nx_p, ny_p = float(px), float(py)
                    for (ax, ay, bx, by, clr_r) in cands:
                        dd, tt = seg_dist(nx_p, ny_p, ax, ay, bx, by)
                        if dd < clr_r - 0.6:
                            qx = ax + (bx - ax) * tt
                            qy = ay + (by - ay) * tt
                            vx, vy = nx_p - qx, ny_p - qy
                            vl = math.hypot(vx, vy)
                            if vl < 1e-4:
                                vx, vy = cx - qx, cy - qy
                                vl = math.hypot(vx, vy) or 1.0
                            push = (clr_r - 0.2) - dd
                            if push > 11.0:
                                blocked = True
                                break
                            nx_p += (vx / vl) * push
                            ny_p += (vy / vl) * push
                            did_nudge = True
                    if blocked:
                        break
                    new_pts.append(rnd((nx_p, ny_p)))
                if not blocked and did_nudge:
                    if abs(poly_area(new_pts)) < 24.0:
                        blocked = True
                    else:
                        b["pts"] = new_pts
                        b.pop("roof", None)
                        b.pop("yangfang", None)
                        nudged_t1_blds += 1
        if blocked:
            removed_t1_blds += 1
            continue
        cleaned_blds.append(b)
    blds = cleaned_blds
    if removed_t1_blds > 0 or nudged_t1_blds > 0:
        print(f"T1 corridor building clearance: nudged {nudged_t1_blds} 沿街商铺 strips behind kerb, removed {removed_t1_blds} deeply encroaching buildings")
        bld_grid = Grid(45.0)
        for b in blds:
            bpts = b["pts"]
            xs = [p[0] for p in bpts]
            ys = [p[1] for p in bpts]
            bld_grid.add((min(xs), min(ys), max(xs), max(ys), bpts), min(xs), min(ys), max(xs), max(ys))

    # Placeholder blocks the real streetscape does not have (中山东路 × 禾兴南路: the lot in front of the 钻石广场
    # tower and the row along the north edge of the 天主堂 park)
    DROP_BLD_BOXES = [(-830.0, -1000.0, -695.0, -925.0), (-656.0, -1012.0, -478.0, -985.0), (-600.0, -1012.0, -478.0, -962.0)]
    n_drop = len(blds)
    blds = [b for b in blds if not any(
        x0 < sum(p[0] for p in b["pts"]) / len(b["pts"]) < x1 and y0 < sum(p[1] for p in b["pts"]) / len(b["pts"]) < y1
        for (x0, y0, x1, y1) in DROP_BLD_BOXES)]
    if len(blds) != n_drop:
        print(f"dropped {n_drop - len(blds)} placeholder buildings by hand")
        bld_grid = Grid(45.0)
        for b in blds:
            bpts = b["pts"]
            xs = [p[0] for p in bpts]
            ys = [p[1] for p in bpts]
            bld_grid.add((min(xs), min(ys), max(xs), max(ys), bpts), min(xs), min(ys), max(xs), max(ys))

    # Append Hanlin Residence towers + authentic south 沿街商业 buildings BEFORE build_street_furniture()
    # so the Hanlin south commercial buildings facing 纺工路 & 中环南路 receive continuous wall-to-wall storefronts!
    for hb in hanlin_tower_buildings():
        blds.append(hb)
        hxs = [q[0] for q in hb["pts"]]
        hys = [q[1] for q in hb["pts"]]
        bld_grid.add((min(hxs), min(hys), max(hxs), max(hys), hb["pts"]), min(hxs), min(hys), max(hxs), max(hys))
    resolve_parallel_overlaps(graph_edges, t1_edge_ids)
    roads, cws, lamps, trees, storefronts = build_street_furniture(
        graph_edges, graph_nodes, blds, poi_nodes, nodes, road_grid, water_grid, rail_grid, bld_grid, freeway_grid, raw_islands
    )
    apply_t1_survey(blds, storefronts, road_grid, bld_grid)
    gated_compounds = build_gated_compounds(landuse_zones, ways, nodes, road_grid, water_grid, rail_grid, bld_grid, park_grid)

    # 底商 face the street from OUTSIDE the compound: wherever a compound fence would pass in front of a building
    # with shopfronts (within 12 m of its street side), the fence is cut there and the shop building itself forms
    # the compound edge — the fence runs on behind / between the buildings
    # (a corner building has shops on two faces: keep every distinct facing, not just the first)
    shop_dir = defaultdict(list)
    for sf in storefronts:
        bi = int(sf.get("b", -1))
        if bi < 0:
            continue
        nv = sf["n"]
        if all(nv[0] * o[0] + nv[1] * o[1] < 0.9 for o in shop_dir[bi]):
            shop_dir[bi].append(nv)
    shop_grid = Grid(40.0)
    for bi, nvs in shop_dir.items():
        bp = blds[bi]["pts"]
        xs = [q[0] for q in bp]
        ys = [q[1] for q in bp]
        for nv in nvs:
            shop_grid.add((bp, nv), min(xs) - 13, min(ys) - 13, max(xs) + 13, max(ys) + 13)

    def in_front_of_shop(px, py):
        for (bp, nv) in shop_grid.query(px, py, px, py):
            for t in (0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0):
                if point_in_poly(px - nv[0] * t, py - nv[1] * t, bp):
                    return True
        return False

    # Build an exact surface-road spatial index matching Godot's rendered widths (clamped to [3.2, 22.0])
    # so EVERY 1.0m of compound fence & EVERY gatehouse footprint is guaranteed strictly clear of ALL road asphalt & curbs!
    final_road_grid = Grid(40.0)
    for r_e in graph_edges:
        if r_e.get("underground") or int(r_e.get("layer", 0)) != 0:
            continue
        rhw_e = max(3.2, min(22.0, float(r_e.get("width", 12.0)) * 0.5))
        rpts_e = r_e.get("pts", [])
        for ri_e in range(len(rpts_e) - 1):
            ax_e, ay_e = float(rpts_e[ri_e][0]), float(rpts_e[ri_e][1])
            bx_e, by_e = float(rpts_e[ri_e + 1][0]), float(rpts_e[ri_e + 1][1])
            pad_e = rhw_e + 6.0
            final_road_grid.add((ax_e, ay_e, bx_e, by_e, rhw_e),
                                min(ax_e, bx_e) - pad_e, min(ay_e, by_e) - pad_e,
                                max(ax_e, bx_e) + pad_e, max(ay_e, by_e) + pad_e)

    def fence_pt_hits_road_or_rail(px, py, margin=2.2):
        # Hanlin Residence SE commercial plaza & parking forecourt (x >= 1352, y in 1435..1605):
        # residential compound fence along 中环南路 MUST stop cleanly at the west edge of 瀚林商业广场 (never cross to 纺工路!)
        if px >= 1351.0 and 1435.0 <= py <= 1605.0 and px <= 1445.0:
            return True
        for (rax, ray, rbx, rby, rhw) in final_road_grid.query(px - 2, py - 2, px + 2, py + 2):
            if seg_dist(px, py, rax, ray, rbx, rby)[0] < rhw + margin:
                return True
        for (rax, ray, rbx, rby, rw) in rail_grid.query(px - 2, py - 2, px + 2, py + 2):
            if seg_dist(px, py, rax, ray, rbx, rby)[0] < rw + 1.2:
                return True
        return False

    cut_m = 0.0
    road_cut_m = 0.0
    n_gate_moved, n_gate_dropped = 0, 0
    for comp in gated_compounds:
        new_segs = []
        for (sa, sb) in comp["segs"]:
            L = math.hypot(sb[0] - sa[0], sb[1] - sa[1])
            n = max(1, int(L / 1.0))
            run_start = None
            for k in range(n + 1):
                f = k / n
                px, py = sa[0] + (sb[0] - sa[0]) * f, sa[1] + (sb[1] - sa[1]) * f
                hit_shop = in_front_of_shop(px, py)
                hit_rd = fence_pt_hits_road_or_rail(px, py, 2.2)
                keep = (not hit_shop) and (not hit_rd)
                if keep and run_start is None:
                    run_start = f
                if (not keep or k == n) and run_start is not None:
                    f_end = f if keep else max(run_start, (k - 1) / n)
                    a = (sa[0] + (sb[0] - sa[0]) * run_start, sa[1] + (sb[1] - sa[1]) * run_start)
                    b = (sa[0] + (sb[0] - sa[0]) * f_end, sa[1] + (sb[1] - sa[1]) * f_end)
                    if math.hypot(b[0] - a[0], b[1] - a[1]) >= 2.2:
                        new_segs.append([rnd(a), rnd(b)])
                    run_start = None
                if hit_shop:
                    cut_m += L / n
                elif hit_rd:
                    road_cut_m += L / n
        comp["segs"] = new_segs
        # the gatehouse must not stand in front of shops OR encroach onto any widened road/curb:
        gp = comp.get("gate_pos", [])
        if len(gp) == 2:
            gx0, gy0 = gp
            near_shop = in_front_of_shop(gx0, gy0) or any(
                math.hypot(q[0] - gx0, q[1] - gy0) < 9.0 for (bp, _nv) in shop_grid.query(gx0 - 9, gy0 - 9, gx0 + 9, gy0 + 9) for q in bp)
            gate_on_road = fence_pt_hits_road_or_rail(gx0, gy0, 2.6)
            if near_shop or gate_on_road:
                n_gate_moved += 1
                ring = comp.get("_ring") or []
                cx_c, cy_c = centroid(ring) if len(ring) >= 3 else (gx0, gy0)
                best = None
                for si, (sa, sb) in enumerate(new_segs):
                    L = math.hypot(sb[0] - sa[0], sb[1] - sa[1])
                    if L < 11.0:
                        continue
                    ux, uy = (sb[0] - sa[0]) / L, (sb[1] - sa[1]) / L
                    mx, my = (sa[0] + sb[0]) * 0.5, (sa[1] + sb[1]) * 0.5
                    nx, ny = -uy, ux
                    if (mx - cx_c) * nx + (my - cy_c) * ny < 0.0:
                        nx, ny = -nx, -ny  # outward
                    if in_front_of_shop(mx, my):
                        continue
                    # gatehouse footprint (13 m canopy, 3.3 m inside .. 2.6 m outside the fence) clear of buildings & roads!
                    clear = True
                    probes = [(mx + ux * a + nx * b, my + uy * a + ny * b) for a in (-6.6, -4.4, -2.2, 0.0, 2.2, 4.4, 6.6) for b in (-3.3, 0.0, 2.6)]
                    if any(fence_pt_hits_road_or_rail(fx, fy, 2.0) for (fx, fy) in probes):
                        continue
                    for ob in bld_grid.query(mx - 10, my - 10, mx + 10, my + 10):
                        if any(point_in_poly(fx, fy, ob[4]) for (fx, fy) in probes):
                            clear = False
                            break
                    if not clear:
                        continue
                    d_road = 1e9
                    for (rax, ray, rbx, rby, rhw) in final_road_grid.query(mx - 40, my - 40, mx + 40, my + 40):
                        d_road = min(d_road, seg_dist(mx + nx * 2.0, my + ny * 2.0, rax, ray, rbx, rby)[0] - rhw)
                    if d_road < 2.2 or d_road > 45.0:
                        continue
                    if best is None or d_road < best[0]:
                        best = (d_road, si, mx, my, ux, uy, nx, ny, sa, sb)
                if best is None:
                    comp["gate_pos"] = []
                    n_gate_dropped += 1
                else:
                    _d, si, mx, my, ux, uy, nx, ny, sa, sb = best
                    pieces = []
                    a2 = (mx - ux * 5.6, my - uy * 5.6)
                    b2 = (mx + ux * 5.6, my + uy * 5.6)
                    if math.hypot(a2[0] - sa[0], a2[1] - sa[1]) >= 2.2:
                        pieces.append([rnd(sa), rnd(a2)])
                    if math.hypot(sb[0] - b2[0], sb[1] - b2[1]) >= 2.2:
                        pieces.append([rnd(b2), rnd(sb)])
                    comp["segs"] = new_segs[:si] + pieces + new_segs[si + 1:]
                    comp["gate_pos"] = rnd((mx, my))
                    comp["gate_angle"] = round(-math.atan2(ny, nx) + math.pi * 0.5, 4)
    print(f"底商 & road-clearance compound audit: {cut_m / 1000.0:.1f} km cut for shops, "
          f"{road_cut_m / 1000.0:.2f} km cut off roads/curbs; "
          f"{n_gate_moved} gatehouses relocated ({n_gate_dropped} dropped)")

    # 小区绿化: the courtyard of every gated compound is landscaped lawn (buildings stand on it) with trees in the
    # gaps between blocks. A lawn is only laid where its whole outline keeps clear of roads, rail, water and other
    # mapped areas (no coplanar overlaps); it is a plain lawn layer, not a detailed park
    area_grid = Grid(120.0)
    for a in areas:
        if a.get("kind") == "water":
            continue
        axs = [q[0] for q in a["pts"]]
        ays = [q[1] for q in a["pts"]]
        area_grid.add((min(axs), min(ays), max(axs), max(ays)), min(axs), min(ays), max(axs), max(ays))
    n_lawn, n_ctree = 0, 0
    rng_cg = random.Random(20261124)
    for comp in gated_compounds:
        ring = comp.pop("_ring", None)
        if not ring or len(ring) < 3:
            continue
        c = centroid(ring)
        lawn = []
        for q in ring:
            vx, vy = q[0] - c[0], q[1] - c[1]
            L = math.hypot(vx, vy)
            lawn.append((q[0] - vx / L * 1.0, q[1] - vy / L * 1.0) if L > 3.0 else q)
        xs = [q[0] for q in lawn]
        ys = [q[1] for q in lawn]
        bb = (min(xs), min(ys), max(xs), max(ys))
        ok = not any(not (o[2] < bb[0] or o[0] > bb[2] or o[3] < bb[1] or o[1] > bb[3])
                     for o in area_grid.query(bb[0], bb[1], bb[2], bb[3]))
        if ok:
            for i in range(len(lawn)):
                a0, a1 = lawn[i], lawn[(i + 1) % len(lawn)]
                L = math.hypot(a1[0] - a0[0], a1[1] - a0[1])
                n = max(1, int(L / 5.0))
                for k in range(n + 1):
                    px = a0[0] + (a1[0] - a0[0]) * k / n
                    py = a0[1] + (a1[1] - a0[1]) * k / n
                    for (rax, ray, rbx, rby, rhw) in road_grid.query(px - 16, py - 16, px + 16, py + 16):
                        if seg_dist(px, py, rax, ray, rbx, rby)[0] < rhw + 1.0:
                            ok = False
                            break
                    if ok:
                        for (rax, ray, rbx, rby, rw) in rail_grid.query(px - 16, py - 16, px + 16, py + 16):
                            if seg_dist(px, py, rax, ray, rbx, rby)[0] < rw:
                                ok = False
                                break
                    if ok:
                        for wp in water_grid.query(px - 2, py - 2, px + 2, py + 2):
                            if point_in_poly(px, py, wp):
                                ok = False
                                break
                    if not ok:
                        break
                if not ok:
                    break
        if not ok:
            continue
        areas.append({"kind": "compound_green", "pts": [rnd(q) for q in lawn]})
        area_grid.add(bb, bb[0], bb[1], bb[2], bb[3])
        n_lawn += 1
        # trees between the blocks (香樟 / 桂花 / 银杏 groups), clear of every building by 4.5 m
        cnt = 0
        gy = bb[1] + 7.0
        while gy < bb[3] - 6.0 and cnt < 18:
            gx = bb[0] + 7.0 + rng_cg.uniform(-2.0, 2.0)
            while gx < bb[2] - 6.0 and cnt < 18:
                tx, ty = gx + rng_cg.uniform(-2.5, 2.5), gy + rng_cg.uniform(-2.5, 2.5)
                if point_in_poly(tx, ty, lawn):
                    clear = True
                    for ob in bld_grid.query(tx - 6, ty - 6, tx + 6, ty + 6):
                        if ob[0] - 4.5 <= tx <= ob[2] + 4.5 and ob[1] - 4.5 <= ty <= ob[3] + 4.5:
                            clear = False
                            break
                    if clear and rng_cg.random() < 0.7:
                        trees.append([round(tx, 2), round(ty, 2)])
                        cnt += 1
                        n_ctree += 1
                gx += 12.0
            gy += 12.0
    print(f"小区绿化: {n_lawn} landscaped compound lawns, {n_ctree} courtyard trees")

    # Classify open unbuilt plots via Google Earth z16 satellite RGB into REAL Farmland (农田),
    # REAL Active Construction Sites (在建工地), and urban vacant rough grass!
    def _in_south_plaza(qx, qy):
        dx_s = qx - SOUTH_STA_POS[0]
        dy_s = qy - SOUTH_STA_POS[1]
        ca_s, sa_s = math.cos(0.4925), math.sin(0.4925)
        lx_s = dx_s * ca_s - dy_s * sa_s
        lz_s = dx_s * sa_s + dy_s * ca_s
        return -245.0 <= lx_s <= 278.0 and -368.0 <= lz_s <= 85.0

    CELL = 50.0
    n_vac = 0
    n_ge_farm = 0
    ge_const_cells = []   # (cx, cy, r0)
    farm_gh_cands = []    # (cx, cy, area_m2)
    # Seed greenhouse candidates from real OSM farmland polygons first
    for a_item in areas:
        if a_item.get("kind") == "farmland":
            apts = [(float(p[0]), float(p[1])) for p in a_item.get("pts", [])]
            if len(apts) >= 3:
                aa = abs(poly_area(apts))
                if aa >= 2600.0:
                    acx, acy = centroid(apts)
                    if not in_zhonghuan(acx, acy) and not _in_south_plaza(acx, acy) and not in_airport_precinct((acx, acy)):
                        farm_gh_cands.append((acx, acy, aa))

    bx0, by0, bx1, by1 = BOUNDS
    gy = by0
    while gy < by1:
        gx = bx0
        while gx < bx1:
            cx, cy = gx + CELL * 0.5, gy + CELL * 0.5
            gx += CELL
            if not in_active((cx, cy), -30.0) or _in_south_plaza(cx, cy) or in_airport_precinct((cx, cy)):
                continue
            r0 = (cx - CELL * 0.5, cy - CELL * 0.5, cx + CELL * 0.5, cy + CELL * 0.5)
            if any(not (o[2] < r0[0] - 10 or o[0] > r0[2] + 10 or o[3] < r0[1] - 10 or o[1] > r0[3] + 10)
                   for o in bld_grid.query(r0[0] - 12, r0[1] - 12, r0[2] + 12, r0[3] + 12)):
                continue
            if any(not (o[2] < r0[0] or o[0] > r0[2] or o[3] < r0[1] or o[1] > r0[3])
                   for o in area_grid.query(r0[0], r0[1], r0[2], r0[3])):
                continue
            near = False
            for (rax, ray, rbx, rby, rhw) in road_grid.query(cx - 56, cy - 56, cx + 56, cy + 56):
                if seg_dist(cx, cy, rax, ray, rbx, rby)[0] < rhw + 2.5 + CELL * 0.54:
                    near = True
                    break
            if not near:
                for (rax, ray, rbx, rby, rw) in rail_grid.query(cx - 56, cy - 56, cx + 56, cy + 56):
                    if seg_dist(cx, cy, rax, ray, rbx, rby)[0] < rw + CELL * 0.54:
                        near = True
                        break
            if not near:
                for (fax, fay, fbx, fby, fhw) in freeway_grid.query(cx - 65, cy - 65, cx + 65, cy + 65):
                    if seg_dist(cx, cy, fax, fay, fbx, fby)[0] < fhw + 4.0 + CELL * 0.54:
                        near = True
                        break
            if not near:
                for wp in water_grid.query(r0[0] - 2, r0[1] - 2, r0[2] + 2, r0[3] + 2):
                    if any(point_in_poly(qx, qy, wp) for qx, qy in ((cx, cy), (r0[0], r0[1]), (r0[2], r0[1]), (r0[2], r0[3]), (r0[0], r0[3]))):
                        near = True
                        break
            if near or in_zs_rect(cx, cy) or in_nh_rect(cx, cy):
                continue
            sq_pts = [(r0[0], r0[1]), (r0[2], r0[1]), (r0[2], r0[3]), (r0[0], r0[3])]
            pcls = GE_SAMPLER.classify_open_plot(sq_pts) if GE_SAMPLER.available else "vacant"
            if pcls == "farmland" and not in_zhonghuan(cx, cy):
                areas.append({"kind": "farmland", "pts": [rnd(p) for p in sq_pts]})
                n_ge_farm += 1
                farm_gh_cands.append((cx, cy, CELL * CELL))
                if rng_cg.random() < 0.18:
                    trees.append([round(r0[0] + rng_cg.uniform(2.0, 6.0), 2), round(r0[1] + rng_cg.uniform(2.0, 6.0), 2)])
            elif pcls == "construction":
                ge_const_cells.append((cx, cy, r0))
            else:
                areas.append({"kind": "vacant_green", "pts": [rnd(p) for p in sq_pts]})
                n_vac += 1
                for _t in range(rng_cg.choice([0, 0, 1, 1, 2, 3])):
                    trees.append([round(cx + rng_cg.uniform(-20.0, 20.0), 2), round(cy + rng_cg.uniform(-20.0, 20.0), 2)])
        gy += CELL

    # --- Build REAL 3D Construction Sites (OSM landuse=construction + Google Earth bare-earth clusters) ---
    construction_sites = []
    used_const_centers = []

    def _const_clear(ccx, ccy, ring):
        if not in_active((ccx, ccy), -25.0) or _in_south_plaza(ccx, ccy) or in_airport_precinct((ccx, ccy)):
            return False
        if any(math.hypot(ccx - ox, ccy - oy) < 72.0 for ox, oy in used_const_centers):
            return False
        if any(point_in_poly(ccx, ccy, wp) for wp in water_grid.query(ccx - 6, ccy - 6, ccx + 6, ccy + 6)):
            return False
        if any(point_in_poly(ccx, ccy, pp) for pp in park_grid.query(ccx - 6, ccy - 6, ccx + 6, ccy + 6)):
            return False
        # Do not place construction on top of existing real buildings OR overlapping any road asphalt/curb!
        xs_c = [p[0] for p in ring]
        ys_c = [p[1] for p in ring]
        hit_b = sum(1 for ob in bld_grid.query(min(xs_c), min(ys_c), max(xs_c), max(ys_c)) if point_in_poly(*centroid(ob[4]), ring))
        if hit_b > 1:
            return False
        for ci_r in range(len(ring)):
            pa_r = ring[ci_r]
            pb_r = ring[(ci_r + 1) % len(ring)]
            el_r = math.hypot(pb_r[0] - pa_r[0], pb_r[1] - pa_r[1])
            n_st = max(2, int(el_r / 3.0) + 1)
            for k_r in range(n_st + 1):
                tf = k_r / n_st
                px_r = pa_r[0] + (pb_r[0] - pa_r[0]) * tf
                py_r = pa_r[1] + (pb_r[1] - pa_r[1]) * tf
                if fence_pt_hits_road_or_rail(px_r, py_r, 2.0):
                    return False
        return True

    # Source 1: Real OSM landuse=construction / building=construction polygons
    for wid, (refs, t) in ways.items():
        if (t.get("landuse") == "construction" or t.get("building") == "construction") and len(refs) >= 4 and refs[0] == refs[-1]:
            pts_c = [nodes[r] for r in refs if r in nodes][:-1]
            ring_c = simplify_ring(pts_c, 3.0)
            if len(ring_c) < 3:
                continue
            ac = abs(poly_area(ring_c))
            if ac < 1200.0 or ac > 120000.0:
                continue
            ccx, ccy = centroid(ring_c)
            if not _const_clear(ccx, ccy, ring_c):
                continue
            oc = obb(ring_c)
            if oc is None:
                continue
            construction_sites.append({
                "pts": [rnd(p) for p in ring_c],
                "c": rnd((oc[0], oc[1])),
                "a": round(oc[2], 4),
                "hl": round(min(oc[3], 95.0), 1),
                "hw": round(min(oc[4], 65.0), 1),
                "name": t.get("name", "在建工程项目"),
            })
            used_const_centers.append((ccx, ccy))

    # Source 2: Group adjacent Google Earth bare-earth 50m cells into cohesive multi-cell active construction sites
    if ge_const_cells:
        c_parent = list(range(len(ge_const_cells)))
        def cf_find(i):
            while c_parent[i] != i:
                c_parent[i] = c_parent[c_parent[i]]
                i = c_parent[i]
            return i
        for i in range(len(ge_const_cells)):
            xi, yi, _ = ge_const_cells[i]
            for j in range(i + 1, len(ge_const_cells)):
                xj, yj, _ = ge_const_cells[j]
                if abs(xi - xj) <= 55.0 and abs(yi - yj) <= 55.0:
                    ri, rj = cf_find(i), cf_find(j)
                    if ri != rj:
                        c_parent[ri] = rj
        c_groups = defaultdict(list)
        for i in range(len(ge_const_cells)):
            c_groups[cf_find(i)].append(ge_const_cells[i])
        # Sort by largest contiguous bare-earth area; promote up to 120 real Google Earth active sites (incl. standalone >= 2500 m² urban sites!)
        ranked = sorted(c_groups.values(), key=len, reverse=True)
        promoted_cells = set()
        for grp in ranked:
            if len(construction_sites) >= 120:
                break
            if len(grp) < 1:
                continue
            gx0 = min(item[2][0] for item in grp)
            gy0 = min(item[2][1] for item in grp)
            gx1 = max(item[2][2] for item in grp)
            gy1 = max(item[2][3] for item in grp)
            hl_c = min((gx1 - gx0) * 0.5, 85.0)
            hw_c = min((gy1 - gy0) * 0.5, 60.0)
            ccx = (gx0 + gx1) * 0.5
            ccy = (gy0 + gy1) * 0.5
            rect_c = [(ccx - hl_c, ccy - hw_c), (ccx + hl_c, ccy - hw_c), (ccx + hl_c, ccy + hw_c), (ccx - hl_c, ccy + hw_c)]
            # If bounding box touches a road edge, inset gently up to 2 steps so the construction hoarding stays 100% off asphalt!
            ok_c = _const_clear(ccx, ccy, rect_c)
            if not ok_c and hl_c >= 22.0 and hw_c >= 22.0:
                for shrink_f in (0.86, 0.74):
                    hl_s, hw_s = hl_c * shrink_f, hw_c * shrink_f
                    rect_s = [(ccx - hl_s, ccy - hw_s), (ccx + hl_s, ccy - hw_s), (ccx + hl_s, ccy + hw_s), (ccx - hl_s, ccy + hw_s)]
                    if _const_clear(ccx, ccy, rect_s):
                        hl_c, hw_c, rect_c = hl_s, hw_s, rect_s
                        ok_c = True
                        break
            if ok_c:
                ang_c = 0.0 if hl_c >= hw_c else math.pi * 0.5
                construction_sites.append({
                    "pts": [rnd(p) for p in rect_c],
                    "c": rnd((ccx, ccy)),
                    "a": round(ang_c, 4),
                    "hl": round(max(hl_c, hw_c), 1),
                    "hw": round(min(hl_c, hw_c), 1),
                    "name": "嘉兴在建工地",
                })
                used_const_centers.append((ccx, ccy))
                for item in grp:
                    promoted_cells.add((item[0], item[1]))
        # Any un-promoted bare-earth cell falls back cleanly to vacant_green
        for cx_u, cy_u, r0_u in ge_const_cells:
            if (cx_u, cy_u) not in promoted_cells:
                areas.append({"kind": "vacant_green", "pts": [rnd((r0_u[0], r0_u[1])), rnd((r0_u[2], r0_u[1])), rnd((r0_u[2], r0_u[3])), rnd((r0_u[0], r0_u[3]))]})
                n_vac += 1

    # --- Place neat Jiangnan vegetable polytunnel greenhouses (蔬菜大棚) on ~28 well-spaced real farmland plots ---
    farmland_greenhouses = []
    gh_centers = []
    farm_gh_cands.sort(key=lambda it: -it[2])
    for fcx, fcy, _faa in farm_gh_cands:
        if len(farmland_greenhouses) >= 32:
            break
        if any(math.hypot(fcx - ox, fcy - oy) < 185.0 for ox, oy in gh_centers):
            continue
        if any(math.hypot(fcx - ox, fcy - oy) < 120.0 for ox, oy in used_const_centers):
            continue
        # Ensure greenhouse cluster footprint (~42m x 36m) is completely clear of buildings, roads, rail & water
        if any(True for _ in bld_grid.query(fcx - 26, fcy - 26, fcx + 26, fcy + 26)):
            continue
        if any(seg_dist(fcx, fcy, rax, ray, rbx, rby)[0] < rhw + 26.0 for (rax, ray, rbx, rby, rhw) in road_grid.query(fcx - 45, fcy - 45, fcx + 45, fcy + 45)):
            continue
        if any(point_in_poly(fcx, fcy, wp) for wp in water_grid.query(fcx - 24, fcy - 24, fcx + 24, fcy + 24)):
            continue
        farmland_greenhouses.append({
            "c": rnd((fcx, fcy)),
            "a": round(rng_cg.choice([0.08, 0.14, 0.22, -0.06, 1.52]), 3),
            "n": rng_cg.choice([3, 4, 5]),
            "len": round(rng_cg.uniform(26.0, 38.0), 1),
        })
        gh_centers.append((fcx, fcy))

    # Strip any stray street/vacant trees that fall inside active construction site pads!
    if construction_sites:
        cs_polys = [[(float(p[0]), float(p[1])) for p in s["pts"]] for s in construction_sites]
        cs_bbs = [(min(p[0] for p in r), min(p[1] for p in r), max(p[0] for p in r), max(p[1] for p in r), r) for r in cs_polys]
        trees = [
            t for t in trees
            if not any(b0 <= t[0] <= b2 and b1 <= t[1] <= b3 and point_in_poly(t[0], t[1], r) for (b0, b1, b2, b3, r) in cs_bbs)
        ]

    n_osm_farm = sum(1 for a_it in areas if a_it.get("kind") == "farmland") - n_ge_farm
    print(f"农田与在建工地: {n_osm_farm} OSM + {n_ge_farm} Google Earth farmland plots, "
          f"{len(farmland_greenhouses)} 蔬菜大棚 clusters, {len(construction_sites)} 3D construction sites, {n_vac} vacant plots")

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
        {"pos": rnd((437.0, -680.0)), "angle": 0.0, "span": 62.0},            # 北湖小岛东连岸人行步桥
        {"pos": rnd((380.0, -740.0)), "angle": 1.5708, "span": 68.0},         # 北湖小岛北连岸人行步桥
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
            # Lake islands are dry land strictly inside water polygons!
            if any(point_in_poly(px, py, ir) for ir in raw_islands):
                continue
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
        # North Lake Scenic Island (#353, center ~399,-634): twin footbridge approaches + complete 环岛步道 loop + spine path!
        ("timber", 3.6, [(380, -778), (380, -706)]),
        ("timber", 3.6, [(468, -680), (402, -680)]),
        ("stone", 3.0, [(380, -706), (395, -688), (408, -634), (425, -595), (424, -568), (412, -571), (386, -619), (368, -677), (371, -698), (380, -706)]),
        ("stone", 2.8, [(380, -706), (386, -672), (398, -634), (414, -592), (420, -569)]),
        # Xiangjiadang Wetland Park lush dry-shore circular walking trails & lakefront greenway!
        ("greenway", 4.0, [(4520, -5620), (4640, -5420), (4710, -5180), (4700, -4920), (4640, -4680), (4820, -4480)]),
        ("stone", 3.2, [(4710, -5180), (4560, -5180), (4560, -4960), (4700, -4920)]),
        ("timber", 3.4, [(4820, -4480), (5180, -4380), (5620, -4380), (6100, -4420), (6420, -4720), (6440, -5280), (6360, -5920)]),
        ("greenway", 3.8, [(4640, -5420), (4760, -5920), (5060, -6340), (5580, -6380), (6120, -6320), (6360, -5920)]),
    ]
    for kind_c, w_c, cpts in curated_paths:
        scenic_paths.append({"kind": kind_c, "w": w_c, "pts": [rnd(p) for p in cpts]})

    # Curated Jiangnan Lakeside & Urban Park Scenic Gazebos (verified strictly on dry land!)
    gazebo_cands = [
        (-215.0, -120.0),  # 揽秀园望塔亭
        (-85.0, -250.0),   # 壕股北岸亭
        (-265.0, -245.0),  # 伍相祠园亭
        (-330.0, -10.0),   # 西南湖观荷亭
        (-240.0, 160.0),   # 揽秀园南林亭
        (680.0, 430.0),    # 南湖东南观湖亭
        (780.0, 260.0),    # 会景园南亭
        (560.0, 455.0),    # 南湖纪念馆东亭
        (420.0, 475.0),    # 南湖革命广场亭
        (105.0, -1385.0),  # 人民公园翠湖亭
        (120.0, -1455.0),  # 人民公园林荫亭
        (386.0, -672.0),   # 北湖小岛北观景凉亭
        (414.0, -592.0),   # 北湖小岛南水岸凉亭
        (985.0, 2980.0),   # 中央公园东亭
        (1165.0, 3110.0),  # 中央公园南亭
        (1020.0, 3150.0),  # 中央公园西亭
        (4660.0, -5440.0), # 湘家荡西岸亭
        (4680.0, -4820.0), # 湘家荡北林亭
        (5320.0, -4360.0), # 湘家荡望湖亭
        (6410.0, -5120.0), # 湘家荡东湿地亭
        (5560.0, -6370.0), # 湘家荡南荷风亭
        (5020.0, -6310.0), # 湘家荡荷塘月色亭
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
    # 月河 canal banks: water-polygon edges inside the quarter, with the direction toward the water, and whether
    # houses stand right behind them (those stretches get the covered waterside arcade, 廊棚)
    YH_RECT = (-905.0, -2275.0, -375.0, -1845.0)
    yh_hgrid = Grid(30.0)
    for hh in YH_HOUSES:
        yh_hgrid.add(hh, hh["c"][0] - 8, hh["c"][1] - 8, hh["c"][0] + 8, hh["c"][1] + 8)
    yh_banks = []
    for wp in water_polys:
        for i in range(len(wp)):
            a = wp[i]
            b = wp[(i + 1) % len(wp)]
            mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            if not (YH_RECT[0] <= mx <= YH_RECT[2] and YH_RECT[1] <= my <= YH_RECT[3]):
                continue
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            if L < 2.0:
                continue
            nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
            if not point_in_poly(mx + nx * 0.8, my + ny * 0.8, wp):
                nx, ny = -nx, -ny
            if not point_in_poly(mx + nx * 0.8, my + ny * 0.8, wp):
                continue
            lx, ly = mx - nx * 7.0, my - ny * 7.0
            arcade = any(math.hypot(hh["c"][0] - lx, hh["c"][1] - ly) < 7.5 for hh in yh_hgrid.query(lx - 8, ly - 8, lx + 8, ly + 8))
            yh_banks.append({"a": rnd(a), "b": rnd(b), "w": [round(nx, 3), round(ny, 3)], "arc": arcade})
    yh_paifang = {}
    if YH_ALLEYS:
        longest = max(YH_ALLEYS, key=lambda sgm: math.hypot(sgm[1][0] - sgm[0][0], sgm[1][1] - sgm[0][1]))
        (pa0, pa1), (pb0, pb1) = longest
        Lp = max(1e-6, math.hypot(pb0 - pa0, pb1 - pa1))
        yh_paifang = {"pos": rnd((pa0 + (pb0 - pa0) * 4.0 / Lp, pa1 + (pb1 - pa1) * 4.0 / Lp)),
                      "angle": round(-math.atan2(pb1 - pa1, pb0 - pa0), 4)}
    print(f"月河: {len(YH_HOUSES)} watertown houses, {len(YH_ALLEYS)} alley segments, {len(yh_banks)} bank segments "
          f"({sum(1 for b_ in yh_banks if b_['arc'])} with arcades)")
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

    # 天主堂 lawn stays an open lawn (no generated loop path, benches or tree clumps); its two car parks get
    # parked cars from the block builder
    zs_parking = []
    for a in areas:
        pts_a = a.get("pts") or []
        if not pts_a:
            continue
        cx_a = sum(q[0] for q in pts_a) / len(pts_a)
        cy_a = sum(q[1] for q in pts_a) / len(pts_a)
        if not in_zs_rect(cx_a, cy_a):
            continue
        if a.get("kind") == "grass":
            a["plain"] = True
        elif a.get("kind") == "parking":
            zs_parking.append(pts_a)
    # 鸳湖里弄: rows of two-storey lane houses (grey tile gables, lime or brick walls) on an east-west lane grid,
    # kept off the canal and the roads
    nh_lanes = []
    rng_l = random.Random(5150)
    lx0, ly0, lx1, ly1 = NH_LANES_RECT
    yy = ly0 + 8.0
    row = 0
    while yy < ly1 - 6.0:
        xx = lx0 + 6.0 + (row % 2) * 4.0
        while xx < lx1 - 6.0:
            hl = rng_l.uniform(8.0, 14.0)
            hd = rng_l.uniform(9.0, 11.0)
            cxh, cyh = xx + hl * 0.5, yy
            corners = [(cxh + sx * hl * 0.5, cyh + sy * hd * 0.5) for sx in (-1, 1) for sy in (-1, 1)] + [(cxh, cyh)]
            ok = True
            for (qx, qy) in corners:
                for wp in water_grid.query(qx - 1, qy - 1, qx + 1, qy + 1):
                    if point_in_poly(qx, qy, wp):
                        ok = False
                        break
                if not ok:
                    break
                for (rax, ray, rbx, rby, rhw) in road_grid.query(qx - 30, qy - 30, qx + 30, qy + 30):
                    if seg_dist(qx, qy, rax, ray, rbx, rby)[0] < rhw + 3.0:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                nh_lanes.append({"c": rnd((cxh, cyh)), "l": round(hl, 1), "d": round(hd, 1),
                                 "h": round(rng_l.choice((7.2, 7.8, 8.6, 9.4)), 1), "f": 1 if row % 2 == 0 else -1,
                                 "brick": 1 if rng_l.random() < 0.35 else 0})
            xx += hl + rng_l.uniform(0.0, 1.5)
        yy += 12.0 if row % 2 == 0 else 15.0
        row += 1
    print(f"鸳湖里弄: {len(nh_lanes)} lane houses")
    # 壕股塔 fronts the water: face the nearest lake shore
    best_w = (1e9, 0.0, 1.0)
    for wp in water_grid.query(HAOGU_PAGODA_POS[0] - 260, HAOGU_PAGODA_POS[1] - 260, HAOGU_PAGODA_POS[0] + 260, HAOGU_PAGODA_POS[1] + 260):
        for k in range(len(wp)):
            a_w, b_w = wp[k], wp[(k + 1) % len(wp)]
            dd, _ = seg_dist(HAOGU_PAGODA_POS[0], HAOGU_PAGODA_POS[1], a_w[0], a_w[1], b_w[0], b_w[1])
            if dd < best_w[0]:
                mx_w, my_w = (a_w[0] + b_w[0]) * 0.5, (a_w[1] + b_w[1]) * 0.5
                best_w = (dd, mx_w - HAOGU_PAGODA_POS[0], my_w - HAOGU_PAGODA_POS[1])
    lw = math.hypot(best_w[1], best_w[2]) or 1.0
    haogu_face = [round(best_w[1] / lw, 3), round(best_w[2] / lw, 3)]
    print(f"壕股塔: shore {best_w[0]:.0f} m away, facing {haogu_face}")
    landmarks = {
        "jiaxing_south_station": {"pos": rnd(SOUTH_STA_POS), "angle": round(hsr_angle, 4)},
        "yanyu_tower": {"pos": rnd(YANYU_POS), "island_pts": island_pts},
        "haogu_pagoda": {"pos": rnd(HAOGU_PAGODA_POS), "face": haogu_face},
        "huijingyuan": {"pos": rnd(HUIJINGYUAN_POS)},
        "nanhu_gate": {"pos": rnd(NANHU_GATE_POS), "angle": -1.32},
        "nanhu_tiandi": {"pos": rnd(NANHU_TIANDI_POS)},
        "nanhu_memorial": {"pos": rnd(MEMORIAL_POS), "angle": 0.08},
        "jiaxing_gov": {"pos": rnd(GOV_POS), "angle": 0.04},
        "jiaxing_no1_school": {"pos": rnd(JIAXING_NO1_POS), "angle": 0.02},
        "hanlin_residence": {"pos": rnd(HANLIN_POS), "bridge_pos": rnd(NO1_BRIDGE_POS), "angle": 0.203},
        "yuehe_quarter": {
            "houses": YH_HOUSES,
            "alleys": YH_ALLEYS,
            "banks": yh_banks,
            "paifang": yh_paifang,
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
        "pingshan_park": {"pos": rnd(PINGSHAN_PARK_POS), "angle": 0.14},
        "shaonian_street": {"pos": rnd(SHAONIAN_POS), "angle": 0.144},
        "zhongshan_block": {"parking": zs_parking},
        "nanhu_district": {"lanes": nh_lanes},
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
        "construction_sites": construction_sites,
        "farmland_greenhouses": farmland_greenhouses,
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
        "road_signs": build_road_signs(graph_edges, graph_nodes),
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
