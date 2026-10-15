import 'dart:io';
import '../../tools/services/device_session.dart';
import '../../tools/services/tool_cancellation.dart';
import '../../tools/services/tool_process.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScreenshotService {
  final _cancellation = ToolCancellation();
  void dispose() => _cancellation.cancel();
  static const _folderName = 'MagicLink_Screenshots';

  Future<Directory> _ensureLocalDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _timestampFilename() {
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'Screenshot_${ts}_${now.microsecondsSinceEpoch}.png';
  }

  /// Captures screen from device with [serial], pulls to local screenshots folder,
  /// removes remote temp file, and returns the local File.
  Future<File> captureScreen(String serial) async {
    if (serial.trim().isEmpty) throw StateError('请先选择设备');
    final dir = await _ensureLocalDir();
    final localName = _timestampFilename();
    final localPath = p.join(dir.path, localName);

    _cancellation.check();
    final command =
        DeviceSession(serial).bind(['adb', 'exec-out', 'screencap', '-p']);
    final result = await runToolExecutable(command.first, command.sublist(1),
        stdoutEncoding: null, cancellation: _cancellation);
    _cancellation.check();
    final bytes = result.stdout as List<int>;
    if (bytes.isEmpty) throw StateError('设备未返回截图数据');
    final file = File(localPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Load history of screenshots (png/jpg) from local screenshots folder, sorted by modified desc.
  Future<List<File>> loadHistory() async {
    final dir = await _ensureLocalDir();
    if (!await dir.exists()) return [];
    final files = dir.listSync().whereType<File>().where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
    }).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Open image with platform default viewer.
  Future<void> openImage(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }
}
