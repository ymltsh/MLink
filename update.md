# 妙联更新发布体系

参考 Mfuns-Flutter/update.md 的清单协议与 Windows 打包流程，按 MLink 桌面工具适配。

## 更新接口

- 原始清单：https://raw.githubusercontent.com/ymltsh/MLink/main/version.json
- 应用读取：https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/MLink/main/version.json
- 发布页：https://github.com/ymltsh/MLink/releases/latest

启动不检查；“设置 → 关于 → 检查更新”才读取清单。先按三段数值比较版本，版本相同再比较 build。
有更新展示说明和当前平台下载按钮，无对应产物可打开发布页；错误提示并可点击重试。
链接只接受 HTTPS，网络总超时 15 秒。下载按钮通过系统浏览器打开，不自动安装。

`version.json` 使用 `latest` 和 `history`。latest 必填 version（x.y.z）、build（正整数）、name；
可选 date、notes、urls、page。urls 支持 windows、windows_portable、android。
首次初始化没有虚构下载链接，首次正式发布后由工具写入真实链接。
应用源码版本由发布工具同步到 `pubspec.yaml` 与 `lib/core/config/app_config.dart`；稳定清单以最后一次公开发布为准，旧关于页的 1.0.5 不作为已发布版本依据。

## 前置条件

- Python 3.9+（CI 使用 3.11）、Flutter 3.32.8 与 Windows C++ 桌面工具链。
- 安装 Inno Setup 6，ISCC.exe 在 PATH 或设置 `INNO_SETUP_COMPILER`。
- Flutter 不在 PATH 时设置 `FLUTTER_BIN`。
- 上传需 GitHub CLI，执行 `gh auth login`；Git 推送凭据需可写 `ymltsh/MLink`。
- `release_config.json` 固定 repo、main 分支、品牌、产物前缀与现有 `code.exe` 名称。
- 构建前手动关闭本应用；工具不终止 `code.exe`，避免误伤同名进程。
- 安装包不内嵌 ADB / scrcpy；Windows x64 首次运行从官方 latest 补全环境。版本元数据及必要的 SHA256SUMS 直连官方，只有 ZIP 默认通过 `https://hub.wgen.top/` 加速。官方校验信息不可达时不改用代理提供的摘要；已有有效环境仍可离线使用。macOS/Linux 暂使用系统安装的工具。

手动检查最新环境时先验证本地缓存，再比较官方 tag 和 ZIP 摘要；二者未变化就复用当前目录，不重复下载。
安装使用独立目录及原子清单切换，失败保留旧环境，并回收尚未切换成功的新目录。
回收仅处理本应用标记且位于缓存根目录内的目录，保留当前版本和一个回退版本。
工具进程持有文件锁租约直到退出，回收会跳过仍在使用的目录；无法清理的文件留待下次检查重试。
旧缓存只有在完整校验后才纳入本应用回收范围，未知目录不会删除。

## 推荐发布流程

源码提交单独处理。先准备本地版本和产物，检查后提交推送源码，再上传同一批产物。

```powershell
python release.py --version 1.0.1 --build 2 --dry-run
python release.py --version 1.0.1 --build 2 --notes '更新说明' --local-only
# 检查源码、配置和版本改动，提交并推送 main 后：
python release.py --version 1.0.1 --build 2 --notes '更新说明' --skip-build
```

无参数 `python release.py` 可交互填写版本、构建号、类型和多行说明。
交互正式上传同样要求版本已同步且源码已提交推送；准备新版本使用上面的 local-only 命令。
发布工具顺序：同步版本 → pub get → analyze / Flutter 测试 / Python 测试 →
Windows 构建 → 便携 ZIP → Inno 安装包 →（可选 APK）→ 草稿 Release → 上传全部资产与 SHA256SUMS →
公开 Release → 更新稳定 version.json → 仅提交清单并推送 main。

上传前要求工作区干净、HEAD 与 origin/main 一致、版本与命令参数相同。
Release tag 指向构建的源码提交，避免标签指向旧源码。复用文件核对 artifacts.json 内版本、源码指纹及 SHA256；构建后若源码或配置变化，须重新构建。

构建号独立于版本号递增，须高于稳定清单及历史中的最大构建号，且不得低于当前源码构建号。
只有相同的已准备版本和构建号可通过显式 `--build` 重试；升级版本号时不能复用旧构建号。
实际上传还会读取远端全部已公开 Release（包括 Beta）的标签源码，核对最大构建号；无法读取或解析旧版本记录时拒绝上传。
`--dry-run` 只验证本地边界，不联网核对远端，因此预览成功不代表远端发布检查已完成。

`--skip-build` 默认重新执行 analyze、Flutter 测试及 Python 测试，不继承本地构建时的 `--skip-checks`。
检查失败不会创建 Release，也不会把检查标记成通过。跳过检查必须在当前这次命令中再次明确指定 `--skip-checks`。
schema 2 的 artifacts.json 记录构建工具链、检查状态和对应源码指纹；旧 schema 缺少这些信息，必须重新构建。
检查或构建期间源码发生变化会失败；上传前还会再次校验源码和资产哈希。

| 参数 | 作用 |
| --- | --- |
| --version / --build | 版本号与构建号；构建号缺省当前+1，重复运行须显式指定 |
| --name / --notes / --notes-file | 标题、说明或 UTF-8 说明文件 |
| --beta / --beta2 | tag 与文件名加后缀，创建预发布，不更新稳定清单 |
| --android | 附加 APK；当前 Android 工程使用调试签名，需要独立规划正式签名 |
| --dry-run | 打印计划，不改文件、不构建、不读取凭据、不访问远端 |
| --local-only | 同步版本并只构建本地产物，不发布或改稳定清单 |
| --skip-build | 按精确版本与构建号复用已校验产物 |
| --skip-checks | 显式跳过检查，需自行确认并记录原因 |
| --no-push | 仍创建远端 Release、写本地清单，但不提交推送 |

## 产物与安装

产物在 `build/releases/<version[-beta|-beta2]>+<build>/`：

- `mlink-setup-<version[-suffix]>.exe`：当前用户安装至 `%LOCALAPPDATA%\Programs\MLink`，无需管理员权限。
- `mlink-windows-<version[-suffix]>.zip`：完整 Windows Release 目录，排除旧 ZIP 与 PDB。
- `mlink-<version[-suffix]>.apk`：仅 --android 时提供。
- `artifacts.json`：本地版本、源码及资产哈希、构建工具链和检查记录，不上传。
- `SHA256SUMS.txt`：随 Release 上传校验和。

安装程序创建开始菜单快捷方式、可选桌面快捷方式并注册卸载项。
macOS/Linux 暂无自动打包发布，更新弹窗仍可访问发布页。

## 失败恢复与验证

- 构建失败：版本可能已经同步，修复后使用相同 --version / --build 重跑 local-only。
- 上传失败：保留草稿；清单不会提前更新。使用 gh release upload 补全全部产物与校验和，再公开草稿并手动同步清单；或删除失败草稿后重跑。
- 已存在同名 Release：工具拒绝覆盖。新的同版本构建须使用不同版本 tag，或维护者手动处理原 Release。
- 公开成功但推送失败：Release 已存在，勿盲目重跑；检查本地 version.json 和 Git 提交后补推送。
- Beta/Beta2 仅供手动下载；正式版 build 高于已有 beta build，稳定检查入口不分发测试版本。

2026-10-15 本地验证：全仓 analyze 已无问题，严格 CI 与默认发布检查不再被原有分析项阻断。
file_picker 6.x 仍输出桌面插件声明提示，需后续独立评估升级；没有通过放宽分析规则隐藏问题。

发布后检查加速清单的版本、构建号和三个（或两个）资产地址，可能存在代理缓存延迟。
手动验证旧版发现更新、同版无更新、断网重试、窗口销毁期间请求完成、窄窗口内容滚动和下载按钮。
每次正式发布必须确认 Windows 安装与卸载、便携启动，以及 ADB / scrcpy 的实际设备操作。
