# 本机稳定签名与安装

本流程仅用于当前用户的本机开发。主应用和 XPC 使用同一张专用本地证书，固定安装在 `~/Applications/Airlet.app`。不使用新出现的 Apple Development 身份，不导出私钥，也不修改已安装的 boring.notch。

| 项目 | 固定值 |
| --- | --- |
| 证书名称 | `NotchIsland Local Development` |
| 证书 SHA-1 | `0A93291611F302DBECD76D2ACEC9DEF86D1F3DB2` |
| 主应用 Bundle ID | `com.dongfengrui.Airlet` |
| XPC Bundle ID | `com.dongfengrui.Airlet.XPCHelper` |
| XPC 相对路径 | `Contents/XPCServices/NotchIslandXPCHelper.xpc` |
| Xcode 工程默认 Build | `280` |
| 构建脚本默认 Build | `280`（音频输出、显示模式与原彩显示） |
| 安装位置 | `~/Applications/Airlet.app` |

证书已经创建在登录钥匙串，当前用户的 `codeSign` 信任已按用户确认配置，专用 SHA-1 已通过 `security find-identity -v -p codesigning` 验证。没有修改系统范围信任，没有导出私钥。首次私钥访问由 macOS 钥匙串管理；脚本不会代填密码或自动放行。

## 构建

在工程根目录执行：

```sh
bash scripts/build.sh Debug
# 或
bash scripts/build.sh Release
```

默认 `ISLAND_BUILD_JOBS=1`，减少首次访问专用私钥时多个构建任务同时触发钥匙串授权的机会。确认首次授权已完成后，可自行设置 `ISLAND_BUILD_JOBS` 为其他正整数；单任务构建不能保证 macOS 不再逐次请求私钥访问，也不替代用户处理系统授权。

如果授权窗口堆积或构建已取消，先暂停新的构建和签名。构建/签名成功退出才释放锁；收到 HUP、INT、TERM 或非零退出时保留自己持有的锁，并在锁目录的 `interrupted` 文件记录原因、退出状态与时间，后续运行会拒绝取得该锁。SIGKILL 无法执行退出处理，也可能留下未写原因的锁，仍然拒绝自动接管。脚本尚未追踪或等待 Xcode 构建服务派生的所有 `codesign` 进程，构建命令退出不等于所有子签名请求都已结束；应先确认本次遗留的构建与签名操作已停止，再手动清除该锁、处理 `.cstemp` 或重新构建。脚本不会操作安全窗口、发送终止信号或修改私钥访问控制。安装器仍执行原有失败回滚与锁清理。

脚本首先确认专用 SHA-1 对应的有效代码签名身份，再明确向 Xcode 传入该身份、手动签名与空 Development Team。找不到身份、信任未就绪或签名失败时直接失败，不选择其他证书，也不自动退回临时签名。工程的主应用/XPC、Debug/Release 四项配置均使用上述证书名称；脚本用 SHA-1 进一步避免重名证书歧义。

构建产物为 `build/Build/Products/Debug/Airlet.app`（Release 对应 Release 目录）。构建完成后，`scripts/codesign-local.sh` 检查主应用与 XPC 的公开签名证书及 designated requirement（DR）。目标要求是：

```text
identifier "com.dongfengrui.Airlet" and certificate leaf = H"0A93291611F302DBECD76D2ACEC9DEF86D1F3DB2"
identifier "com.dongfengrui.Airlet.XPCHelper" and certificate leaf = H"0A93291611F302DBECD76D2ACEC9DEF86D1F3DB2"
```

如果 codesign 已生成相同的要求，或者针对这张自签证书生成等价的 `identifier … and anchor H"同一 SHA-1"` 要求，保留原签名。否则按 XPC、主应用的顺序固定 DR，保留既有 entitlements 和 hardened runtime 数据；不使用 `--deep --force` 重签第三方代码。最后同时检查证书 SHA-1、Bundle ID、DR、外部 leaf 要求及嵌套签名完整性。整个流程不导出私钥；验签暂存的公开 DER 证书随即删除。

需要显式临时签名调试时：

```sh
ISLAND_SIGN_IDENTITY=- bash scripts/build.sh Debug
```

此选项仅允许 Debug，终端会明确提示临时签名。安装脚本拒绝该产物，不能用它验收辅助功能权限的跨版本保留。直接在 Xcode 内 Build 可以用于开发；正式安装前仍通过构建脚本或单独运行 `codesign-local.sh` 完成一致的 DR 校验。

## 安装与首次授权

先从应用菜单退出所有运行中的“Airlet”，包括旧原型或其他路径下的同 Bundle ID 副本。安装脚本只读取 AppKit 的运行应用清单，不发送退出指令，也不按名称结束任何进程。

```sh
# 仅验签、显示主应用/XPC的DR，不安装、不启动
bash scripts/install-local.sh Debug --verify-only

# 安装通过验签的产物，不自动启动
bash scripts/install-local.sh Debug

# 也可使用 Release 或明确的绝对 app 路径
bash scripts/install-local.sh Release
```

安装脚本不接受 `sudo`。它先验证源应用的证书、ID、DR 与嵌套签名，再复制到 `~/Applications` 内的临时目录并重新验证。已有目标必须是本应用 Bundle ID 的真实目录；符号链接或其他应用会被拒绝。替换前再次检查运行状态，然后把旧应用移动至：

```text
~/Library/Application Support/Airlet/Install Backups/Airlet-日期时间-唯一编号.app.backup
```

随后把通过验证的新应用移动到固定位置；最终移动失败时尝试恢复旧版本。备份使用 `.app.backup` 后缀，不会作为额外 Airlet 出现在启动台中，也不会自动删除；需要恢复时将后缀改回 `.app`。脚本不碰应用偏好、休息数据、钥匙串或辅助功能授权，也不操作 `/Applications/boringNotch.app`。备份与临时文件可能保留 Finder 元数据，这是复制应用的正常行为；脚本不移除 quarantine 来规避系统检查。

首次授权应针对最终的 **`~/Applications/Airlet.app`**，不要针对构建目录或备份副本。打开这份固定应用，在 HUD 设置中查看诊断的 Process、Bundle ID、Signature、AX 和 Event tap，再按界面操作授权。若系统仍保留旧临时签名条目，用户可在辅助功能列表确认并替换为固定路径下的新应用；脚本不会重置整个 TCC 数据库。

今后更新继续使用同一证书、Bundle ID、稳定 DR 与固定路径。代码变化应改变 CDHash，但不应改变 DR。该机制用于建立稳定身份；**是否保留 macOS 的辅助功能授权仍需在此机器上实测，不把签名校验通过视为权限验收通过。** 本地证书不等于 Developer ID 公证分发身份。

## 两次构建的身份对照

`ISLAND_BUILD_NUMBER` 可覆盖本次主应用及 XPC 的编号，不修改工程默认值。下面保留可重复的对照流程；263、264 为示例，实际已完成 264/265/266 的签名身份对照，并原生确认265→266的授权保留：

```sh
mkdir -p build/validation/local-signing
ISLAND_BUILD_NUMBER=263 bash scripts/build.sh Debug
bash scripts/install-local.sh Debug --verify-only > build/validation/local-signing/263-verify.log
/usr/bin/codesign -d -r- build/Build/Products/Debug/NotchIslandNext.app > build/validation/local-signing/263-main.dr 2>/dev/null
/usr/bin/codesign -d -r- build/Build/Products/Debug/NotchIslandNext.app/Contents/XPCServices/NotchIslandXPCHelper.xpc > build/validation/local-signing/263-xpc.dr 2>/dev/null
/usr/bin/codesign -dvv build/Build/Products/Debug/NotchIslandNext.app 2> build/validation/local-signing/263-signature.log

ISLAND_BUILD_NUMBER=264 bash scripts/build.sh Debug
bash scripts/install-local.sh Debug --verify-only > build/validation/local-signing/264-verify.log
/usr/bin/codesign -d -r- build/Build/Products/Debug/NotchIslandNext.app > build/validation/local-signing/264-main.dr 2>/dev/null
/usr/bin/codesign -d -r- build/Build/Products/Debug/NotchIslandNext.app/Contents/XPCServices/NotchIslandXPCHelper.xpc > build/validation/local-signing/264-xpc.dr 2>/dev/null
/usr/bin/codesign -dvv build/Build/Products/Debug/NotchIslandNext.app 2> build/validation/local-signing/264-signature.log
diff -u build/validation/local-signing/263-main.dr build/validation/local-signing/264-main.dr
diff -u build/validation/local-signing/263-xpc.dr build/validation/local-signing/264-xpc.dr
```

期望主应用和 XPC 各自两份 DR 无差异，验签均通过且专用证书 SHA-1 一致，主应用 CDHash 随编号变化。接着分别安装、运行这两次构建并检查真实 AX/event tap 状态，才能验证跨构建授权保留。

## 本地动态库与运行配置

自签证书没有 Apple Team ID。Build 263 虽通过资源验签，但启动时被 DYLD 的库验证拒绝加载 `NotchIslandNext.debug.dylib`，因此不能把这一版记为可运行。主应用现在使用 `boringNotch.local.entitlements`：保留原有权限，仅增加 `com.apple.security.cs.disable-library-validation=true`；保留 hardened runtime 其他保护。基础 `boringNotch.entitlements` 未增加此项，供以后正规分发重新评估。

此差异对应 [Apple 库验证说明](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation)：库必须由 Apple 或与主程序相同的 Team ID 签名。本配置仅针对已固定证书的本机开发版，不是 Developer ID 分发配置。

## 当前验证界限

280 已使用同一专用证书完成构建、主应用／XPC 验签及固定路径安装；安装器保留被替换版本。见 [280 验证记录](TOOLS-NOTIFICATIONS-280-VALIDATION.md)。新增截图、通知与系统控制的权限和真实操作单独验收，不把签名成功视为功能或授权验证成功。下文保留 264–266 的历史签名与授权证据。

已实际完成专用证书构建、严格资源及身份验证和固定路径安装。曾中止的并行 codesign 在 XPC seal 中遗留 `.cstemp` 记录；只对本工程两份 XPC 和主程序按顺序重新签名后通过 deep/strict 验证，没有编辑 CodeResources 或重签第三方框架。同 Bundle ID 的调试应用运行时，安装器已实际拒绝替换；退出后安装成功。

Build 264 的动态库启动修复已经在固定路径实际验证；Build 265 已再次构建并严格验签。两构建主应用及 XPC 的 DR 完全一致，主程序 CDHash 分别为 `9a20c70463995946ff7108562fbcfb86143e6324` 与 `a0ed4ecddc49163166e8ce58a2c74be68de16f4d`，符合代码变化而身份稳定的预期。265 固定副本已实际确认主进程 AX=true、event tap=true；用户内置键盘亮度、音量和静音事件已接管，用户确认岛上提示正常且系统右上角没有同时出现。264/265 的 TCC 日志均为 Allowed，但未捕捉264授权完成后、升级前的实际 UI AX 状态；此次另保存了265更新前实际 AX/tap 为 true 的记录；安装同证书266后，主 PID 40151 在固定路径的原生诊断仍为 AX=true、event tap=true，期间未修改权限或重新授权。265→266这一轮的授权保留实测通过；当前构建的代码哈希为 `6311762f7f96db2169be2c1988eb150e0afe42df`。见 [更新前记录](build/validation/hud25d/pre-update-265.json)、[更新后记录](build/validation/hud25d/post-update-266.json)和[身份对照](build/validation/hud25d/signing-version-comparison.json)。真实物理按键验收记录属于265，266仅改设置窗口标题，新的物理事件尚未记录。

可重复且不调用签名/安装的检查：`bash scripts/test-local-signing.sh`。它包含脚本语法、工程四项身份/版本配置及 7 项 DR 策略用例，替换了读取 DR 的函数。安全测试直接运行生产锁与安装清理函数，仅修改临时目录中的 fixture；中断用例调用已登记的实际 trap 内容，不发送进程信号，也不枚举或终止系统进程。此前静态日志为 `build/validation/local-signing/script-static-checks.log`。

构建与独立签名共用 `build/.NotchIsland-build.lock`，仅成功退出时释放；异常退出保留锁及中断原因，不自动抢占残留锁。安装对固定目标使用独立锁，保留正常失败回滚与清理。签名前拒绝符号链接、`.cstemp` 和损坏 seal。最新 **30 项安全检查与 7 项 DR 策略检查通过**，包括 HUP/INT/TERM 后 build/sign 保留原因与拒绝重入、非零退出保留锁，以及 installer 仍恢复旧应用并清理锁。日志归档为 `build/validation/hud25d/signing-interruption-tests.log`；`build/validation/hud25d/signing-safety-tests.log` 是此前 23 项检查的历史证据。
