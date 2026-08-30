package dev.meowworks.tokenmeow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 把应用私有目录的路径告诉 Dart 侧（storage.dart），数据文件就存在这里。
        // 这样就不用引入 shared_preferences / path_provider 插件了。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.meowworks.tokenmeow/platform")
            .setMethodCallHandler { call, result ->
                if (call.method == "getFilesDir") {
                    result.success(filesDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }
    }
}
