#!/usr/bin/env python3
"""Render the actual brief view in an isolated, never-shown macOS hosting window."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [Path(__file__).with_name('RenderBrief.swift'),
           ROOT / 'boringNotch/Interaction/BriefPromptRow.swift',
           ROOT / 'boringNotch/Interaction/Core/BriefPresentation.swift',
           ROOT / 'boringNotch/Interaction/IslandAppearance.swift',
           ROOT / 'boringNotch/Interaction/IslandSurface.swift',
           ROOT / 'boringNotch/Interaction/Core/NotchHitRegion.swift',
           ROOT / 'boringNotch/Interaction/Core/IslandDisplayProfile.swift',
           ROOT / 'boringNotch/components/Live activities/MarqueeTextView.swift']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/validation/brief/layout-compact')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    color_source = ROOT / 'boringNotch/extensions/NSImage+Extensions.swift'
    shape_source = ROOT / 'boringNotch/components/Notch/NotchShape.swift'
    inputs = SOURCES + [color_source, shape_source, Path(__file__), Path(__file__).with_name('audit.py')]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    with tempfile.TemporaryDirectory(prefix='notchisland-brief-preview-') as scratch:
        contents = Path(scratch) / 'BriefPreview.app/Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'BriefPreview', 'CFBundleIdentifier': 'dev.validation.brief-layout',
            'CFBundleName': 'Brief Layout Preview', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
        }))
        executable = contents / 'MacOS/BriefPreview'
        color = Path(scratch) / 'PreviewColor.swift'
        source = color_source.read_text()
        color.write_text('import AppKit\nimport SwiftUI\n' + source[source.index('extension Color {'):])
        shape = Path(scratch) / 'NotchShape.swift'
        shape.write_text(shape_source.read_text().split('#Preview')[0])
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                        '-module-cache-path', str(Path(scratch) / 'ModuleCache'),
                        *map(str, SOURCES), str(color), str(shape), '-o', str(executable)], cwd=ROOT, check=True)
        subprocess.run([str(executable), str(output)], cwd=ROOT, check=True)
    for name, digest in hashes.items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError('Source changed during rendering: ' + name)
    (output / 'manifest.json').write_text(json.dumps({
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'evidenceType': 'Actual production BriefPromptRow: NSHostingView cacheDisplay for attached rows in isolated, never-shown windows; SwiftUI ImageRenderer for floating semantic-content rows',
        'sources': hashes, 'nativeAppInteractionVerified': False, 'nativeGlassVisualVerified': False, 'materialEvidence': False,
        'readsProductionPreferencesOrNotifications': False,
        'reduceMotionEvidence': 'Explicit preview override in the actual view; no system accessibility setting was changed or verified',
        'legacyEvidence': 'Reconstructed former ContentView music-row geometry using the current legacy MarqueeText source; not a historical screenshot',
        'geometryEvidence': 'Attached rows use BriefPresentationLayout.rowHeight; floating fixtures use 18- and 24-point capsule rows in both color schemes. Legacy reconstruction retains its historical 40-point height. Exact dimensions are in render-summary.json.',
        'limitations': 'Static initial marquee layout, production contours and deterministic backdrops only; native glass is compiled but cannot be captured by offscreen cacheDisplay. No native hover, click routing, long-running scroll or notification delivery verification.',
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
