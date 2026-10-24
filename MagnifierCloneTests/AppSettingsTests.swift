import Foundation
import Testing
@testable import MagnifierClone

struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test func defaultsAreAskEachTimeAndOneSecond() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.inputMode == .askEachTime)
        #expect(settings.waitInterval == 1.0)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)
        first.inputMode = .voice
        first.waitInterval = 2.0

        let second = AppSettings(defaults: defaults)
        #expect(second.inputMode == .voice)
        #expect(second.waitInterval == 2.0)
    }

    @Test func waitIntervalIsClamped() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.waitInterval = 0.1
        #expect(settings.waitInterval == 0.5)
        settings.waitInterval = 9
        #expect(settings.waitInterval == 3.0)
    }
}
