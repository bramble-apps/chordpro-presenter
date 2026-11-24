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
 * Shows the projector on external screens.
 *
 * Android phones offer a second screen in two ways:
 *  - Mirroring / a plain HDMI or USB-C screen (Samsung with DeX off, most
 *    phones): a "presentation" display. The projector is drawn there
 *    directly ([Presentation]) while the app stays open on the phone.
 *  - Samsung DeX, Android desktop mode (Pixel 8+): the screen is a desktop.
 *    Presentations aren't allowed there, so the projector opens as its own
 *    window on that desktop ([ProjectorActivity]).
 *
 * Each screen has its own projector, in its own Flutter engine
 * (`secondaryDisplayMain`), so two screens can show different views (the
 * lyrics on one, the band's stage view on the other). Messages pass both
 * ways between them and the operator through here.
 */
object ExternalDisplay {
    const val EXTRA_DISPLAY = "display"
    private const val TAG = "ExternalDisplay"

    /** A screen showing the projector. */
    private class Output(
        val id: Int,
        /** The view it's kept on ("stage" / "lyrics"), or null: the shared one. */
        val show: String?,
        val engine: FlutterEngine,
        val channel: MethodChannel,
    ) {
        var presentation: Presentation? = null
        var window: Activity? = null
    }

    private var activity: Activity? = null
    private var operator: MethodChannel? = null
    private var displays: DisplayManager? = null
    private val outputs = LinkedHashMap<Int, Output>()
    private val main = Handler(Looper.getMainLooper())

    fun engineId(display: Int) = "projector-$display"

    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) = changed()
        override fun onDisplayChanged(id: Int) = changed()
        override fun onDisplayRemoved(id: Int) {
            outputs[id]?.let { closed(it) }
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
                        "show" -> result.success(
                            show(call.argument<Int>("id")!!, call.argument<String>("show"))
                        )
                        "hide" -> {
                            // One screen, or (no id) all of them.
                            val id = call.argument<Int>("id")
                            if (id == null) hideAll() else outputs[id]?.let { hide(it) }
                            result.success(null)
                        }
                        "send" -> {
                            for (o in outputs.values) {
                                o.channel.invokeMethod("message", call.arguments)
                            }
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
        // (Drawn through this activity: they go with it.)
        for (o in outputs.values.filter { it.presentation != null }) hide(o)
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

    /**
     * Shows the projector on display [id], kept on the view [show] if
     * given; returns how ("screen" / "window"). Other screens stay as
     * they are.
     */
    private fun show(id: Int, show: String?): String {
        val act = activity ?: throw IllegalStateException("The app isn't open")
        val dm = displays ?: throw IllegalStateException("No display service")
        val display = dm.getDisplay(id) ?: throw IllegalArgumentException(
            "That screen was disconnected"
        )
        outputs[id]?.let { hide(it) }
        val o = start(act, id, show)
        val presentable = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .any { it.displayId == id }
        // Mirroring / plain screens: draw straight onto it. If that's
        // refused (desktop modes), open a window there instead.
        if (presentable) {
            try {
                showPresentation(act, display, o)
                return "screen"
            } catch (e: Exception) {
                Log.i(TAG, "Presentation refused on $id, opening a window", e)
                o.presentation = null
            }
        }
        try {
            openWindow(act, id)
        } catch (e: Exception) {
            hide(o)
            throw e
        }
        return "window"
    }

    private fun showPresentation(act: Activity, display: Display, o: Output) {
        val p = object : Presentation(act, display) {
            private var view: FlutterView? = null

            override fun onCreate(savedInstanceState: Bundle?) {
                super.onCreate(savedInstanceState)
                window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                view = FlutterView(context).also {
                    setContentView(it)
                    it.attachToFlutterEngine(o.engine)
                }
            }

            override fun onStop() {
                view?.detachFromFlutterEngine()
                view = null
                super.onStop()
            }
        }
        p.setOnDismissListener {
            // Taken down by Android (not by hide, which forgets it first).
            if (o.presentation === p) {
                o.presentation = null
                closed(o)
            }
        }
        p.show() // throws if this screen doesn't allow it
        o.presentation = p
        o.engine.lifecycleChannel.appIsResumed()
    }

    private fun openWindow(act: Activity, id: Int) {
        val intent = Intent(act, ProjectorActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            .putExtra(EXTRA_DISPLAY, id)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(id)
        act.startActivity(intent, options.toBundle())
    }

    private fun hideAll() {
        for (o in outputs.values.toList()) hide(o)
    }

    /** Takes the projector off a screen (the operator asked). */
    private fun hide(o: Output) {
        if (outputs[o.id] === o) outputs.remove(o.id)
        o.presentation?.let { o.presentation = null; it.dismiss() }
        val w = o.window
        if (w != null) {
            // Its engine goes once the window has (projectorWindowClosed).
            w.finish()
        } else {
            release(o)
        }
    }

    /** A projector stopped showing without the operator asking. */
    private fun closed(o: Output) {
        if (outputs[o.id] !== o) return
        hide(o)
        operator?.invokeMethod("projectorClosed", o.id)
    }

    private fun release(o: Output) {
        val key = engineId(o.id)
        val cache = FlutterEngineCache.getInstance()
        if (cache.get(key) === o.engine) cache.remove(key)
        // (After the view has let go of it.)
        main.post { o.engine.destroy() }
    }

    private val windowOutputs = HashMap<Activity, Output>()

    fun projectorWindowOpened(window: Activity, display: Int) {
        val o = outputs[display] ?: return
        o.window = window
        windowOutputs[window] = o
    }

    fun projectorWindowClosed(window: Activity) {
        val o = windowOutputs.remove(window) ?: return
        o.window = null
        if (outputs[o.id] === o) {
            // Closed on the desktop itself.
            closed(o)
        } else {
            release(o)
        }
    }

    /** True if display [id] has a projector for a window to show. */
    fun has(id: Int) = outputs.containsKey(id)

    /** Starts a projector for display [id]. */
    private fun start(context: Context, id: Int, show: String?): Output {
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val engine = FlutterEngine(app)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "bp/projector")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "toOperator" -> {
                    operator?.invokeMethod("fromProjector", call.arguments)
                    result.success(null)
                }
                // Which view this screen is kept on (asked as it starts).
                "show" -> result.success(show)
                else -> result.success(null)
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "secondaryDisplayMain")
        )
        FlutterEngineCache.getInstance().put(engineId(id), engine)
        return Output(id, show, engine, channel).also { outputs[id] = it }
    }
}
