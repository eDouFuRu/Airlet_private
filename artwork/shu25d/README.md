# Captain Shu 分层素材导入

当前状态：已于 2026-09-06 按用户“继续计划”的明确回复，承接前文的本机抠图确认，完成 11 个透明场景图层导入。14 张高清源图的哈希在每轮处理前后保持一致。母版和全部高清生成图保留在 `source/`；这些文件永远不作为输出目标。真实授权上下文及每轮处理记录见 `processed/import-record.json`。

## 文件与职责

- `source/`：原始高清图，禁止覆盖。母版的造型、颜色与光照为权威参考。
- `generation-log.json`：生成过程记录，由主代理维护；导入器不修改。
- `import-plan.json`：源文件选择、抠图方式、双臂裁切多边形与挂点。
- `import-assets.py`：默认只读计划；授权后可执行派生素材导入。
- `ShuForegroundMask.swift`：macOS Vision 的离线前景蒙版工具，只在真正导入复杂背景时执行。
- `processed/`：授权导入后创建，保留完整分辨率的裁切与透明边距派生图、导入记录。
- `../../build/validation/shu/alpha`（工程根目录下）：授权导入后创建，在黑色、米色、草地绿色背景上的边缘检查图。

完整 hero 的 AppIcon 等比例尺寸导出由主代理单独处理。此管线仅处理 `Shu25D-*` 透明场景图层，不覆盖 `ShuIcon-*`、AppIcon 或 logo。

## 复现导入

本会话所需的本机编辑授权已记录，下面的流程可在相同授权范围内复现。命令中的 `--approval-note` 用于留下记录，不代表需要再次向用户确认。

使用带 Pillow 与 NumPy 的 Python。当前会话提供的解释器为：

```sh
/Users/dongfengrui/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
```

系统 Xcode Python 没有这两项依赖；无需修改系统 Python 或联网安装包。

先仅查看计划（不会创建目录、编译工具或写图片）：

```sh
python3 artwork/shu25d/import-assets.py
```

**只有在用户明确同意本机图像编辑之后**，用上述完整 Python 路径代替下面的 `python3`，并把授权说明替换为真实的用户授权记录：

```sh
python3 artwork/shu25d/import-assets.py --apply --approval-note '填写用户明确授权的实际内容与时间'
```

建议先派生与检视，不写入 app catalog：

```sh
python3 artwork/shu25d/import-assets.py --apply --no-catalog --approval-note '实际授权记录'
```

局部校准可以使用 `--only arm-near --only arm-far`。`--preserve-raw-alpha` 可对比生红薯原有透明度；它仅跳过该素材的 Vision 去光晕，不影响其他图层。调整 `import-plan.json` 的标记后可重复生成，所有源文件保持不变。

## 素材处理约定

青底处理按 `min(G, B) - R` 估计背景占比，从四角读取实际底色；生成背景有约 3–9% 的渐变偏差，因此剔除低于 10% 的前景置信度，再连续映射边缘透明度。仅对半透明边缘消除青色混入，保留叶片、喷壶、皮肤、红衣和黑眼睛。水壶把手内的青色也会透明。导入器不直接删除所有绿色像素。

复杂背景使用 `VNGenerateForegroundInstanceMaskRequest`。抱薯 hero 的奶油底使用 Vision；母版若使用棋盘背景，也不能把格子当透明通道。蒙版以线性灰度导出，再向内收一像素，避免色彩空间把半透明边缘变成浅色光边。`raw-potato.png` 已确认有真实 alpha（0…254），但带柔光晕；默认将 Vision 蒙版与已有 alpha 相乘来压掉背景光晕，而不是假定整张黑底均为不透明。Vision 的结果会随 macOS 模型版本变化，导入记录会保存系统版本和蒙版哈希。

双臂取自 `captain-welcome.png`。裁切多边形保留手和少量袖口，肩部切口放在人物身体下方遮住。使用肩部→手部向量计算旋转，统一为肩在上、手在下的中性姿态；PNG、肩部 pivot 和手部标记采用同一变换。导入后已检查三种底色上的手臂边缘，并以实际页面校准手部、锄头握点和水壶喷口。

所有图层按 alpha 大于 4 的边界紧裁，再分别在左右、上下加入内容宽高的 8% 透明边距。`processed/` 不缩小；catalog 最大边长 1024，保持比例。PNG 存储 straight alpha，源图不覆盖。导入时核对输入哈希，记录输出尺寸、alpha 统计、源与输出哈希、处理步骤和标记坐标。

## 挂点与原生接线

主逻辑人物尺寸为 `180×220`，页面显示 `124×152`。`pivot`、`hand` 与 `emitter` 为最终透明 PNG 内的归一化坐标；`rigShoulder` 为逻辑人物坐标。导入后脚本更新 `boringNotch/components/Island/Shu25DAssets.json` 的对应项，保留时间轴和持久化说明。

`captain-base`、`arm-near`、`arm-far` 三层齐全后，原生场景自动从旧矢量 fallback 切换到分层人物。场景的其他必备素材为锄头、水壶、幼苗、生红薯、熟红薯和柴堆；`captain-holding` 优先取抱薯 hero，缺失时才尝试母版 Vision 蒙版。`ground` 已作为可选地台接入：耕地在左，火堆在右，库存展示区沿用既有页面。图片缺失时仍可使用旧 fallback，当前预览使用完整的实际图层。

首次渲染前应核对近臂压在衣身前、远臂压在衣身后，肩部没有透明缝或红色重影；手臂 pivot 必须与 PNG 的实际显示比例一致。水壶喷口与水滴发射点也需要按 `emitter` 校准。静态预览不会证明原生动画帧率或锁屏行为。

## 批准后的验收顺序

1. 查看 `build/validation/shu/alpha/*-backgrounds.png`：无青边、棋盘、黑晕，叶片/眼睛/袖口/把手孔没有误抠。
2. 检查原图哈希未变，所有必备图层都有真实透明像素，库存红薯缩小时仍可辨认。
3. 运行 `python3 scripts/render-shu-previews.py`，检查双语页面、0/1/3/5/6 口、不同库存与 15 个时间点。
4. 使用 `python3 scripts/render-shu-previews.py --animation` 导出采样 GIF；它只展示程序时间轴，不替代原生交互或帧率验收。
5. 调整挂点、画面位置后在原生 App 中确认连续动作、暂停冻结、收起/隐藏/锁屏停止绘制、60 秒奖励仍只结算一次。

已完成导入器 Python AST、计划 JSON、Swift Vision helper 类型检查、11 个 RGBA 图层导入、源图哈希保护和真实 SwiftUI 静态预览。时间轴 6 项测试通过，覆盖动作边界、暂停/离屏/减少动态效果及红薯携带连续性。采样动画为完整 60 秒、20 fps；它不验证真实悬停、窗口形变、系统帧率或锁屏。计时 v2 与库存结算未在本素材任务中修改。
