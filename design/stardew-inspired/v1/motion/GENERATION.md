# 像素动画素材生成记录

两组位图均使用 imagegen 内置工具，以 `../farm-garden-concept.png` 为角色与风格参考，生成透明分层素材。保留原始 Alpha，运行时依照 `assets.json` 取各个部件，不将设计板整体平移充当动画。

## 藤蔓、葡萄和叶片

文件：`plant-sprites.png`，1536×1024，透明背景。

```text
Use case: identity-preserve / precise sprite component extraction for animation.
Use the attached NEW farm-garden concept board as the exact plant identity reference. Build ONE transparent pixel-art ANIMATION COMPONENT ATLAS. Preserve the source's chunky farm-game pixels, brown wooden trellis, stocky purple/green/gold grape bunch shapes and grass-green lobed leaves. Do not invent a different plant style.

Output TRUE TRANSPARENT ALPHA background. No blue, paper, checkerboard or black background paint, no glow, no drop shadow. No title, text, numbers, frames, catalogue boxes or UI. No people.
Organize isolated animation parts on a wide 1536x1024-style canvas in THREE clearly separated rows, with generous fully transparent gutters:
TOP ROW (top ~30%): ONE bare horizontal wooden trellis crossbar with a short right vertical stake. Its shape follows the source, horizontal bar left-to-right, right stake downward, simple thick pixel wood. Bare wood ONLY: remove EVERY leaf, vine, flower and grape from this trellis so these can be layered later. Keep whole crossbar and post inside this top band with margin.
MIDDLE ROW (middle ~34%): THREE complete separate grape sprites in this exact order: purple, green, gold. The SAME short fat 7–9 berry silhouette as the source with small highlights. Each sprite includes ONLY its short thin top stalk, grape berries and at most one tiny sepal. Remove the large leaf and diagonal woody branch so it can sway from a clean narrow stalk pivot. Each sprite is fully isolated and entirely within its own broad column.
BOTTOM ROW (lower ~30%): THREE independent small grape LEAF sprites, left to right: leafA points upper-left, leafB points upper-right, leafC is a smaller young leaf. Each includes a narrow short petiole whose cut base is easy to anchor. Preserve the source's squat lobes and minimal pixel veins. At the far right of this row place ONE tiny separate orange petal from the source's new wildflower; it will be animated falling.
No other objects, no extra leaves or fruits. Keep all sprites separated so alpha connected components can identify them.
The source pixel shapes remain crisp and stepped, 2–3 tones per material, no smooth gradients, antialiasing, painted noise or vector outlines. It must be an animation kit for THE SAME newly designed farm grapevine.
```

## 六阶段花朵

文件：`flower-states.png`，1536×1024，透明背景。花期使用六个完整关键姿态；花梗支点对齐，凋零姿态围绕根部镜像以延续萎垂方向。落瓣独立运动。

```text
Use case: identity-preserve / pixel animation keypose sheet.
The attached farm-garden board is the exact flower identity and chunky pixel style reference. Create a TRUE TRANSPARENT 3-column by 2-row atlas of SIX flower keyposes for that SAME new apricot-orange farming-game wildflower. It must be useful as discrete deadline-life-cycle animation cels.

No board, frames, blue background, paper, glow, halo, text, numbers or shadow. Only six isolated flowers with their small green stalk and at most one small side leaf. All non-plant pixels genuinely transparent alpha. Large fully transparent gaps separate every cell; no plant crosses a cell.
Maintain the same pixel size, direction of light, orange hues, brown-plum outline and plant identity. Visible coarse square pixel clusters, 2–3 tones per material, no antialiasing or high-resolution paint. Not cream/rose clematis.

Every pose shares the same plant size and the same bottom support/root point in its cell, on a common baseline. Keep the stalk short and plainly jointed. Petals open around the same flower center. Six cells in reading order:
0: CLOSED slender green drop-shaped bud with an orange tip.
1: SWOLLEN round orange bud, seam beginning to part, still enclosed by green sepals.
2: HALF OPEN — three rounded apricot petals opening outward, deep gold center partially visible.
3: FULL BLOOM — the complete broad orange wildflower, five simple round lobed petals with a deep golden pixel heart, exactly matching the source's fully open flower character.
4: WILTING — original orange color retained, petals curling downward, flower neck bowed slightly, still complete, gold center partly hidden by the curling upper petals.
5: DRIED — short bowed stalk, ochre-brown curled residual flower and ONE missing petal. The residual flower remains attached. Do NOT include any detached or falling petal in this sheet; a separate petal sprite will be animated later.
DO NOT draw all six as the same flat flower merely recolored. Silhouette/pose changes must be obvious, yet coherent between neighboring poses.
Keep every plant complete and inside its own cell including all leaves and root. This is a clean reusable pixel keypose atlas, not an explanatory illustration.
```
