package com.meetlaud.app.infra.system

import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Asks Android for a runtime permission and waits for the answer, the way an iOS `requestAccess()` call does. The
 * activity registers itself at launch, since only an activity can show the system's question.
 */
class Permissions(private val context: Context, private val preferences: AppPreferences) {
    private var launcher: ActivityResultLauncher<Array<String>>? = null
    private var pending: CompletableDeferred<Map<String, Boolean>>? = null

    fun attach(activity: ComponentActivity) {
        launcher = activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            pending?.complete(result)
            pending = null
        }
    }

    fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** Whether the app asked before. Android cannot tell "never asked" from "said no", and iOS can. */
    fun wasAsked(permission: String): Boolean = preferences.bool("permissions.asked.$permission") == true

    suspend fun request(vararg permissions: String): Boolean {
        if (permissions.all(::isGranted)) return true
        val launcher = launcher ?: return false
        permissions.forEach { preferences.setBool("permissions.asked.$it", true) }
        val answer = CompletableDeferred<Map<String, Boolean>>()
        pending = answer
        withContext(Dispatchers.Main) { launcher.launch(arrayOf(*permissions)) }
        answer.await()
        return permissions.all(::isGranted)
    }
}
