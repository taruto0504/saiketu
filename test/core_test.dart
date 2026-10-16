import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labsight/data/lab_catalog_data.dart';
import 'package:labsight/models/lab_set.dart';
import 'package:labsight/services/ai_service.dart';
import 'package:labsight/services/clinical_calc.dart';
import 'package:labsight/services/lab_catalog.dart';
import 'package:labsight/services/ocr_parser.dart';
import 'package:labsight/services/rule_engine.dart';

LabSet labs(Map<String, double> v, {PatientContext? ctx, OxygenInfo? o2, SpecimenInfo? spec, DateTime? at}) => LabSet(
      takenAt: at,
      values: [for (final e in v.entries) LabValue(code: e.key, value: e.value)],
      context: ctx,
      oxygen: o2,
      specimen: spec,
    );

void main() {
  final catalog = LabCatalog();
  final rules = RuleSet.fromJsonString(File('assets/rules/disease_rules.json').readAsStringSync());
  final engine = RuleEngine(rules, catalog);

  group('項目マスタ・別名辞書', () {
    test('全項目のコードが一意', () {
      final codes = builtinLabItems.map((e) => e.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('別名が同一項目にまとまる', () {
      for (final a in ['Cr', 'CRE', 'クレアチニン', 'Ｃｒｅ', 'S-Cre']) {
        expect(catalog.codeForAlias(a), 'CRE', reason: a);
      }
      expect(catalog.codeForAlias('γ-GTP'), 'GGT');
      expect(catalog.codeForAlias('GOT'), 'AST');
      expect(catalog.codeForAlias('PT-INR'), 'PT_INR');
      expect(catalog.codeForAlias('HCO3-'), 'HCO3');
      expect(catalog.codeForAlias('D-ダイマー'), 'DDIMER');
      expect(catalog.codeForAlias('PHT'), 'PHT');
    });

    test('基準値の範囲が正しい向き', () {
      for (final d in builtinLabItems) {
        if (d.low != null && d.high != null) expect(d.low! <= d.high!, isTrue, reason: d.code);
        if (d.plausLow != null && d.plausHigh != null) expect(d.plausLow! < d.plausHigh!, isTrue, reason: d.code);
      }
    });

    test('高値・低値・危険値の判定', () {
      expect(catalog.flagFor(LabValue(code: 'K', value: 5.2)), LabFlag.high);
      expect(catalog.flagFor(LabValue(code: 'K', value: 6.5)), LabFlag.critHigh);
      expect(catalog.flagFor(LabValue(code: 'NA', value: 130)), LabFlag.low);
      expect(catalog.flagFor(LabValue(code: 'NA', value: 140)), LabFlag.normal);
      // 用紙の基準値を優先
      expect(catalog.flagFor(LabValue(code: 'NA', value: 136, sheetLow: 135, sheetHigh: 147)), LabFlag.normal);
      // 性別
      expect(catalog.flagFor(LabValue(code: 'HB', value: 13.0), sex: 'M'), LabFlag.low);
      expect(catalog.flagFor(LabValue(code: 'HB', value: 13.0), sex: 'F'), LabFlag.normal);
      // 静脈血は静脈血の基準値・PO2の危険値は適用しない
      expect(catalog.flagFor(LabValue(code: 'PO2', value: 38), specimen: SpecimenType.venous), LabFlag.normal);
      expect(catalog.flagFor(LabValue(code: 'PO2', value: 38), specimen: SpecimenType.arterial), LabFlag.critLow);
    });

    test('誤読検出（小数点ずれ）', () {
      final na = catalog.checkPlausibility('NA', 14);
      expect(na, isNotNull);
      expect(na!.suggestion, 140);
      expect(catalog.checkPlausibility('K', 45)!.suggestion, 4.5);
      expect(catalog.checkPlausibility('NA', 140), isNull);
    });
  });

  group('OCR解析', () {
    final parser = LabSheetParser(catalog);
    final now = DateTime.now().subtract(const Duration(days: 1));
    final dateStr = '${now.year}/${now.month}/${now.day} 08:30';

    test('検査用紙の行を解析し、個人情報行は除外', () {
      final lines = [
        '氏名 山田 太郎 様',
        '生年月日 1950/01/02 74歳 男',
        '採取日時 $dateStr',
        'WBC 12500 /μL 3300-8600 H',
        'Hb 9.8 g/dL 13.7-16.8 L',
        'PLT 8.5 ×10^4/μL',
        'Na 14 mEq/L',
        'K 6.2 mEq/L H',
        'クレアチニン 2.35 mg/dL',
        'BUN 58',
        'CRP 12.50 mg/dL 0.00~0.14 H',
        'AST(GOT) 4O U/L',
        '動脈血ガス',
        'pH 7.28',
        'PaO2 62.0 mmHg',
        'PaCO2 30',
        'HCO3- 14.0',
        'Lac 4.5',
        'O2 3L/min 鼻カヌラ',
      ].map((t) => OcrLine(t)).toList();
      final r = parser.parse(lines);
      final m = {for (final v in r.values) v.code: v};
      expect(m.keys, containsAll(['WBC', 'HB', 'PLT', 'NA', 'K', 'CRE', 'BUN', 'CRP', 'AST', 'PH', 'PO2', 'PCO2', 'HCO3', 'LAC']));
      expect(m['WBC']!.value, 12500);
      expect(m['WBC']!.sheetLow, 3300);
      expect(m['WBC']!.sheetHigh, 8600);
      expect(m['WBC']!.sheetFlag, 'H');
      expect(m['CRP']!.sheetHigh, 0.14);
      expect(m['CRE']!.value, 2.35);
      // Na 14 は誤読として要確認
      expect(m['NA']!.uncertain, isTrue);
      expect(m['NA']!.warnings.join(), contains('140'));
      // O→0 の置換は要確認
      expect(m['AST']!.value, 40);
      expect(m['AST']!.uncertain, isTrue);
      expect(m['K']!.uncertain, isFalse);
      expect(r.specimen, SpecimenType.arterial);
      expect(r.oxygen.flowLpm, 3);
      expect(r.oxygen.device, '鼻カヌラ');
      expect(r.age, 74);
      expect(r.sex, 'M');
      expect(r.skippedPersonalRows, 2);
      expect(r.takenAt?.day, now.day);
    });

    test('同じ高さの断片を1行にまとめる・単位換算', () {
      final lines = [
        OcrLine('WBC', left: 10, top: 100, right: 60, bottom: 120),
        OcrLine('6.5', left: 200, top: 101, right: 240, bottom: 121),
        OcrLine('×10^3/μL', left: 260, top: 100, right: 340, bottom: 120),
        OcrLine('PLT', left: 10, top: 140, right: 60, bottom: 160),
        OcrLine('235', left: 200, top: 141, right: 240, bottom: 161),
      ];
      final r = parser.parse(lines);
      final m = {for (final v in r.values) v.code: v};
      expect(m['WBC']!.value, closeTo(6500, 0.01));
      // 単位なしで桁が合わない PLT 235 → ×10^3/μL と推定して 23.5
      expect(m['PLT']!.value, closeTo(23.5, 0.01));
      expect(m['PLT']!.uncertain, isTrue);
    });

    test('2列組みの用紙', () {
      final r = parser.parse([OcrLine('AST 25 U/L ALT 30 U/L'), OcrLine('Na140 K4.1')]);
      final m = {for (final v in r.values) v.code: v.value};
      expect(m, {'AST': 25, 'ALT': 30, 'NA': 140, 'K': 4.1});
    });

    test('酸素投与の検出', () {
      expect(detectOxygen('FiO2 40%').fio2, closeTo(0.4, 1e-9));
      expect(detectOxygen('FIO2: 0.6').fio2, closeTo(0.6, 1e-9));
      expect(detectOxygen('室内気').fio2, 0.21);
      expect(detectOxygen('リザーバーマスク 10L/分').device, 'リザーバーマスク');
      final none = detectOxygen('SO2 98 % PO2 65 L');
      expect(none.hasInfo, isFalse);
    });
  });

  group('A/V推定・計算値', () {
    test('静脈血を推定', () {
      final e = estimateSpecimen(labs({'PO2': 35, 'SO2': 65, 'PCO2': 48, 'PH': 7.36}));
      expect(e.type, SpecimenType.venous);
      expect(e.reasons, isNotEmpty);
    });

    test('動脈血を推定・用紙の記載を優先', () {
      expect(estimateSpecimen(labs({'PO2': 92, 'SO2': 97})).type, SpecimenType.arterial);
      expect(
          estimateSpecimen(labs({'PO2': 92, 'SO2': 97}, spec: SpecimenInfo(sheetLabel: SpecimenType.venous))).type,
          SpecimenType.venous);
    });

    test('AG・BUN/Cre・P/F比', () {
      final d = computeDerived(labs({'NA': 140, 'CL': 100, 'HCO3': 12, 'BUN': 40, 'CRE': 1.0, 'PO2': 80, 'SO2': 96},
          o2: OxygenInfo(fio2: 0.4)));
      expect(d['AG_CALC']!.value, 28);
      expect(d['BUN_CRE']!.value, 40);
      expect(d['PF']!.value, closeTo(200, 1e-9));
    });
  });

  group('疾患推定ルール', () {
    test('ルールJSONが読み込める', () {
      expect(rules.diseases.length, greaterThan(40));
      expect(rules.sampleChecks, isNotEmpty);
    });

    test('DKA：採血データのみで上位に', () {
      final r = engine.evaluate(labs({'GLU': 520, 'NA': 132, 'CL': 96, 'HCO3': 8, 'PH': 7.12, 'PCO2': 22, 'PO2': 95, 'SO2': 97, 'K': 5.6, 'KETONE': 6500}));
      expect(r.stage, 1);
      final top3 = r.diseases.take(3).map((d) => d.id).toList();
      expect(top3, contains('dka'));
      final dka = r.diseases.firstWhere((d) => d.id == 'dka');
      expect(dka.support.map((e) => e.text).join(), contains('血糖'));
    });

    test('前回値からの変化で AKI', () {
      final prev = labs({'CRE': 0.8, 'BUN': 15}, at: DateTime.now().subtract(const Duration(days: 2)));
      final cur = labs({'CRE': 1.4, 'BUN': 32, 'K': 5.0});
      final r = engine.evaluate(cur, previous: prev);
      final aki = r.diseases.firstWhere((d) => d.id == 'aki');
      expect(aki.support.first.text, contains('前回'));
    });

    test('溶血の警告（K高値＋LDH高値）', () {
      final r = engine.evaluate(labs({'K': 6.1, 'LDH': 400, 'AST': 60, 'ALT': 20}));
      expect(r.sampleWarnings.map((w) => w.name).join(), contains('溶血'));
    });

    test('第2段階：追加情報で順位が変わり、変化の要因が示される', () {
      final set = labs({'TNT': 0.05, 'CK': 300, 'DDIMER': 2.5, 'PO2': 70, 'SO2': 93, 'PCO2': 32});
      final first = engine.evaluate(set);
      set.context = PatientContext(age: 68, sex: 'M', symptoms: ['胸痛', '冷汗'], history: '糖尿病');
      final second = engine.evaluate(set, useContext: true);
      expect(second.stage, 2);
      final diff = diffEvaluations(first, second);
      final acs = diff.items.firstWhere((d) => d.result.id == 'acs');
      expect(acs.added.where((e) => e.fromContext), isNotEmpty);
      final r1 = first.diseases.indexWhere((d) => d.id == 'acs');
      final r2 = second.diseases.indexWhere((d) => d.id == 'acs');
      expect(r2, lessThanOrEqualTo(r1));
      expect(second.diseases.first.id, 'acs');
    });

    test('第1段階では追加情報を使わない', () {
      final set = labs({'K': 5.8}, ctx: PatientContext(medications: 'スピロノラクトン'));
      final r = engine.evaluate(set);
      final hk = r.diseases.firstWhere((d) => d.id == 'hyperkalemia');
      expect(hk.support.any((e) => e.fromContext), isFalse);
    });

    test('全ルールが例外なく評価できる（全項目を異常値にしても）', () {
      final hi = labs({for (final d in builtinLabItems) d.code: (d.high ?? d.low ?? 1) * 3 + 1});
      final lo = labs({for (final d in builtinLabItems) d.code: (d.low ?? 0) * 0.3});
      final prev = labs({for (final d in builtinLabItems) d.code: (d.low ?? 1)});
      final ctx = PatientContext(age: 80, sex: 'F', temp: 39, sbp: 80, hr: 120, rr: 30, spo2: 85, jcs: '10', gcs: 12, symptoms: ['胸痛']);
      expect(() => engine.evaluate(hi..context = ctx, previous: prev, useContext: true), returnsNormally);
      expect(() => engine.evaluate(lo..context = ctx, previous: prev, useContext: true), returnsNormally);
    });
  });

  group('AI送信データ', () {
    test('氏名・自由記載・日付を含まない', () {
      final set = labs({'NA': 128, 'K': 5.5},
          ctx: PatientContext(age: 70, sex: 'F', complaint: '山田さん 胸痛', history: '糖尿病', medications: 'ワルファリン'));
      set.memo = 'メモ';
      final eval = AiService.privacySafeEvaluation(engine, set, null);
      final s = AiService.buildLabSummary(catalog: catalog, current: set, evaluation: eval);
      expect(s, contains('70歳'));
      expect(s, contains('女性'));
      expect(s, isNot(contains('山田')));
      expect(s, isNot(contains('胸痛')));
      expect(s, isNot(contains('ワルファリン')));
      expect(s, isNot(contains('糖尿病')));
      expect(s, isNot(contains(set.takenAt.year.toString())));
    });

    test('個人情報らしき入力の警告', () {
      expect(personalInfoWarning('生年月日は？'), isNotNull);
      expect(personalInfoWarning('カリウムの補正は？'), isNull);
    });
  });
}
