# 薯队长动作分层素材

本轮沿用已有角色身体、面部、绿芽、红衣和「小红书」字样的 PNG，不改写这些像素。新肢体由 imagegen 按同一角色参考生成；材质保持暖色哑光公仔效果。

原生试用后，用户指出两段手臂过长、关节不自然，因此当前手臂改用 `source/short-arm.png` 生成的一体式短圆造型，袖口、胳膊和小手没有中间接缝。`short-arm-generation.json` 保存提示词，`import-short-arm.py` 用同一获授权的青底提取流程导入，最终派生图和握点见 `processed/short-arm.png`、`processed/short-arm-import.json`。旧两段臂素材保留作过程记录，当前场景不再使用；腿脚素材继续使用。

- `source/limb-sheet.png`：未经修改的生成源图，六个独立组件。
- `generation-log.json`：成功生成的提示词、输出来源和处理说明。
- `prompts.json`：初始组件设计描述；这组独立请求没有产生可交付素材，不作为最终素材来源。
- `processed/`：六张真正带 alpha 的上臂、前臂、手掌后层、前指、近腿、远腿，及本机 Vision 蒙版。
- `import-layers.py`：沿用本会话已获授权的本机抠图导入流程。只整理新肢体的画布与挂点，不处理原身体图像。
- `processed/import-record.json`：源图和派生图哈希、透明通道范围、尺寸、挂点。

原生成图含不透明棋盘背景。使用系统 Vision 提取六个前景实例，收紧边缘后再裁切分层。不能把生成图中的棋盘当作真实透明通道。上臂和前臂整理为中性向下的画布；腿与脚整理到统一脚踝位置，渲染时脚底单独保持着地姿态。前掌与前指共享同一画布和握点，物件绘制在两层之间。

重现导入：先使用 `artwork/shu25d/ShuForegroundMask.swift` 的现有工具对源图创建 `processed/limb-sheet-mask.png`，然后运行：

```sh
/Users/dongfengrui/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 artwork/shu-motion/import-layers.py
```

运行时清单在 `boringNotch/components/Island/Shu25DAssets.json`。`pivot` 和 `end` 都是最终 PNG 画布内的归一化坐标；身体、肩腕、工具和持物使用 `ShuAnimationRig.swift` 的同一世界坐标采样。一体手臂直接绑定肩部和握点，不绘制中间肘关节；种植与放下的红薯改为位于小手下方，以较短的伸手距离完成动作。胸前字样通过手臂姿势和工位布局避让，没有在字样区域挖除手臂或重新叠字。

本轮未修改三款应用图标、旧素材或 v2 库存持久化规则。实际时间轴仍在满 60 秒时交给库存结算，55.7 秒后的落薯只是本轮临时画面。
