import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 職種の選択肢（保存する値, 表示名）。
const List<(String, String)> kRoles = [
  ('doctor', '医師'),
  ('nurse', '看護師'),
  ('paramedic', '救急救命士'),
  ('mt', '臨床検査技師'),
  ('other', 'その他'),
];

/// 資格取得からの年数の区分（保存する値, 表示名）。勤務年数ではない。
const List<(String, String)> kYearBands = [
  ('pre', '取得前・学生'),
  ('lt1', '1年未満'),
  ('1-2', '1〜2年'),
  ('3-5', '3〜5年'),
  ('6-10', '6〜10年'),
  ('11-20', '11〜20年'),
  ('21+', '21年以上'),
];

String labelOf(List<(String, String)> list, String? key) =>
    list.firstWhere((e) => e.$1 == key, orElse: () => ('', '未設定')).$2;

/// 記録する利用イベント（キー → 表示名）。
const Map<String, String> kStatEvents = {
  'set_saved': '検査データの保存',
  'read_camera': 'カメラ読み取り',
  'read_photo': '写真読み取り',
  'read_manual': '手入力',
  'result_view': '結果の表示',
  'diag_view': '疾患推定の表示',
  'ai_advice': 'AIアドバイス',
  'ai_chat': 'AIへの追加質問',
  'compare': '前回との比較',
};

/// 利用統計。将来、職種・資格取得からの年数ごとの利用状況を集計するための準備。
///
/// 今は端末内に記録するだけで、どこにも送信しない。
/// 記録するのは職種・年数の区分と、機能ごとの利用回数（月単位）のみ。検査値・患者情報・日時は含めない。
/// 送信機能を作るときは [consent] が true の場合だけ [payload] を送ること。
class UsageStats {
  UsageStats(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'usage_stats_v1';
  static const _keepMonths = 24;

  Map<String, dynamic> _load() {
    final raw = _prefs.getString(_key);
    final m = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    m['schema'] ??= 1;
    m['installId'] ??= _randomId();
    m['consent'] ??= false;
    m['months'] ??= <String, dynamic>{};
    return m;
  }

  Future<void> _save(Map<String, dynamic> m) => _prefs.setString(_key, jsonEncode(m));

  /// 端末ごとのランダムなID（個人とは結び付かない）。
  String get installId {
    final m = _load();
    if (_prefs.getString(_key) == null) _save(m);
    return m['installId'] as String;
  }

  bool get consent => _load()['consent'] as bool;
  Future<void> setConsent(bool v) async {
    final m = _load()..['consent'] = v;
    await _save(m);
  }

  /// 月ごとの利用回数（'2026-10' → {イベント: 回数}）。
  Map<String, Map<String, int>> get months => {
        for (final e in (_load()['months'] as Map<String, dynamic>).entries)
          e.key: {for (final c in (e.value as Map<String, dynamic>).entries) c.key: c.value as int},
      };

  Future<void> track(String event, {DateTime? now}) async {
    if (!kStatEvents.containsKey(event)) return;
    final m = _load();
    final months = m['months'] as Map<String, dynamic>;
    final d = now ?? DateTime.now();
    final month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final c = (months[month] ??= <String, dynamic>{}) as Map<String, dynamic>;
    c[event] = ((c[event] as int?) ?? 0) + 1;
    final keys = months.keys.toList()..sort();
    while (keys.length > _keepMonths) {
      months.remove(keys.removeAt(0));
    }
    await _save(m);
  }

  Future<void> clearCounts() async {
    final m = _load()..['months'] = <String, dynamic>{};
    await _save(m);
  }

  /// 将来送信する場合のデータ。
  Map<String, dynamic> payload({required String? role, required String? years, required String rulesVersion}) => {
        'schema': 1,
        'app': 'labsight-app',
        'installId': installId,
        'role': role,
        'years': years,
        'rules': rulesVersion,
        'months': months,
      };

  static String _randomId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }
}
