# 系统 HUD 与 2.5D 薯队长验收记录

日期：2026-09-06。工程基准：boring.notch v2.7.3 / 16b0f11f51c79d42e27c10d77fd9e53c11410fdb。**Build 266 已严格验签、安装并运行于 `~/Applications/工位充电岛.app`，主进程 PID 40151 实际诊断 AX=true、Event tap=true，状态为“正在使用小岛提示”；同证书 265→266 更新未修改权限或重新授权，前后 AX/tap 均保持 true。** 266 原生通用/HUD 设置标题与正文即时切换中英，已恢复中文。265 的真实按键验收中，用户确认不按 Option 的亮度/音量按键会改变实际值，提示显示在刘海上，系统右上角没有同时出现；闭合内嵌 HUD 基本硬件操作通过。真实一分钟休息的计时、关键阶段、一次结算、暂停继续及提前结束也已通过。默认样式已有真实按键与回读日志，视觉确认仍待用户；完整原生动画流畅度及其他场景继续验收。核心 103 项、服务 87 项、签名安全 30 项和 DR 策略 7 项通过；素材、双语审计及离线预览已整合。此记录区分日志、静态验证与用户实际按键确认。

## 实现与证据

| 项目 | 实现情况 | 验证证据 |
|---|---|---|
| 系统媒体键 | 解析 systemDefined subtype 8；亮度、静音、音量 down/up 成对，重复音量/亮度串行，其他事件原样传递 | Core 媒体解析、配对、长按测试；实际 AppKit/CG adapter 类型检查 |
| 设备操作 | 亮度读写串行，XPC 单次回复与 2 秒超时；音量读写与回读，失败不发布伪目标值 | 服务 harness；265 真实亮度回读 0.4466 success、音量回读 0.6380 / muted=false / success；用户确认普通亮度与音量按键实际生效 |
| 权限与监听 | 主进程 AX 检查，启用意图不被权限状态覆盖；监听失活恢复；前台切换/唤醒刷新；诊断显示进程、签名、AX、tap、最近 20 条媒体事件及最后一次实际控制回读/错误/时间 | HUD 服务 30 项；硬件控制服务 22 项；265→266 无重新授权，更新前后主进程 AX/tap 均 true；真实媒体键 down/up 接管证据来自 265 |
| 隐藏与锁屏 | 无真实可见面板停止拦截；隐藏/禁用后旧按键任务及迟到亮度结果不再弹出；启动先读取 public onConsole/loginDone，未知会话保持关闭；私有可选锁屏字段仅作补充，唤醒不清除会话未激活状态 | Core 初始化会话 7 项；服务 availability/generation 测试；265 原生菜单隐藏时 tap=false，显示后 tap=true，AX 和启用偏好保持；隐藏期间真实按键、摄像头及锁屏待验 |
| HUD 显示 | 独立于音乐/计时，最后一次提示 2 秒；内嵌两翼留出摄像头，默认增加 44pt 行保留正文；全屏媒体策略不遮 HUD；闭合英文背光和错误使用短文案，展开/help/辅助功能保留完整说明 | SystemHUDTests 11 项；生产组件离线编译；50 张 HUD 预览与像素核验 |
| 刘海交互 | 物理触发区未随 HUD 两翼扩宽；固定承载 680×360；SwiftUI 外壳动画 | 原生 debug 菜单程序驱动 20 次展开/收起＋10 次反向：2082 次几何采样，固定 carrier/物理 trigger、非激活与鼠标路由诊断通过；真实悬停、输入及帧率待验 |
| 双语设置 | 修复 Defaults.Toggle 的字符串直出，LaunchAtLogin/快捷键标签使用显式 Text；11 个导航标题使用 Text(verbatim: L())，移除竞争 AppKit 观察；HUD 诊断可展开、选中和复制 | 266 审计：488 catalog、8 项 InfoPlist、367 静态 UI key、6 项审计器回归通过；原生通用/HUD 标题、正文、侧栏和控件即时切换中英并恢复中文；复制待验 |
| 2.5D 图像 | 抱薯、种薯、烤薯三张精修主图，以及身体、道具、地面源图；与用户原型一致的红衣、绿芽、薯形 | imagegen 输出逐张查看；源图及提示词归档 |
| 三款图标 | 3 张完整主图等比例缩小导入三图标、品牌图；默认款补齐 16–1024 像素 macOS 尺寸 | scripts/export-shu25d-icons.sh，源图保留 |
| 连续动画 | 11 个 RGBA 图层已接入共享挂点和七阶段动作；暂停、离屏与减少动态效果门控；库存从右下填充，六口遮罩按食物实际 alpha 宽度切分 | 时间轴/交付 7 项；57 张静态图与完整采样 GIF；原生已见种植、烘烤、完成阶段，未连续观看整轮，帧率/流畅度仍待验 |
| 数据 | 不改 v2 计时与库存规则；原迁移、奖励和展示登记保留 | Core 回归；原生一分钟库存 4→5、creditedRestCycles=1；再次展开未重复加库存，第二轮暂停后提前结束仍为 5 |

完整 Core **103 项通过**，服务 **87 项通过**（7 组：30 + 11 + 4 + 7 + 6 + 7 + 22）。服务测试使用实际生产方法与替身硬件，不操作用户真实音量、亮度、日历或分享服务；实际媒体键 adapter 另做类型检查，不安装 event tap。

主要证据：

- [核心测试](build/validation/hud25d/core-tests.log)、[服务测试](build/validation/hud25d/service-tests.log)。
- [266 双语审计](build/validation/hud25d/hud-localization-audit-266.log)：488/8/367，6 项扫描器回归通过；静态 key 比此前 368 少 1，来自移除旧通用标题调用，不是删除翻译词条。
- [Build 263 构建日志](build/validation/hud25d/build-signed-263.log)：Xcode 报 `BUILD SUCCEEDED`，但后置签名步骤失败；不算整个构建/验签流程成功。
- [Build 263 资源修复验签](build/validation/hud25d/signature-263-verification.log)：中止的旧 codesign 导致 XPC seal 残留 `.cstemp`，重新签名自有 XPC 与主应用后严格校验通过。此版仍因本地证书无 Team ID 导致 DYLD 库验证拒绝，不能运行。
- [Build 264 构建](build/validation/hud25d/build-signed-264.log)、[安装及备份](build/validation/hud25d/install-264.log)、[稳定身份](build/validation/hud25d/signature-264-requirements.txt)：本地专用 entitlements 修复库加载后，固定路径应用已实际启动；设置中看到简体中文与内嵌 HUD 选项。
- [Build 265 构建](build/validation/hud25d/build-signed-265.log)、[严格验签](build/validation/hud25d/signature-265-verification.log)、[安装与旧版备份](build/validation/hud25d/install-265.log)：265 曾运行于固定路径，主 PID 35020 的 AX/tap 均通过；该版承载本轮真实硬件、计时和窗口诊断验收。
- [Build 266 构建及稳定验签](build/validation/hud25d/build-signed-266.log)、[安装与 265 备份](build/validation/hud25d/install-266.log)、[更新后实测](build/validation/hud25d/post-update-266.json)、[当前原生会话](build/validation/hud25d/native-session.json)：当前固定副本为 266，主 PID 40151 的 AX/tap 均通过。
- [构建/签名/安装安全检查](build/validation/hud25d/signing-interruption-tests.log)：30 项生产函数安全测试、7 项 DR 策略检查及本地 entitlements/runtime 配置检查通过。**构建/签名锁仅成功退出后释放，失败或中断时保留锁与原因，禁止自动重入；安装器仍执行失败回滚和自身锁清理。** 旧 23 项日志仅保留历史。

## HUD 离线预览

[HUD 预览目录与说明](build/validation/hud25d/hud-previews/README.md)包含 **40 种状态、8 张摄像头辅助线图、2 张总览，共 50 张 PNG**。覆盖中英、展开/收起、inline/default、音量/亮度/错误/背光/麦克风。使用生产 HUD、进度条、形状及 IslandPage，隔离设置和硬件控制；default 标题栏为代表性占位，没有实例化完整 ContentView 或原生窗口。

本机屏幕宽 1512 点，safeTop 为 32 点，左右辅助区为 663/664 点，得到 **185 点**摄像头留空。40 个留空区域均无内容侵入，40 个 HUD 图标均可见；10 组正文保持 **206 点**高度，default 只下移 **44 点**。像素对照采用每色通道 3/255 容差，保留了实际差异，不宣称逐字节完全一致。见 [几何记录](build/validation/hud25d/hud-previews/geometry.json)、[像素核验](build/validation/hud25d/hud-previews/pixel-checks.json)和[源码/素材散列](build/validation/hud25d/hud-previews/manifest.json)。

## 签名进度

通过 Apple 证书助理在**登录钥匙串**创建了专用证书：

- 名称：NotchIsland Local Development
- SHA-1：0A93291611F302DBECD76D2ACEC9DEF86D1F3DB2
- 有效期至 2036-09-03；仅签名/代码签名扩展
- 私钥未导出，仓库仅包含证书公开标识；公开 PEM 在验证输出目录
- 默认构建与安装脚本严格检查此证书、Bundle ID 和稳定 designated requirement，禁止静默回退

此前的信任审批阻塞已解除：在用户明确同意后，**当前用户 codeSign 信任已成功设置**，专用证书列为有效签名身份，见 [身份查询结果](build/validation/hud25d/signing-identity.txt)。本轮没有扩展为系统级或管理员信任。Build 263 的资源签名问题及后续自签证书库加载限制均已修复；264、265、266 已先后完成严格验签和固定路径安装，旧副本已备份。

历史授权刷新仅针对 `com.dongfengrui.NotchIsland` 的 Accessibility 条目：按用户许可定向重置，再通过系统 UI 添加固定路径下的 264 副本，随后重启到同证书的 265；265 主 PID 35020 当时实际显示 **AX=true、Event tap=true、“正在使用小岛提示”**。没有改动其他应用权限，未导出私钥；后续 265→266 更新未再次执行权限修改或授权。

[TCC 定向日志](build/validation/hud25d/tcc-targeted.log)分别记录 264 PID 33637 和 265 PID 35020 的 Accessibility `Allowed (System Set)`，相同证书 DR 匹配 `status: 0`。264 重新授权后的 UI AX=true 没有被捕捉，故 **264→265 的历史验收仍不完整**。这项历史限制不影响下面另行完成的 265→266 连续授权实测。

[265 更新前状态](build/validation/hud25d/pre-update-265.json)于 **08:12:40 UTC** 捕捉主 PID 35020 的 AX=true、Event tap=true；[266 更新后状态](build/validation/hud25d/post-update-266.json)于 **08:18:57 UTC** 捕捉固定路径下主 PID **40151** 的 AX=true、Event tap=true，CDHash 为 `6311762f7f96db2169be2c1988eb150e0afe42df`。两次之间未修改权限或重新授权，库存仍 5、idle。**同证书固定路径 265→266 更新保留 AX/tap 的实测通过。** [构建身份对照](build/validation/hud25d/signing-version-comparison.json)确认 264/265/266 主应用及 XPC 的 DR 一致、CDHash 不同，并保存实际更新前后状态。266 此次观察时没有新增媒体事件；真实硬件按键证据仍属于 265，不能据此称已在 266 重跑。

[266 原生语言记录](build/validation/hud25d/native-language-266.json)确认同页从中文“通用”切换至英文“General”时窗口标题与正文即时改变，随后“HUDs”标题与正文正确，再切回中文“通用”。侧栏与控件同步变化，最终已恢复简体中文。11 个导航标题接线均已静态核验；原生抽样覆盖通用和 HUD 页面，系统生成的菜单、显示器名称仍遵循 macOS。

266 重开小岛后，原生界面已看到薯队长抱薯、库存 **5**、idle 和中文界面，见[更新后页面观察](build/validation/hud25d/post-update-266.json)的 `nativeIslandAfterRelaunch`。[最终计时快照](build/validation/hud25d/native-final-timer.json)同时确认库存 5、idle、无待交付收获或专注提醒，休息/专注时长仍为 **1/25 分钟**。

详见 [LOCAL-SIGNING.md](LOCAL-SIGNING.md)。本机开发签名不作为对外分发签名。[Apple 本地签名说明](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

## 素材整合进度

用户已授权本机透明素材处理，现已导入 **11 个具有真实透明像素的 RGBA 图层**，14 张高清源图每轮处理前后哈希一致。黑色、米色、草地绿色背景上检查并修正了青边、光晕、手臂边缘及水壶把手孔；双臂、肩位、握点和喷口使用相同坐标变换。当前场景没有缺失素材，未使用旧人物矢量回退。

已检查 **57 张生产 SwiftUI 静态图**，覆盖双语、库存边界、休息/暂停/完成、专注、六口和 15 个时间点；最终交付落点修复后重新生成了[完整采样动画](build/validation/shu/previews/shu-60s-loop.gif)，并提供 **2,830,646 字节（约 2.83MB）**的[轻量预览](build/validation/shu/previews/shu-60s-preview.gif)。两者均为 1200 帧、60.0 秒、20fps；轻量版使用全片共享 256 色调色板和差分帧，没有抽帧。见[素材验证记录](artwork/shu25d/VALIDATION.md)、[源图与 alpha 审计](build/validation/shu/alpha/source-and-alpha-audit.json)、[动画元数据](build/validation/shu/previews/animation-validation.json)和[轻量编码记录](build/validation/shu/previews/lightweight-preview.json)。这些结果不替代原生帧率、窗口动画或真实一分钟奖励验收。

## 当前真实媒体键证据

[亮度记录](build/validation/hud25d/physical-brightness-265.json)来自用户按下 MacBook 内置键盘、主任务读取原生 HUD 诊断，未合成媒体键。07:57:10–18 UTC 的最近 20 条事件包含亮度增加/减少的 down/up，观察到的事件均为 consumed=true；最后一次亮度实际回读为 **0.4466，success，无错误**。开始前没有捕捉初始亮度，不能用这份日志重建每一步中间值或证明已恢复初值。

随后 07:58:23–43 UTC 的[真实音量/静音操作](build/validation/hud25d/physical-volume-265.json)也观察到 down/up consumed=true，最近控制结果为 **actual=0.6380、muted=false、success**。用户明确确认：**不按 Option 也能调整实际亮度与音量，提示都在刘海，系统右上角没有同时出现。** 因此闭合内嵌 HUD 基本硬件显示与系统提示抑制已通过；该结论不扩展为长按、全部 Option/Shift 分支、默认样式、展开、锁屏或全屏场景均已通过。

切换到默认样式后，主任务在原生诊断中记录到 **08:05:10–21 UTC** 的媒体键 down/up，最后音量实际回读 **0.3880、success**。这证明该次输入与硬件回读已发生；默认样式的具体显示和是否同时出现系统提示仍等待用户视觉答复，暂不标为默认 HUD 视觉通过。

音量检查结束后，已按原始设备 UID 恢复内置扬声器：实际回读 **0.70045346021652222、muted=false**，与基线精确相同（`matchesBaselineExactly=true`）。见[恢复记录](build/validation/hud25d/volume-restored.json)。此记录只证明音量/静音恢复，不推定未捕捉初始值的亮度也已恢复。

## 真实一分钟休息与暂停取消

[完整原生记录](build/validation/hud25d/native-rest-validation.json)汇总本轮实际应用操作、原生界面观察与持久化快照，并单独列出未验证的连续播放、专注六口和系统场景。

[开始前快照](build/validation/hud25d/native-rest-before.json)为 `idle`、库存 **4**。[运行快照](build/validation/hud25d/native-rest-running.json)记录 `sessionDuration=60`、`endDate=810374714.326622`（Foundation 参考时间，即 **08:05:14.326622 UTC**）；按 60 秒时长推算，本轮约在 **08:04:14.326622 UTC** 开始。原生界面分别观察到种植 `1:00`、烘烤 `0:16`，完成后显示库存 **5** 和“出炉 +1”。

[08:05:21 完成快照](build/validation/hud25d/native-rest-after.json)为 `completed`、`creditedRestCycles=1`、`potatoCount=5`、`pendingHarvestCount=1`。随后展开已消费收获展示，再次打开库存仍为 **5**，没有重复发放。

第二轮启动后立即暂停，[08:06:17 确认快照](build/validation/hud25d/native-rest-paused-confirmed.json)为 `paused`，`pausedRemaining=59.5540759563`，库存仍 **5**。等待约 30 秒后，原生 UI 仍显示暂停和 `1:00`；继续后显示 `0:59`，再提前结束，UI 回到 idle，库存仍 **5**。据此确认暂停计时冻结、继续恢复、未完成一分钟的取消不增加库存。

[首次暂停后磁盘读取](build/validation/hud25d/native-rest-paused-first.json)仍显示旧 `running`，原因是 cfprefsd 延后落盘；随后已由持久化 `paused` 和原生 UI 两者确认。不能把那一次过早磁盘读取当成暂停失败。

**本轮通过的是实际 60 秒计时、关键阶段、一次结算及暂停/继续/取消。** 一分钟期间窗口曾收起，没有连续观看整段原生动画，因此不能宣称“连续原生 60 秒动画流畅”通过。暂停姿态/动画冻结的视觉检查、专注六口、减少动态效果、锁屏/全屏等仍待逐项验收。

## 原生窗口诊断与隐藏恢复

[265 窗口诊断汇总](build/validation/hud25d/interaction-summary-265.json)来自已安装应用的 debug 菜单：程序驱动 **20 次展开/收起＋10 次中途反向**，暂停自动指针触发，没有合成鼠标输入。**35.8704 秒内采集 2082 个样本**，只有一个 carrier frame：原点 `(416, 622)`、尺寸 **680×360**；物理触发矩形始终为原点 `(663, 950)`、尺寸 **185×32**。所有样本 `isKeyWindow=false`、`isMainWindow=false`，鼠标路由诊断不匹配数为 **0**。

这些证据支持窗口位置、承载尺寸、物理区域不扩宽及非激活状态稳定。它们不证明真实 150ms 悬停、两侧拒绝、编辑器持续输入、透明区域实际点击或主观动画流畅度；约 16ms 的几何采样也不是屏幕渲染帧率测量。

[265 原生隐藏记录](build/validation/hud25d/native-hide-265.json)来自菜单隐藏/显示和 HUD 设置实际状态：隐藏时 **AX=true、Event tap=false**，文本为“**小岛隐藏期间使用系统提示**”；显示后 **AX=true、Event tap=true**，恢复“正在使用小岛提示”。启用偏好保持不变。隐藏期间尚未实际按媒体键，也未启动摄像头验证停止，因此系统 HUD 回退显示与镜子会话停止仍待实用验证。

## 原生验收清单（逐项记录，不以逻辑测试替代）

| 操作 | 要记录的证据 | 状态 |
|---|---|---|
| 参考 boring.notch 内置键盘对照 | 亮度/静音/音量短按、长按、松开；数值、岛上提示及系统提示 | 待实际运行参考应用并按键 |
| Build 266 资源验签与安装 | 主应用及 XPC 的证书/ID/DR/资源完整性，固定路径，旧版备份 | 通过；265 已备份，266 固定副本运行于主 PID 40151 |
| 最终固定副本 AX | 路径、签名、AX true、tap true；真实事件记录 | 266 当前 AX/tap 通过；真实 down/up consumed=true 来自 265，本次 266 尚未观察新媒体事件 |
| 闭合内嵌 HUD 基本硬件操作 | 普通亮度/音量按键、实际回读、刘海提示与系统提示抑制 | 日志与用户确认通过；长按和其他组合不在此结论内 |
| 默认样式与展开 HUD | 展开/收起、休息/专注/暂停、最后一次键后约 2 秒恢复、正文保留 | 默认样式已有 08:05:10–21 UTC 按键与 0.3880 回读成功；视觉等待用户，其他组合继续验收 |
| 隐藏与关闭替换 | 隐藏停止 tap、显示恢复且启用偏好不变；系统回退与摄像头停止 | 原生菜单隐藏/显示诊断通过；隐藏期间真实按键、系统 HUD 回退及摄像头停止待验，关闭替换待验 |
| 权限撤销/恢复/唤醒 | 撤销后停止接管、恢复后正确重建监听 | 待用户系统操作 |
| 全屏 | 按键 HUD 可见、计时提醒及物理刘海悬停可用 | 待原生操作 |
| 真实一分钟与结算 | 60 秒结束、关键阶段、只发放一次、重复展开 | 通过；库存 4→5，credited=1，原生见种植/烘烤/完成，重复展开仍 5 |
| 暂停/继续/提前结束 | 剩余时间冻结、恢复倒计时、取消不重复奖励 | 通过；暂停约 59.554 秒，等待约 30 秒仍 1:00，继续后 0:59，提前结束回 idle/库存 5 |
| 连续动画与其他视觉场景 | 连续观看整轮、暂停动画冻结、专注六口、库存边界、中英、减少动态效果 | 素材/静态图/采样 GIF 已完成；原生整轮流畅度与这些视觉场景待验 |
| 20 次展开/收起＋10 次反向 | 固定窗口、物理区域、非激活状态；真实悬停/输入/视觉另验 | 程序驱动诊断通过：2082 样本、680×360 carrier 和 185×32 trigger 不变、key/main=false、鼠标路由 mismatch=0；真实悬停、输入、帧率待验 |
| 同证书两个不同构建 | DR 兼容、更新前后实际 AX/tap | 265→266 通过：前后实际 AX/tap 均 true，无权限修改或重新授权；三版 DR 一致且 CDHash 不同，264→265 历史前态缺口保留 |
| 设置语言即时切换 | 同页标题、正文、侧栏和控件；恢复原语言 | 266 原生通用→General→HUDs→通用通过，已恢复中文；11 个导航标题静态核验通过 |
| 30 分钟办公体验 | 误触、遮挡、主动再次使用意愿 | 待人工体验 |

上述服务测试与离线渲染未改变真实音量、亮度或用户计时/库存，也未替换参考 boring.notch。原生硬件验收由主任务继续记录，操作前后应保留实际读值与设置恢复结果。

## 当前继续入口

[原生会话记录](build/validation/hud25d/native-session.json)：**当前固定路径运行版为 266，主 PID 40151，AX/tap 均为 true**；265→266 无重新授权的保留检查和 266 原生语言标题切换已通过。265 完成了用户确认的基本闭合内嵌硬件 HUD、真实 60 秒计时/结算与暂停继续取消、菜单程序驱动窗口诊断及隐藏/显示 tap 门控。待验保留默认 HUD 视觉、隐藏期间真实按键和摄像头、真实悬停与输入、锁屏/唤醒、全屏及原生动画视觉场景。程序驱动窗口循环不计为物理鼠标悬停验收，未把 265 的真实媒体事件计为 266 新按键结果。

最后放薯动作已修复为与下一库存格一致的位置及尺寸，满 12 颗时与 `+N` 图标交接。见[9 帧交接对照](build/validation/shu/previews/handoff-contactsheet.png)与[独立源码清单](build/validation/shu/previews/handoff-manifest.json)，不提前修改库存。

## 卡住的旧签名弹窗（2026-09-06）

用户报告多个 `codesign` 私钥访问窗口点击允许和拒绝都无响应。只读检查确认没有 codesign/xcodebuild 进程，旧 SecurityAgent PID 19302 仍驻留。正常 TERM 无效，核对其路径与当前用户 UID 后强制结束该旧 PID，取消残留请求；随后系统按需启动了新的弹窗进程，未对新进程进行操作。没有修改钥匙串、证书、密码或安全数据库，没有启动新构建。用户已明确确认这些弹窗全部消失；不能把此前窗口无响应归因于密码错误。证据：`build/validation/hud25d/stale-dialog-cleanup.json`。

后续该应用的旧 Accessibility 条目已定向刷新；固定副本现为 266，265→266 未重新授权即保留 AX/tap，实际授权与 265 真实媒体键结果见上文。此前等待安全验证和“尚未开始按键调节”的记录已成为历史状态。
