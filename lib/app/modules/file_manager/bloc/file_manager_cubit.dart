import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import 'package:adb_tool/app/modules/file_manager/services/adb_file_service.dart';
import 'file_manager_state.dart';
import 'package:adb_tool/utils/app_output.dart';

class FileManagerCubit extends Cubit<FileManagerState> {
  final AdbFileService service;
  StreamSubscription<String>? _logSubscription;

  // track last logged percent per file tag to avoid flooding the output
  final Map<String, int> _lastLoggedPercent = {};

  // Accept deviceSerial and create the AdbFileService internally so ADB commands
  // target the correct device.
  FileManagerCubit({required String deviceSerial})
      : service = AdbFileService(deviceSerial: deviceSerial),
        super(FileManagerState.initial()) {
    // 绑定日志流
    _logSubscription = service.logStream.listen((raw) {
      appendAppOutput('[ADB] $raw');
    });
  }

  @override
  Future<void> close() async {
    await _logSubscription?.cancel();
    try {
      service.dispose();
    } catch (_) {}
    return super.close();
  }

  Future<void> loadPath(String path) async {
    // 1. 规范化输入路径，避免多斜杠或拼接错误
    final normalized = p.posix.normalize(path);
    emit(state.copyWith(status: FileManagerStatus.loading, currentPath: normalized));
    try {
      final files = await service.ls(normalized, useRoot: state.isRootMode);
      // clear selection when changing path
      emit(state.copyWith(files: files, status: FileManagerStatus.success, selectedFiles: <FileEntry>{}));
    } catch (e) {
      // 在失败时只更新状态为 failure，而不进行自动重试，防止死循环
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> mapsUp() async {
    final current = state.currentPath;
    if (current == '/' || current.isEmpty) return;
    final parent = p.posix.dirname(current);
    final normalizedParent = p.posix.normalize(parent.isEmpty ? '/' : parent);
    await loadPath(normalizedParent);
  }

  Future<void> enterDirectory(FileEntry dir) async {
    if (!dir.isDirectory) return;
    final newPath = p.posix.normalize(dir.path);
    await loadPath(newPath);
  }

  /// Toggle selection for a single file entry
  void toggleSelection(FileEntry file) {
    final set = Set<FileEntry>.from(state.selectedFiles);
    final exists = set.any((e) => e.path == file.path);
    if (exists) {
      set.removeWhere((e) => e.path == file.path);
    } else {
      set.add(file);
    }
    emit(state.copyWith(selectedFiles: set));
  }

  /// Select all files currently listed
  void selectAll() {
    emit(state.copyWith(selectedFiles: Set<FileEntry>.from(state.files)));
  }

  /// Clear selection
  void clearSelection() {
    emit(state.copyWith(selectedFiles: <FileEntry>{}));
  }

  /// Jump to path via address bar
  Future<void> jumpToPath(String path) async {
    await loadPath(path);
  }

  void toggleRootMode() {
    emit(state.copyWith(isRootMode: !state.isRootMode));
    // reload current path
    loadPath(state.currentPath);
  }

  Future<void> deleteFile(FileEntry file) async {
    emit(state.copyWith(status: FileManagerStatus.loading));
    try {
      await service.delete(file.path, useRoot: state.isRootMode);
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  /// Delete selected files (batch)
  Future<void> deleteSelected() async {
    if (state.selectedFiles.isEmpty) return;
    emit(state.copyWith(status: FileManagerStatus.loading));
    try {
      for (final f in state.selectedFiles) {
        await service.delete(f.path, useRoot: state.isRootMode);
      }
      await loadPath(state.currentPath);
      emit(state.copyWith(selectedFiles: <FileEntry>{}));
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> downloadFile(FileEntry file, String localPath) async {
    final tag = file.name;
    _lastLoggedPercent[tag] = -100;
    emit(state.copyWith(progress: 0.0));
    try {
      await for (final p in service.pull(file.path, localPath, useRoot: state.isRootMode)) {
        emit(state.copyWith(progress: p));
        _logProgress(tag, p);
      }
      emit(state.copyWith(progress: 1.0));
    } catch (e) {
      appendAppOutput('下载失败 $tag: $e');
    } finally {
      // ensure progress is cleared so UI is not stuck
      emit(state.copyWith(progress: null));
    }
  }

  /// Download all selected files into [localDir]
  Future<void> downloadSelected(String localDir) async {
    if (state.selectedFiles.isEmpty) return;
    for (final f in state.selectedFiles) {
      final local = p.join(localDir, f.name);
      await downloadFile(f, local);
    }
    // clear progress after done
    emit(state.copyWith(downloadProgress: 0.0, selectedFiles: <FileEntry>{}));
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    final tag = p.posix.basename(localPath);
    _lastLoggedPercent[tag] = -100;
    emit(state.copyWith(progress: 0.0));
    try {
      final targetRemote = p.posix.normalize(remotePath);
      await for (final p in service.push(localPath, targetRemote, useRoot: state.isRootMode)) {
        emit(state.copyWith(progress: p));
        _logProgress(tag, p);
      }
      emit(state.copyWith(progress: 1.0));
      await loadPath(state.currentPath);
    } catch (e) {
      appendAppOutput('上传失败 $tag: $e');
    } finally {
      // always reset the transient progress indicator
      emit(state.copyWith(progress: null));
    }
  }

  /// Upload multiple local files to current remote path
  Future<void> uploadFiles(List<String> localPaths) async {
    // Upload sequentially but keep UI non-blocking with progress updates
    for (final local in localPaths) {
      final remote = p.posix.join(state.currentPath, p.posix.basename(local));
      try {
        await uploadFile(local, remote);
      } catch (e) {
        appendAppOutput('上传任务出错 ${p.posix.basename(local)}: $e');
      }
    }
  }

  /// Log progress with throttling to avoid flooding the UI output panel.
  /// Only logs at start (0%), every +10% increment, and at 100%.
  void _logProgress(String tag, double percent) {
    final p100 = (percent * 100).toInt();
    final last = _lastLoggedPercent[tag] ?? -100;
    if (p100 == 0 || p100 == 100 || p100 - last >= 10) {
      appendAppOutput('正在传输 $tag: $p100%');
      _lastLoggedPercent[tag] = p100;
    }
  }

  Future<void> makeDir(String name) async {
    final target = p.posix.normalize(p.posix.join(state.currentPath, name));
    try {
      await service.mkdir(target, useRoot: state.isRootMode);
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> rename(FileEntry entry, String newName) async {
    final parent = p.posix.dirname(entry.path);
    final target = p.posix.normalize(parent == '.' ? newName : p.posix.join(parent, newName));
    try {
      await service.rename(entry.path, target, useRoot: state.isRootMode);
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  /// Rename the single selected file to [newName]
  Future<void> renameSelected(String newName) async {
    if (state.selectedFiles.length != 1) return;
    final entry = state.selectedFiles.first;
    await rename(entry, newName);
  }

  Future<void> search(String query) async {
    emit(state.copyWith(status: FileManagerStatus.loading));
    try {
      final results = await service.search(state.currentPath, query, useRoot: state.isRootMode);
      emit(state.copyWith(files: results, status: FileManagerStatus.success));
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }
}
