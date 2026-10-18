package com.example.khmer_recap_ai

import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.khmer_recap_ai/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(context, arrayOf(path), null) { scannedPath, uri ->
                            result.success(uri?.toString() ?: scannedPath)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                "saveVideoToGallery" -> {
                    val srcPath = call.argument<String>("srcPath")
                    val title = call.argument<String>("title") ?: "KhmerRecap_${System.currentTimeMillis()}"
                    if (srcPath == null) {
                        result.error("INVALID_PATH", "srcPath is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val srcFile = java.io.File(srcPath)
                        if (!srcFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source file does not exist", null)
                            return@setMethodCallHandler
                        }

                        var savedUri: android.net.Uri? = null
                        var savedFilePath: String? = null

                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            val values = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.Video.Media.DISPLAY_NAME, "$title.mp4")
                                put(android.provider.MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                                put(android.provider.MediaStore.Video.Media.RELATIVE_PATH, "DCIM/KhmerRecap")
                                put(android.provider.MediaStore.Video.Media.IS_PENDING, 1)
                            }

                            val collection = android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            savedUri = contentResolver.insert(collection, values)

                            if (savedUri != null) {
                                contentResolver.openOutputStream(savedUri)?.use { out ->
                                    java.io.FileInputStream(srcFile).use { input ->
                                        input.copyTo(out)
                                    }
                                }
                                values.clear()
                                values.put(android.provider.MediaStore.Video.Media.IS_PENDING, 0)
                                contentResolver.update(savedUri, values, null, null)
                            }

                            // Query real physical path for playback if available
                            val realDcimFile = java.io.File(
                                android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DCIM),
                                "KhmerRecap/$title.mp4"
                            )
                            if (realDcimFile.exists()) {
                                savedFilePath = realDcimFile.absolutePath
                            }
                        } else {
                            // Legacy Android (pre-Android 10): copy once and notify media scanner
                            try {
                                val dcimDir = java.io.File(
                                    android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DCIM),
                                    "KhmerRecap"
                                )
                                if (!dcimDir.exists()) {
                                    dcimDir.mkdirs()
                                }
                                val directFile = java.io.File(dcimDir, "$title.mp4")
                                srcFile.copyTo(directFile, overwrite = true)
                                savedFilePath = directFile.absolutePath
                                MediaScannerConnection.scanFile(context, arrayOf(directFile.absolutePath), arrayOf("video/mp4"), null)
                            } catch (_: Exception) {}
                        }

                        // Return real physical file path for playback, never a content:// URI!
                        result.success(savedFilePath ?: srcPath)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.localizedMessage, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
