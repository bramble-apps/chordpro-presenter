package com.bilingualprojector.bilingual_projector

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Monitors, TVs and projectors on USB-C / HDMI, and DeX / desktop mode.
        ExternalDisplay.attach(this, flutterEngine)
        // The worship pad's gapless loops.
        PadPlayer.attach(flutterEngine)
        // Settings → App icon.
        AppIcon.attach(this, flutterEngine)
        // Songs shared to the app or opened with it.
        ShareReceiver.attach(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ShareReceiver.handle(this, intent)
    }

    // Shared while the app was already open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShareReceiver.handle(this, intent)
    }

    override fun onDestroy() {
        ExternalDisplay.detach(this)
        PadPlayer.detach()
        super.onDestroy()
    }
}
