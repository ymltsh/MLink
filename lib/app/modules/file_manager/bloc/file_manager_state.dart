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
  final double? progress;
  final String? errorMessage;
  final Set<FileEntry> selectedFiles;

  const FileManagerState({
    required this.currentPath,
    required this.files,
    required this.status,
    required this.isRootMode,
    required this.uploadProgress,
    required this.downloadProgress,
    this.progress,
    this.errorMessage,
    required this.selectedFiles,
  });

  factory FileManagerState.initial() => const FileManagerState(
        currentPath: '/sdcard',
        files: [],
        status: FileManagerStatus.initial,
        isRootMode: false,
        uploadProgress: 0.0,
        downloadProgress: 0.0,
      progress: null,
      selectedFiles: const <FileEntry>{},
      );

  FileManagerState copyWith({
    String? currentPath,
    List<FileEntry>? files,
    FileManagerStatus? status,
    bool? isRootMode,
    double? uploadProgress,
    double? downloadProgress,
    double? progress,
    String? errorMessage,
    Set<FileEntry>? selectedFiles,
  }) {
    return FileManagerState(
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
      status: status ?? this.status,
      isRootMode: isRootMode ?? this.isRootMode,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      selectedFiles: selectedFiles ?? this.selectedFiles,
    );
  }

  @override
  // Use file paths for stable comparison of selected files
  List<Object?> get props => [
        currentPath,
        files,
        status,
        isRootMode,
      progress,
        uploadProgress,
        downloadProgress,
        errorMessage,
        selectedFiles.map((e) => e.path).toList(),
      ];
}
