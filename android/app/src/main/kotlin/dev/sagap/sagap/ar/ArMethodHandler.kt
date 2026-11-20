package dev.sagap.sagap.ar

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `sagap/ar` commands (SPEC.md §2): availability, install, camera permission,
 * pause/resume. Availability and install statuses are sent as enum names.
 */
class ArMethodHandler(
    private val activity: Activity,
    private val manager: ArSessionManager,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "sagap/ar"
        const val CAMERA_REQUEST_CODE = 4201
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" ->
                result.success(ArCoreApk.getInstance().checkAvailability(activity).name)

            "requestInstall" -> try {
                val status = ArCoreApk.getInstance().requestInstall(activity, true)
                result.success(status.name)
            } catch (e: UnavailableException) {
                result.error("install_failed", e.javaClass.simpleName, null)
            }

            "cameraPermission" -> result.success(cameraStatus())

            "requestCameraPermission" -> {
                if (cameraStatus() == "granted") {
                    result.success("granted")
                } else if (pendingPermission != null) {
                    result.error("busy", "A camera permission request is already open", null)
                } else {
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST_CODE)
                }
            }

            "pause" -> {
                manager.userPause()
                result.success(null)
            }

            "resume" -> {
                manager.userResume()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != CAMERA_REQUEST_CODE) return
        val result = pendingPermission ?: return
        pendingPermission = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(if (granted) "granted" else "denied")
    }

    private fun cameraStatus(): String =
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else {
            "denied"
        }
}
