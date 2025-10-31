package com.example.pay_go

import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var ringtone: Ringtone? = null

    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.paygo/ringtone")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playRingtone" -> {
                        Handler(Looper.getMainLooper()).post {
                            val uri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                            if (ringtone != null && !ringtone!!.isPlaying) {
                                ringtone!!.play()
                            }
                        }
                        result.success(null)
                    }
                    "stopRingtone" -> {
                        if (ringtone != null && ringtone!!.isPlaying) {
                            ringtone!!.stop()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
