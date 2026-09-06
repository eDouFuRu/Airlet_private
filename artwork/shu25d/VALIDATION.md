# 2.5D 场景验证 · 2026-09-06

已完成本机授权范围内的透明素材导入、连续时间轴与页面接线。此次没有修改 `PotatoSessionStore`、`IslandRestModel`、v2 存储、库存结算、签名或安装流程。

| 检查 | 结果与证据 |
| --- | --- |
| 原图保护 | `source/` 的 14 张高清源始终保留，每轮处理前后校验哈希。最终清单在 `build/validation/shu/alpha/source-and-alpha-audit.json`。 |
| 透明素材 | 11 个 `Shu25D-*` 图层均为 RGBA 且存在 alpha=0 的像素；没有缺失素材或使用旧人物 fallback。 |
| 去底质量 | 查看黑色、米色、草地绿色三个底色的检查图；修正首轮青底低透明度残留及抱薯图浅色光边。叶子、黑眼睛、水壶把手孔与手臂边缘保留。 |
| 挂点 | 双臂由 welcome 原图拆分并旋转为中性姿态；肩、手、锄头握点和水壶喷口使用同一坐标变换。显示尺寸保持 PNG 比例，避免透明边距导致手与道具分离。 |
| 动作衔接 | 锄地有蓄力、快速落下和收势；拔薯先弯身再拉起；转身、翻烤与交付采用连续插值。七阶段与 60 秒循环边界由纯时间轴驱动。 |
| 时间轴测试 | 7 项通过，覆盖边界连续性、暂停/离屏/减少动态效果、有限数值范围、红薯携带连续性，以及按库存数量对齐下一格/溢出徽标的交付坐标和最终尺寸。 |
| 库存与六口 | 只调整视觉堆放顺序，从右下角填充，避免与火上红薯重叠。六口遮罩使用食物的真实 alpha 内容宽度，第五口保留约 1/6 长度，第六口为空；未改数量或扣减规则。 |
| 页面截图 | 57 张实际 SwiftUI 静态图，包含中英双语、0/1/12/13/大库存、休息/暂停/完成、专注与六口、15 个时间点。 |
| 完整采样动画 | 已按最终交付落点修复后的源码重新生成 `build/validation/shu/previews/shu-60s-loop.gif`：1200 帧、60.0 秒、20 fps，324×186，23,787,620 字节。元数据与哈希见同目录 `animation-validation.json`。 |
| 轻量动画 | `build/validation/shu/previews/shu-60s-preview.gif`：2,830,646 字节（约2.83MB），仍为1200帧/60秒/20fps。使用全片共享256色调色板和差分帧，无抽帧；关键帧与完整版已并排检查。编码记录见 `lightweight-preview.json`。 |
| 最终交付修复 | 原先最后位置固定且提前淡出，已改为对齐下一库存格并缩到21×16，落点后有0.6秒回稳，保持到真实结算。满12格时对齐溢出徽标图标。`handoff-contactsheet.png` 展示库存1→2、11→12、12→13在59.00/59.95/60.00秒的9张证据。渲染器提供前后模拟数量，未写入真实库存。 |

主要可视化文件：

- `build/validation/shu/previews/timeline-contactsheet.png`
- `build/validation/shu/previews/overview-zh-Hans.png`
- `build/validation/shu/previews/overview-en.png`
- `build/validation/shu/previews/potato-bites-contactsheet.png`
- `build/validation/shu/previews/zh-Hans-rest-45s.png`
- `build/validation/shu/previews/shu-60s-loop.gif`
- `build/validation/shu/previews/shu-60s-preview.gif`
- `build/validation/shu/previews/handoff-contactsheet.png`
- `build/validation/shu/previews/handoff-manifest.json`

标准57图和10张交接图的源码哈希均由各自 manifest 保存。完整GIF覆盖固定样例库存下的[0,60)秒，交接图另行提供60秒结算前后的模拟数量；动画文件不访问或结算真实库存。

这些验证证明素材、确定性采样与静态布局可生成并经过视觉检查。采样 GIF 不是原生录屏，不能代替悬停窗口动画、系统帧率、锁屏唤醒、摄像头权限或真实 60 秒奖励验收；原生验证由主任务继续执行。
