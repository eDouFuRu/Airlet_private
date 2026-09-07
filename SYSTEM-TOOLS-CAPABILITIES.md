# 快捷工具能力代码核对矩阵

核对时间：2026-09-07T05:16:05+08:00

目录与行为数量按 280 当前源码重新统计；本轮增加声音输出选择、原彩实验控制和显示模式选择直接接口。蓝牙、夜览和输入法沿用 279，区域录屏沿用 277，自定义录制与时间机器沿用 278。既有原生结果见 [277 验证记录](TOOLS-NOTIFICATIONS-277-VALIDATION.md)、[278 验证记录](TOOLS-NOTIFICATIONS-278-VALIDATION.md)和 [279 原生记录](TOOLS-NOTIFICATIONS-279-VALIDATION.md)。279 固定副本只读结果：夜览显示关闭；输入法列出 ABC 和当前简体拼音；蓝牙超时后显示明确失败且自有 helper 已回收。上述 279 三项真实切换仍未测试。

280 最终固定应用的原生验收结果：原彩完成 **ON → OFF → ON**，各次读回确认，最终恢复开启；音频输出菜单只有 1 个内置扬声器输出项，当前项已勾选，未切换输出；显示模式菜单有 61 项完整标签、61 个唯一项，当前勾选为 `1512 × 982 · HiDPI · 120 Hz`，未改变分辨率；蓝牙主进程公开授权状态为 `notDetermined`，电源读取仍超时。蓝牙已提供仅用户明确点击才触发的申请入口，尚未点击申请、未获得授权，也未进行电源切换。

最终 **431 项核心测试通过**。独立只读探针和固定应用的菜单验收均不能替代尚未执行的音频输出 / 显示模式切换；蓝牙真实授权与开关仍待验。原彩只记录本机开关与读回恢复成功，不据此宣称所有硬件、全部控制中心功能已验证。

范围：本次文档编辑只读取目录并运行不含系统操作的统计程序，汇入主任务已完成的固定应用验收结果；文档编辑过程未重复操作 UI、系统设置、网络、声音、亮度、主题、锁屏或权限，未读取私有应用数据。系统包元数据结论沿用此前核对。下表逐项区分实现、已获得证据和待验事项。

结论：73 项中 **35 项仍只打开系统设置，13 项打开原生应用，25 项为本应用路由、直接操作接口、滑块或截图录制流程**。后两类不能合称为已验证的系统开关：其中包含页面入口、外部应用启动，以及尚待真实操作验证的实验控制。尚未实现完整控制中心全部直接控制。工具 ID 与原排序保持；原 14 项之外暂留蓝牙卡片供用户授权验证，其余临时测试卡片已移除。完整原生记录见 [280 验证记录](TOOLS-NOTIFICATIONS-280-VALIDATION.md)。

所有设置入口在卡片副标题、帮助与辅助功能提示中使用“打开系统设置”；库中的开关控制是否显示工具，不是系统开关。此前核对的 13 个原生应用 fallback 路径均存在且 Bundle ID 匹配。设置基础 ID 的安装元数据沿用此前结果；辅助功能 query 锚点未在此做原生跳转验证。蓝牙、夜览和原彩的卡片明确标记“实验”，不兼容时转到对应设置页，暂时错误只刷新而不盲目切换；输入法、声音输出和显示模式菜单保留刷新及对应系统设置入口。

## 280 目录行为统计

以下数量由当前 `SystemToolCatalog.all` 实际枚举得到，按 `SystemToolBehavior` 分类；不是原生验收通过数量。

| 行为 | 数量 | 含义 |
|---|---:|---|
| `systemSettings` | 35 | 系统设置入口 |
| `nativeApp` | 13 | 原生应用入口 |
| `capture` | 7 | 截图与录制流程 |
| `utility` | 3 | 本应用秒表、计时器、闹钟 |
| `slider` | 3 | 音量、屏幕亮度、键盘亮度 |
| `wifiPower` | 1 | Wi-Fi 电源事务 |
| `bluetoothPower` | 1 | 蓝牙电源实验接口 |
| `nightShiftToggle` | 1 | 夜览实验接口 |
| `inputSourcePicker` | 1 | 输入法选择接口 |
| `audioOutputPicker` | 1 | 默认声音输出设备选择接口 |
| `trueToneToggle` | 1 | 原彩实验接口 |
| `displayModePicker` | 1 | 显示分辨率 / 刷新率模式选择接口 |
| `appearanceToggle` | 1 | 深色模式事务 |
| `timeMachineBackup` | 1 | 时间机器备份事务 |
| `systemShortcut` | 1 | 锁屏快捷键投递 |
| `mute` | 1 | 静音操作 |
| `mediaHome` | 1 | 本应用播放器主页路由 |
| **合计** | **73** | |

## 截图 / 录制流程（7 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| captureScreen | 全屏截屏 | 截取 | 调用 screencapture 截取编号 1 显示器，保存到暂存器 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| captureRegion | 区域截屏 | 截取 | 调用系统区域选择截屏，保存到暂存器 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| captureWindow | 窗口截屏 | 截取 | 调用系统窗口选择截屏，保存到暂存器 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| captureCustom | 自定义截屏 | 截取 | 打开系统截屏工具条，用户选择后捕获产物 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| recordScreen | 全屏录制 | 截取 | 调用 screencapture 全屏录制，明确停止后处理产物 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| recordRegion | 区域录制 | 截取 | 本应用原生单屏框选后，以固定 -v -R 录制；从小岛安全停止 | 需要屏幕录制权限；交互选择 / 取消与产物确认需真实操作；本次不运行 |
| recordCustom | 自定义录制 | 截取 | ScreenCaptureKit 原生选择屏幕/窗口，再由 SCRecordingOutput 完成视频文件并入暂存 | macOS 15+；仅画面，无系统音频或麦克风；已触发选择，真实有效视频待验；应用取消不等于系统选择器已关闭 |

## 应用内时钟工具（3 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| stopwatch | 秒表 | 打开工具 | 打开自有秒表页；开始、暂停、计圈与复位 | 窗口关闭后仍计时；通知受 macOS 权限、专注与睡眠影响；本次不运行 |
| timer | 计时器 | 打开工具 | 打开自有计时器页；自定义时分秒、暂停与取消 | 窗口关闭后仍计时；通知受 macOS 权限、专注与睡眠影响；本次不运行 |
| alarm | 闹钟 | 打开工具 | 打开自有闹钟页；设置未来整分钟并调度通知 | 窗口关闭后仍计时；通知受 macOS 权限、专注与睡眠影响；本次不运行 |

## 岛内滑块（3 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| volume | 音量 | 直接调节 | 读取真实音量并调用已有 VolumeManager.setAbsolute | 读写失败或硬件不可用需显示失败；本次不调音量 / 亮度 |
| displayBrightness | 屏幕亮度 | 直接调节 | 读取真实屏幕亮度并调用现有 HardwareBrightnessManager | 读写失败或硬件不可用需显示失败；本次不调音量 / 亮度 |
| keyboardBrightness | 键盘亮度 | 直接调节 | 读取真实键盘背光并调用现有 HardwareBrightnessManager | 读写失败或硬件不可用需显示失败；本次不调音量 / 亮度 |

## 直接静音操作（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| mute | 静音 | 切换静音 | VolumeManager.toggleMuteAction；失败回传 lastError | 实际静音及读回需原生验收；本次不执行 |

## 直接 Wi-Fi 电源操作（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| wifi | Wi-Fi | 切换 Wi-Fi | CoreWLAN powerOn 读取 → 校验旧状态 → setPower → 读回 | 不读取网络名称；setPower 可能被系统拒绝；本次不改变网络 |

## 蓝牙电源实验控制（1 项，279 新增，280 补授权入口）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| bluetooth | 蓝牙 | 蓝牙控制 · 实验 | 同应用独立 CLI helper 动态加载 IOBluetooth SPI，先读取并校验预期电源值，明确点击后调用 setter 一次，再以实际读回确认；主进程串行监督，8 秒超时后终止自有 helper | 不是公开系统开关 API。不读取设备名称、地址或配对记录，不写私有偏好，不提权。独立探针和固定应用中的电源读取均超时。固定 280 主进程公开授权读值为 notDetermined；授权与 SPI 电源结果分别呈现，不从任一结果推断另一结果必成或蓝牙关闭。仅用户点击申请入口才创建并保留一个 CBCentralManager，禁用电源提醒，不扫描 / 连接设备；授权变化后只刷新状态，不切电源。尚未点击实际申请、未授权，真实开启 / 关闭均待验；不支持时转蓝牙设置，读取失败 / 超时保留未知和重试。 |

25 项核心 / 协议测试和 33 项假子进程 / 假授权服务检查已通过，覆盖旧状态校验、单次写入、读回确认、错误协议、超时回收、取消，以及显式授权入口不重复创建、初始化 / 刷新不请求权限、授权后只读刷新。测试没有请求真实权限或切换真实蓝牙，不能替代硬件验收。

## 夜览实验控制（1 项，279 新增）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| nightShift | 夜览 | 夜览控制 · 实验 | 动态校验私有 CoreBrightness 的 CBBlueLightClient 方法签名与状态结构；只读取 enabled / available，明确点击后 setEnabled 并有界重复读回 | 不修改色温和计划。不支持的 ABI / 硬件转到显示器设置；读写失败不把未知状态显示为关闭，也不把请求目标显示为成功。真实开启 / 关闭及屏幕效果尚待验；代码 / 逻辑验证不能证明本机实控已生效。 |

## 输入法直接选择（1 项，279 新增）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| inputSources | 输入法 | 选择输入法 | 公开 HIToolbox TIS API 枚举已启用且可选择的键盘输入源，显示当前输入法与子模式；明确选择后 TISSelectInputSource 一次，再检查实际当前 ID | 不安装 / 启用新输入法，不读键盘输入内容。菜单项失效、系统拒绝、取消或读回不一致显示失败，保留实际读回；支持刷新和打开键盘设置。真实输入法切换、输入内容及焦点保留尚待验，不以菜单已列出或 OSStatus 成功替代。 |

## 声音输出直接选择（1 项，280 新增）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| sound | 声音与音频输出 | 选择音频输出 | 公开 CoreAudio API 枚举已连接且可作为默认输出的设备；以稳定 DeviceUID 标识菜单项，明确选择后重新解析设备 ID，写入默认音频输出并读取实际结果；监听设备列表、当前输出及相关设备属性变化 | 不改变音量、静音或独立的系统提示音输出，不读取麦克风内容。串行后台执行并限制响应等待；取消、超时、设备断开、只读或读回不一致不显示成功。独立只读探针识别 1 个可选输出、当前设备匹配；最终固定 280 原生菜单确认只有 1 个内置扬声器输出项且当前项勾选。没有进行真实输出切换；切换 / 断开恢复仍待验。 |

7 项核心测试、33 条注入假设备的服务断言及独立类型检查通过；假设备检查没有写入真实输出。菜单提供当前设备标记、刷新和声音设置入口，忙碌或系统不可写时禁止选择。

## 原彩实验控制（1 项，280 新增）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| trueTone | 原彩显示 | 原彩控制 · 实验 | 动态校验私有 CoreBrightness `CBTrueToneClient` 的方法 ABI；读取 supported / available 及两次 enabled，确认有效状态后允许明确点击；校验原状态、调用 setEnabled 一次并有界重复读回 | 不是公开系统开关 API。不修改强度、模式或显示器覆盖。无法确认 supported / available 时保留未知，不冒充“关闭”；ABI 不兼容提供显示器设置入口，暂时失败只重试读取。最终固定 280 原生应用已完成 ON → OFF → ON，每次读取确认，最终恢复原开启状态。本机开关事务与恢复已验；不同硬件兼容性及具体视觉效果不由该读回结果代替。 |

## 显示模式直接选择（1 项，280 新增）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| display | 显示器 | 选择显示模式 | 公开 CoreGraphics / ColorSync API 枚举活动显示器和桌面可用模式，显示分辨率、HiDPI 与刷新率；以显示器 UUID 和完整模式元数据校验菜单快照，明确选择后调用 CGDisplaySetDisplayMode 一次，再检查实际当前模式 | 过滤无效 / 重复 / 冲突模式；读不到固定刷新率时显示系统默认。仅作应用生命周期内的模式调整，退出应用由 macOS 恢复，未写入永久配置。镜像屏菜单说明可能影响同组屏幕；设备断开、模式变化、取消或未确认结果显示失败。独立只读探针识别 1 屏、61 个过滤后模式且当前 HiDPI 模式匹配；最终固定 280 原生菜单确认 61 项完整标签、61 个唯一项，当前勾选为 1512 × 982 · HiDPI · 120 Hz。没有改变分辨率；真实切换 / 退出恢复及镜像屏行为仍待验。 |

显示模式菜单提供手动刷新及显示器设置入口。21 项核心测试、16 项假服务检查及独立类型检查通过。代码读取显示元数据，不截图、不枚举窗口内容、不捕获屏幕；只读结果和菜单勾选不证明切换已生效。

## 直接深色模式操作（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| darkMode | 深色模式 | 切换深色模式 | 点击后固定 System Events 脚本读 → 写 → 读回；初始不探测权限 | 需自动化授权；UI 展示上次确认结果，非持续监视系统状态；本次不执行 |

## 时间机器备份控制（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| timeMachine | 时间机器 | 备份控制 | 固定 tmutil status/destinationinfo 读状态；明确点击后 startbackup/stopbackup 并读回确认 | 未配置时显示配置入口；不提权、不改备份配置、不自动开始；本机生产只读返回未运行/未配置/无错误，最终原生卡片显示“设置备份磁盘”。status -X 无本机手册保证，格式异常时停用操作。 |

## 系统快捷键动作（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| lockScreen | 锁定屏幕 | 执行操作 | 已授权时发送成对 Control-Command-Q 系统快捷键 | 需要当前进程辅助功能权限；代码只确认按键提交，不宣称已锁屏；本次不执行 |

## 岛内页面入口（1 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| media | 正在播放 | 打开播放器 | 切换小岛到媒体 / 日历主页 | 是小岛内部主页路由，不启动音乐播放 |

## 原生应用入口（13 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| clock | 时钟 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Clock.app`；`com.apple.clock` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| calculator | 计算器 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Calculator.app`；`com.apple.calculator` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| notes | 备忘录 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Notes.app`；`com.apple.Notes` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| voiceMemos | 语音备忘录 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/VoiceMemos.app`；`com.apple.VoiceMemos` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| shortcuts | 快捷指令 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Shortcuts.app`；`com.apple.shortcuts` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| siri | Siri | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Siri.app`；`com.apple.siri.launcher` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| spotlight | 聚焦搜索 | 打开应用 | NSWorkspace.openApplication → `/System/Library/CoreServices/Spotlight.app`；`com.apple.Spotlight` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| weather | 天气 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Weather.app`；`com.apple.weather` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| home | 家庭 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Home.app`；`com.apple.Home` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| accessibility | 辅助功能快捷键 | 打开应用 | NSWorkspace.openApplication → `/System/Library/CoreServices/UniversalAccessControl.app`；`com.apple.UniversalAccessControl` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| screenSaver | 启动屏幕保护程序 | 打开应用 | NSWorkspace.openApplication → `/System/Library/CoreServices/ScreenSaverEngine.app`；`com.apple.ScreenSaver.Engine` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| magnifier | 放大镜 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Utilities/Magnifier.app`；`com.apple.Magnifier` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |
| reminders | 提醒事项 | 打开应用 | NSWorkspace.openApplication → `/System/Applications/Reminders.app`；`com.apple.reminders` | 路径与 Bundle ID 已核对；仅证明可解析应用，不证明目标面板已实际出现 |

## 仅打开系统设置（35 项）

| 工具 ID | 中文名 | 能力标签 | 实际实现 / 目标 | 边界 / 证据 |
|---|---|---|---|---|
| airDrop | 隔空投送 | 打开系统设置 | `x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| focus | 专注模式 | 打开系统设置 | `x-apple.systempreferences:com.apple.Focus-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| screenMirroring | 屏幕镜像 | 打开系统设置 | `x-apple.systempreferences:com.apple.Displays-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| stageManager | 台前调度 | 打开系统设置 | `x-apple.systempreferences:com.apple.Desktop-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| battery | 电池 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.battery` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| energyMode | 能耗模式 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.battery` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| keyboard | 键盘 | 打开系统设置 | `x-apple.systempreferences:com.apple.Keyboard-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| vpn | VPN | 打开系统设置 | `x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| network | 网络 | 打开系统设置 | `x-apple.systempreferences:com.apple.Network-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| fastUserSwitching | 快速用户切换 | 打开系统设置 | `x-apple.systempreferences:com.apple.Users-Groups-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| controlCenter | 控制中心设置 | 打开系统设置 | `x-apple.systempreferences:com.apple.ControlCenter-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| recognizeMusic | 音乐识别控件 | 打开系统设置 | `x-apple.systempreferences:com.apple.ControlCenter-Settings.extension` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| hearing | 助听设备 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Hearing` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| backgroundSounds | 背景音 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Audio` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| liveCaptions | 实时字幕 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?LiveCaptions` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| liveSpeech | 实时语音 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?LiveSpeech` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| voiceOver | 旁白 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_VoiceOver` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| zoom | 缩放 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Zoom` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| hoverText | 悬停文本 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?HoverText` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| hoverTyping | 悬停键入 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?HoverText` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| colorFilters | 色彩滤镜 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| invertColors | 反转颜色 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| increaseContrast | 增加对比度 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| reduceMotion | 减弱动态效果 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Motion` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| reduceTransparency | 降低透明度 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| accessibilityReader | 辅助功能阅读器 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?AccessibilityReader` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| voiceControl | 语音控制 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?VoiceControl` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| switchControl | 切换控制 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?SwitchControl` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| fullKeyboardAccess | 全键盘控制 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| accessibilityKeyboard | 辅助功能键盘 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| stickyKeys | 粘滞键 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| slowKeys | 慢速键 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| mouseKeys | 鼠标键 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Mouse` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| headPointer | 头部指针 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Mouse` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |
| vehicleMotionCues | 车辆运动提示 | 打开系统设置 | `x-apple.systempreferences:com.apple.preference.universalaccess?Motion` | 不是开关；部分工具共用父设置页；深链投递不等于子页原生跳转已验证 |

## 可追溯实现

- `boringNotch/Interaction/Core/SystemToolCatalog.swift`：73 项定义、稳定 ID 与能力标签。
- `boringNotch/Interaction/SystemToolsPage.swift`：能力副标题、帮助、辅助功能提示；截图、时钟、主页分流。
- `boringNotch/Interaction/SystemToolActions.swift`：原生应用、设置 URL、硬件、静音与锁屏动作。
- `boringNotch/Interaction/SystemWifiControl.swift`：CoreWLAN 电源事务。
- `boringNotch/Interaction/SystemAppearanceControl.swift`：固定脚本后台串行主题事务。
- `boringNotch/Interaction/SystemBluetoothControl.swift`、`Core/BluetoothPowerTransaction.swift`：蓝牙实验 helper、固定 CLI 协议、真实读回事务与超时回收，以及主进程公开授权诊断和仅明确点击创建的授权请求器。
- `Tests/ServiceHarnesses/run-bluetooth-control.sh`：只启动假 helper / 假授权请求器的可复跑服务检查，不访问蓝牙硬件、不触发真实权限申请。
- `boringNotch/Interaction/SystemNightShiftControl.swift`、`Core/NightShiftTransaction.swift`：夜览私有接口 ABI 与状态校验、明确点击后的事务。
- `boringNotch/Interaction/SystemInputSourceControl.swift`、`Core/InputSourceSelection.swift`：公开 TIS 输入源选择与读回确认。
- `boringNotch/Interaction/SystemAudioOutputControl.swift`、`Core/AudioOutputSelection.swift`：公开 CoreAudio 默认输出选择、设备变化观察、超时 / 取消及实际读回确认。
- `boringNotch/Interaction/SystemTrueToneControl.swift`、`Core/TrueToneTransaction.swift`：原彩私有接口 ABI 校验、可用性检查和读回事务。
- `boringNotch/Interaction/SystemDisplayModeControl.swift`、`Core/DisplayModeSelection.swift`：公开活动显示器和模式选择，稳定标识 / 完整菜单快照校验及读回确认。
- `boringNotch/Interaction/SystemAdditionalTools.swift`：实验状态卡片、失败 / 设置回退及输入法、声音输出、显示模式菜单。
- `boringNotch/Interaction/Core/CaptureFilePolicy.swift`、`CaptureTools.swift`：截图 / 录制固定参数与产物处理；父任务可能继续修复此部分。
- `boringNotch/Interaction/UtilityClockWindow.swift`：自有时钟页及通知调度。

280 机器可读目录快照：`/tmp/notch-system-tool-catalog-280-audit.json`。
