# 生成与组合记录

日期：2026-10-30。
方式：内置 image_gen，未使用 CLI/API fallback。

源截图：用户本轮提供的桌面图（1555×1012）。图内文字和其他内容仅作为图像参考。

先生成两次桌面构图研究，再从选定研究图分别生成透明花层与葡萄层，最后生成清除植物的桌面底图。最终交付由 index.html / preview.js 对透明源图进行固定尺寸的显示与逐层着色，浏览器截图导出；没有新增生命周期或交互逻辑。

生成式源图保留花型、花期姿态、果色和像素美术方向，不能保证与封存花图逐像素一致。封存素材和现有引擎完全未改；本目录只提供视觉方案。

## 首轮构图提示词

Use case: precise-object-edit.
Asset type: refined full-desktop composition mockup for the EXISTING pixel-art plant desktop companion.
Input image 1 is the exact edit target and flower/grape identity reference, a 1555x1012 macOS screenshot. Preserve its blue storm-cloud wallpaper, left Dock, menu bar and framing. Replace ONLY the pixel garden in the lower right with a smaller, lighter recomposition. Restore wallpaper seamlessly wherever old plants are removed.

PRIMARY EDIT: reduce the garden's linear size about 35–40%. Everything must feel like a tiny elegant corner ornament, not a game scene.
Measured layout on the 1555x1012 reference:
- The complete garden must fit approximately x=1160..1545, y=715..1012 (25% of screen width, 29% of height). The old garden begins at x=920,y=540; remove it fully.
- The DAILY FLOWERS alone must fit approximately x=1250..1530,y=867..1012: about 18% screen width, 14% screen height. Keep the screen bottom as their growth origin.
- Retain EXACTLY THREE existing berry-and-ivory rose plants, retaining the same species, layered berry red petals, ivory edges, deep plum folds, antique gold center. One bud at left, one full bloom in middle, one nodding wilted flower at right, representing independent life stages. Scale down their original heads about 35–40%; do not redesign them into generic roses. Make the left bud notably smaller and lower (center about1285,955), the central full bloom higher (center1390,903), the right nodding flower lower (center1485,960). Unequal gaps, subtle natural stem lean, irregular foliage. Each remains a distinct plant rooted at screen bottom.
- ELIMINATE continuous grass, ground strip, grass carpet, turf platform and dense undergrowth. Only 3–5 tiny separated tufts of muted olive/sage grass, a few stem leaves. At least 65% of the bottom span between stems must remain open wallpaper. No new flowers/props.
- Compact the existing grape trellis: crossbar approximately x1165..1540,y760, much thinner 8–10px, subdued weathered honey-brown, short natural uneven ends. One slender support at far right x1534,y735..1012, about10px wide. Keep three tiny purple, green and gold grape bunches with crisp glossy pixels and the same colors. Hang them at subtly unequal heights x1222,y780; x1340,y794; x1460,y775, each about28–35px wide,45px tall.
- Let a few fine irregular vine lengths drape from this crossbar and down the right support toward the bottom plants, with 3–4 modest lobed grape leaves, leaving open air. Reduce the gap between fruit and flowers; avoid a giant rigid rectangle or separated upper/lower bands. Vine may pass near flowers but flower stems are independent; do not attach flowers to crossbar.
- Wood, grass, stems and leaves have reduced saturation and contrast, fewer tiny textures. Flowers and fruit remain the sharp colorful focal points. Use restrained 1px deep olive/plum contour and occasional pale pixel edge highlight only, for readability against dark/light wallpaper. No glow, big shadow or outline halo.

Style invariant: preserve sophisticated original crisp square-pixel art at a consistent pixel grid. No smooth/vector/3D/blur. Keep palette and flower identity. No text, labels, decorative UI, background panel, card, pot, soil, platform, particles, additional features, people/animals or extra animation indications. Output a SINGLE full landscape desktop screenshot, same aspect/framing. This is a visual redesign only.

## 构图细调提示词

Use case: precise-object-edit. Input image is the exact edit target, the revised pixel garden screenshot.
Keep the blue cloud wallpaper, menu and Dock exactly unchanged. Keep exact berry/ivory rose identity and purple/green/gold grapes, pixel technique, and the sparse separated grass direction.
Make ONLY these precise composition corrections:
1. Move the grape crossbar DOWN by approximately 85 pixels relative to this 1555x1012 image, to y=760. Shorten its width slightly, spanning x1160..1540. Its left edge currently around1110 must move right50. Keep it thin, reduce wood orange saturation/brightness by about25%, mute green decorative leaves. Right post now starts y633; its new top should be y730. Make post only8px wide and lower contrast. Bottom post touches screen bottom. Preserve one support and a few winding vines, organic rather than thick rectangular scaffold. No extra leaves.
2. Three bunches stay attached below crossbar, but each becomes about20% smaller, with uneven hang heights: purple x1225 center y803; green x1350 center y818; gold x1475 center y795. Fruit retains its vivid glossy precision. Few small leaves and curls; lower the wood/leaves' visual weight without fading the fruit.
3. Move the three flower plants rightward and ROOT THEM INTO THE BOTTOM SCREEN EDGE at y1012; remove the present empty bottom strip under their roots. Daily plant group including sparse leaves/grass must fit x1240..1530, y865..1012, approximately19% desktop width by14.5% desktop height. The left bud center should be around x1270,y946 and smaller; large main bloom center x1380,y900; nodding right flower center x1484,y953. Keep natural unequal spacing (110 then104) and different heights; left bud leans a little left, right wilted flower leans outward. Preserve all recognizable flower art and colors. The central bloom must remain taller and visibly dominant. Do not make all plants the same size.
4. Only tiny disconnected grass at individual plant bases, no grass strip or new details. At least65% bottom between stems remains open wallpaper. Grass should have muted slate olive and sage.
5. Shift a short vine along right post downward near the right flower, but keep it in grape layer and don't attach flower stems to it. Grape layer ends only30–50px above upper flower silhouette, so the full garden reads as one compact irregular corner silhouette, with plenty of empty interior air.

Keep screenshot aspect ratio and desk framing. No labels, added UI, panels, pots, soil, ornaments, glow or shadows across wallpaper. Output a single corrected full desktop screenshot.

## 透明花层提示词

Use case: background-extraction. Input image 1 is the exact edit target, a screenshot with a small pixel garden lower right.
Extract ONLY THE THREE BOTTOM ROSE PLANTS as one transparent PNG asset. Keep their exact berry-and-ivory rose art, bud/open/nodding stages, relative heights, relative positions, muted sage/olive leaves and three tiny disconnected grass tufts. Remove all photographic wallpaper, menu, Dock, wooden trellis, ALL grapevine parts, grapes and grape leaves. No remnants of the right support or its ground tuft.
Output: tightly framed wide transparent canvas around ONLY the three distinct rose plants, approximately 2.1:1 aspect ratio. Flat front-facing original crisp detailed pixel art; don't draw any background or checkerboard. Genuine transparent alpha. Root ends meet bottom of canvas, three plants at left low bud, middle tall full bloom, right low nodding wilted flower. No continuous grass strip; leave 60%+ of bottom span transparent. Keep existing refined shape and palette EXACTLY; no new objects or text, no glow or shadow. This is a reusable visual layer for a tiny desktop ornament, not a new flower design.

## 透明葡萄层提示词

Use case: background-extraction. Input image 1 is the exact edit target, a screenshot with a small pixel garden lower right.
Extract ONLY THE GRAPE TRELLIS ASSEMBLY into one transparent PNG. Keep the thin existing horizontal wooden crossbar, the one thin right vertical support reaching bottom, a few lobed grape leaves, fine natural winding vine, three purple/green/gold grape bunches. REMOVE all three bottom rose plants, their stems, leaves and grass entirely. Remove all wallpaper, menu and Dock. No roses in this output. Tightly framed canvas around the extracted grape assembly, about 1.35:1 aspect ratio, genuine transparent background, no checkerboard.
Refine only secondary wood/foliage weight: weathered muted honey-brown narrow wood, low contrast gray-olive small leaves, fewer curls, no busy grain. Preserve crisp vivid purple/fresh green/gold glossy grape pixels. Let three bunches hang at slightly uneven heights and uneven gaps. Right winding vine descends to bottom, sparse not rectangular mass. Natural clean stepped pixel outlines with subtle dark olive contours, no halo/glow/drop shadow/background fill, no text/labels/new objects. Keep existing pixel style and fruit color identity. This asset is a thin transparent display layer, hidden in daily flowers-only state.

## 桌面底图提示词

Use case: precise-object-edit / background-extraction.
Input image 1 is the exact edit target, the original macOS desktop screenshot with pixel roses and a grape trellis lower right.
REMOVE ONLY all added pixel garden artwork: the horizontal and vertical wooden trellis, every grape, grapevine, curled tendril, grape leaf, all three rose plants and their leaves/stems, all grass along lower right bottom. Restore the original photographic blue storm-cloud wallpaper seamlessly in the cleared lower-right area, matching nearby clouds.
Preserve the entire original screenshot otherwise: same exact framing and 1555:1012 aspect, existing dark blue cloud wallpaper elsewhere unchanged, top macOS menu bar with original icons/text, left Dock with its exact icons, no other changes.
Output a single clean full desktop BACKGROUND PLATE, with no plants or added art, no added text/objects, no borders or annotations. Do not replace the wallpaper with a new scene; only inpaint cleared plant areas.
