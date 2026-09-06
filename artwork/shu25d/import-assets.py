#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prepare/import Captain Shu layers, preserving every source image.

Default is a read-only plan. --apply requires an explicit approval note.
Do not run --apply until the user has authorized local image editing.
Pillow + NumPy are needed only for --apply; macOS Vision handles complex masks.
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parents[1]
SOURCES = DIRECTORY / "source"
PROCESSED = DIRECTORY / "processed"
QA = ROOT / "build/validation/shu/alpha"
CATALOG = ROOT / "boringNotch/Assets.xcassets"
RUNTIME_MANIFEST = ROOT / "boringNotch/components/Island/Shu25DAssets.json"
PLAN_PATH = DIRECTORY / "import-plan.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write derived PNGs/catalogs after user approval")
    parser.add_argument("--approval-note", help="Record the user authorization; required with --apply")
    parser.add_argument("--only", action="append", help="Process one asset id; may be repeated")
    parser.add_argument("--preserve-raw-alpha", action="store_true", help="Compare raw-potato's existing alpha without Vision glow removal")
    parser.add_argument("--no-catalog", action="store_true", help="Write processed/QA files without changing the app asset catalog or manifest")
    return parser.parse_args()


def choose_source(spec):
    for filename in spec["sources"]:
        candidate = SOURCES / filename
        if candidate.is_file():
            return candidate
    if spec.get("optional"):
        return None
    raise RuntimeError("Missing required source for " + spec["id"] + ": " + ", ".join(spec["sources"]))


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def save_png(image, path):
    if path.resolve().is_relative_to(SOURCES.resolve()):
        raise RuntimeError("Refusing to write inside the immutable source directory")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    image.save(temporary, format="PNG", optimize=True)
    temporary.replace(path)


def cyan_matte(image):
    """Unmix the cyan backing, preserving warm skin, red fabric and green props.

    The key channel is min(G, B) - R. This differs from indiscriminately deleting
    green pixels, which would destroy the sprout and watering can. Background
    colour is estimated from the four corners; near-edge cyan is unmixed before
    storing straight-alpha RGB. No treatment is applied to opaque interiors.
    """
    pixels = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    rgb = pixels[..., :3]
    size = max(4, min(image.size) // 40)
    corners = np.concatenate([rgb[:size, :size].reshape(-1, 3), rgb[:size, -size:].reshape(-1, 3),
                              rgb[-size:, :size].reshape(-1, 3), rgb[-size:, -size:].reshape(-1, 3)])
    backing = np.median(corners, axis=0)
    key_strength = min(backing[1], backing[2]) - backing[0]
    if key_strength < 0.45:
        raise RuntimeError("Source is not on the expected cyan backing; use Vision instead")
    dominance = np.minimum(rgb[..., 1], rgb[..., 2]) - rgb[..., 0]
    unmix_alpha = np.clip(1.0 - dominance / key_strength, 0.0, 1.0)
    # Generated cyan backgrounds vary by roughly 3–9% across their gradients.
    # Remove that low-confidence backing before trimming, while keeping a
    # continuous matte at the silhouette instead of leaving a faint rectangle.
    alpha = np.clip((unmix_alpha - 0.10) / 0.90, 0.0, 1.0) * pixels[..., 3]
    # Decontaminate only pixels whose matte contains some of the cyan backing.
    unassociated = (rgb - (1.0 - unmix_alpha[..., None]) * backing) / np.maximum(unmix_alpha[..., None], 0.025)
    corrected = np.where((alpha < 0.998)[..., None], np.clip(unassociated, 0.0, 1.0), rgb)
    corrected[alpha <= 0] = 0
    rgba = np.concatenate([corrected, alpha[..., None]], axis=2)
    return Image.fromarray(np.uint8(np.round(np.clip(rgba, 0, 1) * 255)), "RGBA"), {
        "method": "cyan-unmix", "estimatedBackingRGB": [round(float(c), 6) for c in backing]
    }


def vision_matte(image, source, asset_id):
    helper = ROOT / "build/tools/ShuForegroundMask"
    swift_source = DIRECTORY / "ShuForegroundMask.swift"
    if not helper.is_file() or helper.stat().st_mtime < swift_source.stat().st_mtime:
        helper.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
                        str(ROOT / "build/tools/ModuleCache"), str(swift_source), "-o", str(helper)], check=True)
    mask_path = QA / (asset_id + "-vision-mask.png")
    subprocess.run([str(helper), str(source), str(mask_path)], check=True)
    mask = Image.open(mask_path).convert("L").filter(ImageFilter.MinFilter(3))
    if mask.size != image.size:
        raise RuntimeError("Vision mask dimensions differ from source; review image orientation")
    rgba = image.convert("RGBA")
    # Retain legitimate source transparency while removing background and glow.
    alpha = ImageChops.multiply(rgba.getchannel("A"), mask)
    rgba.putalpha(alpha)
    return rgba, {"method": "vision-foreground-intersect-source-alpha", "maskSHA256": sha256(mask_path)}


def normalized_point(point, size):
    return (point[0] * size[0], point[1] * size[1])


def isolate_arm(image, spec):
    """Extract the open arm, then rotate it to shoulder-up / hand-down neutral.

    Supersampled polygon masks preserve the visible silhouette; only the sleeve
    join is manually cut and is subsequently hidden under the body layer.
    Shoulder and hand landmarks undergo the same rotation and crop as the PNG.
    """
    arm = spec["arm"]
    points = [normalized_point(point, image.size) for point in arm["polygon"]]
    supersampling = 4
    mask = Image.new("L", (image.width * supersampling, image.height * supersampling))
    ImageDraw.Draw(mask).polygon([(x * supersampling, y * supersampling) for x, y in points], fill=255)
    mask = mask.resize(image.size, Image.Resampling.LANCZOS)
    isolated = image.copy()
    isolated.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
    shoulder = normalized_point(arm["shoulder"], image.size)
    hand = normalized_point(arm["hand"], image.size)
    angle = math.degrees(math.atan2(hand[1] - shoulder[1], hand[0] - shoulder[0])) - 90.0
    turned = isolated.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    radians = math.radians(angle)

    def transform(point):
        x, y = point[0] - image.width / 2, point[1] - image.height / 2
        return (math.cos(radians) * x + math.sin(radians) * y + turned.width / 2,
                -math.sin(radians) * x + math.cos(radians) * y + turned.height / 2)

    return turned, {"pivot": transform(shoulder), "hand": transform(hand)}, {"neutralRotationDegrees": angle}


def trim_with_padding(image, points, fraction):
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value > 4 else 0).getbbox()
    if not bounds:
        raise RuntimeError("Foreground mask is empty")
    crop = image.crop(bounds)
    pad_x, pad_y = max(1, math.ceil(crop.width * fraction)), max(1, math.ceil(crop.height * fraction))
    result = Image.new("RGBA", (crop.width + pad_x * 2, crop.height + pad_y * 2), (0, 0, 0, 0))
    result.alpha_composite(crop, (pad_x, pad_y))
    translated = {key: [(point[0] - bounds[0] + pad_x) / result.width,
                        (point[1] - bounds[1] + pad_y) / result.height] for key, point in points.items()}
    for key, point in translated.items():
        if not all(0 <= coordinate <= 1 for coordinate in point):
            raise RuntimeError("Landmark " + key + " falls outside trimmed asset")
    return result, translated, {"untrimmedBounds": list(bounds), "paddingPixels": [pad_x, pad_y]}


def check_alpha(image):
    alpha = np.asarray(image.getchannel("A"))
    opaque_fraction = float(np.mean(alpha >= 250))
    visible_fraction = float(np.mean(alpha > 4))
    if not np.any(alpha == 0) or visible_fraction < 0.01 or visible_fraction > 0.96:
        raise RuntimeError("Derived alpha is empty or still covers nearly the entire rectangle")
    return {"alphaMin": int(alpha.min()), "alphaMax": int(alpha.max()),
            "visibleFraction": visible_fraction, "opaqueFraction": opaque_fraction}


def qa_composites(image, asset_id):
    preview = image.copy()
    preview.thumbnail((560, 640), Image.Resampling.LANCZOS)
    tile_width, tile_height = 600, 700
    sheet = Image.new("RGB", (tile_width * 3, tile_height), (30, 30, 30))
    for index, color in enumerate([(18, 18, 18, 255), (249, 241, 222, 255), (158, 194, 154, 255)]):
        tile = Image.new("RGBA", (tile_width, tile_height), color)
        tile.alpha_composite(preview, ((tile_width - preview.width) // 2, 32 + (640 - preview.height) // 2))
        ImageDraw.Draw(tile).text((16, tile_height - 28), asset_id + [" / dark", " / cream", " / garden"][index], fill=(255, 255, 255) if index == 0 else (30, 30, 30))
        sheet.paste(tile.convert("RGB"), (index * tile_width, 0))
    save_png(sheet, QA / (asset_id + "-backgrounds.png"))


def import_one(spec, source, plan, args):
    source_hash = sha256(source)
    original = Image.open(source).convert("RGBA")
    method = spec.get("matteBySource", {}).get(source.name, spec["matte"])
    if spec["id"] == "raw-potato" and args.preserve_raw_alpha:
        method = "existing-alpha"
    if method == "cyan":
        image, matte_record = cyan_matte(original)
    elif method == "vision":
        image, matte_record = vision_matte(original, source, spec["id"])
    elif method == "existing-alpha":
        image, matte_record = original.copy(), {"method": "existing-source-alpha"}
    else:
        raise RuntimeError("Unknown matte method " + method)
    points, arm_record = {}, {}
    if "arm" in spec:
        image, points, arm_record = isolate_arm(image, spec)
    else:
        for field, key in [("pivotSource", "pivot"), ("emitterSource", "emitter")]:
            if field in spec:
                points[key] = normalized_point(spec[field], image.size)
    image, points, trim_record = trim_with_padding(image, points, plan["paddingFraction"])
    points.setdefault("pivot", spec.get("pivotTrimmed", [0.5, 0.5]))
    alpha_record = check_alpha(image)
    processed_path = PROCESSED / (spec["id"] + ".png")
    save_png(image, processed_path)
    qa_composites(image, spec["id"])
    catalog_name = "Shu25D-" + spec["id"]
    if not args.no_catalog:
        catalog_image = image.copy()
        maximum = plan["catalogMaximumDimension"]
        catalog_image.thumbnail((maximum, maximum), Image.Resampling.LANCZOS)
        target = CATALOG / (catalog_name + ".imageset")
        save_png(catalog_image, target / (spec["id"] + ".png"))
        atomic_json(target / "Contents.json", {
            "images": [{"filename": spec["id"] + ".png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1}
        })
    if sha256(source) != source_hash:
        raise RuntimeError("Immutable source changed during import: " + source.name)
    manifest_entry = {"id": spec["id"], "catalogName": catalog_name, **points}
    visible = image.getchannel("A").point(lambda value: 255 if value > 4 else 0).getbbox()
    manifest_entry["contentBounds"] = [visible[0] / image.width, visible[1] / image.height,
                                        (visible[2] - visible[0]) / image.width, (visible[3] - visible[1]) / image.height]
    if "rigShoulder" in spec:
        manifest_entry["rigShoulder"] = spec["rigShoulder"]
    record = {"id": spec["id"], "source": str(source.relative_to(ROOT)), "sourceSHA256": source_hash,
              "sourceSize": list(original.size), "outputSize": list(image.size),
              "processedSHA256": sha256(processed_path), **matte_record, **arm_record, **trim_record, **alpha_record,
              "landmarks": points}
    return manifest_entry, record


def main():
    args = arguments()
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    known_ids = {spec["id"] for spec in plan["assets"]}
    if args.only and not set(args.only).issubset(known_ids):
        raise RuntimeError("Unknown asset id: " + ", ".join(set(args.only) - known_ids))
    selected = [spec for spec in plan["assets"] if not args.only or spec["id"] in args.only]
    selected = [(spec, choose_source(spec)) for spec in selected]
    if not args.apply:
        print("READ-ONLY PLAN. No images, catalogs or manifests will be changed.")
        for spec, source in selected:
            print(spec["id"] + ": " + (source.name if source else "optional source not available"))
        print("After explicit user approval: --apply --approval-note '...'")
        return
    if not args.approval_note or not args.approval_note.strip():
        raise RuntimeError("--apply requires --approval-note recording explicit user authorization")
    # Imports, Vision execution and all directory/image writes start only here.
    global Image, ImageChops, ImageDraw, ImageFilter, np
    try:
        from PIL import Image, ImageChops, ImageDraw, ImageFilter
        import numpy as np
    except ImportError as error:
        raise RuntimeError("Run with a Python interpreter that has Pillow and NumPy; see README.md") from error
    QA.mkdir(parents=True, exist_ok=True)
    records, updates = [], {}
    source_hashes_before = {str(path): sha256(path) for path in SOURCES.glob("*.png")}
    for spec, source in selected:
        if source is None:
            continue
        entry, record = import_one(spec, source, plan, args)
        updates[entry["id"]] = entry
        records.append(record)
        print("Imported " + spec["id"] + " -> " + str(record["outputSize"]))
    if not args.no_catalog:
        runtime = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
        existing = {entry["id"]: entry for entry in runtime["assets"]}
        for asset_id, update in updates.items():
            existing.setdefault(asset_id, {}).update(update)
        runtime["assets"] = list(existing.values())
        atomic_json(RUNTIME_MANIFEST, runtime)
    for filename, before in source_hashes_before.items():
        if sha256(Path(filename)) != before:
            raise RuntimeError("Source changed during processing: " + filename)
    record_path = PROCESSED / "import-record.json"
    record = json.loads(record_path.read_text()) if record_path.exists() else {"runs": []}
    record["runs"].append({
        "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "approvalNote": args.approval_note.strip(), "catalogWritten": not args.no_catalog,
        "pythonVersion": sys.version, "pillowVersion": getattr(Image, "__version__", "unknown"), "numpyVersion": np.__version__,
        "macOSVersion": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
        "planSHA256": sha256(PLAN_PATH), "scriptSHA256": sha256(Path(__file__)),
        "visionSourceSHA256": sha256(DIRECTORY / "ShuForegroundMask.swift"), "assets": records,
        "limitations": "Alpha statistics cannot prove clean edges. Inspect QA backgrounds and native-size timeline render before accepting. Vision output can vary with macOS model versions."
    })
    atomic_json(record_path, record)
    print("Source hashes verified unchanged. Review " + str(QA))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print("Import failed: " + str(error), file=sys.stderr)
        sys.exit(1)
