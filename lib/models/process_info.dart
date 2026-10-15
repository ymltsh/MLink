class ProcessInfo {
  final String pid;
  final String uid;
  final String name;
  final String rss;
  final String cpu;
  final String package;
  final String type;
  final String status;

  ProcessInfo({
    required this.pid,
    required this.uid,
    required this.name,
    required this.rss,
    required this.cpu,
    required this.package,
    required this.type,
    required this.status,
  });

  factory ProcessInfo.fromMap(Map<String, dynamic> map) {
    return ProcessInfo(
      pid: map['PID'] ?? '',
      uid: map['UID'] ?? '',
      name: map['NAME'] ?? '',
      rss: map['RSS'] ?? '',
      cpu: map['CPU'] ?? '',
      package: map['package'] ?? '',
      type: map['type'] ?? '',
      status: map['status'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'PID': pid,
      'UID': uid,
      'NAME': name,
      'RSS': rss,
      'CPU': cpu,
      'package': package,
      'type': type,
      'status': status,
    };
  }
}
