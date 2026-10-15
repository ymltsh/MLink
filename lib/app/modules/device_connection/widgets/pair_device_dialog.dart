import 'dart:io';
import 'package:flutter/material.dart';

class PairDeviceDialog extends StatefulWidget {
  final String initialHost;
  const PairDeviceDialog({super.key, required this.initialHost});
  @override
  State<PairDeviceDialog> createState() => _PairDeviceDialogState();
}

class _PairDeviceDialogState extends State<PairDeviceDialog> {
  late final _host = TextEditingController(text: widget.initialHost);
  final _port = TextEditingController();
  final _code = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  void _pair() {
    final port = int.tryParse(_port.text);
    final address = InternetAddress.tryParse(_host.text.trim());
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = '请填写有效的 IPv4 地址、端口和六位配对码');
      return;
    }
    Navigator.pop(context, [
      'adb',
      'pair',
      '${_host.text.trim()}:$port',
      _code.text.trim(),
    ]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('无线调试配对'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _host,
          decoration: const InputDecoration(labelText: '设备 IPv4 地址'),
        ),
        TextField(
          controller: _port,
          decoration: const InputDecoration(labelText: '配对端口（不是连接端口）'),
        ),
        TextField(
          controller: _code,
          obscureText: true,
          decoration: const InputDecoration(labelText: '六位配对码'),
        ),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(onPressed: _pair, child: const Text('配对')),
    ],
  );
}
