# 花朵动效离线导出

读取上级目录的 `scene.js`、`assets.json` 和素材图，由 JavaScriptCore 计算与网页相同的逐帧动作，再用 CoreGraphics 合成。原生画布 384×192，以最近邻放大 3 倍，背景使用 sRGB 浅色 `#eef0e8` 或深色 `#202b30`。

```bash
./tools/render.sh --stills-only
./tools/render.sh --stills-only --dark
./tools/render.sh --presence
```

默认输出 `flower-motion.mp4`：20 秒、24 fps、1152×384，无音轨，画面裁自原生 y=48…176。`--full` 额外输出 1152×576 完整画面；`--presence` 额外导出 `flower-presence.mp4`，这是源时间 6…12 秒的常驻动效片段，包含 12 秒阶段切换前的全部帧。风的变化并不周期重复，因此这个片段不宣称无缝循环。

`keyframes/` 和 `closeups/` 保存放大帧，`native-proofs/` 保存 384×100（原生 y=60…160）的原生大小证明，`contact-sheet.png` 覆盖六阶段与盛开期多个动作相位。深色检查另存带 `-dark` 后缀的目录和文件。`media-checks/` 保存从已编码视频实际解码的帧；`metadata.json` 与 `metadata-presence.json` 使用 AVAsset 读取真实视频时长、尺寸、帧率及音轨数。`--output <目录>` 可另存产物。

支持 `sprite`、`rect`、`line` 命令。sprite 的可选 `clipPolygon: [[x,y], ...]` 位于原生锚点局部坐标系，在平移、旋转与缩放之后、图像锚点偏移之前建立闭合剪裁，供花瓣分区独立变形使用。

需要完整 Xcode；脚本仅为当前命令设置 `DEVELOPER_DIR`。不操作浏览器或用户桌面，不修改素材及共享动作文件。
