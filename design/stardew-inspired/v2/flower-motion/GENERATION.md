# 常驻像素花朵 · 生成记录

使用 imagegen 内置工具从空白设计新的半重瓣花型，输出带真实 Alpha 的 `flower-atlas.png`。本次没有在旧橙色五瓣图标上简单改色。

素材包含六个花期头部、独立侧叶与落瓣。运行时按 `assets.json` 取各部件；盛放分成三个花瓣区域和一个匹配花心，花梗另行绘制。花心与花萼的不同位置通过对应的连接向量保持一致。

## 完整提示词

```text
Use case: stylized-concept.
Asset type: premium PIXEL-ART flower animation character atlas with transparent alpha.
Design a NEW, unusually refined semi-double miniature wild rose for an always-visible desktop deadline flower. It lives in a cozy farm-game pixel-art world, but must be much more elegant and organic than a generic flat five-petal game icon.

FLOWER ART DIRECTION:
A subtly asymmetric semi-double bloom viewed THREE-QUARTER FRONT, five broad softly-notched outer petals plus three smaller curled inner petals. Delicate creamy-ivory edges, dusty berry-rose petal bodies, deeper plum-rose folds near the throat, and a tiny restrained old-gold stamen center. Depth comes from the visible front/back petal overlap and controlled color clusters. A clear charming silhouette even at 36–40 native pixels. No perfectly radial pinwheel, no flat round-disc flower, no sunflower/daisy, no orange wildflower, no ornate realistic rose full of tiny petals.
True clean hand-placed-looking pixel art: conceptual 36–40px bloom, coherent chunky square pixels enlarged about 8x, sharp stair-step edges, a shared limited palette, 3 tones per petal material, warm dark plum outline selectively softened by neighboring pixel colors. No antialiasing, no smooth gradients, no painted texture, no 3D, no glitter, no glow, no halo, no photorealism.

ATLAS:
A 4-column by 2-row layout on one landscape 3:2 transparent canvas. Exactly eight separated assets, generous fully transparent gutters, NO text/numbers/frames/background:
Row 1, cells left to right:
0. HEAD ONLY tightly CLOSED bud, tapered green sepals with a berry/ivory petal seam. Small, graceful, tilted slightly to the left. No stem or leaves.
1. HEAD ONLY swelling bud, fuller rounded berry-rose, curled petal tips begin loosening. No stem or leaves.
2. HEAD ONLY half-open cupped semi-double flower, front petals open lower, inner curled petals and a few gold pixels visible; three-quarter depth. No stem or leaves.
3. HEAD ONLY complete FULL BLOOM of the refined semi-double rose described above. Slightly irregular silhouette, richly layered yet readable, the most beautiful state. Make the front two outer petals distinct and the back petals slightly higher, stamen slightly off-center. No stem or leaves.
Row 2, left to right:
4. HEAD ONLY the same rose WILTING, still berry/ivory colored, front petal ends curl inward/down, flower head faces gently DOWN-LEFT. Show a lovely sagging silhouette, not an intact front view simply recolored. No stem or leaves.
5. HEAD ONLY DRIED residual rose facing deeply DOWN-LEFT, dusty dried-rose and honey-ochre, papery curled petals, ONE missing petal. Still an attached residual flower, not a dead stump. No falling petal in this cell. No stem or leaves.
6. ONE small elegant jade-green side leaf with a short petiole, slightly curved, modest narrow teardrop silhouette with only a few pixels of vein. No grape leaf lobes, no extra foliage.
7. ONE isolated curled cream-and-berry petal, suitable for a single falling-petal animation. No stem or leaf.

All six heads are the SAME flower at the SAME plant scale, same lighting and pixel density. The closed bud is naturally smaller than the full bloom. Each entire head stays inside its cell. Heads have a short green calyx only, with a clean lower attachment point; do not include the long stalk, because the stalk will be dynamically drawn later.
Composition is a strict clean asset atlas, not a concept board or a decorated scene. True transparent alpha outside the actual plant shapes, no cast shadows, no backdrop paint or simulated checkerboard.
```
