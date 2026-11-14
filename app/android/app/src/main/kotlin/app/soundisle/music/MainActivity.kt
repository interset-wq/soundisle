package app.soundisle.music

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts Flutter and the embedded Go music core.
 *
 * The Go core is linked in as a gomobile AAR (see scripts/build_mobile_core.sh).
 * It is located through reflection so the project still compiles before the AAR
 * has been generated (for example during `flutter analyze` on a fresh checkout).
 */
class MainActivity : AudioServiceActivity() {
    private val channelName = "app.soundisle/backend"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
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
