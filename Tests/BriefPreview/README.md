# Actual brief-row layout preview

This isolated macOS fixture compiles the production `BriefPromptRow.swift` and
captures attached rows through `NSHostingView.cacheDisplay` and floating rows
through SwiftUI `ImageRenderer`. Its borderless hosting windows
are never ordered front, and the application uses activation policy `prohibited`.
It does not launch the main application, read production defaults, read
notifications, or change an accessibility preference.

```sh
python3 Tests/BriefPreview/render.py
python3 Tests/BriefPreview/audit.py   # use an interpreter that has Pillow
```

Run from the repository root. The audit requires Pillow. `render.py --output PATH`
and `audit.py --output PATH` select another output directory. macOS application
registration must be available to the preview process: in the agent sandbox,
`NSApplication.shared` aborted inside LaunchServices before any rendering. The
successful run used the same isolated command outside that sandbox.

The default output is `build/validation/brief/layout-compact`. Earlier `layout`
and `layout-narrow` evidence is preserved separately:

- `overview-w257.png` and `overview-w578.png`: actual production row snapshots
  at the closed and expanded content widths, respectively.
- `comparison-{zh,en}-w{257,578}.png`: captured old-layout reconstruction and
  actual new row. The legacy reconstruction retains its 40-point bounds and
  20-point center; the new row uses the compiled shared
  `BriefPresentationLayout.rowHeight` (currently 28 points), with its 14-point
  center marked. Each image is displayed at its own actual height.
- `{fixture}-w{257,578}-{normal,reduced}-{1,2}x.png`: unannotated actual rows.
  Eight synthetic fixtures cover music titles, long lyrics, private hi notices,
  and detailed hi notices in Chinese and English. No fixture contains real
  message or lyric content. The public hi icon is read using
  `NSWorkspace.icon(forFile:)` from `/Applications/hi.app` when installed.
- `manifest.json`, `render-summary.json`, and `layout-audit.json`: source hashes,
  scope, and pixel measurements. Source hashes are checked again after rendering
  so concurrent production edits cannot silently mix into one evidence set. The
  renderer and audit script are hashed too; the audit rejects stale inputs.
- `overview-floating-h18.png` and `overview-floating-h24.png`: side-by-side light
  and dark semantic-content contact sheets at 320-point width, with all eight
  Chinese/English synthetic fixtures. Their labels explicitly exclude native
  material evidence.

The compact audit now requires 224 actual fixtures (32 attached rows and 192 floating rows), verifies all 1x/2x dimensions
against the shared height recorded by the renderer, confirms the requested
28-point row and unchanged 40-point legacy row, and measures visible text
against each row's own center. It also checks that text has top/bottom margins.

The floating fixtures add 18- and 24-point compact rows in light and dark appearances,
at 120-, 320- and 640-point widths, in Chinese and English, with normal and reduced
motion. They use the actual production row, semantic palette and shared contour.
Native `glassEffect` compiles in this harness but cannot be captured correctly by
`NSHostingView.cacheDisplay` in a never-shown window: it produces a diagnostic
material image instead of real content. The fixture therefore uses a deterministic
backdrop, and manifests explicitly set `materialEvidence` and
`nativeGlassVisualVerified` to `false`. These previews establish layout and ink
contrast; native glass must be reviewed in a real application window.

The floating rows use `ImageRenderer` because `cacheDisplay` also retained the
first appearance of some SF Symbols across successive isolated hosts, producing
white lyric icons on light backdrops even with an explicit AppKit appearance.
The alternative renderer uses the same unmodified production view and semantic
palette; no pixels are recolored or substituted after rendering.

The current Liquid Glass validation artifacts are in
`build/validation/liquid-glass/final-brief`; see the manifest for generation time
and the exact source hashes. A complete run has 448 actual-row PNGs (224 fixtures
at two scales), 8 reconstructed legacy PNGs, and 8 overview/comparison sheets.
`../final-hud` contains 104 actual HUD and brief component snapshots plus 6 contact
sheets, covering both languages, attached dark appearance and floating light/dark
appearances, 18/24-point compact heights and 36-point expanded headers. Its expanded
body is a labeled geometry fixture rather than a claim of actual page coverage.
Both sets explicitly record `materialEvidence=false`; native glass, all actual
pages, hover/click routing and multiple-display interaction require live review.

The 2026-09-06 23:11 compact run passed once through rendering and once through
the audit: all 64 actual PNGs have the requested dimensions; the 8 legacy PNGs
remain 40 points high. Visible text centers measure 14–15.5 points, with at least
8 points above and 6 below. The 257- and 578-point overview sheets were visually
checked for icon/text alignment, vertical clipping, and reduced-motion tail
truncation. The new row's text is 6 points higher than in the prior centered
40-point row, while the row itself is 12 points shorter. Source hashes before
and after rendering matched; see the compact manifest and audit JSON.

The before row reconstructs the former ContentView HStack/GeometryReader geometry
and compiles the existing production `MarqueeTextView.swift`; it is explicitly
**not a historical application screenshot**. The comparison uses its real macOS
rendered pixels, not manually positioned replacement text.

`previewReduceMotion` overrides only the fixture view. Its default is `nil`, so
production still reads the system `accessibilityReduceMotion` environment. These
artifacts demonstrate the normal and reduced layout branches, not a real OS
setting change. Normal snapshots capture the initial marquee hold; ongoing
scrolling, native hover/click routing, notification delivery, and the full
ContentView shell remain separate integration checks.
