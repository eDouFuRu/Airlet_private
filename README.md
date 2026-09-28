# Airlet

Airlet 是一款原生 macOS 灵动岛应用。它为带刘海和外接无刘海显示器提供各自合适的小岛样式，并把媒体、日历、专注计时和常用系统工具放在菜单栏附近。

**当前版本：v1.1.2（build 306）** · **要求：macOS 15.0 或更新版本、Apple Silicon**

[下载 Airlet v1.1.2 DMG](https://github.com/eDouFuRu/Airlet_private/releases/download/v1.1.2/Airlet-1.1.2.dmg)（仅仓库成员可访问）

## 灵动岛与显示器

- 内置刘海屏保留贴合刘海的原生小岛。
- 外接无刘海屏采用独立悬浮胶囊：内容不受摄像头区域限制，悬停显示，停留达到设置的延迟后展开。
- 无刘海屏默认自动隐藏，可在「设置 → 通用」关闭。菜单栏高度会按每块屏幕分别匹配。
- 无刘海屏的玻璃清透程度可在「设置 → 外观 → 悬浮岛透明度」调节。滑块改变浅色薄雾，原生清透玻璃不会因透明度提高而消失；内容文字不随外壳淡出。
- 玻璃边缘会根据背后画面的明暗呈现局部亮边与暗边，而不是播放循环旋转的光圈。在「设置 → 外观」可关闭这项效果。它需要 macOS「屏幕录制」权限；Airlet 只在无刘海岛可见时读取周围很小范围的亮度，不保存画面。未授权时使用中性边缘光，授权后需重启应用。
- macOS 26 及以上使用原生 Clear Liquid Glass 与光学边缘层；macOS 15–25 使用系统材质回退。设计不依赖 macOS 27 专属 API，27 上的实际视觉效果仍需实机复测。

## 功能

- **音乐与歌词**：控制当前播放器、显示同步歌词和专辑封面；收起时只占一行。
- **日历**：查看日程、提醒事项和日期热力图。
- **番茄钟**：专注与休息计时、暂停恢复、离线结算、统计和热力图。
- **系统提示**：显示音量、亮度和电源状态。
- **快捷工具**：按需选择工具，包括截屏、录屏、计时器、闹钟、亮度和音量控制。
- **文件暂存**：暂存文件、截图和剪贴板图片；可拖放整理。
- **通知**：选择要显示的应用通知，并按应用配置内容预览。

## 下载与安装

1. 下载上方 DMG，打开后将 Airlet 拖到「应用程序」。
2. 本版本使用项目本地自签名证书，未经过 Apple 公证。首次打开若被 Gatekeeper 拦截，请到「系统设置 → 隐私与安全性」允许打开，再启动 Airlet。
3. 首次使用相关功能时，按系统提示授予辅助功能、屏幕录制、日历或提醒事项权限。

发布包为 Apple Silicon 构建。下载页面同时提供 SHA-256 校验值和详细安装说明。

## 从源码构建

需要 Xcode 26 或更新版本。打开 boringNotch.xcodeproj，选择 NotchIslandNext scheme。开发机签名和本地安装步骤见 [LOCAL-SIGNING.md](LOCAL-SIGNING.md)。

在具有项目签名证书的开发机上，可执行 **bash scripts/build.sh Debug** 进行 Debug 构建，或执行 **bash scripts/package-release.sh** 生成 Release 构建和 DMG。Release 包要求本地签名证书；私钥不会存放在仓库中。打包产物写入被 Git 忽略的 dist/ 目录。

## 项目与验证

本版本以 macOS 26.6.2、Xcode 26 为开发基准，SwiftPM 的 595 项测试已通过。外接无刘海屏的玻璃形状与静态回退已实机检查；背景感应边缘光需要在授予屏幕录制权限后继续实测，macOS 27 仍待验证。

- [Liquid Glass 实现与验证记录](LIQUID-GLASS-VALIDATION.md)
- [使用和工程说明](README-Island.md)
- [设置验收矩阵](SETTINGS-VERIFICATION.md)
- [系统 HUD 验收记录](HUD25D-VALIDATION.md)
- [系统工具与应用通知能力](SYSTEM-TOOLS-CAPABILITIES.md)

## 上游与许可

Airlet 基于 [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) v2.7.3，遵循 [GPL-3.0](LICENSE)。仓库保留上游 Git 历史和第三方声明。
