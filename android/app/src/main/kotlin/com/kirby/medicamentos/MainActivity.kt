package com.kirby.medicamentos

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val soundPickerChannel = "mis_medicamentos/system_sound"
    private val requestCodePickSystemSound = 46021
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundPickerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickSystemNotificationSound" -> {
                        if (pendingResult != null) {
                            result.error("busy", "Ya hay una solicitud de tono en curso.", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val currentUriRaw = call.argument<String>("currentUri")
                        val pickerIntent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(
                                RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_NOTIFICATION
                            )
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            if (!currentUriRaw.isNullOrBlank()) {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    Uri.parse(currentUriRaw)
                                )
                            }
                        }
                        startActivityForResult(pickerIntent, requestCodePickSystemSound)
                    }
                    "getRingtoneTitle" -> {
                        val uriRaw = call.argument<String>("uri")
                        if (uriRaw.isNullOrBlank()) {
                            result.success("Predeterminado del sistema")
                            return@setMethodCallHandler
                        }
                        val ringtone = RingtoneManager.getRingtone(this, Uri.parse(uriRaw))
                        result.success(ringtone?.getTitle(this) ?: "Tono personalizado")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestCodePickSystemSound) return
        val result = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val pickedUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }

        result.success(pickedUri?.toString())
    }
}
