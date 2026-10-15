import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../tools/services/tool_process.dart';
import '../../tools/services/command_runner.dart';
import '../../tools/services/device_session.dart';
import '../../tools/services/shell_quote.dart';
import '../../tools/services/tool_cancellation.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';

class ADBFileServiceException implements Exception {
  final String message;
  ADBFileServiceException(this.message);
  @override
  String toString() => 'ADBFileServiceException: $message';
}

class AdbFileService {
  final String? deviceSerial;

  // 日志流控制器
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  final Future<ProcessResult> Function(String, List<String>)? _run;
  final _cancellation = ToolCancellation();
  final Future<Process> Function(String, List<String>) _start;
  final Set<void Function()> _cancelTransfers = {};
  bool _disposed = false;

  AdbFileService({
    this.deviceSerial,
    Future<ProcessResult> Function(String, List<String>)? run,
    Future<Process> Function(String, List<String>)? start,
  }) : _run = run,
       _start = start ?? startToolProcess;

  // 日志辅助方法
  void _verbose(String msg) {
    if (!_logController.isClosed) _logController.add(msg);
  }

  /// 基础 ADB 命令参数
  List<String> _baseAdbArgs() {
    return DeviceSession(deviceSerial).bind(['adb']);
  }

  /// 执行 Shell 命令的核心方法（增强了日志和错误处理）
  Future<ProcessResult> _runShell(String cmd, {bool useRoot = false}) async {
    if (_disposed) throw StateError('文件服务已关闭');
    final shellCmd = useRoot ? 'su -c ${quotePosix(cmd)}' : cmd;
    final args = List<String>.from(_baseAdbArgs())..addAll(['shell', shellCmd]);
    try {
      _verbose('EXEC: ${args.join(' ')}');
      final result = _run == null
          ? await const CommandRunner().run(args, cancellation: _cancellation)
          : await _run(args.first, args.sublist(1));
      _cancellation.check();
      if (result.stdout.toString().isNotEmpty) {
        _verbose('OUT: ${result.stdout}');
      }
      if (result.stderr.toString().isNotEmpty) {
        _verbose('ERR: ${result.stderr}');
      }
      return result;
    } catch (e) {
      _verbose('CRASH: $e');
      throw ADBFileServiceException('执行命令失败: $e');
    }
  }

  /// 元数据和原始路径分别以 NUL 分隔，文件名不参与文本列解析。
  static const _metadataScript = r'''
for entry do
  meta=$(stat -c '%f %s %Y' -- "$entry") || {
    printf 'ERROR\000%s\000\000' "$entry"
    continue
  }
  directory=0
  [ -d "$entry" ] && directory=1
  printf '%s %s\000%s\000' "$meta" "$directory" "$entry"
  if [ -L "$entry" ]; then readlink -- "$entry"; fi
  printf '\000'
done
''';

  String _findPath(String path) {
    final normalized = p.posix.normalize(path);
    return normalized.startsWith('/') ? normalized : './$normalized';
  }

  Future<List<FileEntry>> ls(String remotePath, {bool useRoot = false}) async {
    final normalized = _findPath(remotePath);
    final target = normalized.endsWith('/') ? normalized : '$normalized/';
    final cmd =
        '[ -d ${quotePosix(target)} ] && [ -r ${quotePosix(target)} ] && [ -x ${quotePosix(target)} ] || exit 1; '
        'find ${quotePosix(target)} -mindepth 1 -maxdepth 1 -exec sh -c ${quotePosix(_metadataScript)} sh {} +';
    return _readEntries(await _runShell(cmd, useRoot: useRoot));
  }

  List<FileEntry> _readEntries(ProcessResult result) {
    if (result.exitCode != 0) {
      throw ADBFileServiceException(
        '读取文件失败（退出码 ${result.exitCode}）：${result.stderr}',
      );
    }
    final output = result.stdout.toString();
    if (output.isEmpty) return [];
    final fields = output.split('\x00');
    if (fields.removeLast().isNotEmpty || fields.length % 3 != 0) {
      throw ADBFileServiceException('设备返回的文件元数据格式不完整');
    }
    final entries = <FileEntry>[];
    for (var i = 0; i < fields.length; i += 3) {
      final header = fields[i].split(' ');
      if (header.length != 4 || header.first == 'ERROR') {
        throw ADBFileServiceException('无法读取文件属性：${fields[i + 1]}');
      }
      final mode = int.tryParse(header[0], radix: 16);
      final size = int.tryParse(header[1]);
      final seconds = int.tryParse(header[2]);
      if (mode == null ||
          size == null ||
          seconds == null ||
          fields[i + 1].isEmpty ||
          !['0', '1'].contains(header[3])) {
        throw ADBFileServiceException('设备返回的文件元数据无效');
      }
      final isLink = mode & 0xf000 == 0xa000;
      final link = fields[i + 2];
      if (isLink && !link.endsWith('\n')) {
        throw ADBFileServiceException('无法读取链接目标');
      }
      entries.add(
        FileEntry(
          name: p.posix.basename(fields[i + 1]),
          path: fields[i + 1],
          isDirectory: header[3] == '1',
          permission: _permissions(mode),
          size: size,
          modifiedTime: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          linkTarget: isLink ? link.substring(0, link.length - 1) : null,
        ),
      );
    }
    entries.sort(
      (a, b) => a.isDirectory != b.isDirectory
          ? (a.isDirectory ? -1 : 1)
          : a.name.compareTo(b.name),
    );
    return entries;
  }

  String _permissions(int mode) {
    final type =
        {
          0x4000: 'd',
          0xa000: 'l',
          0x8000: '-',
          0x2000: 'c',
          0x6000: 'b',
          0x1000: 'p',
          0xc000: 's',
        }[mode & 0xf000] ??
        '?';
    final bits = List.generate(
      9,
      (i) => mode & (1 << (8 - i)) != 0 ? 'rwx'[i % 3] : '-',
    );
    for (var i = 0; i < 3; i++) {
      final index = 2 + i * 3;
      if (mode & (0x800 >> i) != 0) {
        bits[index] = i == 2
            ? (bits[index] == 'x' ? 't' : 'T')
            : (bits[index] == 'x' ? 's' : 'S');
      }
    }
    return type + bits.join();
  }

  Stream<double> push(
    String localPath,
    String remotePath, {
    bool useRoot = false,
  }) => useRoot
      ? Stream.error(ADBFileServiceException('Root 模式暂不支持上传，请关闭 Root 后重试'))
      : _transfer('push', [localPath, p.posix.normalize(remotePath)]);

  Stream<double> pull(
    String remotePath,
    String localPath, {
    bool useRoot = false,
  }) => useRoot
      ? Stream.error(ADBFileServiceException('Root 模式暂不支持下载，请关闭 Root 后重试'))
      : _transfer('pull', [p.posix.normalize(remotePath), localPath]);

  Stream<double> _transfer(String operation, List<String> paths) {
    late StreamController<double> controller;
    Process? process;
    bool cancelled = false;
    bool finished = false;
    void cancel() {
      if (cancelled || finished) return;
      cancelled = true;
      process?.kill();
    }

    Future<void> transfer() async {
      _cancelTransfers.add(cancel);
      try {
        if (_disposed) throw StateError('文件服务已关闭');
        final args = [..._baseAdbArgs(), operation, '-a', ...paths];
        process = await _start(args.first, args.sublist(1));
        if (cancelled || _disposed) {
          process!.kill();
          cancelled = true;
        }
        Future<void> read(Stream<List<int>> stream) async {
          await for (final line
              in stream
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())) {
            _verbose(line);
            final match = RegExp(r'(\d+)%').firstMatch(line);
            if (!cancelled && match != null) {
              controller.add((double.parse(match[1]!) / 100).clamp(0, 1));
            }
          }
        }

        // 同时消费输出并等待退出，确保最后一段输出也已处理。
        final results = await Future.wait<Object?>([
          process!.exitCode,
          read(process!.stdout),
          read(process!.stderr),
        ], eagerError: true);
        final code = results.first as int;
        if (!cancelled && code != 0) {
          throw ADBFileServiceException('adb $operation 失败，退出码: $code');
        }
        if (!cancelled) controller.add(1);
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
        if (!cancelled) process?.kill();
        cancelled = true;
      } finally {
        finished = true;
        _cancelTransfers.remove(cancel);
        // 不等待单订阅流的 done 被消费，避免关闭与订阅互相等待。
        unawaited(controller.close());
      }
    }

    controller = StreamController<double>(
      onListen: () {
        unawaited(transfer());
      },
      onCancel: cancel,
    );
    return controller.stream;
  }

  void dispose() {
    _disposed = true;
    _cancellation.cancel();
    for (final cancel in _cancelTransfers.toList()) {
      cancel();
    }
    _logController.close();
  }

  Future<void> delete(String remotePath, {bool useRoot = false}) async {
    final target = p.posix.normalize(remotePath);
    final cmd = 'rm -rf -- ${quotePosix(target)}';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('删除失败: ${res.stderr}');
  }

  Future<void> mkdir(String remotePath, {bool useRoot = false}) async {
    final target = p.posix.normalize(remotePath);
    final cmd = 'mkdir -p -- ${quotePosix(target)}';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) {
      throw ADBFileServiceException('创建目录失败: ${res.stderr}');
    }
  }

  Future<void> rename(String from, String to, {bool useRoot = false}) async {
    final src = p.posix.normalize(from);
    final dst = p.posix.normalize(to);
    final cmd = 'mv -- ${quotePosix(src)} ${quotePosix(dst)}';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) {
      throw ADBFileServiceException('重命名失败: ${res.stderr}');
    }
  }

  Future<List<FileEntry>> search(
    String remotePath,
    String query, {
    bool useRoot = false,
  }) async {
    final normalized = _findPath(remotePath);
    final target = normalized.endsWith('/') ? normalized : '$normalized/';
    final cmd =
        'find ${quotePosix(target)} -maxdepth 5 -iname ${quotePosix('*$query*')} '
        '-exec sh -c ${quotePosix(_metadataScript)} sh {} +';
    return _readEntries(await _runShell(cmd, useRoot: useRoot));
  }
}
