package dev.sagap.sagap

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.provider.Settings
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `sagap/wifi` (SPEC.md §6, §7): location permission and the channel check.
 *
 * The channel check returns only aggregates: the connected network's
 * frequency and, per frequency, how many *other* networks are at or above
 * [STRONG_DBM]. SSIDs and BSSIDs never leave this class and are never logged.
 */
class WifiScanHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "sagap/wifi"
        const val LOCATION_REQUEST_CODE = 4202
        private const val STRONG_DBM = -70
        private const val SCAN_TIMEOUT_MS = 10_000L
    }

    private val wifiManager =
        activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "locationPermission" -> result.success(if (hasLocation()) "granted" else "denied")

            "requestLocationPermission" -> when {
                hasLocation() -> result.success("granted")
                pendingPermission != null ->
                    result.error("busy", "A location permission request is already open", null)
                else -> {
                    pendingPermission = result
                    activity.requestPermissions(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION,
                        ),
                        LOCATION_REQUEST_CODE,
                    )
                }
            }

            "locationServicesOn" -> result.success(locationServicesOn())

            "channelScan" -> channelScan(result)

            // Lets the user re-allow a permission they denied (SPEC.md §6).
            "openAppSettings" -> {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", activity.packageName, null),
                )
                activity.startActivity(intent)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int) {
        if (requestCode != LOCATION_REQUEST_CODE) return
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(if (hasLocation()) "granted" else "denied")
    }

    private fun hasLocation(): Boolean =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun locationServicesOn(): Boolean {
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager?
            ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun channelScan(result: MethodChannel.Result) {
        val wm = wifiManager
        if (wm == null) {
            result.error("unavailable", "Wi-Fi service is not available", null)
            return
        }
        if (!hasLocation()) {
            result.error("no_permission", "Location permission is not granted", null)
            return
        }
        if (!locationServicesOn()) {
            result.error("location_off", "Location services are off", null)
            return
        }

        var done = false
        lateinit var receiver: BroadcastReceiver
        val timeout = Runnable {
            if (done) return@Runnable
            done = true
            activity.unregisterReceiver(receiver)
            result.success(aggregate(wm, fresh = false))
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (done) return
                done = true
                mainHandler.removeCallbacks(timeout)
                activity.unregisterReceiver(this)
                val updated = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                result.success(aggregate(wm, fresh = updated))
            }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }

        @Suppress("DEPRECATION") // Still the only way to request a scan; SPEC.md §7.
        val started = wm.startScan()
        if (!started) {
            // Throttled or Wi-Fi busy: use the last results.
            done = true
            activity.unregisterReceiver(receiver)
            result.success(aggregate(wm, fresh = false))
            return
        }
        mainHandler.postDelayed(timeout, SCAN_TIMEOUT_MS)
    }

    private fun aggregate(wm: WifiManager, fresh: Boolean): Map<String, Any> {
        @Suppress("DEPRECATION")
        val connection = wm.connectionInfo
        val ownBssid = connection?.bssid
        val counts = HashMap<Int, Int>()
        for (scan in wm.scanResults) {
            if (ownBssid != null && scan.BSSID == ownBssid) continue
            if (scan.level < STRONG_DBM) continue
            counts[scan.frequency] = (counts[scan.frequency] ?: 0) + 1
        }
        return mapOf(
            "ownFreqMhz" to (connection?.frequency ?: -1),
            "fresh" to fresh,
            "counts" to counts,
        )
    }
}
