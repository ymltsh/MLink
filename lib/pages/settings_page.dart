import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../utils/settings_manager.dart'; // 添加这一行
import 'package:adb_tool/app/modules/settings/bloc/theme_cubit.dart';

class SettingsPage extends StatelessWidget {
  final TextEditingController defaultBitrateController;
  final TextEditingController defaultResolutionController;
  final TextEditingController defaultDpiController;
  final Future<bool> Function(List<String>) onRunCommand;
  final bool keepScreenOn;
  final bool showTouches;
  final bool autoScanAndConnect;
  final bool turnScreenOff;  // 添加新属性
  final bool enableH265;
  final bool enablePhysicalKeyboard;
  final bool disableAudio;
  final bool enableRecording;
  final bool autoCleanAdbProcess;
  final ValueChanged<bool> onKeepScreenOnChanged;
  final ValueChanged<bool> onShowTouchesChanged;
  final ValueChanged<bool> onAutoScanAndConnectChanged;
  final ValueChanged<bool> onTurnScreenOffChanged;  // 添加新属性
  final ValueChanged<bool> onEnableH265Changed;
  final ValueChanged<bool> onEnablePhysicalKeyboardChanged;
  final ValueChanged<bool> onDisableAudioChanged;
  final ValueChanged<bool> onEnableRecordingChanged;
  final ValueChanged<bool> onAutoCleanAdbProcessChanged;
  final VoidCallback onManualCleanAdbProcess;

  const SettingsPage({
    super.key,
    required this.defaultBitrateController,
    required this.defaultResolutionController,
    required this.defaultDpiController,
    required this.onRunCommand,
    required this.keepScreenOn,
    required this.showTouches,
    required this.autoScanAndConnect,
    required this.onKeepScreenOnChanged,
    required this.onShowTouchesChanged,
    required this.onAutoScanAndConnectChanged,
    required this.turnScreenOff,  // 添加新参数
    required this.onTurnScreenOffChanged,  // 添加新参数
    required this.enableH265,
    required this.enablePhysicalKeyboard,
    required this.onEnableH265Changed,
    required this.onEnablePhysicalKeyboardChanged,
    required this.disableAudio,
    required this.enableRecording,
    required this.onDisableAudioChanged,
    required this.onEnableRecordingChanged,
    required this.autoCleanAdbProcess,
    required this.onAutoCleanAdbProcessChanged,
    required this.onManualCleanAdbProcess,
  });

  Widget _buildPersonalizationSection(BuildContext context) {
    final List<Color> presetColors = [
      const Color(0xFF0ABAB5), // 蒂芙尼蓝
      Colors.blue,
      Colors.purple,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.pink,
      Colors.teal,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('个性化', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 实时预览当前 seed color
                Row(
                  children: [
                    const Text('当前主题色：'),
                    const SizedBox(width: 8),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: state.seedColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('#${state.seedColor.value.toRadixString(16).toUpperCase()}'),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('外观模式'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: <ButtonSegment<ThemeMode>>[
                    ButtonSegment(value: ThemeMode.system, label: const Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: const Icon(Icons.wb_sunny)),
                    ButtonSegment(value: ThemeMode.dark, label: const Icon(Icons.dark_mode)),
                  ],
                  selected: <ThemeMode>{state.themeMode},
                  onSelectionChanged: (newSelection) {
                    final mode = newSelection.first;
                    context.read<ThemeCubit>().setThemeMode(mode);
                  },
                ),
                const SizedBox(height: 12),
                const Text('主题强调色'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presetColors.map((color) {
                    final selected = color.value == state.seedColor.value;
                    return InkWell(
                      onTap: () => context.read<ThemeCubit>().setSeedColor(color),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        // 弹出对话框输入自定义 Hex 颜色
                        String? result = await showDialog<String>(
                          context: context,
                          builder: (context) {
                            String hex = '';
                            Color preview = Colors.transparent;
                            return StatefulBuilder(builder: (context, setState) {
                              return AlertDialog(
                                title: const Text('输入自定义颜色 (Hex)'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      decoration: const InputDecoration(
                                        prefixText: '#',
                                        hintText: 'e.g. 0ABAB5 或 FF0ABAB5',
                                      ),
                                      onChanged: (v) {
                                        hex = v.trim();
                                        final cleaned = v.replaceAll('#', '').replaceAll('0x', '');
                                        if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) {
                                          preview = Color(int.parse('0xFF' + cleaned));
                                        } else if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(cleaned)) {
                                          preview = Color(int.parse('0x' + cleaned));
                                        } else {
                                          preview = Colors.transparent;
                                        }
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Text('预览：'),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: preview,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.grey.shade300),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop(hex);
                                    },
                                    child: const Text('确定'),
                                  ),
                                ],
                              );
                            });
                          },
                        );

                        if (!context.mounted) return;
                        if (result != null && result.trim().isNotEmpty) {
                          final cleaned = result.replaceAll('#', '').replaceAll('0x', '');
                          try {
                            Color newColor;
                            if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) {
                              newColor = Color(int.parse('0xFF' + cleaned));
                            } else if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(cleaned)) {
                              newColor = Color(int.parse('0x' + cleaned));
                            } else {
                              throw FormatException('Invalid hex');
                            }
                            await context.read<ThemeCubit>().setSeedColor(newColor);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('主题颜色已应用: #${cleaned.toUpperCase()}')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无效的十六进制颜色')));
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('自定义颜色'),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('输入 6 或 8 位十六进制颜色代码，例如 0ABAB5 或 FF0ABAB5'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDefaultSettings(),
        const SizedBox(height: 16),
        _buildPersonalizationSection(context),
        const Divider(),
        _buildDeviceSettings(),
        const Divider(),
        _buildAboutSection(),
      ],
    );
  }

  Widget _buildDefaultSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('默认设置', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: defaultBitrateController,
                decoration: const InputDecoration(
                  labelText: '默认码率（M）',
                  hintText: '例如：8',
                ),
                onChanged: (value) {
                  SettingsManager.saveSettings(defaultBitrate: value);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: defaultResolutionController,
                decoration: const InputDecoration(
                  labelText: '默认分辨率',
                  hintText: '例如：1080',
                ),
                onChanged: (value) {
                  SettingsManager.saveSettings(defaultResolution: value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: defaultDpiController,
          decoration: const InputDecoration(
            labelText: '默认DPI',
            hintText: '例如：420',
          ),
          onChanged: (value) {
            SettingsManager.saveSettings(defaultDpi: value);
          },
        ),
      ],
    );
  }

  Widget _buildDeviceSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('设备设置', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // 熄屏投送
        SwitchListTile(
          title: const Text('熄屏投送'),
          subtitle: const Text('投屏时自动关闭设备屏幕'),
          value: turnScreenOff,
          onChanged: (value) {
            onTurnScreenOffChanged(value);
            SettingsManager.saveSettings(turnScreenOff: value);
          },
        ),
        // 保持屏幕常亮
        SwitchListTile(
          title: const Text('保持屏幕常亮'),
          subtitle: const Text('防止设备自动锁屏'),
          value: keepScreenOn,
          onChanged: (value) async {
            try {
              final success = await onRunCommand([
                'adb', 'shell', 'settings', 'put', 'system',
                'screen_off_timeout',
                value ? '2147483647' : '60000'
              ]);
              if (success) {
                onKeepScreenOnChanged(value);
                await SettingsManager.saveSettings(keepScreenOn: value);
              }
            } catch (e) {
              debugPrint('屏幕常亮设置失败: $e');
            }
          },
        ),
        // 添加自动扫描连接开关
        SwitchListTile(
          title: const Text('启动时自动扫描连接'),
          subtitle: const Text('应用启动时自动扫描并连接设备'),
          value: autoScanAndConnect,
          onChanged: (value) {
            onAutoScanAndConnectChanged(value);
            SettingsManager.saveSettings(autoScanAndConnect: value);
          },
        ),
        // 显示触摸点
        SwitchListTile(
          title: const Text('显示触摸点'),
          subtitle: const Text('在屏幕上显示触摸位置'),
          value: showTouches,
          onChanged: (value) async {
            try {
              final success = await onRunCommand([
                'adb', 'shell', 'settings', 'put', 'system',
                'show_touches',
                value ? '1' : '0'
              ]);
              if (success) {
                onShowTouchesChanged(value);
                await SettingsManager.saveSettings(showTouches: value);
              }
            } catch (e) {
              debugPrint('显示触摸点设置失败: $e');
            }
          },
        ),
        SwitchListTile(
          title: const Text('启用H.265编码'),
          subtitle: const Text('使用H.265视频编码可能提供更好的画质和性能'),
          value: enableH265,
          onChanged: (value) {
            onEnableH265Changed(value);
            SettingsManager.saveSettings(enableH265: value);
          },
        ),
        SwitchListTile(
          title: const Text('透射物理键盘'),
          subtitle: const Text('使用UHID模式转发物理键盘输入'),
          value: enablePhysicalKeyboard,
          onChanged: (value) {
            onEnablePhysicalKeyboardChanged(value);
            SettingsManager.saveSettings(enablePhysicalKeyboard: value);
            // 添加 ADB 命令来控制物理键盘透射
            onRunCommand([
              'adb', 'shell', 'settings', 'put', 'secure',
              'enable_physical_keyboard',
              value ? '1' : '0'
            ]);
          },
        ),
        SwitchListTile(
          title: const Text('禁用音频投送'),
          subtitle: const Text('不传输设备音频'),
          value: disableAudio,
          onChanged: (value) {
            onDisableAudioChanged(value);
            SettingsManager.saveSettings(disableAudio: value);
          },
        ),
        SwitchListTile(
          title: const Text('开启屏幕录制'),
          subtitle: const Text('将投屏内容保存为视频文件'),
          value: enableRecording,
          onChanged: (value) {
            onEnableRecordingChanged(value);
            SettingsManager.saveSettings(enableRecording: value);
          },
        ),
        // ADB进程清理设置
        SwitchListTile(
          title: const Text('自动清理ADB进程'),
          subtitle: const Text('每次启动时自动清理残留的ADB进程'),
          value: autoCleanAdbProcess,
          onChanged: (value) {
            onAutoCleanAdbProcessChanged(value);
            SettingsManager.saveSettings(autoCleanAdbProcess: value);
          },
        ),
        // 手动清理ADB进程按钮
        ListTile(
          title: const Text('立即清理ADB进程'),
          subtitle: const Text('强制清理所有残留的ADB进程'),
          trailing: ElevatedButton.icon(
            onPressed: onManualCleanAdbProcess,
            icon: const Icon(Icons.cleaning_services),
            label: const Text('清理'),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('妙联 | 连接世界', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '“我们在乘着这温暖的上升气流离开这里。这是我们动身的时刻。我们是飞天蜘蛛，我们正在到世界上去结我们的网。”——《夏洛的网》',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('版本：', style: TextStyle(color: Colors.grey[600])),
                    const Text('1.0.5'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('开源协议：', style: TextStyle(color: Colors.grey[600])),
                    const Text('Apache License 2.0'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}