# 葡萄与 DDL 花朵（macOS）

外观唯一维护在 `appearance`。分类、正文提取和 DDL 提取由相邻 `filepet-engine/backend` 提供，原文件不移动或删除。

## 打开 App

双击 `build/FilePetShell.app` 即可。App 会自己启动并连接本机分类核心，终端不需要保持打开。无参数运行 `启动葡萄藤.command` 也会直接打开 App，不再询问文件夹。

自动模式使用当前用户的主目录作为核心可读取范围，仅在主动拖入或选择文件后分析，不扫描目录。macOS 对桌面、文稿、下载等位置的系统权限仍适用。App 为本机非 App Store 构建，不启用会阻止外部 Python 子进程的 App Sandbox；核心仍只绑定本机地址并执行其路径授权检查。

自动服务使用独立空闲端口，不依赖固定的 8765。启动时先等待健康检查，再读取类别；重复连接复用 App 自己的服务，服务退出后会在空闲时自动检查并重新启动，也可从菜单手动重新连接。退出 App 只停止自身服务，不停止外部启动的引擎。

## 从源码构建

需要 macOS 13+、完整 Xcode，以及核心目录中已安装依赖的 `.venv`。当前 App 使用本机安装的 Python 环境，不包含完整的跨机器运行时。

```bash
./build-app.sh
open build/FilePetShell.app
```

构建脚本默认使用相邻的 `filepet-engine/`，也可设置 `FILEPET_ENGINE_ROOT`。生成的 App 配置会记住这台机器上的核心路径；启动时的环境变量优先，其次检查记录的位置与相邻目录。缺少核心或环境时，App 会给出具体说明，离线动画仍可用。

## 开发时使用外部核心

需要限制到单独目录、使用样例或指定固定端口时，可以显式运行：

```bash
./run-dev.sh --examples
./run-dev.sh --root "$HOME/Downloads"
./run-dev.sh --root "$HOME/Downloads" --port 8766 --engine-root /绝对路径/filepet-engine
```

`--examples` 授权核心的 `backend/`：普通分类样例位于 `scripts/examples/`，DDL 样例位于 `examples/deadline_notice.txt`。支持 `--engine-only` 只开服务。这种模式需保持终端运行，Ctrl+C 只停止脚本启动的核心。

连接自己启动的核心：

```bash
open build/FilePetShell.app --args --engine-url http://127.0.0.1:8765
```

显式 `--engine-url` 不会额外启动自动服务。切换模式前退出已运行的 App，避免 macOS 忽略新启动参数；之后从 Finder 直接打开 App 即恢复自动模式。

## 当前外观

App 直接渲染 `compact-garden/v1` 的轻盈像素木架，葡萄层为 400×292，位于右下角、立柱底部与屏幕底边对齐，花朵根部保持原位；花层保持独立并常驻。旧的弯曲藤蔓和光滑圆葡萄已从运行中的外壳撤下。

素材原有的三串葡萄不会作为固定示例留在基底：每类一株、每个真实文件一粒；没有分类数据时木架上没有葡萄。多于三类时在同一木架内排布，果粒较多时在各自串内缩排。落下剧情从当前像素串的同一坐标开始，沿用既有动作时间。

## 待确认事项

App 菜单和菜单栏都有“待确认事项（N）…”入口。新一批文件中存在待确认结果时，确认窗口会自动打开；“查看最近分类结果”也可进入处理。

普通的“分类待确认”表示主题证据不足，并不一定已经提取到 DDL。可在窗口中补充主要内容、项目、截止日期和可选时间，点击“确认 DDL 并生成花朵”，也可切换为普通分类并选择核心提供的类别。候选有多条时逐项确认。

对图片 OCR 中 `dd|`、`dd1`、`ddI` 等疑似 `ddl` 的识别，核心会保留原文并标记为待核对候选；确认前不会生成花朵。明确识别的普通 DDL 沿用自动生成花朵的方式。未填写时间不会补成 23:59，过去日期也不会擅自改成下一年。

待确认记录保存在本机，重启后可继续处理；输入日期或时间无效时不会清除记录。确认完成后仍遵守同时最多三朵、多余依次排队的规则。

## 投喂与收获

- 同一次提取同时检查 DDL 和普通主题；明确 DDL 优先生成花朵，疑似 OCR 截止日期先进入待确认事项，每条确认后的独立 DDL 一朵，不同时增长葡萄。
- 花朵使用最新轻盈构图中的三株透明素材，固定在屏幕右下角，最多三朵。多余 DDL 按投喂顺序排队。
- 悬停展示主要内容、截止时间和项目；日期缺失年份会标注推定，未给时间则明确显示未注明。
- 点击花朵即收获、完成 DDL，排队项自动补位。超期不会自行删除 DDL。队列和完成时间保存在本机，重启后恢复；重复投喂不复活已完成项。
- 普通分类按核心的类别 ID 生长，一类一株，每个新增文件一颗葡萄。同一规范路径跨批次、重启后不会重复计数。
- 葡萄不再满 12 颗自动消失；更多像素果粒在同一串内缩放排布。杰瑞预览保留为动画演示，不消耗文件计数。
- 花朵实心部分响应鼠标，透明空隙穿透桌面。可通过花朵或唤醒的葡萄区域拖入文件，也可从菜单选择文件。隐藏挂件会同时隐藏两层。

项目目前取核心提供的网页标题、正文明确项目字段或分类名称/文件名作为来源；主要内容是通知原句摘录。核心仍使用规则识别明确日期，不支持“明天”“下周五”等相对日期。

## 验证

可为原生渲染核对额外导出静态截图（独立测试数据，不写用户计数）：

```bash
FILEPET_RENDER_COMPACT=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter CompactGardenRenderingTests
```

图像位于 `.tmp/compact-qa/`，用于对比设计稿与运行时木架、像素果粒和花层构图。


```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./build-app.sh
```

真实核心检查需单独启动授权 `backend/` 的核心，然后设置：

```bash
FILEPET_LIVE_ENGINE_URL=http://127.0.0.1:8765 \
FILEPET_LIVE_EXAMPLES=/绝对路径/filepet-engine/backend/scripts/examples \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter Live
```

默认测试离线运行并跳过真实核心检查。设置 `FILEPET_TEST_ENGINE_ROOT=/绝对路径/filepet-engine` 可运行自动核心的真实生命周期检查，不需要先手动启动服务。旧版 App 的葡萄、花朵完成状态及去重记录在第一次启动新版时迁移，已有新记录优先，旧数据副本保留。检查覆盖队列、收获补位、完成持久化、分类去重、HTTP 协议与原文件保持原样。
