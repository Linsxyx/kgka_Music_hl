import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_version.dart';
import 'music_api.dart';

class AppUpdateService {
  AppUpdateService(this._api);

  static const MethodChannel _channel = MethodChannel('kgka_music_hl/update');

  final MusicApi _api;

  static bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<AppVersionInfo?> checkForUpdate() async {
    if (!isSupportedPlatform) {
      return null;
    }

    final latest = await _api.latestAppVersion(AppUpdatePlatform.android);
    if (!latest.isNewerThanCurrent) {
      return null;
    }
    return latest;
  }

  Future<void> downloadAndInstall(AppVersionInfo version) async {
    if (!isSupportedPlatform) {
      throw UnsupportedError('当前平台不支持应用内更新');
    }
    if (!version.hasDownloadUrl) {
      throw StateError('更新包下载地址为空');
    }

    await _channel.invokeMethod<void>('downloadAndInstallApk', {
      'url': version.downloadUrl,
      'fileName': _safeApkName(version.versionName),
    });
  }

  String _safeApkName(String versionName) {
    final cleanVersion = versionName.replaceAll(
      RegExp(r'[^0-9A-Za-z._-]'),
      '_',
    );
    final suffix = cleanVersion.isEmpty ? 'latest' : cleanVersion;
    return 'ka_music_$suffix.apk';
  }
}
