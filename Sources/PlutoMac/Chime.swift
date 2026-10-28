import AppKit

/// Pluto's sounds: soft tap when an agent starts, chime when it's done,
/// gentle knock when it needs you, thud when it fails.
@MainActor
final class Chime: ObservableObject {
    static let shared = Chime()

    private var customFiles: [Prefs.Moment: URL] = [:]

    init() {
        reloadCustomSounds()
    }

    static var soundsFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pluto/Sounds", isDirectory: true)
    }

    func reloadCustomSounds() {
        customFiles = [:]
        let fm = FileManager.default
        let folder = Self.soundsFolder
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "wav" {
                if let moment = Prefs.Moment(rawValue: file.deletingPathExtension().lastPathComponent) {
                    customFiles[moment] = file
                }
            }
        }
    }

    func play(_ moment: Prefs.Moment) {
        let volume = Float(Prefs.shared.soundVolume)
        guard volume > 0.01 else { return }
        switch Prefs.shared.soundChoice(for: moment) {
        case .none:
            return
        case .custom:
            guard let url = customFiles[moment] ?? customFiles[.start],
                  let sound = NSSound(contentsOf: url, byReference: false) else { return }
            sound.volume = Swift.min(1.0, volume)
            sound.play()
        case .pluto:
            guard let name = moment.systemSoundName(for: .pluto),
                  let sound = NSSound(named: name) else { return }
            sound.volume = Swift.min(1.0, volume)
            sound.play()
        }
    }
}
