package dev.sagap.sagap.ar

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel

/**
 * Owns the single ARCore [Session] (SPEC.md §7, §10).
 *
 * The session lives while the AR camera view is on screen. It is paused when
 * the user pauses the scan or the activity goes to the background. Poses are
 * sent to Dart over `sagap/pose` at most every [POSE_INTERVAL_MS].
 */
class ArSessionManager(private val activity: Activity) : EventChannel.StreamHandler {

    companion object {
        const val POSE_CHANNEL = "sagap/pose"
        private const val POSE_INTERVAL_MS = 200L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    var session: Session? = null
        private set

    /** True only while the session is resumed; read on the GL thread. */
    @Volatile
    var isRunning = false
        private set

    private var view: ArCameraView? = null
    private var userPaused = false
    private var activityPaused = false

    private var poseSink: EventChannel.EventSink? = null
    private var pendingError: Pair<String, String>? = null
    private var lastPoseEmitMs = 0L

    // ---- Pose stream -------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        poseSink = events
        pendingError?.let { (code, message) -> events.error(code, message, null) }
        pendingError = null
    }

    override fun onCancel(arguments: Any?) {
        poseSink = null
    }

    private fun sendError(code: String, message: String) {
        mainHandler.post {
            val sink = poseSink
            if (sink == null) pendingError = code to message else sink.error(code, message, null)
        }
    }

    // ---- View attach / detach ---------------------------------------------

    fun attach(cameraView: ArCameraView) {
        view = cameraView
        userPaused = false
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            sendError("camera_permission", "Camera permission is not granted")
            return
        }
        try {
            val newSession = Session(activity)
            val config = Config(newSession).apply {
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                focusMode = Config.FocusMode.AUTO
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
            }
            newSession.configure(config)
            session = newSession
        } catch (e: UnavailableException) {
            sendError("ar_unavailable", e.javaClass.simpleName)
            return
        }
        resumeIfAllowed()
    }

    fun detach(cameraView: ArCameraView) {
        if (view !== cameraView) return
        pauseSession()
        session?.close()
        session = null
        view = null
    }

    // ---- Pause / resume ----------------------------------------------------

    fun userPause() {
        userPaused = true
        pauseSession()
    }

    fun userResume() {
        userPaused = false
        resumeIfAllowed()
    }

    fun onActivityPause() {
        activityPaused = true
        pauseSession()
    }

    fun onActivityResume() {
        activityPaused = false
        resumeIfAllowed()
    }

    private fun resumeIfAllowed() {
        val s = session ?: return
        val v = view ?: return
        if (isRunning || userPaused || activityPaused) return
        try {
            s.resume()
        } catch (e: CameraNotAvailableException) {
            sendError("camera_unavailable", "The camera is in use or unavailable")
            return
        }
        v.onResume()
        isRunning = true
    }

    private fun pauseSession() {
        if (!isRunning) return
        isRunning = false
        // Stop the GL thread first so it is not inside session.update().
        view?.onPause()
        session?.pause()
    }

    // ---- Frames (GL thread) -----------------------------------------------

    fun onFrame(frame: Frame) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastPoseEmitMs < POSE_INTERVAL_MS) return
        lastPoseEmitMs = now
        val camera = frame.camera
        val pose = camera.pose
        val event = HashMap<String, Any>()
        event["tMs"] = now
        event["tracking"] = camera.trackingState.name
        event["failure"] = camera.trackingFailureReason.name
        event["x"] = pose.tx().toDouble()
        event["y"] = pose.ty().toDouble()
        event["z"] = pose.tz().toDouble()
        mainHandler.post { poseSink?.success(event) }
    }

    fun onFrameError(code: String, message: String) = sendError(code, message)
}
