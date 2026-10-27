import Foundation
import Testing
@testable import MagnifierClone

struct SystemSoundsTests {
    @Test func listsSoundFilesRecursivelyWithReadableNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nano"), withIntermediateDirectories: true)
        for path in ["Tink.caf", "nano/Alarm_Haptic.caf", "readme.txt", "sms-received1.m4a"] {
            try Data().write(to: root.appendingPathComponent(path))
        }
        let sounds = SystemSounds.all(in: root)
        #expect(sounds.map(\.name) == ["nano / Alarm Haptic", "sms-received1", "Tink"])
        #expect(sounds.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    @Test func missingFolderGivesNoSounds() {
        #expect(SystemSounds.all(in: URL(filePath: "/no/such/folder")).isEmpty)
    }
}
