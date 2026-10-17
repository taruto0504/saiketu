import 'dart:convert';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import 'clinical_calc.dart';
import 'lab_catalog.dart';

/// 判定ルール（JSONで定義。assets/rules/disease_rules.json）。
///
/// 条件の書式（"t" で種類を指定）:
///   {"t":"lab","item":"CRE","op":"high"}               … 項目の判定（high/low/normal/abnormal/crit/present）
///   {"t":"lab","item":"CRE","op":"gt","value":2}        … 数値比較（gt/ge/lt/le/between）
///   {"t":"lab","item":"AST","op":"gtx","value":3}       … 基準上限の何倍を超えるか（ltx: 下限の何倍未満か）
///   {"t":"lab","item":"BUN_CRE","op":"gt","value":20}   … 計算値（BUN_CRE, AST_ALT, AG_CALC, PF など）も同様
///   {"t":"delta","item":"CRE","op":"rise","value":0.3}  … 前回値からの変化（rise/fall/rise_ratio/fall_pct）
///   {"t":"fio2","op":"le","value":0.21}                 … 用紙・入力の FiO2
///   {"t":"specimen","value":"A"}                        … 検体種別（A/V）
///   {"t":"ctx","field":"temp","op":"ge","value":38}     … 追加情報（第2段階のみ。age/temp/sbp/dbp/hr/rr/spo2/gcs/jcs/weight）
///   {"t":"sex","value":"F"}                             … 性別（第2段階のみ）
///   {"t":"kw","field":"symptoms","any":["胸痛"]}         … 追加情報の語句（symptoms/history/meds/course/other/any）
///   {"t":"any","of":[...]} / {"t":"all","of":[...]} / {"t":"not","of":[...]}
class RuleSet {
  RuleSet({required this.version, required this.diseases, required this.sampleChecks});

  final String version;
  final List<DiseaseRule> diseases;
  final List<SampleCheck> sampleChecks;

  factory RuleSet.fromJsonString(String s) => RuleSet.fromJson(jsonDecode(s) as Map<String, dynamic>);

  factory RuleSet.fromJson(Map<String, dynamic> j) => RuleSet(
        version: (j['version'] ?? '').toString(),
        diseases: ((j['diseases'] as List?) ?? const []).map((e) => DiseaseRule.fromJson(e as Map<String, dynamic>)).toList(),
        sampleChecks: ((j['sampleChecks'] as List?) ?? const []).map((e) => SampleCheck.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Finding {
  Finding(this.cond, this.weight, this.note);
  final Cond cond;
  final double weight;
  final String? note;

  factory Finding.fromJson(Map<String, dynamic> j) =>
      Finding(Cond.fromJson(j['if'] as Map<String, dynamic>), (j['w'] as num?)?.toDouble() ?? 1, j['note'] as String?);
}

class DiseaseRule {
  DiseaseRule({
    required this.id,
    required this.name,
    required this.category,
    required this.gate,
    required this.gateWeight,
    required this.gateNote,
    required this.findings,
    required this.against,
    required this.tests,
    required this.wantItems,
    required this.minScore,
    this.alert,
  });

  final String id;
  final String name;
  final String category;
  final Cond gate;
  final double gateWeight;
  final String? gateNote;
  final List<Finding> findings;
  final List<Finding> against;
  final List<String> tests;

  /// 未測定なら「追加で確認したい検査」に挙げる項目コード。
  final List<String> wantItems;
  final double minScore;
  final String? alert;

  factory DiseaseRule.fromJson(Map<String, dynamic> j) => DiseaseRule(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        gate: Cond.fromJson(j['gate'] as Map<String, dynamic>),
        gateWeight: (j['gateWeight'] as num?)?.toDouble() ?? 2,
        gateNote: j['gateNote'] as String?,
        findings: ((j['findings'] as List?) ?? const []).map((e) => Finding.fromJson(e as Map<String, dynamic>)).toList(),
        against: ((j['against'] as List?) ?? const []).map((e) => Finding.fromJson(e as Map<String, dynamic>)).toList(),
        tests: ((j['tests'] as List?) ?? const []).cast<String>(),
        wantItems: ((j['want'] as List?) ?? const []).cast<String>(),
        minScore: (j['minScore'] as num?)?.toDouble() ?? 2,
        alert: j['alert'] as String?,
      );
}

class SampleCheck {
  SampleCheck(this.id, this.name, this.cond, this.message);
  final String id;
  final String name;
  final Cond cond;
  final String message;

  factory SampleCheck.fromJson(Map<String, dynamic> j) =>
      SampleCheck(j['id'] as String, j['name'] as String, Cond.fromJson(j['if'] as Map<String, dynamic>), j['message'] as String);
}

/// 条件にマッチしたときの根拠。
class Hit {
  Hit(this.texts, {this.fromContext = false});
  final List<String> texts;
  final bool fromContext;
}

/// 評価に必要な情報一式。
class EvalEnv {
  EvalEnv({
    required this.catalog,
    required this.current,
    this.previous,
    required this.useContext,
  })  : values = current.valueMap,
        derived = computeDerived(current),
        prevValues = previous?.valueMap ?? const {},
        specimen = effectiveSpecimen(current),
        estimate = estimateSpecimen(current),
        fio2 = resolveFio2(current.oxygen).fio2;

  final LabCatalog catalog;
  final LabSet current;
  final LabSet? previous;
  final bool useContext;
  final Map<String, double> values;
  final Map<String, DerivedValue> derived;
  final Map<String, double> prevValues;
  final SpecimenType specimen;
  final SpecimenEstimate estimate;
  final double? fio2;

  PatientContext get ctx => current.context;
  String? get sex => useContext ? ctx.sex : null;

  double? value(String code) => values[code] ?? derived[code]?.value;

  LabValue? labValue(String code) => current.valueOf(code);

  LabFlag flag(String code) {
    final lv = labValue(code);
    if (lv != null) return catalog.flagFor(lv, sex: sex, specimen: specimen);
    final d = derived[code];
    if (d != null) return catalog.flagFor(LabValue(code: code, value: d.value), sex: sex, specimen: specimen);
    return LabFlag.unknown;
  }

  RefRange range(String code) {
    final lv = labValue(code) ?? LabValue(code: code, value: value(code));
    return catalog.rangeFor(lv, sex: sex, specimen: specimen);
  }

  String label(String code) => catalog.byCode(code)?.name ?? derived[code]?.label ?? code;

  String fmt(String code, double v) {
    final def = catalog.byCode(code);
    if (def != null) return def.formatValue(v);
    return formatNumber(v, derived[code]?.decimals ?? 1);
  }

  String unit(String code) => catalog.byCode(code)?.unit ?? derived[code]?.unit ?? '';

  /// 「Cre 2.30 mg/dL（基準 0.46–1.07）↑」形式の説明。
  String describe(String code) {
    final v = value(code);
    if (v == null) return '${label(code)} 未測定';
    final def = catalog.byCode(code);
    final f = flag(code);
    final arrow = f.isHigh ? '↑' : (f.isLow ? '↓' : '');
    final r = range(code);
    final u = unit(code);
    final rs = r.isEmpty || def == null ? '' : '（基準 ${r.formatFor(def)}）';
    return '${label(code)} ${fmt(code, v)}${u.isEmpty ? '' : ' $u'}$rs$arrow';
  }
}

abstract class Cond {
  Hit? eval(EvalEnv env);

  /// 追加情報（第2段階）を使う条件か。
  bool get usesContext => false;

  static Cond fromJson(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'lab':
        return LabCond(j['item'] as String, j['op'] as String, (j['value'] as num?)?.toDouble(), (j['value2'] as num?)?.toDouble());
      case 'delta':
        return DeltaCond(j['item'] as String, j['op'] as String, (j['value'] as num).toDouble());
      case 'fio2':
        return Fio2Cond(j['op'] as String, (j['value'] as num).toDouble());
      case 'specimen':
        return SpecimenCond(j['value'] as String);
      case 'ctx':
        return CtxCond(j['field'] as String, j['op'] as String, (j['value'] as num).toDouble());
      case 'sex':
        return SexCond(j['value'] as String);
      case 'kw':
        return KeywordCond(j['field'] as String, ((j['any'] as List?) ?? const []).cast<String>());
      case 'any':
        return AnyCond(((j['of'] as List?) ?? const []).map((e) => Cond.fromJson(e as Map<String, dynamic>)).toList());
      case 'all':
        return AllCond(((j['of'] as List?) ?? const []).map((e) => Cond.fromJson(e as Map<String, dynamic>)).toList());
      case 'not':
        return NotCond(((j['of'] as List?) ?? const []).map((e) => Cond.fromJson(e as Map<String, dynamic>)).toList());
      default:
        throw FormatException('未知の条件タイプ: ${j['t']}');
    }
  }
}

bool _cmp(double x, String op, double? a, double? b) {
  switch (op) {
    case 'gt':
      return x > a!;
    case 'ge':
      return x >= a!;
    case 'lt':
      return x < a!;
    case 'le':
      return x <= a!;
    case 'eq':
      return x == a!;
    case 'between':
      return x >= a! && x <= b!;
    default:
      return false;
  }
}

class LabCond extends Cond {
  LabCond(this.item, this.op, this.a, this.b);
  final String item;
  final String op;
  final double? a;
  final double? b;

  @override
  Hit? eval(EvalEnv env) {
    final v = env.value(item);
    if (v == null) return null;
    bool ok;
    switch (op) {
      case 'present':
        ok = true;
      case 'high':
        ok = env.flag(item).isHigh;
      case 'low':
        ok = env.flag(item).isLow;
      case 'normal':
        ok = env.flag(item) == LabFlag.normal;
      case 'abnormal':
        ok = env.flag(item).isAbnormal;
      case 'crit':
        ok = env.flag(item).isCritical;
      case 'gtx':
        final h = env.range(item).high;
        ok = h != null && v > h * a!;
      case 'ltx':
        final l = env.range(item).low;
        ok = l != null && v < l * a!;
      default:
        ok = _cmp(v, op, a, b);
    }
    if (!ok) return null;
    var text = env.describe(item);
    if (op == 'gtx') {
      final h = env.range(item).high;
      if (h != null && h > 0) text += '（上限の${(v / h).toStringAsFixed(1)}倍）';
    }
    return Hit([text]);
  }
}

class DeltaCond extends Cond {
  DeltaCond(this.item, this.op, this.a);
  final String item;
  final String op;
  final double a;

  @override
  Hit? eval(EvalEnv env) {
    final cur = env.values[item];
    final prev = env.prevValues[item];
    if (cur == null || prev == null) return null;
    bool ok;
    switch (op) {
      case 'rise':
        ok = cur - prev >= a;
      case 'fall':
        ok = prev - cur >= a;
      case 'rise_ratio':
        ok = prev > 0 && cur / prev >= a;
      case 'fall_pct':
        ok = prev > 0 && (prev - cur) / prev * 100 >= a;
      default:
        ok = false;
    }
    if (!ok) return null;
    final d = cur - prev;
    final sign = d >= 0 ? '+' : '−';
    return Hit(['${env.label(item)} 前回${env.fmt(item, prev)}→今回${env.fmt(item, cur)}（$sign${env.fmt(item, d.abs())}）']);
  }
}

class Fio2Cond extends Cond {
  Fio2Cond(this.op, this.a);
  final String op;
  final double a;

  @override
  Hit? eval(EvalEnv env) {
    final f = env.fio2;
    if (f == null || !_cmp(f, op, a, null)) return null;
    return Hit([f <= 0.21 ? '室内気（FiO2 0.21）' : 'FiO2 ${f.toStringAsFixed(2)}']);
  }
}

class SpecimenCond extends Cond {
  SpecimenCond(this.v);
  final String v;

  @override
  Hit? eval(EvalEnv env) {
    if (env.estimate.type == SpecimenType.unknown && !hasBloodGas(env.values)) return null;
    if (env.specimen.short != v) return null;
    return Hit(['検体: ${env.specimen.label}${env.estimate.fromSheet || env.estimate.manual ? '' : '（推定）'}']);
  }
}

class CtxCond extends Cond {
  CtxCond(this.field, this.op, this.a);
  final String field;
  final String op;
  final double a;

  @override
  bool get usesContext => true;

  static const labels = {
    'age': ('年齢', '歳'),
    'temp': ('体温', '℃'),
    'sbp': ('収縮期血圧', 'mmHg'),
    'dbp': ('拡張期血圧', 'mmHg'),
    'hr': ('脈拍', '/分'),
    'rr': ('呼吸数', '/分'),
    'spo2': ('SpO2', '%'),
    'gcs': ('GCS', ''),
    'jcs': ('JCS', ''),
    'weight': ('体重', 'kg'),
  };

  static double? jcsValue(String? s) {
    if (s == null) return null;
    final t = s.toUpperCase().replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(t);
  }

  @override
  Hit? eval(EvalEnv env) {
    if (!env.useContext) return null;
    final c = env.ctx;
    final double? x = switch (field) {
      'age' => c.age?.toDouble(),
      'temp' => c.temp,
      'sbp' => c.sbp?.toDouble(),
      'dbp' => c.dbp?.toDouble(),
      'hr' => c.hr?.toDouble(),
      'rr' => c.rr?.toDouble(),
      'spo2' => c.spo2?.toDouble(),
      'gcs' => c.gcs?.toDouble(),
      'jcs' => jcsValue(c.jcs),
      'weight' => c.weightKg,
      _ => null,
    };
    if (x == null || !_cmp(x, op, a, null)) return null;
    final l = labels[field] ?? (field, '');
    final xs = x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toString();
    return Hit(['${l.$1} $xs${l.$2}'], fromContext: true);
  }
}

class SexCond extends Cond {
  SexCond(this.v);
  final String v;

  @override
  bool get usesContext => true;

  @override
  Hit? eval(EvalEnv env) {
    if (!env.useContext || env.ctx.sex != v) return null;
    return Hit([v == 'M' ? '男性' : '女性'], fromContext: true);
  }
}

class KeywordCond extends Cond {
  KeywordCond(this.field, this.keywords);
  final String field;
  final List<String> keywords;

  @override
  bool get usesContext => true;

  static const fieldLabels = {
    'symptoms': '症状',
    'history': '既往歴',
    'meds': '内服薬',
    'course': '経過',
    'other': 'その他検査',
    'any': '追加情報',
  };

  @override
  Hit? eval(EvalEnv env) {
    if (!env.useContext) return null;
    final c = env.ctx;
    final text = switch (field) {
      'symptoms' => '${c.symptoms.join(' ')} ${c.complaint}',
      'history' => c.history,
      'meds' => c.medications,
      'course' => c.course,
      'other' => c.otherTests,
      _ => '${c.symptoms.join(' ')} ${c.complaint} ${c.history} ${c.medications} ${c.course} ${c.otherTests}',
    }
        .toLowerCase();
    if (text.trim().isEmpty) return null;
    for (final k in keywords) {
      if (text.contains(k.toLowerCase())) {
        return Hit(['${fieldLabels[field] ?? field}に「$k」'], fromContext: true);
      }
    }
    return null;
  }
}

class AnyCond extends Cond {
  AnyCond(this.of);
  final List<Cond> of;

  @override
  bool get usesContext => of.any((c) => c.usesContext);

  @override
  Hit? eval(EvalEnv env) {
    for (final c in of) {
      final h = c.eval(env);
      if (h != null) return h;
    }
    return null;
  }
}

class AllCond extends Cond {
  AllCond(this.of);
  final List<Cond> of;

  @override
  bool get usesContext => of.any((c) => c.usesContext);

  @override
  Hit? eval(EvalEnv env) {
    final texts = <String>[];
    var ctx = false;
    for (final c in of) {
      final h = c.eval(env);
      if (h == null) return null;
      texts.addAll(h.texts);
      ctx = ctx || h.fromContext;
    }
    return Hit(texts, fromContext: ctx);
  }
}

class NotCond extends Cond {
  NotCond(this.of);
  final List<Cond> of;

  @override
  Hit? eval(EvalEnv env) {
    for (final c in of) {
      if (c.eval(env) != null) return null;
    }
    return Hit(const []);
  }
}

// ───────── 結果 ─────────

class Evidence {
  Evidence(this.text, this.weight, {this.note, this.fromContext = false});
  final String text;
  final double weight;
  final String? note;
  final bool fromContext;

  String get key => '$text|${note ?? ''}';

  Map<String, dynamic> toJson() => {'text': text, 'w': weight, if (note != null) 'note': note, if (fromContext) 'ctx': true};

  factory Evidence.fromJson(Map<String, dynamic> j) =>
      Evidence(j['text'] as String, (j['w'] as num).toDouble(), note: j['note'] as String?, fromContext: (j['ctx'] as bool?) ?? false);
}

class DiseaseResult {
  DiseaseResult({
    required this.id,
    required this.name,
    required this.category,
    required this.score,
    required this.support,
    required this.against,
    required this.tests,
    this.alert,
  });

  final String id;
  final String name;
  final String category;
  final double score;
  final List<Evidence> support;
  final List<Evidence> against;
  final List<String> tests;
  final String? alert;

  String get likelihood => score >= 7 ? '高' : (score >= 4 ? '中' : '低');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'score': score,
        'support': support.map((e) => e.toJson()).toList(),
        'against': against.map((e) => e.toJson()).toList(),
        'tests': tests,
        if (alert != null) 'alert': alert,
      };

  factory DiseaseResult.fromJson(Map<String, dynamic> j) => DiseaseResult(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        score: (j['score'] as num).toDouble(),
        support: ((j['support'] as List?) ?? const []).map((e) => Evidence.fromJson(e as Map<String, dynamic>)).toList(),
        against: ((j['against'] as List?) ?? const []).map((e) => Evidence.fromJson(e as Map<String, dynamic>)).toList(),
        tests: ((j['tests'] as List?) ?? const []).cast<String>(),
        alert: j['alert'] as String?,
      );
}

class SampleWarning {
  SampleWarning(this.name, this.message, this.evidence);
  final String name;
  final String message;
  final List<String> evidence;

  Map<String, dynamic> toJson() => {'name': name, 'message': message, 'evidence': evidence};
  factory SampleWarning.fromJson(Map<String, dynamic> j) =>
      SampleWarning(j['name'] as String, j['message'] as String, ((j['evidence'] as List?) ?? const []).cast<String>());
}

class EvaluationResult {
  EvaluationResult({
    String? id,
    required this.at,
    required this.stage,
    required this.diseases,
    required this.sampleWarnings,
    required this.contextUsed,
    this.comparedWithPrevious = false,
    this.rulesVersion = '',
  }) : id = id ?? newId();

  final String id;
  final DateTime at;

  /// 1 = 採血データのみ、2 = 追加情報を含む。
  final int stage;
  final List<DiseaseResult> diseases;
  final List<SampleWarning> sampleWarnings;
  final Map<String, String> contextUsed;
  final bool comparedWithPrevious;
  final String rulesVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'stage': stage,
        'diseases': diseases.map((e) => e.toJson()).toList(),
        'sample': sampleWarnings.map((e) => e.toJson()).toList(),
        'context': contextUsed,
        'prev': comparedWithPrevious,
        'rules': rulesVersion,
      };

  factory EvaluationResult.fromJson(Map<String, dynamic> j) => EvaluationResult(
        id: j['id'] as String?,
        at: DateTime.parse(j['at'] as String),
        stage: (j['stage'] as num).toInt(),
        diseases: ((j['diseases'] as List?) ?? const []).map((e) => DiseaseResult.fromJson(e as Map<String, dynamic>)).toList(),
        sampleWarnings: ((j['sample'] as List?) ?? const []).map((e) => SampleWarning.fromJson(e as Map<String, dynamic>)).toList(),
        contextUsed: ((j['context'] as Map?) ?? const {}).cast<String, String>(),
        comparedWithPrevious: (j['prev'] as bool?) ?? false,
        rulesVersion: (j['rules'] as String?) ?? '',
      );
}

/// ルールベースの疾患推定エンジン（端末内で完結）。
class RuleEngine {
  RuleEngine(this.rules, this.catalog);
  final RuleSet rules;
  final LabCatalog catalog;

  /// 同じ値の根拠は1行にまとめる（注釈を連結）。
  static void _addEvidence(List<Evidence> list, Evidence e) {
    final i = list.indexWhere((x) => x.text == e.text);
    if (i < 0) {
      list.add(e);
      return;
    }
    final old = list[i];
    final notes = [old.note, e.note].whereType<String>().join(' / ');
    list[i] = Evidence(old.text, old.weight + e.weight, note: notes.isEmpty ? null : notes, fromContext: old.fromContext || e.fromContext);
  }

  EvaluationResult evaluate(LabSet current, {LabSet? previous, bool useContext = false}) {
    final env = EvalEnv(catalog: catalog, current: current, previous: previous, useContext: useContext);
    final results = <DiseaseResult>[];
    for (final r in rules.diseases) {
      final gate = r.gate.eval(env);
      if (gate == null) continue;
      final support = <Evidence>[
        Evidence(gate.texts.join('、'), r.gateWeight, note: r.gateNote, fromContext: gate.fromContext),
      ];
      var score = r.gateWeight;
      for (final f in r.findings) {
        final h = f.cond.eval(env);
        if (h == null || h.texts.isEmpty) continue;
        _addEvidence(support, Evidence(h.texts.join('、'), f.weight, note: f.note, fromContext: h.fromContext));
        score += f.weight;
      }
      final against = <Evidence>[];
      for (final f in r.against) {
        final h = f.cond.eval(env);
        if (h == null || h.texts.isEmpty) continue;
        _addEvidence(against, Evidence(h.texts.join('、'), f.weight, note: f.note, fromContext: h.fromContext));
        score -= f.weight;
      }
      if (score < r.minScore) continue;
      final tests = <String>[
        for (final c in r.wantItems)
          if (env.value(c) == null) '${catalog.byCode(c)?.name ?? c}（未測定）',
        ...r.tests,
      ];
      results.add(DiseaseResult(
        id: r.id,
        name: r.name,
        category: r.category,
        score: score,
        support: support,
        against: against,
        tests: tests,
        alert: r.alert,
      ));
    }
    results.sort((a, b) => b.score.compareTo(a.score));

    final warnings = <SampleWarning>[];
    for (final s in rules.sampleChecks) {
      final h = s.cond.eval(env);
      if (h != null) warnings.add(SampleWarning(s.name, s.message, h.texts));
    }
    return EvaluationResult(
      at: DateTime.now(),
      stage: useContext && !current.context.isEmpty ? 2 : 1,
      diseases: results,
      sampleWarnings: warnings,
      contextUsed: useContext ? current.context.describe() : const {},
      comparedWithPrevious: previous != null,
      rulesVersion: rules.version,
    );
  }
}

// ───────── 再評価の差分 ─────────

enum RankChange { up, down, same, newEntry }

class DiseaseDiff {
  DiseaseDiff(this.result, this.change, this.prevRank, this.rank, this.added, this.removed);
  final DiseaseResult result;
  final RankChange change;
  final int? prevRank;
  final int rank;

  /// 今回新たに加わった根拠・否定的所見（評価を変えた要因）。
  final List<Evidence> added;
  final List<Evidence> removed;
}

class EvaluationDiff {
  EvaluationDiff(this.items, this.dropped);
  final List<DiseaseDiff> items;
  final List<DiseaseResult> dropped;
}

EvaluationDiff diffEvaluations(EvaluationResult? prev, EvaluationResult cur) {
  final prevRank = <String, int>{};
  final prevById = <String, DiseaseResult>{};
  if (prev != null) {
    for (var i = 0; i < prev.diseases.length; i++) {
      prevRank[prev.diseases[i].id] = i + 1;
      prevById[prev.diseases[i].id] = prev.diseases[i];
    }
  }
  final items = <DiseaseDiff>[];
  for (var i = 0; i < cur.diseases.length; i++) {
    final d = cur.diseases[i];
    final pr = prevRank[d.id];
    final rank = i + 1;
    RankChange ch;
    if (prev == null) {
      ch = RankChange.same;
    } else if (pr == null) {
      ch = RankChange.newEntry;
    } else if (rank < pr) {
      ch = RankChange.up;
    } else if (rank > pr) {
      ch = RankChange.down;
    } else {
      ch = RankChange.same;
    }
    final p = prevById[d.id];
    final added = <Evidence>[];
    final removed = <Evidence>[];
    if (prev != null) {
      final before = {...?p?.support.map((e) => e.key), ...?p?.against.map((e) => e.key)};
      final now = {...d.support.map((e) => e.key), ...d.against.map((e) => e.key)};
      for (final e in [...d.support, ...d.against]) {
        if (!before.contains(e.key)) added.add(e);
      }
      for (final e in [...?p?.support, ...?p?.against]) {
        if (!now.contains(e.key)) removed.add(e);
      }
    }
    items.add(DiseaseDiff(d, ch, pr, rank, added, removed));
  }
  final curIds = cur.diseases.map((e) => e.id).toSet();
  final dropped = prev?.diseases.where((d) => !curIds.contains(d.id)).toList() ?? const <DiseaseResult>[];
  return EvaluationDiff(items, dropped);
}
