# 275 版：默认系统提示栏紧凑化

日期：2026-09-07。

## 结果

- 仅调整“默认”样式的音量、亮度提示行：44 点 → 28 点，与歌词栏共用 `BriefPresentationLayout.rowHeight`。
- 收起状态的刘海下方提示和展开状态导航下方的提示都使用这一高度，正文保留自己的高度。
- 默认提示的图标为 15 点，置于 22×22 点容器内，与文字、进度条垂直居中。
- 内嵌视图及共用进度、错误文字、符号组件与修改前源码完全一致；内嵌样式仍只占原有刘海顶栏。

## 验证证据

- 现有 HUD 与提示优先级、尺寸回归测试共 29 项通过；覆盖默认行替换歌词时的高度、全屏零高度恢复、展开正文保留及内嵌尺寸。
- 使用当前生产 `SystemHUDRow`、`InlineHUD`、进度条和歌词行离线渲染，中文并排图确认音量、亮度与歌词行均为 28 点。40 个 HUD 场景的摄像头留空和图标可见检查通过，10 个展开正文对照通过。
- `inline-source-unchanged.json` 记录 `InlineHUD` 和 `SystemHUDValue` 源码与 Git HEAD 相同的 SHA-256。
- 与隔离读取的修改前 HUD 源码渲染对照：20 个内嵌顶栏逐像素一致。16 张完整画面一致，另外 4 张的正文渲染差异最大为 1/255 色阶；内嵌提示区域无差异。
- 最终 Debug 构建、主应用和辅助服务签名验证通过，275 版安装到 `~/Applications/工位充电岛.app`，274 版已自动备份。
- 原生设置页确认：“系统提示样式”为“默认”，“替换系统提示”开启，运行状态为“正在使用小岛提示”。未改变用户的样式、音量、亮度或其他偏好。
- 本轮没有重新实测物理媒体按键或权限撤销；离线视图渲染不作为真实按键证据。媒体键处理和硬件操作逻辑未修改。

## 本机产物

- `build/validation/compact-hud-275/layout-tests.log`
- `build/validation/compact-hud-275/build-signed-275-final.log`
- `build/validation/compact-hud-275/install-275.log`
- `build/validation/compact-hud-275/inline-source-unchanged.json`
- `build/validation/compact-hud-275/hud-previews/compact-rows-zh-Hans.png`
- `build/validation/compact-hud-275/hud-previews/geometry.json`
- `build/validation/compact-hud-275/hud-previews/pixel-checks.json`
- `build/validation/compact-hud-275/hud-previews/inline-baseline-pixels.json`

可复现渲染：`python3 scripts/render-hud-previews.py --output build/validation/compact-hud-275/hud-previews`。渲染器隔离设置和硬件服务，不改动用户数据。
