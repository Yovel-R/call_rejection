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

        // Strategy 1: respond immediately (most reliable — no delay issues)
        // Uncomment this block and comment out Strategy 2 to test immediate reject:
        
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
        

        // Strategy 2: Thread.sleep delay (avoids Handler main-looper timing issues)
        // Log.d(TAG, "⏳ Starting background thread for 3 s delay...")
        // Thread {
        //     try {
        //         Thread.sleep(3000)
        //         Log.d(TAG, "⛔ Rejecting call from $number after 3 s")
        //         val response = CallResponse.Builder()
        //             .setRejectCall(true)
        //             .setDisallowCall(true)
        //             .setSkipNotification(true)
        //             .build()
        //             
        //         // When using CallScreeningService, we must NOT be the ones ending
        //         // the call from the fallback receiver. But the fallback receiver 
        //         // handles the UI streaming. We leave the delay simply to not race.
        //     } catch (e: Exception) {}
        // }.start()
    }
}
