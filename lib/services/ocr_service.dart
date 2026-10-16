import 'package:flutter/services.dart';

import 'ocr_parser.dart';

/// 端末内OCR。iOS は Vision / VisionKit（ios/Runner/AppDelegate.swift）、
/// Android は ML Kit（android/.../MainActivity.kt）で、同じチャネルを使う。
/// 画像は端末外へ送信しない。
class OcrService {
  static const _channel = MethodChannel('labsight/vision');

  /// 画像ファイルから文字を認識する。
  Future<List<OcrLine>> recognize(String imagePath) async {
    final res = await _channel.invokeListMethod<Map<dynamic, dynamic>>('recognize', {'path': imagePath});
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

  /// 書類の輪郭を自動検出して撮影する。撮影画像のパスを返す。キャンセル時は null。
  /// 端末が対応していない場合は PlatformException。
  Future<String?> scanDocument() async {
    final paths = await _channel.invokeListMethod<String>('scanDocument');
    return (paths == null || paths.isEmpty) ? null : paths.first;
  }
}
