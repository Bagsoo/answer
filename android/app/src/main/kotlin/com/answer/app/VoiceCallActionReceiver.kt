package com.answer.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class VoiceCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = when (intent?.action) {
            VoiceCallForegroundService.ACTION_END_CALL -> "end"
            else -> "return"
        }

        context.getSharedPreferences(VoiceCallForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(VoiceCallForegroundService.KEY_PENDING_ACTION, action)
            .apply()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        context.startActivity(launchIntent)
    }
}
