# 葡萄藤动画外壳（macOS）

保存现有葡萄藤、枝叶轻摆、果粒生长、杰瑞背葡萄与常驻花朵预览。这个 Swift 外壳只负责展示、透明窗口、拖放与本机引擎通信，不包含文件分类算法。

最新“地面花丛与葡萄架分离”构图位于 [设计目录](../../design/grounded-garden/v1/README.md)，目前是静态设计稿，尚未替换本外壳中的画面。花朵也尚未接入真实 DDL。

## 独立构建与离线预览

要求 macOS 13+、完整 Xcode；不需要 Python 或分类核心。

```bash
./build-app.sh
open build/FilePetShell.app
```

构建脚本生成 `build/FilePetShell.app`，复制资源并进行本地签名校验。重新构建前请从菜单栏退出已运行的外壳。菜单中的动画演示不提交真实分类请求。

## 连接外部分类核心

FilePet Engine 在独立仓库中维护，请单独启动后连接其本机地址：

```bash
open build/FilePetShell.app --args --engine-url http://127.0.0.1:8765
```

默认地址也是 `http://127.0.0.1:8765`。客户端通过 `GET /health`、`GET /categories`、`POST /jobs` 和 `GET /jobs/{id}` 获取真实分类结果。成功分类增长葡萄；待确认和失败结果不触发成功增长。核心未连接时仍可观看离线动作。

外壳的葡萄是反馈计数，收葡萄动画不会移动、复制、归档或删除原文件。核心的授权读取目录及 Python 环境由外部核心自己管理。本仓库不包含后端、Python 解释器或分类关键词。

`run-dev.sh` 与 `启动葡萄藤.command` 为原联合工作区入口，仍依赖仓库根目录的 `.venv/` 与 `backend/`；独立 appearance 仓库应使用上述构建及连接方式。这两个脚本作为历史源码保留。

## 动画与交互

- 汤姆静态头部已撤下；杰瑞保留已确认跑动帧与肩背葡萄合成。
- 动画窗口平时点击穿透，拖入文件时开启接收区域，接收结束恢复穿透。
- 当前默认常驻花朵预览有含苞、待放、初绽、盛放、萎垂和凋零六阶段。它们是视觉样例，不是真实截止日期。
- 用户主动关闭整个挂件时可收起全部展示。

| 位置 | 责任 |
| --- | --- |
| `Sources/FilePetShell/` | 菜单、透明窗口、拖放、引擎连接与渲染 |
| `Sources/FilePetShell/Appearance/` | 展示状态、布局、颜色和动作时间线 |
| `Sources/FilePetShell/Resources/` | 已有角色与花朵素材及来源说明 |
| `Tests/FilePetShellTests/` | 展示状态、存储、动作与客户端检查 |

## 验证

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

本次记录中 50 项通过，1 项真实引擎集成检查按默认跳过，0 失败。真实核心接线需另行设置 `FILEPET_LIVE_ENGINE_URL` 和 `FILEPET_LIVE_EXAMPLES`，不属于本次离线检查。
