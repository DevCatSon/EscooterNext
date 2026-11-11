package com.devcat.escootercontrol.next

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.devcat.escooter_control.MainActivity

/** Forward the default launcher entry without tying the running engine to its enabled state. */
class LauncherDefault : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(intent).setClass(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
