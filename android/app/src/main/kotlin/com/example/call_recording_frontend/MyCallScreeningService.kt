package com.example.call_recording_frontend

import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log

class MyCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "CallScreeningService"
    }

    override fun onScreenCall(callDetails: Call.Details) {
        val number = callDetails.handle?.schemeSpecificPart ?: "unknown"
        val direction = if (callDetails.callDirection == Call.Details.DIRECTION_INCOMING)
            "INCOMING" else "OUTGOING"

        Log.d(TAG, "▶ onScreenCall triggered — direction=$direction number=$number")

        
        try {
            val response = CallResponse.Builder()
                .setRejectCall(true)
                .setDisallowCall(true)
                .setSkipNotification(true)
                .build()
            respondToCall(callDetails, response)
            Log.d(TAG, "✅ Immediate respondToCall() done")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Immediate respondToCall() failed: ${e.message}", e)
        }
    }
}
