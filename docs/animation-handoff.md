# 小岛动画交付文档（展开 / 收起 / Tab 切换）

> 交付目标：把 Airlet 小岛的展开、收起、Tab 切换动画做到与上游 [boring.notch](https://github.com/TheBoredTeam/boring.notch) **肉眼无法区分**。
> 用户判定标准：以上游为准，"一模一样、优美流畅"。经三轮修复：遮罩扫出（第 1 轮）、打开事务缺失（第 2 轮）、**冷开启无在飞事务导致内容钉在最终尺寸**（第 3 轮，用户以"快速触发对、间隔触发滑"锁定）均已修复并装机；**冷开启修复待用户真机复验**。本文档给出全部已确认事实、机制结论与剩余排查清单。
> 2026-09-22 由前一开发者（AI 协作）整理。所有结论均有帧实测或源码对照依据，标注见正文。

---

## 1. 工程与代码位置

| 项 | 值 |
|---|---|
| 开发仓库 | `/Users/dongfengrui/Documents/Rednote_Vibecoding/NotchIslandNext-pomodoro`（git worktree，分支 `public-edition`） |
| 当前状态 | 全部工作已提交：`8ebfa7a`（番茄钟公开版 + Airlet 更名 + 动画修复），分支 `public-edition` |
| 应用名 / Bundle ID | Airlet / `com.dongfengrui.Airlet` |
| 构建 | `bash scripts/build.sh Debug`（固定本地证书，产物 `build/Build/Products/Debug/Airlet.app`） |
| 安装运行 | 先 `osascript -e 'tell application id "com.dongfengrui.Airlet" to quit'; sleep 3`，再 `bash scripts/install-local.sh Debug`，最后 `open -a ~/Applications/Airlet.app`。**安装脚本拒绝应用运行时安装**；perl 适配器进程会残留，可靠序列见仓库 `LOCAL-SIGNING.md` |
| 上游参照源码 | 本仓库 git remote `upstream`（v2.7.3，固定提交 `16b0f11`）与 `upstream-main`。查看：`git show upstream/main:boringNotch/ContentView.swift` |
| 上游参照 App | `/Applications/boringNotch.app`（真身已装，可启动对照录屏；**注意它和 Airlet 同时运行会在刘海上互相打架，对照前先退出 Airlet**） |
| 承载窗口 | 固定 750×380，运行期**不变尺寸**；岛内容顶部对齐居中 |

## 2. 目标效果（以上游 v2.7.3 / main 为准）

上游关键源码（按阅读顺序）：

1. `boringNotch/ContentView.swift`
   - `body`：`let mainLayout = NotchLayout()…background(.black).clipShape(…)`，然后 `mainLayout.frame(height: vm.notchState == .open ? vm.notchSize.height : nil)` + `.animation(开/关弹簧, value: vm.notchState)`——**高度提案在 background/clipShape 外侧**。
   - `NotchLayout()`：`VStack(alignment: .leading)`（默认 spacing）= 头部 VStack（含 HUD/两翼行，`.zIndex(2)`）+ `if open { VStack{switch 页}.transition(…).zIndex(1) }`。
   - 页面 transition：`.scale(scale: 0.8, anchor: .top).combined(with: .opacity).animation(.smooth(duration: 0.35))`。
   - `doOpen()`：`withAnimation(animationSpring) { vm.open() }`，`animationSpring = interactiveSpring(response: 0.38, dampingFraction: 0.8)`。**关闭路径不包 withAnimation**，靠 `.animation(value: notchState)` 驱动。
   - `body` 外层还有 `.compositingGroup()`、`.scaleEffect(gestureScale)`（手势缩放）、`.padding(.bottom, 8)`、底部 chin 矩形等，属于结构性差异清单（见 §5）。
2. `boringNotch/models/BoringViewModel.swift`：`open()` 先 `notchSize = openNotchSize` 再 `notchState = .open`；`close()` 反向。
3. `boringNotch/components/Tabs/TabSelectionView.swift`：切 tab 是 `withAnimation(.smooth) { coordinator.currentView = tab.view }`。

上游观感特征（用户认可"优美流畅"的点）：
- 展开时黑色壳从物理刘海向下生长，**页面内容跟着壳一起从小到大长出来（morph）**，不是等壳长完再出现，也不是被遮罩逐步扫出；
- 内容进场带 scale(0.8→1.0、顶部锚点)+淡入，与壳生长叠合；
- 收起时壳平滑收回、内容随之退出，无跳变。

## 3. 当前实现（Airlet）结构

全部动画相关代码集中在 `boringNotch/ContentView.swift`，触发路径在 `boringNotch/boringNotchApp.swift`：

```swift
// ContentView.body（现状，符号名定位，行号会漂）
NotchLayout()
    .padding(.horizontal, isOpen ? 31 : 6)
    .padding(.bottom, isOpen ? 12 : 0)
    .frame(width: visibleWidth, alignment: .top)      // 宽度在形状内侧强制
    .background(.black)
    .clipShape(NotchShape(…))
    .overlay(alignment: .top) { 顶部 1pt 黑线 }
    .shadow(…)
    .frame(height: isOpen ? visibleHeight : nil, alignment: .top)   // 高度提案在外侧
    .modifier(NotchPresentationReporter(…))           // 给指针协调器上报几何
    .animation(shellAnimation, value: vm.notchState)
    .animation(shellAnimation, value: visibleWidth)
    .animation(shellAnimation, value: visibleHeight)
    .animation(shellAnimation, value: systemHUD.activeKind)
    .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
    …
```

- `shellAnimation = .spring(response: isOpen ? 0.42 : 0.45, dampingFraction: isOpen ? 0.8 : 1.0)`（与上游一致）。
- `visibleHeight` 来自 `hudLayout` 公式（`SystemHUDLayout` + `baseExpandedHeight + briefLayout.addedHeight`），不是上游的 `vm.notchSize.height`；`baseExpandedHeight = max(openNotchSize.height=190, headerHeight+156)`，工具页另有 `SystemToolGridMetrics.expandedHeight`。
- 页面区（`NotchLayout` 内 `if isOpen { Group { switch … } }`）：`.padding(.top, 8)` + transition，**无包装 frame**，各页面自行撑满提案（home 靠 MusicControlsView 里的 GeometryReader、shelf 靠 RoundedRectangle 形状、tools 靠 ScrollView、pomodoro 自带 `.frame(maxWidth:.infinity, maxHeight:.infinity)`）。
- 打开路径已包事务动画（与上游同构）：
  - 悬停打开：`boringNotchApp.swift` 中 `NotchPointerCoordinator` 的 `open:` 闭包 → `withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { model?.open() }`；
  - 菜单栏「展开小岛」：`AppDelegate.expandIsland()` 同样包裹；
  - 拖拽打开：`ContentView.openShelfForDrag()` 用 `withAnimation(vm.animationLibrary.animation)`。
- 关闭路径（`close:` 闭包）**不包**事务，靠 `.animation(value:)`——与上游一致。
- Tab 切换：`TabSelectionView` 的 `withAnimation(.smooth)`，与上游逐字一致。

## 4. 已实锤的机制结论（四轮帧实测换来，不要推翻重试）

1. **背景必须贴内容，高度提案必须在 background/clipShape 外侧。**
   若 `.frame(width:height:)` 包在 `.background(.black)` 外面，黑色形状 = 动画中的 frame 尺寸，内容瞬间就位、被下移的裁剪边缘逐行扫出。帧实测证实。
2. **⭐ 核心定律：插入的页面内容只有在"动画事务"里才会跟随弹簧逐帧重排（morph）。**
   - **快速重开是对的、隔一段时间（冷）展开就"从上滑下来"** —— 用户实测给出的分界线，机制如下：
     - 冷开启：没有任何在飞的动画事务时，`if isOpen` 新插入的页面按**最终提案**瞬间布局（帧实测：壳 424×119 时内容已是最终尺寸、整体上移 ~63pt 被上下裁切、与 header 重叠）→ 壳的生长退化成遮罩扫出；
     - 快速重开：上一次关闭弹簧还在飞行中，open 的变更并入在飞事务 → 内容按插值提案逐帧重排 = morph。
   - **因此每一条打开路径都必须包 `withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8))`**（上游 `doOpen()` 正是这么写的）。已覆盖：悬停打开闭包、菜单「展开小岛」(`expandIsland`)、拖拽打开、DEBUG 诊断入口。**新增任何 open() 调用点必须同样包裹**，否则该路径冷开启必滑。
   - 关闭路径不包事务（与上游一致）：移除内容不需要提案插值，壳收缩由 `.animation(value:)` 驱动即可。
3. **每个页面必须能纵向撑满提案**，否则壳会塌到内容理想高度（岛变矮）。四个页面当前的"弹性来源"：home 靠 MusicControlsView 的 GeometryReader、shelf 靠 RoundedRectangle 形状、tools 靠 ScrollView、pomodoro 自带 `.frame(maxWidth:.infinity, maxHeight:.infinity)`。页面区**不要加包装 frame**（上游就是裸挂）。
4. **闭合态两翼宽度不能交给内容自然宽**：`.frame(width: visibleWidth)` 留在形状内侧是刻意的（闭合态 header 自然宽 ≠ `baseClosedWidth` 公式，去掉会让黑壳比物理刘海窄）。动这块前先理解 `baseClosedWidth`/`computedChinWidth` 两条平行链（见仓库根 README-Island.md）。
5. **Tab 切换（2026-09-22 定案，用户拍板不参考上游）**：用户实测**上游切 tab 同样是从上滑下来的**（不必抄）。
   我们的滑动由两层叠加：① `NotchHomeView.mainContent` 自带 `insertion: .opacity + .move(edge: .top)`（上游遗产，
   本意是首次启动揭示），主页每次被重新插入都会重放 → 已改为纯 `.opacity`；② 页面分支继承容器
   `.transition(.scale(0.8, .top))` 后仍残留 ~44pt 弹簧沉降（帧实测封面顶边 13→57pt，壳尺寸恒定）→
   **分支显式 `.transition(.identity)`，tab 切换为瞬间就位**，已帧验证零位移。开/关岛的 scale+opacity
   由容器 transition 承担，不受影响。若未来想要 tab 切换动效，从"容器 transition 如何只作用于开/关"入手，
   不要恢复分支继承。
6. **冷开启 morph 已在最终构建帧级验证**：间隔 ≥10s 后触发，封面从 ~30pt 随壳长大到 103pt、顶边恒定
   在最终位置、无遮罩扫出（帧序列：壳 192→381→575→631→635，封面 top 恒定 55-58pt）。

## 5. 剩余排查清单（按优先级）

截至 2026-09-22 收尾：冷开启 morph 已帧级验证（§4.6）、tab 切换已改为瞬间就位（§4.5）、两台构建均装机。
**待用户真机复验：冷开启手感是否达到"上游那种自然扩展"、tab 瞬间切换是否可接受。** 若复验仍有问题，按以下顺序排查：

1. **与上游做 60fps 并排对照录屏（第一优先）**
   我此前的连拍只有 ~5fps，只能证机制、不能证手感。方法：退出 Airlet → 启动 `/Applications/boringNotch.app`（先用 `defaults write theboringteam.boringnotch firstLaunch -bool false` 跳过引导），QuickTime 屏幕录制（或 `screencapture -v`），人工悬停触发上游开/合；换回 Airlet 同场景录制；逐帧对比壳高度-时间与内容缩放-时间曲线。⚠️ 连拍窗口要盖住用户操作时段（上一轮因此扑空：70 帧全是壁纸）。
2. **冷开启复验失败的专用排查**：确认用户触发的路径真的走了包事务的闭包（悬停 → `NotchPointerCoordinator` 的 `open:` 闭包；菜单 → `expandIsland`）；用 §7 帧捕获比对冷开启中间帧的内容尺寸（morph = 内容压缩；钉住 = 内容最终尺寸被裁）。注意应用**启动时会自动展开一次**，捕获冷开启要先等它收回（§7.3.1）。
3. **收起（close）半程的观感**。展开已证 morph，收起只粗测过壳轮廓平滑（192→90→54→32）。收起时页面是"移除+过渡渲染在冻结几何上"，移除时机、冻结位置、透明度曲线未逐帧对照。
4. **结构性差异清单**（上游有、我们没有；逐个试点对照）：
   - 上游 `body` 有 `.compositingGroup()` + 整体 `.scaleEffect(gestureScale)`（手势进行时整体缩放）+ `ZStack(alignment: .top){ VStack{ mainLayout; chin } }` + `.padding(.bottom, 8)`；
   - 上游头部 VStack 用**默认 spacing**，我们 `spacing: 0` + 页面区 `.padding(.top, 8)`（上游没有这 8pt）；
   - 上游 `mainLayout` 外还有 `.padding(.bottom, effectiveClosedNotchHeight == 0 ? 10 : 0)`；chin 宽度链不同（我们 `baseClosedWidth`，上游 `computedChinWidth`）；
   - 上游 sneakPeek 行有 `.fixedSize()` 条件修饰；
   - 我们有 brief 歌词/通知行（`briefLayout.addedHeight`）会在展开态插行改高度——展开动画进行中插行会推动页面，注意时机。
5. **高度来源的语义差**：上游 `vm.notchSize.height` 是状态存储值（open()/close() 显式赋值），我们 `visibleHeight` 是公式推导。开/关数值一致，但**悬停中断、HUD 插行、多屏切换**等边界下两者的中间态可能不同。
6. **弹簧叠用**：我们外壳挂了 4 个 `.animation(shellAnimation, value:)`（notchState/visibleWidth/visibleHeight/activeKind）+ 打开事务 interactiveSpring(0.38/0.8)；上游只有 1 个 `.animation(开/关弹簧, value: notchState)` + 事务。多 value 触发在 HUD 插行等场景可能用了不同弹簧参数，观感会差一拍。
7. **NotchPointerCoordinator 的悬停阈值/挂起逻辑**（150ms/100ms，`Interaction/Core/NotchHoverStateMachine.swift`）与上游 `extendedHoverPadding` 行为的差异——若用户抱怨的是"跟手性"而不是形状动画，查这里。

## 6. 硬约束（动画改动不得违反，全文见仓库根 VectorX.md）

1. 触发区只能是**物理刘海矩形**（`NotchHitRegion.triggerRect`）；视觉扩展不得扩大触发判定；`visibleFrame`（逐帧上报的绘制形状）与 `triggerRect` 是两个概念。
2. 窗口运行期**不变尺寸**（750×380）；画到窗口外会被裁掉。动画全部由 SwiftUI 驱动；**禁止** AppKit 窗口尺寸动画与 SwiftUI 布局动画同时对同一元素生效。
3. 窗口永不抢键盘焦点（key/main 保持 false）；透明区域靠 `window.ignoresMouseEvents` 按光标位置动态穿透——新增动画元素不得破坏 `NotchPointerCoordinator` 的命中协商（`NotchPresentationReporter` 上报的几何就是命中区依据）。
4. 悬停/命中改动要并入状态机 `inVisibleContent` 判定，否则"画得出来点不着"。
5. HUD/brief 行插入只加高不压缩页面控件。
6. 合成 HID 点击无法触发小岛悬停、弹不出菜单——**自动化验证只能靠 §7 的诊断入口**，不要用合成点击做对照实验后误判自己改坏了。
7. 改用户可见文案要同步 `Localizable.xcstrings`（原位改，**严禁全表 sorted()**），跑 `python3 scripts/audit-localization.py`；纯逻辑改动进 `Interaction/Core/` 并配单测。
8. 不要主动 `git commit`（用户明确开口才提交）。

## 7. 自验工具（不需要用户配合）

### 7.1 程序化触发开合循环（DEBUG 构建才有）

菜单栏图标右键 →「动画检查（20 次开合＋10 次反向）」→ 程序化跑 20 次 open/close + 10 次中途反向。
代码入口：`boringNotch/boringNotchApp.swift` 的 `runInteractionCheck()`（菜单按钮在同一文件 `#if DEBUG` 段）。它调用 `entry.model.open(preferredPage: .home)` / `close(force: true)`，与悬停路径同动画管线（开已包 `withAnimation` 事务，与真实路径一致）。

**程序化切 tab（DEBUG）**：菜单项「调试：切换到主页」/「调试：切换到番茄钟」，代码入口同一文件的 `switchTab(to:)`——它走 `keepExpandedForUserCommand()` + `withAnimation(.smooth) { coordinator.currentView = view }`，与真实 tab 点击同管线，用于连拍 tab 切换帧（§4.5 的 `.transition(.identity)` 瞬时就位就是用它帧验证的）。

菜单也可用 AX 脚本点击（系统已授权辅助功能）：

```applescript
tell application "System Events" to tell process "Airlet"
  click menu bar item 1 of menu bar 2
  delay 0.5
  click menu item "动画检查（20 次开合＋10 次反向）" of menu 1 of menu bar item 1 of menu bar 2
end tell
```

### 7.2 帧连拍 + 逐帧分析

```bash
# 1) 取岛窗口坐标（显示器排布变化后要重取）
osascript -e 'tell application "System Events" to tell process "Airlet" to get {position, size} of window 1'
# 例：583, 1080, 750, 380 → 截取区域 -R583,1080,750,320

# 2) 连拍（~210ms/帧，够看机制；判手感请用 QuickTime 视频 + AVAssetImageGenerator 抽帧）
rm -rf /tmp/airlet-frames && mkdir -p /tmp/airlet-frames
( for i in $(seq -w 1 60); do screencapture -x -R583,1080,750,320 /tmp/airlet-frames/f_$i.png; done ) &
sleep 0.6
# 3) 触发动画（AX 点菜单「动画检查」，或请用户悬停）
# 4) 分析：
swift /tmp/frame-profile.swift   # 逐帧输出黑色壳 宽×高 + 亮色内容行分布
swift /tmp/art-profile.swift     # 逐帧追踪专辑图（饱和红块）尺寸/位置 → 判定内容是 morph 还是被遮罩扫出
```

判定标准：
- **morph（对）**：中间帧里页面元素（专辑图、控件列）尺寸/间距明显小于最终值，随壳一起长大；
- **遮罩扫出（错）**：中间帧里内容已是最终尺寸、被壳边缘裁掉一部分（左/下边缘出现"切边"，甚至与 header 重叠、内容上移被顶边裁切）。

### 7.3.1 冷开启协议（必须遵守，否则测不出用户抱怨的场景）

触发前让岛**静置 ≥10 秒**（确保所有弹簧完全收敛、无在飞事务），再触发一次打开。快速连开合时上一次动画还在飞行，即使代码有缺陷也会"看起来对"——这正是第 3 轮修复前漏判的原因。菜单路径用 §7.1 的「展开小岛」；悬停路径请用户配合触发。

### 7.4 同构建 A/B 法（归因利器）

同一个二进制上，用**不同触发路径**对比同一动画阶段（例如：菜单「展开小岛」= 包事务路径 vs DEBUG「动画检查」旧版 = 裸调用路径）。若两条路径表现不同，差异就在路径代码里；若表现相同，差异在共享代码里。第 3 轮定位冷开启根因时就是用本法（裸路径冷开启钉住 vs 包事务路径冷开启 morph）。

### 7.3 逐帧分析脚本（当前放在 /tmp，会丢；建议收进仓库后使用）

`frame-profile.swift`——逐帧找近黑像素包围盒（壳）：

```swift
import AppKit
let dir = URL(fileURLWithPath: "/tmp/airlet-frames")
for file in try FileManager.default.contentsOfDirectory(atPath: dir.path)
    .filter({ $0.hasPrefix("f_") && $0.hasSuffix(".png") }).sorted() {
    guard let img = NSImage(contentsOf: dir.appendingPathComponent(file)),
          let rep = NSBitmapImageRep(data: img.tiffRepresentation!) else { continue }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var minRow = h, maxRow = 0, minCol = w, maxCol = 0
    for y in 0..<h { for x in 0..<w {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        let lum = 0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent
        if lum < 0.16 { minRow = min(minRow, y); maxRow = max(maxRow, y)
                        minCol = min(minCol, x); maxCol = max(maxCol, x) }
    } }
    let s = 2.0  // retina 截屏 2x
    print("\(file): shell \(Double(maxCol-minCol+1)/s)x\(Double(maxRow-minRow+1)/s)pt")
}
```

`art-profile.swift`——追踪饱和红块（主页专辑图占位图是红底，天然示踪剂；若换图请换示踪色）：

```swift
import AppKit
let dir = URL(fileURLWithPath: "/tmp/airlet-frames")
for name in ["f_25","f_26","f_27","f_28","f_29","f_30"] {  // 按实际过渡帧调整
    guard let img = NSImage(contentsOf: dir.appendingPathComponent("\(name).png")),
          let rep = NSBitmapImageRep(data: img.tiffRepresentation!) else { continue }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var minRow = h, maxRow = -1, minCol = w, maxCol = -1
    for y in 0..<h { for x in 0..<w {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        if r > 0.45 && g < 0.45 && b < 0.45 && (r - max(g, b)) > 0.18 {
            minRow = min(minRow, y); maxRow = max(maxRow, y)
            minCol = min(minCol, x); maxCol = max(maxCol, x)
        }
    } }
    guard maxRow >= 0 else { print("\(name): no blob"); continue }
    print("\(name): blob \(Double(maxCol-minCol+1)/2)x\(Double(maxRow-minRow+1)/2)pt at col \(minCol/2), row \(minRow/2)")
}
```

## 8. 验收标准

1. **并排 60fps 录屏逐帧对照**（上游 vs Airlet，同样场景：无音乐静置展开、播放中展开、播放中收起、四个 tab 互切、HUD 触发时展开）：
   - 壳高度-时间曲线形状一致（允许整体相位差 <1 帧）；
   - 页面内容尺寸-时间曲线一致（morph 幅度与节奏）；
   - 无内容瞬间就位、无遮罩扫出、无跳帧/回跳。
2. 用户本人真机悬停主观确认（**这一步不可替代**——录屏一致 + 用户确认才算完成；只过录屏不算验收）。
3. 回归：`bash scripts/build.sh Debug`、`swift test --scratch-path /private/tmp/notch-island-next-core-build`（549 项）、`bash scripts/test-local-signing.sh`（30 项）、`python3 scripts/audit-localization.py` 全绿；装机后番茄钟、暂存区、HUD 接管无回归。

## 9. 诚实性纪律（交付双方共同遵守）

- 汇报进度必须区分"已验证 / 待验证 / 被阻塞"，帧实测/单元测试通过 ≠ 用户验收通过；
- 验收记录用 `| 项目 | 实际证据 | 结果及边界 |` 格式，写清证据不能证明什么；
- 动画是主观观感，**唯一最终判据是用户真机确认**。

## 10. 快速上手顺序（建议）

1. 读本文 §2 上游源码三处（ContentView 的 body/NotchLayout/doOpen）→ 读 §3 现状 → `git diff` 看 worktree 未提交改动（就是前两轮的全部修改）。
2. 按 §5.1 做并排录屏，定位"不对"具体是哪一段（展开前半 / 展开后半 / 收起 / tab 切换）。
3. 按对应嫌疑项修，每改一轮用 §7 自验（机制级）+ 录屏（手感级）。
4. 找用户真机确认。
