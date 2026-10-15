import '../models/process_info.dart';
import '../models/device_memory_info.dart';

abstract class ProcessDataSource {
  Future<List<ProcessInfo>> fetchProcesses();
  Future<DeviceMemoryInfo> fetchMemoryInfo();
  Future<String> getForegroundPackage();
}
