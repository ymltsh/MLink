class MemorySnapshot {
  final double usedGB;
  final double totalGB;
  final DateTime timestamp;

  double get availableGB => totalGB - usedGB;
  double get usageRatio => usedGB / totalGB; // 0.0 - 1.0

  MemorySnapshot({required this.usedGB, required this.totalGB, required this.timestamp});
}
