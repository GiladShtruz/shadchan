package com.gilad.shadchan

import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private var pendingInvite: String? = null
    private val pendingFilePaths = mutableListOf<String>()
    private val pendingSharedProfiles = mutableListOf<Map<String, Any>>()
    private var eventSink: EventChannel.EventSink? = null
    private var sharedProfilesEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        consumeIncomingIntent(intent)
        super.onCreate(savedInstanceState)
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_PROFILES_METHOD_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingDrafts" -> {
                    result.success(pendingSharedProfiles.toList())
                    pendingSharedProfiles.clear()
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INVITE_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingInvite" -> {
                    result.success(pendingInvite)
                    pendingInvite = null
                }

                "takeInstallReferrer" -> takeInstallReferrer(result)

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WHATSAPP_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendToChat" -> {
                    val phone = call.argument<String>("phone")
                    val text = call.argument<String>("text") ?: ""
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    result.success(
                        if (phone.isNullOrBlank()) false else sendToWhatsAppChat(phone, text, paths),
                    )
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL_NAME,
        ).setStreamHandler(this)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_PROFILES_EVENT_CHANNEL_NAME,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sharedProfilesEventSink = events
                flushPendingSharedProfiles()
            }

            override fun onCancel(arguments: Any?) {
                sharedProfilesEventSink = null
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        consumeIncomingIntent(intent)
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun consumeIncomingIntent(intent: Intent?) {
        if (intent == null) {
            return
        }

        val handled = when {
            // Before everything else: isBackupIntent claims every ACTION_VIEW.
            isInviteIntent(intent) -> {
                pendingInvite = intent.data?.toString()
                true
            }

            // Then: a spreadsheet or a chat export is a batch of
            // people for the AI import, and it would otherwise be claimed by
            // isBackupIntent (which accepts any ACTION_VIEW) and fed to the
            // backup restore, where it fails as unreadable JSON.
            isImportDocumentIntent(intent) -> {
                enqueueIncomingSharedProfile(intent)
                true
            }

            isBackupIntent(intent) -> {
                enqueueIncomingFiles(intent)
                true
            }

            isSharedProfileIntent(intent) -> {
                enqueueIncomingSharedProfile(intent)
                true
            }

            else -> false
        }

        if (!handled) {
            return
        }

        intent.action = Intent.ACTION_MAIN
        intent.data = null
        intent.replaceExtras(Bundle())
        intent.clipData = null
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

    private fun enqueueIncomingSharedProfile(intent: Intent?) {
        if (intent == null) {
            return
        }

        val text = extractIncomingText(intent)
        val copiedPaths = extractIncomingUris(intent)
            .mapNotNull { uri -> copySharedUriToCache(uri) }

        if (text.isNullOrBlank() && copiedPaths.isEmpty()) {
            return
        }

        val draft = mutableMapOf<String, Any>(
            "id" to UUID.randomUUID().toString(),
            "filePaths" to copiedPaths,
        )
        if (!text.isNullOrBlank()) {
            draft["text"] = text.trim()
        }

        pendingSharedProfiles.add(draft)
        flushPendingSharedProfiles()
    }

    /// Opens one WhatsApp chat — [phone] in international digits — with a card's
    /// text and photos already in the composer, without the share sheet.
    ///
    /// WhatsApp accepts a `jid` extra on its SEND intent that names the chat,
    /// which is the only way on Android to address a file share to one
    /// person. Tried on WhatsApp, then WhatsApp Business; false when neither is
    /// installed, so the caller can fall back to a text-only chat link.
    private fun sendToWhatsAppChat(phone: String, text: String, paths: List<String>): Boolean {
        val digits = phone.filter { it.isDigit() }
        if (digits.isEmpty()) return false

        val shareDirectory = File(cacheDir, "card_share")
        shareDirectory.deleteRecursively()
        shareDirectory.mkdirs()
        val uris = ArrayList<Uri>()
        for (path in paths) {
            try {
                val source = File(path)
                if (!source.exists()) continue
                val copy = File(shareDirectory, "${UUID.randomUUID()}_${sanitizeFileName(source.name)}")
                source.copyTo(copy, overwrite = true)
                uris.add(FileProvider.getUriForFile(this, "$packageName.cardshare", copy))
            } catch (_: Exception) {
            }
        }

        for (target in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            val intent = if (uris.size > 1) {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    type = "image/*"
                }
            } else if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    putExtra(Intent.EXTRA_STREAM, uris[0])
                    type = "image/*"
                }
            } else {
                Intent(Intent.ACTION_SEND).apply { type = "text/plain" }
            }
            intent.setPackage(target)
            intent.putExtra(Intent.EXTRA_TEXT, text)
            intent.putExtra("jid", "$digits@s.whatsapp.net")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (intent.resolveActivity(packageManager) == null) continue
            return try {
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
        return false
    }

    private fun isInviteIntent(intent: Intent): Boolean {
        return intent.action == Intent.ACTION_VIEW &&
            intent.data?.scheme == INVITE_SCHEME
    }

    /// The Play Store referrer of this install, read once ever. A matchmaker's
    /// invitation link sends a new user to the store with
    /// `referrer=from=<uid>&name=<name>`; this is how it survives the install.
    private fun takeInstallReferrer(result: MethodChannel.Result) {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (prefs.getBoolean(REFERRER_READ_KEY, false)) {
            result.success(null)
            return
        }
        val client = com.android.installreferrer.api.InstallReferrerClient
            .newBuilder(this)
            .build()
        var answered = false
        fun answer(value: String?) {
            if (answered) return
            answered = true
            runOnUiThread { result.success(value) }
        }
        try {
            client.startConnection(object :
                com.android.installreferrer.api.InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    var referrer: String? = null
                    if (responseCode ==
                        com.android.installreferrer.api.InstallReferrerClient
                            .InstallReferrerResponse.OK
                    ) {
                        try {
                            referrer = client.installReferrer.installReferrer
                        } catch (_: Exception) {
                        }
                        prefs.edit().putBoolean(REFERRER_READ_KEY, true).apply()
                    }
                    try {
                        client.endConnection()
                    } catch (_: Exception) {
                    }
                    answer(referrer)
                }

                override fun onInstallReferrerServiceDisconnected() {
                    answer(null)
                }
            })
        } catch (_: Exception) {
            answer(null)
        }
    }

    private fun isBackupIntent(intent: Intent): Boolean {
        return when (intent.action) {
            Intent.ACTION_VIEW -> true
            Intent.ACTION_SEND,
            Intent.ACTION_SEND_MULTIPLE -> looksLikeBackupMimeType(intent.type)
            else -> false
        }
    }

    private fun isSharedProfileIntent(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return false
        }

        val mimeType = intent.type?.lowercase() ?: return false
        return mimeType == "text/plain" ||
            mimeType.startsWith("image/") ||
            mimeType.startsWith("audio/") ||
            mimeType == "application/ogg"
    }

    /// A file meant for the AI import: a spreadsheet, or a WhatsApp chat
    /// export as either the .zip with its media or the bare .txt.
    ///
    /// Both the declared type and the file name are consulted. Senders are
    /// wildly inconsistent — a file manager may offer application/octet-stream
    /// for a .xlsx, and an ACTION_VIEW of a content:// Uri often carries no
    /// type at all — so trusting either one alone loses real files.
    private fun isImportDocumentIntent(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW &&
            intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return false
        }

        val uris = extractIncomingUris(intent)
        if (uris.isEmpty()) {
            return false
        }

        if (IMPORT_MIME_TYPES.contains(intent.type?.lowercase())) {
            return true
        }

        return uris.any { uri ->
            IMPORT_MIME_TYPES.contains(contentResolver.getType(uri)?.lowercase()) ||
                IMPORT_EXTENSIONS.contains(documentExtension(uri))
        }
    }

    /// The lower-cased extension of what a Uri points at, including the dot.
    private fun documentExtension(uri: Uri): String? {
        val name = resolveDisplayName(uri) ?: uri.lastPathSegment ?: return null
        val dot = name.lastIndexOf('.')
        return if (dot >= 0) name.substring(dot).lowercase() else null
    }

    private fun looksLikeBackupMimeType(mimeType: String?): Boolean {
        val type = mimeType?.lowercase() ?: return false
        return type == "application/json" ||
            type == "text/json" ||
            type == "application/octet-stream"
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

    private fun extractIncomingText(intent: Intent): String? {
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
        if (!text.isNullOrEmpty()) {
            return text
        }

        return intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
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

    private fun copySharedUriToCache(uri: Uri): String? {
        return try {
            // The extension is what the Dart side reads to decide whether this
            // is a spreadsheet, a chat export or a photo, so a Uri with no
            // resolvable name falls back to one derived from its type rather
            // than to a .jpg that would send a workbook down the photo path.
            val fileName = resolveDisplayName(uri) ?: fallbackFileName(uri)
            val importsDirectory = File(cacheDir, "incoming_shared_profiles")
            if (!importsDirectory.exists()) {
                importsDirectory.mkdirs()
            }

            val safeFileName = sanitizeFileName(fileName)
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

    private fun fallbackFileName(uri: Uri): String {
        val extension = when (contentResolver.getType(uri)?.lowercase()) {
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> ".xlsx"
            "application/vnd.ms-excel" -> ".xlsx"
            "application/zip", "application/x-zip-compressed", "multipart/x-zip" -> ".zip"
            "text/plain" -> ".txt"
            "audio/ogg", "audio/opus", "application/ogg" -> ".opus"
            "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac" -> ".m4a"
            "audio/mpeg" -> ".mp3"
            "audio/amr" -> ".amr"
            else -> documentExtension(uri) ?: ".jpg"
        }
        return "shared_${UUID.randomUUID()}$extension"
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

    private fun sanitizeFileName(fileName: String): String {
        return fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
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

    private fun flushPendingSharedProfiles() {
        val sink = sharedProfilesEventSink ?: return
        if (pendingSharedProfiles.isEmpty()) {
            return
        }

        val draftsToSend = pendingSharedProfiles.toList()
        pendingSharedProfiles.clear()
        for (draft in draftsToSend) {
            sink.success(draft)
        }
    }

    companion object {
        /// What the AI import can read: a spreadsheet, or a WhatsApp chat
        /// export as either the .zip with its media or the bare .txt.
        private val IMPORT_EXTENSIONS = setOf(".xlsx", ".xlsm", ".zip", ".txt")
        private val IMPORT_MIME_TYPES = setOf(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-excel",
            "application/zip",
            "application/x-zip-compressed",
            "multipart/x-zip",
        )

        private const val INVITE_CHANNEL_NAME = "shadchan/invite_links"
        private const val WHATSAPP_CHANNEL_NAME = "shadchan/whatsapp_direct"
        private const val INVITE_SCHEME = "shadchan-invite"
        private const val PREFS_NAME = "shadchan_native"
        private const val REFERRER_READ_KEY = "installReferrerRead"
        private const val METHOD_CHANNEL_NAME = "shadchan/incoming_backup_files/methods"
        private const val EVENT_CHANNEL_NAME = "shadchan/incoming_backup_files/events"
        private const val SHARED_PROFILES_METHOD_CHANNEL_NAME =
            "shadchan/incoming_shared_profiles/methods"
        private const val SHARED_PROFILES_EVENT_CHANNEL_NAME =
            "shadchan/incoming_shared_profiles/events"
    }
}
