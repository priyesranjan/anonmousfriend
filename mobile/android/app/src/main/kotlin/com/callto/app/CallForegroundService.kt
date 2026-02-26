package com.callto.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class CallForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "callto_ongoing_call_channel"
        const val NOTIFICATION_ID = 7310

        const val ACTION_START = "com.callto.app.action.START_CALL_FOREGROUND"
        const val ACTION_UPDATE = "com.callto.app.action.UPDATE_CALL_FOREGROUND"
        const val ACTION_STOP = "com.callto.app.action.STOP_CALL_FOREGROUND"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_TEXT = "extra_text"
        const val EXTRA_OPEN_CALL_SCREEN = "open_call_screen"
    }

    private var isForegroundStarted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startForegroundServiceInternal(intent)
            ACTION_UPDATE -> updateNotificationInternal(intent)
            ACTION_STOP -> stopForegroundInternal()
            else -> startForegroundServiceInternal(intent)
        }
        return START_STICKY
    }

    private fun startForegroundServiceInternal(intent: Intent?) {
        createNotificationChannelIfNeeded()
        val notification = buildNotification(
            title = intent?.getStringExtra(EXTRA_TITLE) ?: "Call in Progress",
            text = intent?.getStringExtra(EXTRA_TEXT) ?: "Tap to return to call"
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isForegroundStarted = true
    }

    private fun updateNotificationInternal(intent: Intent?) {
        if (!isForegroundStarted) {
            startForegroundServiceInternal(intent)
            return
        }

        val notification = buildNotification(
            title = intent?.getStringExtra(EXTRA_TITLE) ?: "Call in Progress",
            text = intent?.getStringExtra(EXTRA_TEXT) ?: "Tap to return to call"
        )
        NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundInternal() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
        isForegroundStarted = false
        stopSelf()
    }

    private fun buildNotification(
        title: String,
        text: String
    ): Notification {
        val openCallIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(EXTRA_OPEN_CALL_SCREEN, true)
        }

        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        val contentIntent = PendingIntent.getActivity(
            this,
            1001,
            openCallIntent,
            pendingIntentFlags
        )

        val actionIntent = PendingIntent.getActivity(
            this,
            1002,
            openCallIntent,
            pendingIntentFlags
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(contentIntent)
            .addAction(
                android.R.drawable.sym_action_call,
                "Return to call",
                actionIntent
            )
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ongoing Calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Active call controls"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        isForegroundStarted = false
        super.onDestroy()
    }
}
