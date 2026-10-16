# ML Kit 文字認識：日本語モデルのみ同梱し、他言語モデルのクラスは参照のみのため警告を抑制
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**

# SQLCipher（暗号化DB）はネイティブコードから呼ばれるため保持
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }
