import 'package:equatable/equatable.dart';

/// 表示设备端的文件/目录条目
class FileEntry extends Equatable {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final String? permission;
  final String? linkTarget;
  final DateTime? modifiedTime;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.permission,
    this.linkTarget,
    this.modifiedTime,
  });

  bool get isLink => (permission ?? '').startsWith('l');

  @override
  List<Object?> get props => [name, path, isDirectory, size, permission, linkTarget, modifiedTime];

  FileEntry copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    int? size,
    String? permission,
    String? linkTarget,
    DateTime? modifiedTime,
  }) {
    return FileEntry(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      permission: permission ?? this.permission,
      linkTarget: linkTarget ?? this.linkTarget,
      modifiedTime: modifiedTime ?? this.modifiedTime,
    );
  }

  @override
  String toString() => 'FileEntry(name: $name, path: $path, isDirectory: $isDirectory, linkTarget: $linkTarget)';
}
