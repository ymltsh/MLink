import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/app_config.dart';
import 'tool_cache.dart';

enum ToolPhase { idle, checking, downloading, extracting, ready, failed }

class ScrcpyAsset {
  final String tag;
  final String name;
  final Uri url;
  final int size;
  final String? sha256Digest;
  final Uri? checksumsUrl;

  ScrcpyAsset.fromRelease(Map<String, dynamic> release)
    : tag = release['tag_name'] as String,
      name = _asset(release)['name'] as String,
      url = _officialUrl(_asset(release)['browser_download_url'] as String),
      size = _asset(release)['size'] as int,
      sha256Digest = _digest(_asset(release)['digest'] as String?),
      checksumsUrl = _checksums(release) {
    if (!RegExp(r'^v[0-9][0-9A-Za-z.\-]*$').hasMatch(tag) ||
        release['draft'] == true ||
        release['prerelease'] == true ||
        size <= 0 ||
        size > 256 * 1024 * 1024) {
      throw const FormatException('scrcpy 发布信息无效');
    }
  }

  static Map<String, dynamic> _asset(Map<String, dynamic> release) {
    final tag = release['tag_name'];
    final matches = (release['assets'] as List).where(
      (asset) => asset['name'] == 'scrcpy-win64-$tag.zip',
    );
    if (matches.length != 1) {
      throw const FormatException('最新发布没有 Windows x64 运行包');
    }
    return Map<String, dynamic>.from(matches.single as Map);
  }

  static String? _digest(String? digest) {
    if (digest == null) return null;
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('发布校验和无效');
    }
    return digest.substring(7).toLowerCase();
  }

  static Uri _officialUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith('/Genymobile/scrcpy/releases/download/')) {
      throw const FormatException('运行包必须来自 scrcpy 官方发布');
    }
    return uri;
  }

  static Uri? _checksums(Map<String, dynamic> release) {
    for (final asset in release['assets'] as List) {
      if (asset['name'] == 'SHA256SUMS.txt') {
        return _officialUrl(asset['browser_download_url'] as String);
      }
    }
    return null;
  }
}

typedef ToolDownload =
    Future<void> Function(
      Uri uri,
      File file,
      int maxBytes,
      void Function(int, int?) progress,
    );

/// 私有运行环境。不修改系统 PATH；所有 ADB/scrcpy 调用共用此解析器。
class ToolEnvironment extends ChangeNotifier {
  static final instance = ToolEnvironment();
  static const proxyPreference = 'tools_proxy_base';
  static const requiredFiles = [
    'adb.exe',
    'AdbWinApi.dll',
    'AdbWinUsbApi.dll',
    'scrcpy.exe',
    'scrcpy-server',
  ];
  final Future<Directory> Function() _rootProvider;
  final Future<Map<String, dynamic>> Function(Uri)? _releaseLoader;
  final ToolDownload _download;
  final Future<void> Function(Directory) _validate;
  final bool _windows;
  Future<bool>? _pending;
  Directory? _directory;
  ToolPhase phase = ToolPhase.idle;
  String message = '运行环境尚未检查';
  String proxyBase = AppConfig.defaultToolsProxy;
  String? version;
  String? _archiveDigest;
  Future<ToolLease?> acquireLease() async =>
      _directory == null ? null : await ToolLease.acquire(_directory!);
  double? progress;
  bool get busy =>
      phase == ToolPhase.checking ||
      phase == ToolPhase.downloading ||
      phase == ToolPhase.extracting;
  String? get directory => _directory?.path;

  ToolEnvironment({
    Future<Directory> Function()? rootProvider,
    Future<Map<String, dynamic>> Function(Uri)? releaseLoader,
    ToolDownload? download,
    Future<void> Function(Directory)? validate,
    bool? windows,
  }) : _rootProvider = rootProvider ?? _defaultRoot,
       _releaseLoader = releaseLoader,
       _download = download ?? downloadHttp,
       _validate = validate ?? _validateExecutables,
       _windows = windows ?? Platform.isWindows;

  static Future<Directory> _defaultRoot() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'MLink', 'tools'),
  );

  static String normalizeProxy(String value) {
    if (value.trim().isEmpty) return '';
    final uri = Uri.parse(value.trim());
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('加速源需为 HTTPS 地址，留空则直连 GitHub');
    }
    return '${value.trim().replaceAll(RegExp(r'/+$'), '')}/';
  }

  Uri sourceUri(Uri original) => Uri.parse('$proxyBase$original');

  Future<void> setProxy(String value) async {
    if (busy) throw StateError('下载期间不能修改加速源');
    final normalized = normalizeProxy(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(proxyPreference, normalized);
    proxyBase = normalized;
    notifyListeners();
  }

  String executable(String name) => executableIn(_directory, name);

  String executableIn(Directory? directory, String name) {
    if (name != 'adb' && name != 'scrcpy') return name;
    if (directory == null) {
      if (_windows) throw StateError('ADB / scrcpy 私有运行环境未就绪，请重新检查运行环境');
      return name;
    }
    return p.join(directory.path, '$name.exe');
  }

  Map<String, String>? get processEnvironment => environmentIn(_directory);

  Map<String, String>? environmentIn(Directory? directory) {
    if (directory == null) return null;
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = env.keys.firstWhere(
      (key) => key.toLowerCase() == 'path',
      orElse: () => 'PATH',
    );
    env[pathKey] =
        '${directory.path}${Platform.isWindows ? ';' : ':'}${env[pathKey] ?? ''}';
    env['ADB'] = executableIn(directory, 'adb');
    env['SCRCPY_SERVER_PATH'] = p.join(directory.path, 'scrcpy-server');
    return env;
  }

  Future<bool> ensure({bool force = false}) {
    if (_pending != null) return _pending!;
    _pending = _ensure(force).whenComplete(() => _pending = null);
    return _pending!;
  }

  void _status(ToolPhase value, String text, [double? fraction]) {
    phase = value;
    message = text;
    progress = fraction;
    notifyListeners();
  }

  Future<bool> _ensure(bool force) async {
    Directory? temporary;
    try {
      _status(ToolPhase.checking, '正在检查 ADB / scrcpy 运行环境…');
      final prefs = await SharedPreferences.getInstance();
      proxyBase = normalizeProxy(
        prefs.getString(proxyPreference) ?? AppConfig.defaultToolsProxy,
      );
      if (!_windows) {
        if (!(Platform.isLinux || Platform.isMacOS)) {
          throw const FormatException('自动补全支持 Windows x64；当前平台请手动配置运行环境');
        }
        for (final command in ['adb', 'scrcpy']) {
          final process = await Process.start(command, [
            command == 'adb' ? 'version' : '--version',
          ]);
          await _readVersionProcess(process);
        }
        _status(ToolPhase.ready, '正在使用系统 ADB / scrcpy');
        return true;
      }
      final root = await _rootProvider();
      await root.create(recursive: true);
      final record = File(p.join(root.path, 'installed.json'));
      final restored = await _restore(root, record);
      if (!force && restored) {
        await _prune(root, record);
        _status(ToolPhase.ready, '运行环境已就绪，scrcpy $version');
        return true;
      }
      if (!restored) {
        // 缓存已失效时不得继续解析到损坏的私有可执行文件。
        _directory = null;
        version = null;
      }
      _status(ToolPhase.checking, '正在获取 scrcpy 最新正式版…');
      final release = _releaseLoader != null
          ? await _releaseLoader(Uri.parse(AppConfig.scrcpyLatestApi))
          : await _loadRelease();
      final asset = ScrcpyAsset.fromRelease(release);
      temporary = await root.createTemp('download-');
      final zip = File(p.join(temporary.path, 'package.zip'));
      var digest = asset.sha256Digest;
      if (digest == null) {
        if (asset.checksumsUrl == null) {
          throw const FormatException('官方发布缺少 SHA256 校验和');
        }
        final sums = File(p.join(temporary.path, 'SHA256SUMS.txt'));
        await _download(asset.checksumsUrl!, sums, 1024 * 1024, (_, __) {});
        digest = checksumFor(await sums.readAsString(), asset.name);
      }
      if (restored && version == asset.tag && _archiveDigest == digest) {
        await _prune(root, record);
        _status(ToolPhase.ready, '运行环境已是最新版本，scrcpy $version');
        return true;
      }
      _status(ToolPhase.downloading, '正在下载 scrcpy ${asset.tag}（包含 ADB）…', 0);
      await _download(sourceUri(asset.url), zip, asset.size, (received, total) {
        _status(
          ToolPhase.downloading,
          '正在下载 scrcpy ${asset.tag}（包含 ADB）…',
          (received / asset.size).clamp(0, 1).toDouble(),
        );
      });
      if (await zip.length() != asset.size) {
        throw const FormatException('运行包下载不完整');
      }
      _status(ToolPhase.extracting, '正在校验并解压运行环境…');
      final bundle = await compute(extractToolBundle, <String, String>{
        'zip': zip.path,
        'destination': p.join(temporary.path, 'unpacked'),
        'sha256': digest,
      });
      await _validate(Directory(bundle));
      final hashes = await compute(bundleHashes, bundle);
      await withToolCacheLock(root, () async {
        Map<String, dynamic>? previous;
        try {
          if (await record.exists()) {
            previous =
                jsonDecode(await record.readAsString()) as Map<String, dynamic>;
          }
        } catch (_) {
          /* 损坏的清单由本次安装修复 */
        }
        final installed = await root.createTemp('${asset.tag}-');
        final nextRecord = File(p.join(root.path, 'installed.json.next'));
        try {
          // 目标由 createTemp 生成且位于 root 中，不覆盖已有版本。
          await installed.delete();
          await Directory(bundle).rename(installed.path);
          await File(
            p.join(installed.path, cacheMarker),
          ).writeAsString('{"managed":true}', flush: true);
          await nextRecord.writeAsString(
            jsonEncode({
              'version': asset.tag,
              'archive_sha256': digest,
              'folder': p.basename(installed.path),
              'files': hashes,
              'previous_folder': previous?['folder'],
            }),
            flush: true,
          );
          await nextRecord.rename(record.path);
          _directory = installed;
          version = asset.tag;
          _archiveDigest = digest;
        } catch (_) {
          // 根锁阻止任何进程在指针切换前取得这个新目录的使用租约。
          if (await installed.exists()) await installed.delete(recursive: true);
          if (await nextRecord.exists()) await nextRecord.delete();
          rethrow;
        }
        await _pruneUnlocked(root, record);
      });
      _status(ToolPhase.ready, '运行环境已就绪，scrcpy $version');
      return true;
    } catch (error) {
      _status(ToolPhase.failed, '运行环境补全失败：$error');
      return false;
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      } on FileSystemException {
        // 清理失败不掩盖已完成的安装结果；下次仍可复用已验证的清单。
      }
    }
  }

  Future<bool> _restore(Directory root, File record) =>
      withToolCacheLock(root, () => _restoreUnlocked(root, record));

  Future<bool> _restoreUnlocked(Directory root, File record) async {
    try {
      if (!await record.exists()) return false;
      final data =
          jsonDecode(await record.readAsString()) as Map<String, dynamic>;
      final folder = data['folder'] as String;
      if (folder != p.basename(folder) ||
          folder.contains('..') ||
          folder.contains('\\') ||
          folder.contains(':')) {
        return false;
      }
      final candidate = Directory(p.join(root.path, folder));
      if (await FileSystemEntity.type(candidate.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          !p.equals(
            p.dirname(await candidate.resolveSymbolicLinks()),
            await root.resolveSymbolicLinks(),
          )) {
        return false;
      }
      final expected = Map<String, dynamic>.from(data['files'] as Map);
      final actual = await compute(bundleHashes, candidate.path);
      if (!mapEquals(expected, actual)) return false;
      await _validate(candidate);
      _directory = candidate;
      version = data['version'] as String;
      _archiveDigest = data['archive_sha256'] as String?;
      await File(
        p.join(candidate.path, cacheMarker),
      ).writeAsString('{"managed":true}', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _prune(Directory root, File record) =>
      withToolCacheLock(root, () => _pruneUnlocked(root, record));

  Future<void> _pruneUnlocked(Directory root, File record) async {
    try {
      final data =
          jsonDecode(await record.readAsString()) as Map<String, dynamic>;
      final keep = <String>{};
      for (final value in [data['folder'], data['previous_folder']]) {
        if (value is String && value == p.basename(value)) keep.add(value);
      }
      await pruneToolCache(root, keep);
    } on FileSystemException {
      /* 不影响已安装版本，下次再回收。 */
    }
  }

  Future<Map<String, dynamic>> _loadRelease() async {
    // 校验依据始终通过官方 TLS 通道获取，不通过文件代理。
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse(AppConfig.scrcpyLatestApi),
        );
        request.headers.set(HttpHeaders.userAgentHeader, 'MLink');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('官方发布接口返回 ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('发布信息过大');
          }
        }
        final result = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        ScrcpyAsset.fromRelease(result);
        return result;
      })().timeout(const Duration(seconds: 20));
    } finally {
      client.close(force: true);
    }
  }

  static String checksumFor(String text, String filename) {
    for (final line in text.split('\n')) {
      final match = RegExp(
        r'^([a-fA-F0-9]{64})\s+\*?(.+?)\s*$',
      ).firstMatch(line);
      if (match != null && match[2] == filename) return match[1]!.toLowerCase();
    }
    throw const FormatException('没有找到运行包 SHA256 校验和');
  }

  static Future<void> _validateExecutables(Directory directory) async {
    for (final name in requiredFiles) {
      if (!await File(p.join(directory.path, name)).exists()) {
        throw FormatException('运行包缺少 $name');
      }
    }
    for (final name in ['adb', 'scrcpy']) {
      final process = await Process.start(p.join(directory.path, '$name.exe'), [
        name == 'adb' ? 'version' : '--version',
      ], workingDirectory: directory.path);
      await _readVersionProcess(process);
    }
  }

  static Future<void> _readVersionProcess(Process process) async {
    // 同时排空两路输出，超时时仅结束本次启动的版本检查进程。
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.drain<void>();
    try {
      final exit = await process.exitCode.timeout(const Duration(seconds: 10));
      if (exit != 0) throw ProcessException('ADB / scrcpy', [], '运行检查失败', exit);
    } on TimeoutException {
      process.kill();
      rethrow;
    } finally {
      await Future.wait([stdoutDone, stderrDone]);
    }
  }

  static Future<void> downloadHttp(
    Uri uri,
    File file,
    int maxBytes,
    void Function(int, int?) onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'MLink');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('下载返回 ${response.statusCode}');
        }
        if (response.contentLength > maxBytes) {
          throw const FormatException('下载文件大小异常');
        }
        sink = file.openWrite();
        var received = 0;
        var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > maxBytes) throw const FormatException('下载文件超出预期大小');
          sink!.add(chunk);
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds > 100) {
            onProgress(
              received,
              response.contentLength > 0 ? response.contentLength : null,
            );
            lastUpdate = now;
          }
        }
        await sink!.flush();
        onProgress(
          received,
          response.contentLength > 0 ? response.contentLength : null,
        );
      })().timeout(const Duration(minutes: 10));
    } finally {
      client.close(force: true);
      await sink?.close();
    }
  }
}

/// 在隔离线程中校验、解压，拒绝路径穿越、符号链接和异常膨胀的归档。
String extractToolBundle(Map<String, String> args) {
  final bytes = File(args['zip']!).readAsBytesSync();
  if (sha256.convert(bytes).toString() != args['sha256']) {
    throw const FormatException('运行包 SHA256 校验失败');
  }
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final destination = p.absolute(args['destination']!);
  var expandedSize = 0;
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    final target = p.normalize(p.join(destination, name));
    expandedSize += entry.size;
    if (p.posix.isAbsolute(name) ||
        p.windows.isAbsolute(name) ||
        name.contains(':') ||
        !p.isWithin(destination, target) ||
        entry.isSymbolicLink ||
        expandedSize > 512 * 1024 * 1024) {
      throw const FormatException('运行包包含不安全或过大的文件');
    }
  }
  for (final entry in archive) {
    final target = p.join(destination, entry.name.replaceAll('\\', '/'));
    if (entry.isFile) {
      File(target).parent.createSync(recursive: true);
      File(target).writeAsBytesSync(entry.content as List<int>);
    } else {
      Directory(target).createSync(recursive: true);
    }
  }
  final executables = Directory(destination)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => p.basename(file.path) == 'scrcpy.exe')
      .toList();
  if (executables.length != 1) throw const FormatException('运行包目录结构无效');
  final bundle = executables.single.parent;
  for (final name in ToolEnvironment.requiredFiles) {
    if (!File(p.join(bundle.path, name)).existsSync()) {
      throw FormatException('运行包缺少 $name');
    }
  }
  return bundle.path;
}

Map<String, String> bundleHashes(String directory) {
  final result = <String, String>{};
  for (final file in Directory(
    directory,
  ).listSync(recursive: true, followLinks: false).whereType<File>()) {
    if (p.basename(file.path) == cacheMarker ||
        p.basename(file.path).startsWith('.mlink-lease-')) {
      continue;
    }
    result[p.relative(file.path, from: directory)] = sha256
        .convert(file.readAsBytesSync())
        .toString();
  }
  for (final name in ToolEnvironment.requiredFiles) {
    if (!result.containsKey(name)) throw FormatException('本地运行环境缺少 $name');
  }
  return result;
}
