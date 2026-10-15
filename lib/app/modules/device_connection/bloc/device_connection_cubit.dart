import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../tools/services/command_runner.dart';
import '../../tools/services/device_session.dart';
import '../../tools/services/tool_cancellation.dart';
import '../services/device_info_service.dart';
import '../services/network_scanner.dart';
import '../../../../utils/app_output.dart';

class DeviceConnectionState extends Equatable {
  static const _unchanged = Object();
  final List<String> devices;
  final String? serial;
  final Map<String, String> info;
  final List<String> packages;
  final List<String> endpoints;
  final String? selectedEndpoint;
  final bool scanning;
  const DeviceConnectionState({
    this.devices = const [],
    this.serial,
    this.info = const {},
    this.packages = const [],
    this.endpoints = const [],
    this.selectedEndpoint,
    this.scanning = false,
  });
  DeviceConnectionState copyWith({
    List<String>? devices,
    Object? serial = _unchanged,
    Map<String, String>? info,
    List<String>? packages,
    List<String>? endpoints,
    Object? selectedEndpoint = _unchanged,
    bool? scanning,
  }) => DeviceConnectionState(
    devices: devices ?? this.devices,
    serial: identical(serial, _unchanged) ? this.serial : serial as String?,
    info: info ?? this.info,
    packages: packages ?? this.packages,
    endpoints: endpoints ?? this.endpoints,
    selectedEndpoint: identical(selectedEndpoint, _unchanged)
        ? this.selectedEndpoint
        : selectedEndpoint as String?,
    scanning: scanning ?? this.scanning,
  );
  @override
  List<Object?> get props => [
    devices,
    serial,
    info,
    packages,
    endpoints,
    selectedEndpoint,
    scanning,
  ];
}

class DeviceConnectionCubit extends Cubit<DeviceConnectionState> {
  final CommandRunner commands;
  final DeviceInfoService _info;
  final NetworkScanner _scanner;
  final _lifetime = ToolCancellation();
  ToolCancellation _selection = ToolCancellation();
  ToolCancellation? _scan;
  bool _closing = false;
  int _refreshGeneration = 0;
  int _queryGeneration = 0;
  bool get _alive => !_closing && !isClosed;
  DeviceSession get session => DeviceSession(state.serial, commands: commands);
  DeviceConnectionCubit({
    this.commands = const CommandRunner(),
    DeviceInfoService info = const DeviceInfoService(),
    NetworkScanner? scanner,
  }) : _info = info,
       _scanner = scanner ?? NetworkScanner(),
       super(const DeviceConnectionState());

  Future<void> refresh() async {
    if (!_alive) return;
    final generation = ++_refreshGeneration;
    try {
      final result = await commands.run([
        'adb',
        'devices',
      ], cancellation: _lifetime);
      if (!_alive || generation != _refreshGeneration) return;
      final devices = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim().split(RegExp(r'\s+')))
          .where((parts) => parts.length >= 2 && parts[1] == 'device')
          .map((parts) => parts.first)
          .toSet()
          .toList();
      emit(state.copyWith(devices: List.unmodifiable(devices)));
      if (state.serial != null && !devices.contains(state.serial)) {
        await select(null);
      }
    } on ToolCancelled {
      /* 已关闭 */
    } catch (error) {
      if (_alive) appendAppOutput('刷新设备失败：$error', task: '设备');
    }
  }

  Future<void> select(String? serial) async {
    if (!_alive) return;
    _selection.cancel();
    final cancellation = _selection = ToolCancellation();
    _queryGeneration++;
    emit(state.copyWith(serial: serial, info: {}, packages: []));
    if (serial == null) return;
    try {
      final info = await _info.load(session, cancellation);
      if (_alive &&
          identical(cancellation, _selection) &&
          !cancellation.isCancelled) {
        emit(state.copyWith(info: Map.unmodifiable(info)));
      }
    } on ToolCancelled {
      /* 设备已切换 */
    } catch (error) {
      if (_alive && identical(cancellation, _selection)) {
        appendAppOutput('读取设备信息失败：$error', task: '设备');
      }
    }
  }

  Future<void> queryPackages(String keyword) async {
    if (!_alive) return;
    final query = keyword.trim();
    final generation = ++_queryGeneration;
    final cancellation = _selection;
    emit(state.copyWith(packages: []));
    if (query.isEmpty) return;
    try {
      final result = await session.run([
        'adb',
        'shell',
        'pm',
        'list',
        'packages',
      ], cancellation: cancellation);
      if (!_alive ||
          generation != _queryGeneration ||
          cancellation.isCancelled) {
        return;
      }
      final packages = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('package:'))
          .map((line) => line.substring(8).trim())
          .where((line) => line.contains(query) && line.isNotEmpty)
          .toSet()
          .toList();
      emit(state.copyWith(packages: List.unmodifiable(packages)));
      appendAppOutput(
        packages.isEmpty ? '未找到相关包名' : packages.join('\n'),
        task: '包名查询',
      );
    } on ToolCancelled {
      /* 设备已切换 */
    } catch (error) {
      if (_alive && generation == _queryGeneration) {
        appendAppOutput('查询失败：$error', task: '包名查询');
      }
    }
  }

  void selectEndpoint(String? endpoint) {
    if (_alive) emit(state.copyWith(selectedEndpoint: endpoint));
  }

  void cancelScan() => _scan?.cancel();
  Future<List<String>?> scan(String range, int port) async {
    if (!_alive) return null;
    if (_scan != null) {
      cancelScan();
      return null;
    }
    final cancellation = _scan = ToolCancellation();
    emit(state.copyWith(scanning: true, endpoints: [], selectedEndpoint: null));
    try {
      final addresses = Ipv4Range.parse(range);
      appendAppOutput('扫描 $range 的 $port 端口', task: '扫描');
      final found = await _scanner.scan(
        addresses,
        port,
        cancellation,
        onFound: (endpoint) {
          if (_alive && !cancellation.isCancelled) {
            emit(
              state.copyWith(
                endpoints: List.unmodifiable([...state.endpoints, endpoint]),
              ),
            );
          }
        },
      );
      if (!_alive || cancellation.isCancelled) return null;
      appendAppOutput('扫描完成，发现 ${found.length} 个开放端口（连接后确认设备）', task: '扫描');
      return List.unmodifiable(found);
    } catch (error) {
      if (_alive) appendAppOutput('扫描失败：$error', task: '扫描');
      return null;
    } finally {
      if (_alive) {
        _scan = null;
        emit(state.copyWith(scanning: false));
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _lifetime.cancel();
    _selection.cancel();
    _scan?.cancel();
    return super.close();
  }
}
