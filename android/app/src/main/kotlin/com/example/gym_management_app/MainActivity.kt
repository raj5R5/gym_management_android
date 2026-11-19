package com.example.gym_management_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gym_management/public_links")
            .setMethodCallHandler { call, result ->
                if (call.method != "openHttps") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = (call.arguments as? String)?.let { Uri.parse(it) }
                if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) {
                    result.error("INVALID_URL", "A public HTTPS URL is required.", null)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("BROWSER_UNAVAILABLE", "No browser is available. Copy the link to open it elsewhere.", null)
                } catch (_: SecurityException) {
                    result.error("BROWSER_UNAVAILABLE", "The browser could not be opened. Copy the link instead.", null)
                }
            }
    }
}
