package emkiwear.app

import android.content.Intent
import android.os.Build
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal "emkiwear/offline_speech": consulta y descarga el modelo de
 * reconocimiento de voz EN EL DISPOSITIVO (el mismo que usa speech_to_text con
 * onDevice: true), para que el asistente funcione sin internet.
 * Requiere Android 13 (API 33); en Android 14+ informa el resultado de la descarga.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "emkiwear/offline_speech"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val language = call.argument<String>("language") ?: "es-US"
                when (call.method) {
                    "status" -> status(language, result)
                    "download" -> download(language, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun recognizerIntent(language: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        }

    private fun onDeviceAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)

    /** Idiomas instalados, en descarga y descargables para el reconocedor en el dispositivo. */
    private fun status(language: String, result: MethodChannel.Result) {
        if (!onDeviceAvailable()) {
            result.success(mapOf("supported" to false, "reason" to "Android < 13 o sin reconocedor en el dispositivo"))
            return
        }
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        var replied = false
        recognizer.checkRecognitionSupport(
            recognizerIntent(language),
            mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (replied) return
                    replied = true
                    recognizer.destroy()
                    result.success(
                        mapOf(
                            "supported" to true,
                            "installed" to support.installedOnDeviceLanguages,
                            "pending" to support.pendingOnDeviceLanguages,
                            "available" to support.supportedOnDeviceLanguages,
                            "online" to support.onlineLanguages,
                        )
                    )
                }

                override fun onError(error: Int) {
                    if (replied) return
                    replied = true
                    recognizer.destroy()
                    result.success(mapOf("supported" to false, "reason" to "error $error"))
                }
            },
        )
    }

    /**
     * Pide al sistema descargar el modelo del idioma. Devuelve "success",
     * "scheduled" (se descargará cuando haya red/wifi), "requested" (Android 13,
     * sin confirmación), "error:<código>" o "unsupported".
     */
    private fun download(language: String, result: MethodChannel.Result) {
        if (!onDeviceAvailable()) {
            result.success("unsupported")
            return
        }
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            var replied = false
            fun reply(value: String) {
                if (replied) return
                replied = true
                recognizer.destroy()
                result.success(value)
            }
            recognizer.triggerModelDownload(
                recognizerIntent(language),
                mainExecutor,
                object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {}
                    override fun onSuccess() = reply("success")
                    override fun onScheduled() = reply("scheduled")
                    override fun onError(error: Int) = reply("error:$error")
                },
            )
        } else {
            recognizer.triggerModelDownload(recognizerIntent(language))
            recognizer.destroy()
            result.success("requested")
        }
    }
}
