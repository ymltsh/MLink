import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/package_query_widget.dart';

class AppManagementPage extends StatelessWidget {
  final TextEditingController apkController;
  final TextEditingController appKeywordController;
  final Function(List<String>) onRunCommand;
  final VoidCallback onQueryPackages;
  final List<String> packageQueryResult;

  const AppManagementPage({
    super.key,
    required this.apkController,
    required this.appKeywordController,
    required this.onRunCommand,
    required this.onQueryPackages,
    required this.packageQueryResult,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildApkInstaller(),
        const Divider(),
        _buildPackageQuery(),
        const Divider(),
        _buildCommandLine(), // 添加命令行部分
      ],
    );
  }

  Widget _buildApkInstaller() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('APK 安装', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: apkController,
                decoration: const InputDecoration(
                  labelText: 'APK文件路径',
                  hintText: '请选择要安装的APK文件',
                ),
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['apk'],
                );
                if (result != null && result.files.single.path != null) {
                  apkController.text = result.files.single.path!;
                }
              },
              icon: const Icon(Icons.file_upload),
              label: const Text('选择文件'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => onRunCommand(['adb', 'install', apkController.text]),
              child: const Text('普通安装'),
            ),
            ElevatedButton(
              onPressed: () => onRunCommand([
                'adb', 
                'install', 
                '--bypass-low-target-sdk-block', 
                apkController.text
              ]),
              child: const Text('低SDK安装'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPackageQuery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('包名查询|卸载', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        PackageQueryWidget(
          packageController: appKeywordController,
          onQueryPackages: onQueryPackages,
          packageQueryResult: packageQueryResult,
          showCopyButton: true,
          // 添加卸载功能按钮
          trailingButtons: (String package) => [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onRunCommand(['adb', 'uninstall', package]),
              tooltip: '卸载应用',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () => onRunCommand(['adb', 'uninstall', '-k', package]),
              tooltip: '卸载应用(保留数据)',
            ),
          ],
        ),
      ],
    );
  }

  // 添加命令行部分的实现
  Widget _buildCommandLine() {
    final commandController = TextEditingController();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ADB 命令行', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: commandController,
                decoration: const InputDecoration(
                  labelText: 'ADB 命令',
                  hintText: '输入要执行的 ADB 命令',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                if (commandController.text.isNotEmpty) {
                  final List<String> args = commandController.text.split(' ');
                  onRunCommand(args);
                  commandController.clear();
                }
              },
              child: const Text('执行'),
            ),
          ],
        ),
      ],
    );
  }
}