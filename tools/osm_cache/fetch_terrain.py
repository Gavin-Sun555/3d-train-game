#!/usr/bin/env python3
"""
Real ground elevation for the Seattle map: Terrarium elevation tiles (AWS open data "elevation-tiles-prod",
USGS 3DEP / NED in the US; bare earth, metres above sea level) are downloaded into
tools/osm_cache/raw/terrain/ (git-ignored) and resampled to an 8 m grid in game coordinates:

  data/seattle_terrain.bin   int16 little-endian, height in decimetres, row-major (z rows, x columns)
  data/seattle_terrain.json  {"x0", "z0", "cell", "w", "h", "scale"}

Water below the surface (Elliott Bay bathymetry) is clamped; lakes keep their flat surface.
"""

import json
import math
import os
import struct
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(HERE, "raw", "terrain")
os.makedirs(RAW, exist_ok=True)
sys.path.insert(0, os.path.dirname(HERE))
from extend_seattle_map import proj, BOUNDS  # noqa: E402

Z = 14
URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
CELL = 8.0
SOUTH, WEST, NORTH, EAST = 47.580, -122.385, 47.672, -122.268


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lr = math.radians(lat)
    y = (1.0 - math.log(math.tan(lr) + 1.0 / math.cos(lr)) / math.pi) / 2.0 * n
    return x, y


def latlon_of(px, py, z):
    n = 2 ** z
    lon = px / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * py / n))))
    return lat, lon


def decode_png_rgb(data):
    """Minimal PNG decoder for 8-bit RGB / RGBA non-interlaced images (all five filter types)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = b""
    w = h = 0
    ch = 3
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (2, 6)
            ch = 3 if ctype == 2 else 4
        elif typ == b"IDAT":
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        f = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, out


def main():
    x0f, y0f = tile_xy(NORTH, WEST, Z)
    x1f, y1f = tile_xy(SOUTH, EAST, Z)
    tiles = {}
    for tx in range(int(x0f), int(x1f) + 1):
        for ty in range(int(y0f), int(y1f) + 1):
            fn = os.path.join(RAW, f"{Z}_{tx}_{ty}.png")
            if not os.path.exists(fn) or os.path.getsize(fn) < 1000:
                subprocess.run(["curl", "-s", "-m", "60", "-A", "train-sim-map-builder/1.0", "-o", fn,
                                URL.format(z=Z, x=tx, y=ty)], check=False)
            with open(fn, "rb") as f:
                w, h, ch, px = decode_png_rgb(f.read())
            hm = [0.0] * (w * h)
            for k in range(w * h):
                r, g, b = px[k * ch], px[k * ch + 1], px[k * ch + 2]
                hm[k] = (r * 256.0 + g + b / 256.0) - 32768.0
            tiles[(tx, ty)] = (w, hm)
    print(f"{len(tiles)} terrain tiles (z{Z})")

    def elev_at(lat, lon):
        fx, fy = tile_xy(lat, lon, Z)
        tx, ty = int(fx), int(fy)
        w, hm = tiles[(tx, ty)]
        u = (fx - tx) * w - 0.5
        v = (fy - ty) * w - 0.5

        def sample(ix, iy):
            # neighbouring tiles at the edges
            ttx, tty = tx, ty
            if ix < 0:
                ttx, ix = tx - 1, ix + w
            elif ix >= w:
                ttx, ix = tx + 1, ix - w
            if iy < 0:
                tty, iy = ty - 1, iy + w
            elif iy >= w:
                tty, iy = ty + 1, iy - w
            t = tiles.get((ttx, tty))
            if t is None:
                ix = min(max(ix, 0), w - 1)
                iy = min(max(iy, 0), w - 1)
                t = tiles[(tx, ty)]
            return t[1][iy * t[0] + ix]
        iu, iv = int(math.floor(u)), int(math.floor(v))
        fu, fv = u - iu, v - iv
        h00 = sample(iu, iv)
        h10 = sample(iu + 1, iv)
        h01 = sample(iu, iv + 1)
        h11 = sample(iu + 1, iv + 1)
        return (h00 * (1 - fu) + h10 * fu) * (1 - fv) + (h01 * (1 - fu) + h11 * fu) * fv

    # Game grid -> lat / lon (inverse of extend_seattle_map.proj, which is linear)
    x00, z00 = proj(47.645, -122.370)
    x10, _ = proj(47.645, -122.360)
    _, z01 = proj(47.635, -122.370)
    dx_dlon = (x10 - x00) / 0.010
    dz_dlat = (z01 - z00) / -0.010
    gx0 = BOUNDS[0] - 200.0
    gz0 = BOUNDS[1] - 200.0
    gw = int((BOUNDS[2] - BOUNDS[0] + 400.0) / CELL) + 1
    gh = int((BOUNDS[3] - BOUNDS[1] + 400.0) / CELL) + 1
    out = bytearray()
    lo, hi = 1e9, -1e9
    for j in range(gh):
        z = gz0 + j * CELL
        lat = 47.645 + (z - z00) / dz_dlat
        for i in range(gw):
            x = gx0 + i * CELL
            lon = -122.370 + (x - x00) / dx_dlon
            e = max(-8.0, elev_at(lat, lon))  # Elliott Bay floor: clamped just under the water plane
            lo, hi = min(lo, e), max(hi, e)
            out += struct.pack("<h", int(round(e * 10.0)))
    with open(os.path.join(ROOT, "data", "seattle_terrain.bin"), "wb") as f:
        f.write(out)
    meta = {"x0": gx0, "z0": gz0, "cell": CELL, "w": gw, "h": gh, "scale": 0.1}
    with open(os.path.join(ROOT, "data", "seattle_terrain.json"), "w") as f:
        json.dump(meta, f)
    print(f"terrain grid {gw} x {gh} @ {CELL} m, {lo:.1f} .. {hi:.1f} m, {len(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
