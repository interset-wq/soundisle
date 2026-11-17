package app.soundisle.music

import android.Manifest
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Hosts Flutter and the embedded Go music core.
 *
 * The Go core is linked in as a gomobile AAR (see scripts/build_mobile_core.sh).
 * It is located through reflection so the project still compiles before the AAR
 * has been generated (for example during `flutter analyze` on a fresh checkout).
 */
class MainActivity : AudioServiceActivity() {
    private val channelName = "app.soundisle/backend"
    private val storageChannelName = "app.soundisle/storage"
    private val permissionChannelName = "app.soundisle/permissions"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannelName)
            .setMethodCallHandler { call, result -> handleStorage(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestStartupPermissions" -> {
                        requestStartupPermissions()
                        result.success(true)
                    }
                    "notificationStatus" -> result.success(notificationStatus())
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startCore(call, result)
            "stop" -> {
                try {
                    coreClass().getMethod("stop").invoke(null)
                    result.success(true)
                } catch (error: Throwable) {
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun handleStorage(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportAudio" -> exportAudio(call, result)
            "importExported" -> importExported(call, result)
            else -> result.notImplemented()
        }
    }

    /** Reports why the media notification may be missing (permission/channel). */
    private fun notificationStatus(): Map<String, Any> {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val channel = manager.getNotificationChannel("app.soundisle.channel.audio")
        val active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.activeNotifications.size
        } else {
            0
        }
        return mapOf(
            "granted" to (granted && manager.areNotificationsEnabled()),
            "permissionGranted" to granted,
            "appEnabled" to manager.areNotificationsEnabled(),
            "channelExists" to (channel != null),
            "channelImportance" to (channel?.importance ?: -1),
            "activeNotifications" to active,
        )
    }

    /**
     * Android 13+ needs an explicit notification permission before the media
     * session can show playback controls. Android 9 and older need write access
     * so downloads can be exported to the public Music folder.
     */
    private fun requestStartupPermissions() {
        val wanted = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            wanted.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
        val missing = wanted.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 4201)
        }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    /**
     * Copies a downloaded file from the app-private directory into the shared
     * Music collection so file managers and other music apps can see it.
     */
    private fun exportAudio(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
        if (path.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("bad_args", "path and fileName are required", null)
            return
        }
        val source = File(path)
        if (!source.isFile) {
            result.error("missing_file", "下载文件不存在：$path", null)
            return
        }
        Thread {
            try {
                val location = exportToMediaStore(source, fileName, mimeType)
                // Lyrics and cover art live next to the private audio file.
                // Publish them too so a file manager / other player sees the
                // complete download, not just the bare track.
                exportSidecars(source, fileName)
                mainHandler.post { result.success(location) }
            } catch (error: Throwable) {
                val message = error.message ?: error.toString()
                mainHandler.post { result.error("export_failed", message, null) }
            }
        }.start()
    }

    private fun exportToMediaStore(source: File, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Re-exporting a finished download on every launch must not leave
            // "Song (1).mp3" copies behind.
            runCatching {
                contentResolver.delete(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    "${MediaStore.Audio.Media.RELATIVE_PATH}=? AND ${MediaStore.Audio.Media.DISPLAY_NAME}=?",
                    arrayOf("Music/声屿/", fileName),
                )
            }
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/声屿")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("无法在系统音乐库中创建文件")
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { input -> input.copyTo(output, 128 * 1024) }
                } ?: throw IOException("无法写入系统音乐库")
                values.clear()
                values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Throwable) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return "Music/声屿/$fileName"
        }
        @Suppress("DEPRECATION")
        val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        val targetDir = File(musicDir, "声屿").apply { mkdirs() }
        val target = File(targetDir, fileName)
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output, 128 * 1024) }
        }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mimeType), null)
        return target.absolutePath
    }

    /** Publishes `.lrc` and `<name>.cover.*` next to the exported audio file. */
    private fun exportSidecars(source: File, audioFileName: String) {
        val sourceBase = File(
            source.parentFile,
            source.name.substringBeforeLast('.', source.name),
        ).absolutePath
        val targetBase = audioFileName.substringBeforeLast('.', audioFileName)
        val items = mutableListOf<Pair<File, String>>()
        File("$sourceBase.lrc").takeIf { it.isFile }?.let { items.add(it to "$targetBase.lrc") }
        for (ext in listOf("jpg", "jpeg", "png", "webp", "gif")) {
            File("$sourceBase.cover.$ext").takeIf { it.isFile }?.let {
                items.add(it to "$targetBase.cover.$ext")
            }
        }
        for ((file, name) in items) {
            // A missing lyric/cover must never fail the audio export.
            runCatching { exportSidecarToMediaStore(file, name) }
        }
    }

    private fun exportSidecarToMediaStore(source: File, fileName: String) {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        val mime = when (extension) {
            "lrc" -> "text/plain"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            else -> "image/jpeg"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            runCatching {
                contentResolver.delete(
                    collection,
                    "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                    arrayOf("Music/声屿/", fileName),
                )
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Music/声屿")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(collection, values)
                ?: throw IOException("无法在系统音乐目录中创建 $fileName")
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
                } ?: throw IOException("无法写入 $fileName")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Throwable) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return
        }
        @Suppress("DEPRECATION")
        val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        val targetDir = File(musicDir, "声屿").apply { mkdirs() }
        val target = File(targetDir, fileName)
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
        }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
    }

    private class ImportCandidate(
        val name: String,
        val size: Long,
        val open: () -> java.io.InputStream,
    )

    private data class PendingImport(val dir: String, val result: MethodChannel.Result)

    private var pendingImport: PendingImport? = null

    private fun audioReadPermission(): String = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> Manifest.permission.READ_MEDIA_AUDIO
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> Manifest.permission.READ_EXTERNAL_STORAGE
        else -> Manifest.permission.WRITE_EXTERNAL_STORAGE
    }

    /**
     * Copies tracks that were exported to `Music/声屿` back into the app-private
     * download directory. Uninstalling clears the private directory, so this is
     * how a fresh install restores the local library.
     */
    private fun importExported(call: MethodCall, result: MethodChannel.Result) {
        val dir = call.argument<String>("dir")
        if (dir.isNullOrBlank()) {
            result.error("bad_args", "dir is required", null)
            return
        }
        val permission = audioReadPermission()
        val granted = ActivityCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pendingImport?.result?.error("superseded", "新的导入请求已开始", null)
            pendingImport = PendingImport(dir, result)
            ActivityCompat.requestPermissions(this, arrayOf(permission), 4302)
            return
        }
        runImport(dir, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4302) return
        val pending = pendingImport ?: return
        pendingImport = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            runImport(pending.dir, pending.result)
        } else {
            pending.result.error(
                "permission_denied",
                "需要「音乐和音频」权限才能读取 Music/声屿 中的文件",
                null,
            )
        }
    }

    private fun runImport(dir: String, result: MethodChannel.Result) {
        Thread {
            try {
                val summary = importFromMusicFolder(File(dir))
                mainHandler.post { result.success(summary) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("import_failed", error.message ?: error.toString(), null)
                }
            }
        }.start()
    }

    private fun importFromMusicFolder(targetDir: File): Map<String, Any> {
        if (!targetDir.isDirectory && !targetDir.mkdirs()) {
            throw IOException("无法创建下载目录：${targetDir.absolutePath}")
        }
        // Leftovers from an interrupted import.
        targetDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".import") }
            ?.forEach { it.delete() }
        val candidates = listExportedAudio()
        var imported = 0
        var skipped = 0
        var failed = 0
        for (candidate in candidates) {
            var temp: File? = null
            try {
                val target = resolveImportTarget(targetDir, candidate.name, candidate.size)
                if (target == null) {
                    skipped++
                    continue
                }
                // Stage under a temp name so an interrupted import never shows
                // up as a truncated song in the local library.
                val staging = File(targetDir, target.name + ".import")
                temp = staging
                staging.delete()
                candidate.open().use { input ->
                    staging.outputStream().use { output -> input.copyTo(output, 128 * 1024) }
                }
                if (!staging.renameTo(target)) {
                    throw IOException("无法写入 ${target.name}")
                }
                imported++
            } catch (_: Throwable) {
                temp?.delete()
                failed++
            }
        }
        // Bring back lyrics/cover art saved next to the exported tracks. These
        // are optional: a missing or unreadable sidecar never fails an import.
        runCatching { importSidecars(targetDir) }
        return mapOf(
            "found" to candidates.size,
            "imported" to imported,
            "skipped" to skipped,
            "failed" to failed,
        )
    }

    /** Returns null when an identical file is already imported. */
    private fun resolveImportTarget(dir: File, rawName: String, size: Long): File? {
        val name = rawName.substringAfterLast('/').substringAfterLast('\\').ifBlank { "audio.mp3" }
        val base = File(name).nameWithoutExtension.ifBlank { "audio" }
        val ext = File(name).extension.ifBlank { "mp3" }
        for (index in 0..99) {
            val candidate = File(dir, if (index == 0) "$base.$ext" else "$base ($index).$ext")
            if (!candidate.exists()) return candidate
            if (candidate.isFile && candidate.length() == size) return null
        }
        throw IOException("同名文件过多：$base.$ext")
    }

    private fun listExportedAudio(): List<ImportCandidate> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val out = mutableListOf<ImportCandidate>()
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.SIZE,
            )
            val selection = "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                arrayOf("Music/声屿/%"),
                null,
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameColumn) ?: continue
                    if (!isAudioName(name)) continue
                    val uri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        cursor.getLong(idColumn),
                    )
                    out.add(
                        ImportCandidate(name, cursor.getLong(sizeColumn)) {
                            contentResolver.openInputStream(uri)
                                ?: throw IOException("无法读取 $name")
                        },
                    )
                }
            }
            return out
        }
        val folder = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "声屿",
        )
        if (!folder.isDirectory) return emptyList()
        return folder.listFiles()
            ?.filter { it.isFile && isAudioName(it.name) }
            ?.map { file ->
                ImportCandidate(file.name, file.length()) { file.inputStream() }
            }
            ?: emptyList()
    }

    private fun isAudioName(name: String): Boolean =
        name.substringAfterLast('.', "").lowercase() in setOf(
            "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "wma",
        )

    private data class SidecarCandidate(
        val name: String,
        val size: Long,
        val open: () -> java.io.InputStream,
    )

    private fun listExportedSidecars(): List<SidecarCandidate> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val out = mutableListOf<SidecarCandidate>()
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.SIZE,
            )
            val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
            runCatching {
                contentResolver.query(
                    MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                    projection,
                    selection,
                    arrayOf("Music/声屿/%"),
                    null,
                )?.use { cursor ->
                    val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                    val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                    val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(nameColumn) ?: continue
                        if (!isSidecarName(name)) continue
                        val uri = ContentUris.withAppendedId(collection, cursor.getLong(idColumn))
                        out.add(
                            SidecarCandidate(name, cursor.getLong(sizeColumn)) {
                                contentResolver.openInputStream(uri)
                                    ?: throw IOException("无法读取 $name")
                            },
                        )
                    }
                }
            }
            return out
        }
        val folder = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "声屿",
        )
        if (!folder.isDirectory) return emptyList()
        return folder.listFiles()
            ?.filter { it.isFile && isSidecarName(it.name) }
            ?.map { file ->
                SidecarCandidate(file.name, file.length()) { file.inputStream() }
            }
            ?: emptyList()
    }

    private fun isSidecarName(name: String): Boolean =
        name.endsWith(".lrc", ignoreCase = true) || name.contains(".cover.", ignoreCase = true)

    private fun importSidecars(targetDir: File) {
        for (sidecar in listExportedSidecars()) {
            val name = sidecar.name.substringAfterLast('/').substringAfterLast('\\')
            if (name.isBlank()) continue
            val stem = when {
                name.endsWith(".lrc", ignoreCase = true) -> name.dropLast(4)
                else -> name.substringBeforeLast(".cover.", "")
            }
            if (stem.isBlank()) continue
            // Only restore a sidecar when its audio file is present locally;
            // otherwise it would be an orphan the library cannot use.
            val hasAudio = targetDir.listFiles()?.any { file ->
                file.isFile && isAudioName(file.name) &&
                    file.name.substringBeforeLast('.', file.name) == stem
            } ?: false
            if (!hasAudio) continue

            val target = File(targetDir, name)
            if (target.isFile && target.length() == sidecar.size) continue
            try {
                val staging = File(targetDir, "$name.import")
                staging.delete()
                sidecar.open().use { input ->
                    staging.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
                }
                if (!staging.renameTo(target)) throw IOException("无法写入 $name")
            } catch (_: Throwable) {
                // Keep the existing sidecar if any; audio import already won.
            }
        }
    }

    private fun startCore(call: MethodCall, result: MethodChannel.Result) {
        val dataDir = call.argument<String>("dataDir")
        val token = call.argument<String>("token")
        if (dataDir.isNullOrBlank() || token.isNullOrBlank()) {
            result.error("bad_args", "dataDir and token are required", null)
            return
        }
        Thread {
            try {
                val dir = File(dataDir).apply { mkdirs() }
                val method = coreClass().getMethod("start", String::class.java, String::class.java)
                val port = (method.invoke(null, dir.absolutePath, token) as Number).toInt()
                mainHandler.post { result.success(port) }
            } catch (error: Throwable) {
                val message = when {
                    error is ClassNotFoundException ->
                        "音乐核心未集成：请先运行 scripts/build_mobile_core.sh android 生成 AAR"
                    error.cause != null -> error.cause!!.message ?: error.cause.toString()
                    else -> error.message ?: error.toString()
                }
                mainHandler.post { result.error("core_error", message, null) }
            }
        }.start()
    }

    // gomobile appends the Go package name to -javapkg, so the generated class
    // lives at app.soundisle.core.mobile.Mobile.
    private fun coreClass(): Class<*> = Class.forName("app.soundisle.core.mobile.Mobile")
}
