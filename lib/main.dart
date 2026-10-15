import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app/modules/tools/services/tool_process.dart';
import 'app/modules/tools/services/command_runner.dart';
import 'app/modules/device_connection/bloc/device_connection_cubit.dart';
import 'app/modules/tools/widgets/tool_environment_card.dart';
import 'dart:async';
import 'app/modules/tools/services/tool_cancellation.dart';
import 'app/modules/tools/services/mirror_session.dart';
import 'app/modules/screen_mirroring/models/mirror_config.dart';
import 'app/modules/device_connection/services/network_scanner.dart';
import 'enums/page_category2.dart' as page_category;
import 'pages/device_connection_page.dart';
import 'pages/screen_mirroring_page.dart';
import 'pages/app_management_page.dart';
import 'pages/settings_page.dart';
import 'pages/file_manager_page.dart';
import 'pages/screenshot_page.dart';
import 'package:adb_tool/utils/app_output.dart';
import 'pages/device_operations_page.dart'; // 添加设备操作页面的导入
import 'utils/settings_manager.dart'; // 添加这一行
import 'package:adb_tool/app/theme/app_theme.dart';
import 'package:adb_tool/app/modules/settings/bloc/theme_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeCubit = ThemeCubit();
  await themeCubit.loadTheme();

  runApp(
    MultiBlocProvider(
      providers: [BlocProvider<ThemeCubit>(create: (_) => themeCubit)],
      child: const AdbToolApp(),
    ),
  );
}

class AdbToolApp extends StatelessWidget {
  const AdbToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return MaterialApp(
          title: '妙联',
          theme: AppTheme.create(state.seedColor, Brightness.light),
          darkTheme: AppTheme.create(state.seedColor, Brightness.dark),
          themeMode: state.themeMode,
          home: const ToolBootstrap(child: AdbHomePage()),
        );
      },
    );
  }
}

class AdbHomePage extends StatefulWidget {
  final CommandRunner? commands;
  final DeviceConnectionCubit? devices;
  final MirrorSession? mirror;
  const AdbHomePage({super.key, this.commands, this.devices, this.mirror});

  @override
  State<AdbHomePage> createState() => _AdbHomePageState();
}

class _AdbHomePageState extends State<AdbHomePage> {
  // 状态变量
  page_category.PageCategory _selectedCategory =
      page_category.PageCategory.deviceConnection;
  set output(String message) => appendAppOutput(message, task: '设备');
  final _lifetime = ToolCancellation();
  late final CommandRunner _commands;
  late final DeviceConnectionCubit _devices;
  StreamSubscription<DeviceConnectionState>? _deviceSubscription;
  late final MirrorSession _mirror;
  String? _mirrorDevice;
  final scanRangeController = TextEditingController();
  final _outputScrollController = ScrollController();
  bool _scrollScheduled = false;
  List<String> get deviceList => _devices.state.devices;
  String? get selectedDevice => _devices.state.serial;
  List<String> get foundAdbDevices => _devices.state.endpoints;
  String? get selectedFoundDevice => _devices.state.selectedEndpoint;
  List<String> get packageQueryResult => _devices.state.packages;
  Map<String, String> get deviceInfo => _devices.state.info;

  // 控制器
  final ipController = TextEditingController();
  final portController = TextEditingController(text: '5555'); // 添加端口控制器并设置默认值
  final apkController = TextEditingController();
  final bitrateController = TextEditingController();
  final sizeController = TextEditingController();
  final appKeywordController = TextEditingController();
  final appPackageController = TextEditingController();
  final appDisplaySizeController = TextEditingController(text: '1920x1080');
  final appDisplayDpiController = TextEditingController();

  // 设置页面的状态变量
  final defaultBitrateController = TextEditingController(text: '8');
  final defaultResolutionController = TextEditingController(text: '1080');
  final defaultDpiController = TextEditingController(text: '420');
  bool keepScreenOn = false;
  bool showTouches = false;
  bool turnScreenOff = false;
  bool enableH265 = false; // 添加这一行
  bool enablePhysicalKeyboard = false; // 添加这一行
  bool disableAudio = false;
  bool enableRecording = false;
  bool autoCleanAdbProcess = false; // 添加ADB进程清理开关状态

  // 添加输出面板显示状态控制
  bool _showOutputPanel = true;
  bool autoScanAndConnect = false; // 添加这一行

  @override
  void initState() {
    super.initState();
    appOutputNotifier.addListener(_onLogChanged);
    _commands =
        widget.commands ?? widget.devices?.commands ?? const CommandRunner();
    _devices = widget.devices ?? DeviceConnectionCubit(commands: _commands);
    _deviceSubscription = _devices.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _mirror =
        widget.mirror ??
        MirrorSession(onLog: (line) => appendAppOutput(line, task: '投屏'));
    _mirror.addListener(_onMirrorChanged);
    _initializeDevicePage();
  }

  Future<void> _initializeDevicePage() async {
    try {
      await _loadSettings();
      if (mounted && autoCleanAdbProcess) await cleanAdbProcesses();
      if (mounted) await _devices.refresh();
    } catch (error) {
      if (mounted) setState(() => output = '无法连接 ADB，请在设置中补全运行环境：$error');
    }
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.loadSettings();
    if (!mounted) return;
    setState(() {
      autoScanAndConnect = settings[SettingsManager.keyAutoScanAndConnect];
      keepScreenOn = settings[SettingsManager.keyKeepScreenOn];
      showTouches = settings[SettingsManager.keyShowTouches];
      defaultBitrateController.text =
          settings[SettingsManager.keyDefaultBitrate];
      defaultResolutionController.text =
          settings[SettingsManager.keyDefaultResolution];
      defaultDpiController.text = settings[SettingsManager.keyDefaultDpi];
      turnScreenOff = settings[SettingsManager.keyTurnScreenOff];
      enableH265 = settings[SettingsManager.keyEnableH265]; // 添加这一行
      enablePhysicalKeyboard =
          settings[SettingsManager.keyEnablePhysicalKeyboard]; // 添加这一行
      disableAudio = settings[SettingsManager.keyDisableAudio];
      enableRecording = settings[SettingsManager.keyEnableRecording];
      autoCleanAdbProcess =
          settings[SettingsManager.keyAutoCleanAdbProcess]; // 添加这一行
    });

    scanRangeController.text = settings[SettingsManager.keyScanRange];
    portController.text = settings[SettingsManager.keyScanPort];
    if (autoScanAndConnect && mounted) {
      final found = await scanAdbDevices();
      if (!mounted || found == null) return;
      for (final endpoint in found) {
        if (!mounted) return;
        await runCommand(['adb', 'connect', endpoint]);
      }
    }
  }

  void _onMirrorChanged() {
    if (mounted) setState(() {});
  }

  void _onLogChanged() {
    if (_scrollScheduled || !mounted) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _outputScrollController.hasClients) {
        _outputScrollController.jumpTo(
          _outputScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  void dispose() {
    appOutputNotifier.removeListener(_onLogChanged);
    _outputScrollController.dispose();
    _lifetime.cancel();
    unawaited(_deviceSubscription?.cancel());
    if (widget.devices == null) unawaited(_devices.close());
    _mirror.removeListener(_onMirrorChanged);
    if (widget.mirror == null) _mirror.dispose();
    scanRangeController.dispose();
    // 释放所有控制器
    ipController.dispose();
    portController.dispose(); // 添加端口控制器释放
    apkController.dispose();
    bitrateController.dispose();
    sizeController.dispose();
    appKeywordController.dispose();
    appPackageController.dispose();
    appDisplaySizeController.dispose();
    appDisplayDpiController.dispose();
    defaultBitrateController.dispose();
    defaultResolutionController.dispose();
    defaultDpiController.dispose();
    super.dispose();
  }

  // 核心功能方法
  Future<void> runCommand(List<String> cmd) async {
    if (!mounted) return;
    if (cmd.isEmpty) return;
    final session = _devices.session;
    final label = cmd.length > 1 && cmd[1] == 'pair'
        ? '无线配对'
        : (cmd.first == 'scrcpy' ? '投屏' : '命令');
    appendAppOutput('开始执行', task: label);
    setState(() => _showOutputPanel = true);
    try {
      final bound = session.bind(cmd);
      if (cmd.first == 'scrcpy') {
        _mirrorDevice = selectedDevice;
        await _mirror.start(bound);
      } else {
        final result = await _commands.run(bound, cancellation: _lifetime);
        if (!mounted) return;
        final out = result.stdout.toString();
        final err = result.stderr.toString();
        appendAppOutput(
          out.isEmpty && err.isEmpty
              ? '执行成功'
              : '$out${err.isEmpty ? '' : '\n$err'}',
          task: label,
        );
      }
    } on ToolCancelled {
      // 页面关闭后不再显示结果。
    } catch (error) {
      if (mounted) {
        appendAppOutput(
          label == '无线配对' ? '配对失败，请检查地址、端口和配对码' : '执行失败：$error',
          task: label,
        );
      }
    }
  }

  Future<void> queryPackages() =>
      _devices.queryPackages(appKeywordController.text);

  // 仅终止本应用持有句柄的客户端，不终止共享 ADB 服务。
  Future<void> cleanAdbProcesses() async {
    final count = ownedAdbProcesses.clean();
    if (!mounted) return;
    setState(
      () => output = count == 0
          ? '没有可清理的本应用 ADB 客户端进程'
          : '已请求停止 $count 个本应用 ADB 客户端进程',
    );
  }

  Future<List<String>?> scanAdbDevices() async {
    if (!mounted) return null;
    if (_devices.state.scanning) {
      _devices.cancelScan();
      return null;
    }
    try {
      final range = scanRangeController.text.trim();
      Ipv4Range.parse(range);
      final port = int.tryParse(portController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('端口范围为 1–65535');
      }
      final pending = _devices.scan(range, port);
      try {
        await SettingsManager.saveSettings(
          scanRange: range,
          scanPort: port.toString(),
        );
      } catch (error) {
        if (mounted) appendAppOutput('保存扫描设置失败：$error', task: '扫描');
      }
      return await pending;
    } catch (error) {
      if (mounted) appendAppOutput('扫描失败：$error', task: '扫描');
      return null;
    }
  }

  Widget buildButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(onPressed: onPressed, child: Text(label)),
    );
  }

  // 界面构建
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('妙联'),
        actions: [
          if (_mirror.isActive)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onPrimary,
              ),
              onPressed: _mirror.isStopping
                  ? null
                  : () async {
                      await _mirror.stop();
                    },
              icon: const Icon(Icons.stop),
              label: Text('停止投屏（$_mirrorDevice）'),
            ),
        ],
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Row(
        children: [
          // 左侧导航栏
          NavigationRail(
            extended: true,
            minExtendedWidth: 180,
            selectedIndex: _selectedCategory.index,
            selectedIconTheme: IconThemeData(color: colorScheme.primary),
            selectedLabelTextStyle: TextStyle(color: colorScheme.primary),
            onDestinationSelected: (index) {
              setState(
                () => _selectedCategory =
                    page_category.PageCategory.values[index],
              );
            },
            destinations: page_category.PageCategory.values.map((category) {
              return NavigationRailDestination(
                icon: Icon(category.icon),
                label: Text(category.label),
              );
            }).toList(),
          ),

          // 中间内容区
          Expanded(flex: 2, child: _buildContent()),

          // 右侧输出区
          Expanded(flex: _showOutputPanel ? 1 : 0, child: _buildOutputPanel()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedCategory) {
      case page_category.PageCategory.deviceConnection:
        return DeviceConnectionPage(
          scanRangeController: scanRangeController,
          isScanning: _devices.state.scanning,
          deviceList: deviceList,
          selectedDevice: selectedDevice,
          foundAdbDevices: foundAdbDevices,
          selectedFoundDevice: selectedFoundDevice,
          ipController: ipController,
          portController: portController,
          onDeviceSelected: (device) {
            unawaited(_devices.select(device));
          },
          onFoundDeviceSelected: (endpoint) {
            _devices.selectEndpoint(endpoint);
            if (endpoint != null) {
              final parts = endpoint.split(':');
              ipController.text = parts.first;
              if (parts.length == 2) portController.text = parts.last;
            }
          },
          onRefreshDevices: () {
            unawaited(_devices.refresh());
          },
          onRunCommand: runCommand,
          onScanDevices: scanAdbDevices,
          deviceInfo: deviceInfo, // 添加这一行
        );

      case page_category.PageCategory.screenMirroring:
        return ScreenMirroringPage(
          config: () => MirrorConfig(
            bitrate: defaultBitrateController.text,
            maxSize: defaultResolutionController.text,
            dpi: defaultDpiController.text,
            turnScreenOff: turnScreenOff,
            disableAudio: disableAudio,
            h265: enableH265,
            physicalKeyboard: enablePhysicalKeyboard,
            record: enableRecording,
          ),
          isMirrorActive: _mirror.isActive,
          onStop: () {
            unawaited(_mirror.stop());
          },
          bitrateController: bitrateController,
          sizeController: sizeController,
          appPackageController: appPackageController,
          appDisplaySizeController: appDisplaySizeController,
          appDisplayDpiController: appDisplayDpiController,
          searchController: appKeywordController,
          onRunCommand: runCommand,
          onQueryPackages: () => queryPackages(),
          packageQueryResult: packageQueryResult,
        );

      case page_category.PageCategory.appManagement:
        return AppManagementPage(
          key: ValueKey(selectedDevice),
          session: _devices.session,
          apkController: apkController,
          appKeywordController: appKeywordController,
          onRunCommand: runCommand,
          onQueryPackages: () => queryPackages(),
          packageQueryResult: packageQueryResult,
        );

      case page_category.PageCategory.deviceOperations:
        return DeviceOperationsPage(onRunCommand: runCommand);

      case page_category.PageCategory.superScreenshot:
        return ScreenshotPage(
          key: ValueKey(selectedDevice),
          serial: selectedDevice ?? '',
        );

      case page_category.PageCategory.fileManager:
        return FileManagerPage(
          key: ValueKey(selectedDevice),
          serial: selectedDevice ?? '',
        );

      case page_category.PageCategory.settings:
        return SettingsPage(
          defaultBitrateController: defaultBitrateController,
          defaultResolutionController: defaultResolutionController,
          defaultDpiController: defaultDpiController,
          onRunCommand: (List<String> command) async {
            try {
              final process = await _devices.session.run(
                command,
                cancellation: _lifetime,
              );
              if (process.exitCode == 0) {
                debugPrint('命令执行成功: ${command.join(" ")}');
                return true;
              } else {
                debugPrint('命令执行失败: ${process.stderr}');
                return false;
              }
            } catch (e) {
              debugPrint('命令执行错误: $e');
              return false;
            }
          },
          keepScreenOn: keepScreenOn,
          showTouches: showTouches,
          autoScanAndConnect: autoScanAndConnect,
          turnScreenOff: turnScreenOff, // 添加这一行
          onKeepScreenOnChanged: (value) {
            setState(() => keepScreenOn = value);
            SettingsManager.saveSettings(keepScreenOn: value);
          },
          onShowTouchesChanged: (value) {
            setState(() => showTouches = value);
            SettingsManager.saveSettings(showTouches: value);
          },
          onAutoScanAndConnectChanged: (value) {
            setState(() => autoScanAndConnect = value);
            SettingsManager.saveSettings(autoScanAndConnect: value);
          },
          onTurnScreenOffChanged: (value) {
            // 添加这一行
            setState(() => turnScreenOff = value);
            SettingsManager.saveSettings(turnScreenOff: value);
          }, // 添加这一行
          enableH265: enableH265, // 添加这一行
          enablePhysicalKeyboard: enablePhysicalKeyboard, // 添加这一行
          onEnableH265Changed: (value) {
            // 添加这一行
            setState(() => enableH265 = value);
            SettingsManager.saveSettings(enableH265: value);
          },
          onEnablePhysicalKeyboardChanged: (value) {
            // 添加这一行
            setState(() => enablePhysicalKeyboard = value);
            SettingsManager.saveSettings(enablePhysicalKeyboard: value);
          },
          disableAudio: disableAudio,
          enableRecording: enableRecording,
          onDisableAudioChanged: (value) {
            setState(() => disableAudio = value);
            SettingsManager.saveSettings(disableAudio: value);
          },
          onEnableRecordingChanged: (value) {
            setState(() => enableRecording = value);
            SettingsManager.saveSettings(enableRecording: value);
          },
          autoCleanAdbProcess: autoCleanAdbProcess,
          onAutoCleanAdbProcessChanged: (value) {
            setState(() => autoCleanAdbProcess = value);
            SettingsManager.saveSettings(autoCleanAdbProcess: value);

            // 如果启用了自动清理，立即执行一次清理
            if (value) {
              cleanAdbProcesses();
            }
          },
          onManualCleanAdbProcess: cleanAdbProcesses,
        );
    }
  }

  Widget _buildOutputPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _showOutputPanel ? null : 48,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部标题栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: colorScheme.primary.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_showOutputPanel)
                  const Text(
                    '输出结果：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showOutputPanel)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.clear,
                          color: colorScheme.primary,
                          size: 18,
                        ),
                        onPressed: _clearOutput,
                        tooltip: '清除输出',
                      ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _showOutputPanel
                            ? Icons.keyboard_arrow_right
                            : Icons.keyboard_arrow_left,
                        color: colorScheme.primary,
                      ),
                      onPressed: () {
                        setState(() => _showOutputPanel = !_showOutputPanel);
                      },
                      tooltip: _showOutputPanel ? '收起' : '展开',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 输出内容区
          if (_showOutputPanel)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: colorScheme.primary.withValues(alpha: 0.05),
                child: SingleChildScrollView(
                  controller: _outputScrollController,
                  child: ValueListenableBuilder<String>(
                    valueListenable: appOutputNotifier,
                    builder: (_, val, __) => SelectableText(
                      val,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 清除输出内容
  void _clearOutput() {
    clearAppOutput();
  }
}
