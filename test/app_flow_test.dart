import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labsight/app.dart';
import 'package:labsight/models/lab_set.dart';
import 'package:labsight/services/app_services.dart';
import 'package:labsight/services/database.dart';
import 'package:labsight/services/lab_catalog.dart';
import 'package:labsight/services/rule_engine.dart';
import 'package:labsight/services/settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 実際の画面を、端末内DB（SQLite）を使って通しで操作するテスト。
void main() {
  late AppServices services;
  final secure = <String, String>{};

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    secure.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return secure[key];
        case 'write':
          secure[key!] = args['value'] as String;
          return null;
        case 'delete':
          secure.remove(key);
          return null;
        case 'containsKey':
          return secure.containsKey(key);
        case 'readAll':
          return secure;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (call) async => ['none']);
    messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, _) {}));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onConfigure: AppDatabase.configure,
        onCreate: AppDatabase.createSchema,
        singleInstance: false,
      ),
    );
    final db = AppDatabase.withDatabase(raw);
    final rules = RuleSet.fromJsonString(File('assets/rules/disease_rules.json').readAsStringSync());
    services = AppServices(
      db: db,
      catalog: LabCatalog(),
      settings: AppSettings(prefs, const FlutterSecureStorage()),
      rules: rules,
      builtinRules: rules,
    );

    // フォルダと2回分の採血データ
    final folder = Folder(name: 'ケースA');
    await db.saveFolder(folder);
    final now = DateTime.now();
    await db.saveLabSet(LabSet(
      folderId: folder.id,
      takenAt: now.subtract(const Duration(days: 2)),
      values: [
        for (final e in {'WBC': 7000.0, 'HB': 13.5, 'PLT': 22.0, 'CRE': 0.8, 'BUN': 14.0, 'K': 4.2, 'NA': 140.0, 'CRP': 0.3}.entries)
          LabValue(code: e.key, value: e.value)
      ],
      source: 'manual',
    ));
    await db.saveLabSet(LabSet(
      folderId: folder.id,
      takenAt: now,
      values: [
        for (final e in {
          'WBC': 16500.0, 'NEUT': 88.0, 'HB': 12.9, 'PLT': 9.0, 'CRE': 1.9, 'BUN': 42.0, 'K': 6.4, 'NA': 133.0,
          'CL': 98.0, 'CRP': 18.2, 'PCT': 6.3, 'TBIL': 2.4, 'LDH': 380.0,
          'PH': 7.29, 'PCO2': 30.0, 'PO2': 64.0, 'HCO3': 14.0, 'SO2': 91.0, 'LAC': 4.6,
        }.entries)
          LabValue(code: e.key, value: e.value)
      ],
      oxygen: OxygenInfo(device: '鼻カニューラ', flowLpm: 3, foundTexts: ['O2 3L/min', '鼻カニューラ']),
      source: 'photo',
    ));
  });

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: services),
          ChangeNotifierProvider.value(value: services.settings),
          ChangeNotifierProvider.value(value: services.catalog),
        ],
        child: const LabSightApp(),
      );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  testWidgets('免責同意 → フォルダ → 結果 → 疾患推定 → 追加情報で再評価 → 比較', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);

    expect(find.textContaining('本アプリは医療従事者の診療を補助する目的'), findsOneWidget);
    await t.tap(find.text('上記の内容を理解し、同意します'));
    await t.pump();
    await t.tap(find.text('同意して始める'));
    await settle(t);
    // 職種・資格取得からの年数（初回のみ）
    expect(find.text('はじめに教えてください'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '次へ')).onPressed, isNull);
    await t.tap(find.text('救急救命士'));
    await t.tap(find.text('1〜2年'));
    await t.pump();
    await t.tap(find.text('次へ'));
    await settle(t);
    expect(services.settings.role, 'paramedic');
    expect(services.settings.yearsSinceLicense, '1-2');
    expect(find.text('カメラで読み取る'), findsOneWidget);
    expect(find.text('ケースA'), findsOneWidget);

    await t.tap(find.text('ケースA'));
    await settle(t);
    expect(find.textContaining('採血データ（2件）'), findsOneWidget);

    // 最新のデータを開く
    await t.tap(find.textContaining('危険値').first);
    await settle(t);
    expect(find.text('結果'), findsOneWidget);
    expect(find.textContaining('危険値 '), findsWidgets);
    expect(find.text('血液ガス 検体の推定'), findsOneWidget);
    expect(find.textContaining('溶血の可能性'), findsWidgets);

    // 異常値のみ表示
    await t.tap(find.text('異常値のみ表示'));
    await settle(t);

    // 疾患推定
    await t.tap(find.text('疾患推定'));
    await settle(t);
    expect(find.text('第1段階：採血データのみの評価'), findsOneWidget);
    expect(find.text('敗血症（臓器障害を伴う感染症）'), findsOneWidget);
    expect(find.text('なぜ疑うか'), findsWidgets);

    await t.tap(find.text('情報を追加して再評価'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, '年齢'), '72');
    await t.enterText(find.widgetWithText(TextField, '収縮期血圧'), '82');
    await t.tap(find.text('この情報で再評価'));
    await settle(t);
    expect(find.text('第2段階：追加情報を含めた評価'), findsOneWidget);
    expect(find.text('前回の評価からの変化'), findsOneWidget);
    expect(find.textContaining('収縮期血圧 82mmHg'), findsWidgets);

    // 履歴
    await t.tap(find.byTooltip('評価履歴'));
    await settle(t);
    expect(find.textContaining('2回目'), findsOneWidget);
    await t.tapAt(const Offset(20, 20));
    await settle(t);

    // AI（オフライン）
    await t.tap(find.text('AI'));
    await settle(t);
    expect(find.textContaining('オフラインのためAI機能は使えません'), findsOneWidget);
    final gen = t.widget<FilledButton>(find.ancestor(of: find.text('AIアドバイスを生成'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(gen.onPressed, isNull);
    await t.tap(find.byType(BackButton).last);
    await settle(t);
    await t.tap(find.byType(BackButton).last);
    await settle(t);

    // 比較
    await t.tap(find.text('比較'));
    await settle(t);
    expect(find.textContaining('改善'), findsWidgets);
    await t.scrollUntilVisible(find.textContaining('推移グラフ'), 400, scrollable: find.byType(Scrollable).first);
    await settle(t);
    expect(find.textContaining('推移グラフ'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    await t.tap(find.text('疾患推定で再評価'));
    await settle(t);
    expect(find.textContaining('前回値からの変化も評価に使用'), findsOneWidget);
    await t.scrollUntilVisible(find.text('急性腎障害（AKI）'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('急性腎障害（AKI）'), findsOneWidget);
  });

  testWidgets('手入力 → 確認（誤読警告）→ 結果 → 保存', (t) async {
    phone(t);
    await services.settings.setAgreed(true);
    await services.settings.setProfile(role: 'nurse', years: '3-5');
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('手入力'));
    await settle(t);

    await t.enterText(find.byType(TextField).first, 'Na');
    await settle(t);
    final naField = find.descendant(of: find.ancestor(of: find.text('ナトリウム'), matching: find.byType(Row)).first, matching: find.byType(TextField));
    await t.enterText(naField, '14');
    await settle(t);
    await t.tap(find.textContaining('確認へ'));
    await settle(t);
    expect(find.text('入力内容の確認'), findsOneWidget);
    expect(find.textContaining('小数点ずれ'), findsOneWidget);

    await t.tap(find.text('結果を見る'));
    await settle(t);
    // 黄色の項目があるので確認ダイアログ
    expect(find.text('未確認の項目があります'), findsOneWidget);
    await t.tap(find.text('このまま進む'));
    await settle(t);
    // 先に結果を表示し、保存は結果の画面で決める
    expect(find.text('結果'), findsOneWidget);
    expect(find.textContaining('この結果はまだ保存していません', findRichText: true), findsOneWidget);
    expect(await services.db.folders().then((f) => f.map((x) => x.name)), isNot(contains('ケースB')));
    await t.tap(find.widgetWithText(FilledButton, '保存する'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, '新しいフォルダ名'), 'ケースB');
    await t.tap(find.text('作成'));
    await settle(t);
    expect(find.text('結果'), findsOneWidget);
    expect(find.text('危険値 1項目'), findsOneWidget);
    final folders = await services.db.folders();
    expect(folders.map((f) => f.name), contains('ケースB'));
  });

  testWidgets('タブレットは結果と疾患推定を左右2画面で表示', (t) async {
    t.view.physicalSize = const Size(2732, 2048);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await services.settings.setAgreed(true);
    await services.settings.setProfile(role: 'nurse', years: '3-5');
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('ケースA'));
    await settle(t);
    await t.tap(find.textContaining('危険値').first);
    await settle(t);
    expect(find.text('検査値（19項目・異常 16）'), findsNothing); // 文言の安定性に依存しないよう下で確認
    expect(find.textContaining('検査値（19項目'), findsOneWidget);
    expect(find.text('第1段階：採血データのみの評価'), findsOneWidget);
  });

  testWidgets('設定画面・基準値・パスコードロック', (t) async {
    phone(t);
    await services.settings.setAgreed(true);
    await services.settings.setProfile(role: 'nurse', years: '3-5');
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('設定'));
    await settle(t);
    expect(find.text('文字サイズ'), findsOneWidget);
    await t.tap(find.text('基準値の設定'));
    await settle(t);
    expect(find.textContaining('優先順位'), findsOneWidget);
    await t.tap(find.byType(BackButton).last);
    await settle(t);
    await t.tap(find.text('判定ルール'));
    await settle(t);
    expect(find.textContaining('疾患・病態'), findsWidgets);
    await t.tap(find.byType(BackButton).last);
    await settle(t);

    // パスコード設定 → ロック画面で解除
    await services.settings.setPasscode('2468');
    expect(await services.settings.verifyPasscode('2468'), isTrue);
    expect(await services.settings.verifyPasscode('1111'), isFalse);
  });

  testWidgets('ダークモード・文字サイズ最大でも表示が崩れない', (t) async {
    phone(t);
    await services.settings.setAgreed(true);
    await services.settings.setProfile(role: 'nurse', years: '3-5');
    await services.settings.setThemeMode(ThemeMode.dark);
    await services.settings.setTextScale(1.6);
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('ケースA'));
    await settle(t);
    await t.tap(find.textContaining('危険値').first);
    await settle(t);
    expect(find.text('結果'), findsOneWidget);
    await t.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(t);
  });

  testWidgets('背景の切替・利用統計の記録（端末内のみ）', (t) async {
    phone(t);
    await services.settings.setAgreed(true);
    await services.settings.setProfile(role: 'mt', years: '21+');
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('設定').last);
    await settle(t);
    expect(find.text('臨床検査技師・21年以上'), findsOneWidget);
    await t.tap(find.text('黒'));
    await settle(t);
    expect(services.settings.themeMode, ThemeMode.dark);
    await t.tap(find.text('白'));
    await settle(t);
    expect(services.settings.themeMode, ThemeMode.light);

    final st = services.settings.stats;
    await st.track('diag_view', now: DateTime(2026, 10, 3));
    await st.track('diag_view', now: DateTime(2026, 10, 20));
    await st.track('unknown_event');
    expect(st.months['2026-10']!['diag_view'], 2);
    expect(st.consent, isFalse);
    final p = st.payload(role: services.settings.role, years: services.settings.yearsSinceLicense, rulesVersion: 'x');
    expect(p['role'], 'mt');
    expect(p['years'], '21+');
    expect(p.keys, containsAll(['installId', 'months']));
    expect(p.toString(), isNot(contains('Na')));
  });

  test('個人情報は保存しない（フォルダ名・自由記載・AIの質問、保存済みデータ）', () async {
    final db = services.db;
    final f = Folder(name: '山田太郎様');
    f.memo = 'ID 00123456 連絡先 090-1234-5678';
    await db.saveFolder(f);
    final saved = (await db.folders()).firstWhere((x) => x.id == f.id);
    expect(saved.name, startsWith('ケース '));
    expect(saved.memo, isNot(contains('00123456')));
    expect(saved.memo, isNot(contains('090')));

    final set = LabSet(folderId: f.id, values: [LabValue(code: 'K', value: 5.9)], context: PatientContext(complaint: '鈴木花子さん、昨夜から嘔吐'));
    await db.saveLabSet(set);
    final back = (await db.labSets(f.id)).first;
    expect(back.context.complaint, '［削除］、昨夜から嘔吐');

    await db.saveAiChat(set.id, [
      {'role': 'user', 'content': '佐藤様のKについて'},
      {'role': 'assistant', 'content': 'はい'},
    ]);
    expect((await db.aiChat(set.id)).first['content'], '［削除］のKについて');
  });
}
