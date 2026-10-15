import '../../tools/services/device_session.dart';
import '../../tools/services/tool_cancellation.dart';

class DeviceInfoService {
  const DeviceInfoService();
  Future<Map<String, String>> load(
    DeviceSession session,
    ToolCancellation cancellation,
  ) async {
    Future<String> read(List<String> args) async => (await session.run([
      'adb',
      'shell',
      ...args,
    ], cancellation: cancellation)).stdout.toString().trim();
    final model = await read(['getprop', 'ro.product.model']);
    final version = await read(['getprop', 'ro.build.version.release']);
    final screen = await read(['wm', 'size']);
    final memory = await read(['cat', '/proc/meminfo']);
    final storage = await read(['df', '/storage/emulated']);
    final abi = await read(['getprop', 'ro.product.cpu.abi']);
    final battery = await read(['dumpsys', 'battery']);
    final mem = RegExp(
      r'^MemTotal:\s*(\d+)\s+kB',
      multiLine: true,
    ).firstMatch(memory);
    final level = RegExp(
      r'^\s*level:\s*(\d+)\s*$',
      multiLine: true,
    ).firstMatch(battery);
    final size = RegExp(r'Physical size:\s*(\d+x\d+)').firstMatch(screen);
    var disk = '未知';
    for (final line in storage.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6 || !parts.last.startsWith('/storage/emulated')) {
        continue;
      }
      final values = parts.sublist(1, 4).map(int.tryParse).toList();
      if (values.any((value) => value == null || value < 0)) continue;
      String format(int value) =>
          '${(value / 1024 / 1024).toStringAsFixed(2)} GB';
      disk =
          '总:${format(values[0]!)} 已用:${format(values[1]!)} 可用:${format(values[2]!)}';
      break;
    }
    return {
      'model': model.isEmpty ? '未知' : model,
      'android_version': version.isEmpty ? '未知' : version,
      'screen_size': size?[1] ?? '未知',
      'memory': mem == null
          ? '未知'
          : '${(int.parse(mem[1]!) / 1024 / 1024).toStringAsFixed(2)} GB',
      'storage': disk,
      'cpu_abi': abi.isEmpty ? '未知' : abi,
      'battery': level == null ? '未知' : '${level[1]}%',
    };
  }
}
