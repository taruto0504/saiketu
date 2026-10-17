/// 検査項目の定義（項目マスタ）。
library;

enum LabCategory {
  cbc('血算'),
  coag('凝固'),
  liver('肝胆膵'),
  renal('腎・電解質'),
  protein('蛋白・炎症'),
  metabolic('代謝・内分泌'),
  lipid('脂質'),
  cardiac('心筋'),
  gas('血液ガス'),
  urine('尿検査'),
  sputum('喀痰検査'),
  other('その他'),
  custom('追加項目');

  const LabCategory(this.label);
  final String label;

  static LabCategory fromName(String? n) =>
      LabCategory.values.firstWhere((c) => c.name == n, orElse: () => LabCategory.custom);
}

/// 別の単位で記載されていた場合の換算（value * factor = 標準単位）。
class AltUnit {
  const AltUnit(this.unit, this.factor);
  final String unit;
  final double factor;
}

/// 定性・半定量の結果（−、±、1+ や Class III など）。value の大小で判定する。
class Ordinal {
  const Ordinal(this.value, this.label, [this.aliases = const []]);
  final double value;
  final String label;

  /// 用紙での別の書き方（(−)、陰性、++ など）。
  final List<String> aliases;
}

/// 試験紙法の一般的な段階（−、±、1+〜4+）。
const qualitativeScale = [
  Ordinal(0, '−', ['-', '(-)', '陰性', 'NEG', 'NEGATIVE', 'N']),
  Ordinal(0.5, '±', ['(±)', '+-', '+/-', '弱陽性', '偽陽性']),
  Ordinal(1, '1+', ['(1+)', '+', '(+)', '陽性', 'POS', 'POSITIVE', '少数', '少量']),
  Ordinal(2, '2+', ['(2+)', '++', '(++)', '中等量']),
  Ordinal(3, '3+', ['(3+)', '+++', '(+++)', '多数', '多量']),
  Ordinal(4, '4+', ['(4+)', '++++', '(++++)']),
];

class LabItemDef {
  const LabItemDef({
    required this.code,
    required this.name,
    required this.jpName,
    required this.category,
    required this.unit,
    this.low,
    this.high,
    this.lowM,
    this.highM,
    this.lowF,
    this.highF,
    this.venousLow,
    this.venousHigh,
    this.critLow,
    this.critHigh,
    this.plausLow,
    this.plausHigh,
    this.aliases = const [],
    this.decimals = 1,
    this.altUnits = const [],
    this.isCustom = false,
    this.isGas = false,
    this.rangeNote,
    this.ordinals = const [],
    this.sectionAliases = const [],
  });

  /// 内部コード（例: CRE）。
  final String code;

  /// 表示名（例: Cre）。
  final String name;

  /// 日本語名（例: クレアチニン）。
  final String jpName;
  final LabCategory category;
  final String unit;

  /// 既定の基準値（性別不明時）。
  final double? low;
  final double? high;
  final double? lowM;
  final double? highM;
  final double? lowF;
  final double? highF;

  /// 静脈血の基準値（血液ガス項目のみ）。
  final double? venousLow;
  final double? venousHigh;

  /// 危険値（パニック値）。
  final double? critLow;
  final double? critHigh;

  /// 生理的にありうる範囲。外れたら誤読を疑う。
  final double? plausLow;
  final double? plausHigh;
  final List<String> aliases;
  final int decimals;
  final List<AltUnit> altUnits;
  final bool isCustom;
  final bool isGas;
  final String? rangeNote;

  /// 定性・半定量の段階。空なら数値の項目。
  final List<Ordinal> ordinals;

  /// 尿検査・喀痰検査の欄の中でだけ使う別名（例: 尿検査欄の「蛋白」「pH」「Na」）。
  final List<String> sectionAliases;

  String get displayName => name;

  bool get isQualitative => ordinals.isNotEmpty;

  /// 表示用の値（定性の項目は 1+ などの段階、それ以外は数値）。
  String formatValue(double v) {
    for (final o in ordinals) {
      if (o.value == v) return o.label;
    }
    return formatNumber(v, decimals);
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'jpName': jpName,
        'category': category.name,
        'unit': unit,
        'low': low,
        'high': high,
        'critLow': critLow,
        'critHigh': critHigh,
        'plausLow': plausLow,
        'plausHigh': plausHigh,
        'aliases': aliases,
        'decimals': decimals,
      };

  factory LabItemDef.fromJson(Map<String, dynamic> j) => LabItemDef(
        code: j['code'] as String,
        name: j['name'] as String,
        jpName: (j['jpName'] as String?) ?? '',
        category: LabCategory.fromName(j['category'] as String?),
        unit: (j['unit'] as String?) ?? '',
        low: (j['low'] as num?)?.toDouble(),
        high: (j['high'] as num?)?.toDouble(),
        critLow: (j['critLow'] as num?)?.toDouble(),
        critHigh: (j['critHigh'] as num?)?.toDouble(),
        plausLow: (j['plausLow'] as num?)?.toDouble(),
        plausHigh: (j['plausHigh'] as num?)?.toDouble(),
        aliases: ((j['aliases'] as List?) ?? const []).cast<String>(),
        decimals: (j['decimals'] as num?)?.toInt() ?? 1,
        isCustom: true,
      );
}

/// 基準値の範囲。
class RefRange {
  const RefRange(this.low, this.high, {this.source = RefSource.defaults});
  final double? low;
  final double? high;
  final RefSource source;

  bool get isEmpty => low == null && high == null;

  /// 項目に合わせた表示（定性の項目は「−〜±」のように段階で）。
  String formatFor(LabItemDef? def) {
    if (def != null && def.isQualitative && def.unit.isEmpty) {
      final ok = [
        for (final o in def.ordinals)
          if ((low == null || o.value >= low!) && (high == null || o.value <= high!)) o.label
      ];
      if (ok.isNotEmpty && ok.length < def.ordinals.length) return ok.length == 1 ? ok.first : '${ok.first}〜${ok.last}';
    }
    return format(def?.decimals ?? 1);
  }

  String format(int decimals) {
    String f(double v) => formatNumber(v, decimals);
    if (low != null && high != null) return '${f(low!)}–${f(high!)}';
    if (high != null) return '≦${f(high!)}';
    if (low != null) return '≧${f(low!)}';
    return '—';
  }
}

enum RefSource {
  sheet('用紙'),
  user('設定'),
  defaults('既定');

  const RefSource(this.label);
  final String label;
}

String formatNumber(double v, int decimals) {
  if (v.abs() >= 1000 && decimals > 0 && v == v.roundToDouble()) {
    return v.toStringAsFixed(0);
  }
  var s = v.toStringAsFixed(decimals);
  if (decimals > 0 && s.contains('.')) {
    // 不要な末尾ゼロは残す（検査値は桁が意味を持つため）。ただし -0.0 は 0.0 に。
    if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  }
  return s;
}
