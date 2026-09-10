# 工位充电岛 · NotchIslandNext

基于 **boring.notch v2.7.3** 的原生 macOS 刘海应用，对外发布版本 **v1.0.0（build 303）**。使用 SwiftUI + AppKit，保留物理刘海悬停、弹簧伸缩、反向圆角及上游常用工具。

<p align="center"><img src="boringNotch/Assets.xcassets/ShuIcon-captain.imageset/icon.png" width="160" alt="薯队长"></p>

## 当前功能

- **默认主页**：展开显示媒体与日历，左侧红薯图标可进入红薯钟。
- **薯队长小岛**：软萌 2.5D 角色、种薯与烤薯动作、双手与飘动的云。
- **红薯钟**：自定义休息和专注时间，暂停、恢复、离线结算与本地库存。
- **系统 HUD**：MacBook 内置亮度、音量、静音键的刘海提示。
- **音乐与歌词**：播放器控制、简体同步歌词、长句滚动、28 点紧凑提示行；无歌词或暂停时收起，不扩大刘海宽度。
- **设置**：中英文切换、图标选择，以及媒体、日历、文件暂存等工具。
- **系统工具**：新增第四个标签，可选工具及摆放顺序；提供截屏、录屏、秒表、计时器、闹钟、音量／亮度滑块和系统应用入口。标注“打开设置”的功能是设置快捷入口，不等于直接切换系统状态。
- **截图暂存**：应用截屏和录屏进入文件暂存；系统快捷键保存的新截图自动复制，保留原图。hi／微信截图可通过“暂存剪贴板图片”手动添加。
- **应用通知**：任意 App 的桌面横幅都可转显到小岛，App 发出第一条通知后自动出现在设置页，可逐个开关并单独控制是否显示内容预览。已在真实微信、hi、ValOS 横幅上验证转显与点击打开。原系统横幅隐藏、横幅跟随小岛所在屏幕尚未开放。

## 打开与构建

运行要求：macOS 15.0+。当前在 macOS 26.6.2 / Apple Silicon / Xcode 26 上验证。

1. 打开 `boringNotch.xcodeproj`。
2. 选择 `NotchIslandNext` scheme。
3. 当前开发机器使用专用本地证书，按 [LOCAL-SIGNING.md](LOCAL-SIGNING.md) 构建和安装。证书私钥不在仓库中。其他机器可显式使用临时签名进行 Debug 构建：

```sh
ISLAND_SIGN_IDENTITY=- bash scripts/build.sh Debug
```

临时签名产物不能通过本项目的固定路径安装器，也不能据此验证跨构建辅助功能授权保留。

## 对外发布

对外发布走 `eDouFuRu/notch-island`（公开仓库），本仓库保持私有。三步：

```sh
bash scripts/package-release.sh          # Release 构建 + 素材基线校验 + 出 dist/ 里的 DMG 与发布说明
bash scripts/make-public-snapshot.sh     # 从 HEAD 生成公开源码快照（单个提交 + 版本 tag），含泄露词扫描
bash scripts/publish-release.sh --yes    # 建仓/推快照/建 release 上传 DMG；不带 --yes 只打印将公开的内容
```

- 素材基线 `scripts/release-artwork-baseline.txt` 锁住 13 个曾带公司字样的图标／贴图的 sha256，比对不上就中止打包。字样是用 `scripts/scrub-brand-mark.swift` 逐像素抹掉的（检测种子 → 区域生长 → 按行插值重绘），派生图标由 `scripts/export-shu25d-icons.sh` 重导。
- 快照从 **HEAD** 取，未提交的改动不会进去，所以脚本要求工作树干净。
- 公开版没有 Apple 公证（无付费开发者账号），用户首次打开必须在「系统设置 → 隐私与安全性」点「仍要打开」；`spctl` 实测结论是 `rejected`（origin 为本机自签证书）。

## 文档与验证

- [271 版原文歌词与时钟修复](LYRICS-271-VALIDATION.md)
- [272 版歌词颜色设置](LYRICS-COLOR-272-VALIDATION.md)
- [273 版菜单栏图标与显示开关](MENU-BAR-273-VALIDATION.md)
- [274 版默认主页](HOME-DEFAULT-274-VALIDATION.md)
- [275 版紧凑系统提示栏](COMPACT-HUD-275-VALIDATION.md)
- [276 版系统工具与应用通知](TOOLS-NOTIFICATIONS-276-VALIDATION.md)
- [280 版音频输出、显示模式与原彩显示验证](TOOLS-NOTIFICATIONS-280-VALIDATION.md)
- [293 版系统通知真实消息转显与点击打开](NOTIFICATIONS-293-VALIDATION.md)
- [294 版应用通知通用化](NOTIFICATIONS-294-VALIDATION.md)

- [使用和工程说明](README-Island.md)
- [歌词与 hi 验收记录](BRIEF-NOTIFICATIONS-VALIDATION.md)
- [系统 HUD 验收记录](HUD25D-VALIDATION.md)
- [薯队长动作验收记录](SHU-MOTION-VALIDATION.md)
- [设置验收矩阵](SETTINGS-VERIFICATION.md)
- [素材源图与处理说明](artwork/shu25d/README.md)

276 本轮 **237 项核心测试通过，0 失败**。87 项原服务检查、37 项歌词服务检查属于历史通过记录，本轮未重跑。原生系统、硬件或真实消息的待验项目在文档中单独标注。部分文档链接指向本机构建日志或预览，这些 `build/` 产物不纳入源码仓库，可用测试与渲染脚本重新生成。

## 上游与许可

上游：[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)，固定提交 `16b0f11f51c79d42e27c10d77fd9e53c11410fdb`。保留上游 Git 历史、[GPL-3.0 许可证](LICENSE)、[上游原始说明](docs/upstream/README-boring-notch.md)和现有第三方声明。薯队长等品牌元素用于本项目的内部开发，相关品牌权利归其权利人。

上游工作流存放在 `.github/upstream-workflows/`，本备份不自动构建、发布或部署。仓库不包含钥匙串、签名私钥、用户计时数据、消息正文、构建缓存或已安装应用。
