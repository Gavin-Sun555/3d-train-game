#!/usr/bin/env python3
"""
Builds data files for the full 3D Seattle Streetcar/Train Simulation Game:
1. data/tram_models.json      - 14 detailed modern & pre-1950s classic vintage trams (ported from 2d-train-game)
2. data/seattle_expanded.json - Expanded ~980m x 2010m Downtown Seattle -> Denny Triangle -> South Lake Union
   map with a clean connected buildable Street Graph (junctions + edges), 590+ 3D buildings, landmarks,
   crosswalks, streetlamps, trees, and a pre-built editable Starter Line.
"""

import gzip
import heapq
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "data")
os.makedirs(DATA_DIR, exist_ok=True)

SEATTLE_GZ = "/Users/yansun/personal/2d-train-game/mapdata/seattle.json.gz"


def point_to_seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def poly_min_dist_to_segs(pts, seg_list):
    # Quick AABB pre-reject per segment
    bx0 = min(p[0] for p in pts) - 5.0
    bx1 = max(p[0] for p in pts) + 5.0
    by0 = min(p[1] for p in pts) - 5.0
    by1 = max(p[1] for p in pts) + 5.0
    best = 1e9
    for ax, ay, cx, cy in seg_list:
        if max(ax, cx) < bx0 or min(ax, cx) > bx1 or max(ay, cy) < by0 or min(ay, cy) > by1:
            continue
        for px, py in pts:
            d = point_to_seg_dist(px, py, ax, ay, cx, cy)
            if d < best:
                best = d
                if best < 3.6:
                    return best
    return best


def build_tram_models():
    # 14 iconic trams: 8 modern low-floor LRVs/trams + 6 pre-1950s classic vintage streetcars
    models = [
        # --- Modern Trams (8) ---
        {
            "key": "siemens-s700",
            "name_zh": "西门子 S700 轻轨电车",
            "name_en": "Siemens S700 LRV",
            "era": "modern",
            "origin": "美国 · 北美主力轻轨",
            "year": 2020,
            "max_speed_kmh": 90,
            "accel": 1.30,
            "decel": 1.45,
            "width": 2.65,
            "default_sections": 3,
            "section_len": 9.4,
            "cap_per_section": 68,
            "nose": "streamlined",
            "roof": "lrv_pods",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.90, 0.93, 0.96],
            "accent_color": [0.08, 0.42, 0.68],
            "roof_color": [0.25, 0.28, 0.32],
            "seat_color": [0.14, 0.38, 0.62],
        },
        {
            "key": "inekon-trio",
            "name_zh": "Inekon 12 Trio 西湖电车",
            "name_en": "Inekon 12 Trio",
            "era": "modern",
            "origin": "捷克/美国 · 西雅图街车",
            "year": 2007,
            "max_speed_kmh": 70,
            "accel": 1.22,
            "decel": 1.35,
            "width": 2.46,
            "default_sections": 3,
            "section_len": 8.2,
            "cap_per_section": 54,
            "nose": "panoramic",
            "roof": "compact",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.94, 0.95, 0.96],
            "accent_color": [0.84, 0.34, 0.14],
            "roof_color": [0.22, 0.25, 0.28],
            "seat_color": [0.72, 0.30, 0.16],
        },
        {
            "key": "crrc-suzhou",
            "name_zh": "中车长客 · 苏州高新电车",
            "name_en": "CRRC Suzhou Low-Floor",
            "era": "modern",
            "origin": "中国 · 100%低地板",
            "year": 2018,
            "max_speed_kmh": 70,
            "accel": 1.25,
            "decel": 1.35,
            "width": 2.65,
            "default_sections": 3,
            "section_len": 9.2,
            "cap_per_section": 64,
            "nose": "sleek",
            "roof": "shrouded",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.93, 0.96, 0.95],
            "accent_color": [0.18, 0.68, 0.52],
            "roof_color": [0.24, 0.28, 0.31],
            "seat_color": [0.16, 0.56, 0.44],
        },
        {
            "key": "crrc-haizhu",
            "name_zh": "中车株机 · 海珠超级电容电车",
            "name_en": "CRRC Haizhu Supercap",
            "era": "modern",
            "origin": "中国 · 广州木棉号",
            "year": 2015,
            "max_speed_kmh": 70,
            "accel": 1.20,
            "decel": 1.35,
            "width": 2.65,
            "default_sections": 3,
            "section_len": 9.0,
            "cap_per_section": 62,
            "nose": "panoramic",
            "roof": "battery",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.96, 0.96, 0.97],
            "accent_color": [0.82, 0.18, 0.20],
            "roof_color": [0.26, 0.27, 0.30],
            "seat_color": [0.74, 0.22, 0.22],
        },
        {
            "key": "citadis-x05",
            "name_zh": "阿尔斯通 Citadis X05",
            "name_en": "Alstom Citadis X05",
            "era": "modern",
            "origin": "法国 · 欧洲全景电车",
            "year": 2021,
            "max_speed_kmh": 80,
            "accel": 1.30,
            "decel": 1.40,
            "width": 2.40,
            "default_sections": 3,
            "section_len": 9.0,
            "cap_per_section": 60,
            "nose": "sleek",
            "roof": "shrouded",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.92, 0.93, 0.95],
            "accent_color": [0.16, 0.54, 0.68],
            "roof_color": [0.16, 0.19, 0.22],
            "seat_color": [0.18, 0.46, 0.58],
        },
        {
            "key": "siemens-avenio",
            "name_zh": "西门子 Avenio 现代电车",
            "name_en": "Siemens Avenio",
            "era": "modern",
            "origin": "德国 · 慕尼黑/多哈款",
            "year": 2019,
            "max_speed_kmh": 80,
            "accel": 1.25,
            "decel": 1.40,
            "width": 2.65,
            "default_sections": 3,
            "section_len": 9.1,
            "cap_per_section": 65,
            "nose": "faceted",
            "roof": "lrv_pods",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.20, 0.38, 0.62],
            "accent_color": [0.88, 0.90, 0.94],
            "roof_color": [0.20, 0.23, 0.27],
            "seat_color": [0.22, 0.36, 0.56],
        },
        {
            "key": "hu300-lightline",
            "name_zh": "宇都宫 HU300 雷都线",
            "name_en": "Utsunomiya HU300 Lightline",
            "era": "modern",
            "origin": "日本 · 现代黑金轻轨",
            "year": 2023,
            "max_speed_kmh": 70,
            "accel": 1.25,
            "decel": 1.35,
            "width": 2.65,
            "default_sections": 3,
            "section_len": 9.2,
            "cap_per_section": 60,
            "nose": "sleek",
            "roof": "shrouded",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.18, 0.20, 0.23],
            "accent_color": [0.95, 0.76, 0.14],
            "roof_color": [0.14, 0.15, 0.18],
            "seat_color": [0.76, 0.60, 0.16],
        },
        {
            "key": "hiroden-5200",
            "name_zh": "广岛电铁 5200形 APEX",
            "name_en": "Hiroden 5200 Green Mover",
            "era": "modern",
            "origin": "日本 · 路面低地板",
            "year": 2019,
            "max_speed_kmh": 60,
            "accel": 1.15,
            "decel": 1.30,
            "width": 2.45,
            "default_sections": 3,
            "section_len": 8.4,
            "cap_per_section": 52,
            "nose": "boxy",
            "roof": "battery",
            "panto": "single_arm",
            "vintage": False,
            "single_headlamp": False,
            "body_color": [0.93, 0.95, 0.93],
            "accent_color": [0.18, 0.58, 0.28],
            "roof_color": [0.24, 0.27, 0.25],
            "seat_color": [0.20, 0.50, 0.28],
        },
        # --- Classic Pre-1950s Vintage Streetcars (6) ---
        {
            "key": "pcc-1936",
            "name_zh": "PCC 流线型古典电车 (1936)",
            "name_en": "PCC Streamliner (1936)",
            "era": "vintage",
            "origin": "美国 · 1936 传奇流线电车",
            "year": 1936,
            "max_speed_kmh": 65,
            "accel": 1.30,
            "decel": 1.35,
            "width": 2.54,
            "default_sections": 1,
            "section_len": 14.2,
            "cap_per_section": 58,
            "nose": "streamlined",
            "roof": "vintage_arch",
            "panto": "trolley_pole",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.95, 0.91, 0.78],
            "accent_color": [0.76, 0.22, 0.15],
            "roof_color": [0.42, 0.39, 0.34],
            "seat_color": [0.48, 0.26, 0.15],
        },
        {
            "key": "dalian-3000-1935",
            "name_zh": "大连 3000型有轨电车 (1935)",
            "name_en": "Dalian 3000 Classic (1935)",
            "era": "vintage",
            "origin": "中国 · 1935 历史木质老电车",
            "year": 1935,
            "max_speed_kmh": 45,
            "accel": 0.85,
            "decel": 1.05,
            "width": 2.40,
            "default_sections": 1,
            "section_len": 13.6,
            "cap_per_section": 50,
            "nose": "panoramic",
            "roof": "clerestory",
            "panto": "diamond",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.15, 0.34, 0.22],
            "accent_color": [0.93, 0.88, 0.72],
            "roof_color": [0.30, 0.26, 0.22],
            "seat_color": [0.54, 0.34, 0.18],
        },
        {
            "key": "lisbon-1930",
            "name_zh": "里斯本 Remodelado 老电车 (1930)",
            "name_en": "Lisbon Remodelado 28E (1930)",
            "era": "vintage",
            "origin": "葡萄牙 · 1930 经典山城电车",
            "year": 1930,
            "max_speed_kmh": 45,
            "accel": 0.95,
            "decel": 1.20,
            "width": 2.28,
            "default_sections": 1,
            "section_len": 10.8,
            "cap_per_section": 38,
            "nose": "panoramic",
            "roof": "clerestory",
            "panto": "trolley_pole",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.94, 0.74, 0.14],
            "accent_color": [0.96, 0.95, 0.90],
            "roof_color": [0.38, 0.36, 0.33],
            "seat_color": [0.56, 0.36, 0.18],
        },
        {
            "key": "perley-thomas-1923",
            "name_zh": "新奥尔良 900型铛铛车 (1923)",
            "name_en": "Perley Thomas 900 (1923)",
            "era": "vintage",
            "origin": "美国 · 1923 圣查尔斯老电车",
            "year": 1923,
            "max_speed_kmh": 45,
            "accel": 0.82,
            "decel": 1.08,
            "width": 2.44,
            "default_sections": 1,
            "section_len": 14.0,
            "cap_per_section": 52,
            "nose": "panoramic",
            "roof": "clerestory",
            "panto": "trolley_pole",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.14, 0.28, 0.18],
            "accent_color": [0.68, 0.24, 0.16],
            "roof_color": [0.26, 0.23, 0.20],
            "seat_color": [0.60, 0.40, 0.20],
        },
        {
            "key": "berlin-t24-1924",
            "name_zh": "柏林 T24型古典电车 (1924)",
            "name_en": "Berlin T24 Classic (1924)",
            "era": "vintage",
            "origin": "德国 · 1924 魏玛时代电车",
            "year": 1924,
            "max_speed_kmh": 50,
            "accel": 0.88,
            "decel": 1.12,
            "width": 2.24,
            "default_sections": 2,
            "section_len": 11.2,
            "cap_per_section": 42,
            "nose": "boxy",
            "roof": "vintage_arch",
            "panto": "diamond",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.92, 0.86, 0.68],
            "accent_color": [0.22, 0.24, 0.28],
            "roof_color": [0.30, 0.29, 0.27],
            "seat_color": [0.52, 0.32, 0.16],
        },
        {
            "key": "hiroden-650-1942",
            "name_zh": "广岛电铁 650形老电车 (1942)",
            "name_en": "Hiroden 650 Classic (1942)",
            "era": "vintage",
            "origin": "日本 · 1942 昭和古董电车",
            "year": 1942,
            "max_speed_kmh": 45,
            "accel": 0.82,
            "decel": 1.10,
            "width": 2.40,
            "default_sections": 1,
            "section_len": 12.8,
            "cap_per_section": 46,
            "nose": "boxy",
            "roof": "vintage_arch",
            "panto": "diamond",
            "vintage": True,
            "single_headlamp": True,
            "body_color": [0.88, 0.84, 0.72],
            "accent_color": [0.18, 0.42, 0.28],
            "roof_color": [0.28, 0.27, 0.25],
            "seat_color": [0.22, 0.44, 0.30],
        },
    ]
    out_path = os.path.join(DATA_DIR, "tram_models.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"models": models}, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(models)} tram models -> {out_path}")


def add_junction_links(nodes, edges, max_gap=25.0):
    """Join junction points that one real intersection was split into.

    Points of a junction farther apart than the 15 m cluster radius stay
    separate nodes. A street that bends into a neighbouring street just
    before the intersection can then reach the main road only through a
    hairpin (Lenora Street -> Boren Avenue -> Denny Way turns 143 and 123
    degrees), which no tram can run. Append a short link that continues
    such a street straight into the nearby node. Links are only appended,
    so every existing node and edge id (stored in saves) is unchanged.
    """
    pos = {n["id"]: n["pos"] for n in nodes}
    inc = {n["id"]: [] for n in nodes}
    linked = set()
    for e in edges:
        inc[e["a"]].append(e)
        inc[e["b"]].append(e)
        linked.add((min(e["a"], e["b"]), max(e["a"], e["b"])))

    def heading_out(e, nid):
        p = e["pts"]
        a, b = (p[0], p[1]) if e["a"] == nid else (p[-1], p[-2])
        return math.atan2(b[1] - a[1], b[0] - a[0])

    def turn(h0, h1):
        return abs((h1 - h0 + math.pi) % (2 * math.pi) - math.pi)

    def heading_in(e, nid):
        # Direction of travel when arriving at nid along e.
        return heading_out(e, nid) + math.pi

    def runnable_path(u, came, v, depth=3, limit=math.radians(75)):
        # Can a tram arriving at u along `came` reach v over at most
        # `depth` existing edges, never turning more than `limit`?
        stack = [(u, came, depth)]
        while stack:
            node, via, left = stack.pop()
            for f in inc[node]:
                if f is via or turn(heading_in(via, node), heading_out(f, node)) > limit:
                    continue
                nxt = f["b"] if f["a"] == node else f["a"]
                if nxt == v:
                    return True
                if left > 1:
                    stack.append((nxt, f, left - 1))
        return False

    added = []
    for u in sorted(pos):
        for v in sorted(pos):
            if u == v or (min(u, v), max(u, v)) in linked:
                continue
            pu, pv = pos[u], pos[v]
            gap = math.hypot(pv[0] - pu[0], pv[1] - pu[1])
            if gap > max_gap or gap < 8.0:
                continue
            link = math.atan2(pv[1] - pu[1], pv[0] - pu[0])
            for e in inc[u]:
                arrive = heading_out(e, u) + math.pi  # travelling into u along e
                # The street must point straight at v, and the existing
                # streets must not already lead there without a hairpin.
                if turn(arrive, link) > math.radians(15):
                    continue
                if runnable_path(u, e, v):
                    continue
                # At v, a tram must be able to carry on with a gentle turn.
                if not any(turn(link, heading_out(f, v)) <= math.radians(60) for f in inc[v]):
                    continue
                key = (min(u, v), max(u, v))
                linked.add(key)
                a, b = key
                pts = [pos[a], pos[b]]
                added.append({
                    "id": len(edges) + len(added),
                    "a": a,
                    "b": b,
                    "name": e["name"],
                    "width": e["width"],
                    "length": round(gap, 1),
                    "pts": pts,
                })
                print(f"  junction link: {e['name']} node {u} -> node {v} ({gap:.1f} m)")
                break
    edges.extend(added)
    return added


# Id reference: the latest released graph (v2 = v1 downtown/SLU ids + Seattle Center/waterfront ids).
# Each map extension freezes the previous graph here so every id ever shipped stays valid for saves.
FROZEN_GRAPH_V1 = os.path.join(ROOT, "tools", "osm_cache", "seattle_graph_v2.json")


def stabilize_graph_ids(final_nodes, final_edges, starter_network):
    """Re-number the freshly extracted graph so every node/edge that already existed in the frozen v1
    graph keeps its id, direction (a->b) and exact geometry; new streets get ids after the v1 maximum."""
    if not os.path.exists(FROZEN_GRAPH_V1):
        return starter_network
    with open(FROZEN_GRAPH_V1, encoding="utf-8") as f:
        v1 = json.load(f)
    old_nodes = {n["id"]: n for n in v1["graph_nodes"]}
    old_edges = v1["graph_edges"]

    # 1. Nodes: match by position (game coords)
    node_map = {}  # new id -> final id
    used_old = set()
    cell = {}
    for on in old_nodes.values():
        k = (int(on["pos"][0] // 6), int(on["pos"][1] // 6))
        cell.setdefault(k, []).append(on)
    for n in final_nodes:
        kx, ky = int(n["pos"][0] // 6), int(n["pos"][1] // 6)
        best, bd = None, 1.6
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for on in cell.get((kx + dx, ky + dy), []):
                    d = math.hypot(on["pos"][0] - n["pos"][0], on["pos"][1] - n["pos"][1])
                    if d < bd and on["id"] not in used_old:
                        best, bd = on, d
        if best is not None:
            node_map[n["id"]] = best["id"]
            used_old.add(best["id"])
    next_nid = max(old_nodes) + 1
    for n in sorted(final_nodes, key=lambda q: q["id"]):
        if n["id"] not in node_map:
            node_map[n["id"]] = next_nid
            next_nid += 1
    for n in final_nodes:
        nid = node_map[n["id"]]
        if nid in old_nodes:
            n["pos"] = old_nodes[nid]["pos"]
            n["name"] = old_nodes[nid]["name"]
        n["id"] = nid
    pos_of = {n["id"]: n["pos"] for n in final_nodes}

    # 2. Edges: same (old) end nodes + similar length -> keep old id, direction and polyline
    by_ends = {}
    for oe in old_edges:
        by_ends.setdefault(frozenset((oe["a"], oe["b"])), []).append(oe)
    edge_map = {}
    used_e = set()
    for e in final_edges:
        a, b = node_map[e["a"]], node_map[e["b"]]
        e["a"], e["b"] = a, b
        cands = [oe for oe in by_ends.get(frozenset((a, b)), []) if oe["id"] not in used_e]
        best = None
        for oe in cands:
            if abs(oe["length"] - e["length"]) < 3.0 and (best is None or abs(oe["length"] - e["length"]) < abs(best["length"] - e["length"])):
                best = oe
        if best is not None:
            used_e.add(best["id"])
            edge_map[e["id"]] = best["id"]
            e.update({"a": best["a"], "b": best["b"], "pts": best["pts"], "length": best["length"], "name": best["name"], "width": best["width"]})
    next_eid = max(oe["id"] for oe in old_edges) + 1
    for e in sorted(final_edges, key=lambda q: q["id"]):
        if e["id"] not in edge_map:
            edge_map[e["id"]] = next_eid
            next_eid += 1
            # snap new edge ends onto (possibly kept) node positions
            e["pts"][0] = list(pos_of[e["a"]])
            e["pts"][-1] = list(pos_of[e["b"]])
    for e in final_edges:
        e["id"] = edge_map[e["id"]]
    final_nodes.sort(key=lambda q: q["id"])
    final_edges.sort(key=lambda q: q["id"])
    lost = [oe["id"] for oe in old_edges if oe["id"] not in used_e]
    print(f"  id-stable merge: kept {len(used_e)}/{len(old_edges)} v1 edges, {len(used_old)}/{len(old_nodes)} v1 nodes; "
          f"{len(final_edges) - len(used_e)} new edges; v1 edges without a match: {lost}")

    # 3. Starter network references (edge ids of the freshly built graph)
    for t in starter_network["tracks"]:
        t["edge_id"] = edge_map.get(t["edge_id"], t["edge_id"])
    for st in starter_network["stations"]:
        st["edge_id"] = edge_map.get(st["edge_id"], st["edge_id"])
    return starter_network


def build_seattle_expanded():
    with gzip.open(SEATTLE_GZ, "rt", encoding="utf-8") as f:
        m = json.load(f)

    # Expanded ~980m x 2010m corridor: Pike Place Market & Westlake Center (south)
    # -> Denny Triangle & Amazon Spheres (mid) -> South Lake Union & Lake Union Park (north)!
    # v2: extended west to Seattle Center / Space Needle / Olympic Sculpture Park and south along the
    # Elliott Bay waterfront to the Great Wheel. Origin (cx, cy) unchanged so existing coordinates hold.
    # v3: further south along the waterfront to Colman Dock (Seattle Ferry Terminal, Pier 52).
    x0, x1 = 1000.0, 2940.0
    y0, y1 = 1950.0, 4900.0
    cx = 2420.0
    cy = 2960.0

    def rc(pt):
        return [round(pt[0] - cx, 2), round(pt[1] - cy, 2)]

    osm_nodes = m["nodes"]

    # 1. Extract in-bounds ground roads and build a clean clustered planar street network!
    in_roads = []
    used_nids = set()
    node_use_count = {}
    for r in m["roads"]:
        if r.get("l", 0) != 0:
            continue
        cls = r.get("c", "")
        if cls in ("service", "footway", "path", "steps", "cycleway", "pedestrian"):
            continue
        nids = r["p"]
        pts = [osm_nodes[i] for i in nids]
        if not any(x0 <= p[0] <= x1 and y0 <= p[1] <= y1 for p in pts):
            continue
        # Clip polyline to padded bounds
        sub_nids = [nid for nid in nids if (x0 - 35 <= osm_nodes[nid][0] <= x1 + 35 and y0 - 35 <= osm_nodes[nid][1] <= y1 + 35)]
        if len(sub_nids) < 2:
            continue
        in_roads.append((r, sub_nids))
        for nid in sub_nids:
            used_nids.add(nid)
            node_use_count[nid] = node_use_count.get(nid, 0) + 1
        # Endpoints are always junction candidates
        node_use_count[sub_nids[0]] = max(node_use_count.get(sub_nids[0], 0), 2)
        node_use_count[sub_nids[-1]] = max(node_use_count.get(sub_nids[-1], 0), 2)

    # Cluster intersection nodes within 15m using Union-Find so parallel carriageways connect cleanly!
    junction_nids = sorted([nid for nid, cnt in node_use_count.items() if cnt >= 2])
    parent = {nid: nid for nid in junction_nids}

    def find(u):
        while parent[u] != u:
            parent[u] = parent[parent[u]]
            u = parent[u]
        return u

    for i in range(len(junction_nids)):
        ni = junction_nids[i]
        pi = osm_nodes[ni]
        for j in range(i + 1, len(junction_nids)):
            nj = junction_nids[j]
            pj = osm_nodes[nj]
            if abs(pi[0] - pj[0]) <= 15.0 and abs(pi[1] - pj[1]) <= 15.0:
                if math.hypot(pi[0] - pj[0], pi[1] - pj[1]) <= 15.0:
                    ri, rj = find(ni), find(nj)
                    if ri != rj:
                        parent[rj] = ri

    clusters = {}
    for nid in junction_nids:
        root = find(nid)
        clusters.setdefault(root, []).append(nid)

    junc_map = {}
    graph_nodes = []
    for root, members in sorted(clusters.items()):
        jx = sum(osm_nodes[u][0] for u in members) / len(members)
        jy = sum(osm_nodes[u][1] for u in members) / len(members)
        jid = len(graph_nodes)
        for u in members:
            junc_map[u] = jid
        graph_nodes.append({
            "id": jid,
            "pos": rc([jx, jy]),
            "osm_pos": [jx, jy],
            "streets": set(),
        })

    # Split ways at junctions into clean graph edges
    raw_edges = {}
    for r, sub_nids in in_roads:
        nm = r.get("n", "")
        lanes = max(2, int(r.get("f", 1)) + int(r.get("b", 1)))
        w = round(min(18.0, lanes * 3.4 + 3.0), 1)
        if nm in ("Westlake Avenue", "Westlake Avenue North", "5th Avenue", "4th Avenue", "Mercer Street", "Stewart Street", "Olive Way", "Pine Street", "Pike Street", "Denny Way"):
            w = max(w, 15.0)

        start_idx = 0
        for idx in range(1, len(sub_nids)):
            nid = sub_nids[idx]
            if nid not in junc_map and idx < len(sub_nids) - 1:
                continue
            ja = junc_map.get(sub_nids[start_idx])
            jb = junc_map.get(nid)
            if ja is not None and jb is not None and ja != jb:
                pa = graph_nodes[ja]["osm_pos"]
                pb = graph_nodes[jb]["osm_pos"]
                mid_pts = [osm_nodes[u] for u in sub_nids[start_idx + 1 : idx]]
                # Filter mid_pts too close to endpoints
                clean_mid = [p for p in mid_pts if math.hypot(p[0] - pa[0], p[1] - pa[1]) > 6.0 and math.hypot(p[0] - pb[0], p[1] - pb[1]) > 6.0]
                full_osm_pts = [pa] + clean_mid + [pb]
                elen = sum(math.hypot(full_osm_pts[k + 1][0] - full_osm_pts[k][0], full_osm_pts[k + 1][1] - full_osm_pts[k][1]) for k in range(len(full_osm_pts) - 1))

                if elen >= 12.0:
                    key = (min(ja, jb), max(ja, jb))
                    if ja > jb:
                        full_osm_pts = list(reversed(full_osm_pts))
                    prev = raw_edges.get(key)
                    if prev is None or (nm and not prev["name"]) or w > prev["width"]:
                        raw_edges[key] = {
                            "a": key[0],
                            "b": key[1],
                            "name": nm,
                            "width": w,
                            "length": round(elen, 1),
                            "osm_pts": full_osm_pts,
                        }
                    if nm:
                        graph_nodes[ja]["streets"].add(nm)
                        graph_nodes[jb]["streets"].add(nm)
            start_idx = idx

    # Keep only the main connected component of the street graph so every street can reach every other!
    adj = {n["id"]: [] for n in graph_nodes}
    for key, ed in raw_edges.items():
        adj[ed["a"]].append(ed["b"])
        adj[ed["b"]].append(ed["a"])

    best_comp = set()
    visited = set()
    for nid in adj:
        if nid in visited or not adj[nid]:
            continue
        comp = set()
        stack = [nid]
        visited.add(nid)
        while stack:
            u = stack.pop()
            comp.add(u)
            for v in adj[u]:
                if v not in visited:
                    visited.add(v)
                    stack.append(v)
        if len(comp) > len(best_comp):
            best_comp = comp

    old_to_new = {}
    final_nodes = []
    for n in graph_nodes:
        if n["id"] in best_comp:
            new_id = len(final_nodes)
            old_to_new[n["id"]] = new_id
            st_names = sorted(list(n["streets"]))
            label = " & ".join(st_names[:2]) if st_names else f"路口 #{new_id}"
            final_nodes.append({
                "id": new_id,
                "pos": n["pos"],
                "osm_pos": n["osm_pos"],
                "name": label,
            })

    final_edges = []
    all_road_segs_osm = []
    for key, ed in sorted(raw_edges.items()):
        if ed["a"] in old_to_new and ed["b"] in old_to_new:
            eid = len(final_edges)
            opts = ed["osm_pts"]
            for k in range(len(opts) - 1):
                all_road_segs_osm.append((opts[k][0], opts[k][1], opts[k + 1][0], opts[k + 1][1]))
            final_edges.append({
                "id": eid,
                "a": old_to_new[ed["a"]],
                "b": old_to_new[ed["b"]],
                "name": ed["name"] if ed["name"] else "City Street",
                "width": ed["width"],
                "length": ed["length"],
                "pts": [rc(p) for p in opts],
            })

    # Helper: find closest graph node to an OSM (x, y) coordinate
    def closest_node(ox, oy):
        return min(final_nodes, key=lambda n: math.hypot(n["osm_pos"][0] - ox, n["osm_pos"][1] - oy))["id"]

    # Helper: Dijkstra shortest path on final_edges
    g_adj = {n["id"]: [] for n in final_nodes}
    for ed in final_edges:
        g_adj[ed["a"]].append((ed["b"], ed["length"], ed["id"]))
        g_adj[ed["b"]].append((ed["a"], ed["length"], ed["id"]))

    def shortest_edge_path(u_start, u_goal):
        pq = [(0.0, u_start)]
        dist = {u_start: 0.0}
        prev = {}
        while pq:
            d, u = heapq.heappop(pq)
            if u == u_goal:
                break
            if d > dist.get(u, 1e18):
                continue
            for v, w, eid in g_adj[u]:
                nd = d + w
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = (u, eid)
                    heapq.heappush(pq, (nd, v))
        if u_goal not in prev and u_start != u_goal:
            return []
        path_eids = []
        cur = u_goal
        while cur != u_start:
            pu, eid = prev[cur]
            path_eids.append(eid)
            cur = pu
        path_eids.reverse()
        return path_eids

    # Build a Closed Downtown–SLU Loop + Lake Union Turnout Spurs so 3 trams circulate smoothly through curves & turnouts!
    waypoints_osm = [
        ("Westlake Center · 西湖中心站", 2443.2, 3576.6, 1),      # BedStyle 1 = ASPHALT downtown
        ("Westlake & 7th · 亚马逊总部站", 2406.5, 3236.0, 1),     # ASPHALT (mid-block in front of Spheres)
        ("Westlake & Denny · 丹尼公园站", 2368.0, 2975.0, 0),     # BedStyle 0 = GRASS_VIGNOLE!
        ("Westlake & Thomas · 联合湖南站", 2360.8, 2560.0, 0),    # GRASS_VIGNOLE
        ("Terry & Mercer · 联合湖东站", 2565.0, 2555.0, 0),       # GRASS_VIGNOLE
        ("Fairview & Stewart · 东环大道站", 2595.0, 3180.0, 1),   # ASPHALT
    ]
    wp_nodes = [closest_node(wx, wy) for (_, wx, wy, _) in waypoints_osm]

    starter_tracks = {}
    starter_stops = []
    loop_wp_nodes = wp_nodes + [wp_nodes[0]]
    loop_beds = [w[3] for w in waypoints_osm]
    for i in range(len(waypoints_osm)):
        seg_eids = shortest_edge_path(loop_wp_nodes[i], loop_wp_nodes[i + 1])
        bed_here = loop_beds[i]
        for eid in seg_eids:
            starter_tracks[eid] = bed_here

    # Add real 3-way turnout spurs (Lake Union Park North Spur + Downtown Crossover) so turnouts exist along the loop!
    spur_lake_node = closest_node(2510.0, 2112.0)
    for eid in shortest_edge_path(wp_nodes[3], spur_lake_node):
        if eid not in starter_tracks:
            starter_tracks[eid] = 0
    spur_denny_cross = shortest_edge_path(wp_nodes[2], wp_nodes[5])
    for eid in spur_denny_cross[:2]:
        if eid not in starter_tracks:
            starter_tracks[eid] = 1

    # Place starter stations cleanly on each segment of the loop
    for idx_w, (st_name, wx, wy, _) in enumerate(waypoints_osm):
        seg_candidates = shortest_edge_path(loop_wp_nodes[idx_w], loop_wp_nodes[idx_w + 1])
        search_eids = seg_candidates if seg_candidates else sorted(starter_tracks.keys())
        best_eid = search_eids[0]
        best_t = 0.5
        best_d = 1e9
        tx, tz = wx - cx, wy - cy
        for eid in search_eids:
            pts = final_edges[eid]["pts"]
            p0, p1 = pts[0], pts[-1]
            dx, dz = p1[0] - p0[0], p1[1] - p0[1]
            l2 = dx * dx + dz * dz
            if final_edges[eid]["length"] < 28.0:
                continue
            t = 0.5 if l2 < 1.0 else max(0.28, min(0.72, ((tx - p0[0]) * dx + (tz - p0[1]) * dz) / l2))
            px, pz = p0[0] + dx * t, p0[1] + dz * t
            d = math.hypot(tx - px, tz - pz)
            if d < best_d:
                best_d = d
                best_eid = eid
                best_t = round(t, 3)
        starter_stops.append({
            "id": idx_w + 1,
            "name": st_name,
            "edge_id": best_eid,
            "t": best_t,
            "side": 1,
        })

    loop_station_ids = [s["id"] for s in starter_stops] + [starter_stops[0]["id"]]
    starter_network = {
        "tracks": [{"edge_id": eid, "bed_style": bst} for eid, bst in sorted(starter_tracks.items())],
        "stations": starter_stops,
        "lines": [
            {
                "id": 1,
                "name": "1号线 · 西湖—联合湖示范环线",
                "color": [0.12, 0.54, 0.86],
                "model_key": "siemens-s700",
                "trams_count": 3,
                "sections": 3,
                "station_ids": loop_station_ids,
            }
        ],
    }

    # 2. Extract and enrich Buildings (ensuring 3.8m clearance from all buildable street edges!)
    overrides = [
        (2291.2, 3245.3, 22.0, 27.0, 0, True),   # Amazon The Spheres -> custom 3D domes
        (2478.1, 3642.1, 18.0, 10.0, 2, True),   # Monorail station -> custom 3D station
        (2399.6, 3488.4, 24.0, 13.5, 2, False),  # Westin podium (+ custom twin 137m/121m cylinders)
        (2439.0, 3642.9, 25.0, 21.0, 2, False),  # Westlake Center mall (+ custom 102m tower)
        (2293.4, 3635.6, 25.0, 38.0, 1, False),  # Macy's / 300 Pine
        (2544.1, 3629.6, 25.0, 38.0, 1, False),  # Nordstrom Flagship
        (2388.3, 3590.1, 20.0, 26.0, 1, False),  # Times Square Flatiron
        (2512.0, 3307.1, 25.0, 92.0, 2, False),  # US Federal Courthouse
        (2450.9, 3216.1, 25.0, 58.0, 0, False),  # Amazon Apollo
    ]

    buildings = []
    for b in m["buildings"]:
        pts = b["p"]
        if not any(x0 <= p[0] <= x1 and y0 <= p[1] <= y1 for p in pts):
            continue
        bcx = sum(p[0] for p in pts) / len(pts)
        bcy = sum(p[1] for p in pts) / len(pts)

        h = max(5.5, float(b.get("h", 12.0)))
        kind = b.get("k", "")
        style = -1
        skip = False
        for ox, oy, rad, new_h, st_ov, sk in overrides:
            if math.hypot(bcx - ox, bcy - oy) < rad:
                h = new_h
                style = st_ov
                skip = sk
                break
        if skip:
            continue

        # Guarantee every buildable street edge has clean 3D tram clearance!
        if poly_min_dist_to_segs(pts, all_road_segs_osm) < 3.7:
            continue

        if style < 0:
            if h >= 68.0:
                style = 0
            elif kind in ("retail", "hotel") or (bcy > 3480 and h < 45.0):
                style = 1
            elif h <= 22.0 and ((int(bcx + bcy) % 3) != 0):
                style = 1
            else:
                style = 2

        buildings.append({
            "pts": [rc(p) for p in pts],
            "h": round(h, 1),
            "kind": kind,
            "style": style,
        })

    # 3. Areas (Lake Union water, Denny Park, Lake Union Park, Westlake Park)
    areas = []
    for a in m["areas"]:
        pts = a["p"]
        if not any(x0 - 80 <= p[0] <= x1 + 80 and y0 - 160 <= p[1] <= y1 + 80 for p in pts):
            continue
        areas.append({
            "kind": a["k"],
            "pts": [rc(p) for p in pts],
        })
    areas.append({
        "kind": "brick_plaza",
        "pts": [rc([2454.0, 3592.0]), rc([2508.0, 3672.0]), rc([2474.0, 3692.0]), rc([2448.0, 3652.0])],
    })

    # Junction links are appended after the starter line is routed, so the
    # demo network is unchanged; they still get road surface below.
    add_junction_links(final_nodes, final_edges)

    # Keep node/edge ids of the original (v1) map stable so existing saves (tracks, stations, lines that
    # reference edge ids) still load after the map was extended.
    starter_network = stabilize_graph_ids(final_nodes, final_edges, starter_network)

    # 4. Roads (from graph edges so visual roads & buildable street edges align 1:1!), crosswalks & lamps
    roads = []
    crosswalks = []
    streetlamps = []
    node_deg = {n["id"]: 0 for n in final_nodes}
    for ed in final_edges:
        node_deg[ed["a"]] += 1
        node_deg[ed["b"]] += 1

    for ed in final_edges:
        pts = ed["pts"]
        w = ed["width"]
        roads.append({
            "name": ed["name"],
            "width": w,
            "layer": 0,
            "pts": pts,
        })
        p0, p1 = pts[0], pts[-1]
        seg_len = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        if seg_len >= 22.0:
            dx, dz = (p1[0] - p0[0]) / seg_len, (p1[1] - p0[1]) / seg_len
            nx, nz = -dz, dx
            if node_deg[ed["a"]] >= 3:
                crosswalks.append({"pos": [round(p0[0] + dx * 7.8, 2), round(p0[1] + dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})
            if node_deg[ed["b"]] >= 3:
                crosswalks.append({"pos": [round(p1[0] - dx * 7.8, 2), round(p1[1] - dz * 7.8, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": w})

            s_l = 16.0
            while s_l < seg_len - 12.0:
                for side in (-1.0, 1.0):
                    lx = round(p0[0] + dx * s_l + nx * side * (w * 0.5 + 1.4), 2)
                    lz = round(p0[1] + dz * s_l + nz * side * (w * 0.5 + 1.4), 2)
                    streetlamps.append([lx, lz])
                s_l += 52.0

    # Fast spatial grid deduplication for lamps & crosswalks
    lamp_cells = set()
    dedup_lamps = []
    for lp in streetlamps:
        cell = (int(lp[0] // 22), int(lp[1] // 22))
        if cell not in lamp_cells:
            lamp_cells.add(cell)
            dedup_lamps.append(lp)

    cw_cells = set()
    dedup_cw = []
    for cw in crosswalks:
        cell = (int(cw["pos"][0] // 10), int(cw["pos"][1] // 10))
        if cell not in cw_cells:
            cw_cells.add(cell)
            dedup_cw.append(cw)

    trees = []
    for t in m["trees"]:
        if x0 <= t[0] <= x1 and y0 <= t[1] <= y1:
            if poly_min_dist_to_segs([t], all_road_segs_osm) >= 5.2:
                trees.append(rc(t))

    ne_x, ne_y = 0.66 * 3.3, -0.75 * 3.3
    # v2: the monorail now runs its full real route, from the Seattle Center terminal (beside MoPOP)
    # east along the curve onto 5th Ave N, down 5th Ave N to Denny Way, then down 5th Avenue to Westlake.
    seattle_center_leg = [
        (1556.0, 2604.0), (1600.0, 2609.0), (1640.0, 2624.0), (1668.0, 2650.0), (1679.0, 2690.0),
        (1679.0, 2790.0), (1680.0, 2880.0), (1690.0, 2918.0), (1718.0, 2944.0), (1780.0, 2998.0),
        (1849.0, 3058.0), (1917.0, 3118.0),
    ]
    monorail_pts = [[round(px - cx, 2), 7.4, round(py - cy, 2)] for px, py in seattle_center_leg] + [
        [round(2015.0 + ne_x - cx, 2), 7.4, round(3190.0 + ne_y - cy, 2)],
        [round(2121.4 + ne_x - cx, 2), 7.4, round(3283.7 + ne_y - cy, 2)],
        [round(2218.3 + ne_x - cx, 2), 7.4, round(3369.1 + ne_y - cy, 2)],
        [round(2315.8 + ne_x - cx, 2), 7.4, round(3454.1 + ne_y - cy, 2)],
        [round(2413.0 + ne_x - cx, 2), 7.4, round(3538.6 + ne_y - cy, 2)],
        [round(2443.2 + ne_x - cx, 2), 7.4, round(3576.6 + ne_y - cy, 2)],
        [round(2492.0 + ne_x - cx, 2), 7.4, round(3650.0 + ne_y - cy, 2)],
    ]

    landmarks = {
        "spheres": {
            "center": rc([2293.0, 3245.5]),
            "domes": [
                {"pos": rc([2293.5, 3245.0]), "r": 15.2, "h": 27.0},
                {"pos": rc([2278.5, 3259.5]), "r": 12.2, "h": 22.0},
                {"pos": rc([2307.5, 3231.5]), "r": 10.6, "h": 18.5},
            ],
        },
        "westin_towers": [
            {"pos": rc([2372.0, 3440.0]), "r": 16.2, "h": 137.0, "base_y": 13.0},
            {"pos": rc([2395.0, 3482.0]), "r": 16.2, "h": 121.0, "base_y": 13.0},
        ],
        "westlake_center": {
            "tower_pos": rc([2435.0, 3625.0]),
            "tower_size": [36.0, 36.0],
            "tower_h": 102.0,
            "arch_pos": rc([2458.0, 3648.0]),
            "fountain_pos": rc([2478.0, 3668.0]),
        },
        "monorail": {
            "path": monorail_pts,
            "station_pos": rc([2478.0, 3638.0]),
            "station2_pos": rc([1556.0, 2604.0]),
        },
        # v2: Seattle Center & waterfront landmarks (positions from OSM / map landmarks)
        "space_needle": {"pos": [-866.55, -250.97], "h": 184.0},
        "climate_pledge": {"pos": [-1222.47, -430.2]},
        "mopop": {"pos": [-788.32, -359.37]},
        "pacific_science": {"pos": [-1014.27, -148.33]},
        "international_fountain": {"pos": rc([1373.0, 2477.0])},
        "chihuly": {"pos": rc([1487.1, 2705.2])},
        "great_wheel": {"pos": rc([2063.5, 4293.9])},
        "colman_dock": {"pos": rc([2494.5, 4793.1])},
        "aquarium": {"pos": rc([2023.7, 4105.9])},
        # foot of Pike Street (junction with Pike Place), on the market arcade roof, facing up Pike St
        "pike_market_sign": {"pos": [-220.3, 1062.0], "face": [0.90, -0.43], "roof_h": 8.5},
        "sculpture_eagle": {"pos": rc([1095.6, 3150.0])},
    }

    # Strip internal osm_pos helper before saving
    for n in final_nodes:
        n.pop("osm_pos", None)

    # Real-world OSM detail: building names / landmark keys, ground-floor storefronts, named plazas
    from osm_storefronts import augment as osm_augment
    storefronts, plazas, piers = osm_augment(buildings, roads)

    out = {
        "key": "seattle",
        "name": "02  西雅图 · 中心城区 (Seattle)",
        "bounds": [round(x0 - cx, 1), round(y0 - cy, 1), round(x1 - cx, 1), round(y1 - cy, 1)],
        "graph_nodes": final_nodes,
        "graph_edges": final_edges,
        "starter_network": starter_network,
        "buildings": buildings,
        "areas": areas,
        "roads": roads,
        "crosswalks": dedup_cw,
        "streetlamps": dedup_lamps,
        "traffic_signals": [],
        "trees": trees,
        "landmarks": landmarks,
        "storefronts": storefronts,
        "plazas": plazas,
        "piers": piers,
    }
    out_path = os.path.join(DATA_DIR, "seattle_expanded.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(
        f"Wrote Expanded Seattle -> {out_path}:\n"
        f"  Graph: {len(final_nodes)} junctions, {len(final_edges)} buildable street edges\n"
        f"  Starter Line: {len(starter_tracks)} built edges, {len(starter_stops)} stations\n"
        f"  City: {len(buildings)} buildings, {len(areas)} areas, {len(dedup_cw)} crosswalks, {len(dedup_lamps)} lamps, {len(trees)} trees"
    )


def build_grid_city():
    """Generates Map 01: Grid City (01 网格新城), matching 2d-train-game's deterministic practice city."""
    import random
    rng = random.Random(20261117)

    # 9x9 grid at 125m block spacing -> [-500 .. +500]m (1000m x 1000m clean grid)
    coords = [-500.0 + i * 125.0 for i in range(9)]
    ew_names = [
        "北四街 (North 4th St)", "北三街 (North 3rd St)", "北二街 (North 2nd St)", "北一街 (North 1st St)",
        "中央大道 (Central Blvd)",
        "南一街 (South 1st St)", "南二街 (South 2nd St)", "南三街 (South 3rd St)", "南四街 (South 4th St)",
    ]
    ns_names = [
        "西四路 (West 4th Ave)", "西三路 (West 3rd Ave)", "西二路 (West 2nd Ave)", "西一路 (West 1st Ave)",
        "中轴干道 (Grand Ave)",
        "东一路 (East 1st Ave)", "东二路 (East 2nd Ave)", "东三路 (East 3rd Ave)", "东四路 (East 4th Ave)",
    ]

    nodes = []
    nid_grid = {}
    for iz, z in enumerate(coords):
        for ix, x in enumerate(coords):
            nid = len(nodes)
            nid_grid[(ix, iz)] = nid
            nodes.append({
                "id": nid,
                "pos": [round(x, 2), round(z, 2)],
                "name": f"{ns_names[ix].split(' ')[0]} & {ew_names[iz].split(' ')[0]}",
            })

    edges = []
    roads = []
    crosswalks = []
    streetlamps = []

    def add_grid_edge(na, nb, name, width):
        pa = nodes[na]["pos"]
        pb = nodes[nb]["pos"]
        elen = round(math.hypot(pb[0] - pa[0], pb[1] - pa[1]), 1)
        eid = len(edges)
        edges.append({
            "id": eid,
            "a": na,
            "b": nb,
            "name": name,
            "width": width,
            "length": elen,
            "pts": [pa, pb],
        })
        roads.append({"name": name, "width": width, "layer": 0, "pts": [pa, pb]})
        dx, dz = (pb[0] - pa[0]) / elen, (pb[1] - pa[1]) / elen
        nx, nz = -dz, dx
        crosswalks.append({"pos": [round(pa[0] + dx * 9.0, 2), round(pa[1] + dz * 9.0, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": width})
        crosswalks.append({"pos": [round(pb[0] - dx * 9.0, 2), round(pb[1] - dz * 9.0, 2)], "dir": [round(dx, 4), round(dz, 4)], "width": width})
        for s_l in (34.0, 62.5, 91.0):
            for side in (-1.0, 1.0):
                streetlamps.append([
                    round(pa[0] + dx * s_l + nx * side * (width * 0.5 + 1.4), 2),
                    round(pa[1] + dz * s_l + nz * side * (width * 0.5 + 1.4), 2),
                ])
        return eid

    horiz_eids = {}
    vert_eids = {}
    for iz in range(9):
        w = 18.0 if iz == 4 else (14.5 if iz in (2, 6) else 11.5)
        for ix in range(8):
            horiz_eids[(ix, iz)] = add_grid_edge(nid_grid[(ix, iz)], nid_grid[(ix + 1, iz)], ew_names[iz], w)

    for ix in range(9):
        w = 18.0 if ix == 4 else (14.5 if ix in (2, 6) else 11.5)
        for iz in range(8):
            vert_eids[(ix, iz)] = add_grid_edge(nid_grid[(ix, iz)], nid_grid[(ix, iz + 1)], ns_names[ix], w)

    # Winding canal/river across block row iz = 5..6 (between z = +125 and z = +250, centered z = +187.5)
    areas = [
        {
            "kind": "water",
            "pts": [[-680.0, 172.0], [680.0, 172.0], [680.0, 203.0], [-680.0, 203.0]],
        },
        # Riverside linear park flanking the river
        {
            "kind": "park",
            "pts": [[-520.0, 142.0], [520.0, 142.0], [520.0, 171.5], [-520.0, 171.5]],
        },
        {
            "kind": "park",
            "pts": [[-520.0, 203.5], [520.0, 203.5], [520.0, 232.0], [-520.0, 232.0]],
        },
    ]

    buildings = []
    trees = []

    def rect_poly(cx_b, cz_b, bw, bd):
        hw, hd = bw * 0.5, bd * 0.5
        return [
            [round(cx_b - hw, 2), round(cz_b - hd, 2)],
            [round(cx_b + hw, 2), round(cz_b - hd, 2)],
            [round(cx_b + hw, 2), round(cz_b + hd, 2)],
            [round(cx_b - hw, 2), round(cz_b + hd, 2)],
        ]

    for iz in range(8):
        if iz == 5:
            # River & riverside park row: populate lush park trees instead of buildings!
            for ix in range(8):
                bx_c = coords[ix] + 62.5
                for tx_off in (-36.0, -12.0, 12.0, 36.0):
                    trees.append([round(bx_c + tx_off, 2), 156.0])
                    trees.append([round(bx_c + tx_off, 2), 218.0])
            continue

        for ix in range(8):
            bx_c = coords[ix] + 62.5
            bz_c = coords[iz] + 62.5
            dist_center = max(abs(ix - 3.5), abs(iz - 3.5))

            # Central Civic Plaza & Park at (3, 3) and (4, 3)
            if (ix, iz) == (3, 3):
                areas.append({"kind": "park", "pts": rect_poly(bx_c, bz_c, 96.0, 96.0)})
                for tx in (-28.0, 0.0, 28.0):
                    for tz in (-28.0, 28.0):
                        trees.append([round(bx_c + tx, 2), round(bz_c + tz, 2)])
                continue
            if (ix, iz) == (4, 3):
                areas.append({"kind": "brick_plaza", "pts": rect_poly(bx_c, bz_c, 96.0, 96.0)})
                buildings.append({
                    "pts": rect_poly(bx_c, bz_c, 44.0, 44.0),
                    "h": 96.0,
                    "kind": "office",
                    "style": 0,
                })
                continue

            # Subdivide each 125x125m urban block into 2 or 4 clean architectural parcels (leaving generous sidewalks)
            if dist_center <= 1.6:
                # Downtown core high-rises & historic department stores
                for qx in (-24.0, 24.0):
                    for qz in (-24.0, 24.0):
                        h_val = round(rng.uniform(48.0, 128.0) if rng.random() < 0.6 else rng.uniform(24.0, 44.0), 1)
                        st = 0 if h_val >= 56.0 else (1 if rng.random() < 0.55 else 2)
                        buildings.append({
                            "pts": rect_poly(bx_c + qx, bz_c + qz, 38.0, 38.0),
                            "h": h_val,
                            "kind": "office" if st == 0 else "retail",
                            "style": st,
                        })
            else:
                # Mid-rise & classic brick residential/commercial blocks + courtyard trees
                for qx in (-25.0, 25.0):
                    for qz in (-25.0, 25.0):
                        if rng.random() < 0.14:
                            areas.append({"kind": "park", "pts": rect_poly(bx_c + qx, bz_c + qz, 36.0, 36.0)})
                            trees.append([round(bx_c + qx, 2), round(bz_c + qz, 2)])
                            continue
                        h_val = round(rng.uniform(12.0, 34.0), 1)
                        st = 1 if rng.random() < 0.58 else 2
                        buildings.append({
                            "pts": rect_poly(bx_c + qx, bz_c + qz, 36.0, 34.0),
                            "h": h_val,
                            "kind": "apartments",
                            "style": st,
                        })

    # Starter Demo Loop around the Inner Ring (ix = 2..6, iz = 2..6) crossing the river bridges!
    starter_tracks = {}
    for ix in range(2, 6):
        starter_tracks[horiz_eids[(ix, 2)]] = 1  # Asphalt on North 2nd St
        starter_tracks[horiz_eids[(ix, 6)]] = 0  # Vignole Grass along South 2nd Riverside!
    for iz in range(2, 6):
        starter_tracks[vert_eids[(2, iz)]] = 1   # Asphalt on West 2nd Ave
        starter_tracks[vert_eids[(6, iz)]] = 0   # Vignole Grass on East 2nd Ave!
    # Add 2 real 3-way turnout branch spurs onto the Grid City starter loop!
    starter_tracks[horiz_eids[(1, 2)]] = 1
    starter_tracks[vert_eids[(6, 1)]] = 0

    starter_stops = [
        {"id": 1, "name": "中央公园西站 (Central Park W)", "edge_id": vert_eids[(2, 3)], "t": 0.5, "side": 1},
        {"id": 2, "name": "北二街商业站 (North 2nd Plaza)", "edge_id": horiz_eids[(4, 2)], "t": 0.5, "side": 1},
        {"id": 3, "name": "东二路金融中心站 (Financial Ctr)", "edge_id": vert_eids[(6, 3)], "t": 0.5, "side": 1},
        {"id": 4, "name": "南岸绿茵河畔站 (Riverside Lawn)", "edge_id": horiz_eids[(4, 6)], "t": 0.5, "side": 1},
    ]

    starter_network = {
        "tracks": [{"edge_id": eid, "bed_style": bst} for eid, bst in sorted(starter_tracks.items())],
        "stations": starter_stops,
        "lines": [
            {
                "id": 1,
                "name": "1号线 · 新城内环示范线",
                "color": [0.16, 0.68, 0.48],
                "model_key": "crrc-suzhou",
                "trams_count": 3,
                "sections": 3,
                "station_ids": [1, 2, 3, 4, 1],
            }
        ],
    }

    out = {
        "key": "grid",
        "name": "01  网格新城 (Grid City)",
        "bounds": [-560.0, -560.0, 560.0, 560.0],
        "graph_nodes": nodes,
        "graph_edges": edges,
        "starter_network": starter_network,
        "buildings": buildings,
        "areas": areas,
        "roads": roads,
        "crosswalks": crosswalks,
        "streetlamps": streetlamps[::2],
        "traffic_signals": [],
        "trees": trees,
        "landmarks": {},
    }
    out_path = os.path.join(DATA_DIR, "grid_city.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"Wrote Grid City -> {out_path}: {len(nodes)} junctions, {len(edges)} edges, {len(buildings)} buildings")


if __name__ == "__main__":
    build_tram_models()
    build_grid_city()
    build_seattle_expanded()
