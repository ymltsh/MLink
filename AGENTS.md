# 妙联（MLink）项目协作约定

## 项目定位与结构
- Flutter 桌面端屏幕互联工具，使用 ADB / scrcpy；主要发布目标是 Windows x64。
- Dart 包名为 `adb_tool`，Windows 二进制仍为 `code.exe`，勿凭品牌名猜测可执行文件名。
- `lib/pages/` 为现有页面，`lib/app/modules/` 按业务组织状态与服务；新增业务优先放对应模块。
- `lib/datasources/` 与 `lib/models/` 管理设备数据；外部命令调用与界面展示分离。
- `lib/core/config/app_config.dart` 管理应用版本与更新接口。
- 本文档以实际源码为准，README 中部分宣传、目录与协议描述可能尚未同步。

## 开发约定
- 使用简体中文沟通、文档和用户提示；保持现有 Material / BLoC 风格。
- 修改前检查 `git status`，保留用户未提交改动，不覆盖、回滚或自动提交无关文件。
- Dart 文件使用 `dart format`，只格式化本次涉及的文件，不全仓格式化。
- 异步操作检查 mounted，释放控制器、网络客户端与子进程资源。
- 执行 ADB / scrcpy 使用独立参数列表，不将用户输入拼接进 shell 命令。
- 不结束所有 `code.exe`、ADB 或 scrcpy 进程；只管理能明确识别为本应用启动的进程。
- 不提交设备标识、访问令牌、签名密钥、机器路径与构建产物。
- 新分支默认 `codex/` 前缀，提交消息采用 Conventional Commits。

## 验证
```powershell
flutter pub get
dart format <本次修改的 Dart 文件>
flutter analyze
flutter test
python -m unittest discover -s tests
python release.py --version 1.0.1 --build 2 --dry-run
```
- 为版本比较、清单校验、更新交互和发布流程编写有意义的回归测试。
- 现有分析问题须如实报告，不通过删除规则或默认跳过检查掩盖。
- Windows 构建依赖 Visual Studio C++ 桌面工具链；安装程序需 Inno Setup 6。

## 更新与发布
- 遵循 `update.md`；配置见 `release_config.json`，工具为 `release.py`。
- `pubspec.yaml` 与 AppConfig 版本、构建号一致；稳定 `version.json` 表示已发布版本，可在本地准备新版时落后。
- 构建号递增，重试显式使用同一 `--build`，不要依赖自动加一。
- 应用自身版本检查仅用户点击“设置 → 关于 → 检查更新”时联网；数值比较 x.y.z，再比较 build。
- Windows x64 首次运行自动从 scrcpy 官方 latest 补全 ADB / scrcpy，默认 `https://hub.wgen.top/` 加速；后续验证并复用本地缓存，不在每次启动追踪 latest。
- 所有 ADB / scrcpy 执行必须经过 `lib/app/modules/tools/services/tool_process.dart`，使用私有运行环境的绝对路径与子进程环境，不修改系统 PATH。
- 运行环境安装需先校验官方 SHA256、拒绝不安全归档路径，再验证可执行文件；更新失败保留旧环境，避免覆盖正在使用的文件。
- Windows 默认发布安装程序和便携 ZIP；Android 通过 `--android` 选择，目前调试签名，不作为正式手机发行方案。
- Beta/Beta2 创建预发布 Release，不覆盖稳定更新入口；不迁移参考项目的星座彩蛋规则。
- 默认先 `--local-only` 准备版本和产物，再提交推送源码，最后同版本 `--skip-build` 上传。
- Release 先创建草稿、全部资产上传成功后公开，最后写入并只提交 `version.json`。
- 生成发布工具不等于执行发布。只有用户任务包含实际发布意图时，才创建远端 Release、推送或上传产物。
