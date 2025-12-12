import 'dart:io';
import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScreenshotService {
  static const _remoteTmpPath = '/sdcard/tmp_screen.png';
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
    final ts = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'Screenshot_$ts.png';
  }

  /// Captures screen from device with [serial], pulls to local screenshots folder,
  /// removes remote temp file, and returns the local File.
  Future<File> captureScreen(String serial) async {
    final dir = await _ensureLocalDir();
    final localName = _timestampFilename();
    final localPath = p.join(dir.path, localName);

    // 1. screencap to remote tmp path
    final screencapCmd = ['adb', if (serial.isNotEmpty) '-s', if (serial.isNotEmpty) serial, 'shell', 'screencap', '-p', _remoteTmpPath];
    final screencapResult = await runExecutableArguments(screencapCmd.first, screencapCmd.sublist(1));
    if (screencapResult.exitCode != 0) {
      throw Exception('screencap failed: ${screencapResult.stderr ?? screencapResult.stdout}');
    }

    // 2. pull to local
    final pullCmd = ['adb', if (serial.isNotEmpty) '-s', if (serial.isNotEmpty) serial, 'pull', _remoteTmpPath, localPath];
    final pullResult = await runExecutableArguments(pullCmd.first, pullCmd.sublist(1));
    // Prefer exitCode to determine success; adb may write status to stdout or stderr depending on platform/version.
    if (pullResult.exitCode != 0) {
      // attempt to cleanup remote tmp
      try {
        final rmCmd = ['adb', if (serial.isNotEmpty) '-s', if (serial.isNotEmpty) serial, 'shell', 'rm', _remoteTmpPath];
        await runExecutableArguments(rmCmd.first, rmCmd.sublist(1));
      } catch (_) {}
      final message = (pullResult.stderr ?? pullResult.stdout)?.toString() ?? 'Unknown error';
      throw Exception('Pull failed: $message');
    }

    // ensure local file exists
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      // try fallback: sometimes adb outputs but file path differs; throw informative error
      final msg = (pullResult.stdout ?? pullResult.stderr)?.toString() ?? 'pull completed but file not found';
      throw Exception('Pull succeeded but local file missing: $msg');
    }

    // 3. remove remote tmp
    final rmCmd = ['adb', if (serial.isNotEmpty) '-s', if (serial.isNotEmpty) serial, 'shell', 'rm', _remoteTmpPath];
    try {
      await runExecutableArguments(rmCmd.first, rmCmd.sublist(1));
    } catch (_) {}

    return localFile;
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
