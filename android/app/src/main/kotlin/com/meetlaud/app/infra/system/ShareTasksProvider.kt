package com.meetlaud.app.infra.system

import android.content.Context
import android.content.Intent
import com.meetlaud.domain.RemindersProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Sends tasks to the person's task app. iOS writes each one into Reminders; Android has no shared task store, so the
 * tasks are gathered and handed over together through the share sheet, as a checklist any task app can take in.
 */
class ShareTasksProvider(private val context: Context) : RemindersProvider {
    private val gathered = mutableListOf<String>()

    override suspend fun add(title: String, notes: String?) {
        gathered += listOfNotNull("- [ ] $title", notes?.takeIf { it.isNotBlank() }?.lines()?.joinToString("\n") { "  $it" }).joinToString("\n")
    }

    override suspend fun finish() = withContext(Dispatchers.Main) {
        if (gathered.isEmpty()) return@withContext
        val text = gathered.joinToString("\n")
        gathered.clear()
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
