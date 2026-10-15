import 'dart:convert';
import 'dart:io';

import '../../../../core/config/app_config.dart';

class UpdateRelease {
  final String version;
  final int build;
  final String name;
  final String notes;
  final Uri page;
  final Map<String, Uri> urls;

  UpdateRelease.fromJson(Map<String, dynamic> json)
      : version = json['version'] as String,
        build = json['build'] as int,
        name = json['name'] as String,
        notes = json['notes'] as String? ?? '',
        page = httpsUri(json['page'] as String? ?? AppConfig.releasePage),
        urls = (json['urls'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, httpsUri(value as String)),
        ) {
    versionParts(version);
    if (build < 1 || name.trim().isEmpty) {
      throw const FormatException('更新清单版本信息无效');
    }
  }

  static Uri httpsUri(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('更新链接必须为 HTTPS 地址');
    }
    return uri;
  }

  static List<int> versionParts(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) {
      throw const FormatException('版本号必须为 x.y.z');
    }
    return value.split('.').map(int.parse).toList();
  }

  bool isNewerThan(String currentVersion, int currentBuild) {
    final latest = versionParts(version);
    final current = versionParts(currentVersion);
    for (var i = 0; i < 3; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return build > currentBuild;
  }
}

class UpdateService {
  Future<UpdateRelease> check() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(Uri.parse(AppConfig.updateUrl));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('更新接口返回 ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const FormatException('更新清单过大');
          }
        }
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return UpdateRelease.fromJson(json['latest'] as Map<String, dynamic>);
      })()
          .timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}
