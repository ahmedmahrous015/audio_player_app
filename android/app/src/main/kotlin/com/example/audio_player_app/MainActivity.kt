package com.example.audio_player_app

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.audio_player_app/device"
    private val DELETE_REQUEST_CODE = 4217
    private val MOVE_REQUEST_CODE = 4218

    // State of an in-flight MediaStore write (move) confirmation (Android 11+).
    private var pendingMoveResult: MethodChannel.Result? = null
    private var pendingMoved: HashMap<String, String> = HashMap()
    private var pendingMoveItems: List<Triple<String, Uri, String>> = emptyList()

    // State of an in-flight MediaStore delete confirmation (Android 11+).
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleted: List<String> = emptyList()
    private var pendingConsentPaths: List<String> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache.getInstance().put("audio_service_engine", flutterEngine)
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setRingtone" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        setRingtone(path, result)
                    } else {
                        result.error("INVALID_ARG", "path is required", null)
                    }
                }
                "deleteFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths != null) {
                        deleteFiles(paths, result)
                    } else {
                        result.error("INVALID_ARG", "paths is required", null)
                    }
                }
                "moveFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    val target = call.argument<String>("targetDir")
                    if (paths != null && target != null) {
                        moveFiles(paths, target, result)
                    } else {
                        result.error("INVALID_ARG", "paths and targetDir are required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deleteFiles(paths: List<String>, result: MethodChannel.Result) {
        if (pendingDeleteResult != null) {
            result.error("BUSY", "A delete request is already in progress", null)
            return
        }

        val deleted = mutableListOf<String>()
        val needConsent = mutableListOf<Pair<String, Uri>>()
        val unindexed = mutableListOf<String>()

        for (path in paths) {
            val file = File(path)
            if (!file.exists()) {
                deleted.add(path)
                continue
            }
            val ok = try { file.delete() } catch (e: Exception) { false }
            if (ok) {
                deleted.add(path)
            } else {
                val uri = findAudioUri(path)
                if (uri != null) needConsent.add(path to uri) else unindexed.add(path)
            }
        }

        // Keep the media library in sync for files we removed directly.
        if (deleted.isNotEmpty()) {
            MediaScannerConnection.scanFile(applicationContext, deleted.toTypedArray(), null, null)
        }

        if (unindexed.isEmpty()) {
            requestConsentAndFinish(deleted, needConsent, result)
            return
        }

        // Files the media library hasn't indexed yet (e.g. just copied) have no
        // MediaStore entry to delete through: index them first, then continue.
        var remaining = unindexed.size
        MediaScannerConnection.scanFile(applicationContext, unindexed.toTypedArray(), null) { path, scannedUri ->
            runOnUiThread {
                val uri = findAudioUri(path) ?: scannedUri
                if (uri != null) needConsent.add(path to uri)
                remaining--
                if (remaining == 0) requestConsentAndFinish(deleted, needConsent, result)
            }
        }
    }

    private fun requestConsentAndFinish(
        deleted: MutableList<String>,
        needConsent: List<Pair<String, Uri>>,
        result: MethodChannel.Result
    ) {
        if (needConsent.isEmpty()) {
            result.success(deleted)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val request = MediaStore.createDeleteRequest(contentResolver, needConsent.map { it.second })
                pendingDeleteResult = result
                pendingDeleted = deleted
                pendingConsentPaths = needConsent.map { it.first }
                startIntentSenderForResult(request.intentSender, DELETE_REQUEST_CODE, null, 0, 0, 0)
            } catch (e: Exception) {
                pendingDeleteResult = null
                result.success(deleted)
            }
            return
        }

        // Android 10 and older: best effort through the content resolver.
        for ((path, uri) in needConsent) {
            try {
                if (contentResolver.delete(uri, null, null) > 0 || !File(path).exists()) {
                    deleted.add(path)
                }
            } catch (e: Exception) {
                // RecoverableSecurityException on Android 10; leave the file in place.
            }
        }
        result.success(deleted)
    }

    /** Free destination path: "name.mp3", then "name (1).mp3", ... */
    private fun uniqueTarget(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (candidate.exists()) {
            candidate = File(dir, "$base ($i)$ext")
            i++
        }
        return candidate
    }

    private fun moveFiles(paths: List<String>, targetDir: String, result: MethodChannel.Result) {
        if (pendingMoveResult != null || pendingDeleteResult != null) {
            result.error("BUSY", "Another file request is already in progress", null)
            return
        }
        val dir = File(targetDir)
        if (!dir.exists()) dir.mkdirs()

        val moved = HashMap<String, String>()
        val needConsent = mutableListOf<Triple<String, Uri, String>>()
        for (path in paths) {
            val src = File(path)
            if (!src.exists() || src.parentFile?.absolutePath == dir.absolutePath) continue
            val dst = uniqueTarget(dir, src.name)
            val ok = try { src.renameTo(dst) } catch (e: Exception) { false }
            if (ok) {
                moved[path] = dst.absolutePath
            } else {
                findAudioUri(path)?.let { needConsent.add(Triple(path, it, dst.absolutePath)) }
            }
        }
        if (moved.isNotEmpty()) {
            MediaScannerConnection.scanFile(
                applicationContext, (moved.keys + moved.values).toTypedArray(), null, null)
        }

        if (needConsent.isEmpty()) {
            result.success(moved)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val request = MediaStore.createWriteRequest(contentResolver, needConsent.map { it.second })
                pendingMoveResult = result
                pendingMoved = moved
                pendingMoveItems = needConsent
                startIntentSenderForResult(request.intentSender, MOVE_REQUEST_CODE, null, 0, 0, 0)
            } catch (e: Exception) {
                pendingMoveResult = null
                result.success(moved)
            }
            return
        }

        // Android 10: works only for files this app may already write.
        for ((path, uri, dst) in needConsent) {
            applyMove(uri, dst)?.let { moved[path] = it }
        }
        result.success(moved)
    }

    /** Moves a MediaStore item by changing its folder; returns the new path. */
    private fun applyMove(uri: Uri, dstPath: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val root = Environment.getExternalStorageDirectory().absolutePath
            val dst = File(dstPath)
            val relative = dst.parentFile!!.absolutePath.removePrefix(root).trim('/') + "/"
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.DISPLAY_NAME, dst.name)
            }
            if (contentResolver.update(uri, values, null, null) <= 0) return null
            // MediaStore may adjust the name on conflicts: read the real path.
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                ?.takeIf { File(it).exists() }
        } catch (e: Exception) {
            null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == MOVE_REQUEST_CODE) {
            val result = pendingMoveResult
            pendingMoveResult = null
            if (result != null) {
                val moved = HashMap(pendingMoved)
                if (resultCode == Activity.RESULT_OK) {
                    for ((path, uri, dst) in pendingMoveItems) {
                        applyMove(uri, dst)?.let { moved[path] = it }
                    }
                    result.success(moved)
                } else if (moved.isEmpty()) {
                    result.error("CANCELLED", "The user declined the move request", null)
                } else {
                    result.success(moved)
                }
            }
            return
        }
        if (requestCode == DELETE_REQUEST_CODE) {
            val result = pendingDeleteResult
            pendingDeleteResult = null
            if (result != null) {
                val deleted = pendingDeleted.toMutableList()
                if (resultCode == Activity.RESULT_OK) {
                    deleted.addAll(pendingConsentPaths.filter { !File(it).exists() })
                    result.success(deleted)
                } else if (deleted.isEmpty()) {
                    // The user tapped "Deny" in the system dialog: not an error.
                    result.error("CANCELLED", "The user declined the delete request", null)
                } else {
                    result.success(deleted)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun findAudioUri(path: String): Uri? {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        return try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DATA}=?",
                arrayOf(path),
                null
            )?.use { c ->
                if (c.moveToFirst()) ContentUris.withAppendedId(collection, c.getLong(0)) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun setRingtone(filePath: String, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.System.canWrite(applicationContext)) {
                    val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.error("PERMISSION_DENIED", "Write settings permission is required", null)
                    return
                }
            }

            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File not found", null)
                return
            }

            val fileName = file.name
            val mimeType = getMimeType(fileName)

            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.IS_RINGTONE, true)
                put(MediaStore.Audio.Media.IS_NOTIFICATION, false)
                put(MediaStore.Audio.Media.IS_ALARM, false)
                put(MediaStore.Audio.Media.IS_MUSIC, false)
            }

            val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Scoped storage: copy the file into the shared Ringtones collection.
                values.put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_RINGTONES)
                values.put(MediaStore.Audio.Media.IS_PENDING, true)
                val inserted = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                if (inserted != null) {
                    try {
                        contentResolver.openOutputStream(inserted)?.use { output ->
                            file.inputStream().use { input -> input.copyTo(output) }
                        }
                        val done = ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, false) }
                        contentResolver.update(inserted, done, null, null)
                    } catch (e: Exception) {
                        contentResolver.delete(inserted, null, null)
                        throw e
                    }
                }
                inserted
            } else {
                // Legacy storage: register the existing file instead of copying it.
                val existing = findAudioUri(filePath)
                if (existing != null) {
                    val flags = ContentValues().apply { put(MediaStore.Audio.Media.IS_RINGTONE, true) }
                    contentResolver.update(existing, flags, null, null)
                    existing
                } else {
                    @Suppress("DEPRECATION")
                    values.put(MediaStore.MediaColumns.DATA, filePath)
                    contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                }
            }

            if (uri == null) {
                result.error("INSERT_FAILED", "Failed to insert into MediaStore", null)
                return
            }

            RingtoneManager.setActualDefaultRingtoneUri(
                applicationContext,
                RingtoneManager.TYPE_RINGTONE,
                uri
            )

            result.success(true)
        } catch (e: Exception) {
            result.error("SET_RINGTONE_ERROR", e.message, null)
        }
    }

    private fun getMimeType(fileName: String): String {
        return when (fileName.substringAfterLast('.', "").lowercase()) {
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            "aac" -> "audio/aac"
            "ogg", "opus" -> "audio/ogg"
            "m4a" -> "audio/mp4"
            "amr" -> "audio/amr"
            "3gp" -> "audio/3gpp"
            "mid", "midi" -> "audio/midi"
            else -> "audio/*"
        }
    }
}
