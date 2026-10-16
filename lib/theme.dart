import 'package:flutter/material.dart';

/// 検査値表示用の色（高値=赤・低値=青・危険値=赤背景・要確認=黄）。
@immutable
class LabColors extends ThemeExtension<LabColors> {
  const LabColors({
    required this.high,
    required this.low,
    required this.critBg,
    required this.critFg,
    required this.uncertainBg,
    required this.uncertainBorder,
    required this.improved,
    required this.worsened,
    required this.subtle,
  });

  final Color high;
  final Color low;
  final Color critBg;
  final Color critFg;
  final Color uncertainBg;
  final Color uncertainBorder;
  final Color improved;
  final Color worsened;
  final Color subtle;

  static const light = LabColors(
    high: Color(0xFFC62828),
    low: Color(0xFF1565C0),
    critBg: Color(0xFFFFE1E1),
    critFg: Color(0xFFB71C1C),
    uncertainBg: Color(0xFFFFF4C2),
    uncertainBorder: Color(0xFFE0B400),
    improved: Color(0xFF2E7D32),
    worsened: Color(0xFFC62828),
    subtle: Color(0xFFF3F6F8),
  );

  static const dark = LabColors(
    high: Color(0xFFFF7B7B),
    low: Color(0xFF7DB8FF),
    critBg: Color(0xFF5A1A1D),
    critFg: Color(0xFFFFB4B4),
    uncertainBg: Color(0xFF4A3D00),
    uncertainBorder: Color(0xFFD4AA00),
    improved: Color(0xFF7BD88F),
    worsened: Color(0xFFFF7B7B),
    subtle: Color(0xFF1E2529),
  );

  @override
  LabColors copyWith() => this;

  @override
  LabColors lerp(ThemeExtension<LabColors>? other, double t) => t < 0.5 ? this : (other as LabColors? ?? this);
}

extension LabColorsX on BuildContext {
  LabColors get lab => Theme.of(this).extension<LabColors>()!;
}

const seedColor = Color(0xFF0E7C9B); // メディカルブルー〜ティール

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: b,
    surface: b == Brightness.light ? Colors.white : const Color(0xFF111619),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF5F7F9) : const Color(0xFF0B0F11),
    extensions: [b == Brightness.light ? LabColors.light : LabColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: b == Brightness.light ? Colors.white : const Color(0xFF111619),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56), // 手袋でも押しやすい大きさ
        textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      labelTextStyle: WidgetStateProperty.all(base.textTheme.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
    ),
  );
}

/// 数値表示用（等幅数字・大きめ）。
TextStyle numberStyle(BuildContext context, {double size = 22, FontWeight weight = FontWeight.w700, Color? color}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );

const disclaimerText = '本アプリは医療従事者の診療を補助する目的で提供するものであり、診断・治療を行うものではありません。'
    '表示される疾患・A/V推定・AIアドバイスは参考情報です。最終的な判断は必ず医療従事者自身が行ってください。'
    '本アプリの利用により生じたいかなる損害についても、開発者は責任を負いません。';
