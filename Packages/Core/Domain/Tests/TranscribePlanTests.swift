@testable import Domain
import Foundation
import Testing

struct TranscribePlanTests {
    @Test func `a measured speed gives one number of minutes`() {
        let plan = TranscribePlan(duration: 3600, speed: .measured(10), rightNow: .great, isCharging: true)
        #expect(plan.minutes == 6 ... 6)
        #expect(!plan.deservesNote, "A short job on a device in good shape just starts")
    }

    @Test func `an estimated speed gives a range, shortest first`() {
        let plan = TranscribePlan(
            duration: 3600,
            speed: .estimated(low: 4, high: 8),
            rightNow: .great,
            isCharging: true,
        )
        #expect(plan.minutes == 8 ... 15)
        #expect(plan.deservesNote, "Fifteen minutes is long enough to mention")
    }

    @Test func `a device that is not at its best is always mentioned`() {
        let plan = TranscribePlan(
            duration: 60, speed: .measured(20), rightNow: .limited(.lowBattery), isCharging: false,
        )
        #expect(plan.deservesNote)
        #expect(plan.canWaitForCharger)
    }

    @Test func `an unknown speed has no time, and a charging device cannot wait for a charger`() {
        let plan = TranscribePlan(duration: 600, speed: .unknown, rightNow: .good(.warm), isCharging: true)
        #expect(plan.minutes == nil)
        #expect(!plan.canWaitForCharger)
    }

    @Test func `even a tiny job takes at least a minute`() {
        let plan = TranscribePlan(duration: 5, speed: .measured(30), rightNow: .great, isCharging: true)
        #expect(plan.minutes == 1 ... 1)
    }
}
