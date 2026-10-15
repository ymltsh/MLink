import '../models/process_info.dart';
import '../models/device_memory_info.dart';
import './process_data_source.dart';
import 'dart:math';

class MockProcessDataSource implements ProcessDataSource {
  final Random _random = Random();
  int _foregroundIndex = 0;

  @override
  Future<List<ProcessInfo>> fetchProcesses() async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 100));

    // 模拟进程列表
    final processes = [
      ProcessInfo(
        pid: '1234',
        uid: '1000',
        name: 'com.example.app',
        rss: '${102400 + _random.nextInt(10000)}',
        cpu: '${_random.nextInt(20)}.${_random.nextInt(10)}',
        package: 'com.example.app',
        type: 'App',
        status: _foregroundIndex == 0 ? '前台' : '后台',
      ),
      ProcessInfo(
        pid: '5678',
        uid: '1001',
        name: 'com.android.systemui',
        rss: '${51200 + _random.nextInt(5000)}',
        cpu: '${_random.nextInt(10)}.${_random.nextInt(10)}',
        package: 'com.android.systemui',
        type: 'System',
        status: _foregroundIndex == 1 ? '前台' : '后台',
      ),
      ProcessInfo(
        pid: '9012',
        uid: '1002',
        name: 'com.google.android.gms',
        rss: '${76800 + _random.nextInt(8000)}',
        cpu: '${_random.nextInt(15)}.${_random.nextInt(10)}',
        package: 'com.google.android.gms',
        type: 'System',
        status: _foregroundIndex == 2 ? '前台' : '后台',
      ),
      ProcessInfo(
        pid: '3456',
        uid: '1003',
        name: 'com.android.settings',
        rss: '${38400 + _random.nextInt(6000)}',
        cpu: '${_random.nextInt(8)}.${_random.nextInt(10)}',
        package: 'com.android.settings',
        type: 'App',
        status: _foregroundIndex == 3 ? '前台' : '后台',
      ),
    ];

    // 模拟前台进程轮换
    _foregroundIndex = (_foregroundIndex + 1) % processes.length;

    return processes;
  }

  @override
  Future<DeviceMemoryInfo> fetchMemoryInfo() async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 100));

    // 模拟内存信息，值随时间缓慢变化
    final baseTotal = 8192000; // 8GB
    final baseAvailable = 4096000 + _random.nextInt(512000); // 4GB ± 500MB
    final baseBuffers = 512000 + _random.nextInt(102400); // 500MB ± 100MB
    final baseCached = 1024000 + _random.nextInt(204800); // 1GB ± 200MB

    return DeviceMemoryInfo(
      memTotal: baseTotal,
      memAvailable: baseAvailable,
      buffers: baseBuffers,
      cached: baseCached,
    );
  }

  @override
  Future<String> getForegroundPackage() async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 50));

    // 模拟前台包名
    final packages = [
      'com.example.app',
      'com.android.systemui',
      'com.google.android.gms',
      'com.android.settings',
    ];

    return packages[_foregroundIndex % packages.length];
  }
}
