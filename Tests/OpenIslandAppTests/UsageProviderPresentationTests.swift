import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct UsageProviderPresentationTests {
    @Test
    func claudeUsagePresentationAlwaysTargetsTheFiveHourWindow() {
        let provider = UsageProviderPresentation.claudeFiveHour(
            ClaudeUsageWindow(usedPercentage: 37.6, resetsAt: nil)
        )

        #expect(provider.title == "Claude")
        #expect(provider.peakWindowLabel == "5h")
        #expect(provider.peakUsageText == "38%")
    }

    @Test
    func claudeUsagePresentationHasAnUnavailableStateBeforeTheFirstRefresh() {
        let provider = UsageProviderPresentation.claudeFiveHour(nil)

        #expect(provider.peakWindowLabel == "5h")
        #expect(provider.peakUsedPercentage == nil)
        #expect(provider.peakUsageText == "—")
    }
}
