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

    @Test func waitingCueDefaults() {
        let cue = AppSettings(defaults: makeDefaults()).waitingCue
        #expect(cue == WaitingCue(interval: 1.0, delay: 0, soundURL: WaitingCue.defaultSoundURL, vibrates: true))
    }

    @Test func cueSettingsPersistAndMapToCue() throws {
        let defaults = makeDefaults()
        let sound = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        try Data().write(to: sound)
        defer { try? FileManager.default.removeItem(at: sound) }
        let first = AppSettings(defaults: defaults)
        first.waitDelay = 2.5
        first.vibrates = false
        first.waitingSound = sound.path

        let second = AppSettings(defaults: defaults)
        #expect(second.waitingCue == WaitingCue(interval: 1.0, delay: 2.5, soundURL: URL(filePath: sound.path), vibrates: false))
    }

    @Test func noSoundMapsToNilURL() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.waitingSound = AppSettings.noSound
        #expect(settings.waitingCue.soundURL == nil)
    }

    @Test func missingSoundFileFallsBackToBuiltIn() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults).waitingSound = "/no/such/sound.caf"
        #expect(AppSettings(defaults: defaults).waitingSound == AppSettings.builtInSound)
    }

    @Test func waitDelayIsClamped() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.waitDelay = -1
        #expect(settings.waitDelay == 0)
        settings.waitDelay = 60
        #expect(settings.waitDelay == 5)
    }

    @Test func answerStyleDefaultsToStandardAndPersists() {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.answerStyle == .standard)
        first.answerStyle = .accessibility
        #expect(AppSettings(defaults: defaults).answerStyle == .accessibility)
    }
}
