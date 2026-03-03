package com.example.call_recording_frontend

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object BackendApi {
    private const val TAG = "BackendApi"
    
    private const val BASE_URL = "https://call-backend-fzhj.onrender.com" 

    fun sendCallLog(context: Context, incomingNumber: String) {
        if (incomingNumber.isBlank()) return

        thread {
            try {
                // Read the logged-in user's phone number from Flutter SharedPreferences
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val receivingNumber = prefs.getString("flutter.user_phone", null)

                Log.d(TAG, "Attempting to send log: receivingNumber=$receivingNumber, incomingNumber=$incomingNumber")

                if (receivingNumber.isNullOrBlank()) {
                    Log.e(TAG, "Cannot send call log: No user logged in (receivingNumber is empty)")
                    return@thread
                }

                val url = URL("$BASE_URL/api/calls")
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.doOutput = true
                connection.connectTimeout = 5000
                connection.readTimeout = 5000

                // Create JSON payload
                val jsonParam = JSONObject()
                jsonParam.put("receivingNumber", receivingNumber)
                jsonParam.put("incomingNumber", incomingNumber)

                Log.d(TAG, "Payload: $jsonParam")

                OutputStreamWriter(connection.outputStream).use { writer ->
                    writer.write(jsonParam.toString())
                    writer.flush()
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Server Response Code: $responseCode")

            } catch (e: Exception) {
                Log.e(TAG, "Failed to send call log to backend: ${e.message}", e)
            }
        }
    }
}
