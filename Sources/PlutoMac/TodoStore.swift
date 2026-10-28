import Foundation

/// Pluto's daily To Do, saved to ~/Library/Application Support/Pluto/todos.json.
/// A new day starts at the hour you choose; the finished day moves to History,
/// where you can bring its unfinished tasks back.
@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    struct Item: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var text: String
        var done: Bool = false
        var createdAt: Date = Date()

        init(text: String) {
            self.text = text
        }
    }

    struct HistoryDay: Codable, Hashable, Identifiable {
        var dayKey: String
        var items: [Item]
        var id: String { dayKey }
    }

    struct File_ : Codable {
        var dayKey: String
        var items: [Item]
        var history: [HistoryDay]
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var history: [HistoryDay] = []
    private(set) var dayKey: String = ""
    @Published private(set) var savedAt: Date?

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pluto/todos.json")
    }

    init() {
        load()
        rollIfNeeded()
    }

    // The "day" a timestamp belongs to, honoring the chosen start hour.
    static func dayKey(for date: Date = Date(), startHour: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var d = date
        if cal.component(.hour, from: date) < startHour {
            d = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    func rollIfNeeded() {
        let today = Self.dayKey(startHour: Prefs.shared.todoDayStartHour)
        if today != dayKey {
            archiveCurrentDayIfNeeded()
            dayKey = today
            items = []
            save()
        }
    }

    func startNewDayNow() {
        dayKey = ""
        rollIfNeeded()
        objectWillChange.send()
    }

    private func archiveCurrentDayIfNeeded() {
        guard !dayKey.isEmpty else { return }
        let unfinished = items.filter { !$0.done }
        guard !unfinished.isEmpty || !items.isEmpty else { return }
        // Keep the day in History even if fully finished — you can restore it.
        if !items.isEmpty {
            history.append(HistoryDay(dayKey: dayKey, items: items))
        }
        trimHistory()
    }

    private func trimHistory() {
        let maxDays = Prefs.shared.historyRetention.days
        history.sort { $0.dayKey > $1.dayKey }
        if history.count > maxDays {
            history.removeLast(history.count - maxDays)
        }
    }

    func bringBackUnfinished(from day: HistoryDay) {
        let existing = Set(items.map { $0.text.lowercased() })
        for item in day.items where !item.done && !existing.contains(item.text.lowercased()) {
            items.append(Item(text: item.text))
        }
        history.removeAll { $0.dayKey == day.dayKey }
        save()
    }

    // MARK: - Mutations (each one saves right away)

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(Item(text: t))
        normalizeCheckedOrder()
        save()
    }

    func toggle(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].done.toggle()
            if Prefs.shared.checkedBehavior == .bottom {
                normalizeCheckedOrder()
            }
            save()
        }
    }

    func rename(_ id: UUID, to text: String) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                items.remove(at: i)
            } else {
                items[i].text = t
            }
            save()
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func move(_ id: UUID, offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(items.count - 1, i + offset))
        guard i != j else { return }
        items.swapAt(i, j)
        save()
    }

    func uncheckAll() {
        for i in items.indices { items[i].done = false }
        save()
    }

    /// Done tasks always sit at the bottom (Pluto's option "where checked tasks go").
    private func normalizeCheckedOrder() {
        guard items.contains(where: \.done) else { return }
        let open = items.filter { !$0.done }
        let done = items.filter(\.done)
        items = open + done
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.fileURL
        guard let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(File_.self, from: data) else { return }
        dayKey = f.dayKey
        items = f.items
        history = f.history
        trimHistory()
    }

    func save() {
        trimHistory()
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let f = File_(dayKey: dayKey, items: items, history: history)
        if let data = try? JSONEncoder().encode(f) {
            try? data.write(to: url, options: .atomic)
        }
        savedAt = Date()
    }
}
