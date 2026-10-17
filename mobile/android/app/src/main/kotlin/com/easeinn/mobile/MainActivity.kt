package com.easeinn.mobile

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "com.easeinn.mobile/downloads"
    private val writePermissionRequest = 7401
    private var pendingDownload: PendingDownload? = null

    private data class PendingDownload(
        val fileName: String,
        val mimeType: String,
        val bytes: ByteArray,
        val result: MethodChannel.Result,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName.isNullOrBlank() || mimeType.isNullOrBlank() || bytes == null) {
                    result.error("INVALID_EXPORT", "The export file is incomplete.", null)
                    return@setMethodCallHandler
                }

                val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(safeName, mimeType, bytes, result)
                } else if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    saveLegacyDownload(safeName, bytes, result)
                } else if (pendingDownload == null) {
                    pendingDownload = PendingDownload(safeName, mimeType, bytes, result)
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        writePermissionRequest,
                    )
                } else {
                    result.error("DOWNLOAD_BUSY", "Another download is being prepared.", null)
                }
            }
    }

    private fun saveWithMediaStore(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/EaseInn")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            result.error("DOWNLOAD_CREATE_FAILED", "Android could not create the download file.", null)
            return
        }

        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Android could not open the download file.")
            val completed = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, completed, null, null)
            result.success(uri.toString())
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            result.error("DOWNLOAD_WRITE_FAILED", error.message, null)
        }
    }

    private fun saveLegacyDownload(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        try {
            val folder = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "EaseInn",
            )
            if (!folder.exists() && !folder.mkdirs()) {
                throw IllegalStateException("Could not create the Downloads/EaseInn folder.")
            }
            val file = File(folder, fileName)
            FileOutputStream(file).use { it.write(bytes) }
            result.success(file.absolutePath)
        } catch (error: Exception) {
            result.error("DOWNLOAD_WRITE_FAILED", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != writePermissionRequest) return

        val pending = pendingDownload ?: return
        pendingDownload = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveLegacyDownload(pending.fileName, pending.bytes, pending.result)
        } else {
            pending.result.error(
                "DOWNLOAD_PERMISSION_DENIED",
                "Storage permission is needed to save to Downloads on this Android version.",
                null,
            )
        }
    }
}
