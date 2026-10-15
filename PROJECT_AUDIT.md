# 妙联（MLink）项目问题清单

排查日期：2026-10-14。基于当前工作区（包括已有未提交改动），本轮未修改业务源码。

## 第 1 阶段整改记录（2026-10-15）

本节记录审计后的整改；下文证据和行号保留为原始排查记录。F01–F05 已完成代码修复和自动化回归，仍需连接真实 Android 设备验收。

| 编号 | 处理结果 |
| --- | --- |
| F01 | push/pull 共用传输流，订阅后立即启动并同时消费 stdout/stderr；等待退出和输出处理完成后结束，非零退出及启动异常向上传递。取消订阅、释放服务及启动期间取消只终止对应传输进程。 |
| F02 | 文件列表、删除、创建、重命名、搜索统一使用 POSIX 单引号引用，Root 的整个命令再次引用为 su -c 的单个参数；处理单引号、空格、换行、双引号、变量和命令替换字符。删除、创建和重命名增加选项结束标记。 |
| F03 | 新增不可变 DeviceSession；主页面命令、进程监控与 Kill/Stop、设置操作绑定明确 serial，无设备时拒绝设备命令。投屏包名查询复用统一入口；断开连接显式指定当前设备。设备相关页面按 serial 重建，包名和设备信息避免展示上一设备的延迟结果。截图与文件服务也拒绝空 serial。 |
| F04 | 删除 taskkill /IM 与 killall。工具入口记录本应用启动且仍持有句柄的 ADB 客户端，清理只调用这些进程的 kill；共享 ADB 服务和其他程序的进程不纳入清理。设置说明同步调整。 |
| F05 | 监控失败不再切换 Mock，不用默认空值掩盖命令异常；清空失效监控数据、显示连接错误并允许刷新。Kill/Stop 只在成功读取真实数据后开放，确认和执行时再次检查状态，并使用监控所属设备会话。增加刷新重入及页面退出检查。 |

验证结果：

- `flutter pub get` 成功；仍有 file_picker 的 Linux/macOS/Windows 默认插件声明提示。
- 本次涉及的 Dart 文件已执行 `dart format`。
- `flutter test --no-pub`：24 项通过，1 项真实联网 smoke 按原配置跳过；其中本阶段新增 11 项回归测试，见 `test/phase_one_test.dart`。
- `python -m unittest discover -s tests`：4 项通过。
- `python release.py --version 1.0.1 --build 2 --dry-run`：预览成功，未执行构建、上传、推送或发布。
- `flutter analyze --no-pub`：退出码 1，31 项（2 warning / 29 info），无 error；仍有未使用声明/导入、弃用 API 和风格提示，未放宽规则。F17 尚未完成。

本阶段未接真机执行删除、安装、Kill/Stop 或双设备操作。后续真机验收应覆盖特殊字符文件名的上传下载及 Root 操作、断线恢复、双设备切换和共享 ADB 服务保留。F06–F20 继续按原阶段计划处理；本阶段的局部生命周期保护不代表 F06 已全面解决。

## 第 2 阶段整改记录（2026-10-15）

F06–F12 已完成代码整改与自动化验证。保留原有未提交改动，没有执行实际发布或连接真实 Android 设备。

| 编号 | 处理结果 |
| --- | --- |
| F06 | 短命令支持取消，包括启动期间取消与迟到进程回收；监控页面退出取消在途命令，避免继续执行后续读取。文件服务释放取消命令和传输，Cubit 关闭后不再更新状态或启动批量后续任务；目录和搜索共用请求代次，只接受最后一次结果。截图异常进入可显示的错误状态，连续截图失败停止定时器，退出后不再读取历史或 emit。截图改用 exec-out 直接获取 PNG，避免遗留远端临时文件。文件选择与确认操作补充 mounted 检查。 |
| F07 | 替换为固定工作池，最多 20 个并发连接。用户显式填写 IPv4 起止范围（最多 4096 个地址）和端口，保存后可用于下次自动扫描；支持停止扫描和关闭时取消。结果保存完整端点，不再把开放 TCP 端口直接认定为 ADB 设备。新增独立无线调试配对对话框，校验地址、配对端口与六位配对码；配对失败日志不记录配对码。 |
| F08 | copyWith 用 sentinel 区分省略参数与显式 null；传输成功、失败和退出均清理临时进度，新任务清理旧错误，失败在界面中明确显示。 |
| F09 | 用 find/stat 读取模式、大小、修改时间、目录类型及链接目标；元数据与原始路径以 NUL 分隔，避免空白分列和冒号锚点误判。检查退出码、权限和数据完整性，失败不再当作空目录；搜索使用相同元数据解析，链接目录可继续浏览。Root 浏览及文件操作继续支持，尚未实现提权的 push/pull 明确拒绝，不再静默执行普通权限传输。 |
| F10 | MirrorConfig 统一普通、摄像头、音频和单 App 投屏参数；临时码率/最大分辨率留空时回退默认值，校验后才启动。默认 DPI 用于单 App 虚拟显示，普通投屏保持设备本身 DPI；设置说明与此一致。物理键盘选项通过 scrcpy 参数实现，移除无依据的 secure setting 写入。启动和开启自动清理时调用安全的本应用客户端清理。 |
| F11 | MirrorSession 持有 scrcpy 进程，启动期间阻止重复启动，实时读取双通道日志，提供停止按钮，退出后可重启；关闭主页面释放自己的会话，启动期间停止也会终止迟到进程。短命令统一检查非零退出，启动及执行各有 30 秒超时，输出每个通道上限 16 MiB。文件传输和投屏走独立长任务入口，不套用短命令超时。 |
| F12 | 移除主输出区的双通道优先级，所有消息进入同一个按任务标记的日志队列；保留最多 500 条且合计最多 65536 字符，过长单条截断，读取时合并文本。新结果可见并自动滚动，文件操作不再随意清空其他任务日志，保留用户手动清空入口。 |

投屏参数依据：[scrcpy 画质选项](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md)、[虚拟显示尺寸与 DPI](https://github.com/Genymobile/scrcpy/blob/master/doc/virtual-display.md)。

验证结果：

- `flutter pub get` 成功；file_picker 的多平台默认插件声明提示仍存在。
- 本次涉及的 Dart 文件已格式化。
- `flutter test --no-pub`：44 项通过，1 项真实联网 smoke 按原配置跳过。本阶段新增 20 项测试，涵盖乱序响应、退出、传输错误恢复、扫描并发/取消、配置回退、超时、投屏会话、日志容量及界面操作。
- 另外实际运行本机 POSIX shell 验证文件元数据脚本及 Root 命令的嵌套引用（用普通 shell 函数模拟 su，不提权），并用本机回环套接字验证扫描端点和连接回收；这些检查不能代替 Android 真机兼容性验收。
- `python -m unittest discover -s tests`：4 项通过。
- `python release.py --version 1.0.1 --build 2 --dry-run`：预览成功，未执行构建、上传、推送或发布。
- `flutter analyze --no-pub`：退出码 1，26 项（1 warning / 25 info），无 error。剩余为既有弃用 API、未使用声明和风格问题，没有放宽规则；F17 留待第 3 阶段处理。

真机验收尚待执行：Android 文件权限与链接目录、特殊名称上传下载、Root 浏览与明确的传输限制、截图及连续截图断线恢复、非 5555 端口与无线配对、投屏实时日志/停止/重启。F13–F20 尚未在本阶段宣告完成。

## 第 3 阶段整改记录（2026-10-15）

F13–F17 已完成代码整改和本地验证。本阶段没有准备真实新版本、构建发行包、创建 Release、上传资产、提交或推送。

| 编号 | 处理结果 |
| --- | --- |
| F13 | 手动检查先验证缓存，再比较官方 tag/归档摘要，相同则不下载或更换目录。安装清单保存归档摘要和一个回退目录；切换失败回收新目录，损坏清单可修复。仅回收根目录中经本应用标记且不在保留列表的目录，未知目录及符号链接不纳入回收。根目录互斥锁与进程文件锁租约协调启动和回收，活跃目录跳过；最后才删除管理标记，系统占用导致的清理失败留待下次重试。 |
| F14 | 发布元数据直连 api.github.com，摘要缺失时 SHA256SUMS 也直连官方，不再通过同一代理获取校验依据。ZIP 仍可走配置的加速源；校验失败发生在执行版本验证之前。官方不可达时保留有效旧环境，不回退到代理元数据。Windows 私有环境未就绪时明确报错，避免隐式落回系统 PATH。 |
| F15 | 构建号单独比较，不再因版本号升高而接受相同或更低 build；本地核对当前源码、稳定清单及历史。相同准备版本的重试必须显式指定同一 build。正式上传还通过远端已公开 Release（含 Beta）的标签源码核对最大 build，旧记录无法读取/解析时拒绝上传；只读预览保持不联网。 |
| F16 | skip-build 先验证 schema 2 的版本、源码指纹、构建工具链和资产哈希，默认补做全部严格检查，即使本地构建时跳过过检查。artifacts.json 保存构建工具链、检查状态及检查对应指纹，检查失败不更新为 passed、不创建 Release。显式 skip-checks 仅对当前命令生效并记录 skipped_explicitly。检查及构建中检测源码变化，上传前再校验指纹与哈希；旧记录要求重建。 |
| F17 | 修复既有弃用 Color API、字符串拼接、构造参数、布局和未使用声明等分析项，保留严格规则与原有 CI 检查顺序。全仓 analyze 返回 0，原有分析问题已不再阻断默认检查。 |

验证结果：

- `flutter pub get` 成功；本次修改的 Dart 文件已格式化。
- `flutter analyze --no-pub`：No issues found，退出码 0。
- `flutter test --no-pub`：50 项通过，1 项真实联网 smoke 按原配置跳过；本阶段新增 6 项运行环境回归测试。
- `python -m unittest discover -s tests`：14 项通过，新增 10 项覆盖构建号、远端 Beta 构建上限、产物复用补做检查、检查失败阻断发布和来源记录。
- 缓存回收额外使用真实独立子进程持有文件锁验收：持锁时保留目录，退出后可回收；临时文件均位于测试专用目录。
- `python release.py --version 1.0.1 --build 2 --dry-run`：预览成功。更高版本但仍使用 build 1 的预览被回归测试确认拒绝，预览不修改文件或调用远端。

远端发布核对在测试中使用模拟响应，没有执行真实上传。file_picker 的多平台插件声明提示仍存在；未验证真实 Windows 安装包、真实工具进程占用和 Android 设备操作，也未触发远端 CI。发布说明已同步到 update.md。F18–F20 留待下一阶段综合处理，已有业务回归和模块拆分不等于这些项目全部完成。

## 结论与边界

共整理 20 项：5 项 P1、12 项 P2、3 项 P3。P1 表示核心功能故障或可能误操作；P2 表示一般功能缺陷、发布阻断或需要整改的设计风险；P3 表示维护与一致性问题。优先级不等于漏洞评级。

本轮执行结果：flutter analyze 35 项（3 warning / 32 info），退出码 1；13 项普通 Flutter 测试通过，真实联网 smoke 默认跳过；4 项 Python 测试通过。现有工作区不能仅凭这些测试视为核心功能已验证。

没有连接真实 Android 设备执行安装、删除、Kill 或 Stop。本轮系统 PATH 中的 adb help 因 Windows 要求提升权限未能启动，未绕过权限；上轮私有运行环境下载与版本检查已通过，但本轮业务问题主要由源码和最小复现确认。没有执行发布、推送或进程清理。

## 优先处理

| 编号 | 优先级 | 问题 | 确认方式 |
| --- | --- | --- | --- |
| F01 | P1 | 文件上传/下载可能永久卡住 | 确认并最小复现 |
| F02 | P1 | 远端 shell 参数转义不完整 | 源码确认 |
| F03 | P1 | 当前设备选择没有贯穿所有操作 | 源码确认 |
| F04 | P1 | ADB 清理会误伤其他程序 | 源码确认 |
| F05 | P1 | Mock 进程仍可执行真实 Kill/Stop | 源码确认（条件触发） |
| F06 | P2 | 异步任务与页面生命周期脱节 | 源码确认 |
| F07 | P2 | 局域网扫描的并发限制无效 | 源码确认 |
| F08 | P2 | 传输进度和错误无法清空 | 源码确认 |
| F09 | P2 | 文件浏览会把失败当空目录，元数据不准确 | 源码确认 |
| F10 | P2 | 默认投屏配置没有真正生效 | 源码确认 |
| F11 | P2 | 长运行进程没有会话管理 | 源码确认 |
| F12 | P2 | 双日志通道会遮挡新结果且无限增长 | 源码确认 |
| F13 | P2 | 运行环境更新会反复下载并积累目录 | 源码确认（设计缺陷） |
| F14 | P2 | 运行包校验依赖同一个代理的信任 | 设计风险，未发现篡改 |
| F15 | P2 | 发布脚本不保证构建号全局递增 | 已用 dry-run 复现 |
| F16 | P2 | 复用产物会绕过默认发布检查 | 源码确认 |
| F17 | P2 | 默认 CI 和发布流程当前被阻断 | 本轮检查确认 |
| F18 | P3 | 测试偏重新增基础设施，核心功能缺回归 | 测试目录确认 |
| F19 | P3 | 状态与命令入口分散，维护成本高 | 设计问题 |
| F20 | P3 | 开发环境、平台与品牌文档不一致 | 文件核对确认 |

## 逐项说明

### F01 · P1 · 文件上传/下载可能永久卡住

**证据位置：** [lib/app/modules/file_manager/services/adb_file_service.dart](lib/app/modules/file_manager/services/adb_file_service.dart#L249)；pull 同样在 288 行

push/pull 在 yield* controller.stream 建立订阅之前先 await controller.close()。单订阅流的 close 需等 done 被消费，执行到这里后永远无法订阅；即使外部 adb 已完成或失败，界面与批量任务仍等不到结束。应先转发流，统一管理进程退出、输出订阅与流关闭，支持取消。

### F02 · P1 · 远端 shell 参数转义不完整

**证据位置：** [lib/app/modules/file_manager/services/adb_file_service.dart](lib/app/modules/file_manager/services/adb_file_service.dart#L329)

文件路径只替换双引号，搜索 query 直接插入双引号包围的 shell 字符串，$()、反引号等仍会被 Android shell 解释。包含这些字符的文件名/搜索词可能触发额外命令，删除涉及 rm -rf 时影响更严重。Root 模式又将已含引号的命令直接套入 su -c，含空格路径会被破坏。需统一远端 POSIX 参数引用；本地 Process 的参数列表不能替代远端 shell 转义。

### F03 · P1 · 当前设备选择没有贯穿所有操作

**证据位置：** [lib/datasources/adb_process_data_source.dart](lib/datasources/adb_process_data_source.dart#L67)；[lib/main.dart](lib/main.dart#L615)

进程数据源保存了 runCommand 回调却不使用，直接运行不带 -s 的 adb；设置页也绕过 selectedDevice。多设备时会报错，继承 ANDROID_SERIAL 时还可能读取另一台设备；进程 Kill/Stop 则走主页面所选设备。需统一 DeviceSession 与命令执行入口，所有读写使用明确 serial，监控数据与操作绑定同一设备。

### F04 · P1 · ADB 清理会误伤其他程序

**证据位置：** [lib/main.dart](lib/main.dart#L277)

Windows 直接 taskkill /F /IM adb.exe /T，Linux/macOS 使用 killall -9 adb。会结束 Android Studio、其他投屏工具及用户启动的 ADB，违背项目进程管理约定。改为只管理可确认归属的进程/连接，避免按名字全局终止。

### F05 · P1 · Mock 进程仍可执行真实 Kill/Stop

**证据位置：** [lib/pages/app_management_page.dart](lib/pages/app_management_page.dart#L164)；[lib/pages/app_management_page.dart](lib/pages/app_management_page.dart#L823)

刷新异常时自动切换 Mock 数据；表格仍开放 Kill/Stop 并发出真实 adb 命令。若虚构 PID 恰好对应真实进程，且设备允许终止，会操作无关进程。模拟模式必须明确隔离并禁用真实写操作；连接故障不应自动用虚构数据替代真实状态。

### F06 · P2 · 异步任务与页面生命周期脱节

**证据位置：** [lib/pages/app_management_page.dart](lib/pages/app_management_page.dart#L120)；[lib/app/modules/screenshot/bloc/screenshot_cubit.dart](lib/app/modules/screenshot/bloc/screenshot_cubit.dart#L49)

监控刷新 await 后直接 setState；退出页面只取消 Timer，不取消在途请求。截图 capture 的异常会 rethrow，但定时器与快捷键调用未 await/catch，Cubit 关闭后还有 emit 风险。文件管理 loadPath 也无请求序号：快速切换目录时旧响应能覆盖新目录列表。需 mounted/isClosed 检查、错误收敛、取消机制与请求代次。

### F07 · P2 · 局域网扫描的并发限制无效

**证据位置：** [lib/main.dart](lib/main.dart#L347)

Future.any 返回任意完成任务，但 removeAt(0) 移除的是首任务，不一定是完成任务。已完成 Future 留在列表会让后续等待立即返回，实际连接数量可超过 maxConcurrent=20。扫描还固定 5555 并按 IPv4 前三段推断 /24，忽略用户端口、实际网段和配对式无线调试。使用固定工作池，显式扫描范围/端口；配对连接另建流程。

### F08 · P2 · 传输进度和错误无法清空

**证据位置：** [lib/app/modules/file_manager/bloc/file_manager_state.dart](lib/app/modules/file_manager/bloc/file_manager_state.dart#L58)

copyWith 用 progress ?? this.progress、errorMessage ?? this.errorMessage，不能区分“保持”与“设为 null”。Cubit 的 finally 中 progress:null 实际不清空，错误信息也可能沿用。修复传输卡死后仍会出现进度条残留。采用 sentinel 或显式 clearProgress/clearError。

### F09 · P2 · 文件浏览会把失败当空目录，元数据不准确

**证据位置：** [lib/app/modules/file_manager/services/adb_file_service.dart](lib/app/modules/file_manager/services/adb_file_service.dart#L77)；[lib/app/modules/file_manager/services/adb_file_service.dart](lib/app/modules/file_manager/services/adb_file_service.dart#L175)

ls 未检查退出码，stdout 为空即返回 []，权限拒绝等错误被显示为空目录。解析使用空白拆分再拼接文件名，会改变连续空格或误识别含冒号名称；modifiedTime 全部使用 DateTime.now()。search 依据路径是否以 / 结尾判断目录，但 find 通常不这样标记。Root push/pull 的 useRoot 参数也未实现。需区分错误、改用可可靠解析的元数据输出，并明确 Root 能力边界。

### F10 · P2 · 默认投屏配置没有真正生效

**证据位置：** [lib/main.dart](lib/main.dart#L122)；[lib/pages/screen_mirroring_page.dart](lib/pages/screen_mirroring_page.dart#L94)

默认码率/分辨率/DPI 只加载到设置控制器，没有传给普通“开始投屏”；临时画质按钮使用另一组初始为空的控制器，空值会构造无效参数。自动清理设置宣称每次启动执行，但启动仅加载开关，只有开启开关时立即清理。应建立统一配置对象，临时设置覆盖默认值，校验输入，并让说明与行为一致。

### F11 · P2 · 长运行进程没有会话管理

**证据位置：** [lib/app/modules/tools/services/tool_process.dart](lib/app/modules/tools/services/tool_process.dart#L8)

主页面通过收集完整输出的调用运行 scrcpy，要等投屏退出才显示其输出；没有持有进程句柄、实时日志、停止按钮、重复启动约束。一般 ADB 调用也缺少超时和退出码的统一错误处理。区分短命令与投屏会话；会话采用 Process.start、流式输出及明确的生命周期。

### F12 · P2 · 双日志通道会遮挡新结果且无限增长

**证据位置：** [lib/main.dart](lib/main.dart#L755)；[lib/utils/app_output.dart](lib/utils/app_output.dart#L7)

输出区优先显示 appOutputNotifier 非空内容，而 runCommand 等只更新局部 output。查看过文件管理日志后，新命令的结果可能被旧日志遮挡。全局字符串追加无上限，还对大段字符串反复复制。统一日志模型，按任务区分消息并设置缓冲上限。

### F13 · P2 · 运行环境更新会反复下载并积累目录

**证据位置：** [lib/app/modules/tools/services/tool_environment.dart](lib/app/modules/tools/services/tool_environment.dart#L247)

强制更新不比较当前 tag/digest，即使 latest 未变化也下载并新建 tag+时间戳目录。旧环境和失败后遗留的已移动目录没有回收策略；反复点击更新会持续占用磁盘。先比较版本和校验和，保留当前及必要回退版本，确认未使用后回收。

### F14 · P2 · 运行包校验依赖同一个代理的信任

**证据位置：** [lib/app/modules/tools/services/tool_environment.dart](lib/app/modules/tools/services/tool_environment.dart#L303)

元数据/API、校验和及压缩包都优先经过同一第三方代理。若代理同时替换元数据和内容，SHA256 仍可匹配；当前“官方校验”证明内容一致，不能独立证明来源。校验通过后还会执行版本检查。建议从可信官方通道读取摘要或验证固定可信密钥的签名，代理只传输大文件。此项不是对当前加速源已被攻击的判断。

### F15 · P2 · 发布脚本不保证构建号全局递增

**证据位置：** [release.py](release.py#L119)

比较顺序为 version 在前、build 在后，因此当前 1.0.0+1 时 --version 1.0.1 --build 1 被接受。版本号增大时也能降低 build，不符合项目约定；可选 Android 产物会遇到 versionCode 升级问题。新发布独立要求 build > 已发布构建号；同次重试走显式复用逻辑。

### F16 · P2 · 复用产物会绕过默认发布检查

**证据位置：** [release.py](release.py#L171)

analyze/test 仅位于非 skip-build 分支。按推荐 local-only → skip-build 流程，若本地阶段使用了 skip-checks，最后上传即使未指定 skip-checks 也不会补做检查。artifacts.json 未记录检查通过状态。应记录检查结果、源码指纹和工具链，正式上传强制验证，或明确要求显式跳过检查。

### F17 · P2 · 默认 CI 和发布流程当前被阻断

**证据位置：** [.github/workflows/ci.yml](.github/workflows/ci.yml#L23)；[release.py](release.py#L198)

flutter analyze 返回退出码 1，共 35 项：3 个 warning、32 个 info、无编译级 error。严格 CI 在这里停止，后续测试不运行；默认 local-only 构建也停止。应逐项修复已有问题，保持严格规则，不依赖长期 skip-checks。

### F18 · P3 · 测试偏重新增基础设施，核心功能缺回归

**证据位置：** [test/tool_environment_test.dart](test/tool_environment_test.dart#L1)

13 项普通 Flutter 测试与 4 项 Python 测试通过，但没有覆盖文件传输、远端引用、多设备选择、监控异常与页面退出。真实环境 smoke 默认跳过。测试全绿无法说明核心业务可用，F01 就未被发现。优先建立可注入命令执行器和业务服务测试，保留少量真机验收。

### F19 · P3 · 状态与命令入口分散，维护成本高

**证据位置：** [lib/main.dart](lib/main.dart#L55)；[lib/app/modules/file_manager/bloc/file_manager_cubit.dart](lib/app/modules/file_manager/bloc/file_manager_cubit.dart#L12)

main 同时管理设备、扫描、配置、信息查询、命令、页面和输出，部分模块 BLoC，部分直接 setState；数据源还有传入但不使用的回调。统一 ToolProcess 已解决工具路径，但尚未统一设备、错误、取消和日志。建议逐步引入 DeviceSession、CommandRunner、MirrorSession，按模块拆分，避免一次性全仓重构。

### F20 · P3 · 开发环境、平台与品牌文档不一致

**证据位置：** [pubspec.yaml](pubspec.yaml#L6)；[README.md](README.md#L151)；[lib/pages/settings_page.dart](lib/pages/settings_page.dart#L523)

README 宣称 Flutter 3.13 / Dart 2.17，而当前 lock 要求 Flutter >=3.32 / Dart >=3.8；README 声称 MIT 且链接 LICENSE，关于页写 Apache 2.0，工作区未找到许可证文件；ADB 手动路径设置说明也与当前界面不一致。Windows 名称仍 code.exe，Android 保留 com.example.code 和调试签名。统一实际支持矩阵、工具链、品牌和由维护者确认的许可证；Android 未完成正式发行准备。

## 最小复现与外部依据

F01：构造一个单订阅 StreamController，添加事件后调用 close；未订阅前其 Future 不完成，随后订阅才完成。本轮实际输出为：

```text
close completed before stream subscription: false
close completed after stream subscription: true
```

这与源码先 await close、再 yield* 的顺序一致。[Dart 官方 close 文档](https://api.dart.dev/dart-async/StreamController/close.html) 明确说明无订阅者时可能永不完成。

F15：本轮执行以下只读预览，当前 1.0.0+1 下脚本仍生成 1.0.1+1 的发布计划，证明未单独要求构建号递增：

```powershell
python release.py --version 1.0.1 --build 1 --dry-run
```

补充核对：[ADB 官方命令实现](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/commandline.cpp) 中 -p 为兼容旧版本而忽略，push 的 -a 也未传给实际同步调用。因此本报告没有把这些旧参数本身误判为“必然无法传输”的原因，F01 的等待顺序才是明确阻断点。

## 建议整改顺序

1. 先处理 F01–F05：传输可结束、远端参数安全、操作目标一致、避免全局清理、隔离 Mock 写操作。
2. 然后处理 F06–F12：异步生命周期、扫描并发、状态清空、文件浏览和配置、进程与日志管理。
3. 完善 F13–F17：运行环境更新策略、可信校验、发布构建号、检查记录及 CI。
4. 按 F18–F20 补业务回归测试，再逐步整理架构与文档。

修复后至少验收：双设备切换、包含特殊字符的文件名、上传下载成功与失败、离开页面时任务完成、断网恢复、重复更新、构建号回退拒绝和完整发布预览。


## 第 4 阶段处理记录（2026-10-15）

本节记录 F18–F20 的实施结果，前文保留为整改前的审计证据。

- **F18：已补自动化覆盖，真机验收待执行。** 新增 `test/phase_four_test.dart` 的 11 项回归：命令参数解析、退出码与取消、设备目标约束、信息解析、A→B→A 切换、包名查询乱序、设备掉线、关闭取消、扫描取消与重试、刷新乱序，以及主页面选择设备/加载偏好/启动停止投屏和设置命令绑定。结合前阶段传输、远端名称、监控异常、页面关闭等测试形成覆盖矩阵；见 `docs/TESTING.md`。未把模拟进程测试当作真机完成证明。
- **F19：完成渐进拆分。** 新增 CommandRunner、DeviceInfoService 和 DeviceConnectionCubit，主页面保留导航和页面组装。短命令统一处理退出码、编码及取消，DeviceSession 约束目标；设备模块集中管理信息、查询和扫描，旧请求不能覆盖新状态。流式传输、截图二进制与 MirrorSession 保留各自生命周期。修复投屏页面漏传关闭屏幕/禁用音频设置，复用并释放命令输入与截图间隔控制器，修正前台应用只识别 com 包名的问题。剩余设置回调和页面状态后续按模块逐步整理，见 `docs/ARCHITECTURE.md`。
- **F20：已统一。** 按维护者明确选择添加 MIT `LICENSE`，关于页统一为 MIT，发布打包目录附带 LICENSE。pubspec 明确 Flutter >=3.32.0 / Dart >=3.8.0，移除无调用的 process_run 依赖。README 同步实际工具链、支持矩阵、缓存/校验策略和功能边界，保留 Windows `code.exe`；同步 Android 显示名和 Windows 产品信息。Android 仍为 `com.example.code` 与调试签名，不宣称正式发行。

验证：`flutter pub get` 成功；本次 Dart 文件格式检查通过；`flutter analyze` 零问题；Flutter 61 项通过、1 项真实网络 smoke 按默认条件跳过；Python 14 项通过；`python release.py --version 1.0.1 --build 2 --dry-run` 成功，仅输出发布计划。现有 file_picker 的桌面插件声明提示仍存在，未删除规则或掩盖提示。

未执行：真实 Android 设备验收、真实 latest 下载 smoke、Windows 原生构建/安装验收、远端 CI、提交推送和远端发布。待验收清单及安全测试目录要求见 `docs/TESTING.md`；本地源码修改不等于已发布。


## 发布准备验证（2026-10-15）

维护者已明确要求提交更新并发布。准备版本为 1.0.1+2，Windows 安装程序和完整便携 ZIP 已完成本地构建，许可证与必要运行文件检查通过；Windows 原生窗口标题同步为妙联，可执行文件仍为 code.exe。

另行启用真实网络 smoke：scrcpy 官方 latest v5.0.1 下载、官方摘要校验、归档解压、ADB / scrcpy 版本执行和离线恢复均通过。本项补充前阶段默认跳过的网络检查，不代表连接 Android 真机验收。

仍未执行：真实 Android 设备兼容性、干净系统安装/卸载与跨平台发行验收。发布说明明确记录这些边界。
