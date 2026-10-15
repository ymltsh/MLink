import 'dart:async';
import 'dart:io';
import '../../tools/services/tool_cancellation.dart';

class Ipv4Range {
  final int first;
  final int last;
  Ipv4Range._(this.first, this.last);
  static int _number(String address) {
    final parts = address.trim().split('.');
    if (parts.length != 4) throw const FormatException('请输入有效的 IPv4 地址');
    var number = 0;
    for (final part in parts) {
      final value = int.tryParse(part);
      if (!RegExp(r'^\d{1,3}$').hasMatch(part) ||
          value == null ||
          value > 255) {
        throw const FormatException('请输入有效的 IPv4 地址');
      }
      number = (number << 8) | value;
    }
    return number;
  }

  factory Ipv4Range.parse(String text) {
    final parts = text.split('-');
    if (parts.length > 2) throw const FormatException('扫描范围格式应为 起始IP-结束IP');
    final first = _number(parts.first);
    final last = _number(parts.last);
    if (first > last || last - first >= 4096) {
      throw const FormatException('扫描范围应按顺序填写，最多 4096 个地址');
    }
    return Ipv4Range._(first, last);
  }
  Iterable<String> get addresses sync* {
    for (var value = first; value <= last; value++) {
      yield [24, 16, 8, 0].map((shift) => (value >> shift) & 255).join('.');
    }
  }
}

class NetworkScanner {
  final int concurrency;
  final Future<bool> Function(String, int, ToolCancellation) _probe;
  NetworkScanner({
    this.concurrency = 20,
    Future<bool> Function(String, int, ToolCancellation)? probe,
  }) : _probe = probe ?? _connect {
    if (concurrency < 1) throw ArgumentError('并发数必须大于 0');
  }
  static Future<bool> _connect(
    String host,
    int port,
    ToolCancellation cancellation,
  ) async {
    ConnectionTask<Socket>? pending;
    Socket? socket;
    void cancel() {
      pending?.cancel();
      socket?.destroy();
    }

    cancellation.add(cancel);
    try {
      cancellation.check();
      pending = await Socket.startConnect(host, port);
      if (cancellation.isCancelled) {
        pending.cancel();
        return false;
      }
      socket = await pending.socket.timeout(const Duration(milliseconds: 300));
      return !cancellation.isCancelled;
    } catch (_) {
      return false;
    } finally {
      cancel();
      cancellation.remove(cancel);
    }
  }

  Future<List<String>> scan(
    Ipv4Range range,
    int port,
    ToolCancellation cancellation, {
    void Function(String)? onFound,
  }) async {
    if (port < 1 || port > 65535) throw const FormatException('端口范围为 1–65535');
    final iterator = range.addresses.iterator;
    final found = <String>[];
    Future<void> worker() async {
      while (!cancellation.isCancelled && iterator.moveNext()) {
        final host = iterator.current;
        final open = await _probe(host, port, cancellation);
        if (cancellation.isCancelled) return;
        if (open) {
          final endpoint = '$host:$port';
          found.add(endpoint);
          onFound?.call(endpoint);
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return found;
  }
}
