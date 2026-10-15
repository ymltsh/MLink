# 妙联（MLink）

基于 Flutter、ADB 和 scrcpy 的 Android 设备连接与屏幕互联工具。主要发布目标为 **Windows x64**；Dart 包名为 `adb_tool`，Windows 可执行文件为 **`code.exe`**。

项目目标是让所有用户都能轻松地在电脑上操控手机，实现轻量化屏幕互联。

## 平台与功能范围

| 平台 | 当前状态 |
| --- | --- |
| Windows x64 | 主要目标，提供安装程序与完整便携 ZIP，首次启动补全私有 ADB / scrcpy 运行环境 |
| macOS / Linux | 实验性桌面工程，检测系统 ADB / scrcpy；尚未完成真机和发行验收，无正式安装包流程 |
| Android | 可选调试签名 APK，仍使用 `com.example.code`；不是正式手机发行方案 |

现有界面提供以下功能，具体支持情况取决于设备 Android 版本、授权和 scrcpy 能力：

- USB / 无线连接、显式 IPv4 范围端口扫描、无线调试配对和设备信息读取。扫描发现开放端口，连接成功后才能确认是 ADB 设备；配对端口和连接端口分别填写。
- 屏幕镜像、音频或摄像头投送、画质配置、录制及单应用虚拟显示。当前管理一个投屏会话，可停止后再启动；普通投屏使用默认码率和尺寸，临时参数可覆盖，DPI 用于虚拟显示。
- APK 安装、包名查询、应用启动/停止/卸载和进程监控。读取失败展示错误，不以演示数据替代真实设备。
- 文件浏览、搜索、创建/重命名/删除和上传下载；元数据保留真实类型、时间和符号链接信息。Root 模式传输尚不支持，会明确拒绝。
- 截图、截图历史和定时截图。
- 主题、运行环境管理及用户主动触发的应用版本检查。

涉及设备的操作使用选中设备的明确标识。切换设备后，尚未完成的旧信息和查询结果不会覆盖新设备；文件、截图和监控页面随设备切换重建。

## 首次使用

1. 在 Android 设备上开启开发者选项及 USB 调试，连接后接受设备上的授权提示。
2. 在 Windows x64 启动妙联，等待运行环境下载、校验、解压和可执行文件检查完成。
3. 在“设备连接”刷新并选择设备，再进入投屏或其他页面。

首次安装从 scrcpy 官方 latest 正式版读取元数据和 SHA256，**元数据与摘要从官方通道直连**；默认仅运行包 ZIP 通过 `https://hub.wgen.top/` 加速。官方通道无法获取校验依据时不会执行未校验内容。所有下载均会校验摘要，归档路径检查通过后才解压。

工具位于当前用户应用数据目录的 `MLink/tools`，后续启动验证并复用本地缓存，不在每次启动追踪 latest。“设置 → ADB / scrcpy 运行环境”可查看路径、重试安装、手动更新或配置加速源，留空可直连。相同 tag 和摘要不重复下载；更新失败保留旧环境，正在使用的目录不会被清理。

Windows 使用私有工具绝对路径及子进程环境，不修改系统 PATH。macOS / Linux 需自行将 ADB、scrcpy 配置到系统环境中，暂未提供可编辑的工具路径选项。应用中的进程清理仅针对本应用启动并持有的 ADB 客户端，不结束系统全部 ADB、scrcpy 或同名 `code.exe`。

## 开发环境

- Flutter **>=3.32.0**、Dart **>=3.8.0 <4.0.0**；CI 固定 Flutter **3.32.8**，以 `pubspec.yaml` 和 `pubspec.lock` 为准。
- Windows 桌面构建需要 Visual Studio 的 C++ 桌面工具链及 Windows SDK。
- 发布脚本需要 Python 3.9+（CI 使用 3.11）；Windows 安装程序需要 Inno Setup 6；上传远端还需 GitHub CLI 与仓库权限。

```powershell
flutter pub get
flutter run -d windows
```

本地构建后的入口为 `build/windows/x64/runner/Release/code.exe`。分发时保留整个 Release 目录及其 DLL、data 等依赖；仅复制 EXE 无法组成完整应用。

## 验证

```powershell
flutter analyze
flutter test
python -m unittest discover -s tests
python release.py --version 1.0.1 --build 2 --dry-run
```

只对本次修改的 Dart 文件执行 `dart format`。普通测试使用可注入的命令和进程，不依赖 Android 真机。覆盖范围及待执行的真机检查见 [测试与验收](docs/TESTING.md)，测试通过不能代替真机验收。

可选真实下载检查（联网并运行已校验工具的版本查询，不连接设备）：

```powershell
$env:MLINK_TOOLS_SMOKE = '1'
flutter test test/tool_environment_smoke_test.dart
Remove-Item Env:MLINK_TOOLS_SMOKE
```

现有 `file_picker` 依赖会输出桌面插件声明提示；静态分析结果和测试失败应分别如实记录，不通过跳过规则掩盖。

## 结构与协作

```text
lib/
  main.dart                       应用入口、导航和页面组装
  pages/                          现有界面
  app/modules/
    device_connection/            设备状态、信息读取、扫描和配对
    tools/                        私有运行环境、命令、设备/投屏会话
    screen_mirroring/             投屏配置
    file_manager/                 文件业务状态和服务
    screenshot/                   截图业务状态和服务
    settings/                     主题和更新服务
  datasources/                    设备进程数据源
  models/                         业务数据模型
  core/config/app_config.dart     应用版本、构建号与更新入口
  utils/                          设置持久化和有界日志
```

[架构边界](docs/ARCHITECTURE.md)说明命令入口和异步任务归属。贡献代码遵循 [AGENTS.md](AGENTS.md)，保留已有未提交修改，默认新分支使用 `codex/` 前缀，提交采用 Conventional Commits。审计原始发现与本轮处理记录见 [PROJECT_AUDIT.md](PROJECT_AUDIT.md)。

## 更新与发布

应用仅在用户点击“设置 → 关于 → 检查更新”时检查自身版本。先数值比较 `x.y.z`，再比较 build；Beta/Beta2 为预发布，不覆盖稳定更新入口。

完整流程见 [update.md](update.md)，配置在 `release_config.json`，工具为 `release.py`。通常先以 `--local-only` 准备并验证产物，提交推送对应源码后，使用同版本和显式构建号 `--skip-build` 上传；产物复用会验证源码指纹和检查记录。Release 先创建草稿，所有资产上传成功后才公开，最后更新稳定 `version.json`。预览不会构建、上传或创建远端 Release。

## 许可证

项目采用 [MIT License](LICENSE)，应用“关于”页与此一致。ADB、scrcpy、Flutter 及其他第三方组件遵循各自许可证；本项目许可证不替代它们的授权与声明。
