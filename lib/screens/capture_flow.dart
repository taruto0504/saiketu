import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/ocr_parser.dart';
import '../widgets/common.dart';
import 'confirm_screen.dart';
import 'manual_entry_screen.dart';

enum CaptureSource { camera, photo, manual }

/// 取り込み開始（カメラ / 写真 / 手入力）→ 確認画面へ。
Future<void> startCapture(BuildContext context, CaptureSource source, {String? folderId}) async {
  final services = context.read<AppServices>();
  if (source == CaptureSource.manual) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ManualEntryScreen(folderId: folderId)));
    return;
  }

  String? path;
  try {
    if (source == CaptureSource.camera) {
      try {
        path = await services.ocr.scanDocument();
      } on PlatformException catch (e) {
        // 書類スキャナが使えない端末では通常のカメラ撮影にフォールバック
        if (!context.mounted) return;
        showSnack(context, '自動検出が使えないため通常撮影に切り替えます（${e.message ?? e.code}）');
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
        path = x?.path;
      } on MissingPluginException {
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
        path = x?.path;
      }
    } else {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
      path = x?.path;
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '画像を取得できませんでした: $e');
    return;
  }
  if (path == null || !context.mounted) return;

  ParsedSheet? parsed;
  String? error;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('端末内で読み取り中…')),
        ]),
      ),
    ),
  );
  try {
    final lines = await services.ocr.recognize(path);
    parsed = LabSheetParser(services.catalog).parse(lines);
    services.settings.stats.track(source == CaptureSource.camera ? 'read_camera' : 'read_photo');
  } catch (e) {
    error = '$e';
  } finally {
    // 撮影画像は保存しない（一時ファイルを削除）
    _deleteTemp(path);
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
