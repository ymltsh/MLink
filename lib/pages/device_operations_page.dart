import 'package:flutter/material.dart';

class DeviceOperationsPage extends StatelessWidget {
  final Function(List<String>) onRunCommand;

  const DeviceOperationsPage({
    super.key,
    required this.onRunCommand,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '设备操作',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          // 导航控制区
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '导航栏',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '82']),
                        icon: const Icon(Icons.menu),
                        label: const Text('菜单键'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '3']),
                        icon: const Icon(Icons.home),
                        label: const Text('Home键'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '4']),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回键'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 音量控制区
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '音量控制',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '24']),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('增加音量'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '25']),
                        icon: const Icon(Icons.volume_down),
                        label: const Text('降低音量'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '164']),
                        icon: const Icon(Icons.volume_off),
                        label: const Text('静音'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 电源控制区
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '电源控制',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => onRunCommand(['adb', 'shell', 'input', 'keyevent', '26']),
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('电源键'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8fb5be),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}