import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import 'dart:io';
import 'dart:convert';
import 'enums/page_category2.dart' as page_category;
import 'pages/device_connection_page.dart';
import 'pages/screen_mirroring_page.dart';
import 'pages/app_management_page.dart';
import 'pages/settings_page.dart';
import 'pages/file_manager_page.dart';
import 'pages/screenshot_page.dart';
import 'package:adb_tool/utils/app_output.dart';
import 'pages/device_operations_page.dart'; // 添加设备操作页面的导入
import 'utils/settings_manager.dart';  // 添加这一行
// flutter_bloc was used by file manager; removed along with feature

void main() {
  runApp(const AdbToolApp());
}

class AdbToolApp extends StatelessWidget {
  const AdbToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '妙联',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AdbHomePage(),
    );
  }
}

class AdbHomePage extends StatefulWidget {
  const AdbHomePage({super.key});

  @override
  State<AdbHomePage> createState() => _AdbHomePageState();
}

class _AdbHomePageState extends State<AdbHomePage> {
  // 状态变量
  page_category.PageCategory _selectedCategory = page_category.PageCategory.deviceConnection;
  String output = '';
  List<String> deviceList = [];
  String? selectedDevice;
  List<String> foundAdbDevices = [];
  String? selectedFoundDevice;
  List<String> packageQueryResult = [];
  
  // 添加设备信息Map
  Map<String, String> deviceInfo = {};

  // 控制器
  final ipController = TextEditingController();
  final portController = TextEditingController(text: '5555');  // 添加端口控制器并设置默认值
  final apkController = TextEditingController();
  final bitrateController = TextEditingController();
  final sizeController = TextEditingController();
  final appKeywordController = TextEditingController();
  final appPackageController = TextEditingController();
  final appDisplaySizeController = TextEditingController(text: '1920x1080');
  final appDisplayDpiController = TextEditingController(text: '420');

  // 设置页面的状态变量
  final defaultBitrateController = TextEditingController(text: '8');
  final defaultResolutionController = TextEditingController(text: '1080');
  final defaultDpiController = TextEditingController(text: '420');
  bool keepScreenOn = false;
  bool showTouches = false;
  bool turnScreenOff = false;
  bool enableH265 = false;        // 添加这一行
  bool enablePhysicalKeyboard = false;  // 添加这一行
  bool disableAudio = false;
  bool enableRecording = false;

  // 添加输出面板显示状态控制
  bool _showOutputPanel = true;
  bool autoScanAndConnect = false;  // 添加这一行

  @override
  void initState() {
    super.initState();
    _loadSettings();
    refreshDeviceList();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.loadSettings();
    setState(() {
      autoScanAndConnect = settings[SettingsManager.keyAutoScanAndConnect];
      keepScreenOn = settings[SettingsManager.keyKeepScreenOn];
      showTouches = settings[SettingsManager.keyShowTouches];
      defaultBitrateController.text = settings[SettingsManager.keyDefaultBitrate];
      defaultResolutionController.text = settings[SettingsManager.keyDefaultResolution];
      defaultDpiController.text = settings[SettingsManager.keyDefaultDpi];
      turnScreenOff = settings[SettingsManager.keyTurnScreenOff];
      enableH265 = settings[SettingsManager.keyEnableH265];          // 添加这一行
      enablePhysicalKeyboard = settings[SettingsManager.keyEnablePhysicalKeyboard];  // 添加这一行
      disableAudio = settings[SettingsManager.keyDisableAudio];
      enableRecording = settings[SettingsManager.keyEnableRecording];
    });

    // 如果启用了自动扫描连接，则执行扫描
    if (autoScanAndConnect) {
      Future.delayed(const Duration(seconds: 1), () {
        scanAdbDevices().then((_) {
          if (foundAdbDevices.isNotEmpty) {
            for (var ip in foundAdbDevices) {
              runCommand(['adb', 'connect', '$ip:${portController.text}']);
            }
          }
        });
      });
    }
  }

  @override
  void dispose() {
    // 释放所有控制器
    ipController.dispose();
    portController.dispose();  // 添加端口控制器释放
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
    setState(() => output = '执行中...');
    List<String> realCmd = List.from(cmd);
    if (selectedDevice != null && (cmd.first == 'adb' || cmd.first == 'scrcpy')) {
      realCmd.insert(1, selectedDevice!);
      realCmd.insert(1, '-s');
    }

    try {
      final result = await _runWithSmartEncoding(realCmd);
      setState(() {
        final stdoutStr = result.stdout?.toString() ?? '';
        final stderrStr = result.stderr?.toString() ?? '';
        output = stdoutStr + (stderrStr.isNotEmpty ? '\n' + stderrStr : '');
        _showOutputPanel = true;
      });
    } catch (e) {
      setState(() {
        output = 'Error: $e';
        _showOutputPanel = true;
      });
    }
  }

  // 根据命令内容智能选择编码并执行可执行文件
  Future<ProcessResult> _runWithSmartEncoding(List<String> cmd) async {
    if (cmd.isEmpty) {
      throw ArgumentError('Empty command');
    }
    final bool isShellCmd = cmd.contains('shell');
    final encoding = isShellCmd ? utf8 : const SystemEncoding();

    return await runExecutableArguments(
      cmd.first,
      cmd.sublist(1),
      stdoutEncoding: encoding,
      stderrEncoding: encoding,
    );
  }

  Future<void> refreshDeviceList() async {
    final result = await _runWithSmartEncoding(['adb', 'devices']);
    final devices = result.stdout.toString()
        .split('\n')
        .where((line) => line.contains('\tdevice'))
        .map((line) => line.split('\t').first)
        .toList();
    
    setState(() {
      deviceList = devices;
      if (selectedDevice != null && !devices.contains(selectedDevice)) {
        selectedDevice = null;
      }
    });
  }

  Future<void> queryPackages() async {
    final keyword = appKeywordController.text.trim();
    if (keyword.isEmpty) return;
    setState(() => output = '查询中...');
    List<String> cmd = ['adb', 'shell', 'pm', 'list', 'packages'];
    if (selectedDevice != null) {
      cmd.insert(1, selectedDevice!);
      cmd.insert(1, '-s');
    }
    final result = await _runWithSmartEncoding(cmd);
    final lines = result.stdout.toString().split('\n');
    final filtered = lines.where((line) => line.contains(keyword)).toList();
    setState(() {
      packageQueryResult = filtered;
      output = filtered.isEmpty ? '未找到相关包名' : filtered.join('\n');
    });
  }

  Future<void> startAppProjection() async {
    final pkg = appPackageController.text.trim();
    final displaySize = appDisplaySizeController.text.trim();
    final displayDpi = appDisplayDpiController.text.trim();
    if (pkg.isEmpty || displaySize.isEmpty || displayDpi.isEmpty) return;
    await runCommand([
      'scrcpy',
      '--new-display=$displaySize/$displayDpi',
      '--start-app=$pkg',
      '--no-vd-system-decorations'
    ]);
  }

  Future<void> scanAdbDevices() async {
    setState(() {
      foundAdbDevices.clear();
      output = '正在扫描所有网卡局域网5555端口，请稍候...';
    });

    // 获取所有本地IPv4网卡的网段
    List<String> baseIps = [];
    for (var interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (var addr in interface.addresses) {
        if (!addr.isLoopback && addr.address.contains('.')) {
          var parts = addr.address.split('.');
          if (parts.length == 4) {
            baseIps.add('${parts[0]}.${parts[1]}.${parts[2]}.');
          }
        }
      }
    }
    // 用户手动输入的IP优先
    if (ipController.text.isNotEmpty && ipController.text.contains('.')) {
      var parts = ipController.text.split('.');
      if (parts.length == 4) {
        baseIps.insert(0, '${parts[0]}.${parts[1]}.${parts[2]}.');
      }
    }
    // 去重
    baseIps = baseIps.toSet().toList();

    const int maxConcurrent = 20;
    List<Future> futures = [];
    int current = 0;

    for (var baseIp in baseIps) {
      for (int i = 1; i < 255; i++) {
        final ip = '$baseIp$i';
        if (current >= maxConcurrent) {
          await Future.any(futures);
          // Remove the first completed future (since Future.any completes when any future completes)
          futures.removeAt(0);
          current = futures.length;
        }
        final future = Socket.connect(ip, 5555, timeout: const Duration(milliseconds: 300)).then((socket) {
          socket.destroy();
          if (!foundAdbDevices.contains(ip)) {
            setState(() {
              foundAdbDevices.add(ip);
              output = '发现设备：\n${foundAdbDevices.join('\n')}';
            });
          }
        }).catchError((_) {});
        futures.add(future);
        current++;
      }
    }
    await Future.wait(futures);

    setState(() {
      output = foundAdbDevices.isEmpty
          ? '未发现开放5555端口的设备'
          : '发现如下设备：\n${foundAdbDevices.join('\n')}';
    });
  }

  // 添加获取设备信息的方法
  Future<void> _refreshDeviceInfo(String device) async {
    // 获取设备型号
    final modelResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'getprop', 'ro.product.model']);
    
    // 获取Android版本
    final versionResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'getprop', 'ro.build.version.release']);
    
    // 获取屏幕分辨率
    final sizeResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'wm', 'size']);
    
    // 获取运行内存
    final memResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'cat', '/proc/meminfo']);
    
    // 获取存储信息
    final storageResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'df', '/storage/emulated']);

    // 解析存储信息
    String storageTotal = '未知';
    String storageUsed = '未知';
    String storageAvailable = '未知';

    // KB转GB/MB字符串
    String formatSize(String value) {
      if (value == '未知') return value;
      int num = int.tryParse(value) ?? 0;
      if (num >= 1024 * 1024) {
        return '${(num / (1024 * 1024)).toStringAsFixed(2)} GB';
      } else if (num >= 1024) {
        return '${(num / 1024).toStringAsFixed(2)} MB';
      } else {
        return '$num KB';
      }
    }

    if (storageResult.stdout.toString().isNotEmpty) {
      final lines = storageResult.stdout.toString().split('\n');
      // 查找包含 /storage/emulated 的行
      final storageLine = lines.firstWhere(
        (line) => line.contains('/storage/emulated'),
        orElse: () => '',
      );
      if (storageLine.isNotEmpty) {
        // 按空格分割并去除多余空格
        final parts = storageLine.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.length >= 6) {
          // parts[1] 总大小，parts[2] 已用，parts[3] 可用
          storageTotal = formatSize(parts[1]);
          storageUsed = formatSize(parts[2]);
          storageAvailable = formatSize(parts[3]);
        }
      }
    }

    // 获取CPU架构
    final abiResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'getprop', 'ro.product.cpu.abi']);
    
    // 获取电池信息
    final batteryResult = await _runWithSmartEncoding(['adb', '-s', device, 'shell', 'dumpsys', 'battery']);

    // 解析电池信息
    String batteryLevel = '未知';
    if (batteryResult.stdout.toString().isNotEmpty) {
      final lines = batteryResult.stdout.toString().split('\n');
      for (var line in lines) {
        if (line.trim().startsWith('level:')) {
          batteryLevel = line.split(':')[1].trim();
          break;
        }
      }
    }

    setState(() {
      deviceInfo = {
        'model': modelResult.stdout.toString().trim(),
        'android_version': versionResult.stdout.toString().trim(),
        'screen_size': sizeResult.stdout.toString().contains('Physical size:') 
            ? sizeResult.stdout.toString().split('Physical size:')[1].trim()
            : '未知',
        'memory': memResult.stdout.toString().contains('MemTotal:')
            ? '${(int.parse(memResult.stdout.toString().split('MemTotal:')[1].trim().split(' ')[0]) / 1024 / 1024).toStringAsFixed(2)} GB'
            : '未知',
        // 存储信息格式化
        'storage': (storageTotal != '未知' && storageUsed != '未知' && storageAvailable != '未知')
            ? '总:$storageTotal 已用:$storageUsed 可用:$storageAvailable'
            : '未知',
        'cpu_abi': abiResult.stdout.toString().trim(),
        'battery': '$batteryLevel%',
      };
    });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('妙联'),
        backgroundColor: const Color(0xFF8fb5be),
      ),
      body: Row(
        children: [
          // 左侧导航栏
          NavigationRail(
            extended: true,
            minExtendedWidth: 180,
            selectedIndex: _selectedCategory.index,
            selectedIconTheme: const IconThemeData(
              color: Color(0xFF8fb5be),
            ),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFF8fb5be),
            ),
            onDestinationSelected: (index) {
              setState(() => _selectedCategory = page_category.PageCategory.values[index]);
            },
            destinations: page_category.PageCategory.values.map((category) {
              return NavigationRailDestination(
                icon: Icon(category.icon),
                label: Text(category.label),
              );
            }).toList(),
          ),
          
          // 中间内容区
          Expanded(
            flex: 2,
            child: _buildContent(),
          ),

          // 右侧输出区
          Expanded(
            flex: _showOutputPanel ? 1 : 0,
            child: _buildOutputPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
  switch (_selectedCategory) {
    case page_category.PageCategory.deviceConnection:
      return DeviceConnectionPage(
        deviceList: deviceList,
        selectedDevice: selectedDevice,
        foundAdbDevices: foundAdbDevices,
        selectedFoundDevice: selectedFoundDevice,
        ipController: ipController,
        portController: portController,
        onDeviceSelected: (device) {
          setState(() {
            selectedDevice = device;
            // 当选择设备时，自动获取设备信息
            if (device != null) {
              _refreshDeviceInfo(device);
            }
          });
        },
        onFoundDeviceSelected: (device) {
          setState(() {
            selectedFoundDevice = device;
            ipController.text = device ?? '';
          });
        },
        onRefreshDevices: refreshDeviceList,
        onRunCommand: runCommand,
        onScanDevices: scanAdbDevices,
        deviceInfo: deviceInfo, // 添加这一行
      );
    
    case page_category.PageCategory.screenMirroring:
      return ScreenMirroringPage(
        bitrateController: bitrateController,
        sizeController: sizeController,
        appPackageController: appPackageController,
        appDisplaySizeController: appDisplaySizeController,
        appDisplayDpiController: appDisplayDpiController,
        searchController: appKeywordController,
        onRunCommand: runCommand,
        onQueryPackages: () => queryPackages(),
        packageQueryResult: packageQueryResult,
        enableH265: enableH265,
        enablePhysicalKeyboard: enablePhysicalKeyboard,
        turnScreenOff: turnScreenOff,
        disableAudio: disableAudio,       // 添加这一行
        enableRecording: enableRecording,  // 添加这一行
      );
    
    case page_category.PageCategory.appManagement:
      return AppManagementPage(
        apkController: apkController,
        appKeywordController: appKeywordController,
        onRunCommand: runCommand,
        onQueryPackages: () => queryPackages(),
        packageQueryResult: packageQueryResult,
      );
    
    case page_category.PageCategory.deviceOperations:
      return DeviceOperationsPage(
        onRunCommand: runCommand,
      );

    case page_category.PageCategory.superScreenshot:
      return ScreenshotPage(serial: selectedDevice ?? '');
    
    case page_category.PageCategory.fileManager:
      return FileManagerPage(serial: selectedDevice ?? '');

    case page_category.PageCategory.settings:
      return SettingsPage(
        defaultBitrateController: defaultBitrateController,
        defaultResolutionController: defaultResolutionController,
        defaultDpiController: defaultDpiController,
        onRunCommand: (List<String> command) async {
          try {
            final process = await Process.run(command[0], command.sublist(1));
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
        turnScreenOff: turnScreenOff,  // 添加这一行
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
        onTurnScreenOffChanged: (value) {  // 添加这一行
          setState(() => turnScreenOff = value);
          SettingsManager.saveSettings(turnScreenOff: value);
        },  // 添加这一行
        enableH265: enableH265,                    // 添加这一行
        enablePhysicalKeyboard: enablePhysicalKeyboard,  // 添加这一行
        onEnableH265Changed: (value) {             // 添加这一行
          setState(() => enableH265 = value);
          SettingsManager.saveSettings(enableH265: value);
        },
        onEnablePhysicalKeyboardChanged: (value) {      // 添加这一行
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
      );
  }
}

  Widget _buildOutputPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _showOutputPanel ? null : 48,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: const Color(0xFF8fb5be).withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部标题栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF8fb5be).withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_showOutputPanel) const Text(
                  '输出结果：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    _showOutputPanel 
                        ? Icons.keyboard_arrow_right 
                        : Icons.keyboard_arrow_left,
                    color: const Color(0xFF8fb5be),
                  ),
                  onPressed: () {
                    setState(() => _showOutputPanel = !_showOutputPanel);
                  },
                  tooltip: _showOutputPanel ? '收起' : '展开',
                ),
              ],
            ),
          ),
          // 输出内容区
          if (_showOutputPanel)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFF8fb5be).withOpacity(0.05),
                child: SingleChildScrollView(
                  child: ValueListenableBuilder<String>(
                    valueListenable: appOutputNotifier,
                    builder: (_, val, __) => SelectableText(
                      // prefer the global notifier content, fallback to the old `output`
                      val.isNotEmpty ? val : output,
                      style: TextStyle(
                        color: Colors.grey[800],
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
}