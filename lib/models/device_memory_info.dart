class DeviceMemoryInfo {
  final int memTotal;
  final int memAvailable;
  final int buffers;
  final int cached;

  DeviceMemoryInfo({
    required this.memTotal,
    required this.memAvailable,
    required this.buffers,
    required this.cached,
  });

  factory DeviceMemoryInfo.fromMap(Map<String, dynamic> map) {
    return DeviceMemoryInfo(
      memTotal: map['MemTotal'] ?? 0,
      memAvailable: map['MemAvailable'] ?? 0,
      buffers: map['Buffers'] ?? 0,
      cached: map['Cached'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'MemTotal': memTotal,
      'MemAvailable': memAvailable,
      'Buffers': buffers,
      'Cached': cached,
    };
  }

  int get usedMemory {
    return memTotal - memAvailable;
  }

  double get usedMemoryGB {
    return usedMemory / 1024 / 1024;
  }

  double get totalMemoryGB {
    return memTotal / 1024 / 1024;
  }

  double get availableMemoryGB {
    return memAvailable / 1024 / 1024;
  }
}
