import '../config/app_config.dart';
import 'music_models.dart';

enum AppUpdatePlatform {
  android('android'),
  ios('ios'),
  hm('hm');

  const AppUpdatePlatform(this.apiValue);

  final String apiValue;
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.platform,
    required this.versionName,
    required this.versionCode,
    required this.updateContent,
    required this.downloadUrl,
    required this.forceUpdate,
    this.releaseDate,
  });

  final String platform;
  final String versionName;
  final int versionCode;
  final String updateContent;
  final String downloadUrl;
  final bool forceUpdate;
  final DateTime? releaseDate;

  bool get hasDownloadUrl => downloadUrl.trim().isNotEmpty;

  bool get isNewerThanCurrent {
    final currentCode = normalizedVersionCode(AppConfig.appVersionCode);
    return versionCode > currentCode;
  }

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      platform: asString(json['platform']) ?? '',
      versionName: asString(json['versionName']) ?? '',
      versionCode: normalizedVersionCode(json['versionCode']),
      updateContent: asString(json['updateContent']) ?? '',
      downloadUrl: asString(json['downloadUrl']) ?? '',
      forceUpdate: _asBool(json['forceUpdate']),
      releaseDate: DateTime.tryParse(asString(json['releaseDate']) ?? ''),
    );
  }
}

int normalizedVersionCode(Object? value) {
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return value < 0 ? 0 : value;
  }

  final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return 0;
  }
  return int.tryParse(digits) ?? 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value == 1;
  }

  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1';
}
