package app.nekodot.client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.nekodot/lifecycle")
            .setMethodCallHandler { call, result ->
                if (call.method == "background") {
                    moveTaskToBack(true)
                    result.success(null)
                } else result.notImplemented()
            }
    }
}
