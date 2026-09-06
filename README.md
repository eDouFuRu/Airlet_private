# 工位充电岛 · NotchIslandNext

基于 **boring.notch v2.7.3** 的原生 macOS 刘海应用，当前备份为 **270 版**。使用 SwiftUI + AppKit，保留物理刘海悬停、弹簧伸缩、反向圆角及上游常用工具。

<p align="center"><img src="boringNotch/Assets.xcassets/ShuIcon-captain.imageset/icon.png" width="160" alt="薯队长"></p>

## 当前功能

- **薯队长小岛**：软萌 2.5D 角色、种薯与烤薯动作、双手与飘动的云。
- **红薯钟**：自定义休息和专注时间，暂停、恢复、离线结算与本地库存。
- **系统 HUD**：MacBook 内置亮度、音量、静音键的刘海提示。
- **音乐与歌词**：播放器控制、简体同步歌词、长句滚动、28 点紧凑提示行；无歌词或暂停时收起，不扩大刘海宽度。
- **设置**：中英文切换、图标选择，以及媒体、日历、文件暂存等工具。
- **hi 通知实验**：适配器与隐私设置已实现，默认关闭；真实 hi 横幅尚待验证，原系统横幅隐藏尚未开放。

## 打开与构建

运行要求：macOS 15.0+。当前在 macOS 26.6.2 / Apple Silicon / Xcode 26 上验证。

1. 打开 `boringNotch.xcodeproj`。
2. 选择 `NotchIslandNext` scheme。
3. 当前开发机器使用专用本地证书，按 [LOCAL-SIGNING.md](LOCAL-SIGNING.md) 构建和安装。证书私钥不在仓库中。其他机器可显式使用临时签名进行 Debug 构建：

```sh
ISLAND_SIGN_IDENTITY=- bash scripts/build.sh Debug
```

临时签名产物不能通过本项目的固定路径安装器，也不能据此验证跨构建辅助功能授权保留。

## 文档与验证

- [使用和工程说明](README-Island.md)
- [歌词与 hi 验收记录](BRIEF-NOTIFICATIONS-VALIDATION.md)
- [系统 HUD 验收记录](HUD25D-VALIDATION.md)
- [薯队长动作验收记录](SHU-MOTION-VALIDATION.md)
- [设置验收矩阵](SETTINGS-VERIFICATION.md)
- [素材源图与处理说明](artwork/shu25d/README.md)

当前记录：181 项核心测试、87 项原服务测试、37 项歌词服务检查通过。原生系统、硬件或真实消息的待验项目在文档中单独标注。部分文档链接指向本机构建日志或预览，这些 `build/` 产物不纳入源码仓库，可用测试与渲染脚本重新生成。

## 上游与许可

上游：[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)，固定提交 `16b0f11f51c79d42e27c10d77fd9e53c11410fdb`。保留上游 Git 历史、[GPL-3.0 许可证](LICENSE)、[上游原始说明](docs/upstream/README-boring-notch.md)和现有第三方声明。薯队长等品牌元素用于本项目的内部开发，相关品牌权利归其权利人。

上游工作流存放在 `.github/upstream-workflows/`，本备份不自动构建、发布或部署。仓库不包含钥匙串、签名私钥、用户计时数据、消息正文、构建缓存或已安装应用。
