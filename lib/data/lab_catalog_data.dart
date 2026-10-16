// 組み込みの検査項目マスタ。
//
// 基準値は主に JCCLS 共用基準範囲などの一般的な値を参考にした目安です。
// 施設ごとの基準値は設定画面から変更できます。用紙に基準値の記載があればそちらを優先します。
// 危険値（パニック値）・誤読判定範囲も一般的な目安であり、施設の運用に合わせて変更してください。

import '../models/lab_item.dart';

const _cbc = LabCategory.cbc;
const _coag = LabCategory.coag;
const _liver = LabCategory.liver;
const _renal = LabCategory.renal;
const _prot = LabCategory.protein;
const _meta = LabCategory.metabolic;
const _lipid = LabCategory.lipid;
const _card = LabCategory.cardiac;
const _gas = LabCategory.gas;
const _other = LabCategory.other;

const List<LabItemDef> builtinLabItems = [
  // ───────── 血算 ─────────
  LabItemDef(
      code: 'WBC', name: 'WBC', jpName: '白血球数', category: _cbc, unit: '/μL',
      low: 3300, high: 8600, critLow: 1500, critHigh: 30000,
      plausLow: 50, plausHigh: 500000, decimals: 0,
      aliases: ['WBC', '白血球', '白血球数', 'ワイビーシー', 'WBCCOUNT'],
      altUnits: [AltUnit('×10^3/μL', 1000), AltUnit('×10^3/μL', 1000), AltUnit('10^3/μL', 1000), AltUnit('×10^2/μL', 100), AltUnit('×10^9/L', 1000)]),
  LabItemDef(
      code: 'NEUT', name: 'Neut', jpName: '好中球', category: _cbc, unit: '%',
      low: 40, high: 75, plausLow: 0, plausHigh: 100,
      aliases: ['NEUT', 'NEUT%', '好中球', '好中球%', '好中球率', 'NEUTRO', 'SEG', 'NE%', '分葉核球']),
  LabItemDef(
      code: 'LYMPH', name: 'Lymph', jpName: 'リンパ球', category: _cbc, unit: '%',
      low: 18, high: 50, plausLow: 0, plausHigh: 100,
      aliases: ['LYMPH', 'LYMPH%', 'LYMPHO', 'LY%', 'リンパ球', 'リンパ球%', 'リンパ球率']),
  LabItemDef(
      code: 'MONO', name: 'Mono', jpName: '単球', category: _cbc, unit: '%',
      low: 2, high: 10, plausLow: 0, plausHigh: 100,
      aliases: ['MONO', 'MONO%', 'MO%', '単球', '単球%', '単球率']),
  LabItemDef(
      code: 'EOS', name: 'Eos', jpName: '好酸球', category: _cbc, unit: '%',
      low: 0, high: 7, plausLow: 0, plausHigh: 100,
      aliases: ['EOS', 'EOS%', 'EOSINO', 'EO%', '好酸球', '好酸球%', '好酸球率']),
  LabItemDef(
      code: 'BASO', name: 'Baso', jpName: '好塩基球', category: _cbc, unit: '%',
      low: 0, high: 2, plausLow: 0, plausHigh: 100,
      aliases: ['BASO', 'BASO%', 'BA%', '好塩基球', '好塩基球%', '好塩基球率']),
  LabItemDef(
      code: 'RBC', name: 'RBC', jpName: '赤血球数', category: _cbc, unit: '×10^4/μL',
      low: 386, high: 555, lowM: 435, highM: 555, lowF: 386, highF: 492,
      plausLow: 50, plausHigh: 900, decimals: 0,
      aliases: ['RBC', '赤血球', '赤血球数'],
      altUnits: [AltUnit('×10^6/μL', 100), AltUnit('×10^6/μL', 100), AltUnit('×10^12/L', 100)]),
  LabItemDef(
      code: 'HB', name: 'Hb', jpName: 'ヘモグロビン', category: _cbc, unit: 'g/dL',
      low: 11.6, high: 16.8, lowM: 13.7, highM: 16.8, lowF: 11.6, highF: 14.8,
      critLow: 6.0, critHigh: 20.0, plausLow: 1.0, plausHigh: 26.0,
      aliases: ['HB', 'HGB', 'ヘモグロビン', '血色素', '血色素量', 'ヘモグロビン量'],
      altUnits: [AltUnit('g/L', 0.1), AltUnit('mmol/L', 1.611)]),
  LabItemDef(
      code: 'HT', name: 'Ht', jpName: 'ヘマトクリット', category: _cbc, unit: '%',
      low: 35.1, high: 50.1, lowM: 40.7, highM: 50.1, lowF: 35.1, highF: 44.4,
      plausLow: 5, plausHigh: 80,
      aliases: ['HT', 'HCT', 'ヘマトクリット', 'ヘマトクリット値']),
  LabItemDef(
      code: 'MCV', name: 'MCV', jpName: '平均赤血球容積', category: _cbc, unit: 'fL',
      low: 83.6, high: 98.2, plausLow: 40, plausHigh: 160,
      aliases: ['MCV', '平均赤血球容積']),
  LabItemDef(
      code: 'MCH', name: 'MCH', jpName: '平均赤血球血色素量', category: _cbc, unit: 'pg',
      low: 27.5, high: 33.2, plausLow: 10, plausHigh: 60,
      aliases: ['MCH', '平均赤血球血色素量', '平均赤血球ヘモグロビン量']),
  LabItemDef(
      code: 'MCHC', name: 'MCHC', jpName: '平均赤血球血色素濃度', category: _cbc, unit: '%',
      low: 31.7, high: 35.3, plausLow: 20, plausHigh: 45,
      aliases: ['MCHC', '平均赤血球血色素濃度', '平均赤血球ヘモグロビン濃度'],
      altUnits: [AltUnit('g/dL', 1)]),
  LabItemDef(
      code: 'PLT', name: 'PLT', jpName: '血小板数', category: _cbc, unit: '×10^4/μL',
      low: 15.8, high: 34.8, critLow: 3.0, critHigh: 100,
      plausLow: 0.1, plausHigh: 300,
      aliases: ['PLT', '血小板', '血小板数', 'PLTS'],
      altUnits: [AltUnit('×10^3/μL', 0.1), AltUnit('×10^3/μL', 0.1), AltUnit('×10^9/L', 0.1), AltUnit('/μL', 0.0001)]),
  LabItemDef(
      code: 'RET', name: 'Ret', jpName: '網赤血球', category: _cbc, unit: '%',
      low: 0.5, high: 2.0, plausLow: 0, plausHigh: 50,
      aliases: ['RET', 'RETIC', 'RETICULOCYTE', '網赤血球', '網状赤血球', '網赤血球数'],
      altUnits: [AltUnit('‰', 0.1)]),

  // ───────── 凝固 ─────────
  LabItemDef(
      code: 'PT', name: 'PT', jpName: 'プロトロンビン時間', category: _coag, unit: '秒',
      low: 10.0, high: 13.0, plausLow: 5, plausHigh: 200,
      aliases: ['PT', 'PT秒', 'PT(秒)', 'プロトロンビン時間', 'PTSEC']),
  LabItemDef(
      code: 'PT_PCT', name: 'PT%', jpName: 'PT活性', category: _coag, unit: '%',
      low: 70, high: 130, critLow: 20, plausLow: 1, plausHigh: 200, decimals: 0,
      aliases: ['PT%', 'PT活性', 'PT(%)', 'PT活性値', 'プロトロンビン活性']),
  LabItemDef(
      code: 'PT_INR', name: 'PT-INR', jpName: 'PT-INR', category: _coag, unit: '',
      low: 0.85, high: 1.15, critHigh: 4.0, plausLow: 0.5, plausHigh: 15, decimals: 2,
      aliases: ['PT-INR', 'PTINR', 'INR', 'PT(INR)', 'PT INR']),
  LabItemDef(
      code: 'APTT', name: 'APTT', jpName: '活性化部分トロンボプラスチン時間', category: _coag, unit: '秒',
      low: 24, high: 39, critHigh: 100, plausLow: 10, plausHigh: 250,
      aliases: ['APTT', 'APTT秒', '活性化部分トロンボプラスチン時間']),
  LabItemDef(
      code: 'FIB', name: 'Fib', jpName: 'フィブリノゲン', category: _coag, unit: 'mg/dL',
      low: 200, high: 400, critLow: 100, plausLow: 10, plausHigh: 1500, decimals: 0,
      aliases: ['FIB', 'FBG', 'FIBRINOGEN', 'フィブリノゲン', 'フィブリノーゲン', 'フィブリノゲン量']),
  LabItemDef(
      code: 'FDP', name: 'FDP', jpName: 'FDP', category: _coag, unit: 'μg/mL',
      high: 5.0, plausLow: 0, plausHigh: 2000,
      aliases: ['FDP', 'フィブリン分解産物', 'フィブリン・フィブリノゲン分解産物']),
  LabItemDef(
      code: 'DDIMER', name: 'Dダイマー', jpName: 'Dダイマー', category: _coag, unit: 'μg/mL',
      high: 1.0, plausLow: 0, plausHigh: 1000, decimals: 2,
      aliases: ['DD', 'D-D', 'DDIMER', 'D-DIMER', 'Dダイマー', 'D-ダイマー', 'Dダイマー定量']),
  LabItemDef(
      code: 'AT', name: 'AT', jpName: 'アンチトロンビン', category: _coag, unit: '%',
      low: 80, high: 130, plausLow: 1, plausHigh: 250, decimals: 0,
      aliases: ['AT', 'AT3', 'ATIII', 'AT-III', 'AT活性', 'アンチトロンビン', 'アンチトロンビン活性']),

  // ───────── 肝胆膵 ─────────
  LabItemDef(
      code: 'AST', name: 'AST', jpName: 'AST(GOT)', category: _liver, unit: 'U/L',
      low: 13, high: 30, critHigh: 1000, plausLow: 1, plausHigh: 50000, decimals: 0,
      aliases: ['AST', 'GOT', 'AST(GOT)', 'GOT(AST)', 'アスパラギン酸アミノトランスフェラーゼ']),
  LabItemDef(
      code: 'ALT', name: 'ALT', jpName: 'ALT(GPT)', category: _liver, unit: 'U/L',
      low: 7, high: 42, lowM: 10, highM: 42, lowF: 7, highF: 23,
      critHigh: 1000, plausLow: 1, plausHigh: 50000, decimals: 0,
      aliases: ['ALT', 'GPT', 'ALT(GPT)', 'GPT(ALT)', 'アラニンアミノトランスフェラーゼ']),
  LabItemDef(
      code: 'LDH', name: 'LDH', jpName: '乳酸脱水素酵素', category: _liver, unit: 'U/L',
      low: 124, high: 222, plausLow: 20, plausHigh: 50000, decimals: 0,
      aliases: ['LDH', 'LD', 'LDH(IFCC)', 'LD(IFCC)', '乳酸脱水素酵素']),
  LabItemDef(
      code: 'ALP', name: 'ALP', jpName: 'アルカリホスファターゼ', category: _liver, unit: 'U/L',
      low: 38, high: 113, plausLow: 5, plausHigh: 10000, decimals: 0,
      rangeNote: 'IFCC法。JSCC法の用紙では基準値が異なります',
      aliases: ['ALP', 'ALP(IFCC)', 'ALP(JSCC)', 'アルカリホスファターゼ']),
  LabItemDef(
      code: 'GGT', name: 'γ-GTP', jpName: 'γ-GT', category: _liver, unit: 'U/L',
      low: 9, high: 64, lowM: 13, highM: 64, lowF: 9, highF: 32,
      plausLow: 1, plausHigh: 10000, decimals: 0,
      aliases: ['γ-GTP', 'γGTP', 'Γ-GTP', 'ΓGTP', 'γ-GT', 'γGT', 'GGT', 'GGTP', 'GTP', 'Y-GTP', 'YGTP', 'r-GTP', 'rGTP', 'ガンマGTP']),
  LabItemDef(
      code: 'TBIL', name: 'T-Bil', jpName: '総ビリルビン', category: _liver, unit: 'mg/dL',
      low: 0.4, high: 1.5, critHigh: 15, plausLow: 0, plausHigh: 60,
      aliases: ['T-BIL', 'TBIL', 'T.BIL', 'T-BILI', 'TB', '総ビリルビン', 'T-Bil'],
      altUnits: [AltUnit('μmol/L', 0.0585)]),
  LabItemDef(
      code: 'DBIL', name: 'D-Bil', jpName: '直接ビリルビン', category: _liver, unit: 'mg/dL',
      low: 0, high: 0.4, plausLow: 0, plausHigh: 40,
      aliases: ['D-BIL', 'DBIL', 'D.BIL', 'D-BILI', 'DB', '直接ビリルビン', '抱合型ビリルビン', 'D-Bil'],
      altUnits: [AltUnit('μmol/L', 0.0585)]),
  LabItemDef(
      code: 'AMY', name: 'AMY', jpName: 'アミラーゼ', category: _liver, unit: 'U/L',
      low: 44, high: 132, plausLow: 1, plausHigh: 20000, decimals: 0,
      aliases: ['AMY', 'AMYL', 'アミラーゼ', '血清アミラーゼ', 'S-AMY']),
  LabItemDef(
      code: 'LIP', name: 'リパーゼ', jpName: 'リパーゼ', category: _liver, unit: 'U/L',
      low: 13, high: 55, plausLow: 1, plausHigh: 20000, decimals: 0,
      aliases: ['LIP', 'LIPASE', 'リパーゼ']),
  LabItemDef(
      code: 'CHE', name: 'ChE', jpName: 'コリンエステラーゼ', category: _liver, unit: 'U/L',
      low: 201, high: 486, lowM: 240, highM: 486, lowF: 201, highF: 421,
      plausLow: 5, plausHigh: 1000, decimals: 0,
      aliases: ['CHE', 'CH-E', 'コリンエステラーゼ']),

  // ───────── 腎・電解質 ─────────
  LabItemDef(
      code: 'BUN', name: 'BUN', jpName: '尿素窒素', category: _renal, unit: 'mg/dL',
      low: 8, high: 20, plausLow: 1, plausHigh: 300,
      aliases: ['BUN', 'UN', '尿素窒素', '血中尿素窒素', 'S-UN']),
  LabItemDef(
      code: 'CRE', name: 'Cre', jpName: 'クレアチニン', category: _renal, unit: 'mg/dL',
      low: 0.46, high: 1.07, lowM: 0.65, highM: 1.07, lowF: 0.46, highF: 0.79,
      plausLow: 0.05, plausHigh: 30, decimals: 2,
      aliases: ['CRE', 'CR', 'CREA', 'CRN', 'CRTN', 'クレアチニン', 'S-CRE', 'Cre'],
      altUnits: [AltUnit('μmol/L', 0.01131)]),
  LabItemDef(
      code: 'EGFR', name: 'eGFR', jpName: '推算GFR', category: _renal, unit: 'mL/min/1.73m^2',
      low: 60, plausLow: 1, plausHigh: 250,
      aliases: ['EGFR', 'eGFR', 'EGFRCRE', 'eGFRcre', '推算GFR', 'GFR']),
  LabItemDef(
      code: 'UA', name: 'UA', jpName: '尿酸', category: _renal, unit: 'mg/dL',
      low: 2.6, high: 7.8, lowM: 3.7, highM: 7.8, lowF: 2.6, highF: 5.5,
      plausLow: 0.1, plausHigh: 30,
      aliases: ['UA', '尿酸', 'S-UA']),
  LabItemDef(
      code: 'NA', name: 'Na', jpName: 'ナトリウム', category: _renal, unit: 'mEq/L',
      low: 138, high: 145, critLow: 120, critHigh: 160, plausLow: 90, plausHigh: 200, decimals: 0,
      aliases: ['NA', 'ナトリウム', 'S-NA', 'NA+'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'K', name: 'K', jpName: 'カリウム', category: _renal, unit: 'mEq/L',
      low: 3.6, high: 4.8, critLow: 2.5, critHigh: 6.0, plausLow: 1.0, plausHigh: 12.0,
      aliases: ['K', 'カリウム', 'S-K', 'K+'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'CL', name: 'Cl', jpName: 'クロール', category: _renal, unit: 'mEq/L',
      low: 101, high: 108, plausLow: 50, plausHigh: 160, decimals: 0,
      aliases: ['CL', 'クロール', 'クロライド', '塩素', 'S-CL', 'CL-'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'CA', name: 'Ca', jpName: 'カルシウム', category: _renal, unit: 'mg/dL',
      low: 8.8, high: 10.1, critLow: 6.0, critHigh: 12.0, plausLow: 2.0, plausHigh: 20.0,
      aliases: ['CA', 'カルシウム', 'S-CA', 'CA2+'],
      altUnits: [AltUnit('mmol/L', 4.008)]),
  LabItemDef(
      code: 'CA_CORR', name: '補正Ca', jpName: '補正カルシウム', category: _renal, unit: 'mg/dL',
      low: 8.8, high: 10.1, critLow: 6.0, critHigh: 12.0, plausLow: 2.0, plausHigh: 20.0,
      aliases: ['補正CA', '補正カルシウム', 'CCA', 'CORRCA', 'CORRECTEDCA', '補正値CA']),
  LabItemDef(
      code: 'P', name: 'P', jpName: '無機リン', category: _renal, unit: 'mg/dL',
      low: 2.7, high: 4.6, critLow: 1.0, plausLow: 0.2, plausHigh: 20,
      aliases: ['P', 'IP', '無機リン', 'リン', 'S-IP', 'PI']),
  LabItemDef(
      code: 'MG', name: 'Mg', jpName: 'マグネシウム', category: _renal, unit: 'mg/dL',
      low: 1.8, high: 2.4, critLow: 1.0, critHigh: 5.0, plausLow: 0.2, plausHigh: 15,
      aliases: ['MG', 'マグネシウム', 'S-MG'],
      altUnits: [AltUnit('mmol/L', 2.43), AltUnit('mEq/L', 1.215)]),

  // ───────── 蛋白・炎症 ─────────
  LabItemDef(
      code: 'TP', name: 'TP', jpName: '総蛋白', category: _prot, unit: 'g/dL',
      low: 6.6, high: 8.1, plausLow: 1.5, plausHigh: 15,
      aliases: ['TP', '総蛋白', '総タンパク', '総たんぱく']),
  LabItemDef(
      code: 'ALB', name: 'Alb', jpName: 'アルブミン', category: _prot, unit: 'g/dL',
      low: 4.1, high: 5.1, plausLow: 0.5, plausHigh: 7,
      aliases: ['ALB', 'アルブミン', 'ALB(BCP改良法)', 'ALB(BCG)']),
  LabItemDef(
      code: 'CRP', name: 'CRP', jpName: 'C反応性蛋白', category: _prot, unit: 'mg/dL',
      low: 0, high: 0.14, plausLow: 0, plausHigh: 60, decimals: 2,
      aliases: ['CRP', 'C反応性蛋白', 'C反応性タンパク', 'CRP定量'],
      altUnits: [AltUnit('mg/L', 0.1)]),
  LabItemDef(
      code: 'PCT', name: 'PCT', jpName: 'プロカルシトニン', category: _prot, unit: 'ng/mL',
      high: 0.05, plausLow: 0, plausHigh: 1000, decimals: 2,
      rangeNote: '0.5 ng/mL以上で細菌感染症（敗血症）を疑う目安',
      aliases: ['PCT', 'プロカルシトニン']),
  LabItemDef(
      code: 'FERRITIN', name: 'フェリチン', jpName: 'フェリチン', category: _prot, unit: 'ng/mL',
      low: 5, high: 282, lowM: 21, highM: 282, lowF: 5, highF: 157,
      plausLow: 0.5, plausHigh: 100000, decimals: 0,
      aliases: ['FERRITIN', 'FER', 'フェリチン']),

  // ───────── 代謝・内分泌 ─────────
  LabItemDef(
      code: 'GLU', name: '血糖', jpName: 'グルコース', category: _meta, unit: 'mg/dL',
      low: 73, high: 109, critLow: 50, critHigh: 500, plausLow: 5, plausHigh: 3000, decimals: 0,
      rangeNote: '空腹時の基準値',
      aliases: ['GLU', 'BS', 'PG', 'FBS', 'FPG', '血糖', '血糖値', 'グルコース', '随時血糖', '空腹時血糖', 'GLUCOSE'],
      altUnits: [AltUnit('mmol/L', 18.0)]),
  LabItemDef(
      code: 'HBA1C', name: 'HbA1c', jpName: 'HbA1c', category: _meta, unit: '%',
      low: 4.9, high: 6.0, plausLow: 3, plausHigh: 20,
      aliases: ['HBA1C', 'A1C', 'HBA1C(NGSP)', 'ヘモグロビンA1C', 'グリコヘモグロビン']),
  LabItemDef(
      code: 'KETONE', name: 'ケトン体', jpName: '総ケトン体', category: _meta, unit: 'μmol/L',
      low: 0, high: 130, plausLow: 0, plausHigh: 20000, decimals: 0,
      aliases: ['KETONE', 'ケトン体', '総ケトン体', 'TKB', '血中ケトン体', 'Β-HB', 'BHB', '3-HB', 'Β-ヒドロキシ酪酸', '3-ヒドロキシ酪酸'],
      altUnits: [AltUnit('mmol/L', 1000)]),
  LabItemDef(
      code: 'TSH', name: 'TSH', jpName: '甲状腺刺激ホルモン', category: _meta, unit: 'μIU/mL',
      low: 0.5, high: 5.0, plausLow: 0, plausHigh: 500, decimals: 2,
      aliases: ['TSH', '甲状腺刺激ホルモン'],
      altUnits: [AltUnit('mIU/L', 1)]),
  LabItemDef(
      code: 'FT3', name: 'FT3', jpName: '遊離T3', category: _meta, unit: 'pg/mL',
      low: 2.3, high: 4.0, plausLow: 0.1, plausHigh: 50, decimals: 2,
      aliases: ['FT3', 'F-T3', '遊離T3', '遊離トリヨードサイロニン']),
  LabItemDef(
      code: 'FT4', name: 'FT4', jpName: '遊離T4', category: _meta, unit: 'ng/dL',
      low: 0.9, high: 1.7, plausLow: 0.05, plausHigh: 15, decimals: 2,
      aliases: ['FT4', 'F-T4', '遊離T4', '遊離サイロキシン']),
  LabItemDef(
      code: 'CORTISOL', name: 'コルチゾール', jpName: 'コルチゾール', category: _meta, unit: 'μg/dL',
      low: 4.5, high: 21.1, plausLow: 0.1, plausHigh: 200,
      rangeNote: '早朝安静時の基準値',
      aliases: ['CORTISOL', 'コルチゾール', 'コルチゾル', 'CORT']),

  // ───────── 脂質 ─────────
  LabItemDef(
      code: 'TC', name: 'TC', jpName: '総コレステロール', category: _lipid, unit: 'mg/dL',
      low: 142, high: 248, plausLow: 20, plausHigh: 2000, decimals: 0,
      aliases: ['TC', 'T-CHO', 'TCHO', 'T-CHOL', '総コレステロール', 'CHO']),
  LabItemDef(
      code: 'TG', name: 'TG', jpName: '中性脂肪', category: _lipid, unit: 'mg/dL',
      low: 30, high: 234, lowM: 40, highM: 234, lowF: 30, highF: 117,
      plausLow: 5, plausHigh: 20000, decimals: 0,
      aliases: ['TG', '中性脂肪', 'トリグリセライド', 'トリグリセリド']),
  LabItemDef(
      code: 'HDL', name: 'HDL-C', jpName: 'HDLコレステロール', category: _lipid, unit: 'mg/dL',
      low: 38, high: 103, lowM: 38, highM: 90, lowF: 48, highF: 103,
      plausLow: 3, plausHigh: 250, decimals: 0,
      aliases: ['HDL', 'HDL-C', 'HDLC', 'HDL-CHO', 'HDLコレステロール']),
  LabItemDef(
      code: 'LDL', name: 'LDL-C', jpName: 'LDLコレステロール', category: _lipid, unit: 'mg/dL',
      low: 65, high: 163, plausLow: 3, plausHigh: 1500, decimals: 0,
      aliases: ['LDL', 'LDL-C', 'LDLC', 'LDL-CHO', 'LDLコレステロール']),

  // ───────── 心筋 ─────────
  LabItemDef(
      code: 'CK', name: 'CK', jpName: 'クレアチンキナーゼ', category: _card, unit: 'U/L',
      low: 41, high: 248, lowM: 59, highM: 248, lowF: 41, highF: 153,
      critHigh: 10000, plausLow: 1, plausHigh: 500000, decimals: 0,
      aliases: ['CK', 'CPK', 'クレアチンキナーゼ', 'クレアチンホスホキナーゼ']),
  LabItemDef(
      code: 'CKMB', name: 'CK-MB', jpName: 'CK-MB', category: _card, unit: 'U/L',
      high: 25, plausLow: 0, plausHigh: 10000, decimals: 0,
      aliases: ['CK-MB', 'CKMB', 'CPK-MB']),
  LabItemDef(
      code: 'TNT', name: 'トロポニンT', jpName: '高感度トロポニンT', category: _card, unit: 'ng/mL',
      high: 0.014, critHigh: 0.1, plausLow: 0, plausHigh: 100, decimals: 3,
      aliases: ['TNT', 'TROPT', 'HSTNT', 'HS-TNT', 'トロポニンT', '高感度トロポニンT', '心筋トロポニンT', 'CTNT']),
  LabItemDef(
      code: 'TNI', name: 'トロポニンI', jpName: '高感度トロポニンI', category: _card, unit: 'pg/mL',
      high: 26.2, critHigh: 1000, plausLow: 0, plausHigh: 500000,
      aliases: ['TNI', 'TROPI', 'HSTNI', 'HS-TNI', 'トロポニンI', '高感度トロポニンI', '心筋トロポニンI', 'CTNI'],
      altUnits: [AltUnit('ng/mL', 1000), AltUnit('ng/L', 1)]),
  LabItemDef(
      code: 'BNP', name: 'BNP', jpName: '脳性ナトリウム利尿ペプチド', category: _card, unit: 'pg/mL',
      high: 18.4, plausLow: 0, plausHigh: 50000,
      aliases: ['BNP', '脳性ナトリウム利尿ペプチド', 'ヒト脳性ナトリウム利尿ペプチド']),
  LabItemDef(
      code: 'NTPROBNP', name: 'NT-proBNP', jpName: 'NT-proBNP', category: _card, unit: 'pg/mL',
      high: 125, plausLow: 0, plausHigh: 100000, decimals: 0,
      aliases: ['NT-PROBNP', 'NTPROBNP', 'NT-BNP', 'NTBNP']),

  // ───────── 血液ガス（A=動脈血 / V=静脈血） ─────────
  LabItemDef(
      code: 'PH', name: 'pH', jpName: 'pH', category: _gas, unit: '',
      low: 7.35, high: 7.45, venousLow: 7.31, venousHigh: 7.41,
      critLow: 7.20, critHigh: 7.60, plausLow: 6.5, plausHigh: 8.0, decimals: 2, isGas: true,
      aliases: ['PH', 'pH', 'PH(37℃)']),
  LabItemDef(
      code: 'PCO2', name: 'PCO2', jpName: '二酸化炭素分圧', category: _gas, unit: 'mmHg',
      low: 35, high: 45, venousLow: 41, venousHigh: 51,
      critLow: 20, critHigh: 70, plausLow: 5, plausHigh: 200, isGas: true,
      aliases: ['PCO2', 'PACO2', 'PVCO2', 'PCO2(T)', '二酸化炭素分圧'],
      altUnits: [AltUnit('kPa', 7.50062)]),
  LabItemDef(
      code: 'PO2', name: 'PO2', jpName: '酸素分圧', category: _gas, unit: 'mmHg',
      low: 80, high: 100, venousLow: 25, venousHigh: 45,
      critLow: 50, plausLow: 5, plausHigh: 700, isGas: true,
      rangeNote: '動脈血の critLow(50) は静脈血では適用しません',
      aliases: ['PO2', 'PAO2', 'PVO2', 'PO2(T)', '酸素分圧'],
      altUnits: [AltUnit('kPa', 7.50062)]),
  LabItemDef(
      code: 'HCO3', name: 'HCO3-', jpName: '重炭酸イオン', category: _gas, unit: 'mEq/L',
      low: 22, high: 26, venousLow: 23, venousHigh: 29,
      critLow: 10, critHigh: 40, plausLow: 1, plausHigh: 60, isGas: true,
      aliases: ['HCO3', 'HCO3-', 'HCO3ACT', 'CHCO3', 'HCO3(P)', 'HCO3(ACT)', 'BICARB', '重炭酸', '重炭酸イオン'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'BE', name: 'BE', jpName: '塩基過剰', category: _gas, unit: 'mEq/L',
      low: -2, high: 2, venousLow: -2, venousHigh: 2,
      critLow: -15, plausLow: -40, plausHigh: 40, isGas: true,
      aliases: ['BE', 'ABE', 'SBE', 'BE(B)', 'BE(ECF)', 'BEB', 'BEECF', 'ベースエクセス', '塩基過剰'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'SO2', name: 'SO2', jpName: '酸素飽和度', category: _gas, unit: '%',
      low: 95, high: 100, venousLow: 60, venousHigh: 85,
      plausLow: 5, plausHigh: 100, isGas: true,
      aliases: ['SO2', 'SAO2', 'SVO2', 'O2SAT', 'SO2(C)', 'SO2C', 'O2HB', 'FO2HB', '酸素飽和度']),
  LabItemDef(
      code: 'LAC', name: '乳酸', jpName: '乳酸', category: _gas, unit: 'mmol/L',
      low: 0.5, high: 2.0, venousLow: 0.5, venousHigh: 2.2,
      critHigh: 4.0, plausLow: 0, plausHigh: 35, isGas: true,
      aliases: ['LAC', 'LACT', 'LACTATE', '乳酸', 'ラクテート', 'LA'],
      altUnits: [AltUnit('mg/dL', 0.111)]),
  LabItemDef(
      code: 'AG', name: 'AG', jpName: 'アニオンギャップ', category: _gas, unit: 'mEq/L',
      low: 8, high: 16, venousLow: 8, venousHigh: 16,
      plausLow: -10, plausHigh: 60, isGas: true,
      rangeNote: 'AG = Na −(Cl + HCO3-)。Kを含む式では基準値が高くなります',
      aliases: ['AG', 'ANIONGAP', 'アニオンギャップ', 'AGAP', 'AG(K)']),

  // ───────── その他 ─────────
  LabItemDef(
      code: 'NH3', name: 'NH3', jpName: 'アンモニア', category: _other, unit: 'μg/dL',
      low: 12, high: 66, critHigh: 200, plausLow: 1, plausHigh: 2000, decimals: 0,
      aliases: ['NH3', 'アンモニア', '血中アンモニア', 'AMMONIA'],
      altUnits: [AltUnit('μmol/L', 1.703)]),
  LabItemDef(
      code: 'OSM', name: '浸透圧', jpName: '血漿浸透圧', category: _other, unit: 'mOsm/kgH2O',
      low: 275, high: 290, critLow: 240, critHigh: 330, plausLow: 150, plausHigh: 500, decimals: 0,
      aliases: ['OSM', '浸透圧', '血漿浸透圧', '血清浸透圧', 'POSM', 'SOSM']),
  LabItemDef(
      code: 'DIGOXIN', name: 'ジゴキシン', jpName: 'ジゴキシン血中濃度', category: _other, unit: 'ng/mL',
      low: 0.5, high: 2.0, critHigh: 2.0, plausLow: 0, plausHigh: 20, decimals: 2,
      rangeNote: '治療域の目安（心不全では0.5–0.9）',
      aliases: ['DIGOXIN', 'ジゴキシン', 'DIG']),
  LabItemDef(
      code: 'VCM', name: 'バンコマイシン', jpName: 'バンコマイシン血中濃度', category: _other, unit: 'μg/mL',
      low: 10, high: 20, plausLow: 0, plausHigh: 200,
      rangeNote: 'トラフ値の目安（AUCによる管理が推奨されます）',
      aliases: ['VCM', 'VANCOMYCIN', 'バンコマイシン', 'バンコマイシン(トラフ)']),
  LabItemDef(
      code: 'PHT', name: 'フェニトイン', jpName: 'フェニトイン血中濃度', category: _other, unit: 'μg/mL',
      low: 10, high: 20, critHigh: 30, plausLow: 0, plausHigh: 150,
      aliases: ['PHT', 'DPH', 'PHENYTOIN', 'フェニトイン', 'アレビアチン']),
  LabItemDef(
      code: 'VPA', name: 'バルプロ酸', jpName: 'バルプロ酸血中濃度', category: _other, unit: 'μg/mL',
      low: 50, high: 100, critHigh: 150, plausLow: 0, plausHigh: 1000, decimals: 0,
      aliases: ['VPA', 'VALPROATE', 'バルプロ酸', 'デパケン']),
  LabItemDef(
      code: 'THEO', name: 'テオフィリン', jpName: 'テオフィリン血中濃度', category: _other, unit: 'μg/mL',
      low: 5, high: 15, critHigh: 20, plausLow: 0, plausHigh: 200,
      aliases: ['THEO', 'THEOPHYLLINE', 'テオフィリン', 'テオドール']),
  LabItemDef(
      code: 'LI', name: 'リチウム', jpName: 'リチウム血中濃度', category: _other, unit: 'mEq/L',
      low: 0.6, high: 1.2, critHigh: 2.0, plausLow: 0, plausHigh: 10, decimals: 2,
      aliases: ['LI', 'LITHIUM', 'リチウム', '炭酸リチウム'],
      altUnits: [AltUnit('mmol/L', 1)]),
  LabItemDef(
      code: 'CBZ', name: 'カルバマゼピン', jpName: 'カルバマゼピン血中濃度', category: _other, unit: 'μg/mL',
      low: 4, high: 12, critHigh: 20, plausLow: 0, plausHigh: 100,
      aliases: ['CBZ', 'CARBAMAZEPINE', 'カルバマゼピン', 'テグレトール']),
];
