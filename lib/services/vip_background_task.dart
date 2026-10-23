import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import 'music_api.dart';

enum VipClaimStatus { idle, running, claimed, alreadyClaimed, failed }

class VipBackgroundTask extends ChangeNotifier {
  VipBackgroundTask(this._api) {
    unawaited(_restorePreferences());
  }

  final MusicApi _api;

  static const _autoEnabledKey = 'settings.auto_claim_vip_enabled';
  static const _lastRunKeyPref = 'settings.auto_claim_vip_last_run_key';
  static const _lastMessagePref = 'settings.auto_claim_vip_last_message';
  static const _lastStatusPref = 'settings.auto_claim_vip_last_status';
  static const _lastTimePref = 'settings.auto_claim_vip_last_time';

  bool _autoEnabled = true;
  bool get autoEnabled => _autoEnabled;

  VipClaimStatus _lastStatus = VipClaimStatus.idle;
  VipClaimStatus get lastStatus => _lastStatus;

  String? _lastMessage;
  String? get lastMessage => _lastMessage;

  DateTime? _lastClaimTime;
  DateTime? get lastClaimTime => _lastClaimTime;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String? _lastCompletedRunKey;

  VoidCallback? onClaimSuccess;

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _autoEnabled = prefs.getBool(_autoEnabledKey) ?? true;
    _lastCompletedRunKey = prefs.getString(_lastRunKeyPref);
    _lastMessage = prefs.getString(_lastMessagePref);
    final statusName = prefs.getString(_lastStatusPref);
    if (statusName != null) {
      for (final value in VipClaimStatus.values) {
        if (value.name == statusName) {
          _lastStatus = value;
          break;
        }
      }
    }
    final timeRaw = prefs.getString(_lastTimePref);
    if (timeRaw != null) {
      _lastClaimTime = DateTime.tryParse(timeRaw);
    }
    notifyListeners();
  }

  Future<void> setAutoEnabled(bool enabled, {LoginSession? session}) async {
    if (_autoEnabled == enabled) return;
    _autoEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoEnabledKey, enabled);
    if (enabled && session != null) {
      schedule(session);
    }
  }

  void schedule(LoginSession? session) {
    if (!_autoEnabled) return;
    final runKey = _buildRunKey(session);
    if (runKey == null || _isRunning || _lastCompletedRunKey == runKey) {
      return;
    }

    _isRunning = true;
    unawaited(_run(runKey));
  }

  Future<bool> claimNow(LoginSession? session) async {
    if (session?.isValid != true) {
      _updateStatus(VipClaimStatus.failed, '请先登录酷狗账号');
      return false;
    }
    if (_isRunning) return false;
    final runKey =
        _buildRunKey(session) ??
        'manual@${DateTime.now().toIso8601String().split('T').first}';
    _isRunning = true;
    return _run(runKey, force: true);
  }

  String? _buildRunKey(LoginSession? session) {
    if (session?.isValid != true) {
      return null;
    }

    final candidates = [
      session?.userId,
      session?.sessionId,
      session?.token,
    ];
    String identity = '';
    for (final item in candidates) {
      if (item != null && item.trim().isNotEmpty && item.trim() != '0') {
        identity = item.trim();
        break;
      }
    }
    if (identity.isEmpty) {
      return null;
    }

    final today = DateTime.now().toIso8601String().split('T').first;
    return '$identity@$today';
  }

  Future<bool> _run(String runKey, {bool force = false}) async {
    _updateStatus(VipClaimStatus.running, '正在签到领取概念版 VIP...');
    try {
      final history = await _api.vipReceiveHistory();
      if (history.status != 1 && !force) {
        _debugLog(
          'skip, vip history status=${history.status} error=${history.errorCode}',
        );
        _updateStatus(
          VipClaimStatus.failed,
          '查询签到记录失败（错误码：${history.errorCode ?? '未知'}）',
        );
        return false;
      }

      final today = DateTime.now().toIso8601String().split('T').first;
      VipReceiveItem? todayRecord;
      for (final item in history.items) {
        if (item.day == today) {
          todayRecord = item;
          break;
        }
      }

      if (todayRecord == null) {
        final result = await _api.dailyVip();
        if (result.status != 1) {
          _debugLog('daily vip failed, error=${result.errorCode}');
          _updateStatus(
            VipClaimStatus.failed,
            '领取畅听 VIP 失败（错误码：${result.errorCode ?? '未知'}）',
          );
          return false;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        final upgraded = await _upgradeVipReward();
        await _markCompleted(
          runKey,
          VipClaimStatus.claimed,
          upgraded ? '今日已签到并升级概念版 VIP' : '今日已签到领取畅听 VIP',
        );
        onClaimSuccess?.call();
        return true;
      } else if (todayRecord.vipType == 'tvip' || force) {
        final upgraded = await _upgradeVipReward();
        await _markCompleted(
          runKey,
          upgraded ? VipClaimStatus.claimed : VipClaimStatus.alreadyClaimed,
          upgraded ? '今日已升级为概念版 VIP' : '今日概念版 VIP 已领取',
        );
        onClaimSuccess?.call();
        return true;
      } else {
        _debugLog('today vip already fully claimed');
        await _markCompleted(
          runKey,
          VipClaimStatus.alreadyClaimed,
          '今日概念版 VIP 已领取',
        );
        onClaimSuccess?.call();
        return true;
      }
    } catch (error, stackTrace) {
      _debugLog('vip background task failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _updateStatus(VipClaimStatus.failed, '签到失败：$error');
      return false;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<bool> _upgradeVipReward() async {
    try {
      final result = await _api.upgradeVipReward();
      if (result.status != 1) {
        _debugLog('upgrade vip failed, error=${result.errorCode}');
        return false;
      }
      return true;
    } catch (error) {
      _debugLog('upgrade vip exception: $error');
      return false;
    }
  }

  void _updateStatus(VipClaimStatus status, String message) {
    _lastStatus = status;
    _lastMessage = message;
    notifyListeners();
  }

  Future<void> _markCompleted(
    String runKey,
    VipClaimStatus status,
    String message,
  ) async {
    _lastCompletedRunKey = runKey;
    _lastStatus = status;
    _lastMessage = message;
    _lastClaimTime = DateTime.now();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunKeyPref, runKey);
    await prefs.setString(_lastStatusPref, status.name);
    await prefs.setString(_lastMessagePref, message);
    await prefs.setString(_lastTimePref, _lastClaimTime!.toIso8601String());
  }

  void _debugLog(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[KA Music][vip-task] $message');
  }
}