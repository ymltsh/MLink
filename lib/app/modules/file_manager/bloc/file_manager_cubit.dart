import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import '../services/adb_file_service_clean.dart';
import 'file_manager_state.dart';

class FileManagerCubit extends Cubit<FileManagerState> {
  final AdbFileService service;

  // Accept deviceSerial and create the AdbFileService internally so ADB commands
  // target the correct device.
  FileManagerCubit({required String deviceSerial})
      : service = AdbFileService(deviceSerial: deviceSerial),
        super(FileManagerState.initial());

  Future<void> loadPath(String path) async {
    // 1. 规范化输入路径，避免多斜杠或拼接错误
    final normalized = p.posix.normalize(path);
    emit(state.copyWith(status: FileManagerStatus.loading, currentPath: normalized));
    try {
      final files = await service.ls(normalized, useRoot: state.isRootMode);
      emit(state.copyWith(files: files, status: FileManagerStatus.success));
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

  Future<void> downloadFile(FileEntry file, String localPath) async {
    emit(state.copyWith(downloadProgress: 0.0, status: FileManagerStatus.loading));
    try {
      await for (final p in service.pull(file.path, localPath, useRoot: state.isRootMode)) {
        emit(state.copyWith(downloadProgress: p));
      }
      emit(state.copyWith(downloadProgress: 1.0, status: FileManagerStatus.success));
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    emit(state.copyWith(uploadProgress: 0.0, status: FileManagerStatus.loading));
    try {
      final targetRemote = p.posix.normalize(remotePath);
      await for (final p in service.push(localPath, targetRemote, useRoot: state.isRootMode)) {
        emit(state.copyWith(uploadProgress: p));
      }
      emit(state.copyWith(uploadProgress: 1.0, status: FileManagerStatus.success));
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
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
