# 正式版与切花测试版

`main` 是日常运行和部署入口。2026-11-07 的稳定基线包含已确认的单花花头 72%、花茎竖向增加 18pt、整组右移 86pt、原生全屏隐藏与退出恢复，以及分类、OCR、归档和持久化功能。

切花、双击收获和碎裂动画只在 `test/flower-harvest-slash-effect` 验证。该测试分支必须包含最新稳定 `main`，不可从旧 `main` 单独构建后当作正式更新。其他旧功能分支保留历史，不能代替稳定入口。

正式 App 为 `FilePetShell.app`，标识 `com.filepet.GrapeShell`。切花测试 App 使用独立名称、独立标识和独立偏好记录，避免测试版顶替正式版或改写正式任务。

构建结果的 Info.plist 保存 `FilePetReleaseChannel`、`FilePetBuildCommit`、`FilePetBuildBranch` 与 `FilePetBuildSourceRoot`。核对运行路径和这些字段即可确认正在使用哪个版本。合并切花功能前，应检查 `main...test/flower-harvest-slash-effect`，差异应限于切花实现、交互说明和对应测试。
