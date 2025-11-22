import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';

class ADBFileServiceException implements Exception {
  final String message;
  ADBFileServiceException(this.message);
  @override
  String toString() => 'ADBFileServiceException: $message';
}

/// 提供与 adb 的文件交互功能：ls/push/pull/delete/mkdir/mv/find
class AdbFileService {
  final String? deviceSerial;
  AdbFileService({this.deviceSerial});

  List<String> _baseAdbArgs() {
    if (deviceSerial == null) return ['adb'];
    return ['adb', '-s', deviceSerial!];
  }

  /// helper: run adb shell <cmd>
  Future<ProcessResult> _runShell(String cmd, {bool useRoot = false}) async {
    final shellCmd = useRoot ? 'su -c "$cmd"' : cmd;
    final args = List<String>.from(_baseAdbArgs())..addAll(['shell', shellCmd]);
    try {
      return await runExecutableArguments(args.first, args.sublist(1));
    } catch (e) {
      throw ADBFileServiceException('执行 shell 命令失败: $e');
    }
  }

  /// 列出目录，解析 ls -al 输出
  Future<List<FileEntry>> ls(String remotePath, {bool useRoot = false}) async {
    final cmd = 'ls -al "${remotePath.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    final out = res.stdout.toString();
    if (out.isEmpty) return [];

    final lines = out.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final entries = <FileEntry>[];

    final regex = RegExp(
      r'^([dlncbsp-][rwx-]{9})\s+(?:(\d+)\s+)?(\S+)\s+(\S+)\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}|\w{3}\s+\d{1,2}\s+(?:\d{4}|\d{2}:\d{2}))\s+(.*)\$',
    );

    for (var line in lines) {
      if (line.startsWith('total')) continue;
      try {
        String? perm;
        int? size;
        String name = '';
        String? linkTarget;
        DateTime? mtime;
        bool isDir = false;

        final m = regex.firstMatch(line);
        if (m != null) {
          perm = m.group(1);
          size = int.tryParse(m.group(5) ?? '0');
          final timeStr = m.group(6)?.trim();
          name = m.group(7)?.trim() ?? '';
          isDir = (perm?.startsWith('d') ?? false);

          if ((perm?.startsWith('l') ?? false) && name.contains(' -> ')) {
            final parts = name.split(' -> ');
            if (parts.isNotEmpty) {
              name = parts[0].trim();
              if (parts.length >= 2) {
                linkTarget = parts.sublist(1).join(' -> ').trim();
              }
            }
          }

          if (timeStr != null) {
            try {
              mtime = DateTime.parse(timeStr);
            } catch (_) {
              mtime = DateTime.fromMillisecondsSinceEpoch(0);
            }
          } else {
            mtime = DateTime.fromMillisecondsSinceEpoch(0);
          }
        } else {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 6) {
            perm = parts[0];
            size = int.tryParse(parts[4]) ?? 0;
            name = parts.sublist(5).join(' ');
            isDir = perm.startsWith('d');
            if ((perm?.startsWith('l') ?? false) && name.contains(' -> ')) {
              final pparts = name.split(' -> ');
              name = pparts[0].trim();
              if (pparts.length >= 2) linkTarget = pparts.sublist(1).join(' -> ').trim();
            }
            mtime = DateTime.fromMillisecondsSinceEpoch(0);
          } else {
            name = line.trim();
            mtime = DateTime.fromMillisecondsSinceEpoch(0);
          }
        }

        final fullPath = p.posix.join(remotePath, name);
        entries.add(FileEntry(
          name: name,
          path: fullPath,
          isDirectory: isDir,
          size: size,
          permission: perm,
          linkTarget: linkTarget,
          modifiedTime: mtime,
        ));
      } catch (e) {
        continue;
      }
    }

    return entries;
  }

  Stream<double> push(String localPath, String remotePath, {bool useRoot = false}) async* {
    final args = List<String>.from(_baseAdbArgs())..addAll(['push', localPath, remotePath]);
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
    final args = List<String>.from(_baseAdbArgs())..addAll(['pull', remotePath, localPath]);
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
    final cmd = 'rm -rf "${remotePath.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('删除失败: ${res.stderr}');
  }

  Future<void> mkdir(String remotePath, {bool useRoot = false}) async {
    final cmd = 'mkdir -p "${remotePath.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('创建目录失败: ${res.stderr}');
  }

  Future<void> rename(String from, String to, {bool useRoot = false}) async {
    final cmd = 'mv "${from.replaceAll('"', '\\"')}" "${to.replaceAll('"', '\\"')}"';
    final res = await _runShell(cmd, useRoot: useRoot);
    if (res.exitCode != 0) throw ADBFileServiceException('重命名失败: ${res.stderr}');
  }

  Future<List<FileEntry>> search(String remotePath, String query, {bool useRoot = false}) async {
    final cmd = 'find "${remotePath.replaceAll('"', '\\"')}" -name "*$query*" -maxdepth 5 2>/dev/null';
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
