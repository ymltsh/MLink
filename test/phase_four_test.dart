import 'dart:async';
import 'dart:io';

import 'package:adb_tool/app/modules/device_connection/bloc/device_connection_cubit.dart';
import 'package:adb_tool/app/modules/device_connection/services/device_info_service.dart';
import 'package:adb_tool/app/modules/device_connection/services/network_scanner.dart';
import 'package:adb_tool/app/modules/settings/bloc/theme_cubit.dart';
import 'package:adb_tool/app/modules/tools/services/command_parser.dart';
import 'package:adb_tool/app/modules/tools/services/command_runner.dart';
import 'package:adb_tool/app/modules/tools/services/device_session.dart';
import 'package:adb_tool/app/modules/tools/services/mirror_session.dart';
import 'package:adb_tool/app/modules/tools/services/tool_cancellation.dart';
import 'package:adb_tool/datasources/adb_process_data_source.dart';
import 'package:adb_tool/main.dart';
import 'package:adb_tool/pages/settings_page.dart';
import 'package:adb_tool/utils/settings_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase_one_test.dart' show TestProcess;

ProcessResult ok([String output = '']) => ProcessResult(1, 0, output, '');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('自定义命令保留带空格的路径、空参数和远端特殊字符', () {
    expect(parseToolCommand(r'adb install "C:\下载目录\my app.apk"'), [
      'adb',
      'install',
      r'C:\下载目录\my app.apk',
    ]);
    expect(parseToolCommand('adb shell echo "" \'a;\$b\''), [
      'adb',
      'shell',
      'echo',
      '',
      r'a;$b',
    ]);
    expect(
      () => parseToolCommand('adb install "missing'),
      throwsFormatException,
    );
    expect(
      () => parseToolCommand('powershell anything'),
      throwsFormatException,
    );
  });

  test('设备会话拒绝覆盖目标及停止共享服务', () {
    final session = DeviceSession('selected');
    for (final command in [
      ['adb', '-d', 'shell', 'id'],
      ['adb', '-sother', 'shell', 'id'],
      ['adb', 'kill-server'],
      ['scrcpy', '--serial=other'],
      ['scrcpy', '--select-usb'],
      ['scrcpy', '--tcpip=other'],
    ]) {
      expect(() => session.bind(command), throwsArgumentError);
    }
    expect(session.bind(['adb', 'disconnect']), [
      'adb',
      'disconnect',
      'selected',
    ]);
  });

  test('短命令失败携带退出码，取消后不返回过时结果', () async {
    final failed = CommandRunner(
      execute: (_, args, __) async {
        expect(args, ['pair', 'endpoint', 'secret-code']);
        return ProcessResult(1, 7, '', 'failed');
      },
    );
    await expectLater(
      failed.run(['adb', 'pair', 'endpoint', 'secret-code']),
      throwsA(
        isA<ProcessException>()
            .having((e) => e.errorCode, 'code', 7)
            .having((e) => e.arguments, 'arguments', isEmpty),
      ),
    );
    final pending = Completer<ProcessResult>();
    final cancellation = ToolCancellation();
    final runner = CommandRunner(execute: (_, __, ___) => pending.future);
    final work = runner.run(['adb', 'devices'], cancellation: cancellation);
    final assertion = expectLater(work, throwsA(isA<ToolCancelled>()));
    cancellation.cancel();
    pending.complete(ok('late'));
    await assertion;
  });

  test('设备信息解析真实字段，格式异常显示未知且始终指定目标', () async {
    final commands = <List<String>>[];
    final outputs = [
      'Model',
      '14',
      'Physical size: 1080x2400',
      'MemTotal: 8388608 kB',
      'Filesystem 1K-blocks Used Available Use% Mounted on\n'
          '/dev/fuse 67108864 33554432 33554432 50% /storage/emulated',
      'arm64-v8a',
      '  level: 87\n',
    ];
    final session = DeviceSession(
      'device-b',
      commands: CommandRunner(
        execute: (_, args, __) async {
          commands.add(args);
          return ok(outputs[commands.length - 1]);
        },
      ),
    );
    final info = await const DeviceInfoService().load(
      session,
      ToolCancellation(),
    );
    expect(info['memory'], '8.00 GB');
    expect(info['storage'], '总:64.00 GB 已用:32.00 GB 可用:32.00 GB');
    expect(info['battery'], '87%');
    expect(info['screen_size'], '1080x2400');
    expect(
      commands.every((args) => args[0] == '-s' && args[1] == 'device-b'),
      true,
    );
    final invalid = DeviceSession(
      'device-b',
      commands: CommandRunner(execute: (_, __, ___) async => ok('unexpected')),
    );
    final unknown = await const DeviceInfoService().load(
      invalid,
      ToolCancellation(),
    );
    for (final field in ['memory', 'storage', 'battery', 'screen_size']) {
      expect(unknown[field], '未知');
    }
  });

  test('A→B→A 快速选择忽略旧信息并停止后续旧设备读取', () async {
    final old = Completer<ProcessResult>();
    var first = true;
    final calls = <List<String>>[];
    final cubit = DeviceConnectionCubit(
      commands: CommandRunner(
        execute: (_, args, __) async {
          calls.add(args);
          if (first) {
            first = false;
            return old.future;
          }
          return ok(args[1] == 'A' ? 'new A' : 'B');
        },
      ),
    );
    addTearDown(cubit.close);
    final previous = cubit.select('A');
    await cubit.select('B');
    await cubit.select('A');
    old.complete(ok('stale A'));
    await previous;
    expect(cubit.state.serial, 'A');
    expect(cubit.state.info['model'], 'new A');
    expect(calls.where((args) => args[1] == 'A').length, 8);
  });

  test('包名查询只接收最新请求，断开选择清空所有设备状态', () async {
    final old = Completer<ProcessResult>();
    var queryCount = 0;
    final cubit = DeviceConnectionCubit(
      commands: CommandRunner(
        execute: (_, args, __) async {
          if (args.contains('packages')) {
            if (++queryCount == 1) return old.future;
            return ok('package:org.new.app\npackage:org.new.app\nnoise\n');
          }
          if (args.first == 'devices') {
            return ok('List of devices attached\nA offline\nB unauthorized\n');
          }
          return ok();
        },
      ),
    );
    addTearDown(cubit.close);
    await cubit.select('A');
    final previous = cubit.queryPackages('old');
    await cubit.queryPackages('new');
    old.complete(ok('package:org.old.app'));
    await previous;
    expect(cubit.state.packages, ['org.new.app']);
    await cubit.refresh();
    expect(cubit.state.devices, isEmpty);
    expect(cubit.state.serial, isNull);
    expect(cubit.state.info, isEmpty);
    expect(cubit.state.packages, isEmpty);
  });

  test('关闭设备模块取消读取且不继续启动信息子命令', () async {
    final pending = Completer<ProcessResult>();
    ToolCancellation? token;
    var calls = 0;
    final cubit = DeviceConnectionCubit(
      commands: CommandRunner(
        execute: (_, __, cancellation) {
          calls++;
          token = cancellation;
          return pending.future;
        },
      ),
    );
    final work = cubit.select('A');
    await cubit.close();
    expect(token!.isCancelled, true);
    pending.complete(ok('late'));
    await work;
    expect(calls, 1);
    expect(cubit.state.info, isEmpty);
  });

  test('前台应用识别支持 org 包名', () async {
    final source = AdbProcessDataSource(
      session: DeviceSession(
        'A',
        runner: (_, __) async =>
            ok('mCurrentFocus=Window{12 u0 org.example.app/.MainActivity}'),
      ),
    );
    expect(await source.getForegroundPackage(), 'org.example.app');
  });

  test('取消扫描清除忙状态，迟到发现不自动连接且可重新扫描', () async {
    final pending = Completer<bool>();
    var probes = 0;
    final cubit = DeviceConnectionCubit(
      scanner: NetworkScanner(
        concurrency: 1,
        probe: (_, __, ___) {
          return ++probes == 1 ? pending.future : Future.value(true);
        },
      ),
    );
    addTearDown(cubit.close);
    final scan = cubit.scan('192.168.1.1-192.168.1.3', 5555);
    expect(cubit.state.scanning, true);
    cubit.cancelScan();
    pending.complete(true);
    expect(await scan, isNull);
    expect(cubit.state.scanning, false);
    expect(cubit.state.endpoints, isEmpty);
    expect(probes, 1);
    expect(await cubit.scan('192.168.1.2', 6000), ['192.168.1.2:6000']);
    expect(cubit.state.endpoints, ['192.168.1.2:6000']);
    cubit.selectEndpoint('192.168.1.2:6000');
    expect(await cubit.scan('invalid', 6000), isNull);
    expect(cubit.state.selectedEndpoint, isNull);
    expect(cubit.state.scanning, false);
  });

  test('乱序刷新只接受最新设备列表', () async {
    final old = Completer<ProcessResult>();
    var calls = 0;
    final cubit = DeviceConnectionCubit(
      commands: CommandRunner(
        execute: (_, __, ___) => ++calls == 1
            ? old.future
            : Future.value(
                ok('List of devices attached\nB device\nB device\n'),
              ),
      ),
    );
    addTearDown(cubit.close);
    final previous = cubit.refresh();
    await cubit.refresh();
    old.complete(ok('List of devices attached\nA device\n'));
    await previous;
    expect(cubit.state.devices, ['B']);
  });

  testWidgets('主页面选设备、加载偏好并启动停止投屏，设置命令绑定当前设备', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsManager.keyTurnScreenOff: true,
      SettingsManager.keyDisableAudio: true,
      SettingsManager.keyDefaultBitrate: '12',
    });
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <List<String>>[];
    final commands = CommandRunner(
      execute: (_, args, __) async {
        calls.add(args);
        return ok(
          args.first == 'devices'
              ? 'List of devices attached\nA device\nB device\n'
              : '',
        );
      },
    );
    final devices = DeviceConnectionCubit(commands: commands);
    final process = TestProcess();
    List<String>? mirrorArgs;
    final mirror = MirrorSession(
      onLog: (_) {},
      start: (_, args) async {
        mirrorArgs = args;
        return process;
      },
    );
    final theme = ThemeCubit();
    addTearDown(devices.close);
    addTearDown(mirror.dispose);
    addTearDown(theme.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: theme,
        child: MaterialApp(
          home: AdbHomePage(devices: devices, mirror: mirror),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏幕镜像'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始投屏'));
    await tester.pumpAndSettle();
    expect(mirrorArgs!.take(2), ['-s', 'B']);
    expect(
      mirrorArgs,
      containsAll(['--turn-screen-off', '--no-audio', '--video-bit-rate=12M']),
    );
    await tester.tap(find.text('停止投屏'));
    await tester.pumpAndSettle();
    expect(process.kills, 1);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final settings = tester.widget<SettingsPage>(find.byType(SettingsPage));
    expect(await settings.onRunCommand(['adb', 'shell', 'id']), true);
    expect(calls.last, ['-s', 'B', 'shell', 'id']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(devices.isClosed, false); // 注入对象由调用者释放。
    expect(tester.takeException(), isNull);
  });
}
