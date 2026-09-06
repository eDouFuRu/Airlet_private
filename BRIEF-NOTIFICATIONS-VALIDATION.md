# 270 版：刘海歌词与 hi 转显实验验收

## 交付状态

固定应用：`~/Applications/工位充电岛.app`，工程：`boringNotch.xcodeproj`，scheme：`NotchIslandNext`。沿用原 Bundle ID、专用本地证书及红薯钟 v2 存储；不修改薯队长素材、计时库存规则或参考 boring.notch。

歌词与共享提示行已接入并在真实网易云播放中验证。hi 适配器、隐私设置、消息合并和点击回退已实现，但**尚无真实 hi 新横幅验证**：用户确认自己发给自己不会产生电脑端横幅。本轮不得称为 hi 真实消息接入成功或 macOS 通知替换完成。原横幅隐藏能力保持未验证、开关禁用；没有执行隐藏、清除或删除任何系统通知。

269 回退副本：`/Users/dongfengrui/Applications/.NotchIsland-backups/工位充电岛-20260906-222322-AA0E5CD8-0A6C-461F-B8B4-2357BDF67A54.app`。本轮后续安装还保留了中间 270 副本；最终安装记录以 `build/validation/brief/install-270-compact.log` 为准。

## 最终交互

- 共享 28 点紧凑提示行（按最新意见从 40 点缩减，文字中心上提 6 点），图标与文字垂直居中；顺序为系统 HUD、hi、换歌、歌词。高优先级消失后只恢复当前有效歌词，不补播过期提示。
- 按用户本轮追加意见：**歌词保持原来关闭态刘海的宽度，只增加下方一行**；长句开头停留 2 秒后以 22 点/秒滚到尾部并停住，下句重置。开启减少动态效果时静态截断。
- 无匹配歌词、加载中、网络错误、前奏/间奏的空 cue 都不展开歌词行。当前有非空歌词且正在播放时显示；暂停保留内部状态并收起，恢复重新对齐播放进度。
- 简体中文界面把歌词显示转成简体，原文和时间轴不变；元数据匹配也统一繁简及宽字符。英文界面保留歌词源原文。
- 媒体设置：关闭／播放器内／刘海下方，以及“重试当前歌曲歌词”。旧 `enableLyrics=true` 首次迁移为播放器内；本机测试后按本轮目标选择刘海下方。
- hi 默认关闭、隐私默认只提示新消息。本机试验开关已恢复关闭；开启后只观察真实系统横幅。原动作仍有效时尝试打开对应通知，否则打开 hi；不猜造会话深链。
- 只有 hi 提示行接受点击，歌词行保持穿透；原物理刘海 150ms/100ms 触发矩形不扩宽。

## 验证矩阵

| 项目 | 证据与结论 |
| --- | --- |
| 核心回归 | `core-tests-final.log`：181 项通过，含原 111 项、新提示/歌词/hi/卡片复用等测试 |
| 原服务回归 | `services-regression.log`：87 项通过，覆盖既有 HUD、硬件控制、日历、电池和分享逻辑 |
| 歌词生产服务 | `brief-lyrics/lyrics-service-tests.log`：37 项通过，使用实际 LyricsStore，覆盖取消、旧结果、缓存、暂停、语言、有限重试、隐藏取消、空白 cue 与无词收起 |
| 最终窄行布局 | `layout-compact/`：32 组实际 macOS NSHostingView 渲染、64 张 1x/2x 原图；257 点关闭内容宽与 578 点展开内容宽，28 点行高与文字中心检查通过 |
| 对齐前后对照 | `layout-compact/comparison-zh-w257.png`：旧文字中心约 8 点、新行约 14 点；旧图是明确标注的旧 GeometryReader 布局复现，不是历史截图 |
| 网易云真实播放 | 270 初次安装时通过原生 Control > Play，刘海歌词实际随播放换句；网易云自身页面与小岛显示处于同一句歌词。不是逐字/逐帧音频同步精度测量 |
| 最终紧凑行原生观察 | 最终签名安装后，用真实网易云继续播放：实际歌词行贴在媒体头下方，随后空白间奏收回，再有歌词时恢复且显示简体，外壳宽度保持不变；行组件 28 点，系统安全区域仍留空 |
| 暂停与旧状态迁移 | 原生暂停后歌词行收起；旧启用开关迁移为播放器内；选择刘海下方后下一次安装保留该选择 |
| 实际网络 | 《模特》精确请求 HTTP 200、同步歌词存在；另有搜索 TLS EOF。用户报告《街道》后，实际查询发现多个同步歌词版本，包含林俊杰/林俊傑、JJ陆/JJ陸等写法；保留版本核对，不取第一项 |
| 网络恢复 | 临时失败先在 HTTP 层有限重试，仍失败时可见且播放中最多再重试 2 次；暂停、隐藏、关闭取消重试；手动重试 5 秒防连点，服务端 Retry-After 保留 |
| hi 权限/观察启动 | 实际主进程 AX=true、Observer=true，重装没有要求重新授权；诊断不含发送者、正文或通知标题 |
| hi 实际消息、聚合、会话跳转 | **待验**，没有符合条件的真实 hi 横幅；演示/纯逻辑结果不算来源接通 |
| 原 hi 横幅隐藏与通知历史保留 | **隐藏待验且功能禁用**。代码没有执行 AX 位置写入，也没有 Close/Clear；不读取通知数据库或修改 hi 应用 |
| 全屏、锁屏、权限撤销、多通知堆栈 | **待原生验收**，逻辑 guard/失败路径已测试但不能代替实际系统体验 |
| 新提示真实悬停/点击穿透与 20+10 动画 | **待原生交互验收**；本轮纯几何检查不能替代鼠标操作 |
| 减少动态效果 | 两个渲染分支预览通过；未更改或验证用户真实系统开关 |

最终原生补充观察见 `build/validation/brief/native-270.json`。最后的签名、安装和来源状态按该记录及构建日志核对，不把早期中间构建的状态冒充最终构建。

## 真实歌词与限制

采用 [LRCLIB](https://lrclib.net/docs) 同步歌词，使用实际播放器元数据和进度。它与网易云自身的词库可能不同，不能保证每个版本都有同步歌词。精确匹配后才使用；降级搜索仍核对标题、歌手、专辑和时长。缺专辑时收紧时长误差并拒绝有歧义或截断的候选；繁简和显式中英并列艺人署名可规范化，现场版、翻唱和带来源后缀的不同记录仍拒绝。

`netease-track-network.json` 与 `jiedao-network.json` 记录真实 API 元数据和网络错误，不存 hi 消息。网络失败与源里无匹配在设置诊断中区分；两者在刘海上都收起。歌词请求和缓存仅在本机进程内，库存结算不依赖歌词服务。

网易云原设置已从其自己的偏好设置读取并关闭：桌面歌词原为开启、菜单栏显示、宽度 183、带播放控制。恢复方式：网易云音乐 → 设置 → 桌面歌词 → 开启桌面歌词；原位置选项未改，重新开启即可恢复。没有修改其安装文件。

## 可重复检查

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/notch-brief-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/notch-brief-module-cache \
swift test --disable-sandbox --scratch-path /private/tmp/notch-brief-final-tests \
  --cache-path /private/tmp/notch-brief-swift-cache
bash scripts/test-services.sh
bash Tests/ServiceHarnesses/run-lyrics.sh
python3 Tests/BriefPreview/render.py --output build/validation/brief/layout-compact
```

主应用串行构建与安装使用 `scripts/build.sh Debug`、`scripts/install-local.sh Debug`，沿用 `LOCAL-SIGNING.md` 的现有证书。不并行签名，不导出私钥，不重置 TCC。图像预览使用独立、从不显示的 NSHostingView 窗口，不能当成真实通知或鼠标验收。
