# 离线动效导出

从同目录的 `scene.js` 与 `assets.json` 读取动作及素材，JavaScriptCore 计算与网页预览相同的绘制命令，CoreGraphics 以 384×192 原生像素绘制并用最近邻放大 3 倍。它不操作浏览器或用户桌面。

在 `motion/` 下执行：

```bash
./tools/render.sh --stills-only
./tools/render.sh --stills-only --dark
./tools/render.sh
```

需要完整 Xcode，脚本仅为本次命令设置 `DEVELOPER_DIR`。

完整导出包含 16 秒、24 fps、无音轨的两个 MP4：完整画面 1152×576；动作近景 1152×384（原生 y=48…176）。`metadata.json` 和 `metadata-closeup.json` 由导出后的 AVAsset 实际读取时长、尺寸、帧率与音轨数。

`keyframes/`、`closeups/` 和 `contact-sheet.png` 用于检查开合、葡萄回弹、风摆、垂头与落瓣；深色检查另存 `keyframes-dark/`，不会覆盖浅色帧。`media-checks/` 是从已编码的两部视频实际解码得到的 0、7.21、14.79、15 秒图像，用于核对真实成片。指定 `--output <目录>` 可把产物写到另一处。

PNG 角色仍来自图像生成的分层素材；MP4 是本地逐帧合成，不是图像生成器直接输出的视频。
