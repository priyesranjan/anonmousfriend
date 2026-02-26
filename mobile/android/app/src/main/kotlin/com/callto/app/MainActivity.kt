package com.callto.app

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var callForegroundChannel: MethodChannel
    private lateinit var appTaskChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        callForegroundChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.callto.app/call_foreground_service"
        )
        callForegroundChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val title = call.argument<String>("title")
                    val text = call.argument<String>("text")
                    startOrUpdateForegroundCall(
                        action = CallForegroundService.ACTION_START,
                        title = title,
                        text = text
                    )
                    result.success(null)
                }

                "updateService" -> {
                    val title = call.argument<String>("title")
                    val text = call.argument<String>("text")
                    startOrUpdateForegroundCall(
                        action = CallForegroundService.ACTION_UPDATE,
                        title = title,
                        text = text
                    )
                    result.success(null)
                }

                "stopService" -> {
                    stopService(Intent(this, CallForegroundService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        appTaskChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.callto.app/app_task"
        )
        appTaskChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }

        notifyFlutterToOpenCallScreen(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notifyFlutterToOpenCallScreen(intent)
    }

    private fun startOrUpdateForegroundCall(
        action: String,
        title: String?,
        text: String?
    ) {
        val serviceIntent = Intent(this, CallForegroundService::class.java).apply {
            this.action = action
            putExtra(CallForegroundService.EXTRA_TITLE, title)
            putExtra(CallForegroundService.EXTRA_TEXT, text)
        }
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    private fun notifyFlutterToOpenCallScreen(sourceIntent: Intent?) {
        val shouldOpen = sourceIntent?.getBooleanExtra(
            CallForegroundService.EXTRA_OPEN_CALL_SCREEN,
            false
        ) ?: false
        if (!shouldOpen) return

        callForegroundChannel.invokeMethod("openCallScreen", null)
        sourceIntent?.removeExtra(CallForegroundService.EXTRA_OPEN_CALL_SCREEN)
    }
}
