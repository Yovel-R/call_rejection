package com.example.call_recording_frontend

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "call_screening_channel"
        private const val EVENT_CHANNEL  = "call_screening_events"
        private const val REQUEST_CODE_ROLE = 1001
        private const val REQUEST_CODE_PERMISSIONS = 1002
        private const val TAG = "MainActivity"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var callReceiver: CallAutoRejectReceiver? = null

    private val requiredPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.ANSWER_PHONE_CALLS,
            Manifest.permission.READ_CALL_LOG
        )
    } else {
        arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_CALL_LOG)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine: setting up channels")

        // ── EventChannel — streams {state, number} to Flutter ──────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    Log.d(TAG, "EventChannel: Flutter started listening")
                    if (callReceiver == null) callReceiver = CallAutoRejectReceiver(applicationContext)
                    callReceiver!!.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EventChannel: Flutter cancelled")
                    callReceiver?.eventSink = null
                }
            })

        // ── MethodChannel — role requests / status ─────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "MethodChannel: ${call.method}")
                when (call.method) {
                    "requestScreeningRole" -> {
                        requestPermissionsIfNeeded()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(RoleManager::class.java)
                            val available = roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)
                            val held = roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
                            Log.d(TAG, "  roleAvailable=$available roleHeld=$held permsOk=${allPermissionsGranted()}")
                            if (available && !held) {
                                pendingResult = result
                                startActivityForResult(
                                    roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING),
                                    REQUEST_CODE_ROLE
                                )
                            } else {
                                registerFallbackReceiverIfNeeded()
                                result.success(true)
                            }
                        } else {
                            registerFallbackReceiverIfNeeded()
                            result.success(true)
                        }
                    }
                    "isScreeningRoleHeld" -> {
                        val permsOk = allPermissionsGranted()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val held = getSystemService(RoleManager::class.java)
                                .isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
                            Log.d(TAG, "isScreeningRoleHeld → roleHeld=$held permsOk=$permsOk")
                            result.success(permsOk || held)
                        } else {
                            result.success(permsOk)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStart() {
        super.onStart()
        if (allPermissionsGranted()) registerFallbackReceiverIfNeeded()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterFallbackReceiver()
    }

    private fun registerFallbackReceiverIfNeeded() {
        if (!allPermissionsGranted()) {
            Log.w(TAG, "⚠️ Cannot register receiver — permissions missing")
            return
        }
        if (callReceiver == null) callReceiver = CallAutoRejectReceiver(applicationContext)
        try {
            registerReceiver(callReceiver, callReceiver!!.intentFilter)
            Log.d(TAG, "📡 CallAutoRejectReceiver registered")
        } catch (e: Exception) {
            Log.w(TAG, "Receiver may already be registered: ${e.message}")
        }
    }

    private fun unregisterFallbackReceiver() {
        callReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            Log.d(TAG, "📡 CallAutoRejectReceiver unregistered")
        }
        callReceiver = null
    }

    private fun allPermissionsGranted() = requiredPermissions.all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissionsIfNeeded() {
        val missing = requiredPermissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            Log.d(TAG, "Requesting permissions: $missing")
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_CODE_PERMISSIONS)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_PERMISSIONS && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            Log.d(TAG, "Permissions granted — registering receiver")
            registerFallbackReceiverIfNeeded()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.d(TAG, "onActivityResult: requestCode=$requestCode resultCode=$resultCode")
        if (requestCode == REQUEST_CODE_ROLE) {
            val granted = resultCode == RESULT_OK
            Log.d(TAG, "  Role request result: granted=$granted")
            registerFallbackReceiverIfNeeded()
            pendingResult?.success(granted)
            pendingResult = null
        }
    }
}
