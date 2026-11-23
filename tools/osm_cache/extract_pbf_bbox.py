#!/usr/bin/env python3
"""
Zero-dependency pure-Python OSM PBF bounding-box extractor (stdlib only: struct + zlib).
Extracts all nodes, ways, and relations intersecting a lat/lon bounding box (plus all node
coordinates referenced by kept ways and all member ways/nodes of kept relations) into an
Overpass-compatible JSON file.
"""

import json
import os
import struct
import sys
import time
import zlib


def read_varint(buf, pos):
    val = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7


def zigzag(v):
    return (v >> 1) ^ -(v & 1)


def skip_field(buf, pos, wire):
    if wire == 0:
        _, pos = read_varint(buf, pos)
        return pos
    if wire == 1:
        return pos + 8
    if wire == 2:
        ln, pos = read_varint(buf, pos)
        return pos + ln
    if wire == 5:
        return pos + 4
    raise ValueError(f"Unsupported wire type {wire}")


def iter_pbf_blocks(path):
    """Yield (header_type, raw_blob_bytes) for every block in an OSM PBF file."""
    with open(path, "rb") as f:
        while True:
            hdr_len_b = f.read(4)
            if not hdr_len_b or len(hdr_len_b) < 4:
                break
            hdr_len = struct.unpack(">I", hdr_len_b)[0]
            hdr = f.read(hdr_len)
            btype = ""
            datasize = 0
            pos = 0
            while pos < len(hdr):
                tag, pos = read_varint(hdr, pos)
                fn, wt = tag >> 3, tag & 7
                if fn == 1 and wt == 2:
                    ln, pos = read_varint(hdr, pos)
                    btype = hdr[pos:pos + ln].decode("utf-8")
                    pos += ln
                elif fn == 3 and wt == 0:
                    datasize, pos = read_varint(hdr, pos)
                else:
                    pos = skip_field(hdr, pos, wt)
            blob = f.read(datasize)
            if btype != "OSMData":
                continue
            # Decode Blob: field 1 = raw, field 3 = zlib_data
            pos = 0
            raw = None
            while pos < len(blob):
                tag, pos = read_varint(blob, pos)
                fn, wt = tag >> 3, tag & 7
                if fn == 1 and wt == 2:
                    ln, pos = read_varint(blob, pos)
                    raw = blob[pos:pos + ln]
                    pos += ln
                elif fn == 3 and wt == 2:
                    ln, pos = read_varint(blob, pos)
                    raw = zlib.decompress(blob[pos:pos + ln])
                    pos += ln
                else:
                    pos = skip_field(blob, pos, wt)
            if raw is not None:
                yield raw


def parse_primitive_block(raw):
    """Parse PrimitiveBlock -> (strings, granularity, lat_offset, lon_offset, groups)."""
    strings = []
    groups = []
    granularity = 100
    lat_offset = 0
    lon_offset = 0
    pos = 0
    n = len(raw)
    while pos < n:
        tag, pos = read_varint(raw, pos)
        fn, wt = tag >> 3, tag & 7
        if fn == 1 and wt == 2:
            ln, pos = read_varint(raw, pos)
            end = pos + ln
            while pos < end:
                st, pos = read_varint(raw, pos)
                sfn, swt = st >> 3, st & 7
                if sfn == 1 and swt == 2:
                    sln, pos = read_varint(raw, pos)
                    strings.append(raw[pos:pos + sln].decode("utf-8", errors="replace"))
                    pos += sln
                else:
                    pos = skip_field(raw, pos, swt)
        elif fn == 2 and wt == 2:
            ln, pos = read_varint(raw, pos)
            groups.append(raw[pos:pos + ln])
            pos += ln
        elif fn == 17 and wt == 0:
            granularity, pos = read_varint(raw, pos)
        elif fn == 19 and wt == 0:
            lat_offset, pos = read_varint(raw, pos)
        elif fn == 20 and wt == 0:
            lon_offset, pos = read_varint(raw, pos)
        else:
            pos = skip_field(raw, pos, wt)
    return strings, granularity, lat_offset, lon_offset, groups


def parse_packed_varints(buf, start, end, signed=False):
    out = []
    pos = start
    while pos < end:
        v, pos = read_varint(buf, pos)
        out.append(zigzag(v) if signed else v)
    return out


def parse_dense_nodes(buf, strings, gran, lat_off, lon_off, bbox, want_ids, out_nodes, out_node_tags):
    s_lat, w_lon, n_lat, e_lon = bbox
    ids = []
    lats = []
    lons = []
    kv_buf = None
    pos = 0
    end = len(buf)
    while pos < end:
        tag, pos = read_varint(buf, pos)
        fn, wt = tag >> 3, tag & 7
        if fn == 1 and wt == 2:
            ln, pos = read_varint(buf, pos)
            ids = parse_packed_varints(buf, pos, pos + ln, signed=True)
            pos += ln
        elif fn == 8 and wt == 2:
            ln, pos = read_varint(buf, pos)
            lats = parse_packed_varints(buf, pos, pos + ln, signed=True)
            pos += ln
        elif fn == 9 and wt == 2:
            ln, pos = read_varint(buf, pos)
            lons = parse_packed_varints(buf, pos, pos + ln, signed=True)
            pos += ln
        elif fn == 10 and wt == 2:
            ln, pos = read_varint(buf, pos)
            kv_buf = parse_packed_varints(buf, pos, pos + ln, signed=False)
            pos += ln
        else:
            pos = skip_field(buf, pos, wt)

    nid = 0
    ilat = 0
    ilon = 0
    kv_i = 0
    kv_n = len(kv_buf) if kv_buf else 0
    scale = 1e-9 * gran
    lat_base = 1e-9 * lat_off
    lon_base = 1e-9 * lon_off

    # Quick block-level bbox check? Iterate tightly in C-speed int arithmetic!
    s_i = int((s_lat - lat_base) / scale)
    n_i = int((n_lat - lat_base) / scale)
    w_i = int((w_lon - lon_base) / scale)
    e_i = int((e_lon - lon_base) / scale)

    for idx in range(len(ids)):
        nid += ids[idx]
        ilat += lats[idx]
        ilon += lons[idx]
        in_box = (s_i <= ilat <= n_i and w_i <= ilon <= e_i)
        keep = in_box or (want_ids is not None and nid in want_ids)
        if keep:
            out_nodes[nid] = (round(lat_base + ilat * scale, 7), round(lon_base + ilon * scale, 7))
        if kv_buf:
            if keep:
                tags = {}
                while kv_i < kv_n and kv_buf[kv_i] != 0:
                    k = strings[kv_buf[kv_i]]
                    v = strings[kv_buf[kv_i + 1]]
                    tags[k] = v
                    kv_i += 2
                if kv_i < kv_n:
                    kv_i += 1
                if tags:
                    out_node_tags[nid] = tags
            else:
                while kv_i < kv_n and kv_buf[kv_i] != 0:
                    kv_i += 2
                if kv_i < kv_n:
                    kv_i += 1


def parse_way(buf, strings):
    wid = 0
    keys = []
    vals = []
    refs = []
    pos = 0
    end = len(buf)
    while pos < end:
        tag, pos = read_varint(buf, pos)
        fn, wt = tag >> 3, tag & 7
        if fn == 1 and wt == 0:
            wid, pos = read_varint(buf, pos)
        elif fn == 2 and wt == 2:
            ln, pos = read_varint(buf, pos)
            keys = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        elif fn == 3 and wt == 2:
            ln, pos = read_varint(buf, pos)
            vals = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        elif fn == 8 and wt == 2:
            ln, pos = read_varint(buf, pos)
            drefs = parse_packed_varints(buf, pos, pos + ln, signed=True)
            r = 0
            for d in drefs:
                r += d
                refs.append(r)
            pos += ln
        else:
            pos = skip_field(buf, pos, wt)
    tags = {strings[k]: strings[v] for k, v in zip(keys, vals)}
    return wid, refs, tags


def parse_relation(buf, strings):
    rid = 0
    keys, vals = [], []
    roles, memids, mtypes = [], [], []
    pos = 0
    end = len(buf)
    while pos < end:
        tag, pos = read_varint(buf, pos)
        fn, wt = tag >> 3, tag & 7
        if fn == 1 and wt == 0:
            rid, pos = read_varint(buf, pos)
        elif fn == 2 and wt == 2:
            ln, pos = read_varint(buf, pos)
            keys = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        elif fn == 3 and wt == 2:
            ln, pos = read_varint(buf, pos)
            vals = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        elif fn == 8 and wt == 2:
            ln, pos = read_varint(buf, pos)
            roles = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        elif fn == 9 and wt == 2:
            ln, pos = read_varint(buf, pos)
            dids = parse_packed_varints(buf, pos, pos + ln, signed=True)
            mid = 0
            for d in dids:
                mid += d
                memids.append(mid)
            pos += ln
        elif fn == 10 and wt == 2:
            ln, pos = read_varint(buf, pos)
            mtypes = parse_packed_varints(buf, pos, pos + ln)
            pos += ln
        else:
            pos = skip_field(buf, pos, wt)
    tags = {strings[k]: strings[v] for k, v in zip(keys, vals)}
    type_names = ("node", "way", "relation")
    members = []
    for r_i, m_id, m_t in zip(roles, memids, mtypes):
        members.append({
            "type": type_names[m_t] if m_t < 3 else "node",
            "ref": m_id,
            "role": strings[r_i] if r_i < len(strings) else "",
        })
    return rid, members, tags


def extract_bbox(pbf_path, out_json, bbox):
    t0 = time.time()
    # Expand node bbox slightly so ways/polygons crossing the border retain complete geometry
    pad = 0.015
    node_bbox = (bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad)

    nodes = {}
    node_tags = {}
    ways = {}
    rels = {}

    print(f"Pass 1: scanning {pbf_path} for bbox={bbox} ...", flush=True)
    n_blocks = 0
    for raw in iter_pbf_blocks(pbf_path):
        n_blocks += 1
        strings, gran, lat_off, lon_off, groups = parse_primitive_block(raw)
        for grp in groups:
            pos = 0
            gend = len(grp)
            while pos < gend:
                tag, pos = read_varint(grp, pos)
                fn, wt = tag >> 3, tag & 7
                if fn == 2 and wt == 2:  # DenseNodes
                    ln, pos = read_varint(grp, pos)
                    parse_dense_nodes(grp[pos:pos + ln], strings, gran, lat_off, lon_off, node_bbox, None, nodes, node_tags)
                    pos += ln
                elif fn == 3 and wt == 2:  # Way
                    ln, pos = read_varint(grp, pos)
                    wid, refs, tags = parse_way(grp[pos:pos + ln], strings)
                    pos += ln
                    if any(r in nodes for r in refs):
                        ways[wid] = (refs, tags)
                elif fn == 4 and wt == 2:  # Relation
                    ln, pos = read_varint(grp, pos)
                    rid, members, tags = parse_relation(grp[pos:pos + ln], strings)
                    pos += ln
                    # Keep multipolygons / buildings / water / parks / transit relations touching our area
                    rt = tags.get("type", "")
                    if rt in ("multipolygon", "building", "boundary", "route"):
                        if any((m["type"] == "way" and m["ref"] in ways) or (m["type"] == "node" and m["ref"] in nodes) for m in members):
                            rels[rid] = (members, tags)
                else:
                    pos = skip_field(grp, pos, wt)

    print(f"Pass 1 done in {time.time() - t0:.1f}s ({n_blocks} blocks): {len(nodes)} nodes, {len(ways)} ways, {len(rels)} rels", flush=True)

    # Check if any kept way references a node outside node_bbox (e.g. long lake/river/highway)
    missing_nodes = set()
    for refs, _ in ways.values():
        for r in refs:
            if r not in nodes:
                missing_nodes.add(r)
    if missing_nodes:
        print(f"Pass 2: fetching {len(missing_nodes)} boundary-crossing way nodes...", flush=True)
        for raw in iter_pbf_blocks(pbf_path):
            strings, gran, lat_off, lon_off, groups = parse_primitive_block(raw)
            for grp in groups:
                pos = 0
                gend = len(grp)
                while pos < gend:
                    tag, pos = read_varint(grp, pos)
                    fn, wt = tag >> 3, tag & 7
                    if fn == 2 and wt == 2:
                        ln, pos = read_varint(grp, pos)
                        parse_dense_nodes(grp[pos:pos + ln], strings, gran, lat_off, lon_off, (99, 99, -99, -99), missing_nodes, nodes, node_tags)
                        pos += ln
                    else:
                        pos = skip_field(grp, pos, wt)

    # Write Overpass-compatible JSON
    elements = []
    for nid, (lat, lon) in nodes.items():
        el = {"type": "node", "id": nid, "lat": lat, "lon": lon}
        if nid in node_tags:
            el["tags"] = node_tags[nid]
        elements.append(el)
    for wid, (refs, tags) in ways.items():
        el = {"type": "way", "id": wid, "nodes": refs}
        if tags:
            el["tags"] = tags
        elements.append(el)
    for rid, (members, tags) in rels.items():
        el = {"type": "relation", "id": rid, "members": members}
        if tags:
            el["tags"] = tags
        elements.append(el)

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump({"elements": elements}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {out_json} ({os.path.getsize(out_json) / 1e6:.1f} MB) in {time.time() - t0:.1f}s total!", flush=True)


if __name__ == "__main__":
    pbf = sys.argv[1]
    out = sys.argv[2]
    bbox = tuple(float(x) for x in sys.argv[3].split(","))
    extract_bbox(pbf, out, bbox)
