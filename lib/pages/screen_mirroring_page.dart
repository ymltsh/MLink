import 'package:flutter/material.dart';
import 'dart:io';

class ScreenMirroringPage extends StatefulWidget {
  final TextEditingController bitrateController;
  final TextEditingController sizeController;
  final TextEditingController appPackageController;
  final TextEditingController appDisplaySizeController;
  final TextEditingController appDisplayDpiController;
  final Function(List<String>) onRunCommand;
  final VoidCallback onQueryPackages;
  final TextEditingController searchController; // 添加搜索关键字控制器
  final List<String> packageQueryResult; // 新增
  final bool enableH265;
  final bool enablePhysicalKeyboard;
  final bool turnScreenOff;
  final bool disableAudio;    // 添加禁用音频属性
  final bool enableRecording; // 添加开启录制属性

  const ScreenMirroringPage({
    super.key,
    required this.bitrateController,
    required this.sizeController,
    required this.appPackageController,
    required this.appDisplaySizeController,
    required this.appDisplayDpiController,
    required this.onRunCommand,
    required this.onQueryPackages,
    required this.searchController, // 添加到构造函数
    required this.packageQueryResult, // 新增
    required this.enableH265,
    required this.enablePhysicalKeyboard,
    required this.turnScreenOff,
    required this.disableAudio,    // 添加到构造函数
    required this.enableRecording, // 添加到构造函数
  });

  @override
  ScreenMirroringPageState createState() => ScreenMirroringPageState();
}

class ScreenMirroringPageState extends State<ScreenMirroringPage> {
  void onQueryPackages() {
    if (widget.searchController.text.isEmpty) return;

    final command = 'adb shell pm list packages | findstr ${widget.searchController.text}';
    // 执行命令并更新 packageQueryResult
    Process.run('cmd', ['/c', command]).then((result) {
      if (result.stdout != null) {
        final packages = (result.stdout as String)
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        // 更新状态
        setState(() {
          widget.packageQueryResult.clear(); // 清空原有数据
          widget.packageQueryResult.addAll(packages); // 添加新查询结果
        });
      }
    });
  }
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

  Widget _buildBasicMirroring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基础投屏', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () {
                final args = ['scrcpy'];
                if (widget.turnScreenOff) {
                  args.add('--turn-screen-off');
                }
                if (widget.enableH265) {
                  args.add('--video-codec=h265');
                }
                if (widget.enablePhysicalKeyboard) {
                  args.add('--keyboard=uhid');
                }
                // 添加音频和录制参数
                if (widget.disableAudio) {
                  args.add('--no-audio');
                }
                if (widget.enableRecording) {
                  args.add('--record=scrcpy_${DateTime.now().millisecondsSinceEpoch}.mp4');
                }
                widget.onRunCommand(args);
              },
              child: const Text('开始投屏'),
            ),
            ElevatedButton(
              onPressed: () {
                final args = ['scrcpy', '--no-video'];
                widget.onRunCommand(args);
              },
              child: const Text('仅音频投送（安卓11+）'),
            ),
            ElevatedButton(
              onPressed: () {
                final args = ['scrcpy', '--video-source=camera'];
                widget.onRunCommand(args);
              },
              child: const Text('仅投送摄像头（安卓12+）'),
            ),
          ],
        ),
      ],
    );
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
                  hintText: '例如：8',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.sizeController,
                decoration: const InputDecoration(
                  labelText: '分辨率最大值',
                  hintText: '例如：1080',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            final args = [
              'scrcpy',
              '-b',
              '${widget.bitrateController.text}m',
              '-m',
              widget.sizeController.text,
            ];
            if (widget.turnScreenOff) {
              args.add('--turn-screen-off');
            }
            if (widget.enableH265) {
              args.add('--video-codec=h265');
            }
            if (widget.enablePhysicalKeyboard) {
              args.add('--keyboard=uhid');
            }
            // 添加音频和录制参数
            if (widget.disableAudio) {
              args.add('--no-audio');
            }
            if (widget.enableRecording) {
              args.add('--record=scrcpy_${DateTime.now().millisecondsSinceEpoch}.mp4');
            }
            widget.onRunCommand(args);
          },
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(cleanPkg, style: const TextStyle(fontSize: 13)),
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
                      hintText: '例如：420',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                final pkg = widget.appPackageController.text.trim();
                if (pkg.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请先查询并选择应用包名')),
                  );
                  return;
                }

                final List<String> command = ['scrcpy', '--start-app=$pkg'];
                
                // 添加显示参数
                if (widget.appDisplaySizeController.text.isNotEmpty && 
                    widget.appDisplayDpiController.text.isNotEmpty) {
                  final display = '${widget.appDisplaySizeController.text}/${widget.appDisplayDpiController.text}';
                  command.addAll(['--new-display=$display']);
                }
                
                // 添加通用设置参数
                if (widget.turnScreenOff) {
                  command.add('--turn-screen-off');
                }
                if (widget.enableH265) {
                  command.add('--video-codec=h265');
                }
                if (widget.enablePhysicalKeyboard) {
                  command.add('--keyboard=uhid');
                }
                // 添加音频和录制参数
                if (widget.disableAudio) {
                  command.add('--no-audio');
                }
                if (widget.enableRecording) {
                  command.add('--record=scrcpy_${DateTime.now().millisecondsSinceEpoch}.mp4');
                }
                
                command.add('--no-vd-system-decorations');
                widget.onRunCommand(command);
              },
              child: const Text('启动单App投屏'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '提示：单App投屏功能需要 scrcpy 1.25 及以上版本',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}