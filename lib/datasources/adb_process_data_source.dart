import 'dart:async';
import 'dart:io';
import '../app/modules/tools/services/device_session.dart';
import '../app/modules/tools/services/tool_cancellation.dart';
import '../models/process_info.dart';
import '../models/device_memory_info.dart';
import './process_data_source.dart';

class AdbProcessDataSource implements ProcessDataSource {
  final DeviceSession session;
  final ToolCancellation? cancellation;

  AdbProcessDataSource({required this.session, this.cancellation});

  @override
  Future<List<ProcessInfo>> fetchProcesses() async => _parseProcessList(
    await _executeCommand([
      'adb',
      'shell',
      'ps',
      '-A',
      '-o',
      'PID,UID,NAME,RSS,PCPU',
    ]),
  );

  @override
  Future<DeviceMemoryInfo> fetchMemoryInfo() async => _parseMemoryInfo(
    await _executeCommand(['adb', 'shell', 'cat', '/proc/meminfo']),
  );

  @override
  Future<String> getForegroundPackage() async => _parseForegroundPackage(
    await _executeCommand(['adb', 'shell', 'dumpsys', 'window']),
  );

  Future<String> _executeCommand(List<String> command) async {
    final result = await session.run(command, cancellation: cancellation);
    if (result.exitCode != 0) {
      throw ProcessException(
        command.first,
        command.sublist(1),
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString();
  }

  List<ProcessInfo> _parseProcessList(String output) {
    final processes = <ProcessInfo>[];
    final lines = output.trim().split('\n');

    // 跳过表头
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 分割行数据
      final parts = line.split(RegExp('\\s+'));
      if (parts.length < 5) continue;

      final pid = parts[0];
      final uid = parts[1];
      final name = parts[2];
      final rss = parts[3];
      final cpu = parts[4];

      // 构建ProcessInfo对象
      processes.add(
        ProcessInfo(
          pid: pid,
          uid: uid,
          name: name,
          rss: rss,
          cpu: cpu,
          package: name,
          type: name.startsWith('com.android') || name.startsWith('com.google')
              ? 'System'
              : 'App',
          status: '后台', // 默认为后台，后续会根据前台包名更新
        ),
      );
    }

    return processes;
  }

  // 解析内存信息
  DeviceMemoryInfo _parseMemoryInfo(String output) {
    final lines = output.trim().split('\n');
    int memTotal = 0;
    int memAvailable = 0;
    int buffers = 0;
    int cached = 0;

    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length < 2) continue;

      final key = parts[0].trim();
      final valueStr = parts[1].trim().split(' ')[0];
      final value = int.tryParse(valueStr) ?? 0;

      switch (key) {
        case 'MemTotal':
          memTotal = value;
          break;
        case 'MemAvailable':
          memAvailable = value;
          break;
        case 'Buffers':
          buffers = value;
          break;
        case 'Cached':
          cached = value;
          break;
      }
    }

    return DeviceMemoryInfo(
      memTotal: memTotal,
      memAvailable: memAvailable,
      buffers: buffers,
      cached: cached,
    );
  }

  // 解析前台包名
  String _parseForegroundPackage(String output) {
    final lines = output.trim().split('\n');

    for (final line in lines) {
      if (line.contains('mCurrentFocus')) {
        final match = RegExp(
          r'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)/',
        ).firstMatch(line);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    }

    return '';
  }
}
