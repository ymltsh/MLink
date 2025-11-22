import 'dart:async';

import 'package:bloc/bloc.dart';

import '../models/file_entry.dart';
import '../services/adb_file_service_clean.dart';
import 'file_manager_state.dart';

class FileManagerCubit extends Cubit<FileManagerState> {
  final AdbFileService service;
  FileManagerCubit({required this.service}) : super(FileManagerState.initial());

  Future<void> loadPath(String path) async {
    emit(state.copyWith(status: FileManagerStatus.loading, currentPath: path));
    try {
      final files = await service.ls(path, useRoot: state.isRootMode);
      emit(state.copyWith(files: files, status: FileManagerStatus.success));
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> mapsUp() async {
    final current = state.currentPath;
    if (current == '/' || current.isEmpty) return;
    final parent = current.contains('/') ? current.substring(0, current.lastIndexOf('/')) : '/';
    await loadPath(parent.isEmpty ? '/' : parent);
  }

  Future<void> enterDirectory(FileEntry dir) async {
    if (!dir.isDirectory) return;
    final newPath = dir.path;
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
      await for (final p in service.push(localPath, remotePath, useRoot: state.isRootMode)) {
        emit(state.copyWith(uploadProgress: p));
      }
      emit(state.copyWith(uploadProgress: 1.0, status: FileManagerStatus.success));
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> makeDir(String name) async {
    final target = '${state.currentPath}/${name}';
    try {
      await service.mkdir(target, useRoot: state.isRootMode);
      await loadPath(state.currentPath);
    } catch (e) {
      emit(state.copyWith(status: FileManagerStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> rename(FileEntry entry, String newName) async {
    final parent = entry.path.contains('/') ? entry.path.substring(0, entry.path.lastIndexOf('/')) : '';
    final target = parent.isEmpty ? newName : '$parent/$newName';
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
