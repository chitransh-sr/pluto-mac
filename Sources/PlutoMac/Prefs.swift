import AppKit
import Combine
import SwiftUI

/// All user preferences, persisted to UserDefaults (~/Library/Preferences).
/// Pluto-equivalent: Settings › General / Agents / Hooks / Sound / To Do.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let d = UserDefaults.standard

    // MARK: General

    enum Location: String, CaseIterable, Identifiable {
        case notch, floating
        var id: String { rawValue }
        var label: String { self == .notch ? "Notch" : "Floating" }
    }

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @Published var location: Location {
        didSet { d.set(location.rawValue, forKey: "location") }
    }
    @Published var size: Size {
        didSet { d.set(size.rawValue, forKey: "size") }
    }
    @Published var hoverPop: Bool {
        didSet { d.set(hoverPop, forKey: "hoverPop") }
    }
    @Published var launchAtLogin: Bool {
        didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); LoginItem.set(launchAtLogin) }
    }

    // Horizontal center of the pet, per location, clamped at use site.
    @Published var notchX: Double {
        didSet { d.set(notchX, forKey: "notchX") }
    }
    @Published var floatX: Double {
        didSet { d.set(floatX, forKey: "floatX") }
    }

    // MARK: Agents

    /// Agent ids the pet watches. Default: all.
    @Published var watchedAgents: [String] {
        didSet { d.set(watchedAgents, forKey: "watchedAgents") }
    }

    @Published var eventPort: Int {
        didSet { d.set(eventPort, forKey: "eventPort") }
    }

    // MARK: Sound

    enum SoundChoice: String, CaseIterable, Identifiable {
        case pluto, none, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pluto: return "Pluto"
            case .none: return "None"
            case .custom: return "Custom file"
            }
        }
    }

    enum Moment: String, CaseIterable, Identifiable {
        case start, done, needsYou, failed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .start: return "Agent starts"
            case .done: return "Agent is done"
            case .needsYou: return "Agent needs you"
            case .failed: return "Agent failed"
            }
        }
        /// Pluto's two-note chime favourite: soft tap start, chime done, knock needs-you.
        func systemSoundName(for pref: SoundChoice) -> String? {
            guard pref == .pluto else { return nil }
            switch self {
            case .start: return "Pop"
            case .done: return "Glass"
            case .needsYou: return "Ping"
            case .failed: return "Basso"
            }
        }
    }

    @Published var soundChoices: [String: String] {   // moment.rawValue -> SoundChoice.rawValue
        didSet { d.set(soundChoices, forKey: "soundChoices") }
    }
    @Published var soundVolume: Double {
        didSet { d.set(soundVolume, forKey: "soundVolume") }
    }

    // MARK: To Do

    @Published var todoDayStartHour: Int {
        didSet { d.set(todoDayStartHour, forKey: "todoDayStartHour") }
    }
    enum CheckedBehavior: String, CaseIterable, Identifiable {
        case bottom, stay
        var id: String { rawValue }
        var label: String { self == .bottom ? "Move to bottom" : "Stay in place" }
    }
    @Published var checkedBehavior: CheckedBehavior {
        didSet { d.set(checkedBehavior.rawValue, forKey: "checkedBehavior") }
    }
    enum HistoryRetention: String, CaseIterable, Identifiable {
        case week1, week2, month1, month3, year1
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week1: return "1 week"
            case .week2: return "2 weeks"
            case .month1: return "1 month"
            case .month3: return "3 months"
            case .year1: return "1 year"
            }
        }
        var days: Int {
            switch self {
            case .week1: return 7
            case .week2: return 14
            case .month1: return 30
            case .month3: return 92
            case .year1: return 365
            }
        }
    }
    @Published var historyRetention: HistoryRetention {
        didSet { d.set(historyRetention.rawValue, forKey: "historyRetention") }
    }

    // MARK: init

    private init() {
        location = Location(rawValue: d.string(forKey: "location") ?? "") ?? .notch
        size = Size(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        hoverPop = d.object(forKey: "hoverPop") as? Bool ?? true
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? false
        notchX = d.object(forKey: "notchX") as? Double ?? 0   // 0 = centered
        floatX = d.object(forKey: "floatX") as? Double ?? 0
        watchedAgents = d.stringArray(forKey: "watchedAgents") ?? AgentKind.all.map(\.id)
        eventPort = d.object(forKey: "eventPort") as? Int ?? 7717
        soundChoices = d.dictionary(forKey: "soundChoices") as? [String: String] ?? [:]
        soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.7
        todoDayStartHour = d.object(forKey: "todoDayStartHour") as? Int ?? 4
        checkedBehavior = CheckedBehavior(rawValue: d.string(forKey: "checkedBehavior") ?? "") ?? .bottom
        historyRetention = HistoryRetention(rawValue: d.string(forKey: "historyRetention") ?? "") ?? .week2
    }

    func isWatching(_ agent: AgentKind) -> Bool {
        watchedAgents.contains(agent.id)
    }

    func setWatching(_ agent: AgentKind, _ on: Bool) {
        if on {
            if !watchedAgents.contains(agent.id) { watchedAgents.append(agent.id) }
        } else {
            watchedAgents.removeAll { $0 == agent.id }
        }
    }

    func soundChoice(for moment: Moment) -> SoundChoice {
        SoundChoice(rawValue: soundChoices[moment.rawValue] ?? "") ?? .pluto
    }
}
