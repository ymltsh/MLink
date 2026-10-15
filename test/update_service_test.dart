import 'dart:convert';
import 'dart:io';
import 'package:adb_tool/app/modules/settings/services/update_service.dart';
import 'package:adb_tool/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> entry(String version, int build) => {
      'version': version,
      'build': build,
      'name': '妙联',
    };
void main() {
  test('版本按数值比较，再比较构建号', () {
    expect(UpdateRelease.fromJson(entry('1.10.0', 1)).isNewerThan('1.9.9', 99),
        isTrue);
    expect(UpdateRelease.fromJson(entry('1.0.0', 2)).isNewerThan('1.0.0', 1),
        isTrue);
    expect(UpdateRelease.fromJson(entry('1.0.0', 1)).isNewerThan('1.0.0', 1),
        isFalse);
    expect(UpdateRelease.fromJson(entry('0.9.9', 999)).isNewerThan('1.0.0', 1),
        isFalse);
  });
  test('拒绝非法版本、构建和危险链接', () {
    for (final json in [
      entry('1.0', 1),
      entry('1.0.0-beta', 1),
      entry('1.0.0', 0),
      {
        ...entry('1.0.0', 1),
        'urls': {'windows': 'file:///C:/bad.exe'}
      },
      {...entry('1.0.0', 1), 'page': 'javascript:alert(1)'},
    ]) {
      expect(() => UpdateRelease.fromJson(json), throwsFormatException);
    }
  });
  test('项目与应用配置版本同步，初始化清单可解析', () {
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('version: ${AppConfig.appVersion}+${AppConfig.appBuild}'));
    final manifest = jsonDecode(File('version.json').readAsStringSync());
    expect(UpdateRelease.fromJson(manifest['latest']).build, greaterThan(0));
  });
}
