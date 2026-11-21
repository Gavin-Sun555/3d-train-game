#!/usr/bin/env python3
"""
Download raw OpenStreetMap data for the Seattle game map from the public Overpass API, tile by tile,
into tools/osm_cache/raw/tile_<row>_<col>.json (git-ignored). Re-running skips tiles already fetched.

Area: Fremont / Wallingford / University of Washington (north) -> T-Mobile Park (south),
      Queen Anne (west) -> Lake Washington shore (east).
Map data (c) OpenStreetMap contributors, ODbL.
"""

import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
os.makedirs(RAW, exist_ok=True)

SOUTH, WEST, NORTH, EAST = 47.585, -122.378, 47.667, -122.276
ROWS, COLS = 4, 4
URL = "https://overpass-api.de/api/interpreter"

QUERY = """[out:json][timeout:240];
(
  way["highway"]({b});
  way["building"]({b});
  relation["building"]({b});
  way["building:part"]({b});
  way["landuse"]({b});
  way["leisure"]({b});
  way["natural"]({b});
  way["water"]({b});
  way["waterway"]({b});
  way["railway"]({b});
  way["man_made"]({b});
  way["amenity"]({b});
  way["place"]({b});
  relation["natural"]({b});
  relation["water"]({b});
  relation["landuse"]({b});
  relation["leisure"]({b});
  relation["amenity"]({b});
  node["natural"="tree"]({b});
  node["highway"~"street_lamp|traffic_signals"]({b});
  node["shop"]["name"]({b});
  node["amenity"]["name"]({b});
  node["tourism"]["name"]({b});
);
out body;
>;
out skel qt;"""


def fetch(r, c):
    out = os.path.join(RAW, f"tile_{r}_{c}.json")
    if os.path.exists(out) and os.path.getsize(out) > 1000:
        return "cached"
    s = SOUTH + (NORTH - SOUTH) * r / ROWS
    n = SOUTH + (NORTH - SOUTH) * (r + 1) / ROWS
    w = WEST + (EAST - WEST) * c / COLS
    e = WEST + (EAST - WEST) * (c + 1) / COLS
    bbox = f"{s:.5f},{w:.5f},{n:.5f},{e:.5f}"
    query = QUERY.replace("{b}", bbox)
    tmp = out + ".part"
    for attempt in range(5):
        # curl (system TLS) rather than urllib: some Python builds cannot negotiate TLS with the server
        res = subprocess.run(["curl", "-s", "-m", "320", "-A", "train-sim-map-builder/1.0", "--data-urlencode",
                              "data@-", URL, "-o", tmp], input=query.encode(), capture_output=True)
        try:
            with open(tmp, "rb") as f:
                body = f.read()
            json.loads(body)  # must be complete JSON (rate-limit pages are HTML)
            os.replace(tmp, out)
            return f"{len(body) / 1e6:.1f} MB"
        except Exception as ex:
            wait = 30 * (attempt + 1)
            print(f"  tile {r},{c} attempt {attempt + 1} failed (curl rc={res.returncode}, {str(ex)[:80]}); retry in {wait}s", flush=True)
            time.sleep(wait)
    return "FAILED"


if __name__ == "__main__":
    for r in range(ROWS):
        for c in range(COLS):
            res = fetch(r, c)
            print(f"tile {r},{c}: {res}", flush=True)
            if res != "cached":
                time.sleep(8)
    print("done")
    sys.exit(0)
