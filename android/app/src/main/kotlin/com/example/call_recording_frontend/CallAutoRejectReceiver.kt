package com.example.call_recording_frontend

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.EventChannel

/**
 * Fallback auto-reject using TelephonyManager state + TelecomManager.endCall().
 * Works reliably on custom ROMs (Vivo/iQOO) where CallScreeningService is bypassed.
 * Also streams call events {state, number} to Flutter via [eventSink].
 */
class CallAutoRejectReceiver(
    private val context: Context,
    var eventSink: EventChannel.EventSink? = null
) : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallAutoReject"
        private const val REJECT_DELAY_MS = 3000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var rejectRunnable: Runnable? = null

    val intentFilter: IntentFilter
        get() = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)

    override fun onReceive(ctx: Context, intent: Intent) {
        val state  = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
        Log.d(TAG, "Phone state changed → state=$state  number=$number")

        // Push event to Flutter UI
        handler.post {
            eventSink?.success(mapOf("state" to state, "number" to number))
        }

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                Log.d(TAG, "📞 Incoming call from $number — scheduling reject in ${REJECT_DELAY_MS}ms")
                cancelPending()
                rejectRunnable = Runnable {
                    Log.d(TAG, "⛔ Attempting to end call via TelecomManager")
                    endCallViaTelecom()
                }.also { handler.postDelayed(it, REJECT_DELAY_MS) }
            }
            TelephonyManager.EXTRA_STATE_IDLE,
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                Log.d(TAG, "📴 Call ended/answered — cancelling pending reject")
                cancelPending()
            }
        }
    }

    private fun cancelPending() {
        rejectRunnable?.let { handler.removeCallbacks(it) }
        rejectRunnable = null
    }

    @Suppress("DEPRECATION")
    private fun endCallViaTelecom() {
        try {
            val telecom = context.getSystemService(TelecomManager::class.java)
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)
                == PackageManager.PERMISSION_GRANTED
            ) {
                val ended = telecom.endCall()
                Log.d(TAG, "✅ telecom.endCall() returned: $ended")
            } else {
                Log.e(TAG, "❌ ANSWER_PHONE_CALLS permission not granted")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ endCall() threw: ${e.message}", e)
        }
    }
}
