> 历史归档：2026-10-30 从 FilePet Engine 移出的联合工作区外壳说明。以下相对路径对应原 filepet-engine/frontend/macos/，当前启动方式请看 appearance/frontend/macos/README.md。

# 葡萄藤动画外壳（macOS）

保留现有葡萄藤、枝叶轻摆、果粒生长和杰瑞背葡萄动画，将文件分类交给 `../../backend/` 的 FilePet Engine。外壳负责桌面窗口、拖入文件、任务状态和动画，不包含分类关键词、正文提取或另一套按扩展名分类算法。

当前核心是只读分类服务，不移动、复制、归档或删除原文件。外壳的果粒是收到成功分类结果后的展示反馈，不是受管文件库存；动画收走葡萄也不会处理原文件。`needs_review` 与失败结果保留说明，不触发成功增长。

## 启动

日常启动可双击本目录的 `启动葡萄藤.command`，拖入允许分类的文件夹并回车；直接回车使用示例。该入口会同时启动界面和核心，界面已打开时则只补启动核心。终端保持运行，关闭它会停止本次分类服务。

要求 macOS 13+、完整 Xcode，以及仓库根目录已经准备好的 `.venv`。首次从仓库根目录准备 Python 环境：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e './backend[dev]'
```

已有项目环境可直接使用，无需重复安装。核心接口与支持格式见 [backend/README.md](../../backend/README.md)。

```bash
cd frontend/macos
./run-dev.sh --examples
```

这会构建 `build/FilePetShell.app`，用项目示例作为允许读取的目录，启动独立 Python 引擎，再打开葡萄藤。将 `backend/scripts/examples/` 内的示例文件拖向葡萄藤可验证真实分类；选择根目录本身不会自动扫描或分类其中的文件。

处理自己的文件时显式指定授权目录：

```bash
./run-dev.sh --root "$HOME/Downloads"
```

只拖入该目录内的普通文件。核心会拒绝目录外路径和跳出根目录的符号链接；文件夹不是当前的分类输入。引擎进程本身必须有读取授权目录的系统权限：外壳收到拖放权限，不会自动把这份权限转给独立的 Python 进程。启动器以 `backend/` 为引擎工作目录，并将选定目录的绝对路径传入 `--root`。

端口占用时不会停止已有服务，也不会默默复用未知授权目录的服务，可指定其他端口：

```bash
./run-dev.sh --root "$HOME/Downloads" --port 8766
```

保持启动器所在终端运行。Ctrl+C 只停止本启动器创建的引擎，界面会失去在线分类连接，离线动画预览仍可使用。`--engine-only`（也支持旧参数 `--no-open`）只启动引擎，不构建或打开界面，因此界面已经运行时也能补启动服务；随后点菜单中的“重新连接分类引擎”即可。`--help` 显示参数。

## 只构建外壳

```bash
./build-app.sh
open build/FilePetShell.app
```

在菜单栏中使用葡萄藤及杰瑞偷葡萄预览，无需分类引擎。预览使用演示事件，不提交真实分类请求。重新构建前先从菜单栏退出已运行的葡萄藤。

单独启动引擎时，请使用 `backend/` 作为工作目录。当前项目的虚拟环境无需重新安装为全局模块：

```bash
cd ../../backend
../.venv/bin/python -m filepet serve --root "$HOME/Downloads" --port 8765
```

外壳默认连接 `http://127.0.0.1:8765`；启动器通过 `--engine-url` 传入选定的本机地址。应用包只包含 Swift 程序与角色资源，不打包 Python 解释器或分类算法。

## 两边的边界

```text
系统拖放
   ↓
外壳 → POST /jobs → 分类核心提取正文、判断主题
   ↑       ↓
   └── GET /jobs/{id} 轮询真实状态
           ↓
  成功：对应主题增长葡萄
  待确认 / 失败：显示原因，不增加成功计数
```

分类 ID、名称和结果来自核心。内容主题与旧应用的“文档、图片、代码”等扩展名分组不同。替换分类算法或修改主题应在 `backend/` 完成，动画端通过相同协议接收结果。

主要目录：

| 位置 | 责任 |
| --- | --- |
| `Sources/FilePetShell/` | 菜单、透明窗口、拖放、引擎连接与动画渲染 |
| `Sources/FilePetShell/Appearance/` | 纯展示状态、葡萄布局、颜色、动作时间线 |
| `Sources/FilePetShell/Resources/Characters/` | 已确认的杰瑞原片跑动帧与来源说明 |
| `Tests/FilePetShellTests/` | 展示状态、动作接触、存储与客户端验证 |
| `../../backend/filepet/` | 唯一文件分类核心 |

汤姆的静态头部已撤下，杰瑞使用已认可的原片跑动与肩背葡萄合成。动画窗口平时保持鼠标穿透；拖文件时才启用接收区域，接收结束恢复穿透。

当前默认常驻六阶段花朵设计预览：含苞、待放、初绽、盛放、萎垂、凋零。花和短枝不随葡萄藤自动淡出，仍保持点击穿透；用户主动使用整个挂件的显示/隐藏开关时可以收起。它们是视觉样例，不是真实 DDL 数据，后端尚未接入花朵状态。

## 验证

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./build-app.sh
```

默认检查不依赖运行中的引擎。先单独启动以示例目录为 `--root` 的引擎，再运行真实接线检查：

```bash
FILEPET_LIVE_ENGINE_URL=http://127.0.0.1:8765 \
FILEPET_LIVE_EXAMPLES="$(cd ../../backend/scripts/examples && pwd)" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter LiveEngineIntegrationTests
```

该检查验证两个成功主题、一个待确认、目录外拒绝和原文件不变，使用隔离的展示计数。应用状态与传输检查共 50 项通过；真实接线检查另 1 项通过。核心的 13 项 Python 检查通过，其中旧 API 测试的示例已对齐当前存在的招聘分类，没有改分类算法。

构建脚本生成 release 应用，复制 `FilePetShell_FilePetShell.bundle` 资源并完成本地签名校验。该外壳使用独立的 `com.filepet.GrapeShell` 应用标识，与旧宝藏纸篓工程分开；旧工程没有作为依赖接入。

API 任务仅在引擎内存中保存，服务重启后旧任务会过期。分类服务尚无文件移动、归档、撤销和文件夹监控 API，这些能力不能由成功动画代替。正式跨平台发布和 Python sidecar 打包仍需单独实现。
