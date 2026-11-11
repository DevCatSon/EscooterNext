package com.devcat.escooter_control

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Platform APIs only. No coordinates leave the native location callback. */
class PlatformFeatures(private val activity: MainActivity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, LocationListener {
    private val methods = MethodChannel(messenger, "escooter/platform")
    private val events = EventChannel(messenger, "escooter/phone_speed")
    private val locations = activity.getSystemService(LocationManager::class.java)
    private var sink: EventChannel.EventSink? = null
    private var authorization: MethodChannel.Result? = null
    private var foreground = true
    private val aliases = linkedMapOf("standard" to "LauncherDefault", "material" to "LauncherMaterial", "midnight" to "LauncherMidnight", "volt" to "LauncherVolt")
    init { methods.setMethodCallHandler(this); events.setStreamHandler(this) }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "authorizeLocation" -> {
                    if (precisePermission()) result.success(null)
                    else if (authorization != null) result.error("busy", "A location request is already open.", null)
                    else {
                        authorization = result
                        activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 8401)
                    }
                }
                "iconInfo" -> result.success(mapOf("name" to currentIcon(), "canChange" to true))
                "setIcon" -> { setIcon(call.argument<String>("name") ?: ""); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            if (authorization === result) authorization = null
            result.error("platform", error.message ?: "This feature is unavailable.", null)
        }
    }
    private fun precisePermission() = activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    fun permissionsResult(code: Int) {
        if (code != 8401) return
        val reply = authorization; authorization = null
        if (precisePermission()) reply?.success(null)
        else reply?.error("location_permission", "Allow Precise Location in phone settings to use phone speed.", null)
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink; startLocation() }
    override fun onCancel(arguments: Any?) { stopLocation(); sink = null }
    private fun startLocation() {
        if (!foreground || sink == null) return
        if (!precisePermission()) { sink?.error("location_permission", "Allow Precise Location in phone settings.", null); return }
        try {
            if (!locations.allProviders.contains(LocationManager.GPS_PROVIDER) || !locations.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                sink?.error("location_disabled", "Turn on Location services for phone speed.", null); return
            }
            locations.removeUpdates(this)
            @Suppress("DEPRECATION", "MissingPermission")
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this, Looper.getMainLooper())
        } catch (_: SecurityException) { sink?.error("location_permission", "Allow Precise Location in phone settings.", null) }
    }
    private fun stopLocation() { try { locations.removeUpdates(this) } catch (_: SecurityException) { } }
    fun pause() { foreground = false; stopLocation() }
    fun resume() { foreground = true; startLocation() }
    override fun onLocationChanged(location: Location) {
        if (!foreground) return
        val uncertainty = if (Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond.toDouble() else null
        sink?.success(mapOf(
            "speed" to if (location.hasSpeed()) location.speed.toDouble() else -1.0,
            "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else -1.0,
            "speedAccuracy" to uncertainty,
            "ageMs" to (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1000000L
        ))
    }
    override fun onProviderDisabled(provider: String) { sink?.error("location_disabled", "Location services are unavailable.", null) }
    override fun onProviderEnabled(provider: String) { startLocation() }
    @Deprecated("Required on Android 7")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) { }
    private fun component(name: String) = ComponentName(activity.packageName, "${activity.packageName}.${aliases[name]}")
    private fun currentIcon(): String = aliases.keys.firstOrNull { key ->
        when (activity.packageManager.getComponentEnabledSetting(component(key))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> key == "standard"
            else -> false
        }
    } ?: "standard"
    private fun setIcon(name: String) {
        require(aliases.containsKey(name)) { "Unknown icon preset." }
        val pm = activity.packageManager
        if (Build.VERSION.SDK_INT >= 33) {
            pm.setComponentEnabledSettings(aliases.keys.map { key -> PackageManager.ComponentEnabledSetting(component(key), if (key == name) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) })
        } else {
            val old = currentIcon()
            try {
                pm.setComponentEnabledSetting(component(name), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                aliases.keys.filter { it != name }.forEach { pm.setComponentEnabledSetting(component(it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) }
            } catch (error: Exception) {
                pm.setComponentEnabledSetting(component(old), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                throw error
            }
        }
    }
    fun close() {
        stopLocation(); sink = null
        authorization?.error("closed", "The permission request was interrupted.", null); authorization = null
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
    }
}
