package com.devcat.escooter_control

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var features: PlatformFeatures? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        features = PlatformFeatures(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onResume() { super.onResume(); features?.resume() }
    override fun onPause() { features?.pause(); super.onPause() }
    override fun onDestroy() { features?.close(); features = null; super.onDestroy() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        features?.permissionsResult(requestCode)
    }
}
