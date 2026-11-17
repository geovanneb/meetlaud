package com.meetlaud.app.infra.system

import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
import org.junit.Assert.assertEquals
import org.junit.Test

/** The service declares what the work really is: Google Play compares the type with what the app does. */
class WorkServiceTypeTest {
    @Test fun aDownloadIsDataSyncOnEveryVersion() {
        assertEquals(FOREGROUND_SERVICE_TYPE_DATA_SYNC, ForegroundWork.serviceType(setOf(WorkKind.TRANSFER), 36))
        assertEquals(FOREGROUND_SERVICE_TYPE_DATA_SYNC, ForegroundWork.serviceType(setOf(WorkKind.TRANSFER), 29))
    }

    @Test fun transcriptionIsMediaProcessingFromAndroid15() {
        assertEquals(FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING, ForegroundWork.serviceType(setOf(WorkKind.PROCESSING), 35))
        assertEquals(FOREGROUND_SERVICE_TYPE_DATA_SYNC, ForegroundWork.serviceType(setOf(WorkKind.PROCESSING), 34))
    }

    @Test fun bothAtOnceDeclareBoth() {
        assertEquals(
            FOREGROUND_SERVICE_TYPE_DATA_SYNC or FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING,
            ForegroundWork.serviceType(setOf(WorkKind.PROCESSING, WorkKind.TRANSFER), 36),
        )
    }

    @Test fun nothingRunningStillHasAType() {
        assertEquals(FOREGROUND_SERVICE_TYPE_DATA_SYNC, ForegroundWork.serviceType(emptySet(), 36))
    }
}
