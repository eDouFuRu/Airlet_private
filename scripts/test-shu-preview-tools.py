#!/usr/bin/env python3
"""Exercise the real preview wrapper's boundary behavior without rendering/signing."""
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name('render-shu-previews.py').resolve()
namespace = {'__file__': str(SCRIPT), '__name__': 'shu_preview_wrapper_under_test'}
exec(compile(SCRIPT.read_text(), str(SCRIPT), 'exec'), namespace)


class PreviewToolTests(unittest.TestCase):
    def testCustomOutputAndRenderFlagsAreForwarded(self):
        with tempfile.TemporaryDirectory(prefix='shu-preview-test-') as directory:
            output = Path(directory) / 'artifacts'
            calls = []
            def capture(args, selected_output, scratch):
                self.assertTrue(scratch.is_dir())
                calls.append((args, selected_output, scratch))
            with mock.patch.dict(namespace, render=capture), mock.patch.object(sys, 'argv', [str(SCRIPT), '--output', str(output), '--motion-only', '--full-60s', '--fps', '1', '--inventory', '13']):
                namespace['main']()
            args, selected, scratch = calls[0]
            self.assertEqual(selected, output.resolve())
            self.assertTrue(args.motion_only and args.full_60s)
            self.assertEqual((args.fps, args.inventory), (1, 13))
            self.assertFalse(scratch.exists(), 'Temporary executable directory must be removed')

    def testOriginalBaselineAndItsChildrenAreRefusedBeforeRendering(self):
        baseline = namespace['ROOT'] / 'build/validation/shu-motion/before'
        for output in [baseline, baseline / 'refused-test-child']:
            with self.subTest(output=output), mock.patch.dict(namespace, render=mock.Mock(side_effect=AssertionError('must not render'))), mock.patch.object(sys, 'argv', [str(SCRIPT), '--output', str(output)]):
                with self.assertRaisesRegex(SystemExit, 'Refusing'):
                    namespace['main']()
        self.assertFalse((baseline / 'refused-test-child').exists())

    def testRelocatedBaselineMarkerIsAlsoRefused(self):
        with tempfile.TemporaryDirectory(prefix='shu-preview-test-') as directory:
            output = Path(directory)
            marker = output / 'baseline-manifest.json'
            marker.write_text('unchanged')
            with mock.patch.object(sys, 'argv', [str(SCRIPT), '--output', directory]):
                with self.assertRaisesRegex(SystemExit, 'Refusing'):
                    namespace['main']()
            self.assertEqual(marker.read_text(), 'unchanged')

    def testIncompatibleModesAndUnboundedInputsAreRejected(self):
        for flags in [['--fps', '0'], ['--fps', '31'], ['--inventory', '-1'], ['--motion-only', '--handoff-only']]:
            with self.subTest(flags=flags), mock.patch.object(sys, 'argv', [str(SCRIPT), *flags]), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as failure:
                    namespace['options']()
                self.assertEqual(failure.exception.code, 2)

    def testRendererIncludesProductionRigAndExcludesProductionPersistence(self):
        names = {path.name for path in namespace['SOURCES']}
        self.assertIn('ShuAnimationRig.swift', names)
        self.assertIn('ShuAnimationTimeline.swift', names)
        self.assertIn('Shu25DScene.swift', names)
        self.assertNotIn('PotatoSessionStore.swift', names)
        self.assertNotIn('IslandRestModel.swift', names)


if __name__ == '__main__':
    unittest.main(verbosity=2)
