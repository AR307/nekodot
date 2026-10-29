package app.nekodot.nativeclient

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.webkit.WebView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import java.io.File

class NekodotFileProvider : FileProvider()

@InvokeArg class FocusArgs { var nodeId: String? = null; var conversationId: String? = null }
@InvokeArg class ShareArgs { lateinit var name: String; lateinit var mime: String; lateinit var data: List<Int> }

@TauriPlugin
class NekodotPlugin(private val activity: Activity) : Plugin(activity) {
    companion object { var instance: NekodotPlugin? = null; var active = false }

    override fun load(webView: WebView) {
        instance = this
        active = true
        (activity.getSystemService(Activity.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(NotificationChannel("nekodot_tasks", "nekodot tasks", NotificationManager.IMPORTANCE_DEFAULT))
        (activity as AppCompatActivity).onBackPressedDispatcher.addCallback(activity, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { trigger("back", JSObject()) }
        })
        onNewIntent(activity.intent)
    }
    override fun onPause() { active = false; trigger("lifecycle", JSObject().put("active", false)) }
    override fun onResume() { active = true; trigger("lifecycle", JSObject().put("active", true)) }
    override fun onDestroy() { active = false; instance = null }

    override fun onNewIntent(intent: Intent) {
        val node = intent.getStringExtra("nodeId") ?: return
        val conversation = intent.getStringExtra("conversationId") ?: return
        val value = JSObject().put("nodeId", node).put("conversationId", conversation)
        activity.getPreferences(Activity.MODE_PRIVATE).edit().putString("pendingNotification", value.toString()).apply()
        trigger("notificationClick", value)
        intent.removeExtra("nodeId")
        intent.removeExtra("conversationId")
    }
    @Command fun pushToken(invoke: Invoke) {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) != ConnectionResult.SUCCESS) {
            invoke.reject("Google Play services are unavailable"); return
        }
        if (FirebaseApp.initializeApp(activity) == null) {
            invoke.reject("Firebase configuration is missing from this build"); return
        }
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            invoke.resolve(JSObject().put("token", token))
        }.addOnFailureListener { invoke.reject("Firebase token registration failed") }
    }
    @Command fun focusConversation(invoke: Invoke) {
        val args = invoke.parseArgs(FocusArgs::class.java)
        activity.getSharedPreferences("nekodot", Activity.MODE_PRIVATE).edit()
            .putString("nodeId", args.nodeId).putString("conversationId", args.conversationId).apply()
        invoke.resolve()
    }
    @Command fun clearPushToken(invoke: Invoke) {
        if (FirebaseApp.getApps(activity).isEmpty()) { invoke.resolve(); return }
        FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { invoke.resolve() }
    }
    @Command fun takeNotification(invoke: Invoke) {
        val prefs = activity.getPreferences(Activity.MODE_PRIVATE)
        val pending = prefs.getString("pendingNotification", null)
        prefs.edit().remove("pendingNotification").apply()
        invoke.resolve(if (pending == null) JSObject() else JSObject(pending))
    }
    @Command fun background(invoke: Invoke) {
        activity.moveTaskToBack(true)
        invoke.resolve()
    }
    @Command fun shareFile(invoke: Invoke) {
        val args = invoke.parseArgs(ShareArgs::class.java)
        val directory = File(activity.cacheDir, "nekodot-shares").apply { mkdirs() }
        val file = File(directory, File(args.name).name)
        file.writeBytes(args.data.map { it.toByte() }.toByteArray())
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".shared", file)
        val intent = Intent(Intent.ACTION_SEND).setType(args.mime).putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(intent, args.name))
        invoke.resolve()
    }
}
