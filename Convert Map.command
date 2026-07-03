#!/bin/bash
# FieldMap converter — turns a GeoTIFF or geospatial PDF into a .fieldmap tile package.
# Double-click this file, pick your map, and it produces mapname.fieldmap next to the original.

set -e

QGIS_BIN="/Applications/QGIS-final-4_0_3.app/Contents/MacOS"
export GDAL_DATA="/Applications/QGIS-final-4_0_3.app/Contents/Resources/qgis/gdal"
export PROJ_LIB="/Applications/QGIS-final-4_0_3.app/Contents/Resources/qgis/proj"
export PROJ_DATA="$PROJ_LIB"

if [ ! -x "$QGIS_BIN/gdal2tiles" ]; then
  echo "ERROR: QGIS (with bundled GDAL) not found at $QGIS_BIN"
  echo "Install QGIS or edit QGIS_BIN at the top of this script."
  read -p "Press enter to close"
  exit 1
fi

# Input file: from argument, or file picker dialog
INPUT="$1"
if [ -z "$INPUT" ]; then
  INPUT=$(osascript -e 'POSIX path of (choose file with prompt "Pick your GeoTIFF or geospatial PDF" of type {"tif","tiff","pdf","TIF","TIFF","PDF"})' 2>/dev/null || true)
fi
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "No file selected."
  read -p "Press enter to close"
  exit 1
fi

NAME=$(basename "$INPUT")
NAME="${NAME%.*}"
DIR=$(dirname "$INPUT")
WORK=$(mktemp -d)
TILES="$WORK/tiles"
OUT="$DIR/$NAME.fieldmap"

echo "═══════════════════════════════════════"
echo " FieldMap converter"
echo " Input:  $INPUT"
echo " Output: $OUT"
echo "═══════════════════════════════════════"

SRC="$INPUT"

# Geospatial PDFs: rasterize to GeoTIFF first at good DPI
if [[ "$INPUT" =~ \.[pP][dD][fF]$ ]]; then
  echo "→ Rasterizing PDF at 300 DPI…"
  "$QGIS_BIN/gdal_translate" --config GDAL_PDF_DPI 300 -of GTiff "$INPUT" "$WORK/from_pdf.tif"
  SRC="$WORK/from_pdf.tif"
fi

# Check georeferencing
if ! "$QGIS_BIN/gdalinfo" "$SRC" | grep -qE "Coordinate System is|GCP"; then
  echo "ERROR: This file has no georeferencing — FieldMap can't position GPS on it."
  read -p "Press enter to close"
  exit 1
fi

echo "→ Generating tile pyramid (this is the slow part — a few minutes for big maps)…"
"$QGIS_BIN/gdal2tiles" --xyz --processes=4 -r bilinear -w none "$SRC" "$TILES"

# Zoom range from generated directories
MINZ=$(ls "$TILES" | grep -E '^[0-9]+$' | sort -n | head -1)
MAXZ=$(ls "$TILES" | grep -E '^[0-9]+$' | sort -n | tail -1)

# WGS84 bounds from gdalinfo JSON
echo "→ Extracting bounds…"
"$QGIS_BIN/gdalinfo" -json "$SRC" > "$WORK/info.json"
python3 - "$WORK/info.json" "$TILES/metadata.json" "$NAME" "$MINZ" "$MAXZ" <<'PYEOF'
import json, sys
info = json.load(open(sys.argv[1]))
coords = info["wgs84Extent"]["coordinates"][0]
lons = [c[0] for c in coords]; lats = [c[1] for c in coords]
meta = {
  "name": sys.argv[3],
  "bounds": [min(lons), min(lats), max(lons), max(lats)],  # W S E N
  "minzoom": int(sys.argv[4]),
  "maxzoom": int(sys.argv[5]),
  "format": "png"
}
json.dump(meta, open(sys.argv[2], "w"))
print(f"   bounds: {meta['bounds']}")
print(f"   zoom:   {meta['minzoom']}–{meta['maxzoom']}")
PYEOF

echo "→ Packaging…"
rm -f "$OUT"
(cd "$TILES" && zip -q -r -0 "$OUT" .)
rm -rf "$WORK"

SIZE=$(du -h "$OUT" | cut -f1)
echo "═══════════════════════════════════════"
echo " ✓ Done: $OUT ($SIZE)"
echo ""
echo " Send this file to your phone (AirDrop /"
echo " email / Drive) and load it in FieldMap."
echo "═══════════════════════════════════════"
read -p "Press enter to close"
