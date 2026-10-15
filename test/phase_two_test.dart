import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:adb_tool/pages/screen_mirroring_page.dart';
import 'package:adb_tool/app/modules/device_connection/widgets/pair_device_dialog.dart';
import 'package:adb_tool/app/modules/device_connection/services/network_scanner.dart';
import 'package:adb_tool/app/modules/file_manager/bloc/file_manager_cubit.dart';
import 'package:adb_tool/app/modules/file_manager/bloc/file_manager_state.dart';
import 'package:adb_tool/app/modules/file_manager/models/file_entry.dart';
import 'package:adb_tool/app/modules/file_manager/services/adb_file_service.dart';
import 'package:adb_tool/app/modules/screenshot/bloc/screenshot_cubit.dart';
import 'package:adb_tool/app/modules/screenshot/services/screenshot_service.dart';
import 'package:adb_tool/app/modules/screen_mirroring/models/mirror_config.dart';
import 'package:adb_tool/app/modules/tools/services/mirror_session.dart';
import 'package:adb_tool/app/modules/tools/services/tool_cancellation.dart';
import 'package:adb_tool/app/modules/tools/services/tool_process.dart';
import 'package:adb_tool/utils/app_output.dart';
import 'phase_one_test.dart' show TestProcess;

Future<void> tick() => Future<void>.delayed(Duration.zero);
const entry = FileEntry(name: 'file', path: '/sdcard/file', isDirectory: false);

class FakeFiles extends AdbFileService {
  Future<List<FileEntry>> Function(String)? read;
  Stream<double> Function()? transfer;
  void Function()? onDispose;
  int transfers = 0;
  FakeFiles() : super(deviceSerial: 'test-device');
  @override
  Future<List<FileEntry>> ls(String path, {bool useRoot = false}) async =>
      read == null ? [] : await read!(path);
  @override
  Future<List<FileEntry>> search(String path, String query,
          {bool useRoot = false}) =>
      ls(query);
  @override
  Stream<double> push(String localPath, String remotePath,
      {bool useRoot = false}) {
    transfers++;
    return transfer?.call() ?? Stream.value(1.0);
  }

  @override
  Stream<double> pull(String remotePath, String localPath,
          {bool useRoot = false}) =>
      push(localPath, remotePath);
  @override
  void dispose() {
    onDispose?.call();
    super.dispose();
  }
}

class FakeScreenshots extends ScreenshotService {
  final captureResult = Completer<File>();
  int historyReads = 0;
  bool disposed = false;
  @override
  Future<File> captureScreen(String serial) => captureResult.future;
  @override
  Future<List<File>> loadHistory() async {
    historyReads++;
    return [];
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test('进度和错误明确设为 null，省略参数保留原值', () {
    final state =
        FileManagerState.initial().copyWith(progress: 0.5, errorMessage: 'old');
    expect(state.copyWith().progress, 0.5);
    final clear = state.copyWith(progress: null, errorMessage: null);
    expect(clear.progress, isNull);
    expect(clear.errorMessage, isNull);
  });

  test('文件元数据保留特殊名称、真实日期、类型和链接目标', () async {
    const name = 'a  b:12\n\'"\$()`';
    final output = '81a4 42 1700000000 0\x00/sdcard/$name\x00\x00'
        '41ed 4096 1700000001 1\x00/sdcard/folder\x00\x00'
        'a1ff 7 1700000002 1\x00/sdcard/link\x00/target\n\n\x00';
    final service = AdbFileService(
        deviceSerial: 'test-device',
        run: (_, __) async => ProcessResult(0, 0, output, ''));
    addTearDown(service.dispose);
    final files = await service.ls('/sdcard');
    final file = files.firstWhere((f) => f.name == name);
    expect(file.size, 42);
    expect(file.modifiedTime!.millisecondsSinceEpoch, 1700000000000);
    expect(file.permission, '-rw-r--r--');
    final link = files.firstWhere((f) => f.name == 'link');
    expect(link.isLink, true);
    expect(link.isDirectory, true);
    expect(link.linkTarget, '/target\n');
    expect(
        (await service.search('/sdcard', 'anything')).first.isDirectory, true);
  });

  test('文件读取区分空目录、权限错误与不完整元数据', () async {
    var result = ProcessResult(0, 0, '', '');
    final service = AdbFileService(
        deviceSerial: 'test-device', run: (_, __) async => result);
    addTearDown(service.dispose);
    expect(await service.ls('/empty'), isEmpty);
    result = ProcessResult(0, 1, '', 'Permission denied');
    await expectLater(
        service.ls('/private'), throwsA(isA<ADBFileServiceException>()));
    result = ProcessResult(0, 0, '81a4 1 123 0\x00/path', '');
    await expectLater(
        service.ls('/bad'), throwsA(isA<ADBFileServiceException>()));
    result = ProcessResult(0, 0, 'ERROR\x00/private\x00\x00', '');
    await expectLater(service.search('/', 'private'),
        throwsA(isA<ADBFileServiceException>()));
  });

  test('Root 传输明确拒绝且不会启动普通权限的传输', () async {
    var started = 0;
    final service = AdbFileService(
        deviceSerial: 'test-device',
        start: (_, __) async {
          started++;
          return TestProcess();
        });
    addTearDown(service.dispose);
    await expectLater(
        service.push('local', '/private', useRoot: true).drain<void>(),
        throwsA(isA<ADBFileServiceException>()));
    await expectLater(
        service.pull('/private', 'local', useRoot: true).drain<void>(),
        throwsA(isA<ADBFileServiceException>()));
    expect(started, 0);
  });

  test('目录和搜索请求乱序完成时只有最后一次结果生效', () async {
    final old = Completer<List<FileEntry>>();
    final newer = Completer<List<FileEntry>>();
    final service = FakeFiles()
      ..read = (path) => path == '/old' ? old.future : newer.future;
    final cubit =
        FileManagerCubit(deviceSerial: 'test-device', service: service);
    final first = cubit.loadPath('/old');
    final last = cubit.search('new');
    newer.complete([entry]);
    await last;
    old.complete([]);
    await first;
    expect(cubit.state.files, [entry]);
    expect(cubit.state.status, FileManagerStatus.success);
    await cubit.close();
  });

  test('关闭文件页面后忽略读结果，并停止批量传输后续文件', () async {
    final pending = Completer<List<FileEntry>>();
    final service = FakeFiles()..read = (_) => pending.future;
    final cubit =
        FileManagerCubit(deviceSerial: 'test-device', service: service);
    final read = cubit.loadPath('/pending');
    await cubit.close();
    pending.complete([entry]);
    await read;
    final stream = StreamController<double>();
    final batchService = FakeFiles()..transfer = () => stream.stream;
    batchService.onDispose = () {
      unawaited(stream.close());
    };
    final batch =
        FileManagerCubit(deviceSerial: 'test-device', service: batchService);
    final uploading = batch.uploadFiles(['one', 'two']);
    await tick();
    await batch.close();
    await uploading;
    expect(batchService.transfers, 1);
  });

  test('传输失败清空进度并显示错误，重试成功清空错误', () async {
    final service = FakeFiles()
      ..transfer = () => Stream.error(StateError('offline'));
    final cubit =
        FileManagerCubit(deviceSerial: 'test-device', service: service);
    await cubit.downloadFile(entry, 'local');
    expect(cubit.state.progress, isNull);
    expect(cubit.state.status, FileManagerStatus.failure);
    expect(cubit.state.errorMessage, contains('offline'));
    service.transfer = () => Stream.value(1.0);
    await cubit.downloadFile(entry, 'local');
    expect(cubit.state.progress, isNull);
    expect(cubit.state.errorMessage, isNull);
    expect(cubit.state.status, FileManagerStatus.success);
    await cubit.close();
  });

  test('截图失败收敛到状态并停止定时器；页面关闭后不加载历史', () async {
    final service = FakeScreenshots();
    final cubit = ScreenshotCubit(service);
    cubit.startContinuousCapture('test-device');
    service.captureResult.completeError(StateError('offline'));
    await tick();
    expect(cubit.state.isCapturing, false);
    expect(cubit.state.isContinuousCapturing, false);
    expect(cubit.state.errorMessage, contains('offline'));
    await cubit.close();
    final pendingService = FakeScreenshots();
    final pendingCubit = ScreenshotCubit(pendingService);
    await tick();
    final capture = pendingCubit.capture('test-device');
    await pendingCubit.close();
    pendingService.captureResult.complete(File('image.png'));
    await capture;
    expect(pendingService.historyReads, 1);
    expect(pendingService.disposed, true);
  });

  test('扫描工作池在乱序完成时仍保持并发上限并使用指定端口', () async {
    var active = 0;
    var peak = 0;
    final pending = <String, Completer<bool>>{};
    final scanner = NetworkScanner(
        concurrency: 3,
        probe: (host, port, token) async {
          expect(port, 43210);
          active++;
          if (active > peak) peak = active;
          final completer = Completer<bool>();
          pending[host] = completer;
          final open = await completer.future;
          active--;
          return open;
        });
    final result = scanner.scan(
        Ipv4Range.parse('10.0.0.1-10.0.0.9'), 43210, ToolCancellation());
    expect(pending.length, 3);
    pending.remove('10.0.0.2')!.complete(true);
    await tick();
    expect(pending.length, 3);
    expect(pending.containsKey('10.0.0.4'), true);
    while (pending.isNotEmpty) {
      pending.remove(pending.keys.last)!.complete(false);
      await tick();
    }
    expect(await result, ['10.0.0.2:43210']);
    expect(peak, 3);
  });

  test('扫描取消后不调度新地址，非法范围和端口被拒绝', () async {
    final cancellation = ToolCancellation();
    var count = 0;
    final scanner = NetworkScanner(
        concurrency: 2,
        probe: (_, __, token) {
          count++;
          final completer = Completer<bool>();
          token.add(() => completer.complete(false));
          return completer.future;
        });
    final result =
        scanner.scan(Ipv4Range.parse('10.0.0.1-10.0.0.50'), 5555, cancellation);
    cancellation.cancel();
    expect(await result, isEmpty);
    expect(count, 2);
    expect(() => Ipv4Range.parse('10.0.0.9-10.0.0.1'), throwsFormatException);
    expect(() => Ipv4Range.parse('10.0.0.1-10.1.0.1'), throwsFormatException);
    expect(() => Ipv4Range.parse('10.0.0.999'), throwsFormatException);
    await expectLater(
        scanner.scan(Ipv4Range.parse('10.0.0.1'), 65536, ToolCancellation()),
        throwsFormatException);
  });

  test('实际套接字探测关闭连接并返回完整端点', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final connections = server.listen((socket) => socket.destroy());
    addTearDown(() async {
      await connections.cancel();
      await server.close();
    });
    final found = await NetworkScanner(concurrency: 1)
        .scan(Ipv4Range.parse('127.0.0.1'), server.port, ToolCancellation());
    expect(found, ['127.0.0.1:${server.port}']);
  });

  test('默认和临时画质共用配置，单App DPI 回退到默认值并校验输入', () {
    const config =
        MirrorConfig(bitrate: '12', maxSize: '1440', dpi: '360', h265: true);
    expect(
        config.command(),
        containsAll(
            ['--video-bit-rate=12M', '--max-size=1440', '--video-codec=h265']));
    expect(config.command(bitrateOverride: '20', sizeOverride: '720'),
        containsAll(['--video-bit-rate=20M', '--max-size=720']));
    expect(config.command(package: 'com.example.app', displaySize: '1920x1080'),
        contains('--new-display=1920x1080/360'));
    expect(config.command(package: 'com.example.app'),
        contains('--new-display=/360'));
    expect(config.command(), isNot(contains(contains('dpi'))));
    expect(() => config.command(bitrateOverride: '-1'), throwsFormatException);
    expect(() => config.command(sizeOverride: 'oops'), throwsFormatException);
    expect(
        () => config.command(package: 'com.example.app', displaySize: '1920x'),
        throwsFormatException);
    expect(() => config.command(package: 'com.example.app', dpiOverride: '0'),
        throwsFormatException);
  });

  test('短命令完整收集尾部输出，非零退出转为错误', () async {
    final process = TestProcess();
    final result = runToolExecutable('adb', [],
        start: (_, __) async => process, stdoutEncoding: utf8);
    await tick();
    process.exit.complete(0);
    process.out.add(utf8.encode('尾部输出'));
    await tick();
    process.out.close();
    process.err.close();
    expect((await result).stdout, '尾部输出');
    final failed = TestProcess()..finish(1);
    await expectLater(
        runToolExecutable('adb', [], start: (_, __) async => failed),
        throwsA(isA<ProcessException>()));
    expect(failed.kills, 0);
  });

  test('短命令超时和取消只终止自己的进程，启动取消也立即返回', () async {
    final process = TestProcess();
    await expectLater(
        runToolExecutable('adb', [],
            start: (_, __) async => process,
            timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    expect(process.kills, 1);
    final pending = Completer<Process>();
    final token = ToolCancellation();
    final result = runToolExecutable('adb', [],
        start: (_, __) => pending.future, cancellation: token);
    final checked = expectLater(result, throwsA(isA<ToolCancelled>()));
    token.cancel();
    await checked;
    final lateProcess = TestProcess();
    pending.complete(lateProcess);
    await tick();
    expect(lateProcess.kills, 1);
  });

  test('投屏实时日志、重复启动拒绝和停止后可重启', () async {
    final processes = <TestProcess>[];
    final logs = <String>[];
    final session = MirrorSession(
        onLog: logs.add,
        start: (_, __) async {
          final process = TestProcess();
          processes.add(process);
          return process;
        });
    await session.start(['scrcpy', '-s', 'test-device']);
    processes.first.out.add(utf8.encode('frame ready\n'));
    await tick();
    expect(logs, contains('frame ready'));
    expect(session.isActive, true);
    await expectLater(session.start(['scrcpy']), throwsStateError);
    await session.stop();
    expect(processes.first.kills, 1);
    expect(session.isActive, false);
    await session.start(['scrcpy', '-s', 'test-device']);
    session.dispose();
    await tick();
    expect(processes.last.kills, 1);
  });

  test('投屏启动中停止，迟到的进程也被终止', () async {
    final pending = Completer<Process>();
    final session =
        MirrorSession(onLog: (_) {}, start: (_, __) => pending.future);
    final start = session.start(['scrcpy']);
    final stopped = session.stop();
    await start;
    await stopped;
    final process = TestProcess();
    pending.complete(process);
    await tick();
    expect(process.kills, 1);
    expect(session.isActive, false);
    session.dispose();
  });

  test('统一日志按任务显示新结果且有消息数和字符上限', () {
    final log = AppLogBuffer(maxEntries: 3, maxCharacters: 100);
    addTearDown(log.dispose);
    log.append('旧文件结果', task: '文件');
    log.append('新命令结果', task: '命令');
    expect(log.value, contains('[命令] 新命令结果'));
    for (var i = 0; i < 20; i++) {
      log.append('event $i');
    }
    expect(log.entries.length, 3);
    expect(log.value, contains('event 19'));
    log.append(List.filled(1000, 'x').join(), task: '投屏');
    expect(log.value.length, lessThanOrEqualTo(100));
    log.clear();
    expect(log.value, '');
  });

  testWidgets('投屏按钮使用默认画质，错误输入不会启动，活动会话显示停止按钮', (tester) async {
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    final commands = <List<String>>[];
    var stopped = 0;
    Widget page(bool active) => MaterialApp(
            home: Scaffold(
                body: ScreenMirroringPage(
          config: () => const MirrorConfig(bitrate: '16', maxSize: '1440'),
          isMirrorActive: active,
          onStop: () {
            stopped++;
          },
          bitrateController: controllers[0],
          sizeController: controllers[1],
          appPackageController: controllers[2],
          appDisplaySizeController: controllers[3],
          appDisplayDpiController: controllers[4],
          searchController: controllers[5],
          onRunCommand: commands.add,
          onQueryPackages: () {},
          packageQueryResult: const [],
        )));
    await tester.pumpWidget(page(false));
    await tester.tap(find.text('开始投屏'));
    expect(commands.single,
        containsAll(['--video-bit-rate=16M', '--max-size=1440']));
    controllers[0].text = 'invalid';
    await tester.tap(find.text('开始投屏'));
    await tester.pump();
    expect(commands.length, 1);
    expect(find.text('码率必须是 1–1000 的整数（M）'), findsOneWidget);
    await tester.pumpWidget(page(true));
    await tester.tap(find.text('停止投屏'));
    expect(stopped, 1);
    expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '开始投屏'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('配对对话框校验端口及配对码，确认后返回独立配对命令', (tester) async {
    List<String>? paired;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      child: const Text('打开配对'),
                      onPressed: () async {
                        paired = await showDialog<List<String>>(
                            context: context,
                            builder: (_) => const PairDeviceDialog(
                                initialHost: '10.0.0.2'));
                      },
                    )))));
    await tester.tap(find.text('打开配对'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.tap(find.text('配对'));
    await tester.pump();
    expect(paired, isNull);
    expect(find.text('请填写有效的 IPv4 地址、端口和六位配对码'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '43210');
    await tester.tap(find.text('配对'));
    await tester.pumpAndSettle();
    expect(paired, ['adb', 'pair', '10.0.0.2:43210', '123456']);
    await tester.pumpWidget(const SizedBox());
  });

  final shell =
      Platform.isWindows ? r'C:\Program Files\Git\bin\bash.exe' : '/bin/sh';
  test('实际 POSIX shell 执行元数据脚本，特殊文件名不触发命令替换', () async {
    final dir = await Directory.systemTemp.createTemp('mlink-metadata-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/two  spaces\'s;\$HOME`name`');
    await file.writeAsString('test content');
    String posix(String path) {
      final normalized = path.replaceAll('\\', '/');
      return Platform.isWindows
          ? '/${normalized[0].toLowerCase()}${normalized.substring(2)}'
          : normalized;
    }

    final service = AdbFileService(
        deviceSerial: 'test-device',
        run: (_, args) => Process.run(
            shell,
            [
              '-c',
              r'''su() { [ "$1" = '-c' ] || return 1; shift; sh -c "$1"; }; ''' +
                  args.last
            ],
            environment: {'MSYS2_ARG_CONV_EXCL': '*'},
            stdoutEncoding: utf8));
    addTearDown(service.dispose);
    final files = await service.ls(posix(dir.path));
    expect(files.single.name, "two  spaces's;\$HOME`name`");
    expect(files.single.size, 12);
    expect(
        files.single.modifiedTime!
            .difference(await file.lastModified())
            .inSeconds
            .abs(),
        lessThanOrEqualTo(1));
    expect(await service.search(posix(dir.path), 'spaces'), hasLength(1));
    expect((await service.ls(posix(dir.path), useRoot: true)).single.name,
        files.single.name);
  }, skip: !File(shell).existsSync() ? '当前平台未安装 POSIX shell' : false);
}
