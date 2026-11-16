package com.meetlaud.app.infra.device

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import com.meetlaud.domain.DeviceCondition
import com.meetlaud.domain.DeviceMonitor
import com.meetlaud.domain.DeviceProfile
import com.meetlaud.domain.ThermalLevel
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import java.io.File

/**
 * Watches the device through system broadcasts and listeners. There is no timer here, so that it costs nothing when
 * idle. The counterpart of SystemDeviceMonitor.swift.
 */
class SystemDeviceMonitor(private val context: Context, private val storage: File) : DeviceMonitor {
    private val power = context.getSystemService(PowerManager::class.java)
    private val activities = context.getSystemService(ActivityManager::class.java)
    private val signal = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val changes: Flow<Unit> = signal

    init {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                signal.tryEmit(Unit)
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        }
        context.registerReceiver(receiver, filter)
        power.addThermalStatusListener(context.mainExecutor) { signal.tryEmit(Unit) }
    }

    override suspend fun profile(): DeviceProfile {
        val memory = ActivityManager.MemoryInfo().also { activities.getMemoryInfo(it) }
        return DeviceProfile(
            // The name the phone shows in its own settings, "Redmi Note 11" or "Pixel 8", rather than a model code.
            name = android.provider.Settings.Global.getString(context.contentResolver, android.provider.Settings.Global.DEVICE_NAME)
                ?.takeIf { it.isNotBlank() } ?: Build.MODEL,
            identifier = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            physicalMemoryMB = (memory.totalMem / 1_000_000).toInt(),
        )
    }

    override suspend fun condition(): DeviceCondition {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.let {
            val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1).takeIf { value -> value >= 0 }?.let { value -> value.toDouble() / scale }
        } ?: 1.0
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val memory = ActivityManager.MemoryInfo().also { activities.getMemoryInfo(it) }
        return DeviceCondition(
            thermal = thermal(power.currentThermalStatus),
            isLowPower = power.isPowerSaveMode,
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL,
            batteryLevel = level,
            availableMemoryMB = (memory.availMem / 1_000_000).toInt(),
            freeBytes = runCatching { StatFs(storage.path).availableBytes }.getOrDefault(0),
        )
    }

    /** Android has more steps than iOS. Each maps to the iOS level that asks for the same response. */
    private fun thermal(status: Int): ThermalLevel = when (status) {
        PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> ThermalLevel.NOMINAL
        PowerManager.THERMAL_STATUS_MODERATE -> ThermalLevel.FAIR
        PowerManager.THERMAL_STATUS_SEVERE -> ThermalLevel.SERIOUS
        else -> ThermalLevel.CRITICAL
    }
}
