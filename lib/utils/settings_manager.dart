import 'package:shared_preferences/shared_preferences.dart';

class SettingsManager {
  static const String keyAutoScanAndConnect = 'autoScanAndConnect';
  static const String keyKeepScreenOn = 'keepScreenOn';
  static const String keyShowTouches = 'showTouches';
  static const String keyDefaultBitrate = 'defaultBitrate';
  static const String keyDefaultResolution = 'defaultResolution';
  static const String keyDefaultDpi = 'defaultDpi';
  static const String keyTurnScreenOff = 'turn_screen_off'; // 改为公开字段

  // 添加新的键值定义
  static const String keyEnableH265 = 'enableH265';
  static const String keyEnablePhysicalKeyboard = 'enablePhysicalKeyboard';
  static const String keyDisableAudio = 'disableAudio';
  static const String keyEnableRecording = 'enableRecording';

  static Future<void> saveSettings({
    bool? autoScanAndConnect,
    bool? keepScreenOn,
    bool? showTouches,
    String? defaultBitrate,
    String? defaultResolution,
    String? defaultDpi,
    bool? turnScreenOff,
    bool? enableH265,
    bool? enablePhysicalKeyboard,
    bool? disableAudio,
    bool? enableRecording,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (autoScanAndConnect != null) {
      await prefs.setBool(keyAutoScanAndConnect, autoScanAndConnect);
    }
    if (keepScreenOn != null) {
      await prefs.setBool(keyKeepScreenOn, keepScreenOn);
    }
    if (showTouches != null) {
      await prefs.setBool(keyShowTouches, showTouches);
    }
    if (defaultBitrate != null) {
      await prefs.setString(keyDefaultBitrate, defaultBitrate);
    }
    if (defaultResolution != null) {
      await prefs.setString(keyDefaultResolution, defaultResolution);
    }
    if (defaultDpi != null) {
      await prefs.setString(keyDefaultDpi, defaultDpi);
    }
    if (turnScreenOff != null) {
      await prefs.setBool(keyTurnScreenOff, turnScreenOff);
    }
    if (enableH265 != null) {
      await prefs.setBool(keyEnableH265, enableH265);
    }
    if (enablePhysicalKeyboard != null) {
      await prefs.setBool(keyEnablePhysicalKeyboard, enablePhysicalKeyboard);
    }
    if (disableAudio != null) {
      await prefs.setBool(keyDisableAudio, disableAudio);
    }
    if (enableRecording != null) {
      await prefs.setBool(keyEnableRecording, enableRecording);
    }
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      keyAutoScanAndConnect: prefs.getBool(keyAutoScanAndConnect) ?? false,
      keyKeepScreenOn: prefs.getBool(keyKeepScreenOn) ?? false,
      keyShowTouches: prefs.getBool(keyShowTouches) ?? false,
      keyDefaultBitrate: prefs.getString(keyDefaultBitrate) ?? '8',
      keyDefaultResolution: prefs.getString(keyDefaultResolution) ?? '1080',
      keyDefaultDpi: prefs.getString(keyDefaultDpi) ?? '420',
      keyTurnScreenOff: prefs.getBool(keyTurnScreenOff) ?? false,  // 使用公开字段
      keyEnableH265: prefs.getBool(keyEnableH265) ?? false,
      keyEnablePhysicalKeyboard: prefs.getBool(keyEnablePhysicalKeyboard) ?? false,
      keyDisableAudio: prefs.getBool(keyDisableAudio) ?? false,
      keyEnableRecording: prefs.getBool(keyEnableRecording) ?? false,
    };
  }
}