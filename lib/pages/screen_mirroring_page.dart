import 'package:flutter/material.dart';
import '../app/modules/screen_mirroring/models/mirror_config.dart';

class ScreenMirroringPage extends StatefulWidget {
  final MirrorConfig Function() config;
  final bool isMirrorActive;
  final VoidCallback onStop;
  final TextEditingController bitrateController;
  final TextEditingController sizeController;
  final TextEditingController appPackageController;
  final TextEditingController appDisplaySizeController;
  final TextEditingController appDisplayDpiController;
  final Function(List<String>) onRunCommand;
  final VoidCallback onQueryPackages;
  final TextEditingController searchController; // 添加搜索关键字控制器
  final List<String> packageQueryResult; // 新增

  const ScreenMirroringPage({
    super.key,
    required this.config,
    required this.isMirrorActive,
    required this.onStop,
    required this.bitrateController,
    required this.sizeController,
    required this.appPackageController,
    required this.appDisplaySizeController,
    required this.appDisplayDpiController,
    required this.onRunCommand,
    required this.onQueryPackages,
    required this.searchController, // 添加到构造函数
    required this.packageQueryResult, // 新增
  });

  @override
  ScreenMirroringPageState createState() => ScreenMirroringPageState();
}

class ScreenMirroringPageState extends State<ScreenMirroringPage> {
  void onQueryPackages() => widget.onQueryPackages();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBasicMirroring(),
        const Divider(),
        _buildQualitySettings(),
        const Divider(),
        _buildSingleAppMirroring(context),
      ],
    );
  }

  void _start(
      {bool audioOnly = false, bool camera = false, bool singleApp = false}) {
    try {
      final args = widget.config().command(
          bitrateOverride: widget.bitrateController.text,
          sizeOverride: widget.sizeController.text,
          audioOnly: audioOnly,
          camera: camera,
          package: singleApp ? widget.appPackageController.text.trim() : null,
          displaySize: widget.appDisplaySizeController.text,
          dpiOverride: widget.appDisplayDpiController.text);
      widget.onRunCommand(args);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Widget _buildBasicMirroring() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('基础投屏', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ElevatedButton(
            onPressed: widget.isMirrorActive ? null : () => _start(),
            child: const Text('开始投屏')),
        ElevatedButton(
            onPressed:
                widget.isMirrorActive ? null : () => _start(audioOnly: true),
            child: const Text('仅音频投送（安卓11+）')),
        ElevatedButton(
            onPressed:
                widget.isMirrorActive ? null : () => _start(camera: true),
            child: const Text('仅投送摄像头（安卓12+）')),
        if (widget.isMirrorActive)
          ElevatedButton(onPressed: widget.onStop, child: const Text('停止投屏')),
      ]),
    ]);
  }

  Widget _buildQualitySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('临时画质设置', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.bitrateController,
                decoration: const InputDecoration(
                  labelText: '码率（M）',
                  hintText: '留空使用默认码率',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.sizeController,
                decoration: const InputDecoration(
                  labelText: '分辨率最大值',
                  hintText: '留空使用默认分辨率',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: widget.isMirrorActive ? null : () => _start(),
          child: const Text('应用设置并投屏'),
        ),
      ],
    );
  }

  Widget _buildSingleAppMirroring(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('单App投屏', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // 第一步：包名查询部分
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('第一步：查询应用包名',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.searchController,
                    decoration: const InputDecoration(
                      labelText: '输入应用名称关键字',
                      hintText: '例如：chrome',
                    ),
                    onSubmitted: (_) => onQueryPackages(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onQueryPackages,
                  child: const Text('查询'),
                ),
              ],
            ),
            if (widget.packageQueryResult.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.packageQueryResult.map((pkg) {
                    final cleanPkg = pkg.replaceAll('package:', '').trim();
                    return ElevatedButton(
                      onPressed: () {
                        widget.appPackageController.text = cleanPkg;
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      child:
                          Text(cleanPkg, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // 第二步：输入包名投屏
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('第二步：输入包名进行投屏',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: widget.appPackageController,
              decoration: const InputDecoration(
                labelText: '应用包名',
                hintText: '从上方查询结果中选择或手动输入包名',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 第三步：开始投屏
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('第三步：开始投屏',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            // 添加显示参数设置
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.appDisplaySizeController,
                    decoration: const InputDecoration(
                      labelText: '分辨率',
                      hintText: '例如：1920x1080',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.appDisplayDpiController,
                    decoration: const InputDecoration(
                      labelText: 'DPI',
                      hintText: '留空使用默认 DPI',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed:
                  widget.isMirrorActive ? null : () => _start(singleApp: true),
              child: const Text('启动单App投屏'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '提示：单App投屏使用虚拟显示；DPI 留空时使用设置中的默认值',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
