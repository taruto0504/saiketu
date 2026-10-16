import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage_stats.dart';

/// アプリ設定。機密性のない設定は SharedPreferences、
/// パスコード（ハッシュ）と APIキーは端末のセキュア領域に保存する。
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, this._secure) : stats = UsageStats(_prefs);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  /// 利用統計（端末内に記録するだけで、送信はしない）。
  final UsageStats stats;

  static const defaultModel = 'claude-opus-5-5';

  bool get agreed => _prefs.getBool('agreed_v1') ?? false;
  Future<void> setAgreed(bool v) async {
    await _prefs.setBool('agreed_v1', v);
    notifyListeners();
  }

  /// 利用者の職種（kRoles のキー）と、資格取得からの年数（kYearBands のキー）。
  String? get role => _prefs.getString('profile_role');
  String? get yearsSinceLicense => _prefs.getString('profile_years');
  bool get hasProfile => role != null && yearsSinceLicense != null;
  Future<void> setProfile({required String role, required String years}) async {
    await _prefs.setString('profile_role', role);
    await _prefs.setString('profile_years', years);
    notifyListeners();
  }

  bool get statsConsent => stats.consent;
  Future<void> setStatsConsent(bool v) async {
    await stats.setConsent(v);
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values[_prefs.getInt('theme') ?? 0];
  Future<void> setThemeMode(ThemeMode m) async {
    await _prefs.setInt('theme', m.index);
    notifyListeners();
  }

  double get textScale => _prefs.getDouble('text_scale') ?? 1.0;
  Future<void> setTextScale(double v) async {
    await _prefs.setDouble('text_scale', v);
    notifyListeners();
  }

  /// 0 = 自動削除しない。
  int get autoDeleteDays => _prefs.getInt('auto_delete_days') ?? 0;
  Future<void> setAutoDeleteDays(int v) async {
    await _prefs.setInt('auto_delete_days', v);
    notifyListeners();
  }

  bool get lockEnabled => _prefs.getBool('lock_enabled') ?? false;
  bool get biometricEnabled => _prefs.getBool('biometric') ?? false;
  Future<void> setBiometric(bool v) async {
    await _prefs.setBool('biometric', v);
    notifyListeners();
  }

  int get autoLockMinutes => _prefs.getInt('auto_lock_min') ?? 3;
  Future<void> setAutoLockMinutes(int v) async {
    await _prefs.setInt('auto_lock_min', v);
    notifyListeners();
  }

  bool get abnormalOnly => _prefs.getBool('abnormal_only') ?? false;
  Future<void> setAbnormalOnly(bool v) async {
    await _prefs.setBool('abnormal_only', v);
    notifyListeners();
  }

  String get aiModel => _prefs.getString('ai_model') ?? defaultModel;
  Future<void> setAiModel(String v) async {
    await _prefs.setString('ai_model', v.trim().isEmpty ? defaultModel : v.trim());
    notifyListeners();
  }

  // ───────── パスコード ─────────

  Future<void> setPasscode(String code) async {
    final r = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await _secure.write(key: 'passcode', value: '$salt:${_hash(salt, code)}');
    await _prefs.setBool('lock_enabled', true);
    notifyListeners();
  }

  Future<void> clearPasscode() async {
    await _secure.delete(key: 'passcode');
    await _prefs.setBool('lock_enabled', false);
    await _prefs.setBool('biometric', false);
    notifyListeners();
  }

  Future<bool> verifyPasscode(String code) async {
    final s = await _secure.read(key: 'passcode');
    if (s == null) return false;
    final i = s.indexOf(':');
    final salt = s.substring(0, i);
    return _hash(salt, code) == s.substring(i + 1);
  }

  String _hash(String salt, String code) {
    // 総当たり対策として反復ハッシュ
    List<int> d = utf8.encode('$salt$code');
    for (var i = 0; i < 20000; i++) {
      d = sha256.convert([...d, ...utf8.encode(salt)]).bytes;
    }
    return base64Encode(d);
  }

  // ───────── APIキー ─────────

  Future<String?> apiKey() => _secure.read(key: 'ai_api_key');
  Future<void> setApiKey(String? v) async {
    if (v == null || v.trim().isEmpty) {
      await _secure.delete(key: 'ai_api_key');
    } else {
      await _secure.write(key: 'ai_api_key', value: v.trim());
    }
    notifyListeners();
  }
}
