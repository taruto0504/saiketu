import 'dart:convert';
import 'dart:math';

import '../services/pii.dart';

/// 1つの測定値。
class LabValue {
  LabValue({
    required this.code,
    this.value,
    this.unit = '',
    this.rawText,
    this.sheetLow,
    this.sheetHigh,
    this.sheetFlag,
    this.uncertain = false,
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  String code;
  double? value;

  /// 用紙に書かれていた単位（標準単位へ換算済みなら標準単位）。
  String unit;

  /// OCRで読み取った元の文字列（確認画面の表示用。保存はしない）。
  String? rawText;

  /// 用紙に記載されていた基準値。
  double? sheetLow;
  double? sheetHigh;

  /// 用紙に記載されていた H/L マーク。
  String? sheetFlag;

  /// 読み取りが不確か（確認画面で黄色表示）。
  bool uncertain;
  List<String> warnings;

  LabValue copy() => LabValue(
        code: code,
        value: value,
        unit: unit,
        rawText: rawText,
        sheetLow: sheetLow,
        sheetHigh: sheetHigh,
        sheetFlag: sheetFlag,
        uncertain: uncertain,
        warnings: [...warnings],
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'value': value,
        'unit': unit,
        if (sheetLow != null) 'sheetLow': sheetLow,
        if (sheetHigh != null) 'sheetHigh': sheetHigh,
        if (sheetFlag != null) 'sheetFlag': sheetFlag,
      };

  factory LabValue.fromJson(Map<String, dynamic> j) => LabValue(
        code: j['code'] as String,
        value: (j['value'] as num?)?.toDouble(),
        unit: (j['unit'] as String?) ?? '',
        sheetLow: (j['sheetLow'] as num?)?.toDouble(),
        sheetHigh: (j['sheetHigh'] as num?)?.toDouble(),
        sheetFlag: j['sheetFlag'] as String?,
      );
}

/// 検体種別（血液ガス）。
enum SpecimenType {
  arterial('A', '動脈血'),
  venous('V', '静脈血'),
  unknown('?', '不明');

  const SpecimenType(this.short, this.label);
  final String short;
  final String label;

  static SpecimenType? fromShort(String? s) {
    for (final t in SpecimenType.values) {
      if (t.short == s) return t;
    }
    return null;
  }
}

class SpecimenInfo {
  SpecimenInfo({this.sheetLabel, this.manual});

  /// 用紙に記載されていた検体種別。
  SpecimenType? sheetLabel;

  /// ユーザーが手動で切り替えた検体種別。
  SpecimenType? manual;

  Map<String, dynamic> toJson() => {
        if (sheetLabel != null) 'sheet': sheetLabel!.short,
        if (manual != null) 'manual': manual!.short,
      };

  factory SpecimenInfo.fromJson(Map<String, dynamic>? j) => SpecimenInfo(
        sheetLabel: SpecimenType.fromShort(j?['sheet'] as String?),
        manual: SpecimenType.fromShort(j?['manual'] as String?),
      );
}

/// 酸素投与の情報。
class OxygenInfo {
  OxygenInfo({
    List<String>? foundTexts,
    this.device,
    this.flowLpm,
    this.fio2,
    this.manual = false,
  }) : foundTexts = foundTexts ?? [];

  /// 用紙から見つかった記載（原文の断片）。
  List<String> foundTexts;

  /// 器具（室内気 / 鼻カニューラ / マスク / リザーバー など）。
  String? device;
  double? flowLpm;

  /// 記載または入力された FiO2（0.21–1.0）。
  double? fio2;

  /// 手入力されたか。
  bool manual;

  bool get hasInfo => device != null || flowLpm != null || fio2 != null || foundTexts.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'found': foundTexts,
        if (device != null) 'device': device,
        if (flowLpm != null) 'flow': flowLpm,
        if (fio2 != null) 'fio2': fio2,
        'manual': manual,
      };

  factory OxygenInfo.fromJson(Map<String, dynamic>? j) => OxygenInfo(
        foundTexts: ((j?['found'] as List?) ?? const []).cast<String>(),
        device: j?['device'] as String?,
        flowLpm: (j?['flow'] as num?)?.toDouble(),
        fio2: (j?['fio2'] as num?)?.toDouble(),
        manual: (j?['manual'] as bool?) ?? false,
      );
}

/// 疾患推定の第2段階で追加する情報。すべて任意。
class PatientContext {
  PatientContext({
    this.age,
    this.sex,
    this.weightKg,
    this.temp,
    this.sbp,
    this.dbp,
    this.hr,
    this.rr,
    this.spo2,
    this.jcs,
    this.gcs,
    List<String>? symptoms,
    this.complaint = '',
    this.history = '',
    this.medications = '',
    this.course = '',
    this.otherTests = '',
  }) : symptoms = symptoms ?? [];

  int? age;

  /// 'M' または 'F'。
  String? sex;
  double? weightKg;
  double? temp;
  int? sbp;
  int? dbp;
  int? hr;
  int? rr;
  int? spo2;
  String? jcs;
  int? gcs;
  List<String> symptoms;
  String complaint;
  String history;
  String medications;
  String course;
  String otherTests;

  bool get isEmpty => describe().isEmpty;

  /// 自由記載から個人情報と思われる部分を削除する。削除した箇所の数を返す。
  int scrubPersonalInfo() {
    var n = 0;
    String f(String s) {
      final r = scrubPII(s);
      n += r.removed;
      return r.text;
    }

    complaint = f(complaint);
    history = f(history);
    medications = f(medications);
    course = f(course);
    otherTests = f(otherTests);
    return n;
  }

  PatientContext copy() => PatientContext.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        if (age != null) 'age': age,
        if (sex != null) 'sex': sex,
        if (weightKg != null) 'weight': weightKg,
        if (temp != null) 'temp': temp,
        if (sbp != null) 'sbp': sbp,
        if (dbp != null) 'dbp': dbp,
        if (hr != null) 'hr': hr,
        if (rr != null) 'rr': rr,
        if (spo2 != null) 'spo2': spo2,
        if (jcs != null) 'jcs': jcs,
        if (gcs != null) 'gcs': gcs,
        if (symptoms.isNotEmpty) 'symptoms': symptoms,
        if (complaint.isNotEmpty) 'complaint': complaint,
        if (history.isNotEmpty) 'history': history,
        if (medications.isNotEmpty) 'meds': medications,
        if (course.isNotEmpty) 'course': course,
        if (otherTests.isNotEmpty) 'other': otherTests,
      };

  factory PatientContext.fromJson(Map<String, dynamic>? j) {
    j ??= const {};
    return PatientContext(
      age: (j['age'] as num?)?.toInt(),
      sex: j['sex'] as String?,
      weightKg: (j['weight'] as num?)?.toDouble(),
      temp: (j['temp'] as num?)?.toDouble(),
      sbp: (j['sbp'] as num?)?.toInt(),
      dbp: (j['dbp'] as num?)?.toInt(),
      hr: (j['hr'] as num?)?.toInt(),
      rr: (j['rr'] as num?)?.toInt(),
      spo2: (j['spo2'] as num?)?.toInt(),
      jcs: j['jcs'] as String?,
      gcs: (j['gcs'] as num?)?.toInt(),
      symptoms: ((j['symptoms'] as List?) ?? const []).cast<String>(),
      complaint: (j['complaint'] as String?) ?? '',
      history: (j['history'] as String?) ?? '',
      medications: (j['meds'] as String?) ?? '',
      course: (j['course'] as String?) ?? '',
      otherTests: (j['other'] as String?) ?? '',
    );
  }

  /// 入力済み項目の一覧（ラベル → 値）。
  Map<String, String> describe() {
    final m = <String, String>{};
    if (age != null) m['年齢'] = '$age歳';
    if (sex != null) m['性別'] = sex == 'M' ? '男性' : '女性';
    if (weightKg != null) m['体重'] = '${weightKg}kg';
    if (temp != null) m['体温'] = '$temp℃';
    if (sbp != null || dbp != null) m['血圧'] = '${sbp ?? '-'}/${dbp ?? '-'} mmHg';
    if (hr != null) m['脈拍'] = '$hr/分';
    if (rr != null) m['呼吸数'] = '$rr/分';
    if (spo2 != null) m['SpO2'] = '$spo2%';
    if (jcs != null) m['JCS'] = jcs!;
    if (gcs != null) m['GCS'] = '$gcs';
    if (symptoms.isNotEmpty) m['症状'] = symptoms.join('、');
    if (complaint.isNotEmpty) m['主訴・症状メモ'] = complaint;
    if (history.isNotEmpty) m['既往歴'] = history;
    if (medications.isNotEmpty) m['内服薬'] = medications;
    if (course.isNotEmpty) m['経過'] = course;
    if (otherTests.isNotEmpty) m['その他検査'] = otherTests;
    return m;
  }
}

/// 1回分の採血データ。
class LabSet {
  LabSet({
    String? id,
    this.folderId,
    DateTime? takenAt,
    DateTime? createdAt,
    List<LabValue>? values,
    PatientContext? context,
    SpecimenInfo? specimen,
    OxygenInfo? oxygen,
    this.source = 'manual',
    this.memo = '',
  })  : id = id ?? newId(),
        takenAt = takenAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        values = values ?? [],
        context = context ?? PatientContext(),
        specimen = specimen ?? SpecimenInfo(),
        oxygen = oxygen ?? OxygenInfo();

  final String id;
  String? folderId;
  DateTime takenAt;
  DateTime createdAt;
  List<LabValue> values;
  PatientContext context;
  SpecimenInfo specimen;
  OxygenInfo oxygen;

  /// 'camera' / 'photo' / 'manual'
  String source;
  String memo;

  bool get isSaved => folderId != null;

  LabValue? valueOf(String code) {
    for (final v in values) {
      if (v.code == code && v.value != null) return v;
    }
    return null;
  }

  Map<String, double> get valueMap => {
        for (final v in values)
          if (v.value != null) v.code: v.value!,
      };

  String valuesJson() => jsonEncode(values.map((v) => v.toJson()).toList());

  static List<LabValue> valuesFromJson(String s) =>
      (jsonDecode(s) as List).map((e) => LabValue.fromJson(e as Map<String, dynamic>)).toList();
}

class Folder {
  Folder({String? id, required this.name, this.memo = '', DateTime? createdAt, DateTime? updatedAt})
      : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  String memo;
  DateTime createdAt;
  DateTime updatedAt;

  /// 一覧表示用（DBから集計）。
  int setCount = 0;
  DateTime? lastTakenAt;
}

final _rand = Random.secure();

String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = List.generate(8, (_) => _rand.nextInt(36).toRadixString(36)).join();
  return '$t$r';
}
