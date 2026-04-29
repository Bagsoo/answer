package com.answer.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class VoiceCallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val roomName = intent?.getStringExtra(EXTRA_ROOM_NAME)?.takeIf { it.isNotBlank() }
            ?: "Voice Room"
        val ongoingText = intent?.getStringExtra(EXTRA_ONGOING_TEXT)?.takeIf { it.isNotBlank() }
            ?: "Voice call in progress"
        val returnActionLabel =
            intent?.getStringExtra(EXTRA_RETURN_ACTION_LABEL)?.takeIf { it.isNotBlank() }
                ?: "Return"
        val endActionLabel =
            intent?.getStringExtra(EXTRA_END_ACTION_LABEL)?.takeIf { it.isNotBlank() }
                ?: "End"

        ensureChannel()
        startForeground(
            NOTIFICATION_ID,
            buildNotification(roomName, ongoingText, returnActionLabel, endActionLabel)
        )
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Voice Call",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Ongoing voice call"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        roomName: String,
        ongoingText: String,
        returnActionLabel: String,
        endActionLabel: String,
    ): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val returnIntent = Intent(this, VoiceCallActionReceiver::class.java).apply {
            action = ACTION_RETURN_TO_CALL
        }
        val returnPendingIntent = PendingIntent.getBroadcast(
            this,
            1002,
            returnIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val endIntent = Intent(this, VoiceCallActionReceiver::class.java).apply {
            action = ACTION_END_CALL
        }
        val endPendingIntent = PendingIntent.getBroadcast(
            this,
            1003,
            endIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(roomName)
            .setContentText(ongoingText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .addAction(0, returnActionLabel, returnPendingIntent)
            .addAction(0, endActionLabel, endPendingIntent)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "voice_call_service"
        const val NOTIFICATION_ID = 42021
        const val PREFS_NAME = "voice_call_service"
        const val KEY_PENDING_ACTION = "pending_action"
        const val ACTION_RETURN_TO_CALL = "com.answer.app.voice_call.RETURN"
        const val ACTION_END_CALL = "com.answer.app.voice_call.END"
        const val EXTRA_ROOM_NAME = "room_name"
        const val EXTRA_ONGOING_TEXT = "ongoing_text"
        const val EXTRA_RETURN_ACTION_LABEL = "return_action_label"
        const val EXTRA_END_ACTION_LABEL = "end_action_label"
    }
}
