#!/usr/bin/env python3
"""Measure actual page/picker proposals with isolated models and a mocked app environment."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build/validation/pomodoro-layout'
PRODUCTS = ROOT / 'build/Build/Products/Debug'
SOURCES = [Path(__file__).with_name('LayoutPomodoro.swift')] + [ROOT / 'boringNotch/Interaction' / p for p in [
    'Core/PomodoroSessionCore.swift', 'Core/PomodoroSessionStore.swift',
    'Core/PomodoroRingPresentation.swift', 'Core/PomodoroHeatmapMath.swift',
    'PomodoroModel.swift', 'PomodoroRingView.swift', 'PomodoroWeekStats.swift',
    'PomodoroPage.swift', 'PomodoroHeatmapView.swift', 'PomodoroWheelPicker.swift',
    'NotchPopoverHold.swift', 'NotchOpenHoldCenter.swift']]
OUTPUT.mkdir(parents=True, exist_ok=True)
hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
with tempfile.TemporaryDirectory(prefix='airlet-layout-') as scratch:
    contents = Path(scratch) / 'LayoutPreview.app/Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'LayoutPreview', 'CFBundleIdentifier': 'dev.validation.pomodoro-layout',
        'CFBundleName': 'Layout Preview', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
    shutil.copy2(PRODUCTS / 'Airlet.app/Contents/Resources/Assets.car', contents / 'Resources/Assets.car')
    binary = contents / 'MacOS/LayoutPreview'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-I', str(PRODUCTS), '-module-cache-path', str(Path(scratch) / 'ModuleCache'),
                    *map(str, SOURCES), str(PRODUCTS / 'Defaults.o'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(OUTPUT), str(ROOT / 'boringNotch/Localizable.xcstrings'), scratch], check=True)
for p in SOURCES:
    assert hashlib.sha256(p.read_bytes()).hexdigest() == hashes[str(p.relative_to(ROOT))]
(OUTPUT / 'manifest.json').write_text(json.dumps({'sources': hashes,
    'evidence': 'Actual page and week picker with proposed 578x136 / 168x136 sizes, temporary models',
    'mocked': ['BoringViewModel closed state to freeze ring sampling', 'IslandVisibility available', 'Settings window action'],
    'notVerified': ['Native pointer routing', 'real trackpad wheel gestures', 'shell animation'],
}, indent=2) + '\n')
