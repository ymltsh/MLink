import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb_tool/app/modules/file_manager/services/adb_file_service.dart';
import 'package:adb_tool/app/modules/tools/services/device_session.dart';
import 'package:adb_tool/app/modules/tools/services/tool_process.dart';
import 'package:adb_tool/datasources/adb_process_data_source.dart';
import 'package:adb_tool/pages/app_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestProcess implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exit = Completer<int>();
  int kills = 0;

  void finish(int code) {
    out.close();
    err.close();
    if (!exit.isCompleted) exit.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    finish(-1);
    return true;
  }

  @override
  Future<int> get exitCode => exit.future;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  int get pid => 123;
  @override
  IOSink get stdin => throw UnsupportedError('测试无需 stdin');
}

void main() {
  for (final operation in ['push', 'pull']) {
    test('$operation 实时进度、双通道尾部输出与成功结束', () async {
      final process = TestProcess();
      final started = Completer<void>();
      final service = AdbFileService(
          deviceSerial: 'device-a',
          start: (exe, args) async {
            expect(exe, 'adb');
            expect(args.take(3), ['-s', 'device-a', operation]);
            started.complete();
            return process;
          });
      addTearDown(service.dispose);
      final values = <double>[];
      final firstProgress = Completer<void>();
      final stream = operation == 'push'
          ? service.push('local', '/sdcard/remote')
          : service.pull('/sdcard/remote', 'local');
      final done = stream.listen((value) {
        values.add(value);
        if (!firstProgress.isCompleted) firstProgress.complete();
      }).asFuture<void>();
      await started.future;
      process.out.add(utf8.encode('[ 25%] copying\n'));
      await firstProgress.future.timeout(const Duration(seconds: 2));
      expect(process.exit.isCompleted, false);
      process.err.add(utf8.encode('[ 90%] final'));
      process.finish(0);
      await done.timeout(const Duration(seconds: 2));
      expect(values, [0.25, 0.9, 1.0]);
    });

    test('$operation 失败结束并传递异常', () async {
      final process = TestProcess()..finish(1);
      final service = AdbFileService(
          deviceSerial: 'device-a', start: (_, __) async => process);
      addTearDown(service.dispose);
      final stream = operation == 'push'
          ? service.push('local', '/remote')
          : service.pull('/remote', 'local');
      await expectLater(stream.toList().timeout(const Duration(seconds: 2)),
          throwsA(isA<ADBFileServiceException>()));
    });
  }

  test('取消订阅、服务释放和启动期间取消仅终止对应传输', () async {
    for (final duringStart in [false, true]) {
      final process = TestProcess();
      final pending = Completer<Process>();
      final started = Completer<void>();
      final service = AdbFileService(
          deviceSerial: 'device-a',
          start: (_, __) async {
            started.complete();
            if (duringStart) return await pending.future;
            return process;
          });
      final sub = service.push('local', '/remote').listen((_) {});
      await started.future;
      if (!duringStart) await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      if (duringStart) pending.complete(process);
      await Future<void>.delayed(Duration.zero);
      expect(process.kills, 1);
      service.dispose();
    }
    final process = TestProcess();
    final service = AdbFileService(
        deviceSerial: 'device-a', start: (_, __) async => process);
    final done = service.pull('/remote', 'local').drain<void>();
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    await done.timeout(const Duration(seconds: 2));
    expect(process.kills, 1);
  });

  test('启动失败与未选设备均结束且不启动隐式目标', () async {
    var starts = 0;
    final service = AdbFileService(start: (_, __) async {
      starts++;
      throw StateError('unexpected');
    });
    addTearDown(service.dispose);
    await expectLater(
        service.push('local', '/remote').toList(), throwsStateError);
    expect(starts, 0);
    final failing = AdbFileService(
        deviceSerial: 'device-a',
        start: (_, __) async => throw ProcessException('adb', []));
    addTearDown(failing.dispose);
    await expectLater(failing.pull('/remote', 'local').toList(),
        throwsA(isA<ProcessException>()));
  });

  test('特殊文件名与搜索词作为远端字面参数，Root 保持嵌套引用', () async {
    final commands = <String>[];
    final service = AdbFileService(
        deviceSerial: 'device-a',
        run: (exe, args) async {
          expect(args.take(3), ['-s', 'device-a', 'shell']);
          commands.add(args.last);
          return ProcessResult(0, 0, '', '');
        });
    addTearDown(service.dispose);
    const path = '/sdcard/a b\'"\n\$HOME\$(id)`id`;x';
    await service.delete(path);
    expect(commands.last,
        'rm -rf -- \'/sdcard/a b\'"\'"\'"\n\$HOME\$(id)`id`;x\'');
    await service.mkdir('-leading');
    expect(commands.last, "mkdir -p -- '-leading'");
    await service.rename('/old name', path);
    expect(commands.last, startsWith("mv -- '/old name' '/sdcard/a b"));
    await service.ls(path);
    expect(commands.last, contains("find '/sdcard/a b"));
    await service.search('/sdcard', r'$(id)`id`";x');
    expect(
        commands.last,
        startsWith(
            'find \'/sdcard/\' -maxdepth 5 -iname \'*\$(id)`id`";x*\' '));
    await service.mkdir('/sdcard/a b', useRoot: true);
    expect(
        commands.last, '''su -c 'mkdir -p -- '"'"'/sdcard/a b'"'"'' '''.trim());
  });

  test('双设备会话独立，所有监控读写绑定 serial，失败向上传递', () async {
    final targets = <List<String>>[];
    Future<ProcessResult> run(String exe, List<String> args) async {
      targets.add(args);
      return ProcessResult(0, 0, '', '');
    }

    final a = DeviceSession('device-a', runner: run);
    final b = DeviceSession('device-b', runner: run);
    final source = AdbProcessDataSource(session: a);
    await source.fetchMemoryInfo();
    await source.fetchProcesses();
    await source.getForegroundPackage();
    await a.run(['adb', 'shell', 'kill', '123']);
    await b.run(
        ['adb', 'shell', 'settings', 'put', 'system', 'show_touches', '1']);
    expect(
        targets
            .take(4)
            .every((args) => args[0] == '-s' && args[1] == 'device-a'),
        true);
    expect(targets.last.take(2), ['-s', 'device-b']);
    expect(() => DeviceSession(null).bind(['adb', 'shell', 'ps']),
        throwsStateError);
    expect(() => DeviceSession('').bind(['scrcpy']), throwsStateError);
    expect(a.bind(['adb', 'connect', 'host:5555']),
        ['adb', 'connect', 'host:5555']);
    expect(a.bind(['adb', 'disconnect']), ['adb', 'disconnect', 'device-a']);
    expect(() => DeviceSession(null).bind(['adb', 'disconnect']),
        throwsStateError);
    final failed = AdbProcessDataSource(
        session: DeviceSession('device-a',
            runner: (_, __) async => ProcessResult(0, 1, '', 'offline')));
    await expectLater(
        failed.fetchProcesses(), throwsA(isA<ProcessException>()));
  });

  test('清理只访问持有的活跃进程，已退出进程不再清理', () async {
    final owned = TestProcess();
    final exited = TestProcess();
    final unrelated = TestProcess();
    final registry = OwnedAdbProcesses()
      ..track(owned)
      ..track(exited);
    exited.finish(0);
    await Future<void>.delayed(Duration.zero);
    expect(registry.clean(), 1);
    expect(owned.kills, 1);
    expect(exited.kills, 0);
    expect(unrelated.kills, 0);
    unrelated.finish(0);
  });

  testWidgets('监控断线显示错误且无模拟进程可操作，退出时忽略在途刷新', (tester) async {
    final apk = TextEditingController();
    final keyword = TextEditingController();
    addTearDown(apk.dispose);
    addTearDown(keyword.dispose);
    var writes = 0;
    final pending = Completer<ProcessResult>();
    Widget page(DeviceSession session) => MaterialApp(
            home: Scaffold(
                body: AppManagementPage(
          session: session,
          apkController: apk,
          appKeywordController: keyword,
          onRunCommand: (_) {
            writes++;
          },
          onQueryPackages: () {},
          packageQueryResult: const [],
        )));
    await tester.pumpWidget(page(DeviceSession('device-a',
        runner: (_, __) async => ProcessResult(0, 1, '', 'offline'))));
    await tester.pumpAndSettle();
    expect(find.text('设备读取失败'), findsOneWidget);
    expect(find.text('Kill'), findsNothing);
    expect(find.text('Stop'), findsNothing);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        page(DeviceSession('device-b', runner: (_, __) => pending.future)));
    await tester.pumpWidget(const SizedBox());
    pending.complete(ProcessResult(0, 1, '', 'offline'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认框打开后监控失败，确认不会执行旧进程操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final apk = TextEditingController();
    final keyword = TextEditingController();
    addTearDown(apk.dispose);
    addTearDown(keyword.dispose);
    var offline = false;
    var writes = 0;
    final session = DeviceSession('device-a', runner: (_, args) async {
      if (args.contains('kill') || args.contains('force-stop')) writes++;
      if (offline) return ProcessResult(0, 1, '', 'offline');
      if (args.contains('ps')) {
        return ProcessResult(
            0,
            0,
            'PID UID NAME RSS PCPU\n123 u0_a123 com.example.app 1024 1.0\n',
            '');
      }
      if (args.contains('/proc/meminfo')) {
        return ProcessResult(
            0,
            0,
            'MemTotal: 4096000 kB\nMemAvailable: 2048000 kB\nBuffers: 1000 kB\nCached: 1000 kB\n',
            '');
      }
      return ProcessResult(0, 0, 'mCurrentFocus com.example.app/Main', '');
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AppManagementPage(
      session: session,
      apkController: apk,
      appKeywordController: keyword,
      onRunCommand: (_) {
        writes++;
      },
      onQueryPackages: () {},
      packageQueryResult: const [],
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kill'));
    await tester.tap(find.text('Kill'));
    await tester.pumpAndSettle();
    expect(find.text('确定'), findsOneWidget);
    offline = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Kill'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
