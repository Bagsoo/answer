package com.answer.app

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val backgroundChannel = "com.answer.messenger/background"
    private val shareChannel = "com.answer.messenger/share"
    private val shareEventsChannel = "com.answer.messenger/share_events"

    private var shareEventSink: EventChannel.EventSink? = null
    private var pendingSharePayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSharePayload = parseShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = parseShareIntent(intent) ?: return
        pendingSharePayload = payload
        shareEventSink?.success(payload)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    moveTaskToBack(true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedPayload" -> result.success(pendingSharePayload)
                    "clearSharedPayload" -> {
                        pendingSharePayload = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, shareEventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            })

        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine, "listTile", ListTileNativeAdFactory(context)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "listTile")
    }

    private fun parseShareIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val action = intent.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""
        val mimeType = intent.type ?: ""
        val files = mutableListOf<Map<String, Any?>>()

        if (action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (stream != null) {
                copyUriToCache(stream)?.let { files.add(it) }
            }
        } else if (action == Intent.ACTION_SEND_MULTIPLE) {
            @Suppress("DEPRECATION")
            val streams = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            streams?.forEach { uri ->
                copyUriToCache(uri)?.let { files.add(it) }
            }
        }

        if (text.isBlank() && subject.isBlank() && files.isEmpty()) {
            return null
        }

        return mapOf(
            "text" to text,
            "subject" to subject,
            "mimeType" to mimeType,
            "sourceApp" to (referrer?.host ?: ""),
            "files" to files,
        )
    }

    private fun copyUriToCache(uri: Uri): Map<String, Any?>? {
        return try {
            val resolver = applicationContext.contentResolver
            var displayName = "shared_file"
            var size = 0L

            resolver.query(uri, null, null, null, null)?.use { cursor: Cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (cursor.moveToFirst()) {
                    if (nameIndex != -1) {
                        displayName = cursor.getString(nameIndex) ?: displayName
                    }
                    if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }

            val mimeType = resolver.getType(uri)
                ?: guessMimeTypeFromName(displayName)
                ?: "application/octet-stream"
            val safeName = sanitizeFileName(displayName, mimeType)
            val dir = File(cacheDir, "shared_external").apply {
                if (!exists()) mkdirs()
            }
            val target = File(
                dir,
                "${System.currentTimeMillis()}_${UUID.randomUUID()}_$safeName"
            )

            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            } ?: return null

            if (size <= 0L) {
                size = target.length()
            }

            mapOf(
                "path" to target.absolutePath,
                "name" to displayName,
                "mimeType" to mimeType,
                "size" to size.toInt(),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun sanitizeFileName(name: String, mimeType: String): String {
        val cleaned = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        if (cleaned.contains(".")) return cleaned
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return if (ext.isNullOrBlank()) cleaned else "$cleaned.$ext"
    }

    private fun guessMimeTypeFromName(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext.isBlank()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
    }
}
