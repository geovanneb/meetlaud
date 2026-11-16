package com.meetlaud.app

import android.app.Application
import android.content.Intent
import com.meetlaud.app.localization.Strings

class MeetlaudApplication : Application() {
    private var built: AppContainer? = null

    override fun onCreate() {
        super.onCreate()
        Strings.install(this)
    }

    /**
     * One container for the life of the process. `showcase` (debug builds only) seeds the fictional meetings in a
     * library of their own, so a demo never touches the person's own recordings.
     */
    fun container(intent: Intent?): AppContainer = built ?: AppContainer(
        this,
        showcase = BuildConfig.DEBUG && intent?.getBooleanExtra("showcase", false) == true,
    ).also { built = it }
}
