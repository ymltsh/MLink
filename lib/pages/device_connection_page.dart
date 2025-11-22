import 'package:flutter/material.dart';

class DeviceConnectionPage extends StatelessWidget {
  final List<String> deviceList;
  final String? selectedDevice;
  final List<String> foundAdbDevices;
  final String? selectedFoundDevice;
  final TextEditingController ipController;
  final TextEditingController portController;  // 新增端口控制器
  final Function(String?) onDeviceSelected;
  final Function(String?) onFoundDeviceSelected;
  final VoidCallback onRefreshDevices;
  final Function(List<String>) onRunCommand;
  final VoidCallback onScanDevices;
  final Map<String, String> deviceInfo;  // 添加这一行

  const DeviceConnectionPage({
    super.key,
    required this.deviceList,
    required this.selectedDevice,
    required this.foundAdbDevices,
    required this.selectedFoundDevice,
    required this.ipController,
    required this.portController,  // 新增端口参数
    required this.onDeviceSelected,
    required this.onFoundDeviceSelected,
    required this.onRefreshDevices,
    required this.onRunCommand,
    required this.onScanDevices,
    required this.deviceInfo,  // 添加这一行
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDeviceList(),
        const Divider(),
        _buildWiredConnection(),
        const Divider(),
        _buildWirelessConnection(),
      ],
    );
  }

  Widget _buildDeviceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('已连接设备列表', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: onRefreshDevices,
              child: const Text('刷新设备列表'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: deviceList.isEmpty
                  ? const Text('无设备')
                  : Wrap(
                      spacing: 8,
                      children: deviceList.map((d) => ChoiceChip(
                        label: Text(d),
                        selected: selectedDevice == d,
                        onSelected: (selected) {
                          onDeviceSelected(selected ? d : null);
                        },
                      )).toList(),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWiredConnection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('有线连接', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => onRunCommand(['adb', 'usb']),
          child: const Text('切换为USB连接模式'),
        ),
      ],
    );
  }

  Widget _buildWirelessConnection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('无线连接', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: '设备IP地址',
                  hintText: '例如：192.168.1.100',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '5555',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => onRunCommand(['adb', 'connect', '${ipController.text}:${portController.text}']),
              child: const Text('连接'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: onScanDevices,
              child: const Text('扫描局域网设备'),
            ),
            const SizedBox(width: 16),
            if (foundAdbDevices.isNotEmpty) ...[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: foundAdbDevices.map((ip) => ChoiceChip(
                    label: Text(ip),
                    selected: selectedFoundDevice == ip,
                    onSelected: (selected) {
                      onFoundDeviceSelected(selected ? ip : null);
                    },
                  )).toList(),
                ),
              ),
            ],
          ],
        ),
        if (selectedDevice != null) ...[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => onRunCommand(['adb', 'disconnect']),
            child: const Text('断开连接'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => onRunCommand(['adb', 'tcpip', '5555']),
            child: const Text('切换为TCP/IP模式'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('设备信息', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    icon: Icons.phone_android,
                    label: '设备型号',
                    value: deviceInfo['model'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.android,
                    label: 'Android版本',
                    value: deviceInfo['android_version'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.desktop_windows,
                    label: '屏幕分辨率',
                    value: deviceInfo['screen_size'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.memory,
                    label: '运行内存',
                    value: deviceInfo['memory'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.storage,
                    label: '存储信息',
                    value: deviceInfo['storage'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.developer_board,
                    label: 'CPU架构',
                    value: deviceInfo['cpu_abi'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.battery_full,
                    label: '电池电量',
                    value: deviceInfo['battery'] ?? '未知',
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(height: 1.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}