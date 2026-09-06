#!/bin/bash
set -euo pipefail
ISLAND_ART_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISLAND_SOURCE="$ISLAND_ART_ROOT/artwork/shu25d/source"
ISLAND_CATALOG="$ISLAND_ART_ROOT/boringNotch/Assets.xcassets"
ISLAND_BACKUP="$ISLAND_ART_ROOT/artwork/shu25d/previous-icons"
mkdir -p "$ISLAND_BACKUP"
# Packaging only: proportional whole-image downsampling, no extraction/cropping.
for ISLAND_VARIANT in captain planting roasting; do
  ISLAND_INPUT="$ISLAND_VARIANT-hero.png"
  [[ "$ISLAND_VARIANT" != captain ]] || ISLAND_INPUT=holding-hero.png
  ISLAND_ICON="$ISLAND_CATALOG/ShuIcon-$ISLAND_VARIANT.imageset/icon.png"
  [[ -f "$ISLAND_BACKUP/$ISLAND_VARIANT.png" ]] || cp "$ISLAND_ICON" "$ISLAND_BACKUP/$ISLAND_VARIANT.png"
  /usr/bin/sips -z 1024 1024 "$ISLAND_SOURCE/$ISLAND_INPUT" --out "$ISLAND_ICON" >/dev/null
done
for ISLAND_SIZE in 16 32 64 128 256 512 1024; do
  /usr/bin/sips -z "$ISLAND_SIZE" "$ISLAND_SIZE" "$ISLAND_SOURCE/holding-hero.png" \
    --out "$ISLAND_CATALOG/AppIcon.appiconset/shu-$ISLAND_SIZE.png" >/dev/null
done
cp "$ISLAND_CATALOG/ShuIcon-captain.imageset/icon.png" "$ISLAND_CATALOG/logo2.imageset/shu-brand.png"
printf 'Exported three whole-image icons and all macOS dimensions.\n'
