package app.soundisle.music

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
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
            else -> result.notImplemented()
        }
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
                mainHandler.post { result.success(location) }
            } catch (error: Throwable) {
                val message = error.message ?: error.toString()
                mainHandler.post { result.error("export_failed", message, null) }
            }
        }.start()
    }

    private fun exportToMediaStore(source: File, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
