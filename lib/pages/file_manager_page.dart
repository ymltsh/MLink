import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../app/modules/file_manager/bloc/file_manager_cubit.dart';
import '../app/modules/file_manager/bloc/file_manager_state.dart';
import '../app/modules/file_manager/models/file_entry.dart';

/// File Manager Page with editable address bar, multi-select and toolbar
class FileManagerPage extends StatelessWidget {
  final String serial;

  const FileManagerPage({Key? key, required this.serial}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FileManagerCubit(deviceSerial: serial)..loadPath('/sdcard'),
      child: const _FileManagerView(),
    );
  }
}

class _FileManagerView extends StatefulWidget {
  const _FileManagerView({Key? key}) : super(key: key);

  @override
  State<_FileManagerView> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<_FileManagerView> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _renameController = TextEditingController();
  bool _isEditingPath = false;

  @override
  void dispose() {
    _pathController.dispose();
    _searchController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FileManagerCubit, FileManagerState>(
      listener: (context, state) {
        // Update path controller when state changes, but avoid overwriting while user edits
        if (!_isEditingPath && _pathController.text != state.currentPath) {
          _pathController.text = state.currentPath;
        }
      },
      child: BlocBuilder<FileManagerCubit, FileManagerState>(builder: (context, state) {
        final cubit = context.read<FileManagerCubit>();
        final selected = state.selectedFiles;
        return Column(
          children: [
            // Address bar area
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(isDense: true, hintText: '路径'),
                      onTap: () => _isEditingPath = true,
                      onChanged: (_) => _isEditingPath = true,
                      onSubmitted: (v) async {
                        _isEditingPath = false;
                        if (v.trim().isNotEmpty) await cubit.jumpToPath(v.trim());
                      },
                      onEditingComplete: () => _isEditingPath = false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => cubit.loadPath(state.currentPath),
                  ),
                  Row(
                    children: [
                      const Text('Root'),
                      Switch(value: state.isRootMode, onChanged: (_) => cubit.toggleRootMode()),
                    ],
                  ),
                ],
              ),
            ),

            // Action toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.grey.shade50,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('上传'),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                      if (result != null) {
                        final paths = result.paths.whereType<String>().toList();
                        if (paths.isNotEmpty) await cubit.uploadFiles(paths);
                      }
                    },
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('下载'),
                    onPressed: selected.isNotEmpty
                        ? () async {
                            final dir = await FilePicker.platform.getDirectoryPath();
                            if (dir != null) await cubit.downloadSelected(dir);
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('删除'),
                    onPressed: selected.isNotEmpty
                        ? () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('确认删除'),
                                content: Text('确定删除选中的 ${selected.length} 个条目吗？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
                                  TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true) await cubit.deleteSelected();
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('重命名'),
                    onPressed: selected.length == 1
                        ? () async {
                            final entry = selected.first;
                            _renameController.text = entry.name;
                            final newName = await showDialog<String?>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('重命名'),
                                content: TextField(controller: _renameController),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx, null), child: const Text('取消')),
                                  TextButton(onPressed: () => Navigator.pop(dctx, _renameController.text.trim()), child: const Text('确定')),
                                ],
                              ),
                            );
                            if (newName != null && newName.isNotEmpty) await cubit.renameSelected(newName);
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('属性'),
                    onPressed: selected.length == 1
                        ? () {
                            final e = selected.first;
                            showDialog<void>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('属性'),
                                content: Text('路径: ${e.path}\n类型: ${e.isDirectory ? '目录' : '文件'}\n大小: ${e.size ?? '-'}\n权限: ${e.permission ?? '-'}\n修改时间: ${e.modifiedTime ?? '-'}'),
                                actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('关闭'))],
                              ),
                            );
                          }
                        : null,
                  ),

                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text('已选: ${selected.length} / 条目: ${state.files.length}'),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(hintText: '搜索文件/名称', isDense: true),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) context.read<FileManagerCubit>().search(v.trim());
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      final v = _searchController.text.trim();
                      if (v.isNotEmpty) context.read<FileManagerCubit>().search(v);
                    },
                  )
                ],
              ),
            ),

            // File list
            Expanded(
              child: state.status == FileManagerStatus.loading
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: state.files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final entry = state.files[idx];
                          final checked = state.selectedFiles.any((e) => e.path == entry.path);
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: ListTile(
                              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                                Checkbox(
                                  value: checked,
                                  onChanged: (_) => cubit.toggleSelection(entry),
                                ),
                                Icon(entry.isDirectory ? Icons.folder : Icons.insert_drive_file),
                              ]),
                              title: Text(entry.name),
                              subtitle: Text(entry.permission ?? ''),
                              trailing: Text(entry.size != null ? _formatSize(entry.size!) : ''),
                              onTap: () => entry.isDirectory ? cubit.enterDirectory(entry) : null,
                              onLongPress: () => _showContextMenu(context, entry, cubit),
                            ),
                          );
                        },
                      ),
                    ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
              child: Row(
                children: [
                  if (state.uploadProgress > 0 && state.uploadProgress < 1)
                    Expanded(child: LinearProgressIndicator(value: state.uploadProgress)),
                  if (state.downloadProgress > 0 && state.downloadProgress < 1)
                    Expanded(child: LinearProgressIndicator(value: state.downloadProgress)),
                  if (state.status == FileManagerStatus.failure)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text('错误: ${state.errorMessage ?? ""}', style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  String _formatSize(int size) {
    if (size >= 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    return '$size B';
  }

  void _showContextMenu(BuildContext context, FileEntry entry, FileManagerCubit cubit) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final dir = await FilePicker.platform.getDirectoryPath();
                if (dir != null) {
                  final local = p.join(dir, entry.name);
                  cubit.downloadFile(entry, local);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('删除'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('确认删除'),
                    content: Text('确定删除 ${entry.name} 吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) cubit.deleteFile(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () async {
                Navigator.of(ctx).pop();
                _renameController.text = entry.name;
                final newName = await showDialog<String?>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('重命名'),
                    content: TextField(controller: _renameController),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx, null), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(dctx, _renameController.text.trim()), child: const Text('确定')),
                    ],
                  ),
                );
                if (newName != null && newName.isNotEmpty) cubit.rename(entry, newName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('属性'),
              onTap: () {
                Navigator.of(ctx).pop();
                showDialog<void>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('属性'),
                    content: Text('路径: ${entry.path}\n类型: ${entry.isDirectory ? '目录' : '文件'}\n大小: ${entry.size ?? '-'}'),
                    actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('关闭'))],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
