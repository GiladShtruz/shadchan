package com.gilad.shadchan

import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val pendingFilePaths = mutableListOf<String>()
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enqueueIncomingFiles(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingFilePaths" -> {
                    result.success(pendingFilePaths.toList())
                    pendingFilePaths.clear()
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL_NAME,
        ).setStreamHandler(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueIncomingFiles(intent)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        flushPendingFilePaths()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun enqueueIncomingFiles(intent: Intent?) {
        val uris = extractIncomingUris(intent)
        if (uris.isEmpty()) {
            return
        }

        for (uri in uris) {
            val copiedPath = copyUriToCache(uri) ?: continue
            pendingFilePaths.add(copiedPath)
        }

        flushPendingFilePaths()
    }

    private fun extractIncomingUris(intent: Intent?): List<Uri> {
        if (intent == null) {
            return emptyList()
        }

        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let(::listOf) ?: emptyList()
            Intent.ACTION_SEND -> {
                extractSingleStreamUri(intent)?.let(::listOf)
                    ?: extractClipDataUris(intent)
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                extractMultipleStreamUris(intent).ifEmpty { extractClipDataUris(intent) }
            }

            else -> emptyList()
        }
    }

    private fun extractSingleStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
    }

    private fun extractMultipleStreamUris(intent: Intent): List<Uri> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                ?.filterNotNull()
                ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        }
    }

    private fun extractClipDataUris(intent: Intent): List<Uri> {
        val clipData = intent.clipData ?: return emptyList()
        return buildList {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(::add)
            }
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val fileName = ensureJsonExtension(resolveDisplayName(uri) ?: "shadchan_backup.json")
            val importsDirectory = File(cacheDir, "incoming_backups")
            if (!importsDirectory.exists()) {
                importsDirectory.mkdirs()
            }

            val safeFileName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val outputFile = File(importsDirectory, "${UUID.randomUUID()}_$safeFileName")

            contentResolver.openInputStream(uri)?.use { inputStream ->
                FileOutputStream(outputFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: return null

            outputFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor: Cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            return cursor.getString(index)
                        }
                    }
                }
        }

        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun ensureJsonExtension(fileName: String): String {
        return if (fileName.lowercase().endsWith(".json")) {
            fileName
        } else {
            "$fileName.json"
        }
    }

    private fun flushPendingFilePaths() {
        val sink = eventSink ?: return
        if (pendingFilePaths.isEmpty()) {
            return
        }

        val pathsToSend = pendingFilePaths.toList()
        pendingFilePaths.clear()
        for (path in pathsToSend) {
            sink.success(path)
        }
    }

    companion object {
        private const val METHOD_CHANNEL_NAME = "shadchan/incoming_backup_files/methods"
        private const val EVENT_CHANNEL_NAME = "shadchan/incoming_backup_files/events"
    }
}
