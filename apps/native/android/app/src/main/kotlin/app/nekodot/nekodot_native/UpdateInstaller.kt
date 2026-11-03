package app.nekodot.client

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

object UpdateInstaller {
    @Suppress("DEPRECATION")
    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.nekodot/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "version" -> {
                            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                            result.success(mapOf("version" to info.versionName, "build" to info.longVersionCode))
                        }
                        "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                        "installPermission" -> {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:" + activity.packageName)))
                            result.success(null)
                        }
                        "install" -> {
                            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                            require(file.parentFile == File(activity.cacheDir, "updates").canonicalFile && file.extension == "apk")
                            check(activity.packageManager.canRequestPackageInstalls()) { "Allow app installation first" }
                            val uri = FileProvider.getUriForFile(activity, activity.packageName + ".provider", file)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("update_failed", error.message, null)
                }
            }
    }
}
