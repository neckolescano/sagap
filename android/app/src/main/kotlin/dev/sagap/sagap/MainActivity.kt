package dev.sagap.sagap

import dev.sagap.sagap.ar.ArCameraViewFactory
import dev.sagap.sagap.ar.ArMethodHandler
import dev.sagap.sagap.ar.ArSessionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val arManager by lazy { ArSessionManager(this) }
    private val arMethods by lazy { ArMethodHandler(this, arManager) }
    private val wifiScan by lazy { WifiScanHandler(this) }
    private var signalStream: WifiSignalStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val stream = WifiSignalStreamHandler(this)
        signalStream = stream
        EventChannel(messenger, WifiSignalStreamHandler.CHANNEL).setStreamHandler(stream)
        MethodChannel(messenger, ArMethodHandler.CHANNEL).setMethodCallHandler(arMethods)
        MethodChannel(messenger, WifiScanHandler.CHANNEL).setMethodCallHandler(wifiScan)
        MethodChannel(messenger, ShareHandler.CHANNEL).setMethodCallHandler(ShareHandler(this))
        EventChannel(messenger, ArSessionManager.POSE_CHANNEL).setStreamHandler(arManager)
        flutterEngine.platformViewsController.registry
            .registerViewFactory(ArCameraViewFactory.VIEW_TYPE, ArCameraViewFactory(arManager))
    }

    // Dart never cancels the stream when the activity is destroyed, so stop
    // the 1 s timer and network callback here; otherwise they keep running
    // and send to a detached engine.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        signalStream?.stop()
        signalStream = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        arManager.onActivityResume()
    }

    override fun onPause() {
        arManager.onActivityPause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        arMethods.onPermissionResult(requestCode, grantResults)
        wifiScan.onPermissionResult(requestCode)
    }
}
