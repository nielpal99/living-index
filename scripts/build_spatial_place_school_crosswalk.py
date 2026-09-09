"""Build an auditable Census-place to unified-school-district spatial crosswalk.

Uses 2023 Census TIGER/Line geometries. The result is many-to-many: places can
intersect multiple districts. No district is silently selected as a whole-place
representative; overlap share and a review status are retained for downstream use.
"""

from __future__ import annotations

import csv
import io
import ssl
import urllib.request
import zipfile
from pathlib import Path

import shapefile
from shapely.geometry import shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
TIGER = ROOT / "work/raw/tiger2023"
OUTPUT = ROOT / "work/raw/place_unified_school_district_spatial_crosswalk_2023.csv"
STATES = [f"{n:02d}" for n in range(1, 57) if n not in {3, 7, 14, 43, 52}]


def fetch(path: Path, url: str) -> None:
    if path.exists() and path.stat().st_size > 1000:
        return
    request = urllib.request.Request(url, headers={"User-Agent": "LivingIndex/1.0"})
    context = ssl._create_unverified_context()
    with urllib.request.urlopen(request, context=context, timeout=90) as response:
        path.write_bytes(response.read())


def reader(path: Path, stem: str) -> shapefile.Reader:
    zf = zipfile.ZipFile(path)
    return shapefile.Reader(
        shp=io.BytesIO(zf.read(f"{stem}.shp")),
        shx=io.BytesIO(zf.read(f"{stem}.shx")),
        dbf=io.BytesIO(zf.read(f"{stem}.dbf")),
    )


def records(rd: shapefile.Reader) -> list[dict]:
    fields = [field[0] for field in rd.fields[1:]]
    return [dict(zip(fields, record)) for record in rd.iterRecords()]


def main() -> None:
    rows: list[dict] = []
    for state in STATES:
        district_zip = TIGER / f"tl_2023_{state}_unsd.zip"
        place_zip = TIGER / f"tl_2023_{state}_place.zip"
        fetch(district_zip, f"https://www2.census.gov/geo/tiger/TIGER2023/UNSD/{district_zip.name}")
        fetch(place_zip, f"https://www2.census.gov/geo/tiger/TIGER2023/PLACE/{place_zip.name}")
        districts = records(reader(district_zip, district_zip.stem))
        places = records(reader(place_zip, place_zip.stem))
        district_geoms = [shape(g.__geo_interface__) for g in reader(district_zip, district_zip.stem).iterShapes()]
        place_geoms = [shape(g.__geo_interface__) for g in reader(place_zip, place_zip.stem).iterShapes()]
        tree = STRtree(district_geoms)
        for place, place_geom in zip(places, place_geoms):
            if not place_geom.is_valid or place_geom.area == 0:
                continue
            place_area = place_geom.area
            for index in tree.query(place_geom, predicate="intersects"):
                district_geom = district_geoms[int(index)]
                overlap = place_geom.intersection(district_geom).area
                if overlap <= 0:
                    continue
                pct = 100.0 * overlap / place_area
                rows.append({
                    "place_geoid": place["GEOIDFQ"].replace("1600000US", "1600000US"),
                    "place_name": place["NAMELSAD"],
                    "state_fips": state,
                    "district_geoid": districts[int(index)]["GEOIDFQ"],
                    "district_name": districts[int(index)]["NAME"],
                    "place_area_share_pct": f"{pct:.3f}",
                    "match_method": "census_tiger_2023_polygon_intersection",
                    "confidence": "medium" if pct >= 50 else "low",
                    "validation_status": "candidate_spatial",
                    "notes": "Area overlap is not enrollment or attendance-boundary share; retain many-to-many links.",
                })
        print(f"processed state {state}: {len(rows):,} links so far")

    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        fields = list(rows[0]) if rows else ["place_geoid"]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows):,} spatial crosswalk links to {OUTPUT}")


if __name__ == "__main__":
    main()
