#!/usr/bin/env python3
"""
v4: extend the Seattle map from the downtown / SLU / Seattle Center core (v3) out to
Fremont / Wallingford / University of Washington (north), Queen Anne (west), Capitol Hill / Central District /
the Arboretum (east) and Pioneer Square / SoDo / T-Mobile Park (south).

The v3 map (tools/osm_cache/seattle_v3_base.json) is kept exactly as it is: every node, edge, building,
road, lamp ... keeps its id / index and geometry. Everything outside the v3 bounds is added from raw
OpenStreetMap data (tools/osm_cache/raw/tile_*.json, downloaded by osm_cache/fetch_overpass.py):

  * streets -> new buildable graph nodes / edges (appended), joined to the v3 streets that end at its border
  * buildings with real heights (OSM height / levels; type-, size- and neighbourhood-based estimates otherwise),
    pitched roofs for houses, recorded colours / materials / names
  * water, parks, woods, lawns, pitches, parking, piers; street trees; lamps & crosswalks; storefronts

Map data (c) OpenStreetMap contributors, ODbL.
"""

import json
import math
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(HERE, "osm_cache", "raw")
BASE = os.path.join(HERE, "osm_cache", "seattle_v3_base.json")
OUT = os.path.join(ROOT, "data", "seattle_expanded.json")

sys.path.insert(0, HERE)
from extract_demo_data import road_width_for, poly_min_dist_to_segs  # noqa: E402
from osm_storefronts import KIND_WIDTH, SKIP_KINDS, LANDMARK_NAMES  # noqa: E402

# Same projection as the v1-v3 data (2d-train-game seattle.json and osm_cache/parse_osm_tiles.py)
N0, W0, S0 = 47.645, -122.370, 47.592
KX = 111320.0 * math.cos((S0 + N0) * 0.5 * math.pi / 180.0)
KY = 110574.0


def proj(lat, lon):
    return ((lon - W0) * KX - 2420.0, (N0 - lat) * KY - 2960.0)


# v3 map bounds (game coordinates): left exactly as built
R0 = (-1420.0, -1010.0, 520.0, 1940.0)
R0_PAD = 35.0  # v3 streets run on up to 35 m past its bounds
# Full map: the downloaded box less a margin (ways are complete only inside it)
_bx0, _by1 = proj(47.585, -122.378)
_bx1, _by0 = proj(47.667, -122.276)
MARGIN = 40.0
BOUNDS = (round(_bx0 + MARGIN), round(_by0 + MARGIN), round(_bx1 - MARGIN), round(_by1 - MARGIN))


def in_rect(p, r, pad=0.0):
    return r[0] - pad <= p[0] <= r[2] + pad and r[1] - pad <= p[1] <= r[3] + pad


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
    """Sutherland-Hodgman clip of a (possibly concave) polygon against an axis-aligned rectangle."""
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


def outer_rects():
    """The extension ring as four non-overlapping rectangles around R0 (inside BOUNDS)."""
    bx0, by0, bx1, by1 = BOUNDS
    x0, y0, x1, y1 = R0
    return [
        (bx0, by0, bx1, y0),  # north strip
        (bx0, y1, bx1, by1),  # south strip
        (bx0, y0, x0, y1),  # west strip
        (x1, y0, bx1, y1),  # east strip
    ]


def rnd(p):
    return [round(p[0], 2), round(p[1], 2)]


class Grid:
    """Uniform grid of items keyed by bounding box, for neighbourhood queries."""

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


# ---------------------------------------------------------------------------------------------
# 1. Raw OSM
# ---------------------------------------------------------------------------------------------
def load_osm():
    nodes, ways, rels, poi_nodes = {}, {}, {}, {}
    files = sorted(f for f in os.listdir(RAW) if f.startswith("tile_") and f.endswith(".json"))
    if len(files) < 16:
        print(f"warning: only {len(files)} of 16 OSM tiles downloaded")
    for fn in files:
        with open(os.path.join(RAW, fn), encoding="utf-8") as f:
            d = json.load(f)
        for e in d["elements"]:
            t = e["type"]
            if t == "node":
                nodes[e["id"]] = proj(e["lat"], e["lon"])
                if e.get("tags"):
                    poi_nodes[e["id"]] = e["tags"]
            elif t == "way":
                if e["id"] not in ways or (e.get("tags") and not ways[e["id"]][1]):
                    ways[e["id"]] = (e.get("nodes", []), e.get("tags", {}))
            elif t == "relation":
                if e["id"] not in rels or (e.get("tags") and not rels[e["id"]][1]):
                    rels[e["id"]] = (e.get("members", []), e.get("tags", {}))
    print(f"OSM: {len(nodes)} nodes, {len(ways)} ways, {len(rels)} relations")
    return nodes, ways, rels, poi_nodes


def assemble_rings(member_ways, nodes, ways):
    """Join multipolygon member ways (ids) into closed rings of game points."""
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


# ---------------------------------------------------------------------------------------------
# 2. Streets -> graph
# ---------------------------------------------------------------------------------------------
ROAD_CLASSES = {"primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "trunk"}


def lanes_of(tags):
    def num(k):
        try:
            return int(str(tags.get(k, "")).split(";")[0])
        except ValueError:
            return None
    lanes = num("lanes")
    oneway = tags.get("oneway", "no")
    if oneway in ("yes", "true", "1", "-1") or tags.get("junction") == "roundabout":
        n = max(1, min(4, lanes or 1))
        return (0, n) if oneway == "-1" else (n, 0)
    f = num("lanes:forward")
    b = num("lanes:backward")
    if f is None and b is None:
        if lanes:
            f = max(1, lanes // 2)
            b = max(1, lanes - f)
        else:
            f = b = 1
    f = f if f is not None else max(1, (lanes or 2) - (b or 1))
    b = b if b is not None else max(1, (lanes or 2) - (f or 1))
    return (max(1, min(3, f)), max(1, min(3, b)))


def road_ways(nodes, ways):
    out = []
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in ROAD_CLASSES:
            continue
        if t.get("area") == "yes" or t.get("tunnel") in ("yes", "building_passage"):
            continue
        layer = str(t.get("layer", "0"))
        if t.get("bridge") and t.get("bridge") != "no":
            # low (bascule / short) bridges carry ordinary streets: Fremont, University, Montlake ...
            if cls == "trunk" or layer not in ("0", "1"):
                continue
        elif layer not in ("0", ""):
            continue
        pts = [r for r in refs if r in nodes]
        if len(pts) >= 2:
            out.append((wid, pts, t))
    return out


def clip_way_outside(ids, nodes, rect):
    """Pieces of a way outside `rect`, each a list of (node_key, (x, y)); boundary crossings become
    synthetic seam points ('seam', n)."""
    pieces = []
    cur = []
    seam_n = [0]

    def cross(a, b):
        # point where segment a->b crosses the rect boundary (a, b on opposite sides)
        best = None
        for t in _rect_hits(a, b, rect):
            if best is None or abs(t - 0.5) < abs(best - 0.5):
                best = t
        if best is None:
            best = 0.5
        return (a[0] + (b[0] - a[0]) * best, a[1] + (b[1] - a[1]) * best)

    prev_id = None
    for nid in ids:
        p = nodes[nid]
        inside = in_rect(p, rect)
        if prev_id is not None:
            pp = nodes[prev_id]
            pin = in_rect(pp, rect)
            if pin != inside:
                c = cross(pp, p)
                key = ("seam", nid, prev_id)
                if pin:  # entering the outside: start a piece at the crossing
                    cur = [(key, c)]
                else:  # leaving to the inside: end the piece at the crossing
                    cur.append((key, c))
                    if len(cur) >= 2:
                        pieces.append(cur)
                    cur = []
        if not inside:
            cur.append((nid, p))
        prev_id = nid
    if len(cur) >= 2:
        pieces.append(cur)
    seam_n[0] += 1
    return pieces


def _rect_hits(a, b, r):
    ts = []
    dx, dy = b[0] - a[0], b[1] - a[1]
    for x in (r[0], r[2]):
        if abs(dx) > 1e-9:
            t = (x - a[0]) / dx
            y = a[1] + dy * t
            if 0.0 <= t <= 1.0 and r[1] - 1e-6 <= y <= r[3] + 1e-6:
                ts.append(t)
    for y in (r[1], r[3]):
        if abs(dy) > 1e-9:
            t = (y - a[1]) / dy
            x = a[0] + dx * t
            if 0.0 <= t <= 1.0 and r[0] - 1e-6 <= x <= r[2] + 1e-6:
                ts.append(t)
    return ts


def build_street_graph(nodes, ways, base):
    r0p = (R0[0] - R0_PAD, R0[1] - R0_PAD, R0[2] + R0_PAD, R0[3] + R0_PAD)
    pieces = []  # (tags, [(key, (x, y)), ...])
    for wid, ids, t in road_ways(nodes, ways):
        # keep inside the full map box only
        if not any(in_rect(nodes[i], BOUNDS, 20.0) for i in ids):
            continue
        for pc in clip_way_outside(ids, nodes, r0p):
            pc = [kp for kp in pc if in_rect(kp[1], BOUNDS, 30.0)]
            if len(pc) >= 2:
                pieces.append((t, pc))

    use = defaultdict(int)
    pos = {}
    for t, pc in pieces:
        for k, p in pc:
            use[k] += 1
            pos[k] = p
        use[pc[0][0]] = max(use[pc[0][0]], 2)
        use[pc[-1][0]] = max(use[pc[-1][0]], 2)
    junc = [k for k, c in use.items() if c >= 2]

    # Union-find clustering of junction points within 15 m (grid accelerated)
    parent = {k: k for k in junc}

    def find(u):
        while parent[u] != u:
            parent[u] = parent[parent[u]]
            u = parent[u]
        return u

    cell = defaultdict(list)
    for k in junc:
        p = pos[k]
        cell[(int(p[0] // 15), int(p[1] // 15))].append(k)
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
                if math.hypot(pa[0] - pb[0], pa[1] - pb[1]) <= 15.0:
                    ra, rb = find(a), find(b)
                    if ra != rb:
                        parent[rb] = ra
    clusters = defaultdict(list)
    for k in junc:
        clusters[find(k)].append(k)
    jnodes = []  # {pos, streets, seam}
    jmap = {}
    for root in sorted(clusters, key=lambda r: (pos[r][0], pos[r][1])):
        mem = clusters[root]
        jx = sum(pos[k][0] for k in mem) / len(mem)
        jy = sum(pos[k][1] for k in mem) / len(mem)
        j = len(jnodes)
        for k in mem:
            jmap[k] = j
        jnodes.append({"pos": (jx, jy), "streets": set(), "seam": any(isinstance(k, tuple) for k in mem)})

    raw_edges = {}
    for t, pc in pieces:
        nm = t.get("name", "")
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
                    key = (min(ja, jb), max(ja, jb))
                    lf, lb = lf0, lb0
                    if ja > jb:
                        full = list(reversed(full))
                        lf, lb = lb0, lf0
                    prev = raw_edges.get(key)
                    if prev is not None and (prev["lf"] == 0 or prev["lb"] == 0) and (lf == 0 or lb == 0) \
                            and (prev["lf"] == 0) != (lf == 0):
                        prev["lf"] = max(prev["lf"], lf)
                        prev["lb"] = max(prev["lb"], lb)
                        prev["divided"] = True
                    elif prev is None or (nm and not prev["name"]) or w > prev["width"]:
                        raw_edges[key] = {"a": key[0], "b": key[1], "name": nm, "width": w, "lf": lf, "lb": lb,
                                          "length": elen, "pts": full, "cls": t.get("highway", ""),
                                          "bridge": bool(t.get("bridge")) and t.get("bridge") != "no"}
                    if nm:
                        jnodes[ja]["streets"].add(nm)
                        jnodes[jb]["streets"].add(nm)
            start = idx

    # --- Join to the v3 graph: a seam junction takes over the v3 street end it meets ---
    b_nodes = {n["id"]: n for n in base["graph_nodes"]}
    b_deg = defaultdict(int)
    b_names = defaultdict(set)
    for e in base["graph_edges"]:
        b_deg[e["a"]] += 1
        b_deg[e["b"]] += 1
        b_names[e["a"]].add(e["name"])
        b_names[e["b"]].add(e["name"])
    border = [n for n in base["graph_nodes"] if b_deg[n["id"]] <= 2 and not in_rect(n["pos"], R0, -60.0)]
    taken = set()
    j_to_base = {}
    for j, jn in enumerate(jnodes):
        if not jn["seam"]:
            continue
        best, best_s = None, 1e9
        for n in border:
            if n["id"] in taken:
                continue
            d = math.hypot(n["pos"][0] - jn["pos"][0], n["pos"][1] - jn["pos"][1])
            if d > 70.0:
                continue
            s = d - (25.0 if jn["streets"] & b_names[n["id"]] else 0.0) - (8.0 if b_deg[n["id"]] == 1 else 0.0)
            if s < best_s:
                best, best_s = n, s
        if best is not None:
            j_to_base[j] = best["id"]
            taken.add(best["id"])

    # --- Ids: v3 ids stay; new nodes / edges are appended ---
    next_nid = max(b_nodes) + 1
    next_eid = max(e["id"] for e in base["graph_edges"]) + 1
    j_ids = {}
    for j in range(len(jnodes)):
        if j in j_to_base:
            j_ids[j] = j_to_base[j]
    new_edges = []
    for key in sorted(raw_edges):
        ed = raw_edges[key]
        pts = list(ed["pts"])
        if ed["a"] in j_to_base:
            pts[0] = tuple(b_nodes[j_to_base[ed["a"]]]["pos"])
        if ed["b"] in j_to_base:
            pts[-1] = tuple(b_nodes[j_to_base[ed["b"]]]["pos"])
        new_edges.append((ed, pts))

    # Keep only what connects to the v3 network (one connected street graph)
    adj = defaultdict(set)
    for e in base["graph_edges"]:
        adj[("b", e["a"])].add(("b", e["b"]))
        adj[("b", e["b"])].add(("b", e["a"]))

    def gkey(j):
        return ("b", j_to_base[j]) if j in j_to_base else ("n", j)

    for ed, _ in new_edges:
        ka, kb = gkey(ed["a"]), gkey(ed["b"])
        adj[ka].add(kb)
        adj[kb].add(ka)
    start = ("b", base["graph_edges"][0]["a"])
    seen = {start}
    stack = [start]
    while stack:
        u = stack.pop()
        for v in adj[u]:
            if v not in seen:
                seen.add(v)
                stack.append(v)

    out_nodes, out_edges = [], []
    for j, jn in enumerate(jnodes):
        if j in j_to_base or ("n", j) not in seen:
            continue
        j_ids[j] = next_nid
        st = sorted(jn["streets"])
        out_nodes.append({"id": next_nid, "pos": rnd(jn["pos"]), "name": " & ".join(st[:2]) if st else f"路口 #{next_nid}"})
        next_nid += 1
    for ed, pts in new_edges:
        if gkey(ed["a"]) not in seen or gkey(ed["b"]) not in seen:
            continue
        elen = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        out_edges.append({
            "id": next_eid,
            "a": j_ids[ed["a"]],
            "b": j_ids[ed["b"]],
            "name": ed["name"] or "City Street",
            "width": round(ed["width"], 1),
            "lanes_f": ed["lf"],
            "lanes_b": ed["lb"],
            "divided": bool(ed.get("divided", False)),
            "length": round(elen, 1),
            "pts": [rnd(p) for p in pts],
        })
        if ed.get("bridge"):
            out_edges[-1]["bridge"] = True  # deck carried over the ground (freeway, canal ...): see Terrain decks
        next_eid += 1
    print(f"Streets: {len(out_nodes)} new junctions, {len(out_edges)} new edges, {len(j_to_base)} joined to v3 street ends "
          f"(of {sum(1 for j in jnodes if j['seam'])} border crossings)")
    return out_nodes, out_edges


# ---------------------------------------------------------------------------------------------
# 3. Buildings
# ---------------------------------------------------------------------------------------------
HOUSE_KINDS = {"house", "detached", "semidetached_house", "terrace", "bungalow", "cabin", "residential_house"}
SMALL_KINDS = {"garage", "garages", "shed", "carport", "hut", "roof", "kiosk", "toilets", "greenhouse"}
WESTLAKE = (0.0, 0.0)  # game origin is near Westlake Center: downtown core distance reference


def parse_len(v):
    if not v:
        return None
    s = str(v).strip().lower().replace(",", ".")
    try:
        if s.endswith("ft") or s.endswith("'"):
            return float(s.rstrip("ft'").strip()) * 0.3048
        return float(s.split()[0].rstrip("m"))
    except ValueError:
        return None


def obb(pts):
    """Minimum-area oriented box: (cx, cy, angle, half_len, half_wid) with half_len along `angle`."""
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


def estimate_height(t, area, cen):
    kind = t.get("building", "yes")
    h = parse_len(t.get("height"))
    lv = None
    try:
        lv = float(str(t.get("building:levels", "")).split(";")[0])
    except ValueError:
        lv = None
    roof_lv = 0.0
    try:
        roof_lv = float(t.get("roof:levels", 0) or 0)
    except ValueError:
        roof_lv = 0.0
    if h is None and lv is not None:
        h = lv * 3.3 + (1.2 if lv >= 3 else 0.6) + roof_lv * 2.4
    core = math.hypot(cen[0] - WESTLAKE[0], cen[1] - WESTLAKE[1])
    if h is None:
        if kind in SMALL_KINDS:
            h = 3.0 if kind != "roof" else 4.5
        elif kind == "houseboat":
            h = 4.2
        elif kind in HOUSE_KINDS:
            h = 7.0 if area < 220 else 8.5
        elif kind in ("apartments", "residential", "dormitory"):
            h = 10.5 if area < 450 else (14.5 if area < 1400 else (18.5 if area < 3500 else 22.0))
        elif kind in ("retail", "commercial", "supermarket"):
            h = 6.0 if area < 600 else 8.0
        elif kind in ("office",):
            h = 16.0 if area < 1500 else 24.0
        elif kind in ("industrial", "warehouse", "service", "storage_tank"):
            h = 9.0
        elif kind in ("school", "university", "college", "public", "civic", "government", "hospital"):
            h = 13.0 if area < 3000 else 18.0
        elif kind in ("church", "chapel", "cathedral"):
            h = 15.0
        elif kind in ("parking",):
            h = 12.0
        elif kind == "stadium":
            h = 21.0 if area < 6000 else 34.0
        else:  # building=yes: footprint says most of what we know
            if area < 140:
                h = 6.5
            elif area < 320:
                h = 8.0
            elif area < 900:
                h = 10.5
            elif area < 2500:
                h = 13.5
            else:
                h = 16.0
            if core < 1700 and area >= 900:
                h += 8.0  # denser fringe of downtown / First Hill / Pioneer Square
    return max(3.0, min(290.0, h))


def roof_for(t, kind, pts, area, h):
    """Pitched roofs for houses and small residential blocks (OSM roof:shape, else by footprint)."""
    shape = t.get("roof:shape", "")
    houseish = kind in HOUSE_KINDS or (kind in ("yes", "residential") and area < 260 and h <= 10.0)
    if shape in ("", "flat") and not houseish:
        return None
    if shape == "flat":
        return None
    o = obb(pts)
    if o is None:
        return None
    cx, cy, ang, hl, hw = o
    box_area = 4.0 * hl * hw
    if box_area <= 0 or abs(area) / box_area < 0.72 or hw < 2.5 or hl > 40.0:
        return None  # irregular / large footprints keep a flat roof
    if shape not in ("gabled", "hipped", "pyramidal", "skillion", "gambrel", "mansard", "half-hipped"):
        # Seattle houses: mostly gables (craftsman / foursquare); squarer footprints often hipped
        shape = "hipped" if hl < hw * 1.25 else "gabled"
    if shape in ("gambrel", "half-hipped"):
        shape = "gabled"
    if shape == "mansard":
        shape = "hipped"
    rh = max(1.6, min(5.5, hw * (0.62 if shape != "skillion" else 0.4)))
    return {"shape": shape, "h": round(rh, 2), "c": [round(cx, 2), round(cy, 2)], "a": round(ang, 4),
            "hl": round(hl, 2), "hw": round(hw, 2)}


# Landmark detail (scripts/city_builder.gd draws these): UW's Collegiate Gothic halls, churches, King Street
# Station's campanile, stadium roofs
UW_GOTHIC = {
    "Suzzallo Library", "Allen Library", "Denny Hall", "Savery Hall", "Gowen Hall", "Raitt Hall", "Smith Hall",
    "Miller Hall", "Thomson Hall", "Anderson Hall", "Johnson Hall", "Guggenheim Hall", "Gerberding Hall",
    "Mary Gates Hall", "Parrington Hall", "Hutchinson Hall", "Architecture Hall", "Clark Hall", "Lewis Hall",
    "Cunningham Hall", "Eagleson Hall", "Hansee Hall", "Music Building", "Art Building", "Condon Hall",
    "Bagley Hall", "Padelford Hall", "Sieg Hall", "Kane Hall", "Henry Art Gallery", "Engineering Annex",
}
UW_GOTHIC_STRICT = {"Suzzallo Library", "Allen Library", "Denny Hall", "Savery Hall", "Gowen Hall", "Raitt Hall",
                    "Smith Hall", "Miller Hall", "Thomson Hall", "Anderson Hall", "Johnson Hall", "Guggenheim Hall",
                    "Gerberding Hall", "Mary Gates Hall", "Parrington Hall", "Hutchinson Hall", "Architecture Hall",
                    "Clark Hall", "Lewis Hall", "Cunningham Hall", "Eagleson Hall", "Hansee Hall", "Music Building",
                    "Art Building", "Engineering Annex"}
STADIUM_ROOFS = {"T-Mobile Park": "retractable", "Lumen Field": "arch_canopy", "Husky Stadium": "cantilever"}


def steep_roof(pts, area, pitch, min_ratio=0.55):
    o = obb(pts)
    if o is None:
        return None
    cx, cy, ang, hl, hw = o
    if 4.0 * hl * hw <= 0 or abs(area) / (4.0 * hl * hw) < min_ratio or hw < 3.0:
        return None
    return {"shape": "gabled", "h": round(min(hw * pitch, 18.0), 2), "c": [round(cx, 2), round(cy, 2)], "a": round(ang, 4),
            "hl": round(hl, 2), "hw": round(hw, 2)}


def landmark_detail(b, t, pts, area, stadium_sites, part=False):
    nm = t.get("name", "")
    if nm in UW_GOTHIC_STRICT:
        b["lm"] = "suzzallo" if nm == "Suzzallo Library" else "uw_gothic"
        b["style"] = 1
        b.setdefault("colour", "#9d7a5b")  # UW tan brick with cast-stone trim
        rf = steep_roof(pts, area, 1.05 if nm == "Suzzallo Library" else 0.8, 0.4)
        if rf is not None:
            b["roof"] = rf
            b.setdefault("roof_colour", "#4a5552")  # slate / weathered copper
        return
    kind = t.get("building", "")
    if (kind in ("church", "cathedral", "chapel") or t.get("amenity") == "place_of_worship"
            or "Church" in nm or "Cathedral" in nm) and area > 140:
        b["lm"] = "church"
        b["style"] = 1
        if "Cathedral" in nm:
            b["twin_towers"] = True
        rf = steep_roof(pts, area, 0.95, 0.5)
        if rf is not None:
            b["roof"] = rf
            b.setdefault("roof_colour", "#3e4442")
        return
    if nm == "King Street Station" and not part:  # (its OSM 3D parts already hold the real clock tower)
        b["lm"] = "campanile"
        b["style"] = 1
        b.setdefault("colour", "#8f4f3c")
        return
    if b.get("kind") == "stadium" and "inner" in b:
        c = centroid(pts)
        for snm, ring in stadium_sites:
            if point_in_poly(c[0], c[1], ring):
                b["name"] = snm
                if snm in STADIUM_ROOFS:
                    b["stadium_roof"] = STADIUM_ROOFS[snm]
                break


def building_style(kind, h, area, t):
    mat = t.get("building:material", "")
    if kind in HOUSE_KINDS or kind == "houseboat" or (kind in ("yes", "residential") and area < 260 and h <= 10.0):
        return 3
    if mat in ("glass",) or h >= 60.0:
        return 0
    if mat in ("brick", "stone", "sandstone", "limestone") or kind in ("church", "school", "university", "civic"):
        return 1
    if kind in ("retail", "commercial") and h < 16:
        return 1
    return 2


def min_height_of(t):
    mh = parse_len(t.get("min_height"))
    if mh is None:
        try:
            mh = float(str(t.get("building:min_level", "")).split(";")[0]) * 3.3
        except ValueError:
            mh = None
    return mh or 0.0


def tagged_height(t):
    return bool(t.get("height") or t.get("building:levels"))


def build_buildings(nodes, ways, rels, base, road_grid):
    """OSM buildings outside the v3 bounds. Buildings mapped in 3D (building:part ways / type=building relations,
    e.g. Columbia Center's stepped tower) become their parts, each with its own height, base height and colour."""
    # --- 3D building parts ---
    parts = []  # (tags, ring)
    for wid, (refs, t) in ways.items():
        if t.get("building:part") and t.get("building:part") != "no" and len(refs) >= 4 and refs[0] == refs[-1]:
            pts = [nodes[r] for r in refs if r in nodes]
            if len(pts) >= 4:
                parts.append((t, pts[:-1]))
    for rid, (mem, t) in rels.items():
        if t.get("type") == "multipolygon" and t.get("building:part"):
            for ring in assemble_rings([m["ref"] for m in mem if m.get("type") == "way" and m.get("role") in ("outer", "")], nodes, ways):
                parts.append((t, ring))
    part_grid = Grid(40.0)
    for pi, (t, ring) in enumerate(parts):
        c = centroid(ring)
        part_grid.add(pi, c[0], c[1], c[0], c[1])
    part_cen = [centroid(r) for _, r in parts]

    # named stadium sites (leisure=stadium): name the stadium bowl inside them
    stadium_sites = []
    for wid, (refs, t) in ways.items():
        if t.get("leisure") == "stadium" and t.get("name") and len(refs) >= 4 and refs[0] == refs[-1]:
            stadium_sites.append((t["name"], [nodes[r] for r in refs if r in nodes]))
    for rid, (mem, t) in rels.items():
        if t.get("leisure") == "stadium" and t.get("name"):
            for ring in assemble_rings([m["ref"] for m in mem if m.get("type") == "way" and m.get("role") in ("outer", "")], nodes, ways):
                stadium_sites.append((t["name"], ring))

    # --- outlines (tags, ring, hole) ---
    outlines = []
    for rid, (mem, t) in rels.items():
        if t.get("type") == "building":  # 3D building relation: outline member + parts
            for m in mem:
                if m.get("type") == "way" and m.get("role") == "outline" and m["ref"] in ways:
                    refs, wt = ways[m["ref"]]
                    pts = [nodes[r] for r in refs if r in nodes]
                    if len(pts) >= 4 and refs[0] == refs[-1]:
                        merged = dict(wt)
                        merged.update({k: v for k, v in t.items() if k != "type"})
                        merged.pop("building:part", None)
                        merged.setdefault("building", "yes")
                        outlines.append((merged, pts[:-1], None))
            continue
        if "building" not in t or t.get("type") != "multipolygon" or t.get("building:part"):
            continue
        outers = [m["ref"] for m in mem if m.get("type") == "way" and m.get("role") in ("outer", "")]
        inners = assemble_rings([m["ref"] for m in mem if m.get("type") == "way" and m.get("role") == "inner"], nodes, ways)
        for ring in assemble_rings(outers, nodes, ways):
            hole = None
            if inners:
                cands = [r for r in inners if point_in_poly(*centroid(r), ring)]
                if cands:
                    hole = max(cands, key=lambda r: abs(poly_area(r)))
            outlines.append((t, ring, hole))
    for wid, (refs, t) in ways.items():
        if "building" not in t or t.get("building") == "no" or t.get("building:part"):
            continue
        pts = [nodes[r] for r in refs if r in nodes]
        if len(pts) >= 4 and refs[0] == refs[-1]:
            outlines.append((t, pts[:-1], None))

    # v3 buildings near its border (their footprints may poke out)
    bgrid = Grid(60.0)
    for bi, b in enumerate(base["buildings"]):
        xs = [p[0] for p in b["pts"]]
        ys = [p[1] for p in b["pts"]]
        if min(xs) < R0[0] + 80 or max(xs) > R0[2] - 80 or min(ys) < R0[1] + 80 or max(ys) > R0[3] - 80:
            bgrid.add((min(xs), min(ys), max(xs), max(ys), b["pts"], bi), min(xs), min(ys), max(xs), max(ys))
    replaced = set()  # v3 ring buildings (centred outside the v3 bounds) superseded by their real 3D OSM version
    used_parts = set()
    out = []
    taken = Grid(40.0)

    def overlaps(ob, bb, cen, pts):
        if ob[2] < bb[0] or ob[0] > bb[2] or ob[3] < bb[1] or ob[1] > bb[3]:
            return False
        return point_in_poly(cen[0], cen[1], ob[4]) or point_in_poly(*centroid(ob[4]), pts)

    for t, pts, hole in outlines:
        cen = centroid(pts)
        if not in_rect(cen, BOUNDS):
            continue
        core = in_rect(cen, R0)
        if core and in_rect(cen, R0, -80.0):
            continue
        area = abs(poly_area(pts))
        if area < 12.0:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bb = (min(xs), min(ys), max(xs), max(ys))
        grp = [pi for pi in part_grid.query(*bb) if pi not in used_parts and point_in_poly(part_cen[pi][0], part_cen[pi][1], pts)]
        kind = t.get("building", "yes")
        if kind == "yes" and t.get("amenity") in ("school", "university", "college"):
            kind = "school"
        if t.get("leisure") == "stadium" and kind in ("yes", "stadium"):
            kind = "stadium"
        h = estimate_height(t, area, cen)
        top_h = max([h] + [estimate_height(parts[pi][0], abs(poly_area(parts[pi][1])), part_cen[pi]) for pi in grp
                            if tagged_height(parts[pi][0])])
        blocked = False
        repl = []
        for ob in bgrid.query(*bb):
            if ob[5] in replaced or not overlaps(ob, bb, cen, pts):
                continue
            old_h = float(base["buildings"][ob[5]]["h"])
            if not in_rect(centroid(ob[4]), R0) and (grp or tagged_height(t)) and (grp or top_h > old_h * 1.5 + 3.0):
                repl.append(ob[5])
            else:
                blocked = True
                break
        if not blocked:
            for ob in taken.query(*bb):
                if overlaps(ob, bb, cen, pts):
                    blocked = True
                    break
        if blocked or (core and not repl):
            continue
        on_road = False
        for (ax, ay, bx, by, hw) in road_grid.query(bb[0] - 20, bb[1] - 20, bb[2] + 20, bb[3] + 20):
            lim = hw + 0.6
            if point_in_poly((ax + bx) * 0.5, (ay + by) * 0.5, pts):
                on_road = True
                break
            for p in pts:
                if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < lim:
                    on_road = True
                    break
            if on_road:
                break
        if on_road:
            continue
        replaced.update(repl)
        taken.add((bb[0], bb[1], bb[2], bb[3], pts), *bb)
        style = building_style(kind, top_h, area, t)
        if kind == "stadium" and hole is not None and abs(poly_area(hole)) > 0.12 * area:
            used_parts.update(grp)  # the stands' 3D parts are drawn as one raked bowl round the open field
            grp = []
        if grp:
            used_parts.update(grp)
            tallest = max(grp, key=lambda pi: estimate_height(parts[pi][0], abs(poly_area(parts[pi][1])), part_cen[pi])
                          if tagged_height(parts[pi][0]) else 0.0)
            for pi in grp:
                pt, ring = parts[pi]
                ph = estimate_height(pt, abs(poly_area(ring)), part_cen[pi]) if tagged_height(pt) else h
                pb = {"pts": [rnd(p) for p in ring], "h": round(ph, 1), "kind": kind, "style": style}
                mh = min_height_of(pt)
                if mh > 0.5 and mh < ph - 1.0:
                    pb["min_h"] = round(mh, 1)
                col = pt.get("building:colour") or t.get("building:colour")
                if col:
                    pb["colour"] = col
                if pi == tallest and t.get("name"):
                    pb["name"] = t["name"]
                    if t["name"] in LANDMARK_NAMES:
                        pb["lm"] = LANDMARK_NAMES[t["name"]]
                if mh <= 0.5:
                    landmark_detail(pb, t, ring, abs(poly_area(ring)), stadium_sites, part=True)
                if t.get("name") == "King Street Station":
                    pb["style"] = 1  # red brick (1906), not a glass tower because its campanile is 74 m tall
                    pb["colour"] = "#8f4f3c"
                    if ph > 50.0 and abs(poly_area(ring)) < 200.0:
                        pb["lm"] = "campanile_tower"  # the real clock-tower part: gets belfry, cap and clock faces
                out.append(pb)
            continue
        b = {"pts": [rnd(p) for p in pts], "h": round(h, 1), "kind": kind, "style": style}
        rf = roof_for(t, kind, pts, area, h)
        if rf is not None:
            b["roof"] = rf
        if kind == "stadium" and hole is not None and abs(poly_area(hole)) > 0.12 * area:
            b["inner"] = [rnd(p) for p in hole]  # the field: an open bowl, not a roof
        for k_src, k_dst in (("name", "name"), ("building:levels", "levels"), ("building:colour", "colour"),
                             ("building:material", "material"), ("roof:colour", "roof_colour"), ("start_date", "year")):
            if t.get(k_src):
                b[k_dst] = t[k_src]
        if b.get("name") in LANDMARK_NAMES:
            b["lm"] = LANDMARK_NAMES[b["name"]]
        landmark_detail(b, t, pts, area, stadium_sites)
        out.append(b)
    print(f"Buildings: {sum(1 for b in out if b.get('lm') in ('uw_gothic', 'suzzallo'))} UW Gothic, "
          f"{sum(1 for b in out if b.get('lm') == 'church')} churches, "
          f"{[b['name'] for b in out if b.get('stadium_roof')]} stadium roofs")
    print(f"Buildings: {len(out)} new ({sum(1 for b in out if 'roof' in b)} with pitched roofs, "
          f"{sum(1 for b in out if b['h'] >= 40)} >= 40 m, {len(used_parts)} 3D parts); "
          f"{len(replaced)} v3 ring buildings replaced by their 3D OSM version")
    return out, replaced


# ---------------------------------------------------------------------------------------------
# 4. Areas: water, parks, woods, lawns, pitches, parking
# ---------------------------------------------------------------------------------------------
def area_kind(t):
    if t.get("natural") == "water" or t.get("water") or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin"):
        return "water"
    if t.get("leisure") in ("park", "garden", "dog_park", "nature_reserve", "playground") or t.get("landuse") == "cemetery":
        return "park"
    if t.get("natural") in ("wood", "scrub") or t.get("landuse") == "forest":
        return "wood"
    if t.get("landuse") in ("grass", "recreation_ground", "village_green", "meadow") or t.get("leisure") == "common" or t.get("natural") in ("grassland", "wetland"):
        return "grass"
    if t.get("leisure") in ("pitch", "track", "sports_centre") and t.get("building") is None:
        return "sports"  # (v3 kept "pitch": drawn as paving there; the new map draws its playing fields as turf)
    if t.get("amenity") == "parking" and t.get("parking", "surface") == "surface" and t.get("building") is None:
        return "parking"
    if t.get("place") == "square" or (t.get("highway") == "pedestrian" and t.get("area") == "yes"):
        return "plaza"
    return None


def build_areas(nodes, ways, rels, base):
    raw = []  # (kind, ring, name, tags)
    for wid, (refs, t) in ways.items():
        k = area_kind(t)
        if k is None or len(refs) < 4 or refs[0] != refs[-1]:
            continue
        pts = [nodes[r] for r in refs if r in nodes]
        if len(pts) >= 4:
            raw.append((k, pts[:-1], t.get("name", ""), t))
    for rid, (mem, t) in rels.items():
        if t.get("type") not in ("multipolygon",):
            continue
        k = area_kind(t)
        if k is None:
            continue
        outers = [m["ref"] for m in mem if m.get("type") == "way" and m.get("role") in ("outer", "")]
        for ring in assemble_rings(outers, nodes, ways):
            raw.append((k, ring, t.get("name", ""), t))

    rects = outer_rects()
    new_areas = []
    for k, ring, nm, t in raw:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        if max(xs) < BOUNDS[0] or min(xs) > BOUNDS[2] or max(ys) < BOUNDS[1] or min(ys) > BOUNDS[3]:
            continue
        for r in rects:
            if max(xs) < r[0] or min(xs) > r[2] or max(ys) < r[1] or min(ys) > r[3]:
                continue
            cp = clip_poly_rect(ring, r)
            if len(cp) >= 3 and abs(poly_area(cp)) > 25.0:
                new_areas.append({"kind": k, "pts": [rnd(p) for p in cp]})

    # v3 areas: anything reaching past the v3 bounds is cut back to them (identical inside), and the part
    # outside is kept only for Elliott Bay (sea, which OSM models as coastline, not as an area)
    base_areas = []
    sea_parts = []
    for a in base["areas"]:
        pts = a["pts"]
        if all(in_rect(p, R0) for p in pts):
            base_areas.append(a)
            continue
        inner = clip_poly_rect(pts, R0)
        if len(inner) >= 3 and abs(poly_area(inner)) > 1.0:
            base_areas.append({"kind": a["kind"], "pts": [rnd(p) for p in inner]})
        if a["kind"] == "water" and min(p[0] for p in pts) <= -2470.0:
            # the 2d-train-game sea polygon is cut at x = -2480; Elliott Bay carries on west to the map edge
            ext = [(BOUNDS[0] - 10.0, p[1]) if p[0] <= -2479.0 else p for p in pts]
            for r in rects:
                cp = clip_poly_rect(ext, r)
                if len(cp) >= 3 and abs(poly_area(cp)) > 25.0:
                    sea_parts.append({"kind": "water", "pts": [rnd(p) for p in cp]})
    print(f"Areas: {len(new_areas)} new pieces + {len(sea_parts)} Elliott Bay pieces; "
          f"{sum(1 for a in base['areas'] if not all(in_rect(p, R0) for p in a['pts']))} v3 areas cut back to the v3 bounds")
    named_parks = [(nm, k, ring) for k, ring, nm, t in raw if nm and k in ("park", "plaza", "grass", "wood")]
    return base_areas, new_areas + sea_parts, named_parks


# ---------------------------------------------------------------------------------------------
# 5. Street furniture, trees, storefronts
# ---------------------------------------------------------------------------------------------
def lamps_and_crosswalks(new_edges, all_edges):
    deg = defaultdict(int)
    for e in all_edges:
        deg[e["a"]] += 1
        deg[e["b"]] += 1
    roads, cws, lamps = [], [], []
    for ed in new_edges:
        pts = ed["pts"]
        w = ed["width"]
        roads.append({"name": ed["name"], "width": w, "lanes_f": ed["lanes_f"], "lanes_b": ed["lanes_b"], "layer": 0, "pts": pts})
        if ed.get("bridge"):
            roads[-1]["bridge"] = True
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
        s = 16.0
        while s < L - 12.0:
            for side in (-1.0, 1.0):
                lamps.append([round(p0[0] + dx * s + nx * side * (w * 0.5 + 1.4), 2), round(p0[1] + dz * s + nz * side * (w * 0.5 + 1.4), 2)])
            s += 52.0
    seen = set()
    d_l = []
    for lp in lamps:
        c = (int(lp[0] // 22), int(lp[1] // 22))
        if c not in seen:
            seen.add(c)
            d_l.append(lp)
    seen = set()
    d_c = []
    for cw in cws:
        c = (int(cw["pos"][0] // 10), int(cw["pos"][1] // 10))
        if c not in seen:
            seen.add(c)
            d_c.append(cw)
    return roads, d_c, d_l


def street_trees(poi_nodes, nodes, road_grid, bld_grid):
    out = []
    seen = set()
    for nid, t in poi_nodes.items():
        if t.get("natural") != "tree":
            continue
        p = nodes[nid]
        if in_rect(p, R0) or not in_rect(p, BOUNDS):
            continue
        c = (int(p[0] // 4.5), int(p[1] // 4.5))
        if c in seen:
            continue
        ok = True
        for (ax, ay, bx, by, hw) in road_grid.query(p[0] - 16, p[1] - 16, p[0] + 16, p[1] + 16):
            if seg_dist(p[0], p[1], ax, ay, bx, by)[0] < hw + 1.2:
                ok = False
                break
        if ok:
            for ob in bld_grid.query(p[0], p[1], p[0], p[1]):
                if point_in_poly(p[0], p[1], ob[4]):
                    ok = False
                    break
        if ok:
            seen.add(c)
            out.append(rnd(p))
    print(f"Street trees: {len(out)}")
    return out


def poi_list(poi_nodes, nodes, ways):
    AMEN = {'restaurant', 'cafe', 'fast_food', 'bar', 'pub', 'bank', 'pharmacy', 'cinema', 'theatre', 'ice_cream',
            'food_court', 'nightclub', 'post_office', 'library', 'marketplace', 'clinic', 'dentist'}

    def keep(t):
        if 'name' not in t:
            return False
        return 'shop' in t or t.get('amenity') in AMEN or t.get('tourism') in ('hotel', 'museum', 'gallery')

    out = []
    for nid, t in poi_nodes.items():
        if keep(t):
            out.append({"name": t["name"], "kind": t.get("shop") or t.get("amenity") or t.get("tourism"),
                        "brand": t.get("brand", ""), "pos": nodes[nid], "level": t.get("level", "")})
    return [p for p in out if not in_rect(p["pos"], R0) and in_rect(p["pos"], BOUNDS)]


def storefronts_for(new_blds, idx_offset, pois, road_grid):
    """osm_storefronts.augment, grid-accelerated, for the new buildings only (b = index in the merged list)."""
    fgrid = Grid(30.0)
    for bi, b in enumerate(new_blds):
        if b["style"] == 3 or b["h"] < 5.0:
            continue
        poly = b["pts"]
        ccw = poly_area(poly) > 0.0
        for ei in range(len(poly)):
            a, c = poly[ei], poly[(ei + 1) % len(poly)]
            ex, ey = c[0] - a[0], c[1] - a[1]
            el = math.hypot(ex, ey)
            if el < 4.0:
                continue
            nx, ny = (ey / el, -ex / el) if ccw else (-ey / el, ex / el)
            mx, my = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5

            def rd(px, py):
                best = 1e9
                for (ax, ay, bx, by, hw) in road_grid.query(px - 30, py - 30, px + 30, py + 30):
                    best = min(best, seg_dist(px, py, ax, ay, bx, by)[0] - hw)
                return best
            d_mid = rd(mx, my)
            if d_mid > 14.0 or rd(mx + nx * 3.0, my + ny * 3.0) >= d_mid:
                continue
            fe = (bi, ei, a, c, (nx, ny), el)
            fgrid.add(fe, min(a[0], c[0]), min(a[1], c[1]), max(a[0], c[0]), max(a[1], c[1]))
    per_edge = defaultdict(list)
    for p in pois:
        kind = p.get("kind") or ""
        if kind in SKIP_KINDS:
            continue
        lvl = str(p.get("level", "")).split(";")[0].strip()
        if lvl not in ("", "0", "1"):
            continue
        px, py = p["pos"]
        best = None
        for fe in fgrid.query(px - 26, py - 26, px + 26, py + 26):
            bi, ei, a, c, n, el = fe
            d, t = seg_dist(px, py, a[0], a[1], c[0], c[1])
            inside = point_in_poly(px, py, new_blds[bi]["pts"])
            if d > (24.0 if inside else 14.0):
                continue
            score = d - (6.0 if inside else 0.0)
            if best is None or score < best[0]:
                best = (score, fe, t)
        if best is None:
            continue
        _, fe, t = best
        w = min(KIND_WIDTH.get(kind, 6.5), fe[5] - 0.8)
        if w >= 3.2:
            per_edge[(fe[0], fe[1])].append({"t": t, "w": w, "poi": p, "fe": fe})
    out = []
    for lst in per_edge.values():
        lst.sort(key=lambda s: s["t"])
        bi, ei, a, c, n, el = lst[0]["fe"]
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
                lo = max(lo, max(u1 for u0, u1 in used) + 0.35)
                if hi - lo < 3.2:
                    continue
            used.append((lo, hi))
            ux, uy = (c[0] - a[0]) / el, (c[1] - a[1]) / el
            p = s["poi"]
            out.append({"b": bi + idx_offset, "p0": [round(a[0] + ux * lo, 2), round(a[1] + uy * lo, 2)],
                        "p1": [round(a[0] + ux * hi, 2), round(a[1] + uy * hi, 2)], "n": [round(n[0], 4), round(n[1], 4)],
                        "name": p["name"], "kind": p.get("kind", ""), "brand": p.get("brand", "")})
    print(f"Storefronts: {len(out)} new")
    return out


def piers_of(ways, nodes):
    out = []
    for wid, (refs, t) in ways.items():
        if t.get("man_made") != "pier" or len(refs) < 4 or refs[0] != refs[-1]:
            continue
        pts = [nodes[r] for r in refs if r in nodes][:-1]
        if len(pts) >= 3 and not in_rect(centroid(pts), R0) and in_rect(centroid(pts), BOUNDS):
            out.append({"name": t.get("name", ""), "pts": [rnd(p) for p in pts]})
    return out


# ---------------------------------------------------------------------------------------------
# 6. Freeways (I-5, I-90, SR-520, SR-99 / Aurora, ramps): drawn structures with real deck heights
# ---------------------------------------------------------------------------------------------
TERRAIN_BIN = os.path.join(ROOT, "data", "seattle_terrain.bin")
TERRAIN_META = os.path.join(ROOT, "data", "seattle_terrain.json")


class Ground:
    def __init__(self):
        import struct
        with open(TERRAIN_META) as f:
            m = json.load(f)
        with open(TERRAIN_BIN, "rb") as f:
            b = f.read()
        self.x0, self.z0, self.cell, self.w, self.h = m["x0"], m["z0"], m["cell"], m["w"], m["h"]
        self.hs = struct.unpack("<%dh" % (self.w * self.h), b[: self.w * self.h * 2])

    def at(self, x, z):
        fx = min(max((x - self.x0) / self.cell, 0.0), self.w - 1.001)
        fz = min(max((z - self.z0) / self.cell, 0.0), self.h - 1.001)
        ix, iz = int(fx), int(fz)
        ux, uz = fx - ix, fz - iz
        k = iz * self.w + ix
        hs = self.hs
        g = (hs[k] * (1 - ux) + hs[k + 1] * ux) * (1 - uz) + (hs[k + self.w] * (1 - ux) + hs[k + self.w + 1] * ux) * uz
        return g * 0.1


FREEWAY_CLASSES = {"motorway", "motorway_link", "trunk", "trunk_link"}


def build_freeways(nodes, ways):
    if not os.path.exists(TERRAIN_BIN):
        print("Freeways: no terrain data, skipped")
        return []
    G = Ground()
    fw = []  # (wid, ids, tags, bridge, layer)
    for wid, (refs, t) in ways.items():
        cls = t.get("highway", "")
        if cls not in FREEWAY_CLASSES or t.get("tunnel") in ("yes", "building_passage") or t.get("area") == "yes":
            continue
        bridge = bool(t.get("bridge")) and t.get("bridge") != "no"
        try:
            layer = int(str(t.get("layer", "0")).split(";")[0])
        except ValueError:
            layer = 0
        if layer < 0 and t.get("tunnel"):
            continue
        # surface trunk streets are part of the buildable street graph already
        if cls == "trunk" and not bridge and layer in (0,):
            continue
        ids = [r for r in refs if r in nodes]
        if len(ids) < 2 or not any(in_rect(nodes[i], BOUNDS, 60.0) for i in ids):
            continue
        fw.append((wid, ids, t, bridge, max(0, layer)))
    # Heights: at-grade freeway nodes sit on the ground; a bridge spans between its ends (ground where it
    # meets an at-grade carriageway) and keeps one clearance per layer above whatever is underneath
    node_h = {}
    for wid, ids, t, bridge, layer in fw:
        if not bridge and layer == 0:
            for i in ids:
                node_h[i] = G.at(*nodes[i]) + 0.12
    joint_h = {}
    for wid, ids, t, bridge, layer in fw:
        if bridge or layer > 0:
            for i in (ids[0], ids[-1]):
                if i not in node_h:
                    p = nodes[i]
                    joint_h[i] = max(joint_h.get(i, -1e9), G.at(*p) + 6.6 * max(1, layer))
    out = []
    for wid, ids, t, bridge, layer in fw:
        pts = [nodes[i] for i in ids]
        dense = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, int(math.ceil(L / 8.0)))
            for k in range(1, n + 1):
                dense.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
        cum = [0.0]
        for a, b in zip(dense, dense[1:]):
            cum.append(cum[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
        L = cum[-1] or 1.0
        nm = t.get("name") or t.get("ref") or ""
        floating = "Floating" in nm or t.get("bridge:structure") == "floating"
        if bridge or layer > 0:
            ha = node_h.get(ids[0], joint_h.get(ids[0], G.at(*pts[0]) + 6.6))
            hb = node_h.get(ids[-1], joint_h.get(ids[-1], G.at(*pts[-1]) + 6.6))
            a_grade = ids[0] in node_h
            b_grade = ids[-1] in node_h
            clr = 6.6 * max(1, layer)
            ys = []
            for p, d in zip(dense, cum):
                base = ha + (hb - ha) * d / L
                ramp = 1.0
                if a_grade:
                    ramp = min(ramp, d / 70.0)
                if b_grade:
                    ramp = min(ramp, (L - d) / 70.0)
                g = G.at(*p)
                y = max(base, g + clr * max(0.0, min(1.0, ramp)))
                if floating:
                    y = min(y, max(g, 5.6) + 3.2) if ramp >= 1.0 else y
                ys.append(y)
        else:
            ys = [G.at(*p) + 0.12 for p in dense]
        # smooth the profile (elevation data is noisy at 8 m)
        sm = []
        for k in range(len(ys)):
            lo, hi = max(0, k - 2), min(len(ys), k + 3)
            sm.append(sum(ys[lo:hi]) / (hi - lo))
        sm[0], sm[-1] = ys[0], ys[-1]
        try:
            lanes = int(str(t.get("lanes", "")).split(";")[0])
        except ValueError:
            lanes = 1 if t.get("highway", "").endswith("_link") else (3 if t.get("highway") == "motorway" else 2)
        lanes = max(1, min(6, lanes))
        oneway = t.get("oneway", "yes" if t.get("highway", "").startswith("motorway") else "no") in ("yes", "1", "-1")
        width = lanes * 3.6 + (2.4 if oneway else 3.2) + (0 if oneway else 1.0)
        structure = ""
        if floating:
            structure = "floating"
        elif "Ship Canal" in nm or t.get("bridge:structure") == "truss" or (t.get("bridge:name") or "").startswith("George Washington"):
            structure = "truss"
        rec = {"pts": [[round(p[0], 2), round(p[1], 2), round(y, 2)] for p, y in zip(dense, sm)], "lanes": lanes,
               "w": round(width, 1), "oneway": oneway, "bridge": bool(bridge or layer > 0), "kind": t.get("highway", ""),
               "name": nm}
        if structure:
            rec["structure"] = structure
        # pieces of <= ~240 m so map tiles can take them
        P = rec["pts"]
        start = 0
        while start < len(P) - 1:
            end = min(len(P) - 1, start + 30)
            piece = dict(rec)
            piece["pts"] = P[start:end + 1]
            out.append(piece)
            start = end
    print(f"Freeways: {len(fw)} ways -> {len(out)} pieces "
          f"({sum(1 for r in out if r['bridge'])} elevated, {sum(1 for r in out if r.get('structure') == 'truss')} truss, "
          f"{sum(1 for r in out if r.get('structure') == 'floating')} floating)")
    return out


def main():
    with open(BASE, encoding="utf-8") as f:
        base = json.load(f)
    nodes, ways, rels, poi_nodes = load_osm()
    print("Map bounds:", BOUNDS)

    new_nodes, new_edges = build_street_graph(nodes, ways, base)
    all_edges = base["graph_edges"] + new_edges

    road_grid = Grid(40.0)
    for e in all_edges:
        pts = e["pts"]
        hw = float(e["width"]) * 0.5
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            road_grid.add((a[0], a[1], b[0], b[1], hw), min(a[0], b[0]) - hw, min(a[1], b[1]) - hw, max(a[0], b[0]) + hw, max(a[1], b[1]) + hw)

    new_blds, replaced = build_buildings(nodes, ways, rels, base, road_grid)
    base_blds = [dict(b) for b in base["buildings"]]
    for bi in replaced:
        # same index (saves / storefronts refer to building indices), no footprint: the 3D version is appended
        base_blds[bi] = {"pts": [], "h": 0.0, "kind": "replaced", "style": 2}
    bld_grid = Grid(40.0)
    for b in base_blds + new_blds:
        if not b["pts"]:
            continue
        xs = [p[0] for p in b["pts"]]
        ys = [p[1] for p in b["pts"]]
        bld_grid.add((min(xs), min(ys), max(xs), max(ys), b["pts"]), min(xs), min(ys), max(xs), max(ys))

    base_areas, new_areas, named_parks = build_areas(nodes, ways, rels, base)
    new_roads, new_cws, new_lamps = lamps_and_crosswalks(new_edges, all_edges)
    new_trees = street_trees(poi_nodes, nodes, road_grid, bld_grid)
    pois = poi_list(poi_nodes, nodes, ways)
    new_shops = storefronts_for(new_blds, len(base["buildings"]), pois, road_grid)
    plazas = [{"name": nm, "kind": k, "pts": [rnd(p) for p in ring]} for nm, k, ring in named_parks
              if not in_rect(centroid(ring), R0) and in_rect(centroid(ring), BOUNDS) and len(ring) <= 400]
    piers = piers_of(ways, nodes)
    freeways = build_freeways(nodes, ways)

    out = dict(base)
    out["bounds"] = [float(v) for v in BOUNDS]
    out["core_bounds"] = list(R0)  # the v3 map: built in full at load; the rest streams in around it
    out["graph_nodes"] = base["graph_nodes"] + new_nodes
    out["graph_edges"] = all_edges
    out["buildings"] = base_blds + new_blds
    out["areas"] = base_areas + new_areas
    out["roads"] = base["roads"] + new_roads
    out["crosswalks"] = base["crosswalks"] + new_cws
    out["streetlamps"] = base["streetlamps"] + new_lamps
    out["trees"] = base["trees"] + new_trees
    out["storefronts"] = base["storefronts"] + new_shops
    out["plazas"] = base["plazas"] + plazas
    out["piers"] = base["piers"] + piers
    out["freeways"] = freeways
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {OUT}: {os.path.getsize(OUT) / 1e6:.1f} MB — {len(out['graph_nodes'])} junctions, {len(out['graph_edges'])} edges, "
          f"{len(out['buildings'])} buildings, {len(out['areas'])} areas, {len(out['trees'])} trees, {len(out['streetlamps'])} lamps")


if __name__ == "__main__":
    main()
