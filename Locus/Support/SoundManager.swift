import AudioToolbox
import Foundation

enum SoundEffect {
    case tap        // System sound 1104 (tock / subtle tap)
    case toggle     // System sound 1105 (pop)
    case success    // System sound 1054 (chime / success)
    case alert      // System sound 1053 (warning / cancel)
    case dwell      // System sound 1057 (soft knock / waypoint dwell)
    case trash      // System sound 1051 (empty trash / delete points)
    case teleport   // System sound 1109 (whoosh / teleport jump)
}

final class SoundManager {
    static let shared = SoundManager()
    static let soundEnabledKey = "locus.soundEffectsEnabled"

    var isSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.soundEnabledKey) == nil {
                return true // default enabled
            }
            return UserDefaults.standard.bool(forKey: Self.soundEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.soundEnabledKey)
        }
    }

    private init() {}

    static func play(_ effect: SoundEffect) {
        guard shared.isSoundEnabled else { return }
        let soundID: SystemSoundID
        switch effect {
        case .tap: soundID = 1104
        case .toggle: soundID = 1105
        case .success: soundID = 1054
        case .alert: soundID = 1053
        case .dwell: soundID = 1057
        case .trash: soundID = 1051
        case .teleport: soundID = 1109
        }
        AudioServicesPlaySystemSound(soundID)
    }
}
