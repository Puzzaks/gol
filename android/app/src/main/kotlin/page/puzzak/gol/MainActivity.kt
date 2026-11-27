package page.puzzak.gol

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var displayChannel: MethodChannel? = null
    private var pendingInitialLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingInitialLink = intent?.dataString
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        displayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "page.puzzak.gol/display",
        )
        displayChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showToast" -> {
                    val message = call.argument<String>("message")
                    val long = call.argument<Boolean>("long") ?: false
                    if (!message.isNullOrEmpty()) {
                        runOnUiThread {
                            Toast.makeText(
                                this,
                                message,
                                if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }
                    result.success(null)
                }

                "getInitialDeepLink" -> {
                    val link = pendingInitialLink ?: intent?.dataString
                    pendingInitialLink = null
                    intent?.data = null
                    result.success(link)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString
        if (link != null) {
            if (displayChannel != null) {
                displayChannel?.invokeMethod("onDeepLink", link)
            } else {
                pendingInitialLink = link
            }
        }
    }
}
