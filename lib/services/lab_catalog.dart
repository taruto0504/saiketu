import 'package:flutter/foundation.dart';

import '../data/lab_catalog_data.dart';
import '../models/lab_item.dart';
import '../models/lab_set.dart';

/// 判定結果。
enum LabFlag {
  normal,
  high,
  low,
  critHigh,
  critLow,
  unknown;

  bool get isHigh => this == high || this == critHigh;
  bool get isLow => this == low || this == critLow;
  bool get isCritical => this == critHigh || this == critLow;
  bool get isAbnormal => isHigh || isLow;
}

/// 全角英数字・記号・空白を半角にする。
String toHalfWidthAscii(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    if (c == 0x3000) c = 0x20;
    b.writeCharCode(c);
  }
  return b.toString();
}

/// 文字列を項目名照合用に正規化する（全角→半角、大文字化、記号・空白除去）。
String normalizeName(String s) {
  var t = toHalfWidthAscii(s).toUpperCase();
  t = t
      .replaceAll('Γ', 'G') // γ-GTP
      .replaceAll('γ'.toUpperCase(), 'G')
      .replaceAll('Β', 'B')
      .replaceAll('₂', '2')
      .replaceAll('₃', '3')
      .replaceAll('⁻', '')
      .replaceAll('Ⅲ', 'III');
  t = t.replaceAll(RegExp(r'[\s\-‐−–—_・･.,:：/()（）\[\]［］「」*＊]'), '');
  return t;
}

/// 項目マスタ（組み込み + ユーザー追加）と基準値の管理。
class LabCatalog extends ChangeNotifier {
  LabCatalog() {
    _rebuild();
  }

  final List<LabItemDef> _custom = [];

  /// ユーザーが設定した基準値（code → [low, high]）。
  final Map<String, RefRange> _userRanges = {};

  late List<LabItemDef> _all;
  late Map<String, LabItemDef> _byCode;
  late Map<String, String> _aliasIndex;
  late Map<LabCategory, Map<String, String>> _sectionIndex;
  late Map<String, String> _ocrIndex;
  late Map<String, String> _ocrExact;

  List<LabItemDef> get all => _all;
  List<LabItemDef> get customItems => List.unmodifiable(_custom);
  Map<String, RefRange> get userRanges => Map.unmodifiable(_userRanges);

  void load({required List<LabItemDef> custom, required Map<String, RefRange> userRanges}) {
    _custom
      ..clear()
      ..addAll(custom);
    _userRanges
      ..clear()
      ..addAll(userRanges);
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    _all = [...builtinLabItems, ..._custom];
    _byCode = {for (final i in _all) i.code: i};
    _aliasIndex = {};
    _sectionIndex = {LabCategory.urine: {}, LabCategory.sputum: {}};
    for (final item in _all) {
      for (final a in item.sectionAliases) {
        final k = normalizeName(a);
        if (k.isNotEmpty) _sectionIndex[item.category]?.putIfAbsent(k, () => item.code);
      }
    }
    for (final item in _all) {
      for (final a in [item.code, item.name, item.jpName, ...item.aliases]) {
        final k = normalizeName(a);
        if (k.isEmpty) continue;
        // 先に登録された（組み込み）定義を優先
        _aliasIndex.putIfAbsent(k, () => item.code);
      }
    }
    // 読み取りの紛らわしい文字を同じとみなした名前（2つ以上の項目にあたるものは使わない）
    _ocrExact = {
      for (final e in ocrAliases)
        if (_byCode.containsKey(e.value) && !_aliasIndex.containsKey(normalizeName(e.key))) normalizeName(e.key): e.value,
    };
    _ocrIndex = {};
    final amb = <String>{};
    void addOcr(String a, String code) {
      final k = ocrKey(normalizeName(a));
      if (k.length < 2) return;
      final prev = _ocrIndex[k];
      if (prev != null && prev != code) {
        amb.add(k);
      } else {
        _ocrIndex[k] = code;
      }
    }

    _aliasIndex.forEach(addOcr);
    for (final e in ocrAliases) {
      if (_byCode.containsKey(e.value)) addOcr(e.key, e.value);
    }
    amb.forEach(_ocrIndex.remove);
    _jpKeys = null;
  }

  LabItemDef? byCode(String code) => _byCode[code];

  /// 別名から項目コードを引く（例: "クレアチニン" → CRE）。
  /// [section] が尿検査・喀痰検査のときは、その欄だけの別名（「蛋白」「pH」「Na」など）を先に見る。
  /// [exact] のときは読み違いを許した照合をしない（複数の語をつないで照合するとき。「Ca L」→「CAL」→ iCa などを防ぐ）。
  String? codeForAlias(String text, {LabCategory? section, bool exact = false}) {
    final k = normalizeName(text);
    final c = (section == null ? null : _sectionIndex[section]?[k]) ?? _aliasIndex[k] ?? (exact ? null : _ocrExact[k]);
    if (c != null || exact) return c;
    // 読み取りの紛らわしい文字（0とO、1とl、bとD など）を同じとみなして、もう一度探す
    if (k.length < 2 || RegExp(r'^[\d.,]+$').hasMatch(k) || (k.length < 3 && !RegExp(r'\d').hasMatch(k))) return null;
    return _ocrIndex[ocrKey(k)];
  }

  List<MapEntry<String, String>>? _jpKeys;

  /// 日本語の項目名を、1文字の違いまで許して探す（読めなかった行の救済用。「リバパーゼ」→ リパーゼ）。
  String? fuzzyJp(String text) {
    final k = kanaKey(text);
    final jp = RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]');
    if (k.length < 3 || !jp.hasMatch(k)) return null;
    _jpKeys ??= {
      for (final d in _all)
        for (final a in [d.jpName, ...d.aliases])
          if (jp.hasMatch(a) && kanaKey(a).length >= 3) kanaKey(a): d.code,
    }.entries.toList();
    final hits = {for (final e in _jpKeys!) if (editDistance(e.key, k) <= 1) e.value};
    return hits.length == 1 ? hits.first : null;
  }

  /// 別名辞書のキー（OCRの照合用）。
  Iterable<String> get aliasKeys => _aliasIndex.keys;

  List<LabItemDef> byCategory(LabCategory c) => _all.where((i) => i.category == c).toList();

  void setUserRange(String code, RefRange? r) {
    if (r == null || r.isEmpty) {
      _userRanges.remove(code);
    } else {
      _userRanges[code] = RefRange(r.low, r.high, source: RefSource.user);
    }
    notifyListeners();
  }

  void addOrUpdateCustom(LabItemDef def) {
    _custom.removeWhere((c) => c.code == def.code);
    _custom.add(def);
    _rebuild();
    notifyListeners();
  }

  void removeCustom(String code) {
    _custom.removeWhere((c) => c.code == code);
    _rebuild();
    notifyListeners();
  }

  /// 既定の基準値（性別・検体種別を考慮）。
  RefRange defaultRange(LabItemDef def, {String? sex, SpecimenType? specimen}) {
    if (def.isGas && specimen == SpecimenType.venous && (def.venousLow != null || def.venousHigh != null)) {
      return RefRange(def.venousLow, def.venousHigh);
    }
    if (sex == 'M' && (def.lowM != null || def.highM != null)) return RefRange(def.lowM, def.highM);
    if (sex == 'F' && (def.lowF != null || def.highF != null)) return RefRange(def.lowF, def.highF);
    return RefRange(def.low, def.high);
  }

  /// 実際に使う基準値。優先順: 用紙 > 設定 > 既定。
  RefRange rangeFor(LabValue v, {String? sex, SpecimenType? specimen}) {
    if (v.sheetLow != null || v.sheetHigh != null) {
      return RefRange(v.sheetLow, v.sheetHigh, source: RefSource.sheet);
    }
    final def = byCode(v.code);
    if (def == null) return const RefRange(null, null);
    // 静脈血の場合、血液ガス項目は静脈血の基準値を使う（ユーザー設定は動脈血として扱う）
    if (def.isGas && specimen == SpecimenType.venous) {
      return defaultRange(def, sex: sex, specimen: specimen);
    }
    final u = _userRanges[v.code];
    if (u != null) return u;
    return defaultRange(def, sex: sex, specimen: specimen);
  }

  LabFlag flagFor(LabValue v, {String? sex, SpecimenType? specimen}) {
    final x = v.value;
    if (x == null) return LabFlag.unknown;
    final def = byCode(v.code);
    final r = rangeFor(v, sex: sex, specimen: specimen);
    final venous = specimen == SpecimenType.venous && (def?.isGas ?? false);
    // 静脈血では PO2/SO2 の危険値は適用しない
    final skipCrit = venous && (v.code == 'PO2' || v.code == 'SO2');
    if (def != null && !skipCrit) {
      if (def.critHigh != null && x >= def.critHigh!) return LabFlag.critHigh;
      if (def.critLow != null && x <= def.critLow!) return LabFlag.critLow;
    }
    if (r.high != null && x > r.high!) return LabFlag.high;
    if (r.low != null && x < r.low!) return LabFlag.low;
    if (r.isEmpty) {
      if (v.sheetFlag == 'H') return LabFlag.high;
      if (v.sheetFlag == 'L') return LabFlag.low;
      return LabFlag.unknown;
    }
    return LabFlag.normal;
  }

  /// 誤読チェック。ありえない値なら警告文（と推定される正しい値）を返す。
  PlausibilityIssue? checkPlausibility(String code, double value) {
    final def = byCode(code);
    if (def == null) return null;
    final lo = def.plausLow, hi = def.plausHigh;
    if (lo == null && hi == null) return null;
    final ok = (lo == null || value >= lo) && (hi == null || value <= hi);
    if (ok) return null;
    if (def.isQualitative && def.unit.isEmpty) {
      return PlausibilityIssue(
          '${def.name} の結果「${formatNumber(value, def.decimals)}」は段階（${def.ordinals.map((o) => o.label).join('・')}）として読めませんでした。原本を確認して選び直してください',
          null);
    }
    // 小数点ずれの候補を探す
    final mid = _mid(def);
    double? best;
    for (final f in const [10.0, 0.1, 100.0, 0.01, 1000.0, 0.001]) {
      final c = value * f;
      if ((lo == null || c >= lo) && (hi == null || c <= hi)) {
        if (best == null || (mid != null && (c - mid).abs() < (best - mid).abs())) best = c;
      }
    }
    final name = def.name;
    if (best != null) {
      final s = formatNumber(best, def.decimals);
      return PlausibilityIssue('$name ${_fmt(value)} はありえない値です。小数点ずれ・誤読の可能性（$s の誤りでは？）', best);
    }
    return PlausibilityIssue('$name ${_fmt(value)} はありえない値です。誤読の可能性があります', null);
  }

  double? _mid(LabItemDef d) {
    if (d.low != null && d.high != null) return (d.low! + d.high!) / 2;
    return d.high ?? d.low;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class PlausibilityIssue {
  PlausibilityIssue(this.message, this.suggestion);
  final String message;
  final double? suggestion;
}

/// 写真の読み取りで取り違えやすい文字をまとめる（項目名の照合用）。
String ocrKey(String k) => k
    .replaceAll(RegExp('[0QD]'), 'O')
    .replaceAll(RegExp(r'[1L|!Iİ]'), 'I')
    .replaceAll(RegExp(r'[5$]'), 'S')
    .replaceAll('8', 'B')
    .replaceAll('6', 'G')
    .replaceAll('Z', '2');

/// 血液ガスの印字などで、よくある読み違い。
const ocrAliases = <MapEntry<String, String>>[
  MapEntry('HET', 'HT'), MapEntry('HETHB', 'METHB'), MapEntry('NETHB', 'METHB'), MapEntry('CATT', 'ICA'),
  MapEntry('CA+T', 'ICA'), MapEntry('CAT+', 'ICA'), MapEntry('ANBAR', 'AG'), MapEntry('ANGAR', 'AG'),
  MapEntry('ANBAP', 'AG'), MapEntry('ANGAF', 'AG'), MapEntry('O2H', 'O2HB'), MapEntry('SSO2', 'SO2'),
  MapEntry('HC03ACT', 'HCO3'), MapEntry('FH', 'PH'), MapEntry('HHD', 'HHB'), MapEntry('O2HD', 'O2HB'),
  MapEntry('SU2', 'SO2'), MapEntry('K4', 'K'), MapEntry('TO2', 'TCO2'), MapEntry('卜体', 'U_KET'), MapEntry('体', 'U_KET'), MapEntry('トン体', 'U_KET'),
];

const _voiced = 'ガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ';
const _plain = 'カキクケコサシスセソタチツテトハヒフヘホハヒフヘホウかきくけこさしすせそたちつてとはひふへほはひふへほ';

/// カタカナの濁点・半濁点・長音を除いた名前（読み取りで「リパーゼ」が「リバパーゼ」になる など）。
String kanaKey(String s) {
  final b = StringBuffer();
  for (final ch in normalizeName(s).split('')) {
    if ('゛゜ーｰ‐°\'’・ﾞﾟ'.contains(ch)) continue;
    final i = _voiced.indexOf(ch);
    b.write(i >= 0 ? _plain[i] : ch);
  }
  return b.toString();
}

/// 編集距離（1文字の挿入・削除・置換を1とする）。長さが2以上違うときは 2 を返す。
int editDistance(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 2;
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0)..[0] = i);
  for (var j = 1; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final x = d[i - 1][j] + 1, y = d[i][j - 1] + 1, z = d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      d[i][j] = x < y ? (x < z ? x : z) : (y < z ? y : z);
    }
  }
  return d[a.length][b.length];
}
