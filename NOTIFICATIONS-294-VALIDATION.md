# Build 294 —— 应用通知通用化：任意 App 自动接管

范围：把 293 的**白名单制**改成**通用制** —— 任意 App 的桌面横幅都能被转显，
App 在发出第一条通知后自动出现在设置页，逐个可关；多张卡片同时在屏时取最上面一张。
「隐藏系统原生横幅」「横幅跟随小岛所在屏」两项按约定放到 295。

## 改动

| 文件 | 改动 |
|---|---|
| `Interaction/Core/ApplicationNameIndex.swift`（新增） | `BannerNamePrefix` 抽出前缀匹配（分隔符 空格/`,`/`，`/NBSP/全角空格/换行，名字上限 80 字符）；`ApplicationNameIndex.resolve(bannerDescription:)` 把横幅署名解析成 `bundleID + displayName + 正文剩余`。歧义裁决链：最长名字 → 剔除嵌套在别人包里的 bundle → 优先正在运行的 → 仍并列则放弃归属 |
| `Interaction/Core/AppNotificationPolicy.swift`（新增） | `allows(bundleID)`：显式选择 > 内置排除 > 「新 App 默认」。`allowsAnySource` 决定还值不值得挂观察器；`isUnconfigured` 供设置页判断是否显式配置过 |
| `Interaction/Core/AppNotificationMigration.swift`（新增） | 旧的 hi 专用键 `enableHiNotifications` / `hiNotificationDetail` 一次性迁进共享字典，**永不覆盖**已存在的值；空 bundleID 直接拒绝，不写空键 |
| `Interaction/Core/BannerCardSelection.swift`（新增） | 多卡时取 y 最小（AX 原点在左上，最上面 = 最新）；并列取最左；坐标读不到就跳过，但只有一张时仍然保留 |
| `Interaction/Core/AppNotificationNameFilter.swift` | `isContained` 提升为 `isBundlePath(_:containedIn:)`，`ApplicationNameIndex` 复用同一套「helper 不算另一个 App」判定 |
| `Interaction/Core/HiNotificationState.swift` | `matchedDisplayName` 改走 `BannerNamePrefix`；`Notice`/`Candidate` 增加 `sourceName`（归属失败时也有东西可渲染）；`enabledSources`/`detailedSources` 两个 Set 换成 `AppNotificationPolicy`，Set 版 `configure` 保留为适配器 |
| `Interaction/InstalledApplicationCatalog.swift`（新增） | 运行中 App（便宜、覆盖绝大多数真实发信方）+ 磁盘扫描（覆盖「脚本编辑器没在跑也能发通知」这类情况）。扫描在 `Task.detached(.utility)` 上跑，10 分钟内不重复；归属失败时才 `refreshIfStale()`。缓存 bundleURL 与图标（`NSWorkspace.icon(forFile:)` 每次都会重建位图，动画期间扛不住） |
| `Interaction/AppNotificationPreferences.swift` | 硬编码白名单**删除**。新键：`appNotificationAllowsNewSources`（默认 true）、`appNotificationDetailsNewSources`（默认 true）、`seenAppNotificationSources`（见过即记名）、`appNotificationLegacyHiMigrated`。内置排除只有小岛自己 |
| `Interaction/HiNotificationSource.swift` | 归属改走 catalog；多卡/堆叠不再整体丢弃，改 `topmostCard`；识别成功即 `remember()` 落进 `seen`；图标与点击回退都走 catalog |
| `Interaction/HiNotificationSettings.swift` | 新增「macOS 通知权限」段（含跳转按钮，并注明本 App 读不到那份权限）、「新 App 的默认行为」两个开关、空列表提示；行渲染抽成 `AppNotificationRow` |
| `Localizable.xcstrings` | 删 1 条、新增 12 条中英词条 |
| `scripts/build.sh` + `project.pbxproj` | build 293 → 294 |

## 验收表

| 项目 | 实际证据 | 结果及边界 |
|---|---|---|
| 单元测试 | `swift test` → `Executed 564 tests, with 0 failures` | **已验证**逻辑正确。不能证明真机可用 |
| 服务层 | `./scripts/test-services.sh` → `97 passed` | **已验证**服务层无回归 |
| 双语 | `python3 scripts/audit-localization.py` → `948 entries` PASS | **已验证**新增文案中英齐备 |
| 签名自检 | `bash scripts/test-local-signing.sh` → `30 passed` | **已验证**脚本安全性 |
| 构建 | `bash scripts/build.sh Debug` → BUILD SUCCEEDED，固定证书 | **已验证**签名成功。不等于功能可用 |
| 装机 | `~/Applications/工位充电岛.app`，`CFBundleVersion = 294`，`Identifier=com.dongfengrui.NotchIsland` | **已验证**已装机运行 |
| **通用化转显（无任何白名单）** | 清空四个通知相关 Defaults 模拟新用户 → 装 294 → `osascript` 弹真实横幅。截图 `/tmp/i294-d.png`：小岛闭合态出现「脚本编辑器 · 通用化A · 通用化转显正文」并带脚本编辑器图标 | **已验证**。脚本编辑器已不在任何白名单里，完全靠 catalog 自动识别 |
| **设置页自动收录** | `defaults read … seenAppNotificationSources` 由空变为 `{ "com.apple.ScriptEditor2" = "脚本编辑器"; }`；设置页「应用通知」出现「脚本编辑器」分组（AX 树实读） | **已验证**「发过一条就自动出现在设置里」 |
| **点击打开** | 点击小岛提示行 (910,1125) → `System Events` 报告 frontmost = `Script Editor` | **已验证**。边界：与 293 同，未能区分 AXPress 与 `NSWorkspace` 回退 |
| **逐个 App 关闭** | AX 点掉「脚本编辑器」开关 → `enabledAppNotificationSources` 写入 `com.apple.ScriptEditor2 = 0` → 再弹横幅，截图 `/tmp/i294-off.png` 小岛保持闭合无提示 | **已验证**单 App 关闭生效 |
| **显式开启优先于总开关** | 关掉「转显尚未配置过的 App 的通知」（`appNotificationAllowsNewSources = 0`）+ 显式打开脚本编辑器 → 截图 `/tmp/i294-e.png` 仍正常转显 | **已验证**显式选择优先级高于默认行为 |
| **总开关关 + 未配置 = 不转显** | 移除脚本编辑器的显式键（回到未配置）且总开关仍为 0 → 截图 `/tmp/i294-f.png` 小岛闭合无提示 | **已验证**默认行为开关真的生效（顺带证明外部 `defaults write` 能被 App 实时接住） |
| **内容预览开关** | 把「消息展示方式」切成「仅提示有新通知」→ 截图 `/tmp/i294-h.png` 只显示「脚本编辑器 有新通知」，标题与正文都不外泄 | **已验证**预览关闭后不泄露内容 |
| **hi 零配置回归** | 迁移把旧键搬成 `com.electron.redcity = 1/1`；本次运行中同事真实 hi 群消息 3 条（12:07:36 / 12:08:10 / 12:09:18，探针记录 `desc=[REDcity <会话名>, <姓名>:<正文>]`，内容已脱敏）；设置页 REDcity 行显示「本次运行已收到实际桌面通知」 | **已验证**。hi 在 294 下**不需要任何手工配置**即可转显，旧设置被正确迁移 |
| 连发聚合 | 0.25s 内连发 3 条 → 截图 `/tmp/i294-g.png` 显示「脚本编辑器 · 堆叠3 · 堆叠正文3 **(2)**」 | **已验证**取最新一条并计数。边界：计数是 2 不是 3 —— 探针显示 macOS 把第 2 条**原地替换**进了第 1 张卡片，系统层面只产生了 2 个 UUID，不是我们漏了一条 |
| 多卡取最上面一张 | `BannerCardSelection` 有单测覆盖（最小 y / 并列取左 / 坐标不可读跳过 / 非有限坐标拒绝） | **仅单测验证**。本机实测始终只有一张卡在屏（连发 4 条也只是原地换内容，`AXNotificationCenterBannerStack` 从未出现），真机堆叠场景**未能复现**，因此这条路径**未在真机上验证** |
| catalog 扫描开销 | 独立探针复刻同一组搜索路径：冷启 `263 个 .app / 231 个唯一 bundleID / 1566 ms`，热态 `266 ms`；运行中 App 85 个 | **已测量**。扫描在后台 `.utility` 队列、10 分钟节流，不在抓取热路径上。边界：这是探针进程的数字，不是 App 内实测（`log show` 在本机读不到该进程日志） |
| macOS 通知权限提示 | 设置页新增段落实读到位：「App 必须先在『系统设置 → 通知』里被允许发送通知…」+「打开系统通知设置」按钮 | **已验证**文案与按钮存在。按钮跳转本身未点验 |
| **微信零配置回归** | — | **待验证**。本轮期间没有收到真实微信消息；`com.tencent.xinWeChat` 的解析路径与 hi 完全同构，但没有 294 下的真实样本 |
| 隐藏原生横幅 / 跟随小岛所在屏 | — | **不在本轮范围**，按约定放 295 |

## 排查记录：一开始「294 完全不转显」是勿扰模式

装机后第一轮测试，`osascript` 弹通知小岛毫无反应、`seen` 一直是空。
挂 AX 探针轮询通知中心，**一张卡都抓不到** —— 说明系统层面根本没弹横幅，问题不在本项目。
逐一排除：脚本编辑器在系统设置里 `allow-notifications=1`、桌面=1、提醒样式=临时，全是对的。
最后在控制中心 AX 树里读到 `AXCheckBox 勿扰模式 | 1` —— **勿扰模式开着**。
用户关掉后，同一条命令立刻弹出横幅，上面所有验收项一次通过。

教训：**「小岛没弹」要先证明「系统弹了」**。挂一个只读通知中心 AX 树的探针比看小岛截图有效得多。

## 已知差距

1. 微信在 294 下没有真实样本，只有 293 的验收可以佐证解析链路。
2. 多卡堆叠取最上面一张只有单测，真机复现不出堆叠形态。
3. 提示行 5s 后消失，小岛内仍没有通知历史。
4. 归属失败（catalog 认不出署名）时会退化成「整条 description 当 sourceName」，这条兜底路径没有真机样本。
5. catalog 磁盘扫描只覆盖固定的 6 个目录 + 一层子目录，装在其它位置的 App 只能靠「正在运行」被识别。
