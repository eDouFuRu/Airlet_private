# Build 293 —— 系统通知接管：真实消息转显 + 点击打开

范围：把既有的应用通知实验（`HiNotificationSource` + 设置页 + 小岛提示行）用**真实系统横幅**跑通，
并把微信加入通知源白名单。通用「所有 App 自动接管」不在本轮。

## 根因：归属解析建立在错误的横幅格式假设上

在本机用 `osascript -e 'display notification …'` 弹出真实横幅，读通知中心（pid 1238）的 AX 树：

```
AXWindow  title="Notification Center"  subrole=AXSystemDialog  1512x982
 └ AXGroup › AXGroup › AXScrollArea
    └ AXGroup subrole=AXNotificationCenterBanner  344x73  [AXPress]
       AXIdentifier            = A516651C-2832-4BD1-87C0-2096DA996582   （每条通知一个 UUID）
       AXAttributedDescription = "脚本编辑器 标题B, 副B, 正文B"
       ├ AXStaticText AXIdentifier="title"    AXValue="标题B"
       ├ AXStaticText AXIdentifier="subtitle" AXValue="副B"
       └ AXStaticText AXIdentifier="body"     AXValue="正文B"
```

逐码点确认，App 名与标题之间是 **U+0020 普通空格**，只有其余字段之间才是 `", "`。
旧实现 `HiNotificationSourceEvidence.attributedAppName()` 按**第一个逗号**切 App 名，
真实横幅上得到的是 `"脚本编辑器 标题B"`，永远匹配不到任何 App 显示名，
`captures()` 的 `matching.count == 1` 因此恒不成立 —— **任何 App 的横幅都不会被转显**。
旧单测还专门断言 `"<Name> task finished"` 不得匹配，即当初的假设与真实系统格式相反。

## 改动

| 文件 | 改动 |
|---|---|
| `Interaction/Core/HiNotificationState.swift` | 删除 `attributedAppName`，改为 `matchedDisplayName(in:candidates:)`：整条 description 做前缀匹配，分隔符 空格/`,`/`，`/NBSP/全角空格/换行；最长候选优先，长度并列则拒绝。`bannerDescriptions` 取代 `appNames` |
| `Interaction/HiNotificationSource.swift` | 调用点改为把整条 description 交给 evidence；`cardIdentity` 优先用卡片 `AXIdentifier` 的 UUID，为空才回退 `hash(pid, CFHash(window), CFHash(card))` |
| `Interaction/AppNotificationPreferences.swift` | 新增 `com.tencent.xinWeChat`（别名 `WeChat` / `微信`）与 `com.apple.ScriptEditor2`（别名 `Script Editor` / `脚本编辑器`，作为长期自检入口）。两者默认关闭 |
| `Interaction/Core/AppNotificationNameFilter.swift`（新增） | 去歧义过滤改为按 bundle 路径包含关系判定：跑在源 App 包内部的 helper 不算「另一个 App」，不再剔除它借用的名字 |
| `Interaction/Core/BriefPresentation.swift` | 新增 `noticeMinimumWidth = 420` |
| `ContentView.swift` | 通知档给 `BriefPresentationLayout` 传 `minimumBriefWidth`；提示行去掉 `scrolls: false`，长文本沿用歌词行的「停留 2s 后滚一次」 |
| `scripts/build.sh` + `project.pbxproj` | build 292 → 293 |

`cardIdentity` 改用 UUID 的原因：真实横幅共用同一个整屏 `Notification Center` 窗口，
`CFHash(window)` 恒定、`CFHash(card)` 会被系统复用，容易让新通知被 `HiAXCardTracker` 误判成旧卡片。
UUID 只在内存里做去重键，不落盘、不写日志。

## 验收表

| 项目 | 实际证据 | 结果及边界 |
|---|---|---|
| 单元测试 | `swift test` → `Executed 540 tests, with 0 failures` | **已验证**逻辑正确。不能证明真机可用 |
| 服务层 | `./scripts/test-services.sh` → `97 passed (8 groups)` | **已验证**服务层无回归。用的是假 helper，不碰真实硬件 |
| 双语 | `python3 scripts/audit-localization.py` → `937 entries` PASS | **已验证**静态词条齐备。本轮未新增可见文案 |
| 签名自检 | `bash scripts/test-local-signing.sh` → `30 passed` | **已验证**脚本安全性。不等于产物已授权 |
| 构建 | `bash scripts/build.sh Debug` → BUILD SUCCEEDED，证书 SHA-1 `0A93…3DB2` | **已验证**固定证书签名成功。不等于任何功能可用 |
| 装机 | `install-local.sh Debug` → `~/Applications/工位充电岛.app`，`CFBundleVersion = 293` | **已验证**已装机运行 |
| **真实横幅转显** | 真机截图 `/tmp/island-notice-1.png`：`osascript` 弹出真实横幅后，小岛闭合态出现「Script Editor · 张三…」带脚本编辑器图标 | **已验证**。这是该功能第一次在真实横幅上成功。边界：署名为「脚本编辑器」的本机测试横幅，不是第三方 IM |
| **点击打开** | 真机：小岛提示行坐标 (752,45) 合成点击后，`System Events` 报告 frontmost = `Script Editor`，小岛提示行随即收起（截图 `/tmp/island-click-after.png`） | **已验证**「点击 → 打开来源 App」。边界：**未能区分**走的是原横幅 `AXPress` 还是 `NSWorkspace` 回退 —— 独立 `pressat` 实测 AXPress 同样不会让 osascript 横幅消失，所以「横幅是否还在」无法作为判据 |
| 连发聚合 | 连发甲/乙/丙三条，加宽后截图 `/tmp/island-burst2.png` 显示「Script Editor · 丙 · 第三条消息 **(3)**」 | **已验证**显示最新一条并带条数计数 |
| 加宽 + 滚动 | 截图 `/tmp/island-wide-1.png` / `-2.png`：22 字长消息先显示前半段，约 3s 后滚动到「…你那边方便吗？」完整可读 | **已验证**闭合外壳加宽到 420 且长文本滚动 |
| **微信真实消息转显** | 好友真实微信消息，AX 探针抓到 `desc=[微信 真别豆腐乳🌰, 点击测试] id=5D634906-892F-4D52-A547-95E62696019F fields=["title=真别豆腐乳🌰","body=点击测试"] actions=AXPress/回复/关闭`；用户确认小岛上弹出了该提示 | **已验证**。真实第三方 IM 消息转显成功。同轮还顺带抓到 ValOS 的真实横幅 `desc=[ValOS ValOS, Agent 有问题需要您回答]` |
| **点击打开到具体会话** | 用户亲手点击小岛提示行，实测**直接跳到该好友的聊天窗口**，不是只打开微信主窗口 | **已验证**走的是原横幅的 `AXPress` 动作而非 `NSWorkspace` 回退。边界：单条微信消息样本，未覆盖群消息/公众号 |
| 微信名字被误剔除（拦路石） | `discover()` 探针实测 `com.tencent.xinWeChat attributableNames=["WeChat"]`，`微信` 被丢弃；肇事者是 WeChat.app 包内的 `com.tencent.flue.WeChatAppEx`（pid 67068，`localizedName=微信`） | **已修复并验证**：改用 `AppNotificationNameFilter` 按 bundle 路径包含关系判定「同一个 App 的内部 helper」，修复后 `attributableNames=["WeChat","微信"]` |
| macOS 侧微信通知权限 | System Settings AX 读出：允许通知=1、桌面=1、通知中心=1、锁定屏幕=1、提醒样式=临时、角标=1、声音=1 | **已验证**系统侧配置正确，横幅未见不是权限问题 |
| 「原生横幅没弹」的真相 | `displays`：外接 `U27P2G6B` 在 `(0,0) 1920x1080` 为主显示器，内建屏在 `(202,1080)`；探针记录横幅坐标恒为 `@1560…1932,46`，全部落在外接屏 | **已定位**，不是缺陷：横幅弹在外接屏右上角，小岛在内建屏，用户看不到而已 |
| hi 走不走系统通知 | 用户在 hi 内打开通知后，`REDcity` 出现在系统设置→通知列表（此前 25 个 App 里没有它）。macOS 用的署名是 **REDcity**，正在我们的可归属名字集合 `["REDcity","hi"]` 内 | **已验证**hi 用的是 macOS 系统通知（不是自绘窗口），走的是同一条 AX 抓取路径；署名也命中 |
| hi 曾被 macOS 总开关挡住 | 打开前 System Settings AX 读到 `allow-notifications=0`（其余 桌面/通知中心/提醒样式=临时 都是对的）；用户手动打开后读回 `allow-notifications=1` | **已定位并解除**。这解释了为什么 hi 从来没在这台机器上注册过通知 |
| **hi 真实消息转显** | 同事发来的真实 hi 消息，AX 探针抓到 `desc=[REDcity <姓名>, <正文>] id=A3BBFCB0-7B29-4B38-8B5A-9A260C57B8BF fields=["title=<姓名>","body=<正文>"] actions=AXPress`（内容已脱敏）；用户确认小岛正常弹出 | **已验证**。署名确为 `REDcity`，格式与微信/ValOS 同构 |
| hi 点击打开 | — | **待验证**。与微信走同一条 `AXPress` 路径，但 hi 未单独点过 |
| 发给「文件传输助手」不弹横幅 | 自发消息全程无横幅，好友消息立刻有 | **微信自身行为**，非本项目缺陷 |
| 隐藏原生横幅 | 未启用。实测横幅窗口 `AXPosition` 的 `settable == true` | **本轮明确不做**。可设置 ≠ 移动/还原已验证，开关保持禁用 |
| 通用「所有 App」接管 | — | **不在本轮范围** |

## 下一轮待办（用户已提出）

1. **隐藏系统原生横幅**，真正做到「只进小岛」。
2. **横幅跟随小岛所在屏幕**：用户实测外接屏上也会显示小岛，横幅应该弹在小岛所在的那块屏。
3. 通用化：从白名单改成「所有会发通知的 App 自动发现 + 逐个开关」。

## 已知差距

1. 提示行仍是白名单制（hi / ValOS / Lobi / ChatGPT / 微信 / 脚本编辑器），不是「所有 App」。
2. 微信横幅自带「回复」自定义动作，目前未使用；小岛内直接回复尚未实现。
3. 提示行 5s 后自动消失，错过就只能回系统通知中心找，小岛内没有历史列表。
4. 微信只验了单条一对一消息，群消息 / 公众号 / 聚合形态未覆盖。
5. hi 只验了转显，点击打开未单独点过（与微信同一条 AXPress 路径）。
   过程中的教训：**「微信通了」不等于「hi 通了」** —— hi 当时卡在「App 从未在系统通知里注册」，
   跟解析逻辑毫无关系；而「系统通知列表里没有它」只代表从没发过，不代表它不能发。
