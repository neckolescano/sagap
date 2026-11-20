package dev.sagap.sagap

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/**
 * Streams the connected Wi-Fi network's signal to Dart about once per second
 * (SPEC.md §7). Emits maps: tMs, connected, rssi, freqMhz, source.
 *
 * Never reads or emits SSID/BSSID. On Android 12+ the network callback is
 * registered without the location flag, so the OS redacts those fields.
 */
class WifiSignalStreamHandler(context: Context) : EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "sagap/rssi"
        private const val TICK_MS = 1000L
        private const val SOURCE_CALLBACK = "callback"
        private const val SOURCE_POLL = "poll"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectivityManager =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
    private val wifiManager =
        appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?

    private var sink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Latest values from the network callback (Android 12+ only).
    private var callbackWifiNetwork: Network? = null
    private var callbackRssi: Int? = null
    private var callbackFreqMhz: Int? = null

    private val tick = object : Runnable {
        override fun run() {
            emitReading()
            mainHandler.postDelayed(this, TICK_MS)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (connectivityManager == null || wifiManager == null) {
            events.error("unavailable", "Wi-Fi or connectivity service is not available", null)
            return
        }
        sink = events
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            registerCallback(connectivityManager)
        }
        mainHandler.post(tick)
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    /** Stops readings and releases the network callback. Safe to call twice. */
    fun stop() {
        mainHandler.removeCallbacks(tick)
        networkCallback?.let { callback ->
            connectivityManager?.unregisterNetworkCallback(callback)
        }
        networkCallback = null
        callbackWifiNetwork = null
        callbackRssi = null
        callbackFreqMhz = null
        sink = null
    }

    private fun registerCallback(cm: ConnectivityManager) {
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val info = caps.transportInfo as? WifiInfo ?: return
                callbackWifiNetwork = network
                callbackRssi = info.rssi
                callbackFreqMhz = info.frequency
            }

            override fun onLost(network: Network) {
                if (network == callbackWifiNetwork) {
                    callbackWifiNetwork = null
                    callbackRssi = null
                    callbackFreqMhz = null
                }
            }
        }
        cm.registerNetworkCallback(request, callback, mainHandler)
        networkCallback = callback
    }

    private fun emitReading() {
        val events = sink ?: return
        val reading = HashMap<String, Any?>()
        reading["tMs"] = SystemClock.elapsedRealtime()

        val rssi = callbackRssi
        if (callbackWifiNetwork != null && rssi != null) {
            reading["connected"] = true
            reading["rssi"] = rssi
            reading["freqMhz"] = callbackFreqMhz
            reading["source"] = SOURCE_CALLBACK
        } else if (isWifiActiveNetwork()) {
            @Suppress("DEPRECATION") // Fallback; see SPEC.md §7.
            val info = wifiManager?.connectionInfo
            reading["connected"] = info != null
            reading["rssi"] = info?.rssi
            reading["freqMhz"] = info?.frequency
            reading["source"] = SOURCE_POLL
        } else {
            reading["connected"] = false
            reading["source"] = SOURCE_POLL
        }
        events.success(reading)
    }

    private fun isWifiActiveNetwork(): Boolean {
        val cm = connectivityManager ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }
}
