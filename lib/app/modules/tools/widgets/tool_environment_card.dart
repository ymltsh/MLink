import 'package:flutter/material.dart';

import '../services/tool_environment.dart';

class ToolEnvironmentCard extends StatelessWidget {
  final ToolEnvironment? environment;
  final VoidCallback? onReady;
  const ToolEnvironmentCard({super.key, this.environment, this.onReady});

  Future<void> _configure(BuildContext context, ToolEnvironment tools) async {
    var value = tools.proxyBase;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('运行环境下载源'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: TextFormField(
              initialValue: value,
              decoration: const InputDecoration(
                labelText: 'GitHub 加速源',
                hintText: 'https://hub.wgen.top/',
                helperText: '留空使用 GitHub 直连',
              ),
              onChanged: (text) => value = text,
              validator: (text) {
                try {
                  ToolEnvironment.normalizeProxy(text ?? '');
                  return null;
                } catch (_) {
                  return '请输入有效的 HTTPS 地址';
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      try {
        await tools.setProxy(result);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tools = environment ?? ToolEnvironment.instance;
    return AnimatedBuilder(
      animation: tools,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ADB / scrcpy 运行环境',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('首次运行自动补齐官方最新环境，完成后可离线使用。'),
              const Text('版本和校验信息直连 GitHub，下载源只加速运行包。'),
              const SizedBox(height: 12),
              Text(tools.message),
              if (tools.busy) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: tools.progress),
                if (tools.progress != null)
                  Text('${(tools.progress! * 100).toStringAsFixed(0)}%'),
              ],
              if (tools.directory != null) ...[
                const SizedBox(height: 8),
                SelectableText('安装位置：${tools.directory}'),
              ],
              const SizedBox(height: 8),
              Text(
                  '下载源：${tools.proxyBase.isEmpty ? 'GitHub 直连' : tools.proxyBase}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: tools.busy
                        ? null
                        : () async {
                            if (await tools.ensure(
                                force: tools.directory != null)) {
                              onReady?.call();
                            }
                          },
                    icon: const Icon(Icons.download),
                    label: Text(tools.phase == ToolPhase.failed
                        ? '重试补全'
                        : tools.directory != null
                            ? '更新到最新版本'
                            : '补全运行环境'),
                  ),
                  TextButton(
                    onPressed:
                        tools.busy ? null : () => _configure(context, tools),
                    child: const Text('配置下载源'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 完成环境准备后再创建业务页面，避免首次启动 ADB 调用抢先执行。
class ToolBootstrap extends StatefulWidget {
  final Widget child;
  final ToolEnvironment? environment;
  const ToolBootstrap({super.key, required this.child, this.environment});

  @override
  State<ToolBootstrap> createState() => _ToolBootstrapState();
}

class _ToolBootstrapState extends State<ToolBootstrap> {
  bool _ready = false;
  ToolEnvironment get _tools => widget.environment ?? ToolEnvironment.instance;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final ready = await _tools.ensure();
    if (mounted && ready) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return Scaffold(
      appBar: AppBar(title: const Text('欢迎使用妙联')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToolEnvironmentCard(
                    environment: _tools,
                    onReady: () {
                      if (mounted) setState(() => _ready = true);
                    }),
                AnimatedBuilder(
                  animation: _tools,
                  builder: (context, _) => TextButton(
                    onPressed: _tools.busy
                        ? null
                        : () => setState(() => _ready = true),
                    child: const Text('稍后配置，继续进入'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
