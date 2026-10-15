import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';

import '../widgets/package_query_widget.dart';
import '../models/process_info.dart';
import '../models/device_memory_info.dart';
import '../models/memory_snapshot.dart';
import '../datasources/process_data_source.dart';
import '../app/modules/tools/services/device_session.dart';
import '../app/modules/tools/services/tool_cancellation.dart';
import '../app/modules/tools/services/command_parser.dart';
import '../datasources/adb_process_data_source.dart';

// 进程分类枚举
enum ProcessCategory {
  userApp, // 普通应用
  systemApp, // 系统应用
  other, // 其他/原生
  all, // 全部
}

// 排序类型枚举
enum SortType {
  none, // 不排序
  pidAsc, // PID升序
  pidDesc, // PID降序
  cpuAsc, // CPU升序
  cpuDesc, // CPU降序
  memoryAsc, // 内存升序
  memoryDesc, // 内存降序
}

class AppManagementPage extends StatefulWidget {
  final DeviceSession session;
  final TextEditingController apkController;
  final TextEditingController appKeywordController;
  final Function(List<String>) onRunCommand;
  final VoidCallback onQueryPackages;
  final List<String> packageQueryResult;

  const AppManagementPage({
    super.key,
    required this.session,
    required this.apkController,
    required this.appKeywordController,
    required this.onRunCommand,
    required this.onQueryPackages,
    required this.packageQueryResult,
  });

  @override
  State<AppManagementPage> createState() => _AppManagementPageState();
}

class _AppManagementPageState extends State<AppManagementPage> {
  // 内存信息
  DeviceMemoryInfo? _memoryInfo;
  // 内存使用趋势数据
  final List<MemorySnapshot> _memoryTrendSnapshots = [];
  // 进程列表
  List<ProcessInfo> _processList = [];
  // 自动刷新定时器
  Timer? _refreshTimer;
  final _cancellation = ToolCancellation();
  final _commandController = TextEditingController();
  // 数据源
  late ProcessDataSource _dataSource;
  String? _monitorError;
  bool _refreshing = false;
  bool _monitorReady = false;
  // 是否折叠进程列表
  bool _isProcessListCollapsed = true;
  // 进程分类筛选
  ProcessCategory _selectedCategory = ProcessCategory.userApp;
  // 排序类型
  SortType _sortType = SortType.none;

  @override
  void initState() {
    super.initState();
    // 初始化数据源
    _initDataSource();
    // 初始刷新数据
    _refreshData();
    // 启动自动刷新定时器
    _startAutoRefresh();
  }

  @override
  void dispose() {
    // 取消定时器
    _commandController.dispose();
    _cancellation.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // 初始化数据源
  void _initDataSource() {
    // 尝试使用ADB数据源
    _switchToAdbDataSource();
  }

  void _switchToAdbDataSource() {
    _dataSource = AdbProcessDataSource(
      session: widget.session,
      cancellation: _cancellation,
    );
  }

  // 启动自动刷新
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });
  }

  // 刷新数据
  Future<void> _refreshData() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      // 获取内存信息
      final memoryInfo = await _dataSource.fetchMemoryInfo();
      // 获取进程列表
      final processes = await _dataSource.fetchProcesses();
      // 获取前台包名
      final foregroundPackage = await _dataSource.getForegroundPackage();

      // 更新前台状态
      final updatedProcesses = processes.map((process) {
        return ProcessInfo(
          pid: process.pid,
          uid: process.uid,
          name: process.name,
          rss: process.rss,
          cpu: process.cpu,
          package: process.package,
          type: process.type,
          status: process.package == foregroundPackage ? '前台' : '后台',
        );
      }).toList();

      if (!mounted) return;
      // 应用排序
      _applySort(updatedProcesses);

      setState(() {
        _monitorError = null;
        _monitorReady = true;
        _memoryInfo = memoryInfo;
        _processList = updatedProcesses;

        // 添加到内存趋势
        if (_memoryInfo != null) {
          _memoryTrendSnapshots.add(
            MemorySnapshot(
              usedGB: _memoryInfo!.usedMemoryGB,
              totalGB: _memoryInfo!.totalMemoryGB,
              timestamp: DateTime.now(),
            ),
          );
          // 保持最多10分钟的数据（20个数据点）
          if (_memoryTrendSnapshots.length > 20) {
            _memoryTrendSnapshots.removeAt(0);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _monitorReady = false;
        _monitorError = '读取设备状态失败，请检查连接后刷新：$e';
        _processList = [];
        _memoryInfo = null;
        _memoryTrendSnapshots.clear();
      });
    } finally {
      _refreshing = false;
    }
  }

  // 应用排序
  void _applySort(List<ProcessInfo> processes) {
    switch (_sortType) {
      case SortType.pidAsc:
        processes.sort((a, b) => int.parse(a.pid).compareTo(int.parse(b.pid)));
        break;
      case SortType.pidDesc:
        processes.sort((a, b) => int.parse(b.pid).compareTo(int.parse(a.pid)));
        break;
      case SortType.cpuAsc:
        processes.sort(
          (a, b) => double.parse(a.cpu).compareTo(double.parse(b.cpu)),
        );
        break;
      case SortType.cpuDesc:
        processes.sort(
          (a, b) => double.parse(b.cpu).compareTo(double.parse(a.cpu)),
        );
        break;
      case SortType.memoryAsc:
        processes.sort((a, b) => int.parse(a.rss).compareTo(int.parse(b.rss)));
        break;
      case SortType.memoryDesc:
        processes.sort((a, b) => int.parse(b.rss).compareTo(int.parse(a.rss)));
        break;
      case SortType.none:
        // 不排序
        break;
    }
  }

  // 获取排序按钮文本
  String _getSortButtonText(
    SortType ascType,
    SortType descType,
    String baseText,
  ) {
    if (_sortType == ascType) {
      return '$baseText (升序)';
    } else if (_sortType == descType) {
      return '$baseText (降序)';
    } else {
      return baseText;
    }
  }

  // 手动刷新数据
  Future<void> _manualRefresh() async {
    await _refreshData();
  }

  // 进程分类辅助函数
  ProcessCategory _classifyProcess(ProcessInfo process) {
    // 解析 UID (假设 uid 字段是 String，如 "u0_a125" 或 "10125" 或 "root")

    // 1. 检查是否为普通应用 (包含 u0_a 或 uid >= 10000)
    if (process.uid.startsWith('u0_a') ||
        (int.tryParse(process.uid) ?? 0) >= 10000) {
      return ProcessCategory.userApp;
    }

    // 2. 检查是否为核心系统应用
    if (process.uid == 'system' ||
        process.name.startsWith('com.android.') ||
        process.name == 'system_server') {
      return ProcessCategory.systemApp;
    }

    // 3. 其他归为 Other (root, shell, zygote 等)
    return ProcessCategory.other;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 设备状态与内存监控
        _buildDeviceStatusMonitor(context),
        const Divider(),
        // 进程管理
        _buildProcessManagement(),
        const Divider(),
        // 原有功能区
        _buildApkInstaller(),
        const Divider(),
        _buildPackageQuery(),
        const Divider(),
        _buildCommandLine(),
      ],
    );
  }

  Widget _buildApkInstaller() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('APK 安装', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.apkController,
                decoration: const InputDecoration(
                  labelText: 'APK文件路径',
                  hintText: '请选择要安装的APK文件',
                ),
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['apk'],
                );
                if (mounted &&
                    result != null &&
                    result.files.single.path != null) {
                  widget.apkController.text = result.files.single.path!;
                }
              },
              icon: const Icon(Icons.file_upload),
              label: const Text('选择文件'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => widget.onRunCommand([
                'adb',
                'install',
                widget.apkController.text,
              ]),
              child: const Text('普通安装'),
            ),
            ElevatedButton(
              onPressed: () => widget.onRunCommand([
                'adb',
                'install',
                '--bypass-low-target-sdk-block',
                widget.apkController.text,
              ]),
              child: const Text('低SDK安装'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPackageQuery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('包名查询|管理', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        PackageQueryWidget(
          packageController: widget.appKeywordController,
          onQueryPackages: widget.onQueryPackages,
          packageQueryResult: widget.packageQueryResult,
          showCopyButton: true,
          // 添加应用管理功能按钮
          trailingButtons: (String package) => [
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => widget.onRunCommand([
                'adb',
                'shell',
                'monkey',
                '-p',
                package,
                '-c',
                'android.intent.category.LAUNCHER',
                '1',
              ]),
              tooltip: '打开应用',
            ),
            IconButton(
              icon: const Icon(Icons.stop_circle),
              onPressed: () => widget.onRunCommand([
                'adb',
                'shell',
                'am',
                'force-stop',
                package,
              ]),
              tooltip: '结束应用进程',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  widget.onRunCommand(['adb', 'uninstall', package]),
              tooltip: '卸载应用',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () =>
                  widget.onRunCommand(['adb', 'uninstall', '-k', package]),
              tooltip: '卸载应用(保留数据)',
            ),
          ],
        ),
      ],
    );
  }

  // 添加命令行部分的实现
  Widget _buildCommandLine() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ADB 命令行', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'ADB 命令',
                  hintText: '输入要执行的 ADB 命令',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                if (_commandController.text.isNotEmpty) {
                  try {
                    widget.onRunCommand(
                      parseToolCommand(_commandController.text),
                    );
                    _commandController.clear();
                  } on FormatException catch (error) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                }
              },
              child: const Text('执行'),
            ),
          ],
        ),
      ],
    );
  }

  // 设备状态与内存监控
  Widget _buildDeviceStatusMonitor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '设备状态',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _monitorError == null ? 'ADB数据源' : '设备读取失败',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _manualRefresh,
                      tooltip: '手动刷新',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
            Text(
              _monitorError ?? '内存与进程资源使用情况',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildMemoryTrend(context),
          ],
        ),
      ),
    );
  }

  // 内存使用情况 - 单根多色条形图
  Widget _buildMemoryTrend(BuildContext context) {
    if (_monitorError != null) return const Text('内存信息不可用');
    if (_memoryInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    int totalMemory = _memoryInfo!.memTotal;
    int usedMemory = _memoryInfo!.usedMemory;
    int availableMemory = _memoryInfo!.memAvailable;
    int buffers = _memoryInfo!.buffers;
    int cached = _memoryInfo!.cached;
    int otherUsed = usedMemory - buffers - cached;

    // 计算百分比
    double otherUsedPercent = otherUsed / totalMemory;
    double buffersPercent = buffers / totalMemory;
    double cachedPercent = cached / totalMemory;
    double availablePercent = availableMemory / totalMemory;
    double usedPercent = usedMemory / totalMemory;

    final colorScheme = Theme.of(context).colorScheme;

    // 内存类型数据 - 使用主题颜色方案
    final memoryTypes = [
      {
        'name': '已用内存',
        'value': otherUsed,
        'percent': otherUsedPercent,
        'color': colorScheme.primary,
      },
      {
        'name': 'Buffers',
        'value': buffers,
        'percent': buffersPercent,
        'color': colorScheme.secondary,
      },
      {
        'name': 'Cached',
        'value': cached,
        'percent': cachedPercent,
        'color': colorScheme.tertiary,
      },
      {
        'name': '可用内存',
        'value': availableMemory,
        'percent': availablePercent,
        'color': colorScheme.surfaceContainerHighest,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 内存基本信息
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总内存: ${_memoryInfo!.totalMemoryGB.toStringAsFixed(2)} GB',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '可用内存: ${_memoryInfo!.availableMemoryGB.toStringAsFixed(2)} GB',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 合并的多色条形图
            _buildCombinedMemoryBar(memoryTypes),
            const SizedBox(height: 16),

            // 内存类型图例
            _buildMemoryLegend(context, memoryTypes),
            const SizedBox(height: 12),

            // 内存使用率
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '内存使用率: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${(usedPercent * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: usedPercent > 0.8
                            ? colorScheme.error
                            : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Text(
                  '已用: ${_memoryInfo!.usedMemoryGB.toStringAsFixed(2)} GB',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建合并的多色条形图
  Widget _buildCombinedMemoryBar(List<Map<String, dynamic>> memoryTypes) {
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // 背景
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.grey[300],
            ),
          ),

          // 多色条形
          LayoutBuilder(
            builder: (context, constraints) {
              double currentX = 0;
              List<Widget> barSegments = [];

              for (int i = 0; i < memoryTypes.length; i++) {
                var memoryType = memoryTypes[i];
                double width = memoryType['percent'] * constraints.maxWidth;

                // 只在两端使用半圆端点，中间方形相连
                BorderRadius borderRadius;
                if (i == 0) {
                  // 第一个内存类型，左上角和左下角圆角
                  borderRadius = const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  );
                } else if (i == memoryTypes.length - 1) {
                  // 最后一个内存类型，右上角和右下角圆角
                  borderRadius = const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  );
                } else {
                  // 中间的内存类型，没有圆角
                  borderRadius = BorderRadius.zero;
                }

                barSegments.add(
                  Positioned(
                    left: currentX,
                    top: 0,
                    width: width,
                    height: constraints.maxHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        color: memoryType['color'],
                      ),
                    ),
                  ),
                );
                currentX += width;
              }

              return Stack(children: barSegments);
            },
          ),
        ],
      ),
    );
  }

  // 构建内存类型图例
  Widget _buildMemoryLegend(
    BuildContext context,
    List<Map<String, dynamic>> memoryTypes,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: memoryTypes.map((memoryType) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: memoryType['color'],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${memoryType['name']}: ${(memoryType['value'] / 1024 / 1024).toStringAsFixed(2)} GB',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // 进程管理
  Widget _buildProcessManagement() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '运行中进程',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    // 按PID排序按钮
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (_sortType == SortType.pidAsc) {
                            _sortType = SortType.pidDesc;
                          } else if (_sortType == SortType.pidDesc) {
                            _sortType = SortType.none;
                          } else {
                            _sortType = SortType.pidAsc;
                          }
                          _applySort(_processList);
                        });
                      },
                      child: Text(
                        _getSortButtonText(
                          SortType.pidAsc,
                          SortType.pidDesc,
                          '按PID排序',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 按CPU排序按钮
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (_sortType == SortType.cpuAsc) {
                            _sortType = SortType.cpuDesc;
                          } else if (_sortType == SortType.cpuDesc) {
                            _sortType = SortType.none;
                          } else {
                            _sortType = SortType.cpuAsc;
                          }
                          _applySort(_processList);
                        });
                      },
                      child: Text(
                        _getSortButtonText(
                          SortType.cpuAsc,
                          SortType.cpuDesc,
                          '按CPU排序',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 按内存排序按钮
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (_sortType == SortType.memoryAsc) {
                            _sortType = SortType.memoryDesc;
                          } else if (_sortType == SortType.memoryDesc) {
                            _sortType = SortType.none;
                          } else {
                            _sortType = SortType.memoryAsc;
                          }
                          _applySort(_processList);
                        });
                      },
                      child: Text(
                        _getSortButtonText(
                          SortType.memoryAsc,
                          SortType.memoryDesc,
                          '按内存排序',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _manualRefresh,
                      tooltip: '手动刷新',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProcessFilterBar(),
            const SizedBox(height: 16),
            _buildProcessTable(),
          ],
        ),
      ),
    );
  }

  // 进程过滤栏
  Widget _buildProcessFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text("筛选: ", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8.0,
            children: [
              _buildFilterChip('普通应用', ProcessCategory.userApp),
              _buildFilterChip('系统进程', ProcessCategory.systemApp),
              _buildFilterChip('其他/底层', ProcessCategory.other),
              _buildFilterChip('全部', ProcessCategory.all),
            ],
          ),
        ],
      ),
    );
  }

  // 构建筛选芯片
  Widget _buildFilterChip(String label, ProcessCategory category) {
    final isSelected = _selectedCategory == category;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedCategory = category;
          });
        }
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue,
    );
  }

  // 进程表
  Widget _buildProcessTable() {
    if (_monitorError != null) return const Text('进程信息不可用，请刷新重试');
    if (_monitorReady && _processList.isEmpty) return const Text('未发现进程');
    if (_processList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 获取过滤后的进程列表
    List<ProcessInfo> filteredProcesses = _getFilteredProcesses();

    // 根据折叠状态决定显示多少个进程
    List<ProcessInfo> displayProcesses = filteredProcesses;
    if (_isProcessListCollapsed && filteredProcesses.length > 3) {
      displayProcesses = filteredProcesses.sublist(0, 3);
    }

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('PID')),
              DataColumn(label: Text('UID')),
              DataColumn(label: Text('CPU (%)')),
              DataColumn(label: Text('RSS (KB)')),
              DataColumn(label: Text('包名')),
              DataColumn(label: Text('类型')),
              DataColumn(label: Text('状态')),
              DataColumn(label: Text('操作')),
            ],
            rows: displayProcesses.map((process) {
              return DataRow(
                cells: [
                  DataCell(Text(process.pid)),
                  DataCell(Text(process.uid)),
                  DataCell(Text(process.cpu)),
                  DataCell(Text(process.rss)),
                  DataCell(Text(process.package)),
                  DataCell(Text(process.type)),
                  DataCell(Text(process.status)),
                  DataCell(
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: !_monitorReady
                              ? null
                              : () {
                                  _showProcessActionDialog(
                                    'Kill PID',
                                    '确定要终止进程 ${process.pid} 吗？',
                                    () {
                                      _runProcessAction([
                                        'adb',
                                        'shell',
                                        'kill',
                                        process.pid,
                                      ]);
                                    },
                                  );
                                },
                          child: const Text('Kill'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: !_monitorReady
                              ? null
                              : () {
                                  _showProcessActionDialog(
                                    '停止应用',
                                    '确定要停止应用 ${process.package} 吗？',
                                    () {
                                      _runProcessAction([
                                        'adb',
                                        'shell',
                                        'am',
                                        'force-stop',
                                        process.package,
                                      ]);
                                    },
                                  );
                                },
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        if (filteredProcesses.length > 3) ...[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isProcessListCollapsed = !_isProcessListCollapsed;
              });
            },
            child: Text(_isProcessListCollapsed ? '显示全部进程' : '收起进程列表'),
          ),
        ],
      ],
    );
  }

  // 根据选中的分类获取过滤后的进程列表
  List<ProcessInfo> _getFilteredProcesses() {
    if (_selectedCategory == ProcessCategory.all) return _processList;

    return _processList
        .where((p) => _classifyProcess(p) == _selectedCategory)
        .toList();
  }

  Future<void> _runProcessAction(List<String> command) async {
    if (!mounted || !_monitorReady) return;
    try {
      final result = await widget.session.run(
        command,
        cancellation: _cancellation,
      );
      if (result.exitCode != 0) throw StateError(result.stderr.toString());
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  // 进程操作确认对话框
  void _showProcessActionDialog(
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (mounted && _monitorReady) onConfirm();
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}

// 内存趋势图表绘制 - 堆叠面积图
class MemoryRatioTrendPainter extends CustomPainter {
  final List<MemorySnapshot> snapshots;

  MemoryRatioTrendPainter(this.snapshots);

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.isEmpty) return;

    final usedPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final freePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // 绘制"总容量"（背景）
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), freePaint);

    // 绘制"已用容量"波浪
    final path = Path();
    double stepX =
        size.width / (snapshots.length > 1 ? snapshots.length - 1 : 1);

    for (int i = 0; i < snapshots.length; i++) {
      final snapshot = snapshots[i];
      // 计算高度比例：已用 / 总量
      double ratio = snapshot.usedGB / snapshot.totalGB;
      if (ratio > 1.0) ratio = 1.0;

      double x = i * stepX;
      double y = size.height * (1 - ratio); // y轴向下为正，所以要用 1-ratio

      if (i == 0) {
        path.moveTo(x, size.height); // 起点底部
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 闭合路径到底部
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, usedPaint);

    // 可选：绘制文字标签 (显示当前最新占比)
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${(snapshots.last.usageRatio * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 8, 8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

// 扩展 Switch 组件以支持文本
class SwitchWidget extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String activeText;
  final String inactiveText;

  const SwitchWidget({
    super.key,
    required this.value,
    required this.onChanged,
    required this.activeText,
    required this.inactiveText,
  });

  @override
  State<SwitchWidget> createState() => _SwitchWidgetState();
}

class _SwitchWidgetState extends State<SwitchWidget> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.value ? widget.activeText : widget.inactiveText),
        const SizedBox(width: 8),
        Switch(value: widget.value, onChanged: widget.onChanged),
      ],
    );
  }
}
