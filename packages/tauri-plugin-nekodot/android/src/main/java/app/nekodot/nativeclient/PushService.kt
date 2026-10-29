package app.nekodot.nativeclient

import app.tauri.plugin.JSObject
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // The authenticated WebView owns registration. Resume also fetches the latest token.
        NekodotPlugin.instance?.trigger("token", JSObject().put("token", token))
    }
    override fun onMessageReceived(message: RemoteMessage) {
        val signal = JSObject()
        for (key in listOf("notificationId", "nodeId", "conversationId", "kind")) signal.put(key, message.data[key])
        NekodotPlugin.instance?.trigger("notification", signal)
    }
}
