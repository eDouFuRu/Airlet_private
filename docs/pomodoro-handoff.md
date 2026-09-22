# 番茄钟交付文档（页面美化 / 后续开发）

> 交付目标：接手 Airlet 公开版**番茄钟页面美化**及后续功能开发。本文档给出代码地图、架构纪律、
> 小岛级硬约束、持久化兼容规则与验证工具。**动画系统**（展开/收起/tab 切换）另有专门文档
> `docs/animation-handoff.md`，本文不重复，两份都要读。
> 2026-09-22 整理。全部工作已提交（`8ebfa7a` + `7383d1b`，分支 `public-edition`）。

---

## 1. 工程与代码位置

| 项 | 值 |
|---|---|
| 开发仓库 | `/Users/dongfengrui/Documents/Rednote_Vibecoding/NotchIslandNext-pomodoro`（git worktree，分支 `public-edition`） |
| 应用 / Bundle ID | Airlet / `com.dongfengrui.Airlet`（XPC：`com.dongfengrui.Airlet.XPCHelper`） |
| 构建 | `bash scripts/build.sh Debug` → `build/Build/Products/Debug/Airlet.app` |
| 安装运行 | 先 `osascript -e 'tell application id "com.dongfengrui.Airlet" to quit'; sleep 3` + `pkill -f "Airlet.app/Contents/Resources/mediaremote-adapter.pl"`，再 `bash scripts/install-local.sh Debug`，最后 `open -a ~/Applications/Airlet.app`。**安装脚本拒绝应用运行时安装** |
| 真机待验项 | 滚轮循环手感、popover 主题输入、热力图交互、闭合态两翼显示、重启恢复（见 §8，均未真机验收过） |

## 2. 代码地图（全部在 `boringNotch/Interaction/`）

**纯逻辑 Core（`Interaction/Core/`，无 UI、可单测——改行为必须配测试）：**

| 文件 | 行数 | 职责 |
|---|---|---|
| `PomodoroSessionCore.swift` | 213 | 状态机：`PomodoroMode`（countdown/countup）、`PomodoroPhase`（idle/running/paused）、`defaultDurationSeconds`、`canStart`、`clockText`；**所有时间都从墙钟时间戳推导，不依赖 tick 累加** |
| `PomodoroHeatmapMath.swift` | 122 | 热力图聚合/配色档位数学 |
| `PomodoroSessionStore.swift` | 72 | 文件持久化（见 §5） |

**视图/桥接层（美化主要动这里）：**

| 文件 | 行数 | 职责 |
|---|---|---|
| `PomodoroModel.swift` | 217 | `PomodoroModel.shared`（ObservableObject）：@Published phase/mode/plannedSeconds/topic/remainingSeconds/elapsedSeconds/justCompleted + ticker Timer。桥接 Core → SwiftUI |
| `PomodoroPage.swift` | 249 | 小岛里的番茄钟页面；根 `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment: .top)`（第 24 行，**不许拆**，见 §4.1）；内含 `TopicEditorPopover` |
| `PomodoroRingView.swift` | 88 | 环形进度 |
| `PomodoroWheelPicker.swift` | 172 | 滚轮选择器（时长选择） |
| `PomodoroHeatmapView.swift` | 160 | 热力图 |
| `PomodoroSettings.swift` | 55 | 设置窗口里的番茄钟区块，挂在 `SettingsView.swift:81` |
| `TomatoStatusIcon.swift` | 72 | 闭合态两翼图标 + 菜单栏图标共用位图（`boringNotchApp.swift:22`、`TabSelectionView.swift:20`） |

**单测**：`Tests/NotchInteractionTests/Pomodoro{SessionCore,HeatmapMath,SessionStore}Tests.swift`（swift test 全套 549 项的一部分）。

## 3. 架构纪律：计时结算与展示分离（硬约束，违反 = 回退）

- **结算时点只由 Core 决定**（墙钟推导 + 先持久化后展示，见 `PomodoroModel.swift` 头注释）。美化改动**只能动展示**：环、滚轮、热力图、配色、布局、动效；不得让 UI 状态影响 tick、结算、持久化时点。
- 新增可测试决策（如新的配色档位算法、新的时长档位规则）→ 放 `Interaction/Core/` 纯 Swift + 单测，视图层只消费。

## 4. 小岛级硬约束（美化最容易踩的四个）

1. **页面必须纵向撑满提案**：`PomodoroPage` 根部的 `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment: .top)` 是整页的"弹性来源"。壳高度是外部逐帧动画提案的（见动画文档 §4.3），页面撑不满 → 岛塌到内容理想高度。改布局时保留这个 frame，内部随意。
2. **tab 切换是瞬时就位**：`ContentView.swift:371` 的 `PomodoroPage().transition(pageSwapTransition)`（= `.identity`）是刻意设计——用户拍板切 tab 不做动画。**不要给页面或其子树加 transition**，否则"从上滑下来"的旧 bug 复活（根因分析见动画文档 §4.5）。
3. **承载窗口固定 750×380、运行期不变尺寸**：画到窗口外的内容会被裁掉；岛宽由 `visibleWidth` 公式算，页面内不要试图撑破它。
4. **闭合态两翼是两条平行链**：若美化涉及闭合态的番茄钟倒计时图标/宽度（`ContentView.swift:112` `showsPomodoroOnClosed`、`:156` 宽度 +88、`:410` header 绘制分支），**三条引用点必须一起改**，否则"壳撑宽了却什么都不画"或反之。

## 5. 持久化与数据兼容（改存储结构前必读）

- 文件：`~/Library/Application Support/boringNotch/Pomodoro/sessions.json`（`PomodoroSessionStore.swift:3`）。
- 容器 = 会话数组 + `openRun` 槽（第 13 行）——序列化的运行中机器状态，用于**跨启动恢复**。
- `load()` 逐条兜底解码（第 44-47 行）：单条坏记录被丢弃，坏 `openRun` 被丢弃（丢一条进行中的会话可接受，丢整个历史不可接受）。
- **给容器/会话新增字段必须是 Optional**（或带默认值的自定义解码），否则旧文件整体判损坏。改完必须跑 `PomodoroSessionStoreTests` 并用一个手工造的旧格式 JSON 验一遍。

## 6. 设置项与本地化

- Defaults 键集中在 `boringNotch/models/Constants.swift:111-116`（`showPomodoroTimerOnClosed`、`pomodoroHeatmapPalette` 等）；新设置项加在这里，UI 加进 `PomodoroSettings.swift`。
- **任何用户可见文案**（页面、设置、popover、辅助功能标签）必须中英双语进 `Localizable.xcstrings`：**原位删除 + 尾部追加，严禁全表 sorted()**（会把 diff 炸到上百 hunk）。改完跑 `python3 scripts/audit-localization.py`。
- 代码里用 `L("…")` 取串。

## 7. 素材与发布基线

- 相关资产在 `boringNotch/Assets.xcassets/`：`PomodoroTomato`（环内占位番茄）、`TomatoGlyph`（用户番茄线稿剪影，template 模式，可随标题染色）、`logo2/tomato-brand.png`（品牌图）、`AppIcon.appiconset/tomato-*.png`。
- ⚠️ 发布守卫：`scripts/release-artwork-baseline.txt` 锁了 10 项素材的 sha256。**替换任何素材后**要跑 `bash scripts/package-release.sh --update-artwork-baseline` 固化新基线（先人工确认图没问题）；**不要用 `--audit` 启发式模式**（误报多）。

## 8. 验证与诚实性

```sh
swift test --scratch-path /private/tmp/notch-island-next-core-build   # 549 项
bash scripts/build.sh Debug
python3 scripts/audit-localization.py
bash scripts/test-services.sh   # 服务层 harness 97 项（动了服务层才需要）
```

**当前真机待验清单（截至本文档，均未人工验收，接手后美化验收可顺带覆盖）**：
滚轮循环手感、popover 主题输入（IME）、热力图交互、闭合态两翼倒计时显示、重启后会话恢复。

**诚实性纪律**：`swift test` 通过 ≠ 功能验收；汇报必须区分"已验证 / 待验证 / 被阻塞"，验收记录用
`| 项目 | 实际证据 | 结果及边界 |` 格式。最终判据是用户真机确认。

## 9. 快速上手顺序

1. 读 `docs/animation-handoff.md` §4（动画机制四定律）——页面美化在展开动画下工作，不懂机制会改坏。
2. `git log --oneline -3` 看基线；读本文 §2 代码地图，通读 `PomodoroPage.swift`（249 行，是美化的主战场）。
3. 美化迭代循环：改视图层 → `swift test` → `build.sh Debug` → 装机 → 真机看展开动画下页面表现（用动画文档 §7 的帧连拍自验，冷开启协议 ≥10s 静置）。
4. 涉及 Core/存储/文案/素材的改动分别按 §3/§5/§6/§7 的规则走。
