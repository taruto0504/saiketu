import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_service.dart';
import 'database.dart';
import 'lab_catalog.dart';
import 'ocr_service.dart';
import 'rule_engine.dart';
import 'settings.dart';

/// アプリ全体で共有するサービス。
class AppServices extends ChangeNotifier {
  AppServices({
    required this.db,
    required this.catalog,
    required this.settings,
    required RuleSet rules,
    required this.builtinRules,
  }) : _rules = rules; // ignore: prefer_initializing_formals

  final AppDatabase db;
  final LabCatalog catalog;
  final AppSettings settings;
  final OcrService ocr = OcrService();
  final AiService ai = AiService();

  /// 組み込みルール（assets）。
  final RuleSet builtinRules;
  RuleSet _rules;
  RuleSet get rules => _rules;
  RuleEngine get engine => RuleEngine(_rules, catalog);

  /// フォルダ・データの変更通知（一覧の再読込用）。
  final ValueNotifier<int> dataVersion = ValueNotifier(0);
  void dataChanged() => dataVersion.value++;

  static const rulesAsset = 'assets/rules/disease_rules.json';

  static Future<RuleSet> loadRules(AppDatabase db) async {
    final custom = await db.getKv('rules_json');
    if (custom != null) {
      try {
        return RuleSet.fromJsonString(custom);
      } catch (e) {
        debugPrint('custom rules invalid: $e');
      }
    }
    return RuleSet.fromJsonString(await rootBundle.loadString(rulesAsset));
  }

  /// 判定ルールを差し替える（JSON文字列）。null で組み込みルールに戻す。
  Future<void> setCustomRules(String? json) async {
    if (json == null) {
      await db.setKv('rules_json', null);
      _rules = builtinRules;
    } else {
      final parsed = RuleSet.fromJsonString(json); // 不正なら例外
      await db.setKv('rules_json', json);
      _rules = parsed;
    }
    notifyListeners();
  }

  bool get usingCustomRules => !identical(_rules, builtinRules);

  Future<void> runAutoDelete() async {
    final days = settings.autoDeleteDays;
    if (days <= 0) return;
    final n = await db.purgeOlderThan(days);
    if (n > 0) dataChanged();
  }

  Future<void> saveCatalogSettings() async {
    await db.saveCustomItems(catalog.customItems);
    await db.saveUserRanges(catalog.userRanges);
  }
}
