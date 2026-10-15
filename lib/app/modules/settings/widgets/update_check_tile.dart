import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../services/update_service.dart';

class UpdateCheckTile extends StatefulWidget {
  final Future<UpdateRelease> Function()? check;
  const UpdateCheckTile({super.key, this.check});

  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开浏览器');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: SelectableText('无法打开浏览器，请复制链接：$uri')),
        );
      }
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final release = await (widget.check ?? UpdateService().check)();
      if (!mounted) return;
      if (!release.isNewerThan(AppConfig.appVersion, AppConfig.appBuild)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
        return;
      }
      final downloads = <String, Uri>{};
      if (Platform.isWindows) {
        if (release.urls['windows'] != null) {
          downloads['下载安装程序'] = release.urls['windows']!;
        }
        if (release.urls['windows_portable'] != null) {
          downloads['下载便携版'] = release.urls['windows_portable']!;
        }
      } else if (Platform.isAndroid && release.urls['android'] != null) {
        downloads['下载 APK'] = release.urls['android']!;
      }
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(release.name),
          content: SingleChildScrollView(
            child: SelectableText(
                '版本 ${release.version}+${release.build}\n\n${release.notes}'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
            TextButton(
                onPressed: () => _open(release.page), child: const Text('发布页')),
            for (final entry in downloads.entries)
              TextButton(
                  onPressed: () => _open(entry.value), child: Text(entry.key)),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查更新失败，请检查网络后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('检查更新'),
        subtitle: Text(_failed
            ? '检查失败，点击重试'
            : '当前版本 ${AppConfig.appVersion}+${AppConfig.appBuild}'),
        trailing: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.system_update_alt),
        onTap: _busy ? null : _check,
      );
}
