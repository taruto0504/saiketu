import '../models/lab_item.dart';
import '../models/lab_set.dart';
import 'lab_catalog.dart';

/// OCRで認識した1行（座標は画像内のピクセルまたは正規化座標）。
class OcrLine {
  OcrLine(this.text, {this.left = 0, this.top = 0, this.right = 0, this.bottom = 0, this.confidence});
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// 0–1。取得できない場合は null。
  final double? confidence;

  double get height => (bottom - top).abs();
  double get centerY => (top + bottom) / 2;
}

class ParsedSheet {
  ParsedSheet({
    required this.values,
    required this.specimen,
    required this.oxygen,
    this.takenAt,
    this.age,
    this.sex,
    this.skippedPersonalRows = 0,
  });
  final List<LabValue> values;
  final SpecimenType? specimen;
  final OxygenInfo oxygen;
  final DateTime? takenAt;
  final int? age;
  final String? sex;
  final int skippedPersonalRows;
}

/// 全角英数字を半角に。
String toHalfWidth(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    if (c == 0x3000) c = 0x20;
    b.writeCharCode(c);
  }
  return b.toString();
}

final _personalRow = RegExp(
    r'(氏名|患者名|名前|フリガナ|ﾌﾘｶﾞﾅ|カナ氏名|生年月日|誕生日|カルテ|患者番号|患者ID|住所|電話|TEL|保険証|(?<![A-Za-z])ID(?![A-Za-z])|様(\s|$)|殿(\s|$))',
    caseSensitive: false);

/// OCRの行を、表の「行」単位にまとめる（同じ高さにある断片を左から順に結合）。
List<({String text, double? confidence})> groupRows(List<OcrLine> lines) {
  final hasBoxes = lines.any((l) => l.height > 0);
  if (!hasBoxes) return [for (final l in lines) (text: l.text, confidence: l.confidence)];
  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrLine>>[];
  for (final l in sorted) {
    if (rows.isNotEmpty) {
      final last = rows.last;
      final refH = last.map((e) => e.height).reduce((a, b) => a + b) / last.length;
      final refY = last.map((e) => e.centerY).reduce((a, b) => a + b) / last.length;
      if ((l.centerY - refY).abs() < 0.5 * (refH > 0 ? refH : l.height)) {
        last.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return [
    for (final r in rows)
      (
        text: (r..sort((a, b) => a.left.compareTo(b.left))).map((e) => e.text).join('  '),
        confidence: r.any((e) => e.confidence != null)
            ? r.where((e) => e.confidence != null).map((e) => e.confidence!).reduce((a, b) => a < b ? a : b)
            : null,
      )
  ];
}

class LabSheetParser {
  LabSheetParser(this.catalog);
  final LabCatalog catalog;

  static final _num = RegExp(r'^[<>≦≧≤≥]?[-+]?[0-9OoIlSB]*[0-9][0-9OoIlSB]*([.,][0-9OoIl]+)?$');
  static final _range = RegExp(r'^[(（\[]?([-+]?\d+(?:\.\d+)?)\s*[-~～〜–－]\s*(\d+(?:\.\d+)?)[)）\]]?$');
  static final _upper = RegExp(r'^[(（]?[≦≤<]=?\s*(\d+(?:\.\d+)?)[)）]?$');
  static final _lower = RegExp(r'^[(（]?[≧≥>]=?\s*(\d+(?:\.\d+)?)[)）]?$');
  static final _unitHint = RegExp(r'(/|%|‰|mg|g/|U/L|IU|mEq|mmol|μmol|umol|mmHg|kPa|fL|fl|pg|ng|μg|ug|秒|sec|×10|x10|mOsm|ml/min|mL/min)', caseSensitive: false);
  static final _flagToken = RegExp(r'^\*?(H|L|HH|LL|↑|↓|高|低|\+|-)\*?$');
  static final _valueWithFlag = RegExp(r'^(.*?\d)\s*\*?(H|L|↑|↓)\*?$');
  static final _flagWithValue = RegExp(r'^\*?(H|L|↑|↓)\*?\s*([-+]?\d.*)$');

  ParsedSheet parse(List<OcrLine> lines) {
    final rows = groupRows(lines);
    final values = <LabValue>[];
    final seen = <String>{};
    final safeText = StringBuffer();
    var skipped = 0;
    int? age;
    String? sex;
    DateTime? takenAt;

    for (final row in rows) {
      final text = toHalfWidth(row.text).trim();
      if (text.isEmpty) continue;
      if (_personalRow.hasMatch(text)) {
        // 個人情報の行は値として使わない（年齢・性別だけ参考に拾う）
        skipped++;
        age ??= _extractAge(text);
        sex ??= _extractSex(text);
        continue;
      }
      age ??= _extractAge(text);
      safeText.writeln(text);
      takenAt ??= _extractDate(text);
      for (final v in _parseRow(text, row.confidence)) {
        if (seen.contains(v.code)) continue;
        seen.add(v.code);
        values.add(v);
      }
    }
    final all = safeText.toString();
    return ParsedSheet(
      values: values,
      specimen: detectSpecimenLabel(all),
      oxygen: detectOxygen(all),
      takenAt: takenAt,
      age: age,
      sex: sex,
      skippedPersonalRows: skipped,
    );
  }

  int? _extractAge(String t) {
    final m = RegExp(r'(\d{1,3})\s*(歳|才)').firstMatch(t);
    if (m == null) return null;
    final a = int.parse(m.group(1)!);
    return a <= 120 ? a : null;
  }

  String? _extractSex(String t) {
    if (RegExp(r'(男性|性別\s*[:：]?\s*男|(^|[\s(（:：/])男($|[\s)）/]))').hasMatch(t)) return 'M';
    if (RegExp(r'(女性|性別\s*[:：]?\s*女|(^|[\s(（:：/])女($|[\s)）/]))').hasMatch(t)) return 'F';
    return null;
  }

  DateTime? _extractDate(String t) {
    if (!RegExp(r'(採取|採血|検体|測定|受付|報告|日時|DATE)', caseSensitive: false).hasMatch(t)) return null;
    final m = RegExp(r'(20\d\d)\s*[/.\-年]\s*(\d{1,2})\s*[/.\-月]\s*(\d{1,2})\s*日?(?:\s*(\d{1,2})\s*[:時]\s*(\d{2}))?').firstMatch(t);
    if (m == null) return null;
    try {
      final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
          m.group(4) != null ? int.parse(m.group(4)!) : 0, m.group(5) != null ? int.parse(m.group(5)!) : 0);
      final now = DateTime.now();
      if (d.isAfter(now.add(const Duration(days: 1))) || d.isBefore(now.subtract(const Duration(days: 365 * 3)))) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 行のトークン化。"Na140" のような項目名と数値の連結も分割する。
  List<String> _tokens(String text) {
    final raw = text
        .replaceAll(RegExp(r'[|｜]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final out = <String>[];
    for (final t in raw) {
      if (catalog.codeForAlias(t) != null) {
        out.add(t);
        continue;
      }
      final m = RegExp(r'^(.*?[^\d.\-+])([-+]?\d+(?:\.\d+)?[HL↑↓*]*)$').firstMatch(t);
      if (m != null && catalog.codeForAlias(m.group(1)!) != null) {
        out
          ..add(m.group(1)!)
          ..add(m.group(2)!);
        continue;
      }
      out.add(t);
    }
    return out;
  }

  List<LabValue> _parseRow(String text, double? conf) {
    final tokens = _tokens(text);
    final results = <LabValue>[];
    _Entry? cur;
    var i = 0;
    while (i < tokens.length) {
      // 項目名（最大3トークン）を照合
      String? code;
      var used = 0;
      for (var k = 3; k >= 1; k--) {
        if (i + k > tokens.length) continue;
        final joined = tokens.sublist(i, i + k).join('');
        final c = catalog.codeForAlias(joined);
        if (c != null) {
          // 数値単独のトークンを項目名とみなさない
          if (_num.hasMatch(joined)) continue;
          code = c;
          used = k;
          break;
        }
      }
      if (code != null && (cur == null || cur.value != null || cur.code == code)) {
        if (cur != null && cur.value != null) results.add(cur.build(catalog, conf));
        cur = _Entry(code);
        i += used;
        continue;
      }
      if (cur != null) _consume(cur, tokens, i);
      i++;
    }
    if (cur != null && cur.value != null) results.add(cur.build(catalog, conf));
    return results;
  }

  void _consume(_Entry e, List<String> tokens, int i) {
    var t = tokens[i];
    // 範囲 "138-145" / "(3.6~4.8)"
    final r = _range.firstMatch(t);
    if (r != null && e.value != null) {
      e.low ??= double.parse(r.group(1)!);
      e.high ??= double.parse(r.group(2)!);
      return;
    }
    final up = _upper.firstMatch(t);
    if (up != null && e.value != null) {
      e.high ??= double.parse(up.group(1)!);
      return;
    }
    final lo = _lower.firstMatch(t);
    if (lo != null && e.value != null) {
      e.low ??= double.parse(lo.group(1)!);
      return;
    }
    if (_flagToken.hasMatch(t) && e.value != null) {
      if (t == '-' || t == '+') {
        // "138 - 145" のような区切り
        return;
      }
      e.flag ??= (t.contains('H') || t.contains('↑') || t.contains('高')) ? 'H' : 'L';
      return;
    }
    final vf = _valueWithFlag.firstMatch(t);
    if (vf != null && e.value == null) {
      e.flag = (vf.group(2) == 'H' || vf.group(2) == '↑') ? 'H' : 'L';
      t = vf.group(1)!;
    }
    final fv = _flagWithValue.firstMatch(t);
    if (fv != null && e.value == null) {
      e.flag = (fv.group(1) == 'H' || fv.group(1) == '↑') ? 'H' : 'L';
      t = fv.group(2)!;
    }
    if (_num.hasMatch(t)) {
      final parsed = _parseNumber(t);
      if (parsed == null) return;
      if (e.value == null) {
        e.value = parsed.value;
        e.raw = tokens[i];
        e.substituted = parsed.substituted;
        e.prefix = parsed.prefix;
      } else if (e.low == null && e.pendingLow == null) {
        e.pendingLow = parsed.value;
      } else if (e.pendingLow != null && e.high == null) {
        e.low = e.pendingLow;
        e.high = parsed.value;
        e.pendingLow = null;
      } else {
        e.extraNumbers++;
      }
      return;
    }
    if (_unitHint.hasMatch(t) && e.unit == null) {
      e.unit = t;
      return;
    }
  }

  ({double value, bool substituted, String? prefix})? _parseNumber(String t) {
    var s = t;
    String? prefix;
    final pm = RegExp(r'^[<>≦≧≤≥]').firstMatch(s);
    if (pm != null) {
      prefix = pm.group(0);
      s = s.substring(1);
    }
    final before = s;
    s = s.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[Il]'), '1').replaceAll('S', '5').replaceAll('B', '8');
    final substituted = s != before;
    // 千の位区切り "6,500"
    if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s)) {
      s = s.replaceAll(',', '');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    final v = double.tryParse(s);
    if (v == null) return null;
    return (value: v, substituted: substituted || before.contains(','), prefix: prefix);
  }
}

class _Entry {
  _Entry(this.code);
  final String code;
  double? value;
  String? raw;
  String? unit;
  double? low;
  double? high;
  double? pendingLow;
  String? flag;
  String? prefix;
  bool substituted = false;
  int extraNumbers = 0;

  LabValue build(LabCatalog catalog, double? conf) {
    final def = catalog.byCode(code);
    final warnings = <String>[];
    var uncertain = false;
    var v = value!;
    var u = unit ?? def?.unit ?? '';
    var lo = low, hi = high;
    if (pendingLow != null && lo == null && hi == null) {
      // 値の後に数値が1つだけ → 上限のみの基準値（例: CRP 0.30 0.14）とみなす
      hi = pendingLow;
    }

    if (conf != null && conf < 0.7) {
      uncertain = true;
      warnings.add('文字認識の確信度が低い');
    }
    if (substituted) {
      uncertain = true;
      warnings.add('数値に紛らわしい文字（O/I/S/カンマ）が含まれていた');
    }
    if (prefix != null) {
      warnings.add('「$prefix」付きの値（検出限界など）');
    }
    if (extraNumbers > 0) {
      uncertain = true;
      warnings.add('同じ行に数値が多く、列の取り違えの可能性');
    }

    if (def != null) {
      // 単位換算
      if (unit != null && normalizeName(unit!) != normalizeName(def.unit)) {
        AltUnit? alt;
        for (final a in def.altUnits) {
          if (normalizeName(a.unit) == normalizeName(unit!)) alt = a;
        }
        if (alt != null) {
          if (alt.factor != 1) {
            warnings.add('単位換算: ${_f(v)} ${alt.unit} → ${formatNumber(v * alt.factor, def.decimals)} ${def.unit}');
            v = v * alt.factor;
            if (lo != null) lo = lo * alt.factor;
            if (hi != null) hi = hi * alt.factor;
          }
          u = def.unit;
        } else if (!_unitLooksSame(unit!, def.unit)) {
          uncertain = true;
          warnings.add('単位「$unit」が標準（${def.unit}）と異なる可能性');
        } else {
          u = def.unit;
        }
      } else {
        u = def.unit;
      }
      // 単位なしで桁が合わない場合（例: WBC 6.5 → ×10³/μL）
      var issue = catalog.checkPlausibility(code, v);
      // 危険値を大きく超える場合も、別単位（例: PLT 235 ×10³/μL）の可能性を検討
      final suspicious = issue != null || (def.critHigh != null && v > def.critHigh! * 1.5);
      if (suspicious && unit == null) {
        for (final a in def.altUnits) {
          final c = v * a.factor;
          if (catalog.checkPlausibility(code, c) == null && a.factor != 1) {
            final inRef = def.low == null || def.high == null || (c >= def.low! * 0.2 && c <= def.high! * 5);
            if (inRef) {
              warnings.add('単位が ${a.unit} と推定し換算: ${_f(v)} → ${formatNumber(c, def.decimals)} ${def.unit}');
              v = c;
              if (lo != null) lo = lo * a.factor;
              if (hi != null) hi = hi * a.factor;
              uncertain = true;
              issue = null;
              break;
            }
          }
        }
      }
      if (issue != null) {
        uncertain = true;
        warnings.add(issue.message);
      }
      // 用紙の基準値がおかしい場合は採用しない
      if (lo != null && hi != null && lo > hi) {
        lo = null;
        hi = null;
      }
    }

    return LabValue(
      code: code,
      value: v,
      unit: u,
      rawText: raw,
      sheetLow: lo,
      sheetHigh: hi,
      sheetFlag: flag,
      uncertain: uncertain,
      warnings: warnings,
    );
  }

  static bool _unitLooksSame(String a, String b) {
    String n(String s) => normalizeName(s).replaceAll('Μ', 'U').replaceAll('µ'.toUpperCase(), 'U').replaceAll('⁴', '4').replaceAll('^', '');
    return n(a) == n(b);
  }

  static String _f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// 用紙の「動脈血」「静脈血」などの記載を探す。
SpecimenType? detectSpecimenLabel(String text) {
  final t = toHalfWidth(text);
  final a = RegExp(r'(動脈血|動脈|ARTERIAL|\bABG\b|Aライン|\bART\b|検体\s*[:：]?\s*A\b|PaO2|PaCO2|SaO2)', caseSensitive: false).hasMatch(t);
  final v = RegExp(r'(静脈血|静脈|VENOUS|\bVBG\b|\bVEN\b|検体\s*[:：]?\s*V\b|PvO2|PvCO2|SvO2)', caseSensitive: false).hasMatch(t);
  if (a && !v) return SpecimenType.arterial;
  if (v && !a) return SpecimenType.venous;
  return null;
}

/// 酸素投与に関する記載を探す。
OxygenInfo detectOxygen(String text) {
  final t = toHalfWidth(text);
  final found = <String>[];
  String? device;
  double? flow;
  double? fio2;

  void add(Match m) {
    final s = m.group(0)!.trim();
    if (!found.contains(s)) found.add(s);
  }

  final fio2Re = RegExp(r'F\s*I\s*O\s*2\s*[:：=]?\s*(\d+(?:\.\d+)?)\s*(%)?', caseSensitive: false);
  for (final m in fio2Re.allMatches(t)) {
    add(m);
    final x = double.parse(m.group(1)!);
    final f = x > 1 ? x / 100 : x;
    if (f >= 0.21 && f <= 1.0) fio2 ??= f;
  }
  final flowRe = RegExp(r'(?:(?<![A-Za-z])O2|酸素)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:L|ℓ|l|リットル)(?![A-Za-z])(?:\s*/\s*(?:min|分)|pm|PM)?', caseSensitive: false);
  for (final m in flowRe.allMatches(t)) {
    add(m);
    flow ??= double.parse(m.group(1)!);
  }
  final flowRe2 = RegExp(r'(\d+(?:\.\d+)?)\s*(?:L|ℓ)\s*/\s*(?:min|分)', caseSensitive: false);
  for (final m in flowRe2.allMatches(t)) {
    add(m);
    flow ??= double.parse(m.group(1)!);
  }
  final o2pct = RegExp(r'(?:(?<![A-Za-z])O2|酸素)\s*[:：]?\s*(\d{2,3})\s*%', caseSensitive: false);
  for (final m in o2pct.allMatches(t)) {
    add(m);
    final x = double.parse(m.group(1)!);
    if (x >= 21 && x <= 100) fio2 ??= x / 100;
  }
  final devices = <String, RegExp>{
    '室内気': RegExp(r'(室内気|ROOM\s*AIR|\bR\.?A\.?\b|大気下|自発呼吸\(?RA)', caseSensitive: false),
    '鼻カヌラ': RegExp(r'(鼻カ[ヌニ]ュ?ー?[ラレ]|カ[ヌニ]ュ?ー?[ラレ]|NASAL\s*CANNULA|\bNC\b)', caseSensitive: false),
    'リザーバーマスク': RegExp(r'(リザーバ|RESERVOIR|NRBM|ノンリブリーザー)', caseSensitive: false),
    'ベンチュリーマスク': RegExp(r'(ベンチュリ|VENTURI)', caseSensitive: false),
    'ハイフロー': RegExp(r'(HFNC|ハイフロー|HIGH\s*FLOW|ネーザルハイ)', caseSensitive: false),
    'NPPV': RegExp(r'(NPPV|\bNIV\b|BIPAP|CPAP)', caseSensitive: false),
    '人工呼吸器': RegExp(r'(人工呼吸|挿管|VENTILATOR|\bIPPV\b|SIMV|\bA/C\b|\bPCV\b|\bVCV\b)', caseSensitive: false),
    '簡易マスク': RegExp(r'(マスク|\bMASK\b)', caseSensitive: false),
  };
  for (final e in devices.entries) {
    final m = e.value.firstMatch(t);
    if (m != null) {
      add(m);
      device ??= e.key;
    }
  }
  if (device == '室内気') fio2 ??= 0.21;
  return OxygenInfo(foundTexts: found, device: device, flowLpm: flow, fio2: fio2);
}
