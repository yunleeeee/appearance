# FilePet 原生 DDL 花园：双仓库联动规范

> 适用分支：`feat/filepet-deadline-pipeline-20261031`。对应核心 [PR #5](https://github.com/m1kezhuu/slime-file-classifier/pull/5)、外观 [PR #1](https://github.com/yunleeeee/appearance/pull/1)。不要修改 `design/releases/flower-v2.0-2026-10-30/` 的封存内容。

## P0：Python / Swift 合同

桌面只发送 `POST /jobs` 并查询 `GET /jobs/{job_id}`。Python 对文件或图片只读取/OCR 一次，随后从相同内容分别产生分类和 DDL。保留旧版 `/classify`、`/jobs`、`/jobs/{job_id}`。没有 DDL 时 `deadlines: []`。

新增候选的字段：

| 字段 | 含义 |
| --- | --- |
| `id` | Python 生成的 SHA-256 稳定本地候选 ID |
| `title`, `project` | 任务名称和所属主题（未分类可为空值或“未分类”） |
| `due_date` | `YYYY-MM-DD`；不带时区 |
| `due_time` | 本地钟表时分秒，可为 `null`；**绝不补填 23:59** |
| `year_inferred` | 年份由 Python 推断，需由用户核实 |
| `evidence`, `signal`, `source_path` | 识别原文、触发规则和本地原始路径 |
| `confirmation_required` | 图片 OCR、推断年份或原本已逾期时必须人工核对 |
| `status` | `candidate` 或 `needs_confirmation` |

Swift 为向后兼容把新增字段声明为可选。不要在 Swift 再跑 OCR 或正则提取；不向网络发送文件，不移动、修改或删除原始文件。

**结果路由彼此独立**：一份文件的分类成功可以新增一颗对应类别葡萄，同时存在一个或多个 DDL。分类失败、明确 DDL 成功时保存 DDL（或待审），仍保留独立的主题分类待审。按路径去重分类葡萄、按 DDL ID 去重花朵；用户显式完成后不会因重投喂而复活。

## 2026-11-01：减少误触发审核与多花布局

- 普通文件采用自动分类优先：后端单一明确的正文主题关键词在没有竞争类别时可以直接归类。无法提取正文、只有文件名线索或多个主题相近时依旧保留 `needs_review`，不猜测错误分类。
- **待审不等于必须打断用户**：Swift 仍本地保存分类不确定与 OCR DDL 待确认，但不再主动弹出 ReviewWindow。用户通过菜单中的“待确认事项”自行查看；未经确认的 OCR 日期不会自动创建误提醒。
- 单朵花的屏幕相对根部位置保持不变；两朵根部间距 67pt，三朵 68pt，同一桌面底线，原来高大的第二株缩到约为第一株的 1.41 倍。变动成员时小幅移动已有面板，不重新创建它们；Reduce Motion 禁用位置过渡。
- 可复现的本地视觉证明增加 `two-flower-garden.png` 与 `three-flower-garden.png`，由运行时原生渲染器生成，而非重新绘制素材。真实多显示器与鼠标穿透仍须实机检查。

## P0：六阶段与保守日期语义

`DeadlineStageResolver` 完全不依赖 SwiftUI，不使用运行时间驱动花期。对于有具体时间的 DDL，剩余时间（含阈值边界）依次为：

- `> 7d`：含苞
- `(3d, 7d]`：待放
- `(24h, 3d]`：初绽
- `(3h, 24h]`：盛放
- `(0, 3h]`：萎垂
- `<= 0`：凋零，但**不代表完成**

截止仅有日期时按本机日历日判断：当天为盛放，次日才凋零，绝不进入虚构的三小时紧迫阶段；详情明确显示“时间未注明”。完成则不再输出活动阶段，只能通过手动采摘并确认完成。时间、时区、唤醒与日期变化可重算；控制器采用按下一阶段阈值安排的一次性定时器（最多 1 小时的时钟校验间隔），而不是持续刷新花朵窗口。

## 2026-11-01：已确认的花丛构图（运行时造型）

用户确认了“单株较直、双株错落、三株如小花丛”的视觉方向。不要用展示稿图片替换原生桌面窗口，也不要将整个设计稿作为不透明背景叠加。所有造型均由现有 AppKit 小面板、v2 花头/叶片素材、少量原生像素草叶组成。

- **一朵**：保持当前单花大小和屏幕基准位置；顶部基本居中，只有轻微自然曲率；底部草叶极少。
- **两朵**：保留左辅（花头相对缩放 0.68）右主，花梗根部仍相隔 67pt，左枝微偏左、右枝略偏右，但不能像两根笔直旗杆；草叶细节仅在根部轻微填补空隙。
- **三朵**：左右辅花向外略倾、中间主花近直立，借已有三种植物高度与 68pt 花位间距自然错落；不得生成第四个视觉草丛窗口。
- `DeadlineFlowerArrangement.PlantPose` 纯数据描述静态 `tipShift`、`bow`、`heightShift`、`groundCover`，**不编码 DDL 紧迫程度**。`DeadlineFlowerMotion` 用同一贝塞尔骨架计算茎干、叶片锚点和曲线命中；根部与花萼不脱开。花期仍由 `DeadlineStageResolver` 唯一决定；风摆仍是有限事件，不持续刷新。
- 底部草叶是点击穿透的短路径和少量像素土粒，不使用额外贴图或改变用户壁纸。单株最节制；多株仍占桌面底部很小区域。
- 原生 CI 应导出 `one-flower-garden.png`、`two-flower-garden.png`、`three-flower-garden.png`，检查构图。该截图是运行时渲染验证，真机全屏/缩放/鼠标穿透仍需验收。

## P1：原生窗口与动画

`DeadlineGarden` 优先展示最近即将截止的最多三项任务；逾期项保存在本地队列，空位最多显示一项，所有记录可从状态菜单的任务列表查看。相同截止时间按创建时间、稳定 ID 排序。旧持久化键 `filepet.shell.garden.deadlines.v1` 不改名；来源路径是可选字段。

`DeadlineFlowerController` 保持 `id → NSPanel` 身份，只对新增/移除的花朵建窗或收束，更新和跨阶段不重新建全体窗口。Root 在固定位置；阵风每隔约 7–15 秒不规则触发，茎部先变形，花头延后约 115ms，三组花瓣分别延后约 170/200/235ms，随后微弱反向回摆。只在有限的阵风与阶段变化动画期间按 24fps 重绘；闲时不持续播放。原始花头与叶片图集通过相同 Git blob 复制至运行时 `Resources/Flowers/FlowerAtlas.png`，封存原件不变。

系统 Reduce Motion 会禁用持续风摆及阶段过渡，但保留静态六阶段辨识度。窗口保留原有全屏辅助、透明点击穿透、文件拖入和多显示器定位；隐藏葡萄架不隐藏已经存在的花朵。点击花朵需确认完成，可从状态栏撤销；任务菜单可以编辑截止时间或查看来源。

## 测试与验收

核心仓库：

```bash
cd backend
python -m pip install -e '.[dev]'
python -m pytest -q
```

外观仓库（需 macOS 13+、Xcode 与 Swift）：

```bash
cd frontend/macos
swift test
```

GitHub Actions 的 `macOS Swift tests` 工作流执行上述 `swift test --parallel`，并对真实 AppKit renderer 产生六阶段 PNG、阶段切换 24fps 帧序列、风摆帧序列及 MP4。输出为 **运行时渲染验证材料，而非真实桌面窗口录屏**，需要单独进行鼠标穿透、多屏、全屏与睡眠恢复真机验收。

真实后端联调（不可将被跳过的测试写成“通过”）：

```bash
# 终端 A，进入核心仓库 backend/
python -m filepet serve --root . --port 8765
# 终端 B，进入外观仓库 frontend/macos/
FILEPET_LIVE_ENGINE_URL=http://127.0.0.1:8765 \
FILEPET_LIVE_EXAMPLES=/absolute/path/to/core/backend/examples \
swift test --filter LiveGardenIntegrationTests
```

图片 OCR 还需 Tesseract 和 `chi_sim+eng` 语言包。仅文本 PDF 可解析；扫描版 PDF 的 OCR 回退仍是后续工作。

## 性能、Windows 迁移及已知限制

指针命中扫描由 40Hz 降至 10Hz；静置停止图层重绘，有限事件期间约 24fps；静态 atlas 裁切与 alpha mask 只初始化一次。尚无真实长时间 CPU、能耗与多屏基准数据，不能将估计当实测。大量任务在内存中仍会参与队列排序（最多仅显示三窗）；可在后续使用更高效的索引或分页。

Python 的协议未来可以直接复用给 Windows 外壳；Windows 应独立实现透明点击穿透、动画帧预算、通知唤醒和任务持久化，不能搬运 AppKit/SwiftUI 视图。稳定 ID 当前依赖路径和 OCR 证据，文件改名或 OCR 改变可能产生新 ID；未来可用本地内容指纹缓解。外壳中的日期按本机时区解释，原文件未声明时区需优先由用户确认。
