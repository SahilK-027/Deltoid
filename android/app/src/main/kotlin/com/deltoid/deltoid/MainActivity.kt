package com.deltoid.deltoid

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the launch window on screen for the whole of boot.
 *
 * Without this the mark is drawn twice: the OS draws it, drops it the moment
 * the engine attaches, and Flutter draws its own copy a beat later at a
 * different size — the platform scales a 288dp canvas into a 192dp circle,
 * Flutter was drawing the raw asset at 150dp. Keeping the system splash up
 * means there is only ever one mark, and no handoff to hide.
 */
class MainActivity : FlutterActivity() {
    private var bootComplete = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must precede super.onCreate: the splash is installed against the
        // activity's theme before the first window is laid out.
        val splash = installSplashScreen()
        splash.setKeepOnScreenCondition { !bootComplete }

        // Flutter lays its first frame out underneath the splash view, and
        // removing that view does not re-dispatch window insets on its own —
        // so ask for them again on the way out, or the shell keeps the
        // geometry it measured while the splash was up.
        splash.setOnExitAnimationListener { provider ->
            provider.remove()
            ViewCompat.requestApplyInsets(window.decorView)
        }

        super.onCreate(savedInstanceState)

        // After super, not before: FlutterActivity does its own window setup in
        // onCreate and would undo this. Until the decor stops fitting system
        // windows, the first frame is laid out below the status bar —
        // HeaderBand's SafeArea sees a top padding of zero, the band stops
        // short, and the window background shows through as a dark strip until
        // a tab switch rebuilds against the real geometry.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Dead man's switch. If Dart dies before it can signal — a failed
        // migration, an exception in main — the splash would otherwise sit
        // there forever, hiding the error behind it.
        Handler(Looper.getMainLooper()).postDelayed({ bootComplete = true }, BOOT_TIMEOUT_MS)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bootComplete" -> {
                        bootComplete = true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        // Off the main thread: this copies a file that can be
                        // tens of megabytes, and the UI it was started from is
                        // showing progress that has to keep moving.
                        Thread {
                            try {
                                val location = DownloadsWriter.save(
                                    applicationContext,
                                    call.argument<String>("sourcePath")!!,
                                    call.argument<String>("fileName")!!,
                                    call.argument<String>("folder")!!,
                                )
                                runOnUiThread { result.success(location) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "save_failed",
                                        e.message ?: e.toString(),
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val CHANNEL = "com.deltoid.deltoid/boot"
        private const val FILES_CHANNEL = "com.deltoid.deltoid/files"
        private const val BOOT_TIMEOUT_MS = 5_000L
    }
}
