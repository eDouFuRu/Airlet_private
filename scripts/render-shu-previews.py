#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build and render actual SwiftUI source with isolated, nonpersistent samples."""
import argparse
import datetime
import hashlib
import json
import plistlib
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ROOT / "scripts/RenderShuPreviews.swift",
    ROOT / "boringNotch/components/Island/CaptainShuArtwork.swift",
    ROOT / "boringNotch/components/Island/IslandPage.swift",
    ROOT / "boringNotch/components/Island/Shu25DAssets.swift",
    ROOT / "boringNotch/components/Island/Shu25DScene.swift",
    *sorted((ROOT / "boringNotch/components/Island/Core").glob("Shu*.swift")),
]


def options():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/validation/shu-motion/after",
                        help="Artifact directory; the archived before baseline is never overwritten")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--motion-only", action="store_true", help="Keyframes, 1x/2x frames, 4x crops and walking/settlement sheets")
    mode.add_argument("--handoff-only", action="store_true", help="Only 0/1/12/13-stock delivery handoff samples")
    parser.add_argument("--animation", action="store_true", help="Render a 60-second GIF at the requested FPS")
    parser.add_argument("--variants", action="store_true", help="Also render stock 0/12/13 and Reduce Motion keyframes")
    parser.add_argument("--video", action="store_true", help="Encode 60 seconds of motion plus 1 second of settlement with AVFoundation")
    parser.add_argument("--full-60s", action="store_true", help="Render every frame in the full minute and validate bitmap output")
    parser.add_argument("--fps", type=int, choices=range(1, 31), default=20, metavar="1..30")
    parser.add_argument("--inventory", type=int, choices=(0, 1, 12, 13), default=1)
    parser.add_argument("--reduce-motion", action="store_true", help="Render the accessibility Reduce Motion branch")
    return parser.parse_args()


def main():
    args = options()
    output = args.output.expanduser().resolve()
    before = (ROOT / "build/validation/shu-motion/before").resolve()
    if output == before or before in output.parents:
        raise SystemExit("Refusing to overwrite the archived motion baseline")
    output.mkdir(parents=True, exist_ok=True)
    if (output / "baseline-manifest.json").exists():
        raise SystemExit("Refusing to write into a baseline archive")
    # Compiling this isolated harness does not invoke project signing scripts,
    # select a certificate, or link the production persistence model.
    with tempfile.TemporaryDirectory(prefix="notchisland-shu-preview-") as scratch:
        render(args, output, Path(scratch))


def render(args, OUTPUT, scratch):
    BUNDLE = scratch / "RenderShuPreviews.app/Contents"
    (BUNDLE / "MacOS").mkdir(parents=True, exist_ok=True)
    (BUNDLE / "Resources").mkdir(exist_ok=True)
    (BUNDLE / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "RenderShuPreviews",
        "CFBundleIdentifier": "dev.validation.shu-previews",
        "CFBundleName": "Shu Static Previews",
        "CFBundlePackageType": "APPL",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleLocalizations": ["en", "zh-Hans"],
        "LSUIElement": True,
    }))
    catalog = json.loads((ROOT / "boringNotch/Localizable.xcstrings").read_text())["strings"]
    for language in ("en", "zh-Hans"):
        target = BUNDLE / "Resources" / (language + ".lproj")
        target.mkdir(exist_ok=True)
        values = {key: entry["localizations"][language]["stringUnit"]["value"]
                  for key, entry in catalog.items() if key and language in entry.get("localizations", {})}
        (target / "Localizable.strings").write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
    assets = {}
    asset_metadata = {}
    asset_manifest = ROOT / "boringNotch/components/Island/Shu25DAssets.json"
    expected_assets = {"Shu25D-" + item["id"] for item in json.loads(asset_manifest.read_text())["assets"]}
    for stale_sprite in (BUNDLE / "Resources").glob("Shu25D-*.png"):
        stale_sprite.unlink()
    (BUNDLE / "Resources/Shu25DAssets.json").write_bytes(asset_manifest.read_bytes())
    available_assets = set()
    for image_set in (ROOT / "boringNotch/Assets.xcassets").glob("Shu25D-*.imageset"):
        contents = json.loads((image_set / "Contents.json").read_text())
        filename = next((item.get("filename") for item in contents.get("images", []) if item.get("filename")), None)
        if filename:
            source = image_set / filename
            source_bytes = source.read_bytes()
            (BUNDLE / "Resources" / (image_set.stem + ".png")).write_bytes(source_bytes)
            assets[str(source.relative_to(ROOT))] = hashlib.sha256(source_bytes).hexdigest()
            if source_bytes.startswith(b"\x89PNG\r\n\x1a\n") and len(source_bytes) >= 29:
                width, height, bit_depth, color_type = struct.unpack(">IIBB", source_bytes[16:26])
                asset_metadata[image_set.stem] = {
                    "width": width, "height": height, "bitDepth": bit_depth,
                    "colorType": color_type, "hasAlphaChannel": color_type in (4, 6),
                }
            available_assets.add(image_set.stem)
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES}
    metadata_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                       for path in [asset_manifest, ROOT / "boringNotch/Localizable.xcstrings"]}
    # Refuse accidental inclusion of the app's persistence implementation in the
    # renderer. These preview views use the in-memory stub in RenderShuPreviews.
    import re
    persistence_access = [str(path.relative_to(ROOT)) for path in SOURCES
                          if re.search(r"UserDefaults\s*\.|@AppStorage|Defaults\[", path.read_text())]
    if persistence_access:
        raise RuntimeError("Preview source directly accesses persisted preferences: " + ", ".join(persistence_access))
    manifest_name = "handoff-manifest.json" if args.handoff_only else "manifest.json"
    for stale in [OUTPUT / manifest_name, OUTPUT / "render-summary.json"]:
        if stale.exists():
            stale.unlink()
    executable = BUNDLE / "MacOS/RenderShuPreviews"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                    "-module-cache-path", str(scratch / "ModuleCache"),
                    *map(str, SOURCES), "-o", str(executable)], cwd=ROOT, check=True)
    flags = [flag for flag, enabled in (("--motion-only", args.motion_only),
             ("--handoff-only", args.handoff_only), ("--animation", args.animation), ("--video", args.video),
             ("--full-60s", args.full_60s), ("--reduce-motion", args.reduce_motion), ("--variants", args.variants)) if enabled]
    subprocess.run([str(executable), str(OUTPUT), *flags, "--fps", str(args.fps),
                    "--inventory", str(args.inventory)], cwd=ROOT, check=True)
    changed = [name for name, digest in {**source_hashes, **metadata_hashes, **assets}.items()
               if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    if changed:
        raise RuntimeError("Sources changed during rendering; rerun for consistent evidence: " + ", ".join(changed))
    body_path = "boringNotch/Assets.xcassets/Shu25D-captain-base.imageset/captain-base.png"
    before_body = ROOT / "build/validation/shu-motion/before/inputs" / body_path
    body_check = {"path": body_path, "currentSHA256": assets.get(body_path)}
    if before_body.exists():
        body_check["beforeSHA256"] = hashlib.sha256(before_body.read_bytes()).hexdigest()
        body_check["unchanged"] = body_check["beforeSHA256"] == body_check["currentSHA256"]
        if not body_check["unchanged"]:
            raise RuntimeError("Protected original body texture changed from the before archive")
    manifest = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "evidenceType": "Deterministic offscreen SwiftUI samples; not native playback",
        "nativeAnimationVerified": False,
        "staticOnly": not (args.animation or args.full_60s or args.video),
        "options": {"motionOnly": args.motion_only, "handoffOnly": args.handoff_only,
                    "animation": args.animation, "video": args.video, "full60s": args.full_60s, "variants": args.variants,
                    "fps": args.fps, "inventory": args.inventory, "reduceMotion": args.reduce_motion},
        "productionUserDefaultsAccess": False,
        "sources": source_hashes,
        "metadataSources": metadata_hashes,
        "rasterAssets": assets,
        "protectedBodyTexture": body_check,
        "rasterMetadata": asset_metadata,
        "missingRasterAssets": sorted(expected_assets - available_assets),
        "runtimeAssetAvailability": json.loads((OUTPUT / "render-summary.json").read_text()).get("assetAvailability", {}),
        "usesLegacyCharacterFallback": json.loads((OUTPUT / "render-summary.json").read_text())["usesLegacyCharacterFallback"],
        "snapshots": [name for name in json.loads((OUTPUT / "render-summary.json").read_text())["files"] if name.endswith(".png")],
        "sampledAnimations": ["shu-60s-loop.gif"] if args.animation else [],
        "sampledVideos": ["shu-60s.mp4"] if args.video else [],
        "limitations": "Offscreen ImageRenderer frames from real scene sources, with isolated sample state. Does not verify native windows, hover, keyboard focus, lock/unlock, presentation frame pacing or motion quality.",
    }
    manifest_name = "handoff-manifest.json" if args.handoff_only else "manifest.json"
    (OUTPUT / manifest_name).write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
