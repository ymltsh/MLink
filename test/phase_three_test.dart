import 'dart:convert';
import 'dart:io';
import 'package:adb_tool/app/modules/tools/services/tool_cache.dart';
import 'package:adb_tool/app/modules/tools/services/tool_environment.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'tool_environment_test.dart' show toolZip, release;

Map<String, dynamic> atVersion(List<int> bytes, String tag) {
  final result = release(bytes)..['tag_name'] = tag;
  final asset = (result['assets'] as List).single as Map;
  asset['name'] = 'scrcpy-win64-$tag.zip';
  asset['browser_download_url'] =
      'https://github.com/Genymobile/scrcpy/releases/download/$tag/scrcpy-win64-$tag.zip';
  return result;
}

void main() {
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('mlink-cache-regression-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('重复检查相同 tag/digest 不下载、不更换目录且可离线复用', () async {
    final zip = toolZip();
    var downloads = 0;
    var requests = 0;
    final tools = ToolEnvironment(
        windows: true,
        rootProvider: () async => root,
        releaseLoader: (_) async {
          requests++;
          return release(zip);
        },
        download: (_, file, __, ___) async {
          downloads++;
          await file.writeAsBytes(zip);
        },
        validate: (_) async {});
    addTearDown(tools.dispose);
    expect(await tools.ensure(), true);
    final directory = tools.directory;
    expect(await tools.ensure(force: true), true);
    expect(await tools.ensure(force: true), true);
    expect(downloads, 1);
    expect(requests, 3);
    expect(tools.directory, directory);
    expect(await tools.ensure(), true);
    expect(requests, 3);
    expect((await root.list().where((f) => f is Directory).toList()).length, 1);
  });

  test('官方元数据和校验和直连，代理只提供经过摘要校验的 ZIP', () async {
    final zip = toolZip();
    final metadata = release(zip);
    ((metadata['assets'] as List).single as Map).remove('digest');
    (metadata['assets'] as List).add({
      'name': 'SHA256SUMS.txt',
      'browser_download_url':
          'https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/SHA256SUMS.txt'
    });
    final urls = <Uri>[];
    final tools = ToolEnvironment(
        windows: true,
        rootProvider: () async => root,
        releaseLoader: (uri) async {
          expect(uri.host, 'api.github.com');
          return metadata;
        },
        download: (uri, file, _, __) async {
          urls.add(uri);
          if (uri.path.endsWith('SHA256SUMS.txt')) {
            expect(uri.host, 'github.com');
            await file.writeAsString(
                '${sha256.convert(zip)}  scrcpy-win64-v5.0.1.zip\n');
          } else {
            expect(uri.host, 'hub.wgen.top');
            await file.writeAsBytes(zip);
          }
        },
        validate: (_) async {});
    addTearDown(tools.dispose);
    expect(await tools.ensure(), true);
    expect(urls, hasLength(2));
  });

  test('代理替换 ZIP 时在运行验证前拒绝，官方连接失败不会退回代理元数据', () async {
    final zip = toolZip();
    var validations = 0;
    var requests = 0;
    var offline = false;
    final tools = ToolEnvironment(
        windows: true,
        rootProvider: () async => root,
        releaseLoader: (uri) async {
          requests++;
          expect(uri.host, 'api.github.com');
          if (offline) throw const SocketException('official unavailable');
          return release(zip);
        },
        download: (_, file, __, ___) async =>
            file.writeAsBytes(List.filled(zip.length, 0)),
        validate: (_) async {
          validations++;
        });
    addTearDown(tools.dispose);
    expect(await tools.ensure(), false);
    expect(validations, 0);
    offline = true;
    expect(await tools.ensure(), false);
    expect(requests, 2);
  });

  test('保留当前/回退目录及活跃租约，租约释放后回收，未知目录不删除', () async {
    final zip = toolZip();
    var tag = 'v5.0.1';
    var downloads = 0;
    final tools = ToolEnvironment(
        windows: true,
        rootProvider: () async => root,
        releaseLoader: (_) async => atVersion(zip, tag),
        download: (_, file, __, ___) async {
          downloads++;
          await file.writeAsBytes(zip);
        },
        validate: (_) async {});
    addTearDown(tools.dispose);
    expect(await tools.ensure(), true);
    final first = tools.directory!;
    final lease = (await tools.acquireLease())!;
    final user = await Directory(p.join(root.path, 'user-files')).create();
    await File(p.join(user.path, 'keep')).writeAsString('keep');
    tag = 'v5.0.2';
    expect(await tools.ensure(force: true), true);
    final second = tools.directory!;
    tag = 'v5.0.3';
    expect(await tools.ensure(force: true), true);
    expect(await Directory(first).exists(), true);
    expect(await Directory(second).exists(), true);
    await lease.release();
    expect(await tools.ensure(force: true), true);
    expect(downloads, 3);
    expect(await Directory(first).exists(), false);
    expect(await Directory(second).exists(), true);
    expect(await user.exists(), true);
  });

  test('清单切换失败回收新目录并保留旧环境，损坏清单可修复', () async {
    final zip = toolZip();
    var tag = 'v5.0.1';
    final tools = ToolEnvironment(
        windows: true,
        rootProvider: () async => root,
        releaseLoader: (_) async => atVersion(zip, tag),
        download: (_, file, __, ___) async => file.writeAsBytes(zip),
        validate: (_) async {});
    addTearDown(tools.dispose);
    expect(await tools.ensure(), true);
    final first = tools.directory;
    final pointer = File(p.join(root.path, 'installed.json'));
    final before = await pointer.readAsString();
    final blocker =
        await Directory(p.join(root.path, 'installed.json.next')).create();
    tag = 'v5.0.2';
    expect(await tools.ensure(force: true), false);
    expect(tools.directory, first);
    expect(await pointer.readAsString(), before);
    final managed = await root
        .list()
        .where((f) => f is Directory && p.basename(f.path).startsWith('v'))
        .toList();
    expect(managed, hasLength(1));
    await blocker.delete();
    await pointer.writeAsString('broken json');
    expect(await tools.ensure(), true);
    expect(tools.version, 'v5.0.2');
  });

  test('其他进程持有文件锁时不回收，退出后可回收', () async {
    final cached = await Directory(p.join(root.path, 'v0.0.1-test')).create();
    await File(p.join(cached.path, cacheMarker))
        .writeAsString('{"managed":true}');
    final lease = File(p.join(cached.path, '.mlink-lease-child'));
    const script = '''import os, sys
f = open(sys.argv[1], 'w+b'); f.write(b'x'); f.flush(); f.seek(0)
if os.name == 'nt':
 import msvcrt
 msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
else:
 import fcntl
 fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
print('READY', flush=True)
sys.stdin.readline()
f.close()
''';
    final child =
        await Process.start('python', ['-u', '-c', script, lease.path]);
    final stderr = child.stderr.transform(utf8.decoder).join();
    try {
      expect(
          await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10)),
          'READY');
      await withToolCacheLock(root, () => pruneToolCache(root, {}));
      expect(await cached.exists(), true);
      child.stdin.writeln('exit');
      await child.stdin.close();
      expect(await child.exitCode, 0, reason: await stderr);
      await withToolCacheLock(root, () => pruneToolCache(root, {}));
      expect(await cached.exists(), false);
    } finally {
      child.kill();
    }
  });
}
