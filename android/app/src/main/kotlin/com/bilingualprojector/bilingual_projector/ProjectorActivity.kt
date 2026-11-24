package com.bilingualprojector.bilingual_projector

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * The projector as its own window on another screen: used for Samsung DeX
 * and Android desktop mode (Pixel), where that screen is a desktop rather
 * than a plain second display. It shows the projector that
 * [ExternalDisplay] started for that screen.
 */
class ProjectorActivity : FlutterActivity() {
    private val display: Int
        get() = intent.getIntExtra(ExternalDisplay.EXTRA_DISPLAY, -1)

    // (False when Android brings the window back after the app was
    // closed: there's no projector to show any more.)
    private var live = false

    override fun getCachedEngineId(): String? =
        if (live) ExternalDisplay.engineId(display) else null

    // ExternalDisplay ends the projector once this window has gone.
    override fun shouldDestroyEngineWithHost(): Boolean = !live

    override fun onCreate(savedInstanceState: Bundle?) {
        live = ExternalDisplay.has(display)
        if (!live) {
            super.onCreate(null)
            finish()
            return
        }
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Full screen: no status or navigation bars over the slides.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
        ExternalDisplay.projectorWindowOpened(this, display)
    }

    override fun onDestroy() {
        super.onDestroy()
        ExternalDisplay.projectorWindowClosed(this)
    }
}
