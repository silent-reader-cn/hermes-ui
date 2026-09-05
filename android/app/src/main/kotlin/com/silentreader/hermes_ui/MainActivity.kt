package com.silentreader.hermes_ui

import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 把本地文件路径转换为 FileProvider content:// URI，
        // 供 ACTION_VIEW Intent 跨应用打开（Android 7+ 禁止裸 file:// URI）。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getShareUri" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_ARGUMENT", "path is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "file does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.provider",
                            file
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("URI_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.silentreader.hermes_ui/file_share"
    }
}
