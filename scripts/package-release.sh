#!/bin/bash
set -euo pipefail
umask 077

# Package a public release: verify the shipped artwork, build Release, and put the
# signed app into a drag-to-Applications disk image. This script never installs,
# never launches, never touches the network and never publishes anything.
#
# Usage:
#   bash scripts/package-release.sh [--skip-build] [--allow-dirty] [--update-artwork-baseline]

ISLAND_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-signing.sh"

ISLAND_SKIP_BUILD=false
ISLAND_ALLOW_DIRTY=false
ISLAND_UPDATE_BASELINE=false
for ISLAND_ARGUMENT in "$@"; do
  case "$ISLAND_ARGUMENT" in
    --skip-build) ISLAND_SKIP_BUILD=true ;;
    --allow-dirty) ISLAND_ALLOW_DIRTY=true ;;
    --update-artwork-baseline) ISLAND_UPDATE_BASELINE=true ;;
    *) island_die "Usage: $0 [--skip-build] [--allow-dirty] [--update-artwork-baseline]" ;;
  esac
done

ISLAND_BASELINE_FILE="$ISLAND_PROJECT_ROOT/scripts/release-artwork-baseline.txt"
# Every shipped tomato image. Their hashes are pinned so a stale or reverted asset
# can never reach a public download.
ISLAND_ARTWORK_FILES=(
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-16.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-32.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-64.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-128.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-256.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-512.png'
  'boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-1024.png'
  'boringNotch/Assets.xcassets/logo2.imageset/tomato-brand.png'
  'boringNotch/Assets.xcassets/PomodoroTomato.imageset/tomato-idle.png'
  'boringNotch/Assets.xcassets/TomatoGlyph.imageset/tomato-glyph.png'
)

island_artwork_hashes() {
  local island_file
  for island_file in "${ISLAND_ARTWORK_FILES[@]}"; do
    [[ -f "$ISLAND_PROJECT_ROOT/$island_file" ]] || island_die "Missing shipped artwork: $island_file"
    printf '%s  %s\n' "$(/usr/bin/shasum -a 256 "$ISLAND_PROJECT_ROOT/$island_file" | /usr/bin/awk '{print $1}')" "$island_file"
  done
}

if [[ "$ISLAND_UPDATE_BASELINE" == true ]]; then
  island_artwork_hashes >"$ISLAND_BASELINE_FILE"
  printf 'Recorded %s artwork hashes in %s\n' "${#ISLAND_ARTWORK_FILES[@]}" "$ISLAND_BASELINE_FILE"
  printf 'Review the images by eye before trusting this baseline.\n'
  exit 0
fi

[[ -f "$ISLAND_BASELINE_FILE" ]] ||
  island_die "No artwork baseline. Inspect the icons, then run: $0 --update-artwork-baseline"
if ! /usr/bin/diff -u "$ISLAND_BASELINE_FILE" <(island_artwork_hashes) >/dev/null; then
  /usr/bin/diff -u "$ISLAND_BASELINE_FILE" <(island_artwork_hashes) || true
  island_die 'Shipped artwork differs from the reviewed baseline. Nothing was packaged.'
fi
printf 'Artwork matches the reviewed baseline (%s files).\n' "${#ISLAND_ARTWORK_FILES[@]}"

if [[ "$ISLAND_ALLOW_DIRTY" != true ]]; then
  [[ -z "$(/usr/bin/git -C "$ISLAND_PROJECT_ROOT" status --porcelain)" ]] ||
    island_die 'The working tree has uncommitted changes; commit them or pass --allow-dirty.'
fi

island_require_signing_identity
if [[ "$ISLAND_SKIP_BUILD" != true ]]; then
  bash "$ISLAND_PROJECT_ROOT/scripts/build.sh" Release
fi

ISLAND_BUILT_APP="$ISLAND_PROJECT_ROOT/build/Build/Products/Release/Airlet.app"
[[ -d "$ISLAND_BUILT_APP" ]] || island_die "No Release build at $ISLAND_BUILT_APP"
island_verify_app "$ISLAND_BUILT_APP"
ISLAND_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ISLAND_BUILT_APP/Contents/Info.plist")"
ISLAND_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$ISLAND_BUILT_APP/Contents/Info.plist")"
printf 'Verified: %s (version %s, build %s)\n' "$ISLAND_BUILT_APP" "$ISLAND_SHORT_VERSION" "$ISLAND_BUILD_VERSION"

ISLAND_DISTRIBUTION="$ISLAND_PROJECT_ROOT/dist"
ISLAND_IMAGE="$ISLAND_DISTRIBUTION/Airlet-$ISLAND_SHORT_VERSION.dmg"
ISLAND_STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/notchisland-release.XXXXXX")"
trap '/bin/rm -rf "$ISLAND_STAGE"' EXIT
/bin/mkdir -p "$ISLAND_DISTRIBUTION" "$ISLAND_STAGE/volume"
# The app is renamed the same way the local installer does it, so downloaded and
# locally installed copies show the same name in Finder, Dock and permissions.
/usr/bin/ditto "$ISLAND_BUILT_APP" "$ISLAND_STAGE/volume/Airlet.app"
# This script runs under umask 077; a downloaded app has to stay readable and
# executable for whoever copies it, so restore the usual bundle permissions.
/bin/chmod -R a+rX "$ISLAND_STAGE/volume/Airlet.app"
island_verify_app "$ISLAND_STAGE/volume/Airlet.app"
/bin/ln -s /Applications "$ISLAND_STAGE/volume/应用程序"
/bin/rm -f "$ISLAND_IMAGE"
/usr/bin/hdiutil create -quiet -volname 'Airlet' -srcfolder "$ISLAND_STAGE/volume" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "$ISLAND_IMAGE"

ISLAND_CHECKSUM="$(/usr/bin/shasum -a 256 "$ISLAND_IMAGE" | /usr/bin/awk '{print $1}')"
ISLAND_NOTES="$ISLAND_DISTRIBUTION/RELEASE-NOTES-$ISLAND_SHORT_VERSION.md"
cat >"$ISLAND_NOTES" <<NOTES
## Airlet v${ISLAND_SHORT_VERSION}（build ${ISLAND_BUILD_VERSION}）

### 本次更新

- 收起状态宽度可自定义，并可控制长歌词是否自动扩宽；实验性选项已从设置中隐藏。
- 切歌媒体提示期间暂不显示歌词，避免歌词和媒体提示重叠。
- 最高透明度下保留清透中央和原生玻璃边缘的背景晕染，移除固定的蓝白反光层。

### 主要功能

- 无刘海显示器使用悬浮灵动岛，支持悬停唤出、延迟展开和自动隐藏。
- 无刘海岛使用原生清透玻璃，透明度只淡化中央材质，玻璃边缘继续呈现背景色散射；岛内文字保持清晰。
- 边缘光根据岛后方画面的亮度与明暗变化，呈现局部亮边和暗边，不使用循环旋转动画。可在「设置 → 外观」关闭。
- 背景感应边缘光需屏幕录制权限，只在无刘海岛可见时读取周围亮度；不保存截图。未授权时显示中性边缘光，授权后请重启 Airlet。
- macOS 26 及以上采用原生 Clear Liquid Glass；macOS 15–25 使用系统材质回退。
- 优化音乐歌词、日历、番茄钟、系统提示与快捷工具在紧凑布局中的显示。
- macOS 27 实际外观尚待实机复测；本版不依赖 27 专属 API。

macOS 15.0 及以上，Apple Silicon。下载 \`$(basename "$ISLAND_IMAGE")\`，打开后把「Airlet」拖进「应用程序」。

### 首次打开需要手动放行

本应用没有 Apple 公证（notarization），首次双击会被 Gatekeeper 拦下并提示「无法验证是否包含恶意软件」。放行步骤：

1. 双击一次，关掉提示；
2. 打开「系统设置 → 隐私与安全性」，在底部找到被拦下的记录，点「仍要打开」；
3. 再双击一次，在弹窗里点「打开」。

macOS 15 之后已取消「按住 Control 点图标 → 打开」这条旧路径。命令行等价做法（自行承担跳过 Gatekeeper 校验的风险）：\`xattr -dr com.apple.quarantine /Applications/Airlet.app\`。

放行一次之后正常双击即可。首次运行还会请求「辅助功能」与「屏幕录制」权限，分别用于接管系统 HUD／通知横幅和截屏录屏工具。

### 校验

\`\`\`
shasum -a 256 $(basename "$ISLAND_IMAGE")
$ISLAND_CHECKSUM
\`\`\`

签名证书（自签，非 Apple Developer ID）：
\`\`\`
$(/usr/bin/codesign --display --verbose=2 "$ISLAND_IMAGE" 2>&1 | /usr/bin/grep -E '^(Identifier|TeamIdentifier)' || printf 'Disk image itself is unsigned; the app inside is signed.\n')
$(/usr/bin/codesign --display --verbose=2 "$ISLAND_BUILT_APP" 2>&1 | /usr/bin/grep -E '^(Identifier|Authority|TeamIdentifier)')
\`\`\`
NOTES

printf '\nPackaged: %s\n' "$ISLAND_IMAGE"
printf 'SHA256:   %s\n' "$ISLAND_CHECKSUM"
printf 'Notes:    %s\n' "$ISLAND_NOTES"
printf 'Nothing was installed, launched or uploaded.\n'
