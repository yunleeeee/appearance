# 轻盈像素植物挂件 · 视觉优化 v1

日期：2026-10-30。

将右下角植物从大面积花园收为小巧的桌面挂件：缩小整体尺寸，移除连续草地，三株莓玫瑰错落生长，木架与叶片降低饱和度和对比度，保留花朵、果实与原有像素美术方向。

## 交付文件

- [desktop-all.png](desktop-all.png)：保留菜单栏与 Dock 的完整桌面构图，展示葡萄架、果串与底部花朵。
- [desktop-flowers.png](desktop-flowers.png)：同一桌面的日常常驻状态，葡萄架整层隐藏，花朵位置和尺寸保持一致。
- [desktop-background.png](desktop-background.png)：用于桌面合成的无植物背景。
- [complex-all.png](complex-all.png) / [complex-flowers.png](complex-flowers.png)：复杂云纹壁纸适应性核对，背景采用原壁纸的无植物区域裁放。
- [light-all.png](light-all.png) / [light-flowers.png](light-flowers.png)：浅色背景核对。
- [dark-all.png](dark-all.png) / [dark-flowers.png](dark-flowers.png)：深色背景核对。
- [flowers-source.png](flowers-source.png) / [trellis-source.png](trellis-source.png)：内置 `image_gen` 生成的透明像素素材。花朵分株裁切组合，花果保留鲜艳色彩，次要枝叶和木架在展示层降低视觉权重。
- [layout.json](layout.json)：后续实现用的视觉规格，目标花区 285×145；当前运行时不读取此配置。
- [index.html](index.html) / [preview.js](preview.js)：静态外观核对页面，无额外产品控件。
- [GENERATION.md](GENERATION.md)：内置 image_gen 的完整提示词和组合方式。

全部核对图为 1555×1012。实际花层为 289×148，约占屏幕宽度 18.6%、高度 14.6%；葡萄层尺寸保持 400×292，整体上移 72 像素，底边距为 72 像素，让花朵上方留出更多空间。两层合并的外接范围约 400×364，增加的是层间留白，花朵和葡萄架均未缩放。花朵位置不变，花茎仍从底边自然长出，根部仅有分散的小草叶。

## 打开核对页面

在本目录启动静态文件服务后打开 `index.html`。查询参数只用于核对两种可见状态与三类背景，不会生成或修改植物状态。

```bash
python3 -m http.server 18780 --bind 127.0.0.1
```

访问 `http://127.0.0.1:18780/index.html`，默认显示原桌面取景下的花朵常驻状态。可用 `?state=all&background=light` 查看浅色完整组合；`state` 支持 `all`、`flowers`，`background` 支持 `desktop`、`complex`、`light`、`dark`。

## 实现边界

本目录只交付视觉设计与静态核对，不改动原生应用、分类核心或已封存的 `design/releases/flower-v2.0-2026-10-30/`。页面没有接入真实 DDL、摘花或葡萄成熟掉落逻辑。

后续接入时沿用宿主已有的 DDL 与花朵对应关系、独立花期和时间戳、摘花交互及成熟掉落机制；只应用尺寸、位置、装饰和图层显示调整。葡萄架隐藏时，木架、葡萄、藤蔓、葡萄叶和卷须共同隐藏，花层保持原位。若宿主调整果串位置或比例，应同步其既有掉落起点和点击区域的坐标变换，保持机制本身不变。
