import 'dart:math';

import '../models/lab_set.dart';

/// 計算値（比・ギャップなど）。
class DerivedValue {
  DerivedValue(this.code, this.label, this.value, {this.unit = '', this.formula = '', this.note, this.decimals = 1});
  final String code;
  final String label;
  final double value;
  final String unit;
  final String formula;
  final String? note;
  final int decimals;
}

/// A/V 推定結果。
class SpecimenEstimate {
  SpecimenEstimate(this.type, this.reasons, {this.fromSheet = false, this.manual = false});
  final SpecimenType type;
  final List<String> reasons;
  final bool fromSheet;
  final bool manual;

  bool get hasGas => reasons.isNotEmpty || fromSheet || manual;
}

const gasCodes = ['PH', 'PCO2', 'PO2', 'HCO3', 'BE', 'SO2', 'LAC'];

bool hasBloodGas(Map<String, double> v) => v.containsKey('PO2') || v.containsKey('PCO2') || v.containsKey('PH') || v.containsKey('SO2');

/// 血液ガスの PO2・SO2・PCO2 から動脈血/静脈血を推定する。
SpecimenEstimate estimateSpecimen(LabSet set) {
  final v = set.valueMap;
  if (set.specimen.manual != null) {
    return SpecimenEstimate(set.specimen.manual!, ['手動で${set.specimen.manual!.label}に切り替え'], manual: true);
  }
  if (set.specimen.sheetLabel != null && set.specimen.sheetLabel != SpecimenType.unknown) {
    return SpecimenEstimate(set.specimen.sheetLabel!, ['用紙に「${set.specimen.sheetLabel!.label}」の記載あり'], fromSheet: true);
  }
  if (!hasBloodGas(v)) return SpecimenEstimate(SpecimenType.unknown, []);

  var score = 0;
  final reasons = <String>[];
  final po2 = v['PO2'], so2 = v['SO2'], pco2 = v['PCO2'];
  final onO2 = (set.oxygen.fio2 ?? 0.21) > 0.21 || (set.oxygen.flowLpm ?? 0) > 0;
  if (po2 != null) {
    if (po2 >= 70) {
      score += 2;
      reasons.add('PO₂ ${po2.toStringAsFixed(0)} mmHg（≧70は動脈血に典型的）');
    } else if (po2 >= 55) {
      score += 1;
      reasons.add('PO₂ ${po2.toStringAsFixed(0)} mmHg（やや動脈血寄り）');
    } else if (po2 <= 45) {
      score -= 2;
      reasons.add('PO₂ ${po2.toStringAsFixed(0)} mmHg（≦45は静脈血に典型的${onO2 ? '。酸素投与下でも静脈血は通常低値' : ''}）');
    } else {
      reasons.add('PO₂ ${po2.toStringAsFixed(0)} mmHg（判別困難な範囲）');
    }
  }
  if (so2 != null) {
    if (so2 >= 92) {
      score += 2;
      reasons.add('SO₂ ${so2.toStringAsFixed(0)}%（≧92は動脈血に典型的）');
    } else if (so2 <= 80) {
      score -= 2;
      reasons.add('SO₂ ${so2.toStringAsFixed(0)}%（≦80は静脈血に典型的）');
    } else {
      reasons.add('SO₂ ${so2.toStringAsFixed(0)}%（判別困難な範囲）');
    }
  }
  if (pco2 != null) {
    if (pco2 >= 46 && (po2 == null || po2 < 50)) {
      score -= 1;
      reasons.add('PCO₂ ${pco2.toStringAsFixed(0)} mmHg（静脈血は動脈血より約5–6高い）');
    } else {
      reasons.add('PCO₂ ${pco2.toStringAsFixed(0)} mmHg（単独では判別困難）');
    }
  }
  final type = score >= 2
      ? SpecimenType.arterial
      : score <= -2
          ? SpecimenType.venous
          : SpecimenType.unknown;
  if (type == SpecimenType.unknown) {
    reasons.add('判別困難のため動脈血の基準値で表示しています（手動で切替可）');
  }
  if (po2 != null && po2 < 60 && so2 != null && so2 >= 85 && so2 < 92) {
    reasons.add('呼吸不全の動脈血や、静脈血の可能性もあります');
  }
  return SpecimenEstimate(type, reasons);
}

/// 基準値・評価に使う検体種別（不明なら動脈血扱い）。
SpecimenType effectiveSpecimen(LabSet set) {
  final e = estimateSpecimen(set);
  return e.type == SpecimenType.venous ? SpecimenType.venous : SpecimenType.arterial;
}

/// 器具と流量からの FiO2 目安。
double? estimateFio2(String? device, double? flow) {
  switch (device) {
    case '室内気':
      return 0.21;
    case '鼻カヌラ':
      if (flow == null) return null;
      return min(0.21 + 0.04 * flow, 0.45);
    case '簡易マスク':
      if (flow == null) return null;
      if (flow < 5) return 0.35;
      if (flow < 6) return 0.40;
      if (flow < 7) return 0.50;
      return 0.60;
    case 'リザーバーマスク':
      if (flow == null) return null;
      if (flow < 6) return 0.50;
      return min(0.60 + (flow - 6) * 0.1, 0.90);
    default:
      return null;
  }
}

/// FiO2 と、それが記載値か推定値か。
({double? fio2, bool estimated}) resolveFio2(OxygenInfo o) {
  if (o.fio2 != null) return (fio2: o.fio2, estimated: false);
  final e = estimateFio2(o.device, o.flowLpm);
  return (fio2: e, estimated: e != null && o.device != '室内気');
}

/// 計算値を求める。用紙に直接記載がある項目（AG・補正Ca・eGFR）はそちらを優先。
Map<String, DerivedValue> computeDerived(LabSet set) {
  final v = set.valueMap;
  final ctx = set.context;
  final out = <String, DerivedValue>{};
  double? g(String c) => v[c];

  final bun = g('BUN'), cre = g('CRE');
  if (bun != null && cre != null && cre > 0) {
    out['BUN_CRE'] = DerivedValue('BUN_CRE', 'BUN/Cre比', bun / cre, formula: 'BUN ÷ Cre', note: '>20で腎前性・消化管出血・異化亢進などを示唆', decimals: 1);
  }
  final ast = g('AST'), alt = g('ALT');
  if (ast != null && alt != null && alt > 0) {
    out['AST_ALT'] = DerivedValue('AST_ALT', 'AST/ALT比', ast / alt, formula: 'AST ÷ ALT', note: '>2でアルコール性・筋由来・溶血など、<1で脂肪肝・慢性肝炎など', decimals: 2);
  }
  final na = g('NA'), cl = g('CL'), hco3 = g('HCO3'), alb = g('ALB');
  double? ag = g('AG');
  if (na != null && cl != null && hco3 != null) {
    final calc = na - (cl + hco3);
    out['AG_CALC'] = DerivedValue('AG_CALC', 'AG（計算）', calc, unit: 'mEq/L', formula: 'Na −(Cl + HCO₃⁻)', note: '基準 8–16（施設により10–14）', decimals: 1);
    ag ??= calc;
  }
  if (ag != null && alb != null) {
    final c = ag + 2.5 * (4.0 - alb);
    out['AG_CORR'] = DerivedValue('AG_CORR', '補正AG', c, unit: 'mEq/L', formula: 'AG + 2.5×(4.0 − Alb)', note: '低Alb時はAGが見かけ上低くなるため補正', decimals: 1);
  }
  if (ag != null && hco3 != null && ag > 16 && hco3 < 24) {
    final dr = (ag - 12) / (24 - hco3);
    out['DELTA_RATIO'] = DerivedValue('DELTA_RATIO', 'Δ比（ΔAG/ΔHCO₃⁻）', dr, formula: '(AG−12) ÷ (24−HCO₃⁻)', note: '<1: 正AG性アシドーシス合併 / >2: 代謝性アルカローシス合併', decimals: 2);
  }
  final ca = g('CA');
  if (ca != null && alb != null && !v.containsKey('CA_CORR')) {
    final c = alb < 4.0 ? ca + (4.0 - alb) : ca;
    out['CA_CORR'] = DerivedValue('CA_CORR', '補正Ca', c, unit: 'mg/dL', formula: 'Ca + (4 − Alb)（Alb<4のとき）', decimals: 1);
  }
  if (cre != null && cre > 0 && ctx.age != null && ctx.sex != null && !v.containsKey('EGFR') && ctx.age! >= 18) {
    var e = 194 * pow(cre, -1.094) * pow(ctx.age!, -0.287);
    if (ctx.sex == 'F') e *= 0.739;
    out['EGFR'] = DerivedValue('EGFR', 'eGFR（計算）', e.toDouble(), unit: 'mL/min/1.73m²', formula: '日本人のGFR推算式', decimals: 1);
  }
  final tbil = g('TBIL'), dbil = g('DBIL');
  if (tbil != null && dbil != null && tbil > 0) {
    out['DBIL_RATIO'] = DerivedValue('DBIL_RATIO', '直接Bil比率', dbil / tbil * 100, unit: '%', formula: 'D-Bil ÷ T-Bil', note: '>50%で抱合型（肝細胞性・閉塞性）優位', decimals: 0);
  }
  final glu = g('GLU');
  if (na != null && glu != null && bun != null) {
    final calc = 2 * na + glu / 18 + bun / 2.8;
    out['OSM_CALC'] = DerivedValue('OSM_CALC', '計算浸透圧', calc, unit: 'mOsm/kg', formula: '2Na + 血糖/18 + BUN/2.8', decimals: 0);
    final osm = g('OSM');
    if (osm != null) {
      out['OSM_GAP'] = DerivedValue('OSM_GAP', '浸透圧ギャップ', osm - calc, unit: 'mOsm/kg', formula: '実測 − 計算', note: '>10でアルコール類・マンニトールなどを考慮', decimals: 0);
    }
  }
  if (na != null && glu != null && glu > 200) {
    out['NA_CORR'] = DerivedValue('NA_CORR', '補正Na（高血糖）', na + 1.6 * (glu - 100) / 100, unit: 'mEq/L', formula: 'Na + 1.6×(血糖−100)/100', decimals: 0);
  }
  final mcv = g('MCV'), rbc = g('RBC');
  if (mcv != null && rbc != null && rbc > 0 && mcv < 80) {
    out['MENTZER'] = DerivedValue('MENTZER', 'Mentzer指数', mcv / (rbc / 100), formula: 'MCV ÷ RBC(×10⁶/μL)', note: '<13でサラセミア、>13で鉄欠乏を示唆', decimals: 1);
  }
  final wbc = g('WBC'), neut = g('NEUT'), lymph = g('LYMPH');
  if (wbc != null && neut != null) {
    out['ANC'] = DerivedValue('ANC', '好中球数', wbc * neut / 100, unit: '/μL', formula: 'WBC × Neut%', note: '<500で高度好中球減少', decimals: 0);
  }
  if (wbc != null && lymph != null) {
    out['ALC'] = DerivedValue('ALC', 'リンパ球数', wbc * lymph / 100, unit: '/μL', formula: 'WBC × Lymph%', decimals: 0);
  }
  if (neut != null && lymph != null && lymph > 0) {
    out['NLR'] = DerivedValue('NLR', 'NLR', neut / lymph, formula: 'Neut% ÷ Lymph%', decimals: 1);
  }
  final tc = g('TC'), hdl = g('HDL'), tg = g('TG');
  if (tc != null && hdl != null && tg != null && tg < 400 && !v.containsKey('LDL')) {
    out['LDL_F'] = DerivedValue('LDL_F', 'LDL-C（F式）', tc - hdl - tg / 5, unit: 'mg/dL', formula: 'TC − HDL − TG/5', decimals: 0);
  }
  if (tc != null && hdl != null) {
    out['NONHDL'] = DerivedValue('NONHDL', 'non-HDL-C', tc - hdl, unit: 'mg/dL', formula: 'TC − HDL', decimals: 0);
  }

  // 血液ガス（動脈血のときのみ P/F 比・A-aDO2）
  final spec = effectiveSpecimen(set);
  final est = estimateSpecimen(set);
  final po2 = g('PO2'), pco2 = g('PCO2');
  final f = resolveFio2(set.oxygen);
  if (po2 != null && spec == SpecimenType.arterial && est.type != SpecimenType.unknown && f.fio2 != null) {
    final pf = po2 / f.fio2!;
    out['PF'] = DerivedValue('PF', f.estimated ? 'P/F比（FiO₂推定値）' : 'P/F比', pf,
        formula: 'PaO₂ ÷ FiO₂(${f.fio2!.toStringAsFixed(2)})',
        note: '<300: 酸素化障害 / <200: 中等症 / <100: 重症（ARDSの目安）${f.estimated ? '。FiO₂は器具・流量からの推定値' : ''}',
        decimals: 0);
    if (pco2 != null) {
      final aado2 = f.fio2! * 713 - pco2 / 0.8 - po2;
      out['AADO2'] = DerivedValue('AADO2', 'A-aDO₂', aado2, unit: 'mmHg', formula: 'FiO₂×713 − PaCO₂/0.8 − PaO₂', note: '室内気で 年齢/4+4 程度まで', decimals: 0);
    }
  }
  final ph = g('PH');
  if (ph != null && pco2 != null && hco3 != null && ph < 7.35 && hco3 < 22) {
    final expected = 1.5 * hco3 + 8;
    out['WINTER'] = DerivedValue('WINTER', '予測PaCO₂（Winter式）', expected, unit: 'mmHg', formula: '1.5×HCO₃⁻ + 8 ±2',
        note: pco2 > expected + 2
            ? '実測PCO₂が高い → 呼吸性アシドーシス合併'
            : pco2 < expected - 2
                ? '実測PCO₂が低い → 呼吸性アルカローシス合併'
                : '代償は適切',
        decimals: 0);
  }
  return out;
}
