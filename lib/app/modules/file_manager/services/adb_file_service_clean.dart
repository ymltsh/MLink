import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process_run/process_run.dart';
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
  AdbFileService({this.deviceSerial});

  /// 基础 ADB 命令参数
  List<String> _baseAdbArgs() {
    if (deviceSerial == null || deviceSerial!.isEmpty) return ['adb'];
    return ['adb', '-s', deviceSerial!];
  }

  /// 执行 Shell 命令的核心方法（增强了日志和错误处理）
  Future<ProcessResult> _runShell(String cmd, {bool useRoot = false}) async {
    // 1. 构造完整的 adb shell 命令
    final shellCmd = useRoot ? 'su -c "$cmd"' : cmd;
    final args = List<String>.from(_baseAdbArgs())..addAll(['shell', shellCmd]);

    try {
      // 2. 打印调试日志（这是真正的完整命令）
      print('DEBUG_EXEC: ${args.join(' ')}');

      // 关键修改：添加 stdoutEncoding: utf8，强制使用 UTF-8 解码防止中文乱码
      final result = await runExecutableArguments(
        args.first,
        args.sublist(1),
        stdoutEncoding: utf8,
      );

      // 3. 如果有标准错误输出，也打印出来
      if (result.stderr.toString().isNotEmpty) {
        print('DEBUG_ERR: ${result.stderr}');
      }

      return result;
    } catch (e) {
      print('DEBUG_CRASH: $e');
      throw ADBFileServiceException('执行命令失败: $e');
    }
  }

  /// 列出文件列表（使用“锚点解析法”，不再依赖正则）
  Future<List<FileEntry>> ls(String remotePath, {bool useRoot = false}) async {
    // 1. 标准化并强制以 / 结尾 (解决 symlink 只显示自身的问题)
    var targetPath = p.posix.normalize(remotePath);
    if (!targetPath.endsWith('/')) {
      targetPath += '/';
    }

    // 使用 ls -l 而不是 -al，避免 . 和 .. 的干扰，同时格式稍微统一一点
    // -L 参数尝试解引用链接（部分 Android 可能不支持，不支持也没关系，只是报错）
    final cmd = 'ls -l "${targetPath.replaceAll('\"', '\\\"')}"';

    final res = await _runShell(cmd, useRoot: useRoot);
    final out = res.stdout.toString();

    if (out.isEmpty) {
      // 如果 stdout 为空，检查一下 stderr，如果也为空，说明目录可能是空的
      return [];
    }

    return _parseLsSmart(out, targetPath);
  }

  /// 智能解析算法
  List<FileEntry> _parseLsSmart(String output, String parentPath) {
    // DEBUG: 打印原始 ls 输出，便于排查解析问题
    try {
      print('DEBUG_LS_RAW:\n${output}');
    } catch (_) {}
    // 确保 parentPath 已标准化
    final normalizedParent = p.posix.normalize(parentPath);
    final lines = output.split('\n');
    final entries = <FileEntry>[];

    for (var line in lines) {
      line = line.trim();
      // 跳过 total 行或空行
      if (line.isEmpty || line.toLowerCase().startsWith('total')) continue;

      // 按空白字符分割
      final parts = line.split(RegExp(r'\s+'));

      // 如果分割后少于4部分，说明信息严重缺失，跳过
      if (parts.length < 4) continue;

      try {
        // --- 核心逻辑：寻找“时间锚点” ---
        // 大多数 ls 输出格式：[权限] [用户/组/大小...] [日期] [时间] [文件名]
        // 时间通常包含冒号 (HH:MM)，我们在倒数几列里找带冒号的
        
        int timeIndex = -1;
        // 从后往前找，防止文件名里带冒号干扰（虽然文件名在最后，但倒序找更稳）
        // 通常文件名是最后一部分，时间是倒数第二部分(或倒数第三部分)
        // 限制查找范围在 parts 的后半段
        for (int i = parts.length - 2; i >= 0; i--) {
          if (parts[i].contains(':') && parts[i].length >= 3) {
            timeIndex = i;
            break;
          }
          // 兼容有些 ls 只显示年份的情况 (e.g. 2023)
          if (RegExp(r'^\d{4}$').hasMatch(parts[i])) {
            timeIndex = i; // 暂定这个是时间（年份）
            // 如果它后面那个也是时间（比如 HH:MM），那它可能只是日期，继续往后看一眼
             if (i + 1 < parts.length && parts[i+1].contains(':')) {
               timeIndex = i + 1;
             }
            break;
          }
        }

        // 如果实在找不到时间锚点，只能盲猜倒数第1个是文件名
        if (timeIndex == -1) {
          timeIndex = parts.length - 2; 
        }

        // --- 提取数据 ---

        // 1. 权限 (第一列)
        final permission = parts[0];
        final isDir = permission.startsWith('d');
        final isLink = permission.startsWith('l');

        // 2. 文件名 (时间锚点之后的所有部分拼接)
        // sublist 的 end 不包含，所以从 timeIndex + 1 开始
        var rawName = parts.sublist(timeIndex + 1).join(' ');
        
        String name = rawName;
        String? linkTarget;

        // 处理软链接 "name -> target"
        if (isLink && rawName.contains(' -> ')) {
          final linkParts = rawName.split(' -> ');
          name = linkParts[0];
          if (linkParts.length > 1) {
            linkTarget = linkParts.sublist(1).join(' -> ');
          }
        }

        // 3. 大小
        // 通常在时间锚点的前面。可能是 timeIndex - 1 (如果日期只有一列) 或 timeIndex - 2 (如果日期有两列 Date+Time)
        // 我们尝试解析 timeIndex - 1 和 timeIndex - 2，哪个是数字就是哪个
        int size = 0;
        if (timeIndex - 1 > 0) {
           // 优先尝试倒数第一个非时间列
           size = int.tryParse(parts[timeIndex - 1]) ?? 0;
           // 如果解析失败（可能是 "Nov" 这种月份），再往前试
           if (size == 0 && timeIndex - 2 > 0) {
             size = int.tryParse(parts[timeIndex - 2]) ?? 0;
           }
        }

        // 4. 时间
        // 简单处理，直接给个当前时间，或者尝试解析字符串
        DateTime modifiedTime = DateTime.now();
        
        // 构造完整路径（使用已标准化的 parent）
        final fullPath = p.posix.join(normalizedParent, name);

        // 解析成功，打印解析结果便于调试
        try {
          print('DEBUG_PARSED: Name=$name, Date=$modifiedTime, Size=$size');
        } catch (_) {}

        entries.add(FileEntry(
          name: name,
          path: fullPath,
          isDirectory: isDir,
          size: size,
          permission: permission,
          linkTarget: linkTarget,
          modifiedTime: modifiedTime,
        ));
      } catch (e) {
        // 如果解析失败，打印出错的行与异常信息
        try {
          print('DEBUG_PARSE_ERROR: Line=[${line}], Error=$e');
        } catch (_) {}
        continue;
      }
    }

    // 排序
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return entries;
  }

  Stream<double> push(String localPath, String remotePath, {bool useRoot = false}) async* {
    final targetRemote = p.posix.normalize(remotePath);
    final args = List<String>.from(_baseAdbArgs())..addAll(['push', localPath, targetRemote]);
    try {
      final proc = await Process.start(args.first, args.sublist(1));
      final controller = StreamController<double>();

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final m = RegExp(r'(\d+)%').firstMatch(line);
        if (m != null) {
          final pct = double.tryParse(m.group(1)!) ?? 0.0;
          controller.add(pct / 100.0);
        }
      });
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final m = RegExp(r'(\d+)%').firstMatch(line);
        if (m != null) {
          final pct = double.tryParse(m.group(1)!) ?? 0.0;
          controller.add(pct / 100.0);
        }
      });

      final exitCode = await proc.exitCode;
      if (exitCode != 0) {
        controller.addError(ADBFileServiceException('adb push 失败，exit code: $exitCode'));
      }
      await controller.close();
      yield* controller.stream;
    } catch (e) {
      throw ADBFileServiceException('adb push 异常: $e');
    }
  }

  Stream<double> pull(String remotePath, String localPath, {bool useRoot = false}) async* {
    final targetRemote = p.posix.normalize(remotePath);
    final args = List<String>.from(_baseAdbArgs())..addAll(['pull', targetRemote, localPath]);
    try {
      final proc = await Process.start(args.first, args.sublist(1));
      final controller = StreamController<double>();

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final m = RegExp(r'(\d+)%').firstMatch(line);
        if (m != null) controller.add(double.parse(m.group(1)!) / 100.0);
      });
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final m = RegExp(r'(\d+)%').firstMatch(line);
        if (m != null) controller.add(double.parse(m.group(1)!) / 100.0);
      });

      final exitCode = await proc.exitCode;
      if (exitCode != 0) {
        controller.addError(ADBFileServiceException('adb pull 失败，exit code: $exitCode'));
      }
      await controller.close();
      yield* controller.stream;
    } catch (e) {
      throw ADBFileServiceException('adb pull 异常: $e');
    }
  }

  Future<void> delete(String remotePath, {bool useRoot = false}) async {
    final target = p.posix.normalize(remotePath);
    final cmd = 'rm -rf "${target.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('删除失败: ${res.stderr}');
  }

  Future<void> mkdir(String remotePath, {bool useRoot = false}) async {
    final target = p.posix.normalize(remotePath);
    final cmd = 'mkdir -p "${target.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('创建目录失败: ${res.stderr}');
  }

  Future<void> rename(String from, String to, {bool useRoot = false}) async {
    final src = p.posix.normalize(from);
    final dst = p.posix.normalize(to);
    final cmd = 'mv "${src.replaceAll('"', '\\"')}" "${dst.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('重命名失败: ${res.stderr}');
  }

  Future<List<FileEntry>> search(String remotePath, String query, {bool useRoot = false}) async {
    final target = p.posix.normalize(remotePath);
    final cmd = 'find "${target.replaceAll('"', '\\"')}" -name "*$query*" -maxdepth 5 2>/dev/null';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('查找失败: ${res.stderr}');
    final lines = res.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final results = <FileEntry>[];
    for (var line in lines) {
      final name = p.posix.basename(line);
      results.add(FileEntry(name: name, path: line.trim(), isDirectory: line.endsWith('/')));
    }
    return results;
  }
}
