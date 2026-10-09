import EventKit
import SwiftUI

enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case red, blue, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: Color(red: 1, green: 0.36, blue: 0.36)
        case .blue: Color(red: 0.29, green: 0.64, blue: 1)
        case .green: Color(red: 0.2, green: 0.83, blue: 0.6)
        }
    }
}

struct Note: Identifiable, Codable, Equatable {
    /// A UUID for a note kept here; the reminder's identifier for one that
    /// lives in Apple Reminders. Stored notes wrote their id as a UUID string,
    /// so they still decode.
    var id = UUID().uuidString
    var text: String
    var color: NoteColor
    var createdAt: Date
    var updatedAt: Date
    var isDone = false

    /// "now", "10 min ago", "yesterday".
    var age: String {
        let seconds = Date().timeIntervalSince(updatedAt)
        if seconds < 60 { return "now" }
        return Self.relative.localizedString(for: updatedAt, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// The Home widget's list: your Apple Reminders once you allow it, quick notes
/// kept in `notes.json` until then.
///
/// Connected, it is your Reminders, both ways: what you add or tick off here
/// shows up in Reminders — new ones in the default list — and anything added
/// or ticked off there, in any list, shows up here. Open reminders are listed,
/// plus the ones finished today so a tick does not make a row vanish under the
/// pointer. The colour bar is NeoNotch's own — Reminders has no colour per
/// item — and is remembered by reminder.
///
/// The note being written lives in `draft`, not in the editor. So when the
/// panel closes mid-sentence — you moved the pointer, you clicked elsewhere —
/// nothing is lost: the editor comes back with exactly what you had typed.
final class NotesModel: ObservableObject {
    enum Access: Equatable { case notDetermined, granted, denied }

    struct Draft: Equatable {
        /// The note being edited, or nil for a new one.
        var noteID: String?
        var text: String
        var color: NoteColor
    }

    @Published private(set) var notes: [Note] = []
    @Published var draft: Draft?
    @Published private(set) var remindersAccess: Access
    /// The Reminders list shown, while connected.
    @Published private(set) var listName: String?

    /// Allowed is enough: reminders show from every list whether or not
    /// Reminders names a default one. Requiring the default list is what left
    /// "Sync with Reminders" on screen after you had already said yes.
    var isUsingReminders: Bool { remindersAccess == .granted }

    /// Off for snapshots, which must not raise a permission prompt.
    static var connectsReminders = true

    private static let file = "notes.json"
    private static let colorsFile = "reminder-colors.json"

    private let syncsReminders: Bool
    private var store = EKEventStore()
    private var list: EKCalendar?
    /// Notes kept on this Mac; shown whenever Reminders is not connected.
    private var localNotes: [Note]
    private var colors: [String: NoteColor]
    private var observer: NSObjectProtocol?
    /// Newest reload wins; an older fetch finishing late is dropped.
    private var generation = 0
    /// Set by snapshot seeding, so a reload cannot swap the seed for real data.
    private var isFrozen = false

    /// `syncsReminders: false` keeps everything local — for self-tests, which
    /// must never write into your real Reminders.
    init(syncsReminders: Bool = NotesModel.connectsReminders) {
        self.syncsReminders = syncsReminders
        localNotes = Storage.load([Note].self, from: Self.file) ?? []
        colors = Storage.load([String: NoteColor].self, from: Self.colorsFile) ?? [:]
        remindersAccess = syncsReminders ? Self.currentAccess() : .denied
        notes = localNotes

        if syncsReminders {
            observeStore()
            reload()
            // Asked once, straight away: macOS never asks twice, and after a
            // yes the list is simply your Reminders.
            if remindersAccess == .notDetermined { connectReminders() }
        }
    }

    /// Follows changes made anywhere — the Reminders app, your phone.
    private func observeStore() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Open notes first, newest first; done notes after them.
    var sortedNotes: [Note] {
        notes.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: Reminders

    /// Asks macOS for access to Reminders or — if it was refused — opens the
    /// settings pane where it can be given.
    func connectReminders() {
        guard syncsReminders else { return }
        guard remindersAccess != .denied else {
            openPrivacySettings()
            return
        }
        store.requestFullAccessToReminders { [weak self] granted, error in
            if let error { Trace.log("reminders", "access request failed: \(error.localizedDescription)") }
            Trace.log("reminders", "access \(granted ? "granted" : "refused")")
            DispatchQueue.main.async {
                guard let self else { return }
                // A store made before access was given can go on answering as
                // if it had none, so start a fresh one.
                self.store = EKEventStore()
                self.observeStore()
                self.reload()
            }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }

    func reload() {
        guard syncsReminders, !isFrozen else { return }
        let access = Self.currentAccess()
        if remindersAccess != access { remindersAccess = access }
        guard access == .granted else {
            list = nil
            if listName != nil { listName = nil }
            if notes != localNotes { notes = localNotes }
            return
        }
        // Where new ones go: Reminders' default list, or failing that any
        // list that can take them.
        list = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: \.allowsContentModifications)
        if listName != list?.title { listName = list?.title }

        generation += 1
        let current = generation
        let today = Calendar.current.startOfDay(for: Date())
        // Every list, so anything added in Reminders shows here; new ones
        // from the notch go to the default list.
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let doneToday = store.predicateForCompletedReminders(withCompletionDateStarting: today, ending: nil, calendars: nil)
        store.fetchReminders(matching: open) { [weak self] openReminders in
            let first = (openReminders ?? []).map(Fetched.init)
            self?.store.fetchReminders(matching: doneToday) { doneReminders in
                let fetched = first + (doneReminders ?? []).map(Fetched.init)
                DispatchQueue.main.async {
                    guard let self, current == self.generation else { return }
                    let fresh = fetched.map { $0.note(color: self.colors[$0.id] ?? .blue) }
                    if fresh != self.notes { self.notes = fresh }
                }
            }
        }
    }

    /// What a reminder is copied into on EventKit's queue, so nothing
    /// EventKit owns crosses to the main thread.
    private struct Fetched {
        let id: String
        let title: String
        let created: Date
        let modified: Date
        let isDone: Bool

        init(_ reminder: EKReminder) {
            id = reminder.calendarItemIdentifier
            title = reminder.title ?? ""
            created = reminder.creationDate ?? Date()
            modified = reminder.lastModifiedDate ?? created
            isDone = reminder.isCompleted
        }

        func note(color: NoteColor) -> Note {
            Note(id: id, text: title, color: color, createdAt: created, updatedAt: modified, isDone: isDone)
        }
    }

    private func reminder(_ id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    private func save(_ reminder: EKReminder) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            Trace.log("reminders", "save failed: \(error.localizedDescription)")
            reload()
            return false
        }
    }

    // MARK: Editing

    func beginNew() {
        if draft == nil || draft?.noteID != nil {
            draft = Draft(noteID: nil, text: "", color: draft?.color ?? .blue)
        }
    }

    func beginEditing(_ note: Note) {
        draft = Draft(noteID: note.id, text: note.text, color: note.color)
    }

    /// Saves the draft; an empty draft deletes the note it was editing.
    func commitDraft() {
        guard let draft else { return }
        self.draft = nil
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        if let id = draft.noteID, let index = notes.firstIndex(where: { $0.id == id }) {
            guard !text.isEmpty else {
                delete(notes[index])
                return
            }
            if isUsingReminders {
                guard let reminder = reminder(id) else { return reload() }
                reminder.title = text
                // Not saved: keep what was typed rather than lose it.
                guard save(reminder) else { return self.draft = draft }
                setColor(draft.color, for: id)
            }
            notes[index].text = text
            notes[index].color = draft.color
            notes[index].updatedAt = now
        } else if !text.isEmpty {
            var note = Note(text: text, color: draft.color, createdAt: now, updatedAt: now)
            if isUsingReminders {
                let reminder = EKReminder(eventStore: store)
                reminder.title = text
                reminder.calendar = list
                guard save(reminder) else { return self.draft = draft }
                note.id = reminder.calendarItemIdentifier
                setColor(draft.color, for: note.id)
            }
            notes.insert(note, at: 0)
        }
        persistLocal()
    }

    func discardDraft() {
        draft = nil
    }

    // MARK: Notes

    func toggleDone(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        if isUsingReminders {
            guard let reminder = reminder(note.id) else { return reload() }
            reminder.isCompleted = !note.isDone
            guard save(reminder) else { return }
        }
        notes[index].isDone.toggle()
        persistLocal()
    }

    /// Deleting a reminder here deletes it from Reminders too.
    func delete(_ note: Note) {
        if isUsingReminders {
            guard let reminder = reminder(note.id) else { return reload() }
            do {
                try store.remove(reminder, commit: true)
            } catch {
                Trace.log("reminders", "delete failed: \(error.localizedDescription)")
                return reload()
            }
            setColor(nil, for: note.id)
        }
        notes.removeAll { $0.id == note.id }
        if draft?.noteID == note.id { draft = nil }
        persistLocal()
    }

    /// Only ever clears notes kept here; finished reminders stay in Reminders.
    func clearDone() {
        guard !isUsingReminders else { return }
        notes.removeAll(where: \.isDone)
        persistLocal()
    }

    private func setColor(_ color: NoteColor?, for id: String) {
        colors[id] = color
        Storage.save(colors, to: Self.colorsFile)
    }

    /// Writes `notes.json` — only while the notes on screen are the local ones.
    private func persistLocal() {
        guard !isUsingReminders else { return }
        localNotes = notes
        Storage.save(localNotes, to: Self.file)
    }

    #if DEBUG
    func debugSeed(_ seeded: [Note]) {
        isFrozen = true
        notes = seeded
    }
    #endif
}
