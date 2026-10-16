package jp.labsight.labsight

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth（生体認証）には FragmentActivity が必要
class MainActivity : FlutterFragmentActivity() {
    private var pendingScan: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 端末内OCR（ML Kit 日本語）と書類の自動検出撮影（ML Kit Document Scanner）。iOS の Vision 実装と同じチャネル
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "labsight/vision").setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> recognize(call.argument<String>("path"), result)
                "scanDocument" -> scanDocument(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun recognize(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("bad_args", "path is required", null)
            return
        }
        val image = try {
            InputImage.fromFilePath(this, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            result.error("bad_image", e.message, null)
            return
        }
        val recognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        recognizer.process(image)
            .addOnSuccessListener { text ->
                val lines = ArrayList<Map<String, Any?>>()
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        val b = line.boundingBox ?: continue
                        lines.add(
                            mapOf(
                                "text" to line.text,
                                "left" to b.left.toDouble(),
                                "top" to b.top.toDouble(),
                                "right" to b.right.toDouble(),
                                "bottom" to b.bottom.toDouble(),
                                "confidence" to line.confidence.toDouble(),
                            ),
                        )
                    }
                }
                recognizer.close()
                result.success(lines)
            }
            .addOnFailureListener { e ->
                recognizer.close()
                result.error("ocr_failed", e.message, null)
            }
    }

    private fun scanDocument(result: MethodChannel.Result) {
        if (pendingScan != null) {
            result.error("busy", "スキャン中です", null)
            return
        }
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(this)
            .addOnSuccessListener { sender ->
                try {
                    pendingScan = result
                    startIntentSenderForResult(sender, SCAN_REQUEST, null, 0, 0, 0)
                } catch (e: IntentSender.SendIntentException) {
                    pendingScan = null
                    result.error("unsupported", e.message, null)
                }
            }
            .addOnFailureListener { e -> result.error("unsupported", e.message, null) }
    }

    @Suppress("DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCAN_REQUEST) return
        val r = pendingScan ?: return
        pendingScan = null
        if (resultCode != Activity.RESULT_OK) {
            r.success(emptyList<String>())
            return
        }
        try {
            val uri = GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()?.imageUri
            if (uri == null) {
                r.success(emptyList<String>())
                return
            }
            // 一時ファイルにコピー（読み取り後に Dart 側で削除）
            val out = File(cacheDir, "scan_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
            r.success(listOf(out.absolutePath))
        } catch (e: Exception) {
            r.error("scan_failed", e.message, null)
        }
    }

    companion object {
        private const val SCAN_REQUEST = 0x4C53
    }
}
