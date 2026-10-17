import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import 'pii.dart';
import 'rule_engine.dart';

/// 端末内の暗号化データベース（SQLCipher）。
///
/// 暗号鍵は端末のセキュア領域（iOS: Keychain / Android: Keystore）にランダム生成して保存します。
/// 氏名・生年月日などの個人情報は保存しません（フォルダ名はユーザーが任意に付ける識別子）。
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;
  static const _keyName = 'labsight_db_key_v1';

  /// テスト用（任意の Database を使う）。
  AppDatabase.withDatabase(this._db);

  static const schemaVersion = 1;

  static Future<void> configure(Database db) => db.execute('PRAGMA foreign_keys = ON');

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        memo TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE lab_sets(
        id TEXT PRIMARY KEY,
        folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        taken_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        values_json TEXT NOT NULL,
        context_json TEXT NOT NULL,
        specimen_json TEXT NOT NULL,
        oxygen_json TEXT NOT NULL,
        source TEXT NOT NULL,
        memo TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE INDEX idx_sets_folder ON lab_sets(folder_id, taken_at)');
    await db.execute('''
      CREATE TABLE evaluations(
        id TEXT PRIMARY KEY,
        lab_set_id TEXT NOT NULL REFERENCES lab_sets(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        result_json TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE ai_chats(
        lab_set_id TEXT PRIMARY KEY REFERENCES lab_sets(id) ON DELETE CASCADE,
        updated_at INTEGER NOT NULL,
        messages_json TEXT NOT NULL
      )''');
    await db.execute('CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  static Future<AppDatabase> open(FlutterSecureStorage storage) async {
    var key = await storage.read(key: _keyName);
    if (key == null) {
      final r = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)));
      await storage.write(key: _keyName, value: key);
    }
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'labsight.db'),
      password: key,
      version: schemaVersion,
      onConfigure: configure,
      onCreate: createSchema,
    );
    return AppDatabase._(db);
  }

  // ───────── フォルダ ─────────

  Future<List<Folder>> folders() async {
    final rows = await _db.rawQuery('''
      SELECT f.*, COUNT(s.id) AS n, MAX(s.taken_at) AS last
      FROM folders f LEFT JOIN lab_sets s ON s.folder_id = f.id
      GROUP BY f.id ORDER BY f.updated_at DESC''');
    return rows.map((r) {
      final f = Folder(
        id: r['id'] as String,
        name: r['name'] as String,
        memo: r['memo'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );
      f.setCount = (r['n'] as int?) ?? 0;
      final last = r['last'] as int?;
      f.lastTakenAt = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      return f;
    }).toList();
  }

  /// 個人情報を削除したフォルダ名（空になったら日時の名前）。
  static String safeFolderName(String name, DateTime createdAt) {
    final n = scrubPII(name).text.trim();
    if (n.isNotEmpty && n != piiMark) return n;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ケース ${createdAt.month}/${createdAt.day} ${two(createdAt.hour)}:${two(createdAt.minute)}';
  }

  Future<void> saveFolder(Folder f) async {
    // 氏名・IDなどは保存しない
    f.name = safeFolderName(f.name, f.createdAt);
    f.memo = scrubPII(f.memo).text;
    f.updatedAt = DateTime.now();
    await _db.insert(
      'folders',
      {
        'id': f.id,
        'name': f.name,
        'memo': f.memo,
        'created_at': f.createdAt.millisecondsSinceEpoch,
        'updated_at': f.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> touchFolder(String id) =>
      _db.update('folders', {'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteFolder(String id) => _db.delete('folders', where: 'id = ?', whereArgs: [id]);

  // ───────── 採血データ ─────────

  Future<List<LabSet>> labSets(String folderId) async {
    final rows = await _db.query('lab_sets', where: 'folder_id = ?', whereArgs: [folderId], orderBy: 'taken_at ASC');
    return rows.map(_rowToSet).toList();
  }

  Future<LabSet?> labSet(String id) async {
    final rows = await _db.query('lab_sets', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _rowToSet(rows.first);
  }

  /// 同じフォルダ内で、指定日時より前の直近のデータ（前回値）。
  Future<LabSet?> previousOf(LabSet s) async {
    if (s.folderId == null) return null;
    final rows = await _db.query('lab_sets',
        where: 'folder_id = ? AND taken_at < ? AND id != ?',
        whereArgs: [s.folderId, s.takenAt.millisecondsSinceEpoch, s.id],
        orderBy: 'taken_at DESC',
        limit: 1);
    return rows.isEmpty ? null : _rowToSet(rows.first);
  }

  LabSet _rowToSet(Map<String, Object?> r) => LabSet(
        id: r['id'] as String,
        folderId: r['folder_id'] as String,
        takenAt: DateTime.fromMillisecondsSinceEpoch(r['taken_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        values: LabSet.valuesFromJson(r['values_json'] as String),
        context: PatientContext.fromJson(jsonDecode(r['context_json'] as String) as Map<String, dynamic>),
        specimen: SpecimenInfo.fromJson(jsonDecode(r['specimen_json'] as String) as Map<String, dynamic>),
        oxygen: OxygenInfo.fromJson(jsonDecode(r['oxygen_json'] as String) as Map<String, dynamic>),
        source: r['source'] as String,
        memo: r['memo'] as String,
      );

  Future<void> saveLabSet(LabSet s) async {
    if (s.folderId == null) throw StateError('フォルダが未指定です');
    s.context.scrubPersonalInfo();
    s.memo = scrubPII(s.memo).text;
    await _db.insert(
      'lab_sets',
      {
        'id': s.id,
        'folder_id': s.folderId,
        'taken_at': s.takenAt.millisecondsSinceEpoch,
        'created_at': s.createdAt.millisecondsSinceEpoch,
        'values_json': s.valuesJson(),
        'context_json': jsonEncode(s.context.toJson()),
        'specimen_json': jsonEncode(s.specimen.toJson()),
        'oxygen_json': jsonEncode(s.oxygen.toJson()),
        'source': s.source,
        'memo': s.memo,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await touchFolder(s.folderId!);
  }

  Future<void> deleteLabSet(String id) => _db.delete('lab_sets', where: 'id = ?', whereArgs: [id]);

  // ───────── 評価履歴 ─────────

  Future<void> saveEvaluation(String labSetId, EvaluationResult e) => _db.insert(
        'evaluations',
        {'id': e.id, 'lab_set_id': labSetId, 'created_at': e.at.millisecondsSinceEpoch, 'result_json': jsonEncode(e.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<EvaluationResult>> evaluations(String labSetId) async {
    final rows = await _db.query('evaluations', where: 'lab_set_id = ?', whereArgs: [labSetId], orderBy: 'created_at ASC');
    return rows.map((r) => EvaluationResult.fromJson(jsonDecode(r['result_json'] as String) as Map<String, dynamic>)).toList();
  }

  // ───────── AIチャット ─────────

  Future<List<Map<String, String>>> aiChat(String labSetId) async {
    final rows = await _db.query('ai_chats', where: 'lab_set_id = ?', whereArgs: [labSetId]);
    if (rows.isEmpty) return [];
    return (jsonDecode(rows.first['messages_json'] as String) as List)
        .map((e) => (e as Map).cast<String, String>())
        .toList();
  }

  Future<void> saveAiChat(String labSetId, List<Map<String, String>> messages) => _db.insert(
        'ai_chats',
        {'lab_set_id': labSetId, 'updated_at': DateTime.now().millisecondsSinceEpoch, 'messages_json': jsonEncode(_scrubChat(messages))},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  static List<Map<String, String>> _scrubChat(List<Map<String, String>> messages) => [
        for (final m in messages)
          m['role'] == 'user' ? {...m, 'content': scrubPII(m['content'] ?? '').text} : m,
      ];

  /// 保存済みのデータから個人情報を削除する（以前のバージョンで入力されたものを含む）。
  /// 1回だけ実行する。削除した箇所の数を返す。
  Future<int> scrubStoredPersonalInfo() async {
    if (await getKv('pii_scrub_v1') != null) return 0;
    var n = 0;
    for (final f in await folders()) {
      final name = safeFolderName(f.name, f.createdAt);
      final memo = scrubPII(f.memo);
      if (name != f.name || memo.removed > 0) {
        n += memo.removed + (name != f.name ? 1 : 0);
        await _db.update('folders', {'name': name, 'memo': memo.text}, where: 'id = ?', whereArgs: [f.id]);
      }
    }
    for (final r in await _db.query('lab_sets', columns: ['id', 'context_json', 'memo'])) {
      final c = PatientContext.fromJson(jsonDecode(r['context_json'] as String) as Map<String, dynamic>);
      final memo = scrubPII(r['memo'] as String);
      final k = c.scrubPersonalInfo() + memo.removed;
      if (k > 0) {
        n += k;
        await _db.update('lab_sets', {'context_json': jsonEncode(c.toJson()), 'memo': memo.text}, where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    for (final r in await _db.query('ai_chats')) {
      final msgs = (jsonDecode(r['messages_json'] as String) as List).map((e) => (e as Map).cast<String, String>()).toList();
      final clean = _scrubChat(msgs);
      if (jsonEncode(clean) != jsonEncode(msgs)) {
        n++;
        await _db.update('ai_chats', {'messages_json': jsonEncode(clean)}, where: 'lab_set_id = ?', whereArgs: [r['lab_set_id']]);
      }
    }
    await setKv('pii_scrub_v1', '1');
    return n;
  }

  // ───────── 自動削除 ─────────

  /// 登録から [days] 日を過ぎたデータを削除し、空になったフォルダも削除する。
  Future<int> purgeOlderThan(int days) async {
    final limit = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final n = await _db.delete('lab_sets', where: 'created_at < ?', whereArgs: [limit]);
    await _db.delete('folders',
        where: 'updated_at < ? AND id NOT IN (SELECT DISTINCT folder_id FROM lab_sets)', whereArgs: [limit]);
    return n;
  }

  /// 全フォルダ・採血データ・評価履歴・AIチャットを削除（設定は残す）。
  Future<void> deleteAllRecords() => _db.delete('folders');

  // ───────── 設定（暗号化DB内に保存） ─────────

  Future<String?> getKv(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setKv(String key, String? value) async {
    if (value == null) {
      await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<LabItemDef>> customItems() async {
    final s = await getKv('custom_items');
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => LabItemDef.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveCustomItems(List<LabItemDef> items) =>
      setKv('custom_items', jsonEncode(items.map((e) => e.toJson()).toList()));

  Future<Map<String, RefRange>> userRanges() async {
    final s = await getKv('user_ranges');
    if (s == null) return {};
    final m = jsonDecode(s) as Map<String, dynamic>;
    return m.map((k, v) {
      final l = v as List;
      return MapEntry(k, RefRange((l[0] as num?)?.toDouble(), (l[1] as num?)?.toDouble(), source: RefSource.user));
    });
  }

  Future<void> saveUserRanges(Map<String, RefRange> r) =>
      setKv('user_ranges', jsonEncode(r.map((k, v) => MapEntry(k, [v.low, v.high]))));
}
