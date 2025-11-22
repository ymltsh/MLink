import 'package:equatable/equatable.dart';
import '../models/file_entry.dart';

enum FileManagerStatus { initial, loading, success, failure }

class FileManagerState extends Equatable {
  final String currentPath;
  final List<FileEntry> files;
  final FileManagerStatus status;
  final bool isRootMode;
  final double uploadProgress;
  final double downloadProgress;
  final String? errorMessage;

  const FileManagerState({
    required this.currentPath,
    required this.files,
    required this.status,
    required this.isRootMode,
    required this.uploadProgress,
    required this.downloadProgress,
    this.errorMessage,
  });

  factory FileManagerState.initial() => const FileManagerState(
        currentPath: '/sdcard',
        files: [],
        status: FileManagerStatus.initial,
        isRootMode: false,
        uploadProgress: 0.0,
        downloadProgress: 0.0,
      );

  FileManagerState copyWith({
    String? currentPath,
    List<FileEntry>? files,
    FileManagerStatus? status,
    bool? isRootMode,
    double? uploadProgress,
    double? downloadProgress,
    String? errorMessage,
  }) {
    return FileManagerState(
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
      status: status ?? this.status,
      isRootMode: isRootMode ?? this.isRootMode,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [currentPath, files, status, isRootMode, uploadProgress, downloadProgress, errorMessage];
}
