import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceConnectionPage extends StatefulWidget {
  final List<String> deviceList;
  final String? selectedDevice;
  final List<String> foundAdbDevices;
  final String? selectedFoundDevice;
  final TextEditingController ipController;
  final TextEditingController portController;
  final Function(String?) onDeviceSelected;
  final Function(String?) onFoundDeviceSelected;
  final VoidCallback onRefreshDevices;
  final Function(List<String>) onRunCommand;
  final VoidCallback onScanDevices;
  final Map<String, String> deviceInfo;

  const DeviceConnectionPage({
    super.key,
    required this.deviceList,
    required this.selectedDevice,
    required this.foundAdbDevices,
    required this.selectedFoundDevice,
    required this.ipController,
    required this.portController,
    required this.onDeviceSelected,
    required this.onFoundDeviceSelected,
    required this.onRefreshDevices,
    required this.onRunCommand,
    required this.onScanDevices,
    required this.deviceInfo,
  });

  @override
  State<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends State<DeviceConnectionPage> {
  List<String> _historyDevices = [];
  bool _historyExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadHistoryDevices();
  }

  // 加载历史设备列表
  Future<void> _loadHistoryDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('historyDevices') ?? [];
    setState(() {
      _historyDevices = history;
    });
  }

  // 保存历史设备列表
  Future<void> _saveHistoryDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('historyDevices', _historyDevices);
  }

  // 添加设备到历史列表
  void _addToHistory(String deviceIp) {
    if (deviceIp.isEmpty) return;
    
    setState(() {
      // 移除已存在的相同设备
      _historyDevices.remove(deviceIp);
      // 添加到列表开头
      _historyDevices.insert(0, deviceIp);
      // 限制历史记录数量为10个
      if (_historyDevices.length > 10) {
        _historyDevices = _historyDevices.sublist(0, 10);
      }
    });
    _saveHistoryDevices();
  }

  // 从历史列表中删除设备
  void _removeFromHistory(String deviceIp) {
    setState(() {
      _historyDevices.remove(deviceIp);
    });
    _saveHistoryDevices();
  }

  // 清空历史列表
  void _clearHistory() {
    setState(() {
      _historyDevices.clear();
    });
    _saveHistoryDevices();
  }

  // 快速连接历史设备
  void _connectHistoryDevice(String deviceIp) {
    final parts = deviceIp.split(':');
    if (parts.isNotEmpty) {
      widget.ipController.text = parts[0];
      if (parts.length > 1) {
        widget.portController.text = parts[1];
      } else {
        widget.portController.text = '5555';
      }
      
      // 自动连接
      widget.onRunCommand(['adb', 'connect', deviceIp]);
    }
  }

  // 构建历史设备列表UI
  Widget _buildHistoryDevices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('历史连接设备', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: Icon(_historyExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() {
                  _historyExpanded = !_historyExpanded;
                });
              },
            ),
          ],
        ),
        if (_historyExpanded) ...[
          const SizedBox(height: 8),
          if (_historyDevices.isEmpty)
            const Text('暂无历史连接设备', style: TextStyle(color: Colors.grey))
          else
            Column(
              children: _historyDevices.map((device) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.history, color: Colors.blue),
                  title: Text(device),
                  subtitle: const Text('点击快速连接'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeFromHistory(device),
                    tooltip: '删除',
                  ),
                  onTap: () => _connectHistoryDevice(device),
                ),
              )).toList(),
            ),
          if (_historyDevices.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    // 添加当前输入的设备到历史
                    final ip = widget.ipController.text.trim();
                    final port = widget.portController.text.trim();
                    if (ip.isNotEmpty) {
                      final device = port.isNotEmpty ? '$ip:$port' : '$ip:5555';
                      _addToHistory(device);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加到历史设备: $device')),
                      );
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('添加到历史'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('清空历史'),
                ),
              ],
            ),
          ],
        ],
        const Divider(),
      ],
    );
  }

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
        _buildHistoryDevices(),
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
              onPressed: widget.onRefreshDevices,
              child: const Text('刷新设备列表'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: widget.deviceList.isEmpty
                  ? const Text('无设备')
                  : Wrap(
                      spacing: 8,
                      children: widget.deviceList.map((d) => ChoiceChip(
                        label: Text(d),
                        selected: widget.selectedDevice == d,
                        onSelected: (selected) {
                          widget.onDeviceSelected(selected ? d : null);
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
          onPressed: () => widget.onRunCommand(['adb', 'usb']),
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
                controller: widget.ipController,
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
                controller: widget.portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '5555',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                final ip = widget.ipController.text.trim();
                final port = widget.portController.text.trim();
                if (ip.isNotEmpty) {
                  final device = port.isNotEmpty ? '$ip:$port' : '$ip:5555';
                  // 添加到历史记录
                  _addToHistory(device);
                  // 执行连接
                  widget.onRunCommand(['adb', 'connect', device]);
                }
              },
              child: const Text('连接'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: widget.onScanDevices,
              child: const Text('扫描局域网设备'),
            ),
            const SizedBox(width: 16),
            if (widget.foundAdbDevices.isNotEmpty) ...[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: widget.foundAdbDevices.map((ip) => ChoiceChip(
                    label: Text(ip),
                    selected: widget.selectedFoundDevice == ip,
                    onSelected: (selected) {
                      widget.onFoundDeviceSelected(selected ? ip : null);
                    },
                  )).toList(),
                ),
              ),
            ],
          ],
        ),
        if (widget.selectedDevice != null) ...[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => widget.onRunCommand(['adb', 'disconnect']),
            child: const Text('断开连接'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => widget.onRunCommand(['adb', 'tcpip', '5555']),
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
                    value: widget.deviceInfo['model'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.android,
                    label: 'Android版本',
                    value: widget.deviceInfo['android_version'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.desktop_windows,
                    label: '屏幕分辨率',
                    value: widget.deviceInfo['screen_size'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.memory,
                    label: '运行内存',
                    value: widget.deviceInfo['memory'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.storage,
                    label: '存储信息',
                    value: widget.deviceInfo['storage'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.developer_board,
                    label: 'CPU架构',
                    value: widget.deviceInfo['cpu_abi'] ?? '未知',
                  ),
                  _buildInfoRow(
                    icon: Icons.battery_full,
                    label: '电池电量',
                    value: widget.deviceInfo['battery'] ?? '未知',
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