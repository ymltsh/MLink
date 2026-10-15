import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

const cacheMarker = '.mlink-cache.json';
final _localLeases = <String, int>{};
final _queues = <String, Future<void>>{};

Future<T> withToolCacheLock<T>(
    Directory root, Future<T> Function() action) async {
  final key = p.normalize(root.absolute.path);
  final previous = _queues[key] ?? Future<void>.value();
  final done = Completer<void>();
  _queues[key] = done.future;
  await previous;
  try {
    return await _withFileLock(root, action);
  } finally {
    done.complete();
    if (identical(_queues[key], done.future)) _queues.remove(key);
  }
}

Future<T> _withFileLock<T>(Directory root, Future<T> Function() action) async {
  final lock =
      await File(p.join(root.path, '.cache.lock')).open(mode: FileMode.append);
  var locked = false;
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!locked) {
      try {
        await lock.lock(FileLock.exclusive);
        locked = true;
      } on FileSystemException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    return await action();
  } finally {
    if (locked) await lock.unlock();
    await lock.close();
  }
}

class ToolLease {
  final Directory directory;
  final RandomAccessFile _handle;
  final File _file;
  bool _released = false;
  ToolLease._(this.directory, this._handle, this._file);

  static Future<ToolLease> acquire(Directory directory) =>
      withToolCacheLock(directory.parent, () async {
        if (!await directory.exists()) throw StateError('运行环境缓存已回收，请重新检查运行环境');
        final file = File(p.join(directory.path,
            '.mlink-lease-$pid-${DateTime.now().microsecondsSinceEpoch}'));
        final handle = await file.open(mode: FileMode.append);
        try {
          await handle.lock(FileLock.exclusive);
        } catch (_) {
          await handle.close();
          rethrow;
        }
        _localLeases.update(p.normalize(directory.absolute.path), (n) => n + 1,
            ifAbsent: () => 1);
        return ToolLease._(directory, handle, file);
      });

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
      final key = p.normalize(directory.absolute.path);
      final remaining = (_localLeases[key] ?? 1) - 1;
      if (remaining == 0) {
        _localLeases.remove(key);
      } else {
        _localLeases[key] = remaining;
      }
      try {
        await _file.delete();
      } on FileSystemException {/* 已被回收 */}
    }
  }
}

/// 调用方持有根目录锁；仅删除有本应用标记、位于根目录内且未使用的目录。
Future<void> pruneToolCache(Directory root, Set<String> keep) async {
  final resolvedRoot = await root.resolveSymbolicLinks();
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory || keep.contains(p.basename(entity.path))) {
      continue;
    }
    if (!await File(p.join(entity.path, cacheMarker)).exists()) continue;
    try {
      if ((jsonDecode(
                  await File(p.join(entity.path, cacheMarker)).readAsString())
              as Map)['managed'] !=
          true) {
        continue;
      }
    } catch (_) {
      continue;
    }
    final resolved = await entity.resolveSymbolicLinks();
    if (!p.equals(p.dirname(resolved), resolvedRoot) ||
        !p.isWithin(resolvedRoot, resolved)) {
      continue;
    }
    if ((_localLeases[p.normalize(entity.absolute.path)] ?? 0) != 0) continue;
    var used = false;
    await for (final lease in entity.list(followLinks: false)) {
      if (lease is! File ||
          !p.basename(lease.path).startsWith('.mlink-lease-')) {
        continue;
      }
      RandomAccessFile? handle;
      var locked = false;
      try {
        handle = await lease.open(mode: FileMode.append);
        await handle.lock(FileLock.exclusive);
        locked = true;
      } on FileSystemException {
        used = true;
      } finally {
        if (locked) await handle!.unlock();
        await handle?.close();
      }
      if (used) break;
    }
    if (!used) {
      try {
        // 最后才删除标记，部分文件被系统占用时，下次仍能识别并重试。
        await for (final child in entity.list(followLinks: false)) {
          if (p.basename(child.path) != cacheMarker) {
            await child.delete(recursive: true);
          }
        }
        await File(p.join(entity.path, cacheMarker)).delete();
        await entity.delete();
      } on FileSystemException {/* DLL 仍被加载等情况留待下次检查。 */}
    }
  }
}
