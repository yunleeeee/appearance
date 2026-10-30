# 像素藤园 · 方案 01

使用 imagegen 内置工具生成，背景为不透明奶油色。新设计概念板，未替换正在运行的前端。

交付图：`pixel-garden-concept.png`。

内容：七色葡萄、藤蔓/叶片/卷须组件、含苞至凋零六阶段花朵、深浅背景组合示意。

此图用于美术方向确认。后续如用于实际像素素材，仍需将独立部件按统一原生网格重整、校准接点，并以整数倍放大检查；不把整张生成图直接视为已对齐的游戏图集。

## 完整提示词

```text
Use case: stylized-concept.
Asset type: cohesive pixel-art sprite family concept board for a small desktop grapevine widget.
Create ONE exceptionally polished 16-bit-style pixel art design sheet containing matching GRAPES, GRAPEVINES, and DEADLINE FLOWERS. It must feel like a carefully art-directed cozy botanical game sprite set, refined enough to sit quietly on a work desktop.

PIXEL DISCIPLINE — essential:
Actual deliberately drawn pixel-art silhouettes and color clusters, a consistent visible square pixel grid across every plant, aligned stepped edges, one-pixel warm dark outlines on the conceptual native grid, crisp nearest-neighbor enlarged look. Imagine sprites designed at 32–48 logical pixels and enlarged 4x. NO antialiasing, NO blur, NO soft gradients, NO painterly flower with a pixel filter, NO glossy vector icons, NO 3D/voxel/isometric renders. Use 3–4 hand-selected tones per material with selective highlights and a restrained shared palette. Pixel detail should describe forms, not add random noise or dense dithering.

DESIGN LANGUAGE:
Warm walnut and honey-brown woody vine, twisting olive-green young shoots, beautifully shaped lobed grape leaves with a few clean pixel veins, small spiral tendrils with elegant stepped curves. Delicate without becoming unreadable.
Grapes are plump individual berries in tapered natural bunches, 10–12 berries, each berry with a tiny 1–2 pixel highlight and strong clean silhouette. Seven related colorways: amethyst purple, warm golden yellow, indigo blue, raspberry rose, pale chartreuse green, tangerine orange, soft lavender gray. Keep the same cluster anatomy and pixel size across variants.
Flowers are a SIX-PETAL imaginary clematis with creamy ivory petal edges, rose-pink inner petals, a small old-gold stamen heart, olive calyx and a short graceful support stem. The flowers must belong to the SAME sprite family as the grapes and vine, with the same pixel density and shading discipline. No realistic roses or photorealistic petals.

FLOWER LIFECYCLE:
Show six clearly distinct silhouettes, left to right:
1 “含苞”: narrow upright closed green-and-blush bud.
2 “待放”: rounder swollen pink bud, slight seam opening.
3 “初绽”: cupped flower with partly opened petals, gold center just visible.
4 “盛放”: broad open six-petal ivory-and-rose flower, the most luminous and full silhouette.
5 “萎垂”: flower still rose colored but its tips curl inward and neck gently bows; imminent deadline.
6 “凋零”: deeply bowed dried-rose/honey-brown flower, curled papery petals, ONE falling petal; overdue. Residual flower stays on the stem, never disappears.
State changes must be readable by shape, not only palette. Do not imply wilting is task completion.

BOARD COMPOSITION:
Landscape 3:2 composition, approximately 1536x1024. Flat warm cream background with ample empty space, very light restrained pixel-line separators. A stylish uncluttered sprite design board, no giant cards or heavy frames.
Title at top left exactly “像素藤园”. Smaller subtitle exactly “葡萄 · 藤蔓 · DDL 花朵”.
Top hero section: one graceful horizontal grapevine grows from the right edge toward the left, with branching leaves and tendrils, TWO modest grape bunches hanging below and THREE flowers at different stages growing above. This hero demonstrates the whole family working together; airy and balanced, not a dense hedge.
Middle section: the SEVEN grape colorways in an evenly spaced row, plus a small modest inset study of modular vine/leaf/tendril pieces if space permits. Small heading exactly “葡萄与藤蔓”. No file-category labels.
Lower section: six evenly spaced flower lifecycle sprites on matching short sprigs, each with ONLY its given short Chinese stage label. Small heading exactly “花期变化”.
Bottom edge: two small slim desktop-use strips, one pale and one charcoal, both showing the same tiny mixed vine/flowers/grape composition at a genuinely modest scale, no invented controls, no clocks, no calendars or task text. The plant pixels stay crisp on both backgrounds.
Chinese typography should be compact and legible, with a restrained pixel-font feel, no faux gibberish or extra text. No characters, people, cats, mice, buildings, stars, sparkles, watermarks or unrelated props.
Make the vines, grapes and flowers aesthetically unified and suitable for a future desktop ornament. The output is a new design proposal, not a replacement of the running app.
```
