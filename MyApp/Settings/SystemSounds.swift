import Foundation

/// A sound file the waiting feedback can play.
nonisolated struct SoundFile: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    var id: String { url.path }
}

/// The sounds that ship with iOS, read from the system sounds folder.
/// That folder isn't a documented API; if it can't be read the list is empty and only the built-in sound is offered.
nonisolated enum SystemSounds {
    static let root = URL(filePath: "/System/Library/Audio/UISounds", directoryHint: .isDirectory)
    private static let extensions: Set<String> = ["caf", "m4a", "wav", "aif", "aiff", "mp3"]

    /// Every sound file under `root`, sorted by name. Files in subfolders are named "Folder / File".
    static func all(in root: URL = root) -> [SoundFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let rootDepth = root.standardizedFileURL.pathComponents.count
        var sounds: [SoundFile] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            let components = url.standardizedFileURL.deletingPathExtension().pathComponents.dropFirst(rootDepth)
            let name = components
                .map { $0.replacingOccurrences(of: "_", with: " ") }
                .joined(separator: " / ")
            sounds.append(SoundFile(name: name, url: url))
        }
        return sounds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
