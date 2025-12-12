import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PackageQueryWidget extends StatelessWidget {
  final TextEditingController packageController;
  final VoidCallback onQueryPackages;
  final List<String> packageQueryResult;
  final bool showCopyButton;
  final bool useChips;
  final void Function(String)? onPackageSelected;
  final List<Widget> Function(String)? trailingButtons;

  const PackageQueryWidget({
    super.key,
    required this.packageController,
    required this.onQueryPackages,
    required this.packageQueryResult,
    this.showCopyButton = false,
    this.useChips = false,
    this.onPackageSelected,
    this.trailingButtons,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: packageController,
                decoration: const InputDecoration(
                  labelText: '应用包名',
                  hintText: '例如：com.tencent.mm',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => onQueryPackages(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onQueryPackages,
              child: const Text('查询包名'),
            ),
          ],
        ),
        if (packageQueryResult.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (useChips)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: packageQueryResult.map((pkg) {
                // 确保包名被正确清理：去除所有空白字符和换行符
                final pkgName = pkg.trim();
                return Chip(
                  label: Text(pkgName, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => onPackageSelected?.call(pkgName),
                );
              }).toList(),
            )
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: packageQueryResult.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final pkg = packageQueryResult[index];
                  // 确保包名被正确清理：去除所有空白字符和换行符
                  final pkgName = pkg.trim();
                  return ListTile(
                    dense: true,
                    title: Text(pkgName, style: const TextStyle(fontSize: 14)),
                    onTap: () => onPackageSelected?.call(pkgName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showCopyButton)
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: '复制包名',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: pkgName));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('包名已复制到剪贴板'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        if (trailingButtons != null) ...trailingButtons!(pkgName),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}