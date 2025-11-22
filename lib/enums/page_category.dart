import 'package:flutter/material.dart';

enum PageCategory {
  deviceConnection,
  screenMirroring,
  appManagement,
  deviceOperations, // 设备操作
  settings,
}

extension PageCategoryExtension on PageCategory {
  String get label {
    switch (this) {
      case PageCategory.deviceConnection:
        return '设备连接';
      case PageCategory.screenMirroring:
        return '屏幕镜像';
      case PageCategory.appManagement:
        return '应用管理';
      case PageCategory.deviceOperations:
        return '设备操作';
      case PageCategory.settings:
        return '设置';
    }
  }

  IconData get icon {
    switch (this) {
      case PageCategory.deviceConnection:
        return Icons.usb;
      case PageCategory.screenMirroring:
        return Icons.screen_share;
      case PageCategory.appManagement:
        return Icons.apps;
      case PageCategory.deviceOperations:
        return Icons.phone_android;
      case PageCategory.settings:
        return Icons.settings;
    }
  }
}