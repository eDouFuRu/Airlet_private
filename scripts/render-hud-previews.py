#!/usr/bin/env python3
"""Render production HUD/Island views offline; never instantiate hardware managers."""
import argparse
import datetime
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / name for name in [
    "scripts/RenderHUDPreviews.swift",
    "boringNotch/Interaction/Core/SystemHUDState.swift",
    "boringNotch/Interaction/Core/BriefPresentation.swift",
    "boringNotch/Interaction/Core/FloatingIslandPresentation.swift",
    "boringNotch/Interaction/Core/NotchHitRegion.swift",
    "boringNotch/Interaction/Core/IslandDisplayProfile.swift",
    "boringNotch/Interaction/IslandAppearance.swift",
    "boringNotch/Interaction/IslandSurface.swift",
    "boringNotch/Interaction/FloatingSystemHUD.swift",
    "boringNotch/Interaction/BriefPromptRow.swift",
    "boringNotch/components/Live activities/InlineHUD.swift",
    "boringNotch/components/Live activities/SystemEventIndicatorModifier.swift",
]]
INPUTS = [ROOT / name for name in [
    "scripts/render-hud-previews.py", "scripts/VerifyHUDPreviews.swift",
    "boringNotch/extensions/NSImage+Extensions.swift", "boringNotch/Localizable.xcstrings",
    "boringNotch/ContentView.swift",
]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/validation/hud25d/hud-previews")
    parser.add_argument("--baseline-hud-ref", help="Read the two HUD sources from a Git ref into isolated preview copies; never alters production files")
    args = parser.parse_args()
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES}
    input_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in INPUTS}
    OUTPUT = args.output.resolve()
    BUNDLE = OUTPUT / "RenderHUDPreviews.app/Contents"
    GENERATED = OUTPUT / "generated"
    GENERATED.mkdir(parents=True, exist_ok=True)
    (BUNDLE / "MacOS").mkdir(parents=True, exist_ok=True)
    resources = BUNDLE / "Resources"
    resources.mkdir(exist_ok=True)
    (BUNDLE / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "RenderHUDPreviews", "CFBundleIdentifier": "dev.validation.hud-previews",
        "CFBundleName": "HUD Static Previews", "CFBundlePackageType": "APPL", "LSUIElement": True,
        "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans"],
    }))
    catalog = json.loads((ROOT / "boringNotch/Localizable.xcstrings").read_text())["strings"]
    for language in ("en", "zh-Hans"):
        target = resources / (language + ".lproj")
        target.mkdir(exist_ok=True)
        values = {key: entry["localizations"][language]["stringUnit"]["value"]
                  for key, entry in catalog.items() if key and language in entry.get("localizations", {})}
        (target / "Localizable.strings").write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
    color_source = (ROOT / "boringNotch/extensions/NSImage+Extensions.swift").read_text()
    (GENERATED / "PreviewColor.swift").write_text("import AppKit\nimport SwiftUI\n" + color_source[color_source.index("extension Color {"):])
    compile_sources = list(SOURCES)
    hud_overrides = {}
    if args.baseline_hud_ref:
        for relative in ["boringNotch/Interaction/Core/SystemHUDState.swift",
                         "boringNotch/components/Live activities/InlineHUD.swift"]:
            contents = subprocess.run(["git", "show", f"{args.baseline_hud_ref}:{relative}"],
                                      cwd=ROOT, check=True, capture_output=True).stdout
            isolated_copy = GENERATED / ("Baseline-" + Path(relative).name)
            if relative.endswith("InlineHUD.swift"):
                # Visibility alone is widened for the compact view that shares these labels.
                contents = contents.replace(b"private extension SystemHUDState", b"extension SystemHUDState")
            isolated_copy.write_bytes(contents)
            compile_sources = [isolated_copy if source == ROOT / relative else source for source in compile_sources]
            hud_overrides[relative] = hashlib.sha256(contents).hexdigest()
    # Module named Defaults satisfies the actual views' imports, but all values
    # are held in memory and cannot read or mutate the production preference suite.
    (GENERATED / "PreviewDefaults.swift").write_text('''
public enum PreviewHUDKey { case enableGradient, systemEventIndicatorUseAccent, systemEventIndicatorShadow, inlineHUD }
public enum PreviewHUDDefaults { public static var inlineHUD = false }
@propertyWrapper public struct Default {
    private let key: PreviewHUDKey
    public init(_ key: PreviewHUDKey) { self.key = key }
    public var wrappedValue: Bool {
        switch key {
        case .inlineHUD: return PreviewHUDDefaults.inlineHUD
        case .systemEventIndicatorShadow: return false
        case .enableGradient, .systemEventIndicatorUseAccent: return true
        }
    }
}
''')
    module_cache = str(OUTPUT / "ModuleCache")
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-emit-module", "-emit-object",
                    "-module-name", "Defaults", "-module-cache-path", module_cache,
                    str(GENERATED / "PreviewDefaults.swift"), "-o", str(GENERATED / "Defaults.o"),
                    "-emit-module-path", str(GENERATED / "Defaults.swiftmodule")], cwd=ROOT, check=True)
    executable = BUNDLE / "MacOS/RenderHUDPreviews"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", module_cache,
                    "-I", str(GENERATED), str(GENERATED / "Defaults.o"),
                    str(GENERATED / "PreviewColor.swift"), *map(str, compile_sources), "-o", str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable), str(OUTPUT)], cwd=ROOT, check=True)
    for name, digest in {**source_hashes, **input_hashes}.items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("Source changed during rendering: " + name)
    manifest = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "staticOnly": True, "materialEvidence": False, "nativeGlassVisualVerified": False, "productionUserDefaultsAccess": False, "hardwareCallsAllowed": False,
        "baselineHUDRef": args.baseline_hud_ref, "isolatedHUDSourceOverrides": hud_overrides,
        "sources": source_hashes,
        "renderInputs": input_hashes,
        "snapshots": sorted(path.name for path in OUTPUT.glob("*.png")),
        "limitations": "Actual HUD, brief rows and production contours over deterministic backdrops; native glass compiles but is omitted by ImageRenderer. Isolated models and settings. Expanded content is a geometry fixture, not actual app pages. Offscreen snapshots do not establish live desktop refraction, ContentView lifecycle or native input behavior.",
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    verifier = GENERATED / "VerifyHUDPreviews"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", module_cache,
                    str(ROOT / "scripts/VerifyHUDPreviews.swift"), "-o", str(verifier)], cwd=ROOT, check=True)
    subprocess.run([str(verifier), str(OUTPUT)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
