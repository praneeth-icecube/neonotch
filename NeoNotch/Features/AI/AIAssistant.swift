import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something Apple Intelligence can do to a piece of text.
enum AITask: String, CaseIterable, Identifiable {
    case rephrase, summarize, refine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rephrase: "Rephrase"
        case .summarize: "Summarise"
        case .refine: "Refine"
        }
    }

    var symbol: String {
        switch self {
        case .rephrase: "arrow.triangle.2.circlepath"
        case .summarize: "list.bullet.below.rectangle"
        case .refine: "wand.and.stars"
        }
    }

    fileprivate var instructions: String {
        switch self {
        case .rephrase:
            "Rewrite the user's text so it reads clearly and naturally. Keep its meaning, its language "
                + "and roughly its length. Reply with the rewritten text only — no preamble, no quotation marks."
        case .summarize:
            "Summarise the user's text in one or two short sentences, in the same language as the text. "
                + "Reply with the summary only — no preamble, no quotation marks."
        case .refine:
            "Correct the spelling, grammar and punctuation of the user's text and tighten the wording, "
                + "without changing its meaning, tone or language. Reply with the corrected text only — "
                + "no preamble, no quotation marks."
        }
    }
}

/// Apple Intelligence, on this Mac, through the Foundation Models framework.
///
/// Everything runs on-device: nothing NeoNotch sends here leaves the Mac. The
/// framework only exists on macOS 26 and later, and only answers on a Mac with
/// Apple Intelligence switched on, so every caller checks `availability` first
/// and the AI buttons simply do not appear where it cannot work.
enum AIAssistant {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    enum Failure: LocalizedError {
        case unavailable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .empty: "There is no text to work with."
            }
        }
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This Mac can't run Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in System Settings.")
                case .modelNotReady:
                    return .unavailable("Apple Intelligence is still getting ready.")
                @unknown default:
                    return .unavailable("Apple Intelligence isn't available right now.")
                }
            }
        }
        #endif
        return .unavailable("Needs macOS 26 or later.")
    }

    static var isAvailable: Bool { availability == .available }

    /// The on-device model reads a few thousand tokens at most; a clipping
    /// longer than this is trimmed rather than refused.
    private static let inputLimit = 6_000

    static func perform(_ task: AITask, on text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        return try await respond(instructions: task.instructions, prompt: String(trimmed.prefix(inputLimit)))
    }

    /// A short, spoken-style summary of a day on the calendar.
    static func briefing(for events: [CalendarEvent], on day: Date) async throws -> String {
        let dayName = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard !events.isEmpty else {
            return "Nothing on your calendar for \(dayName). The day is yours."
        }
        let listing = events.map { event in
            var line = "- \(event.timeRange): \(event.title)"
            if let location = event.location, !location.isEmpty { line += " (at \(location))" }
            return line
        }.joined(separator: "\n")

        let instructions = "You write a short daily brief from the user's calendar. Two to four friendly "
            + "sentences in the second person, mentioning times, most important first. Plain text only — "
            + "no preamble, no lists, no markdown."
        return try await respond(
            instructions: instructions,
            prompt: "Calendar for \(dayName):\n\(listing)"
        )
    }

    private static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = availability else {
                if case .unavailable(let reason) = availability { throw Failure.unavailable(reason) }
                throw Failure.unavailable("Apple Intelligence isn't available.")
            }
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw Failure.unavailable("Needs macOS 26 or later.")
    }
}

/// One AI request and its outcome, for any view that shows a result.
@MainActor
final class AIRequest: ObservableObject {
    enum State: Equatable {
        case idle
        case working(String)
        case done(title: String, text: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var job: Task<Void, Never>?

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    func run(_ title: String, _ work: @escaping () async throws -> String) {
        job?.cancel()
        state = .working(title)
        job = Task { [weak self] in
            do {
                let text = try await work()
                guard !Task.isCancelled else { return }
                self?.state = .done(title: title, text: text)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        job?.cancel()
        job = nil
        state = .idle
    }
}
