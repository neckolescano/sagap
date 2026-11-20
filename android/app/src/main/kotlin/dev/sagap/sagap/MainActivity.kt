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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, WifiSignalStreamHandler.CHANNEL)
            .setStreamHandler(WifiSignalStreamHandler(this))
        MethodChannel(messenger, ArMethodHandler.CHANNEL).setMethodCallHandler(arMethods)
        MethodChannel(messenger, WifiScanHandler.CHANNEL).setMethodCallHandler(wifiScan)
        EventChannel(messenger, ArSessionManager.POSE_CHANNEL).setStreamHandler(arManager)
        flutterEngine.platformViewsController.registry
            .registerViewFactory(ArCameraViewFactory.VIEW_TYPE, ArCameraViewFactory(arManager))
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
