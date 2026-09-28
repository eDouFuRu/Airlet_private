#!/usr/bin/env python3
"""Measure rendered row bounds and text centers; requires Pillow."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image


def text_bounds(path, start_x, light=False):
    with Image.open(path) as image:
        rgb = image.convert('RGB')
        points = [(x, y) for y in range(rgb.height)
                  for x in range(start_x, rgb.width - 12)
                  if (max(rgb.getpixel((x, y))) < 150 if light else min(rgb.getpixel((x, y))) >= 100)]
        if not points:
            raise AssertionError('No visible text in ' + str(path))
        top, bottom = min(p[1] for p in points), max(p[1] for p in points)
        return {'topPixel': top, 'bottomPixel': bottom,
                'centerPoints': (top + bottom + 1) / 2, 'visiblePixels': len(points)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[2] / 'build/validation/brief/layout-compact')
    output = parser.parse_args().output.resolve()
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads((output / 'manifest.json').read_text())
    for name, digest in manifest['sources'].items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, ('Stale source', name)
    assert manifest['materialEvidence'] is False
    assert manifest['nativeGlassVisualVerified'] is False
    summary = json.loads((output / 'render-summary.json').read_text())
    row_height = summary['actualRowHeightPoints']
    legacy_height = summary['legacyRowHeightPoints']
    assert row_height == 28, ('Expected current compact row height', row_height)
    assert legacy_height == 40, ('Legacy reconstruction height changed', legacy_height)
    assert len(summary['actualSourceFixtures']) == 224
    assert len([f for f in summary['actualSourceFixtures'] if f.get('floating')]) == 192
    actual = []
    for fixture in summary['actualSourceFixtures']:
        name, width = fixture['name'], int(fixture['widthPoints'])
        expected_height = fixture['heightPoints'] if fixture.get('floating') else row_height
        assert expected_height in ([18, 24] if fixture.get('floating') else [28])
        assert fixture['heightPoints'] == expected_height, fixture
        for scale in [1, 2]:
            with Image.open(output / f'{name}-{scale}x.png') as image:
                assert image.size == (width * scale, expected_height * scale), (name, image.size)
                if fixture.get('floating'):
                    assert image.convert('RGBA').getpixel((0, 0))[3] == 0, ('Capsule corner is opaque', name)
        if fixture.get('floating') and 'lyric-' in name:
            with Image.open(output / (name + '-1x.png')) as image:
                pixels = image.convert('RGBA')
                inset = 4 if expected_height < 24 else 12
                icon_size = min(22, expected_height - 4)
                light = fixture['colorScheme'] == 'light'
                ink = sum(1 for y in range(pixels.height) for x in range(inset, inset + icon_size)
                          if pixels.getpixel((x, y))[3] > 160 and
                          (max(pixels.getpixel((x, y))[:3]) < 150 if light else min(pixels.getpixel((x, y))[:3]) > 150))
                assert ink > 10, ('Lyric icon lacks semantic contrast', name, ink)
        measured = text_bounds(output / (name + '-1x.png'), 28 if fixture.get('floating') else 43, fixture.get('colorScheme') == 'light')
        assert abs(measured['centerPoints'] - expected_height / 2) <= 3, (name, measured)
        assert measured['topPixel'] > 0 and measured['bottomPixel'] < expected_height - 1, (name, measured)
        actual.append({'name': name, 'rowCenterPoints': expected_height / 2, **measured})
    comparisons = []
    for width in [257, 578]:
        for language in ['zh', 'en']:
            for scale in [1, 2]:
                with Image.open(output / f'legacy-reconstructed-music-{language}-w{width}-{scale}x.png') as image:
                    assert image.size == (width * scale, legacy_height * scale), (width, language, image.size)
            before = text_bounds(output / f'legacy-reconstructed-music-{language}-w{width}-1x.png', 43)
            after = text_bounds(output / f'music-{language}-w{width}-normal-1x.png', 43)
            comparisons.append({'width': width, 'language': language,
                'before': before, 'after': after,
                'afterRowHeightPoints': row_height, 'beforeRowHeightPoints': legacy_height,
                'afterCenterDeltaFromRowCenterPoints': after['centerPoints'] - row_height / 2,
                'beforeCenterDeltaFromRowCenterPoints': before['centerPoints'] - legacy_height / 2})
    result = {'actualRowCount': len(actual), 'allRowsHaveExpectedDimensions': True,
              'sourceHashesMatch': True, 'materialEvidence': False, 'nativeGlassVisualVerified': False,
              'floatingCornersAreTransparent': True, 'floatingLyricIconsHaveSemanticContrast': True,
              'actualRowHeightPoints': row_height, 'actualRowCenterPoints': row_height / 2,
              'legacyRowHeightPoints': legacy_height, 'allTextHasVerticalMargin': True,
              'allTextCentersWithin3PointsOfRowCenter': True,
              'actualRows': actual, 'legacyComparisons': comparisons,
              'limits': 'Pixel layout measurements, not native click/hover or long-running animation verification.'}
    (output / 'layout-audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k:result[k] for k in ['actualRowCount',
        'allRowsHaveExpectedDimensions','allTextCentersWithin3PointsOfRowCenter','legacyComparisons']},indent=2))


if __name__ == '__main__':
    main()
