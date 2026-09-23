#!/usr/bin/env python3
"""Render production SwiftUI components with synthetic data, without launching Airlet."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build/validation/pomodoro'
SOURCES = [Path(__file__).with_name('RenderPomodoro.swift')] + [ROOT / 'boringNotch/Interaction' / p for p in [
    'Core/PomodoroSessionCore.swift', 'Core/PomodoroSessionStore.swift',
    'Core/PomodoroRingPresentation.swift', 'Core/PomodoroHeatmapMath.swift',
    'PomodoroModel.swift', 'PomodoroRingView.swift', 'PomodoroWeekStats.swift']]

OUTPUT.mkdir(parents=True, exist_ok=True)
hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
with tempfile.TemporaryDirectory(prefix='airlet-pomodoro-preview-') as scratch:
    contents = Path(scratch) / 'PomodoroPreview.app/Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'PomodoroPreview', 'CFBundleIdentifier': 'dev.validation.pomodoro',
        'CFBundleName': 'Pomodoro Preview', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    }))
    binary = contents / 'MacOS/PomodoroPreview'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(Path(scratch) / 'ModuleCache'),
                    *map(str, SOURCES), '-o', str(binary)], check=True, cwd=ROOT)
    subprocess.run([str(binary), str(OUTPUT), str(ROOT / 'boringNotch/Localizable.xcstrings'), scratch], check=True)
for p in SOURCES:
    if hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))]:
        raise RuntimeError('Source changed during rendering: ' + str(p))
(OUTPUT / 'manifest.json').write_text(json.dumps({
    'sources': hashes,
    'evidence': 'Production Canvas and statistics views rendered with ImageRenderer at 2x; synthetic data',
    'productionPreferencesOrSessionsRead': False, 'mainAppLaunched': False,
    'limitations': 'Isolated rendering and model harness, not native island hover or cold-open acceptance',
}, indent=2) + '\n')
