package com.bilingualprojector.bilingual_projector

import android.app.Activity
import android.app.ActivityOptions
import android.app.Presentation
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Shows the projector on an external screen.
 *
 * Android phones offer a second screen in two ways:
 *  - Mirroring / a plain HDMI or USB-C screen (Samsung with DeX off, most
 *    phones): a "presentation" display. The projector is drawn there
 *    directly ([Presentation]) while the app stays open on the phone.
 *  - Samsung DeX, Android desktop mode (Pixel 8+): the screen is a desktop.
 *    Presentations aren't allowed there, so the projector opens as its own
 *    window on that desktop ([ProjectorActivity]).
 *
 * The projector runs in a second Flutter engine (`secondaryDisplayMain`);
 * messages pass both ways between it and the operator through here.
 */
object ExternalDisplay {
    const val ENGINE_ID = "projector"
    private const val TAG = "ExternalDisplay"

    private var activity: Activity? = null
    private var operator: MethodChannel? = null
    private var projector: MethodChannel? = null
    private var displays: DisplayManager? = null
    private var presentation: Presentation? = null
    private var projectorWindow: Activity? = null
    private var showingId: Int? = null
    private val main = Handler(Looper.getMainLooper())

    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) = changed()
        override fun onDisplayChanged(id: Int) = changed()
        override fun onDisplayRemoved(id: Int) {
            if (id == showingId) closed()
            changed()
        }
    }

    private fun changed() {
        operator?.invokeMethod("displaysChanged", null)
    }

    fun attach(activity: Activity, engine: FlutterEngine) {
        this.activity = activity
        val dm = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displays?.unregisterDisplayListener(listener)
        displays = dm
        dm.registerDisplayListener(listener, main)
        operator = MethodChannel(engine.dartExecutor.binaryMessenger, "bp/displays").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "list" -> result.success(list())
                        "show" -> result.success(show(call.argument<Int>("id")!!))
                        "hide" -> { hide(); result.success(null) }
                        "send" -> {
                            projector?.invokeMethod("message", call.arguments)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "${call.method} failed", e)
                    result.error("display", e.message ?: e.toString(), null)
                }
            }
        }
    }

    fun detach(activity: Activity) {
        if (this.activity !== activity) return
        displays?.unregisterDisplayListener(listener)
        presentation?.dismiss()
        presentation = null
        this.activity = null
        operator = null
    }

    /** Every screen other than the phone's own that the app may draw on. */
    private fun list(): List<Map<String, Any>> {
        val dm = displays ?: return emptyList()
        val presenting = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .map { it.displayId }.toSet()
        return dm.displays
            .filter { it.displayId != Display.DEFAULT_DISPLAY }
            .filter { it.flags and Display.FLAG_PRIVATE == 0 }
            .filter { it.state != Display.STATE_OFF }
            .map { d ->
                val mode = d.mode
                mapOf(
                    "id" to d.displayId,
                    "name" to (d.name ?: "Display ${d.displayId}"),
                    "width" to mode.physicalWidth,
                    "height" to mode.physicalHeight,
                    "presentation" to (d.displayId in presenting),
                )
            }
    }

    /** Shows the projector on display [id]; returns how ("screen" / "window"). */
    private fun show(id: Int): String {
        val act = activity ?: throw IllegalStateException("The app isn't open")
        val dm = displays ?: throw IllegalStateException("No display service")
        val display = dm.getDisplay(id) ?: throw IllegalArgumentException(
            "That screen was disconnected"
        )
        hide()
        ensureEngine(act)
        val presentable = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .any { it.displayId == id }
        // Mirroring / plain screens: draw straight onto it. If that's
        // refused (desktop modes), open a window there instead.
        if (presentable) {
            try {
                showPresentation(act, display)
                showingId = id
                return "screen"
            } catch (e: Exception) {
                Log.i(TAG, "Presentation refused on $id, opening a window", e)
                presentation = null
            }
        }
        openWindow(act, id)
        showingId = id
        return "window"
    }

    private fun showPresentation(act: Activity, display: Display) {
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)!!
        val p = object : Presentation(act, display) {
            private var view: FlutterView? = null

            override fun onCreate(savedInstanceState: Bundle?) {
                super.onCreate(savedInstanceState)
                window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                view = FlutterView(context).also {
                    setContentView(it)
                    it.attachToFlutterEngine(engine)
                }
            }

            override fun onStop() {
                view?.detachFromFlutterEngine()
                view = null
                super.onStop()
            }
        }
        p.setOnDismissListener {
            if (presentation === p) {
                presentation = null
                closed()
            }
        }
        p.show() // throws if this screen doesn't allow it
        presentation = p
        engine.lifecycleChannel.appIsResumed()
    }

    private fun openWindow(act: Activity, id: Int) {
        val intent = Intent(act, ProjectorActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        )
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(id)
        act.startActivity(intent, options.toBundle())
    }

    private fun hide() {
        showingId = null
        presentation?.let { presentation = null; it.dismiss() }
        projectorWindow?.let { projectorWindow = null; it.finish() }
    }

    /** The projector stopped showing without the operator asking. */
    private fun closed() {
        if (showingId == null) return
        showingId = null
        operator?.invokeMethod("projectorClosed", null)
    }

    fun projectorWindowOpened(window: Activity) {
        projectorWindow = window
    }

    fun projectorWindowClosed(window: Activity) {
        if (projectorWindow !== window) return
        projectorWindow = null
        closed()
    }

    /** Starts the projector engine (once; it's kept for later). */
    fun ensureEngine(context: Context) {
        if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) return
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val engine = FlutterEngine(app)
        projector = MethodChannel(engine.dartExecutor.binaryMessenger, "bp/projector").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "toOperator") {
                    operator?.invokeMethod("fromProjector", call.arguments)
                }
                result.success(null)
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "secondaryDisplayMain")
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
