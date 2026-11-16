package app.nekodot.client

import android.app.Activity
import android.app.ActivityManager
import android.os.Bundle

/**
 * Receives nekodot://oauth?code=… from the browser after a Google or GitHub
 * sign-in, hands it to the running app (which redeems the code with the
 * verifier it kept), brings the app's own task back to the front and closes.
 */
class OAuthReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let { MainActivity.oauth?.invokeMethod("returned", it.toString()) }
        getSystemService(ActivityManager::class.java)
            .appTasks
            .firstOrNull { it.taskInfo.baseActivity?.className == MainActivity::class.java.name }
            ?.moveToFront()
        finish()
    }
}
