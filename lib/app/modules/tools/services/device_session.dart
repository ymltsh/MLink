import 'dart:io';

import 'command_runner.dart';
import 'tool_cancellation.dart';

/// 设备会话固定操作目标，禁止依赖 ADB 的隐式设备选择。
class DeviceSession {
  final String? serial;
  final Future<ProcessResult> Function(String, List<String>)? _runner;
  final CommandRunner _commands;

  DeviceSession(
    this.serial, {
    Future<ProcessResult> Function(String, List<String>)? runner,
    CommandRunner commands = const CommandRunner(),
  }) : _runner = runner,
       _commands = commands;

  List<String> bind(List<String> command) {
    if (command.isEmpty) throw ArgumentError('命令不能为空');
    if (command.first != 'adb' && command.first != 'scrcpy') {
      throw ArgumentError('不支持的工具');
    }
    if (command.first == 'adb' &&
        command.length > 1 &&
        command[1].startsWith('-')) {
      throw ArgumentError('ADB 全局选项由设备会话管理，请先选择设备');
    }
    if (command.first == 'adb' &&
        command.length > 1 &&
        command[1] == 'kill-server') {
      throw ArgumentError('不支持停止共享 ADB 服务，请使用设置中的本应用进程清理');
    }
    if (command.first == 'scrcpy' &&
        command
            .skip(1)
            .any(
              (arg) =>
                  [
                    '-s',
                    '-d',
                    '-e',
                    '--serial',
                    '--select-usb',
                    '--select-tcpip',
                    '--tcpip',
                  ].contains(arg) ||
                  arg.startsWith('--serial=') ||
                  arg.startsWith('--tcpip=') ||
                  arg.startsWith('-s'),
            )) {
      throw ArgumentError('投屏目标必须由设备会话指定');
    }
    if (command.first == 'adb' &&
        command.length == 2 &&
        command[1] == 'disconnect') {
      _requireSerial();
      return ['adb', 'disconnect', serial!];
    }
    const globalCommands = {
      'devices',
      'connect',
      'disconnect',
      'pair',
      'version',
      'help',
      'start-server',
    };
    if (command.first == 'adb' &&
        command.length > 1 &&
        globalCommands.contains(command[1])) {
      return List.of(command);
    }
    _requireSerial();
    if (command.skip(1).contains('-s') ||
        command.skip(1).contains('--serial')) {
      throw ArgumentError('设备目标必须由会话指定');
    }
    return [command.first, '-s', serial!, ...command.skip(1)];
  }

  void _requireSerial() {
    if (serial == null || serial!.trim().isEmpty) {
      throw StateError('请先选择设备');
    }
  }

  Future<ProcessResult> run(
    List<String> command, {
    ToolCancellation? cancellation,
  }) async {
    cancellation?.check();
    final bound = bind(command);
    final result = _runner == null
        ? await _commands.run(bound, cancellation: cancellation)
        : await _runner(bound.first, bound.sublist(1));
    cancellation?.check();
    CommandRunner.check(result, bound.first);
    return result;
  }
}
