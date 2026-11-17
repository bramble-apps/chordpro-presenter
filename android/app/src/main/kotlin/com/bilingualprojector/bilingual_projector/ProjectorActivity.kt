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
 * than a plain second display. It shows the projector engine that
 * [ExternalDisplay] keeps running.
 */
class ProjectorActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = ExternalDisplay.ENGINE_ID

    // The projector keeps running if this window is closed and reopened.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        ExternalDisplay.ensureEngine(this)
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
        ExternalDisplay.projectorWindowOpened(this)
    }

    override fun onDestroy() {
        ExternalDisplay.projectorWindowClosed(this)
        super.onDestroy()
    }
}
