import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'tool_process.dart';
import 'tool_cancellation.dart';

/// 一个投屏窗口对应一个进程；启动期间也计入会话，避免重复启动。
class MirrorSession extends ChangeNotifier {
  final Future<Process> Function(String, List<String>) _start;
  final void Function(String) onLog;
  Process? _process;
  bool _active = false;
  bool _stopping = false;
  bool _disposed = false;
  Completer<void>? _done;
  ToolCancellation? _starting;
  bool get isActive => _active;
  bool get isStopping => _stopping;

  MirrorSession(
      {required this.onLog,
      Future<Process> Function(String, List<String>)? start})
      : _start = start ?? startToolProcess;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _log(String line) {
    if (!_disposed) onLog(line);
  }

  Future<void> start(List<String> command) async {
    if (_disposed) throw StateError('投屏会话已关闭');
    if (_active) throw StateError('已有投屏会话，请先停止');
    _active = true;
    _stopping = false;
    _done = Completer<void>();
    _notify();
    try {
      _starting = ToolCancellation();
      _process = await startToolWithin(command.first, command.sublist(1),
          start: _start, cancellation: _starting);
      if (_stopping || _disposed) _process!.kill();
      _log('投屏进程已启动');
      unawaited(_watch(_process!));
    } catch (error) {
      final cancelled = error is ToolCancelled && _stopping;
      _active = false;
      _stopping = false;
      _done!.complete();
      _notify();
      if (cancelled) {
        _log('投屏启动已取消');
        return;
      }
      rethrow;
    }
  }

  Future<void> _watch(Process process) async {
    final subscriptions = <StreamSubscription<String>>[];
    final drained = <Completer<void>>[];
    void read(Stream<List<int>> stream) {
      final done = Completer<void>();
      drained.add(done);
      subscriptions.add(stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_log, onError: (Object error) {
        _log('读取投屏输出失败：$error');
        process.kill();
        if (!done.isCompleted) done.complete();
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }));
    }

    read(process.stdout);
    read(process.stderr);
    try {
      final code = await process.exitCode;
      // 防止子进程继承管道后，投屏已经退出但输出流一直未关闭。
      await Future.wait(drained.map((done) => done.future))
          .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      _log(_stopping ? '投屏已停止' : '投屏已结束，退出码 $code');
    } catch (error) {
      process.kill();
      _log('投屏异常：$error');
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      _process = null;
      _active = false;
      _stopping = false;
      _done!.complete();
      _notify();
    }
  }

  Future<void> stop() async {
    if (!_active) return;
    _stopping = true;
    _notify();
    _starting?.cancel();
    if (_process != null && !_process!.kill()) {
      _stopping = false;
      _log('无法停止投屏进程，请关闭投屏窗口后重试');
      _notify();
      return;
    }
    await _done!.future;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_active) {
      _stopping = true;
      _starting?.cancel();
      _process?.kill();
    }
    super.dispose();
  }
}
