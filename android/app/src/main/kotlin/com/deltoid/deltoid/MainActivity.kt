package com.deltoid.deltoid

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.io.File
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
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
            // Removing the splash applies the activity's theme, and that
            // application is the last word on the system bars' appearance: it
            // overwrites whatever Flutter set from Dart. So say it again, on
            // the next frame rather than inside the removal. Belt and braces —
            // this listener is not called on every skin, which is why
            // `bootComplete` re-asserts on a spread of frames as well.
            window.decorView.post { applyBarAppearance() }
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

    /**
     * Whether the app is drawing light backgrounds, and so wants dark icons.
     *
     * Sent from Dart over `systemBars`, and said again on every change: the
     * app's theme is a setting of its own and need not agree with the system's
     * night mode, which is all `values-night/styles.xml` can follow. Null
     * until Dart has spoken — an appearance is never guessed at.
     */
    private var lightBars: Boolean? = null

    private fun applyBarAppearance() {
        val light = lightBars ?: return
        WindowInsetsControllerCompat(window, window.decorView).run {
            isAppearanceLightStatusBars = light
            isAppearanceLightNavigationBars = light
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyBarAppearance()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bootComplete" -> {
                        bootComplete = true
                        // The splash is what overwrites the bars' appearance,
                        // so this is the moment to say it again. Over several
                        // frames: the theme is applied somewhere inside the
                        // removal, and the exit listener does not fire on
                        // every skin.
                        applyBarAppearance()
                        for (delay in BAR_REASSERTS) {
                            window.decorView.postDelayed({ applyBarAppearance() }, delay)
                        }
                        result.success(null)
                    }
                    "systemBars" -> {
                        lightBars = call.argument<Boolean>("lightBars")
                        applyBarAppearance()
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
                    "pickBackup" -> {
                        if (pendingPick != null) {
                            result.error("busy", "A file is already being picked.", null)
                        } else {
                            pendingPick = result
                            startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    // Not `application/json`: a .json arriving from
                                    // Downloads, a share sheet or a cloud provider is
                                    // as often octet-stream or text/plain, and the
                                    // filter greys out the very file the user came
                                    // for. What it is gets decided by reading it.
                                    type = "*/*"
                                },
                                PICK_BACKUP,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Copies the picked document into the cache and hands Dart the path.
     *
     * The path, never the bytes. `file_selector` returns a picked file's
     * *contents* through the platform channel, and the codec builds the whole
     * thing in one `ByteArrayOutputStream` on the main thread: a 67 MB backup
     * asked for a 134 MB array and threw `OutOfMemoryError` before a single row
     * had been restored — with the user's only copy of their training in the
     * picker. Export already knew better (see `DownloadsWriter`); this is the
     * same rule on the way back in.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_BACKUP) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPick
        pendingPick = null
        if (result == null) return

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        // On a worker: this is a copy of a file that can be tens of megabytes,
        // and it is started from a screen that has to keep drawing.
        Thread {
            try {
                val target = File(cacheDir, "restore-${System.currentTimeMillis()}.json")
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) throw IllegalStateException("The file could not be opened.")
                    target.outputStream().use { output -> input.copyTo(output, COPY_BUFFER) }
                }
                runOnUiThread { result.success(target.absolutePath) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("pick_failed", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private var pendingPick: MethodChannel.Result? = null

    companion object {
        private const val CHANNEL = "com.deltoid.deltoid/boot"
        private const val FILES_CHANNEL = "com.deltoid.deltoid/files"
        private const val BOOT_TIMEOUT_MS = 5_000L
        private const val PICK_BACKUP = 0x0DEC
        private const val COPY_BUFFER = 64 * 1024

        /**
         * When to say the bars' appearance again, in milliseconds after the
         * launch window is told to lift.
         *
         * A spread rather than a single delay. Removing the splash applies the
         * activity's theme, and that application is what overwrites the
         * appearance; it does not land on a frame this side can name, and
         * `setOnExitAnimationListener` is not called at all on every skin —
         * OxygenOS 12 does not call it, which is what made the first attempt at
         * this dead code.
         */
        private val BAR_REASSERTS = longArrayOf(16, 100, 300, 800, 1600)
    }
}
