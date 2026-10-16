import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_parser.dart';

/// 端末内OCR。iOS は Vision（ネイティブ実装・MethodChannel）、Android は ML Kit を使う。
/// 画像は端末外へ送信しない。
class OcrService {
  static const _ios = MethodChannel('labsight/vision');

  /// 画像ファイルから文字を認識する。
  Future<List<OcrLine>> recognize(String imagePath) async {
    if (Platform.isIOS) {
      final res = await _ios.invokeListMethod<Map<dynamic, dynamic>>('recognize', {'path': imagePath});
      return [
        for (final m in res ?? const [])
          OcrLine(
            m['text'] as String,
            left: (m['left'] as num).toDouble(),
            top: (m['top'] as num).toDouble(),
            right: (m['right'] as num).toDouble(),
            bottom: (m['bottom'] as num).toDouble(),
            confidence: (m['confidence'] as num?)?.toDouble(),
          )
      ];
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return [
        for (final b in result.blocks)
          for (final l in b.lines)
            OcrLine(
              l.text,
              left: l.boundingBox.left,
              top: l.boundingBox.top,
              right: l.boundingBox.right,
              bottom: l.boundingBox.bottom,
              confidence: l.confidence,
            )
      ];
    } finally {
      await recognizer.close();
    }
  }

  /// 書類の輪郭を自動検出して撮影する（iOS: VisionKit / Android: ML Kit Document Scanner）。
  /// 撮影画像のパスを返す。キャンセル時は null。
  Future<String?> scanDocument() async {
    if (Platform.isIOS) {
      final paths = await _ios.invokeListMethod<String>('scanDocument');
      return (paths == null || paths.isEmpty) ? null : paths.first;
    }
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        pageLimit: 1,
        mode: ScannerMode.base,
        isGalleryImport: false,
      ),
    );
    try {
      final r = await scanner.scanDocument();
      final images = r.images;
      if (images == null || images.isEmpty) return null;
      final p = images.first;
      return p.startsWith('file://') ? Uri.parse(p).toFilePath() : p;
    } on PlatformException catch (e) {
      if (e.code.toLowerCase().contains('cancel')) return null;
      rethrow;
    } finally {
      await scanner.close();
    }
  }
}
