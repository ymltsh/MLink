import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../services/adb_file_service.dart';
import '../../tools/services/tool_cancellation.dart';
import 'file_manager_state.dart';
import 'package:adb_tool/utils/app_output.dart';

class FileManagerCubit extends Cubit<FileManagerState> {
  final AdbFileService service;
  StreamSubscription<String>? _logSubscription;
  bool _closing = false;
  bool _busy = false;
  int _readGeneration = 0;
  bool get _alive => !_closing && !isClosed;

  FileManagerCubit({required String deviceSerial, AdbFileService? service})
      : service = service ?? AdbFileService(deviceSerial: deviceSerial),
        super(FileManagerState.initial()) {
    _logSubscription = this.service.logStream.listen((raw) {
      if (_alive) appendAppOutput(raw, task: '文件');
    });
  }

  void _publish(FileManagerState next) {
    if (_alive) emit(next);
  }

  void _checkAlive() {
    if (!_alive) throw ToolCancelled();
  }

  @override
  Future<void> close() async {
    _closing = true;
    _readGeneration++;
    service.dispose();
    await _logSubscription?.cancel();
    return super.close();
  }

  Future<void> loadPath(String path) async {
    if (!_alive) return;
    final generation = ++_readGeneration;
    final normalized = p.posix.normalize(path);
    _publish(state.copyWith(
        status: FileManagerStatus.loading,
        currentPath: normalized,
        errorMessage: null));
    try {
      final files = await service.ls(normalized, useRoot: state.isRootMode);
      if (!_alive || generation != _readGeneration) return;
      _publish(state.copyWith(
          files: files,
          status: FileManagerStatus.success,
          selectedFiles: <FileEntry>{},
          errorMessage: null));
    } catch (e) {
      if (generation != _readGeneration) return;
      _publish(state.copyWith(
          files: [],
          selectedFiles: <FileEntry>{},
          status: FileManagerStatus.failure,
          errorMessage: e.toString()));
    }
  }

  Future<void> search(String query) async {
    if (!_alive) return;
    if (query.isEmpty) return loadPath(state.currentPath);
    final generation = ++_readGeneration;
    _publish(
        state.copyWith(status: FileManagerStatus.loading, errorMessage: null));
    try {
      final files = await service.search(state.currentPath, query,
          useRoot: state.isRootMode);
      if (!_alive || generation != _readGeneration) return;
      _publish(state.copyWith(
          files: files,
          selectedFiles: <FileEntry>{},
          status: FileManagerStatus.success));
    } catch (e) {
      if (generation != _readGeneration) return;
      _publish(state.copyWith(
          status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> mapsUp() async {
    if (state.currentPath != '/') {
      await loadPath(p.posix.dirname(state.currentPath));
    }
  }

  Future<void> enterDirectory(FileEntry dir) async {
    if (dir.isDirectory) await loadPath(dir.path);
  }

  Future<void> jumpToPath(String path) => loadPath(path);
  void toggleSelection(FileEntry file) {
    if (!_alive) return;
    final selected = Set<FileEntry>.from(state.selectedFiles);
    if (selected.any((e) => e.path == file.path)) {
      selected.removeWhere((e) => e.path == file.path);
    } else {
      selected.add(file);
    }
    _publish(state.copyWith(selectedFiles: selected));
  }

  void selectAll() =>
      _publish(state.copyWith(selectedFiles: Set.of(state.files)));
  void clearSelection() =>
      _publish(state.copyWith(selectedFiles: <FileEntry>{}));
  void toggleRootMode() {
    if (!_alive || _busy) return;
    _publish(state.copyWith(isRootMode: !state.isRootMode));
    unawaited(loadPath(state.currentPath));
  }

  Future<void> _perform(Future<void> Function(bool root, String origin) action,
      {bool reload = true}) async {
    if (!_alive || _busy) return;
    _busy = true;
    final origin = state.currentPath;
    final root = state.isRootMode;
    _publish(
        state.copyWith(status: FileManagerStatus.loading, errorMessage: null));
    try {
      await action(root, origin);
      _checkAlive();
      if (reload && state.currentPath == origin) {
        await loadPath(origin);
      } else {
        _publish(state.copyWith(status: FileManagerStatus.success));
      }
    } catch (error) {
      if (_alive) {
        appendAppOutput('任务失败：$error', task: '文件');
        _publish(state.copyWith(
            status: FileManagerStatus.failure, errorMessage: error.toString()));
      }
    } finally {
      _busy = false;
      _publish(state.copyWith(progress: null));
    }
  }

  Future<void> deleteFile(FileEntry file) =>
      _perform((root, _) => service.delete(file.path, useRoot: root));
  Future<void> deleteSelected() {
    final files = state.selectedFiles.toList();
    return _perform((root, _) async {
      for (final file in files) {
        _checkAlive();
        await service.delete(file.path, useRoot: root);
      }
    });
  }

  Future<void> _transfer(Stream<double> stream, String name) async {
    _publish(state.copyWith(progress: 0.0));
    var last = -100;
    await for (final progress in stream) {
      _checkAlive();
      _publish(state.copyWith(progress: progress));
      final percent = (progress * 100).toInt();
      if (percent - last >= 10 || percent == 100 && last != 100) {
        appendAppOutput('$name：$percent%', task: '传输');
        last = percent;
      }
    }
    _checkAlive();
  }

  Future<void> downloadFile(FileEntry file, String localPath) => _perform(
      (root, _) => _transfer(
          service.pull(file.path, localPath, useRoot: root), file.name),
      reload: false);
  Future<void> downloadSelected(String localDir) {
    final files = state.selectedFiles.toList();
    return _perform((root, _) async {
      for (final file in files) {
        _checkAlive();
        await _transfer(
            service.pull(file.path, p.join(localDir, file.name), useRoot: root),
            file.name);
      }
      clearSelection();
    }, reload: false);
  }

  Future<void> uploadFile(String localPath, String remotePath) =>
      _perform((root, origin) {
        final localLooking = remotePath.contains('\\') ||
            RegExp(r'^[A-Za-z]:').hasMatch(remotePath);
        final target = localLooking
            ? p.posix.join(origin, p.basename(localPath))
            : p.posix.normalize(remotePath);
        return _transfer(service.push(localPath, target, useRoot: root),
            p.basename(localPath));
      });
  Future<void> uploadFiles(List<String> localPaths) {
    final files = List.of(localPaths);
    return _perform((root, origin) async {
      for (final file in files) {
        _checkAlive();
        await _transfer(
            service.push(file, p.posix.join(origin, p.basename(file)),
                useRoot: root),
            p.basename(file));
      }
    });
  }

  Future<void> makeDir(String name) => _perform((root, origin) =>
      service.mkdir(p.posix.join(origin, name), useRoot: root));
  Future<void> rename(FileEntry entry, String newName) =>
      _perform((root, _) => service.rename(
          entry.path, p.posix.join(p.posix.dirname(entry.path), newName),
          useRoot: root));
  Future<void> renameSelected(String newName) async {
    if (state.selectedFiles.length == 1) {
      await rename(state.selectedFiles.first, newName);
    }
  }
}
