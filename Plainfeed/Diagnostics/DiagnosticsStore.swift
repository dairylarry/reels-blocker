import Foundation
import SwiftUI

struct DiagEvent: Codable, Identifiable {
    var id = UUID()
    var at = Date()
    var source: String          // "R2", "R4", "app"
    var message: String
}

struct AssertionResult: Codable, Identifiable {
    enum Status: String, Codable { case pass, fail, skipped }

    var rule: String
    var name: String
    var status: Status
    var detail: String
    var checkedAt: Date

    var id: String { "\(rule):\(name)" }
}

/// Everything the diagnostics page shows. Local only — nothing is ever sent
/// anywhere (architecture §7.6.2).
@MainActor
final class DiagnosticsStore: ObservableObject {

    static let maxEvents = 50

    @Published private(set) var events: [DiagEvent] = []
    @Published private(set) var assertions: [AssertionResult] = []
    @Published var currentURL: URL?
    @Published var currentRoute: String = "—"

    private let eventsKey = "plainfeed.diagnostics.events"

    init() { load() }

    // MARK: - Events

    /// Persisted, so a problem at 9am is still visible at 9pm.
    func log(_ source: String, _ message: String) {
        let event = DiagEvent(source: source, message: message)
        events.insert(event, at: 0)
        if events.count > Self.maxEvents { events.removeLast(events.count - Self.maxEvents) }
        save()
    }

    func clearEvents() {
        events.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: eventsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([DiagEvent].self, from: data)
        else { return }
        events = decoded
    }

    // MARK: - Assertions

    /// Latest result wins, keyed by rule+name, so the list doesn't grow.
    func record(_ results: [AssertionResult]) {
        for result in results {
            if let i = assertions.firstIndex(where: { $0.id == result.id }) {
                let was = assertions[i].status
                assertions[i] = result
                // Only log transitions, or the log fills with every page load.
                if was != result.status, result.status == .fail {
                    log(result.rule, "\(result.name) FAILED — \(result.detail)")
                }
            } else {
                assertions.append(result)
                if result.status == .fail {
                    log(result.rule, "\(result.name) FAILED — \(result.detail)")
                }
            }
        }
        assertions.sort { $0.id < $1.id }
    }

    var hasFailure: Bool { assertions.contains { $0.status == .fail } }

    var failureSummary: String? {
        guard let first = assertions.first(where: { $0.status == .fail }) else { return nil }
        return "\(first.rule): \(first.name)"
    }

    // MARK: - Report

    /// Plain text for the clipboard — the whole point is that this can be
    /// pasted into a conversation without a Mac, a cable or Web Inspector.
    func report() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var out = ["Plainfeed diagnostics",
                   "\(AppVersion.display)",
                   "generated \(stamp.string(from: Date()))",
                   "",
                   "CURRENT PAGE",
                   "  url   \(currentURL?.absoluteString ?? "—")",
                   "  route \(currentRoute)",
                   "",
                   "ASSERTIONS"]

        if assertions.isEmpty {
            out.append("  (none recorded yet)")
        } else {
            for a in assertions {
                out.append("  [\(a.status.rawValue.uppercased())] \(a.rule) \(a.name)"
                           + (a.detail.isEmpty ? "" : " — \(a.detail)")
                           + "  (\(stamp.string(from: a.checkedAt)))")
            }
        }

        out.append("")
        out.append("EVENTS (\(events.count))")
        if events.isEmpty {
            out.append("  (none)")
        } else {
            for e in events {
                out.append("  \(stamp.string(from: e.at))  \(e.source)  \(e.message)")
            }
        }
        return out.joined(separator: "\n")
    }
}
