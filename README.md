# 🔧 妙联 - 超轻量化跨平台屏幕互联工具

> **基于adb协议，让手机与电脑真正无差别互联。轻量、流畅、跨品牌。**

## 🚀 项目简介

**妙联**是一款基于 Flutter 打造的**超轻量级、跨平台屏幕互联工具**，专为解决各家手机厂商在电脑端互联体验割裂的问题而设计。
它通过 ADB 作为底层通道，无需用户学习任何命令，即可实现**稳定、清晰、低延迟的手机屏幕投射与操控**。

相比臃肿复杂的厂商互联套件，妙联专注于提供：

* 🎯 **一致的跨品牌体验**：无论是小米、华为、OPPO、vivo 还是三星，都能获得统一顺滑的镜像体验
* ⚡ **极简操作流程**：插上手机即可镜像，无需账号、无需生态绑定、无需繁琐配置
* 🪶 **轻量快速**：资源占用低、启动快、界面简洁优雅
* 🔄 **跨平台支持**：兼容 Windows / macOS / Linux，多端统一体验

妙联的目标不是成为一款 ADB 工具箱，而是**让所有用户都能轻松地在电脑上操控手机，实现真正意义上的轻量化屏幕互联**。

## ✨ 功能特性

### 🔌 设备连接管理
- **有线/无线连接**：支持USB和Wi-Fi两种连接方式
- **自动扫描**：自动发现局域网内的Android设备
- **历史记录**：保存常用设备连接信息，快速重连
- **设备信息**：显示设备型号、Android版本等详细信息

### 📱 屏幕镜像与投屏
- **实时投屏**：使用scrcpy实现高质量屏幕镜像
- **画质调节**：支持码率、分辨率等参数自定义
- **单应用投屏**：仅投屏指定应用，多开挂机
- **录制功能**：支持屏幕录制和音频投送
- **键盘HID**：支持通过ADB发送键盘事件，将电脑键盘作为手机的实体键盘

### 📦 应用管理
- **应用列表**：查看设备上安装的所有应用
- **应用操作**：安装、卸载、启动、停止应用
- **包名查询**：快速搜索和定位特定应用
- **权限管理**：查看和管理应用权限

### 📁 文件管理器
- **文件浏览**：浏览设备文件系统
- **文件传输**：支持文件上传和下载
- **批量操作**：支持多文件选择和操作
- **权限管理**：处理文件权限问题

### ⚙️ 设备操作
- **截图功能**：快速截取设备屏幕
- **系统设置**：调整设备显示、输入等设置
- **ADB命令**：支持自定义ADB命令执行
- **日志查看**：实时查看设备日志信息

## 🛠️ 技术栈

### 前端技术
| 技术 | 版本 | 说明 |
|------|------|------|
| **Flutter** | 3.13+ | 跨平台UI框架 |
| **Dart** | 2.17+ | 编程语言 |
| **Material Design** | 最新 | UI设计规范 |

### 状态管理
| 技术 | 版本 | 说明 |
|------|------|------|
| **flutter_bloc** | ^8.1.3 | BLoC状态管理 |
| **bloc** | ^8.1.4 | BLoC核心库 |
| **equatable** | ^2.0.5 | 值比较工具 |

### 核心依赖
| 依赖 | 版本 | 功能 |
|------|------|------|
| **process_run** | ^0.13.2 | 进程执行管理 |
| **shared_preferences** | ^2.2.2 | 本地数据存储 |
| **file_picker** | ^6.1.1 | 文件选择器 |
| **path_provider** | ^2.1.5 | 路径管理 |

### 架构特色
- **MVVM架构**：采用BLoC模式实现清晰的业务逻辑分离
- **响应式设计**：支持主题切换和暗色模式
- **模块化设计**：功能模块独立，便于维护和扩展
- **跨平台兼容**：一套代码多端运行

## 📁 项目目录结构

```
lib/
├── main.dart                    # 应用入口文件
├── app/                        # 应用核心模块
│   ├── modules/               # 功能模块
│   │   ├── settings/         # 设置模块
│   │   │   └── bloc/        # 设置状态管理
│   │   └── screenshot/       # 截图模块
│   └── theme/                # 主题配置
├── blocs/                    # 业务逻辑层
├── controllers/              # 控制器层
├── enums/                   # 枚举定义
│   ├── page_category.dart   # 页面分类枚举
│   └── page_category2.dart  # 扩展页面分类
├── models/                  # 数据模型
├── pages/                   # 页面组件
│   ├── device_connection_page.dart    # 设备连接页面
│   ├── screen_mirroring_page.dart     # 屏幕镜像页面
│   ├── app_management_page.dart       # 应用管理页面
│   ├── file_manager_page.dart         # 文件管理页面
│   ├── screenshot_page.dart           # 截图页面
│   ├── device_operations_page.dart    # 设备操作页面
│   └── settings_page.dart             # 设置页面
├── utils/                   # 工具类
│   ├── app_output.dart     # 应用输出工具
│   └── settings_manager.dart # 设置管理工具
└── widgets/                # 自定义组件
    ├── package_query_widget.dart # 包查询组件
    └── search_bar.dart          # 搜索栏组件
```

### 主要模块职责说明

- **main.dart**：应用入口，初始化主题和路由
- **pages/**：各功能页面，负责UI展示和用户交互
- **blocs/**：业务逻辑处理，状态管理
- **utils/**：工具函数和辅助类
- **widgets/**：可复用UI组件
- **app/modules/**：功能模块，按业务划分

## 🚀 安装与部署

### 环境要求

- **Flutter SDK**: 3.13.0 或更高版本
- **Dart**: 2.17.0 或更高版本
- **ADB工具**: 需要安装Android SDK Platform-Tools
- **操作系统**: Windows 10/11, macOS 10.15+, Linux Ubuntu 18.04+

### 本地运行步骤

1. **克隆项目**
```bash
git clone <repository-url>
cd code
```

2. **安装依赖**
```bash
flutter pub get
```

3. **检查环境**
```bash
flutter doctor
```

4. **运行应用**
```bash
# 开发模式运行
flutter run

# 构建发布版本
flutter build windows  # Windows
flutter build macos    # macOS  
flutter build linux    # Linux
flutter build apk      # Android
```

### 生产部署

#### Windows部署
```bash
flutter build windows
# 生成的exe文件位于 build/windows/runner/Release/
```

#### macOS部署
```bash
flutter build macos
# 生成的app文件位于 build/macos/Build/Products/Release/
```

#### Linux部署
```bash
flutter build linux
# 生成的可执行文件位于 build/linux/x64/release/bundle/
```

## 💡 使用示例

### 快速开始

1. **连接设备**
   - 通过USB连接Android设备
   - 启用设备的USB调试模式
   - 在应用中选择设备并连接

2. **屏幕镜像**
   - 进入"屏幕镜像"页面
   - 点击"开始投屏"按钮
   - 调整画质参数（可选）

3. **应用管理**
   - 进入"应用管理"页面
   - 查看已安装应用列表
   - 执行安装、卸载等操作

### 代码示例

#### 设备连接示例
```dart
// 连接ADB设备
Future<void> connectDevice(String ip, String port) async {
  final result = await runCommand(['adb', 'connect', '$ip:$port']);
  if (result.exitCode == 0) {
    print('设备连接成功');
  }
}
```

#### 屏幕镜像示例
```dart
// 启动屏幕镜像
void startScreenMirroring({
  int? bitrate,
  String? maxSize,
  bool turnScreenOff = false,
}) {
  final args = ['scrcpy'];
  
  if (bitrate != null) args.addAll(['-b', '${bitrate}m']);
  if (maxSize != null) args.addAll(['-m', maxSize]);
  if (turnScreenOff) args.add('--turn-screen-off');
  
  runCommand(args);
}
```

## ⚙️ 配置说明

### 应用设置
应用支持丰富的配置选项，可通过设置页面进行调整：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 默认码率 | 8M | 屏幕镜像的默认码率 |
| 默认分辨率 | 1080 | 屏幕镜像的最大分辨率 |
| 默认DPI | 420 | 显示密度设置 |
| 保持屏幕常亮 | false | 投屏时保持设备屏幕开启 |
| 显示触摸操作 | false | 在投屏中显示触摸点 |
| 关闭设备屏幕 | false | 投屏时关闭设备屏幕 |

### ADB路径配置
如果系统ADB路径不在环境变量中，需要在设置中指定ADB工具路径：

```dart
// 在设置中配置ADB路径
adbPath: '/path/to/adb'
```

## 🌟 项目亮点与价值

### 🔥 技术亮点
1. **现代化技术栈**：采用最新的Flutter框架，确保应用性能和用户体验
2. **跨平台兼容**：一套代码支持多个平台，降低开发和维护成本
3. **模块化架构**：清晰的代码结构，便于功能扩展和维护
4. **响应式设计**：支持多种屏幕尺寸和主题切换

### 💼 商业价值
1. **提高开发效率**：将复杂的命令行操作图形化，节省开发时间
2. **降低学习成本**：无需记忆复杂的ADB命令，降低使用门槛
3. **团队协作友好**：统一的工具界面，便于团队内部使用和培训
4. **持续维护**：基于活跃的Flutter生态，确保长期可用性

### 🎯 用户价值
- **开发者**：快速调试和测试Android应用
- **测试人员**：方便进行设备兼容性测试
- **技术支持**：远程协助和问题排查
- **普通用户**：管理手机应用和文件

## 🤝 贡献指南

我们欢迎所有形式的贡献！请阅读以下指南：

### 开发流程
1. Fork本仓库
2. 创建功能分支：`git checkout -b feature/AmazingFeature`
3. 提交更改：`git commit -m 'Add some AmazingFeature'`
4. 推送到分支：`git push origin feature/AmazingFeature`
5. 提交Pull Request

### 代码规范
- 遵循Dart官方代码风格指南
- 使用有意义的变量和函数命名
- 添加必要的注释和文档
- 确保代码通过静态分析

### Commit规范
使用[Conventional Commits](https://www.conventionalcommits.org/)规范：

```bash
feat: 添加新功能
fix: 修复bug
docs: 文档更新
style: 代码格式调整
refactor: 代码重构
test: 测试相关
chore: 构建过程或辅助工具变动
```

## 📄 许可证

本项目采用 **MIT许可证** - 详见 [LICENSE](LICENSE) 文件。

## ❓ 常见问题 (FAQ)

### Q: 无法检测到设备怎么办？
A: 
1. 确保设备已启用USB调试模式
2. 检查USB连接是否正常
3. 确认ADB驱动已正确安装
4. 尝试重新插拔USB线

### Q: 无线连接失败怎么办？
A:
1. 确保设备和电脑在同一网络
2. 检查防火墙设置
3. 确认设备已通过USB授权
4. 尝试使用设备的IP地址而非主机名

### Q: 屏幕镜像卡顿怎么办？
A:
1. 降低码率设置（如从8M降到4M）
2. 减小最大分辨率
3. 关闭不必要的后台应用
4. 检查网络连接质量（无线连接时）

### Q: 如何更新ADB工具？
A:
1. 下载最新版Android SDK Platform-Tools
2. 替换系统PATH中的ADB工具
3. 或在应用设置中指定新的ADB路径

## 📞 支持与反馈

如果您在使用过程中遇到问题或有建议，请通过以下方式联系我们：

- 📧 **邮箱**: [您的邮箱地址]
- 💬 **Issues**: [GitHub Issues页面]
- 📱 **社区**: [相关技术社区]

---

<div align="center">

**如果这个项目对您有帮助，请给个⭐Star支持一下！**

*让Android开发变得更简单* 🚀

</div>