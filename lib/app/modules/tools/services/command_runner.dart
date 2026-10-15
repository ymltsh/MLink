import 'dart:convert';
import 'dart:io';
import 'tool_cancellation.dart';
import 'tool_process.dart';

typedef CommandExecution =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      ToolCancellation? cancellation,
    );

/// 短命令统一处理编码、退出码和取消；长任务使用各自的会话服务。
class CommandRunner {
  final CommandExecution? _execute;
  const CommandRunner({CommandExecution? execute}) : _execute = execute;

  Future<ProcessResult> run(
    List<String> command, {
    ToolCancellation? cancellation,
  }) async {
    if (command.isEmpty || !['adb', 'scrcpy'].contains(command.first)) {
      throw ArgumentError('只支持 ADB / scrcpy 命令');
    }
    cancellation?.check();
    final arguments = List<String>.of(command.skip(1));
    final encoding = command.contains('shell') ? utf8 : systemEncoding;
    final result = _execute == null
        ? await runToolExecutable(
            command.first,
            arguments,
            cancellation: cancellation,
            stdoutEncoding: encoding,
            stderrEncoding: encoding,
          )
        : await _execute(command.first, arguments, cancellation);
    cancellation?.check();
    check(result, command.first);
    return result;
  }

  static void check(ProcessResult result, String executable) {
    if (result.exitCode != 0) {
      // 不在异常中附带参数，避免配对码等内容进入日志。
      throw ProcessException(
        executable,
        const [],
        '命令失败（退出码 ${result.exitCode}）：${result.stderr}',
        result.exitCode,
      );
    }
  }
}
