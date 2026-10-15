import 'dart:async';
import 'dart:io';

import 'package:adb_tool/app/modules/tools/services/tool_environment.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

List<int> toolZip({String? extra}) {
  final archive = Archive();
  for (final name in ToolEnvironment.requiredFiles) {
    archive.addFile(ArchiveFile('scrcpy-win64-v5.0.1/$name', 3, [1, 2, 3]));
  }
  if (extra != null) archive.addFile(ArchiveFile(extra, 3, [1, 2, 3]));
  return ZipEncoder().encode(archive);
}

Map<String, dynamic> release(List<int> bytes, {String? digest}) => {
      'tag_name': 'v5.0.1',
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': 'scrcpy-win64-v5.0.1.zip',
          'size': bytes.length,
          'digest': digest ?? 'sha256:${sha256.convert(bytes)}',
          'browser_download_url':
              'https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-win64-v5.0.1.zip',
        }
      ],
    };

void main() {
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('mlink-tools-test-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('默认加速源格式与输入校验', () async {
    final tools =
        ToolEnvironment(windows: true, rootProvider: () async => root);
    expect(tools.sourceUri(Uri.parse('https://github.com/test')).toString(),
        'https://hub.wgen.top/https://github.com/test');
    await tools.setProxy('');
    expect(tools.sourceUri(Uri.parse('https://github.com/test')).host,
        'github.com');
    await tools.setProxy('https://example.org');
    expect(tools.proxyBase, 'https://example.org/');
    for (final bad in [
      'file:///tmp',
      'http://example.com',
      'https://a:b@example.com',
      'https://example.com/?token=a'
    ]) {
      expect(() => ToolEnvironment.normalizeProxy(bad), throwsFormatException);
    }
    tools.dispose();
  });

  test('首次补全包含 ADB，后续实例离线复用，文件损坏触发修复', () async {
    final zip = toolZip();
    var downloads = 0;
    var metadataRequests = 0;
    ToolEnvironment make() => ToolEnvironment(
          windows: true,
          rootProvider: () async => root,
          releaseLoader: (uri) async {
            metadataRequests++;
            expect(uri.toString(),
                'https://api.github.com/repos/Genymobile/scrcpy/releases/latest');
            return release(zip);
          },
          download: (uri, file, maxBytes, progress) async {
            downloads++;
            expect(uri.toString(),
                startsWith('https://hub.wgen.top/https://github.com/'));
            await file.writeAsBytes(zip);
            progress(zip.length, zip.length);
          },
          validate: (dir) async {},
        );
    final first = make();
    expect(await first.ensure(), isTrue);
    expect(first.phase, ToolPhase.ready);
    expect(File(first.executable('adb')).existsSync(), isTrue);
    expect(first.processEnvironment!['ADB'], first.executable('adb'));
    expect(first.processEnvironment!['SCRCPY_SERVER_PATH'],
        p.join(first.directory!, 'scrcpy-server'));
    expect(first.executable('other'), 'other');
    final second = make();
    expect(await second.ensure(), isTrue);
    expect(downloads, 1);
    expect(metadataRequests, 1);
    expect(second.directory, first.directory);
    await File(second.executable('adb')).writeAsBytes([9]);
    expect(await second.ensure(), isTrue);
    expect(downloads, 2);
    expect(await File(second.executable('adb')).readAsBytes(), [1, 2, 3]);
    first.dispose();
    second.dispose();
  });

  test('失败不留下安装清单，重试成功，并发请求只执行一次', () async {
    final zip = toolZip();
    var calls = 0;
    final gate = Completer<void>();
    final tools = ToolEnvironment(
      windows: true,
      rootProvider: () async => root,
      releaseLoader: (_) async {
        calls++;
        await gate.future;
        if (calls == 1) throw const SocketException('offline');
        return release(zip);
      },
      download: (_, file, __, progress) async => file.writeAsBytes(zip),
      validate: (_) async {},
    );
    final a = tools.ensure();
    final b = tools.ensure();
    expect(identical(a, b), isTrue);
    gate.complete();
    expect(await a, isFalse);
    expect(tools.phase, ToolPhase.failed);
    expect(File(p.join(root.path, 'installed.json')).existsSync(), isFalse);
    expect(await tools.ensure(), isTrue);
    expect(calls, 2);
    tools.dispose();
  });

  test('更新失败仍保留之前可用的安装', () async {
    final zip = toolZip();
    var fail = false;
    final tools = ToolEnvironment(
      windows: true,
      rootProvider: () async => root,
      releaseLoader: (_) async {
        if (fail) throw const SocketException('offline');
        return release(zip);
      },
      download: (_, file, __, ___) async {
        await file.writeAsBytes(zip);
      },
      validate: (_) async {},
    );
    expect(await tools.ensure(), isTrue);
    final installed = tools.directory;
    final record =
        await File(p.join(root.path, 'installed.json')).readAsString();
    fail = true;
    expect(await tools.ensure(force: true), isFalse);
    expect(tools.directory, installed);
    expect(
        await File(p.join(root.path, 'installed.json')).readAsString(), record);
    tools.dispose();
  });

  test('拒绝 SHA256 不符与归档路径穿越', () {
    final zip = toolZip();
    final file = File(p.join(root.path, 'package.zip'))..writeAsBytesSync(zip);
    expect(
        () => extractToolBundle({
              'zip': file.path,
              'destination': p.join(root.path, 'unpack'),
              'sha256': 'bad'
            }),
        throwsFormatException);
    for (final unsafe in ['../escape', '..\\escape', 'C:\\escape', '/escape']) {
      final badZip = toolZip(extra: unsafe);
      file.writeAsBytesSync(badZip);
      expect(
          () => extractToolBundle({
                'zip': file.path,
                'destination': p.join(root.path, 'unpack'),
                'sha256': sha256.convert(badZip).toString()
              }),
          throwsFormatException);
      expect(Directory(p.join(root.path, 'unpack')).existsSync(), isFalse);
    }
  });

  test('只选择官方 win64 正式资产，校验和按完整文件名匹配', () {
    final valid = release(toolZip());
    expect(ScrcpyAsset.fromRelease(valid).name, 'scrcpy-win64-v5.0.1.zip');
    expect(() => ScrcpyAsset.fromRelease({...valid, 'prerelease': true}),
        throwsFormatException);
    expect(() => ScrcpyAsset.fromRelease({...valid, 'assets': []}),
        throwsFormatException);
    final digest = 'a' * 64;
    expect(
        ToolEnvironment.checksumFor(
            '$digest  scrcpy-win64-v5.0.1.zip\r\n', 'scrcpy-win64-v5.0.1.zip'),
        digest);
    expect(
        () => ToolEnvironment.checksumFor(
            '$digest  other.zip', 'scrcpy-win64-v5.0.1.zip'),
        throwsFormatException);
  });
}
