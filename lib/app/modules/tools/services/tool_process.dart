import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool_environment.dart';
import 'tool_cancellation.dart';

/// 只记录本应用实际持有的 ADB 客户端句柄，不推断共享 ADB 服务归属。
class OwnedAdbProcesses {
  final Set<Process> _processes = {};

  void track(Process process) {
    _processes.add(process);
    process.exitCode.then((_) => _processes.remove(process),
        onError: (Object _) => _processes.remove(process));
  }

  int clean() {
    var count = 0;
    for (final process in _processes.toList()) {
      if (process.kill()) count++;
    }
    return count;
  }
}

final ownedAdbProcesses = OwnedAdbProcesses();

Future<ProcessResult> runToolExecutable(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  Duration timeout = const Duration(seconds: 30),
  ToolCancellation? cancellation,
  Future<Process> Function(String, List<String>)? start,
  bool checkExitCode = true,
}) async {
  cancellation?.check();
  final process = await startToolWithin(executable, arguments,
      start: start, cancellation: cancellation, timeout: timeout);
  final out = <int>[];
  final err = <int>[];
  final limit = 16 * 1024 * 1024;
  final completion = Completer<ProcessResult>();
  bool exited = false;
  final subscriptions = <StreamSubscription<List<int>>>[];
  final streamDone = <Completer<void>>[];
  void fail(Object error, [StackTrace? stack]) {
    if (completion.isCompleted) return;
    if (!exited) process.kill();
    completion.completeError(error, stack);
  }

  void cancel() => fail(ToolCancelled());
  void collect(Stream<List<int>> stream, List<int> buffer) {
    final done = Completer<void>();
    streamDone.add(done);
    subscriptions.add(stream.listen((chunk) {
      if (buffer.length + chunk.length > limit) {
        fail(StateError('命令输出超过 16 MiB 限制'));
      } else {
        buffer.addAll(chunk);
      }
    }, onError: (Object error, StackTrace stack) {
      fail(error, stack);
      if (!done.isCompleted) done.complete();
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    }));
  }

  collect(process.stdout, out);
  collect(process.stderr, err);
  final timer = Timer(timeout, () => fail(TimeoutException('命令执行超时', timeout)));
  cancellation?.add(cancel);
  Future<void> complete() async {
    try {
      final code = await process.exitCode;
      exited = true;
      // exitCode 可能先于输出管道关闭；等待两个 onDone 后才解码。
      await Future.wait(streamDone.map((s) => s.future));
      if (completion.isCompleted) return;
      cancellation?.check();
      final result = ProcessResult(
          process.pid,
          code,
          stdoutEncoding?.decode(out) ?? out,
          stderrEncoding?.decode(err) ?? err);
      if (checkExitCode && code != 0) {
        throw ProcessException(
            executable, const [], '命令失败（退出码 $code）：${result.stderr}', code);
      }
      completion.complete(result);
    } catch (error, stack) {
      fail(error, stack);
    }
  }

  unawaited(complete());
  try {
    return await completion.future;
  } finally {
    timer.cancel();
    cancellation?.remove(cancel);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final done in streamDone) {
      if (!done.isCompleted) done.complete();
    }
  }
}

/// 启动期间也响应取消/超时；迟到的进程句柄会立即被终止。
Future<Process> startToolWithin(
  String executable,
  List<String> arguments, {
  Future<Process> Function(String, List<String>)? start,
  ToolCancellation? cancellation,
  Duration timeout = const Duration(seconds: 30),
}) async {
  cancellation?.check();
  final ready = Completer<Process>();
  void cancel() {
    if (!ready.isCompleted) ready.completeError(ToolCancelled());
  }

  final timer = Timer(timeout, () {
    if (!ready.isCompleted) {
      ready.completeError(TimeoutException('启动命令超时', timeout));
    }
  });
  cancellation?.add(cancel);
  try {
    final pending = Future<Process>.sync(
        () => (start ?? startToolProcess)(executable, arguments));
    pending.then((process) {
      if (ready.isCompleted) {
        process.kill();
      } else {
        ready.complete(process);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    });
    return await ready.future;
  } finally {
    timer.cancel();
    cancellation?.remove(cancel);
  }
}

Future<ProcessResult> runToolProcess(
        String executable, List<String> arguments) =>
    runToolExecutable(executable, arguments);

Future<Process> startToolProcess(
    String executable, List<String> arguments) async {
  final environment = ToolEnvironment.instance;
  final lease = await environment.acquireLease();
  try {
    final process = await Process.start(
        environment.executableIn(lease?.directory, executable), arguments,
        environment: environment.environmentIn(lease?.directory));
    if (executable == 'adb') ownedAdbProcesses.track(process);
    if (lease != null) {
      unawaited(process.exitCode
          .then<void>((_) => lease.release(),
              onError: (Object _) => lease.release())
          .catchError((Object _) {/* 保留缓存供下次回收，不影响命令结果。 */}));
    }
    return process;
  } catch (_) {
    await lease?.release();
    rethrow;
  }
}
