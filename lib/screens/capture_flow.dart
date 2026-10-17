import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/ocr_parser.dart';
import '../widgets/common.dart';
import 'confirm_screen.dart';
import 'manual_entry_screen.dart';

enum CaptureSource { camera, photo, manual }

/// 一度に読み取るページ数の上限。
const maxPages = 10;

/// 通常のカメラで1枚ずつ続けて撮影する（書類スキャナが使えない端末用）。
Future<void> _cameraLoop(BuildContext context, List<String> paths) async {
  while (paths.length < maxPages) {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
    if (x == null) return;
    paths.add(x.path);
    if (!context.mounted || paths.length >= maxPages) return;
    final more = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${paths.length}ページ撮影しました'),
        content: const Text('続けて次のページを撮影しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('読み取りへ進む')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('次のページを撮影')),
        ],
      ),
    );
    if (more != true) return;
  }
}

/// 複数ページの読み取り結果を1つにまとめる。
/// ページ間で同じ項目の値が食い違う場合は要確認にする。
ParsedSheet parsePages(LabSheetParser parser, List<List<OcrLine>> pages) {
  // ページごとに縦位置をずらして、別ページの行が1行にまとまらないようにする
  final all = <OcrLine>[
    for (var i = 0; i < pages.length; i++)
      for (final l in pages[i])
        OcrLine(l.text, left: l.left, top: l.top + i * 1e6, right: l.right, bottom: l.bottom + i * 1e6, confidence: l.confidence),
  ];
  final merged = parser.parse(all);
  if (pages.length < 2) return merged;
  final perPage = [for (final p in pages) parser.parse(p).values];
  for (final v in merged.values) {
    final first = perPage.indexWhere((vals) => vals.any((x) => x.code == v.code));
    for (var j = 0; j < perPage.length; j++) {
      if (j == first) continue;
      for (final o in perPage[j].where((x) => x.code == v.code && x.value != v.value)) {
        v.uncertain = true;
        final def = parser.catalog.byCode(v.code);
        final shown = def?.formatValue(o.value!) ?? formatNumber(o.value!, 2);
        v.warnings.add('${j + 1}ページ目にも別の値（$shown）があります。どちらが今回の値か確認してください');
      }
    }
  }
  return merged;
}

/// 取り込み開始（カメラ / 写真 / 手入力）→ 確認画面へ。
Future<void> startCapture(BuildContext context, CaptureSource source, {String? folderId}) async {
  final services = context.read<AppServices>();
  if (source == CaptureSource.manual) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ManualEntryScreen(folderId: folderId)));
    return;
  }

  final paths = <String>[];
  try {
    if (source == CaptureSource.camera) {
      try {
        // 書類スキャナは続けて複数ページを撮影できる
        paths.addAll(await services.ocr.scanDocument());
      } on PlatformException catch (e) {
        // 書類スキャナが使えない端末では通常のカメラ撮影にフォールバック（1枚ずつ続けて撮影）
        if (!context.mounted) return;
        showSnack(context, '自動検出が使えないため通常撮影に切り替えます（${e.message ?? e.code}）');
        await _cameraLoop(context, paths);
      } on MissingPluginException {
        if (!context.mounted) return;
        await _cameraLoop(context, paths);
      }
    } else {
      final xs = await ImagePicker().pickMultiImage(imageQuality: 100, limit: maxPages);
      paths.addAll(xs.map((x) => x.path));
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '画像を取得できませんでした: $e');
    for (final p in paths) {
      _deleteTemp(p);
    }
    return;
  }
  if (paths.length > maxPages) {
    for (final p in paths.sublist(maxPages)) {
      _deleteTemp(p);
    }
    paths.removeRange(maxPages, paths.length);
    if (context.mounted) showSnack(context, '一度に読み取れるのは $maxPagesページまでです');
  }
  if (paths.isEmpty || !context.mounted) return;

  ParsedSheet? parsed;
  String? error;
  final failed = <int>[];
  final progress = ValueNotifier<int>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: progress,
              builder: (_, i, _) => Text(paths.length > 1 ? '端末内で読み取り中… ${i + 1} / ${paths.length} ページ' : '端末内で読み取り中…'),
            ),
          ),
        ]),
      ),
    ),
  );
  try {
    final pages = <List<OcrLine>>[];
    for (var i = 0; i < paths.length; i++) {
      progress.value = i;
      try {
        pages.add(await services.ocr.recognize(paths[i]));
      } catch (e) {
        if (paths.length == 1) rethrow;
        failed.add(i + 1);
        pages.add(const []);
      }
    }
    if (failed.length == paths.length) throw StateError('すべてのページで読み取りに失敗しました');
    parsed = parsePages(LabSheetParser(services.catalog), pages);
    services.settings.stats.track(source == CaptureSource.camera ? 'read_camera' : 'read_photo');
  } catch (e) {
    error = '$e';
  } finally {
    // 撮影画像は保存しない（一時ファイルを削除）
    for (final p in paths) {
      _deleteTemp(p);
    }
    progress.dispose();
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();
  if (parsed == null) {
    showSnack(context, '読み取りに失敗しました: $error');
    return;
  }

  final set = LabSet(
    folderId: null,
    takenAt: parsed.takenAt,
    values: parsed.values,
    specimen: SpecimenInfo(sheetLabel: parsed.specimen),
    oxygen: parsed.oxygen,
    context: PatientContext(age: parsed.age, sex: parsed.sex),
    source: source == CaptureSource.camera ? 'camera' : 'photo',
  );
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ConfirmScreen(
        set: set,
        targetFolderId: folderId,
        fromOcr: true,
        skippedPersonalRows: parsed!.skippedPersonalRows,
        pageCount: paths.length,
        failedPages: failed,
      ),
    ),
  );
}

void _deleteTemp(String path) {
  try {
    final f = File(path);
    final p = f.path.toLowerCase();
    if (p.contains('/tmp') || p.contains('cache') || p.contains('scan_')) {
      if (f.existsSync()) f.deleteSync();
    }
  } catch (_) {}
}
