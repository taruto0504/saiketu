import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import 'clinical_calc.dart';
import 'lab_catalog.dart';
import 'rule_engine.dart';

/// オンライン状態の監視。
class Connectivity2 {
  static Stream<bool> watch() => Connectivity().onConnectivityChanged.map(_online);

  static Future<bool> check() async => _online(await Connectivity().checkConnectivity());

  static bool _online(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);
}

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 外部LLM（Claude API）によるAIアドバイス。
///
/// 送信するのは検査値（・計算値・前回値）、年齢・性別、ルールベースの判定結果のみ。
/// 氏名・ID・フォルダ名・日付・自由記載（症状・既往歴など）は送信しない。
class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  static const systemPrompt = '''
あなたは臨床検査医学に詳しい医療従事者向けの診療支援アシスタントです。
利用者は医師・看護師・救急救命士などの医療従事者です。
入力は、採血データと、端末内のルールベース判定結果（疑われる病態と根拠）です。患者の個人情報は含まれません。

以下の方針で日本語で回答してください。
- 診断を確定せず、「考えられる」「可能性がある」という表現で、根拠となる検査値を明示する。
- ルールベースの結果を鵜呑みにせず、検査値から妥当性を検討し、見落とされている可能性のある病態があれば挙げる。
- 緊急性の高い所見（危険値・ショックを示唆する値など）は最初に示す。
- 検体エラー（溶血・混入など）の可能性があれば指摘する。
- 薬剤の用量など具体的な治療指示は断定しない。施設の手順・ガイドライン・上級医への相談を促す。
- 見出しと箇条書きを使い、簡潔にまとめる。
''';

  /// 送信用の検査データ要約（個人情報を含まない）。
  static String buildLabSummary({
    required LabCatalog catalog,
    required LabSet current,
    LabSet? previous,
    required EvaluationResult evaluation,
  }) {
    final ctx = current.context;
    final sex = ctx.sex;
    final spec = effectiveSpecimen(current);
    final est = estimateSpecimen(current);
    final b = StringBuffer();
    b.writeln('## 患者背景');
    b.writeln('- 年齢: ${ctx.age != null ? '${ctx.age}歳' : '不明'}');
    b.writeln('- 性別: ${sex == 'M' ? '男性' : sex == 'F' ? '女性' : '不明'}');
    b.writeln();
    b.writeln('## 今回の採血データ（項目｜値｜基準値｜単位｜判定）');
    final prev = previous?.valueMap ?? const <String, double>{};
    for (final v in current.values) {
      if (v.value == null) continue;
      final def = catalog.byCode(v.code);
      if (def == null) continue;
      final r = catalog.rangeFor(v, sex: sex, specimen: spec);
      final f = catalog.flagFor(v, sex: sex, specimen: spec);
      final mark = switch (f) {
        LabFlag.critHigh => '危険値↑',
        LabFlag.critLow => '危険値↓',
        LabFlag.high => '↑',
        LabFlag.low => '↓',
        _ => '',
      };
      final p = prev[v.code];
      final pv = p == null ? '' : '（前回 ${formatNumber(p, def.decimals)}）';
      b.writeln('- ${def.name}｜${formatNumber(v.value!, def.decimals)}$pv｜${r.format(def.decimals)}｜${def.unit}｜$mark');
    }
    final derived = computeDerived(current);
    if (derived.isNotEmpty) {
      b.writeln();
      b.writeln('## 計算値');
      for (final d in derived.values) {
        b.writeln('- ${d.label}: ${formatNumber(d.value, d.decimals)} ${d.unit}（${d.formula}）');
      }
    }
    if (hasBloodGas(current.valueMap)) {
      b.writeln();
      b.writeln('## 血液ガスの検体種別');
      b.writeln('- ${est.type == SpecimenType.unknown ? '判別困難（動脈血として評価）' : spec.label}'
          '${est.fromSheet ? '（用紙に記載）' : est.manual ? '（手動設定）' : '（推定）'}');
      final f = resolveFio2(current.oxygen);
      b.writeln('- 酸素投与: ${current.oxygen.device ?? '記載なし（未確認）'}'
          '${current.oxygen.flowLpm != null ? ' ${current.oxygen.flowLpm}L/分' : ''}'
          '${f.fio2 != null ? ' FiO₂ ${f.fio2!.toStringAsFixed(2)}${f.estimated ? '（推定）' : ''}' : ''}');
    }
    if (previous != null) {
      final days = current.takenAt.difference(previous.takenAt).inHours / 24;
      b.writeln();
      b.writeln('## 前回データとの間隔');
      b.writeln('- 約${days.toStringAsFixed(1)}日');
    }
    b.writeln();
    b.writeln('## 端末内ルールベース判定（採血データ${ctx.age != null || ctx.sex != null ? '＋年齢・性別' : ''}による評価）');
    if (evaluation.sampleWarnings.isNotEmpty) {
      b.writeln('### 検体エラーの可能性');
      for (final w in evaluation.sampleWarnings) {
        b.writeln('- ${w.name}: ${w.evidence.join('、')}');
      }
    }
    if (evaluation.diseases.isEmpty) {
      b.writeln('- 該当する病態なし');
    }
    for (var i = 0; i < evaluation.diseases.length && i < 12; i++) {
      final d = evaluation.diseases[i];
      b.writeln('${i + 1}. ${d.name}（可能性: ${d.likelihood}）');
      for (final e in d.support) {
        b.writeln('   - 根拠: ${e.text}${e.note != null ? '（${e.note}）' : ''}');
      }
      for (final e in d.against) {
        b.writeln('   - 否定的: ${e.text}${e.note != null ? '（${e.note}）' : ''}');
      }
    }
    return b.toString();
  }

  /// 個人情報を含めない評価（年齢・性別のみ使用）。
  static EvaluationResult privacySafeEvaluation(RuleEngine engine, LabSet current, LabSet? previous) {
    final copy = LabSet(
      id: current.id,
      takenAt: current.takenAt,
      values: current.values,
      specimen: current.specimen,
      oxygen: current.oxygen,
      context: PatientContext(age: current.context.age, sex: current.context.sex),
    );
    return engine.evaluate(copy, previous: previous, useContext: true);
  }

  static const initialRequest = '''
上記の採血データと判定結果について、次の構成で解説してください。
1. 緊急性の高い所見（あれば）
2. 病態の整理（主要な異常値のまとまりと、その解釈）
3. 考えられる疾患・病態と根拠（ルールベース判定の妥当性の検討を含む）
4. 追加で確認したい検査・診察所見
5. 注意点（検体エラーの可能性、評価の限界など）
6. 前回からの変化の解釈（前回データがある場合）
''';

  /// Messages API を呼び出す。[messages] は {role, content} のリスト（user から始まり交互）。
  Future<String> send({
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 16000,
      'system': systemPrompt,
      'messages': messages,
    };
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    };
    // 安全性分類器による拒否時に、サーバー側で別モデルへ自動フォールバックする（対応モデルのみ）
    if (model.startsWith('claude-opus-5') || model.startsWith('claude-sonnet-5-5') || model.startsWith('claude-fable')) {
      body['fallbacks'] = 'default';
      headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
    }
    http.Response res;
    try {
      res = await _client
          .post(Uri.parse(_endpoint), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(minutes: 5));
    } on TimeoutException {
      throw AiException('応答がタイムアウトしました。通信状況を確認して再度お試しください。');
    } catch (e) {
      throw AiException('通信に失敗しました（$e）');
    }
    final decoded = _tryDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      final msg = (decoded?['error'] as Map?)?['message'] ?? res.reasonPhrase;
      throw AiException(switch (res.statusCode) {
        401 => 'APIキーが無効です。設定画面で確認してください。',
        403 => 'このAPIキーでは利用できません（$msg）',
        404 => 'モデルが見つかりません。設定のモデル名を確認してください（$msg）',
        429 => '利用上限に達しました。しばらく待ってから再度お試しください。',
        529 || 500 || 502 || 503 => 'AIサービスが混雑しています。しばらく待ってから再度お試しください。',
        _ => 'AIの呼び出しに失敗しました（${res.statusCode}: $msg）',
      });
    }
    if (decoded == null) throw AiException('応答を解析できませんでした');
    final stop = decoded['stop_reason'];
    final text = ((decoded['content'] as List?) ?? const [])
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    if (stop == 'refusal' && text.trim().isEmpty) {
      throw AiException('AIがこの依頼への回答を控えました。質問の表現を変えてお試しください。');
    }
    if (stop == 'max_tokens') return '$text\n\n（※回答が長すぎるため途中で終了しました）';
    return text;
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// チャットの質問に個人情報らしき記載がないかの簡易チェック。
String? personalInfoWarning(String text) {
  if (RegExp(r'(氏名|名前|生年月日|住所|電話|カルテ番号|患者ID|ID\s*[:：]?\s*\d{3,})').hasMatch(text)) {
    return '氏名・生年月日・ID などの個人情報は入力しないでください。';
  }
  if (RegExp(r'(19|20)\d\d\s*[/年.-]\s*\d{1,2}\s*[/月.-]\s*\d{1,2}').hasMatch(text)) {
    return '日付（生年月日など）が含まれています。個人を特定できる情報は送信しないでください。';
  }
  if (RegExp(r'0\d{1,4}-?\d{1,4}-?\d{3,4}').hasMatch(text)) {
    return '電話番号のような数字が含まれています。個人情報は送信しないでください。';
  }
  return null;
}
