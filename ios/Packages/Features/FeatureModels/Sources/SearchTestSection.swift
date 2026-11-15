import DesignSystem
import Localization
import SwiftUI

struct SearchTestSection: View {
    let controller: ModelsController
    let modelID: String

    var body: some View {
        Section(title: L10n.Models.speedTest) {
            if controller.testing == modelID {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(L10n.Models.testing)
                }
            } else {
                Button(L10n.Models.quickTest) { controller.runSearchTest(modelID) }
                    .disabled(controller.testing != nil)
                    .accessibilityIdentifier("model.quickTest")
            }
            if let error = controller.testError {
                Text(error)
                    .foregroundStyle(Color.dsRecord)
                    .accessibilityIdentifier("model.testError")
            }
            if let result = controller.lastSearchTest, result.modelID == modelID {
                Text(L10n.Models.searchSpeed(result.secondsPerHourOfAudio))
                    .accessibilityIdentifier("model.testResult")
            }
        }
        .listRowBackground(Color.clear)
    }
}
